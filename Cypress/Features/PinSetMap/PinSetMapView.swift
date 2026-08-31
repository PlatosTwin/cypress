//
//  PinSetMapView.swift
//  Cypress — Features/PinSetMap
//
//  **NOT SPECIFIED.** ERRATA E129. The argument for what this screen is, and which parts of it are
//  mine, is in `PinSetPresentation.swift`; this file only draws it.
//
//  Not a raw hex, a raw font size or a raw radius in the file (ARCHITECTURE §6).
//

import MapKit
import SwiftUI

/// Screen 12's two counted rows, answered (ERRATA E129).
///
/// One screen for both, which is the point. `Where eyes are needed` and `Where a tree could go` are
/// the same shape of statement — a number of records in this neighborhood — and each of them used to
/// open a single record. Two screens would be two chances to answer the question differently.
struct PinSetMapView: View {

    let set: PinSet

    /// The reader's fix, from the composition root's shared provider (ARCHITECTURE §3). Drawn as the
    /// GPS dot, which is what makes the map an answer to "where are they" rather than a picture of
    /// somewhere: `All nine are within a 15-minute walk` is a claim about the distance from here to
    /// there, and here has to be on the map for there to mean anything.
    let userCoordinate: Coordinate?

    var onBack: (() -> Void)?

    /// What a tap on a pin opens. Resolved by the composition root, which routes it through
    /// `MapHomeView.route(for:)` — a vacant site opens the site screen, a memorial opens 19, a tree
    /// opens 03/14. This folder builds no other feature's view and invents no third answer to a
    /// question screen 01 has already answered (ARCHITECTURE §3).
    var onOpenPin: ((TreePin) -> Void)?

    /// The rest of the block, for a map about one record. `.none` for the two counted groups, which
    /// carry everything they draw — see `PinSetNeighbors` for why this read exists and why it
    /// cannot contradict the sentence above the map.
    var neighbors: PinSetNeighbors = .none

    @Environment(\.locale) private var locale

    @State private var position: MapCameraRequest?
    @State private var region = MKCoordinateRegion()
    @State private var selectedPinID: UUID?
    /// What `neighbors` returned, or empty. Never counted, never part of `set`.
    @State private var context: [TreePin] = []

