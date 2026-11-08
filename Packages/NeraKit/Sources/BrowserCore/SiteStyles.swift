// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// A SiteStyle: how the user restyles one website (its colors, font, hidden parts and their own CSS). Applied by
/// Nera to every page of the site, on top of the site's own styles.
public struct SiteStyle: Codable, Hashable, Sendable {
    /// Off keeps the SiteStyle but shows the site as it is.
    public var isEnabled = true
    /// Turns the page's colors around (light pages become dark); pictures and videos keep theirs.
    public var isDark = false
    /// Shifts every color of the page around the color wheel (degrees, 0 = unchanged).
    public var hueRotation: Double = 0
    /// Color intensity (1 = unchanged, 0 = grayscale).
    public var saturation: Double = 1
    /// The font the page's text uses.
    public var font = SiteStyleFont.site
    /// Parts of the page the user hid with Zap (CSS selectors).
    public var zapped: [String] = []
    /// The user's own CSS.
    public var css = ""

    /// Creates a SiteStyle that changes nothing yet.
    public init() {}

    /// Whether it changes anything.
    public var isEmpty: Bool {
        !isDark && abs(hueRotation) < 0.5 && abs(saturation - 1) < 0.01 && font == .site && zapped.isEmpty
            && css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The style sheet Nera adds to the site's pages (empty when off).
    public var styleSheet: String {
        guard isEnabled else { return "" }
        var rules: [String] = []
        var filters: [String] = []
        if isDark { filters.append("invert(1) hue-rotate(180deg)") }
        if abs(hueRotation) >= 0.5 { filters.append("hue-rotate(\(Int(hueRotation.rounded()))deg)") }
        if abs(saturation - 1) >= 0.01 { filters.append(String(format: "saturate(%.2f)", max(0, min(saturation, 3)))) }
        if !filters.isEmpty {
            rules.append("html { filter: \(filters.joined(separator: " ")) !important; }")
            // Turn pictures and videos back, so they keep their real colors.
            var undo: [String] = []
            if abs(hueRotation) >= 0.5 { undo.append("hue-rotate(\(-Int(hueRotation.rounded()))deg)") }
            if isDark { undo.append("invert(1) hue-rotate(180deg)") }
            if !undo.isEmpty {
                let media = "img, picture, video, canvas, svg image, [style*=\"background-image\"]"
                rules.append("\(media) { filter: \(undo.joined(separator: " ")) !important; }")
            }
            if isDark { rules.append("html { background: #fff !important; }") }
        }
        if let family = font.cssFamily {
            let text = "body, body *:not(pre):not(code):not(kbd):not(samp):not([class*=\"icon\"]):not([class*=\"Icon\"])"
            rules.append("\(text) { font-family: \(family) !important; }")
        }
        let selectors = zapped.filter(Self.isSafeSelector)
        if !selectors.isEmpty { rules.append("\(selectors.joined(separator: ", ")) { display: none !important; }") }
        let custom = css.replacingOccurrences(of: "</", with: "<\\/")
        if !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rules.append(custom) }
        return rules.joined(separator: "\n")
    }

    /// Zap selectors come from Nera's own picker; anything that could break out of a rule is dropped.
    static func isSafeSelector(_ selector: String) -> Bool {
        !selector.isEmpty && selector.count < 500 && !selector.contains(where: { "{}<;@\\".contains($0) })
    }

    /// The key SiteStyles are stored under: the host without "www.".
    public static func site(of url: URL?) -> String? {
        guard let host = url?.host()?.lowercased(), !host.isEmpty, ["http", "https"].contains(url?.scheme ?? "") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A font choice for SiteStyles.
public enum SiteStyleFont: String, Codable, Hashable, Sendable, CaseIterable {
    /// The site's own fonts.
    case site
    /// The system's sans-serif.
    case sans
    /// A serif for reading.
    case serif
    /// Monospaced.
    case mono
    /// Rounded.
    case rounded

    /// Shown name.
    public var title: String {
        switch self {
        case .site: "Site"
        case .sans: "Sans"
        case .serif: "Serif"
        case .mono: "Mono"
        case .rounded: "Rounded"
        }
    }

    var cssFamily: String? {
        switch self {
        case .site: nil
        case .sans: "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"
        case .serif: "\"New York\", \"Iowan Old Style\", Georgia, serif"
        case .mono: "ui-monospace, \"SF Mono\", Menlo, monospace"
        case .rounded: "ui-rounded, \"SF Pro Rounded\", -apple-system, sans-serif"
        }
    }
}
