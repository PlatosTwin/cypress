//
//  PhotoViewerView.swift
//  Cypress — Features/Photos
//
//  One photograph, whole, over everything else.
//
//  ── NOT SPECIFIED ────────────────────────────────────────────────────────────────────────
//  SCREENS.md has no viewer. Its nearest word on the subject is 03's affordance line — "hero → photo
//  timeline (**NOT SPECIFIED**)" — which is the entry that produced screen 20 (ERRATA E125) and
//  stops there. So the whole of this screen is designed here under ARCHITECTURE §8 rule 8, and this
//  header is the reasoning rather than a stray comment on a view.
//
//  ── The defect it closes (ERRATA E142) ───────────────────────────────────────────────────
//  Reported from the field: *"clicking on photo from tree page should show full view, current is
//  horizontal which cuts off photos taken in vertical orientation."*
//
//  Until this file, tapping a photograph in this app never showed the photograph. The hero on 03 is
//  a 224 pt band, screen 20's rows are the same band repeated, and both are `PhotoFill` — a
//  deliberate crop to a fixed frame, which is right for a hero and right for a list and is the only
//  thing a tap could reach. A phone photograph held upright is 3:4; that band keeps 43% of it. So
//  every route through the app ended at a crop, and there was no *last* tap that produced the
//  picture. **Trees are tall and portrait is the correct way to photograph one**, so the orientation
//  being cut was the orientation the app should expect.
//
//  A viewer is the answer rather than "make the hero taller" because the two are different jobs. A
//  hero is a page's ground and has to be a known height or the page below it moves; a viewer has one
//  job and the whole display to do it in. Nothing is cropped here, in either orientation:
//  `PhotoFit` letterboxes, and the bars are the honest report that the picture is not the shape of
//  the phone.
//
//  ── Why it is presented, not pushed ──────────────────────────────────────────────────────
//  It is not a place in the app, it is a closer look at what is already on screen — the same
//  distinction `AppRouter.sheet` already draws, and the same one that puts 09, 10 and 15 in the
//  cover rather than on the path. Practically: a pushed viewer would inherit the navigation stack's
//  bar and its own dark backdrop would have a light bar across the top of it.
//
//  ── Why there is a delete on it (ERRATA E173) ────────────────────────────────────────────
//  E147 shipped the delete on screen 20 only, and said why: "a delete on the hero would act on
//  whichever photograph the rule happened to pick". That sentence is true of the hero and false of
//  this screen, and applying it here is the defect the owner reported as "I don't see that option".
//
//  Tapping a photograph is the one gesture a person makes to act on a photograph, and every route in
//  the app that starts from a picture — the hero on 03, a row on 20 — ends here. What they arrived
//  at was a surface whose entire vocabulary is *look, then close*: no delete, and no way onward to
//  the screen that has one. The control was reachable only by a second tap on the small metadata
//  pill in the corner of the hero, which reads as a caption rather than a door.
//
//  This screen shows exactly one photograph, named, whole, with its id in hand. There is nothing for
//  a rule to pick. So it gets the same three-beat control screen 20 has — trash glyph, a
//  confirmation naming the consequence, the verb on the button — driven by the *same*
//  `TreePhotosModel`, so there is one implementation of "may this person delete this, and what does
//  it cost" rather than two that can drift.
//
//  ── Why there is no pinch-to-zoom ────────────────────────────────────────────────────────
//  Deliberate, and worth writing down because it is the obvious next thing to reach for. The report
//  is that the photograph is *cut off*; showing it whole answers that completely. A zoom that had to
//  be built would bring a gesture that fights the cover's own dismiss drag, a set of bounds nobody
//  has specified, and a second reason for the image to be at the wrong scale. If somebody asks to
//  look closer, that is a second report and it can have its own entry.
//

import SwiftUI

struct PhotoViewerView: View {

    let photoID: UUID
    /// The words already on screen for this photograph — see `Route.photoViewer`.
    let caption: String
    let onClose: () -> Void

    /// Screen 20's model, over the tree this photograph belongs to. Deliberately the same type: the
    /// question "may this person delete this photograph, and what does removing it cost the tree"
    /// has one answer and it already lives there (ERRATA E173). A second model would be a second
    /// place for `deletablePhotoIDs` and the community-add sentence to live.
    @State private var model: TreePhotosModel

    @Environment(PhotoImageStore.self) private var store: PhotoImageStore?

    init(
        photoID: UUID,
        caption: String,
        treeID: UUID,
        api: (any CypressAPI)? = nil,
        onClose: @escaping () -> Void
    ) {
        self.photoID = photoID
        self.caption = caption
        self.onClose = onClose
        _model = State(wrappedValue: TreePhotosModel(treeID: treeID, api: api))
    }

    /// A finished model, for previews and the screen sweep.
    init(photoID: UUID, caption: String, model: TreePhotosModel, onClose: @escaping () -> Void) {
        self.photoID = photoID
        self.caption = caption
        self.onClose = onClose
        _model = State(wrappedValue: model)
    }

