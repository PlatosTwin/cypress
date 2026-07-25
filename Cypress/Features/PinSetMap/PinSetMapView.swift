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
/// the same shape of statement — a number of records in this neighbourhood — and each of them used to
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

    @Environment(\.locale) private var locale

    @State private var position: MapCameraPosition?
    @State private var region = MKCoordinateRegion()
    @State private var selectedPinID: UUID?

    var body: some View {
        let presentation = PinSetPresentation(set: set, locale: locale)

        VStack(spacing: 0) {
            header(presentation)
            statement(presentation)
            map(presentation)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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
            Text(presentation.subject)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

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
                get: { position ?? .region(Self.region(presentation.frame)) },
                set: { position = $0 }
            ),
            region: $region,
            clusters: [],
            pins: presentation.pins,
            userCoordinate: userCoordinate,
            selectedPinID: selectedPinID,
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
        // No `accessibilityLabel` on the map itself. Every pin under it already speaks — a city tree
        // says C19's words and a basin says `SiteCopy`'s (ERRATA E107, RULINGS R7) — and labelling the
        // container is how a container stops being a container and starts being one element with the
        // pins hidden inside it. What the map holds is said by the two lines above it, in reading
        // order, before anything on the map is reached.
    }

    /// The `BoundingBox` the presentation computed, as MapKit's own camera type.
    ///
    /// The conversion lives here rather than in `MapGeography` because it is this screen's only
    /// caller: `MapGeography` turns a *region* into a box, which is the direction 01 needs, and adding
    /// the inverse to a file another screen owns would be a change to that screen's surface for one
    /// use.
    private static func region(_ box: BoundingBox) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (box.minLatitude + box.maxLatitude) / 2,
                longitude: (box.minLongitude + box.maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: box.maxLatitude - box.minLatitude,
                longitudeDelta: box.maxLongitude - box.minLongitude
            )
        )
    }
}
