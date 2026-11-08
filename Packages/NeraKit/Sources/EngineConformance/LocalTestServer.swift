// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation
import Network
public import Security

/// Local HTTP + HTTPS server for the security conformance suite: no external sites, loopback only.
///
/// Certificates are generated per run with the system `openssl` (nothing private is committed):
/// a throwaway test CA, a valid leaf for `127.0.0.1`/`localhost`, an expired leaf, a leaf for the wrong
/// host, and a self-signed leaf. Each TLS mode listens on its own port. Engines trust the test CA only in
/// Debug test runs (WebKit: ``caCertificate`` as an extra anchor; Chromium: ``validSPKIHash``).
///
/// Routes (all GET): `/page?title=`, `/csp`, `/csp.js`, `/nosniff`, `/sniff.js`, `/after.js`, `/mixed?host=`,
/// `/mixed.js`, `/setcookie?v=&samesite=`, `/cookies`, `/xsite?target=`, `/pixel`, `/storage?set=`,
/// `/cacheable`, `/popup`, `/redirect?to=`.
public final class LocalTestServer: @unchecked Sendable {
    /// Which certificate an HTTPS port presents.
    public enum TLSMode: String, CaseIterable, Sendable {
        /// Signed by the test CA for 127.0.0.1 and localhost.
        case valid
        /// Signed by the test CA, expired in 2020.
        case expired
        /// Signed by the test CA for `wrong.example` only.
        case wrongHost
        /// Self-signed for 127.0.0.1.
        case selfSigned
    }

    /// One received request.
    public struct Request: Sendable {
        /// Path without query.
        public var path: String
        /// The `Cookie` header, if any.
        public var cookie: String?
    }

    /// Plain HTTP port.
    public private(set) var httpPort: UInt16 = 0
    /// HTTPS port per certificate mode.
    public private(set) var httpsPorts: [TLSMode: UInt16] = [:]
    /// The test CA (DER), to add as an extra trust anchor in Debug test runs.
    public let caCertificate: SecCertificate
    /// Base64 SHA-256 of the valid leaf's SubjectPublicKeyInfo (Chromium's SPKI allow-list format).
    public let validSPKIHash: String

    private var listeners: [NWListener] = []
    private let queue = DispatchQueue(label: "dev.nera.local-test-server")
    private let lock = NSLock()
    private var log: [Request] = []

    /// The shared server for a test process (created on first use). `nil` if it couldn't start.
    public static let shared: LocalTestServer? = try? LocalTestServer()

