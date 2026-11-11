// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import Foundation

    /// Records Nera's windows for the promo (`--promo`): every visible Nera window inside the main window's frame
    /// (a Little Window or Peek too), at full resolution, about 60 times a second, from background threads. File
    /// names carry the time in milliseconds; `events.jsonl` logs moments on the same clock.
    final class FrameRecorder: @unchecked Sendable {
        private let dir: URL
        private let lock = NSLock()
        private var running = false
        private var count = 0
        private var startedAt = Date()
        private var current: (CGRect, [UInt32])?
        private var refresh: Timer?
        private let done = DispatchGroup()
        private let events: FileHandle?

        @MainActor init(dir: String) {
            self.dir = URL(fileURLWithPath: dir)
            try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
            let log = self.dir.appending(path: "events.jsonl")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            events = try? FileHandle(forWritingTo: log)
        }

        /// Notes a moment, timed like the frames.
        func log(_ type: String, _ fields: [String: Any]) {
            var entry = fields
            entry["type"] = type
            entry["ms"] = Int(Date().timeIntervalSince(lock.withLock { startedAt }) * 1000)
            guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
            events?.write(data + Data("\n".utf8))
        }

        /// The main window's frame (screen coordinates, top-left origin) and Nera's visible windows' numbers.
        @MainActor private static func targets() -> (CGRect, [UInt32])? {
            guard let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain && $0.frame.width >= 820 }),
                let screen = NSScreen.screens.first
            else { return nil }
            let frame = main.frame
            let rect = CGRect(x: frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
            // Front to back, as they are on screen.
            // Popovers (their own windows) first: they're always in front.
            let popovers = NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
            let numbers = (popovers + NSApp.orderedWindows.filter { $0.isVisible }).map { UInt32($0.windowNumber) }
            return (rect, numbers)
        }

        @MainActor func start() {
            let found = Self.targets()
            lock.withLock {
                running = true
                startedAt = Date()
                current = found
            }
            done.enter()
            // Windows come and go (a Little Window): look again on the main thread every few frames.
            refresh = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    let found = Self.targets()
                    self?.lock.withLock { self?.current = found }
                }
            }
            Thread.detachNewThread { [self] in
                typealias CreateImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
                guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
                    let symbol = dlsym(handle, "CGWindowListCreateImageFromArray")
                else { return done.leave() }
                let create = unsafeBitCast(symbol, to: CreateImage.self)
                let encoders = DispatchQueue(label: "promo.encode", attributes: .concurrent)
                let inFlight = DispatchSemaphore(value: 8)
                var index = 0
                var next = Date()
                while lock.withLock({ running }) {
                    let wait = next.timeIntervalSinceNow
                    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                    next = max(next, Date()).addingTimeInterval(1.0 / 60)
                    guard let (rect, numbers) = lock.withLock({ current }), !numbers.isEmpty else { continue }
                    let ms = Int(Date().timeIntervalSince(lock.withLock { startedAt }) * 1000)
                    // A CFArray of raw window IDs (no retain callbacks), as the API takes it.
                    var pointers: [UnsafeRawPointer?] = numbers.map { UnsafeRawPointer(bitPattern: UInt($0)) }
                    guard let ids = CFArrayCreate(nil, &pointers, pointers.count, nil) else { continue }
                    // Best resolution, windows without their shadows: the video draws its own.
                    guard let image = create(rect, ids, (1 << 0) | (1 << 3))?.takeRetainedValue() else { continue }
                    let name = String(format: "f%05d_%06d.jpg", index, ms)
                    index += 1
                    inFlight.wait()
                    done.enter()
                    encoders.async { [self] in
                        if let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                            try? jpeg.write(to: dir.appending(path: name))
                            lock.withLock { count += 1 }
                        }
                        inFlight.signal()
                        done.leave()
                    }
                }
                DispatchQueue.main.async { [self] in refresh?.invalidate() }
                done.leave()
            }
        }

        func stop() async -> Int {
            lock.withLock { running = false }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in done.notify(queue: .main) { c.resume() } }
            try? events?.close()
            return lock.withLock { count }
        }
    }
#endif
