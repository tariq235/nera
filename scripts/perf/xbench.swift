// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Cross-browser benchmark: Nera against other Mac browsers, measured the same way from outside every app.
//
//   swift scripts/perf/xbench.swift --app nera=<Nera.app> --app ardia=<Ardia.app> --app chrome=<Google Chrome.app> \
//       [--runs 5] [--sessions 2] [--idle 30] [--settle 15] [--out <dir>]
//
// Every browser gets the same treatment (docs/perf/benchmarks.md has the method and the latest results):
// - a fresh, empty profile per run, and never the user's Keychain: Chrome gets --user-data-dir in a throwaway
//   folder and Chromium's mock keychain; Ardia its data folder there (onboarding marked done, as Ardia's own harness
//   does) and the mock keychain; Nera runs with NERA_BENCH=1 (a throwaway library and Chromium profile, the mock
//   keychain, welcome done, links open as tabs, nothing extra at launch);
// - launched with `open -n -a <app> [url]`, the clock started just before; never a bundle the user runs;
// - the same local test page (scripts/perf/bench_server.py) reporting its own first-contentful-paint, so no browser
//   needs a debugging port (Nera forbids it in release builds, SR-020);
// - windows found through CGWindowList; CPU time, wakeups and memory read with proc_pid_rusage for every process of
//   the app (its bundle's executables and their children);
// - browsers interleaved run by run (rotated each round); medians reported.
//
// Rows: launch → window on screen; launch → page painted; idle CPU and wakeups at 1 and 20 tabs; memory at 1 and 20
// tabs; app size on disk.
import AppKit
import CoreGraphics
import Darwin
import Foundation

// MARK: Options

struct Browser {
    let name: String
    let app: URL
    var kind: Kind { name.hasPrefix("nera") ? .nera : name.hasPrefix("ardia") ? .ardia : .chromium }
    enum Kind { case nera, ardia, chromium }
}

var browsers: [Browser] = []
var extraEnv: [String: [String]] = [:]  // --env name=K=V
var runs = 5
var sessions = 2
var idleSeconds = 30.0
var settleSeconds = 15.0
var out = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "nera-xbench")
let port = 9472
do {
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = args.next() {
        switch arg {
        case "--app":
            guard let value = args.next(), let eq = value.firstIndex(of: "=") else { fatalError("--app name=path") }
            browsers.append(Browser(name: String(value[..<eq]), app: URL(fileURLWithPath: String(value[value.index(after: eq)...]))))
        case "--env":
            guard let value = args.next(), let eq = value.firstIndex(of: "=") else { fatalError("--env name=K=V") }
            extraEnv[String(value[..<eq]), default: []].append(String(value[value.index(after: eq)...]))
        case "--runs": runs = Int(args.next() ?? "") ?? runs
        case "--sessions": sessions = Int(args.next() ?? "") ?? sessions
        case "--idle": idleSeconds = Double(args.next() ?? "") ?? idleSeconds
        case "--settle": settleSeconds = Double(args.next() ?? "") ?? settleSeconds
        case "--out": out = URL(fileURLWithPath: args.next() ?? out.path)
        default: fatalError("unknown option \(arg)")
        }
    }
}
guard !browsers.isEmpty else { fatalError("give at least one --app name=path") }
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let beaconLog = out.appending(path: "beacons.jsonl")
let samplesLog = out.appending(path: "samples.jsonl")
FileManager.default.createFile(atPath: beaconLog.path, contents: nil)

func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
func now() -> Double { Date().timeIntervalSince1970 * 1000 }  // ms, same clock as the page's performance.timeOrigin
func wait(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

// MARK: Test pages

let server = Process()
server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
server.arguments = ["-I", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "bench_server.py").path, "\(port)", beaconLog.path]
try server.run()
defer { server.terminate() }
wait(0.8)

func pageURL(run: String, tab: Int) -> String { "http://127.0.0.1:\(port)/page?run=\(run)&tab=\(tab)" }

struct Beacon: Decodable {
    let run: String
    let tab: Int
    let t: Double
}

func beacons(run: String) -> [Beacon] {
    guard let text = try? String(contentsOf: beaconLog, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(Beacon.self, from: Data($0.utf8)) }.filter { $0.run == run }
}

// MARK: Processes

/// Every process of the app: its bundle's executables (helpers included) and their children.
func processes(of app: URL) -> [pid_t] {
    let ps = Process()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-axo", "pid=,ppid=,comm="]
    let pipe = Pipe()
    ps.standardOutput = pipe
    try? ps.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    // ps shows /private/tmp/…, URLs often say /tmp/…: compare both without the /private prefix.
    func plain(_ path: String) -> String { path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path }
    let prefix = plain(app.standardizedFileURL.path) + "/"
    var rows: [(pid: pid_t, ppid: pid_t, path: String)] = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, let pid = pid_t(parts[0]), let ppid = pid_t(parts[1]) else { continue }
        rows.append((pid, ppid, String(parts[2])))
    }
    var own = Set(rows.filter { plain($0.path).hasPrefix(prefix) }.map(\.pid))
    var grew = true
    while grew {
        grew = false
        for row in rows where own.contains(row.ppid) && !own.contains(row.pid) {
            own.insert(row.pid)
            grew = true
        }
    }
    return Array(own)
}

