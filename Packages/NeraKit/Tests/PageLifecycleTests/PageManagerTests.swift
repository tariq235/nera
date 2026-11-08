// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
import EngineTestSupport
import Foundation
import SecurityPolicy
import TestSupport
import Testing

@testable import PageLifecycle

@MainActor
final class Fixture {
    let env = TestEnv()
    let engine: FakeEngine
    let manager: PageManager
    var sent: [Action] = []
    let profile = Profile(id: UUID(), name: "P")

    init(engines: [FakeEngine] = [FakeEngine()], maxLivePages: Int = 24) {
        engine = engines.first { $0.descriptor.isAvailable } ?? engines[0]
        let env = env
        manager = PageManager(registry: EngineRegistry(engines), maxLivePages: maxLivePages, idleTimeout: 600, clock: { env.now })
        manager.send = { [weak self] in self?.sent.append($0) }
    }

    func tab(_ url: String? = "https://a.example") -> Tab {
        Tab(id: UUID(), url: url.flatMap(URL.init(string:)), lastActiveAt: env.now)
    }

    @discardableResult
    func show(_ tab: Tab) -> FakePage {
        manager.page(for: tab, profile: profile) as! FakePage
    }
}

@MainActor
@Suite("PageManager")
struct PageManagerTests {
    @Test func createsPagesLazilyInTheProfilesStorageAndLoadsTheTabURL() {
        let f = Fixture()
        let t = f.tab()
        #expect(f.manager.existingPage(for: t.id) == nil)
        let page = f.show(t)
        #expect(page.loads == [t.url!])
        #expect(f.engine.configurations.first?.storage == .persistent(f.profile.id))
        #expect(f.show(t) === page)  // reused, not recreated
    }

    @Test func registryPrefersTheFirstAvailableEngineAndHonorsProfileChoice() {
        let chromium = FakeEngine(id: "chromium", isAvailable: false)
        let webkit = FakeEngine(id: "webkit")
        let registry = EngineRegistry([chromium, webkit])
        var profile = Profile(id: UUID(), name: "P", engine: .chromium)
        #expect(registry.engine(for: profile) === webkit)  // Chromium unavailable → falls back, no UI change

        chromium.descriptor.isAvailable = true
        #expect(registry.engine(for: profile) === chromium)  // ships → takes over automatically
        profile.engine = .webKit
        #expect(registry.engine(for: profile) === webkit)
        profile.engine = nil
        #expect(registry.defaultEngine === chromium)
    }

    @Test func lruEvictionNeverDiscardsTheActiveTab() {
        let f = Fixture(maxLivePages: 2)
        let a = f.tab()
        let b = f.tab()
        let c = f.tab()
        f.show(a)
        f.env.now += 1
        f.show(b)
        f.env.now += 1
        f.show(a)
        f.env.now += 1  // a is most recent
        f.show(c)  // c active; b is least recent
        #expect(f.manager.livePageCount == 2)
        #expect(f.manager.existingPage(for: b.id) == nil)
        #expect(f.manager.existingPage(for: c.id) != nil)
    }

    @Test func memoryPressureFreesBackgroundPages() {
        let f = Fixture()
        let tabs = (0..<5).map { _ in f.tab() }
        for t in tabs {
            f.show(t)
            f.env.now += 1
        }  // last one is active
        f.manager.handleMemoryPressure(.warning)  // older half of 4 background pages
        #expect(f.manager.livePageCount == 3)
        #expect(f.manager.existingPage(for: tabs[0].id) == nil)
        f.manager.handleMemoryPressure(.critical)
        #expect(f.manager.livePageCount == 1)
        #expect(f.manager.existingPage(for: tabs[4].id) != nil)
    }

    @Test func idleBackgroundPagesAreSuspended() {
        let f = Fixture()
        let old = f.tab()
        let active = f.tab()
        f.show(old)
        f.env.now += 700
        f.show(active)
        f.manager.suspendIdlePages()
        #expect(f.manager.existingPage(for: old.id) == nil)
        #expect(f.manager.existingPage(for: active.id) != nil)
    }

