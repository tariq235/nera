// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import BrowserData
import DesignSystem
import Import
import SecurityPolicy
import SwiftUI
import UniformTypeIdentifiers

/// ⌥⌘B: the current profile's bookmarks — search, folders, open, rename, move, delete, import, export.
struct BookmarksView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var renaming: Bookmark?
    @State private var newTitle = ""
    @State private var isExporting = false

    private var tree: [Bookmark] { model.state.currentProfile?.bookmarkTree ?? [] }

    private var matches: [Bookmark] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return tree.allLinks.filter { link in
            let haystack = (link.title + " " + (link.url?.absoluteString ?? "")).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// Every folder with its path, for "Move to".
    private var folders: [(id: UUID, path: String)] {
        func walk(_ items: [Bookmark], _ prefix: String) -> [(UUID, String)] {
            items.filter(\.isFolder).flatMap { [($0.id, prefix + $0.title)] + walk($0.children ?? [], prefix + $0.title + " › ") }
        }
        return walk(tree, "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Bookmarks").font(.title2.weight(.semibold))
                Spacer()
                Button("New Folder") { model.bookmarks(.addFolder(title: "New Folder", folderID: nil)) }
                #if os(macOS)
                    Button("Import…") {
                        model.isBookmarksPresented = false
                        model.isBrowserImportPresented = true
                    }
                    Button("Export…") { isExporting = true }.disabled(tree.isEmpty)
                #endif
                Button("Done") { model.isBookmarksPresented = false }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            TextField("Search bookmarks", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("bookmarks.search")
            List {
                if tree.isEmpty {
                    Text("No bookmarks yet. Press ⇧⌘D to bookmark a page, or import from another browser.").foregroundStyle(.secondary)
                } else if query.isEmpty {
                    OutlineGroup(tree, children: \.children) { row($0) }
                } else {
                    ForEach(matches) { row($0) }
                }
            }
            .accessibilityIdentifier("bookmarks.list")
        }
        .frame(minWidth: 560, minHeight: 520)
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Rename") { if let b = renaming { model.bookmarks(.rename(b.id, title: newTitle)) } }
            Button("Cancel", role: .cancel) {}
        }
        .fileExporter(
            isPresented: $isExporting, document: BookmarksFile(html: BookmarksHTML.export(tree)), contentType: .html,
            defaultFilename: "Nera Bookmarks.html"
        ) { _ in }
    }

    private func row(_ b: Bookmark) -> some View {
        HStack(spacing: 8) {
            Image(systemName: b.isFolder ? "folder" : "globe").foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.title).lineLimit(1)
                if let url = b.url { Text(DisplayURL.short(url)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(b) }
        .contextMenu {
            if b.url != nil { Button("Open in New Tab") { open(b) } }
            if let url = b.url { Button("Copy Link") { Clipboard.copy(url.absoluteString) } }
            Button("Rename…") {
                newTitle = b.title
                renaming = b
            }
            Menu("Move To") {
                Button("Top Level") { model.bookmarks(.move(b.id, toFolder: nil)) }
                ForEach(folders.filter { $0.id != b.id }, id: \.id) { folder in
                    Button(folder.path) { model.bookmarks(.move(b.id, toFolder: folder.id)) }
                }
            }
            Divider()
            Button(b.isFolder ? "Delete Folder" : "Delete", role: .destructive) { model.bookmarks(.delete(b.id)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bookmarks.row")
    }

    private func open(_ b: Bookmark) {
        guard let url = b.url else { return }
        model.isBookmarksPresented = false
        model.send(.tab(.open(url, .newTab)))
    }
}

/// The exported HTML as a file document.
struct BookmarksFile: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }
    let html: String
    init(html: String) { self.html = html }
    init(configuration: ReadConfiguration) throws { html = "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(html.utf8)) }
}

#if os(macOS)
    /// File → Import from Browser…: bookmarks and history from Chrome, Arc, Brave, Edge, Safari, Firefox or a file.
    struct BrowserImportView: View {  // naming: import-reference
        @Bindable var model: AppModel
        @State private var source: ImportSource = ImportSource.allCases.first { $0.isInstalled && $0 != .bookmarksFile } ?? .bookmarksFile
        @State private var includeBookmarks = true
        @State private var includeHistory = true
        @State private var isPicking = false

        /// Safari's files are protected by macOS privacy: the user picks them (Bookmarks.plist, History.db).
        private var needsFiles: Bool { source == .safari || source == .bookmarksFile }

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Import from Browser").font(.title2.weight(.semibold))
                Picker("From", selection: $source) {
                    ForEach(ImportSource.allCases.filter(\.isInstalled)) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("import.source")
                Toggle("Bookmarks", isOn: $includeBookmarks)
                Toggle("History", isOn: $includeHistory).disabled(source == .bookmarksFile)
                Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.isBrowserImportPresented = false }.keyboardShortcut(.cancelAction)
                    Button(needsFiles ? "Choose Files…" : "Import") {
                        if needsFiles { isPicking = true } else { run(files: []) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!includeBookmarks && !includeHistory)
                    .accessibilityIdentifier("import.run")
                }
            }
            .padding(20)
            .frame(width: 440)
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { run(files: urls) }
            }
        }

        private var explanation: String {
            switch source {
            case .safari:
                "Choose Bookmarks.plist and History.db in your Library › Safari folder. macOS protects them, so Nera can only read the files you pick."
            case .bookmarksFile: "Choose a bookmarks HTML file exported from any browser."
            default:
                "Quit \(source.displayName) first for the most recent history. Bookmarks go into a folder named “Imported from \(source.displayName)”; nothing is removed from \(source.displayName)."
            }
        }

        private func run(files: [URL]) {
            let accessed = files.filter { $0.startAccessingSecurityScopedResource() }
            defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
            model.importFromBrowser(source, bookmarks: includeBookmarks, history: includeHistory && source != .bookmarksFile, files: files)
        }
    }
#endif
