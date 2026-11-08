// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import PageLifecycle
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The sidebar's Downloads button: shows overall progress while files download and opens the tray.
struct DownloadsButton: View {
    @Bindable var model: AppModel

    private var active: [DownloadItem] { model.pages.downloads.filter(\.isActive) }

    /// Combined progress of the running downloads whose size is known.
    private var progress: Double? {
        let fractions = active.compactMap(\.fractionCompleted)
        return fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count)
    }

    var body: some View {
        Group {
            if !model.pages.downloads.isEmpty { button }
        }
        // Like Chrome's download bubble: a new download opens the tray once, so the user sees it started.
        .onChange(of: model.pages.downloads.last?.id) { _, newest in
            if newest != nil, model.pages.downloads.last?.isActive == true { model.isDownloadsTrayPresented = true }
        }
    }

    private var button: some View {
        Group {
            Button {
                model.isDownloadsTrayPresented.toggle()
            } label: {
                ZStack {
                    if !active.isEmpty {
                        Circle().stroke(.primary.opacity(0.15), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: progress ?? 0.25)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: "arrow.down").font(.caption.weight(.bold))
                    if model.hasUnseenFinishedDownload {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: 8, y: -8)
                    }
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Downloads (⌥⌘L)")
            .accessibilityLabel(active.isEmpty ? "Downloads" : "Downloads, \(active.count) in progress")
            .accessibilityIdentifier("downloads.button")
            .popover(isPresented: $model.isDownloadsTrayPresented, arrowEdge: .top) {
                DownloadsTray(model: model)
            }
        }
    }
}

/// The list of this session's downloads, newest first, with Cancel, Retry and Show in Finder.
struct DownloadsTray: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") { model.pages.clearInactiveDownloads() }
                    .buttonStyle(.borderless)
                    .disabled(!model.pages.downloads.contains { !$0.isActive })
                    .accessibilityIdentifier("downloads.clear")
            }
            .padding(12)
            Divider()
            if model.pages.downloads.isEmpty {
                Text("No downloads").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.pages.downloads.reversed()) { item in
                            DownloadRow(model: model, item: item)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 340)
        .onAppear { model.hasUnseenFinishedDownload = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.tray")
    }
}

struct DownloadRow: View {
    let model: AppModel
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(iconStyle).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename).lineLimit(1).truncationMode(.middle)
                if item.isActive {
                    if let fraction = item.fractionCompleted {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                Text(DownloadText.status(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            actions
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.row")
    }

    @ViewBuilder private var actions: some View {
        if item.isActive {
            iconButton("xmark.circle.fill", label: "Cancel \(item.filename)", id: "downloads.cancel") {
                model.pages.cancelDownload(item.id)
            }
        } else if item.canRetry {
            iconButton("arrow.clockwise", label: "Retry \(item.filename)", id: "downloads.retry") { model.pages.retryDownload(item.id) }
        } else if item.fileURL != nil {
            iconButton("magnifyingglass", label: "Show \(item.filename) in Finder", id: "downloads.reveal") { model.revealDownload(item) }
        }
        iconButton("minus.circle", label: "Remove \(item.filename) from the list", id: "downloads.remove") {
            model.pages.dismissDownload(item.id)
        }
        .opacity(item.isActive ? 0 : 1)
        .disabled(item.isActive)
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }

    private var icon: String {
        switch item.state {
        case .finished?: "doc.fill"
        case .failed?: "exclamationmark.triangle.fill"
        case .cancelled?: "xmark.circle"
        default: "arrow.down.circle"
        }
    }

    private var iconStyle: Color {
        switch item.state {
        case .failed?: .orange
        case .finished?: .accentColor
        default: .secondary
        }
    }
}

/// User-facing status lines (pure; unit-tested).
enum DownloadText {
    static func status(_ item: DownloadItem) -> String {
        switch item.state {
        case nil: return "Starting…"
        case .progress(let received, let total?)?: return "\(size(received)) of \(size(total))"
        case .progress(let received, nil)?: return "\(size(received)) downloaded"
        case .finished?: return "Done · \(item.sourceURL?.host() ?? "downloaded")"
        case .failed(let why)?: return "Failed: \(why)"
        case .cancelled?: return "Cancelled"
        }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
