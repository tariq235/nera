// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import SwiftUI

#if os(macOS)
    import AppKit
#endif

// The welcome screen's building blocks: Nera's spectrum, type, the light button, grouped rows and entrances.

/// Nera's spectrum: the colors of the ring in its icon. The welcome screen's light is made of these.
enum Spectrum {
    static let cyan = Color(red: 0.36, green: 0.82, blue: 0.96)
    static let mint = Color(red: 0.50, green: 0.90, blue: 0.74)
    static let violet = Color(red: 0.60, green: 0.50, blue: 0.98)
    static let pink = Color(red: 0.98, green: 0.56, blue: 0.80)
    static let peach = Color(red: 1.00, green: 0.75, blue: 0.58)
    static let all = [cyan, mint, violet, pink, peach]

    /// The ring as an angular gradient (closed loop).
    static var ring: AngularGradient { AngularGradient(colors: [cyan, mint, peach, pink, violet, cyan], center: .center) }
}

/// Colors of the welcome screen in light and dark.
struct WelcomePalette {
    let scheme: ColorScheme
    var dark: Bool { scheme == .dark }

    var canvas: Color { dark ? Color(red: 0.05, green: 0.055, blue: 0.07) : Color(red: 0.972, green: 0.968, blue: 0.962) }
    var group: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.72) }
    var groupStroke: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06) }
    var divider: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07) }
    var ink: Color { dark ? Color(white: 0.97) : Color(white: 0.09) }
    var secondary: Color { dark ? Color(white: 0.66) : Color(white: 0.40) }
    var tertiary: Color { dark ? Color(white: 0.48) : Color(white: 0.58) }
    var buttonFill: Color { dark ? Color(white: 0.97) : Color(white: 0.10) }
    var buttonText: Color { dark ? Color(white: 0.06) : .white }
    var hover: Color { dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035) }
}

/// Sizes that follow the window: smaller windows get a shorter illustration and type.
struct WelcomeMetrics {
    let size: CGSize
    var isCompact: Bool { size.height < 780 }
    /// Very short windows (down to the 520-point minimum).
    var isTight: Bool { size.height < 640 }
    var isWide: Bool { size.width >= 1020 }
    var hero: CGFloat { isTight ? 92 : isCompact ? 132 : 188 }
    var title: Font { .system(size: isTight ? 27 : isCompact ? 31 : 38, weight: .semibold) }
    var gap: CGFloat { isTight ? 12 : isCompact ? 18 : 26 }
}

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = WelcomeMetrics(size: CGSize(width: 1200, height: 800))
}

extension EnvironmentValues {
    var welcomeMetrics: WelcomeMetrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

/// The main button: a capsule of light with a soft spectrum glow, and a return-key cap.
struct LightButton: View {
    let title: String
    var isEnabled = true
    var isBusy = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        Button(action: action) {
            HStack(spacing: 10) {
                if isBusy { ProgressView().controlSize(.small).tint(palette.buttonText) }
                Text(title).font(.system(size: 15, weight: .semibold))
                Image(systemName: "return")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 22, height: 18)
                    .background(palette.buttonText.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .foregroundStyle(palette.buttonText)
            .padding(.horizontal, 26)
            .frame(minWidth: 240, minHeight: 48)
            .background {
                ZStack {
                    Capsule().fill(Spectrum.ring).blur(radius: isHovering ? 16 : 11).opacity(isEnabled ? (isHovering ? 0.75 : 0.45) : 0)
                        .padding(.horizontal, 10).padding(.vertical, 4).offset(y: 5)
                    Capsule().fill(palette.buttonFill)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isBusy)
        .keyboardShortcut(.defaultAction)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovering)
    }
}

/// A small round glass button (Back).
struct GlassCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(isHovering ? 0.18 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Scales down slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Rows in one rounded group, like the Mac's settings, separated by inset dividers.
struct WelcomeGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        VStack(spacing: 0) { content() }
            .background(palette.group, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.groupStroke))
            .shadow(color: .black.opacity(palette.dark ? 0 : 0.04), radius: 10, y: 4)
    }
}

