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
//  ── Why there is a way onward from it (the other half of E173) ───────────────────────────
//  E173's own account of the defect names two missing things: "no delete, **and no way onward to the
//  screen that has one**". It shipped the first and left the second, and the second came back as its
//  own report:
//
//  > when i click on the tree photo from a tree page, i can get to the view where I see all photos
//  > and can thumbs up/down them, change between all/full/trunk/leaf only very ocassionally, and
//  > sometimes not at all, instead seeing only the hero photo and no other photos and no option at
//  > all to thumbs up/down
//
//  That is this screen, described from the outside by somebody who meant to reach screen 20. The
//  hero is 224 pt of photograph and the pill is the only door to the browser, so almost every press
//  on the picture lands here — one photograph, no set, no vote, no filter — and E173's sentence about
//  the pill applies unchanged: it is mono 10.5 in a translucent capsule beside `Best photo · Oct
//  2025`, and nothing about it reads *there are controls behind this*.
//
//  So the viewer gets the door. It already holds the tree id — E173 put it there — so the control
//  costs no read and cannot be wrong about which tree it means. **In the screen's control vocabulary
//  and not its caption vocabulary**, which is the whole point: solid `heroBackFill` and `textBody`,
//  the treatment `Close` and the delete already wear here, rather than the translucent mono capsule
//  that E173 recorded as unreadable as a control.
//
//  ── Why there IS pinch-to-zoom, since 2026-08-21 ─────────────────────────────────────────
//  What stood here said there was none, deliberately, and closed with: *"If somebody asks to look
//  closer, that is a second report and it can have its own entry."* Somebody did, from TestFlight,
//  and the owner ruled it in. The section is rewritten rather than deleted because it named three
//  costs, and two of them turned out not to exist:
//
//  1. *"a gesture that fights the cover's own dismiss drag"* — **there is no such drag.** This
//     screen is presented in `RootView`'s `fullScreenCover`, and a full-screen cover has no
//     interactive dismissal; the drawn ✕ is the only way out and always has been. The concern was
//     `.sheet`'s, written about a screen that is not one.
//  2. *"a set of bounds nobody has specified"* — true, and it is specified here: `PhotoZoom`, one
//     type, tested without rendering. The scale is clamped to `PhotoZoom.range` and the pan is
//     clamped so the picture can never be dragged clear of the frame it is being looked at in.
//  3. *"a second reason for the image to be at the wrong scale"* — this is the real one, and it is
//     why the zoom is a transform over `PhotoFit` rather than a second way of sizing the image.
//     `PhotoFit` still decides what "whole" means and still letterboxes; zoom scales what it drew.
//     At rest the transform is identity and this screen is byte-for-byte what E142 shipped.
//
//  Double tap returns to rest. It is the gesture every photo viewer on the platform has for
//  "undo whatever I just did to this picture", it needs no drawn control on a screen whose corners
//  are all spoken for, and it is the only way back to rest that does not require pinching outward
//  against the clamp.
//

import SwiftUI

struct PhotoViewerView: View {

    let photoID: UUID
    /// The words already on screen for this photograph — see `Route.photoViewer`.
    let caption: String
    let onClose: () -> Void
    /// Opens screen 20 over this photograph's tree — the way onward E173 left unbuilt.
    ///
    /// A closure rather than a `router.push` in here, like every other navigation in this app: a
    /// feature does not construct its siblings' views (`AppRouter`). The composition root closes the
    /// cover and pushes, and it pushes `unlessAlreadyOnTop` — this screen is reached from screen 20's
    /// own rows as well as from the hero, and from there the door means "back to the set", not a
    /// second copy of it on the stack (ERRATA E151's mechanism, a second use for it).
    let onOpenBrowser: () -> Void

    /// Screen 20's model, over the tree this photograph belongs to. Deliberately the same type: the
    /// question "may this person delete this photograph, and what does removing it cost the tree"
    /// has one answer and it already lives there (ERRATA E173). A second model would be a second
    /// place for `deletablePhotoIDs` and the community-add sentence to live.
    @State private var model: TreePhotosModel