    /// The record behind `photoID`, once the tree has been read. `nil` while loading, and on a
    /// photograph this device does not hold.
    private var photo: Photo? { model.photos.first { $0.id == photoID } }

    /// Whether to draw the control. The same gate screen 20 uses and for the same reason: an
    /// anonymized photograph is still *shown* — that is what the leaving door promised — and is
    /// nobody's to take back.
    private var isDeletable: Bool { photo.map(model.isDeletable) ?? false }

    /// Whether to say why there is no control, which is the other half of the same gate and was
    /// missing from both surfaces until task #131. Not `!isDeletable`: this screen draws nothing
    /// while the read is in flight and on a photograph this device does not hold, and neither of
    /// those is a photograph that belongs to nobody.
    private var isNobodysToRemove: Bool { photo.map(model.isNobodysToRemove) ?? false }

    var body: some View {
        ZStack {
            // The backdrop the app already uses when a photograph is the subject and everything
            // else recedes: screen 04's camera ground. A token, not a black rectangle — and the one
            // token in the palette that means exactly this.
            CypressColor.Dark.bgCamera
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if let image = store?.viewerImage(photoID) {
                PhotoFit(image: image, label: PhotoViewerPresentation.imageLabel(caption))
                    .ignoresSafeArea()
            } else {
                // The bytes are still arriving, or they are gone. Either way the screen says so in
                // words rather than drawing a gradient that could be mistaken for a photograph —
                // this is the one screen where a placeholder standing in for the subject would be a
                // lie about what is in the file (ARCHITECTURE §5.7: state a fact and stop).
                Text(PhotoViewerCopy.unavailable)
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.Dark.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, CypressSpacing.gutter)
            }
        }
        .overlay(alignment: .bottomLeading) { captionBlock }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .bottomTrailing) { if isDeletable { deleteControl } }
        // The photograph is the largest thing `PhotoImageStore` ever holds and it is decoded for
        // this screen alone, so it is loaded when this screen appears and dropped when it goes.
        .task(id: photoID) { await store?.loadViewer(photoID) }
        // Who owns this photograph is a separate read from its bytes, and it is what decides whether
        // the control above is drawn at all (ERRATA E173).
        .task { await model.load() }
        .onDisappear { store?.releaseViewer() }
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
                Task {
                    await model.delete(photo.id, images: store)
                    // The subject of this screen is gone. Staying would draw *That photograph could
                    // not be opened* over the place it used to be, which reads as a failure rather
                    // than as the thing that was just asked for. Closing returns to the surface the
                    // reader tapped from, which re-reads itself and shows the set without it.
                    if model.deleteError == nil { onClose() }
                }
            }
            Button(TreePhotosCopy.deleteCancel, role: .cancel) { model.pendingDeletion = nil }
        } message: { photo in
            Text(
                TreePhotosPresentation.deleteMessage(
                    isLastOfACommunityAdd: model.isLastPhotographOfACommunityAdd(photo)
                )
            )
        }
        // A failed deletion is never swallowed, for `TreePhotosModel.deleteError`'s reason: somebody
        // has just been told a photograph is about to be destroyed and has to know whether it was.
        // On this screen it has to be drawn over the photograph, because there is no list to put it
        // above — and the photograph being still there is itself half the message.
        .overlay(alignment: .top) {
            if let message = model.deleteError {
                Text(message)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.Dark.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(CypressSpacing.gutter)
            }
        }
    }

    // MARK: - Chrome

    /// The caption, with the reason there is no delete above it when there is no delete (#131).
    ///
    /// **Above the caption rather than in the corner the trash vacated**, which is the one place
    /// this screen's design departs from "say it where the control would have been". Measured on
    /// the running app, the sentence wraps to two full-width lines on a 440 pt iPhone 16 Pro Max;
    /// put in the bottom-trailing corner it would either run into the caption pill in the other
    /// corner or squeeze into a narrow column over the middle of the photograph. Stacked over the
    /// caption it is a legible block in the place a reader is already looking for words about this
    /// picture, and it is still diagonally opposite the close button — the geometry the delete had.
    /// E126 requires the surface to say why; it does not require the sentence to stand exactly
    /// where the button was.
    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            if isNobodysToRemove {
                Text(TreePhotosCopy.nobodysToRemove)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textOnPhoto)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, CypressSpacing.Component.heroPillPaddingV)
                    .padding(.horizontal, CypressSpacing.Component.heroPillPaddingH)
                    // A rounded rectangle rather than the caption's capsule: a capsule around three
                    // lines of prose draws a lozenge with empty ears, and the fill is the same
                    // token either way so the two read as one family.
                    .background {
                        RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                            .fill(CypressColor.heroMetaPillFill)
                    }
                    .padding(.trailing, CypressSpacing.Component.heroEyebrowLeading)
            }
            captionLine
        }
        .padding(.leading, CypressSpacing.Component.heroEyebrowLeading)
        .padding(.bottom, CypressSpacing.Component.heroBottomInset)
    }

    /// The same sentence the card under the photograph carried, kept so the reader who tapped a
    /// caption to see the picture can still read the caption while looking at it.
    private var captionLine: some View {
        Text(caption)
            .font(CypressFont.mono105)
            .foregroundStyle(CypressColor.textOnPhoto)
            .padding(.vertical, CypressSpacing.Component.heroPillPaddingV)
            .padding(.horizontal, CypressSpacing.Component.heroPillPaddingH)
            .background { Capsule().fill(CypressColor.heroMetaPillFill) }
            // The insets belong to `captionBlock`, which is what is actually positioned — this may
            // now have a sentence stacked over it and the two have to move as one.
            // The caption is read as part of the image's own label, above. Left in the tree twice it
            // is announced twice, which is the `DeepLinkVoiceOverTests` complaint about doubled
            // labels in a different costume.
            .accessibilityHidden(true)
    }

    /// The delete, on the one screen that shows a single named photograph whole (ERRATA E173).
    ///
    /// **The same glyph, register and confirmation as screen 20's**, deliberately: a person who has
    /// seen one of these has seen both, and a second visual vocabulary for the same irreversible act
    /// would be a second thing to learn. It is in the amber hazard register because there is no red
    /// in this palette, and it sits in the bottom-trailing corner — diagonally opposite the close
    /// button, so the destructive control is nowhere near the one that means *never mind*, and clear
    /// of the caption in the other bottom corner.
    ///
    /// **One tap opens a question and destroys nothing.**
    private var deleteControl: some View {
        Button {
            model.pendingDeletion = photo
        } label: {
            Circle()
                .fill(CypressColor.heroBackFill)
                .overlay {
                    Image(systemName: "trash")
                        .font(.system(size: PhotoViewerMetrics.closeGlyph, weight: .semibold))
                        .foregroundStyle(CypressColor.hazardCTAFill)
                }
                .frame(
                    width: CypressSpacing.Component.backCircle,
                    height: CypressSpacing.Component.backCircle
                )
                .cypressShadow(CypressShadow.heroButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PhotoViewerCopy.delete)
        .accessibilityHint(TreePhotosCopy.deleteHint)
        .padding(.trailing, CypressSpacing.Component.heroBackLeading)
        .padding(.bottom, CypressSpacing.Component.heroBottomInset)
    }

    /// A cover with no navigation bar has no way out that the system provides, so it needs one drawn.
    /// The geometry is `HeroPhotoHeader`'s back circle — the control this app already uses for "off
    /// this photograph" — mirrored to the trailing edge, where a dismiss belongs and where it cannot
    /// be confused for the back button on the screen underneath.
    private var closeButton: some View {
        Button(action: onClose) {
            Circle()
                .fill(CypressColor.heroBackFill)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: PhotoViewerMetrics.closeGlyph, weight: .semibold))
                        .foregroundStyle(CypressColor.textBody)
                }
                .frame(
                    width: CypressSpacing.Component.backCircle,
                    height: CypressSpacing.Component.backCircle
                )
                .cypressShadow(CypressShadow.heroButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PhotoViewerCopy.close)
        .padding(.trailing, CypressSpacing.Component.heroBackLeading)
        .padding(.top, CypressSpacing.Component.heroBackTop)
    }
}

