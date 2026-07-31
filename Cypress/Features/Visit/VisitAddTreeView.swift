//
//  VisitAddTreeView.swift
//  Cypress — Features/Visit
//
//  The community add. Reached from screen 02's "None of these? Add this tree" (ERRATA E127).
//
//  **NOT SPECIFIED as a mock.** BUILD-PLAN §9 M2 requires the flow and names its one hard state
//  ("duplicate-proximity warning on add-a-tree"); SCREENS.md draws no screen for it. Per
//  ARCHITECTURE rule 8 nothing is invented where something specified will do, so every part of this
//  is borrowed from the screen that already draws it:
//
//  - the frame, the C1 header and the status chip row are screen 02's, which is where this is
//    entered from and which this is a continuation of;
//  - the photo well is screen 14 §2's dashed well — the same `borderDashedStrong` /
//    `surfaceEmptyThumb` / radius-18 card, tappable for the reason E123 gave: a dashed card is a
//    control when a user action would fill it;
//  - the two photo sources are screen 04's, in the order screen 04 puts them (live session first,
//    photo library as BUILD-PLAN §9 M1's fallback and the only path a simulator can take);
//  - the duplicate warning is C24, which is the component for "this needs something before it can
//    go on", and 02's own `VisitLowAccuracyPanel` is the neighbouring use of it.
//
//  Every decision about *whether* something draws is `VisitAddTreeModel`'s, and every string is
//  `VisitAddTreeCopy`'s, so both halves are testable without a renderer.
//
//  ── The pin ───────────────────────────────────────────────────────────────────────────────
//  This screen used to end with a footnote saying the tree is "recorded where you are standing", and
//  that sentence was the whole of the coordinate story. It is now a statement of the default with the
//  control that changes it underneath (`placementRow`), and the map it opens is `VisitPinAdjustView`.
//  Nothing about the fast path moved: with no pin placed the CTA still writes the fix, and the row
//  above it is one sentence a reader who is standing at the tree scrolls straight past.
//

import PhotosUI
import SwiftUI

struct VisitAddTreeView: View {

    @State private var model: VisitAddTreeModel
    @State private var libraryItem: PhotosPickerItem?

    /// Read for one decision: where the empty well's sentence is drawn. See `wellEmptyNotice`.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Held so the species picker can be handed the same boundary this screen writes through. The
    /// model owns its own reference; this one exists because `SpeciesPickView` builds its own model.
    private let api: any CypressAPI

    /// The tree was created — its id, so the caller can open it.
    let onAdded: (UUID) -> Void
    /// The dedupe found a tree already on record here and the reader chose it instead.
    let onOpenExisting: (UUID) -> Void
    let onBack: () -> Void

    init(
        api: any CypressAPI,
        location: VisitLocationProvider,
        attribution: Attribution,
        onAdded: @escaping (UUID) -> Void,
        onOpenExisting: @escaping (UUID) -> Void,
        onBack: @escaping () -> Void
    ) {
        _model = State(
            wrappedValue: VisitAddTreeModel(api: api, location: location, attribution: attribution)
        )
        self.api = api
        self.onAdded = onAdded
        self.onOpenExisting = onOpenExisting
        self.onBack = onBack
    }

    var body: some View {
        // The pin screen replaces this one rather than covering it, and that is the same decision as
        // `Phase.placingPin` itself: one model, one draft, one screen in two states. A cover would
        // have put a second `fullScreenCover` inside the one `RootView` already presents this flow
        // through, and the photograph would be sitting behind a modal that owns the whole screen
        // anyway.
        Group {
            if case .placingPin = model.phase {
                pinAdjust
            } else if case .pickingSpecies = model.phase {
                // Replaces the composer for the same reason the pin map does: one model, one draft,
                // one screen in several states. A sheet over a `fullScreenCover` would put the
                // photograph behind two layers and give the keyboard nowhere to go.
                SpeciesPickView(
                    api: api,
                    onPick: { model.chooseSpecies($0) },
                    onSkip: { model.skipSpecies() },
                    onBack: { model.cancelPickingSpecies() }
                )
            } else {
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
        .task { await model.load() }
        .onDisappear { model.stop() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.useLibraryImage(data)
                }
                libraryItem = nil
            }
        }
    }

