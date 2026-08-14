import Foundation
import Testing
@testable import Cypress

// MARK: - The far side, scripted

/// `POST /auth/oidc` and nothing else, with the bodies captured.
///
/// Its own double rather than `SessionTests`' `ScriptedHTTP`, which is `private` to that file. Kept
/// deliberately small: this suite is about the composition root, and the transport's own behavior —
/// refresh, replay, single flight — is `SessionTests`' subject and is not re-proved here.
///
/// **Internal rather than `private`, and the reason is a hazard rather than convenience.**
/// `AccountSurfaceTests` also drives `RootView.accountLink()`, and its `AppSession` was built with
/// `AuthClient()`'s defaults — which is `SyncService.defaultBaseURL`, the live `cypress-sync`. That
/// was harmless while the closure never called the network and stopped being harmless the moment it
/// did. One double, used by both suites, is what makes "no test in this target can reach production"
/// a property of the code rather than of everybody remembering.
actor ScriptedAuthHTTP: AuthHTTP {

    static let baseURL = URL(string: "https://example.invalid/api/v1")!

    private var captured: [URLRequest] = []
    private let handler: @Sendable (URLRequest) -> (Int, Data)

    init(handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    var requests: [URLRequest] { captured }

    func bodies(to suffix: String) -> [[String: Any]] {
        captured
            .filter { $0.url?.path.hasSuffix(suffix) == true }
            .compactMap { $0.httpBody }
            .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        captured.append(request)
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? Self.baseURL, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (body, response)
    }

    /// Answers `/auth/oidc` with the ids in order, holding the last one once they run out.
    ///
    /// A sequence rather than one id, because one suite needs the service to answer a **different**
    /// account after a deletion — which is what a real `/auth/oidc` does once the `users` row the
    /// Apple subject resolved to is gone. See `AccountSurfaceTests.deletionIsNotResumable`.
    static func minting(_ ids: [UUID]) -> ScriptedAuthHTTP {
        let counter = Counter()
        return ScriptedAuthHTTP { _ in (200, session(userID: ids[min(counter.next(), ids.count - 1)])) }
    }

    /// A call counter for `minting`. A class with a lock rather than an actor, because the handler
    /// `ScriptedAuthHTTP` takes is synchronous and `@Sendable`.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = -1
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
    }

    /// A 200 minting a session for `userID`. RFC3339 at second precision in UTC, which is what the
    /// service sends and what `AuthCoding.decoder`'s `.iso8601` accepts.
    static func session(userID: UUID, now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return Data("""
        {"access_token":"access-1","refresh_token":"refresh-1",\
        "expires_at":"\(formatter.string(from: now.addingTimeInterval(900)))",\
        "refresh_expires_at":"\(formatter.string(from: now.addingTimeInterval(5_184_000)))",\
        "user_id":"\(userID.uuidString)"}
        """.utf8)
    }

    /// The envelope `APIError.Envelope` decodes — the shape `server/internal/apierr` writes.
    static func refusal(_ code: String, _ message: String, retryable: Bool = false) -> Data {
        Data("""
        {"error":{"code":"\(code)","message":"\(message)","retryable":\(retryable)}}
        """.utf8)
    }
}

// MARK: - Fixtures

/// The three values every test here shares.
///
/// A file-scope enum rather than statics on the suite, and the reason is worth one line: the suite is
/// `@MainActor`, so its statics are too, and reading one from inside the `@Sendable` authorization
/// closure is a concurrency warning today and an error under the Swift 6 language mode. These are
/// immutable `Sendable` values that belong to no actor.
enum AppleSignInFixture {

    static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!

    /// The id the *service* mints. Deliberately unlike anything the device could produce, so an
    /// assertion that the local rows carry it cannot pass by coincidence.
    static let serverUserID = UUID(uuidString: "5E12E12E-0000-4000-8000-00000000AA01")!

    /// The authorization this suite's stub answers with.
    ///
    /// **Built through the real construction, not written as a literal**, and review of PR #84 is
    /// why: with a literal `rawNonce`, `exchangeBodyCarriesEverything`'s nonce assertion stayed green
    /// under the hash-for-raw inversion, because the fixture was not the product. It runs through
    /// `AppleAuthorizationAttempt` now, so the wire test observes the same code path the app does.
    static let attempt = AppleAuthorizationAttempt(nonce: AuthNonce(raw: "raw-nonce"))

