// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SwiftUI

// The welcome screen's light and illustrations.

/// The canvas: soft ribbons of Nera's spectrum drifting along the bottom of the window, with grain. The light
/// grows a little with every step, and its colors lean toward the step's mood.
struct AuroraCanvas: View {
    let progress: Double
    let mood: [Color]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = WelcomePalette(scheme: scheme)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.canvas))
                let strength = (palette.dark ? 0.5 : 0.38) + 0.32 * progress
                var light = context
                light.addFilter(.blur(radius: min(size.width, size.height) * 0.13))
                for (i, color) in mood.enumerated() {
                    let phase = Double(i) * 1.7
                    let w = size.width * (0.46 + 0.1 * sin(t * 0.05 + phase))
                    let h = size.height * (0.36 + 0.06 * cos(t * 0.07 + phase))
                    let x = size.width * (0.1 + 0.27 * Double(i) + 0.06 * sin(t * 0.06 + phase)) - w / 2
                    let y = size.height * (0.86 + 0.05 * cos(t * 0.045 + phase * 1.4)) - h / 2
                    light.opacity = strength * (0.78 + 0.22 * sin(t * 0.11 + phase))
                    light.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
                }
                // A faint glow at the top, so the window never feels flat.
                light.opacity = palette.dark ? 0.14 : 0.2
                let glow = CGRect(x: size.width * 0.25, y: -size.height * 0.38, width: size.width * 0.5, height: size.height * 0.55)
                light.fill(Path(ellipseIn: glow), with: .color(mood.last ?? Spectrum.violet))
            }
        }
        .overlay(Grain(opacity: palette.dark ? 0.22 : 0.3))
        .animation(.easeInOut(duration: 1.2), value: progress)
    }

    /// The colors each step leans toward.
    static func mood(for step: OnboardingFlow.Step, theme: SpaceTheme) -> [Color] {
        switch step {
        case .intro: [Spectrum.cyan, Spectrum.violet, Spectrum.pink, Spectrum.mint]
        case .essentials: [Spectrum.peach, Spectrum.pink, Spectrum.violet, Spectrum.peach]
        case .privacy: [Spectrum.cyan, Spectrum.mint, Spectrum.cyan, Spectrum.violet]
        case .source, .spaces, .extensions, .favorites: [Spectrum.violet, Spectrum.cyan, Spectrum.pink, Spectrum.cyan]
        case .summary: [Spectrum.mint, Spectrum.cyan, Spectrum.peach, Spectrum.pink]
        case .theme: SpaceBackground.colors(theme, dark: false) + [Spectrum.violet]
        }
    }
}

/// Nera's icon in a slowly turning halo of its own spectrum.
struct NeraHalo: View {
    var size: CGFloat
    var burst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(Spectrum.ring).frame(width: size * 1.05, height: size * 1.05)
                    .rotationEffect(.radians(t * 0.35)).blur(radius: size * 0.2).opacity(0.85 + 0.15 * sin(t * 1.3))
                ForEach(0..<2, id: \.self) { i in
                    let p = (t / 3.6 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
                    Circle().strokeBorder(Spectrum.ring, lineWidth: 1.2).opacity(burst ? 0.55 * (1 - p) : 0)
                        .frame(width: size * (1 + 0.55 * p), height: size * (1 + 0.55 * p))
                }
                NeraAppIcon().frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.22), radius: size * 0.14, y: size * 0.07)
                    .offset(y: reduceMotion ? 0 : sin(t * 1.1) * size * 0.025)
            }
        }
        .frame(width: size * 1.6, height: size * 1.6)
    }
}

/// A Mac Dock with real apps; Nera drops in (and bounces) when it's kept there, with a "Default browser" tag
/// when it will open links.
struct DockScene: View {
    let height: CGFloat
    let isInDock: Bool
    let isDefault: Bool
    let neighbors: [Image]
    @State private var bounce = 0.0

