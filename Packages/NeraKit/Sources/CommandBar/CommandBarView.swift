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
    @Environment(\.colorScheme) private var colorScheme
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
        /// The page's address, for its icon (nil: the symbol is shown).
        var url: URL?
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
                symbol: "arrow.right.square", kind: .switchTo(tab.id), url: tab.url)
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
        if query.isEmpty, let space = host.state.selectedSpace {
            // Nothing typed yet: the Space's open tabs, one keystroke away.
            for tab in host.state.orderedTabs(in: space) where out.count < 5 && (tab.id != host.state.selectedTabID || isNewTab) {
                out.append(switchRow(tab))
            }
        }
        if !query.isEmpty {
            let shown = Set(open.compactMap(\.url))
            for entry in host.historySuggestions(for: query.lowercased()) where out.count < 8 && !shown.contains(entry.url) {
                out.append(
                    .init(
                        id: "history:" + entry.url.absoluteString, title: entry.title.isEmpty ? DisplayURL.short(entry.url) : entry.title,
                        subtitle: "\(entry.isBookmark ? "Bookmark" : "History") · \(DisplayURL.short(entry.url))",
                        symbol: entry.isBookmark ? "star" : "clock.arrow.circlepath", kind: .history(entry.url), url: entry.url))
            }
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

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(host.commandBarDisposition == .newTab ? "Search or enter URL…" : "Edit URL or search…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
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
            .padding(.horizontal, 20)
            .frame(height: 56)
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
        .background(colorScheme == .dark ? Color(white: 0.12) : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.22), radius: 40, y: 18)
        #if os(macOS)
            // Esc, or a click anywhere outside the panel (the page, the sidebar), closes it; the click still goes
            // through, so clicking a tab in the sidebar opens it.
            .background(OutsideClickMonitor(dismiss: dismiss))
        #endif
    }

    /// One suggestion: the site's icon, its title (and address), and "Switch to Tab" for open tabs.
    private func row(_ s: Suggestion, isHighlighted: Bool) -> some View {
        let accent = Theme.accent(for: host.commandBarTheme)
        let isSwitch = if case .switchTo = s.kind { true } else { false }
        return HStack(spacing: 10) {
            if let url = s.url {
                SiteIcon(url: url, size: 14, png: host.commandBarIcon(for: url))
            } else {
                Image(systemName: s.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 4) {
                Text(s.title).fontWeight(.medium).lineLimit(1)
                if !isSwitch, let detail = s.subtitle.split(separator: "·").last.map({ $0.trimmingCharacters(in: .whitespaces) }),
                    s.url != nil
                {
                    Text("— \(detail)").foregroundStyle(isHighlighted ? Color.white.opacity(0.75) : Color.secondary).lineLimit(1)
                }
            }
            .font(.system(size: 13.5))
            Spacer(minLength: 12)
            if isSwitch {
                Text("Switch to Tab").font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isHighlighted ? accent : Color.secondary)
                    .background(
                        isHighlighted ? Color.white : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                    .accessibilityHidden(true)
            } else if s.url == nil {
                Text(s.subtitle).font(.system(size: 12.5)).foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(isHighlighted ? accent : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