    static let credential = try! attempt.credential(
        identityToken: Data("identity.jwt".utf8),
        authorizationCode: Data("code-1".utf8)
    )
}

// MARK: - The suite

/// The composition root's half of screen 15's sign-in (#158 spec §10 step 5, RULINGS **R72**
/// ruling 2).
///
/// ── What changed, and why this file was rewritten rather than extended ───────────────────────────
///
/// It used to prove that `RootView.accountLink()` was a *working local* sign-in: mint an id, claim
/// the device, persist it. ERRATA **E124** built that and E124's closing sentence — "when the
/// magic-link service lands, `accountLink()` swaps its body for the client half of the token
/// exchange and nothing on the call path changes" — turned out to be false in three ways, which spec
/// §10 step 5 asked to be checked rather than assumed. So the subject is different now: the id is
/// the **service's**, the exchange is a real `POST /auth/oidc`, and two of the three buttons refuse.
///
/// ── The proof boundary ───────────────────────────────────────────────────────────────────────────
///
/// No Apple Account is signed into anything, here or anywhere in this repository. The authorization
/// is stubbed at `AppleSignIn`, which is exactly the ASAuthorization callback; everything from there
/// to the stored session and the claimed rows is real code over a scripted transport, and the
/// refusals are the service's own envelopes. `AppleSignInRecipeTests` owns the other side of that
/// seam — what Apple is handed, and what the callback becomes.
@MainActor
@Suite("Screen 15 sign-in · the composition root")
struct AccountLinkTests {

