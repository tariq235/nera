// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineTestSupport
import Foundation
import PageLifecycle
import Storage
import TestSupport
import Testing

@testable import BrowserShell

@MainActor
@Suite("App model")
struct AppModelTests {
    func model() -> AppModel {
        AppModel(store: .load(persistence: InMemoryStore()), registry: EngineRegistry([FakeEngine()]), downloadsDirectory: nil)
    }

    @Test func linksFromOtherAppsOpenThroughThePolicy() {
        let m = model()
        m.send(.library(.setExternalLinks(.currentSpace)))
        m.openFromOutside(URL(string: "http://news.example/story")!)
        #expect(m.state.selectedTab?.url?.absoluteString == "https://news.example/story", "HTTPS upgrade applies")
        let tabs = m.state.spaces[0].today.count
        m.openFromOutside(URL(string: "javascript:alert(1)")!)
        m.openFromOutside(URL(string: "zoommtg://join")!)
        #expect(m.state.spaces[0].today.count == tabs, "scripts and other apps' schemes never open tabs")
        #expect(m.pages.lastBlocked != nil)
    }

    @Test func zoomStepsFollowChrome() {
        #expect(AppModel.nextZoom(from: 1, direction: 1) == 1.1)
        #expect(AppModel.nextZoom(from: 1, direction: -1) == 0.9)
        #expect(AppModel.nextZoom(from: 1.05, direction: 1) == 1.1, "between steps: the next one up")
        #expect(AppModel.nextZoom(from: 5, direction: 1) == 5 && AppModel.nextZoom(from: 0.25, direction: -1) == 0.25)
    }

    @Test func privateWindowsAreSeparateAndEphemeral() {
        let registry = EngineRegistry([FakeEngine()])
        let main = AppModel(store: .load(persistence: InMemoryStore()), registry: registry, downloadsDirectory: nil)
        let secret = AppModel.privateWindow(registry: registry)
        #expect(secret.isPrivate && !main.isPrivate)
        #expect(secret.history == nil, "no history")
        guard case .ephemeral? = secret.pages.defaultStorage else {
            Issue.record("private pages must be ephemeral")
            return
        }
        secret.send(.tab(.open(URL(string: "https://secret.example")!, .newTab)))
        #expect(main.state.spaces.flatMap(\.today).isEmpty, "nothing reaches the main library")
        #expect(secret.state.selectedSpace?.title == "Private")
    }

    @Test func developerToolsNeedConfirmationFirst() {
        let m = model()
        m.send(.tab(.open(URL(string: "https://a.example")!, .newTab)))
        m.showDevTools()
        #expect(m.isConfirmingDevTools, "asks before turning them on")
        m.setDeveloperTools(true)
        #expect(m.pages.devToolsEnabled && m.state.settings.isDeveloperToolsEnabled)
    }

    @Test func startingFreshAddsFavoritesAWorkSpaceAndClosesTheWelcome() {
        let m = AppModel(
            store: .load(persistence: InMemoryStore(BrowserState.initial(uuid: UUID.init))), registry: EngineRegistry([FakeEngine()]),
            downloadsDirectory: nil)
        #expect(m.isWelcomePresented)
        let space = m.state.selectedSpaceID
        m.startFresh(favorites: [URL(string: "https://a.example")!, URL(string: "https://b.example")!], addWorkSpace: true)
        #expect(!m.isWelcomePresented)
        #expect(m.state.profiles[0].favorites.compactMap { $0.homeURL?.host() } == ["a.example", "b.example"])
        #expect(m.state.spaces.map(\.title) == ["Personal", "Work"] && m.state.selectedSpaceID == space)
    }

    @Test func startPageTilesUseSiteNamesNotPageTitles() {
        #expect(SiteTile.name(url: URL(string: "https://github.com")!, title: "GitHub · Build and ship software") == "GitHub")
        #expect(SiteTile.name(url: URL(string: "https://claude.ai/login")!, title: "Sign in") == "Claude")
        #expect(SiteTile.name(url: URL(string: "https://open.spotify.com")!, title: "") == "Spotify")
    }

    @Test func newSpaceOpensTheEditorAndCancelRemovesItAgain() {
        let m = model()
        let before = m.state.spaces.map(\.id)
        m.newSpace()
        let id = m.editingSpaceID
        #expect(m.isCreatingSpace && id != nil && m.state.spaces.count == before.count + 1 && m.state.selectedSpaceID == id)
        m.endEditingSpace(keep: false)
        #expect(m.state.spaces.map(\.id) == before && m.editingSpaceID == nil && !m.isCreatingSpace)
        m.newSpace()
        m.endEditingSpace(keep: true)
        #expect(m.state.spaces.count == before.count + 1 && m.state.spaces.last?.title == "Space 2", "a blank name gets a default")
    }

    @Test func editingAnExistingSpaceNeverDeletesIt() {
        let m = model()
        m.editSpace(m.state.selectedSpaceID)
        m.endEditingSpace(keep: false)
        #expect(m.state.spaces.count == 1 && m.editingSpaceID == nil)
    }

    @Test func theWelcomeFlowSkipsImportStepsWhenStartingFresh() {
        let m = model()
        let flow = OnboardingFlow(model: m)
        flow.blockTrackers = false
        flow.makeDefault = false
        flow.addToDock = false
        #expect(flow.step == .intro && !flow.canGoBack)
        flow.next()
        flow.skip()  // essentials
        #expect(flow.step == .privacy)
        flow.next()
        if flow.step == .source { flow.skip() }
        #expect(flow.step == .favorites)
        flow.back()
        #expect(flow.step != .favorites && flow.canGoBack)
    }

    @Test func welcomeProgressDotsFollowTheParts() {
        let flow = OnboardingFlow(model: model())
        #expect(flow.stage == 0 && flow.progress == 0 && !flow.canSkip)
        flow.next()
        #expect(flow.stage == 1 && flow.canSkip && flow.canGoBack)
    }

    @Test func everyImportedSpaceGetsItsOwnLook() {
        let first = SpaceTheme.swatches[1]
        let looks = OnboardingFlow.looks(startingWith: first, count: 4)
        #expect(looks.first == first)
        #expect(Set(looks.map(\.hue)).count == 4, "Spaces are easy to tell apart")
        #expect(looks.allSatisfy { $0.appearance == first.appearance })
    }
}
