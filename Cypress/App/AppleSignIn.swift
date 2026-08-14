//
//  AppleSignIn.swift
//  Cypress — App
//
//  Screen 15's `Continue with Apple`, from the tap to the credential `POST /auth/oidc` needs
//  (spec §5.2, §10 step 5, RULINGS **R72** ruling 2).
//
//  ── Why this file is in `App` and not in `Data` ─────────────────────────────────────────────────
//
//  `AuthenticationServices` presents a sheet, and a sheet needs an `ASPresentationAnchor`, which is
//  a `UIWindow`. ARCHITECTURE §2 keeps `Data` free of UI frameworks, and `Data` already holds
//  everything about this exchange that is *not* the sheet: `AuthNonce` is the replay recipe,
//  `AppleIdentityCredential` is what the sheet yields reduced to three strings, and
//  `AuthClient.exchangeApple` is the wire. So the window-shaped part lives here, in the composition
//  root, for the reason identity questions already live here — `RootView.accountLink()`'s header.
//
//  The #158 session round predicted this and put it as a fork: either `accountLink()` stops being
//  `nonisolated`, or something new is threaded to it. It is the second. (That finding is written up
//  for the errata and carries no number yet, so there is nothing here to cite — see #158's own
//  history for it.) `AppleSignIn` is a `Sendable` value holding one closure, so the
//  `@Sendable` closure the composition root forms can capture it and still carry nothing of the
//  view; the hop to `@MainActor` happens inside `AppleSignInController`, at the point the window is
//  actually needed.
//
//  ── What is testable here, and what is not ──────────────────────────────────────────────────────
//
//  Nobody may sign a real Apple Account into a simulator to prove this, and no test in this
//  repository does. The split below is drawn on exactly that line:
//
//  - `AppleAuthorizationAttempt` and `AppleSignInRecipe` are pure and are tested
//    (`CypressTests/AppleSignInTests.swift`). Between them they own the three things that are wrong
//    far more often than they are right — which value Apple is handed, which value the server is
//    handed, and that those two are the **same** nonce — plus the mapping from
//    `ASAuthorizationError` to this app's own vocabulary.
//  - `AppleSignInController` is the sheet. Only `authorize()` presents; everything it decides is on
//    `preparedRequest()` and `credential(identityToken:authorizationCode:)`, and a test drives both
//    on a real instance without presenting anything.
//
//  **This paragraph used to say the controller "holds no logic beyond delegate plumbing, and every
//  decision it could get wrong has been moved into the enum above it", and that was false** (review
//  of PR #84, F2). It held exactly one: that the nonce given to `prepare` was the nonce given to
//  `credential`. Replacing the second with `AuthNonce.random()` left the whole suite green while
//  every real sign-in would have failed the server's `nonceMatches`. The sentence is true now
//  because the type changed, not because the sentence was reworded.
//

import AuthenticationServices
import Foundation

// MARK: - The pure half

/// Apple's recipe, reduced to the decisions that can be made wrongly.
enum AppleSignInRecipe {

    /// What a sign-in that Apple answered, but answered incompletely, is.
    ///
    /// Its own case rather than a `SessionError`: nothing about the *session* went wrong, the
    /// authorization did — and `/auth/oidc` refuses an empty `identity_token` or
    /// `authorization_code` with `validation_failed` anyway
    /// (`server/internal/api/auth.go`, `authOIDC`), so sending one would be a round trip to be told
    /// what is already known here.
    struct Incomplete: Error, Equatable {
        /// Which of the two was missing, for a failure somebody can act on.
        let missing: String
    }

