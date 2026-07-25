//
//  VisitPinAdjustView.swift
//  Cypress — Features/Visit
//
//  **NOT SPECIFIED.** The argument for what this screen is, and which parts of it are mine, is in
//  `VisitPinAdjustPresentation.swift`; this file only draws it.
//
//  Not a raw hex, a raw font size or a raw radius in the file (ARCHITECTURE §6).
//

import MapKit
import SwiftUI

/// Where the tree is, as opposed to where the phone is.
///
/// Reached from the community add (`VisitAddTreeView`) once there is a fix to move away from. It
/// writes nothing: it takes a coordinate, lets the reader move it, and hands one back.
struct VisitPinAdjustView: View {

    /// The fix, **frozen at the moment this screen opened**, and the point every distance on it is
    /// measured from.
    ///
    /// Frozen rather than live, and that is a decision. `VisitLocationProvider` updates on every
    /// metre, so a live anchor would mean the circle moving under a reader who is aiming — a spot
    /// that was 74 m away when they looked at it becomes 78 m and refused because they shifted their
    /// weight. The reader opened this screen to say "the tree is over *there*, from *here*", and here
    /// is where they were when they said it. It is also exactly the coordinate the add would have
    /// used without this screen, which is what makes the whole gesture legible: what the map lets you
    /// do is move the pin away from that specific default.
    let anchor: Coordinate

    /// The fix's reported accuracy, for the same `GPS ±8 m` chip screens 02 and the add screen draw.
    /// It is the reason this screen exists, so it is on it.
    let accuracyM: Double?

    /// Where the pin starts. The anchor on the first visit; wherever it was left on the second, so
    /// re-opening the screen is a correction rather than a restart.
    let start: Coordinate

    /// The confirmed coordinate. The caller decides what to do with it — this screen has no idea
    /// whether a tree is about to be written or an existing one corrected.
    let onConfirm: (Coordinate) -> Void

    /// Left without confirming. Nothing moves.
    let onCancel: () -> Void

    @State private var pin: Coordinate
    @State private var position: MapCameraPosition?
    @State private var region = MKCoordinateRegion()
    /// The last nudge was refused, and the qualifier under the placement says so until the pin moves
    /// again.
    ///
    /// **On screen and not only spoken.** The announcement a refused nudge posts is heard once and by
    /// one kind of reader; a sighted reader pressing `N` at the boundary would otherwise watch a
    /// control do nothing at all, which is the exact bug report a silent bound generates.
    @State private var refusedNudge = false

