//
//  SessionCredentials.swift
//  Cypress — Data/Auth
//
//  The credentials this app holds — and **they are not all one kind of shape**, which is the first
//  thing to know before editing anything here.
//
//  ── Two kinds of shape, and the difference is load-bearing ─────────────────────────────────────
//
//  *Wire shapes* are what the service sends: `SessionCredentials` and `DeviceRegistration`. Their
//  `CodingKeys` are a contract with `server/internal/api`, and changing one is a protocol change.
//
//  *Storage shapes* are what this installation keeps in the Keychain: `DeviceCredential`. Its
//  `CodingKeys` are a **persistence format**, owned entirely by this app, and changing one is a
//  compatibility question about credentials already on somebody's phone — a different question with
//  a different failure mode.
//
//  They were one type. `DeviceCredential` was decoded straight off `POST /devices/register` *and*
//  encoded into the Keychain, so it could not carry a field the wire does not send — and the field
//  it could not carry was the installation the token belonged to. That is the whole of the reinstall
//  defect this file's `DeviceCredential` header describes. The split exists so the two questions can
//  be asked separately; do not merge them back.
//
//  ── The wire rule ─────────────────────────────────────────────────────────────────────────────
//
//  Wire keys are **snake_case**, which is `server/README.md`'s rule and not a preference: a payload
//  that reconstructs a client-owned Swift type speaks that type's synthesized property names, and
//  everything else — the error envelope, sync results, request bodies, and these — is snake_case.
//  Nothing here is a reconstructed `Core` model, so nothing here is camelCase. The storage shape
//  follows the same spelling, but for a weaker reason: consistency with its neighbours, not a
//  contract with anybody.
//
//  ── The storage rule, which has no equivalent on the wire ─────────────────────────────────────
//
//  **Adding a non-optional key to a storage shape discards every credential already stored.** The
//  decode fails, `AppSession`'s `try?` reads the failure as "nothing stored", and the installation
//  re-registers. Adding an *optional* key does not: old payloads decode with nil.
//
//  Neither is automatically right. Discarding is correct when the missing fact makes the stored
//  value untrustworthy — which is exactly why `deviceUUID` is non-optional — and wrong when it would
//  throw away a credential that is still perfectly usable, because a re-register **retires the
//  previous token server-side** (`server/README.md`) and a needless one signs out a queue that was
//  draining. Decide which you are doing, and say so at the field.
//
//  ── Timestamps ────────────────────────────────────────────────────────────────────────────────
//
//  RFC3339 at second precision in UTC, decoded with `.iso8601` (`.withInternetDateTime`), which
//  **rejects fractional seconds**. The server truncates for exactly this reason; `AuthCoding` is the
//  one place that pairing is stated.
//

import Foundation

/// `POST /auth/oidc` and `POST /auth/refresh` both answer with this.
public struct SessionCredentials: Codable, Sendable, Hashable {
    /// The 15-minute bearer (§5.8).
    public let accessToken: String
    /// The 60-day rotating refresh token (§5.8). Every successful refresh replaces it; the previous
    /// value is spent, and presenting it again revokes the family server-side.
    public let refreshToken: String
    public let expiresAt: Date
    public let refreshExpiresAt: Date
    public let userID: UUID

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        refreshExpiresAt: Date,
        userID: UUID
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case refreshExpiresAt = "refresh_expires_at"
        case userID = "user_id"
    }

    /// Whether the access token is still worth presenting at `now`.
    ///
    /// **`skew` is not politeness.** A token that expires while the request is in flight comes back
    /// 401, and a 401 on a `/sync` batch is the failure §5.8 is written against. Spending one
    /// refresh a few seconds early is free; the alternative costs a round trip and, on the drain
    /// path, risks the item-level `unauthorized` that this whole layer exists to keep off the queue.
    public func accessTokenIsLive(at now: Date, skew: TimeInterval = 30) -> Bool {
        expiresAt.timeIntervalSince(now) > skew
    }

    /// Whether the refresh token can still buy a new access token. Past this there is no session
    /// left to rescue and the person signs in again.
    public func refreshTokenIsLive(at now: Date) -> Bool {
        refreshExpiresAt > now
    }
}

/// `POST /devices/register`'s answer, exactly — and **only** that.
///
/// Split from `DeviceCredential` below, which is what gets *stored*. The two were one type, and the
/// conflation is what made the reinstall defect unwritable-about: a value that is both the wire
/// shape and the storage shape cannot carry a field the wire does not send, and the missing field
/// was the whole bug.
struct DeviceRegistration: Decodable {
    let deviceToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case expiresAt = "expires_at"
    }
}

