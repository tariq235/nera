// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import SecurityPolicy
public import SwiftUI

/// ⌘T / ⌘L. Type a URL or search, or jump to an already-open tab.
public struct CommandBarView: View {
    let host: any CommandBarHost

    /// Creates the command bar for a host (normally the app model).
    public init(host: any CommandBarHost) { self.host = host }
    @State private var text = ""
    @State private var highlighted = 0
    /// The text the bar opened with (⌘L shows the current address): not announced, VoiceOver reads the field itself.
    @State private var openedWith: String?
    @FocusState private var isFocused: Bool

    struct Suggestion: Identifiable, Equatable {
        enum Kind: Equatable {
            case open(URL)
            case search(URL)
            case switchTo(UUID)
            case history(URL)
        }
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let kind: Kind
    }

    private var suggestions: [Suggestion] {
        var out: [Suggestion] = []
        let engine = host.state.settings.searchEngine
        let query = text.trimmingCharacters(in: .whitespaces)
        let open = host.state.spaces.flatMap { host.state.orderedTabs(in: $0) } + (host.state.currentProfile?.favorites ?? [])
        let isNewTab = host.commandBarDisposition == .newTab
        let tabs = OpenTabSearch.matches(query, in: open).filter { $0.tab.id != host.state.selectedTabID || isNewTab }
        func switchRow(_ tab: BrowserCore.Tab) -> Suggestion {
            .init(
                id: tab.id.uuidString, title: tab.displayTitle, subtitle: "Switch to Tab · \(DisplayURL.short(tab.url))",
                symbol: "arrow.right.square", kind: .switchTo(tab.id))
        }
        // A new tab (⌘T) for a site that's already open: going to that tab comes first (Return), not a duplicate.
        // Editing the current address (⌘L) always navigates first.
        let strong = host.commandBarDisposition == .newTab ? tabs.first(where: \.isStrong) : nil
        if let strong { out.append(switchRow(strong.tab)) }
        switch Omnibox.parse(text, engine: engine) {
        case .url(let url)?:
            out.append(.init(id: "open", title: url.absoluteString, subtitle: "Open", symbol: "globe", kind: .open(url)))
        case .search(let q, let url)?:
            out.append(.init(id: "search", title: q, subtitle: "Search \(engine.name)", symbol: "magnifyingglass", kind: .search(url)))
        case nil:
            break
        }
        for match in tabs where match.tab.id != strong?.tab.id && out.count < 8 { out.append(switchRow(match.tab)) }
        if !query.isEmpty {
            let shown = Set(open.compactMap(\.url))
            for entry in host.historySuggestions(for: query.lowercased()) where out.count < 8 && !shown.contains(entry.url) {
                out.append(
                    .init(
                        id: "history:" + entry.url.absoluteString, title: entry.title.isEmpty ? DisplayURL.short(entry.url) : entry.title,
                        subtitle: "\(entry.isBookmark ? "Bookmark" : "History") · \(DisplayURL.short(entry.url))",
                        symbol: entry.isBookmark ? "star" : "clock.arrow.circlepath", kind: .history(entry.url)))
            }
        }
        return out
    }

    /// The command bar overlay.
    public var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(host.commandBarDisposition == .newTab ? "Search or enter URL…" : "Edit URL or search…", text: $text)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .accessibilityLabel("Address and search")
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.webSearch)
                        #endif
                        .onSubmit(commit)
                        .accessibilityIdentifier("commandBar.field")
                }
                .padding(16)
                if !suggestions.isEmpty {
                    Divider()
                    VStack(spacing: 2) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                            HStack(spacing: 10) {
                                Image(systemName: s.symbol).frame(width: 18)
                                Text(s.title).lineLimit(1)
                                Spacer()
                                Text(s.subtitle).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                index == highlighted ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { run(s) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(SuggestionSpeech.label(s))
                            .accessibilityAddTraits(index == highlighted ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { run(s) }
                            .accessibilityIdentifier("commandBar.suggestion")
                        }
                    }
                    .padding(8)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Suggestions")
                }
            }
            .frame(maxWidth: 640)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding(.top, 90)
            .padding(.horizontal, 16)
        }
        .defaultFocus($isFocused, true)
        .onAppear {
            text = host.commandBarDisposition == .currentTab ? host.currentURLString : ""
            openedWith = text
        }
        .task {
            // Focus must be requested after the overlay is in the window, or macOS ignores it.
            await Task.yield()
            isFocused = true
        }
        .onChange(of: text) { highlighted = 0 }
        .task(id: text) {
            // Once typing pauses, VoiceOver hears the new list (A11Y-005).
            guard text != openedWith, (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
            announce(SuggestionSpeech.list(suggestions))
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(suggestions.count - 1, 0))
            announce(SuggestionSpeech.highlighted(suggestions, at: highlighted))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            announce(SuggestionSpeech.highlighted(suggestions, at: highlighted))
            return .handled
        }
    }

    private func commit() {
        let list = suggestions
        guard !list.isEmpty else { return dismiss() }
        run(list[min(highlighted, list.count - 1)])
    }

    private func run(_ s: Suggestion) {
        switch s.kind {
        case .open, .search:
            host.submitCommandBar(text)
        case .switchTo(let id):
            host.switchToTab(id)
        case .history(let url):
            host.submitCommandBar(url.absoluteString)
        }
    }

    private func dismiss() { host.dismissCommandBar() }

    /// Tells VoiceOver (a no-op when it's off).
    private func announce(_ text: String?) {
        guard let text else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
