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
        AppleAuthorizationAttempt(nonce: nonce).prepare(request)

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
        AppleAuthorizationAttempt(nonce: nonce).prepare(request)

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
        let credential = try AppleAuthorizationAttempt(nonce: nonce).credential(
            identityToken: Data("identity.jwt".utf8),
            authorizationCode: Data("code-1".utf8)
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
                try AppleAuthorizationAttempt(nonce: nonce).credential(
                    identityToken: token, authorizationCode: code
                )
            }
        }
    }

    // MARK: - The two ends, connected

    /// **The seam a reviewer proved unobserved (PR #84, F2).**
    ///
    /// The two tests above prove the two *ends*: Apple gets the hash, the server gets the raw value.
    /// Nothing proved they were the same nonce. `AppleSignInController` used to pass one to `prepare`
    /// and another to `credential` by convention, and replacing the second with `AuthNonce.random()`
    /// left the entire suite green — `Test run with 1474 tests in 149 suites passed`, all three UI
    /// tests included — while every real sign-in would have failed `nonceMatches` on the server.
    ///
    /// Asserted across a **real `AppleSignInController`**, driving the two calls its delegate makes,
    /// because that object is where the pairing lives. `authorize()` is never called, so nothing is
    /// presented and no Apple Account is involved.
    ///
    /// The assertion is the server's own comparison run locally: hash what the credential carries and
    /// require it to equal what Apple was handed. That is `nonceMatches`
    /// (`server/internal/api/auth.go`) with the two sides swapped into one process.
    @MainActor
    @Test("the nonce Apple is given is the hash of the nonce the server is given")
    func theTwoEndsCarryOneNonce() throws {
        let controller = AppleSignInController(attempt: AppleAuthorizationAttempt())

        let request = controller.preparedRequest()
        let credential = try controller.credential(
            identityToken: Data("identity.jwt".utf8),
            authorizationCode: Data("code-1".utf8)
        )

        #expect(
            AuthNonce(raw: credential.rawNonce).hashedForApple == request.nonce,
            """
            the nonce sent to the server hashes to \(AuthNonce(raw: credential.rawNonce).hashedForApple), \
            and Apple was given \(request.nonce ?? "nothing"). These are the two halves of one replay \
            defense and they are not the same value, so the service's `nonceMatches` would refuse \
            every sign-in this build made — with nothing on either side able to say why.
            """
        )
        // And the pairing is not accidentally satisfied by both being empty.
        #expect(credential.rawNonce.isEmpty == false)
        #expect(request.nonce?.isEmpty == false)
    }

    /// One nonce per authorization. A reused nonce no longer proves that *this* exchange is fresh,
    /// which is the whole reason the value exists.
    ///
    /// `AppleSignIn.freshAttempt` is what `system` calls, and it is a named function precisely so a
    /// test can call it twice — `system`'s own closure cannot be called here, because calling it
    /// presents a sheet. Hoisting the attempt to a shared `static let` is the mutation this refuses.
    @Test("every authorization mints its own nonce")
    func eachAuthorizationGetsAFreshNonce() {
        let nonces = (0..<8).map { _ in AppleSignIn.freshAttempt().nonce.raw }

        #expect(
            Set(nonces).count == nonces.count,
            """
            \(nonces.count - Set(nonces).count) of \(nonces.count) authorizations reused a nonce. A \
            nonce shared between two sign-ins proves nothing about either of them being fresh.
            """
        )
        #expect(nonces.allSatisfy { $0.count == 64 }, "a nonce was not 32 hex-encoded random bytes")
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

    /// **The boundary this seam keeps**: every value it understands refuses, and none mints a
    /// credential.
    ///
    /// The claim used to be wider — "no mutated build can reach the service" — and review of PR #84
    /// (F1) showed that was a sentence about the wrong object. This file never kept the process off
    /// the network; the `CYPRESS_REMOTE` gate does, and until that review `DataLayer`'s session sat
    /// outside it. What is asserted here is what this seam can actually promise.
    @Test("no value this seam understands mints a credential")
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

    /// **A typo must never restore the real Apple sheet** (review of PR #84, F1).
    ///
    /// `resolve` used to answer `nil` for an unrecognized value, which is the same answer as an
    /// absent variable — so a misspelled key or value in either of the two UI tests that tap the
    /// button put a live system sheet on a CI runner whose simulator may have an Apple Account
    /// signed in. `DebugLocationOverride`'s rule, broken in this file: a typo must not be
    /// indistinguishable from a decision.
    ///
    /// Both halves are asserted, and the second is the one that makes the first a measurement: a
    /// mistyped value refuses **and** an absent one still leaves the real button alone, or no
    /// ordinary launch could sign in at all.
    @Test("a mistyped pin refuses and complains, while an absent one leaves the real button alone")
    func aTypoRefusesRatherThanRestoringTheSheet() async throws {
        let mistyped = try #require(
            DebugAppleSignInOverride.resolve([DebugAppleSignInOverride.environmentKey: "cancle"]),
            """
            a mistyped CYPRESS_APPLE_SIGN_IN resolved to nil, which is the answer an ABSENT variable \
            gets — so the build presents the real Apple sheet, and a UI test taps it on a runner.
            """
        )
        await #expect(throws: DebugAppleSignInOverride.Misconfigured(raw: "cancle")) {
            _ = try await mistyped()
        }

        let complaint = try #require(
            DebugAppleSignInOverride.complaint([DebugAppleSignInOverride.environmentKey: "cancle"]),
            "a mistyped pin refused silently, so a test waits out its timeout on a state nothing draws"
        )
        #expect(complaint.contains("cancle"), "the complaint did not quote what was actually set")

        // The control: nothing set is not a mistake.
        #expect(DebugAppleSignInOverride.resolve([:]) == nil)
        #expect(DebugAppleSignInOverride.complaint([:]) == nil)
    }
}
