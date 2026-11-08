// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// Space colors and icons, Edit Space, and the first-launch welcome flag.
@Suite("Look and welcome")
struct LookAndWelcomeTests {
    let env = TestEnv()

    func start() -> BrowserState { BrowserState.initial(uuid: env.nextUUID) }

    @Test func newSpacesGetTheNextPaletteColorAndIcon() {
        var s = start()
        _ = Reducer.reduce(&s, .space(.create(title: "Work")), env.reducer)
        _ = Reducer.reduce(&s, .space(.create(title: "Study")), env.reducer)
        #expect(s.spaces.map(\.theme) == SpaceTheme.palette.prefix(3).map(\.theme))
        #expect(s.spaces.map(\.icon) == SpaceTheme.palette.prefix(3).map(\.icon))
        #expect(Set(s.spaces.map(\.theme.hue)).count == 3, "Spaces are easy to tell apart")
    }

    @Test func customizeChangesOnlyWhatIsGivenAndClampsColors() {
        var s = start()
        let id = s.selectedSpaceID
        let icon = s.spaces[0].icon
        _ = Reducer.reduce(
            &s, .space(.customize(id, icon: nil, theme: SpaceTheme(hue: 1.7, saturation: -1, appearance: .dark))), env.reducer)
        #expect(s.spaces[0].theme == SpaceTheme(hue: 1, saturation: 0, appearance: .dark) && s.spaces[0].icon == icon)
        _ = Reducer.reduce(&s, .space(.customize(id, icon: .emoji("🚀"), theme: nil)), env.reducer)
        #expect(s.spaces[0].icon == .emoji("🚀") && s.spaces[0].theme.appearance == .dark)
        #expect(Reducer.reduce(&s, .space(.customize(UUID(), icon: .emoji("x"), theme: nil)), env.reducer).isEmpty)
    }

    @Test func theWelcomeShowsOnceOnANewLibraryOnly() throws {
        var s = start()
        #expect(!s.settings.hasCompletedOnboarding)
        _ = Reducer.reduce(&s, .library(.completeOnboarding), env.reducer)
        #expect(s.settings.hasCompletedOnboarding)
        // A library saved before the welcome existed decodes as finished, so existing users never see it.
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings.default)) as? [String: Any])
        json.removeValue(forKey: "onboarded")
        let old = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.hasCompletedOnboarding)
    }

    @Test func themesFromBeforeBlendAndGrainStillLoad() throws {
        let old = Data(#"{"hue":0.5,"saturation":0.3,"appearance":"dark"}"#.utf8)
        let theme = try JSONDecoder().decode(SpaceTheme.self, from: old)
        #expect(theme == SpaceTheme(hue: 0.5, saturation: 0.3, appearance: .dark))
        #expect(theme.secondaryHue == nil && theme.grain == nil)
        let swatch = SpaceTheme.swatches[0]
        #expect(try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(swatch)) == swatch)
        #expect(SpaceTheme(hue: 0.2, saturation: 0.2, appearance: .light, secondaryHue: 3, grain: -1).clamped.secondaryHue == 1)
        #expect(SpaceTheme(hue: 0.2, saturation: 0.2, appearance: .light, secondaryHue: 3, grain: -1).clamped.grain == 0)
    }

    @Test func importedArchiveKeepsKnownSpacesNewestFirstCappedAndUnique() {
        var s = start()
        let space = s.selectedSpaceID
        func archived(_ seconds: TimeInterval, in spaceID: UUID) -> ArchivedTab {
            ArchivedTab(
                tab: Tab(id: env.nextUUID(), url: URL(string: "https://a.example"), title: "", lastActiveAt: Date()), spaceID: spaceID,
                archivedAt: Date(timeIntervalSince1970: seconds))
        }
        let old = archived(1, in: space)
        let new = archived(2, in: space)
        let elsewhere = archived(3, in: UUID())
        _ = Reducer.reduce(&s, .library(.importArchive([old, new, elsewhere])), env.reducer)
        #expect(s.archive.map(\.id) == [new.id, old.id], "only Spaces that exist, newest first")
        _ = Reducer.reduce(&s, .library(.importArchive([new])), env.reducer)
        #expect(s.archive.count == 2, "importing twice doesn't duplicate")
        let many = (0..<(BrowserState.archiveLimit + 20)).map { archived(Double(10 + $0), in: space) }
        _ = Reducer.reduce(&s, .library(.importArchive(many)), env.reducer)
        #expect(s.archive.count == BrowserState.archiveLimit && s.archive.first?.id == many.last?.id)
    }

    @Test func themesBlendTheShortWayRoundTheColorWheel() {
        let a = SpaceTheme(hue: 0.95, saturation: 0.2, appearance: .light, grain: 0)
        let b = SpaceTheme(hue: 0.05, saturation: 0.6, appearance: .dark, grain: 1)
        let mid = a.blended(toward: b, by: 0.5)
        #expect(abs(mid.hue - 0) < 0.001 || abs(mid.hue - 1) < 0.001, "0.95 → 0.05 passes through red, not green")
        #expect(abs(mid.saturation - 0.4) < 0.001 && mid.appearance == .dark && mid.grain == 0.5)
        #expect(a.blended(toward: b, by: 0) == SpaceTheme(hue: 0.95, saturation: 0.2, appearance: .light, secondaryHue: 0.95, grain: 0))
    }
}