    @Test func effectsLoadAndDiscardPages() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        f.manager.handle(.load(tabID: t.id, url: URL(string: "https://b.example")!))
        #expect(page.loads.last == URL(string: "https://b.example"))
        f.manager.handle(.discardPage(tabID: t.id))
        #expect(page.isClosed)
        #expect(f.manager.existingPage(for: t.id) == nil)
    }

    @Test func stateChangesReachTheStoreOnlyWhenURLOrTitleChange() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        f.sent.removeAll()
        page.simulateState { $0.progress = 0.5 }  // not stored
        page.simulateState { $0.title = "Hello" }
        page.simulateState {
            $0.title = "Hello"
            $0.isLoading = true
        }  // unchanged title
        #expect(f.sent == [.tab(.didUpdate(t.id, url: t.url, title: "Hello"))])
    }

    @Test func blockedNavigationsAreRecordedForTheBanner() {
        let f = Fixture()
        let t = f.tab()
        f.show(t).simulate(.navigationBlocked(URL(string: "file:///etc/hosts")!, .fileURLFromWeb))
        #expect(f.manager.lastBlocked == BlockedNavigation(url: URL(string: "file:///etc/hosts")!, reason: .fileURLFromWeb, tabID: t.id))
    }

    @Test func crashedPagesAreMarkedAndReloadRecreatesThem() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        page.simulate(.processTerminated(.crashed))
        #expect(f.manager.crashedTabs == [t.id])
        f.manager.reloadCrashed(t, profile: f.profile)
        #expect(f.manager.crashedTabs.isEmpty)
        #expect(page.isClosed)
        let fresh = f.manager.existingPage(for: t.id) as? FakePage
        #expect(fresh !== page && fresh?.loads == [t.url!])
    }

    @Test func discardingATabDeniesItsPendingRequests() {
        let f = Fixture()
        let t = f.tab()
        var answer: PermissionDecision?
        f.show(t).simulate(
            .permission(
                PermissionRequest(
                    origin: SecurityOrigin(url: URL(string: "https://a.example")), kinds: [.camera],
                    decision: Decision(fallback: .deny) { answer = $0 })))
        #expect(f.manager.requests(for: t.id).count == 1)
        #expect(answer == nil)
        f.manager.discard(t.id)
        #expect(answer == .deny)
    }

    @Test func requestsFromPagesThatAreNoLongerLiveAreDenied() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        f.manager.discard(t.id)
        var answer: ExternalAppDecision?
        page.simulate(
            .externalApp(
                ExternalAppRequest(
                    url: URL(string: "zoommtg://x")!, origin: .opaque,
                    decision: Decision(fallback: .block) { answer = $0 })))
        #expect(answer == .block)
        #expect(f.manager.requests(for: t.id).isEmpty)
    }

    @Test func dialogFloodsAreAutoCancelledUntilTheNextNavigation() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        var answers: [DialogResponse] = []
        func dialog() {
            page.simulate(
                .dialog(
                    DialogRequest(
                        origin: .opaque, kind: .alert(message: "spam"),
                        decision: Decision(fallback: .cancel) { answers.append($0) })))
        }
        for _ in 0..<5 { dialog() }
        #expect(f.manager.requests(for: t.id).count == 3)
        #expect(answers == [.cancel, .cancel])  // the 4th and 5th were suppressed
        page.simulate(.navigationCommitted(URL(string: "https://a.example/next")))
        dialog()
        #expect(f.manager.requests(for: t.id).count == 4)
    }

    @Test func childPagesAreAdoptedAsTabs() {
        let f = Fixture()
        let opener = f.tab()
        let page = f.show(opener)
        let child = FakePage(id: UUID(), delegate: f.manager)
        var decision: NewPageDecision?
        page.simulate(
            .newPage(
                NewPageRequest(
                    page: child, url: URL(string: "https://auth.example"), disposition: .popup,
                    decision: Decision(fallback: .discard) { decision = $0 })))
        #expect(decision == .adopt)
        #expect(f.manager.existingPage(for: child.id) === child)
        #expect(
            f.sent.contains(.tab(.openChild(id: child.id, url: URL(string: "https://auth.example"), openerID: opener.id, select: true))))
    }

    @Test func pagesClosingThemselvesCloseTheirTab() {
        let f = Fixture()
        let t = f.tab()
        f.show(t).simulate(.closeRequested)
        #expect(f.sent.last == .tab(.close(t.id)))
    }

    @Test func downloadsUseTheChosenDestinationOrAreCancelled() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        var answers: [DownloadDecision] = []
        func request(_ id: UUID) {
            page.simulate(
                .download(
                    DownloadRequest(
                        id: id, sourceURL: nil, suggestedFilename: "a.txt", mimeType: nil, expectedLength: nil,
                        decision: Decision(fallback: .cancel) { answers.append($0) })))
        }
        request(UUID())  // no destination provider → cancelled
        let dest = URL(fileURLWithPath: "/Downloads/a.txt")
        f.manager.downloadDestination = { _ in dest }
        let id = UUID()
        request(id)
        #expect(answers == [.cancel, .saveTo(dest)])
        page.simulate(.download(DownloadEvent(id: id, state: .finished(dest))))
        #expect(f.manager.downloads.map(\.id) == [id])
        #expect(f.manager.downloads.first?.state == .finished(dest) && f.manager.downloads.first?.fileURL == dest)
        #expect(f.manager.downloads.first?.destination == dest && f.manager.downloads.first?.tabID == t.id)
        f.manager.dismissDownload(id)
        #expect(f.manager.downloads.isEmpty)
    }

    @Test func dangerousDownloadsWaitForTheUserAndFinishedOnesAreReported() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        var answers: [DownloadDecision] = []
        var finished: [URL] = []
        let dest = URL(fileURLWithPath: "/Downloads/setup.pkg")
        f.manager.downloadDestination = { _ in dest }
        f.manager.downloadRisk = { $0.suggestedFilename.hasSuffix(".pkg") ? "installer" : nil }
        f.manager.downloadFinished = { finished.append($0) }
        let id = UUID()
        page.simulate(
            .download(
                DownloadRequest(
                    id: id, sourceURL: nil, suggestedFilename: "setup.pkg", mimeType: nil, expectedLength: nil,
                    decision: Decision(fallback: .cancel) { answers.append($0) })))
        #expect(answers.isEmpty, "not saved before the user confirms")
        guard case .download(let queued)? = f.manager.pendingRequests[t.id]?.first else {
            Issue.record("dangerous download not queued")
            return
        }
        f.manager.startDownload(queued, tabID: t.id)  // user chose "Download Anyway"
        #expect(answers == [.saveTo(dest)])
        page.simulate(.download(DownloadEvent(id: id, state: .finished(dest))))
        #expect(finished == [dest], "finished downloads are handed over for quarantine")
    }

    @Test func answeredRequestsLeaveTheQueue() {
        let f = Fixture()
        let t = f.tab()
        let request = PageRequest.dialog(
            DialogRequest(origin: .opaque, kind: .alert(message: "hi"), decision: Decision(fallback: .cancel) { _ in }))
        f.show(t).simulate(request)
        f.manager.dismissRequest(request.id)
        #expect(f.manager.requests(for: t.id).isEmpty)
    }
}

