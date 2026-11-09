// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import Foundation

    extension DemoMode {
        /// `--frames <dir>`: saves the window as fast as possible for `seconds`, from a background thread so the
        /// animation being recorded isn't slowed down (file names carry the time in milliseconds).
        static func recordFrames(to dir: String, seconds: Double) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            let number = UInt32(window.windowNumber)
            Thread.detachNewThread {
                typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
                guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
                    let symbol = dlsym(handle, "CGWindowListCreateImage")
                else { return }
                let create = unsafeBitCast(symbol, to: CreateImage.self)
                let start = Date()
                var index = 0
                while Date().timeIntervalSince(start) < seconds {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    guard let image = create(.null, 1 << 3, number, 1 << 4)?.takeRetainedValue(),
                        let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.6])
                    else { continue }
                    try? jpeg.write(to: URL(fileURLWithPath: dir).appending(path: String(format: "f%04d_%05d.jpg", index, ms)))
                    index += 1
                }
            }
        }

    }
#endif
