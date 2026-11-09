// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
public import SwiftUI

/// ⌘T / ⌘L. Type a URL or search, or jump to an already-open tab.
public struct CommandBarView: View {
    let host: any CommandBarHost
    /// The width on the window's left that isn't page (the sidebar): the bar is centered over the page.
    let leadingInset: CGFloat

    /// Creates the command bar for a host (normally the app model), centered over the page beside `leadingInset`.
    public init(host: any CommandBarHost, leadingInset: CGFloat = 0) {
        self.host = host
        self.leadingInset = leadingInset
    }
    @Environment(\.colorScheme) var colorScheme
    @State var text = ""
    @State private var highlighted = 0
    /// The text the bar opened with (⌘L shows the current address): not announced, VoiceOver reads the field itself.
    @State private var openedWith: String?
    /// The last edit removed text: no inline completion until the next character is typed.
    @State var lastEditWasDeletion = false
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
        /// The page's address, for its icon (nil: the symbol is shown).
        var url: URL?
    }

    /// Ranked like Arc's: the completed site, the search, this Space's tabs, history, then other Spaces' tabs.
    private var suggestions: [Suggestion] {
        var out: [Suggestion] = []
        let engine = host.state.settings.searchEngine
        let query = text.trimmingCharacters(in: .whitespaces)
        let isNewTab = host.commandBarDisposition == .newTab
        let selected = host.state.selectedTabID
        let space = host.state.selectedSpace
        let here = space.map { host.state.orderedTabs(in: $0) } ?? []
        let elsewhere = host.state.spaces.filter { $0.id != space?.id }.flatMap { s in host.state.orderedTabs(in: s).map { (s, $0) } }
        func switchRow(_ tab: BrowserCore.Tab, in other: Space? = nil) -> Suggestion {
            .init(
                id: tab.id.uuidString, title: tab.displayTitle,
                subtitle: other.map { "Switch to Tab · \($0.title)" } ?? "Switch to Tab · \(DisplayURL.short(tab.url))",
                symbol: "arrow.right.square", kind: .switchTo(tab.id), url: tab.url)
        }
        if query.isEmpty {
            // Nothing typed yet: this Space's open tabs, one keystroke away.
            for tab in here where out.count < 5 && (tab.id != selected || isNewTab) { out.append(switchRow(tab)) }
            return out
        }
        let history = host.historySuggestions(for: query.lowercased())
        var shown = Set<String>()
        if let site = completion, let url = URL(string: "https://\(site)/") {
            let title = history.first { SiteCompletion.site(of: $0.url) == site && !$0.title.isEmpty }?.title ?? site
            out.append(.init(id: "site", title: title, subtitle: site, symbol: "globe", kind: .open(url), url: url))
            shown.insert(site + "/")
        }
        switch Omnibox.parse(text, engine: engine) {
        case .url(let url)? where completion == nil:
            out.append(.init(id: "open", title: url.absoluteString, subtitle: "Open", symbol: "globe", kind: .open(url)))
        case .search(let q, let url)?:
            out.append(.init(id: "search", title: q, subtitle: "Search \(engine.name)", symbol: "magnifyingglass", kind: .search(url)))
        default:
            break
        }
        for match in OpenTabSearch.matches(query, in: here) where out.count < 8 && (match.tab.id != selected || isNewTab) {
            out.append(switchRow(match.tab))
            shown.insert(match.tab.url?.absoluteString ?? "")
        }
        for entry in history where out.count < 7 {
            let key = entry.url.absoluteString
            guard !shown.contains(key),
                !(SiteCompletion.site(of: entry.url).map { shown.contains($0 + "/") && entry.url.path.count <= 1 } ?? false)
            else { continue }
            shown.insert(key)
            out.append(
                .init(
                    id: "history:" + key, title: entry.title.isEmpty ? DisplayURL.short(entry.url) : entry.title,
                    subtitle: "\(entry.isBookmark ? "Bookmark" : "History") · \(DisplayURL.short(entry.url))",
                    symbol: entry.isBookmark ? "star" : "clock.arrow.circlepath", kind: .history(entry.url), url: entry.url))
        }
        let others = OpenTabSearch.matches(query, in: elsewhere.map(\.1))
        for match in others where out.count < 8 {
            out.append(switchRow(match.tab, in: elsewhere.first { $0.1.id == match.tab.id }?.0))
        }
        return out
    }

    /// The command bar overlay: a panel centered over the page, near its top third. Clicking elsewhere on the page
    /// closes it; the sidebar stays usable. Its place is fixed (it never moves after it appears) and it grows
    /// downward as suggestions appear.
    public var body: some View {
        GeometryReader { geo in
            let pageWidth = max(geo.size.width - leadingInset, 0)
            let width = min(max(pageWidth * 0.46, 520), 760, max(pageWidth - 32, 0))
            ZStack(alignment: .topLeading) {
                #if !os(macOS)
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: pageWidth, height: geo.size.height)
                        .offset(x: leadingInset)
                        .onTapGesture { dismiss() }
                #endif
                panel
                    .frame(width: width)
                    .offset(x: leadingInset + (pageWidth - width) / 2, y: geo.size.height * 0.3)
            }
        }
        .ignoresSafeArea()
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
        .onChange(of: text) { old, new in
            highlighted = 0
            lastEditWasDeletion = new.count < old.count
        }
        .onKeyPress(.rightArrow) { acceptCompletion() }
        .onKeyPress(.tab) { acceptCompletion() }
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

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                fieldIcon
                TextField(host.commandBarDisposition == .newTab ? "Search or Enter URL…" : "Edit URL or search…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .accessibilityLabel("Address and search")
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.webSearch)
                    #endif
                    .onSubmit(commit)
                    .accessibilityIdentifier("commandBar.field")
                    // The inline completion, in grey after what's typed (→ or Tab takes it; Return opens it).
                    .overlay(alignment: .leading) {
                        if let site = completion, site.count > text.count {
                            HStack(spacing: 0) {
                                Text(text).hidden()
                                Text(String(site.dropFirst(text.count))).foregroundStyle(.tertiary)
                            }
                            .font(.system(size: 19))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }
            }
            .padding(.horizontal, 20)
            .frame(height: 62)
            if !suggestions.isEmpty {
                Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
                VStack(spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                        row(s, isHighlighted: index == highlighted)
                            .contentShape(Rectangle())
                            .onTapGesture { run(s) }
                            .onHover { if $0 { highlighted = index } }
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
        // Frosted glass, the page faintly showing through.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                    colorScheme == .dark ? Color.black.opacity(0.25) : Color.white.opacity(0.55))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(colorScheme == .dark ? 0.14 : 0.08)))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 50, y: 22)
        #if os(macOS)
            // Esc, or a click anywhere outside the panel (the page, the sidebar), closes it; the click still goes
            // through, so clicking a tab in the sidebar opens it.
            .background(OutsideClickMonitor(dismiss: dismiss))
        #endif
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

#if os(macOS)
    import AppKit

    /// While the command bar is open: Esc closes it, and so does a mouse-down outside the panel (passed on).
    struct OutsideClickMonitor: NSViewRepresentable {
        let dismiss: () -> Void

        func makeNSView(context: Context) -> MonitorView {
            let view = MonitorView()
            view.dismiss = dismiss
            return view
        }

        func updateNSView(_ view: MonitorView, context: Context) { view.dismiss = dismiss }

        final class MonitorView: NSView {
            var dismiss: () -> Void = {}
            private var monitor: Any?

            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self, let window = self.window, event.window === window else { return event }
                    if event.type == .keyDown {
                        guard event.keyCode == 53 else { return event }  // Esc
                        self.dismiss()
                        return nil
                    }
                    let point = self.convert(event.locationInWindow, from: nil)
                    if !self.bounds.contains(point) { DispatchQueue.main.async { self.dismiss() } }
                    return event
                }
            }

            override func removeFromSuperview() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                super.removeFromSuperview()
            }
        }
    }
#endif
