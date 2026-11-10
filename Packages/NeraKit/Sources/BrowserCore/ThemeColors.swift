// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A color as numbers: sRGB components and opacity, 0...1.
public struct RGBA: Codable, Hashable, Sendable {
    /// Red, 0...1.
    public var red: Double
    /// Green, 0...1.
    public var green: Double
    /// Blue, 0...1.
    public var blue: Double
    /// Opacity, 0...1.
    public var alpha: Double

    /// Creates a color.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// This color moved `t` of the way toward `other`.
    public func mixed(with other: RGBA, _ t: Double) -> RGBA {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return RGBA(red: m(red, other.red), green: m(green, other.green), blue: m(blue, other.blue), alpha: m(alpha, other.alpha))
    }

    /// Hue, saturation and brightness, 0...1.
    public struct HSB: Sendable {
        /// Hue, 0...1.
        public var hue: Double
        /// Saturation, 0...1.
        public var saturation: Double
        /// Brightness, 0...1.
        public var brightness: Double
    }

    /// This color's hue, saturation and brightness.
    public var hsb: HSB {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
        }
        return HSB(hue: hue, saturation: maxC == 0 ? 0 : delta / maxC, brightness: maxC)
    }

    /// Opaque white.
    public static let white = RGBA(red: 1, green: 1, blue: 1)
}

/// A Space's colors exactly as another browser showed them: the window's color, how strongly it tints the window,
/// and the colors derived from it for selections in light and dark.
public struct ExactColors: Codable, Hashable, Sendable {
    /// The Space's color.
    public var base: RGBA
    /// How strongly `base` tints the window, 0...1.
    public var intensity: Double
    /// The selection color (the highlighted suggestion, the selected tab's ring) in light appearance.
    public var focusLight: RGBA
    /// The selection color in dark appearance.
    public var focusDark: RGBA

    /// Creates exact colors.
    public init(base: RGBA, intensity: Double, focusLight: RGBA, focusDark: RGBA) {
        self.base = base
        self.intensity = intensity
        self.focusLight = focusLight
        self.focusDark = focusDark
    }

    /// Exact colors for a base color, with selections derived the way Arc derives them: half white in light
    /// appearance, a fifth in dark.
    public init(base: RGBA, intensity: Double = 0.8) {
        self.init(
            base: base, intensity: intensity, focusLight: base.mixed(with: .white, 0.49),
            focusDark: base.mixed(with: .white, 0.2))
    }

    func blended(toward other: ExactColors, by t: Double) -> ExactColors {
        ExactColors(
            base: base.mixed(with: other.base, t), intensity: intensity + (other.intensity - intensity) * t,
            focusLight: focusLight.mixed(with: other.focusLight, t), focusDark: focusDark.mixed(with: other.focusDark, t))
    }
}
