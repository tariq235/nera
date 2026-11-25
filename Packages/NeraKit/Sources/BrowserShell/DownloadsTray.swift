// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import DesignSystem
import EngineKit
import PageLifecycle
import SwiftUI

#if os(macOS)
    import AppKit
    import QuickLookThumbnailing
#endif

/// The button at the left of the sidebar's bottom bar, as in Arc: opens the downloads shelf, and rings with
/// progress while files download.
struct DownloadsButton: View {
    @Bindable var model: AppModel
    @State private var isHovering = false

    private var active: [DownloadItem] { model.pages.downloads.filter(\.isActive) }

    /// Combined progress of the running downloads whose size is known.
    private var progress: Double? {
        let fractions = active.compactMap(\.fractionCompleted)
        return fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count)
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { model.isDownloadsTrayPresented.toggle() }
        } label: {
            ZStack {
                if !active.isEmpty {
                    Circle().stroke(.primary.opacity(0.15), lineWidth: 2).frame(width: 20, height: 20)
                    Circle()
                        .trim(from: 0, to: progress ?? 0.25)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 20, height: 20)
                }
                Image(systemName: "archivebox").font(.system(size: 14, weight: .medium))
                if model.hasUnseenFinishedDownload {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).offset(x: 9, y: -8)
                }
            }
            .foregroundStyle(.primary.opacity(model.isDownloadsTrayPresented ? 0.9 : 0.6))
            .frame(width: 32, height: 28)
            .contentShape(Rectangle())
            .surface(model.isDownloadsTrayPresented ? .selected : (isHovering ? .hover : nil), cornerRadius: 7)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Downloads (⌥⌘L)")
        .accessibilityLabel(active.isEmpty ? "Downloads" : "Downloads, \(active.count) in progress")
        .accessibilityIdentifier("downloads.button")
        // A new download opens the shelf once, so you see it start.
        .onChange(of: model.pages.downloads.last?.id) { _, newest in
            guard newest != nil, model.pages.downloads.last?.isActive == true else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { model.isDownloadsTrayPresented = true }
        }
    }
}

/// Arc's downloads shelf, above the bottom bar: the latest files in the Downloads folder and the ones downloading
/// now, newest at the bottom (next to the button). Click a file to open it; drag it anywhere.
struct DownloadsTray: View {
    @Bindable var model: AppModel
    @State private var files: [DownloadedFile] = []

    var body: some View {
        VStack(spacing: 2) {
            if files.isEmpty && active.isEmpty {
                Text("No downloads").font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            ForEach(files) { file in FileRow(model: model, file: file, clearAll: clearAll) }
            ForEach(active) { item in ActiveRow(model: model, item: item) }
        }
        .padding(.vertical, 4)
        .onAppear {
            model.hasUnseenFinishedDownload = false
            refresh()
        }
        .onChange(of: model.pages.downloads.map(\.isActive)) { refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Downloads")
        .accessibilityIdentifier("downloads.tray")
    }

    private var active: [DownloadItem] { model.pages.downloads.filter { $0.isActive || $0.canRetry } }

    private func refresh() {
        let cleared = UserDefaults.standard.object(forKey: DownloadedFile.clearedKey) as? Date ?? .distantPast
        files = DownloadedFile.recent(in: model.downloadsDirectory, after: cleared)
    }

    /// Hides everything listed now (the files stay in the Downloads folder).
    private func clearAll() {
        UserDefaults.standard.set(Date(), forKey: DownloadedFile.clearedKey)
        model.pages.clearInactiveDownloads()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { refresh() }
    }
}

/// A file in the Downloads folder, for the shelf.
struct DownloadedFile: Identifiable, Equatable {
    let url: URL
    let added: Date
    var id: URL { url }

    /// When the shelf was last cleared (files added before then aren't listed).
    static let clearedKey = "downloadsShelfClearedAt"
    /// How many files the shelf lists.
    static let limit = 5

    /// The newest files in `directory` (by when they arrived there), oldest first. Hidden files and downloads
    /// still in progress are left out.
    static func recent(in directory: URL?, after cleared: Date, limit: Int = Self.limit) -> [DownloadedFile] {
        guard let directory else { return [] }
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .isHiddenKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]))
            ?? []
        let partial: Set<String> = ["crdownload", "download", "part", "partial"]
        let files = urls.compactMap { url -> DownloadedFile? in
            guard !partial.contains(url.pathExtension.lowercased()),
                let values = try? url.resourceValues(forKeys: Set(keys)), values.isHidden != true,
                let added = values.addedToDirectoryDate ?? values.contentModificationDate, added > cleared
            else { return nil }
            return DownloadedFile(url: url, added: added)
        }
        return Array(files.sorted { $0.added > $1.added }.prefix(limit).reversed())
    }
}