    /// The scopes screen 15's Apple button asks for.
    ///
    /// **`.email` and not `.fullName`, and both halves are a decision.**
    ///
    /// The address: `server/internal/store/identity.go` has a nullable `users.email` and an upsert
    /// whose own comment reasons about "a later sign-in carrying none", so the service was built in
    /// this same ticket to receive one and to survive its absence. Requesting it types nothing into
    /// anything — R72 ruling 2's "no address typed into anything" is kept — and Apple's own sheet
    /// offers Hide My Email, which is the private-relay address `server/internal/apple/apple.go`
    /// already names.
    ///
    /// The name: nothing in this app has anywhere to put one. DECISIONS §3.11 makes contribution
    /// feeds private by default, `User.publicAttribution` is false until somebody turns it on, and
    /// screen 15 collects no name. Asking for a real name in order to discard it is collection
    /// without a use, which is the thing DECISIONS §3 is a charter against.
    ///
    /// ── The half that is cheap in code and not cheap in population (review of PR #84, F5) ──────
    ///
    /// Apple returns `fullName` **only on the first authorization** for a given Apple ID and app.
    /// Every later sign-in carries nil there until the person revokes the app under Settings → Apple
    /// ID → Sign in with Apple. So adding `.fullName` in a later ticket collects names from **new
    /// users only, permanently** — everybody who signed in before that ticket is past their one
    /// chance. Nothing stored bakes the decision in and reversing the line is a one-word edit, but
    /// the population it can still reach shrinks with every sign-in, which is a fact the owner
    /// should have before ship rather than after.
    ///
    /// **The same one-shot rule is what makes the email half robust, pointing the other way.**
    /// `ASAuthorizationAppleIDCredential.email` is first-authorization-only too — so a client that
    /// read the address off the *credential* would have it once and never again. This app does not
    /// read it at all: the address travels inside the identity token, whose `email` claim is not
    /// first-authorization-only, and the server takes it from the **verified** token
    /// (`server/internal/apple/apple.go`). That is why `AppleIdentityCredential` has no email field
    /// and why nothing here looks for one.
    static let requestedScopes: [ASAuthorization.Scope] = [.email]

    /// Apple's error vocabulary, translated into screen 15's.
    ///
    /// Only `.canceled` is singled out, and it is the one that matters: somebody who opened the
    /// sheet and dismissed it has not had anything go wrong, and `AccountAskCopy.noticeFailed` —
    /// *"That did not go through"* — would be a claim about them that is not true. Everything else
    /// travels unchanged and reaches `AccountAskModel.link`'s general `catch`, which is the honest
    /// place for an authorization that really did fail.
    ///
    /// `.unknown` is deliberately **not** folded in with cancellation. It is what a sheet that could
    /// not be presented reports, and a build with no entitlement is exactly that; reading it as
    /// "somebody tapped cancel" would draw silence over a misconfiguration and there would be
    /// nothing on the screen or in the code saying so.
    static func refusal(for error: any Error) -> any Error {
        guard let authorization = error as? ASAuthorizationError else { return error }
        return authorization.code == .canceled ? AccountLinkRefusal.cancelled : error
    }
}

// MARK: - One authorization, and the nonce that has to be the same at both ends

/// A single Sign in with Apple authorization, holding the one value that must not differ between its
/// two ends.
///
/// ── Why this type exists, which is a defect a reviewer proved rather than a tidy-up ─────────────
///
/// `prepare` and `credential` used to be free functions each taking a `nonce:` argument, and
/// `AppleSignInController` passed one to each. Nothing observed that it passed the **same** one.
/// Review of PR #84 (F2) replaced the second call's argument with `AuthNonce.random()` — a nonce
/// Apple never saw — and the entire suite stayed green: `Test run with 1474 tests in 149 suites
/// passed`, plus all three UI tests. Every real sign-in would have failed `nonceMatches` on the
/// server, and nothing anywhere would have said why.
///
/// That pairing *is* the replay defense (`AuthNonce`, `server/internal/api/auth.go`), so it is now a
/// property of a value rather than a convention between two call sites: there is no `nonce:`
/// parameter left to disagree with, and `AppleSignInRecipeTests` asserts
/// `SHA256(credential.rawNonce) == request.nonce` across a real controller instance.
///
/// **One per authorization.** The nonce is minted in `init` and never stored anywhere else. A nonce
/// reused across two sign-ins is a nonce that no longer proves this exchange is fresh, which is why
/// `AppleSignIn.freshAttempt` is a function and is tested as one.
struct AppleAuthorizationAttempt: Sendable {

    /// This authorization's nonce. Raw; `hashedForApple` is what Apple is handed.
    let nonce: AuthNonce

    init(nonce: AuthNonce = .random()) {
        self.nonce = nonce
    }

