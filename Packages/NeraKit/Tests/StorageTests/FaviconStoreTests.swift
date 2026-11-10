// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import Storage

@Suite("Favicon store")
struct FaviconStoreTests {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])

    @Test func iconsSurviveARelaunchAndHostsAreSanitized() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nera-favicons-\(UUID().uuidString)")
        FaviconStore(directory: dir).save(png, forHost: "Example.COM")
        #expect(FaviconStore(directory: dir).icon(forHost: "example.com") == png)
        #expect(FaviconStore.key("../../etc/passwd") == "....etcpasswd", "no path separators")
        #expect(FaviconStore.key("..") == "", "dots only isn't a name")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files == ["example.com.png"])
    }

    /// The command bar completes "face" to facebook.com; the icon was saved while visiting www.facebook.com.
    @Test func wwwAndTheBareDomainShareAnIcon() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nera-favicons-\(UUID().uuidString)")
        let store = FaviconStore(directory: dir)
        store.save(png, forHost: "www.facebook.com")
        #expect(store.icon(forHost: "facebook.com") == png)
        let other = Data([0x89, 0x50, 0x4E, 0x47, 9])
        store.save(other, forHost: "github.com")
        #expect(store.icon(forHost: "www.github.com") == other)
        #expect(store.icon(forHost: "gist.github.com") == nil, "other subdomains are other sites")
    }

    @Test func oversizedIconsAreIgnoredAndClearingWorks() {
        let store = FaviconStore(directory: nil)
        store.save(Data(count: FaviconStore.maxBytes + 1), forHost: "big.example")
        #expect(store.icon(forHost: "big.example") == nil)
        store.save(png, forHost: "a.example")
        store.removeAll()
        #expect(store.icon(forHost: "a.example") == nil)
    }
}
