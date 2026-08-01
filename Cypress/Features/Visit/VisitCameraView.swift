//
//  VisitCameraView.swift
//  Cypress — Features/Visit
//
//  Screen 04 · Visit (dark camera)
//  "The camera opens straight to a ghost overlay of the last photo so the timeline stays
//  comparable. Note and phenology tag are optional; offline, submit still succeeds. Phenology chips
//  come from the species record, so an evergreen never gets asked about fall color."
//
//  Dark **always**, regardless of the system setting (ARCHITECTURE §6) — `.cypressForcedDark()`.
//

import PhotosUI
import SwiftUI

struct VisitCameraView: View {

    @State private var model: VisitCameraModel
    @State private var libraryItem: PhotosPickerItem?
    /// The capture whose flash has already been faded out. See `shutterFlash`.
    @State private var fadedCaptureTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onSaved: (VisitSaveReceipt) -> Void
    let onClose: () -> Void

    init(
        treeID: UUID,
        treeDisplayName: String,
        // A closure, not a number: `@State` runs its initialiser once, and a camera session is the
        // longest a contribution form stays open in this app
        // (ERRATA E158).
        gpsAccuracyM: @escaping @MainActor () -> Double?,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        onSaved: @escaping (VisitSaveReceipt) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = State(wrappedValue: VisitCameraModel(
            treeID: treeID,
            treeDisplayName: treeDisplayName,
            gpsAccuracyM: gpsAccuracyM,
            api: api,
            outbox: outbox,
            attribution: attribution
        ))
        self.onSaved = onSaved
        self.onClose = onClose
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════
    // THE ACCESSIBILITY VARIANT (R14; ERRATA E159)
    //
    // Below the accessibility sizes this screen is exactly what SCREENS 04 draws: a viewfinder that
    // takes what is left after the tray, with the framing chips and the shutter overlaid on its
    // bottom edge. Nothing in the drawn layout moves.
    //
    // At the accessibility sizes the tray outgrows the display, and the *overlay* is what breaks:
    // an overlay aligned `.bottom` pins its bottom edge to the viewfinder's, so when the viewfinder
    // is squeezed shorter than the overlay the chip row grows **upward, off the top of the screen**
    // — under the status bar and the Dynamic Island, where it cannot be read and does not answer a
    // tap. That is E152 — one session, three framings — becoming unreachable, and it is the defect
    // this variant exists to close.
    //
    // R14's answer, and the rule this code applies: the viewfinder keeps a floor and everything else
    // scrolls. What that means concretely is that **the viewfinder carries only furniture whose size
    // does not depend on the type ramp** — the close button, the framing corners, the shutter — and
    // every element that grows with the ramp moves into the scrolling controls below it. The one
    // deliberate exception is the guidance pill, because with the chips moved down it is the only
    // thing left saying which framing you are aiming at; it is top-anchored, so it grows down into
    // the frame rather than off the display, and it is hit-transparent.
    // ══════════════════════════════════════════════════════════════════════════════════════════════

    /// Whether this is the accessibility variant. `isAccessibilitySize` — AX1 and up — and not a
    /// number of its own: measured on a 393 × 852 pt phone, the viewfinder is 583 pt at the drawn
    /// size, 550 pt at `xxxLarge` and 503 pt at AX1, so the floor (524 pt) first binds exactly where
    /// this predicate first turns true. It is also the switch every other adaptive component in the
    /// app already uses; a ninth spelling of "large text" would be drift.
    private var controlsScroll: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if controlsScroll {
                accessibilityLayout
            } else {
                drawnLayout
            }
        }
        .background(CypressColor.Dark.bgCamera)
        .ignoresSafeArea(edges: .top)
        .cypressForcedDark()
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

    // MARK: - The two layouts

    /// SCREENS 04, unchanged: `flex:1` viewfinder over a `flex:none` tray.
    private var drawnLayout: some View {
        VStack(spacing: 0) {
            viewfinder
            controls
                .background(CypressColor.Dark.bgCameraTray)
        }
    }

