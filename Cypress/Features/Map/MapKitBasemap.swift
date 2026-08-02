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

/// **A camera the app has asked for, and the ask it came from.**
///
/// This type is ERRATA E140. The basemap used to be handed a bare `MapCameraPosition`, and the layer
/// decided whether to drive the camera by comparing the incoming value against the last one it had
/// applied. That comparison cannot be made to work, and the reason is worth stating because it is not
/// obvious from either side of the seam.
///
/// A `UIViewRepresentable`'s `updateUIView` is called with the view value from a body pass, and that
/// pass read the app's state at the moment it ran. Screen 01 re-evaluates its basemap body **240
/// times a second at rest** (E139's unexplained residual), so when the reader pans, there is always
/// an update already in flight carrying the camera as it was *before* the pan. Whatever the settle
/// handler writes, that in-flight value arrives afterwards holding the old camera, differs from
/// whatever the layer recorded, and is taken for a fresh request. The map is driven back. Measured:
/// with the two sides written to agree, a pan still produced 39 camera writes and the map returned to
/// the reader's own location every time.
///
/// A sequence number settles it, because staleness is exactly what a sequence number can see. Every
/// genuine ask takes the next ticket; a stale view value carries a ticket the layer has already
/// applied and is ignored on sight. **No comparison of camera geometry is involved, so no amount of
/// snapshot skew can turn an old request into a new one.**
///
/// It also retires the heuristic it replaces. The layer used to notice a pan by measuring how far the
/// camera had drifted from the request, purely so that pressing the recentre control twice was not
/// swallowed as a duplicate value (#66). A press now mints a ticket whether or not it asks for the
/// same place, so the second press works by construction and the settle handler has nothing to say.
struct MapCameraRequest: Equatable {

    /// Where the app wants the camera.
    var region: MKCoordinateRegion

    /// Which ask this is. **Compared, never inspected** — see `==`.
    var sequence: Int

    /// Two requests are the same request when they are the same ask. Regions are deliberately not
    /// compared: `MKCoordinateRegion` is a pair of doubles that MapKit never lands on exactly, and
    /// comparing them is how the layer used to mistake an old value for a new one.
    static func == (lhs: MapCameraRequest, rhs: MapCameraRequest) -> Bool {
        lhs.sequence == rhs.sequence
    }

    /// Where a screen opens.
    ///
    /// Sequence zero, and it is a constant rather than a ticket on purpose: two of the three screens
    /// that use this basemap build their opening camera inside a `Binding` getter, so the value is
    /// reconstructed on every pass. A ticket there would be a new request sixty times a second. Zero
    /// is applied once, when the map view is first made, and never again.
    static func opening(_ region: MKCoordinateRegion) -> MapCameraRequest {
        MapCameraRequest(region: region, sequence: 0)
    }

    /// A camera somebody asked for: a press of the recentre control, a cluster tap, a nudge of a
    /// pin. Always a new request, even when it names the same place as the last one.
    static func move(to region: MKCoordinateRegion) -> MapCameraRequest {
        ticket += 1
        return MapCameraRequest(region: region, sequence: ticket)
    }

    /// Monotonic for the life of the process. `nonisolated(unsafe)` and honest about it: every writer
    /// is a SwiftUI view responding to a gesture, so this is only ever touched on the main thread,
    /// and the alternative — actor isolation on a counter — would put an `await` between a button
    /// press and the camera it moves.
    private nonisolated(unsafe) static var ticket = 0
}

struct MapKitBasemap: View {

    @Binding var position: MapCameraRequest
    /// The live region, echoed back out so a cluster tap knows what "two zoom levels in" means.
    @Binding var region: MKCoordinateRegion
    let clusters: [TreeCluster]
    let pins: [TreePin]
    /// Which species hold the four colour slots for these pins (task #80). Defaults to nothing,
    /// because the two other screens that draw this basemap — 16's pin adjust and the pin-set map —
    /// are about *one* tree and its neighbours rather than about the mix of species on a street, and
    /// a species colouring there would be four hues answering a question nobody is asking.
    var speciesPalette: MapSpeciesPalette = .empty
    let userCoordinate: Coordinate?
    let selectedPinID: UUID?

    var onCameraChange: (BoundingBox, Int) -> Void
    var onSelectPin: (TreePin) -> Void
    var onSelectCluster: (TreeCluster) -> Void
    /// A pan or pinch began on the glass (task #128). Nil on the two one-tree screens, which have
    /// no auto-centring to gate. See `MapAnnotationLayer.onReaderGesture`.
    var onReaderGesture: (() -> Void)?

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
            speciesPalette: speciesPalette,
            userCoordinate: userCoordinate,
            selectedPinID: selectedPinID,
            onCameraChange: onCameraChange,
            onSelectPin: onSelectPin,
            onSelectCluster: onSelectCluster,
            onReaderGesture: onReaderGesture
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

