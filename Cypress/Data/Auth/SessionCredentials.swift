//
//  SessionCredentials.swift
//  Cypress — Data/Auth
//
//  The two credentials this app holds, in the shapes the service actually sends them.
//
//  Keys are **snake_case**, which is `server/README.md`'s rule and not a preference: a payload that
//  reconstructs a client-owned Swift type speaks that type's synthesized property names, and
//  everything else — the error envelope, sync results, request bodies, and these — is snake_case.
//  Nothing here is a reconstructed `Core` model, so nothing here is camelCase.
//
//  Timestamps are RFC3339 at second precision in UTC, decoded with `.iso8601`
//  (`.withInternetDateTime`), which **rejects fractional seconds**. The server truncates for
//  exactly this reason; `AuthCoding` is the one place that pairing is stated.
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

/// `POST /devices/register`'s answer — the anonymous queue's credential (§5.8, D9).
///
/// It is **not an attestation**: a reinstall mints a new one and the server cannot tell the
/// difference. Named here because a type called `DeviceCredential` invites being read as one.
public struct DeviceCredential: Codable, Sendable, Hashable {
    public let deviceToken: String
    public let expiresAt: Date

    public init(deviceToken: String, expiresAt: Date) {
        self.deviceToken = deviceToken
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case expiresAt = "expires_at"
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