struct Usage {
    var cpuNanoseconds: Double = 0
    var wakeups: Double = 0
    var footprint: Double = 0
}

let timebase: Double = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(info.numer) / Double(info.denom)
}()

func usage(_ pids: [pid_t]) -> [pid_t: Usage] {
    var result: [pid_t: Usage] = [:]
    for pid in pids {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard ok == 0 else { continue }
        result[pid] = Usage(
            cpuNanoseconds: Double(info.ri_user_time + info.ri_system_time) * timebase,
            wakeups: Double(info.ri_pkg_idle_wkups + info.ri_interrupt_wkups), footprint: Double(info.ri_phys_footprint))
    }
    return result
}

/// CPU % (100 = one core) and wakeups per second over `seconds`, for processes alive at both ends.
func idle(_ app: URL, seconds: Double) -> (cpu: Double, wakeups: Double) {
    let before = usage(processes(of: app))
    let start = Date()
    wait(seconds)
    let after = usage(processes(of: app))
    let wall = Date().timeIntervalSince(start)
    var cpu = 0.0
    var wakeups = 0.0
    for (pid, end) in after {
        let begin = before[pid] ?? Usage()  // a process started in the window counts from zero
        cpu += max(0, end.cpuNanoseconds - begin.cpuNanoseconds)
        wakeups += max(0, end.wakeups - begin.wakeups)
    }
    return (cpu / (wall * 1e9) * 100, wakeups / wall)
}

func memory(_ app: URL) -> Double {
    usage(processes(of: app)).values.reduce(0) { $0 + $1.footprint } / 1_048_576
}

// MARK: Windows

/// The first on-screen window of the app that's at least 300×200 and visible.
func hasWindow(_ pids: Set<pid_t>) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return false }
    return list.contains { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
            (window[kCGWindowLayer as String] as? Int) == 0, (window[kCGWindowAlpha as String] as? Double ?? 0) > 0,
            let bounds = window[kCGWindowBounds as String] as? [String: Double]
        else { return false }
        return (bounds["Width"] ?? 0) >= 300 && (bounds["Height"] ?? 0) >= 200
    }
}

// MARK: Launching

func makeHome(for browser: Browser) -> URL {
    let home = out.appending(path: "homes/\(browser.name)-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: home.appending(path: "Library"), withIntermediateDirectories: true)
    if browser.kind == .ardia {
        let data = home.appending(path: "data")
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try? Data(#"{"version":1,"completedAt":1}"#.utf8).write(to: data.appending(path: "onboarding.json"))
    }
    return home
}

func environment(_ browser: Browser, home: URL) -> [String] {
    // No fake HOME: macOS then can't find the login keychain and offers to reset it. Each browser gets its own data
    // folder instead, and Chromium's mock keychain, so nothing reads or writes the user's Keychain.
    var env: [String] = []
    switch browser.kind {
    case .nera: env.append("NERA_BENCH=1")
    case .ardia: env.append("ARDIA_DATA_DIR=\(home.appending(path: "data").path)")
    case .chromium: break
    }
    return env + (extraEnv[browser.name] ?? [])
}

func arguments(_ browser: Browser, home: URL) -> [String] {
    switch browser.kind {
    case .nera: []
    case .ardia: ["--no-first-run", "--no-default-browser-check", "--password-store=basic", "--use-mock-keychain", "--mute-audio"]
    case .chromium:
        [
            "--user-data-dir=\(home.appending(path: "udd").path)", "--no-first-run", "--no-default-browser-check",
            "--password-store=basic", "--use-mock-keychain", "--mute-audio", "--window-size=1280,800", "--window-position=40,80",
        ]
    }
}

/// `open -n -a <app> [urls] --env … --args …`; returns the launch time (ms).
@discardableResult
func launch(_ browser: Browser, home: URL, urls: [String]) -> Double {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    var args = ["-n", "-a", browser.app.path]
    for variable in environment(browser, home: home) { args += ["--env", variable] }
    args += urls
    let extra = arguments(browser, home: home)
    if !extra.isEmpty { args += ["--args"] + extra }
    open.arguments = args
    let start = now()
    try? open.run()
    open.waitUntilExit()
    return start
}

/// Sends more links to the running instance of this copy of the app.
func openURL(_ browser: Browser, _ url: String) {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", browser.app.path, url]
    try? open.run()
    open.waitUntilExit()
}

func quit(_ browser: Browser) {
    for pid in processes(of: browser.app) { kill(pid, SIGTERM) }
    for _ in 0..<50 where !processes(of: browser.app).isEmpty { wait(0.1) }
    for pid in processes(of: browser.app) { kill(pid, SIGKILL) }
    for _ in 0..<50 where !processes(of: browser.app).isEmpty { wait(0.1) }
    wait(1)
}

// MARK: Rows

struct Sample: Encodable {
    let browser: String
    let row: String
    let value: Double
}

var samples: [Sample] = []
func record(_ browser: Browser, _ row: String, _ value: Double?) {
    guard let value else {
        log("  \(browser.name) \(row): no result")
        return
    }
    let sample = Sample(browser: browser.name, row: row, value: value)
    samples.append(sample)
    if let line = try? JSONEncoder().encode(sample), let handle = try? FileHandle(forWritingTo: samplesLog) {
        handle.seekToEndOfFile()
        handle.write(line + Data("\n".utf8))
        try? handle.close()
    }
    log(String(format: "  %@ %@: %.2f", browser.name, row, value))
}
FileManager.default.createFile(atPath: samplesLog.path, contents: nil)

/// Launch with no link → the first window on screen.
func launchToWindow(_ browser: Browser) -> Double? {
    let home = makeHome(for: browser)
    defer {
        quit(browser)
        try? FileManager.default.removeItem(at: home)
    }
    let start = launch(browser, home: home, urls: [])
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
        if hasWindow(Set(processes(of: browser.app))) { return now() - start }
        wait(0.004)
    }
    return nil
}

/// Launch with a link → the page's first contentful paint.
func launchToPaint(_ browser: Browser) -> Double? {
    let home = makeHome(for: browser)
    defer {
        quit(browser)
        try? FileManager.default.removeItem(at: home)
    }
    let run = "\(browser.name)-paint-\(UUID().uuidString.prefix(6))"
    let start = launch(browser, home: home, urls: [pageURL(run: run, tab: 0)])
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
        if let beacon = beacons(run: run).first { return beacon.t - start }
        wait(0.02)
    }
    return nil
}

