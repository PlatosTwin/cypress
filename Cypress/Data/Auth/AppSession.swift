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
//  48 h — and the sentence screen 17 then prints is already written: *"Sign in to send this."* So
//  one expired access token does not slow a drain down, it **ends** it, and tells somebody who is
//  signed in to sign in (spec §5.8, ERRATA **E261** §3).
//
//  Both files are correct alone. The fix is here and at `SessionTransport`: a 401 is a fact about
//  the session, never about the item. Nothing in this folder throws `APIError.unauthorized` at a
//  caller; it throws `SessionError`, which carries no taxonomy code, which keeps every queued item
//  alive on the backoff.
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
/// An `actor` because two drains and a screen can ask for a credential at once, and because the
/// refresh has to be **single-flight**: the service revokes a session family when a refresh token is
/// presented twice (`store.ErrSessionReused`), so two concurrent refreshes of the same token would
/// not merely waste a round trip — the second would sign the person out. `refreshInFlight` is what
/// stops that, and `reauthorize(after:)` is the only door to it.
public actor AppSession {

    private let client: AuthClient
    private let credentials: any CredentialStore
    private let deviceUUID: UUID
    private let now: @Sendable () -> Date

    /// The single-flight slot. A second caller arriving while a rotation is in flight awaits the
    /// same task rather than starting a rival one.
    private var reauthorizationInFlight: Task<Authorization, Error>?

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

    public var storedDeviceCredential: DeviceCredential? {
        guard let data = try? credentials.data(forKey: CredentialKey.device) else { return nil }
        return try? AuthCoding.decoder.decode(DeviceCredential.self, from: data)
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
        return .device(try await register().deviceToken)
    }

    // MARK: - Rotation

    /// Replaces a credential that just came back 401, once.
    ///
    /// - Parameter stale: the credential the caller sent. If what is stored is already something
    ///   else, another caller rotated it first and that answer is returned unchanged — which is the
    ///   difference between two concurrent 401s costing one rotation and costing a sign-out.
    public func reauthorize(after stale: Authorization) async throws -> Authorization {
        if let fresher = fresherThan(stale) { return fresher }
        if let inFlight = reauthorizationInFlight { return try await inFlight.value }

        // `self` is captured strongly and the task is transient: it is awaited on the next line and
        // the slot is cleared on the way out, so there is no cycle to outlive this call. A weak
        // capture would have to invent an error for a `nil` that cannot happen, and that error would
        // read as a refused refresh.
        let task = Task<Authorization, Error> { try await self.performReauthorization(after: stale) }
        reauthorizationInFlight = task
        defer { reauthorizationInFlight = nil }
        return try await task.value
    }

    /// A stored credential that is not the one the caller sent — i.e. somebody already rotated.
    private func fresherThan(_ stale: Authorization) -> Authorization? {
        switch stale {
        case let .user(token):
            guard let session = storedSession, session.accessToken != token,
                  session.accessTokenIsLive(at: now()) else { return nil }
            return .user(session.accessToken)
        case let .device(token):
            guard let device = storedDeviceCredential, device.deviceToken != token,
                  device.isLive(at: now()) else { return nil }
            return .device(device.deviceToken)
        }
    }

    private func performReauthorization(after stale: Authorization) async throws -> Authorization {
        switch stale {
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
