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
    /// no licence consent may be used for — that belongs to whoever owns the licence (D12,
    /// BUILD-PLAN §5). The answer travels on the request instead, so the account records what was
    /// actually agreed to and `User.licenseVersion` stays honestly nil when nothing was. Recorded
    /// in ERRATA.
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
    /// is about. Every path either returns `true` — and the caller closes the sheet — or leaves a
    /// `notice` and returns `false`.
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
        } catch {
            notice = .failed
            return false
        }
    }

    func toggleConsent() {
        isConsentAccepted.toggle()
    }
}
