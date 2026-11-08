// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import SecurityPolicy
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// Shows the oldest pending request of the selected tab. Every prompt names the requesting origin
/// (SR-041), and every path out of a prompt resolves its decision (unanswered ones fall back to deny).
struct PageRequestView: View {
    let request: PageRequest
    let model: AppModel

    var body: some View {
        switch request {
        case .dialog(let r): DialogCard(request: r) { model.finish(request) }
        case .permission(let r): PermissionCard(request: r) { model.answerPermission(r, $0, remember: $1) }
        case .authentication(let r): AuthenticationCard(request: r) { model.finish(request) }
        case .externalApp(let r):
            ExternalAppCard(request: r, open: { model.openExternally(r.url) }, done: { model.finish(request) })
        case .certificateError(let r): CertificateErrorView(request: r) { model.finish(request) }
        case .fileChooser(let r): FileChooserPresenter(request: r) { model.finish(request) }
        case .download(let r):  // only dangerous downloads are queued (SEC-045)
            DangerousDownloadCard(request: r, reason: model.downloadRiskReason(r)) { keep in
                if keep { model.confirmDangerousDownload(r) } else { model.finish(request) }
            }
        case .newPage:
            EmptyView()  // Handled by PageManager; never queued.
        }
    }
}

// MARK: - Card chrome

/// A prompt anchored to the top of the web content, visually attributed to the page's origin.
private struct PromptCard<Content: View, Actions: View>: View {
    let origin: SecurityOrigin
    let headline: String
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Label(origin.description, systemImage: origin.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("request.origin")
                Text(headline).font(.headline)
                content
                HStack {
                    Spacer()
                    actions
                }
            }
            .padding(18)
            .frame(maxWidth: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.top, 24)
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("request.card")
    }
}

// MARK: - Dialogs

private struct DialogCard: View {
    let request: DialogRequest
    let done: () -> Void
    @State private var text = ""

