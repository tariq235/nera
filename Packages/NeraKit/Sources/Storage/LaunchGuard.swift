// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Crash-loop detection at launch (SEC-054). A launch "fails" if the app ends (crash, hang killed, force-quit)
/// before it has run stably for a few seconds. After ``threshold`` failed launches in a row, the next launch
/// starts in safe mode: no page is reopened automatically and the fallback engine is used.
public struct LaunchGuard: Sendable {
    /// Failed launches in a row that trigger safe mode.
    public static let threshold = 2

    /// Where the launch record lives.
    public let fileURL: URL

    private struct Record: Codable {
        var launching: Bool
        var failedLaunches: Int
    }

    /// Creates a guard for a record file.
    public init(fileURL: URL) { self.fileURL = fileURL }

    /// `Application Support/<bundle id>/launch.json`.
    public static func standard(bundleID: String = Bundle.main.bundleIdentifier ?? "dev.nera.browser") -> LaunchGuard {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: bundleID)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return LaunchGuard(fileURL: base.appending(path: "launch.json"))
    }

    /// Call first thing at launch. Returns `true` when this launch should start in safe mode.
    public func beginLaunch() -> Bool {
        var record = read() ?? Record(launching: false, failedLaunches: 0)
        if record.launching { record.failedLaunches += 1 }  // the previous launch never completed
        record.launching = true
        write(record)
        return record.failedLaunches >= Self.threshold
    }

    /// Call once the app has run stably, or quits cleanly: the launch succeeded.
    public func launchSucceeded() { write(Record(launching: false, failedLaunches: 0)) }

    /// Failed launches in a row so far.
    public var failedLaunches: Int { read()?.failedLaunches ?? 0 }

    private func read() -> Record? { (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Record.self, from: $0) } }
    private func write(_ record: Record) { try? JSONEncoder().encode(record).write(to: fileURL, options: .atomic) }
}
