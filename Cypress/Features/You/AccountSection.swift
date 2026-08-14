//
//  AccountSection.swift
//  Cypress — Features/You
//
//  The You tab's account block: whether there is one, the way out of it, and the way to delete it
//  (ERRATA E131). Presentation only — a finished state and three callbacks, no `LocalAPI` and no
//  `async` — so every state photographs and previews with static data, the split
//  `ModerationReviewList` and `AccountAskScreen` use.
//
//  ── The one rule this block is most likely to break, and it is broken right now ────────────
//  ARCHITECTURE §5.4 and DECISIONS constraint 3: the app never says it did a thing it did not do.
//  This header used to read: "An account here is **local**. It is an identity, not a backup
//  (`BetaCapability`, ERRATA E124): nothing is uploaded, nothing is recoverable from another device,
//  and the words on this block say so rather than borrowing the reassurance of a cloud that does not
//  exist. Screen 18's storage line makes the same promise on the other side of the sign-in and stays
//  true after it."
//
//  **Every clause of that is now false, and the copy it describes is still drawn.** #158's wiring
//  round gave `DataLayer.boot` a send sink over `RemoteAPI`, so an anonymous installation's
//  contributions already leave the phone; #158 step 5 made `Continue with Apple` a real exchange
//  against `cypress-sync`, so a signed-in account is a row on a service rather than a name on a
//  handset. `AccountCopy.signedInBody` still says "Nothing is uploaded".
//
//  It is left standing on purpose. Which sentence replaces it is a **screen 18 copy question**, the
//  owner's under DECISIONS constraint 21, and it is the same open question PROTOTYPE-FLOW §1.4's
//  storage line already has — recorded unnumbered in `docs/errata-pending/`. Correcting the comment
//  without inventing the sentence is the only move available here, and a comment nobody corrected is
//  how a false promise survives a review.
//
//  Nothing here counts anything (ARCHITECTURE §5.1). No "member since", no contribution tally.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct AccountSection: View {

    let isSignedIn: Bool
    /// What the account agreed to at sign-in, when it is known. Nil while signed out, and nil for an
    /// account claimed before the record existed — see `AccountCopy.licenseLine`.
    var link: AccountLinkRecord?
    /// Whether a sign-out or a deletion is in flight; the rows stop accepting taps while it is.
    var isBusy = false

    var onSignIn: () -> Void = {}
    var onSignOut: () -> Void = {}
    /// Reached **only** from inside `AccountDeletionSheet`, and always carrying the door the person
    /// chose there. See `AccountModel.deleteAccount(_:)`.
    var onDelete: (AccountDeletionChoice) -> Void = { _ in }

    /// Whether the deletion sheet is up. Local to the view, because a confirmation that survived the
    /// screen it was raised on would be a pending destructive action nobody can see.
    @State private var isConfirmingDeletion = false

    /// Which door the sheet is currently showing as chosen.
    ///
    /// **Owned here rather than inside the sheet, so that raising the sheet resets it.** SwiftUI
    /// keeps a `@State` value alive across a `.sheet` dismissal when the presenter's identity does
    /// not change, so a `@State` inside `AccountDeletionSheet` would remember `eraseEverything` from
    /// a session the person backed out of — and the next time they opened it the destructive door
    /// would be pre-selected with nothing on screen explaining why. A destructive default that
    /// arrives by history is the exact failure the whole two-door design is arranged to prevent, so
    /// the reset is written down at the one line that opens the sheet rather than left to SwiftUI's
    /// identity rules.
    @State private var deletionChoice = AccountDeletionChoice.default

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AccountCopy.sectionLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            if isSignedIn {
                signedIn
            } else {
                signedOut
            }
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
        // ══════════════════════════════════════════════════════════════════════════════════════
        // RULINGS R3's confirmation, now two doors wide (the project owner's ruling). **The copy is
        // the feature**, in R3's own words: "deleting more than someone expected is the failure
        // mode this ruling creates, and copy is the whole defense against it". `AccountDeletionCopy`
        // holds every string; `AccountDeletionSheet` arranges them and adds none of its own.
        //
        // A sheet rather than the `confirmationDialog` this used to be, and rather than a pushed
        // screen. The dialog was the right shape while there was one behavior and is the wrong
        // shape for two — see the header of `AccountDeletionSheet` for the argument, which is that
        // a dialog cannot make both doors readable before either is chosen. Still **NOT SPECIFIED**:
        // SCREENS.md draws no deletion surface and BUILD-PLAN §9 lists none.
        //
        // Dismissing by swipe or scrim lands on the same `onCancel` the `Keep my account` button
        // does — R3 wants the way out to be the default on any surface that draws these two, and a
        // sheet's default gesture is a dismissal.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .sheet(isPresented: $isConfirmingDeletion) {
            AccountDeletionSheet(
                choice: $deletionChoice,
                isBusy: isBusy,
                onDelete: { choice in
                    isConfirmingDeletion = false
                    onDelete(choice)
                },
                onCancel: { isConfirmingDeletion = false }
            )
        }
    }

    // MARK: - Signed in

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            statusCard

            IconTextRow(
                accent: .water,
                title: AccountCopy.signOutTitle,
                subtitle: AccountCopy.signOutSubtitle,
                action: isBusy ? nil : onSignOut
            )

            // The destructive row does not delete. It opens R3's two sentences, and the tap that
            // deletes is inside that sheet — there is no path from one tap to an emptied account.
            //
            // The choice is reset here, on the way in, rather than on the way out. See
            // `deletionChoice`.
            IconTextRow(
                accent: .bloom,
                title: AccountCopy.deleteTitle,
                subtitle: AccountCopy.deleteSubtitle,
                action: isBusy ? nil : {
                    deletionChoice = .default
                    isConfirmingDeletion = true
                }
            )
        }
    }

    /// What being signed in actually means here, in the two sentences that are true of it.
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(AccountCopy.signedInTitle)
                .font(CypressFont.body135Bold)
                .foregroundStyle(CypressColor.textInk)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(AccountCopy.signedInBody)
                .font(CypressFont.body115)
                .foregroundStyle(CypressColor.textFaint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let licenseLine = AccountCopy.licenseLine(for: link) {
                Text(licenseLine)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, YouMetrics.settingPaddingV)
        .padding(.horizontal, YouMetrics.settingPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
    }

    // MARK: - Signed out

    /// **NOT SPECIFIED**, and the reason it is here rather than omitted: signing out has to leave a
    /// way back in. D9 puts the account ask on the third visit save and nowhere else, so without
    /// this row the only route back to an account you had this morning is three more field visits —
    /// a door that locks behind you. It opens screen 15 itself, which *is* specified, rather than
    /// asking anything of its own (ARCHITECTURE rule 8: follow the nearest specified thing).
    private var signedOut: some View {
        IconTextRow(
            accent: .water,
            title: AccountCopy.signInTitle,
            subtitle: AccountCopy.signInSubtitle,
            action: isBusy ? nil : onSignIn
        )
    }
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — BUILD-PLAN §9 names "profile" among the You tab's
/// contents and no document draws it. Each states a fact and stops (ARCHITECTURE §5.7: sentence
/// case, real minus signs, no spaces around em dashes).
///
/// The deletion strings are not here. They are `AccountDeletionCopy`'s, in `Core`, written to
/// RULINGS R3 and deliberately kept in one reviewable place; this enum only arranges them.
enum AccountCopy {

    static let sectionLabel = "Account"

    static let signedInTitle = "Signed in on this phone"

    /// **KNOWN FALSE, drawn anyway, and a stop-and-ask — see this file's header.**
    ///
    /// It was written as the sentence ERRATA E124 made true and screen 15's own body copy did not:
    /// a local account is an identity, not a backup, and every clause was checkable because
    /// `claimDevice` was the whole of what signing in did. #158's wiring round and step 5 between
    /// them ended that. "Nothing is uploaded" is false for an anonymous installation (the send sink
    /// reaches `cypress-sync`) and false again for a signed-in one (`POST /auth/oidc` minted the
    /// account and a signed-in account's photograph is auto-approved on the service).
    ///
    /// The third clause still holds: `User.publicAttribution` cannot be turned on anywhere in the
    /// app (ERRATA E100, `YouCopy.privacyBody`), so "nothing about you is public" is true.
    ///
    /// Not rewritten here. Screen 18's copy is the owner's under DECISIONS constraint 21 and the
    /// brief for this round names it as a stop-and-ask by name; the alternative — inventing a
    /// replacement sentence in a sync-API round — is how a governance guarantee erodes.
    static let signedInBody =
        "This account gathers what you save here under one name on this device. Nothing is uploaded, "
        + "and nothing about you is public."

    static let signOutTitle = "Sign out"
    /// Says the part a person cannot see: signing out is not a deletion, and it is not a one-way
    /// door either (`LocalAPI.signOut()` keeps the id so signing in again resumes this account).
    static let signOutSubtitle = "Keeps everything you have saved. Sign in again to pick this account back up"

    /// The destructive row's own title. It was `AccountDeletionCopy.confirmAction` while there was
    /// one of those; there are now two, each naming the door it takes, and neither is the right
    /// label for a row that takes no door at all. So the row says the plain thing and the sheet
    /// says the specific ones.
    static let deleteTitle = "Delete account"

    /// The destructive row's second line. It does not repeat R3's sentences — those are the sheet's,
    /// and a summary of them here would be a shorter, less careful version of the one warning that
    /// matters. "What stays" is now a thing the reader decides rather than a thing they are told,
    /// which the line says by promising a choice rather than a description.
    static let deleteSubtitle = "Choose what happens to your records, then confirm"

    static let signInTitle = "Sign in"
    static let signInSubtitle = "Gather what you save under one name on this phone"

    /// What the license row on screen 15 was answered with, read back (ERRATA E131).
    ///
    /// Nil rather than a third sentence when there is no record at all — an account claimed before
    /// this was persisted, or by something other than screen 15. "Not recorded" would be a true
    /// sentence about a database and a meaningless one about a person.
    static func licenseLine(for link: AccountLinkRecord?) -> String? {
        guard let link, link.provider != nil else { return nil }
        return link.acceptsLicense
            ? "You agreed to share your tree records under the open database license."
            : "You did not agree to share your tree records under the open database license."
    }
}
