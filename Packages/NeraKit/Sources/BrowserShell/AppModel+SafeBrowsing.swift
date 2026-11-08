// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
public import Foundation
import Networking
public import SafeBrowsing
import SecurityPolicy

/// What the navigation policy reads from any thread (it decides navigations synchronously): the running service and
/// the addresses the user chose to open anyway.
final class SafeBrowsingSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var service: SafeBrowsing?
    private var allowed: Set<String> = []

    func set(_ service: SafeBrowsing?) { lock.withLock { self.service = service } }
    func allow(_ url: URL) { _ = lock.withLock { allowed.insert(url.absoluteString) } }

    /// The gate's rule: hold unless off or allowed by the user.
    func holds(_ url: URL) -> Bool {
        let (service, isAllowed) = lock.withLock { (self.service, allowed.contains(url.absoluteString)) }
        return !isAllowed && service?.holds(url) == true
    }
}

/// Safe Browsing's state in the app model.
public struct SafeBrowsingState {
    /// The running service (nil when off or without an API key).
    var service: SafeBrowsing?
    /// Read by every page's navigation policy.
    let gate = SafeBrowsingSwitch()
    /// How it reaches Google (tests use a fake; nil: the real API with the built-in key).
    var transport: (any SafeBrowsingTransport)?
    /// Where its lists are kept.
    var directory: URL?
    /// Warnings shown, by tab.
    var dangerousSites: [UUID: DangerousSite] = [:]
    /// Bumped when the setting changes (it lives in UserDefaults).
    var revision = 0
}

/// A page Safe Browsing warned about.
public struct DangerousSite: Equatable, Sendable {
    /// The address (exactly as navigated to).
    public let url: URL
    /// What it's listed for.
    public let threat: SafeBrowsingThreat
}

/// Phishing and malware protection: Google Safe Browsing in Local List mode for Chromium pages; WebKit pages
/// get Apple's built-in Fraudulent Website Warning. A main-frame navigation whose address matches a local list is
/// held by the navigation policy before anything is requested, until Google answers; then it's loaded once, or a
/// warning is shown instead (malware: no way past it).
extension AppModel {
    static let safeBrowsingKey = "NeraSafeBrowsing"

    /// Settings › Privacy: "Warn about dangerous sites" (on by default).
    public var warnsAboutDangerousSites: Bool {
        get {
            _ = safety.revision
            return UserDefaults.standard.object(forKey: Self.safeBrowsingKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.safeBrowsingKey)
            safety.revision += 1
            configureSafeBrowsing()
        }
    }

    /// Whether this build can check pages (it carries an API key).
    public var safeBrowsingAvailable: Bool { Self.safeBrowsingAPIKey != nil || safety.transport != nil }

    /// The API key built into the app (`NeraSafeBrowsingKey`; Debug builds may use `NERA_SAFE_BROWSING_KEY`).
    static var safeBrowsingAPIKey: String? {
        let built = Bundle.main.object(forInfoDictionaryKey: "NeraSafeBrowsingKey") as? String
        if let built, !built.isEmpty, !built.hasPrefix("$(") { return built }
        #if DEBUG
            return ProcessInfo.processInfo.environment["NERA_SAFE_BROWSING_KEY"]
        #else
            return nil
        #endif
    }

    /// Starts or stops Safe Browsing to match the setting.
    func configureSafeBrowsing(directory: URL? = nil, transport: (any SafeBrowsingTransport)? = nil) {
        if let directory { safety.directory = directory }
        if let transport { safety.transport = transport }
        let reach = safety.transport ?? Self.safeBrowsingAPIKey.map { GoogleSafeBrowsingTransport(key: $0) }
        guard warnsAboutDangerousSites, let reach, let folder = safety.directory else {
            safety.service?.stop()
            safety.service = nil
            safety.gate.set(nil)
            return
        }
        guard safety.service == nil else { return }
        let service = SafeBrowsing(directory: folder, transport: reach)
        safety.service = service
        safety.gate.set(service)
        service.start()
        // Chromium pages only: WebKit has Apple's own warning. Pages made from now on get the gate.
        let gate = safety.gate
        pages.safetyGate = SafetyGate { gate.holds($0) }
        pages.safetyGateEngines = [EngineID.chromium.rawValue]
        pages.safetyHold = { [weak self] page, url in self?.checkHeldNavigation(page, url: url) }
    }

    /// A navigation the gate held (nothing was requested): ask Google, then load it or show the warning.
    func checkHeldNavigation(_ page: any WebPage, url: URL) {
        guard let service = safety.service else { return page.load(url) }
        safety.dangerousSites[page.id] = nil
        Task { @MainActor [weak self] in
            let verdict = await service.verify(url)
            // Only if the page is still held at this address (not closed, not navigated elsewhere meanwhile).
            guard let self, self.pages.existingPage(for: page.id) === page, self.pages.heldNavigations[page.id] == url else { return }
            self.pages.releaseHold(page.id)
            switch verdict {
            case .threat(let threat): self.safety.dangerousSites[page.id] = DangerousSite(url: url, threat: threat)
            case .safe, .unavailable: page.load(url)  // not held again: the answer (or the fail-open pass) is cached
            }
        }
    }

