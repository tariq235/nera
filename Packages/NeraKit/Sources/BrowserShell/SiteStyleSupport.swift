// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import EngineKit
import Foundation

/// Nera's SiteStyle scripts. Text from the user (CSS) is passed as a JSON string literal, never spliced as code.
enum SiteStyleScript {
    /// Adds, updates or removes (`css` empty) Nera's style sheet in the page.
    static func apply(_ css: String) -> String {
        let literal = (try? String(data: JSONEncoder().encode(css), encoding: .utf8)) ?? "\"\""
        return """
            (() => {
              const css = \(literal);
              let s = document.getElementById('nera-siteStyle');
              if (!css) { if (s) s.remove(); return 'removed'; }
              if (!s) { s = document.createElement('style'); s.id = 'nera-siteStyle'; (document.head || document.documentElement).appendChild(s); }
              s.textContent = css;
              return 'applied';
            })()
            """
    }

    /// Zap: hovering outlines a part of the page, clicking hides it. The chosen selectors stay in the page until
    /// ``zapFinish`` collects them.
    static let zapStart = """
        (() => {
          if (window.__neraZap) return 'running';
          const box = document.createElement('div');
          box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #ff3b6b;' +
            'background:rgba(255,59,107,.12);border-radius:4px;transition:all .08s ease-out;display:none';
          document.documentElement.appendChild(box);
          const picked = [];
          const path = (el) => {
            if (el.id && /^[A-Za-z][\\w-]*$/.test(el.id)) return '#' + el.id;
            const parts = [];
            while (el && el.nodeType === 1 && el !== document.body && parts.length < 6) {
              let part = el.tagName.toLowerCase();
              if (el.id && /^[A-Za-z][\\w-]*$/.test(el.id)) { parts.unshift('#' + el.id); break; }
              const parent = el.parentElement;
              if (parent) {
                const same = [...parent.children].filter(c => c.tagName === el.tagName);
                if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(el) + 1) + ')';
              }
              parts.unshift(part);
              el = parent;
            }
            return (parts[0] && parts[0].startsWith('#') ? '' : 'body > ') + parts.join(' > ');
          };
          const over = (e) => {
            const r = e.target.getBoundingClientRect();
            Object.assign(box.style, { display: 'block', left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px' });
          };
          const click = (e) => {
            e.preventDefault(); e.stopPropagation();
            const selector = path(e.target);
            picked.push(selector);
            e.target.style.setProperty('display', 'none', 'important');
            box.style.display = 'none';
          };
          document.addEventListener('mouseover', over, true);
          document.addEventListener('click', click, true);
          window.__neraZap = { picked, stop: () => {
            document.removeEventListener('mouseover', over, true);
            document.removeEventListener('click', click, true);
            box.remove();
          } };
          return 'started';
        })()
        """

    /// Ends Zap and returns the selectors picked (a JSON array).
    static let zapFinish = """
        (() => {
          const z = window.__neraZap;
          if (!z) return [];
          z.stop();
          delete window.__neraZap;
          return z.picked;
        })()
        """
}

extension AppModel {
    /// The SiteStyle for a page's site in its profile (`nil` when there's none).
    public func siteStyle(for page: any WebPage) -> SiteStyle? {
        guard let site = SiteStyle.site(of: page.state.url) else { return nil }
        return (state.profile(forTab: page.id) ?? state.currentProfile)?.siteStyles?[site]
    }

    /// Restyles a page for its site's SiteStyle (or removes a SiteStyle that no longer applies).
    func applySiteStyle(to page: any WebPage) {
        let css = siteStyle(for: page)?.styleSheet ?? ""
        guard !css.isEmpty || styledPages.contains(page.id) else { return }
        if css.isEmpty { styledPages.remove(page.id) } else { styledPages.insert(page.id) }
        Task { _ = await page.evaluate(SiteStyleScript.apply(css)) }
    }

    /// Saves the current page's SiteStyle and applies it to every open page of the site right away.
    public func saveSiteStyle(_ siteStyle: SiteStyle?, site: String) {
        guard let profile = state.currentProfile else { return }
        send(.library(.setSiteStyle(profileID: profile.id, site: site, siteStyle)))
        var ids = Set(state.spaces.flatMap(state.orderedTabs(in:)).map(\.id) + profile.favorites.map(\.id))
        if let peek { ids.insert(peek.id) }
        ids.formUnion(littleTabs.keys)
        for id in ids {
            if let page = pages.existingPage(for: id), SiteStyle.site(of: page.state.url) == site { applySiteStyle(to: page) }
        }
    }

    /// Starts Zap on the current page.
    public func startZap() {
        guard let page = selectedPage else { return }
        isZapping = true
        Task { _ = await page.evaluate(SiteStyleScript.zapStart) }
    }

    /// Ends Zap and adds what was picked to the site's SiteStyle.
    public func finishZap() {
        isZapping = false
        guard let page = selectedPage, let site = SiteStyle.site(of: page.state.url) else { return }
        Task {
            let json = await page.evaluate(SiteStyleScript.zapFinish) ?? "[]"
            let picked = (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
            guard !picked.isEmpty else { return }
            var siteStyle = self.siteStyle(for: page) ?? SiteStyle()
            siteStyle.zapped += picked.filter { !siteStyle.zapped.contains($0) }
            saveSiteStyle(siteStyle, site: site)
        }
    }
}
