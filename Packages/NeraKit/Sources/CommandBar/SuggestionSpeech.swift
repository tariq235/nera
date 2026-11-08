// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// What VoiceOver says for the command bar's suggestions (A11Y-005): each row reads as one element ("Netflix,
/// Switch to Tab · netflix.com"), moving the highlight with the arrow keys announces the row and its position,
/// and a new list is announced once typing pauses.
enum SuggestionSpeech {
    /// One row.
    static func label(_ suggestion: CommandBarView.Suggestion) -> String { "\(suggestion.title), \(suggestion.subtitle)" }

    /// The highlighted row and where it is ("…, 2 of 5").
    static func highlighted(_ suggestions: [CommandBarView.Suggestion], at index: Int) -> String? {
        guard suggestions.indices.contains(index) else { return nil }
        return "\(label(suggestions[index])), \(index + 1) of \(suggestions.count)"
    }

    /// A new list: how many, and the first (what Return opens).
    static func list(_ suggestions: [CommandBarView.Suggestion]) -> String? {
        guard let first = suggestions.first else { return nil }
        let count = suggestions.count == 1 ? "1 suggestion" : "\(suggestions.count) suggestions"
        return "\(count). \(label(first))"
    }
}
