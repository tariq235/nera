// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// A saved login read from another browser. The password is a secret: it's only ever written to the export file
/// the user hands to Apple Passwords, and that file is deleted afterwards.
public struct ImportedLogin: Sendable, Hashable {
    /// The site's address.
    public var url: URL
    /// User name or email.
    public var username: String
    /// Password.
    public var password: String

    /// Creates a login.
    public init(url: URL, username: String, password: String) {
        self.url = url
        self.username = username
        self.password = password
    }
}

/// Reads saved logins from a Chromium-family browser (its "Login Data" database, encrypted with the same
/// Keychain key as its cookies), and writes them in the CSV format Apple Passwords imports.
public enum ChromiumPasswords {
    #if os(macOS)
        /// Reads the browser's saved logins, asking macOS for its key (the user sees a Keychain prompt).
        public static func read(from source: ImportSource) throws -> [ImportedLogin] {
            guard let item = ChromiumCookies.keychainItem(for: source), let profile = source.dataDirectory else {
                throw SignInImportError.noCookies
            }
            let database = profile.appending(path: "Login Data")
            guard FileManager.default.fileExists(atPath: database.path) else { throw SignInImportError.noCookies }
            let password = try ChromiumCookies.keychainPassword(service: item.service, account: item.account)
            return try read(database: database, key: ChromiumCookies.derivedKey(password: password))
        }
    #endif

    /// Reads every saved login (not the sites the user said "never save" for) from a Login Data database.
    public static func read(database: URL, key: Data) throws -> [ImportedLogin] {
        let rows = try SQLiteSnapshot(of: database).rows(
            "SELECT origin_url, username_value, password_value, blacklisted_by_user FROM logins"
        ) { row -> ImportedLogin? in
            guard row.int(3) == 0, let raw = row.text(0), let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""),
                let blob = row.blob(2), let password = ChromiumCookies.decrypt(blob, key: key, hasDomainHash: false), !password.isEmpty
            else { return nil }
            return ImportedLogin(url: url, username: row.text(1) ?? "", password: password)
        }
        var seen = Set<String>()
        return rows.filter { seen.insert("\($0.url.host() ?? "")|\($0.username)|\($0.password)").inserted }
    }

    /// The logins as a CSV file in Chrome's export format (name, url, username, password, note), which Apple
    /// Passwords imports.
    public static func csv(_ logins: [ImportedLogin]) -> String {
        func field(_ value: String) -> String {
            let needsQuotes = value.contains { ",\"\n\r".contains($0) } || value.hasPrefix(" ") || value.hasSuffix(" ")
            return needsQuotes ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
        }
        var lines = ["name,url,username,password,note"]
        for login in logins {
            let name = login.url.host() ?? login.url.absoluteString
            lines.append([name, login.url.absoluteString, login.username, login.password, ""].map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
