// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import Diagnostics

/// PRV-007: the only values ever logged publicly carry no URLs, titles, tokens or paths.
@Suite("Log redaction")
struct RedactTests {
    @Test func urlsKeepOnlyTheirScheme() {
        let url = URL(string: "https://bank.example/account?token=SECRET#x")!
        #expect(Redact.url(url) == "<https url>")
        #expect(!Redact.url(url).contains("bank") && !Redact.url(url).contains("SECRET"))
        #expect(Redact.url(nil) == "<no url>")
    }

    @Test func errorsKeepOnlyDomainAndCode() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSFilePathErrorKey: "/Users/alice/Secret.pdf"])
        #expect(Redact.error(error) == "NSCocoaErrorDomain#4")
    }
}