    /// The warning over the current tab, if any.
    public var currentDangerousSite: DangerousSite? { state.selectedTabID.flatMap { safety.dangerousSites[$0] } }

    /// "Go Back": the previous page; with none, a tab closes and a Peek or Little Window page goes blank.
    public func leaveDangerousSite(_ pageID: UUID) {
        safety.dangerousSites[pageID] = nil
        guard let page = pages.existingPage(for: pageID) else { return }
        if page.state.canGoBack {
            page.goBack()
        } else if state.spaces.contains(where: { state.orderedTabs(in: $0).contains { $0.id == pageID } })
            || (state.currentProfile?.favorites.contains { $0.id == pageID } ?? false)
        {
            send(.tab(.close(pageID)))
        } else if let blank = URL(string: "about:blank") {
            page.load(blank)
        }
    }

    /// "Continue anyway" (phishing and unwanted software only; never malware): this address, this session.
    public func continueToDangerousSite(_ pageID: UUID) {
        guard let site = safety.dangerousSites[pageID], site.threat != .malware else { return }
        safety.dangerousSites[pageID] = nil
        safety.gate.allow(site.url)
        pages.existingPage(for: pageID)?.load(site.url)
    }
}

#if canImport(SwiftUI)
    import SwiftUI

    /// "Suspected deceptive site ahead" / "This site may harm your Mac": over a page Safe Browsing flagged (it was stopped before showing).
    /// The warning over whichever page Safe Browsing flagged (tabs, Split View panes, Peek, Little Windows).
    struct DangerousSiteOverlay: View {
        @Bindable var model: AppModel
        let pageID: UUID

        var body: some View {
            if let site = model.safety.dangerousSites[pageID] { DangerousSiteView(model: model, pageID: pageID, site: site) }
        }
    }

    struct DangerousSiteView: View {
        @Bindable var model: AppModel
        let pageID: UUID
        let site: DangerousSite

        private var title: String {
            switch site.threat {
            case .malware: "This site may harm your Mac"
            case .socialEngineering: "Suspected deceptive site ahead"
            default: "This site may try to install unwanted software"
            }
        }

        private var detail: String {
            let host = site.url.host() ?? site.url.absoluteString
            return switch site.threat {
            case .malware: "\(host) may install malware that can steal or damage your information."
            case .socialEngineering:
                "\(host) may trick you into doing something dangerous, like giving away a password or card number."
            default: "\(host) may try to trick you into installing software that harms your browsing."
            }
        }

        /// Where Google explains this kind of threat (required by the Safe Browsing usage guidelines).
        private var learnMore: URL? {
            let address =
                switch site.threat {
                case .socialEngineering: "https://support.google.com/webmasters/answer/6350487"
                case .malware: "https://developers.google.com/search/docs/advanced/security/malware"
                default: "https://www.google.com/about/unwanted-software-policy.html"
                }
            return URL(string: address)
        }

        var body: some View {
            ZStack {
                Color(red: 0.75, green: 0.13, blue: 0.13).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "exclamationmark.shield.fill").font(.system(size: 44)).foregroundStyle(.white)
                    Text(title).font(.largeTitle.weight(.semibold)).foregroundStyle(.white)
                    Text(detail).font(.title3).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
                    Text("Nera sent Google only a short fingerprint of this address. Warnings can be wrong.")
                        .font(.callout).foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 14) {
                        // Safe Browsing usage guidelines: attribution with a link to the advisory, and an explanation link.
                        if let advisory = URL(string: "https://developers.google.com/safe-browsing/v4/advisory") {
                            Link("Advisory provided by Google", destination: advisory)
                        }
                        if let learnMore { Link("Learn more", destination: learnMore) }
                    }
                    .font(.callout)
                    .tint(.white)
                    HStack(spacing: 16) {
                        Button("Go Back") { model.leaveDangerousSite(pageID) }
                            .keyboardShortcut(.defaultAction)
                            .controlSize(.large)
                            .accessibilityIdentifier("dangerous.back")
                        if site.threat != .malware {
                            Button("Continue anyway") { model.continueToDangerousSite(pageID) }
                                .linkButtonStyle()
                                .foregroundStyle(.white.opacity(0.85))
                                .accessibilityIdentifier("dangerous.continue")
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(40)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dangerous.page")
            .onAppear { AccessibilityNotification.Announcement("\(title). \(detail)").post() }
        }
    }
#endif
