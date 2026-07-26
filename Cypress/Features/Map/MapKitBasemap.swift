//
//  MapKitBasemap.swift
//  Cypress — Features/Map
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  THE SEAM, CLOSED
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  `MapCanvas` (C18) was built with the basemap as a replaceable parameter and `StylizedBasemap`
//  — the mock's abstract SF grid — as the placeholder. This is the real one: MapKit
//  (ARCHITECTURE §1).
//
//  **What is left in this file is the seam and the numbers.** It was the whole basemap — a SwiftUI
//  `Map` with an `Annotation` per marker — until a screenful of pins sitting perfectly still was
//  measured at under 2 fps on a phone-shaped device. The drawing moved to `MapAnnotationLayer`, an
//  `MKMapView` behind a `UIViewRepresentable` with recycled marker views, and that file carries the
//  measurements and the reasoning. This type stays because it is the name `MapCanvas`'s `basemap:`
//  parameter is given and the shape screen 01 asks a basemap for; swapping what draws should not
//  ripple into the screen that composes it, which is what the seam was for.
//
//  `MapLayout`, below, has not moved: the opening camera, the wash opacities, the card and FAB
//  geometry and the cluster-tap zoom are screen 01's numbers rather than any one renderer's.
//

import MapKit
import SwiftUI

struct MapKitBasemap: View {

    @Binding var position: MapCameraPosition
    /// The live region, echoed back out so a cluster tap knows what "two zoom levels in" means.
    @Binding var region: MKCoordinateRegion
    let clusters: [TreeCluster]
    let pins: [TreePin]
    let userCoordinate: Coordinate?
    let selectedPinID: UUID?

    var onCameraChange: (BoundingBox, Int) -> Void
    var onSelectPin: (TreePin) -> Void
    var onSelectCluster: (TreeCluster) -> Void

    var body: some View {
        // Every pass through here used to rebuild the whole annotation layer. It no longer does —
        // it constructs one `UIViewRepresentable` value, and `MapAnnotationLayer` diffs. The count
        // is still worth having on screen, because it is the difference between "the map is being
        // asked to update" and "the map is doing work", and telling those two apart from the
        // outside is what the readout is for. Off unless `CYPRESS_MAP_PROBE=1`; see `MapFrameProbe`.
        #if DEBUG
        let _ = MapFrameProbe.shared.noteBody()
        #endif
        MapAnnotationLayer(
            position: $position,
            region: $region,
            clusters: clusters,
            pins: pins,
            userCoordinate: userCoordinate,
            selectedPinID: selectedPinID,
            onCameraChange: onCameraChange,
            onSelectPin: onSelectPin,
            onSelectCluster: onSelectCluster
        )
    }
}

// MARK: - Layout constants

/// The numbers SCREENS.md 01 gives as absolute positions in its 874pt frame, plus the few this
/// screen needs that no component owns. Colours, fonts, radii and shadows are **never** here —
/// those are `CypressColor` / `CypressFont` / `CypressRadius` / `CypressShadow` (ARCHITECTURE §6).
enum MapLayout {

    /// `top:68px` for the search bar in a frame with no safe-area padding. On a device the bar
    /// hangs off the top safe area instead, which is the same 8pt gap below the status bar.
    static let searchTopInset: CGFloat = 8
    /// `top:126px` − the search bar's own height ≈ the gap between bar and chips.
    static let chipRowTop: CGFloat = 12
    /// `gap:8px` between the three filter chips.
    static let chipGap: CGFloat = CypressSpacing.gapRows
    /// `right:16px` / `left:16px` on the search bar and the FAB.
    static let sideInset: CGFloat = CypressSpacing.gutter
    /// `left:14px; right:14px` on the bottom tree card.
    static let cardInset: CGFloat = CypressSpacing.gutterBottomCard

    /// FAB `bottom:216px`, card `bottom:104px`, card ≈ 86pt tall: 216 − 104 − 86 = 26.
    static let fabToCardGap: CGFloat = 26
    /// Card `bottom:104px` above the tab bar. C16 measures ~80pt with its own 30pt bottom padding,
    /// which is what covers the home indicator; the remainder is the gap the mock draws.
    static let tabBarHeight: CGFloat = 82
    static let cardToTabBarGap: CGFloat = 22

    /// C19's FAB: `padding:15px 20px`, `HStack(spacing:9)`.
    static let fabPaddingV: CGFloat = 15
    static let fabPaddingH: CGFloat = 20
    static let fabSpacing: CGFloat = 9

