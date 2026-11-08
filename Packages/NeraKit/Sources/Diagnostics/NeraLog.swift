// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import os

/// Nera's logging (PRV-007, SEC-070). Rules, enforced by `scripts/ci/check-log-redaction.py`:
/// - log only through these loggers (no `print`/`NSLog` in shipped code);
/// - dynamic values stay private (Swift's `Logger` default), and the only values ever marked public are
///   ``Redact`` outputs, which carry no URLs, titles, cookies, tokens or passwords.
public enum NeraLog {
    /// A logger for one area of the app.
    public static func logger(_ category: String) -> Logger { Logger(subsystem: "dev.nera.browser", category: category) }
}

/// Safe, non-identifying descriptions of sensitive values, for the rare log line that needs some detail.
public enum Redact {
    /// Only the scheme of a URL (`https`), never host, path or query.
    public static func url(_ url: URL?) -> String { url?.scheme.map { "<\($0) url>" } ?? "<no url>" }

    /// An error's domain and code, without its message (messages can contain paths, URLs or user names).
    public static func error(_ error: any Error) -> String {
        let e = error as NSError
        return "\(e.domain)#\(e.code)"
    }
}
