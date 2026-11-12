// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// profiles — create, rename, move Spaces, delete with everything they own.
@Suite("Profiles")
struct ProfileTests {
    let env = TestEnv()

    func start() -> BrowserState { BrowserState.initial(uuid: env.nextUUID) }

    @Test func creatingAProfileAddsItsFirstSpaceAndSwitchesToIt() throws {
        var s = start()
        _ = Reducer.reduce(&s, .library(.createProfile(name: "  Work ")), env.reducer)
        let work = try #require(s.profiles.last)
        #expect(work.name == "Work" && s.profiles.count == 2)
        #expect(s.selectedSpace?.profileID == work.id && s.selectedSpace?.title == "Work")
        _ = Reducer.reduce(&s, .library(.createProfile(name: "   ")), env.reducer)
        #expect(s.profiles.count == 2, "blank names are ignored")
        _ = Reducer.reduce(&s, .library(.renameProfile(work.id, name: "Job")), env.reducer)
        #expect(s.profiles.last?.name == "Job")
    }

    @Test func movingASpaceDiscardsItsPagesSoTheyReopenInTheNewProfile() throws {
        var s = start()
        let personal = s.profiles[0].id
        _ = Reducer.reduce(&s, .tab(.open(URL(string: "https://a.example")!, .newTab)), env.reducer)
        let tab = try #require(s.selectedTabID)
        let space = s.selectedSpaceID
        _ = Reducer.reduce(&s, .library(.createProfile(name: "Work")), env.reducer)
        let work = try #require(s.profiles.last?.id)
        let effects = Reducer.reduce(&s, .space(.setProfile(space, profileID: work)), env.reducer)
        #expect(s.spaces.first { $0.id == space }?.profileID == work)
        #expect(effects == [.discardPage(tabID: tab)])
        #expect(Reducer.reduce(&s, .space(.setProfile(space, profileID: work)), env.reducer).isEmpty, "no-op when unchanged")
        #expect(Reducer.reduce(&s, .space(.setProfile(space, profileID: UUID())), env.reducer).isEmpty, "unknown profile ignored")
        _ = Reducer.reduce(&s, .space(.createInProfile(title: "Home", profileID: personal)), env.reducer)
        #expect(s.selectedSpace?.title == "Home" && s.selectedSpace?.profileID == personal)
    }