    var body: some View {
        let icon = height * 0.4
        VStack(spacing: height * 0.07) {
            Label("Default browser", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor.gradient))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .opacity(isDefault ? 1 : 0)
                .scaleEffect(isDefault ? 1 : 0.6, anchor: .bottom)
            HStack(alignment: .bottom, spacing: icon * 0.18) {
                ForEach(Array(neighbors.enumerated()), id: \.offset) { _, image in
                    image.resizable().interpolation(.high).scaledToFit().frame(width: icon, height: icon)
                }
                if isInDock {
                    VStack(spacing: 4) {
                        NeraAppIcon().frame(width: icon * 1.1, height: icon * 1.1).offset(y: -bounce)
                        Circle().fill(.primary.opacity(0.55)).frame(width: 4, height: 4)
                    }
                    .transition(.scale(scale: 0.3, anchor: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, icon * 0.26)
            .padding(.top, icon * 0.2)
            .padding(.bottom, icon * 0.08)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: icon * 0.42, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: icon * 0.42, style: .continuous).strokeBorder(.white.opacity(0.45)))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        }
        .frame(height: height, alignment: .bottom)
        .animation(.spring(response: 0.5, dampingFraction: 0.68), value: isInDock)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDefault)
        .onChange(of: isInDock) { _, on in if on { hop() } }
        .onAppear { if isInDock { hop() } }
    }

    private func hop() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            for lift in [height * 0.15, 0, height * 0.06, 0] {
                withAnimation(.spring(response: 0.26, dampingFraction: lift == 0 ? 0.55 : 0.8)) { bounce = lift }
                try? await Task.sleep(for: .milliseconds(240))
            }
        }
    }
}

/// Trackers drifting toward a shield and dissolving against it (or slipping through when blocking is off).
struct ShieldScene: View {
    let size: CGFloat
    let isBlocking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let symbols = ["eye.fill", "chart.bar.fill", "dot.radiowaves.left.and.right", "location.fill", "megaphone.fill"]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<10, id: \.self) { tracker($0, t) }
                Circle().fill(Spectrum.ring).frame(width: size * 0.62, height: size * 0.62).blur(radius: size * 0.12)
                    .opacity(isBlocking ? 0.6 : 0.12)
                Circle().fill(.regularMaterial).frame(width: size * 0.5, height: size * 0.5)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6)))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                Image(systemName: isBlocking ? "hand.raised.fill" : "hand.raised.slash")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(isBlocking ? AnyShapeStyle(Spectrum.ring) : AnyShapeStyle(Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size * 2.2, height: size)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isBlocking)
        }
    }

    private func tracker(_ i: Int, _ t: Double) -> some View {
        let angle = Double(i) * 2.399 + 0.4
        let p = (t / 5.5 + Double(i) * 0.137).truncatingRemainder(dividingBy: 1)
        let far = size * 0.62
        let stop = isBlocking ? size * 0.3 : size * 0.04
        let radius = far - (far - stop) * min(1, p / 0.78)
        let fade = p < 0.78 ? min(1, p * 5) : max(0, 1 - (p - 0.78) * 4.5)
        return Image(systemName: Self.symbols[i % Self.symbols.count])
            .font(.system(size: size * 0.065, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size * 0.15, height: size * 0.15)
            .background(Circle().fill(Color(white: 0.55).opacity(0.75)))
            .scaleEffect(isBlocking && p > 0.78 ? 1 + (p - 0.78) * 2.2 : 1)
            .blur(radius: isBlocking && p > 0.78 ? (p - 0.78) * 14 : 0)
            .opacity(fade)
            .offset(x: cos(angle) * radius * 2.2, y: sin(angle) * radius)
    }
}

/// The browser being imported from, sending light along a beam into Nera.
struct ImportBeam: View {
    let height: CGFloat
    let source: Image?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let icon = height * 0.46
        HStack(spacing: 0) {
            ZStack {
                if let source {
                    source.resizable().interpolation(.high).scaledToFit().frame(width: icon, height: icon)
                        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: icon * 0.22, style: .continuous)
                        .strokeBorder(.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        .frame(width: icon * 0.86, height: icon * 0.86)
                        .transition(.opacity)
                }
            }
            .frame(width: icon, height: icon)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let mid = size.height / 2
                    for i in 0..<10 {
                        let p = (t * 0.5 + Double(i) / 10).truncatingRemainder(dividingBy: 1)
                        let x = size.width * p
                        let r = 2 + 1.8 * sin(.pi * p)
                        context.opacity = source == nil ? 0.12 : sin(.pi * p)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: mid - r, width: r * 2, height: r * 2)),
                            with: .color(Spectrum.all[i % Spectrum.all.count]))
                    }
                }
            }
            .frame(width: height * 1.05, height: 20)
            NeraHalo(size: icon * 1.1)
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: source == nil)
    }
}