// MARK: - Presentation

/// The one string this screen derives, kept out of the view so it can be tested without rendering.
enum PhotoViewerPresentation {

    /// The photograph named as its subject, then what a listener cannot otherwise know: that this is
    /// the whole frame and nothing has been cropped away. That is the entire difference between this
    /// screen and the card the reader tapped to reach it, and it is invisible to somebody who cannot
    /// see either.
    static func imageLabel(_ caption: String) -> String {
        "\(caption). " + PhotoViewerCopy.wholeFrame
    }
}

// MARK: - Metrics

/// **Not spec values.** The circle, its inset and its shadow are all `HeroPhotoHeader`'s back
/// button, taken from `CypressSpacing.Component` at the call site; only the glyph inside it needs a
/// size of its own, and it follows screen 20's `thumbGlyph` — the app's other bare SF Symbol in a
/// tap target — rather than inventing a third scale.
enum PhotoViewerMetrics {
    static let closeGlyph: CGFloat = 17
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED** — there is no viewer in SCREENS.md.
enum PhotoViewerCopy {
    static let close = "Close"
    /// Named rather than left as a bare glyph, because a listener has no picture to infer it from —
    /// and it says *this photo* so it cannot be heard as "delete the tree".
    static let delete = "Delete this photo"
    static let wholeFrame = "The whole photograph"
    static let unavailable = "That photograph could not be opened"
}
