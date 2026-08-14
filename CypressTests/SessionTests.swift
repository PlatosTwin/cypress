//
//  SessionTests.swift
//  CypressTests
//
//  #158 step 3 (spec §5.8). What these tests are actually about, in one sentence:
//
//      **a 401 must never reach an outbox item.**
//
//  `APIError.unauthorized.retryable` is `false`; `OutboxRetryPolicy.nextState` reads exactly that
//  and moves a non-retryable item to `.failed` immediately; `OutboxFailureReason.sentence(for:)`
//  then prints "Sign in to send this" — to somebody who is signed in. (The type is
//  `OutboxFailureReason`; `Cypress/Data/Outbox/OutboxViewState.swift` is the file it lives in.) So the assertions below do not stop at "the right
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
    /// A path suffix whose answer is held for `slowBy` — **`""` holds every route** — and the reason
    /// it exists:
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

        if let slowPath, slowPath.isEmpty || request.url?.path.hasSuffix(slowPath) == true {
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

    /// The `kSecAttrAccessible` of the item as it is actually stored, read back off the keychain.
    private func storedAccessibility(
        _ keychain: KeychainCredentialStore,
        forKey key: String
    ) throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)
        #expect(status == errSecSuccess, "the keychain returned OSStatus \(status) reading back the stored item")
        let attributes = try #require(item as? [String: Any], "no attributes came back for the stored item")
        return attributes[kSecAttrAccessible as String] as? String
    }

    /// **The accessibility class, read back off the stored item rather than off the source.**
    ///
    /// Spec §5.8 names `kSecAttrAccessibleAfterFirstUnlock` and gives the reason: "a background
    /// drain runs on a locked phone". `WhenUnlocked` would pass every other test in this file and
    /// silently stop the queue draining while the screen is off — a defect with no symptom anybody
    /// could see in a test that did not ask this question.
    @Test("a first write stores the credential accessible after first unlock")
    func accessibilityOnAdd() throws {
        let keychain = store()
        defer { try? keychain.removeData(forKey: CredentialKey.device) }
        try keychain.setData(Data("token".utf8), forKey: CredentialKey.device)

        let accessible = try storedAccessibility(keychain, forKey: CredentialKey.device)
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

    /// **The same question of the `SecItemUpdate` arm, which is the one the app actually uses.**
    ///
    /// Review of PR #77 found this gap by mutation: downgrading *only* the update dictionary to
    /// `WhenUnlocked` — leaving the add path correct — left the whole 1379-test suite green. That is
    /// the worse half to lose. The add arm runs once per install; the update arm runs on **every**
    /// rotation, which after the first sign-in is the steady state, so a build with that downgrade
    /// would drain normally until the first refresh and then stop draining in the background
    /// forever, with nothing on any screen able to say why.
    @Test("a rotation keeps the credential accessible after first unlock, not only while unlocked")
    func accessibilityOnUpdate() throws {
        let keychain = store()
        defer { try? keychain.removeData(forKey: CredentialKey.session) }

        try keychain.setData(Data("first".utf8), forKey: CredentialKey.session)
        // The second write takes the `errSecDuplicateItem` → `SecItemUpdate` arm. Asserted, so this
        // test cannot quietly become a second copy of `accessibilityOnAdd`.
        try keychain.setData(Data("rotated".utf8), forKey: CredentialKey.session)
        #expect(
            try keychain.data(forKey: CredentialKey.session) == Data("rotated".utf8),
            "the second write did not take effect, so the update arm was not exercised"
        )

        let accessible = try storedAccessibility(keychain, forKey: CredentialKey.session)
        #expect(
            accessible == (kSecAttrAccessibleAfterFirstUnlock as String),
            """
            after a rotation the credential's kSecAttrAccessible is \(accessible ?? "nil"), not \
            kSecAttrAccessibleAfterFirstUnlock. Every refresh after the first sign-in goes through \
            SecItemUpdate, so a downgrade there stops the background drain in the steady state while \
            a fresh install looks perfectly healthy.
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

    /// **Blocker 1 from review of PR #77, and it was measured there before it was fixed here.**
    ///
    /// Two concurrent first requests on a fresh install both find no device credential and both
    /// register. `POST /devices/register` calls `RevokeDeviceTokens` on **every** call
    /// (`server/README.md`: "Re-registering retires the previous token"), so the second registration
    /// kills the token the first one just handed out — and because `register()` stores
    /// unconditionally, the slower of the two also writes the retired credential over the newer one.
    /// The refresh path was given a single-flight slot for exactly this argument; this is the same
    /// argument on the other credential.
    ///
    /// **The double must actually suspend or this test is worthless.** `f1a8c1b` on this branch is
    /// the lesson: the refresh version of this test passed with single-flight deleted, because two
    /// `async let`s over a double that never awaits simply run one after the other and the second
    /// reads the first's stored result. `slowPath` is what makes the two callers overlap.
    @Test("two first requests at once register once, not twice")
    func registrationIsSingleFlight() async throws {
        let now = now
        let http = ScriptedHTTP(slowPath: "/devices/register") { _, index in
            (200, Wire.device(token: "device-\(index + 1)", now: now))
        }
        let live = session(http: http)

        async let first = live.authorization()
        async let second = live.authorization()
        let both = try await [first, second]

        let registrations = await http.requests(to: "/devices/register").count
        #expect(
            registrations == 1,
            """
            \(registrations) registrations for two concurrent first requests. The server retires the \
            previous device token on every register, so the second call does not waste a round trip \
            — it takes the first caller's credential away, and `register()` then stores the retired \
            one over the newer.
            """
        )
        #expect(
            both == [.device("device-1"), .device("device-1")],
            "the two callers were handed different credentials: \(both)"
        )
        let stored = await live.storedDeviceCredential?.deviceToken
        #expect(stored == "device-1", "the stored credential is \(stored ?? "nil"), not the one both callers hold")
    }

    /// **Blocker 2 from review of PR #77: `stored(_:otherThan:)` was untested, and deleting it left
    /// every test green.**
    ///
    /// This is the branch that catches a duplicate mint *after* the in-flight slot has emptied,
    /// which is the ordinary case rather than the rare one — two requests 401 a few milliseconds
    /// apart, the first rotates and finishes, and the second arrives still holding the token it sent.
    /// Sequential on purpose: the slot cannot be what saves it here, so this measures the branch and
    /// nothing else.
    ///
    /// For `.device` the cost of losing it is immediate and is the one the whole folder is about: the
    /// second registration retires the credential the first caller is now using.
    @Test("a caller holding a device token another has already replaced is handed the replacement")
    func aReplacedDeviceTokenIsNotReRegistered() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(Wire.device(token: "device-1", now: now), forKey: CredentialKey.device)
        let http = ScriptedHTTP { _, index in (200, Wire.device(token: "device-\(index + 2)", now: now)) }
        let live = session(http: http, credentials: credentials)

        // The first caller's token is refused, so it re-registers and gets device-2.
        let rotated = try await live.reauthorize(after: .device("device-1"))
        #expect(rotated == .device("device-2"))

        // A second caller arrives holding the same retired token, after the first has finished.
        let handed = try await live.reauthorize(after: .device("device-1"))

        #expect(
            handed == .device("device-2"),
            """
            the second caller was handed \(handed) rather than the credential already minted. A \
            second registration retires device-2 server-side, which is the token the first caller is \
            using — so this is not a wasted round trip, it is taking somebody's credential away.
            """
        )
        let registrations = await http.requests(to: "/devices/register").count
        #expect(registrations == 1, "\(registrations) registrations; the second caller minted a rival credential")
    }

    /// The same branch on the account credential. Losing it here costs a redundant rotation rather
    /// than a sign-out — the second caller would refresh with the *current* token, not the spent one
    /// — but it spends a refresh nobody asked for and leaves the first caller's answer stale, and it
    /// is the branch review found unpinned.
    @Test("a caller holding an access token another has already rotated is handed the new one")
    func aRotatedAccessTokenIsNotRefreshedAgain() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now),
            forKey: CredentialKey.session
        )
        let http = ScriptedHTTP { _, index in
            (200, Wire.session(access: "fresh-\(index + 1)", refresh: "refresh-\(index + 2)", now: now))
        }
        let live = session(http: http, credentials: credentials)

        let rotated = try await live.reauthorize(after: .user("stale"))
        #expect(rotated == .user("fresh-1"))

        let handed = try await live.reauthorize(after: .user("stale"))
        #expect(
            handed == .user("fresh-1"),
            "the second caller was handed \(handed) — it rotated again over a session somebody had already rotated"
        )
        let refreshes = await http.requests(to: "/auth/refresh").count
        #expect(refreshes == 1, "\(refreshes) refreshes; the second caller spent a rotation nobody asked for")
    }

    /// The two slots are not one slot.
    ///
    /// Review of PR #77: a single slot handed a caller that asked to rotate its **account** token
    /// back a **device** token, and `SessionTransport` then replayed the request with a device
    /// bearer — so a write the account should have owned was attributed to the installation, or took
    /// `forbidden` on a user-only route (`server/internal/api/auth.go` refuses a device caller on
    /// `POST /devices/claim`).
    @Test("a user rotation in flight does not hand a device token to an account caller")
    func theSlotsAreKeyedOnTheCredentialFamily() async throws {
        let now = now
        let credentials = InMemoryCredentialStore()
        try credentials.setData(
            Wire.session(access: "stale", refresh: "refresh-1", now: now),
            forKey: CredentialKey.session
        )
        try credentials.setData(Wire.device(token: "device-1", now: now), forKey: CredentialKey.device)
        // Both routes are slow ("" matches every path), so the two rotations really are in flight
        // together — without that they run one after the other and nothing overlaps (see `f1a8c1b`).
        let http = ScriptedHTTP(slowPath: "") { request, _ in
            request.url?.path.hasSuffix("/auth/refresh") == true
                ? (200, Wire.session(access: "fresh", refresh: "refresh-2", now: now))
                : (200, Wire.device(token: "device-2", now: now))
        }
        let live = session(http: http, credentials: credentials)

        async let device = live.reauthorize(after: .device("device-1"))
        async let user = live.reauthorize(after: .user("stale"))
        let (deviceAnswer, userAnswer) = try await (device, user)

        #expect(deviceAnswer == .device("device-2"), "the device caller got \(deviceAnswer)")
        #expect(
            userAnswer == .user("fresh"),
            """
            the account caller was handed \(userAnswer) while a device registration was in flight. \
            SessionTransport would replay the request with that bearer, so a write the account owns \
            is attributed to the installation — or takes `forbidden` on a user-only route.
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

    /// The boundary the folder's narrowed claim is scoped to.
    ///
    /// `AppSession` reports what the service said — `registrationRefusal` above pins that
    /// `bootstrap()` surfaces `validation_failed` as itself, which is the right answer for a caller
    /// that asked it directly. Through the transport it must not be: a taxonomy code arriving here
    /// is a *credential* problem reaching an outbox item, and `validation_failed` is non-retryable,
    /// so it would fail the whole batch terminally over something that is about no item in it.
    @Test("a refused registration reaches the transport's caller as a session failure, not a code")
    func aRefusedRegistrationIsNotTheItemsProblem() async throws {
        let http = ScriptedHTTP { _, _ in (400, LiveEnvelopes.missingDeviceIdentifier) }
        let transport = SessionTransport(session: session(http: http), http: http)

        var thrown: Error?
        do {
            _ = try await transport.send(URLRequest(url: Wire.baseURL.appendingPathComponent("sync")))
        } catch {
            thrown = error
        }
        let error = try #require(thrown, "the transport returned a body without a credential")
        #expect(error as? SessionError == .noCredential, "the transport threw \(error)")
        #expect(
            OutboxFailureReason.apiError(from: error) == nil,
            """
            a refused registration carried a taxonomy code (\
            \(String(describing: OutboxFailureReason.apiError(from: error)))) to the transport's \
            caller. `validation_failed` is non-retryable, so every item in the batch would be given \
            up over a credential the queue has no opinion about.
            """
        )
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