/// "5 minutes ago", "1 week ago".
enum DownloadText {
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return now.timeIntervalSince(date) < 60 ? "Just now" : formatter.localizedString(for: date, relativeTo: now)
    }

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

/// One file on the shelf: its preview, name and when it arrived.
private struct FileRow: View {
    let model: AppModel
    let file: DownloadedFile
    let clearAll: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            #if os(macOS)
                NSWorkspace.shared.open(file.url)  // the user's click; Gatekeeper checks quarantined files
            #endif
        } label: {
            HStack(spacing: 12) {
                FileThumbnail(url: file.url).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.url.lastPathComponent).font(.system(size: 14)).lineLimit(1).truncationMode(.tail)
                    Text(DownloadText.ago(file.added)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .contentShape(Rectangle())
            .surface(isHovering ? .hover : nil)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .draggable(file.url)
        .contextMenu {
            Button("Open") {
                #if os(macOS)
                    NSWorkspace.shared.open(file.url)
                #endif
            }
            Button("Show in Finder") {
                #if os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                #endif
            }
            Divider()
            Button("Clear All", action: clearAll).accessibilityIdentifier("downloads.clear")
        }
        .accessibilityLabel("\(file.url.lastPathComponent), \(DownloadText.ago(file.added))")
        .accessibilityHint("Opens the file")
        .accessibilityAction(named: "Show in Finder") {
            #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            #endif
        }
        .accessibilityIdentifier("downloads.file")
    }
}

/// A download in progress (or one that failed): its name, progress and Cancel or Retry.
private struct ActiveRow: View {
    let model: AppModel
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.canRetry ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                .font(.system(size: 22)).foregroundStyle(item.canRetry ? Color.orange : .secondary).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename).font(.system(size: 14)).lineLimit(1).truncationMode(.middle)
                if item.isActive {
                    ProgressView(value: item.fractionCompleted ?? 0).controlSize(.small)
                }
                Text(DownloadText.status(item)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if item.isActive { model.pages.cancelDownload(item.id) } else { model.pages.retryDownload(item.id) }
            } label: {
                Image(systemName: item.isActive ? "xmark.circle.fill" : "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(item.isActive ? "Cancel" : "Retry")
            .accessibilityLabel(item.isActive ? "Cancel \(item.filename)" : "Retry \(item.filename)")
            .accessibilityIdentifier(item.isActive ? "downloads.cancel" : "downloads.retry")
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloads.row")
    }
}

/// A file's Finder preview (a photo, a page of a document, the app's icon for the rest).
private struct FileThumbnail: View {
    let url: URL
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                #if os(macOS)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                #else
                    Image(systemName: "doc")
                #endif
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            #if os(macOS)
                let request = QLThumbnailGenerator.Request(
                    fileAt: url, size: CGSize(width: 40, height: 40), scale: 2, representationTypes: .thumbnail)
                if let thumb = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    image = Image(nsImage: thumb.nsImage)
                }
            #endif
        }
    }
}
