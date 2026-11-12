// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

extension Reducer {
    static func reduceLibrary(_ state: inout BrowserState, _ action: LibraryAction, _ env: ReducerEnvironment) -> [Effect] {
        switch action {
        case .archiveSweep: return archiveSweep(&state, env)

        case .importLibrary(let spaces, let favorites):
            state.spaces.append(contentsOf: spaces)
            if !favorites.isEmpty, let profileID = spaces.first?.profileID ?? state.profiles.first?.id,
                let pi = state.profiles.firstIndex(where: { $0.id == profileID })
            {
                state.profiles[pi].favorites.append(contentsOf: favorites)
            }
            if let first = spaces.first {
                state.selectedSpaceID = first.id
                state.selectedTabID = nil
            }
            return []

        case .importArchive(let tabs):
            let spaceIDs = Set(state.spaces.map(\.id))
            let known = Set(state.archive.map(\.id))
            let added = tabs.filter { spaceIDs.contains($0.spaceID) && !known.contains($0.id) }
            state.archive = Array((state.archive + added).sorted { $0.archivedAt > $1.archivedAt }.prefix(BrowserState.archiveLimit))
            return []

        case .setEngine(let profileID, let engine):
            guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }),
                state.profiles[pi].engine != engine
            else { return [] }
            state.profiles[pi].engine = engine
            // Pages belong to an engine; discard this profile's pages so they reopen in the new one.
            let spaceTabs = state.spaces.filter { $0.profileID == profileID }.flatMap { $0.pinned + $0.today }.flatMap(\.tabs)
            return (spaceTabs + state.profiles[pi].favorites).map { .discardPage(tabID: $0.id) }