    /// A `DataLayer` over an in-memory store, assembled the way `DataLayer.boot` assembles a real
    /// one, with the session pointed at a scripted `/auth/*`.
    ///
    /// `api:` is the *local* half in both positions on purpose. These tests are about the sign-in
    /// leg; a router in front of it would put a network refusal between the assertion and the table
    /// it is about. What `DataLayer.boot` really wires is `DataLayerWiringTests`' subject.
    private static func bootInMemory(http: ScriptedAuthHTTP) async throws -> DataLayer {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: AppleSignInFixture.deviceID)
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))
        return DataLayer(
            store: store,
            api: api,
            local: api,
            outbox: outbox,
            deviceID: AppleSignInFixture.deviceID,
            session: AppSession(
                deviceUUID: AppleSignInFixture.deviceID,
                client: AuthClient(baseURL: ScriptedAuthHTTP.baseURL, http: http),
                credentials: InMemoryCredentialStore()
            ),
            remoteAccess: .disabled,
            readLog: RemoteReadLog()
        )
    }

    /// The action screen 15 is handed, with the Apple sheet replaced by a value.
    private static func link(
        _ data: DataLayer,
        authorize: @escaping AppleSignIn.Authorize
    ) -> AccountAskLink {
        RootView(data: data, appleSignIn: AppleSignIn(authorize: authorize)).accountLink()
    }

    // MARK: - 1. The success path, callback to stored session

    /// The whole of what a tap on `Continue with Apple` has to do, in the order it has to do it.
    ///
    /// The visit is there so "signed in" is observable as *ownership moving* rather than only as a
    /// flag flipping — D9's "keep your three visits" is the promise screen 15's headline makes, and
    /// a sign-in that minted a session and left the work behind would keep the flag and break the
    /// promise.
    @Test("a tap exchanges at the service, stores the session, and brings this device's work across")
    func appleSignInCompletesEndToEnd() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)

        let tree = try await data.local.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-link-test.jpg",
            attribution: .anonymous(deviceID: AppleSignInFixture.deviceID)
        ))
        _ = try await data.outbox.enqueue(.visit(Visit(
            treeID: tree.id,
            attribution: .anonymous(deviceID: AppleSignInFixture.deviceID),
            note: "before sign-in",
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )))
        _ = try await data.outbox.drain()

        #expect(await data.local.userID == nil, "nobody is signed in before the tap")

        let link = Self.link(data) { AppleSignInFixture.credential }
        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))

        // 1 · the id is the service's, not one this device invented.
        let signedInAs = await data.local.userID
        #expect(
            signedInAs == AppleSignInFixture.serverUserID,
            """
            the device signed in as \(signedInAs?.uuidString ?? "nobody") rather than as the account \
            POST /auth/oidc minted. A locally minted id beside a server-minted one is two answers to \
            "who is this", and every row written under the local one is invisible to the service.
            """
        )

        // 2 · persisted, so `DataLayer.boot` reads it back and a relaunch stays signed in.
        let persisted = try await data.store.appState(.currentUserID)
        #expect(persisted == AppleSignInFixture.serverUserID.uuidString, "sign-in did not survive to app_state")

        // 3 · the session is in the credential store, which is what every later request sends with.
        let stored = await data.session.storedSession
        #expect(stored?.userID == AppleSignInFixture.serverUserID)
        #expect(stored?.accessToken == "access-1")

        // 4 · the work came with them — `claimDevice`, from the composition root.
        let owner = try await data.store.queue.read { connection -> String? in
            let statement = try connection.prepare("SELECT user_id FROM visits")
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.stringIfPresent("user_id") }.first ?? nil
        }
        #expect(owner == AppleSignInFixture.serverUserID.uuidString, "the visit stayed the device's after sign-in")

        // 5 · the consent answer landed locally too, which is what the You tab reads back (E131).
        let record = try await data.local.accountLink()
        #expect(record?.provider == "apple")
        #expect(record?.acceptsLicense == true)
    }

    // MARK: - 2. What travels on the wire

    /// Spec §5.2 and R72 ruling 2: the identity token, the authorization code (or `DELETE /me`
    /// cannot revoke at Apple), the **raw** nonce, the device id (so the claim happens in the same
    /// round trip), and the license answer.
    @Test("the exchange carries the raw nonce, the authorization code, the device id and the consent")
    func exchangeBodyCarriesEverything() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)

        try await Self.link(data, authorize: { AppleSignInFixture.credential })(
            AccountLinkRequest(provider: .apple, acceptsLicense: true)
        )

        let body = try #require(await http.bodies(to: "/auth/oidc").first)
        #expect(body["identity_token"] as? String == "identity.jwt")
        #expect(
            body["authorization_code"] as? String == "code-1",
            """
            the exchange did not carry the authorization code. Without it the service never exchanges \
            at Apple's /auth/token, stores no refresh token, and DELETE /me cannot call the \
            revocation endpoint Apple requires (R72 ruling 2, RULINGS R3).
            """
        )
        #expect(
            body["nonce"] as? String == AppleSignInFixture.attempt.nonce.raw,
            """
            the exchange sent \(body["nonce"] as? String ?? "nothing"). It must be the RAW nonce: the \
            server hashes it and compares against Apple's claim, and a client sending the hash \
            forwards the value anybody holding the captured token already has.
            """
        )
        #expect(
            body["device_uuid"] as? String == AppleSignInFixture.deviceID.uuidString,
            """
            the exchange omitted the device id, so /auth/oidc registered and claimed nothing and the \
            three visits screen 15's headline promised are still the device's on the service.
            """
        )
        #expect(body["license_version"] as? String == LicenseConsent.currentVersion)
    }

    /// Spec §5.6: absent, null and a string are three different facts on the far side, and screen 15
    /// only ever produces two of them — it always asked, so the request is always about consent.
    @Test("an unchecked license row travels as an explicit null, never as an omitted key")
    func declinedConsentTravelsAsNull() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)

        try await Self.link(data, authorize: { AppleSignInFixture.credential })(
            AccountLinkRequest(provider: .apple, acceptsLicense: false)
        )

        let body = try #require(await http.bodies(to: "/auth/oidc").first)
        #expect(
            body.keys.contains("license_version"),
            "a declined consent omitted the key, which the service reads as 'this request is not about consent'"
        )
        #expect(body["license_version"] is NSNull, "a declined consent did not travel as null")

        // And locally: nothing recorded, so `User.hasAcceptedLicense` stays honestly false (E131).
        let record = try await data.local.accountLink()
        #expect(record?.acceptsLicense == false)
    }

    // MARK: - 3. The refusals

    /// A dismissed Apple sheet. The action throws, screen 15 stays as SCREENS.md draws it, and —
    /// the part that matters more — **nothing is written**: no session, no account, no claim.
    @Test("a cancelled sheet signs nobody in and leaves the device exactly as it was")
    func cancellationWritesNothing() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)

        let link = Self.link(data) { throw AccountLinkRefusal.cancelled }
        await #expect(throws: AccountLinkRefusal.cancelled) {
            try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        }

        #expect(await data.local.userID == nil, "a cancelled sheet signed somebody in")
        #expect(await data.session.storedSession == nil, "a cancelled sheet stored a session")
        #expect(
            await http.requests.isEmpty,
            "a cancelled sheet still reached the service — the exchange runs before the cancel is seen"
        )
    }

    /// The service refusing the credential. `/auth/oidc` answers `unauthorized` for a failed verify,
    /// a nonce mismatch and a failed authorization-code exchange
    /// (`server/internal/api/auth.go`), and screen 15 wants exactly that answer: it is the taxonomy,
    /// not a `SessionError`, because a caller that asked `AppSession` directly should be told what
    /// the service actually said (`AppSession`'s header).
    @Test("a service that refuses the credential leaves nothing signed in, as the taxonomy")
    func serviceRefusalReachesTheScreen() async throws {
        let http = ScriptedAuthHTTP { _ in
            (401, ScriptedAuthHTTP.refusal("unauthorized", "That sign-in could not be verified."))
        }
        let data = try await Self.bootInMemory(http: http)

        let link = Self.link(data) { AppleSignInFixture.credential }
        await #expect(throws: APIError.unauthorized) {
            try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        }

        #expect(await data.local.userID == nil, "a refused exchange signed somebody in anyway")
        #expect(await data.session.storedSession == nil, "a refused exchange stored a session")
    }

    /// An authorization Apple answered incompletely never reaches the wire: `/auth/oidc` refuses an
    /// empty `authorization_code` with `validation_failed` anyway, so sending one is a round trip to
    /// be told what is already known (`AppleSignInRecipe.Incomplete`).
    @Test("an authorization missing its code never reaches the service")
    func incompleteAuthorizationStopsBeforeTheWire() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)

        let link = Self.link(data) {
            try AppleAuthorizationAttempt(nonce: AuthNonce(raw: "raw-nonce")).credential(
                identityToken: Data("identity.jwt".utf8),
                authorizationCode: nil
            )
        }
        await #expect(throws: AppleSignInRecipe.Incomplete(missing: "authorization code")) {
            try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        }
        #expect(await http.requests.isEmpty)
        #expect(await data.local.userID == nil)
    }

    /// Spec §5.3 and R72 ruling 2: Apple ships first and the email magic link is deferred to its own
    /// ticket, so screen 15 offers "one working route and two honest 'not yet' buttons".
    ///
    /// The assertion that matters is the second one. These two used to mint a **local account**, and
    /// after the wiring round that told somebody their work was backed up while no session existed
    /// to back it up with — E131's defect with the sign reversed, one screen over.
    @Test("Google and email refuse rather than minting an account nothing is behind")
    func deferredProvidersRefuse() async throws {
        for provider in [AccountAskProvider.google, .email] {
            let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
            let data = try await Self.bootInMemory(http: http)

            let link = Self.link(data) {
                Issue.record("\(provider) opened Apple's sheet")
                return AppleSignInFixture.credential
            }
            await #expect(throws: AccountLinkRefusal.unavailable) {
                try await link(AccountLinkRequest(provider: provider, acceptsLicense: true))
            }

            #expect(
                await data.local.userID == nil,
                """
                `\(provider.title)` created an account. There is no service behind it (R72 ruling 2 \
                defers both), so screen 15's drawn promise — "an account backs them up" — would be \
                false for everybody who tapped it.
                """
            )
            #expect(await http.requests.isEmpty)
        }
    }

    /// **The service refusing the device** (review of PR #84, F3).
    ///
    /// `/auth/oidc` performs the claim inline, and it used to swallow the #174 guard and answer 200
    /// anyway: A signs in on this phone and signs out, B signs in, the service keeps every
    /// contribution on A and this closure moved the local rows to B regardless. It answers `conflict`
    /// now — the same code and sentence `POST /devices/claim` already uses — and it answers it
    /// **before minting a session**, so the whole tap unwinds.
    ///
    /// Screen 15 draws `AccountAskCopy.noticeFailed` for it, through the general `catch`, and that is
    /// deliberate rather than a gap: the sign-in genuinely did not go through. What it does not say
    /// is *why*, which is a copy question no mock answers and is recorded as a stop-and-ask.
    @Test("a service that refuses this device leaves the phone exactly as it was")
    func aRefusedDeviceClaimUnwindsTheWholeTap() async throws {
        let http = ScriptedAuthHTTP { _ in
            (409, ScriptedAuthHTTP.refusal("conflict", "This device is already linked to another account."))
        }
        let data = try await Self.bootInMemory(http: http)

        let link = Self.link(data) { AppleSignInFixture.credential }
        await #expect(throws: APIError.conflict) {
            try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        }

        #expect(await data.local.userID == nil, "a refused claim signed somebody in locally anyway")
        #expect(
            await data.session.storedSession == nil,
            "a refused claim left a session behind, so the phone is half signed in"
        )
        let record = try await data.local.accountLink()
        #expect(record == nil, "a refused claim recorded a consent for an account this phone cannot have")
    }

    /// **The local half failing after the remote half succeeded** (review of PR #84, F4).
    ///
    /// `signInWithApple` persists to the Keychain before `linkAccount` runs. Without a rollback the
    /// phone is left holding a live account session while `app_state.currentUserID` is unset — and
    /// `AppSession.authorization()` reads `storedSession` **before** the device credential, so every
    /// later request would go out with an account bearer while every contribution stayed anonymous.
    /// Screen 15 draws "That did not go through" over all of it.
    ///
    /// ── How the local half is made to fail, and why it is calibrated first ──────────────────────
    ///
    /// There is no seam to inject a throwing `LocalAPI` — `RootView.accountLink()` reads the concrete
    /// actor off `DataLayer` — so the writer connection is put into `PRAGMA query_only`, and SQLite
    /// refuses every write on it from then on. That is a real refusal from the real database rather
    /// than a mock of one, and it lands where the finding is: after `exchangeApple` has returned and
    /// the Keychain has been written.
    ///
    /// **Making the file read-only was tried first and does not work**: POSIX permissions are checked
    /// at `open(2)`, and the store already holds a writable descriptor, so every write still
    /// succeeded and the calibration below caught it — which is exactly what it is for.
    @Test("a local half that fails rolls the session back rather than leaving the phone half signed in")
    func aFailedLocalLinkRollsTheSessionBack() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)

        try await data.store.queue.write { connection in
            try connection.execute("PRAGMA query_only = 1")
        }

        // ── Calibration. Without this, "the session was rolled back" could be reported by a run in
        //    which nothing failed and nothing needed rolling back. ────────────────────────────────
        var storeRefusesWrites = false
        do {
            try await data.store.setAppState(.accountProvider, to: "probe")
        } catch {
            storeRefusesWrites = true
        }
        guard storeRefusesWrites else {
            Issue.record("""
                the store still accepts writes, so `linkAccount` below would succeed and this test \
                would assert a rollback nothing needed. Nothing is proved by what follows.
                """)
            return
        }

        let link = Self.link(data) { AppleSignInFixture.credential }
        await #expect(throws: (any Error).self, "a failed local link reported success") {
            try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        }

        #expect(
            await data.session.storedSession == nil,
            """
            the Keychain kept a live account session after the local link failed. \
            `AppSession.authorization()` returns `.user(…)` from it before it looks at the device \
            credential, so every later request goes out as an account whose contributions are all \
            still anonymous — and screen 15 has just said nothing happened.
            """
        )
        #expect(
            await data.local.userID == nil,
            "the local half half-succeeded, which is a different finding from the one under test"
        )
    }

    // MARK: - 4. Signing in twice

    /// The ask can return once (ERRATA **E34**), and somebody can sign out and back in. Both land on
    /// the same account, and they land on it for a different reason than they used to: the service
    /// resolves the same Apple subject to the same `users` row, so the id does not have to be
    /// remembered on the device at all.
    @Test("signing in again resumes the same account rather than minting a rival")
    func signingInTwiceKeepsOneAccount() async throws {
        let http = ScriptedAuthHTTP { _ in (200, ScriptedAuthHTTP.session(userID: AppleSignInFixture.serverUserID)) }
        let data = try await Self.bootInMemory(http: http)
        let link = Self.link(data) { AppleSignInFixture.credential }

        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        let first = await data.local.userID

        try await data.local.signOut()
        #expect(await data.local.userID == nil)

        try await link(AccountLinkRequest(provider: .apple, acceptsLicense: true))
        let second = await data.local.userID

        #expect(first == AppleSignInFixture.serverUserID)
        #expect(
            first == second,
            "signing back in minted a rival id and orphaned the first account's rows (RULINGS R3)"
        )
    }
}
