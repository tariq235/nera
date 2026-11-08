// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import ImageIO
import SecurityPolicy

/// Finds and fetches a page's icon for the WebKit engine (Chromium downloads icons itself).
///
/// - Icon links are read by a script in Nera's isolated content world (page scripts can't see or change it).
/// - Only `http`/`https` icon URLs are fetched, with no cookies, no cache, a 5 s timeout and a 512 KB cap.
/// - Images are decoded by ImageIO into a ≤ 64 px PNG; SVG icons are skipped.
enum FaviconLoader {
    /// Icon links as `[href, rel, sizes, type]`, in document order.
    static let script = """
        Array.from(document.querySelectorAll('link[rel]'))
          .filter(l => /(^|\\s)(icon|apple-touch-icon)(\\s|$)/i.test(l.rel))
          .map(l => [l.href, l.rel, l.getAttribute('sizes') || '', l.type || ''])
        """

    /// Candidate icon URLs, best first: raster `icon` links (closest to 32–64 px), touch icons, then `/favicon.ico`.
    static func candidates(links: [[String]], pageURL: URL) -> [URL] {
        func size(_ sizes: String) -> Int {
            sizes.lowercased().split(separator: " ").compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max() ?? 0
        }
        func score(_ link: [String]) -> Int {
            let rel = link[1].lowercased()
            let sizes = link[2]
            let type = link[3].lowercased()
            var s = rel.contains("apple-touch-icon") ? 50 : 100
            let px = size(sizes)
            if px > 0 { s -= abs(px - 48) / 4 }
            if type.contains("png") { s += 5 }
            return s
        }
        let raster = links.filter { link in
            link.count == 4 && !link[3].lowercased().contains("svg") && !link[0].lowercased().hasSuffix(".svg")
        }
        var urls = raster.sorted { score($0) > score($1) }.compactMap { URL(string: $0[0]) }.filter(isWeb)
        if let scheme = pageURL.scheme, let host = pageURL.host(), var root = URLComponents(string: "\(scheme)://\(host)") {
            root.port = pageURL.port
            root.path = "/favicon.ico"
            if let fallback = root.url, !urls.contains(fallback) { urls.append(fallback) }
        }
        return Array(urls.filter(isWeb).prefix(3))
    }

    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host() != nil
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }()

    static let maxBytes = 512 * 1024

    /// The first candidate that downloads and decodes, as a ≤ 64 px PNG.
    static func load(_ candidates: [URL]) async -> Data? {
        for url in candidates {
            guard let (bytes, response) = try? await session.bytes(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= maxBytes
            else { continue }
            var data = Data()
            do {
                for try await byte in bytes {
                    data.append(byte)
                    if data.count > maxBytes { break }
                }
            } catch { continue }
            if data.count <= maxBytes, let png = normalize(data) { return png }
        }
        return nil
    }

    /// Decodes any ImageIO format (PNG, ICO, JPEG, GIF, WebP…) into a PNG at most 64 px on its long side.
    static func normalize(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width > 0 else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