    /// Fills in the request Apple is given. **The nonce it carries is the hash, never the raw
    /// value** — see `AuthNonce`, where the whole recipe is written down.
    ///
    /// Testable without presenting anything: `ASAuthorizationAppleIDProvider().createRequest()` is
    /// object construction and needs no Apple Account, so a unit test builds a request, hands it
    /// here, and reads the property back.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = AppleSignInRecipe.requestedScopes
        request.nonce = nonce.hashedForApple
    }

    /// The three strings `/auth/oidc` needs, out of what the callback carried.
    ///
    /// Takes the two `Data?` values rather than the `ASAuthorizationAppleIDCredential` itself,
    /// because that type has no public initializer and a function taking it could not be called by
    /// any test. The delegate passes `credential.identityToken` and `credential.authorizationCode`
    /// straight in.
    ///
    /// **`rawNonce` is this attempt's raw nonce.** Handing `nonce.hashedForApple` here compiles,
    /// round-trips and defends nothing, because it is the value anybody holding the captured
    /// identity token already has. `server/internal/api/auth.go` refuses a sign-in with no nonce on
    /// either side so the check cannot be opted out of; this is the line that has to be right for it
    /// to mean anything.
    func credential(
        identityToken: Data?,
        authorizationCode: Data?
    ) throws -> AppleIdentityCredential {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8),
              !token.isEmpty else {
            throw AppleSignInRecipe.Incomplete(missing: "identity token")
        }
        guard let authorizationCode, let code = String(data: authorizationCode, encoding: .utf8),
              !code.isEmpty else {
            // Not a soft failure. Without the code the service never exchanges at Apple's
            // `/auth/token`, so it stores no refresh token, so `DELETE /me` cannot call the
            // revocation endpoint Apple requires of an app offering this button (R72 ruling 2,
            // RULINGS R3). `AppleIdentityCredential` makes it non-optional for the same reason.
            throw AppleSignInRecipe.Incomplete(missing: "authorization code")
        }
        return AppleIdentityCredential(identityToken: token, authorizationCode: code, rawNonce: nonce.raw)
    }
}

// MARK: - The value the composition root threads

/// One Sign in with Apple authorization, as a value.
///
/// A struct around a closure rather than a protocol, for `AccountAskLink`'s reason: the composition
/// root supplies the action, everything downstream takes it as given, and a test supplies its own
/// without a class to subclass or a framework to stand up.
struct AppleSignIn: Sendable {

    /// Generates the nonce, presents the sheet, and answers what the callback carried — or throws
    /// `AccountLinkRefusal.cancelled`, `AppleSignInRecipe.Incomplete`, or whatever
    /// `AuthenticationServices` reported.
    typealias Authorize = @Sendable () async throws -> AppleIdentityCredential

    private let authorize: Authorize

    init(authorize: @escaping Authorize) {
        self.authorize = authorize
    }

    func callAsFunction() async throws -> AppleIdentityCredential {
        try await authorize()
    }

    /// A fresh authorization, with a fresh nonce.
    ///
    /// A named function rather than an expression inside `system`'s closure, so that "one nonce per
    /// authorization" is a property of a value a test can call twice — the closure below cannot be
    /// called by a test at all, because calling it presents a sheet. Hoisting this to a `static let`
    /// would reuse one nonce across every sign-in in the process, and that mutation now goes red.
    static let freshAttempt: @Sendable () -> AppleAuthorizationAttempt = { AppleAuthorizationAttempt() }

    /// The real one: `ASAuthorizationController`, over the app's own window.
    static let system = AppleSignIn {
        try await AppleSignInController(attempt: freshAttempt()).authorize()
    }

    /// What `RootView` uses when nobody supplied one.
    ///
    /// In a Release build this is `system` and the expression is one dictionary lookup that finds
    /// nothing. In DEBUG a launching test may pin a **refusal** — see `DebugAppleSignInOverride`,
    /// and read its header for why there is no way to pin a *success*.
    ///
    /// `nonisolated`, because it is `RootView.init`'s default argument and a default argument is
    /// evaluated outside the initializer's isolation. It reads the environment and builds a value;
    /// the `@MainActor` hop is inside `AppleSignInController`, where the window is.
    static func launchDefault() -> AppleSignIn {
        #if DEBUG
        if let pinned = DebugAppleSignInOverride.resolve() { return pinned }
        #endif
        return system
    }
}