        case .setSitePermission(let profileID, let origin, let kind, let setting):
            guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }) else { return [] }
            var list = (state.profiles[pi].sitePermissions ?? []).filter { !($0.origin == origin && $0.kind == kind) }
            if let setting { list.append(SitePermission(origin: origin, kind: kind, setting: setting)) }
            state.profiles[pi].sitePermissions = list.isEmpty ? nil : list
            return []

        case .createProfile(let name): return createProfile(&state, name: name, env)
        case .renameProfile(let id, let name): return renameProfile(&state, id, name: name)
        case .deleteProfile(let id): return deleteProfile(&state, id, env)
        case .bookmarks(let profileID, let action): return reduceBookmarks(&state, profileID, action, env)
        case .setSiteZoom(let profileID, let host, let factor): return setSiteZoom(&state, profileID, host: host, factor: factor)
        case .setDeveloperTools, .setSearchEngine, .setArchiveAfter, .setExternalLinks, .addLinkRoute, .removeLinkRoute, .setPeekLinks,
            .setAutoPictureInPicture,
            .setAppearance,
            .setSiteStyle, .setSiteEngine:
            return reduceSettings(&state, action, env)

        case .completeOnboarding:
            state.settings.hasCompletedOnboarding = true
            return []

        case .resetSitePermissions(let profileID, let origin):
            guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }) else { return [] }
            // Resetting every site keeps the profile-wide defaults (origin "*").
            let kept = (state.profiles[pi].sitePermissions ?? []).filter {
                origin == nil ? $0.origin == SitePermission.allSites : $0.origin != origin
            }
            state.profiles[pi].sitePermissions = kept.isEmpty ? nil : kept
            return []
        }
    }

    // MARK: Profiles

    private static func createProfile(_ state: inout BrowserState, name: String, _ env: ReducerEnvironment) -> [Effect] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        let profile = Profile(id: env.uuid(), name: name)
        state.profiles.append(profile)
        return reduceSpace(&state, .createInProfile(title: name, profileID: profile.id), env)
    }

    private static func renameProfile(_ state: inout BrowserState, _ id: UUID, name: String) -> [Effect] {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let pi = state.profiles.firstIndex(where: { $0.id == id }) else { return [] }
        state.profiles[pi].name = name
        return []
    }

    private static func deleteProfile(_ state: inout BrowserState, _ id: UUID, _ env: ReducerEnvironment) -> [Effect] {
        guard state.profiles.count > 1, let pi = state.profiles.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = state.profiles.remove(at: pi)
        let removedSpaces = state.spaces.filter { $0.profileID == id }
        let removedSpaceIDs = Set(removedSpaces.map(\.id))
        state.spaces.removeAll { $0.profileID == id }
        // Closed tabs of the deleted Spaces go too: nothing of the profile stays behind.
        state.archive.removeAll { removedSpaceIDs.contains($0.spaceID) }
        state.recentlyClosed.removeAll { removedSpaceIDs.contains($0.spaceID) }
        if state.spaces.isEmpty, let fallback = state.profiles.first {
            state.spaces.append(Space(id: env.uuid(), title: fallback.name, profileID: fallback.id))
        }
        if removedSpaceIDs.contains(state.selectedSpaceID), let first = state.spaces.first {
            state.selectedSpaceID = first.id
            state.selectedTabID = state.orderedTabs(in: first).first?.id
        }
        let tabs = removedSpaces.flatMap { $0.pinned + $0.today }.flatMap(\.tabs) + removed.favorites
        return tabs.map { .discardPage(tabID: $0.id) } + [.removeProfileData(profileID: id)]
    }

    private static func setSiteStyle(_ state: inout BrowserState, _ profileID: UUID, site: String, _ siteStyle: SiteStyle?) -> [Effect] {
        guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }), !site.isEmpty else { return [] }
        var siteStyles = state.profiles[pi].siteStyles ?? [:]
        siteStyles[site.lowercased()] = siteStyle
        state.profiles[pi].siteStyles = siteStyles.isEmpty ? nil : siteStyles
        return []
    }

    private static func setSiteZoom(_ state: inout BrowserState, _ profileID: UUID, host: String, factor: Double?) -> [Effect] {
        guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }), !host.isEmpty else { return [] }
        var zooms = state.profiles[pi].siteZoom ?? [:]
        zooms[host.lowercased()] = factor.flatMap { abs($0 - 1) < 0.001 ? nil : min(max($0, 0.25), 5) }
        state.profiles[pi].siteZoom = zooms.isEmpty ? nil : zooms
        return []
    }

    private static func archiveSweep(_ state: inout BrowserState, _ env: ReducerEnvironment) -> [Effect] {
        let cutoff = env.now().addingTimeInterval(-state.settings.archiveAfter)
        var effects: [Effect] = []
        for si in state.spaces.indices {
            let stale = state.spaces[si].today.compactMap { node -> UUID? in
                guard case .tab(let t) = node.kind, t.id != state.selectedTabID, t.lastActiveAt < cutoff else { return nil }
                return t.id
            }
            for id in stale {
                if let tab = state.spaces[si].today.removeTab(id: id) {
                    pushArchive(&state, ArchivedTab(tab: tab, spaceID: state.spaces[si].id, archivedAt: env.now()))
                    effects.append(.discardPage(tabID: id))
                }
            }
        }
        return effects
    }

    /// App settings. A search engine is accepted only if it builds a real web address (https, or http for local
    /// ones); tabs are never archived sooner than after an hour.
    private static func reduceSettings(_ state: inout BrowserState, _ action: LibraryAction, _ env: ReducerEnvironment) -> [Effect] {
        switch action {
        case .setDeveloperTools(let on):
            state.settings.isDeveloperToolsEnabled = on
        case .setSearchEngine(let engine):
            guard let url = engine.url(for: "test"), ["https", "http"].contains(url.scheme ?? ""), url.host() != nil,
                engine.template.contains("{query}")
            else { return [] }
            state.settings.searchEngine = engine
        case .setArchiveAfter(let interval):
            state.settings.archiveAfter = max(3600, interval)
        case .setExternalLinks(let target):
            state.settings.externalLinks = target
        case .addLinkRoute(let raw, let spaceID):
            let pattern = LinkRoute.normalize(raw)
            guard !pattern.isEmpty, !pattern.contains(" "), state.spaces.contains(where: { $0.id == spaceID }) else { return [] }
            state.settings.linkRoutes.removeAll { $0.pattern == pattern }
            state.settings.linkRoutes.append(LinkRoute(id: env.uuid(), pattern: pattern, spaceID: spaceID))
        case .removeLinkRoute(let id):
            state.settings.linkRoutes.removeAll { $0.id == id }
        case .setPeekLinks(let on):
            state.settings.peekLinks = on
        case .setAutoPictureInPicture(let on):
            state.settings.autoPictureInPicture = on
        case .setAppearance(let choice):
            state.settings.appearance = choice
        case .setSiteEngine(let profileID, let site, let engine):
            guard let pi = state.profiles.firstIndex(where: { $0.id == profileID }), !site.isEmpty else { return [] }
            var engines = state.profiles[pi].siteEngines ?? [:]
            engines[site.lowercased()] = engine
            state.profiles[pi].siteEngines = engines.isEmpty ? nil : engines
        case .setSiteStyle(let profileID, let site, let siteStyle):
            return setSiteStyle(&state, profileID, site: site, siteStyle)
        default: break
        }
        return []
    }
}
