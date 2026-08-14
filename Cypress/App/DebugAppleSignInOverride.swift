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
//  **There is no `success`.** Every value below refuses, and none of them mints a credential. A
//  pinned success would have to hand `AppSession.signInWithApple` one, and the success path is
//  proven where it can be proven honestly instead: `CypressTests/AccountLinkTests.swift` drives it
//  end to end with a scripted transport and a stub authorization, from the callback to the stored
//  session.
//
//  **What that sentence used to claim, and why it was narrowed** (review of PR #84, F1). It read
//  "none of them reaches the network… a mutated build talking to production". That is a statement
//  about *this file*, and this file was never what kept the process off the network — `DataLayer`'s
//  session was built outside the `CYPRESS_REMOTE` gate entirely, so the **unpinned** path dialled
//  production with nothing in the way. The gate is the guarantee (`RemoteAccess`, and `DataLayer
//  .boot`'s `authHTTP`); this file is a convenience on top of it. Both are true now; only one of
//  them ever was.
//
//  ── A mistyped pin is a refusal, never the real sheet ───────────────────────────────────────────
//
//  `resolve` used to answer `nil` for an unrecognized value, which restores the **real Apple sheet**.
//  On a runner whose simulator has an Apple Account signed in, a typo in either the key or the value
//  therefore put a live system sheet in front of the two UI tests that tap the button. That is
//  `DebugLocationOverride`'s rule broken in this file — a typo must not be indistinguishable from a
//  decision — and it is the deny-list shape `RemoteAccess`'s header refuses. An unrecognized value
//  now refuses like every other value here **and** complains out loud, the way a mistyped
//  `CYPRESS_REMOTE` does.
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

    /// What a **mistyped** pin throws. Never the real sheet — see `resolve`.
    struct Misconfigured: Error, Equatable {
        let raw: String
    }

    /// A sentence for the composition root to draw when somebody mistyped the pin, or nil when
    /// nothing is wrong.
    ///
    /// Mirrors `RemoteAccess.complaint` rather than inventing a second idiom, and is drawn by the
    /// same `RootView` overlay for the same reason: a seam that refuses quietly leaves a test
    /// asserting the cancelled state against a build doing something else entirely.
    static func complaint(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard case let .invalid(raw) = requested(environment) else { return nil }
        return """
            \(environmentKey)=\(raw) is not a value this build understands, so the Apple button \
            refuses. Use `cancel`, or `fail`.
            """
    }

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
    /// **`.invalid` refuses; it does not fall through to the real button.** It used to answer `nil`,
    /// which is the same answer as a missing variable and therefore restores the system sheet — see
    /// this file's header for why that is the one answer it must not give. Refusing rather than
    /// trapping, because a DEBUG seam should not take the app down over a typo; the noise comes from
    /// `complaint`, drawn over the whole app by `RootView`, which is `RemoteAccess.misconfigured`'s
    /// arrangement exactly.
    ///
    /// **Nil still means nil.** An absent variable is not a mistake and must leave the real button
    /// alone, or no ordinary launch could sign in at all.
    static func resolve(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppleSignIn? {
        switch requested(environment) {
        case .cancel:            return AppleSignIn { throw AccountLinkRefusal.cancelled }
        case .fail:              return AppleSignIn { throw PinnedFailure() }
        case let .invalid(raw):  return AppleSignIn { throw Misconfigured(raw: raw) }
        case nil:                return nil
        }
    }
}
#endif
