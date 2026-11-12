// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if DEBUG && os(macOS)
    import AppKit
    import BrowserCore
    import EngineKit

    extension DemoMode {
        /// `--shot pip --url <page playing a video with sound>`: the page's tab reports sound, leaving it floats the
        /// video, coming back puts it back, and mute works. Logs each step (with the floating windows on screen) and quits.
        static func pictureInPictureCheck(_ model: AppModel) async {
            let log = { (line: String) in FileHandle.standardOutput.write(Data("pip: \(line)\n".utf8)) }  // Debug tool output
            if CommandLine.arguments.contains("--webkit"), let site = SiteEngines.site(of: model.selectedPage?.state.url) {
                model.setEngine(.webKit, forSite: site)
                try? await Task.sleep(for: .seconds(5))
            }
            guard let videoTab = model.state.selectedTabID, let page = model.pages.existingPage(for: videoTab) else {
                return log("✘ no page")
            }
            log("audible=\(page.state.isAudible) muted=\(page.state.isMuted)")
            if CommandLine.arguments.contains("--probe") {
                log("probe enter: \(await page.evaluateAsUserGesture(PictureInPictureScript.enter) ?? "nil")")
                log(
                    "probe plain: \(await page.evaluate("[...document.querySelectorAll('video')].map(v => [v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('picture-in-picture'), v.webkitSupportsPresentationMode && v.webkitSupportsPresentationMode('fullscreen'), v.readyState, v.disablePictureInPicture].join()).join(';')") ?? "nil")"
                )
                log("probe gesture: \(await page.evaluateAsUserGesture("Promise.resolve('ok')") ?? "nil")")
                exit(0)
            }
            let other = model.state.spaces.flatMap(model.state.orderedTabs(in:)).first { $0.id != videoTab }
            if let other { model.send(.tab(.select(other.id))) }
            try? await Task.sleep(for: .seconds(4))
            log("left tab: floating=\(model.pictureInPictureTabs.contains(videoTab)) windows=\(floatingWindows())")
            model.send(.tab(.select(videoTab)))
            try? await Task.sleep(for: .seconds(3))
            log(
                "back: floating=\(model.pictureInPictureTabs.contains(videoTab)) windows=\(floatingWindows()) audible=\(page.state.isAudible)"
            )
            log(
                "video: \(await page.evaluate("[...document.querySelectorAll('video')].map(v => [v.paused, v.muted, v.currentTime.toFixed(1)].join()).join(';')") ?? "nil")"
            )
            page.setMuted(true)
            try? await Task.sleep(for: .seconds(1))
            log("muted: audible=\(page.state.isAudible) muted=\(page.state.isMuted)")
            log(
                "video: \(await page.evaluate("[...document.querySelectorAll('video')].map(v => [v.paused, v.muted, v.currentTime.toFixed(1)].join()).join(';')") ?? "nil")"
            )
            page.setMuted(false)
            try? await Task.sleep(for: .seconds(1))
            log("unmuted: audible=\(page.state.isAudible) muted=\(page.state.isMuted)")
            log(
                "video: \(await page.evaluate("[...document.querySelectorAll('video')].map(v => [v.paused, v.muted, v.currentTime.toFixed(1)].join()).join(';')") ?? "nil")"
            )
            exit(0)
        }

        /// On-screen windows above normal ones (Picture in Picture floats), any process: "owner WxH".
        private static func floatingWindows() -> [String] {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            return list.compactMap { info in
                guard let layer = info[kCGWindowLayer as String] as? Int, layer > 0, layer < 25,
                    let owner = info[kCGWindowOwnerName as String] as? String,
                    let bounds = info[kCGWindowBounds as String] as? [String: Double]
                else { return nil }
                return "\(owner) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0)) layer \(layer)"
            }
        }
    }
#endif
