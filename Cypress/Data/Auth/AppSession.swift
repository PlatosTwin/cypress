//
//  AppSession.swift
//  Cypress — Data/Auth
//
//  The type that owns the session (spec §3.2, §5.8). It is injected into `RemoteAPI` through
//  `SessionTransport`; screen 15 reaches it through the `AccountAskLink` closure the composition
//  root forms, exactly as it has since that screen was built.
//
//  ── What this type is for, stated as the defect it designs out ──────────────────────────────────
//
//  `APIError.unauthorized.retryable` is `false` and `OutboxRetryPolicy.nextState` reads exactly
//  that, so a non-retryable code moves an outbox item to `.failed` **immediately** rather than after
//  48 h. So one expired access token does not slow a drain down, it **ends** it (spec §5.8, ERRATA
//  **E261** §3).
//
//  This paragraph used to finish "and the sentence screen 17 then prints is already written:
//  *'Sign in to send this.'* … and tells somebody who is signed in to sign in". That sentence is no
//  longer drawn for a failed row: the owner's ruling 1 of 2026-08-14 makes every terminally refused
//  row read *"This couldn't be sent."*, and `OutboxFailureReason.sentence(for:)`'s per-code arm for
//  `unauthorized` is unreachable from an outbox row. The defect this type designs out is the same
//  one; what a person would read while it happened is now a sentence that says nothing about the
//  session at all.
//
//  Both files are correct alone. The fix is here and at `SessionTransport`: a 401 is a fact about
//  the session, never about the item.
//
//  **The claim, narrowed to what is measured** (review of PR #77, and CLAUDE.md's "never assert an
//  invariant in a comment you have not verified"). This file used to say "nothing in this folder
//  throws `APIError.unauthorized` at a caller", and `signInWithApple` does: `/auth/oidc` answers
//  `unauthorized` for a failed verify, a nonce mismatch and a failed code exchange, and screen 15
//  wants exactly that answer. The true statement, and the one ERRATA E261 §3 needs, is
//  transport-scoped: **nothing reaches an outbox item through `SessionTransport` as a taxonomy
//  code because of a credential.** `SessionTransport.credential(replacing:)` is where that is
//  enforced, and it is enforced there rather than here on purpose — a caller that asked this type
//  directly (`bootstrap()` on a fresh install) should be told what the service actually said.
//

import Foundation

/// The credential a request is sent with.
public enum Authorization: Sendable, Hashable {
    /// A signed-in account's 15-minute access token.
    case user(String)
    /// The anonymous installation's device token. D9 makes this the normal case, not the exception:
    /// "first saves are anonymous and local-first under a device ID… the ask comes at the third
    /// save", so a queue that could not drain without an account is a queue that fills up.
    case device(String)

    public var bearer: String {
        switch self {
        case let .user(token), let .device(token): return token
        }
    }
}

