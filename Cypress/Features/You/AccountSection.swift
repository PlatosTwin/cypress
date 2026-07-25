//
//  AccountSection.swift
//  Cypress — Features/You
//
//  The You tab's account block: whether there is one, the way out of it, and the way to delete it
//  (ERRATA E130). Presentation only — a finished state and three callbacks, no `LocalAPI` and no
//  `async` — so every state photographs and previews with static data, the split
//  `ModerationReviewList` and `AccountAskScreen` use.
//
//  ── The one rule this block is most likely to break ────────────────────────────────────────
//  ARCHITECTURE §5.4 and DECISIONS constraint 3: the app never says it did a thing it did not do.
//  An account here is **local**. It is an identity, not a backup (`BetaCapability`, ERRATA E124):
//  nothing is uploaded, nothing is recoverable from another device, and the words on this block say
//  so rather than borrowing the reassurance of a cloud that does not exist. Screen 18's storage line
//  makes the same promise on the other side of the sign-in and stays true after it.
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
    /// Reached **only** from the confirmation dialog below. See `AccountModel.deleteAccount()`.
    var onDelete: () -> Void = {}

    /// Whether the deletion confirmation is up. Local to the view, because a confirmation that
    /// survived the screen it was raised on would be a pending destructive action nobody can see.
    @State private var isConfirmingDeletion = false

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
        // RULINGS R3's confirmation. **The copy is the feature**, in R3's own words: "deleting more
        // than someone expected is the failure mode this ruling creates, and copy is the whole
        // defence against it". `AccountDeletionCopy` holds every string, written to that ruling and
        // reviewed as prose; this view arranges them and adds none of its own.
        //
        // A dialog rather than a pushed screen, for the reason `ModerationReviewList` raises one:
        // the destructive tap and the sentence about it belong in the same modal moment, and there
        // is no mocked deletion screen to draw (SCREENS.md has none, BUILD-PLAN §9 lists none — so
        // this surface is **NOT SPECIFIED**, and the nearest specified thing in the app is the
        // moderation confirm, which is also a `confirmationDialog` over an irreversible write).
        //
        // `cancelAction` carries `role: .cancel`, so it is the outside tap, the Escape key and the
        // VoiceOver default — R3 wants the way out to be the default on any surface that draws
        // these two.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .confirmationDialog(
            AccountDeletionCopy.title,
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(AccountDeletionCopy.confirmAction, role: .destructive) { onDelete() }
            Button(AccountDeletionCopy.cancelAction, role: .cancel) {}
        } message: {
            Text(AccountCopy.deletionMessage)
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

            // The destructive row does not delete. It opens R3's sentence, and the tap that deletes
            // is inside that dialog — there is no path from one tap to an emptied account.
            IconTextRow(
                accent: .bloom,
                title: AccountDeletionCopy.confirmAction,
                subtitle: AccountCopy.deleteSubtitle,
                action: isBusy ? nil : { isConfirmingDeletion = true }
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

    /// The sentence ERRATA E124 makes true and screen 15's own body copy does not: a local account
    /// is an identity, not a backup. Every clause is checkable — `LocalAPI` writes to this device,
    /// `claimDevice` is the whole of what signing in does, and `User.publicAttribution` cannot be
    /// turned on anywhere in the app (ERRATA E100, `YouCopy.privacyBody`).
    static let signedInBody =
        "This account gathers what you save here under one name on this device. Nothing is uploaded, "
        + "and nothing about you is public."

    static let signOutTitle = "Sign out"
    /// Says the part a person cannot see: signing out is not a deletion, and it is not a one-way
    /// door either (`LocalAPI.signOut()` keeps the id so signing in again resumes this account).
    static let signOutSubtitle = "Keeps everything you have saved. Sign in again to pick this account back up"

    /// The destructive row's second line. It does not repeat R3's sentence — that sentence is the
    /// dialog's, and a summary of it here would be a shorter, less careful version of the one
    /// warning that matters.
    static let deleteSubtitle = "Read what stays and what goes before you confirm"

    static let signInTitle = "Sign in"
    static let signInSubtitle = "Gather what you save under one name on this phone"

    /// R3's three sentences, in the order R3 puts them: what happens, then the queue, then the one
    /// fact that cannot be undone.
    ///
    /// **`whatHappens` is not split**, per its own doc comment: told only that their observations
    /// stay, a person would reasonably expect everything else to stay too. Joined with blank lines
    /// rather than run together, because a dialog message that is one paragraph of three sentences
    /// is a paragraph people skim.
    static let deletionMessage = [
        AccountDeletionCopy.whatHappens,
        AccountDeletionCopy.queuedWork,
        AccountDeletionCopy.irreversible
    ].joined(separator: "\n\n")

    /// What the license row on screen 15 was answered with, read back (ERRATA E130).
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