    /// R14's variant: the viewfinder at its floor, the controls scrolling under it.
    ///
    /// A `GeometryReader` rather than two flexible frames in a `VStack`, because two flexible
    /// children split the space between them and what is wanted here is a split at a *stated* line —
    /// the floor — with the remainder going to the scroll. Both halves are computed from one height,
    /// so they always sum to it and neither can be pushed off the display by the other.
    private var accessibilityLayout: some View {
        GeometryReader { geo in
            let floor = VisitMetrics.Camera.viewfinderFloor(
                width: geo.size.width,
                available: geo.size.height
            )
            VStack(spacing: 0) {
                viewfinder
                    .frame(height: floor)
                ScrollView {
                    controls
                }
                .frame(height: max(0, geo.size.height - floor))
                // Only bounce when there is something to bounce to: on a display roomy enough to
                // hold every control, a scroll view that rubber-bands is claiming content it has not
                // got.
                .scrollBounceBehavior(.basedOnSize)
                .background(CypressColor.Dark.bgCameraTray)
            }
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            base

            // ══════════════════════════════════════════════════════════════════════════════════
            // THE GHOST OVERLAY — the last full-tree photo at 30 % opacity.
            //
            // This is the single artefact the docs say the official city app will never have. It
            // is drawn *over* the live preview and *under* the framing furniture, and it goes away
            // the moment a frame is taken, because at that point there is nothing left to line up.
            //
            // It also goes away when the subject changes. `model.showsGhost`, not `model.ghost` —
            // see there for why a trunk close-up gets no tree behind it (ERRATA E125).
            // ══════════════════════════════════════════════════════════════════════════════════
            if !model.hasSnapped {
                ghostLayer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .top) { guidancePill }
        .overlay { framingCorners }
        // **One** bottom-anchored stack, not two. See `VisitMetrics.Camera.shotTypeGapAboveShutter`:
        // the chip row and the shutter block were separate overlays at `bottom:150` and `bottom:34`,
        // and the fallback sentence inside the shutter block grew up through the chips at AX1.
        .overlay(alignment: .bottom) { bottomControls }
        .overlay(alignment: .bottomLeading) { ghostCaption }
        .overlay { shutterFlash }
    }

    /// czFlash — a sheet of white at `.9` alpha falling to nothing over `.35s`, fired when the
    /// frame is taken. `CypressMotion.flash`.
    ///
    /// The flash is the only feedback that a photo was captured that arrives *before* the snapshot
    /// replaces the viewfinder, and on a simulator or a library fallback the snapshot is the only
    /// other signal there is. It is also the clearest case in the app for Reduce Motion: a
    /// full-screen luminance change is exactly what the setting exists to suppress, so under it
    /// the flash does not draw at all and the snapshot arriving is the confirmation.
    ///
    /// **Keyed on `model.captureTick`, not on `model.hasSnapped`.** `hasSnapped` is per framing now, so
    /// it turns true both when a photograph is taken and when a chip that already has one is selected —
    /// and the second of those flashed the screen white at somebody who had taken nothing. The tick only
    /// ever counts captures. See `VisitCameraModel.captureTick`.
    ///
    /// Two keyframes out of one monotonic counter: the body renders full opacity for the frame in which
    /// the tick is ahead of `fadedCaptureTick`, and `onChange` — which runs after that frame — animates
    /// the two back into agreement. A reset flag would not survive back-to-back captures.
    @ViewBuilder
    private var shutterFlash: some View {
        if !reduceMotion {
            Color.white
                .opacity(model.captureTick > fadedCaptureTick ? CypressMotionOffset.flashOpacity : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onChange(of: model.captureTick) { _, tick in
                    withAnimation(CypressMotion.flash) { fadedCaptureTick = tick }
                }
        }
    }

    @ViewBuilder
    private var base: some View {
        if let snapshot = model.snapshot {
            // `PhotoFill`, not `scaledToFill` — a portrait photo measured 234 pt wider than the
            // phone and took the tray with it (ERRATA E125). See `PhotoFill`.
            //
            // **`.centre`, against the component's default**, and it has to be: this frame, the
            // ghost under it and the live `AVCaptureVideoPreviewLayer` behind both are three
            // drawings of the same scene that only mean anything if they agree, and the preview
            // layer's `.resizeAspectFill` centres. See `PhotoCropAnchor.centre`.
            PhotoFill(image: snapshot, label: "The photo you just took", anchor: .centre)
        } else if model.camera.isLive, let session = model.camera.session {
            VisitCameraPreview(session: session)
        } else {
            // No session: a simulator, a refusal, or the moment before the session starts. The
            // documented viewfinder gradient, so the screen still reads as a viewfinder.
            VisitViewfinderPlaceholder()
        }
    }

    @ViewBuilder
    private var ghostLayer: some View {
        if let ghost = model.ghost, model.subjectTakesGhost {
            // `.centre` for the same reason the snapshot above uses it, and it is the half that
            // matters most: the ghost is what the new frame is lined up against.
            PhotoFill(image: ghost, anchor: .centre)
                .opacity(VisitMetrics.Camera.ghostOpacity)
                .allowsHitTesting(false)
        } else if !model.camera.isLive, model.subjectTakesGhost {
            // First visit, no camera: `CypressGradient.cameraGhost` is the spec's stand-in for the
            // alignment layer, so the screen's own subject is visible in a simulator. It is never
            // drawn over a live preview — an invented ghost on a real camera would be a lie about
            // where the last photo was taken from. It is a stand-in for the alignment layer, so it
            // follows the same subject rule the real one does.
            CypressGradientField(CypressGradient.cameraGhost)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The one growing element the accessibility variant keeps on the viewfinder.
    ///
    /// It stays because with the chip row moved into the scroll it is the only thing left that says
    /// which framing is being aimed, and it can stay because it is anchored to the *top*: it grows
    /// down into the frame rather than off the display, and it is hit-transparent, so nothing behind
    /// it is put out of reach.
    ///
    /// **Its inset is the one number that has to move.** At the drawn sizes the pill is narrow and sits
    /// beside the ✕; at AX5 it is the full width of the phone and covers it completely — the ✕ is
    /// still tappable, because the pill takes no hits, but a control you cannot see is a control you
    /// cannot find, and this one is how you leave the screen. So at accessibility sizes the pill drops
    /// below the close button's row instead of sharing it. Composed from the two tokens that decide
    /// where that row is, so it stays correct if either moves.
    private var guidancePill: some View {
        Text(model.guidance)
            .font(CypressFont.body13)
            .foregroundStyle(VisitColor.guidancePillText)
            .padding(.vertical, VisitMetrics.Camera.guidancePillPaddingV)
            .padding(.horizontal, VisitMetrics.Camera.guidancePillPaddingH)
            .background {
                Capsule()
                    .fill(VisitColor.guidancePillFill)
                    .background { Capsule().fill(.ultraThinMaterial) }
            }
            .padding(.top, controlsScroll ? guidancePillTopBelowClose : VisitMetrics.Camera.guidancePillTop)
            .allowsHitTesting(false)
    }

    /// Clear of the ✕ rather than across it — see `guidancePill`.
    private var guidancePillTopBelowClose: CGFloat {
        CypressSpacing.Device.statusBarInset + VisitMetrics.Camera.closeButton + CypressSpacing.gapRows
    }

    private var framingCorners: some View {
        ZStack {
            ForEach(VisitFramingCorner.Corner.allCases, id: \.self) { corner in
                VisitFramingCorner(corner: corner)
                    .stroke(
                        CypressColor.cameraFramingCorner,
                        lineWidth: VisitMetrics.Camera.framingCornerStroke
                    )
                    .frame(
                        width: VisitMetrics.Camera.framingCornerSide,
                        height: VisitMetrics.Camera.framingCornerSide
                    )
                    .padding(.top, VisitMetrics.Camera.framingCornerTop)
                    .padding(.bottom, VisitMetrics.Camera.framingCornerBottom)
                    .padding(.horizontal, VisitMetrics.Camera.framingCornerInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The chip row and the shutter, in one stack, anchored to the bottom of the viewfinder.
    ///
    /// **At accessibility sizes only the shutter is here**, and that is the answer to the third
    /// question R14 left open. The shutter *pins*; the chips travel.
    ///
    /// The shutter pins because it is the half of the viewfinder that is not a picture. A person on
    /// this screen is holding a phone up at a tree, and aiming and firing are one gesture: a shutter
    /// you have to scroll to find is a shot you lose your aim to reach, which is the same argument
    /// that keeps the viewfinder on screen at all. It costs a constant 68 pt at every text size,
    /// where the controls' cost grows without bound, so it is also the cheapest thing on the screen
    /// to keep. And it does not change house between size classes — it is bottom-anchored on the
    /// viewfinder at 34 pt whatever the ramp says, so a reader who learns where it is at one size
    /// finds it at every other. SCREENS.md §5's own gap 11 already reads this way for the rest of the
    /// app: "scrollable content with a pinned CTA".
    ///
    /// The argument the other way, so that it is on the record rather than merely lost: those 68 pt
    /// plus 34 are viewport the scrolling controls could have, and once all three framings are
    /// photographed the shutter has nothing left to do. It is refused because the screen cannot know
    /// when a contributor is finished — `retake` is one tap away on every framing — and because a
    /// control that is sometimes pinned and sometimes not is worse than one that is always pinned.
    private var bottomControls: some View {
        VStack(spacing: VisitMetrics.Camera.shotTypeGapAboveShutter) {
            if !controlsScroll {
                shotTypeChips
            }
            shutter
        }
        .padding(.bottom, VisitMetrics.Camera.shutterBottom)
    }

    private var shotTypeChips: some View {
        VisitShotTypeChips(
            framings: model.shotTypes.map { type in
                VisitShotTypeChips.Framing(
                    id: type,
                    label: model.label(for: type),
                    isSelected: model.shotType == type,
                    isCaptured: model.capturedShotTypes.contains(type)
                )
            },
            select: { model.shotType = $0 }
        )
        // The gutter is the overlay's own when the row is on the viewfinder; in the scroll the
        // controls column has already applied it, and applying it twice would inset this row past
        // every other control in the column.
        .padding(.horizontal, controlsScroll ? 0 : VisitMetrics.Camera.trayPadding)
    }

    @ViewBuilder
    private var shutter: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            if model.camera.needsLibraryFallback, !controlsScroll {
                // Same treatment as the guidance pill: this sentence sits on the viewfinder, and
                // plain text there is unreadable against a photograph.
                //
                // At accessibility sizes it is not here at all — see `fallbackLine`. It is the
                // sentence E152 already had to rescue once from growing up through the chip row, and
                // it is the clearest case of the rule this variant follows: it is copy, it grows with
                // the ramp, and copy on a viewfinder that cannot grow has nowhere to go.
                Text(fallbackReason)
                    .font(CypressFont.body125)
                    .foregroundStyle(VisitColor.guidancePillText)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, VisitMetrics.Camera.guidancePillPaddingV)
                    .padding(.horizontal, VisitMetrics.Camera.guidancePillPaddingH)
                    .background {
                        Capsule()
                            .fill(VisitColor.guidancePillFill)
                            .background { Capsule().fill(.ultraThinMaterial) }
                    }
                    .padding(.horizontal, CypressSpacing.gutter)
            }

            if model.camera.needsLibraryFallback {
                PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                    VisitShutterButton(isLibrary: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose a photo from your library")
            } else {
                Button {
                    if model.hasSnapped {
                        model.retake()
                    } else {
                        Task { await model.snap() }
                    }
                } label: {
                    VisitShutterButton(isLibrary: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.hasSnapped ? "Take another photo" : "Take the photo")
            }
        }
        // The bottom inset belongs to `bottomControls` now — this block is no longer the last thing
        // above the tray on its own.
    }

    private var fallbackReason: String {
        switch model.camera.availability {
        case .denied:
            // BUILD-PLAN §9: "camera permission ask and denied fallback (photo library)".
            return "Camera access is off. Add the photo from your library instead."
        case .unavailable, .failed:
            return "No camera available here. Add the photo from your library instead."
        default:
            return ""
        }
    }

    /// The caption on the ghost layer, in the corner SCREENS 04 puts it.
    ///
    /// Absent at accessibility sizes, where `ghostCaptionLine` says the same words in the scroll.
    /// Its `max-width:80px` is what makes it impossible to keep here: at AX5 that is a column of
    /// single stacked syllables running the height of the viewfinder and straight through the
    /// shutter, which is what the before-shots of this defect show.
    @ViewBuilder
    private var ghostCaption: some View {
        if !model.hasSnapped, !controlsScroll {
            Text(model.ghostCaption)
                .font(CypressFont.mono105)
                .foregroundStyle(VisitColor.ghostCaption)
                .lineSpacing(VisitMetrics.Camera.ghostCaptionLineSpacing)
                .frame(maxWidth: VisitMetrics.Camera.ghostCaptionMaxWidth, alignment: .leading)
                .padding(.leading, VisitMetrics.Camera.ghostCaptionLeading)
                .padding(.bottom, VisitMetrics.Camera.ghostCaptionBottom)
                .allowsHitTesting(false)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                Circle().fill(VisitColor.cameraCloseFill)
                VisitCloseGlyph()
                    .stroke(
                        CypressColor.Dark.textSecondary,
                        style: StrokeStyle(
                            lineWidth: VisitMetrics.Camera.closeStroke,
                            lineCap: .round
                        )
                    )
                    .frame(width: VisitMetrics.Camera.closeGlyph, height: VisitMetrics.Camera.closeGlyph)
            }
            .frame(width: VisitMetrics.Camera.closeButton, height: VisitMetrics.Camera.closeButton)
        }
        .buttonStyle(.plain)
        .padding(.top, CypressSpacing.Device.statusBarInset)
        .padding(.leading, CypressSpacing.gutter)
        .accessibilityLabel("Close the camera")
    }

    // MARK: - Controls

    /// Everything that is not the viewfinder: the tray SCREENS 04 draws, and — at accessibility
    /// sizes only — the three elements that come down off the viewfinder to join it.
    ///
    /// The order of those three is deliberate. **The chip row is first**, immediately under the frame
    /// it aims, because this whole variant exists because the chips were unreachable and the
    /// strongest discharge of that is a chip row nobody has to scroll to. The fallback sentence is
    /// second, directly beneath the pinned shutter it explains. The ghost caption is third: it is a
    /// legend for the layer above, and the least urgent thing on the screen.
    private var controls: some View {
        VStack(spacing: VisitMetrics.Camera.traySpacing) {
            if controlsScroll {
                shotTypeChips
                fallbackLine
                ghostCaptionLine
            }

            // What this session could still hold, once it holds something. In the tray rather than over
            // the viewfinder because it is about the visit being composed, not about the frame being
            // aimed — and because a second pill on the viewfinder is what E125's overflow was made of.
            if let line = model.remainingShotsLine {
                Text(line)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.Dark.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            noteField

            if !model.availablePhenologyTags.isEmpty {
                phenologyChips
            }

            logVisitButton

            offlineLine

            if let error = model.saveError {
                Text(error)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.Dark.accentAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, VisitMetrics.Camera.trayPadding)
        .padding(.top, VisitMetrics.Camera.trayPadding)
        .padding(.bottom, VisitMetrics.Camera.trayBottom)
        // The fill belongs to whatever is hosting this: the tray itself in the drawn layout, the
        // scroll view in the accessibility one, so that the colour reaches the bottom of the display
        // whether or not the content does.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The camera-denied sentence, as tray copy rather than as a pill on a photograph
    /// (accessibility sizes only; see `shutter` for where it lives otherwise).
    ///
    /// No capsule and no material here. That treatment exists to make the sentence legible *over a
    /// photograph*; on the tray it would be a floating pill in a column of left-aligned copy. It
    /// takes the tray's own primary ink instead — it explains why the primary action is a library
    /// picker, which is not muted information.
    @ViewBuilder
    private var fallbackLine: some View {
        if model.camera.needsLibraryFallback {
            Text(fallbackReason)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `ghost overlay 30%`, in the scroll (accessibility sizes only; see `ghostCaption`).
    ///
    /// It keeps its mono face and its colour, so it is recognisably the same caption, and drops the
    /// 80 pt width cap that is the only part of it the type ramp cannot survive.
    @ViewBuilder
    private var ghostCaptionLine: some View {
        if !model.hasSnapped {
            Text(model.ghostCaption)
                .font(CypressFont.mono105)
                .foregroundStyle(VisitColor.ghostCaption)
                .lineSpacing(VisitMetrics.Camera.ghostCaptionLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var noteField: some View {
        TextField(
            "",
            text: $model.note,
            prompt: Text("Anything worth remembering?")
                .foregroundColor(CypressColor.Dark.textFaint),
            axis: .vertical
        )
        .font(CypressFont.body145)
        .foregroundStyle(CypressColor.Dark.textPrimary)
        .tint(CypressColor.Dark.accentMint)
        .lineLimit(1...3)
        .padding(.vertical, VisitMetrics.Camera.notePaddingV)
        .padding(.horizontal, VisitMetrics.Camera.notePaddingH)
        .frame(minHeight: VisitMetrics.Camera.noteMinHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.Dark.surfaceCardAlt)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .strokeBorder(CypressColor.Dark.borderCamera, lineWidth: CypressSpacing.Component.hairline)
        }
    }

    /// SCREENS 04 §2's phenology row. See `VisitPhenologyChips`.
    @ViewBuilder
    private var phenologyChips: some View {
        if let species = model.species {
            VisitPhenologyChips(
                species: species,
                tags: model.availablePhenologyTags,
                isOn: { model.selectedTags.contains($0) },
                toggle: { model.toggle($0) }
            )
        }
    }

    private var logVisitButton: some View {
        // "the prototype gates `Log visit` on having snapped a photo" — both visually and
        // functionally (PROTOTYPE-FLOW §1.6.1). SCREENS.md marks the disabled styling NOT
        // SPECIFIED; the prototype's own `logBtnStyle` supplies it — fill `#26332A`, label
        // `#5F6F61`. The label is `Dark.textFaint` exactly; the fill has no token of its own, so
        // the nearest documented dark surface (`Dark.surfaceThumb`) stands in rather than a
        // literal being introduced for a state the spec never drew.
        Group {
            if model.canLogVisit {
                PrimaryButton(model.logVisitLabel, style: .camera) {
                    Task {
                        if let receipt = await model.logVisit() { onSaved(receipt) }
                    }
                }
            } else {
                Text(model.isSaving ? "Saving…" : "Log visit")
                    .font(CypressFont.body16ExtraBold)
                    .foregroundStyle(CypressColor.Dark.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(CypressSpacing.Component.buttonPadding)
                    .background {
                        RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                            .fill(CypressColor.Dark.surfaceThumb)
                    }
                    .accessibilityLabel("Log visit, unavailable until you take a photo")
            }
        }
    }

    private var offlineLine: some View {
        // SCREENS 04 draws `No signal · saved to outbox, syncs automatically`. Nothing in the app
        // measures signal, and claiming there is none would be the same class of untruth as
        // "sent to the city" (ARCHITECTURE §5.4). What is always true is the order of operations,
        // which is also the reassurance the line exists to give.
        HStack(spacing: VisitMetrics.Camera.chipGap) {
            Circle()
                .fill(CypressColor.Dark.accentAmber)
                .frame(width: VisitMetrics.Camera.offlineDot, height: VisitMetrics.Camera.offlineDot)
            Text("Saved to your outbox first · syncs on its own")
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.Dark.textMuted)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - The chip row

/// The three framings, and which of them this session has already photographed.
///
/// ── Why the chips had to start reporting state (ERRATA E152) ───────────────────────────────
/// One session can take all three now, so these chips are no longer three ways of labelling one
/// photograph — they are three slots, and a contributor has to be able to see which are filled without
/// tapping each one to find out. The mark is a `CypressCheckmark`, the same shape screen 18's success
/// circle and screen 05's selected row draw, so nothing new is invented for it; it is a `Shape` sized by
/// its frame rather than by the type ramp, which is what keeps it inside a chip that grows its label at
/// AX sizes.
///
/// `CypressChipFlow` and not an `HStack`, and the reason is **legibility, not overflow** — a correction
/// to what this code first said. The claim was that three chips wearing checkmarks at AX5 are wider than
/// the phone and an `HStack` would push the third off the right edge, the way #45's tray once did. That
/// is not what happens, measured: in the 361 pt this row is given, an `HStack` reports 326 pt and fits,
/// because SwiftUI compresses its children rather than overflowing a proposal. What it costs to fit is
/// the chips themselves — each is squeezed from its natural 158 pt to about 103 and its label wraps into
/// a column of stacked syllables, which is what the phenology row below already looks like at AX5. The
/// flow keeps every chip its own size and puts the overflow on a second row. Same component as screen
/// 05's structure chips and the add screen's land row.
///
/// ── Why this is its own type rather than a `private var` on the screen ─────────────────────────
/// Because the sentence above needed a test that could fail, and the one it had could not. It hosted the
/// *whole* of screen 04 at AX5 and asserted the result measured no wider than the phone — and this row
/// is an `.overlay` on the viewfinder, and **an overlay never enlarges what it is over**. Putting the
/// row back to an `HStack` left that test green. Hosting the row on its own is what let it be measured
/// at all, which is also how the paragraph above got corrected; see
/// `theChipRowFitsTheWidthItIsGivenAtAX5` for what is left that a test can actually decide, and what is
/// verified by looking instead.
/// SCREENS 04 §2's phenology row — the tags this species can honestly be asked about (D5).
///
/// ── Why this is a flow and not an `HStack` (ERRATA E161) ──
/// **This row was broken at the default text size, not merely at AX5**, and that is the whole of the
/// report behind it: *"The photo check in labels are too narrow. Text gets all compressed in them as
/// they're currently implemented."*
///
/// The mechanism is the one `VisitShotTypeChips` below already wrote down — an `HStack` compresses
/// its children rather than overflowing its proposal, so a row wider than the space it is given does
/// not spill off the phone, it *squeezes every chip until the labels wrap*. That note even named this
/// row as the place still doing it ("which is what the phenology row below already looks like at
/// AX5"), and it was wrong about only one thing: the size. It does not wait for AX5.
///
/// A curated deciduous species — London Plane, which is the commonest street tree in San Francisco —
/// offers all six tags, and six chips want about 537 pt in the 361 pt this row has. At `.large`, on a
/// 393 pt phone, the result read `Leaf/out · Full/leaf · Flow/ering · Fruit/ing · Fall/colo/r ·
/// Bar/e`: every label broken mid-word, one of them across three lines. It stayed invisible for so
/// long because almost nothing reached this state at the time — `VisitPhenologyVocabulary` then
/// offered the row "for the curated 40 and nobody else", and no preview or fixture stood screen 04
/// over one of the 40 with a sourced habit on it. (That gate fell with #151 — the row is offered for
/// any tree with a species record now, which makes this layout the common case rather than the rare
/// one.)
///
/// `CypressChipFlow` is the component the app's other three chip rows already use (screen 05's
/// structure flags, the add screen's land row, and the framing row below), and it is the same fix for
/// the same reason: it asks every chip for its natural size, gives it exactly that, and puts what does
/// not fit on the next line. No `Spacer` — the flow already reports the width it was proposed, so the
/// row is left-aligned without one, and a `Spacer` inside a `Layout` is a subview competing with the
/// chips for the row.
///
/// ── Why this is its own type rather than a `private var` on the screen ─────────────────────────
/// The same reason `VisitShotTypeChips` is, and it is worth restating because that lesson is what
/// made this defect findable at all: a row measured through its parent cannot be measured. Hosted on
/// its own it can be, and `noPhenologyChipIsNarrowerThanItsLabel` is the test that could fail.
struct VisitPhenologyChips: View {

    let species: Species
    let tags: [PhenologyTag]
    var isOn: (PhenologyTag) -> Bool = { _ in false }
    var toggle: (PhenologyTag) -> Void = { _ in }

    var body: some View {
        CypressChipFlow(spacing: VisitMetrics.Camera.chipGap) {
            // D5, enforced by the component itself: `Chip.phenology(_:for:isOn:)` renders nothing for
            // a tag outside `species.availablePhenologyTags`, and there is no String initializer that
            // could get around it. An evergreen is never asked about fall colour.
            ForEach(tags, id: \.self) { tag in
                Chip.phenology(
                    tag,
                    for: species,
                    isOn: isOn(tag),
                    action: { toggle(tag) }
                )
            }
        }
    }
}

struct VisitShotTypeChips: View {

    struct Framing: Identifiable, Hashable {
        let id: ShotType
        let label: String
        let isSelected: Bool
        let isCaptured: Bool
    }

    let framings: [Framing]
    var select: (ShotType) -> Void = { _ in }

    var body: some View {
        CypressChipFlow(spacing: VisitMetrics.Camera.shotTypeGap) {
            ForEach(framings) { framing in
                Chip(
                    framing.label,
                    style: framing.isSelected ? .shotTypeOn : .shotTypeOff,
                    action: { select(framing.id) }
                )
                .overlay(alignment: .topTrailing) {
                    if framing.isCaptured { capturedMark }
                }
                // The chip is a control whose label no longer carries its whole meaning: "Trunk" and
                // "Trunk, photographed" are different states and a mark is not read out.
                .accessibilityLabel(
                    framing.isCaptured
                        ? "\(framing.label), photographed"
                        : "\(framing.label), not photographed yet"
                )
            }
        }
    }

    /// The tick on a framing that has been photographed. Decoration — the chip's accessibility label
    /// carries the same fact, where it can actually be heard.
    private var capturedMark: some View {
        ZStack {
            Circle().fill(CypressColor.selectionFill)
            CypressCheckmark()
                .stroke(
                    CypressColor.onSelectionFill,
                    style: StrokeStyle(
                        lineWidth: VisitMetrics.Camera.capturedMarkStroke,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(
                    width: VisitMetrics.Camera.capturedMarkGlyph,
                    height: VisitMetrics.Camera.capturedMarkGlyph
                )
        }
        .frame(width: VisitMetrics.Camera.capturedMark, height: VisitMetrics.Camera.capturedMark)
        .offset(x: VisitMetrics.Camera.capturedMarkInset, y: -VisitMetrics.Camera.capturedMarkInset)
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

/// One of the four 32×32 L-brackets, `border-radius: 8px` on its outer corner only.
struct VisitFramingCorner: Shape {

    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    let corner: Corner

    func path(in rect: CGRect) -> Path {
        let radius = CypressRadius.framingCorner
        var path = Path()

        switch corner {
        case .topLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .topTrailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomTrailing:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

/// The camera's ✕. **NOT SPECIFIED** as a glyph in SCREENS.md; the prototype draws a ✕ top-left.
struct VisitCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// 68×68 white circle with a 6pt `rgba(255,255,255,.35)` ring.
struct VisitShutterButton: View {
    let isLibrary: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(VisitColor.shutterFill)
            if isLibrary {
                // A library shutter has to read as "pick a photo", not "take one".
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: VisitMetrics.Camera.closeGlyph, weight: .semibold))
                    .foregroundStyle(CypressColor.ctaCameraLabel)
            }
        }
        .frame(width: VisitMetrics.Camera.shutterDiameter, height: VisitMetrics.Camera.shutterDiameter)
        .overlay {
            Circle()
                .strokeBorder(VisitColor.shutterRing, lineWidth: VisitMetrics.Camera.shutterRingWidth)
                .frame(
                    width: VisitMetrics.Camera.shutterDiameter + VisitMetrics.Camera.shutterRingWidth * 2,
                    height: VisitMetrics.Camera.shutterDiameter + VisitMetrics.Camera.shutterRingWidth * 2
                )
        }
    }
}
