//
//  TreePhotosView.swift
//  Cypress — Features/Photos
//
//  Screen 20 · Photos of this tree — every photograph somebody has taken of one tree, with a thumb
//  up and a thumb down on each, and the one that leads the tree's page marked (ERRATA E125).
//
//  ── Why this screen exists ────────────────────────────────────────────────────────────────
//  A3 picks a hero by heuristic — most recent full-tree shot, resolution breaking ties — and ends
//  "a manual pin by any org member overrides". Nothing could pin one, so the heuristic was the whole
//  rule and a tree led with whatever was newest, however badly framed. This is the override, and it
//  is the only screen in the app where a photograph is the subject rather than the backdrop.
//
//  ── NOT SPECIFIED ────────────────────────────────────────────────────────────────────────
//  SCREENS.md has no screen 20; there is no mock, no drawn geometry and no copy. Everything here
//  therefore follows the nearest specified thing — the profile hero's radius and the You tab's card
//  padding — and every string states a fact and stops (ARCHITECTURE §5.7).
//
//  ── NOT SPECIFIED · deleting a photograph (task #78, ERRATA E147) ────────────────────────
//  Nothing in SCREENS.md deletes a photograph. The single occurrence of the word in the file is
//  screen 17's "**NOT SPECIFIED:** … swipe-to-delete", about an outbox row; the nearest photo
//  sentences point the other way ("Every photo, visit, and check-in stays" on 19, and SPEC-PHASE1's
//  "Sync never deletes community photos or visits", which is about what *sync* may do to somebody
//  else's record). So this control is designed here under ARCHITECTURE §8 rule 8, and the comments
//  on `deleteControl` and `TreePhotosPresentation.deleteMessage` are the reasoning rather than stray
//  comments on a view.
//
//  It belongs on *this* screen and not on the hero or in the viewer, for one reason: this is the
//  only surface in the app that shows the photographs of a tree as a set, one row each, with the
//  controls that already judge them one at a time. A delete on the hero would act on whichever
//  photograph the hero rule happened to pick, which is not a thing anybody means to press.
//

import SwiftUI

struct TreePhotosView: View {

    @State private var model: TreePhotosModel
    @Environment(AppRouter.self) private var router: AppRouter?
    /// Needed so a deleted photograph stops being drawn from memory — see `PhotoImageStore.forget`.
    /// Optional and read from the environment like every other pushed destination in this app; this
    /// screen is on the navigation stack, not in the cover that ERRATA E142 caught.
    @Environment(PhotoImageStore.self) private var images: PhotoImageStore?

    init(treeID: UUID, api: (any CypressAPI)? = nil) {
        _model = State(wrappedValue: TreePhotosModel(treeID: treeID, api: api))
    }