    // MARK: The z-order of the marker layer (task #150)
    //
    // `MKAnnotation` has no z-order of its own; `zPriority` is what MapKit reads, and these three
    // values are the whole ordering — declared together so no two call sites can disagree.
    //
    // **The reader's dot is topmost, above every tree pin and above the selected pin's reticle.**
    // It was `.min` — under every tree — on the reasoning that trees are what the map is for, and
    // the running screen said otherwise: on any street dense enough to matter the dot vanished
    // under the pins, and a map that cannot show you where you are has lost the fact every other
    // fact on it is relative to. The dot is small, `isEnabled == false` (it takes no taps away
    // from the pins beneath it), and there is exactly one of it — the cheapest possible thing to
    // put on top and the most expensive to lose.
    //
    // The selected pin sits *under* the dot for the same reason stated from the other side: #89's
    // reticle exists to make one pin findable among neighbours, and the reader's own position
    // outranks even that — a selection half-covered by the dot is still findable (the rings are
    // outside the dot's footprint at any overlap), where a dot behind a scaled selected pin is
    // simply gone.
    /// The reader's dot. `MKAnnotationViewZPriority.max` — nothing may be given a higher one.
    static let userDotZPriority = MKAnnotationViewZPriority.max
    /// The selected pin: above every unselected neighbour (two pins 20 pt apart overlap inside
    /// 36 pt of reticle), below the dot.
    static let selectedPinZPriority = MKAnnotationViewZPriority(
        rawValue: (MKAnnotationViewZPriority.max.rawValue + MKAnnotationViewZPriority.defaultUnselected.rawValue) / 2
    )
    /// Everything else.
    static let pinZPriority = MKAnnotationViewZPriority.defaultUnselected

    // MARK: The dot's movement (task #149)

    /// How long the dot takes to glide from one fix to the next, in seconds.
    ///
    /// CoreLocation delivers roughly one fix per second while moving, so a one-second linear glide
    /// arrives just as the next fix does and the dot reads as *walking* rather than teleporting.
    /// The glide runs as a `UIView` animation around the annotation's KVO'd coordinate write — the
    /// native layer's own mechanism, on the render server — so it costs no SwiftUI pass at all;
    /// reintroducing per-update view rebuilds is E139's ~50-sessions-a-second class and is exactly
    /// what this must never do.
    static let userDotGlideSeconds: TimeInterval = 1.0

    /// A jump longer than this snaps instead of gliding, in degrees of latitude/longitude.
    ///
    /// ~0.01° is about a kilometre: no pedestrian, cyclist or bus covers it between two fixes, so
    /// a delta past it is a teleport — a simulator's `simctl location set`, a cold fix correcting
    /// a cached one — and a dot seen sliding across the city at 1 km/s would be the animation
    /// claiming a journey that never happened.
    static let userDotSnapDegrees: Double = 0.01

    // MARK: The selection reticle (task #89)
    //
    // ── Why 1.25× was not an answer ────────────────────────────────────────────────────────────
    // A scale was "deliberately the smallest change that still answers the tap", and on the screen
    // it was drawn against — a handful of pins around one tree — it was enough. On a Mission block
    // the map draws up to 288 pins, and 1.25 of 18 pt is 22.5 pt: a pin two and a half points wider
    // than thirty identical neighbours, which is not a thing a reader can find. The card at the
    // bottom names the tree and the map does not say which dot it is talking about.
    //
    // ── What replaces it, and why it cannot be read as a species colour ────────────────────────
    // Two concentric rings **outside** the pin, in ink and in the ring colour, and the scale stays.
    // Three properties make it unconfusable with the species palette, by construction rather than by
    // taste:
    //
    //   1. **It is achromatic.** `textInk` and `pinRingStroke` are the near-black and the white of
    //      the app's two ends; every species slot is a chromatic fill at OKLCh chroma ≥ 0.08. A
    //      reader cannot mistake a black-and-white ring for one of four hues, and a colour-blind
    //      reader — for whom the four hues are the *hardest* thing on the map — finds this one
    //      easiest.
    //   2. **It is outside the pin's own footprint**, at 1.7× and 2× the 18 pt dot, where no pin of
    //      any kind ever draws fill. Species colour is always *inside* a pin.
    //   3. **It is a ring, not a fill**, and there is only ever one of them on the map.
    //
    // Two rings rather than one because the ground is a live MapKit basemap: a white ring vanishes on
    // the paper and an ink one vanishes over a park polygon after dark, so the mark carries both ends
    // of the ramp and one of them always reads. The inner ring takes the outer's colour in the other
    // appearance, which is the same crossed-over trick C19's FAB glyph already uses.
    //
    // It costs **no new bitmap**. The rings are `CALayer`s on the one selected marker view, the way
    // the amber pulse already is, so `MapPinImage`'s cache is untouched by selection entirely.
    /// Outer ring diameter, as a multiple of the pin it surrounds.
    static let selectedReticleOuterScale: CGFloat = 2.0
    /// Inner ring diameter, as a multiple of the pin.
    static let selectedReticleInnerScale: CGFloat = 1.7
    static let selectedReticleStroke: CGFloat = 1.5

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
