//
//  SessionTests.swift
//  CypressTests
//
//  #158 step 3 (spec §5.8). What these tests are actually about, in one sentence:
//
//      **a 401 must never reach an outbox item.**
//
//  `APIError.unauthorized.retryable` is `false`; `OutboxRetryPolicy.nextState` reads exactly that
//  and moves a non-retryable item to `.failed` immediately; `OutboxViewState` then prints "Sign in
//  to send this" — to somebody who is signed in. So the assertions below do not stop at "the right
//  error type was thrown": several of them hand the thrown error to `OutboxRetryPolicy` and check
//  the state the queue would really take, because that is the sentence the spec makes and the type
//  name is only a proxy for it.
//
//  Nothing here touches the network. `ScriptedHTTP` is the far side, and every response is a literal
//  written beside the assertion that reads it — except the error envelopes, which are the bytes the
//  deployed service really returned (see `LiveEnvelopes`).
//

import Foundation
import Security
import Testing
@testable import Cypress

// MARK: - Doubles

/// One scripted far side. `handler` sees the request and its index, so a test can answer the first
/// call differently from the second — which is the whole shape of "refresh once and replay".
private actor ScriptedHTTP: AuthHTTP {
    private var captured: [URLRequest] = []
    private let handler: @Sendable (URLRequest, Int) -> (Int, Data)
    /// A path suffix whose answer is held for `slowBy`, and the reason it exists:
    /// **a concurrency test with nothing slow in it does not overlap.** The single-flight gate below
    /// passed with the single-flight slot deleted until this was added — two `async let`s finished
    /// one after the other, and the second read the first's stored result. That is a guard green
    /// while its defect is present, which is this project's dominant failure mode.
    private let slowPath: String?
    private let slowBy: Duration

    init(
        slowPath: String? = nil,
        slowBy: Duration = .milliseconds(120),
        handler: @escaping @Sendable (URLRequest, Int) -> (Int, Data)
    ) {
        self.slowPath = slowPath
        self.slowBy = slowBy
        self.handler = handler
    }

    var requests: [URLRequest] { captured }

    /// Requests whose path ends in `suffix`, for counting rounds by route.
    func requests(to suffix: String) -> [URLRequest] {
        captured.filter { $0.url?.path.hasSuffix(suffix) == true }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = captured.count
        captured.append(request)

        if let slowPath, request.url?.path.hasSuffix(slowPath) == true {
            // The actor is released here, which is the point: the second caller gets in while this
            // one is still waiting for its answer.
            try await Task.sleep(for: slowBy)
        }
        let (status, body) = handler(request, index)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}

// MARK: - Fixtures

private enum Wire {

    static let baseURL = URL(string: "https://example.invalid/api/v1")!

    /// RFC3339 at second precision in UTC — what the service sends and what `.iso8601` accepts. A
    /// fractional-second form would be rejected by `.withInternetDateTime`, which is why the service
    /// truncates; writing the fixture the same way keeps this suite honest about that pairing.
    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func session(
        access: String,
        refresh: String,
        now: Date,
        accessLifetime: TimeInterval = 15 * 60,
        refreshLifetime: TimeInterval = 60 * 24 * 60 * 60,
        userID: UUID = UUID(uuidString: "3A1F212D-0000-4000-8000-000000000001")!
    ) -> Data {
        Data("""
        {"access_token":"\(access)","refresh_token":"\(refresh)",\
        "expires_at":"\(stamp(now.addingTimeInterval(accessLifetime)))",\
        "refresh_expires_at":"\(stamp(now.addingTimeInterval(refreshLifetime)))",\
        "user_id":"\(userID.uuidString)"}
        """.utf8)
    }

    static func device(token: String, now: Date, lifetime: TimeInterval = 365 * 24 * 60 * 60) -> Data {
        Data("""
        {"device_token":"\(token)","expires_at":"\(stamp(now.addingTimeInterval(lifetime)))"}
        """.utf8)
    }
}

/// Error bodies **as the deployed service returned them**, `https://cypress-sync.fly.dev`,
/// 2026-08-14, by `curl` against the live routes with no credential.
///
/// Copied rather than invented because the thing under test is a decode, and a decode asserted
/// against a body this file also wrote proves only that the file agrees with itself.
private enum LiveEnvelopes {
    /// `POST /api/v1/auth/refresh` with `{"refresh_token":"nope"}` → HTTP 401.
    static let expiredSession = Data(
        #"{"error":{"code":"unauthorized","message":"Your session has expired.","retryable":false}}"#.utf8
    )
    /// `POST /api/v1/devices/register` with `{}` → HTTP 400.
    static let missingDeviceIdentifier = Data(
        #"{"error":{"code":"validation_failed","message":"That request was missing a device identifier.","retryable":false}}"#.utf8
    )
}

// MARK: - The Keychain

@Suite("The session's Keychain storage (§5.8)")
struct SessionKeychainTests {

    /// A service name of this run's own, so two suites — or two agents — cannot read each other's
    /// items, and so a failure leaves nothing behind that a later run would find.
    private func store() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "app.cypress.tests.\(UUID().uuidString)")
    }

    @Test("a credential round-trips, overwrites in place, and can be removed")
    func roundTrip() throws {
        let keychain = store()
        defer { try? keychain.removeData(forKey: CredentialKey.session) }

        #expect(try keychain.data(forKey: CredentialKey.session) == nil, "the store was not empty before the write")

        try keychain.setData(Data("first".utf8), forKey: CredentialKey.session)
        #expect(try keychain.data(forKey: CredentialKey.session) == Data("first".utf8))

        // The update arm. A delete-then-add would pass this too; what it would not survive is a
        // failure between the two, which is why the implementation updates in place.
        try keychain.setData(Data("second".utf8), forKey: CredentialKey.session)
        #expect(try keychain.data(forKey: CredentialKey.session) == Data("second".utf8))

        try keychain.removeData(forKey: CredentialKey.session)
        #expect(try keychain.data(forKey: CredentialKey.session) == nil)

        // Removing what is not there is a success: a sign-out on a device that never signed in must
        // not throw.
        try keychain.removeData(forKey: CredentialKey.session)
    }

    /// **The accessibility class, read back off the stored item rather than off the source.**
    ///
    /// Spec §5.8 names `kSecAttrAccessibleAfterFirstUnlock` and gives the reason: "a background
    /// drain runs on a locked phone". `WhenUnlocked` would pass every other test in this file and
    /// silently stop the queue draining while the screen is off — a defect with no symptom anybody
    /// could see in a test that did not ask this question.
    @Test("tokens are stored accessible after first unlock, not only while unlocked")
    func accessibility() throws {
        let keychain = store()
        defer { try? keychain.removeData(forKey: CredentialKey.device) }
        try keychain.setData(Data("token".utf8), forKey: CredentialKey.device)

        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: CredentialKey.device,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        #expect(status == errSecSuccess, "the keychain returned OSStatus \(status) reading back the item it just stored")

        let attributes = try #require(item as? [String: Any], "no attributes came back for the stored item")
        let accessible = attributes[kSecAttrAccessible as String] as? String
        #expect(
            accessible == (kSecAttrAccessibleAfterFirstUnlock as String),
            """
            the stored credential's kSecAttrAccessible is \(accessible ?? "nil"), not \
            kSecAttrAccessibleAfterFirstUnlock. Spec §5.8 requires it because the outbox drains in \
            the background on a locked phone: any stricter class stops the queue while the screen is \
            off, and nothing on any screen would ever say why.
            """
        )
    }
}

