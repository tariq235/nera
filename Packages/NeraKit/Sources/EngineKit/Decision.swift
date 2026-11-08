// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// A one-shot answer to a ``PageRequest``.
///
/// - The first ``resolve(_:)`` wins; later calls are ignored and return `false`.
/// - **If the decision is released without an answer, it resolves to its `fallback`**, which is
///   always the safe choice (deny, cancel, discard). A page that is closed, a tab that is discarded
///   or a UI that forgets a prompt can therefore never grant anything by accident (AP-4, SR-040).
///   Released on the main thread (always the case in Nera), the fallback applies immediately;
///   released elsewhere, it applies on the main actor right after.
@MainActor
public final class Decision<Answer: Sendable> {
    /// The answer applied if nobody resolves the decision.
    public let fallback: Answer
    /// The answer given, once resolved by ``resolve(_:)``.
    public private(set) var answer: Answer?
    private let box: ResolverBox<Answer>

    /// Creates a decision.
    /// - Parameters:
    ///   - fallback: The safe answer used if the decision is never resolved.
    ///   - resolver: Called exactly once, on the main actor, with the final answer.
    public init(fallback: Answer, _ resolver: @escaping @MainActor (Answer) -> Void) {
        self.fallback = fallback
        self.box = ResolverBox(resolver)
    }

    /// Whether an answer has been given.
    public var isResolved: Bool { box.isEmpty }

    /// Answers the request. Returns `false` (and does nothing) if it was already answered.
    @discardableResult
    public func resolve(_ answer: Answer) -> Bool {
        guard let resolver = box.take() else { return false }
        self.answer = answer
        resolver(answer)
        return true
    }

    // A plain (nonisolated) deinit: Swift 6.3.3's optimizer crashes on `isolated deinit` in generic
    // classes in -O builds, so the main-actor hop lives in ResolverBox instead.
    deinit {
        box.applyFallback(fallback)
    }
}

/// Holds the resolver so it can be taken exactly once and run on the main actor, including from
/// `Decision`'s nonisolated deinit.
final class ResolverBox<Answer: Sendable>: @unchecked Sendable {
    // @unchecked: `resolver` is only read or written on the main actor (every accessor below is
    // @MainActor or hops to it).
    private var resolver: (@MainActor (Answer) -> Void)?

    init(_ resolver: @escaping @MainActor (Answer) -> Void) { self.resolver = resolver }

    @MainActor var isEmpty: Bool { resolver == nil }

    @MainActor func take() -> (@MainActor (Answer) -> Void)? {
        defer { resolver = nil }
        return resolver
    }

    func applyFallback(_ fallback: Answer) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { take()?(fallback) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.take()?(fallback) } }
        }
    }
}
