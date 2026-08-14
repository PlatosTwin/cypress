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
//  `docs/errata-pending/158-the-session-lands-and-the-sign-in-sheet-cannot.md` §1 predicted this and
//  put it as a fork: either `accountLink()` stops being `nonisolated`, or something new is threaded
//  to it. It is the second. `AppleSignIn` is a `Sendable` value holding one closure, so the
//  `@Sendable` closure the composition root forms can capture it and still carry nothing of the
//  view; the hop to `@MainActor` happens inside `AppleSignInController`, at the point the window is
//  actually needed.
//
//  ── What is testable here, and what is not ──────────────────────────────────────────────────────
//
//  Nobody may sign a real Apple Account into a simulator to prove this, and no test in this
//  repository does. The split below is drawn on exactly that line:
//
//  - `AppleSignInRecipe` is pure and is tested (`CypressTests/AppleSignInTests.swift`). It owns the
//    two things that are wrong far more often than they are right — which value Apple is handed and
//    which value the server is handed — and the mapping from `ASAuthorizationError` to this app's
//    own vocabulary.
//  - `AppleSignInController` is the sheet. It is not tested, it holds no logic beyond delegate
//    plumbing, and every decision it could get wrong has been moved into the enum above it.
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
    static let requestedScopes: [ASAuthorization.Scope] = [.email]

    /// Fills in an authorization request. **The nonce Apple is given is the hash, never the raw
    /// value** — see `AuthNonce`, which is where the whole recipe is written down.
    ///
    /// Separated from the controller so that this one line can be asserted by a test that presents
    /// nothing: `ASAuthorizationAppleIDProvider().createRequest()` is object construction and needs
    /// no Apple Account, so a unit test can build a request, hand it to this function, and read the
    /// property back.
    static func prepare(_ request: ASAuthorizationAppleIDRequest, nonce: AuthNonce) {
        request.requestedScopes = requestedScopes
        request.nonce = nonce.hashedForApple
    }

    /// The three strings `/auth/oidc` needs, out of what the callback carried.
    ///
    /// Takes the two `Data?` values rather than the `ASAuthorizationAppleIDCredential` itself,
    /// because that type has no public initializer and a function taking it could not be called by
    /// any test. The delegate below passes `credential.identityToken` and
    /// `credential.authorizationCode` straight in.
    ///
    /// **`rawNonce` is `nonce.raw`.** Handing `nonce.hashedForApple` here compiles, round-trips and
    /// defends nothing, because it is the value anybody holding the captured identity token already
    /// has. `server/internal/api/auth.go` refuses a sign-in with no nonce on either side so that the
    /// check cannot be opted out of; this is the line that has to be right for it to mean anything.
    static func credential(
        identityToken: Data?,
        authorizationCode: Data?,
        nonce: AuthNonce
    ) throws -> AppleIdentityCredential {
        guard let identityToken, let token = String(data: identityToken, encoding: .utf8),
              !token.isEmpty else {
            throw Incomplete(missing: "identity token")
        }
        guard let authorizationCode, let code = String(data: authorizationCode, encoding: .utf8),
              !code.isEmpty else {
            // Not a soft failure. Without the code the service never exchanges at Apple's
            // `/auth/token`, so it stores no refresh token, so `DELETE /me` cannot call the
            // revocation endpoint Apple requires of an app offering this button (R72 ruling 2,
            // RULINGS R3). `AppleIdentityCredential` makes it non-optional for the same reason.
            throw Incomplete(missing: "authorization code")
        }
        return AppleIdentityCredential(identityToken: token, authorizationCode: code, rawNonce: nonce.raw)
    }

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

    /// The real one: `ASAuthorizationController`, over the app's own window.
    ///
    /// The nonce is minted **here**, one per authorization, and never stored. A nonce reused across
    /// two sign-ins is a nonce that no longer proves this exchange is fresh.
    static let system = AppleSignIn {
        let nonce = AuthNonce.random()
        return try await AppleSignInController.authorize(nonce: nonce)
    }

    /// What `RootView` uses when nobody supplied one.
    ///
    /// In a Release build this is `system` and the expression is one dictionary lookup that finds
    /// nothing. In DEBUG a launching test may pin a **refusal** — see `DebugAppleSignInOverride`,
    /// and read its header for why there is no way to pin a *success*.
    @MainActor
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

    /// One authorization. The controller and this delegate are held by the continuation's closure
    /// for the duration and released when it resumes — an `ASAuthorizationController` whose delegate
    /// has been deallocated calls nobody back, and a sign-in that never calls back is a spinner that
    /// never stops.
    static func authorize(nonce: AuthNonce) async throws -> AppleIdentityCredential {
        let delegate = AppleSignInController(nonce: nonce)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        AppleSignInRecipe.prepare(request, nonce: nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate

        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            delegate.retained = controller
            controller.performRequests()
        }
    }

    private let nonce: AuthNonce
    private var continuation: CheckedContinuation<AppleIdentityCredential, any Error>?
    private var retained: ASAuthorizationController?

    private init(nonce: AuthNonce) {
        self.nonce = nonce
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
        finish(Result {
            try AppleSignInRecipe.credential(
                identityToken: apple.identityToken,
                authorizationCode: apple.authorizationCode,
                nonce: nonce
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
        // window has no screen to present over. An empty anchor makes `AuthenticationServices`
        // report its own error, which reaches the notice line, rather than trapping here.
        return window ?? ASPresentationAnchor()
    }
}
