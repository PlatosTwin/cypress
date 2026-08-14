import AuthenticationServices
import Foundation
import Testing
@testable import Cypress

/// `AppleSignInRecipe` — the decidable half of screen 15's `Continue with Apple` (#158 step 5).
///
/// ── The proof boundary, stated before the first assertion ────────────────────────────────────────
///
/// **No test in this repository may use a real Apple credential, and none does.** Nobody signs an
/// Apple Account into a simulator here; the real end-to-end tap is the owner's, on a device, after
/// merge. What is provable without one is everything from the *callback* onward, and this suite owns
/// the part of that which is pure: which value Apple is handed, which value the server is handed,
/// what an incomplete authorization is, and how Apple's error vocabulary becomes this app's.
///
/// `AccountLinkTests` owns the rest of the boundary — callback to stored session, with a scripted
/// transport. Between them nothing on the path is unmeasured except the sheet itself, which holds no
/// decision (`AppleSignInController`).
///
/// ── Why the nonce tests are the load-bearing ones ────────────────────────────────────────────────
///
/// The Apple recipe has exactly one inversion available and it is invisible from either end: send
/// the *hash* to the server instead of the raw value and everything compiles, round-trips and
/// returns 200, while the replay defense is worth nothing — the hash is the value anybody holding a
/// captured identity token already has. `server/internal/api/auth.go` refuses a sign-in with no
/// nonce on either side so the check cannot be opted out of, and its comment says the client "will
/// be written against" that contract. These are the tests that make that true.
@Suite("Sign in with Apple · the recipe")
struct AppleSignInRecipeTests {

    private let nonce = AuthNonce(raw: "3f2a-raw-nonce-value")

    // MARK: - What Apple is handed

    /// `ASAuthorizationAppleIDProvider().createRequest()` constructs an object and asks nothing of
    /// anybody — no Apple Account, no entitlement check, no network — so the one line that has to be
    /// right can be read straight off the request.
    @Test("the request Apple is given carries the hash, never the raw nonce")
    func requestCarriesTheHash() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        AppleSignInRecipe.prepare(request, nonce: nonce)

        #expect(
            request.nonce == nonce.hashedForApple,
            """
            ASAuthorizationAppleIDRequest.nonce is \(request.nonce ?? "nil"). Apple puts this value \
            in the identity token's `nonce` claim and the server hashes the raw value and compares, \
            so anything but the SHA-256 hex makes every sign-in fail the server's check.
            """
        )
        #expect(
            request.nonce != nonce.raw,
            """
            the RAW nonce was handed to Apple. The token's claim would then be the hash of the hash, \
            `nonceMatches` would refuse every sign-in, and the failure would look like a server \
            defect from the app and like a client defect from the server.
            """
        )
    }

    /// The scope decision, pinned so that widening it is a deliberate act rather than an edit.
    /// `.fullName` is the one that would matter: nothing in this app has anywhere to put a name, and
    /// DECISIONS §3 is a charter against collecting what has no use.
    @Test("the request asks for an address and never for a name")
    func requestScopes() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        AppleSignInRecipe.prepare(request, nonce: nonce)

        let scopes = request.requestedScopes ?? []
        #expect(scopes == [.email])
        #expect(
            !scopes.contains(.fullName),
            "screen 15 asked Apple for a real name. Nothing in this app stores one (DECISIONS §3.11)"
        )
    }

    // MARK: - What the server is handed

    @Test("the credential built from the callback carries the RAW nonce, not the hash")
    func credentialCarriesTheRawNonce() throws {
        let credential = try AppleSignInRecipe.credential(
            identityToken: Data("identity.jwt".utf8),
            authorizationCode: Data("code-1".utf8),
            nonce: nonce
        )

        #expect(credential.identityToken == "identity.jwt")
        #expect(credential.authorizationCode == "code-1")
        #expect(
            credential.rawNonce == nonce.raw,
            """
            the credential carries \(credential.rawNonce), which is not the raw nonce. This value \
            travels to POST /auth/oidc as `nonce`; sending the hash forwards the value an attacker \
            holding the token already has, and the server cannot tell the difference.
            """
        )
        #expect(credential.rawNonce != nonce.hashedForApple)
    }

    /// R72 ruling 2: without the authorization code the service never exchanges at Apple's
    /// `/auth/token`, so it stores no refresh token, so `DELETE /me` cannot call the revocation
    /// endpoint Apple requires. A sign-in missing it must not proceed.
    @Test("an authorization missing either half refuses instead of signing in")
    func incompleteAuthorizationRefuses() {
        let cases: [(String, Data?, Data?)] = [
            ("identity token", nil, Data("code".utf8)),
            ("identity token", Data("".utf8), Data("code".utf8)),
            ("authorization code", Data("token".utf8), nil),
            ("authorization code", Data("token".utf8), Data("".utf8)),
        ]

        for (missing, token, code) in cases {
            #expect(throws: AppleSignInRecipe.Incomplete(missing: missing)) {
                try AppleSignInRecipe.credential(identityToken: token, authorizationCode: code, nonce: nonce)
            }
        }
    }

    // MARK: - Apple's errors, in this app's vocabulary

    /// The cancel path. `AccountAskCopy.noticeFailed` — "That did not go through" — is a claim about
    /// somebody who dismissed a sheet, and it is not true of them.
    @Test("a dismissed sheet becomes the refusal that draws nothing")
    func cancellationBecomesSilence() {
        let cancelled = ASAuthorizationError(.canceled)
        #expect(AppleSignInRecipe.refusal(for: cancelled) as? AccountLinkRefusal == .cancelled)
    }

    /// And the other half, which is the one a lazy mapping gets wrong: `.unknown` is what a sheet
    /// that could not be presented reports, and a build with no `com.apple.developer.applesignin`
    /// entitlement is exactly that. Reading it as a cancellation would draw silence over a
    /// misconfiguration, with nothing anywhere saying so.
    @Test("every other Apple error survives as itself, including the one a missing entitlement gives")
    func otherErrorsSurvive() {
        for code in [ASAuthorizationError.Code.unknown, .failed, .invalidResponse, .notHandled] {
            let error = ASAuthorizationError(code)
            let refused = AppleSignInRecipe.refusal(for: error)
            #expect(
                refused as? AccountLinkRefusal == nil,
                "ASAuthorizationError.\(code) was folded into a refusal and would draw no notice at all"
            )
            #expect((refused as? ASAuthorizationError)?.code == code)
        }
    }

    /// A non-`ASAuthorizationError` is not Apple's to interpret and passes straight through.
    @Test("an error that is not Apple's is left alone")
    func foreignErrorsPassThrough() {
        let refused = AppleSignInRecipe.refusal(for: APIError.serverError)
        #expect(refused as? APIError == .serverError)
    }
}