    /// The map, anchored on the fix this screen would otherwise have used verbatim.
    @ViewBuilder
    private var pinAdjust: some View {
        if let anchor = model.pinAnchor {
            VisitPinAdjustView(
                anchor: anchor,
                accuracyM: model.fix.accuracyM,
                // Re-opening picks the pin up where it was left, so a second visit is a correction
                // rather than a restart.
                start: model.coordinate,
                onConfirm: { model.confirmPin($0) },
                onCancel: { model.cancelPlacingPin() }
            )
        }
    }

    /// **A `GeometryReader` around the scroll, and its one job is the well's ceiling (ERRATA E174).**
    /// `proxy.size.height` is the scroll viewport — what a reader can see without scrolling — and
    /// `VisitMetrics.AddTree.wellWidthCeiling` turns it into the width past which the photograph
    /// would leave no room for the form underneath it. Same shape as screen 04's
    /// `accessibilityLayout`, and for a related reason: a split at a *stated* line rather than
    /// whatever two flexible children happen to negotiate.
    ///
    /// **The accuracy chip is pinned with the header rather than scrolled with the form, and that
    /// is what makes the ceiling mean what it says.** "The well takes at most two thirds of the
    /// viewport" is only "a third of the viewport shows the form" if the well starts at the top of
    /// the viewport — with the chip above it inside the scroll, the chip's height came out of the
    /// third, and at AX5 the chip is 68 pt of a 287 pt viewport on the phone the tests host (78 of
    /// 247 on the iPhone 16e this was reported against), which is the whole of it. The chip
    /// is a statement about the screen rather than a row of the form (it is screen 02's status row,
    /// and 02 does not scroll it either), so pinning it is what it was always describing.
    private var composer: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: VisitAddTreeCopy.title, bottomInset: .wide, onBack: onBack)

            if let gps = model.gpsChipLabel {
                Chip(gps, style: .meta, leadingDot: CypressColor.gpsDot)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CypressSpacing.gutter)
                    .padding(.bottom, CypressSpacing.gapRows)
            }

            GeometryReader { viewport in
                ScrollView {
                    composerColumn(
                        wellWidthCeiling: VisitMetrics.AddTree.wellWidthCeiling(
                            viewport: viewport.size.height
                        )
                    )
                }
            }

            footer
        }
    }

    private func composerColumn(wellWidthCeiling: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            photoWell(widthCeiling: wellWidthCeiling)

            wellEmptyNotice

            photoSources

            placementRow

            landRow

            speciesRow

            if case let .duplicate(candidates) = model.phase {
                duplicateWarning(candidates)
            }

            if case let .failed(message) = model.phase {
                Text(message)
                    .cypressBody135(color: CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let reason = model.blockingReason {
                Text(reason)
                    .cypressBody135(color: CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.bottom, CypressSpacing.gapCandidates)
    }

    // MARK: - Where the tree goes

    /// One sentence about the coordinate that is about to be written, and the way to change it.
    ///
    /// **It sits between the photograph and the CTA on purpose.** The reader who is standing at the
    /// tree scrolls past it and presses `Add this tree`, and the fast path is still the fast path;
    /// the reader who shot from across the street reads a sentence that is *wrong about them* right
    /// before they commit, which is the only moment at which they would ever think to fix it. Putting
    /// it behind the CTA would have been a second screen nobody visits.
    ///
    /// It draws only with a fix, because `canAdjustPin` is gate 2: there is no map to open without a
    /// centre, and the blocking reason above already explains the missing fix in words.
    @ViewBuilder
    private var placementRow: some View {
        if model.canAdjustPin {
            VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                Text(VisitAddTreeCopy.placement(offsetM: model.pinOffsetM))
                    .cypressBody135(color: CypressColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)

                Button { model.beginPlacingPin() } label: {
                    Text(VisitPinAdjustCopy.openAction)
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaFill)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .cypressHitArea()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - What ground it stands on

    /// One sentence about the ground, and three chips that answer it.
    ///
    /// **NOT SPECIFIED.** SCREENS.md has no add-tree mock at all (see the file header), so this is
    /// built the way every other part of this screen is: from something already drawn. It is C4's
    /// chip flow in `CypressChipFlow`, which is the component screen 06 uses for exactly this shape
    /// of question — a short closed vocabulary, one answer at a time — and the sentence above it is
    /// `placementRow`'s and `speciesRow`'s, in the same voice, saying what the record will say.
    ///
    /// **It sits between the pin and the species, and the order is the argument.** Both rows above it
    /// are about *where*: the pin decides the coordinate, this decides the ground under it, and only
    /// then does the screen ask *what* the tree is. A reader who has just placed a pin from across the
    /// street is looking at the map they placed it on when this question arrives.
    ///
    /// **No gate.** Unlike `placementRow` there is nothing to wait for — the ground under a tree does
    /// not need a GPS fix — so the row is never hidden and the CTA never waits on it. A contributor
    /// who does not answer reads a sentence saying so and presses `Add this tree`, which is what makes
    /// the field genuinely optional rather than optional-if-you-find-the-skip.
    private var landRow: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(VisitAddTreeCopy.land(model.landContext))
                .cypressBody135(color: CypressColor.textBody)
                .fixedSize(horizontal: false, vertical: true)

            CypressChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(VisitAddTreeModel.offered, id: \.self) { context in
                    // C4's neutral selected/idle pair — screen 05's structure flags, not screen
                    // 06's hazard chips. The amber pair means "this tree needs something" (§1.1)
                    // and none of these three answers does: a tree in a garden is not a worse tree
                    // than a tree on a kerb. Nothing new is added to C4 for one screen.
                    Chip(
                        LandContextCopy.noun(context),
                        style: model.landContext == context ? .structureFlagOn : .structureFlagIdle
                    ) {
                        model.chooseLandContext(context)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint(VisitAddTreeCopy.landHint)
    }

    // MARK: - What the contributor says it is

    /// One sentence about the species, and the way to change it. Sits under the placement row and
    /// above the CTA, in the same shape as that row, because the two are the same kind of thing: a
    /// statement of what is about to be written, next to the control that changes it.
    ///
    /// **It is never a gate.** There is no fix to wait for and no state in which this is hidden — a
    /// species is not required (`VisitAddTreeModel.species` carries that argument), so it draws
    /// always and the CTA never waits on it. A reader standing at a tree they cannot name reads one
    /// sentence saying nobody has said what it is, and presses `Add this tree`.
    ///
    /// The second control appears only once a species has been chosen. Offering "not sure" to
    /// somebody who has not yet said anything would be asking them to decline an offer they were
    /// never made.
    @ViewBuilder
    private var speciesRow: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(VisitAddTreeCopy.species(model.species))
                .cypressBody135(color: CypressColor.textBody)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: CypressSpacing.gutterSheet) {
                Button { model.beginPickingSpecies() } label: {
                    Text(VisitAddTreeCopy.speciesAction(hasSpecies: model.species != nil))
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaFill)
                        .contentShape(Rectangle())
                }
                .cypressHitArea()

                if model.species != nil {
                    Button { model.skipSpecies() } label: {
                        Text(VisitAddTreeCopy.speciesClear)
                            .font(CypressFont.body13Bold)
                            .foregroundStyle(CypressColor.textMuted)
                            .contentShape(Rectangle())
                    }
                    .cypressHitArea()
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The photo

    /// 14 §2's dashed well, in the shape of the photograph it holds rather than a caption's height.
    ///
    /// **It is a portrait 3:4 frame, and it used to be a landscape one** — see
    /// `VisitMetrics.AddTree.wellAspectRatio` for the inverted ratio that made it so and what that
    /// cost the live viewfinder. `.aspectRatio(_:contentMode: .fit)` rather than a stated height, so
    /// the well is derived from whatever width it is given on whatever phone; the shape is the
    /// invariant, not the number.
    ///
    /// **The card is the base and the contents are an overlay, not a `ZStack`.** A `scaledToFill`
    /// photograph reports a size far larger than the frame it is drawn in, and a `frame(maxWidth:
    /// .infinity)` wrapped around it takes *that* size rather than the proposal — which is what this
    /// screen did on its first run: choosing a photo pushed the whole column wider than the phone and
    /// dragged the header and the CTA off to the left. `.overlay` sizes its content against the base
    /// and lets the excess hang, so the layout is the card's and only the drawing overflows. Seen by
    /// looking, on the simulator, after the tests were green.
    ///
    /// **It is bounded as well as shaped, and the bound is a width (ERRATA E174).** The shape is
    /// invariant; what the ceiling changes is how much of the column the well is allowed to take
    /// when the viewport is too short to hold it and a form as well. See
    /// `VisitMetrics.AddTree.wellWidthCeiling`.
    private func photoWell(widthCeiling: CGFloat) -> some View {
        VisitAddTreePhotoWell(widthCeiling: widthCeiling) { wellContents }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.hasPhoto ? VisitAddTreeCopy.wellFilled : VisitAddTreeCopy.wellEmpty)
            // Centred rather than left-aligned once the ceiling narrows it: the column is
            // `alignment: .leading`, and a photograph pinned to one edge of a column whose every
            // other row runs the full gutter reads as a layout accident. A no-op at the widths where
            // the ceiling does not bind. **Here and not inside the well**, so that the well still
            // measures as the card it is and `theAddTreeWellIsAPortraitCaptureFrame` can read a
            // ratio off it rather than off a greedy wrapper.
            .frame(maxWidth: .infinity)
    }

    /// The well has neither a photograph nor a live preview in it, so the sentence has to be drawn
    /// somewhere. **Spelled once**: `wellContents` chooses the branch and `wellEmptyNotice` chooses
    /// where the sentence lands, and if the two conditions ever drift the sentence is drawn twice or
    /// not at all. `isLive` alone is not it — a session that is live but not yet vended still draws
    /// the empty branch.
    private var wellIsEmpty: Bool {
        model.snapshot == nil && !(model.camera.isLive && model.camera.session != nil)
    }

    @ViewBuilder
    private var wellContents: some View {
        if let snapshot = model.snapshot {
            // ══════════════════════════════════════════════════════════════════════════════════
            // **Fitted, not filled — this is the second half of the reported defect.**
            //
            // Reported from the field: *"photo for custom tree should be standard photo style,
            // right now it's horizontal and cuts off vertical frame."* The well was 268 pt tall and
            // about 361 wide; `scaledToFill` scaled a 3:4 photograph to 481 pt and drew the middle
            // 268 of it, so a volunteer who had just photographed a tree in portrait — the correct
            // orientation for a tree — was shown a landscape band of its trunk.
            //
            // **That report had a second half this fix did not reach, and the owner sent it back:**
            // *"Add this tree photo window is still awkwardly horizontal and doesn't capture full
            // view on vertical orientation."* `PhotoFit` stopped the crop but the well stayed a
            // landscape box, so the photograph was merely letterboxed inside it and the *live*
            // preview — which fills rather than fits — went on cropping. The well is now the 3:4
            // frame itself (`VisitMetrics.AddTree.wellAspectRatio`), which is what makes `PhotoFit`
            // here draw edge to edge instead of with bars beside it.
            //
            // That is worse here than anywhere else in the app, because of what this particular
            // picture is *for*. Every other frame is a photograph being displayed; this one is a
            // photograph being **checked**, by the person standing in front of the tree, in the
            // last second before they commit it to a record they cannot easily amend. A crop at
            // that moment does not restyle the picture, it withholds the evidence — it can hide a
            // finger over the lens, a cut-off crown, or the fact that the shot is of next door's
            // tree. `PhotoFit` shows the file.
            //
            // **There is no longer a jump from viewfinder to still, and that is the point.** This
            // used to read as a deliberate feature — the live preview fills, the still fits, so the
            // frame "pulls back" at the moment of capture and shows what the well was never going to
            // show. With the well the same shape as the capture, fill and fit are the same drawing:
            // what you aimed at is what you are shown. The old behaviour was a symptom being read as
            // a design, and what it really told a volunteer was that the viewfinder had been lying.
            // Screen 04 keeps `PhotoFill` for its own reason — it has a ghost overlay to line up
            // against the preview, and `PhotoCropAnchor.centre` says why.
            // ══════════════════════════════════════════════════════════════════════════════════
            PhotoFit(image: snapshot)
        } else if model.camera.isLive, let session = model.camera.session {
            VisitCameraPreview(session: session)
        } else {
            // No live session: a simulator, a refusal, or the moment before the session starts.
            // The sentence and nothing else — screen 14's camera glyph is local to that folder by its
            // own note ("no other screen in SCREENS.md uses it"), and borrowing it here would make it
            // a shared component by accident. A dashed frame with one line in it is §5.6's restraint
            // applied to a space that is genuinely still empty.
            //
            // **At the accessibility sizes the sentence is not in here at all** — see
            // `wellEmptyNotice`. E159's rule for screen 04's viewfinder, applied to the other frame
            // in this feature that is sized by a photograph rather than by its contents: a frame
            // whose size does not follow the type ramp carries only furniture that does not either.
            if !dynamicTypeSize.isAccessibilitySize {
                emptyWellSentence
            }
        }
    }

    /// "A photo of the tree is required", drawn wherever it is legible.
    private var emptyWellSentence: some View {
        Text(VisitAddTreeCopy.wellEmpty)
            .font(CypressFont.body13)
            .foregroundStyle(CypressColor.textFaint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CypressSpacing.gutter)
    }

    /// The empty well's sentence, at the sizes where it does not fit inside the well (ERRATA E174).
    ///
    /// The well is sized by the photograph and the sentence is sized by the type ramp, so above a
    /// certain size the two stop being compatible: at AX5 on a 390 pt phone the well is 122 pt wide
    /// and this sentence sets four lines of ~33 pt type, which the well clips top and bottom into
    /// *"photo of the tree is requir"*. Same rule E159 wrote for screen 04 — a frame whose size does
    /// not follow the ramp carries only furniture that does not follow the ramp either, and
    /// everything that grows moves out into the column. It lands directly under the well, which is
    /// also the first thing a reader meets on the way down.
    ///
    /// Nothing is lost to VoiceOver at any size: the well's own `accessibilityLabel` is this string.
    @ViewBuilder
    private var wellEmptyNotice: some View {
        if dynamicTypeSize.isAccessibilitySize, wellIsEmpty {
            emptyWellSentence
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// The shutter, the library, and — once there is a frame — the way back to an empty well.
    @ViewBuilder
    private var photoSources: some View {
        if model.hasPhoto {
            SecondaryOutlineButton(VisitAddTreeCopy.retake, style: .compact) { model.retake() }
        } else {
            VStack(spacing: CypressSpacing.gapRows) {
                if model.camera.isLive {
                    PrimaryButton(VisitAddTreeCopy.shutter, style: .compact) {
                        Task { await model.snap() }
                    }
                }
                // Offered whether or not the session is live. BUILD-PLAN §9 M1 names the library as
                // the camera-denied fallback, and it is also the only path a simulator can take —
                // both facts point at the same control, so it is a real one rather than a stub.
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Text(VisitAddTreeCopy.chooseFromLibrary)
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaFill)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .cypressHitArea()
            }
        }
    }

    // MARK: - BUILD-PLAN §9 M2 · the duplicate-proximity warning

    /// What `POST /trees` said, in its own words and with its own candidates.
    ///
    /// C24, not C14: Signal Amber is "this tree needs something" (§1.1), and a refused add with a
    /// list of trees to choose between is precisely a thing needing attention before it goes on the
    /// record. The rows lead to the tree the API found, because the reader's next move — "oh, that
    /// one" — is the whole reason the endpoint returns the list instead of a bare error.
    private func duplicateWarning(_ candidates: [NearbyTree]) -> some View {
        AttentionCard {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                AttentionCard<EmptyView>.sectionLabel(VisitAddTreeCopy.duplicateLabel)
                Text(VisitAddTreeCopy.duplicateBody)
                    .cypressBody135(color: CypressColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(candidates) { candidate in
                    Button {
                        onOpenExisting(candidate.tree.id)
                    } label: {
                        HStack(spacing: CypressSpacing.gapCandidates) {
                            Text(VisitAddTreeCopy.candidateName(candidate))
                                .font(CypressFont.listNameSerif)
                                .foregroundStyle(CypressColor.textInk)
                            Spacer(minLength: 0)
                            Text(VisitAddTreeCopy.candidateDistance(candidate))
                                .font(CypressFont.mono12)
                                .foregroundStyle(CypressColor.textMuted)
                                .fixedSize()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cypressHitArea()
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            PrimaryButton(VisitAddTreeCopy.cta, isEnabled: model.canAdd) {
                Task {
                    if let id = await model.add() { onAdded(id) }
                }
            }
            Text(VisitAddTreeCopy.footnote)
                .cypressBody135(color: CypressColor.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, VisitMetrics.Identify.footerTop)
        .padding(.bottom, CypressSpacing.bottomCTA)
    }
}

// MARK: - The photo well

/// Screen 14 §2's dashed well, at the shape of the photograph it holds.
///
/// ── Why this is its own type ───────────────────────────────────────────────────────────────
/// Because its shape is the whole of #113 and a `private var` on the screen cannot be measured.
/// `VisitPhenologyChips` was pulled out for the same reason on the same day, and `VisitShotTypeChips`
/// before both — a row or a frame whose geometry is the defect has to be hostable on its own, or the
/// test that guards it is a test of its parent. See `theAddTreeWellIsAPortraitCaptureFrame`.
///
/// **The card is the base and the contents are an overlay, not a `ZStack`.** A `scaledToFill`
/// photograph reports a size far larger than the frame it is drawn in, and a `frame(maxWidth:
/// .infinity)` wrapped around it takes *that* size rather than the proposal — which is what this
/// screen did on its first run: choosing a photo pushed the whole column wider than the phone and
/// dragged the header and the CTA off to the left. `.overlay` sizes its content against the base and
/// lets the excess hang, so the layout is the card's and only the drawing overflows. Seen by looking,
/// on the simulator, after the tests were green.
struct VisitAddTreePhotoWell<Content: View>: View {

    /// The widest this well may be drawn — `VisitMetrics.AddTree.wellWidthCeiling` of the composer's
    /// scroll viewport, and `.infinity` for a caller with no viewport to answer for.
    ///
    /// **The bound is a width because the shape is not negotiable (ERRATA E174).** With
    /// `.aspectRatio(_:contentMode: .fit)` one dimension derives the other, so a width ceiling is a
    /// height ceiling at exactly the same ratio: the well shrinks along its own diagonal and stays
    /// the frame of the photograph it holds. Capping the *height* of a gutter-wide box would give
    /// back the landscape letterbox E162 removed, and the live preview — which is
    /// `.resizeAspectFill` — would crop the crown off the tree again.
    var widthCeiling: CGFloat = .infinity

    @ViewBuilder let content: () -> Content

    var body: some View {
        RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
            .fill(CypressColor.surfaceEmptyThumb)
            // The shape, and the reason it is a ratio rather than a height, are in
            // `VisitMetrics.AddTree.wellAspectRatio`.
            .aspectRatio(VisitMetrics.AddTree.wellAspectRatio, contentMode: .fit)
            .frame(maxWidth: widthCeiling)
            .overlay { content() }
            // `.clipShape`, not `.clipped()`: ERRATA E114 is this codebase's own record of an overhang
            // that clipped its drawing and kept its touches, swallowing every control beneath it.
            // Clipping to the shape clips both.
            .clipShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
            .cypressDashedBorder(
                CypressColor.borderDashedStrong,
                radius: CypressRadius.cardLg,
                width: CypressSpacing.Component.outlineWidth
            )
    }
}

// MARK: - Copy

/// Every string this screen renders. **None of it is verbatim from a mock** — there is no mock (see
/// the file header) — so each one is here to be argued with in one place, and each states a fact and
/// stops (ARCHITECTURE §5.7).
enum VisitAddTreeCopy {

    /// The C1 title. Screen 02's button says "Add this tree"; the screen it opens is named for the
    /// same act rather than for a different one.
    static let title = "Add this tree"

    static let wellEmpty = "A photo of the tree is required"
    static let wellFilled = "Photo of the tree you are adding"

    static let shutter = "Take the photo"
    static let chooseFromLibrary = "Choose a photo from this phone"
    static let retake = "Use a different photo"

    static let cta = "Add this tree"

    /// Where the coordinate is coming from, in one sentence, above the CTA.
    ///
    /// **The first form used to be the whole story and it was the limitation the owner named.** "The
    /// tree is recorded where you are standing" was true, unavoidable, and wrong about anybody who
    /// photographed a tree from the far kerb. It is now a statement of the *default*, sitting next to
    /// the control that changes it, which is what turns a constraint into a choice.
    ///
    /// The moved form gives the distance and stops. No bearing here, unlike the pin screen's own
    /// sentence: this is a reminder of a decision already taken, and the reader who wants the detail
    /// back presses the control underneath and gets the map with the bearing on it.
    static func placement(offsetM: Double?) -> String {
        guard let offsetM else {
            return "This tree will be recorded where you are standing."
        }
        return "This tree will be recorded \(Int(offsetM.rounded())) m from where you are standing."
    }

    /// What the record will say about the species, in one sentence, above the CTA.
    ///
    /// **Both forms are statements of fact about the row that is about to be written**, in the same
    /// voice as `placement(offsetM:)` right above them, because they are the same kind of sentence.
    ///
    /// The named form says **your claim** and says it before the species, not after. Word order is
    /// the whole design here: "recorded as a London plane, unverified" leads with the botany and
    /// qualifies it, which is how a reader ends up remembering the botany. Leading with the
    /// attribution says who is speaking before it says what they said, which is what this row is for.
    /// It also names the alternative it is *not* — a confirmed identification — because the reader
    /// has no other way to know the app is declining to make one.
    ///
    /// The empty form does not apologise. An unnamed tree is the honest output of a contributor who
    /// does not know, and a sentence that made it sound like a gap would be pressure to guess, which
    /// is the failure mode `VisitAddTreeModel.species` argues this whole row must avoid.
    static func species(_ species: Species?) -> String {
        guard let species else {
            return "No species will be recorded. An unnamed tree is still a tree on the map."
        }
        let name = species.commonName.isEmpty ? species.scientificName : species.commonName
        return "This will be recorded as your claim that it is a \(name) — "
            + "not as a confirmed identification."
    }

    /// What the record will say about the ground, in one sentence, above the chips that change it.
    ///
    /// **The empty form does not apologise, and here that matters more than it does for the
    /// species.** A sentence that made an unanswered land context sound like a gap would be pressure
    /// to tap something, and the cheapest tap is the first chip — which is `Street or sidewalk`,
    /// which is the answer that makes a tree in somebody's front garden look like the city's to fix.
    /// Optionality that is nagged at is not optionality. So the empty form states what the record
    /// will say and stops, exactly as `species(_:)` does.
    ///
    /// The answered form says **you say**, and says it before the ground, for `species(_:)`'s reason:
    /// leading with the attribution says who is speaking before it says what they said. There is no
    /// second source for this fact on a community row — nobody is checking — and the sentence should
    /// not let a reader forget that between tapping a chip and pressing the CTA.
    static func land(_ context: LandContext?) -> String {
        guard let context else {
            return "Where it stands will not be recorded. The tree goes on the map either way."
        }
        return "This will be recorded as your answer that it stands "
            + "\(LandContextCopy.standing(context))."
    }

    /// The row's hint, said once for the whole group rather than repeated on three chips.
    static let landHint = "Optional. Tap the answer again to clear it."

    static func speciesAction(hasSpecies: Bool) -> String {
        hasSpecies ? "Choose a different species" : "Say what species it is"
    }

    /// The retraction, in the picker's own words so that one act has one name in both places.
    static let speciesClear = SpeciesPickCopy.skip

    /// What the record will say. Both halves are facts about what `addTree` writes: the source is
    /// `community` and the verification state is `unverified`, which screen 03 prints as
    /// "community-added, unverified".
    ///
    /// It no longer says *where*, because the row above the CTA now owns that and says it more
    /// precisely. One screen must not carry two sentences about the coordinate that can disagree.
    static let footnote =
        "Recorded as community-added and unverified, on this phone."

    static let noPhoto = "A photo is what makes this a record of a tree rather than a pin."
    static let noLocationPending = "Waiting for a fix. A tree is a place, so it cannot be added without one."
    static let noLocationDenied =
        "Cypress cannot see where you are, and a tree is a place. Turn location on in Settings to add one."

    static func photoNotStored(_ error: Error) -> String {
        "That photo could not be saved to this phone: \(error.localizedDescription)"
    }

    static let addFailed = "This tree could not be added. Nothing was recorded."

    /// BUILD-PLAN §9 M2's warning. The number is `TreeDraft.proximityDedupeRadiusM` rather than a
    /// literal, because the sentence is a claim about the rule the API just applied.
    static let duplicateLabel = "ALREADY ON RECORD"
    static var duplicateBody: String {
        "Something is already on record within \(Int(TreeDraft.proximityDedupeRadiusM)) m of here. "
            + "Nothing was added. If one of these is the tree in front of you, open it."
    }

    /// A candidate's name, by the same rule every other surface names a tree: the species common
    /// name, its scientific name, then the honest "we do not know" (`VisitCandidate.displayName`).
    static func candidateName(_ candidate: NearbyTree) -> String {
        candidate.speciesCommonName ?? candidate.speciesScientificName ?? "Unidentified tree"
    }

    /// `4 m` — the API's own measured distance, rounded to the metre. No bearing: `VisitBearing`
    /// needs the origin the distance was measured from, and this list is the API's answer rather
    /// than a ranking this screen performed.
    static func candidateDistance(_ candidate: NearbyTree) -> String {
        "\(Int(candidate.distanceM.rounded())) m"
    }
}
