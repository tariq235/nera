// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineTestSupport
import Foundation
import TestSupport
import Testing

@testable import BrowserCore

/// Omnibox fuzzing (SEC-067): any input is either blank, a URL, or a search on the configured engine.
@Suite("Omnibox fuzz")
struct OmniboxFuzzTests {
    @Test func randomInputNeverEscapesTheSearchEngine() {
        let engine = SearchEngine.duckDuckGo
        for seed in UInt64(0)..<3000 * SeededRandom.scale {
            var rng = SeededRandom(seed: seed)
            let input = rng.fuzzString()
            switch Omnibox.parse(input, engine: engine) {
            case nil:
                #expect(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "seed \(seed): non-blank input ignored")
            case .search(_, let url):
                #expect(url.host() == "duckduckgo.com", "seed \(seed): search went to \(url)")
                #expect(url.path() == "/", "seed \(seed): query leaked into the path: \(url)")
            case .url(let url):
                #expect(url.scheme != nil, "seed \(seed): URL without a scheme")
            }
        }
    }
}

/// Large libraries (PERF-009): 50 Spaces × 10 tabs, switching and saving stay fast and consistent.
@Suite("Stress")
struct StressTests {
    @Test func fiveHundredTabsAcrossFiftySpaces() throws {
        let env = TestEnv()
        var state = BrowserState.initial(uuid: env.nextUUID)
        let clock = ContinuousClock()
        let build = clock.measure {
            for s in 0..<50 {
                if s > 0 { _ = Reducer.reduce(&state, .space(.create(title: "Space \(s)")), env.reducer) }
                for t in 0..<10 {
                    _ = Reducer.reduce(&state, .tab(.open(URL(string: "https://s\(s)t\(t).example")!, .newTab)), env.reducer)
                }
            }
        }
        #expect(state.spaces.count == 50)
        #expect(state.spaces.reduce(0) { $0 + $1.allTabs.count } == 500)

        var rng = SeededRandom(seed: 42)
        let ids = state.spaces.flatMap(\.allTabs).map(\.id)
        let switching = clock.measure {
            for _ in 0..<5000 {
                if Bool.random(using: &rng) {
                    _ = Reducer.reduce(&state, .tab(.select(ids.randomElement(using: &rng)!)), env.reducer)
                } else {
                    _ = Reducer.reduce(&state, .space(.selectAdjacent(offset: Int.random(in: -2...2, using: &rng))), env.reducer)
                }
            }
        }
        #expect(state.spaces.reduce(0) { $0 + $1.allTabs.count } == 500, "switching never loses tabs")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var decoded: BrowserState?
        let roundTrip = try clock.measure { decoded = try decoder.decode(BrowserState.self, from: encoder.encode(state)) }
        #expect(decoded == state)

        // Generous budgets (debug build, shared CI machine): they catch accidental O(n²) blow-ups, not jitter.
        #expect(build < .seconds(2), "building 500 tabs took \(build)")
        #expect(switching < .seconds(3), "5000 switches took \(switching)")
        #expect(roundTrip < .seconds(1), "saving + loading 500 tabs took \(roundTrip)")
    }

    @Test func randomActionSequencesKeepTheLibraryConsistent() {
        for seed in UInt64(0)..<50 * SeededRandom.scale {
            let env = TestEnv()
            var rng = SeededRandom(seed: seed)
            var state = BrowserState.initial(uuid: env.nextUUID)
            for step in 0..<400 {
                let tabs = state.spaces.flatMap(\.allTabs).map(\.id)
                let action: Action =
                    switch Int.random(in: 0..<9, using: &rng) {
                    case 0, 1: .tab(.open(URL(string: "https://r\(step).example")!, Bool.random(using: &rng) ? .newTab : .currentTab))
                    case 2: tabs.randomElement(using: &rng).map { .tab(.close($0)) } ?? .tab(.restoreLastClosed)
                    case 3: tabs.randomElement(using: &rng).map { .tab(.togglePin($0)) } ?? .tab(.clearSelection)
                    case 4: tabs.randomElement(using: &rng).map { .tab(.select($0)) } ?? .tab(.clearSelection)
                    case 5: .tab(.restoreLastClosed)
                    case 6: .space(.create(title: "S\(step)"))
                    case 7: state.spaces.randomElement(using: &rng).map { .space(.delete($0.id)) } ?? .space(.clearToday)
                    default: .space(.selectAdjacent(offset: Int.random(in: -1...1, using: &rng)))
                    }
                _ = Reducer.reduce(&state, action, env.reducer)
                if let selected = state.selectedTabID {
                    #expect(state.tab(withID: selected) != nil, "seed \(seed) step \(step): selection points at a missing tab")
                }
                let all = state.spaces.flatMap(\.allTabs).map(\.id)
                #expect(Set(all).count == all.count, "seed \(seed) step \(step): a tab appears twice")
            }
        }
    }
}

extension Space {
    fileprivate var allTabs: [Tab] { (pinned + today).flatMap(\.tabs) }
}
