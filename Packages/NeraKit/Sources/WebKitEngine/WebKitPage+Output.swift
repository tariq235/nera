// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Foundation
import WebKit

#if os(macOS)
    import AppKit

    /// Printing and captures (File › Print, Capture).
    extension WebKitPage {
        func printPage() {
            guard let window = webView.window else { return }
            let operation = webView.printOperation(with: NSPrintInfo.shared)
            operation.view?.frame = webView.bounds  // WebKit's print view starts with no size
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }

        func capture(fullPage: Bool) async -> Data? {
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            if fullPage {
                guard let plan = PageCapture.plan(fromSizeScript: await evaluate(PageCapture.sizeScript)) else { return nil }
                configuration.rect = CGRect(x: 0, y: 0, width: plan.width, height: plan.height)
                configuration.snapshotWidth = NSNumber(value: plan.width)
            }
            guard let image = try? await webView.takeSnapshot(configuration: configuration),
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }
    }
#endif