    var body: some View {
        let presentation = PinSetPresentation(set: set, context: context, locale: locale)

        VStack(spacing: 0) {
            header(presentation)
            statement(presentation)
            map(presentation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // One read, once, and only when there is a record for the block to be around. `.task` and
        // not `.onAppear`: coming back from a pin's own profile must not re-read a block that has
        // not moved, and the map is already correct without it.
        .task {
            guard context.isEmpty, let focus = set.pins.first, set.focusPinID != nil else { return }
            context = await neighbors.read(focus.coordinate)
        }
    }

    // MARK: - Header (C1)

    @ViewBuilder
    private func header(_ presentation: PinSetPresentation) -> some View {
        if let name = presentation.neighborhoodName {
            ScreenHeader(title: presentation.title, trailingPill: name, onBack: onBack)
        } else {
            ScreenHeader(title: presentation.title, onBack: onBack)
        }
    }

    // MARK: - The two sentences

    /// The row's claim, then how much of it is drawn below.
    ///
    /// The second line is `text.muted` rather than faint: it is not a caption, it is the qualifier
    /// that makes the first line honest when the map is holding a page (ERRATA E38), and a qualifier
    /// nobody reads is a qualifier that is not there.
    private func statement(_ presentation: PinSetPresentation) -> some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
            // Absent rather than empty when the claim is already the title — see
            // `PinSetCopy.subject`. An empty `Text` would still take the stack's spacing and leave a
            // gap nobody put there.
            if !presentation.subject.isEmpty {
                Text(presentation.subject)
                    .font(CypressFont.body145Bold)
                    .foregroundStyle(CypressColor.textInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(presentation.coverage)
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

    /// Screen 01's basemap, given a list instead of a viewport.
    ///
    /// **This is the seam, and it is where the pin budget is not spent.** `MapModel` reads the
    /// database per viewport in bands under an explicit cap, because 01 is a window onto 195,309
    /// trees and a pan is a stream of reads. This screen has its records already — they came from the
    /// almanac's own read, on the payload — so it never calls `mapContent(in:)`, never debounces a
    /// camera, and cannot cost a query however far it is panned. `clusters` is empty for the same
    /// reason: a group of at most 200 pins has nothing to aggregate, and A1's clustering threshold is
    /// about the density of a city rather than of a list.
    ///
    /// Carrying the pins in also means the map draws exactly the records the sentence above it counts.
    /// A viewport read here would have drawn every tree in the box — the nine among them, and no way
    /// to tell which.
    private func map(_ presentation: PinSetPresentation) -> some View {
        MapKitBasemap(
            position: Binding(
                // `.opening`, not `.move(to:)` — this getter runs on every pass. See
                // `MapCameraRequest`.
                get: { position ?? .opening(Self.region(presentation.frame)) },
                set: { position = $0 }
            ),
            region: $region,
            clusters: [],
            pins: presentation.pins,
            userCoordinate: userCoordinate,
            // **The record the reader asked about is selected before they touch anything.** That is
            // the whole of E144's "which of these thirty is it": `MapAnnotationLayer.applySelection`
            // draws a selected pin 1.25× its neighbors, and this screen has one candidate rather
            // than needing a tap to produce one. No new highlight was invented — a second way to
            // say "this one" is a second thing to keep in step with C19.
            //
            // A `??` rather than seeding the `@State`, so there is no pass where the map is drawn
            // unselected and no `onAppear` to race the first frame. A tap replaces it, which is
            // correct: the reader has asked about a different pin.
            selectedPinID: selectedPinID ?? presentation.focusPinID,
            // Nothing to fetch, so nothing to do. The closure exists because 01 needs one.
            onCameraChange: { _, _ in },
            onSelectPin: { pin in
                // The selection is set before the push so the pin the reader hit grows under their
                // finger — the same 1.25× 01 uses — rather than the tap having no visible target.
                selectedPinID = pin.id
                onOpenPin?(pin)
            },
            // There are no clusters to select. An empty closure rather than a fatal error: a
            // programming mistake here would be a tap that does nothing, and a crash is worse.
            onSelectCluster: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) { recenter(presentation) }
        // No `accessibilityLabel` on the map itself. Every pin under it already speaks — a city tree
        // says C19's words and a basin says `SiteCopy`'s (ERRATA E107, RULINGS R7) — and labeling the
        // container is how a container stops being a container and starts being one element with the
        // pins hidden inside it. What the map holds is said by the two lines above it, in reading
        // order, before anything on the map is reached.
    }

    // MARK: - Back to the one it is about

    /// **NOT SPECIFIED** (ERRATA E144). Drawn only for a map about one record.
    ///
    /// A screen whose entire promise is "here is where this one is" must survive a pan. Without this
    /// control, the reader who drags the map two blocks to read a street name has lost the thing
    /// they came for and has to go back and press the control again — the same dead end
    /// `MapRecenter` exists to close on screen 01, one screen over. The two counted groups do not
    /// get it: there is no single subject to go back to, and a control that centered on "the nine"
    /// would be answering a question nobody asked.
    ///
    /// It is `MapLocateGlyph`, the crosshair screen 01's recenter control already uses, because it
    /// already means *center on the thing*. Its own `MapRecenterButton` is not reused: that button's
    /// three states are about the reader's GPS fix — granted, refused, waiting — and this one has no
    /// states at all. There is always a record and it is always somewhere.
    @ViewBuilder
    private func recenter(_ presentation: PinSetPresentation) -> some View {
        if presentation.focusPinID != nil, let pin = set.pins.first {
            Button {
                // **A ticket, exactly as the recenter press mints one** (ERRATA E140). A press is an
                // explicit user action on the main thread, which is the only thing
                // `MapCameraRequest.move(to:)`'s counter is safe under, and it is a new request even
                // when it names the camera the screen opened on — which is the point: pressing this
                // after a pan that ended up back where it started must still move the map.
                //
                // Nothing else on this screen ever writes the camera. There is no state change
                // anywhere in this file that drives it, which is the property E140 paid for.
                position = .move(
                    to: MapLayout.region(around: pin.coordinate, meters: MapLayout.defaultSpanMeters)
                )
                // Back to the subject, in case a tap on a neighbor took the selection away.
                selectedPinID = nil
                AccessibilityNotification.Announcement(PinSetCopy.spokenRecentered).post()
            } label: {
                ZStack {
                    Circle().fill(CypressColor.surfaceCard)
                    MapLocateGlyph(tint: CypressColor.ctaFill)
                }
                .frame(width: CypressSpacing.minTapTarget, height: CypressSpacing.minTapTarget)
                .overlay {
                    Circle().strokeBorder(
                        CypressColor.borderPinRing,
                        lineWidth: CypressSpacing.Component.hairline
                    )
                }
                .cypressShadow(light: CypressShadow.fab, dark: CypressShadow.Dark.fab)
            }
            .buttonStyle(.plain)
            .padding(CypressSpacing.gutter)
            .accessibilityLabel(PinSetCopy.recenterLabel(presentation.title))
            .accessibilityHint(PinSetCopy.recenterHint)
        }
    }

    /// The `BoundingBox` the presentation computed, as MapKit's own camera type.
    ///
    /// **The arithmetic moved to `MKCoordinateRegion.init(_:)` in `MapGeography`, and the comment
    /// that used to be here is why it moved.** It said the conversion belonged to this screen
    /// because this screen was its only caller — true when it was written, and no longer: screen 01
    /// fits a camera to a box now as well. This wrapper is kept so the two call sites below read as
    /// they did.
    private static func region(_ box: BoundingBox) -> MKCoordinateRegion {
        MKCoordinateRegion(box)
    }
}
