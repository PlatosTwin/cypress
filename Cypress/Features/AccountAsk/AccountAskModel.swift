//
//  AccountAskModel.swift
//  Cypress — Features/AccountAsk
//
//  Screen 15's one `@Observable` model (ARCHITECTURE §3). It talks to `CypressAPI` and to the
//  sign-in action it was handed, and to nothing else.
//

import Foundation
import Observation

/// What performing a sign-in looks like from this screen: take the request, come back or throw.
///
/// Injected rather than called on `CypressAPI`, because there is no `POST /auth/*` on the protocol
/// and `CypressAPI`'s own header says why — "there is no auth server and no local equivalent of a
/// token exchange. Adding throwing stubs would suggest a sign-in flow exists." The same shape screen
/// 06 used for its private reminder before E23 settled it: the composition root supplies the action
/// when there is one, and until then a tap claims nothing.
typealias AccountAskLink = @Sendable (AccountLinkRequest) async throws -> Void

/// The two ways a tap ends without an account and **without anything having gone wrong**.
///
/// Both existed only as ideas while the sign-in was local and could not be refused or cancelled: the
/// action either returned or threw, and `link` turned every throw into "that did not go through".
/// With a real provider behind the Apple button that sentence became false in two directions at
/// once, so the two cases are named here — in `Features`, carrying no `AuthenticationServices`
/// import, so the composition root translates Apple's vocabulary into this one rather than this
/// screen learning Apple's.
///
/// A separate type rather than two more `Notice` cases because the *notice* is the consequence and
/// not the fact: `.cancelled` draws nothing at all.
enum AccountLinkRefusal: Error, Equatable {
    /// Somebody opened the provider's own sheet and dismissed it. **Nothing happened, so nothing is
    /// said** — see `AccountAskModel.link` for why silence is the only answer here that invents no
    /// copy.
    case cancelled
    /// This build has no route for that provider. Spec §5.3 and RULINGS **R72** ruling 2: Apple
    /// ships first, the email magic link is deferred to its own ticket, and Google is the same
    /// server route through a system framework that #158 does not build. Until then screen 15 offers
    /// "one working route and two honest 'not yet' buttons", which is this case.
    case unavailable
}

@MainActor
@Observable
final class AccountAskModel {

    private let api: any CypressAPI
    private let onLink: AccountAskLink?

    /// What this device is holding, for the one sentence with a number in it. `.none` until the
    /// read returns, which renders the numberless headline — never a zero (ARCHITECTURE §5.6).
    private(set) var contributions: DeviceContributions = .none

    /// §6's checkbox. **Drawn checked** ("States: checkbox drawn checked"), so that is the start.
    ///
    /// Unchecking does not disable the sign-in buttons. SCREENS.md 15 states no such rule, and
    /// inventing a gate would decide a data-governance question — what a contribution that carries
    /// no license consent may be used for — that belongs to whoever owns the license (D12,
    /// BUILD-PLAN §5). The answer travels on the request instead, so the account records what was
    /// actually agreed to and `User.licenseVersion` stays honestly nil when nothing was. Recorded
    /// in ERRATA.
    ///
    /// **That last sentence was false for as long as it stood here (ERRATA E131).** The composition
    /// root's handler read `_ = request` and discarded both fields, so unchecking this box changed
    /// nothing anywhere and no account recorded anything. It now lands in `app_state` through
    /// `LocalAPI.linkAccount` and is read back by `AccountLinkRecord`, which is what makes leaving
    /// the box ungated defensible rather than merely convenient.
    var isConsentAccepted = true

    private(set) var notice: AccountAskPresentation.Notice?
    private(set) var isLinking = false

    init(api: any CypressAPI, onLink: AccountAskLink? = nil) {
        self.api = api
        self.onLink = onLink
    }

    var presentation: AccountAskPresentation {
        AccountAskPresentation(
            contributions: contributions,
            isConsentAccepted: isConsentAccepted,
            notice: notice,
            isLinking: isLinking
        )
    }

    /// The one read. A failure leaves `.none`, which is the numberless headline rather than a wrong
    /// number — the screen has something true to say either way, so there is no failure state.
    func load() async {
        contributions = (try? await api.deviceContributions()) ?? .none
    }

    /// Tapping one of the three buttons. Returns whether an account was actually linked.
    ///
    /// The answer is returned rather than stored, so this model holds no "signed in" flag: whether
    /// an account exists is the injected action's answer and the store's, and a screen that kept its
    /// own copy of it would be a second, quieter source of truth for the one fact this whole feature
    /// is about.
    ///
    /// **"Every path either returns `true` or leaves a `notice`" was the rule and it now has one
    /// exception, which is the point of `AccountLinkRefusal.cancelled`.** With a real Apple sheet in
    /// front of the tap, somebody can dismiss it, and the three answers available were: print
    /// `noticeFailed` — *"That did not go through"* — which is a claim that something went wrong
    /// when nothing did; invent a fourth sentence, which DECISIONS constraint 21 forbids and this
    /// round has no drawn state for; or draw the screen the mock draws, unchanged, which is what a
    /// dismissed system sheet leaves behind on every other iOS app. The third invents nothing and
    /// says nothing false, so it is what happens. Written up for the errata and unnumbered as this
    /// is written, so there is no number to cite yet.
    @discardableResult
    func link(_ provider: AccountAskProvider) async -> Bool {
        guard !isLinking else { return false }
        guard let onLink else {
            notice = .unavailable
            return false
        }

        notice = nil
        isLinking = true
        defer { isLinking = false }

        let request = AccountLinkRequest(provider: provider, acceptsLicense: isConsentAccepted)
        do {
            try await onLink(request)
            return true
        } catch AccountLinkRefusal.cancelled {
            // Silence. The sheet stays exactly as it was drawn, which is the state SCREENS.md 15
            // draws and the only one here that claims nothing.
            return false
        } catch AccountLinkRefusal.unavailable {
            notice = .unavailable
            return false
        } catch {
            notice = .failed
            return false
        }
    }

    func toggleConsent() {
        isConsentAccepted.toggle()
    }
}
