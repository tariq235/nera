// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import Foundation
import Testing

@testable import Import

/// A Space brought over from Arc keeps its exact colors, so it looks the same in Nera (made-up colors, in the shape
/// Arc stores them).
@Suite("Arc theme import")
struct ArcThemeImportTests {
    func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> [String: Any] {
        ["red": r, "green": g, "blue": b, "alpha": a, "colorSpace": "extendedSRGB"]
    }

    func windowTheme(base: [String: Any], intensity: Double = 0.7, focusLight: [String: Any]? = nil) -> [String: Any] {
        var theme: [String: Any] = [
            "background": [
                "single": [
                    "_0": [
                        "isVibrant": true,
                        "style": [
                            "color": [
                                "_0": [
                                    "blendedSingleColor": [
                                        "_0": ["color": base, "modifiers": ["intensityFactor": intensity, "noiseFactor": 0]]
                                    ]
                                ]
                            ]
                        ],
                    ]
                ]
            ]
        ]
        if let focusLight {
            theme["semanticColorPalette"] = [
                "appearanceBased": ["light": ["focus": focusLight], "dark": ["focus": color(0.3, 0.3, 0.3, 0.8)]]
            ]
        }
        return theme
    }

    @Test func aSpaceKeepsItsColorIntensityAndSelectionColors() throws {
        let theme = try #require(
            ArcImporter.theme(fromArc: windowTheme(base: color(0.2, 0.4, 0.3), focusLight: color(0.6, 0.7, 0.65))))
        let exact = try #require(theme.exact)
        #expect(exact.base == RGBA(red: 0.2, green: 0.4, blue: 0.3))
        #expect(exact.intensity == 0.7)
        #expect(exact.focusLight == RGBA(red: 0.6, green: 0.7, blue: 0.65))
        #expect(exact.focusDark == RGBA(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.8))
        // Editing in Nera starts from the same color.
        #expect(abs(theme.hue - 0.4167) < 0.001 && abs(theme.saturation - 0.5) < 0.001)
    }

    @Test func withoutAPaletteSelectionsAreDerivedFromTheColor() throws {
        let exact = try #require(ArcImporter.theme(fromArc: windowTheme(base: color(0.2, 0.4, 0.3)))?.exact)
        #expect(exact.focusLight == RGBA(red: 0.2, green: 0.4, blue: 0.3).mixed(with: .white, 0.49))
    }

    @Test func extendedColorsAreKeptInRangeAndNoColorMeansNoTheme() throws {
        let exact = try #require(ArcImporter.theme(fromArc: windowTheme(base: color(1.2, -0.1, 0.5)))?.exact)
        #expect(exact.base == RGBA(red: 1, green: 0, blue: 0.5))
        #expect(ArcImporter.theme(fromArc: ["background": ["single": [:]]]) == nil)
        #expect(ArcImporter.theme(fromArc: nil) == nil)
    }

    /// "Use Colors from Arc" on a Space imported before colors came over: found by the Space's Arc ID.
    @Test func spaceColorsAreFoundByTheSpacesID() throws {
        let id = UUID()
        let file: [String: Any] = [
            "sidebar": [
                "containers": [
                    ["global": [:]],
                    [
                        "spaces": [
                            id.uuidString, ["title": "Work", "customInfo": ["windowTheme": windowTheme(base: color(0.1, 0.2, 0.6))]],
                        ],
                        "items": [],
                    ],
                ]
            ]
        ]
        let themes = ArcImporter.spaceThemes(data: try JSONSerialization.data(withJSONObject: file))
        #expect(themes[id]?.exact?.base == RGBA(red: 0.1, green: 0.2, blue: 0.6))
        #expect(ArcImporter.spaceThemes(data: Data("{}".utf8)).isEmpty)
    }

    @Test func blendingBetweenSpacesMixesExactColors() {
        let a = SpaceTheme(hue: 0, saturation: 0, appearance: .system, exact: ExactColors(base: RGBA(red: 0, green: 0, blue: 0)))
        let b = SpaceTheme(hue: 0, saturation: 0, appearance: .system, exact: ExactColors(base: RGBA(red: 1, green: 1, blue: 1)))
        #expect(a.blended(toward: b, by: 0.5).exact?.base == RGBA(red: 0.5, green: 0.5, blue: 0.5))
        #expect(!a.looksLike(b))
    }
}