// MARK: - The sheet

/// The `ASAuthorizationController` delegate, kept alive for exactly one authorization.
///
/// `@MainActor` because `ASPresentationAnchor` is a `UIWindow` and the controller must be driven
/// from the main thread. Nothing here decides anything: it presents, and hands both outcomes to
/// `AppleSignInRecipe`.
@MainActor
final class AppleSignInController: NSObject {

    /// The authorization this controller is running. **Both ends read it**, which is the whole of
    /// F2's repair — see `AppleAuthorizationAttempt`.
    let attempt: AppleAuthorizationAttempt

    private var continuation: CheckedContinuation<AppleIdentityCredential, any Error>?
    private var retained: ASAuthorizationController?

    /// Internal rather than private, and that is the point: a test constructs one of these and
    /// drives `preparedRequest()` and `credential(identityToken:authorizationCode:)` — the two calls
    /// the delegate makes — without ever calling `authorize()`, which is the only method that
    /// presents anything.
    init(attempt: AppleAuthorizationAttempt) {
        self.attempt = attempt
    }

    /// The request Apple is given, prepared by this controller's own attempt.
    func preparedRequest() -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        attempt.prepare(request)
        return request
    }

    /// What the callback becomes, built by this controller's own attempt.
    func credential(identityToken: Data?, authorizationCode: Data?) throws -> AppleIdentityCredential {
        try attempt.credential(identityToken: identityToken, authorizationCode: authorizationCode)
    }

    /// One authorization. The controller and this delegate are held by the continuation's closure
    /// for the duration and released when it resumes — an `ASAuthorizationController` whose delegate
    /// has been deallocated calls nobody back, and a sign-in that never calls back is a spinner that
    /// never stops.
    func authorize() async throws -> AppleIdentityCredential {
        let controller = ASAuthorizationController(authorizationRequests: [preparedRequest()])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.retained = controller
            controller.performRequests()
        }
    }

    /// Resumes once and only once. `ASAuthorizationController` is not documented to call exactly one
    /// of its two callbacks exactly once, and resuming a continuation twice is a crash rather than a
    /// warning.
    private func finish(_ result: Result<AppleIdentityCredential, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        retained = nil
        continuation.resume(with: result)
    }
}

extension AppleSignInController: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
            // The request asked for an Apple ID authorization and nothing else, so this is not a
            // reachable state — but it is a state whose *silent* handling would be a sheet that
            // closed and did nothing, which is the failure this screen's whole notice line exists
            // to prevent.
            finish(.failure(AppleSignInRecipe.Incomplete(missing: "an Apple ID credential")))
            return
        }
        // Straight into the tested pair. There is deliberately nothing to decide in this method:
        // which nonce the credential carries is `attempt`'s, and `AppleSignInRecipeTests` asserts
        // that it is the same one `preparedRequest()` hashed for Apple.
        finish(Result {
            try credential(
                identityToken: apple.identityToken,
                authorizationCode: apple.authorizationCode
            )
        })
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        finish(.failure(AppleSignInRecipe.refusal(for: error)))
    }
}

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {

    /// The window the sheet hangs off.
    ///
    /// Resolved at presentation time rather than captured at construction, so nothing about the
    /// window travels through `RootView.accountLink()`'s `@Sendable` closure — which is what lets
    /// that closure stay `nonisolated` and carry nothing of the view.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? scenes.compactMap(\.keyWindow).first
            ?? scenes.first?.windows.first
        // `ASPresentationAnchor` is non-optional and there is no honest fallback: an app with no
        // window has no screen to present over, so a bare one is returned rather than trapping here.
        //
        // **What happens next is deliberately not asserted** (review of PR #84, F6). This comment
        // used to claim that "an empty anchor makes `AuthenticationServices` report its own error,
        // which reaches the notice line" — an invariant nobody verified, and not one this repository
        // can verify without presenting a real sheet. What is known and worth writing down is the
        // narrow half: returning a window is required by the signature, `?? ASPresentationAnchor()`
        // is what a process with no window scene gets, and the branch is unreachable while the app
        // has one. Whether Apple then errors or does something else is Apple's, and untested here.
        return window ?? ASPresentationAnchor()
    }
}