extension PageManagerTests {
    /// Downloads UI: cancel, retry, clear, and the states the tray shows.
    @Test func downloadsCanBeCancelledRetriedAndCleared() {
        let f = Fixture()
        let t = f.tab()
        let page = f.show(t)
        let source = URL(string: "https://files.example/big.zip")!
        f.manager.downloadDestination = { URL(fileURLWithPath: "/Downloads/\($0.suggestedFilename)") }
        func start(_ id: UUID, _ name: String, from url: URL? = source) {
            page.simulate(
                .download(
                    DownloadRequest(
                        id: id, sourceURL: url, suggestedFilename: name, mimeType: nil, expectedLength: nil,
                        decision: Decision(fallback: .cancel) { _ in })))
        }
        let big = UUID()
        let done = UUID()
        let blob = UUID()
        start(big, "big.zip")
        start(done, "done.txt")
        start(blob, "blob.bin", from: URL(string: "blob:https://files.example/1"))
        page.simulate(.download(DownloadEvent(id: big, state: .progress(received: 25, total: 100))))
        #expect(f.manager.downloads[0].fractionCompleted == 0.25 && f.manager.downloads[0].isActive)

        f.manager.cancelDownload(big)
        #expect(page.cancelledDownloads == [big], "the engine is told to stop")
        #expect(f.manager.downloads[0].state == .cancelled, "shown as cancelled at once")
        page.simulate(.download(DownloadEvent(id: big, state: .failed("interrupted"))))
        #expect(f.manager.downloads[0].state == .cancelled, "late engine events don't overwrite a cancel")
        #expect(f.manager.downloads[0].canRetry)

        #expect(f.manager.retryDownload(big))
        #expect(page.startedDownloads == [source], "retry downloads the same URL again")
        #expect(!f.manager.downloads.contains { $0.id == big }, "the new download replaces the old entry")

        page.simulate(.download(DownloadEvent(id: blob, state: .failed("gone"))))
        #expect(!f.manager.retryDownload(blob), "blob: downloads can't be fetched again")

        page.simulate(.download(DownloadEvent(id: done, state: .finished(URL(fileURLWithPath: "/Downloads/done.txt")))))
        #expect(!f.manager.downloads.first { $0.id == done }!.canRetry, "finished downloads aren't retried")
        f.manager.cancelDownload(done)
        #expect(page.cancelledDownloads == [big], "finished downloads can't be cancelled")

        start(UUID(), "running.iso")
        f.manager.clearInactiveDownloads()
        #expect(f.manager.downloads.map(\.filename) == ["running.iso"], "Clear keeps running downloads")
    }
}