    /// The 01 tree card: `padding:13px 15px`, `gap:13px`, chevron `8×14`.
    static let cardPaddingV: CGFloat = 13
    static let cardPaddingH: CGFloat = 15
    static let cardSpacing: CGFloat = 13
    static let cardTitleBadgeGap: CGFloat = 8
    static let cardMetaTop: CGFloat = 2
    static let chevronWidth: CGFloat = 8
    static let chevronHeight: CGFloat = 14
    static let chevronStroke: CGFloat = 2

    /// A tapped pin grows a little so the card and the pin read as one selection. **NOT SPECIFIED**
    /// in SCREENS.md — 01 draws no selected pin — so it is deliberately the smallest change that
    /// still answers the tap, and it moves nothing else.
    static let selectedPinScale: CGFloat = 1.25

    /// How far the parchment wash pushes MapKit's palette toward the mock's paper. Tuned against
    /// screenshots of the real basemap, not against the hex — see `parchmentWash`. The test is a
    /// street name: `POPLAR ST` has to stay readable at the opening camera.
    static let washOpacityLight: Double = 0.18
    /// Dark needs more, because MapKit dark is a cool navy that the light basemap's warmth is not
    /// fighting. 0.35 is the most it takes before the street names dim with the ground.
    static let washOpacityDark: Double = 0.35

    /// The wash polygon. A rectangle over the western United States: far outside anything this
    /// SF-only app can be panned to at a useful zoom, and nowhere near the antimeridian, where a
    /// four-corner polygon would have to guess which way round the globe it goes.
    static let washRing: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 20, longitude: -140),
        CLLocationCoordinate2D(latitude: 55, longitude: -140),
        CLLocationCoordinate2D(latitude: 55, longitude: -100),
        CLLocationCoordinate2D(latitude: 20, longitude: -100),
    ]

    // MARK: Camera

    /// Where the map opens when there is no fix: Mission Dolores Park, near enough the centre of
    /// the inventory that the first screen is full of trees wherever the user actually is.
    /// (An earlier comment here claimed the Sunset, the corner of the city SCREENS.md 01 draws.
    /// The coordinate has always been Dolores Park; the prose was wrong, not the number.)
    static let defaultCentre = Coordinate(latitude: 37.7596, longitude: -122.4269)

    /// Where the map opens, in metres across the short edge of the phone.
    ///
    /// SCREENS.md gives no opening zoom, and the number is the whole difference between a map and a
    /// stain. A1 (BUILD-PLAN §11) starts drawing individual pins at zoom 16; on this phone zoom 16
    /// is 742 m wide, and 742 m of San Francisco is a median of 1,807 street trees — 4,556 at this
    /// very coordinate. 98.6 % of trees in the seed are closer to their nearest neighbour than one
    /// 18 pt pin diameter at that scale, so the pin layer's own first zoom is the worst it ever
    /// looks. E12 has the full table.
    ///
    /// A1 is settled and is not being re-litigated here, and nothing is being invented to thin the
    /// pins out. The one honest lever left is where the camera starts, so it starts at the scale
    /// where the pins stop lying about how many trees there are: **120 m across**, at which one
    /// point is 0.305 m and an 18 pt pin covers 5.5 m — exactly the median spacing between two
    /// San Francisco street trees. Below that the pins fuse; above it they separate.
    ///
    /// That is roughly one intersection and the four block faces around it. For an app whose
    /// premise is the tree in front of you, one intersection is the right first view; the city is a
    /// pinch away and arrives clustered, which is what clusters are for.
    ///
    /// One consequence worth knowing before it is reported as a bug: the seed is the *street* tree
    /// list, so standing in the middle of a large park opens on a screen with no pins on it. At
    /// Mission Dolores Park — 390 m across, and the fallback centre above — the nearest inventoried
    /// tree is on 18th or 20th St, outside a 120 × 261 m view. That is the honest answer to "what is
    /// near me", not a failure to load; the trees appear as soon as the camera reaches a street.
    static let defaultSpanMetres: CLLocationDistance = 120

    static func region(around centre: Coordinate, metres: CLLocationDistance = defaultSpanMetres) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: centre.clLocationCoordinate,
            latitudinalMeters: metres,
            longitudinalMeters: metres
        )
    }

    /// Tapping a cluster means "show me what is in there", so the camera goes two zoom levels in —
    /// which from any clustering zoom is a real step toward the pin threshold at 16.
    static func zoomedIn(on cluster: TreeCluster, from region: MKCoordinateRegion) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: cluster.coordinate.clLocationCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: region.span.latitudeDelta / 4,
                longitudeDelta: region.span.longitudeDelta / 4
            )
        )
    }
}