    @Test func deletingAProfileRemovesEverythingItOwns() throws {
        var s = start()
        _ = Reducer.reduce(&s, .library(.createProfile(name: "Work")), env.reducer)
        let work = try #require(s.profiles.last?.id)
        _ = Reducer.reduce(&s, .tab(.open(URL(string: "https://work.example")!, .newTab)), env.reducer)
        let workTab = try #require(s.selectedTabID)
        _ = Reducer.reduce(&s, .tab(.open(URL(string: "https://closed.example")!, .newTab)), env.reducer)
        _ = Reducer.reduce(&s, .tab(.close(try #require(s.selectedTabID))), env.reducer)
        #expect(!s.recentlyClosed.isEmpty)

        let effects = Reducer.reduce(&s, .library(.deleteProfile(work)), env.reducer)
        #expect(!s.profiles.contains { $0.id == work })
        #expect(!s.spaces.contains { $0.profileID == work })
        #expect(s.recentlyClosed.isEmpty && s.archive.isEmpty, "closed tabs of its Spaces are gone too")
        #expect(effects.contains(.discardPage(tabID: workTab)))
        #expect(effects.last == .removeProfileData(profileID: work), "website data and history are deleted")
        #expect(s.spaces.contains { $0.id == s.selectedSpaceID }, "selection moved to a remaining Space")

        let last = s.profiles[0].id
        #expect(Reducer.reduce(&s, .library(.deleteProfile(last)), env.reducer).isEmpty, "the last profile stays")
        #expect(s.profiles.count == 1)
    }

    @Test func deletingTheProfileOfEverySpaceLeavesAFreshSpace() throws {
        var s = start()
        let personal = s.profiles[0].id
        _ = Reducer.reduce(&s, .library(.createProfile(name: "Work")), env.reducer)
        let work = try #require(s.profiles.last?.id)
        for space in s.spaces where space.profileID == personal {
            _ = Reducer.reduce(&s, .space(.setProfile(space.id, profileID: work)), env.reducer)
        }
        _ = Reducer.reduce(&s, .library(.deleteProfile(work)), env.reducer)
        #expect(s.spaces.count == 1 && s.spaces[0].profileID == personal && s.selectedSpaceID == s.spaces[0].id)
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func developerToolsAreOffUntilTurnedOn() throws {
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        #expect(!s.settings.isDeveloperToolsEnabled)
        _ = Reducer.reduce(&s, .library(.setDeveloperTools(true)), env.reducer)
        #expect(s.settings.isDeveloperToolsEnabled)
        _ = Reducer.reduce(&s, .library(.setDeveloperTools(false)), env.reducer)
        #expect(!s.settings.isDeveloperToolsEnabled)
        let old = #"{"archiveAfter":43200,"httpsOnly":true,"searchEngine":{"name":"D","template":"https://d.example/?q={query}"}}"#
        #expect(try !JSONDecoder().decode(Settings.self, from: Data(old.utf8)).isDeveloperToolsEnabled, "older libraries decode")
    }

    @Test func videosPopOutUnlessTurnedOff() throws {
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        #expect(s.settings.autoPictureInPicture)
        _ = Reducer.reduce(&s, .library(.setAutoPictureInPicture(false)), env.reducer)
        #expect(!s.settings.autoPictureInPicture)
        let saved = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s.settings))
        #expect(!saved.autoPictureInPicture, "the choice is saved")
        let old = #"{"archiveAfter":43200,"httpsOnly":true,"searchEngine":{"name":"D","template":"https://d.example/?q={query}"}}"#
        #expect(try JSONDecoder().decode(Settings.self, from: Data(old.utf8)).autoPictureInPicture, "on for older libraries")
    }

    @Test func searchEngineCanBeChangedFromTheDefault() {
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        #expect(s.settings.searchEngine == .duckDuckGo)
        _ = Reducer.reduce(&s, .library(.setSearchEngine(.google)), env.reducer)
        #expect(s.settings.searchEngine == .google)
        _ = Reducer.reduce(&s, .library(.setSearchEngine(SearchEngine(name: "Broken", template: "not a url {query} %%"))), env.reducer)
        #expect(s.settings.searchEngine == .google, "an engine that can't build a search URL is refused")
        for engine in SearchEngine.presets {
            #expect(engine.url(for: "nera browser")?.scheme == "https", "\(engine.name)")
        }
        #expect(Set(SearchEngine.presets.map(\.name)).count == SearchEngine.presets.count)
    }

    @Test func archiveIntervalIsAdjustableButNeverUnderAnHour() {
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        _ = Reducer.reduce(&s, .library(.setArchiveAfter(7 * 86400)), env.reducer)
        #expect(s.settings.archiveAfter == 7 * 86400)
        _ = Reducer.reduce(&s, .library(.setArchiveAfter(5)), env.reducer)
        #expect(s.settings.archiveAfter == 3600)
    }
}

@Suite("Site zoom storage")
struct SiteZoomStorageTests {
    @Test func zoomIsRememberedPerHostAndClamped() {
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        let p = s.profiles[0].id
        _ = Reducer.reduce(&s, .library(.setSiteZoom(profileID: p, host: "News.Example", factor: 1.25)), env.reducer)
        _ = Reducer.reduce(&s, .library(.setSiteZoom(profileID: p, host: "tiny.example", factor: 0.01)), env.reducer)
        #expect(s.profiles[0].siteZoom == ["news.example": 1.25, "tiny.example": 0.25])
        _ = Reducer.reduce(&s, .library(.setSiteZoom(profileID: p, host: "news.example", factor: 1)), env.reducer)
        _ = Reducer.reduce(&s, .library(.setSiteZoom(profileID: p, host: "tiny.example", factor: nil)), env.reducer)
        #expect(s.profiles[0].siteZoom == nil, "100% isn't stored")
    }
}