/// which page changes become history.
@MainActor
@Suite("History recording")
struct HistoryRecordingTests {
    struct Visit: Equatable {
        let profile: UUID, url: String, title: String, isNew: Bool
    }

    @Test func persistentPagesRecordVisitsAndTitlesPrivatePagesNothing() {
        let f = Fixture()
        var visits: [Visit] = []
        f.manager.pageVisited = { visits.append(Visit(profile: $0, url: $1.absoluteString, title: $2, isNew: $3)) }

        let page = f.show(f.tab("https://a.example"))
        page.simulateState {
            $0.url = URL(string: "https://a.example")
            $0.title = "A"
        }
        page.simulateState { $0.title = "A (1)" }
        page.simulateState {
            $0.url = URL(string: "https://b.example")
            $0.title = "B"
        }
        #expect(
            visits == [
                Visit(profile: f.profile.id, url: "https://a.example", title: "A", isNew: true),
                Visit(profile: f.profile.id, url: "https://a.example", title: "A (1)", isNew: false),
                Visit(profile: f.profile.id, url: "https://b.example", title: "B", isNew: true),
            ])

        visits.removeAll()
        let privatePage = f.manager.page(for: f.tab("https://secret.example"), profile: f.profile, storage: .ephemeral(UUID())) as! FakePage
        privatePage.simulateState {
            $0.url = URL(string: "https://secret.example/next")
            $0.title = "Secret"
        }
        #expect(visits.isEmpty, "private pages never reach history")
    }

    @Test func childPagesRecordInTheirOpenersProfile() {
        let f = Fixture()
        var urls: [String] = []
        f.manager.pageVisited = { _, url, _, isNew in if isNew { urls.append(url.absoluteString) } }
        let opener = f.show(f.tab())
        let child = FakePage(id: UUID(), delegate: f.manager)
        opener.simulate(
            .newPage(
                NewPageRequest(
                    page: child, url: URL(string: "https://child.example"), disposition: .foregroundTab,
                    decision: Decision(fallback: .discard) { _ in })))
        child.simulateState {
            $0.url = URL(string: "https://child.example")
            $0.title = "Child"
        }
        #expect(urls == ["https://child.example"])
    }
}

