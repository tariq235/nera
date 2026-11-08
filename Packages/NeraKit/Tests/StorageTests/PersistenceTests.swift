// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import Foundation
import TestSupport
import Testing

@testable import Storage

@Suite("Persistence")
struct PersistenceTests {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "nera-tests-\(UUID().uuidString)/library.json")
    }

    @Test func roundTrip() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = JSONFileStore(fileURL: url)
        let state = sampleState()
        try store.save(state)
        #expect(try store.load() == state)
    }

    @Test func missingFileLoadsNil() throws {
        #expect(try JSONFileStore(fileURL: tempURL()).load() == nil)
    }

    @Test func corruptFileIsMovedAsideNotDeleted() throws {
        let url = tempURL()
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        #expect(try JSONFileStore(fileURL: url).load() == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.contains { $0.hasPrefix("library.corrupt-") })
    }

    @Test func newerSchemaRefusesToLoad() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let store = JSONFileStore(fileURL: url)
        try store.save(sampleState())
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        #expect(throws: PersistenceError.newerSchema(99)) { try store.load() }
    }

    @MainActor
    @Test func storeDebouncesAndFlushes() async throws {
        let mem = InMemoryStore()
        let store = BrowserStore(state: sampleState(), persistence: mem)
        store.saveDebounce = .milliseconds(10)
        store.send(.space(.create(title: "Saved")))
        #expect(try mem.load()?.spaces.last?.title != "Saved")  // not written synchronously
        // Poll instead of a fixed sleep: the main actor may be busy with parallel WebKit tests.
        for _ in 0..<300 where try mem.load()?.spaces.last?.title != "Saved" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try mem.load()?.spaces.last?.title == "Saved")
        store.send(.space(.create(title: "Flushed")))
        store.flush()
        #expect(try mem.load()?.spaces.last?.title == "Flushed")
    }
}

/// A small library with one tab, built through the reducer like the app would.
func sampleState() -> BrowserState {
    let env = TestEnv()
    var state = BrowserState.initial(uuid: env.nextUUID)
    _ = Reducer.reduce(&state, .tab(.open(URL(string: "https://a.example")!, .newTab)), env.reducer)
    return state
}

@Suite("Migration")
struct MigrationTests {
    @Test func libraryWrittenByApp01StillLoads() throws {
        let fixture = try #require(Bundle.module.url(forResource: "library-v1-app-0.1", withExtension: "json", subdirectory: "Fixtures"))
        let copy = FileManager.default.temporaryDirectory.appending(path: "nera-migration-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: fixture, to: copy)
        let state = try #require(try JSONFileStore(fileURL: copy).load())
        #expect(state.spaces.map(\.title) == ["Personal"])
        #expect(state.selectedTab?.title == "Example")
        #expect(state.profiles[0].engine == nil)  // field added after 0.1; absent in 0.1 files
    }
}
