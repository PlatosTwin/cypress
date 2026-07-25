//
//  MapKitBasemap.swift
//  Cypress — Features/Map
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  THE SEAM, CLOSED
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  `MapCanvas` (C18) was built with the basemap as a replaceable parameter and `StylizedBasemap`
//  — the mock's abstract SF grid — as the placeholder. This is the real one: MapKit
//  (ARCHITECTURE §1), through the iOS 17 SwiftUI `Map`.
//
//  Two things about the composition are deliberate.
//
//  **The pins moved into the basemap layer.** C18's header imagined pins staying in the screen-space
//  overlay with "real screen positions" computed for them. They are `Annotation`s instead, because
//  MapKit's own annotation layer is the only thing that tracks a pin to its coordinate through an
//  inertial pan without a frame of lag. Nothing about the pins *themselves* changed: they are the
//  same `MapPin` (C19) views, in the same tokens. `MapCanvas`'s overlay still carries the search
//  bar, the chips, the FAB and the card, which is the half of it that was always ours.
//
//  **The parchment wash is a map overlay, not a view overlay.** The mock's ground is `#E9E5D4`
//  paper. A SwiftUI `.overlay` would tint the pins too and break the status colours; a world-scale
//  `MapPolygon` sits above the basemap but below every annotation, which is the layer the wash
//  wants. It is a *tint*, though, not a repaint: it opened at 0.42 and took the street names, the
//  road markings and the building edges with it, so it is now 0.18 in light and 0.35 in dark and
//  the map underneath is recognisably MapKit. See `parchmentWash` for what was measured.
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

    @Environment(\.colorScheme) private var colorScheme

    /// The one pin the card is open on, if it is still in the fetched set.
    ///
    /// It can stop being: the level-of-detail grid picks one tree per cell and the winner changes
    /// with the zoom, so zooming out with a card open can thin the selected pin away. When that
    /// happens the card stays — it is showing a tree that is still there — and the map simply has no
    /// enlarged pin to draw, which is the same thing that happens when the camera leaves it behind.
    private var selectedPin: TreePin? {
        guard let selectedPinID else { return nil }
        return pins.first { $0.id == selectedPinID }
    }

    /// Everything else. Returns `pins` itself — same array, same identity, no copy — whenever nothing
    /// is selected, which is every frame of a pan and a pinch.
    private var unselectedPins: [TreePin] {
        guard let selectedPinID else { return pins }
        return pins.filter { $0.id != selectedPinID }
    }

    var body: some View {
        GeometryReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                parchmentWash

                ForEach(clusters) { cluster in
                    Annotation("", coordinate: cluster.coordinate.clLocationCoordinate, anchor: .center) {
                        // A cluster badge is a count of *trees*, not of anything a person did —
                        // D1's ban is on counting user actions (ARCHITECTURE §5.1).
                        MapPin(.cluster(count: cluster.count, large: cluster.count >= 10)) {
                            onSelectCluster(cluster)
                        }
                    }
                    .annotationTitles(.hidden)
                }

                // **The unselected pins, and nothing about the selection.** The scale and its
                // animation used to live in here, on every pin, keyed on `selectedPinID` — so one tap
                // opened an animation transaction on the whole layer and every pin in it re-evaluated
                // to arrive at scale 1 (ERRATA E130). The selected pin is one annotation and is
                // hoisted out below; this branch is now invariant under selection, which is what lets
                // MapKit leave it alone while the card opens.
                //
                // `unselectedPins` is the same array by identity when nothing is selected, which is
                // the whole of a pan and a pinch.
                ForEach(unselectedPins) { pin in
                    Annotation("", coordinate: pin.coordinate.clLocationCoordinate, anchor: .center) {
                        MapPin(MapPinKind.kind(for: pin)) { onSelectPin(pin) }
                            // C19 has no pin for a vacant site, so one is drawn as `removed` — a
                            // grey dot with a bar struck through it, whose own label reads "Removed
                            // tree, memorial". That is a sentence about a tree that was, said of
                            // 12,518 basins that never held one. Inventing a drawn pin is a design
                            // decision and was not taken (ERRATA E107); the label is the half of the
                            // distinction that could be made honestly, and it wins by being applied
                            // outside the component's own.
                            .accessibilityLabel(MapPinKind.accessibilityLabel(for: pin))
                    }
                    .annotationTitles(.hidden)
                }

                if let selected = selectedPin {
                    Annotation("", coordinate: selected.coordinate.clLocationCoordinate, anchor: .center) {
                        MapPin(MapPinKind.kind(for: selected)) { onSelectPin(selected) }
                            .accessibilityLabel(MapPinKind.accessibilityLabel(for: selected))
                            .scaleEffect(MapLayout.selectedPinScale)
                            .cypressAnimation(CypressMotion.selection, value: selected.id)
                    }
                    .annotationTitles(.hidden)
                }

                if let userCoordinate {
                    Annotation("", coordinate: userCoordinate.clLocationCoordinate, anchor: .center) {
                        MapPin(.gps)
                    }
                    .annotationTitles(.hidden)
                }
            }
            // "the city reads as street geometry rather than a busy consumer map": no POI pins, no
            // traffic, no 3-D. What is left is the street network and the water, which is what the
            // mock draws.
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {
                // The mock has no zoom, compass or scale control. SCREENS.md 01 lists zoom controls
                // under **NOT SPECIFIED**, so none are added.
            }
            // The region is only needed when a cluster is tapped, and a cluster cannot be tapped
            // mid-gesture — so it is read once the camera settles rather than sixty times a second.
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
            }
            .onMapCameraChange(frequency: .continuous) { context in
                onCameraChange(
                    BoundingBox(context.region),
                    MapZoom.level(
                        longitudeDelta: context.region.span.longitudeDelta,
                        viewWidth: proxy.size.width
                    )
                )
            }
        }
    }

    /// The wash. `surfaceMapPaper` in light (`#E9E5D4`), `Dark.bgMap` in dark (`#141E16`) — D1's
    /// "forest-floor greens instead of inverted gray" comes from tinting the ground green rather
    /// than from MapKit's own dark mode, which is a cool navy-gray.
    ///
    /// **The alpha is the only lever, and it is set by eye, not by fidelity to `#E9E5D4`.** Two
    /// things were measured on device and both matter:
    ///
    /// - `.mapOverlayLevel` makes no difference to a SwiftUI `MapPolygon`. `.aboveLabels` and
    ///   `.aboveRoads` render identically (0.7 % of pixels differ between two screenshots of the
    ///   same camera, which is annotation jitter). Labels are composited above map content either
    ///   way, so moving the wash down the stack does not buy back a single street name. It is left
    ///   at `.aboveRoads` because that is what it means, not because it changes the picture.
    /// - MapKit's light basemap is *already* warm — its land is around `#F2F0EA`. The wash only has
    ///   to finish the job. At the 0.42 it opened at, `POPLAR ST` was a ghost and the yellow centre
    ///   lines had gone; at 0.18 the paper reads and every road casing, building edge and street
    ///   name survives. Dark is the opposite problem: MapKit dark is genuinely blue and needs more
    ///   push, so it gets 0.35 — past that the street names start dimming out with it.
    ///
    /// A flat over-blend toward a near-black green cannot actually *remove* MapKit dark's blue, only
    /// darken it. Getting the whole way to D1's forest floor needs a tinted basemap, not an overlay.
    ///
    /// `MapKit.` is load-bearing: the app has its own `MapContent` — the enum `mapContent(in:)`
    /// returns — and an unqualified `some MapContent` resolves to that one.
    private var parchmentWash: some MapKit.MapContent {
        let isDark = colorScheme == .dark
        return MapPolygon(coordinates: MapLayout.washRing)
            .foregroundStyle(
                (isDark ? CypressColor.Dark.bgMap : CypressColor.surfaceMapPaper)
                    .opacity(isDark ? MapLayout.washOpacityDark : MapLayout.washOpacityLight)
            )
            .mapOverlayLevel(level: .aboveRoads)
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

    // MARK: The recentre control

    /// **NOT SPECIFIED** — see `MapRecentre` for why this control exists and why it is ours. The
    /// numbers are its own; SCREENS.md 01 gives none, so they are derived from what is already drawn.
    ///
    /// The gap to the FAB below it is the same 12 the search bar keeps from the chip row, which is
    /// the only vertical rhythm this screen's chrome has.
    static let locateToFabGap: CGFloat = chipRowTop
    /// The crosshair inside a 44pt circle: a 15pt ring with 4pt ticks and a 2pt gap comes to 27pt of
    /// mark, leaving an 8pt margin all round — the same air C19's 18pt pin keeps inside its own tap
    /// target.
    static let locateRing: CGFloat = 15
    static let locateDot: CGFloat = 5
    static let locateTick: CGFloat = 4
    static let locateTickGap: CGFloat = 2
    static let locateStroke: CGFloat = 2
    /// Long enough to cross the ring and both ticks it passes through, so it reads as one stroke over
    /// the whole mark rather than as a line inside it.
    static let locateSlash: CGFloat = 27

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