/// developer tools follow the user's setting on every page.
@MainActor
@Suite("Developer tools")
struct DevToolsTests {
    @Test func theSettingReachesNewAndExistingPages() {
        let f = Fixture()
        let before = f.show(f.tab())
        #expect(!before.devToolsEnabled && !before.showDevTools(), "off by default (SEC-056)")
        f.manager.devToolsEnabled = true
        #expect(before.devToolsEnabled, "applied to open pages")
        let after = f.show(f.tab("https://b.example"))
        #expect(after.devToolsEnabled, "applied to new pages")
        #expect(after.showDevTools() && after.devToolsShown == 1)
        f.manager.devToolsEnabled = false
        #expect(!after.showDevTools())
    }
}

/// per-site zoom follows the page across sites.
@MainActor
@Suite("Site zoom")
struct SiteZoomTests {
    @Test func rememberedZoomIsAppliedWhenThePageChangesSite() {
        let f = Fixture()
        f.manager.zoomForURL = { _, url in url.host() == "big.example" ? 1.5 : 1 }
        let page = f.show(f.tab("https://a.example"))
        page.simulateState {
            $0.url = URL(string: "https://big.example/")
            $0.title = "Big"
        }
        #expect(page.state.zoom == 1.5)
        page.setZoom(2)  // the user zooms further on the same site
        page.simulateState { $0.url = URL(string: "https://big.example/next") }
        #expect(page.state.zoom == 2, "same site: left alone")
        page.simulateState { $0.url = URL(string: "https://other.example/") }
        #expect(page.state.zoom == 1, "another site: its own zoom")
    }
}

/// favicons are cached only from persistent profiles.
@MainActor
@Suite("Favicons")
struct FaviconCachingTests {
    @Test func iconsFromPrivatePagesAreNeverCached() {
        let f = Fixture()
        var saved: [String] = []
        f.manager.faviconChanged = { host, _ in saved.append(host) }
        let page = f.show(f.tab())
        page.simulateState {
            $0.url = URL(string: "https://a.example/")
            $0.favicon = Data([1])
        }
        page.simulateState { $0.title = "A" }  // same icon: not reported again
        let secret = f.manager.page(for: f.tab("https://s.example"), profile: f.profile, storage: .ephemeral(UUID())) as! FakePage
        secret.simulateState {
            $0.url = URL(string: "https://s.example/")
            $0.favicon = Data([2])
        }
        #expect(saved == ["a.example"])
    }
}

/// private windows.
@MainActor
@Suite("Private windows")
struct PrivateWindowTests {
    @Test func everyPageUsesTheWindowsSessionAndClosingEndsIt() {
        let f = Fixture()
        let session = UUID()
        f.manager.defaultStorage = .ephemeral(session)
        var visits = 0
        f.manager.pageVisited = { _, _, _, _ in visits += 1 }
        let a = f.show(f.tab("https://a.example"))
        let b = f.show(f.tab("https://b.example"))
        #expect(f.engine.configurations.map(\.storage) == [.ephemeral(session), .ephemeral(session)])
        a.simulateState {
            $0.url = URL(string: "https://a.example/next")
            $0.title = "A"
        }
        #expect(visits == 0, "no history from a private window")
        f.manager.discardAll()
        #expect(a.isClosed && b.isClosed, "closing the window closes every page, ending the session")
    }
}
