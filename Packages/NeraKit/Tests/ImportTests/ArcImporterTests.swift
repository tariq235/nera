// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import Foundation
import Testing

@testable import Import

@Suite("ArcImporter")
struct ArcImporterTests {
    let profile = UUID()

    func fixture() throws -> ArcImporter.Result {
        let url = try #require(Bundle.module.url(forResource: "StorableSidebar.sample", withExtension: "json", subdirectory: "Fixtures"))
        return try ArcImporter.parse(data: Data(contentsOf: url), profileID: profile)
    }

    @Test func importsSpacesInOrderWithIcons() throws {
        let r = try fixture()
        #expect(r.spaces.map(\.title) == ["Work", "Imported Space"])
        #expect(r.spaces[0].icon == .emoji("💼"))
        #expect(r.spaces.allSatisfy { $0.profileID == profile })
        #expect(r.spaces[0].id == UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))
    }

    @Test func importsPinnedTreeWithFolderAndSplit() throws {
        let work = try fixture().spaces[0]
        #expect(work.pinned.count == 2)
        guard case .tab(let docs) = work.pinned[0].kind else {
            Issue.record("expected tab")
            return
        }
        #expect(docs.title == "Docs")
        #expect(docs.homeURL == URL(string: "https://docs.example.com/home"))
        #expect(docs.lastActiveAt == Date(timeIntervalSinceReferenceDate: 790_000_000))

        guard case .folder(let folder) = work.pinned[1].kind else {
            Issue.record("expected folder")
            return
        }
        #expect(folder.title == "Projects")
        #expect(folder.children.count == 2)
        guard case .split(let split) = folder.children[1].kind else {
            Issue.record("expected split")
            return
        }
        #expect(split.tabs.map(\.title) == ["Left", "Right"])
    }

    @Test func importsTodayTabsAndSkipsUnknownKinds() throws {
        let r = try fixture()
        #expect(r.spaces[0].today.map(\.tabs).flatMap { $0 }.map(\.title) == ["News"])
        #expect(r.spaces[0].today.first?.tabs.first?.homeURL == nil)
        #expect(r.report.skipped == ["easel": 1, "tab-without-url": 1])
    }

    @Test func importsFavoritesAndReport() throws {
        let r = try fixture()
        #expect(r.favorites.map(\.title) == ["Mail"])
        #expect(r.report.spaces == 2)
        #expect(r.report.folders == 1)
        #expect(r.report.favorites == 1)
        #expect(r.report.tabs == 6)  // docs, repo, left, right, news, other
        #expect(r.report.spacesFromOtherProfiles == 1)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: ArcImporter.ImportError.notArcSidebarFile) {
            try ArcImporter.parse(data: Data(#"{"hello":"world"}"#.utf8), profileID: UUID())
        }
    }

    @Test func importedLibraryFeedsReducer() throws {
        let r = try fixture()
        var state = BrowserState.initial(uuid: { UUID() })
        let p = state.profiles[0].id
        let result = try ArcImporter.parse(
            data: Data(
                contentsOf: Bundle.module.url(forResource: "StorableSidebar.sample", withExtension: "json", subdirectory: "Fixtures")!),
            profileID: p)
        _ = Reducer.reduce(&state, .library(.importLibrary(spaces: result.spaces, favorites: result.favorites)), .live)
        #expect(state.spaces.count == 1 + r.spaces.count)
        #expect(state.selectedSpace?.title == "Work")
        #expect(state.profiles[0].favorites.map(\.title) == ["Mail"])
    }
}