/// One session: 1 tab idle and memory, then 20 tabs (opened one by one, like links) idle and memory.
func session(_ browser: Browser) {
    let home = makeHome(for: browser)
    defer {
        quit(browser)
        try? FileManager.default.removeItem(at: home)
    }
    let run = "\(browser.name)-session-\(UUID().uuidString.prefix(6))"
    launch(browser, home: home, urls: [pageURL(run: run, tab: 0)])
    var deadline = Date().addingTimeInterval(30)
    while beacons(run: run).isEmpty, Date() < deadline { wait(0.1) }
    wait(settleSeconds)
    let one = idle(browser.app, seconds: idleSeconds)
    record(browser, "idle CPU % (1 tab)", one.cpu)
    record(browser, "idle wakeups/s (1 tab)", one.wakeups)
    record(browser, "memory MB (1 tab)", memory(browser.app))
    for tab in 1..<20 {
        openURL(browser, pageURL(run: run, tab: tab))
        wait(0.4)
    }
    deadline = Date().addingTimeInterval(45)
    while Set(beacons(run: run).map(\.tab)).count < 20, Date() < deadline { wait(0.2) }
    let loaded = Set(beacons(run: run).map(\.tab)).count
    record(browser, "tabs that painted (of 20)", Double(loaded))
    wait(settleSeconds)
    let twenty = idle(browser.app, seconds: idleSeconds)
    record(browser, "idle CPU % (20 tabs)", twenty.cpu)
    record(browser, "idle wakeups/s (20 tabs)", twenty.wakeups)
    record(browser, "memory MB (20 tabs)", memory(browser.app))
}

// MARK: Run

for browser in browsers {
    quit(browser)  // nothing left over from an earlier run
    let du = Process()
    du.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    du.arguments = ["-sk", browser.app.path]
    let pipe = Pipe()
    du.standardOutput = pipe
    try? du.run()
    du.waitUntilExit()
    let kb = Double(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\t").first ?? "")
    record(browser, "app size MB", kb.map { $0 / 1024 })
}

for round in 0..<runs {
    let order = (0..<browsers.count).map { browsers[($0 + round) % browsers.count] }
    log("round \(round + 1)/\(runs): launches")
    for browser in order {
        record(browser, "launch → window on screen (ms)", launchToWindow(browser))
        record(browser, "launch → page painted (ms)", launchToPaint(browser))
    }
}
for round in 0..<sessions {
    let order = (0..<browsers.count).map { browsers[($0 + round) % browsers.count] }
    log("round \(round + 1)/\(sessions): sessions")
    for browser in order { session(browser) }
}

// MARK: Report

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

let rows = samples.map(\.row).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
var table = "| | " + browsers.map(\.name).joined(separator: " | ") + " |\n|---|" + browsers.map { _ in "---:" }.joined(separator: "|") + "|\n"
var summary: [String: [String: Double]] = [:]
for row in rows {
    var cells: [String] = []
    for browser in browsers {
        let values = samples.filter { $0.browser == browser.name && $0.row == row }.map(\.value)
        if let m = median(values) {
            summary[row, default: [:]][browser.name] = m
            cells.append(m >= 100 ? String(format: "%.0f", m) : String(format: "%.2f", m))
        } else {
            cells.append("–")
        }
    }
    table += "| \(row) | " + cells.joined(separator: " | ") + " |\n"
}
print(table)
if let json = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
    try? json.write(to: out.appending(path: "summary.json"))
}
log("✔ results in \(out.path) (samples.jsonl, summary.json)")
