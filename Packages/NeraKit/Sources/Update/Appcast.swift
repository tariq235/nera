// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// A release channel. Each channel also receives every release of the more stable channels.
public enum UpdateChannel: String, Codable, CaseIterable, Sendable, Comparable {
    /// Every few weeks, after a beta period.
    case stable
    /// Weekly.
    case beta
    /// Every `main` commit.
    case nightly

    /// Channels whose releases this channel accepts.
    public var accepts: Set<UpdateChannel> { Set(Self.allCases.filter { $0 <= self }) }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    /// `stable < beta < nightly`.
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

/// One release in an appcast feed. The feed format is Sparkle 2's, so the feed can later be served to Sparkle's
/// installer unchanged (ADR-0011).
public struct AppcastItem: Equatable, Sendable {
    /// Build number (`sparkle:version`); updates compare by this.
    public var build: Int
    /// User-facing version (`sparkle:shortVersionString`).
    public var displayVersion: String
    /// Channel (`sparkle:channel`); no channel means stable.
    public var channel: UpdateChannel
    /// The DMG or ZIP to download.
    public var url: URL
    /// Its exact size in bytes.
    public var length: Int
    /// Base64 Ed25519 signature of the file (`sparkle:edSignature`).
    public var edSignature: String
    /// Oldest macOS that can run it.
    public var minimumSystemVersion: OperatingSystemVersion?
    /// Publication date (start of the staged rollout).
    public var publishedAt: Date?
    /// Seconds between rollout groups (`sparkle:phasedRolloutInterval`); nil = everyone at once.
    public var rolloutInterval: TimeInterval?
    /// Security fix: skips the staged rollout (`sparkle:criticalUpdate`).
    public var isCritical: Bool

    /// Creates an item.
    public init(
        build: Int, displayVersion: String, channel: UpdateChannel = .stable, url: URL, length: Int, edSignature: String,
        minimumSystemVersion: OperatingSystemVersion? = nil, publishedAt: Date? = nil, rolloutInterval: TimeInterval? = nil,
        isCritical: Bool = false
    ) {
        self.build = build
        self.displayVersion = displayVersion
        self.channel = channel
        self.url = url
        self.length = length
        self.edSignature = edSignature
        self.minimumSystemVersion = minimumSystemVersion
        self.publishedAt = publishedAt
        self.rolloutInterval = rolloutInterval
        self.isCritical = isCritical
    }

    /// Equality ignores nothing; `OperatingSystemVersion` isn't Equatable, so compare its parts.
    public static func == (a: Self, b: Self) -> Bool {
        func parts(_ v: OperatingSystemVersion?) -> [Int]? { v.map { [$0.majorVersion, $0.minorVersion, $0.patchVersion] } }
        return a.build == b.build && a.displayVersion == b.displayVersion && a.channel == b.channel && a.url == b.url
            && a.length == b.length && a.edSignature == b.edSignature && parts(a.minimumSystemVersion) == parts(b.minimumSystemVersion)
            && a.publishedAt == b.publishedAt && a.rolloutInterval == b.rolloutInterval && a.isCritical == b.isCritical
    }
}

/// Why a feed or an update was rejected.
public enum UpdateError: Error, Equatable, Sendable {
    /// The feed isn't valid appcast XML.
    case malformedFeed
    /// The download isn't the advertised size.
    case wrongLength
    /// The Ed25519 signature doesn't match the file and the public key built into the app.
    case badSignature
    /// The app has no update public key or feed configured.
    case notConfigured
}

/// Parses Sparkle-format appcast feeds. Items missing a build number, an HTTPS enclosure, a length or a signature
/// are dropped: an unsigned update is never offered.
public enum Appcast {
    /// The items in `data`, in feed order.
    public static func parse(_ data: Data) throws -> [AppcastItem] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false  // no XXE
        parser.delegate = delegate
        guard parser.parse(), delegate.sawChannel else { throw UpdateError.malformedFeed }
        return delegate.items
    }

    static func osVersion(_ string: String) -> OperatingSystemVersion? {
        let parts = string.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let p = parts.compactMap(\.self) + [0, 0]
        return OperatingSystemVersion(majorVersion: p[0], minorVersion: p[1], patchVersion: p[2])
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var items: [AppcastItem] = []
        var sawChannel = false
        private var fields: [String: String] = [:]
        private var enclosure: [String: String] = [:]
        private var critical = false
        private var inItem = false
        private var text = ""

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]
        ) {
            text = ""
            switch name {
            case "channel": sawChannel = true
            case "item":
                inItem = true
                fields = [:]
                enclosure = [:]
                critical = false
            case "enclosure" where inItem: enclosure = attributes
            case "sparkle:criticalUpdate" where inItem: critical = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard inItem else { return }
            if name == "item" {
                inItem = false
                if let item = makeItem() { items.append(item) }
            } else {
                fields[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        private func makeItem() -> AppcastItem? {
            let build = (fields["sparkle:version"] ?? enclosure["sparkle:version"]).flatMap { Int($0) }
            guard let build, let raw = enclosure["url"], let url = URL(string: raw), url.scheme == "https",
                let length = enclosure["length"].flatMap({ Int($0) }), length > 0,
                let signature = enclosure["sparkle:edSignature"], !signature.isEmpty
            else { return nil }
            let channel: UpdateChannel?
            if let name = fields["sparkle:channel"] { channel = UpdateChannel(rawValue: name) } else { channel = .stable }
            guard let channel else { return nil }  // an unknown channel is never offered
            return AppcastItem(
                build: build,
                displayVersion: fields["sparkle:shortVersionString"] ?? enclosure["sparkle:shortVersionString"] ?? String(build),
                channel: channel, url: url, length: length, edSignature: signature,
                minimumSystemVersion: fields["sparkle:minimumSystemVersion"].flatMap(Appcast.osVersion),
                publishedAt: fields["pubDate"].flatMap(Self.rfc822),
                rolloutInterval: fields["sparkle:phasedRolloutInterval"].flatMap { TimeInterval($0) },
                isCritical: critical)
        }

        private static func rfc822(_ s: String) -> Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z"] {
                f.dateFormat = format
                if let d = f.date(from: s) { return d }
            }
            return nil
        }
    }
}
