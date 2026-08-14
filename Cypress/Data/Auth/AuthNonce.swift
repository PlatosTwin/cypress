//
//  AuthNonce.swift
//  Cypress — Data/Auth
//
//  The replay defense, and the one place the two halves of it are written down together.
//
//  Apple's recipe has three moving parts and gets misassembled in one direction far more often than
//  the other, so both are named here:
//
//  1. the app generates a random string — the **raw** nonce — and keeps it;
//  2. it hands `ASAuthorizationAppleIDRequest.nonce` the **SHA-256 hex** of that string, and Apple
//     puts that hash in the identity token's `nonce` claim;
//  3. the app sends the **raw** string to `POST /auth/oidc`, and the server hashes it and compares.
//
//  Sending the hash at step 3 compiles, round-trips, and defends nothing: it is the same value
//  anybody who captured the identity token already holds. `server/internal/api/auth.go` refuses a
//  sign-in with no nonce on either side precisely so this cannot be opted out of, and its comment
//  says the client "will be written against" that contract — this file is that client.
//

import CryptoKit
import Foundation

/// A raw nonce and the hash Apple is asked to echo.
///
/// `Data` imports CryptoKit the way `CityDownloader` does — a system library this layer's own job is
/// defined in terms of. ARCHITECTURE §2's direction rule is about UI frameworks and `Features`.
public struct AuthNonce: Sendable, Hashable {

    /// What travels to `POST /auth/oidc`.
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    /// 32 random bytes, hex-encoded. `SystemRandomNumberGenerator` is the platform CSPRNG.
    ///
    /// Hex rather than base64url because the value is compared as a string on the far side and hex
    /// has no case-sensitivity or padding question to get wrong.
    public static func random() -> AuthNonce {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        return AuthNonce(raw: Self.hex(bytes))
    }

    /// What `ASAuthorizationAppleIDRequest.nonce` is set to: lowercase SHA-256 hex of `raw`.
    ///
    /// Lowercase because the server lowercases the claim before comparing
    /// (`server/internal/api/auth.go`, `nonceMatches`), so an uppercase hash would match there and
    /// a mismatch here would be undiagnosable from either side.
    public var hashedForApple: String {
        Self.hex(Array(SHA256.hash(data: Data(raw.utf8))))
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