    /// A finished model, for previews and the screen sweep.
    init(model: TreePhotosModel) {
        _model = State(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: TreePhotosCopy.title, onBack: { router?.pop() })

            ScrollView {
                VStack(alignment: .leading, spacing: TreePhotosMetrics.cardGap) {
                    if model.isEmpty {
                        empty
                    } else {
                        Text(TreePhotosCopy.explainer)
                            .font(CypressFont.body125)
                            .foregroundStyle(CypressColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        // Both failures read the same way and neither is swallowed. The deletion one
                        // matters more: the person has just confirmed something irreversible, and
                        // silence after that reads as "it worked".
                        ForEach([model.voteError, model.deleteError].compactMap { $0 }, id: \.self) { message in
                            Text(message)
                                .font(CypressFont.body125)
                                .foregroundStyle(CypressColor.textInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(model.photos) { photo in
                            card(photo)
                        }
                    }
                }
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.top, TreePhotosMetrics.cardGap)
                .padding(.bottom, TreePhotosMetrics.listBottom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CypressColor.surfaceScreen)
        // The screen draws its own C1 header, so the stack's bar has to go — left in place it sits
        // on top of that header, and the `Back` this screen owns is in the tree but cannot be
        // tapped. That is ERRATA E110's defect exactly, and `DeepLinkVoiceOverTests` caught this one
        // the same way: "Back is in the tree but cannot be activated".
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .confirmationDialog(
            TreePhotosCopy.deleteTitle,
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { photo in
            Button(TreePhotosCopy.deleteAction, role: .destructive) {
                model.pendingDeletion = nil
                Task { await model.delete(photo.id, images: images) }
            }
            Button(TreePhotosCopy.deleteCancel, role: .cancel) { model.pendingDeletion = nil }
        } message: { photo in
            Text(
                TreePhotosPresentation.deleteMessage(
                    isLastOfACommunityAdd: model.isLastPhotographOfACommunityAdd(photo)
                )
            )
        }
    }

    // MARK: - Empty

    private var empty: some View {
        Text(TreePhotosPresentation.emptyText)
            .font(CypressFont.body13)
            .foregroundStyle(CypressColor.textFaint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One photograph

    private func card(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            // **The photograph opens the photograph.** A browser of cropped photographs is a
            // browser that cannot show you a photograph, which is the defect this screen and the
            // hero on 03 were both reported for. The crop below is still right for a row — see the
            // frame — and the way out of it is the viewer.
            PhotoImage(photoID: photo.id, label: TreePhotosPresentation.imageLabel(photo))
                // A fixed height, not an aspect ratio: the photographs are portrait and landscape
                // and a browser whose rows jump height is a browser nobody can scan. `PhotoFill`
                // crops to the box and — the reason it exists — reports the box's width. Which
                // *part* it keeps is `PhotoCropAnchor.crown`, the component's default, and the
                // reason the middle of a portrait tree is the wrong part is written down there.
                .frame(height: TreePhotosMetrics.photoHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    router?.present(
                        .photoViewer(id: photo.id, caption: TreePhotosPresentation.caption(photo))
                    )
                }
                // ══════════════════════════════════════════════════════════════════════════════
                // **A gesture and a named action, not a `Button`** — and this is a deliberate
                // choice rather than a shortcut.
                //
                // `PhotoFill` publishes this element as an *image*, with the photograph's subject
                // and date as its label, because on this one screen the picture is the thing being
                // judged rather than the backdrop. Wrapping it in a `Button` folds the label into
                // the button and the element stops being an image — which is not just a purity
                // argument: `DeepLinkVoiceOverTests.testAThumbActuallyVotes` finds the top card by
                // `app.images` matching `Photo · `, and reads the `Hero` badge's position against
                // that element's frame to prove a vote moved the badge. A button here silently
                // turns that test's subject into something it can no longer find.
                //
                // So the element keeps being what it is, and gains an action. VoiceOver announces
                // the action by name from the rotor, which says more than a button trait would.
                // ══════════════════════════════════════════════════════════════════════════════
                .accessibilityHint(TreePhotosCopy.openHint)
                .accessibilityAction(named: Text(TreePhotosCopy.openAction)) {
                    router?.present(
                        .photoViewer(id: photo.id, caption: TreePhotosPresentation.caption(photo))
                    )
                }
                .overlay(alignment: .topLeading) {
                    if model.heroID == photo.id { heroBadge }
                }

            HStack(alignment: .firstTextBaseline, spacing: CypressSpacing.gapRows) {
                Text(TreePhotosPresentation.caption(photo))
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                Spacer(minLength: 0)
                thumbs(photo)
            }
        }
    }

    private var heroBadge: some View {
        Text(TreePhotosCopy.heroBadge)
            .font(CypressFont.mono105)
            .foregroundStyle(CypressColor.textOnPhoto)
            .padding(.vertical, TreePhotosMetrics.badgePaddingV)
            .padding(.horizontal, TreePhotosMetrics.badgePaddingH)
            .background { Capsule().fill(CypressColor.heroMetaPillFill) }
            .padding(TreePhotosMetrics.badgeInset)
    }

    private func thumbs(_ photo: Photo) -> some View {
        let tally = model.tally(photo.id)
        return HStack(spacing: TreePhotosMetrics.thumbGap) {
            if tally.score != 0 {
                Text(TreePhotosPresentation.score(tally.score))
                    .font(CypressFont.mono105)
                    .foregroundStyle(CypressColor.textMuted)
                    .accessibilityHidden(true)
            }
            thumb(.up, on: photo, tally: tally)
            thumb(.down, on: photo, tally: tally)
            if model.isDeletable(photo) { deleteControl(photo) }
        }
    }

    /// **The control is drawn only on a photograph this person may actually delete**, which is
    /// `TreeProfile.deletablePhotoIDs` and not "every photograph on this device". The two differ on
    /// a photograph whose contributor deleted their account and asked that their work stay where it
    /// is: it is still shown here, and it is nobody's to take back.
    ///
    /// **A trash glyph and no label**, beside two thumbs that are also bare glyphs, so the row keeps
    /// one grammar. **In the amber register, because there is no red in this palette** — the 311
    /// hazard ramp is what this app means by "destructive", which `AccountDeletionSheet` established
    /// and said so in as many words. It is the only cell in the row that is not in the caption
    /// greys, which is the whole of the visual warning a glyph can carry; the words are in the
    /// confirmation, where somebody is actually reading.
    ///
    /// **One tap opens a question and destroys nothing.** That is the same three-beat shape as
    /// account deletion — a control, a sentence naming the consequence, a button carrying the verb —
    /// compressed to two beats because there is only one outcome to choose between here.
    private func deleteControl(_ photo: Photo) -> some View {
        Button {
            model.pendingDeletion = photo
        } label: {
            Image(systemName: "trash")
                .font(.system(size: TreePhotosMetrics.thumbGlyph, weight: .semibold))
                .foregroundStyle(CypressColor.hazardCTAFill)
                .frame(width: TreePhotosMetrics.thumbTarget, height: TreePhotosMetrics.thumbTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TreePhotosPresentation.deleteLabel(photo))
        .accessibilityHint(TreePhotosCopy.deleteHint)
    }

    private func thumb(_ vote: PhotoVote, on photo: Photo, tally: PhotoTally) -> some View {
        let isOn = tally.ownVote == vote
        return Button {
            Task { await model.vote(vote, on: photo.id) }
        } label: {
            Image(systemName: TreePhotosPresentation.glyph(vote, filled: isOn))
                .font(.system(size: TreePhotosMetrics.thumbGlyph, weight: .semibold))
                .foregroundStyle(isOn ? CypressColor.ctaFill : CypressColor.textFaint)
                .frame(width: TreePhotosMetrics.thumbTarget, height: TreePhotosMetrics.thumbTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TreePhotosPresentation.thumbLabel(vote, photo: photo))
        // The state is the whole meaning of the control, and a filled glyph is not readable. Both
        // halves of "this is on and tapping turns it off" have to be in the tree.
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityValue(isOn ? TreePhotosCopy.thumbOn : TreePhotosCopy.thumbOff)
    }
}

// MARK: - Presentation

/// The strings this screen derives from a record, kept out of the view so they can be tested without
/// rendering anything.
enum TreePhotosPresentation {

    static let emptyText = TreePhotosCopy.empty

    static func caption(_ photo: Photo) -> String {
        "\(subject(photo.shotType)) · \(photo.capturedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    /// The photograph named as its subject and its date, because a listener choosing between
    /// photographs needs to know which is which and cannot see either.
    static func imageLabel(_ photo: Photo) -> String {
        "Photo · " + caption(photo)
    }

    static func thumbLabel(_ vote: PhotoVote, photo: Photo) -> String {
        switch vote {
        case .up: return "Thumbs up, \(caption(photo))"
        case .down: return "Thumbs down, \(caption(photo))"
        }
    }

    static func deleteLabel(_ photo: Photo) -> String {
        "Delete, \(caption(photo))"
    }

    /// What the confirmation says, and the only sentence in the app that has to admit a record is
    /// about to stop satisfying its own creation rule.
    ///
    /// The first half is unconditional and says the two things somebody needs before an irreversible
    /// tap: the bytes leave this phone, and there is no way back. It does not say "from the tree",
    /// because the tree is not where the picture lives.
    ///
    /// The second half appears only for the last photograph of a community-added tree. BUILD-PLAN §6
    /// requires a photograph to *add* a tree, so this is the case where the deletion is allowed and
    /// the record ends up in a state its own creation rule forbids — and the honest thing is to say
    /// what happens to the tree rather than to refuse (`LocalAPI.deletePhoto` argues it). It names
    /// the consequence in the terms the person cares about: the tree is not going anywhere.
    static func deleteMessage(isLastOfACommunityAdd: Bool) -> String {
        isLastOfACommunityAdd
            ? TreePhotosCopy.deleteMessage + " " + TreePhotosCopy.deleteLastOfCommunityAdd
            : TreePhotosCopy.deleteMessage
    }

    static func glyph(_ vote: PhotoVote, filled: Bool) -> String {
        switch vote {
        case .up: return filled ? "hand.thumbsup.fill" : "hand.thumbsup"
        case .down: return filled ? "hand.thumbsdown.fill" : "hand.thumbsdown"
        }
    }

    /// A signed count, so `+2` and `−1` read as a tally rather than as a quantity. The minus is a
    /// real minus sign, not a hyphen (ARCHITECTURE §5.7's typography rule).
    static func score(_ score: Int) -> String {
        score > 0 ? "+\(score)" : "−\(abs(score))"
    }

    static func subject(_ shotType: ShotType) -> String {
        switch shotType {
        case .fullTree: return "Full tree"
        case .trunk: return "Trunk"
        case .leaf: return "Leaf close-up"
        case .other: return "Photo"
        }
    }
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — there is no screen 20 in SCREENS.md.
enum TreePhotosCopy {
    static let title = "Photos"
    static let heroBadge = "Hero"
    static let explainer = "The photo with the most thumbs up leads this tree's page."
    static let empty = "No photos of this tree yet"
    static let voteFailed = "That vote could not be saved. Try again."
    static let thumbOn = "on"
    static let thumbOff = "off"
    /// The row's photograph is a crop; this is what pressing it gets you. The hint rather than the
    /// label, on R2's rule: the element is named for what it is — the photograph, already labelled
    /// with its subject and date — rather than relabelled with the next tap.
    static let openHint = "Opens the whole photo"
    /// The same thing, named as an action for the VoiceOver rotor — a verb, because that is what a
    /// rotor lists.
    static let openAction = "Open the whole photo"
    static let deleteFailed = "That photo could not be deleted. It is still here. Try again."
    /// The question, in the dialog's title. A question rather than a statement, because the tap that
    /// opened it did not delete anything and the copy should not imply that it did.
    static let deleteTitle = "Delete this photo?"
    /// The two facts an irreversible tap is owed. "This phone" and not "everywhere": there is no
    /// server yet, and claiming a reach the app does not have is the one thing DECISIONS constraint
    /// 3 forbids above all.
    static let deleteMessage = "The photo is removed from this phone. This cannot be undone."
    /// The extra sentence for the last photograph on a contributor-added tree — BUILD-PLAN §6's
    /// "Community add: requires photo", stated as a consequence rather than enforced as a refusal.
    static let deleteLastOfCommunityAdd =
        "It is the only photo of a tree a contributor added. The tree stays on the map with no photo."
    /// The verb is on the button, so the destructive path cannot be taken without the word *delete*
    /// under your thumb — E136's rule for the account sheet, applied to a smaller thing.
    static let deleteAction = "Delete photo"
    /// Not "Cancel": the button that does nothing should say what nothing means here.
    static let deleteCancel = "Keep it"
    static let deleteHint = "Removes this photo from this phone"
}

// MARK: - Metrics

/// **Not spec values.** The card radius is the profile hero's (`CypressRadius.cardLg`) and the
/// spacing is the You tab's; the photograph's height is the profile hero's, so the picture a tree
/// leads with is the same size here as it is there.
enum TreePhotosMetrics {
    static let photoHeight = CypressSpacing.Component.heroHeightProfile
    static let cardGap: CGFloat = 18
    static let listBottom: CGFloat = 32
    static let badgeInset: CGFloat = 10
    static let badgePaddingV: CGFloat = 4
    static let badgePaddingH: CGFloat = 9
    static let thumbGap: CGFloat = 6
    static let thumbGlyph: CGFloat = 17
    /// 44 pt, the minimum tap target — two of these sit side by side in a row.
    static let thumbTarget: CGFloat = 44
}