    var body: some View {
        PromptCard(origin: request.origin, headline: "\(request.origin) says") {
            switch request.kind {
            case .alert(let message), .confirm(let message):
                Text(message).textSelection(.enabled).accessibilityIdentifier("request.message")
            case .prompt(let message, let defaultText):
                Text(message).accessibilityIdentifier("request.message")
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { text = defaultText ?? "" }
            }
        } actions: {
            if case .alert = request.kind {
                Button("OK") { answer(.ok(text: nil)) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("request.ok")
            } else {
                Button("Cancel") { answer(.cancel) }.keyboardShortcut(.cancelAction)
                Button("OK") { answer(.ok(text: text)) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("request.ok")
            }
        }
    }

    private func answer(_ response: DialogResponse) {
        request.decision.resolve(response)
        done()
    }
}

// MARK: - Permissions

private struct PermissionCard: View {
    let request: PermissionRequest
    /// Decision, and whether to remember it.
    let answer: (PermissionDecision, Bool) -> Void

    private var what: String {
        let names = request.kinds.sorted { $0.rawValue < $1.rawValue }.map { kind in
            switch kind {
            case .camera: "camera"
            case .microphone: "microphone"
            case .motion: "motion and orientation sensors"
            case .location: "location"
            case .notifications: "notifications"
            case .clipboardRead: "clipboard"
            }
        }
        return names.joined(separator: " and ")
    }

    var body: some View {
        PromptCard(origin: request.origin, headline: "Allow \(request.origin) to use your \(what)?") {
            Text("Change it any time from the site settings button in the address bar.").font(.callout).foregroundStyle(.secondary)
        } actions: {
            Button("Don't Allow") { answer(.deny, true) }.keyboardShortcut(.cancelAction)
            Button("Allow This Time") { answer(.grant, false) }.accessibilityIdentifier("request.allowOnce")
            Button("Allow") { answer(.grant, true) }.accessibilityIdentifier("request.allow")
        }
    }

}

// MARK: - HTTP authentication

private struct AuthenticationCard: View {
    let request: AuthenticationRequest
    let done: () -> Void
    @State private var user = ""
    @State private var password = ""

    var body: some View {
        PromptCard(origin: request.origin, headline: "Sign in to \(request.origin)") {
            if let realm = request.realm, !realm.isEmpty {
                Text("The site says: “\(realm)”").font(.callout).foregroundStyle(.secondary)
            }
            if request.isInsecure {
                Text("Your password will be sent unencrypted.").font(.callout).foregroundStyle(.orange)
            }
            if request.previousFailureCount > 0 {
                Text("That username or password didn't work.").font(.callout).foregroundStyle(.red)
            }
            TextField("Username", text: $user).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
        } actions: {
            Button("Cancel") { answer(.cancel) }.keyboardShortcut(.cancelAction)
            Button("Sign In") { answer(.credentials(user: user, password: password)) }
                .keyboardShortcut(.defaultAction)
                .disabled(user.isEmpty)
        }
    }

    private func answer(_ response: AuthenticationResponse) {
        request.decision.resolve(response)
        done()
    }
}

// MARK: - External apps

private struct ExternalAppCard: View {
    let request: ExternalAppRequest
    let open: () -> Void
    let done: () -> Void

    var body: some View {
        PromptCard(origin: request.origin, headline: "Open this link in another app?") {
            Text(request.url.scheme.map { "\($0): link" } ?? "Link").font(.callout).foregroundStyle(.secondary)
        } actions: {
            Button("Cancel") { finish(.block) }.keyboardShortcut(.cancelAction)
            Button("Open") {
                finish(.open)
                open()
            }
        }
    }

    private func finish(_ decision: ExternalAppDecision) {
        request.decision.resolve(decision)
        done()
    }
}

// MARK: - Certificate errors

/// Full-page interstitial. "Visit anyway" only exists when the engine allows a bypass for this host.
private struct CertificateErrorView: View {
    let request: CertificateErrorRequest
    let done: () -> Void

    private var explanation: String {
        switch request.reason {
        case .dateInvalid: "The site's certificate has expired or isn't valid yet."
        case .nameMismatch: "The site's certificate was issued for a different website."
        case .untrusted: "The site's certificate isn't from a trusted authority."
        case .revoked: "The site's certificate was revoked by its issuer."
        case .other(let why): why
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.red)
            Text("This connection isn't private").font(.title2.weight(.semibold))
            Text("\(request.url.host() ?? "This site") might be pretending to be a site you trust. \(explanation)")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack {
                if request.isBypassAllowed {
                    Button("Visit Anyway (Unsafe)") { finish(.proceed) }
                }
                Button("Go Back") { finish(.reject) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityIdentifier("certificateError")
    }

    private func finish(_ decision: CertificateDecision) {
        request.decision.resolve(decision)
        done()
    }
}

// MARK: - File chooser

private struct FileChooserPresenter: View {
    let request: FileChooserRequest
    let done: () -> Void
    #if !os(macOS)
        @State private var isPresented = true
    #endif

    var body: some View {
        #if os(macOS)
            Color.clear.task {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = request.allowsMultiple
                panel.canChooseDirectories = request.allowsDirectories
                panel.canChooseFiles = true
                let response = await panel.begin()
                request.decision.resolve(response == .OK ? panel.urls : nil)
                done()
            }
        #else
            Color.clear.fileImporter(
                isPresented: $isPresented, allowedContentTypes: [.item],
                allowsMultipleSelection: request.allowsMultiple
            ) { result in
                request.decision.resolve(try? result.get())
                done()
            }
        #endif
    }
}

// MARK: - Dangerous download

private struct DangerousDownloadCard: View {
    let request: DownloadRequest
    let reason: String
    let decide: (_ keep: Bool) -> Void

    var body: some View {
        PromptCard(origin: SecurityOrigin(url: request.sourceURL), headline: "Download “\(request.suggestedFilename)”?") {
            Text(reason).font(.callout)
            Text("Only keep it if you trust where it came from. Nera never opens downloads by itself.")
                .font(.callout).foregroundStyle(.secondary)
        } actions: {
            Button("Cancel") { decide(false) }.keyboardShortcut(.cancelAction)
            Button("Download Anyway") { decide(true) }.accessibilityIdentifier("request.downloadAnyway")
        }
    }
}
