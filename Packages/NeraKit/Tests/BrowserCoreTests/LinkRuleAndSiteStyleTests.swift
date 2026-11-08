// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TestSupport
import Testing

@testable import BrowserCore

@Suite("Link rules and SiteStyles")
struct LinkRouteAndSiteStyleTests {
    func route(_ pattern: String) -> LinkRoute { LinkRoute(id: UUID(), pattern: LinkRoute.normalize(pattern), spaceID: UUID()) }

    @Test func rulesMatchTheSiteItsSubdomainsAndPathPrefixes() {
        let figma = route("https://www.Figma.com/")
        #expect(figma.pattern == "figma.com")
        #expect(figma.matches(URL(string: "https://figma.com/file/1")!))
        #expect(figma.matches(URL(string: "https://www.figma.com/")!))
        #expect(figma.matches(URL(string: "https://help.figma.com/x")!))
        #expect(!figma.matches(URL(string: "https://notfigma.com/")!), "a different site that ends the same way")
        #expect(!figma.matches(URL(string: "https://figma.com.evil.example/")!))
        let repo = route("github.com/nera")
        #expect(repo.matches(URL(string: "https://github.com/nera")!))
        #expect(repo.matches(URL(string: "https://github.com/nera/issues/1")!))
        #expect(!repo.matches(URL(string: "https://github.com/nerax")!), "path prefixes stop at a slash")
        #expect(!repo.matches(URL(string: "https://github.com/other")!))
    }

    @Test func firstMatchingRuleWinsThenTheDefault() {
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        _ = Reducer.reduce(&s, .space(.create(title: "Work")), env.reducer)
        let work = s.spaces[1].id
        _ = Reducer.reduce(&s, .library(.addLinkRoute(pattern: "linear.app", spaceID: work)), env.reducer)
        _ = Reducer.reduce(&s, .library(.addLinkRoute(pattern: "  ", spaceID: work)), env.reducer)
        _ = Reducer.reduce(&s, .library(.addLinkRoute(pattern: "x.com", spaceID: UUID())), env.reducer)
        #expect(s.settings.linkRoutes.count == 1, "empty patterns and unknown Spaces are refused")
        #expect(LinkDestination.of(URL(string: "https://linear.app/issue/1")!, in: s) == .space(work))
        #expect(LinkDestination.of(URL(string: "https://example.com")!, in: s) == .littleWindow, "the default is a Little Window")
        _ = Reducer.reduce(&s, .library(.setExternalLinks(.currentSpace)), env.reducer)
        #expect(LinkDestination.of(URL(string: "https://example.com")!, in: s) == .currentSpace)
        _ = Reducer.reduce(&s, .space(.delete(work)), env.reducer)
        #expect(LinkDestination.of(URL(string: "https://linear.app/")!, in: s) == .currentSpace, "rules for deleted Spaces are skipped")
        _ = Reducer.reduce(&s, .library(.removeLinkRoute(s.settings.linkRoutes[0].id)), env.reducer)
        #expect(s.settings.linkRoutes.isEmpty)
    }

    @Test func olderLibrariesGetTheNewDefaults() throws {
        let old = #"{"archiveAfter":43200,"httpsOnly":true,"searchEngine":{"name":"D","template":"https://d.example/?q={query}"}}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        #expect(settings.externalLinks == .littleWindow && settings.linkRoutes.isEmpty && settings.peekLinks)
    }

    @Test func siteStyleStyleSheets() {
        var siteStyle = SiteStyle()
        #expect(siteStyle.isEmpty && siteStyle.styleSheet.isEmpty)
        siteStyle.isDark = true
        siteStyle.font = .serif
        siteStyle.zapped = ["#banner", "body > aside", "x { } body { display:none", ""]
        let css = siteStyle.styleSheet
        #expect(css.contains("invert(1) hue-rotate(180deg)") && css.contains("img, picture, video"))
        #expect(css.contains("Georgia"))
        #expect(css.contains("#banner, body > aside { display: none !important; }"))
        #expect(!css.contains("x { }"), "selectors that could break out of a rule are dropped")
        siteStyle.isEnabled = false
        #expect(siteStyle.styleSheet.isEmpty && !siteStyle.isEmpty, "off keeps the SiteStyle but applies nothing")
        siteStyle = SiteStyle()
        siteStyle.css = "p { color: red } </style><script>"
        #expect(!siteStyle.styleSheet.contains("</style>"))
    }

    @Test func siteStylesAreKeptPerSiteWithoutWww() {
        #expect(SiteStyle.site(of: URL(string: "https://www.Example.com/a")) == "example.com")
        #expect(SiteStyle.site(of: URL(string: "https://docs.example.com")) == "docs.example.com")
        #expect(SiteStyle.site(of: URL(string: "file:///tmp/a.html")) == nil && SiteStyle.site(of: nil) == nil)
        let env = TestEnv()
        var s = BrowserState.initial(uuid: env.nextUUID)
        let profile = s.profiles[0].id
        var siteStyle = SiteStyle()
        siteStyle.font = .mono
        _ = Reducer.reduce(&s, .library(.setSiteStyle(profileID: profile, site: "Example.com", siteStyle)), env.reducer)
        #expect(s.profiles[0].siteStyles?["example.com"] == siteStyle)
        _ = Reducer.reduce(&s, .library(.setSiteStyle(profileID: profile, site: "example.com", nil)), env.reducer)
        #expect(s.profiles[0].siteStyles == nil)
    }
}
