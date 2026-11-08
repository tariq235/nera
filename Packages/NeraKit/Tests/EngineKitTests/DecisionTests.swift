// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import EngineKit

@MainActor
@Suite("Decision (default-deny)")
struct DecisionTests {
    @Test func firstAnswerWinsAndLaterOnesAreIgnored() {
        var answers: [PermissionDecision] = []
        let d = Decision<PermissionDecision>(fallback: .deny) { answers.append($0) }
        #expect(d.resolve(.grant))
        #expect(!d.resolve(.deny))
        #expect(answers == [.grant])
        #expect(d.isResolved)
        #expect(d.answer == .grant)
    }

    @Test func releasingAnUnansweredDecisionAppliesTheFallback() {
        var answers: [PermissionDecision] = []
        do {
            _ = Decision<PermissionDecision>(fallback: .deny) { answers.append($0) }
        }
        #expect(answers == [.deny])
    }

    @Test func releasingAnAnsweredDecisionDoesNothingMore() {
        var answers: [DownloadDecision] = []
        do {
            let d = Decision<DownloadDecision>(fallback: .cancel) { answers.append($0) }
            d.resolve(.saveTo(URL(fileURLWithPath: "/tmp/x")))
        }
        #expect(answers == [.saveTo(URL(fileURLWithPath: "/tmp/x"))])
    }

    @Test func droppedRequestInsideAQueueFallsBackWhenTheQueueIsCleared() {
        var answer: DialogResponse?
        var queue: [PageRequest] = [
            .dialog(
                DialogRequest(
                    origin: .opaque, kind: .confirm(message: "?"),
                    decision: Decision(fallback: .cancel) { answer = $0 }))
        ]
        #expect(answer == nil)
        queue.removeAll()
        #expect(answer == .cancel)
    }

    @Test func pageStateDefaultsAreAnIdleEmptyPage() {
        let s = PageState()
        #expect(s.url == nil && s.title.isEmpty && !s.isLoading && s.zoom == 1 && s.camera == .none)
    }
}
