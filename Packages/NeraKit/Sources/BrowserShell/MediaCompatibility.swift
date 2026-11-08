// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
import EngineKit
import Foundation
import PageLifecycle

// Video and DRM on Chromium: streaming sites (the DRM ones) open in WebKit by default
// (SiteEngines); other sites whose video or audio format Chromium can't play get a suggestion to use WebKit for that
// site. DRM failures aren't detected: those sites are covered by the built-in list and the site popover.
extension AppModel {
    /// The site whose video the current tab can't play on Chromium (shows the suggestion banner).
    public var mediaSuggestion: String? {
        guard let id = state.selectedTabID, let site = mediaSuggestions[id], !dismissedMediaSites.contains(site),
            SiteEngines.site(of: pages.existingPage(for: id)?.state.url) == site  // still on that site
        else { return nil }
        return site
    }

    /// After a Chromium page loads, checks (twice: players often set up their video late) for media it can't play.
    func probeMedia(_ page: any WebPage) {
        mediaSuggestions[page.id] = nil  // a new document
        for id in mediaSuggestions.keys where pages.existingPage(for: id) == nil { mediaSuggestions[id] = nil }  // closed tabs
        guard pages.engineID(of: page.id) == EngineID.chromium.rawValue, let site = SiteEngines.site(of: page.state.url),
            let profile = state.currentProfile,
            SiteEngines.preferred(for: page.state.url, in: profile) == nil  // the user chose Chromium for this site
        else { return }
        Task { @MainActor [weak self] in
            for delay in [3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, SiteEngines.site(of: page.state.url) == site else { return }
                if await page.evaluate(MediaProbe.script) == MediaProbe.unsupported {
                    self.mediaSuggestions[page.id] = site
                    return
                }
            }
        }
    }

    /// Sends a site to an engine (`nil`: back to the default) and reopens its open pages there.
    public func setEngine(_ engine: EngineID?, forSite site: String) {
        guard let profile = state.currentProfile else { return }
        // Choosing what the site would get anyway clears the choice, so it follows the default from then on.
        var withoutChoice = profile
        withoutChoice.siteEngines?[site] = nil
        let byDefault = pages.registry.engine(for: withoutChoice, url: URL(string: "https://\(site)/")).descriptor.id
        let choice = engine?.rawValue == byDefault ? nil : engine
        send(.library(.setSiteEngine(profileID: profile.id, site: site, choice)))
        for (id, suggested) in mediaSuggestions where suggested == site { mediaSuggestions[id] = nil }
        let tabs = state.spaces.flatMap(state.orderedTabs(in:)) + profile.favorites
        for tab in tabs {
            let shown = SiteEngines.site(of: pages.existingPage(for: tab.id)?.state.url ?? tab.url)
            if let shown, shown == site || shown.hasSuffix("." + site) { pages.reopen(tab.id, fallbackURL: tab.url) }
        }
    }

    /// "Not now" on the suggestion: not asked again for the site this session.
    public func dismissMediaSuggestion() {
        if let site = mediaSuggestion { dismissedMediaSites.insert(site) }
    }

    /// The engine the current site uses, for the site popover ("Open with WebKit").
    public var currentSiteEngine: EngineID? {
        guard let id = state.selectedTabID, let raw = pages.engineID(of: id) else { return nil }
        return EngineID(rawValue: raw)
    }
}

#if canImport(SwiftUI)
    import SwiftUI

    /// Over the top of a page whose video Chromium can't play: suggests showing the site with WebKit.
    struct MediaSuggestionBanner: View {
        @Bindable var model: AppModel
        let site: String

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "play.slash").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("This site's video needs WebKit").font(.callout.weight(.semibold))
                    Text("Nera's Chromium can't play this format. WebKit can, and you can switch back any time.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Not Now") { model.dismissMediaSuggestion() }.buttonStyle(.borderless)
                Button("Use WebKit for \(site)") { model.setEngine(.webKit, forSite: site) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("media.useWebKit")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(12)
            .frame(maxWidth: 620)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("media.suggestion")
        }
    }
#endif