    @Environment(PhotoImageStore.self) private var store: PhotoImageStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // ── The zoom's three pieces of state ────────────────────────────────────────────────────────
    //
    // `committed` is where the picture is between gestures; the two `@GestureState`s are what the
    // fingers are currently adding to it. They are `@GestureState` rather than `@State` because that
    // property wrapper resets itself when a gesture *ends or is cancelled* — a pinch interrupted by
    // a phone call, or by the cover being dismissed under it, leaves nothing behind. The same thing
    // written with `@State` and an `onEnded` has a path where the reset never runs.

    /// Where the photograph is between gestures.
    @State private var committed: PhotoZoom = .rest
    /// The pinch in progress, as a multiplier on `committed.scale`. 1 when nothing is pinching.
    @GestureState private var liveMagnification: CGFloat = 1
    /// The drag in progress, as a translation on `committed.offset`. Zero when nothing is dragging.
    @GestureState private var liveTranslation: CGSize = .zero

    init(
        photoID: UUID,
        caption: String,
        treeID: UUID,
        api: (any CypressAPI)? = nil,
        onClose: @escaping () -> Void,
        onOpenBrowser: @escaping () -> Void
    ) {
        self.photoID = photoID
        self.caption = caption
        self.onClose = onClose
        self.onOpenBrowser = onOpenBrowser
        _model = State(wrappedValue: TreePhotosModel(treeID: treeID, api: api))
    }

