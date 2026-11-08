// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineTestSupport
import Foundation
import TestSupport
import Testing

@testable import Storage

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "nera-resilience-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func fixtureCopy(in dir: URL) throws -> URL {
    let fixture = try #require(Bundle.module.url(forResource: "library-v1-app-0.1", withExtension: "json", subdirectory: "Fixtures"))
    let copy = dir.appending(path: "library.json")
    try FileManager.default.copyItem(at: fixture, to: copy)
    return copy
}

/// Crash-loop safe mode (SEC-054).
@Suite("Launch guard")
struct LaunchGuardTests {
    @Test func cleanLaunchesNeverEnterSafeMode() throws {
        let guardian = LaunchGuard(fileURL: try tempDir().appending(path: "launch.json"))
        for _ in 0..<5 {
            #expect(!guardian.beginLaunch())
            guardian.launchSucceeded()
        }
        #expect(guardian.failedLaunches == 0)
    }

    @Test func twoFailedLaunchesInARowStartSafeMode() throws {
        let guardian = LaunchGuard(fileURL: try tempDir().appending(path: "launch.json"))
        #expect(!guardian.beginLaunch())  // launch 1 crashes (never reports success)
        #expect(!guardian.beginLaunch(), "one crash isn't a loop")  // launch 2 crashes
        #expect(guardian.beginLaunch(), "third launch after two crashes is safe mode")
        #expect(guardian.beginLaunch(), "still crashing: stay in safe mode")
        guardian.launchSucceeded()
        #expect(!guardian.beginLaunch(), "a stable run leaves safe mode")
    }

    @Test func aCorruptRecordIsTreatedAsAFreshStart() throws {
        let url = try tempDir().appending(path: "launch.json")
        try Data("garbage".utf8).write(to: url)
        #expect(!LaunchGuard(fileURL: url).beginLaunch())
    }

    @Test func safeModeDeselectsEveryTab() {
        let env = TestEnv()
        var state = BrowserState.initial(uuid: env.nextUUID)
        _ = Reducer.reduce(&state, .tab(.open(URL(string: "https://a.example")!, .newTab)), env.reducer)
        #expect(state.selectedTabID != nil)
        #expect(Reducer.reduce(&state, .tab(.clearSelection), env.reducer).isEmpty, "no page loads")
        #expect(state.selectedTabID == nil)
    }
}

/// Library schema migrations (SEC-055 / upgrade tests).
@Suite("Schema migration")
struct SchemaMigrationTests {
    /// A pretend v2 that renames Spaces' `title` to `name`, then back (so today's types still decode it).
    static let roundTripSteps = [
        LibraryMigration(from: 1) { state in
            var spaces = state["spaces"] as? [[String: Any]] ?? []
            for i in spaces.indices { spaces[i]["name"] = spaces[i].removeValue(forKey: "title") }
            state["spaces"] = spaces
        },
        LibraryMigration(from: 2) { state in
            var spaces = state["spaces"] as? [[String: Any]] ?? []
            for i in spaces.indices { spaces[i]["title"] = (spaces[i].removeValue(forKey: "name") as? String).map { $0 + " (migrated)" } }
            state["spaces"] = spaces
        },
    ]

    @Test func v1FixtureUpgradesStepByStepAndKeepsABackup() throws {
        let dir = try tempDir()
        let url = try fixtureCopy(in: dir)
        let original = try Data(contentsOf: url)
        let store = JSONFileStore(fileURL: url, currentVersion: 3, migrations: Self.roundTripSteps)
        let state = try #require(try store.load())
        #expect(state.spaces.map(\.title) == ["Personal (migrated)"])
        #expect(state.selectedTab?.title == "Example", "tabs survive the upgrade")
        #expect(try Data(contentsOf: dir.appending(path: "library.v1.json")) == original, "pre-upgrade backup kept byte for byte")
        try store.save(state)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(saved?["schemaVersion"] as? Int == 3)
    }

    @Test func aMissingStepRefusesToLoadAndLeavesTheFileAlone() throws {
        let dir = try tempDir()
        let url = try fixtureCopy(in: dir)
        let original = try Data(contentsOf: url)
        let store = JSONFileStore(fileURL: url, currentVersion: 3, migrations: [Self.roundTripSteps[0]])
        #expect(throws: PersistenceError.missingMigration(2)) { try store.load() }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func everyShippedVersionHasAStep() {
        for version in 1..<JSONFileStore.schemaVersion {
            #expect(LibraryMigration.all.contains { $0.fromVersion == version }, "no migration from v\(version)")
        }
    }

    @Test func currentFixtureLoadsWithoutMigrating() throws {
        let dir = try tempDir()
        _ = try #require(try JSONFileStore(fileURL: try fixtureCopy(in: dir)).load())
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "library.v1.json").path))
    }
}

/// Storage decode fuzzing (SEC-067): a damaged library never crashes the app and is never silently lost.
@Suite("Storage fuzz")
struct StorageFuzzTests {
    @Test(arguments: 0..<4)
    func damagedLibrariesLoadOrAreMovedAside(seedBlock: Int) throws {
        let fixture = try Data(
            contentsOf: try #require(Bundle.module.url(forResource: "library-v1-app-0.1", withExtension: "json", subdirectory: "Fixtures")))
        let block = 100 * SeededRandom.scale
        for seed in UInt64(seedBlock) * block..<UInt64(seedBlock + 1) * block {
            var rng = SeededRandom(seed: seed)
            let dir = try tempDir()
            let url = dir.appending(path: "library.json")
            try rng.mutate(fixture).write(to: url)
            do {
                if try JSONFileStore(fileURL: url).load() == nil {
                    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                    #expect(files.contains { $0.hasPrefix("library.corrupt-") }, "seed \(seed): unreadable file was not kept")
                }
            } catch let error as PersistenceError {
                if case .newerSchema = error {} else { Issue.record("seed \(seed): \(error)") }
            } catch {
                Issue.record("seed \(seed): unexpected \(error)")
            }
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

/// Window/Space restoration (MAC-005): what the user was looking at comes back after a relaunch.
@Suite("Restoration")
struct RestorationTests {
    @Test func focusedSpaceAndTabSurviveARelaunch() throws {
        let env = TestEnv()
        var state = BrowserState.initial(uuid: env.nextUUID)
        for title in ["Work", "Research"] { _ = Reducer.reduce(&state, .space(.create(title: title)), env.reducer) }
        let work = try #require(state.spaces.first { $0.title == "Work" })
        _ = Reducer.reduce(&state, .space(.select(work.id)), env.reducer)
        _ = Reducer.reduce(&state, .tab(.open(URL(string: "https://one.example")!, .newTab)), env.reducer)
        let focused = try #require(state.selectedTabID)
        _ = Reducer.reduce(&state, .tab(.open(URL(string: "https://two.example")!, .newTab)), env.reducer)
        _ = Reducer.reduce(&state, .tab(.select(focused)), env.reducer)

        let url = try tempDir().appending(path: "library.json")
        try JSONFileStore(fileURL: url).save(state)
        let relaunched = try #require(try JSONFileStore(fileURL: url).load())  // a new process reads the same file
        #expect(relaunched.selectedSpaceID == work.id)
        #expect(relaunched.selectedTabID == focused)
        #expect(relaunched.spaces.map(\.title) == state.spaces.map(\.title), "Space order kept")
    }
}
