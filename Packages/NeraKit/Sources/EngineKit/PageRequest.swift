// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
public import SecurityPolicy

/// Something a page needs the app to decide. Every case carries a ``Decision`` whose fallback is safe.
@MainActor
public enum PageRequest {
    /// Camera, microphone or another permission.
    case permission(PermissionRequest)
    /// Where to save a download (or cancel it).
    case download(DownloadRequest)
    /// `alert`, `confirm` or `prompt`.
    case dialog(DialogRequest)
    /// `<input type=file>`.
    case fileChooser(FileChooserRequest)
    /// HTTP Basic/Digest credentials.
    case authentication(AuthenticationRequest)
    /// The server's certificate isn't trusted.
    case certificateError(CertificateErrorRequest)
    /// Open a link in another app (mailto:, zoommtg:, …).
    case externalApp(ExternalAppRequest)
    /// The page opened a child page (target=_blank, `window.open`).
    case newPage(NewPageRequest)

    /// A stable identifier for this request (for UI identity and bookkeeping).
    public var id: UUID {
        switch self {
        case .permission(let r): r.id
        case .download(let r): r.id
        case .dialog(let r): r.id
        case .fileChooser(let r): r.id
        case .authentication(let r): r.id
        case .certificateError(let r): r.id
        case .externalApp(let r): r.id
        case .newPage(let r): r.id
        }
    }
}

// MARK: - Permission

/// A permission a page can ask for.
public enum PermissionKind: String, Hashable, Sendable, CaseIterable {
    /// Camera.
    case camera
    /// Microphone.
    case microphone
    /// Device motion and orientation (iOS).
    case motion
    /// Precise location.
    case location
    /// System notifications.
    case notifications
    /// Reading the clipboard.
    case clipboardRead
}

/// Answer to a ``PermissionRequest``.
public enum PermissionDecision: Sendable, Equatable {
    /// Allow.
    case grant
    /// Deny (the fallback).
    case deny
}

/// A page asks for one or more permissions.
@MainActor
public struct PermissionRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// Who is asking. Always shown to the user.
    public let origin: SecurityOrigin
    /// What is requested.
    public let kinds: Set<PermissionKind>
    /// Answer here. Fallback: ``PermissionDecision/deny``.
    public let decision: Decision<PermissionDecision>

    /// Creates a request.
    public init(origin: SecurityOrigin, kinds: Set<PermissionKind>, decision: Decision<PermissionDecision>) {
        self.origin = origin
        self.kinds = kinds
        self.decision = decision
    }
}

// MARK: - Download

/// Answer to a ``DownloadRequest``.
public enum DownloadDecision: Sendable, Equatable {
    /// Save to this file URL (must not exist yet).
    case saveTo(URL)
    /// Don't download (the fallback).
    case cancel
}

/// A download needs a destination.
@MainActor
public struct DownloadRequest: Identifiable {
    /// Identity; later ``DownloadEvent``s carry the same ID.
    public let id: UUID
    /// Where the file comes from.
    public let sourceURL: URL?
    /// The filename the server or page suggested. **Untrusted**: sanitize before use.
    public let suggestedFilename: String
    /// MIME type, if known.
    public let mimeType: String?
    /// Expected size in bytes, if known.
    public let expectedLength: Int64?
    /// Answer here. Fallback: ``DownloadDecision/cancel``.
    public let decision: Decision<DownloadDecision>

    /// Creates a request.
    public init(
        id: UUID = UUID(), sourceURL: URL?, suggestedFilename: String, mimeType: String?, expectedLength: Int64?,
        decision: Decision<DownloadDecision>
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.suggestedFilename = suggestedFilename
        self.mimeType = mimeType
        self.expectedLength = expectedLength
        self.decision = decision
    }
}

// MARK: - JavaScript dialogs

/// Kind of JavaScript dialog.
public enum DialogKind: Equatable, Sendable {
    /// `alert(message)`.
    case alert(message: String)
    /// `confirm(message)`.
    case confirm(message: String)
    /// `prompt(message, defaultText)`.
    case prompt(message: String, defaultText: String?)
}

/// Answer to a ``DialogRequest``.
public enum DialogResponse: Sendable, Equatable {
    /// OK. For prompts, the entered text.
    case ok(text: String?)
    /// Cancel (the fallback): `confirm` returns false, `prompt` returns null.
    case cancel
}

/// A page wants to show a JavaScript dialog.
@MainActor
public struct DialogRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// Who is asking. Shown so a page can't pose as the browser or another site.
    public let origin: SecurityOrigin
    /// The dialog.
    public let kind: DialogKind
    /// Answer here. Fallback: ``DialogResponse/cancel``.
    public let decision: Decision<DialogResponse>

    /// Creates a request.
    public init(origin: SecurityOrigin, kind: DialogKind, decision: Decision<DialogResponse>) {
        self.origin = origin
        self.kind = kind
        self.decision = decision
    }
}

// MARK: - File chooser

/// A page wants the user to pick files.
@MainActor
public struct FileChooserRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// Whether several files may be chosen.
    public let allowsMultiple: Bool
    /// Whether folders may be chosen.
    public let allowsDirectories: Bool
    /// Answer with the chosen file URLs. Fallback: `nil` (cancelled).
    public let decision: Decision<[URL]?>

    /// Creates a request.
    public init(allowsMultiple: Bool, allowsDirectories: Bool, decision: Decision<[URL]?>) {
        self.allowsMultiple = allowsMultiple
        self.allowsDirectories = allowsDirectories
        self.decision = decision
    }
}