// MARK: - Registration and rotation

@Suite("The session (#158 step 3, §5.8)")
struct SessionTests {

    private let deviceUUID = UUID(uuidString: "24D1629F-0000-4000-8000-0000000000D1")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        http: ScriptedHTTP,
        credentials: any CredentialStore = InMemoryCredentialStore(),
        clock: Date? = nil
    ) -> AppSession {
        let fixed = clock ?? now
        return AppSession(
            deviceUUID: deviceUUID,
            client: AuthClient(baseURL: Wire.baseURL, http: http),
            credentials: credentials,
            now: { fixed }
        )
    }

    // MARK: Device registration

    @Test("a device with no credential registers once, and the second call reuses the token")
    func registersOnceAndReuses() async throws {
        let now = now
        let http = ScriptedHTTP { _, _ in (200, Wire.device(token: "device-1", now: now)) }
        let session = session(http: http)

        let first = try await session.bootstrap()
        let second = try await session.authorization()

        #expect(first == .device("device-1"))
        #expect(second == .device("device-1"))
        let registrations = await http.requests(to: "/devices/register").count
        #expect(
            registrations == 1,
            """
            \(registrations) registrations for two calls. Re-registering RETIRES the previous token \
            server-side (server/README.md), so a second registration would sign the first call's \
            credential out.
            """
        )
    }

    @Test("registration sends the installation's device_uuid and nothing else")
    func registrationBody() async throws {
        let now = now
        let http = ScriptedHTTP { _, _ in (200, Wire.device(token: "device-1", now: now)) }
        _ = try await session(http: http).bootstrap()

        let request = try #require(await http.requests(to: "/devices/register").first)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["device_uuid"] as? String == deviceUUID.uuidString)
        // The service decodes with `DisallowUnknownFields`, so an extra key is a
        // `validation_failed` on the whole request rather than a field quietly ignored.
        #expect(Set(json.keys) == ["device_uuid"], "the body carries \(json.keys.sorted()), and the service refuses unknown fields")
    }

    @Test("a validation refusal from the service arrives as the taxonomy, not as a session error")
    func registrationRefusal() async throws {
        let http = ScriptedHTTP { _, _ in (400, LiveEnvelopes.missingDeviceIdentifier) }
        await #expect(throws: APIError.validationFailed) {
            _ = try await session(http: http).bootstrap()
        }
    }

    // MARK: The 401

    @Test("a 401 refreshes once and replays the request with the new token")
    func refreshesOnceAndReplays() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now),
            forKey: CredentialKey.session
        )

        let http = ScriptedHTTP { request, _ in
            if request.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, Wire.session(access: "fresh", refresh: "refresh-2", now: now))
            }
            let bearer = request.value(forHTTPHeaderField: "Authorization")
            return bearer == "Bearer fresh" ? (200, Data(#"{"ok":true}"#.utf8)) : (401, LiveEnvelopes.expiredSession)
        }

        let transport = SessionTransport(session: session(http: http, credentials: credentials), http: http)
        let body = try await transport.send(URLRequest(url: Wire.baseURL.appendingPathComponent("sync")))

        #expect(String(decoding: body, as: UTF8.self) == #"{"ok":true}"#)
        let refreshes = await http.requests(to: "/auth/refresh").count
        let syncs = await http.requests(to: "/sync")
        #expect(refreshes == 1, "the transport refreshed \(refreshes) times")
        #expect(syncs.count == 2, "the transport did not replay exactly once")

        let bearers = syncs.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(bearers == ["Bearer stale", "Bearer fresh"], "the replay carried \(bearers)")

        // …and the rotated pair is what is stored, so the next launch does not present a spent token
        // (the service revokes the whole family when one is replayed).
        let stored = try #require(await session(http: http, credentials: credentials).storedSession)
        #expect(stored.accessToken == "fresh")
        #expect(stored.refreshToken == "refresh-2")
    }

    /// **The assertion this whole folder exists for.** Not "the right type was thrown" — the state
    /// the queue would really take, computed by the real policy.
    @Test("a refused refresh is a transport failure, so every queued item stays alive")
    func refusedRefreshKeepsTheQueue() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "spent", now: now),
            forKey: CredentialKey.session
        )
        let http = ScriptedHTTP { _, _ in (401, LiveEnvelopes.expiredSession) }
        let transport = SessionTransport(session: session(http: http, credentials: credentials), http: http)

        var thrown: Error?
        do {
            _ = try await transport.send(URLRequest(url: Wire.baseURL.appendingPathComponent("sync")))
        } catch {
            thrown = error
        }

        let error = try #require(thrown, "the transport returned a body for a 401 it could not rescue")
        #expect(error as? SessionError == .refreshFailed, "the transport threw \(error)")

        // The two lines the spec's argument turns on.
        #expect(
            OutboxFailureReason.apiError(from: error) == nil,
            """
            the session failure carries a taxonomy code (\
            \(String(describing: OutboxFailureReason.apiError(from: error)))). If that code is \
            non-retryable — and `unauthorized` is — `OutboxRetryPolicy.nextState` fails every item in \
            the batch terminally and screen 17 prints "Sign in to send this" to somebody who is \
            signed in (ERRATA E261 §3).
            """
        )
        let item = OutboxItem(
            kind: .visit,
            clientUUID: UUID(),
            payload: Data("{}".utf8),
            createdAt: now
        )
        #expect(
            OutboxRetryPolicy.nextState(
                for: item,
                error: OutboxFailureReason.apiError(from: error),
                now: now
            ) == .pending,
            "the queue would have given this item up rather than keeping it on the backoff"
        )
    }

    @Test("a 401 that survives a refresh is still the session, never the item")
    func aSecondUnauthorizedIsStillTheSession() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now),
            forKey: CredentialKey.session
        )
        // The refresh succeeds; the replay is refused anyway.
        let http = ScriptedHTTP { request, _ in
            request.url?.path.hasSuffix("/auth/refresh") == true
                ? (200, Wire.session(access: "fresh", refresh: "refresh-2", now: now))
                : (401, LiveEnvelopes.expiredSession)
        }
        let transport = SessionTransport(session: session(http: http, credentials: credentials), http: http)

        var thrown: Error?
        do {
            _ = try await transport.send(URLRequest(url: Wire.baseURL.appendingPathComponent("sync")))
        } catch {
            thrown = error
        }
        let error = try #require(thrown)
        #expect(
            error as? SessionError == .sessionRejected,
            """
            the transport threw \(error). `server/README.md`: "A 401 means the session, never the \
            item… An item that genuinely is not this identity's to send is `forbidden`." Throwing \
            `.unauthorized` here is the defect §5.8 designs out.
            """
        )
        #expect(OutboxFailureReason.apiError(from: error) == nil)
        // …and it does not keep trying. One rotation, one replay.
        let refreshes = await http.requests(to: "/auth/refresh").count
        let syncs = await http.requests(to: "/sync").count
        #expect(refreshes == 1)
        #expect(syncs == 2)
    }

    /// The service revokes a whole session family when a refresh token is presented twice, so two
    /// concurrent 401s costing two refreshes would not waste a round trip — the second would sign
    /// the person out.
    @Test("two requests refused at once cost one refresh, not two")
    func refreshIsSingleFlight() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now),
            forKey: CredentialKey.session
        )
        let http = ScriptedHTTP(slowPath: "/auth/refresh") { request, _ in
            if request.url?.path.hasSuffix("/auth/refresh") == true {
                return (200, Wire.session(access: "fresh", refresh: "refresh-2", now: now))
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh"
                ? (200, Data(#"{"ok":true}"#.utf8))
                : (401, LiveEnvelopes.expiredSession)
        }
        let transport = SessionTransport(session: session(http: http, credentials: credentials), http: http)
        let url = Wire.baseURL.appendingPathComponent("sync")

        async let first = transport.send(URLRequest(url: url))
        async let second = transport.send(URLRequest(url: url))
        _ = try await (first, second)

        let refreshes = await http.requests(to: "/auth/refresh").count
        #expect(
            refreshes == 1,
            """
            \(refreshes) refreshes for two concurrent 401s. The second presents a token the first \
            already spent, and the service answers that by revoking the family \
            (`store.ErrSessionReused`) — so this is a sign-out, not a wasted round trip.
            """
        )
    }

    @Test("a device token that is refused is re-registered rather than refreshed")
    func deviceTokenIsReminted() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.device(token: "device-1", now: now),
            forKey: CredentialKey.device
        )
        let http = ScriptedHTTP { request, _ in
            if request.url?.path.hasSuffix("/devices/register") == true {
                return (200, Wire.device(token: "device-2", now: now))
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer device-2"
                ? (200, Data(#"{"ok":true}"#.utf8))
                : (401, LiveEnvelopes.expiredSession)
        }
        let transport = SessionTransport(session: session(http: http, credentials: credentials), http: http)
        _ = try await transport.send(URLRequest(url: Wire.baseURL.appendingPathComponent("sync")))

        let registrations = await http.requests(to: "/devices/register").count
        let refreshes = await http.requests(to: "/auth/refresh")
        #expect(registrations == 1)
        #expect(refreshes.isEmpty, "a device token has nothing to refresh")
        let bearers = await http.requests(to: "/sync").map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(bearers == ["Bearer device-1", "Bearer device-2"])
    }

    // MARK: Lifetimes

    @Test("an expired access token is refreshed before the request, not after a 401")
    func expiredAccessTokenIsRefreshedUpFront() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        // Minted 20 minutes ago with a 15-minute life: expired, with the refresh token still good.
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now.addingTimeInterval(-20 * 60)),
            forKey: CredentialKey.session
        )
        let http = ScriptedHTTP { request, _ in
            request.url?.path.hasSuffix("/auth/refresh") == true
                ? (200, Wire.session(access: "fresh", refresh: "refresh-2", now: now))
                : (200, Data(#"{"ok":true}"#.utf8))
        }
        let transport = SessionTransport(session: session(http: http, credentials: credentials), http: http)
        _ = try await transport.send(URLRequest(url: Wire.baseURL.appendingPathComponent("sync")))

        let bearers = await http.requests(to: "/sync").map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(bearers == ["Bearer fresh"], "the expired token was sent anyway and cost a 401: \(bearers)")
    }

    @Test("past sixty days there is nothing to rotate, and the device credential carries the queue")
    func aDeadRefreshTokenFallsBackToTheDevice() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now.addingTimeInterval(-61 * 24 * 60 * 60)),
            forKey: CredentialKey.session
        )
        let http = ScriptedHTTP { _, _ in (200, Wire.device(token: "device-1", now: now)) }
        let live = session(http: http, credentials: credentials)

        let authorization = try await live.authorization()
        #expect(authorization == .device("device-1"))
        let refreshes = await http.requests(to: "/auth/refresh")
        #expect(refreshes.isEmpty, "a sixty-day-old refresh token was presented anyway")
        #expect(await live.storedSession == nil, "the dead session is still stored, so every later call re-derives it")
    }

    @Test("a refused refresh forgets the session; a refresh that could not be performed keeps it")
    func onlyARefusalEndsTheSession() async throws {
        let now = now

        // (a) The service refuses. The stored pair will refuse identically forever.
        let refusing = InMemoryCredentialStore()
        try refusing.setData(Wire.session(access: "stale", refresh: "spent", now: now), forKey: CredentialKey.session)
        let refusingHTTP = ScriptedHTTP { _, _ in (401, LiveEnvelopes.expiredSession) }
        let refused = session(http: refusingHTTP, credentials: refusing)
        _ = try? await refused.reauthorize(after: .user("stale"))
        #expect(await refused.storedSession == nil, "a refused refresh left the spent credentials in place")

        // (b) The far side broke. A person must not be signed out by a subway tunnel.
        let keeping = InMemoryCredentialStore()
        try keeping.setData(Wire.session(access: "stale", refresh: "good", now: now), forKey: CredentialKey.session)
        let brokenHTTP = ScriptedHTTP { _, _ in (500, Data(#"{"error":{"code":"server_error","message":"","retryable":true}}"#.utf8)) }
        let kept = session(http: brokenHTTP, credentials: keeping)
        _ = try? await kept.reauthorize(after: .user("stale"))
        #expect(
            await kept.storedSession?.refreshToken == "good",
            "a 500 on the refresh route signed this person out; only a refusal ends a session"
        )
    }

    // MARK: Sign-in

    @Test("the exchange sends the RAW nonce, the authorization code, and the device id")
    func exchangeBody() async throws {
        let now = now
        let http = ScriptedHTTP { _, _ in (200, Wire.session(access: "a", refresh: "r", now: now)) }
        let nonce = AuthNonce(raw: "nonce-raw")

        let userID = try await session(http: http).signInWithApple(
            AppleIdentityCredential(
                identityToken: "identity.jwt",
                authorizationCode: "code-1",
                rawNonce: nonce.raw
            ),
            licenseVersion: .accepted("odbl-1.0")
        )
        #expect(userID == UUID(uuidString: "3A1F212D-0000-4000-8000-000000000001")!)

        let request = try #require(await http.requests(to: "/auth/oidc").first)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["identity_token"] as? String == "identity.jwt")
        #expect(
            json["authorization_code"] as? String == "code-1",
            """
            the exchange did not carry the authorization code. Without it the server never exchanges \
            at Apple's /auth/token, so it stores no refresh token, so `DELETE /me` cannot call the \
            revocation endpoint Apple requires (R72 ruling 2, RULINGS R3).
            """
        )
        #expect(
            json["nonce"] as? String == "nonce-raw",
            """
            the exchange sent \(json["nonce"] as? String ?? "nothing") as the nonce. It must be the \
            RAW value: the server hashes it and compares against Apple's claim, and a client that \
            sent the hash would be forwarding the value anybody holding the captured identity token \
            already has.
            """
        )
        #expect(json["device_uuid"] as? String == deviceUUID.uuidString)
        #expect(json["license_version"] as? String == "odbl-1.0")
    }

    /// Spec §5.6: "A missing `licenseVersion` is a *declined* consent and must arrive as an explicit
    /// null rather than an omitted field the server defaults." The server reads absent, null and a
    /// string as three different facts, and `encodeIfPresent` would collapse two of them.
    @Test("a declined license travels as an explicit null, and an unstated one omits the key")
    func consentTravelsAsThreeStates() throws {
        func keys(_ answer: AuthClient.LicenseAnswer) throws -> [String: Any] {
            let body = AuthClient.OIDCRequest(
                identityToken: "t",
                authorizationCode: "c",
                nonce: "n",
                deviceUUID: nil,
                licenseVersion: answer
            )
            let data = try AuthCoding.encoder.encode(body)
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] ?? [:]
        }

        let declined = try keys(.declined)
        #expect(
            declined.keys.contains("license_version"),
            "a declined consent omitted the key, which the server reads as 'this request is not about consent'"
        )
        #expect(declined["license_version"] is NSNull, "a declined consent did not travel as null")

        let unstated = try keys(.unstated)
        #expect(!unstated.keys.contains("license_version"), "an unstated consent wrote a value")

        let accepted = try keys(.accepted("odbl-1.0"))
        #expect(accepted["license_version"] as? String == "odbl-1.0")
    }

    @Test("signing out keeps the device credential, and deleting an account forgets both")
    func signOutKeepsTheAnonymousQueueDraining() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(Wire.session(access: "a", refresh: "r", now: now), forKey: CredentialKey.session)
        try credentials.setData(Wire.device(token: "device-1", now: now), forKey: CredentialKey.device)
        let http = ScriptedHTTP { _, _ in (500, Data()) }
        let live = session(http: http, credentials: credentials)

        try await live.signOut()
        #expect(await live.storedSession == nil)
        #expect(
            await live.storedDeviceCredential?.deviceToken == "device-1",
            """
            signing out took the device credential with it. D9 makes the anonymous queue the normal \
            case, so a signed-out installation still has to drain — and it cannot re-register while \
            offline.
            """
        )

        try await live.forgetEverything()
        #expect(await live.storedDeviceCredential == nil)
    }
}

// MARK: - The nonce

@Suite("The Apple nonce (§5.2)")
struct AuthNonceTests {

    /// A published vector, so this measures SHA-256 rather than agreeing with itself:
    /// `sha256("abc")` is `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.
    @Test("what Apple is asked to echo is the lowercase SHA-256 hex of the raw value")
    func hashedForApple() {
        #expect(
            AuthNonce(raw: "abc").hashedForApple
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        // Lowercase, because the service lowercases the claim before comparing; an uppercase hash
        // would match there and mismatch nowhere anybody could see.
        #expect(AuthNonce(raw: "abc").hashedForApple == AuthNonce(raw: "abc").hashedForApple.lowercased())
    }

    @Test("the raw value is not the value Apple is given")
    func rawIsNotTheHash() {
        let nonce = AuthNonce.random()
        #expect(nonce.raw != nonce.hashedForApple)
        #expect(nonce.raw.count == 64, "32 random bytes, hex-encoded")
        #expect(AuthNonce.random().raw != AuthNonce.random().raw, "two nonces in a row were identical")
    }
}
