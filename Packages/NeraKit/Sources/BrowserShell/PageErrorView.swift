// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import EngineKit
public import PageLifecycle
import SecurityPolicy
import SwiftUI

extension AppModel {
    /// The current tab's failed load, if its last load failed.
    public var currentLoadFailure: LoadFailure? { state.selectedTabID.flatMap { pages.loadFailures[$0] } }

    /// The current tab is showing the engine's own certificate question (WebKit).
    var isAskingAboutCertificate: Bool {
        if case .certificateError? = currentRequest { return true }
        return false
    }

    /// Try Again: loads the failed address again.
    public func retryFailedLoad() {
        guard let id = state.selectedTabID, let failure = pages.loadFailures[id], let url = failure.url else { return }
        pages.clearLoadFailure(id)
        selectedPage?.load(url)
    }

    /// Continue to Site (Not Secure): allows the host over plain HTTP for this session and loads the `http:` address.
    public func continueOverHTTP() {
        guard let id = state.selectedTabID, case .secureConnectionUnavailable(let http)? = pages.loadFailures[id]?.kind,
            let host = http.host()
        else { return }
        pages.policy.allowedOverHTTP.insert(host)
        pages.clearLoadFailure(id)
        selectedPage?.load(http)
    }

    /// Go Back from an error page, or close the tab when there's nothing to go back to.
    public func leaveFailedPage() {
        guard let id = state.selectedTabID else { return }
        pages.clearLoadFailure(id)
        if pageNavigation.canGoBack { goBack() } else { closeSelectedTab() }
    }
}

/// Shown over a page whose load failed: a certificate problem (never bypassable), a site that can't be reached, or
/// a site that doesn't offer a secure connection (with a per-site choice to continue over HTTP).
struct PageErrorView: View {
    @Bindable var model: AppModel
    let failure: LoadFailure

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(tint)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) { buttons }
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page.error")
    }

    private var host: String { failure.url.map { DisplayURL.short($0) } ?? "This site" }

    private var symbol: String {
        switch failure.kind {
        case .certificate: "lock.trianglebadge.exclamationmark"
        case .unreachable: "wifi.exclamationmark"
        case .secureConnectionUnavailable: "lock.open"
        }
    }

    private var tint: Color {
        if case .certificate = failure.kind { return .red }
        return .secondary
    }

    private var title: String {
        switch failure.kind {
        case .certificate: "This connection isn't private"
        case .unreachable: "Can't reach \(host)"
        case .secureConnectionUnavailable: "\(host) doesn't offer a secure connection"
        }
    }

    private var message: String {
        switch failure.kind {
        case .certificate(let reason):
            "Someone could be pretending to be \(host) to steal your passwords or other information. " + explanation(reason)
                + " Nera won't open it."
        case .unreachable(let description):
            "Check your internet connection and the address. \(description)"
        case .secureConnectionUnavailable:
            "Nera tried a secure (HTTPS) connection and the site didn't answer. If you continue, what you see and send on "
                + "this site can be read or changed by others on the network."
        }
    }

    @ViewBuilder private var buttons: some View {
        switch failure.kind {
        case .certificate:
            Button("Go Back") { model.leaveFailedPage() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("page.error.back")
        case .unreachable:
            Button("Go Back") { model.leaveFailedPage() }
            Button("Try Again") { model.retryFailedLoad() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("page.error.retry")
        case .secureConnectionUnavailable:
            Button("Continue to Site (Not Secure)") { model.continueOverHTTP() }
                .accessibilityIdentifier("page.error.continueHTTP")
            Button("Go Back") { model.leaveFailedPage() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private func explanation(_ reason: CertificateErrorReason) -> String {
        switch reason {
        case .dateInvalid: "Its certificate has expired or isn't valid yet."
        case .nameMismatch: "Its certificate was issued for a different website."
        case .untrusted: "Its certificate isn't from a trusted authority."
        case .revoked: "Its certificate was revoked by its issuer."
        case .other(let why): why
        }
    }
}
