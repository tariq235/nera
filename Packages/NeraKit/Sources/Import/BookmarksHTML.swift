// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import BrowserData
public import Foundation

/// The "Netscape bookmark file" every browser imports and exports (`bookmarks.html`).
public enum BookmarksHTML {
    /// Parses a bookmarks HTML file. Tolerant: unknown tags are ignored, and only web links are kept.
    public static func parse(_ html: String, uuid: () -> UUID = { UUID() }) throws -> [Bookmark] {
        guard html.range(of: "<DL", options: .caseInsensitive) != nil else { throw BrowserImportError.unrecognizedFile }
        // A stack of open folders; index 0 is the root.
        var stack: [[Bookmark]] = [[]]
        var titles: [String] = []
        var pendingFolder: String?
        var count = 0
        var scanner = Substring(html)
        while let open = scanner.firstIndex(of: "<"), count < BrowserImport.limit {
            guard let close = scanner[open...].firstIndex(of: ">") else { break }
            let tag = scanner[scanner.index(after: open)..<close]
            let name = tag.prefix { !$0.isWhitespace && $0 != ">" }.lowercased()
            scanner = scanner[scanner.index(after: close)...]
            switch name {
            case "h3":
                let end = scanner.firstIndex(of: "<") ?? scanner.endIndex
                pendingFolder = decode(String(scanner[..<end]))
            case "dl":
                guard stack.count < 64 else { break }
                stack.append([])
                titles.append(pendingFolder ?? "")
                pendingFolder = nil
            case "/dl":
                guard stack.count > 1, let children = stack.popLast() else { break }
                let title = titles.popLast() ?? ""
                if stack.count == 1, title.isEmpty {
                    stack[0].append(contentsOf: children)  // the file's outer list
                } else {
                    stack[stack.count - 1].append(.folder(id: uuid(), title: title, children: children))
                }
            case "a":
                // The title ends at the next tag (normally </A>; some files leave links unclosed).
                let end = scanner.firstIndex(of: "<") ?? scanner.endIndex
                if let url = BrowserImport.webURL(attribute("href", in: tag)) {
                    let title = decode(String(scanner[..<end]))
                    stack[stack.count - 1].append(.link(id: uuid(), title: title.isEmpty ? (url.host() ?? "") : title, url: url))
                    count += 1
                }
            default:
                break
            }
        }
        while stack.count > 1, let children = stack.popLast() {  // unclosed lists
            stack[stack.count - 1].append(.folder(id: uuid(), title: titles.popLast() ?? "", children: children))
        }
        return stack[0]
    }

    /// Writes bookmarks as a bookmarks HTML file that Chrome, Safari, Firefox and others can import.
    public static func export(_ bookmarks: [Bookmark]) -> String {
        var out = """
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <!-- This is an automatically generated file. It will be read and overwritten. DO NOT EDIT! -->
            <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
            <TITLE>Bookmarks</TITLE>
            <H1>Bookmarks</H1>
            <DL><p>

            """
        func write(_ items: [Bookmark], indent: String) {
            for item in items {
                let added = item.addedAt.map { " ADD_DATE=\"\(Int($0.timeIntervalSince1970))\"" } ?? ""
                if item.isFolder {
                    out += "\(indent)<DT><H3\(added)>\(escape(item.title))</H3>\n\(indent)<DL><p>\n"
                    write(item.children ?? [], indent: indent + "    ")
                    out += "\(indent)</DL><p>\n"
                } else if let url = item.url {
                    out += "\(indent)<DT><A HREF=\"\(escape(url.absoluteString))\"\(added)>\(escape(item.title))</A>\n"
                }
            }
        }
        write(bookmarks, indent: "    ")
        return out + "</DL><p>\n"
    }

    static func attribute(_ name: String, in tag: Substring) -> String? {
        guard let range = tag.range(of: name + "=", options: .caseInsensitive) else { return nil }
        var rest = tag[range.upperBound...]
        guard let quote = rest.first, quote == "\"" || quote == "'" else {
            return decode(String(rest.prefix { !$0.isWhitespace }))
        }
        rest = rest.dropFirst()
        return decode(String(rest.prefix { $0 != quote }))
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func decode(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
        out = out.replacingOccurrences(of: "&amp;", with: "&")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
