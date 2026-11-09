// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import Foundation
import SwiftUI

/// The bottom of the sidebar, about updates: "Nera 0.1.3 is ready, click to restart" when a verified update is
/// staged; "Nera updated!" with what's new once after updating; "available" for builds that can't update
/// themselves. Animated sparkles, unless Reduce Motion is on.
struct UpdateCard: View {
    @Bindable var model: AppModel
    @AppStorage("NeraLastSeenVersion") private var lastSeenVersion = ""
    @State private var dismissedReady = false

    var body: some View {
        Group {
            if case .ready(let version) = model.updateStatus, !dismissedReady {
                ready(version)
            } else if let update = model.availableUpdate {
                available(update.version)
            } else if justUpdated {
                updated
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: model.updateStatus)
        .onAppear {
            if lastSeenVersion.isEmpty { lastSeenVersion = model.appVersion }  // a first install isn't an update
        }
    }

    /// This version is newer than the one seen last: show "updated" once.
    private var justUpdated: Bool { !lastSeenVersion.isEmpty && lastSeenVersion != model.appVersion }

    private func ready(_ version: String) -> some View {
        Button {
            #if os(macOS)
                model.restartToUpdate()
            #endif
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nera \(version) is ready").font(.system(size: 13.5, weight: .bold))
                    Text("Click to restart").font(.system(size: 12)).opacity(0.75)
                }
                Spacer(minLength: 4)
                UpdateGlyph()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .contextMenu {
            Button("Later (Installs When You Quit)") { dismissedReady = true }
            automaticToggle
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nera \(version) is ready. Restart to update.")
        .accessibilityIdentifier("update.ready")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var updated: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nera updated!").font(.system(size: 14, weight: .bold)).padding(.bottom, 2)
            link("What's new", symbol: "sparkles", url: "https://github.com/tariq235/nera/releases/tag/v\(model.appVersion)")
            link("Sponsor Nera", symbol: "heart", url: "https://github.com/sponsors/tariq235")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .overlay(alignment: .topTrailing) { CloseButton { lastSeenVersion = model.appVersion } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("update.done")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func available(_ version: String) -> some View {
        Button {
            model.downloadUpdate()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nera \(version) is available").font(.system(size: 13.5, weight: .bold))
                    Text("Click to download").font(.system(size: 12)).opacity(0.75)
                }
                Spacer(minLength: 4)
                UpdateGlyph()
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .overlay(alignment: .topTrailing) { CloseButton { model.availableUpdate = nil } }
        .accessibilityIdentifier("update.banner")
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func link(_ title: String, symbol: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) { model.send(.tab(.open(url, .newTab))) }
            lastSeenVersion = model.appVersion
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("\(title) →").font(.system(size: 13, weight: .medium))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var automaticToggle: some View {
        Toggle("Download Updates Automatically", isOn: Binding(get: { model.checksForUpdates }, set: { model.checksForUpdates = $0 }))
    }
}

/// The card: a translucent white panel on the sidebar, sparkles drifting over it.
private struct CardStyle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.16))
                    if !reduceMotion { Sparkles().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

extension View {
    fileprivate func cardStyle() -> some View { modifier(CardStyle()) }
}

/// A download arrow in a soft circle that breathes gently.
private struct UpdateGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 17, weight: .bold))
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.22), in: Circle())
            .scaleEffect(breathing ? 1.06 : 0.96)
            .offset(y: breathing ? 1.5 : -1.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
            }
            .accessibilityHidden(true)
    }
}

/// Small sparkles that twinkle at random places.
private struct Sparkles: View {
    private struct Point {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var phase: Double
    }

    private let points: [Point] = (0..<9).map { i in
        let x = CGFloat((i * 37) % 100) / 100
        let y = CGFloat((i * 61) % 100) / 100
        return Point(x: x, y: y, size: CGFloat(2 + (i % 3)), phase: Double(i) * 0.7)
    }

    /// One sparkle at time `t`: it twinkles and drifts up a little.
    private func sparkle(_ p: Point, at t: Double, in size: CGSize) -> some View {
        let glow: Double = 0.15 + 0.55 * max(0, sin(t * 1.3 + p.phase))
        let drift = CGFloat((t * 6 + p.phase * 10).truncatingRemainder(dividingBy: 12))
        return Image(systemName: "sparkle")
            .font(.system(size: p.size * 2.4))
            .opacity(glow)
            .position(x: p.x * size.width, y: p.y * size.height - drift)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ForEach(points.indices, id: \.self) { i in sparkle(points[i], at: t, in: geo.size) }
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(0.6)
        .padding(6)
        .accessibilityLabel("Close")
    }
}
