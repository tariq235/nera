// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import SecurityPolicy
public import SwiftUI

/// Nera's colors, derived from a Space's theme.
public enum Theme {
    /// The gradient behind the sidebar and content for a Space (adapts to light and dark).
    @MainActor public static func background(for theme: SpaceTheme?) -> some View {
        SpaceBackground(theme: theme ?? .default).ignoresSafeArea()
    }

    /// The Space's accent: buttons, highlights and the start page.
    public static func accent(for theme: SpaceTheme?) -> Color {
        let t = theme ?? .default
        return Color(
            hue: t.hue, saturation: t.saturation < 0.05 ? 0 : max(0.55, t.saturation * 1.4), brightness: t.saturation < 0.05 ? 0.35 : 0.72)
    }

    /// A stable color per host, so monogram icons are recognizable.
    public static func monogramColor(for url: URL?) -> Color {
        let host = url?.host() ?? ""
        let hash = host.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.7)
    }
}

/// A site's icon: its favicon when known, otherwise a colored monogram.
public struct SiteIcon: View {
    let url: URL?
    let size: CGFloat
    let png: Data?

    /// Creates an icon for a URL at a point size, with the site's favicon (PNG) if there is one.
    public init(url: URL?, size: CGFloat, png: Data? = nil) {
        self.url = url
        self.size = size
        self.png = png
    }

    /// The icon.
    public var body: some View {
        if let image = png.flatMap(Self.image) {
            image.resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .frame(width: size + 4, height: size + 4)
                .accessibilityHidden(true)
        } else {
            monogram
        }
    }

    /// An image from PNG (or other image) data.
    public static func image(_ data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map { Image(nsImage: $0) }
        #else
            UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }

    @ViewBuilder private var monogram: some View {
        let letter = DisplayURL.short(url).first.map { String($0).uppercased() } ?? "•"
        Text(letter)
            .font(.system(size: size * 0.7, weight: .semibold, design: .rounded))
            .frame(width: size + 4, height: size + 4)
            .background(Theme.monogramColor(for: url), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

/// A Space's icon.
public struct SpaceIconView: View {
    let icon: SpaceIcon

    /// Creates the view.
    public init(icon: SpaceIcon) { self.icon = icon }

    /// The icon.
    public var body: some View {
        switch icon {
        case .emoji(let e): Text(e).font(.system(size: 14))
        case .symbol(let s): Image(systemName: s).font(.system(size: 12))
        }
    }
}

/// The system clipboard.
public enum Clipboard {
    /// Replaces the clipboard contents with plain text.
    @MainActor
    public static func copy(_ text: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
}

/// A Space's backdrop: a soft three-color gradient from its hue (blending into its second hue, if it has one),
/// a light glow at the top, and optional film grain.
public struct SpaceBackground: View {
    let theme: SpaceTheme
    @Environment(\.colorScheme) private var scheme

    /// Creates the backdrop.
    public init(theme: SpaceTheme) { self.theme = theme }

    /// The gradient's colors in `scheme`.
    public static func colors(_ theme: SpaceTheme, dark: Bool) -> [Color] {
        let h = theme.hue
        let s = theme.saturation
        // The way round the color wheel from the first hue to the second.
        var span = (theme.secondaryHue ?? (h + (dark ? 0.03 : 0.06))) - h
        if span > 0.5 { span -= 1 } else if span < -0.5 { span += 1 }
        func tone(_ f: Double, _ ds: Double, _ b: Double) -> Color {
            Color(hue: (h + span * f + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, s * ds), brightness: b)
        }
        return dark
            ? [tone(0, 0.9, 0.30), tone(0.5, 1.0, 0.22), tone(1, 0.95, 0.15)]
            : [tone(0, 0.85, 0.96), tone(0.5, 1.05, 0.90), tone(1, 1.15, 0.84)]
    }

    /// The backdrop.
    public var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: Self.colors(theme, dark: dark), startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [.white.opacity(dark ? 0.06 : 0.30), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            if let grain = theme.grain, grain > 0.01 { Grain(opacity: grain * (dark ? 0.16 : 0.22)) }
        }
    }
}

/// Film grain: a tiled noise texture, drawn over gradients so they don't band and feel like paper.
public struct Grain: View {
    let opacity: Double

    /// Creates grain at `opacity`.
    public init(opacity: Double) { self.opacity = opacity }

    /// The texture, made once.
    @MainActor static let texture: Image? = {
        let side = 160
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = UInt8.random(in: 0...255, using: &generator)
            pixels[i] = v
            pixels[i + 1] = v
            pixels[i + 2] = v
            pixels[i + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return Image(decorative: image, scale: 2)
    }()

    /// The grain.
    public var body: some View {
        if let texture = Self.texture {
            texture.resizable(resizingMode: .tile).blendMode(.overlay).opacity(opacity).allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Fills for the glassy controls on a Space backdrop (sidebar rows, tiles, the address pill).
public enum Surface {
    /// How prominent a fill is.
    public enum Level {
        /// Resting tiles and the address pill.
        case resting
        /// Under the pointer.
        case hover
        /// The selected row or tile.
        case selected
    }

    /// The fill for `level` in `scheme`.
    public static func fill(_ level: Level, _ scheme: ColorScheme) -> Color {
        switch (level, scheme == .dark) {
        case (.resting, false): .white.opacity(0.34)
        case (.hover, false): .white.opacity(0.26)
        case (.selected, false): .white.opacity(0.72)
        case (.resting, true): .white.opacity(0.08)
        case (.hover, true): .white.opacity(0.07)
        case (.selected, true): .white.opacity(0.17)
        }
    }
}

extension View {
    /// A rounded glass fill at `level`, with a soft shadow when selected.
    public func surface(_ level: Surface.Level?, cornerRadius: CGFloat = 8) -> some View {
        modifier(SurfaceModifier(level: level, cornerRadius: cornerRadius))
    }
}

struct SurfaceModifier: ViewModifier {
    let level: Surface.Level?
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background {
            if let level {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Surface.fill(level, scheme))
                    .shadow(color: .black.opacity(level == .selected && scheme == .light ? 0.08 : 0), radius: 1.5, y: 1)
            }
        }
    }
}

#if os(macOS)
    /// Shows or hides the window's close, minimize and zoom buttons (hidden with the sidebar, so the page fills the
    /// window; they come back with the sidebar).
    public struct WindowButtons: NSViewRepresentable {
        let isVisible: Bool

        /// Creates the control; put it in the window's background.
        public init(visible: Bool) { isVisible = visible }

        /// The backing view.
        public func makeNSView(context: Context) -> NSView { ButtonsView() }

        /// Applies the visibility.
        public func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? ButtonsView)?.isVisible = isVisible
        }

        final class ButtonsView: NSView {
            var isVisible = true { didSet { apply() } }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                apply()
            }

            private func apply() {
                for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    window?.standardWindowButton(kind)?.isHidden = !isVisible
                }
            }
        }
    }

    /// Makes empty parts of Nera's top bars act like a Mac title bar: drag to move the window, double-click to
    /// zoom or minimize (whichever is set in System Settings › Desktop & Dock).
    public struct TitleBarArea: NSViewRepresentable {
        /// Creates the area.
        public init() {}

        /// The backing view.
        public func makeNSView(context: Context) -> NSView { TitleBarView() }

        /// Nothing to update.
        public func updateNSView(_ nsView: NSView, context: Context) {}

        final class TitleBarView: NSView {
            override var mouseDownCanMoveWindow: Bool { true }

            override func mouseDown(with event: NSEvent) {
                guard let window else { return }
                if event.clickCount == 2 {
                    switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                    case "Minimize": window.performMiniaturize(nil)
                    case "None", "Do Nothing": break
                    default: window.performZoom(nil)
                    }
                } else {
                    window.performDrag(with: event)
                }
            }
        }
    }
#endif