    /// A finished model, for previews and the screen sweep.
    init(
        photoID: UUID,
        caption: String,
        model: TreePhotosModel,
        onClose: @escaping () -> Void,
        onOpenBrowser: @escaping () -> Void = {}
    ) {
        self.photoID = photoID
        self.caption = caption
        self.onClose = onClose
        self.onOpenBrowser = onOpenBrowser
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
                zoomable(image)
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
        // A different photograph is a different picture to look at, not a continuation of the one
        // that was being looked at closely. `@State` outlives a changed `let` when the view keeps
        // its identity, so without this a second photograph could arrive already at 4× and panned
        // to a corner of a frame that is not its own.
        .onChange(of: photoID) { _, _ in committed = .rest }
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

    // MARK: - The photograph, and the zoom over it

    /// `PhotoFit`'s letterboxed photograph with the viewer's transform on it.
    ///
    /// **The `GeometryReader` is the point.** Both clamps in `PhotoZoom` need two sizes — the box the
    /// picture is drawn in and the size the picture was actually drawn at — and neither is knowable
    /// from the image alone. `.ignoresSafeArea()` on the reader rather than on `PhotoFit` inside it,
    /// so `proxy.size` is the whole display: that is the frame the reader is looking through, and a
    /// pan limit measured against the safe-area box would stop the picture short of the edges of the
    /// screen it is filling.
    ///
    /// The two gestures are `.simultaneously`, not `.exclusively`: a pinch that drifts is one
    /// gesture to the hand making it, and a viewer that made you let go and start again to move what
    /// you had just enlarged would be answering the report with a different annoyance.
    private func zoomable(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let box = proxy.size
            let content = PhotoZoom.fittedSize(image: image.size, in: box)
            let zoom = current(content: content, in: box)

            PhotoFit(image: image, label: PhotoViewerPresentation.imageLabel(caption))
                .scaleEffect(zoom.scale)
                .offset(zoom.offset)
                // Both clamps are applied here as well as inside the gesture, because `scaleEffect`
                // draws outside its own bounds: a photograph at 5× is five displays wide and would
                // otherwise be painted over the caption, the ✕ and the delete — the controls this
                // screen's whole geometry is arranged around (see `deleteControl`).
                .clipped()
                .gesture(
                    magnify(content: content, in: box)
                        .simultaneously(with: pan(content: content, in: box))
                )
                // Back to the whole frame — the gesture the platform has for this, and the only way
                // back to rest that does not mean pinching outward against the clamp. Animated
                // because a picture that teleports from 4× reads as a glitch rather than as an undo;
                // `camera` is the app's curve for a thing settling into place across the whole
                // screen, which is what this is, and it is honestly off under Reduce Motion, where a
                // full-screen transform is precisely what the setting exists to suppress.
                //
                // **`highPriorityGesture`, not `onTapGesture`.** Two `.gesture()`s on one view are
                // resolved by attachment order, and the pan above is attached first, so it wins a
                // contested touch — and a `DragGesture` holds a touch while it waits to see whether
                // `minimumDistance` will be crossed. A double tap crosses nothing, so it should
                // arrive; whether it *does* is a question about SwiftUI's resolution rather than
                // about this screen, and the answer is not worth depending on. Given priority, the
                // tap is decided first and the drag sees what is left. There is no single-tap
                // handler here for it to delay.
                .highPriorityGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(
                            CypressMotion.resolved(CypressMotion.camera, reduceMotion: reduceMotion)
                        ) {
                            committed = .rest
                        }
                    }
                )
        }
        .ignoresSafeArea()
    }

    /// `committed` plus whatever the fingers are currently adding, clamped — what is drawn this
    /// frame. Between gestures the two live values are their identities and this is `committed`.
    private func current(content: CGSize, in box: CGSize) -> PhotoZoom {
        committed
            .scaled(to: committed.scale * liveMagnification, content: content, in: box)
            .panned(by: liveTranslation, content: content, in: box)
    }

    private func magnify(content: CGSize, in box: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($liveMagnification) { value, state, _ in state = value.magnification }
            .onEnded { value in
                committed = committed.scaled(
                    to: committed.scale * value.magnification,
                    content: content,
                    in: box
                )
            }
    }

    /// A `minimumDistance` of zero would take every touch on the photograph, including the first
    /// half of the double tap above it; the default 10 pt leaves taps alone and still starts a pan
    /// as soon as a thumb means one.
    private func pan(content: CGSize, in box: CGSize) -> some Gesture {
        DragGesture()
            .updating($liveTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                committed = committed.panned(by: value.translation, content: content, in: box)
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
            browserDoor
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

    /// The way onward to screen 20 — every photograph of this tree, the thumbs, and the subject
    /// filter. See the file header for the report it answers.
    ///
    /// **Drawn always, and gated on nothing.** The count of photographs is a read that has not
    /// finished when this screen appears, so a door that waited for it would appear late, move the
    /// caption under somebody's thumb, and be missing exactly when the read is slowest. It is also
    /// true of a tree with one photograph: the thumbs live on the other side of this control, and a
    /// single photograph is a thing somebody may want to vote on.
    ///
    /// **Named for where it goes.** R2 asks that a control be named for what it is rather than
    /// relabeled with the next tap; a door is what it goes to, and the hint carries the part of the
    /// destination the name cannot — that the photographs are votable there, which is the half of the
    /// report the delete's repair did not cover.
    private var browserDoor: some View {
        Button(action: onOpenBrowser) {
            Text(PhotoViewerCopy.allPhotos)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.textBody)
                .padding(.vertical, CypressSpacing.Component.headerPillPaddingV)
                .padding(.horizontal, CypressSpacing.Component.headerPillPaddingH)
                .background { Capsule().fill(CypressColor.heroBackFill) }
                .cypressShadow(CypressShadow.heroButton)
                // The drawn capsule is under 44 pt tall, so the target grows around it and the
                // visual stays where it is — ARCHITECTURE §6, the rule `HeroPhotoHeader`'s own pill
                // follows one screen up.
                .cypressTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityHint(PhotoViewerCopy.allPhotosHint)
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
                    PhotoTrashGlyph()
                        .stroke(
                            CypressColor.hazardCTAFill,
                            style: PhotoGlyphMetrics.style(for: PhotoViewerMetrics.closeGlyph)
                        )
                        .frame(
                            width: PhotoViewerMetrics.closeGlyph,
                            height: PhotoViewerMetrics.closeGlyph
                        )
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
                    PhotoCloseGlyph()
                        .stroke(
                            CypressColor.textBody,
                            style: PhotoGlyphMetrics.style(for: PhotoViewerMetrics.closeGlyph)
                        )
                        .frame(
                            width: PhotoViewerMetrics.closeGlyph,
                            height: PhotoViewerMetrics.closeGlyph
                        )
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
    /// The door onward to screen 20. "Of this tree" and not just "All photos": this cover is drawn
    /// over one tree's photograph with no other context on screen, and the app has no all-photos
    /// screen for the phone.
    static let allPhotos = "All photos of this tree"
    /// What is on the other side, in the words the report used — the browser is where a photograph
    /// is voted on, and that is the half of it the label cannot say.
    static let allPhotosHint = "Opens every photo of this tree, with a thumb up and down on each"
}
