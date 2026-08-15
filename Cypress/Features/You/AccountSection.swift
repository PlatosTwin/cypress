//
//  AccountSection.swift
//  Cypress — Features/You
//
//  The You tab's account block: whether there is one, the way out of it, and the way to delete it
//  (ERRATA E131). Presentation only — a finished state and three callbacks, no `LocalAPI` and no
//  `async` — so every state photographs and previews with static data, the split
//  `ModerationReviewList` and `AccountAskScreen` use.
//
//  ── The one rule this block is most likely to break, and the round it broke in ─────────────
//  ARCHITECTURE §5.4 and DECISIONS constraint 3: the app never says it did a thing it did not do.
//  This header used to read: "An account here is **local**. It is an identity, not a backup
//  (`BetaCapability`, ERRATA E124): nothing is uploaded, nothing is recoverable from another device,
//  and the words on this block say so rather than borrowing the reassurance of a cloud that does not
//  exist. Screen 18's storage line makes the same promise on the other side of the sign-in and stays
//  true after it."
//
//  **Every clause of that went false in one ticket.** #158's wiring round gave `DataLayer.boot` a
//  send sink over `RemoteAPI`, so an anonymous installation's contributions already leave the phone;
//  #158 step 5 made `Continue with Apple` a real exchange against `cypress-sync`, so a signed-in
//  account is a row on a service rather than a name on a handset. `AccountCopy.signedInBody` went on
//  saying "Nothing is uploaded" for two rounds, deliberately — the replacement was a copy question
//  and copy is not an engineer's to write (DECISIONS constraint 21).
//
//  The owner ruled it on **2026-08-14** (ruling 2). `AccountCopy.storageBody` is the answer, it is
//  drawn in both arms of this block, and its own doc comment carries the two clauses it is now
//  making and what would falsify each. The one thing that has not moved is
//  `VisitSaveLedger.storageLine` — screen 18's line under the success block, a different sentence
//  with its own PROTOTYPE-FLOW §1.4 arms — which is still false and still open.
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

            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                // **Outside the arms on purpose** — the owner's ruling 2 of 2026-08-14 is "one body
                // for both arms", and a card written once cannot drift into two. SwiftUI builds no
                // render tree a test can walk, so structure is the only place that guarantee can
                // live; a copy of this call inside each arm would go green with one of them deleted.
                storageCard

                if isSignedIn {
                    signedIn
                } else {
                    signedOut
                }
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

    /// Where this phone's work goes, in the one sentence that is true of it.
    ///
    /// **Both arms draw this card and both draw the same body** (the owner's ruling 2 of
    /// 2026-08-14). Two things do differ, and neither is the sentence: the heading — a signed-in
    /// phone gets `signedInTitle`, an anonymous one gets no heading rather than a heading nobody
    /// wrote — and the license line, which only a sign-in can produce an answer to
    /// (`AccountCopy.licenseLine` already returns nil for a nil record, so the anonymous arm needs
    /// no special case).
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            if let title = AccountCopy.storageCardTitle(isSignedIn: isSignedIn) {
                Text(title)
                    .font(CypressFont.body135Bold)
                    .foregroundStyle(CypressColor.textInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(AccountCopy.storageBody)
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

    /// The storage card's heading, or nil.
    ///
    /// A function rather than a ternary in the view body, for the reason `StatGrid.columnCount` and
    /// `QuadActionRow.rows` are functions: a state-dependent choice a test can read is a choice that
    /// cannot be inverted in silence. `nil` here means *no heading*, never *no card* — the body
    /// below it is drawn in both arms (the owner's ruling 2 of 2026-08-14), and there is no heading
    /// for the anonymous arm because nobody wrote one.
    static func storageCardTitle(isSignedIn: Bool) -> String? {
        isSignedIn ? signedInTitle : nil
    }

    /// **The storage sentence, ruled by the owner on 2026-08-14 (ruling 2).**
    ///
    /// What it replaced: *"This account gathers what you save here under one name on this device.
    /// Nothing is uploaded, and nothing about you is public."* That was true while ERRATA E124 held
    /// — a local account was an identity, not a backup, and `claimDevice` was the whole of what
    /// signing in did — and #158's wiring round and step 5 between them ended it. "Nothing is
    /// uploaded" was false for an anonymous installation (the send sink reaches `cypress-sync`) and
    /// false again for a signed-in one (`POST /auth/oidc` mints the account, and a signed-in
    /// account's photograph is auto-approved on the service where a device's stays `pending`).
    ///
    /// **Both of its clauses are checkable, which is the point of it.**
    /// - *Check-ins and notes sync to your grove* — `DataLayer.boot` wires `APIOutboxSendSink` over
    ///   `RemoteAPI`, and `GET /me/grove` is the far side of it under either credential.
    /// - *Photos stay on this phone until you choose to share them* — the outbox has no photo sink.
    ///   `OutboxQueue` holds binaries and the send half was deliberately left out of the wiring
    ///   round (ERRATA E264, and the server prerequisite the #158 wiring entry records). **When the
    ///   photo sink lands, this sentence stops being true and that round revisits it** — the owner
    ///   said so in the same ruling, so it is written here rather than left for someone to notice.
    ///
    /// **One body for both arms.** It is the same sentence whether or not this phone is signed in,
    /// because both halves of it are true of both, so `signedOut` draws it too rather than leaving
    /// an anonymous installation with no statement at all about where its work goes. That was the
    /// state the old sentence was *most* wrong about and the one arm that never drew it.
    ///
    /// What the replacement drops is the old third clause, "nothing about you is public", which is
    /// still true (`User.publicAttribution` cannot be turned on anywhere in the app — ERRATA E100).
    /// It is not lost: `YouCopy.privacyBody` is where the You tab says it, one section down.
    static let storageBody =
        "Check-ins and notes sync to your grove. Photos stay on this phone until you choose to "
        + "share them."

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