/// A row's icon: a symbol on a colored tile, an emoji, or an image.
struct RowIcon: View {
    var symbol: String?
    var tint: Color = .accentColor
    var emoji: String?
    var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().interpolation(.high).scaledToFit().frame(width: 28, height: 28)
            } else if let emoji {
                Text(emoji).font(.system(size: 21))
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// One row: icon, title and detail, and a switch. Clicking anywhere on the row flips the switch.
struct ToggleRow<Icon: View>: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var isLocked = false
    var showsDivider = true
    /// What a locked row says instead of a switch.
    var lockedText = "Done"
    var lockedSymbol = "checkmark.circle.fill"
    @ViewBuilder var icon: () -> Icon
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(palette.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if isLocked {
                    // Already true on this Mac: say so instead of showing a switch that can't move.
                    Label(lockedText, systemImage: lockedSymbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .labelStyle(.titleAndIcon)
                } else {
                    NeraSwitch(isOn: $isOn).accessibilityLabel(title)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 54)
            .background(isHovering && !isLocked ? palette.hover : .clear)
            .contentShape(Rectangle())
            .onTapGesture { if !isLocked { isOn.toggle() } }
            .onHover { isHovering = $0 }
            if showsDivider { Rectangle().fill(palette.divider).frame(height: 1).padding(.leading, 56) }
        }
    }
}

/// Fades, lifts and un-blurs a view in after `delay`, for staggered entrances.
struct Reveal: ViewModifier {
    let delay: Double
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 12)
            .blur(radius: isShown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.86).delay(reduceMotion ? 0 : delay)) { isShown = true }
            }
    }
}

extension View {
    /// Staggered entrance: the `index`th element of a step appears a little after the one before.
    func reveal(_ index: Int) -> some View { modifier(Reveal(delay: 0.05 + Double(index) * 0.055)) }
}

/// Nera's icon.
struct NeraAppIcon: View {
    var body: some View {
        #if os(macOS)
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage).resizable().interpolation(.high).scaledToFit()
        #else
            Image(systemName: "sparkles").resizable().scaledToFit()
        #endif
    }
}

#if os(macOS)
    extension Image {
        /// An installed app's icon, by bundle ID.
        @MainActor static func app(_ bundleID: String) -> Image? { MacIntegration.appIcon(bundleID: bundleID).map(Image.init(nsImage:)) }
    }
#endif

/// Nera's switch: a capsule that fills with the spectrum when on, with a springy knob.
struct NeraSwitch: View {
    @Binding var isOn: Bool
    var isLocked = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(
                    isOn
                        ? AnyShapeStyle(
                            LinearGradient(colors: [Spectrum.cyan, Spectrum.violet], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(palette.ink.opacity(0.13))
                )
                .saturation(isLocked ? 0.25 : 1)
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                .padding(2)
        }
        .frame(width: 38, height: 22)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { if !isLocked { isOn.toggle() } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A row of pills; the picked one sits on a sliding glass lozenge.
struct PillPicker<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(isOn ? palette.ink : palette.secondary)
                        .padding(.horizontal, 16).frame(height: 28)
                        .background {
                            if isOn {
                                Capsule().fill(palette.dark ? Color.white.opacity(0.16) : .white)
                                    .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(palette.ink.opacity(0.07), in: Capsule())
    }
}

/// A slim slider with a spectrum fill.
struct NeraSlider: View {
    @Binding var value: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        GeometryReader { geo in
            let w = geo.size.width
            let x = value * (w - 20)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.ink.opacity(0.1)).frame(height: 6)
                Capsule().fill(
                    LinearGradient(colors: [Spectrum.cyan, Spectrum.violet, Spectrum.pink], startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: x + 10, height: 6)
                Circle().fill(.white).shadow(color: .black.opacity(0.22), radius: 2, y: 1).frame(width: 20, height: 20).offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in value = min(max((g.location.x - 10) / max(w - 20, 1), 0), 1) })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}
