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

import SwiftUI

struct TreePhotosView: View {

    @State private var model: TreePhotosModel
    @Environment(AppRouter.self) private var router: AppRouter?

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

                        if let voteError = model.voteError {
                            Text(voteError)
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
            PhotoImage(photoID: photo.id, label: TreePhotosPresentation.imageLabel(photo))
                // A fixed height, not an aspect ratio: the photographs are portrait and landscape
                // and a browser whose rows jump height is a browser nobody can scan. `PhotoFill`
                // crops to the box and — the reason it exists — reports the box's width.
                .frame(height: TreePhotosMetrics.photoHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
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
        }
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