/// The anonymous queue's credential as this installation stores it (§5.8, D9).
///
/// ── Why it carries the `device_uuid` it was minted for ────────────────────────────────────────
///
/// This type's header used to say: *"It is **not an attestation**: a reinstall mints a new one and
/// the server cannot tell the difference."* The second half is true and the first half was false,
/// and the gap between them is a blocker that reached the merged client.
///
/// **On iOS the Keychain survives app deletion; `app_state.device_uuid` does not.** It lives in
/// SQLite inside the app container, so deleting the app takes the database and `DataLayer.boot`
/// mints a fresh installation id on the next launch — while `KeychainCredentialStore` hands back the
/// credential minted for the *previous* one. From then on the phone authenticates as the old
/// `devices` row and names the new installation on every item, so `applyOne` refuses all of them:
/// *"That item belongs to a different device."*
///
/// **And it is permanent, which is what makes it a blocker rather than a bug.** The refusal is a
/// per-item verdict inside a `200 OK` batch, so `SessionTransport`'s refresh-and-replay never fires
/// — it rotates on a 401 and there is no 401. The credential is live, well-formed and accepted by
/// the service; only its *pairing* is wrong, and nothing recorded the pairing. There is no in-app
/// recovery, and the act that causes it is deleting the app — the first thing anybody tries.
///
/// So the pairing is stored. `AppSession.storedDeviceCredential` reads a credential minted for
/// another installation as **no credential at all**, which routes it into the ordinary lazy
/// registration path and mints a fresh one through the single-flight door. The stale item is not
/// deleted explicitly: `register()` writes to the same key, so it is overwritten by the repair
/// itself, and a getter with a side effect would be the harder thing to reason about.
///
/// ── What this closes, and what it does not ────────────────────────────────────────────────────
///
/// **The device arm only.** `AppSession.authorization()` consults `storedSession` first and returns
/// `.user(…)` before it ever reaches the device credential, so a reinstall on a phone whose Keychain
/// still holds a live *account* session takes a different branch entirely and none of the above
/// applies to it.
///
/// That branch had its own divergence — the session survived while `app_state.currentUserID` did
/// not, nothing re-hydrated it, and the app showed a signed-out installation while the bearer was
/// the account's — and the project owner settled it the **opposite way from this one**: a surviving
/// account session restores, silently. `SessionRestore` holds the ruling and the reasoning, and
/// `DataLayer.boot` applies it. The two answers are not inconsistent, they are about two different
/// things: a device credential belongs to a copy of the app, and an account belongs to a person.
///
/// **No data migration**, and the rule it rests on is this file's header: a non-optional key
/// discards what is already stored, which is the right answer when the missing fact makes the stored
/// value untrustworthy. A credential with no recorded installation is exactly that. The app is
/// unreleased, so no such payload exists in the field; the shape is asserted anyway, in
/// `SessionTests.aPrePairingCredentialReadsAsAbsent`.
public struct DeviceCredential: Codable, Sendable, Hashable {
    public let deviceToken: String
    public let expiresAt: Date
    /// The `app_state.device_uuid` this token was minted for. See the header.
    public let deviceUUID: UUID

    public init(deviceToken: String, expiresAt: Date, deviceUUID: UUID) {
        self.deviceToken = deviceToken
        self.expiresAt = expiresAt
        self.deviceUUID = deviceUUID
    }

    init(_ registration: DeviceRegistration, deviceUUID: UUID) {
        self.deviceToken = registration.deviceToken
        self.expiresAt = registration.expiresAt
        self.deviceUUID = deviceUUID
    }

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case expiresAt = "expires_at"
        case deviceUUID = "device_uuid"
    }

    public func isLive(at now: Date, skew: TimeInterval = 30) -> Bool {
        expiresAt.timeIntervalSince(now) > skew
    }
}

/// What `ASAuthorizationAppleIDCredential` yields, reduced to the three things the exchange needs.
///
/// A `Data` type holding no `AuthenticationServices` import, so the exchange is testable without a
/// sign-in sheet — and so `Data` keeps its side of ARCHITECTURE §2. Whoever presents the Apple sheet
/// fills this in; see the header of `AppleIdentityExchange`.
///
/// **`rawNonce` is the raw value, never its hash.** The Apple recipe hands
/// `ASAuthorizationAppleIDRequest.nonce` the SHA-256 *hex* of a random string and puts that hash in
/// the identity token's `nonce` claim; the raw string is the only thing that proves possession, so
/// it is what travels and the server does the hashing (`server/internal/api/auth.go`). A client that
/// sent the hash would be forwarding the value an attacker holding the token already has.
public struct AppleIdentityCredential: Sendable, Hashable {
    public let identityToken: String
    public let authorizationCode: String
    public let rawNonce: String

    public init(identityToken: String, authorizationCode: String, rawNonce: String) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.rawNonce = rawNonce
    }
}

/// The one place the coder pair for `/auth/*` and `/devices/*` bodies is configured.
public enum AuthCoding {
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        // `.iso8601` is `.withInternetDateTime`, which refuses fractional seconds. The service
        // truncates to the second for exactly this reason (`server/internal/api/wire.go`); a
        // strategy that accepted more here would hide a drift that breaks every dated response.
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
