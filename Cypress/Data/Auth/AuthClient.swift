//
//  AuthClient.swift
//  Cypress — Data/Auth
//
//  The three routes that are **not** on `CypressAPI`, and spec §3.2 is why: "The protocol is every
//  read and write the UI performs. A token exchange is not one of those; it is how the transport
//  earns the right to perform any of them." Adding them as requirements would oblige fourteen
//  preview doubles and eighteen test doubles to answer questions about tokens — the exact tax
//  `CypressAPI`'s own "two methods that were requirements and are not any more" note records paying
//  once already.
//
//  `POST /devices/claim` is deliberately absent from this file: it *is* on `CypressAPI`
//  (`claimDevice(deviceUUID:userID:)`), because it moves rows rather than minting credentials, and
//  `RemoteAPI` implements it. `POST /auth/oidc` performs the claim in the same round trip when a
//  device id is supplied, which is what makes D9's "keep your three visits" true at the moment the
//  button is tapped rather than one drain later.
//

import Foundation

/// Where the live layer is.
public enum SyncService {
    /// The Fly app of RULINGS **R72** (`server/README.md`). One host, named once, for the reason
    /// `CityDownloader.defaultBaseURL` is: a base URL that could be supplied by a rewritable remote
    /// object is a redirect waiting to happen, so this is app configuration and nothing else.
    public static let defaultBaseURL = URL(string: "https://cypress-sync.fly.dev/api/v1")!

    /// How long a request to this service may go without producing anything before it is given up on.
    ///
    /// **`URLSession`'s default is 60 seconds and nothing in this app used to change it**, which is
    /// how a single unreachable host cost a screen a minute. That was survivable only for as long as
    /// nothing on a paint path awaited one; the grove's two reads did, and a reader on a hotel
    /// captive portal watched an empty tab for the whole of it.
    ///
    /// **It is `timeoutIntervalForRequest`, which is an idle timeout and not a deadline.** The clock
    /// restarts every time a byte arrives, so this is not a cap on how long a large response may
    /// take — it is how long a stalled connection is tolerated. Fifteen seconds is far longer than
    /// any of this service's JSON routes takes when it is answering (the slowest,
    /// `GET /me/grove`, is a single indexed query on a machine that Fly may have to autostart first
    /// — the autostart is the reason this is fifteen and not three) and far shorter than the minute
    /// a reader spends deciding the app is broken.
    ///
    /// **What it does not govern.** The photo binary travels on `DataLayer.boot`'s `storageSession`
    /// to a presigned storage URL, and a city pack travels on `CityDownloadService`'s own background
    /// session; neither is this session, both are large transfers, and neither would survive a
    /// timeout written for a JSON route. The outbox *does* share this session — its mutations go
    /// through `SessionTransport` — and that is intended: an outbox item that meets a timeout gets a
    /// `URLError`, which is outside the taxonomy, so it stays alive on the backoff and is retried
    /// (ERRATA **E261** §3) rather than failing terminally.
    public static let requestTimeout: TimeInterval = 15

    /// A session for this service's JSON routes, with `requestTimeout` on it.
    ///
    /// **A session of this app's own, rather than `URLSession.shared`, and that is the whole point.**
    /// `URLSession.shared` cannot be configured — its `configuration` property hands back a *copy*,
    /// so assigning to that copy changes nothing about the session — which means `requestTimeout`
    /// above is unreachable for as long as the wire is the shared session.
    ///
    /// **A function and not a stored `static let`**, because ARCHITECTURE §3 is "no singletons, no
    /// `.shared`": `DataLayer.boot` makes one and hands it to both halves of the wire, so the thing
    /// that decides what the app's network behaves like is the composition root, in one place, where
    /// a test can pass something else. A `boot` that runs again — an inventory change re-boots the
    /// layer — makes a second one, which is a connection pool and not a leak.
    ///
    /// `.default` and not `.ephemeral`: the same on-disk URL cache and cookie behavior `.shared`
    /// had, so the timeout is the only thing that changes.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }
}

/// The `/auth/*` and `/devices/register` client. Holds no state: `AppSession` owns the credentials
/// and this owns the wire.
public struct AuthClient: Sendable {

    public let baseURL: URL
    private let http: any AuthHTTP

    public init(baseURL: URL = SyncService.defaultBaseURL, http: any AuthHTTP = URLSession.shared) {
        self.baseURL = baseURL
        self.http = http
    }

    // MARK: - POST /auth/oidc

