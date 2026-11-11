// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    public import AppKit
    import BrowserCore
    import EngineKit
    import SecurityPolicy
    import UniformTypeIdentifiers

    /// File menu: Print, Save Page As, and Capture.
    extension AppModel {
        /// File › Print (⌘P).
        public func printPage() { selectedPage?.printPage() }

        /// File › Save Page As (⇧⌘S): the page as it is now, as an HTML file where the user chooses.
        public func savePageAs() {
            guard let page = selectedPage, let window = NSApp.keyWindow else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue =
                Self.fileName(for: page.state.title.isEmpty ? DisplayURL.short(page.state.url) : page.state.title) + ".html"
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let destination = panel.url else { return }
                Task { @MainActor in
                    let html = await page.evaluate("'<!DOCTYPE html>\\n' + document.documentElement.outerHTML")
                    guard let html, (try? Data(html.utf8).write(to: destination, options: .atomic)) != nil else {
                        self?.notice = "The page couldn't be saved."
                        return
                    }
                    self?.notice = "Saved \(destination.lastPathComponent)"
                }
            }
        }

        /// File › Capture Full Page.
        public func captureFullPage() {
            guard let page = selectedPage else { return }
            Task { @MainActor in deliverCapture(await page.capture(fullPage: true), title: page.state.title) }
        }

        /// File › Capture… (⇧⌘2): drag over the page to choose an area; a click takes all that's on screen.
        public func startCapture() {
            guard selectedPage != nil else { return }
            isCapturing = true
        }

        /// The area chosen while capturing (`rect` in the page view's points, top-left origin; nil: all of it).
        public func finishCapture(_ rect: CGRect?, in pageSize: CGSize) {
            isCapturing = false
            guard let page = selectedPage else { return }
            Task { @MainActor in
                // Let the selection overlay leave the screen first; the engine captures the page itself anyway.
                try? await Task.sleep(for: .milliseconds(60))
                var png = await page.capture(fullPage: false)
                if let rect, let full = png { png = Self.crop(full, to: rect, of: pageSize) }
                deliverCapture(png, title: page.state.title)
            }
        }

        /// Copies a capture and saves it to Downloads, like Arc's captures.
        private func deliverCapture(_ png: Data?, title: String) {
            guard let png else {
                notice = "The page couldn't be captured."
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let name = "Nera Capture \(formatter.string(from: Date())).png"
            if let downloads = downloadsDirectory, (try? png.write(to: downloads.appending(path: name), options: .atomic)) != nil {
                notice = "Capture copied, and saved to Downloads"
            } else {
                notice = "Capture copied"
            }
        }

        /// The part of a PNG of the page within `rect` (points of a page `size` points wide).
        static func crop(_ png: Data, to rect: CGRect, of size: CGSize) -> Data? {
            guard let image = NSBitmapImageRep(data: png)?.cgImage, size.width > 0, size.height > 0 else { return png }
            let scale = CGFloat(image.width) / size.width
            let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
            guard let part = image.cropping(to: pixels) else { return png }
            return NSBitmapImageRep(cgImage: part).representation(using: .png, properties: [:])
        }

        /// A file name from a page title (no path separators or colons).
        static func fileName(for title: String) -> String {
            let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\\\")).joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Page" : String(cleaned.prefix(120))
        }
    }
#endif
