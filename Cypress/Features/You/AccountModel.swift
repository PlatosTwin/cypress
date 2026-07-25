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
//  For `ModerationModel`'s reason, which is `CypressAPI`'s own: the protocol carries no `/auth/*`
//  and no `DELETE /me` because there is no auth server, and `privateReminders` is a `LocalAPI`
//  method beside `curatedSpecies` for the same kind of reason. Everything this model calls is the
//  local half of an endpoint that does not exist yet, and none of it is a stub.
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

    init(api: LocalAPI?) {
        self.api = api
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
    func signOut() async {
        guard let api, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        try? await api.signOut()
        await load()
    }

    /// Delete the account, through the door the person chose (`AccountDeletionChoice`).
    ///
    /// **Only ever called from behind the confirmation.** The copy `AccountDeletionCopy` holds is,
    /// in R3's own words, "the whole defence" against deleting more than somebody expected, so there
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
    @discardableResult
    func deleteAccount(_ choice: AccountDeletionChoice) async -> AccountDeletion.Outcome? {
        guard let api, !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        let outcome = try? await api.deleteAccount(choice)
        await load()
        return outcome
    }
}