    /// Generates certificates and starts listening. Throws if openssl, PKCS#12 import or a listener fails.
    public init() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nera-test-server-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pki = try TestPKI(directory: dir)
        caCertificate = pki.ca
        validSPKIHash = pki.validSPKIHash
        httpPort = try startListener(identity: nil)
        for mode in TLSMode.allCases { httpsPorts[mode] = try startListener(identity: pki.identities[mode]) }
    }

    /// Stops every listener.
    public func stop() { for l in listeners { l.cancel() } }

    /// A URL on this server. `tls` picks an HTTPS port; `host` can be `localhost` for cross-site tests.
    public func url(_ pathAndQuery: String, tls: TLSMode? = nil, host: String = "127.0.0.1") -> URL {
        let port = tls.map { httpsPorts[$0] ?? 0 } ?? httpPort
        return URL(string: "\(tls == nil ? "http" : "https")://\(host):\(port)\(pathAndQuery)")!
    }

    /// Requests received for `path`, in order.
    public func requests(_ path: String) -> [Request] {
        lock.lock()
        defer { lock.unlock() }
        return log.filter { $0.path == path }
    }

    // MARK: Listening

    private func startListener(identity: SecIdentity?) throws -> UInt16 {
        let parameters: NWParameters
        if let identity, let secIdentity = sec_identity_create(identity) {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        } else {
            parameters = .tcp
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)  // loopback only
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard let port = listener.port?.rawValue, port != 0 else { throw CocoaError(.fileReadUnknown) }
        listeners.append(listener)
        return port
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                if head.hasPrefix("GET /slow-download") { return self.streamSlowDownload(connection, head: head) }
                let response = self.respond(to: head)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if done || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    /// A 16×16 red PNG served at `/icon.png`.
    public static let iconPNG =
        "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR4nGO4o6FBEmIY1TCqYfhqAAAyBCwQhvh37QAAAABJRU5ErkJggg=="

    /// `/slow-download`: a 4 MB attachment sent 64 KB every 100 ms (about 6 s), so a test can cancel it midway.
    private func streamSlowDownload(_ connection: NWConnection, head: String) {
        lock.lock()
        log.append(Request(path: "/slow-download", cookie: nil))
        lock.unlock()
        let chunk = Data(repeating: 0x4C, count: 64 * 1024)
        let chunks = 64
        let header =
            "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(chunk.count * chunks)\r\n"
            + "Content-Disposition: attachment; filename=\"slow.bin\"\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        @Sendable func send(_ index: Int) {
            guard index < chunks else {
                return connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            }
            let data = index == 0 ? Data(header.utf8) + chunk : chunk
            connection.send(
                content: data,
                completion: .contentProcessed { [queue] error in
                    guard error == nil else { return connection.cancel() }  // the client went away (cancelled)
                    queue.asyncAfter(deadline: .now() + 0.1) { send(index + 1) }
                })
        }
        send(0)
    }

    // MARK: Routes

    private func respond(to head: String) -> Data {
        let lines = head.components(separatedBy: "\r\n")
        let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let components = URLComponents(string: target)
        let path = components?.path ?? "/"
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let cookie = lines.first { $0.lowercased().hasPrefix("cookie:") }.map {
            String($0.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        lock.lock()
        log.append(Request(path: path, cookie: cookie))
        lock.unlock()

        func html(_ body: String, headers: [String: String] = [:]) -> Data { reply(200, "text/html; charset=utf-8", body, headers) }
        func js(_ body: String, headers: [String: String] = [:]) -> Data { reply(200, "text/javascript", body, headers) }

        if path == "/video.mp4" {
            // C21: media players fetch video in byte ranges (WebKit requires them).
            let range = lines.first { $0.lowercased().hasPrefix("range:") }.map { String($0.dropFirst(6)) }
            return video(range: range)
        }
        if let response = featureRoute(path) { return response }
        switch path {
        case "/video":
            let src = query["src"] == "/missing.mp4" ? "/missing.mp4" : "/video.mp4"
            return html("<title>video</title><video src=\"\(src)\" preload=auto muted playsinline></video>")
        case "/page":
            let title = query["title"] ?? "page"
            return html("<title>\(title)</title><p>\(title)</p>")
        case "/csp":
            return html(
                "<title>CSP</title><script>document.title='INLINE RAN'</script><script src=\"/csp.js\"></script>",
                headers: ["Content-Security-Policy": "script-src 'self'"])
        case "/csp.js":
            return js("if (document.title !== 'INLINE RAN') document.title = 'CSP OK';")
        case "/nosniff":
            return html("<title>NOSNIFF</title><script src=\"/sniff.js\"></script><script src=\"/after.js\"></script>")
        case "/sniff.js":
            return reply(200, "text/plain", "document.title = 'SNIFFED';", ["X-Content-Type-Options": "nosniff"])
        case "/after.js":
            return js("if (document.title !== 'SNIFFED') document.title = 'NOSNIFF OK';")
        case "/mixed":
            // `host` lets an engine that treats loopback as trustworthy (Chromium) use a non-loopback test name.
            let insecure = url("/mixed.js", host: query["host"] ?? "127.0.0.1")
            return html(
                "<title>MIXED</title><script src=\"\(insecure.absoluteString)\"></script>"
                    + "<script>setTimeout(function(){ if (document.title !== 'MIXED RAN') document.title = 'MIXED BLOCKED'; }, 600)</script>"
            )
        case "/mixed.js":
            return js("document.title = 'MIXED RAN';")
        case "/setcookie":
            let sameSite = query["samesite"].map { "; SameSite=\($0)" } ?? ""
            return html("<title>SET \(query["v"] ?? "")</title>", headers: ["Set-Cookie": "nera=\(query["v"] ?? "x"); Path=/\(sameSite)"])
        case "/cookies":
            return html("<title>COOKIES \(cookie ?? "none")</title>")
        case "/xsite":
            let target = query["target"] ?? ""
            return html(
                "<title>XSITE</title><img src=\"\(target)\" onload=\"document.title='XSITE DONE'\" onerror=\"document.title='XSITE DONE'\">"
            )
        case "/pixel":
            let gif = Data(base64Encoded: "R0lGODlhAQABAAAAACH5BAEAAAAALAAAAAABAAEAAAIBAAA=") ?? Data()
            return reply(200, "image/gif", gif, [:])
        case "/storage":
            return html(
                "<title>STORAGE</title><script>var p = new URLSearchParams(location.search); if (p.get('set')) localStorage.setItem('k', p.get('set'));"
                    + " document.title = 'STORAGE ' + (localStorage.getItem('k') || 'none');</script>")
        case "/cacheable":
            return html("<title>CACHE</title>", headers: ["Cache-Control": "max-age=600"])
        case "/popup":
            return html("<title>POPUP</title><script>window.open('/page?title=child')</script>")
        case "/redirect":
            return reply(302, "text/plain", "", ["Location": query["to"] ?? "/"])
        default:
            return reply(404, "text/plain", "not found", [:])
        }
    }

    /// Routes for feature conformance (extensions X-cases, favicons C19).
    private func featureRoute(_ path: String) -> Data? {
        func html(_ body: String) -> Data { reply(200, "text/html; charset=utf-8", body, [:]) }
        switch path {
        case "/ext-page":
            // X01: does an installed content-blocking extension work in this page's (profile) context?
            return html(
                "<title>EXT WAIT</title><script>const p = location.port;"
                    + " const mark = document.documentElement.dataset.neraTestExtension ? 'ON' : 'OFF';"
                    + " Promise.allSettled([fetch(`http://ok.nera.test:${p}/ok-probe`, {mode: 'no-cors'}),"
                    + " fetch(`http://ads.nera.test:${p}/ad-probe`, {mode: 'no-cors'})])"
                    + ".then(rs => { document.title = `EXT ${mark} ` + rs.map(r => r.status === 'fulfilled' ? 'ok' : 'err').join(' '); });"
                    + "</script>")
        case "/webauthn":
            // P-cases: available → create → get through the engine's WebAuthn path; the title reports the result.
            return html(
                "<title>WA WAIT</title><script>(async () => { try {"
                    + " const rp = new URLSearchParams(location.search).get('rp');"
                    + " const avail = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();"
                    + " const c = await navigator.credentials.create({publicKey: {challenge: new Uint8Array(32), rp: {name: rp},"
                    + " user: {id: new Uint8Array(8), name: 'probe', displayName: 'Probe'}, pubKeyCredParams: [{type: 'public-key', alg: -7}]}});"
                    + " const a = await navigator.credentials.get({publicKey: {challenge: new Uint8Array(32)}});"
                    + " document.title = ['WA OK', c.type, c.id, c.response.attestationObject.byteLength, a.response.signature.byteLength, avail].join(' ');"
                    + " } catch (e) { document.title = 'WA ERR ' + e.name + ': ' + e.message; } })();</script>")
        case "/ok-probe", "/ad-probe":
            return reply(200, "text/plain", "probe", [:])
        case "/icon-page":
            return html("<title>ICON</title><link rel=\"icon\" type=\"image/png\" href=\"/icon.png\"><p>icon</p>")
        case "/icon.png":
            return reply(200, "image/png", Data(base64Encoded: Self.iconPNG) ?? Data(), [:])
        default:
            return nil
        }
    }

    /// The H.264 sample, whole or the byte range asked for (`bytes=a-b`).
    private func video(range: String?) -> Data {
        let body = Data(base64Encoded: String(EngineConformance.h264Video.split(separator: ",").last ?? "")) ?? Data()
        let spec = range?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "bytes=", with: "")
        guard let spec, let dash = spec.firstIndex(of: "-"), let start = Int(spec[..<dash]), start < body.count else {
            return reply(200, "video/mp4", body, ["Accept-Ranges": "bytes"])
        }
        let end = min(Int(spec[spec.index(after: dash)...]) ?? body.count - 1, body.count - 1)
        return reply(
            206, "video/mp4", body.subdata(in: start..<(end + 1)),
            ["Accept-Ranges": "bytes", "Content-Range": "bytes \(start)-\(end)/\(body.count)"])
    }

    private func reply(_ status: Int, _ type: String, _ body: String, _ headers: [String: String]) -> Data {
        reply(status, type, Data(body.utf8), headers)
    }

    private func reply(_ status: Int, _ type: String, _ body: Data, _ headers: [String: String]) -> Data {
        let reason = [200: "OK", 206: "Partial Content", 302: "Found"][status] ?? "Not Found"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if headers["Cache-Control"] == nil { head += "Cache-Control: no-store\r\n" }
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}

/// The run's throwaway PKI, made with the system openssl (LibreSSL).
private struct TestPKI {
    let ca: SecCertificate
    let identities: [LocalTestServer.TLSMode: SecIdentity]
    let validSPKIHash: String

    init(directory dir: URL) throws {
        func openssl(_ args: [String]) throws -> Data {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            p.arguments = args
            p.currentDirectoryURL = dir
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: ["openssl": args.joined(separator: " ")]) }
            return data
        }
        func write(_ name: String, _ text: String) throws {
            try text.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
        }

        try openssl([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem", "-days", "2", "-subj",
            "/CN=Nera Test CA", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
        ]).discard()
        try write("ip.ext", "subjectAltName=IP:127.0.0.1,DNS:localhost\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n")
        try write("wrong.ext", "subjectAltName=DNS:wrong.example\nextendedKeyUsage=serverAuth\nbasicConstraints=CA:FALSE\n")
        try write(
            "ca.cnf",
            "[ca]\ndefault_ca=d\n[d]\ndatabase=index.txt\nnew_certs_dir=.\nserial=serial\ndefault_md=sha256\npolicy=p\n[p]\ncommonName=supplied\n"
        )
        try write("index.txt", "")
        try write("serial", "1000\n")

        for name in ["valid", "old", "wrong", "self"] {  // one key each: Chromium's test trust is keyed on the public key
            try openssl(["req", "-newkey", "rsa:2048", "-nodes", "-keyout", "\(name).key", "-out", "\(name).csr", "-subj", "/CN=127.0.0.1"])
                .discard()
        }
        try openssl([
            "x509", "-req", "-in", "valid.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-out", "valid.pem", "-days", "2",
            "-extfile", "ip.ext",
        ]).discard()
        try openssl([
            "x509", "-req", "-in", "wrong.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial", "-out", "wrong.pem", "-days", "2",
            "-extfile", "wrong.ext",
        ]).discard()
        try openssl([
            "ca", "-batch", "-config", "ca.cnf", "-cert", "ca.pem", "-keyfile", "ca.key", "-in", "old.csr", "-out", "expired.pem",
            "-startdate", "20200101000000Z", "-enddate", "20200102000000Z", "-extfile", "ip.ext", "-notext",
        ]).discard()
        try openssl(["x509", "-req", "-in", "self.csr", "-signkey", "self.key", "-out", "self.pem", "-days", "2", "-extfile", "ip.ext"])
            .discard()

        func identity(cert: String, key: String) throws -> SecIdentity {
            try openssl([
                "pkcs12", "-export", "-inkey", key, "-in", cert, "-out", "\(cert).p12", "-passout", "pass:nera", "-certpbe",
                "PBE-SHA1-3DES",
                "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1",
            ]).discard()
            let data = try Data(contentsOf: dir.appending(path: "\(cert).p12"))
            var options: [String: Any] = [kSecImportExportPassphrase as String: "nera"]
            if #available(macOS 15.0, iOS 18.0, *) { options[kSecImportToMemoryOnly as String] = true }  // never touch the Keychain
            var items: CFArray?
            guard SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess,
                let first = (items as? [[String: Any]])?.first, let identity = first[kSecImportItemIdentity as String]
            else { throw CocoaError(.fileReadCorruptFile) }
            return identity as! SecIdentity  // swiftlint:disable:this force_cast
        }
        identities = [
            .valid: try identity(cert: "valid.pem", key: "valid.key"),
            .expired: try identity(cert: "expired.pem", key: "old.key"),
            .wrongHost: try identity(cert: "wrong.pem", key: "wrong.key"),
            .selfSigned: try identity(cert: "self.pem", key: "self.key"),
        ]
        let caDER = try openssl(["x509", "-in", "ca.pem", "-outform", "der"])
        guard let ca = SecCertificateCreateWithData(nil, caDER as CFData) else { throw CocoaError(.fileReadCorruptFile) }
        self.ca = ca
        let spki = try openssl(["x509", "-pubkey", "-noout", "-in", "valid.pem"])
        try spki.write(to: dir.appending(path: "valid.pub"))
        let der = try openssl(["pkey", "-pubin", "-in", "valid.pub", "-outform", "der"])
        try der.write(to: dir.appending(path: "valid.spki"))
        let digest = try openssl(["dgst", "-sha256", "-binary", "valid.spki"])
        validSPKIHash = digest.base64EncodedString()
    }
}

extension Data {
    fileprivate func discard() {}
}
