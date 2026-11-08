// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

@Suite("Reducer: child pages & engines")
struct ReducerChildPageTests {
    @Test func childPageBecomesATabInTheOpenersSpaceWithTheEnginesID() {
        var h = Harness()
        let first = h.state.selectedSpaceID
        let opener = h.open("https://app.example")
        h.send(.space(.create(title: "Other")))
        let childID = UUID()
        let effects = h.send(.tab(.openChild(id: childID, url: URL(string: "https://auth.example/login"), openerID: opener, select: true)))
        #expect(effects.isEmpty)  // the engine is already loading the child; no `.load`
        #expect(h.state.selectedSpaceID == first)
        #expect(h.state.selectedTabID == childID)
        #expect(h.state.spaces.first { $0.id == first }?.today.first?.id == childID)
    }

    @Test func backgroundChildDoesNotStealFocus() {
        var h = Harness()
        let opener = h.open("https://app.example")
        h.send(.tab(.openChild(id: UUID(), url: nil, openerID: opener, select: false)))
        #expect(h.state.selectedTabID == opener)
        #expect(h.space.today.count == 2)
    }

    @Test func duplicateChildIsIgnored() {
        var h = Harness()
        let opener = h.open("https://app.example")
        let child = UUID()
        h.send(.tab(.openChild(id: child, url: nil, openerID: opener, select: true)))
        h.send(.tab(.openChild(id: child, url: nil, openerID: opener, select: true)))
        #expect(h.space.today.count == 2)
    }

    @Test func profilesDefaultToThePlatformEngine() {
        #expect(Harness().state.profiles[0].engine == nil)
    }

    @Test func changingEngineDiscardsThatProfilesPagesOnly() {
        var h = Harness()
        let profile = h.state.profiles[0].id
        let a = h.open("https://a.example")
        let b = h.open("https://b.example")
        h.send(.tab(.addToFavorites(b)))
        let effects = h.send(.library(.setEngine(profileID: profile, engine: .webKit)))
        #expect(h.state.profiles[0].engine == .webKit)
        #expect(Set(effects) == [.discardPage(tabID: a), .discardPage(tabID: b)])
        #expect(h.send(.library(.setEngine(profileID: profile, engine: .webKit))).isEmpty)  // no-op when unchanged
    }

    @Test func engineIDEncodesAsAPlainString() throws {
        let data = try JSONEncoder().encode(EngineID.chromium)
        #expect(String(decoding: data, as: UTF8.self) == "\"chromium\"")
    }
}
