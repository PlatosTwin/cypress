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
/// pass read the app's state at the moment it ran. When this was written screen 01 re-evaluated its
/// basemap body **240 times a second at rest** (E139's unexplained residual), so when the reader
/// panned, there was always an update already in flight carrying the camera as it was *before* the
/// pan. Whatever the settle handler wrote, that in-flight value arrived afterwards holding the old
/// camera, differed from whatever the layer recorded, and was taken for a fresh request. The map was
/// driven back. Measured: with the two sides written to agree, a pan still produced 39 camera writes
/// and the map returned to the reader's own location every time.
///
/// **That rest-state rate is now zero, and this type is why** — E139 guessed the residual and the
/// unpannable map might share a root cause, and they did. Re-measured on 2026-08-04 (task #226) on a
/// 16e with location granted and 87 markers: 135 of 141 one-second windows report `body=0`, and every
/// window that does not is a pan, a filter tap, a recenter press or the launch itself. E139's "it is
/// cheap, and it is still wrong" is discharged.
///
/// **The ticket is not thereby redundant, and must not be removed as dead weight.** A rate of zero at
/// *rest* is not an absence of in-flight passes during interaction — a pan is precisely when both the
/// stale value and the settle exist — and the guarantee here has never depended on the rate. That is
/// the point of it: staleness is decided by a sequence number rather than by how fast the body runs,
/// so no future change to the invalidation rate can bring E140 back.
///
/// A sequence number settles it, because staleness is exactly what a sequence number can see. Every
/// genuine ask takes the next ticket; a stale view value carries a ticket the layer has already
/// applied and is ignored on sight. **No comparison of camera geometry is involved, so no amount of
/// snapshot skew can turn an old request into a new one.**
///
/// It also retires the heuristic it replaces. The layer used to notice a pan by measuring how far the
/// camera had drifted from the request, purely so that pressing the recenter control twice was not
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

    /// A camera somebody asked for: a press of the recenter control, a cluster tap, a nudge of a
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
    /// Which species hold the four color slots for these pins (task #80). Defaults to nothing,
    /// because the two other screens that draw this basemap — 16's pin adjust and the pin-set map —
    /// are about *one* tree and its neighbors rather than about the mix of species on a street, and
    /// a species coloring there would be four hues answering a question nobody is asking.
    var speciesPalette: MapSpeciesPalette = .empty
    let userCoordinate: Coordinate?
    /// Which way the reader is facing (task #155). Defaults to nothing, for the same reason the
    /// species palette does: 16's pin adjust and the pin-set map are about one tree and the reader's
    /// bearing answers no question either of them asks. `nil` draws the bare dot.
    var userHeadingDegrees: Double?
    let selectedPinID: UUID?

    var onCameraChange: (BoundingBox, Int) -> Void
    var onSelectPin: (TreePin) -> Void
    var onSelectCluster: (TreeCluster) -> Void
    /// A pan or pinch began on the glass (task #128). Nil on the two one-tree screens, which have
    /// no auto-centering to gate. See `MapAnnotationLayer.onReaderGesture`.
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
            userHeadingDegrees: userHeadingDegrees,
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
/// screen needs that no component owns. Colors, fonts, radii and shadows are **never** here —
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

    // MARK: The recenter control

    /// **NOT SPECIFIED** — see `MapRecenter` for why this control exists and why it is ours. The
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

    // MARK: The bottom notice's scroll budget (RULINGS R53 §6, ERRATA E183 §2)
    //
    // `MapLocationNotice` used to be free to grow as tall as its text needed. At AX5 that is
    // taller than a 390 pt phone, and since the card is laid out from `bottomChrome`'s bottom
    // edge it grew *upward past `y = 0`*, taking its own way out off the top of the screen with
    // it. The owner ruled on 2026-08-05 that it scrolls once it runs out of room rather than
    // doing that, so the room it has to work with has to be a real number.

    /// The room reserved for `MapRecenterButton` above the notice slot.
    ///
    /// **Corrected 2026-08-06 by direct owner ruling, superseding RULINGS R53 §6's conservative
    /// stance for this constant specifically.** ERRATA E243 found the old `98` was never a
    /// measurement of the control: it was the control's real AX5 footprint plus the 54 pt top
    /// safe-area inset that `AX5ReflowTests.ax5Size`'s measuring window inherited from whichever
    /// simulator it ran on (54 pt on an iPhone 16 Pro, 47 on an iPhone 16e — the harness has since
    /// been fixed to subtract it, which is why the value here no longer needs to).
    /// `MapRecenterButton` is a fixed `CypressSpacing.minTapTarget` square and measures exactly
    /// that at `.accessibility5`, device-independently — asserted by
    /// `AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5`. The reservation is set to
    /// the footprint itself rather than left as a margin over it.
    static let locateButtonHeightAX5: CGFloat = CypressSpacing.minTapTarget
    /// The room reserved for `IdentifyFAB` above the notice slot. Its label is `.font(…, .body)`,
    /// which does scale with Dynamic Type, so this is genuinely not `fabPaddingV * 2` plus a fixed
    /// glyph.
    ///
    /// **Corrected 2026-08-06**, for the same reason and under the same ruling as
    /// `locateButtonHeightAX5` above: E243 found the old `137` carried the same 54 pt safe-area
    /// term. The FAB's real AX5 footprint is 83 pt, measured through `AX5ReflowTests.ax5Size`
    /// after that helper's fix (subtracting the measuring window's inherited safe-area insets),
    /// device-independently on both the iPhone 16 Pro and the iPhone 16e.
    static let fabHeightAX5: CGFloat = 83

    /// Everything `bottomChrome`'s `VStack` stacks above the notice slot, at or above the worst
    /// case (`.accessibility5`) either control ever measures: the recenter control, the gap to the
    /// FAB, the FAB, the gap to the card, and the card's own gap down to the tab bar. Reserved
    /// unconditionally — at ordinary sizes both controls are far smaller than this, so the notice
    /// is left with more room than it asks for and nothing about its rendering changes; see
    /// `noticeMaxHeight(availableHeight:topInset:)`.
    static let bottomSlotReservedAboveAX5: CGFloat =
        locateButtonHeightAX5 + locateToFabGap + fabHeightAX5 + fabToCardGap
            + tabBarHeight + cardToTabBarGap

    // MARK: The top chrome's own reservation (task #250)
    //
    // Correcting `locateButtonHeightAX5`/`fabHeightAX5` above (task #246) gave `MapLocationNotice`
    // back the ~108 pt of scroll budget those inflated constants had been silently eating — the
    // ticket's own goal, and the taller notice that resulted is the point of #246. But
    // `bottomSlotReservedAboveAX5` only ever named what `bottomChrome`'s `VStack` stacks *above the
    // notice, inside that same block* — the recenter control, the FAB, their gaps, the tab bar. It
    // never named anything about `MapHomeView.chrome`'s other, top-anchored block (the search bar
    // and the filter chip row), because at ordinary sizes the two blocks do not meet. At AX5 they
    // do (`MapHomeView.chrome`'s own comment on the reorder, "the two blocks only overlap at
    // accessibility sizes, where they already did"), and a notice grown all the way to the bigger
    // budget #246 gave back pushes the bottom-anchored stack up far enough that `MapRecenterButton`
    // — first in it — rises **behind** the chip row: present in the tree, `isHittable == false`.
    // Measured on iPhone 16 Pro Max, AX5, `CYPRESS_LOCATION=denied` (the longest of the four
    // `MapOpening.Standing` sentences, so the state that pushes the notice closest to its budget):
    // recenter's frame moved from `(380.3, 204.0, 44.0, 44.0)` (old, over-reserved constants) to
    // `(380.3, 96.0, 44.0, 44.0)` (#246's corrected constants, this reservation still absent) —
    // `isHittable` `true` → `false`. Task #250 fixed it in the same PR that shipped #246's
    // correction — see `docs/ERRATA.md` once the orchestrator splices this branch's entry under
    // its real number at merge.

    /// `SearchBar`'s own AX5 footprint, content only — the simulator's inherited safe-area inset
    /// already subtracted, the same way `AX5ReflowTests.ax5Size` measures `locateButtonHeightAX5`
    /// and `.fabHeightAX5` above (E243). Unlike those two this is a bound rather than an exact
    /// frame: the field carries Dynamic-Type text (`CypressFont.body145`), so it grows with the
    /// size rather than staying a fixed square. Guarded by
    /// `AX5ReflowTests.topChromeFitsItsReservedBudgetAtAX5`.
    static let searchBarHeightAX5: CGFloat = 77
    /// `MapFilterChips`'s own AX5 footprint — the collapsed row only. `isExpanded` starts `false`,
    /// and the opened drawer (behind `MapFilterCopy.moreLabel`) pushes the row's *own* bottom edge
    /// down when the reader opens it themselves, which is not room this reservation owes anybody in
    /// advance. Bounded rather than fixed, for the reason `searchBarHeightAX5` above is: the chip
    /// labels are Dynamic-Type text and the row stays one line at every size (#166) rather than
    /// wrapping, so its height tracks the text without ever taking a second line.
    static let chipRowHeightAX5: CGFloat = 60

    /// The room the top chrome — `MapHomeView.chrome`'s `.top` overlay, down through the filter
    /// chip row — needs before the recenter control may rise into it.
    ///
    /// **`topInset` is read live, not baked in.** It is `GeometryReader`'s own
    /// `proxy.safeAreaInsets.top`, threaded down from `MapHomeView.chrome` through `bottomChrome`
    /// to `noticeMaxHeight(availableHeight:topInset:)` below — never folded into a `MapLayout`
    /// constant, because #246/E243 is exactly the lesson that a safe-area inset baked into a
    /// constant silently doubles up with the real one on whichever simulator happens to measure it
    /// (54 pt on an iPhone 16 Pro, 47 on an iPhone 16e, and neither the iPhone 16 Pro Max's own
    /// figure this reservation is measured against). Reading it live is what makes this correct on
    /// every device rather than merely on the one it was written against.
    ///
    /// `searchTopInset` and `chipRowTop` are the same two gaps the top overlay is itself laid out
    /// with (`MapHomeView.chrome`'s `.padding(.top:)` and its `VStack`'s own `spacing:`), so this
    /// sum is exactly the y-coordinate — in the same screen coordinates `bottomChrome` positions the
    /// recenter control in — of the chip row's own bottom edge.
    static func topChromeReservedAX5(topInset: CGFloat) -> CGFloat {
        topInset + searchTopInset + searchBarHeightAX5 + chipRowTop + chipRowHeightAX5
    }

    /// The height `MapLocationNotice` may take in the bottom slot before it must scroll instead
    /// of growing past the top of the screen, or up into the chip row above it (task #250).
    /// Conservative rather than exact — it reserves the AX5 heights of the recenter control and the
    /// FAB even when Dynamic Type is nowhere near AX5, because at ordinary sizes the notice never
    /// gets close to this budget regardless, and a budget computed once from constants is simpler
    /// than measuring the controls' actual height on every layout pass for a slot this is the
    /// backstop for, not the primary fit.
    static func noticeMaxHeight(availableHeight: CGFloat, topInset: CGFloat) -> CGFloat {
        availableHeight - bottomSlotReservedAboveAX5 - topChromeReservedAX5(topInset: topInset)
    }

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
    // reticle exists to make one pin findable among neighbors, and the reader's own position
    // outranks even that — a selection half-covered by the dot is still findable (the rings are
    // outside the dot's footprint at any overlap), where a dot behind a scaled selected pin is
    // simply gone.
    /// The reader's dot. `MKAnnotationViewZPriority.max` — nothing may be given a higher one.
    static let userDotZPriority = MKAnnotationViewZPriority.max
    /// The selected pin: above every unselected neighbor (two pins 20 pt apart overlap inside
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

    // MARK: The direction cone (task #155)
    //
    // **NOT SPECIFIED in SCREENS.md** — 01 draws a bare GPS dot, and C19's catalog has no cone. This
    // is the owner's own request of 2026-08-01, named as "the compass-cone/beam treatment readers
    // know from Maps", and the numbers below are therefore this screen's rather than the mock's, in
    // the same way `MapRecenter`'s are. Nothing is added to the color palette: the cone is
    // `CypressColor.gpsDot`, the dot's own blue, faded out along its length.

    /// How far the cone reaches past the center of the dot, in points.
    ///
    /// A little under twice the 18 pt dot, so the mark reads as *belonging to* the dot rather than
    /// as a second object beside it, and so it stays inside the 44 pt of tap target the marker view
    /// already claims — the cone must not become a thing the reader tries to touch.
    static let userHeadingConeRadius: CGFloat = 30

    /// How wide the cone opens, in degrees, total.
    ///
    /// Wide enough to read as a direction at a glance at 30 pt long, and no wider: the cone is an
    /// answer to "which way am I facing", not a claim about how precisely the magnetometer knows.
    /// It does **not** vary with `headingAccuracy` — a cone that fattened and thinned as the reader
    /// walked past parked cars would be reporting sensor noise as if it were information, and the
    /// one accuracy decision this feature makes is the honest one: below zero, no cone at all.
    static let userHeadingConeDegrees: Double = 62

    /// The cone's opacity where it leaves the dot. It fades to nothing at `userHeadingConeRadius`.
    ///
    /// Restrained, not faint. The dot is the fact; the cone is a hint about it, and a solid wedge at
    /// the dot's own blue would swallow both the dot and the pins the reader is looking for.
    ///
    /// **It was 0.32 in build 9 and that was too light on the phone** (#208). The number to reason
    /// about is not the peak but the average: the gradient falls linearly to nothing over 30 pt, so a
    /// 0.32 peak is a mean alpha near 0.16 over the cone's whole area — which survives a screenshot
    /// on a desk and disappears against a sunlit basemap outdoors. 0.55 holds the same shape at a
    /// mean near 0.27.
    ///
    /// No simulator can settle this and none ever will: there is no magnetometer, `usable` returns
    /// `nil`, and the cone is never drawn. It is an outdoor judgment on a real phone, and it is the
    /// owner's.
    static let userHeadingConeOpacity: Double = 0.55

    /// How long the cone takes to swing from one heading to the next, in seconds.
    ///
    /// **Not `userDotGlideSeconds`.** The dot's one-second glide is matched to CoreLocation's own
    /// roughly-one-fix-a-second cadence while walking; headings arrive as fast as the reader turns,
    /// gated at `MapHeading.publishDegrees`, and a one-second sweep would leave the cone visibly
    /// behind the phone in the hand holding it. A quarter of a second is long enough to read as a
    /// turn rather than a jump — which is what #149 established for the dot and what this must not
    /// undo one channel over — and short enough that the cone is where the reader is pointing.
    static let userHeadingRotationSeconds: TimeInterval = 0.25

    /// A jump longer than this snaps instead of gliding, in degrees of latitude/longitude.
    ///
    /// ~0.01° is about a kilometer: no pedestrian, cyclist or bus covers it between two fixes, so
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
    // than thirty identical neighbors, which is not a thing a reader can find. The card at the
    // bottom names the tree and the map does not say which dot it is talking about.
    //
    // ── What replaces it, and why it cannot be read as a species color ────────────────────────
    // Two concentric rings **outside** the pin, in ink and in the ring color, and the scale stays.
    // Three properties make it unconfusable with the species palette, by construction rather than by
    // taste:
    //
    //   1. **It is achromatic.** `textInk` and `pinRingStroke` are the near-black and the white of
    //      the app's two ends; every species slot is a chromatic fill at OKLCh chroma ≥ 0.08. A
    //      reader cannot mistake a black-and-white ring for one of four hues, and a color-blind
    //      reader — for whom the four hues are the *hardest* thing on the map — finds this one
    //      easiest.
    //   2. **It is outside the pin's own footprint**, at 1.7× and 2× the 18 pt dot, where no pin of
    //      any kind ever draws fill. Species color is always *inside* a pin.
    //   3. **It is a ring, not a fill**, and there is only ever one of them on the map.
    //
    // Two rings rather than one because the ground is a live MapKit basemap: a white ring vanishes on
    // the paper and an ink one vanishes over a park polygon after dark, so the mark carries both ends
    // of the ramp and one of them always reads. The inner ring takes the outer's color in the other
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

    /// Where the map opens when there is no fix: Mission Dolores Park, near enough the center of
    /// the inventory that the first screen is full of trees wherever the user actually is.
    /// (An earlier comment here claimed the Sunset, the corner of the city SCREENS.md 01 draws.
    /// The coordinate has always been Dolores Park; the prose was wrong, not the number.)
    static let defaultCenter = Coordinate(latitude: 37.7596, longitude: -122.4269)

    /// Where the map opens, in meters across the short edge of the phone.
    ///
    /// SCREENS.md gives no opening zoom, and the number is the whole difference between a map and a
    /// stain. A1 (BUILD-PLAN §11) starts drawing individual pins at zoom 16; on this phone zoom 16
    /// is 742 m wide, and 742 m of San Francisco is a median of 1,807 street trees — 4,556 at this
    /// very coordinate. 98.6 % of trees in the seed are closer to their nearest neighbor than one
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
    /// Mission Dolores Park — 390 m across, and the fallback center above — the nearest inventoried
    /// tree is on 18th or 20th St, outside a 120 × 261 m view. That is the honest answer to "what is
    /// near me", not a failure to load; the trees appear as soon as the camera reaches a street.
    static let defaultSpanMeters: CLLocationDistance = 120

    static func region(around center: Coordinate, meters: CLLocationDistance = defaultSpanMeters) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.clLocationCoordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
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
