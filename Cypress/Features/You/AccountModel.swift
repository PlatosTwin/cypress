//
//  AccountModel.swift
//  Cypress — Features/You
//
//  The You tab's account state, and the two records only an account or this device can read
//  (ERRATA E131).
//
//  ── Why this exists ────────────────────────────────────────────────────────────────────────
//  ERRATA E124 flipped `BetaCapability.accountsAvailable` to true, so sign-in completes locally on
//  the third visit save — and then the app never mentioned the account again. No screen said you
//  were signed in, nothing signed you out, and `LocalAPI.deleteAccount()`, written to RULINGS R3
//  and complete, had exactly one caller: its own test. A person who had signed in could neither see
//  it nor leave it. Private reminders were the same shape one layer down: screen 06 offers "Save a
//  private reminder for yourself", confirms "Saved. Your reminder stays yours alone.", and
//  `LocalAPI.privateReminders(limit:)` — the correct one-owner query — had no shipping caller, so a
//  reminder could be written and never read again by anybody, including the person who wrote it.
//
//  ── Why it owns `LocalAPI` and not `any CypressAPI` ────────────────────────────────────────
//  For `ModerationModel`'s reason, which is `CypressAPI`'s own: the protocol carries no `/auth/*`,
//  and `privateReminders` is a `LocalAPI` method beside `curatedSpecies` because D4's reminder is
//  one owner's row that no screen holding the existential has ever asked for. Everything this model
//  calls is the local half of an endpoint, and none of it is a stub.
//
//  **`DELETE /me` is no longer one of the reasons.** #158 §3.2 made `deleteAccount` a `CypressAPI`
//  requirement, so a model holding `any CypressAPI` could reach it now. This one still holds
//  `LocalAPI`, for the narrower reason above — recorded as narrower rather than left standing at its
//  old width.
//

import Foundation
import Observation

/// One saved reminder, resolved for display.
///
/// The tree's name is resolved here rather than in the row, because the list holds many reminders
/// about few trees and `displayNames(for:)` answers them in one read — the same argument
/// `OutboxViewState` makes for resolving its queued trees in a batch.
struct PrivateReminderItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let treeID: UUID
    /// Nil when the tree could not be named. The row then says nothing about the tree rather than
    /// drawing an empty line, the rule every other screen in this app follows for a missing name.
    let treeName: String?
    let category: HazardCategory
    let createdAt: Date
}

@MainActor
@Observable
final class AccountModel {

    /// Optional for `ModerationModel`'s reason: a preview or a screenshot fixture builds an inert
    /// model with no store behind it, which draws exactly the You tab of a device nobody has signed
    /// in on.
    private let api: LocalAPI?

    /// The credentials half of the same account, so that leaving one leaves both.
    ///
    /// ── Why this model gained a second dependency, and what was wrong without it ───────────────
    ///
    /// `signOut()` below called `LocalAPI.signOut()` and nothing else, so the Keychain session
    /// **survived a sign-out**. Two things followed. The bearer stayed the account's — every request
    /// the app made after the tap still authenticated as the person who had just signed out, and the
    /// service went on attributing the work to them. And once `DataLayer.boot` learned to restore a
    /// signed-in session (`SessionRestore`), the surviving item made the sign-out undo itself on the
    /// next launch: the database said nobody, the Keychain said somebody, and the mirror rule
    /// correctly believed the Keychain. A restore that resurrected deliberate sign-outs would be a
    /// worse defect than the one it was written to close.
    ///
    /// So the ruling's own words — *a surviving **signed-in** session* — are made true here: after
    /// this tap there is no session to survive.
    ///
    /// Optional for the same reason `api` is. A model built with neither draws the You tab of a
    /// device nobody has signed in on, and has nothing to sign out of.
    private let session: AppSession?

    /// Whether there is an account on this device right now. The store's answer, never a cached
    /// flag of this model's own — `AccountAskModel` refuses to hold one for the same reason.
    private(set) var isSignedIn = false

    /// What that account agreed to at sign-in (ERRATA E131). Nil when signed out.
    private(set) var link: AccountLinkRecord?

    /// This contributor's own reminders — the account's, plus the ones this device wrote before
    /// there was an account (ERRATA E23). Never anyone else's; there is no query that could return
    /// one.
    private(set) var reminders: [PrivateReminderItem] = []

    /// Whether the reminder read **failed**, as opposed to returning nothing.
    ///
    /// The distinction is not pedantic here. Two tab roots in this app once drew their empty state
    /// on a failed read, and an empty state is a claim: "you have not saved any reminders" is a
    /// sentence about the person, and saying it when the database could not be opened is telling
    /// them their records are gone. The screen says which of the two happened.
    private(set) var remindersFailed = false

    /// True from the first completed `load()`. Before it, the section draws nothing rather than an
    /// empty state — the same rule that keeps `AccountAskModel`'s headline numberless until its read
    /// lands (ARCHITECTURE §5.6).
    private(set) var hasLoaded = false

    /// A sign-out or a deletion in flight. The rows stop accepting taps while it is, so a second tap
    /// on `Delete account` cannot start a second deletion against a store the first one is emptying.
    private(set) var isBusy = false

    init(api: LocalAPI?, session: AppSession? = nil) {
        self.api = api
        self.session = session
    }