// MARK: - HTTP authentication

/// Answer to an ``AuthenticationRequest``.
public enum AuthenticationResponse: Sendable, Equatable {
    /// Sign in with these credentials.
    case credentials(user: String, password: String)
    /// Cancel (the fallback); the page shows the server's 401 response.
    case cancel
}

/// A server asks for HTTP Basic/Digest credentials.
@MainActor
public struct AuthenticationRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// The server asking.
    public let origin: SecurityOrigin
    /// The server's realm text. **Untrusted**: display as quoted server text, not as browser UI.
    public let realm: String?
    /// Whether the credentials would be sent over an unencrypted connection.
    public let isInsecure: Bool
    /// How many times credentials were already rejected.
    public let previousFailureCount: Int
    /// Answer here. Fallback: ``AuthenticationResponse/cancel``.
    public let decision: Decision<AuthenticationResponse>

    /// Creates a request.
    public init(
        origin: SecurityOrigin, realm: String?, isInsecure: Bool, previousFailureCount: Int, decision: Decision<AuthenticationResponse>
    ) {
        self.origin = origin
        self.realm = realm
        self.isInsecure = isInsecure
        self.previousFailureCount = previousFailureCount
        self.decision = decision
    }
}

// MARK: - Certificate errors

/// Why a certificate was rejected.
public enum CertificateErrorReason: Equatable, Sendable {
    /// Expired or not yet valid.
    case dateInvalid
    /// Issued for a different host.
    case nameMismatch
    /// Not chained to a trusted root (self-signed, unknown CA).
    case untrusted
    /// Revoked by its issuer.
    case revoked
    /// Any other failure.
    case other(String)
}

/// Answer to a ``CertificateErrorRequest``.
public enum CertificateDecision: Sendable, Equatable {
    /// Go back to safety (the fallback).
    case reject
    /// Continue anyway. Only honored when ``CertificateErrorRequest/isBypassAllowed`` is `true`.
    case proceed
}

/// The server's certificate isn't trusted. The UI shows a full-page interstitial (SR-002).
@MainActor
public struct CertificateErrorRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// The URL that failed.
    public let url: URL
    /// Why.
    public let reason: CertificateErrorReason
    /// `false` for HSTS hosts and for engines without ``EngineCapability/certificateErrorBypass``.
    /// When `false`, the UI must not offer "continue anyway".
    public let isBypassAllowed: Bool
    /// Answer here. Fallback: ``CertificateDecision/reject``.
    public let decision: Decision<CertificateDecision>

    /// Creates a request.
    public init(url: URL, reason: CertificateErrorReason, isBypassAllowed: Bool, decision: Decision<CertificateDecision>) {
        self.url = url
        self.reason = reason
        self.isBypassAllowed = isBypassAllowed
        self.decision = decision
    }
}

// MARK: - External apps

/// Answer to an ``ExternalAppRequest``.
public enum ExternalAppDecision: Sendable, Equatable {
    /// Open the link in its app (done by the app, not the engine).
    case open
    /// Don't (the fallback).
    case block
}

/// A link wants to open another app.
@MainActor
public struct ExternalAppRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// The link, e.g. `mailto:` or `zoommtg:`.
    public let url: URL
    /// Who is asking.
    public let origin: SecurityOrigin
    /// Answer here. Fallback: ``ExternalAppDecision/block``.
    public let decision: Decision<ExternalAppDecision>

    /// Creates a request.
    public init(url: URL, origin: SecurityOrigin, decision: Decision<ExternalAppDecision>) {
        self.url = url
        self.origin = origin
        self.decision = decision
    }
}

// MARK: - Child pages

/// How a child page wants to be shown.
public enum NewPageDisposition: Sendable, Equatable {
    /// In a new, focused tab.
    case foregroundTab
    /// In a new tab without focusing it (e.g. ⌘-click).
    case backgroundTab
    /// In a small popup window (e.g. `window.open` with size features, typical for OAuth).
    case popup
}

/// Answer to a ``NewPageRequest``.
public enum NewPageDecision: Sendable, Equatable {
    /// Keep the child page; the app shows it.
    case adopt
    /// Close the child page (the fallback).
    case discard
}

/// A page opened a child page. The engine already created ``page`` (with its opener relationship
/// intact, so `window.opener` and OAuth flows work). The app must adopt it or it is closed.
@MainActor
public struct NewPageRequest: Identifiable {
    /// Request identity.
    public let id = UUID()
    /// The new page, already created by the engine.
    public let page: any WebPage
    /// The URL the child is opening, if known.
    public let url: URL?
    /// How the page wants to be shown.
    public let disposition: NewPageDisposition
    /// Answer here. Fallback: ``NewPageDecision/discard``.
    public let decision: Decision<NewPageDecision>

    /// Creates a request.
    public init(page: any WebPage, url: URL?, disposition: NewPageDisposition, decision: Decision<NewPageDecision>) {
        self.page = page
        self.url = url
        self.disposition = disposition
        self.decision = decision
    }
}
