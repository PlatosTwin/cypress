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

    /// Whether this map draws MapKit's compass, and how far down its top-trailing slot has to start
    /// to clear the chrome over it.
    ///
    /// **`nil` means no compass, and that is the default.** The owner's ruling of 2026-08-21
    /// (RULINGS R80, item 6b) is about screen 01 — the map a morning is conducted from. Screen 16's
    /// pin adjust and the pin-set map draw this same basemap about *one tree*, they are not in the
    /// ruling, and a control appearing on a screen nobody specified it for is the stop-and-ask
    /// DECISIONS constraint 21 names. They rotate too, so if the compass belongs there it is a
    /// second ruling and one argument here.
    var compassTopInset: CGFloat?

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
            compassTopInset: compassTopInset,
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

    /// The bar `MapTreeCard.titlePlaceholder` draws where the name will be, for the moment between
    /// the tap and the profile read landing. **NOT SPECIFIED** — see that property for why the card
    /// draws a bar there rather than a word.
    ///
    /// The width is a street-tree name's worth of bar, short of the badge that sits beside it. It is
    /// deliberately *not* scaled: nothing is derived from it, and a bar that grew with the type ramp
    /// would only reach the badge sooner.
    static let cardTitlePlaceholderWidth: CGFloat = 132

    /// The bar's height — **`CypressFont.listNameSerif`'s drawn line at the reader's own type size**.
    ///
    /// **This was a fixed `21` and it was wrong at every size** (PR #102 review). The doc claimed 21
    /// was "`CypressFont.listNameSerif`'s drawn line (17.5pt serif)"; measured through
    /// `UIFontMetrics`, that line is **24.68 pt** at the default content size — 21 is `17.5 × 1.2`,
    /// a guess at a line height rather than a measurement of one. Worse, the constant was static
    /// while the title it stands in for is `relativeTo: .headline` and reaches **67.18 pt at AX5**,
    /// where `MapTreeCard` also gives the title `.lineLimit(2)`. The bar was a fifth of the row it
    /// claimed to be holding open.
    ///
    /// The number here is the face's **unscaled** drawn line, measured rather than derived from a
    /// multiplier: the 17.5 pt `SourceSerif4-SemiBold` draws **23.9925** pt of line, rounded to the
    /// hundredth. Scaling it is the use site's job (below). For reference, the ramp it rides
    /// measures 24.68 pt at `.large`, 31.53 at `.xxxLarge`, 43.87 at `.accessibility1` and 67.18 at
    /// `.accessibility5`.
    ///
    /// **What this does and does not buy.** It makes the bar the height of *one* line of the title
    /// at the reader's size, which is the claim the old doc made and did not keep. It is not a
    /// promise that nothing under the card moves: a name that takes the second line
    /// `.lineLimit(2)` allows is taller than one line at any size, and on the glass at the default
    /// size the row is sized by the thumbnail beside the title anyway — the card's white surface
    /// measured 769.0 → 850.7 pt in both the awaiting and the resolved frame, unchanged, because
    /// the 3.7 pt the title moved was inside the thumbnail's own height. The bar holding a
    /// title-sized row is the honest claim; "nothing moves" was not.
    ///
    /// **The scaling itself lives at the use site**, as `@ScaledMetric(relativeTo: .headline)` on
    /// `MapTreeCard.titlePlaceholderHeight` — `.headline` because that is `listNameSerif`'s own
    /// `relativeTo:`, so the bar rides the exact ramp the title does. This constant is that
    /// metric's base value and the only number written down. Guarded by
    /// `MapCardPlaceholderTests`, which measures the bar against a real styled `Text` at both ends
    /// of the ramp rather than against a table of expected points.
    static let cardTitlePlaceholderHeight: CGFloat = 23.99

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
    /// **Corrected 2026-08-06** under owner ruling, for the same reason as `locateButtonHeightAX5`
    /// above: E243 found the old `137` carried a 54 pt safe-area term that belonged to the
    /// measuring window rather than to the view. That correction was right about the inset.
    ///
    /// **It was wrong about the number, and 83 shipped as a bound that does not hold** (task #258,
    /// PR #60 review B2). `AX5ReflowTests.ax5Size` offered the FAB `phoneWidth` = 393 pt; screen 01
    /// offers it the phone's width less `sideInset` on each side. **The label wraps between 361 pt
    /// and 370 pt of content width** — 393 pt and 402 pt of phone — so at 393 the harness saw one
    /// line and 83 pt, and every phone at or below 393 pt draws three lines and **135.67 pt**.
    /// Read off the accessibility tree of a running iPhone 16e (390 pt): `(127, 503.33, 247.33,
    /// 135.67)`, against `(60, 571, 364.33, 83)` on an iPhone 16 Pro Max. The 52.67 pt shortfall
    /// put the recenter control 30 pt up inside the species legend and turned #258's own guard red
    /// on a device it had not been run on. The old `137` was closer to the truth than the `83` that
    /// replaced it; what E243 actually removed was the inset, and the width blindness came in with
    /// it unnoticed.
    ///
    /// **One number rather than a width threshold, deliberately.** A `fabHeightAX5(contentWidth:)`
    /// would reserve 83 above 393 pt and 136 below, and would be exact — at the cost of a wrap
    /// threshold in a constant, which is a number that moves the next time the label, the font or
    /// the glyph changes and moves silently. The bound over-reserves 53 pt on phones wider than
    /// 393 pt, which comes out of `MapLocationNotice`'s scroll budget and out of nothing else, and
    /// it buys back margin on exactly the narrow phones where PR #60's review measured only 25.67 pt
    /// between the legend and this control.
    ///
    /// Guarded by `AX5ReflowTests.bottomChromeControlsFitTheReservedBudgetAtAX5`, which now sweeps
    /// `heightBoundWidths` **with screen 01's own gutters applied** — the two changes are one
    /// change, because the constant is only as honest as the width it was measured at.
    static let fabHeightAX5: CGFloat = 136

    /// The same footprint at the largest **ordinary** Dynamic Type size, `.xxxLarge`: 54 pt,
    /// measured through the swept harness at every width.
    ///
    /// **Reserving 136 at every type size was not affordable and it was caught here** (task #258).
    /// `bottomSlotReservedAbove` is subtracted from the screen whatever the reader's text size
    /// is, on the standing argument that at ordinary sizes the notice is nowhere near its budget —
    /// true when the term was 83, and false at 136 on a 667 pt phone, where the AX5 reservation put
    /// `MapSpeciesLegend` into a `ScrollView` **at the default content size**. That would have been
    /// a scroller over the map for a reader who had asked for nothing. Every reservation on this
    /// screen now tracks the size the reader is actually running.
    static let fabHeightLarge: CGFloat = 55

    /// Everything `bottomChrome`'s `VStack` stacks above the notice slot, at or above the worst
    /// case (`.accessibility5`) either control ever measures: the recenter control, the gap to the
    /// FAB, the FAB, the gap to the card, and the card's own gap down to the tab bar. Reserved
    /// unconditionally — at ordinary sizes both controls are far smaller than this, so the notice
    /// is left with more room than it asks for and nothing about its rendering changes; see
    /// `noticeMaxHeight(screenHeight:topInset:namedSpecies:isAccessibilitySize:)`.
    static func bottomSlotReservedAbove(isAccessibilitySize: Bool) -> CGFloat {
        locateButtonHeightAX5
            + locateToFabGap
            + (isAccessibilitySize ? fabHeightAX5 : fabHeightLarge)
            + fabToCardGap
            + tabBarHeight
            + cardToTabBarGap
    }

    // MARK: The top chrome's own reservation (task #250)
    //
    // Correcting `locateButtonHeightAX5`/`fabHeightAX5` above (task #246) gave `MapLocationNotice`
    // back the ~108 pt of scroll budget those inflated constants had been silently eating — the
    // ticket's own goal, and the taller notice that resulted is the point of #246. But
    // `bottomSlotReservedAbove` only ever named what `bottomChrome`'s `VStack` stacks *above the
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
    ///
    /// **PR #60 proposed raising this to 85 and that was wrong** (task #258, review B3). The
    /// derivation was `158.33 − 12 − 62` from an iPhone 16 Pro's chip-row frame, with the 62 built
    /// from `topInset = 54` — and 54 is E243's *synthetic-window* inset, which is the exact number
    /// E243 exists to warn is not the app's. The 16 Pro Max reports the same chip-row `minY` of
    /// 158.33 with a real inset of 62, so the subtraction was 8 pt out. Measured directly instead,
    /// through the swept harness at the width screen 01 gives it: **76.67 pt at all six of
    /// `AX5ReflowTests.heightBoundWidths`**, which the original 77 bounds. Reverted, and left here
    /// because a constant that has been wrongly "corrected" once will be again.
    static let searchBarHeightAX5: CGFloat = 77
    /// `SearchBar` at the largest ordinary size, `.xxxLarge`: 49 pt measured, 50 reserved.
    static let searchBarHeightLarge: CGFloat = 50
    /// `MapFilterChips`'s own AX5 footprint — the collapsed row only. `isExpanded` starts `false`,
    /// and the opened drawer (behind `MapFilterCopy.moreLabel`) pushes the row's *own* bottom edge
    /// down when the reader opens it themselves, which is not room this reservation owes anybody in
    /// advance. Bounded rather than fixed, for the reason `searchBarHeightAX5` above is: the chip
    /// labels are Dynamic-Type text and the row stays one line at every size (#166) rather than
    /// wrapping, so its height tracks the text without ever taking a second line.
    static let chipRowHeightAX5: CGFloat = 60
    /// `MapFilterChips` at the largest ordinary size, `.xxxLarge`: 34.67 pt measured, 36 reserved.
    static let chipRowHeightLarge: CGFloat = 36

    /// The room the top chrome — `MapHomeView.chrome`'s `.top` overlay, down through the filter
    /// chip row — needs before the recenter control may rise into it.
    ///
    /// **`topInset` is read live, not baked in.** It is `GeometryReader`'s own
    /// `proxy.safeAreaInsets.top`, threaded down from `MapHomeView.chrome` through `bottomChrome`
    /// to `noticeMaxHeight(screenHeight:topInset:namedSpecies:isAccessibilitySize:)` below — never
    /// folded into a `MapLayout`
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
    static func topChromeReserved(topInset: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        topInset
            + searchTopInset
            + (isAccessibilitySize ? searchBarHeightAX5 : searchBarHeightLarge)
            + chipRowTop
            + (isAccessibilitySize ? chipRowHeightAX5 : chipRowHeightLarge)
    }

    // MARK: The rest of the top chrome, which the chip row is not the bottom of (task #258)
    //
    // `topChromeReserved` above stops at the filter chip row, and its own doc says so: the sum is
    // "exactly the y-coordinate … of the chip row's own bottom edge". **The chip row is not the last
    // child of that block.** Below it the same `VStack` stacks the `Needs care` toast, the search
    // status line, and — whenever the visible camera has colored any species at all, which is the
    // standing state on this screen — `MapSpeciesLegend`, whose chips wrap onto as many lines as
    // their names need.
    //
    // Measured on an iPhone 16 Pro (402 pt), AX5, `CYPRESS_LOCATION=denied`, at `origin/main`: the
    // legend is `(16, 230, 344.33, 262.67)`, so the top block ends at y 492.67 against the 211 pt
    // the reservation predicted; the recenter control was at y 315 and the identify FAB at
    // `(22, 371, 364.33, 83)` — **inside the legend's rectangle**, and drawn over by it, because
    // `MapHomeView.chrome` applies the bottom block first so that the top block draws over it. The
    // FAB is screen 01's only entrance to the visit flow, and all but the bottom 14 pt of it was
    // covered. That is #250's defect one child further down the same stack.
    //
    // It read as a flaky test rather than a bug for a reason worth keeping: XCUITest resolves
    // `isHittable` by hit-testing the activation point and then points sampled inside the frame, so
    // a control covered everywhere except a 14 pt band reports reachable whenever the sampling lands
    // in the band. See `CypressUITests/IdentifyFABReachabilityTests`, which asserts the rectangles
    // instead.
    //
    // ── Why this is arithmetic on the model and not a measurement ────────────────────────────────
    //
    // The obvious repair is to measure the top block's real bottom edge and feed it back. **It was
    // built, and it does not work.** A `GeometryReader` in a `.background` on the top block, its
    // `maxY` handed to `@State` through `onChange`, removed the occlusion on most launches and froze
    // on some — the same value for the whole life of the process, from the first sample to the last.
    // Instrumented over 32 launches on an iPhone 16 Pro, three froze, and in those three the
    // `GeometryReader` re-rendered with the correct 492.67 while the `@State` value and the last
    // value the `onChange` action was *given* were the same stale intermediate (425.0, a three-row
    // legend; 357.33, a two-row one). **The best explanation is that the action was never called
    // for the last transition** — `onChange` is edge-triggered over a value that then never changes
    // again, so nothing re-delivers it. **It is inferred rather than established**: the probe that
    // reports what the action was given writes into non-observed storage from inside the measuring
    // closure and is read back through the same render, so a reordering of that write against its
    // own publication fits the same three readings. What is not in doubt is that four wirings of
    // the same idea flake, and all four are edge-triggered channels out of the layout system.
    //
    // The palette is not. `MapSpeciesPalette` is model state that `MapHomeView` already observes, so
    // the number of chips is known *before* layout rather than reported back out of it, and there is
    // no channel to drop anything.

    /// One `MapSpeciesLegend` chip's own footprint at an accessibility Dynamic Type size.
    ///
    /// A **bound**, in the sense `searchBarHeightAX5` is: the chip is one line of
    /// `CypressFont.body12SemiBold` (`.lineLimit(1)`, which is what makes a chip's height
    /// independent of how long the species' name is) inside `chipPaddingVFilter` top and bottom.
    /// Measured 59.67 pt on an iPhone 16 Pro at AX5 — `(262.67 − 3 × chipGap) / 4` from the legend's
    /// own frame — and guarded by `AX5ReflowTests.theSpeciesLegendFitsItsReservationAtAX5`.
    static let legendChipHeightAX5: CGFloat = 60

    /// The same footprint at the largest **ordinary** Dynamic Type size, `.xxxLarge`.
    ///
    /// Two buckets rather than one, because unlike every other reservation in this file this one is
    /// multiplied by up to four. Reserving the AX5 figure unconditionally — the bargain
    /// `bottomSlotReservedAbove` makes — would take 276 pt off `noticeMaxHeight` at the default
    /// content size, where the legend is nowhere near that tall, and would put `MapLocationNotice`
    /// into a scroll on a screen with room to spare. Gating on
    /// `dynamicTypeSize.isAccessibilitySize` buys a step at the AX1 boundary instead, and both
    /// sides of the step are bounds that a guard measures rather than guesses.
    static let legendChipHeightLarge: CGFloat = 36

    /// Which of the two above applies at the size the reader is running.
    static func legendChipHeight(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? legendChipHeightAX5 : legendChipHeightLarge
    }

    /// What `MapSpeciesLegend` would take if nothing stopped it — 0 when it draws nothing.
    ///
    /// **An upper bound by construction, not an estimate.** `FlowRow` puts *at most* one chip on a
    /// line, so `count` chips occupy at most `count` lines; every chip is exactly one line tall
    /// (`.lineLimit(1)`), so every line is at most `legendChipHeight` tall. A legend whose names are
    /// short enough to pair up on a line is therefore over-reserved and never under-reserved, which
    /// is the only direction that can put a control back underneath another one. Guarded by
    /// `AX5ReflowTests.theSpeciesLegendFitsItsReservationAtAX5`.
    ///
    /// - Parameter count: how many entries the legend will draw — `MapSpeciesLegend.named(in:)`,
    ///   which is the one definition of that, so the reservation and the view cannot disagree.
    static func legendNaturalHeight(namedSpecies count: Int, isAccessibilitySize: Bool) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * legendChipHeight(isAccessibilitySize: isAccessibilitySize)
            + CGFloat(count - 1) * chipGap
    }

    /// **Everything below the filter chip row is shared between two growable things**, and this is
    /// the room they share: the screen, less what `bottomChrome` stacks above the notice, less the
    /// chip row's own bottom edge, less the gap the two blocks must keep between them.
    ///
    /// Both consumers are bounded out of this one number, so the arithmetic that keeps them apart is
    /// stated once. `AX5ReflowTests.theReservedBlocksNeverMeet` asserts the consequence over every
    /// screen and inset the app runs on.
    static func chromeSlackBelowChipRow(
        screenHeight: CGFloat,
        topInset: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        max(
            0,
            screenHeight
                - bottomSlotReservedAbove(isAccessibilitySize: isAccessibilitySize)
                - topChromeReserved(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
                // The one vertical rhythm this screen's chrome has (`locateToFabGap` is the same
                // number for the same reason). Without it the two blocks come to rest exactly edge
                // to edge, which is a knife edge for the reader and for any guard asserting they do
                // not intersect.
                - chipRowTop
        )
    }

    /// **The height `MapLocationNotice` is never given less than** (task #258, PR #60 review B4).
    ///
    /// The first version of this split served the legend first and gave the notice whatever was
    /// left, which on a short phone is **nothing**: `noticeMaxHeight` came out at 0 on a 667 pt
    /// screen at every inset, and `MapHomeView.standingNotice` hands that straight to
    /// `MapLocationNotice(maxHeight:)` for all four arms — including the refused arm, whose
    /// `Settings` button is the only way the reader has to fix the permission the card is about. A
    /// `ScrollView` at `frame(maxHeight: 0)` draws nothing. **A fix for an unreachable FAB that
    /// makes the permission remedy unreachable instead has not fixed anything**, and RULINGS R53 §6
    /// ruled that this card *scrolls*, not that it disappears.
    ///
    /// The number is the card at its smallest that still carries an action: a one-line title, no
    /// message, and the button — **92.67 pt, identical at all six of
    /// `AX5ReflowTests.heightBoundWidths`**, rounded up. At this budget the button sits at
    /// `cardPaddingV`…`cardPaddingV + 59.67` and is *fully* visible without scrolling, which is the
    /// property that matters; the message, and the second line of a title that takes two, are what
    /// scroll. Guarded by `AX5ReflowTests.theNoticeFloorFitsItsOwnActionButton`.
    ///
    /// It is deliberately not the *whole* first row (143 pt for the denied title at AX5, 243.67 for
    /// `Location Services are off` at 375 pt). A floor that large is affordable on a 440 pt phone
    /// and takes the species legend below one chip on a 667 pt one — it would buy a fully readable
    /// title by making the legend useless. What the reader sees at each width is in `docs/ERRATA.md`
    /// once the orchestrator splices this branch's pending entry under its real number at merge.
    static let noticeFloorAX5: CGFloat = 93

    /// The same card at `.xxxLarge`: 65 pt measured, 66 reserved.
    static let noticeFloorLarge: CGFloat = 66

    /// Whichever floor applies at the size the reader is running.
    static func noticeFloor(isAccessibilitySize: Bool) -> CGFloat {
        isAccessibilitySize ? noticeFloorAX5 : noticeFloorLarge
    }

    /// The ceiling `MapSpeciesLegend` may draw in before it must scroll — **the raw arithmetic,
    /// before `quantizedLegendCeiling` moves it off a chip's edge.**
    ///
    /// The legend is served first out of `chromeSlackBelowChipRow` **and the notice's floor is
    /// taken off the top before it is** — so "served first" now means "served first out of what is
    /// left over the floor", which is what stops this from zeroing the card below it. Serving it
    /// first at all is the deliberate half: the legend is the top block's last child, so it is the
    /// thing physically between the chip row and the identify FAB, and giving the notice priority
    /// would leave the legend to be cut — the legend's cut *is* the defect.
    static func legendCeiling(
        screenHeight: CGFloat,
        topInset: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        // `chipRowTop` is the `VStack`'s own spacing above the legend, which is part of what the top
        // block occupies and is not part of what the legend may draw in.
        max(
            0,
            chromeSlackBelowChipRow(
                screenHeight: screenHeight,
                topInset: topInset,
                isAccessibilitySize: isAccessibilitySize
            )
                - chipRowTop
                - noticeFloor(isAccessibilitySize: isAccessibilitySize)
        )
    }

    // MARK: The ceiling lands mid-chip, never on one (task #72)
    //
    // `legendCeiling` above is a subtraction, and a subtraction has no opinion about where in the
    // chip stack its answer falls. On the phones where it binds it landed, by arithmetic accident,
    // where a reader cannot tell it bound at all: a 844 pt screen at a 47 pt inset gives 201 pt,
    // which is three whole chips (195 pt) and 6 pt of the gap under them — **no part of the fourth
    // chip is on the screen.** A 852 pt screen at the same inset gives 209 and shows 6 pt of it, a
    // sliver thin enough to read as a rendering seam. Both draw a tidy stack of whole chips with
    // nothing beneath, which is what a *complete* list looks like.
    //
    // That is worse here than a clipped list normally is, because **the legend is also the species
    // filter** (#116). A fourth chip nobody can see is a fourth narrowing nobody knows the map has:
    // the screen says "these are the species" when the truth is "these are three of the species,
    // scroll". The owner decided (task #72) to spend a few points of chip on saying so.
    //
    // The correction only ever moves the ceiling **down**. Up is where `MapLocationNotice`'s floor
    // and the identify FAB's clearance live — E248/#258's defect and the reason there is a ceiling
    // at all — so a rule that could raise it would be re-opening the thing this file spends 200
    // lines closing. Down costs the legend chips and gives the notice room, and both are safe
    // directions.

    /// **How much of a chip must show past the ceiling, and how much of it must be hidden** — a
    /// quarter of one, at either end of the type ramp: 15 pt at AX5, 9 pt at `.xxxLarge`.
    ///
    /// Two claims in one number, and they are the same claim from both sides. A quarter of a chip
    /// showing is a slice of capsule wide enough to read as a chip rather than as a seam; a quarter
    /// of it hidden is a cut deep enough to read as a cut rather than as a chip that happens to end
    /// there. The rule is symmetric because the failure is: at 0 pt of peek the reader is told the
    /// list ends, and at 59 pt of a 59.67 pt chip they are told the same thing.
    ///
    /// **A quarter rather than a half, deliberately.** The peek is bought with chips: the quantized
    /// ceiling is the *largest* height that satisfies the rule, so the smaller the required peek,
    /// the more of the legend stays on the screen. Demanding half a chip would take an 874 pt
    /// screen's third species name off the display to show more of a fourth one it was already
    /// showing 20 pt of — a worse screen for the reader by the measure this ticket is about, which
    /// is how many of the filters they can see. A quarter is the least that is legible, and the
    /// least is what this should ask for.
    static let legendPeekShare: CGFloat = 0.25

    /// The peek in points, at the size the reader is running.
    static func legendPeek(isAccessibilitySize: Bool) -> CGFloat {
        legendChipHeight(isAccessibilitySize: isAccessibilitySize) * legendPeekShare
    }

    /// **`ceiling`, moved down to the nearest height that cuts a chip visibly** (task #72).
    ///
    /// The chips stack at `row = legendChipHeight + chipGap`, so chip *i* occupies
    /// `[i·row, i·row + chip]` and the window at `ceiling` shows `shown` points of the first chip it
    /// does not contain whole. `shown` saturates at a whole chip: a remainder past a chip's bottom
    /// edge is the *gap* below it, and a window ending in the gap shows nothing at all of the chip
    /// after it — which is the 201 pt case above, and the reason this cannot be written as a
    /// remainder against `row`.
    ///
    /// Where `shown` is already between `legendPeek` and a chip less `legendPeek`, the ceiling is
    /// returned untouched: it is already cutting a chip and there is nothing to buy. Otherwise the
    /// ceiling drops to the **largest** height whose peek is exactly `chip − legendPeek` — the
    /// deepest cut the rule allows, which is also the one that keeps the most of the legend on the
    /// screen, and which leaves most of the partly-shown species' name readable.
    ///
    /// **It never returns more than it was given**, which is the whole of its safety: every caller's
    /// clearance from the identify FAB and the notice's floor is computed from `legendCeiling`, and
    /// a quantization that could round *up* would be spending points that belong to those two.
    ///
    /// **Below one peek of room it gives up rather than making things worse.** A ceiling under
    /// `chip − legendPeek` is already a cut chip; a ceiling under `legendPeek` is a sliver this
    /// cannot improve by making it smaller, because the only direction available is down.
    ///
    /// **Nothing else reports that screen either, and an earlier draft of this comment said
    /// otherwise** (PR #63 review N1). It claimed such a screen "is a `chromeBudgetShortfall` report
    /// rather than a quantization problem". It is not: `chromeBudgetShortfall` asks whether the
    /// slack covers `chipRowTop + noticeFloor`, which says nothing about the legend's share of what
    /// is left, and `AX5ReflowTests.theChromeBudgetCanHouseBothOccupants` already asserts it is **0
    /// for every screen and inset this app runs on** — so by construction it never speaks for any of
    /// them. Measured: a 667 pt screen leaves 24 pt of legend at a 47 pt inset, 17 at 54 and 9 at
    /// 62, with a shortfall of 0.0 at all three. A legend under one chip is a real gap, it is
    /// **unreported**, and it is named here rather than assigned to a guard that cannot see it. No
    /// shipping phone is in it — 667 pt is the home-button iPhone SE, whose inset is 20 and whose
    /// ceiling is 45 — but the sweep crosses heights with insets precisely because tomorrow's phone
    /// may pair them differently.
    ///
    /// Guarded by `AX5ReflowTests.theLegendCeilingAlwaysCutsAChipAtAX5`, which measures the chips
    /// off the view and the ceiling off `legendMaxHeight` rather than recomputing either — and
    /// which gates that exemption on the room the screen had rather than on the ceiling this
    /// returns, so a quantizer that hands back a sliver cannot excuse itself with it (review B1).
    static func quantizedLegendCeiling(_ ceiling: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        let chip = legendChipHeight(isAccessibilitySize: isAccessibilitySize)
        let row = chip + chipGap
        let peek = legendPeek(isAccessibilitySize: isAccessibilitySize)
        let wholeRows = (ceiling / row).rounded(.down)
        let shown = min(max(0, ceiling - wholeRows * row), chip)
        guard shown < peek || shown > chip - peek else { return ceiling }
        let target = chip - peek
        let landing = ((ceiling - target) / row).rounded(.down)
        guard landing >= 0 else { return ceiling }
        return landing * row + target
    }

    /// **How much room this screen is short of housing both occupants**, in points — 0 when it can
    /// house them.
    ///
    /// The split cannot always succeed, and the failure has to be *sayable* rather than absorbed by
    /// whichever term happens to be the remainder. `legendCeiling` clamps at 0, so once the slack
    /// falls below `chipRowTop + noticeFloorAX5` the legend is given nothing at all and the notice
    /// starts eating into its own floor — silently, if nobody asks. This is the asking.
    ///
    /// `AX5ReflowTests.theChromeBudgetCanHouseBothOccupants` asserts it is 0 for every screen and
    /// inset the app runs on, so a device or a Dynamic-Type change that makes screen 01 unhousable
    /// fails the unit suite with a number rather than shipping a zero-height control.
    static func chromeBudgetShortfall(
        screenHeight: CGFloat,
        topInset: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        max(
            0,
            chipRowTop + noticeFloor(isAccessibilitySize: isAccessibilitySize)
                - chromeSlackBelowChipRow(
                    screenHeight: screenHeight,
                    topInset: topInset,
                    isAccessibilitySize: isAccessibilitySize
                )
        )
    }

    /// The ceiling to hand `MapSpeciesLegend.maxHeight` — **`nil` unless it actually binds.**
    ///
    /// The nil is not a shortcut. A non-nil ceiling puts the legend inside a `ScrollView`, and a
    /// `ScrollView` over a map takes touches across its whole frame where the bare `FlowRow` takes
    /// them only on the chips themselves (`MapHomeView.chrome`: "the empty width beside a chip has
    /// never taken a touch"). Screen 01 cannot afford to make the pan ambiguous, so the scroller
    /// appears only where the alternative is a control the reader cannot reach at all: a short phone
    /// at an accessibility size, where `topChromeReserved` plus four AX5 chips plus the bottom
    /// block wants more than the glass has. At every ordinary content size, on every supported
    /// phone, this returns `nil` and the view is byte-for-byte the wrapped `FlowRow` that shipped;
    /// at AX5 with a full palette it binds at or below 402 pt and does not at 430 and 440.
    /// `AX5ReflowTests.theLegendCeilingBindsWhereTheArithmeticSaysItDoes` carries that boundary as a
    /// table of five named phones.
    ///
    /// Something has to yield in that squeeze, and it is the legend rather than the FAB because a
    /// scrolled chip is reachable and a covered control is not — RULINGS R53 §6's own argument,
    /// applied to the other occupant of the same slot. Every chip stays pressable, which matters
    /// twice here because the legend is also the species filter (#116).
    ///
    /// **And when it binds, it binds mid-chip** (task #72): the ceiling handed back is
    /// `quantizedLegendCeiling`'s, so the clipped legend always ends part-way down a chip rather
    /// than on the seam between two of them. A reader who cannot see that the list continues cannot
    /// see that the filter continues either.
    static func legendMaxHeight(
        screenHeight: CGFloat,
        topInset: CGFloat,
        namedSpecies count: Int,
        isAccessibilitySize: Bool
    ) -> CGFloat? {
        guard count > 0 else { return nil }
        let natural = legendNaturalHeight(
            namedSpecies: count,
            isAccessibilitySize: isAccessibilitySize
        )
        let ceiling = legendCeiling(
            screenHeight: screenHeight,
            topInset: topInset,
            isAccessibilitySize: isAccessibilitySize
        )
        guard natural > ceiling else { return nil }
        // Quantized only on the branch that binds (task #72). Applying it inside `legendCeiling`
        // itself would move the *raw* number this comparison is made against, and the two widest
        // phones — where the whole legend fits with points to spare — would acquire a `ScrollView`
        // over the map because a quantized ceiling happened to fall below a natural height that was
        // never in question. `AX5ReflowTests.theLegendCeilingBindsWhereTheArithmeticSaysItDoes`
        // carries that boundary, and it is the same table as before this ticket.
        return quantizedLegendCeiling(ceiling, isAccessibilitySize: isAccessibilitySize)
    }

    /// The room the legend's block takes out of the slack: what it will actually occupy, plus the
    /// `VStack` gap above it.
    ///
    /// **Derived from `legendMaxHeight` rather than computed alongside it** (task #72). What the
    /// legend occupies is the ceiling when it binds and its natural height when it does not, which
    /// is exactly what that function already decides — and the two disagreeing by so much as the
    /// quantization's few points would be the reservation under-reading the view again, which is
    /// #258's defect in its original form.
    static func legendReserved(
        screenHeight: CGFloat,
        topInset: CGFloat,
        namedSpecies count: Int,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        guard count > 0 else { return 0 }
        let drawn = legendMaxHeight(
            screenHeight: screenHeight,
            topInset: topInset,
            namedSpecies: count,
            isAccessibilitySize: isAccessibilitySize
        ) ?? legendNaturalHeight(
            namedSpecies: count,
            isAccessibilitySize: isAccessibilitySize
        )
        return chipRowTop + drawn
    }

    /// **Where the top chrome really ends**, in the screen coordinates `bottomChrome` positions the
    /// recenter control in: the chip row's bottom edge (`topChromeReserved`) plus the legend
    /// below it.
    ///
    /// The `Needs care` toast and the search status line sit in the same stack and are **not**
    /// reserved here. Both are transient — the toast dismisses itself after three seconds and the
    /// status line exists only while a search is running, and a search is the state R25/#143
    /// deliberately lets the top block draw over the bottom one in. Reserving either would come
    /// straight out of `MapLocationNotice`'s budget in the standing state, where they are not on
    /// screen. It is a real gap and it is named rather than papered over: at AX5, with four species
    /// colored *and* the toast up, the legend is pushed down past this bound for those three
    /// seconds. See `docs/ERRATA.md` once the orchestrator splices this branch's pending entry
    /// under its real number at merge.
    static func topChromeBottom(
        screenHeight: CGFloat,
        topInset: CGFloat,
        namedSpecies: Int,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        topChromeReserved(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
            + legendReserved(
                screenHeight: screenHeight,
                topInset: topInset,
                namedSpecies: namedSpecies,
                isAccessibilitySize: isAccessibilitySize
            )
    }

    // MARK: MapKit's compass, and why its room is bought sideways (PR #102)
    //
    // The owner ruled a MapKit-native compass onto screen 01 on 2026-08-21 (RULINGS R80, item 6b;
    // see the compass block in `MapAnnotationLayer.makeUIView`). MapKit draws it in the map's
    // top-**trailing** ornament slot, under all of this screen's chrome, and PR #102's review found
    // it covered by a species legend chip at AX5 — illegible, untappable, and taking the tap for
    // itself: aiming at "put me back to north" applied a species filter and removed most of the
    // pins.
    //
    // The control needs two things and they are bought in two different currencies, because only one
    // of them is free.
    //
    // ── Width, against the legend: free ──────────────────────────────────────────────────────────
    //
    // The legend hangs below the chip row on the same trailing side and is drawn *over* this map, so
    // a chip long enough to reach the trailing edge covers the compass. That half is bought
    // sideways: `legendNaturalHeight` bounds the legend at **one chip per line** already, so
    // narrowing its column can push the drawn legend toward that bound and never past it, and every
    // vertical reservation on this screen is arithmetically unchanged. `MapSpeciesLegend
    // .trailingReserve` is that reserve. Guarded by
    // `AX5ReflowTests.theLegendReservationIsIndependentOfItsWidth`.
    //
    // The enabling half was a real defect of the legend's own, found by the same review: `FlowRow`
    // measured every chip at its *ideal* width and placed it there, so a `Sycamore, London Plane`
    // chip at AX5 drew 446 pt wide inside a 408 pt column on a 440 pt screen — off the trailing edge
    // of the phone. A trailing reserve on a row that overflows its column buys nothing, so
    // `FlowRow.measure(_:within:)` clamps the proposal first.
    //
    // ── Height, against the notice only — and that is the whole of the second half ───────────────
    //
    // A trailing reserve does nothing about `MapLocationNotice`, which is a **full-width** card
    // growing *upward* out of the bottom block. When the visible camera has colored no species — a
    // common state, not an edge case — the legend reserves nothing and the notice's budget runs to
    // the top of the shared pot, straight through where the compass sits. (An earlier draft of this
    // fix placed the compass with no reservation at all and this file's own new guard caught it, 56
    // assertions red.) So the notice is capped to stay below the compass's band, and where that cap
    // would breach `noticeFloor` the compass is not drawn at all.
    //
    // **Where the compass actually is, and why the arithmetic says `+ topInset`.** MapKit places
    // the ornament against `MKMapView.layoutMargins`, and `insetsLayoutMarginsFromSafeArea` ADDS the
    // map's own safe-area top to whatever is written there. So the written margin
    // (`compassLayoutMargin`, the chip row's bottom edge) and the compass's screen y (`compassTop`,
    // that plus `topInset`) are two different numbers, and PR #102's review found this file
    // conflating them. They are separate functions now. Calibration: 219 + 62 = 281 predicted on an
    // iPhone 16 Pro Max at AX5, against 287 measured off the reviewer's screenshot — MapKit's own
    // ~6 pt.
    //
    // **The sum is left standing rather than cancelled, and the reason is what `layoutMargins`
    // *is*.** On an `MKMapView` it is not an ornament-placement knob: it is the map's own content
    // inset, and moving it moves what the camera treats as its centre. Subtracting the safe area
    // here — the obvious repair, and the one PR #102's review asked for — shrinks the effective top
    // from 230 to 168 and therefore moves the map, for every reader, whether or not any given test
    // notices. That is the reason; the test results below are evidence about it, and they are
    // narrower than the effect.
    //
    // **The evidence is width-dependent, and both measurements belong on the record.** On a 402 pt
    // iPhone 16 Pro the subtraction turned
    // `MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack` red **4 runs out
    // of 4** — the pan probe showing the drag reaching the map and the camera settling back on the
    // reader — while a control worktree at `origin/main` passed on that same simulator, and
    // restoring the unsubtracted value turned it green again. On a 440 pt iPhone 16 Pro Max the
    // verifier applied the same subtraction to this same head, confirmed the compass moved 61 pt,
    // and that test went **green 3 runs out of 3**. So the pan guard catches this on some widths
    // and not others; it is not the definition of the problem, and a future reader should not
    // conclude from a green Pro Max run that the subtraction is safe.
    //
    // What the review was actually right about is that the double-count must not be **load-bearing
    // or unnoticed**, and it is neither now: the compass's clearance from the legend is horizontal
    // and exact, not five accidental points of vertical luck, and the sum is written down in
    // `compassTop` and swept by `AX5ReflowTests.theCompassFitsBetweenTheTwoBlocks`.
    //
    // ── And where it does not fit, there is no compass ───────────────────────────────────────────
    //
    // `noticeFloor` is not negotiable: it is what keeps the location notice's `Settings` button
    // fully visible, which is the reader's only remedy for the permission the card is about (RULINGS
    // R53 §6). Where capping the notice under the compass would breach it, the compass yields. On
    // the screens this app runs that is the 667 pt iPhone SE at an accessibility size, and nothing
    // else. It is a computed, arithmetic condition rather than a type-size switch, and it depends
    // only on the screen and the reader's size — never on the camera, so it cannot flicker
    // during a pan.

    /// MapKit's compass ornament, measured off the glass: **44 × 44 pt**, drawn about 5 pt in from
    /// the map's trailing edge (iPhone 16 Pro Max, x 391–435 on a 440 pt screen). A fixed control —
    /// it carries no Dynamic-Type text, so unlike every other reservation in this file it does not
    /// need two buckets.
    static let compassSize: CGFloat = CypressSpacing.minTapTarget

    /// **The trailing strip on screen 01 that belongs to the compass**, and which
    /// `MapSpeciesLegend` is therefore not given.
    ///
    /// The compass plus the same 12 pt rhythm every other gap on this screen uses, which leaves
    /// about 7 pt of visible air between the nearest chip and the compass once MapKit's own ~5 pt
    /// trailing offset is counted. Guarded by
    /// `IdentifyFABReachabilityTests.testTheSpeciesLegendClearsTheCompassColumnAtAX5WithLocationDenied`.
    static let compassColumnReserved: CGFloat = compassSize + chipRowTop

    /// **Whether this screen can seat a compass without breaching the notice's floor.**
    ///
    /// The floor is the line that cannot move — it is what keeps the location notice's `Settings`
    /// button fully visible, and that button is the reader's only remedy for the permission the card
    /// is about (RULINGS R53 §6). So the question is whether the shared pot, less the compass's
    /// band, still covers it. Where it does not, the compass is what yields.
    ///
    /// **Not a function of the camera.** The palette is deliberately not a parameter even though the
    /// cap below interacts with it: a compass that appeared and vanished as the reader panned across
    /// a patch of one species would be worse than one that is simply absent. Screen and type size
    /// only, both of which hold still for a session.
    static func compassIsAffordable(
        screenHeight: CGFloat,
        topInset: CGFloat,
        isAccessibilitySize: Bool
    ) -> Bool {
        screenHeight
            - bottomSlotReservedAbove(isAccessibilitySize: isAccessibilitySize)
            - compassBandBottom(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
            >= noticeFloor(isAccessibilitySize: isAccessibilitySize)
    }

    /// **The layout margin to write into `MKMapView.layoutMargins`** — not the compass's screen y.
    ///
    /// UIKit adds the map's own safe-area top to this (`insetsLayoutMarginsFromSafeArea`), so the
    /// compass lands at `compassTop` below, which is this plus `topInset`. The two are separate
    /// functions because they are separate numbers and conflating them is exactly what PR #102's
    /// review found. See `MapAnnotationLayer.applyCompass` for why the sum is left standing rather
    /// than cancelled: this value is also the map's content inset, and shrinking it moved the
    /// camera enough to turn a pan guard red four times out of four.
    static func compassLayoutMargin(topInset: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        topChromeReserved(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
    }

    /// The y the compass's band ends at — its own bottom edge plus the gap below it.
    static func compassBandBottom(topInset: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        compassLayoutMargin(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
            + topInset
            + compassSize
            + chipRowTop
    }

    /// **Where the compass's top edge actually lands, in screen coordinates** — a whole safe-area
    /// top *below* the chip row's bottom edge, not at it. `nil` where the screen cannot afford the
    /// control at all.
    ///
    /// **That distinction is the correction PR #102's review was about, and this doc had it wrong
    /// too.** `compassLayoutMargin` is the chip row's bottom edge (`topChromeReserved`, 168 pt at a
    /// 62 pt inset on a 402 pt phone at the default size) and it is what gets *written*. UIKit then
    /// adds the map's own safe-area top on the way to the effective margin
    /// (`insetsLayoutMarginsFromSafeArea`), so the compass draws at 230 — measured at 234 on a
    /// verifier's Pro Max and 236 on mine, against a chip row bottom of 168. Writing "the chip row's
    /// own bottom edge" here, as the ruling's call site and an earlier version of this comment both
    /// did, is out by exactly `topInset`.
    ///
    /// This is built from `topChromeReserved` and not `topChromeBottom`: the legend hangs below the
    /// chip row on the same side, but it is held out of the compass's column horizontally
    /// (`compassColumnReserved`) rather than stepped over vertically. The notice is what the
    /// reserved band above keeps off it.
    ///
    /// **Guarded against UIKit rather than against itself.** The `+ topInset` below is the whole
    /// claim, and an assertion written in terms of `compassLayoutMargin` cannot test it — the
    /// sweep's old "the compass starts below the chip row" reduced to `topInset >= 0` and stayed
    /// green with the term deleted. `AX5ReflowTests.theCompassTopIsWhatUIKitActuallyProduces` puts a
    /// real `MKMapView` in a window with a real safe area, writes `compassLayoutMargin`, and asserts
    /// UIKit's own readback equals this function.
    static func compassTop(
        screenHeight: CGFloat,
        topInset: CGFloat,
        isAccessibilitySize: Bool
    ) -> CGFloat? {
        guard compassIsAffordable(
            screenHeight: screenHeight,
            topInset: topInset,
            isAccessibilitySize: isAccessibilitySize
        ) else { return nil }
        // `+ topInset`: the safe area UIKit adds back on top of the written margin. This is the
        // compass's real screen y, and the only number a guard should assert against.
        return compassLayoutMargin(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
            + topInset
    }

    /// The height `MapLocationNotice` may take in the bottom slot before it must scroll instead
    /// of growing past the top of the screen, or up into the top chrome above it (tasks #250, #258).
    /// Conservative rather than exact — it reserves the AX5 heights of the recenter control and the
    /// FAB even when Dynamic Type is nowhere near AX5, because at ordinary sizes the notice never
    /// gets close to this budget regardless, and a budget computed once from constants is simpler
    /// than measuring the controls' actual height on every layout pass for a slot this is the
    /// backstop for, not the primary fit.
    ///
    /// **What is left of `chromeSlackBelowChipRow` once the legend has taken its ceiling** (task
    /// #258). The two are complementary halves of one number, so no arrangement of them can hand
    /// the same point to both blocks.
    ///
    /// **`screenHeight`, not the safe area's height** (task #258). Every other term here is measured
    /// from the top of the *screen* — `topChromeReserved` has `topInset` in it, and
    /// `bottomSlotReservedAbove` ends at `tabBarHeight`, which is `bottomChrome`'s padding from
    /// the bottom of the block it is anchored in, and that block is `MapCanvas`'s `.ignoresSafeArea`
    /// overlay. This subtracted them from `GeometryReader`'s `size.height` instead, which is the
    /// safe area, so it had been ~93 pt conservative on a notched phone the whole time: harmless
    /// while the number being subtracted was 211, and not harmless once the legend's 276 joins it —
    /// the two together leave a *negative* budget out of the safe area's 781 pt and a workable 98 pt
    /// out of the screen's 874. The screen's height needs no measurement: it is the safe area plus
    /// the two insets that bound it, all three of which `MapHomeView`'s root `GeometryReader`
    /// already has.
    ///
    /// Clamped at zero. A budget below zero is not a smaller budget, it is a `frame(maxHeight:)`
    /// SwiftUI is entitled to treat as garbage.
    static func noticeMaxHeight(
        screenHeight: CGFloat,
        topInset: CGFloat,
        namedSpecies: Int,
        isAccessibilitySize: Bool
    ) -> CGFloat {
        let slack = chromeSlackBelowChipRow(
            screenHeight: screenHeight,
            topInset: topInset,
            isAccessibilitySize: isAccessibilitySize
        )
        let afterLegend = slack
            - legendReserved(
                screenHeight: screenHeight,
                topInset: topInset,
                namedSpecies: namedSpecies,
                isAccessibilitySize: isAccessibilitySize
            )
        // **And never up into the compass's band** (PR #102). The two terms above split the pot
        // between the top block's last child and this one, and neither of them knows about a
        // control MapKit draws underneath both. When the camera has colored no species the legend
        // reserves nothing and this card's ceiling is `chipRowTop` below the chip row — straight
        // through the compass. `min` rather than a third subtraction: where the legend is already
        // using that room the notice never reaches it, and the cap costs nothing at all.
        guard compassIsAffordable(
            screenHeight: screenHeight,
            topInset: topInset,
            isAccessibilitySize: isAccessibilitySize
        ) else { return max(0, afterLegend) }
        let belowTheCompass = screenHeight
            - bottomSlotReservedAbove(isAccessibilitySize: isAccessibilitySize)
            - compassBandBottom(topInset: topInset, isAccessibilitySize: isAccessibilitySize)
        return max(0, min(afterLegend, belowTheCompass))
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
