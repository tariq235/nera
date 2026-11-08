// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Reads another app's accessibility tree the way VoiceOver does (A11Y-009). Needs Accessibility permission for the
// terminal that runs it. Usage:
//   ax-tool read <pid> <text>...   exit 0 when every text is reachable (value, title or description), within 25 s
//   ax-tool press <pid> <title>    presses the first button with that title or description
//   ax-tool flag <pid> <attribute> sets an assistive-app attribute (AXManualAccessibility) on the app
import ApplicationServices
import Foundation

let args = CommandLine.arguments
guard args.count >= 4, let pid = pid_t(args[2]) else {
    print("usage: ax-tool read|press|flag <pid> <text>...")
    exit(2)
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 3)

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

/// Every element, breadth first (bounded).
func elements() -> [AXUIElement] {
    var out: [AXUIElement] = []
    var queue: [(AXUIElement, Int)] = [(app, 0)]
    var next = 0  // a cursor, not removeFirst(): linear in the tree's size
    while next < queue.count, out.count < 20_000 {
        let (element, depth) = queue[next]
        next += 1
        out.append(element)
        if depth < 60 { queue += children(element).map { ($0, depth + 1) } }
    }
    return out
}

func texts(_ element: AXUIElement) -> [String] {
    [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].compactMap { string(element, $0) }
}

switch args[1] {
case "read":
    let wanted = Array(args.dropFirst(3))
    var found: [String: String] = [:]
    let deadline = Date().addingTimeInterval(25)
    repeat {
        for element in elements() {
            for text in texts(element) { for w in wanted where found[w] == nil && text.contains(w) { found[w] = string(element, kAXRoleAttribute) } }
        }
        if found.count < wanted.count { Thread.sleep(forTimeInterval: 1) }
    } while found.count < wanted.count && Date() < deadline
    for w in wanted { print("  \(found[w] == nil ? "✘" : "✔") \(w)\(found[w].map { " (\($0))" } ?? "")") }
    exit(found.count == wanted.count ? 0 : 1)
case "press":
    let title = args[3]
    let button = elements().first { ["AXButton", "AXLink"].contains(string($0, kAXRoleAttribute) ?? "") && texts($0).contains(title) }
    guard let button, AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else { exit(1) }
case "flag":
    exit(AXUIElementSetAttributeValue(app, args[3] as CFString, kCFBooleanTrue) == .success ? 0 : 1)
default:
    exit(2)
}
