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
    /// **Both halves, and the credential first.** See `session` for what a sign-out that forgot the
    /// Keychain left behind. The order is the one that fails safe: if forgetting the session throws,
    /// the local half is left standing too, so the app stays consistently signed in and the person
    /// can tap again — rather than reaching the state this method exists to prevent, a database that
    /// says nobody beside a credential that says somebody. `AppSession.signOut()` keeps the *device*
    /// credential on purpose, so the anonymous queue goes on draining (D9).
    func signOut() async {
        guard let api, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await session?.signOut()
        } catch {
            return
        }
        try? await api.signOut()
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
    /// **First, and refusing if it fails** — the same order and the same rule as `signOut`, stated
    /// once for both: *never leave this app holding a credential for an account it has stopped
    /// having.* The two failures are not symmetric, which is what settles it. Dropping the
    /// credentials and then failing to delete leaves an intact account this phone is signed out of,
    /// and signing in again resolves to the same `users` row through `apple_subject`. Deleting and
    /// then failing to drop leaves a session for an account whose records are gone — and the next
    /// launch's reconciliation, reading a cleared `app_state` beside a live session, would sign the
    /// person straight back into it. One is an inconvenience; the other is the deletion undoing
    /// itself.
    @discardableResult
    func deleteAccount(_ choice: AccountDeletionChoice) async -> AccountDeletion.Outcome? {
        guard let api, !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            try await session?.forgetEverything()
        } catch {
            return nil
        }
        let outcome = try? await api.deleteAccount(choice)
        await load()
        return outcome
    }
}