    /// Read the account and the reminders. Called from the You tab's `.task` and again whenever a
    /// sheet closes over it, so signing in on screen 15 shows up here without a relaunch.
    func load() async {
        guard let api else {
            isSignedIn = false
            link = nil
            reminders = []
            remindersFailed = false
            hasLoaded = true
            return
        }
        isSignedIn = await api.userID != nil
        link = try? await api.accountLink()

        do {
            let saved = try await api.privateReminders()
            // One read for every tree in the list, not one per row.
            let names = await api.displayNames(for: saved.map(\.treeID))
            reminders = saved.map { reminder in
                PrivateReminderItem(
                    id: reminder.id,
                    treeID: reminder.treeID,
                    treeName: names[reminder.treeID],
                    category: reminder.category,
                    createdAt: reminder.createdAt
                )
            }
            remindersFailed = false
        } catch {
            // The list is left as it was rather than emptied: a failed refresh over a list already
            // on screen must not look like the reminders were deleted.
            remindersFailed = true
        }
        hasLoaded = true
    }

    /// Sign out, keeping everything. See `LocalAPI.signOut()` for why the account id is remembered.
    ///
    /// **Both halves, the local one first, and neither failure swallowed** (review of this PR, F2).
    /// See `session` for what a sign-out that forgot the Keychain left behind.
    ///
    /// The first cut dropped the credential first and argued that this "fails safe". It reasoned
    /// about one of the two failures. The reviewer measured the other: with a store that refuses
    /// writes, `try? await api.signOut()` swallowed the local half and left
    /// `sessionGone=true localStillSignedIn=true drawnSignedIn=true` — the app drawing an account it
    /// no longer holds a credential for, `attribution` still that account's, for the rest of the run.
    /// That is the mirror rule violated in the direction the comment claimed the order prevented.
    ///
    /// So the order is the other one, and both failures are now stated rather than one:
    ///
    /// - **the local half fails** → nothing has changed at all. The session is untouched, the app
    ///   stays consistently signed in, and the person can tap again. This is the failure the ordering
    ///   is chosen for, because it is the one a refusing store actually produces.
    /// - **the credential drop fails** → the database says nobody, `signed_out_user_id` names the
    ///   account, and the screen draws what the person asked for. The bearer is still the account's
    ///   until the next launch, which is the pre-existing defect and no worse than it; the next
    ///   launch's discriminator reads that marker beside the surviving session and ends it properly
    ///   (`SessionRestore.reconcile`). It converges, and it converges to *signed out*.
    ///
    /// `AppSession.signOut()` keeps the *device* credential on purpose, so the anonymous queue goes
    /// on draining (D9).
    func signOut() async {
        guard let api, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.signOut()
        } catch {
            return
        }
        try? await session?.signOut()
        await load()
    }

    /// Delete the account, through the door the person chose (`AccountDeletionChoice`).
    ///
    /// **Only ever called from behind the confirmation.** The copy `AccountDeletionCopy` holds is,
    /// in R3's own words, "the whole defense" against deleting more than somebody expected, so there
    /// is no path from a single tap to this method and no default-styled button that reaches it.
    ///
    /// **The choice is a required argument with no default**, unlike `LocalAPI.deleteAccount`, which
    /// takes the safe door when nobody says otherwise. The layering is deliberate in both directions:
    /// a *store* call that forgets to name a door should do the harmless thing, and a *screen* that
    /// forgets to name one should not compile. This is the layer that knows what the person tapped.
    ///
    /// The outcome is returned rather than rendered as a tally. R3's copy names *kinds* of record
    /// and counts nothing, because ARCHITECTURE §5.1 forbids counts of user actions and a farewell
    /// is the last place to start one; the numbers exist so a test can assert what happened.
    /// **The credentials go too, and unlike sign-out that means both of them.**
    /// `AppSession.forgetEverything()` drops the device credential as well as the session, on its own
    /// stated grounds: a device token minted under a deleted account's claim is a pointer to it. This
    /// call is what makes RULINGS **R3**'s promise true of the Keychain and not only of the tables —
    /// and, since `DataLayer.boot` learned to restore a surviving session, it is also what stops the
    /// next launch signing the person back into the account they just deleted.
    ///
    /// **Only on a deletion that happened** (review of this PR, F2b). The first cut dropped the
    /// credentials first, and the reviewer measured what that does to the failure: with a refusing
    /// store, `outcome=nil sessionGone=true deviceGone=true localStillSignedIn=true` — a deletion
    /// that deleted nothing had destroyed **both** credentials, silently, because the nil outcome is
    /// discarded at the call site. So the deletion goes first and the credentials follow it only when
    /// it returned something.
    ///
    /// **This is also the order the wire will need** (review of this PR, F5). Nothing sends
    /// `DELETE /me` today — `RoutedAPI.deleteAccount` routes local — so credential-first cost nothing
    /// yet. On the day that route is wired it would cost everything: the request that performs the
    /// deletion authenticates with the session, and dropping the session first makes the remote
    /// deletion unauthenticatable. The ordering here is what that day needs, arrived at for a reason
    /// that is already true.
    ///
    /// **What this leaves open, stated rather than implied.** If the deletion succeeds and
    /// `forgetEverything()` then throws, this app holds credentials for an account whose local
    /// records are gone, and the next launch's reconciliation restores it — the deletion cleared
    /// `signed_out_user_id`, so the discriminator has nothing to read. That marker is deliberately not
    /// written back: R3 requires that a deleted account is not resumable, and `AccountDeletionTests`
    /// asserts exactly that, so buying this arm would sell a promise the rulings make. The residue is
    /// an account restored with none of its rows, re-deletable from the same screen; the reachable
    /// failure it replaces was destroying two credentials on every deletion that did nothing.
    @discardableResult
    func deleteAccount(_ choice: AccountDeletionChoice) async -> AccountDeletion.Outcome? {
        guard let api, !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        let outcome = try? await api.deleteAccount(choice)
        if outcome != nil { try? await session?.forgetEverything() }
        await load()
        return outcome
    }
}