    init(
        anchor: Coordinate,
        accuracyM: Double?,
        start: Coordinate? = nil,
        onConfirm: @escaping (Coordinate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.anchor = anchor
        self.accuracyM = accuracyM
        self.start = start ?? anchor
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _pin = State(initialValue: start ?? anchor)
    }

    var body: some View {
        let presentation = VisitPinAdjustPresentation(anchor: anchor, pin: pin)

        VStack(spacing: 0) {
            ScreenHeader(title: VisitPinAdjustCopy.title, bottomInset: .wide, onBack: onCancel)
            statement(presentation)
            map(presentation)
            footer(presentation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
    }

    // MARK: - The two sentences, and the chip that explains why they are needed

    /// `PinSetMapView`'s statement block: the claim, then the qualifier that keeps the claim honest.
    ///
    /// Above the map rather than over it, so a VoiceOver user meets the whole state of the screen —
    /// where the pin is, and what the limit is — before they reach a single control, and so no part
    /// of the answer is hidden behind the thing it describes.
    private func statement(_ presentation: VisitPinAdjustPresentation) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            if let accuracyM {
                // The same chip screen 02 and the add screen draw, in the same words, because this is
                // one flow and the number is the reason the reader is here.
                Chip("GPS ±\(Int(accuracyM.rounded())) m", style: .meta, leadingDot: CypressColor.gpsDot)
                    .padding(.bottom, CypressSpacing.gapVitality)
            }

            Text(presentation.placement)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(refusedNudge ? VisitPinAdjustCopy.nudgeRefused : presentation.rule)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.bottom, CypressSpacing.labelSectionTop)
    }

    // MARK: - The map

    /// Screen 01's basemap with nothing on it but the reader's fix, and the pin drawn over the middle.
    ///
    /// ── The pin is the centre of the map, and the map moves under it ──────────────────────────
    /// The alternative — a draggable annotation — was rejected for three reasons, in order of how
    /// much they matter. **The pin under your thumb is the pin you cannot see**, and the thing being
    /// aimed at is a tree the reader is looking at in the street, so hiding the target under a finger
    /// for the whole gesture is the one thing this screen cannot afford. **Every point on the screen
    /// becomes a handle**, instead of an 18 pt dot in a 44 pt hit area, which is the tap-target
    /// problem SCREENS.md §5 gap 12 raises about pins turned into the aiming problem. And MapKit's own
    /// pan recogniser is the only thing that moves a map smoothly; a `DragGesture` layered on an
    /// annotation has to fight it for the touch.
    ///
    /// **No pins and no clusters.** The trees already on record nearby would genuinely help — they
    /// are what the 10 m dedupe is about to refuse against — but a pin on this screen would be a
    /// labelled button with nowhere to go: opening a tree profile from inside a placement would
    /// abandon a photograph, and a button that does nothing is worse than no button (ERRATA E125's
    /// lesson, from the other direction). Left out on purpose; see the round's report for the shape
    /// of adding it.
    ///
    /// The camera is never fetched from and never debounced — this screen has no records to read —
    /// so the `onCameraChange` closure does one thing: it tells the pin where the middle of the map
    /// now is.
    private func map(_ presentation: VisitPinAdjustPresentation) -> some View {
        MapKitBasemap(
            position: Binding(
                get: { position ?? .region(MapLayout.region(around: start, metres: VisitMetrics.PinAdjust.openingSpanM)) },
                set: { position = $0 }
            ),
            region: $region,
            clusters: [],
            pins: [],
            // The fix itself, still drawn — the pin is only meaningful as a displacement from it.
            userCoordinate: anchor,
            selectedPinID: nil,
            onCameraChange: { box, _ in
                let centre = VisitPinAdjust.centre(of: box)
                // A pan clears the refusal, because the pin is moving again. Compared rather than
                // cleared unconditionally: this closure also fires for the camera move a *refused*
                // nudge does not make, and for every settling frame of one that is accepted.
                if centre.distance(to: pin) > VisitMetrics.PinAdjust.stillnessM { refusedNudge = false }
                pin = centre
            },
            onSelectPin: { _ in },
            onSelectCluster: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { reticle(presentation) }
    }

    /// The pin, drawn as the thing it is about to become.
    ///
    /// `MapPin(.community)` and not a new marker: C19's community pin is "the community layer, which
    /// never reads as part of the official inventory", and what this screen is placing is exactly a
    /// `source = community, verification_state = unverified` record. Drawing it as anything else would
    /// promise a status the add cannot deliver.
    ///
    /// Past the limit it fades rather than changing colour. Signal Amber is reserved for "this tree
    /// needs something" (§1.1) and a pin that is merely too far away is not a tree in trouble; the
    /// two sentences above and the disabled CTA below are already saying it in words, and §5.6's
    /// restraint says not to say it a third way in a new colour.
    private func reticle(_ presentation: VisitPinAdjustPresentation) -> some View {
        MapPin(.community)
            .opacity(presentation.isWithinBound ? 1 : VisitMetrics.PinAdjust.beyondLimitOpacity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VisitPinAdjustCopy.pinLabel)
            .accessibilityValue(presentation.placement)
            .allowsHitTesting(false)
    }

    // MARK: - Footer

    /// The nudge pad, the confirm, and the way back to the fix.
    private func footer(_ presentation: VisitPinAdjustPresentation) -> some View {
        VStack(spacing: CypressSpacing.gapRows) {
            nudgePad
            PrimaryButton(
                VisitPinAdjustCopy.confirm,
                isEnabled: presentation.isWithinBound
            ) {
                onConfirm(pin)
            }
            Button { recentre() } label: {
                Text(VisitPinAdjustCopy.recentre)
                    .font(CypressFont.body13Bold)
                    .foregroundStyle(CypressColor.ctaFill)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cypressHitArea()
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, VisitMetrics.Identify.footerTop)
        .padding(.bottom, CypressSpacing.bottomCTA)
    }

    /// Four controls that move the pin without a gesture.
    ///
    /// **This is the accessibility answer, and it is a real control rather than a concession.** A map
    /// with a draggable pin is the hardest thing in this app for VoiceOver: a pan is a gesture the
    /// screen reader owns, and there is no amount of labelling that turns "drag the world 30 m
    /// north-east" into something a swipe-and-double-tap can perform. So the pin has a second way to
    /// move that needs no gesture at all, the screen says where the pin is above the map in reading
    /// order, and every press announces the result — including the presses that are refused, because
    /// a control that stops working silently is the failure this bound would otherwise produce.
    ///
    /// Four `SecondaryOutlineButton`s rather than a drawn D-pad: C7 is the catalogue's control for
    /// "another thing you may do here", it is already well over 44 pt at its compact size, and an
    /// invented four-way pad would be a new component in a closed catalogue. The drawn label is the
    /// compass letter — `VisitBearing`'s own vocabulary, and all that fits four across — and the
    /// spoken label is the whole sentence.
    private var nudgePad: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            Text(VisitPinAdjustCopy.nudgeLabel).cypressMonoSectionLabel()
            HStack(spacing: CypressSpacing.gapRows) {
                ForEach(VisitPinAdjust.Direction.allCases, id: \.self) { direction in
                    SecondaryOutlineButton(
                        VisitPinAdjustCopy.nudgeGlyph(direction),
                        style: .compact
                    ) {
                        nudge(direction)
                    }
                    .accessibilityLabel(VisitPinAdjustCopy.nudge(direction))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Moving the pin

    private func nudge(_ direction: VisitPinAdjust.Direction) {
        guard let moved = VisitPinAdjust.nudge(pin, towards: direction, from: anchor) else {
            refusedNudge = true
            speak(VisitPinAdjustCopy.nudgeRefused)
            return
        }
        move(to: moved)
        speak(VisitPinAdjustPresentation(anchor: anchor, pin: moved).placement)
    }

    private func recentre() {
        move(to: anchor)
        speak(VisitPinAdjustCopy.atFix)
    }

    /// Moves both the pin and the camera under it, so the two cannot come apart.
    ///
    /// The span is whatever the reader last zoomed to, and `MapKitBasemap` only echoes the region back
    /// when the camera settles — so before the first settle there is no span to keep, and the opening
    /// one is used instead. A zero span here would collapse the map to a point.
    private func move(to coordinate: Coordinate) {
        let span = region.span.latitudeDelta > 0
            ? region.span
            : MapLayout.region(around: coordinate, metres: VisitMetrics.PinAdjust.openingSpanM).span
        refusedNudge = false
        pin = coordinate
        position = .region(MKCoordinateRegion(center: coordinate.clLocationCoordinate, span: span))
    }

    /// Says the result out loud.
    ///
    /// The sentence above the map has already changed by the time this fires, but a VoiceOver user's
    /// focus is on the button they just pressed and nothing moves it back up the screen. An
    /// announcement is the one mechanism that reports a consequence without stealing focus, which is
    /// exactly what a nudge control needs: press, hear where the pin now is, press again.
    private func speak(_ sentence: String) {
        AccessibilityNotification.Announcement(sentence).post()
    }
}