/// Holds this installation's credentials, mints them when they are missing, and rotates them.
///
/// An `actor` because two drains and a screen can ask for a credential at once, and because minting
/// has to be **single-flight**. Both credentials retire their predecessor on the far side, so a
/// duplicate mint is not a wasted round trip — it is the other caller's credential being taken away:
///
/// - a refresh token presented twice revokes the whole session family (`store.ErrSessionReused`),
///   which signs the person out;
/// - `POST /devices/register` calls `RevokeDeviceTokens` on **every** call
///   (`server/README.md`: "Re-registering retires the previous token"), so a second registration
///   kills the token the first one just handed out.
///
/// Review of PR #77 found the second half unguarded: the refresh path had a slot and lazy device
/// registration did not, and two concurrent first requests on a fresh install really did register
/// twice. `mint(_:replacing:)` is now the only door to either, and `theFirstRequestsOnAFreshInstall…`
/// in `CypressTests/SessionTests.swift` is what keeps it that way.
public actor AppSession {

    private let client: AuthClient
    private let credentials: any CredentialStore
    private let deviceUUID: UUID
    private let now: @Sendable () -> Date

    /// Which credential a mint produces. The slot below is keyed on this and **not shared between
    /// the two**, which review of PR #77 also caught: one slot for both families handed a caller
    /// that asked to rotate its *account* token back a *device* token, and `SessionTransport` then
    /// replayed the request with a device bearer — so a write the account should have owned was
    /// attributed to the installation, or took `forbidden` on a user-only route.
    private enum CredentialFamily: Hashable {
        case user
        case device
    }

    /// The single-flight slots, one per family. A second caller arriving while a mint of the same
    /// family is in flight awaits that task rather than starting a rival one.
    private var mintingInFlight: [CredentialFamily: Task<Authorization, Error>] = [:]

    public init(
        deviceUUID: UUID,
        client: AuthClient = AuthClient(),
        credentials: any CredentialStore = KeychainCredentialStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.deviceUUID = deviceUUID
        self.client = client
        self.credentials = credentials
        self.now = now
    }

    // MARK: - Reading what is stored

    /// The signed-in account, or nil. Read from the Keychain every time rather than cached, so that
    /// this type has no second copy of the one fact it is about.
    public var storedSession: SessionCredentials? {
        guard let data = try? credentials.data(forKey: CredentialKey.session) else { return nil }
        return try? AuthCoding.decoder.decode(SessionCredentials.self, from: data)
    }

    /// The stored device credential — **or nil when it was minted for a different installation.**
    ///
    /// ── The reinstall blocker, and why the check is here rather than at the call sites ─────────
    ///
    /// The Keychain survives app deletion on iOS; `app_state.device_uuid` does not, because it lives
    /// in the SQLite database inside the app container. So a reinstall pairs a *surviving* credential
    /// with a *fresh* installation id, the phone authenticates as the old `devices` row, and
    /// `applyOne` refuses every item it sends — permanently, because the refusal is a per-item
    /// verdict inside a `200 OK` and `SessionTransport` rotates only on a 401. `DeviceCredential`'s
    /// header has the full account.
    ///
    /// **This closes the anonymous arm and only that arm.** `authorization()` below returns
    /// `.user(…)` from `storedSession` before it ever reads this property, so a reinstall on a phone
    /// holding a live account session never arrives here. That case has its own divergence — the
    /// session outlives `app_state.currentUserID` and nothing re-hydrates it — and it is open, not
    /// closed; `DeviceCredential`'s header states it in full. Do not read this property's guard as
    /// "reinstall is handled".
    ///
    /// Both readers of this property — `authorization()` and `stored(_:otherThan:)` — must agree
    /// about what "this installation has a credential" means, and a rule stated twice is a rule that
    /// can disagree with itself (`server.go` says the same thing about its own fall-through). So it
    /// is stated once, here, at the only door to the stored value.
    ///
    /// Returning nil rather than deleting: `register()` writes to the same key, so the repair
    /// overwrites the stale item on its way past, and a getter with a side effect is the harder
    /// thing to reason about.
    public var storedDeviceCredential: DeviceCredential? {
        guard let data = try? credentials.data(forKey: CredentialKey.device),
              let stored = try? AuthCoding.decoder.decode(DeviceCredential.self, from: data),
              stored.deviceUUID == deviceUUID
        else { return nil }
        return stored
    }

    /// The account this device is signed in as, for callers that need the id and not the token.
    public var userID: UUID? { storedSession?.userID }

    // MARK: - Bootstrap

    /// Makes sure this installation can send something.
    ///
    /// Registering the device is **lazy on purpose**: it is performed the first time a credential is
    /// actually needed rather than at launch, because a launch that reaches the network is a launch
    /// that can be slow or fail for a person who only wanted to look at a map. `server/README.md`
    /// also notes that re-registering *retires* the live token, so calling this on a timer would
    /// sign the previous call out.
    @discardableResult
    public func bootstrap() async throws -> Authorization {
        try await authorization()
    }

    /// The credential to send with: the account's if there is a live one, else the device's.
    ///
    /// **The order matters to more than performance.** A live account session short-circuits here,
    /// before `storedDeviceCredential`'s installation check runs at all — which is why that check
    /// closes the anonymous reinstall and leaves the signed-in one open. See `DeviceCredential`.
    ///
    /// An access token that has expired is refreshed here rather than being sent and coming back
    /// 401 — the round trip saved is not the point, the 401 avoided is.
    public func authorization() async throws -> Authorization {
        if let session = storedSession {
            if session.accessTokenIsLive(at: now()) {
                return .user(session.accessToken)
            }
            if session.refreshTokenIsLive(at: now()) {
                return try await reauthorize(after: .user(session.accessToken))
            }
            // Sixty days without a launch. There is nothing left to rotate and the person signs in
            // again; the device credential below is what keeps the anonymous queue draining
            // meanwhile.
            try? credentials.removeData(forKey: CredentialKey.session)
        }
        if let device = storedDeviceCredential, device.isLive(at: now()) {
            return .device(device.deviceToken)
        }
        // **Through `mint`, not straight to `register()`.** Two concurrent first requests on a fresh
        // install both reach this line, and `POST /devices/register` retires the previous token on
        // every call — so an unguarded pair here mints two credentials and leaves the first caller
        // holding a dead one. Review of PR #77 measured that; `mint` is the fix.
        return try await mint(.device, replacing: nil)
    }

    // MARK: - Minting and rotation

    /// Replaces a credential that just came back 401, once.
    ///
    /// - Parameter stale: the credential the caller sent. If what is stored is already something
    ///   else, another caller rotated it first and that answer is returned unchanged — which is the
    ///   difference between two concurrent 401s costing one rotation and costing a sign-out.
    public func reauthorize(after stale: Authorization) async throws -> Authorization {
        switch stale {
        case let .user(token): return try await mint(.user, replacing: token)
        case let .device(token): return try await mint(.device, replacing: token)
        }
    }

    /// Produce a live credential of `family`, sharing one attempt across every caller that wants it.
    ///
    /// - Parameter replacing: the token the caller was holding, or nil when it held none (a fresh
    ///   install). Anything stored that is not that token was minted by somebody else while this
    ///   caller was waiting, and is returned as-is.
    private func mint(_ family: CredentialFamily, replacing stale: String?) async throws -> Authorization {
        if let fresher = stored(family, otherThan: stale) { return fresher }
        if let inFlight = mintingInFlight[family] { return try await inFlight.value }

        // `self` is captured strongly and the task is transient: it is awaited on the next line and
        // the slot is cleared on the way out, so there is no cycle to outlive this call. A weak
        // capture would have to invent an error for a `nil` that cannot happen, and that error would
        // read as a refused refresh.
        let task = Task<Authorization, Error> { try await self.performMint(family) }
        mintingInFlight[family] = task
        defer { mintingInFlight[family] = nil }
        return try await task.value
    }

    /// A stored, live credential of `family` that is not `stale` — i.e. somebody already minted one.
    ///
    /// **This is the branch that stops a duplicate mint after the in-flight slot has emptied**, which
    /// is the common case rather than the rare one: two requests 401 a few milliseconds apart, the
    /// first rotates and finishes, and the second arrives holding the token it sent. Without this it
    /// mints again — and for `.device` that second registration retires the credential the first
    /// caller is now using. Pinned by `aCallerHoldingAReplacedCredential…` in `SessionTests`, which
    /// review of PR #77 found missing: deleting this line left the whole suite green.
    private func stored(_ family: CredentialFamily, otherThan stale: String?) -> Authorization? {
        switch family {
        case .user:
            guard let session = storedSession, session.accessToken != stale,
                  session.accessTokenIsLive(at: now()) else { return nil }
            return .user(session.accessToken)
        case .device:
            guard let device = storedDeviceCredential, device.deviceToken != stale,
                  device.isLive(at: now()) else { return nil }
            return .device(device.deviceToken)
        }
    }

    /// The round trip itself. Takes no `stale`: the refresh token to present is whatever is stored,
    /// and a registration presents the installation's id — neither is the caller's expired token.
    private func performMint(_ family: CredentialFamily) async throws -> Authorization {
        switch family {
        case .user:
            guard let session = storedSession, session.refreshTokenIsLive(at: now()) else {
                throw SessionError.refreshFailed
            }
            do {
                let fresh = try await client.refresh(refreshToken: session.refreshToken)
                try persist(fresh)
                return .user(fresh.accessToken)
            } catch let error as APIError {
                // **The service refused, so the session is over** — a spent, replayed or revoked
                // refresh token will refuse identically forever, and keeping it means every later
                // call spends a round trip proving that again. Any *other* error (no signal, a 500)
                // leaves the stored session exactly where it is: a person must not be signed out by
                // a subway tunnel.
                if error == .unauthorized || error == .forbidden {
                    try? credentials.removeData(forKey: CredentialKey.session)
                }
                throw SessionError.refreshFailed
            } catch {
                throw SessionError.refreshFailed
            }
        case .device:
            // A device token cannot be refreshed; it is re-minted. `server/README.md`: re-registering
            // retires the previous token, "so a takeover is visible — the real device's next call is
            // a 401 and it re-registers — rather than two holders sharing one queue silently". This
            // is that re-registration, and it is the whole of the client's half of that sentence.
            //
            // **No `catch`, unlike the `.user` arm above, and that asymmetry is deliberate** (review
            // of PR #77 asked). The `.user` arm catches because it has a *side effect* to decide —
            // whether the stored session is now worthless — and only the taxonomy answers that.
            // There is no equivalent decision here, and swallowing the code would take the honest
            // answer away from a caller that asked this type directly:
            // `registrationRefusal` pins that `bootstrap()` on a bad device id reports
            // `validation_failed` as itself. The place a taxonomy code must stop being about the
            // item is one layer out, at `SessionTransport.credential(replacing:)`, which is the only
            // caller for which that matters — and it is tested there.
            return .device(try await register().deviceToken)
        }
    }

    // MARK: - Sign in and out

    /// The Sign in with Apple exchange (spec §5.2, step 5).
    ///
    /// Carries the authorization code, so `DELETE /me` can revoke at Apple (RULINGS **R72** ruling
    /// 2), and the device id, so the claim happens in the same round trip and the three visits the
    /// screen promised are on the account before the sheet closes.
    ///
    /// - Returns: the account's id, which is what the local half (`LocalAPI.linkAccount`) hangs this
    ///   device's rows from. One id, minted by the service rather than by the client, so the local
    ///   and remote halves cannot disagree about who this is.
    @discardableResult
    public func signInWithApple(
        _ credential: AppleIdentityCredential,
        licenseVersion: AuthClient.LicenseAnswer
    ) async throws -> UUID {
        let session = try await client.exchangeApple(
            credential,
            deviceUUID: deviceUUID,
            licenseVersion: licenseVersion
        )
        try persist(session)
        return session.userID
    }

    /// Forgets the account's credentials and keeps the device's.
    ///
    /// The device credential survives on purpose: signing out returns this installation to the
    /// anonymous state D9 calls normal, and an anonymous queue still has to drain.
    public func signOut() throws {
        try credentials.removeData(forKey: CredentialKey.session)
    }

    /// Forgets everything, including the device credential.
    ///
    /// For account deletion: after `DELETE /me` there is nothing on the far side for either
    /// credential to be about, and a device token minted under a deleted account's claim is a
    /// pointer to it.
    public func forgetEverything() throws {
        try credentials.removeData(forKey: CredentialKey.session)
        try credentials.removeData(forKey: CredentialKey.device)
    }

    // MARK: - Storage

    private func register() async throws -> DeviceCredential {
        let credential = try await client.registerDevice(deviceUUID: deviceUUID)
        let data = try AuthCoding.encoder.encode(credential)
        try credentials.setData(data, forKey: CredentialKey.device)
        return credential
    }

    private func persist(_ session: SessionCredentials) throws {
        try credentials.setData(try AuthCoding.encoder.encode(session), forKey: CredentialKey.session)
    }
}
