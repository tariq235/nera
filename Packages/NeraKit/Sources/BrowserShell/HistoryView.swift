// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import SecurityPolicy
import Storage
import SwiftUI

/// ⌘Y: search and browse the current profile's history, reopen recently closed tabs, clear history.
struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var entries: [HistoryEntry] = []
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("History").font(.title2.weight(.semibold))
                Spacer()
                Menu("Clear History…") {
                    Button("Last Hour") { clear(since: Date().addingTimeInterval(-3600)) }
                    Button("Today") { clear(since: Calendar.current.startOfDay(for: Date())) }
                    Divider()
                    Button("All History…") { isConfirmingClear = true }
                }
                .fixedSize()
                .accessibilityIdentifier("history.clear")
                Button("Done") { model.isHistoryPresented = false }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            TextField("Search history", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("history.search")
            List {
                if query.isEmpty, !recentlyClosed.isEmpty {
                    Section("Recently Closed") {
                        ForEach(recentlyClosed) { archived in
                            row(
                                title: archived.tab.displayTitle, url: archived.tab.url, date: archived.archivedAt,
                                symbol: "arrow.uturn.backward")
                        }
                    }
                }
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            row(
                                title: entry.title.isEmpty ? DisplayURL.short(entry.url) : entry.title, url: entry.url,
                                date: entry.lastVisit, symbol: "globe"
                            )
                            .contextMenu {
                                Button("Open in New Tab") { model.openFromHistory(entry.url) }
                                Button("Copy Link") { Clipboard.copy(entry.url.absoluteString) }
                                Divider()
                                Button("Remove from History", role: .destructive) { model.deleteFromHistory(entry.url) }
                            }
                        }
                    }
                }
                if entries.isEmpty {
                    Text(query.isEmpty ? "Pages you visit appear here." : "No matches.").foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("history.list")
        }
        .frame(minWidth: 560, minHeight: 520)
        .task(id: "\(query)|\(model.historyRevision)") { reload() }
        .confirmationDialog("Clear all history for this profile?", isPresented: $isConfirmingClear) {
            Button("Clear All History", role: .destructive) { clear(since: nil) }
        } message: {
            Text("Open tabs, Spaces and downloads aren't affected.")
        }
    }

    private var recentlyClosed: [ArchivedTab] { Array(model.state.recentlyClosed.prefix(8)) }

    private func row(title: String, url: URL?, date: Date, symbol: String) -> some View {
        Button {
            if let url { model.openFromHistory(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).lineLimit(1)
                    Text(DisplayURL.short(url)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history.row")
    }

    /// Entries grouped by day: Today, Yesterday, then dates.
    private var groups: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.lastVisit) }
        return byDay.keys.sorted(by: >).map { day in
            let title =
                calendar.isDateInToday(day)
                ? "Today" : calendar.isDateInYesterday(day) ? "Yesterday" : day.formatted(date: .complete, time: .omitted)
            return (title, byDay[day, default: []].sorted { $0.lastVisit > $1.lastVisit })
        }
    }

    private func reload() {
        guard let history = model.history, let profile = model.state.currentProfile else {
            entries = []
            return
        }
        entries =
            query.isEmpty ? history.recent(profileID: profile.id, limit: 500) : history.search(query, profileID: profile.id, limit: 200)
    }

    private func clear(since: Date?) { model.clearHistory(since: since) }
}