/// The DEBUG launch seam that lets a UI test look at the two states a simulator can otherwise never
/// reach. Its grammar is tested here so that a typo in a launch environment is a red test rather
/// than a silently-real Apple sheet in the middle of a UI run.
@Suite("Sign in with Apple · the DEBUG refusal seam")
struct DebugAppleSignInOverrideTests {

    @Test("the two refusals parse, and nothing else does")
    func grammar() {
        #expect(DebugAppleSignInOverride.parse("cancel") == .cancel)
        #expect(DebugAppleSignInOverride.parse("fail") == .fail)
        #expect(DebugAppleSignInOverride.parse("success") == .invalid(raw: "success"))
        #expect(DebugAppleSignInOverride.parse("Cancel") == .invalid(raw: "Cancel"))
    }

    @Test("an absent variable pins nothing")
    func absenceIsNotAnOverride() {
        #expect(DebugAppleSignInOverride.requested([:]) == nil)
        #expect(DebugAppleSignInOverride.requested([DebugAppleSignInOverride.environmentKey: "  "]) == nil)
        #expect(DebugAppleSignInOverride.resolve([:]) == nil)
    }

    /// **The boundary this seam exists to keep**: it can refuse and it cannot succeed. A pinned
    /// success would have to hand `AppSession.signInWithApple` a forged credential, which is a
    /// mutated build talking to `cypress-sync`. Asserted rather than merely written down, because
    /// "there is no success case" is exactly the kind of sentence a later edit makes false.
    @Test("no value pins a success, so no mutated build can reach the service")
    func nothingPinsASuccess() async throws {
        for raw in ["cancel", "fail", "success", "ok", "true", ""] {
            guard let pinned = DebugAppleSignInOverride.resolve(
                [DebugAppleSignInOverride.environmentKey: raw]
            ) else { continue }

            await #expect(throws: (any Error).self, "CYPRESS_APPLE_SIGN_IN=\(raw) produced a credential") {
                _ = try await pinned()
            }
        }
    }

    @Test("cancel pins the silent refusal and fail pins a failure that is not it")
    func eachValuePinsItsOwnOutcome() async throws {
        let cancel = try #require(
            DebugAppleSignInOverride.resolve([DebugAppleSignInOverride.environmentKey: "cancel"])
        )
        await #expect(throws: AccountLinkRefusal.cancelled) { _ = try await cancel() }

        let fail = try #require(
            DebugAppleSignInOverride.resolve([DebugAppleSignInOverride.environmentKey: "fail"])
        )
        await #expect(throws: DebugAppleSignInOverride.PinnedFailure()) { _ = try await fail() }
    }
}
