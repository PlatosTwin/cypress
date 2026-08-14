//
//  DebugAppleSignInOverride.swift
//  Cypress — App
//
//  The test-only way to pin what screen 15's Apple button does, so that the two states a UI test can
//  otherwise never reach are reachable on a simulator. `#if DEBUG`, read from the launch
//  environment, for `DebugDeepLink.environmentKey`'s reasons.
//
//  ── The one thing this seam deliberately cannot do ──────────────────────────────────────────────
//
//  **There is no `success`.** Every value below refuses, and none of them reaches the network. That
//  is the boundary, written as code rather than as a rule somebody has to remember: a pinned success
//  would have to hand `AppSession.signInWithApple` a credential, which would `POST /auth/oidc` at
//  `cypress-sync` with a forged token — a mutated build talking to production, which is the thing
//  #158's briefs forbid outright. The success path is proven where it can be proven honestly:
//  `CypressTests/AccountLinkTests.swift` drives it end to end with a scripted transport and a stub
//  authorization, from the callback to the stored session.
//
//  So what a UI test gets from this file is exactly the pair of states that are about *drawing*:
//  a cancelled sheet must leave screen 15 as SCREENS.md draws it, and a failed authorization must
//  put the one unspecified line under the buttons. Both are claims about pixels, and pixels are what
//  a UI test is for.
//

#if DEBUG
import Foundation

/// See the file header. `#if DEBUG`; unreachable from the app.
enum DebugAppleSignInOverride {

    static let environmentKey = "CYPRESS_APPLE_SIGN_IN"

    /// The refusals a launch may pin.
    ///
    /// Spelled as the outcome rather than as an Apple error code, because what a test is asserting
    /// is what the screen does — and because `ASAuthorizationError` is a vocabulary this app
    /// translates out of at exactly one place (`AppleSignInRecipe.refusal(for:)`) and should not
    /// re-learn here.
    ///
    ///     CYPRESS_APPLE_SIGN_IN=cancel    the sheet was dismissed — screen 15 must say nothing
    ///     CYPRESS_APPLE_SIGN_IN=fail      the authorization failed — the notice line must draw
    enum Request: Equatable {
        case cancel
        case fail
        /// An unrecognized value, kept distinct from an absence for `DebugLocationOverride`'s
        /// reason: a seam that quietly did nothing would leave a test asserting the cancelled state
        /// against a build that presents the real Apple sheet, and the failure would surface
        /// somewhere else entirely.
        case invalid(raw: String)
    }

    /// What this build's own error type is for a pinned `fail`.
    ///
    /// A distinct type rather than `AppleSignInRecipe.Incomplete`, so that nothing in the app's real
    /// failure vocabulary is reachable only through a test seam.
    struct PinnedFailure: Error, Equatable {}

    static func requested(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Request? {
        guard let raw = environment[environmentKey]?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return parse(raw)
    }

    /// The grammar, in one place so it can be tested without a process.
    static func parse(_ raw: String) -> Request {
        switch raw {
        case "cancel": return .cancel
        case "fail":   return .fail
        default:       return .invalid(raw: raw)
        }
    }

    /// The pinned action, or nil when this launch asked for nothing.
    ///
    /// An `invalid` value resolves to `nil`, which restores the real button — the same choice as a
    /// missing variable, and deliberately not a crash, because this is a DEBUG seam and a typo in a
    /// launch environment should not take the app down. What makes the typo visible is
    /// `DebugAppleSignInOverrideTests`, which asserts the grammar directly, plus the UI test's own
    /// assertion failing on the state it expected.
    static func resolve(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppleSignIn? {
        switch requested(environment) {
        case .cancel:  return AppleSignIn { throw AccountLinkRefusal.cancelled }
        case .fail:    return AppleSignIn { throw PinnedFailure() }
        case .invalid: return nil
        case nil:      return nil
        }
    }
}
#endif