    /// The Sign in with Apple exchange (spec §5.2, RULINGS **R72** ruling 2).
    ///
    /// **`authorizationCode` is required and this method cannot be called without one.** Apple's
    /// account-deletion requirement is that an app offering Sign in with Apple calls the revocation
    /// endpoint at deletion; `/auth/revoke` needs a token; a token exists only if the server
    /// exchanged the authorization code at sign-in. `AppleIdentityCredential` therefore carries it
    /// as a non-optional, so a sign-in that could not keep R3's promise cannot be *expressed* here
    /// rather than being caught at the far end.
    ///
    /// - Parameters:
    ///   - deviceUUID: `app_state.deviceUUID`. Supplying it registers and claims the device in the
    ///     same round trip.
    ///   - licenseVersion: `AccountLinkRecord`'s consent. See `OIDCRequest` for why the *absence* of
    ///     an answer and an answer of "declined" are two different bodies.
    public func exchangeApple(
        _ credential: AppleIdentityCredential,
        deviceUUID: UUID?,
        licenseVersion: LicenseAnswer
    ) async throws -> SessionCredentials {
        let body = OIDCRequest(
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            nonce: credential.rawNonce,
            deviceUUID: deviceUUID,
            licenseVersion: licenseVersion
        )
        let (data, response) = try await http.send(try post("auth/oidc", body: body))
        return try AuthResponse.decode(SessionCredentials.self, data: data, response: response)
    }

    // MARK: - POST /auth/refresh

    /// Rotates the refresh token and mints a new access token.
    ///
    /// Throws the taxonomy — `.unauthorized` for a spent or replayed token. `SessionTransport` is
    /// what turns that into a *transport* failure rather than an item failure; this method reports
    /// what the service said and decides nothing.
    public func refresh(refreshToken: String) async throws -> SessionCredentials {
        let (data, response) = try await http.send(
            try post("auth/refresh", body: RefreshRequest(refreshToken: refreshToken))
        )
        return try AuthResponse.decode(SessionCredentials.self, data: data, response: response)
    }

    // MARK: - POST /devices/register

    /// Exchanges `app_state.deviceUUID` for the device token that authorizes `POST /sync` for items
    /// carrying a `deviceID` and no `userID` (§5.8, D9).
    ///
    /// Re-registering retires whatever token was live over this installation, which is the server's
    /// choice and is worth knowing here: calling this on every launch would sign the previous launch
    /// out. `AppSession.bootstrap()` registers only when there is nothing live to use.
    public func registerDevice(deviceUUID: UUID) async throws -> DeviceCredential {
        let (data, response) = try await http.send(
            try post("devices/register", body: RegisterDeviceRequest(deviceUUID: deviceUUID))
        )
        // The wire answers a token and an expiry; **this call is the only place that knows which
        // installation it was minted for**, so it is where the two are paired. See
        // `DeviceCredential`'s header for what happens when nothing pairs them.
        let registration = try AuthResponse.decode(DeviceRegistration.self, data: data, response: response)
        return DeviceCredential(registration, deviceUUID: deviceUUID)
    }

    // MARK: - Bodies

    /// Whether the person answered the license row, and what they said.
    ///
    /// **Three states, not two, and spec §5.6 is why.** "A missing `licenseVersion` is a *declined*
    /// consent and must arrive as an explicit null rather than an omitted field the server
    /// defaults" — and the server reads absent, null and a string as three different facts
    /// (`consent` in `server/internal/api/auth.go`), because the claim sweep is re-run for reasons
    /// that have nothing to do with consent and a body that wrote on every call withdrew one.
    public enum LicenseAnswer: Sendable, Hashable {
        /// This request is not about consent. The key is omitted.
        case unstated
        /// The row was unchecked. The key travels as an explicit `null`.
        case declined
        /// The version consented to, `LicenseConsent.currentVersion`.
        case accepted(String)
    }

    struct OIDCRequest: Encodable {
        let identityToken: String
        let authorizationCode: String
        let nonce: String
        let deviceUUID: UUID?
        let licenseVersion: LicenseAnswer

        enum CodingKeys: String, CodingKey {
            case identityToken = "identity_token"
            case authorizationCode = "authorization_code"
            case nonce
            case deviceUUID = "device_uuid"
            case licenseVersion = "license_version"
        }

        /// Written by hand because the synthesized encoder cannot express the difference between an
        /// omitted key and a null one — `encodeIfPresent` omits, `encode` on an optional writes
        /// null, and only a hand-written body chooses per case.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identityToken, forKey: .identityToken)
            try container.encode(authorizationCode, forKey: .authorizationCode)
            try container.encode(nonce, forKey: .nonce)
            try container.encodeIfPresent(deviceUUID, forKey: .deviceUUID)
            switch licenseVersion {
            case .unstated:
                break
            case .declined:
                try container.encodeNil(forKey: .licenseVersion)
            case let .accepted(version):
                try container.encode(version, forKey: .licenseVersion)
            }
        }
    }

    struct RefreshRequest: Encodable {
        let refreshToken: String
        enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
    }

    struct RegisterDeviceRequest: Encodable {
        let deviceUUID: UUID
        enum CodingKeys: String, CodingKey { case deviceUUID = "device_uuid" }
    }

    /// `appendingPathComponent`, so a base URL with or without a trailing slash behaves the same.
    ///
    /// The service decodes request bodies with `DisallowUnknownFields`, so an additive key here is
    /// a `validation_failed` on the whole request rather than a field quietly dropped. That is the
    /// server's deliberate choice and it means the bodies above are exact, not approximate.
    private func post(_ path: String, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try AuthCoding.encoder.encode(body)
        return request
    }
}
