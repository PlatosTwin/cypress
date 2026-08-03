//
//  VisitPinAdjustPresentation.swift
//  Cypress — Features/Visit
//
//  **NOT SPECIFIED.** The argument for what this screen is, and which parts of it are mine, is here;
//  `VisitPinAdjustView` only draws it.
//
//  ── Why the screen exists ─────────────────────────────────────────────────────────────────
//  `VisitAddTreeModel.add()` took `location.fix.coordinate` verbatim, and `VisitAddTreeView`'s
//  footnote said so out loud: "the coordinate is the phone's current fix". That was deliberate and it
//  was too narrow, and the project owner said why: you photograph a tree from across the street, from
//  a car, from a window; a fix in a San Francisco street canyon is routinely 20–40 m off the truth;
//  and a whole row of trees photographed from one standing spot all land on one point, where the 10 m
//  dedupe then refuses every tree after the first. Three different ways of ending up with a record
//  whose coordinate is not the tree's.
//
//  ── What is invented, and what it is borrowed from ────────────────────────────────────────
//  `docs/ARCHITECTURE.md` rule 8: a screen in neither SCREENS.md nor BUILD-PLAN §9 is not specified,
//  must say so, and must follow the nearest specified thing rather than invent one. There is no mock
//  for placing a pin. The nearest built thing is `PinSetMapView` (ERRATA E129) — a focused MapKit
//  screen owned by one feature, drawing the reader's fix as the GPS dot, with a header, two lines of
//  prose above the map, and the composition root resolving what anything on it means. This screen is
//  that screen's shape with a different subject, and it shares its basemap (`MapKitBasemap`), its
//  wash, its C1 header and its statement-then-qualifier pair of sentences.
//
//  Four decisions are mine and each is argued where it is made:
//
//  1. **The pin is the center of the map, and the map moves under it.** See `VisitPinAdjustView`.
//  2. **A pin may not go more than `radiusM` from the fix.** See `radiusM`.
//  3. **The bound is stated continuously, not only when it is hit.** See `VisitPinAdjustPresentation`.
//  4. **The keyboard-and-VoiceOver path is four nudge buttons, and a nudge that would leave the
//     circle is refused out loud rather than clamped.** See `nudge(_:from:towards:)`.
//
//  No SwiftUI in this file, so every sentence the screen says and every meter it measures is testable
//  without a renderer (`CypressTests/PinAdjustTests.swift`).
//

import Foundation

// MARK: - The rules

/// The geometry and the limits of moving a community tree's pin.
///
/// A separate namespace from `VisitPinAdjustPresentation` because these are the *rules*, which the
/// model enforces on the add path, and the presentation is the *sentences*, which only the screen
/// reads. `VisitAddTreeModel` must be able to refuse an out-of-range coordinate without building a
/// presentation to ask it.
enum VisitPinAdjust {

    /// **How far the pin may travel from the fix: 75 m.**
    ///
    /// An unbounded pin is not a placement affordance, it is a way to add a tree to a street you have
    /// never been on — somebody in Oakland could drop one in the Mission — and every record this
    /// screen writes is `community, unverified` with no second pair of eyes on it. So there has to be
    /// a number, and the number has to be defended rather than picked.
    ///
    /// It is set by what the reader can actually be looking at while they move it, which is the whole
    /// premise: the tree is in front of you and the pin is not.
    ///
    /// - The two errors it must absorb are the ones the owner named, and they compose. A street-canyon
    ///   fix is off by up to about 40 m; a tree photographed from the far curb is another 21 m away,
    ///   which is San Francisco's standard 68'9" right-of-way, building face to building face. 61 m
    ///   of honest displacement, and 75 leaves a little over rather than exactly enough.
    /// - It is also about half a block face, so the third case works: standing mid-block and
    ///   photographing a row of street trees 6–10 m apart (D6), every tree either side of you is
    ///   reachable without walking.
    /// - And it stops well short of a distance at which you are placing a tree you cannot see. A block
    ///   away is two or three of these; at that range you are pointing at a rooftop on a map, not at a
    ///   trunk, and the record would be a guess wearing a coordinate.
    ///
    /// It is deliberately far larger than `TreeDraft.proximityDedupeRadiusM`, and that ordering is
    /// load-bearing rather than incidental: moving a pin *onto* a tree already on record still trips
    /// the 10 m refusal, because the dedupe runs on whatever coordinate the draft carries. Widening
    /// the pin's reach does not widen the hole in the dedupe — it makes the dedupe reachable, which is
    /// what the row-of-trees case needed.
    static let radiusM: Double = 75

    /// Half a meter of slack on the bound.
    ///
    /// The screen states the pin's distance to the whole meter, so a bound that refused at 75.0004 m
    /// would be refusing a spot the screen is calling `75 m` — which is a bug report about a limit
    /// that lies. Fifteen 5 m nudges land within a millimeter of 75 m and must be accepted; nothing a
    /// finger can do lands in the half-meter band this opens up and is meaningfully different from the
    /// limit itself.
    static let boundToleranceM: Double = 0.5

    /// One press of a nudge control: 5 m.
    ///
    /// The resolution the task actually has. D6 puts street trees 6–10 m apart, so a step of 5 m is
    /// the coarsest one that can still separate a tree from its neighbor, and the finest one that
    /// reaches the 75 m limit in a countable number of presses (fifteen).
    static let nudgeStepM: Double = 5

    /// Below this, a pin is the fix.
    ///
    /// A reader who opens the map, looks, and leaves the pin where it was has not placed anything, and
    /// recording that as a reader-placed coordinate would overstate what they did. One meter is under
    /// the width of the pin's own hit area at any zoom this screen opens at, so it is not a distance
    /// anybody can aim at on purpose.
    static let fixToleranceM: Double = 1

    /// Whether a coordinate is somewhere this screen will let a tree be recorded.
    static func isWithinBound(_ coordinate: Coordinate, of anchor: Coordinate) -> Bool {
        coordinate.distance(to: anchor) <= radiusM + boundToleranceM
    }

    /// The four directions a nudge control moves the pin in. Clockwise from north, which is the order
    /// they are drawn in and the order a compass rose is read in.
    enum Direction: String, CaseIterable {
        case north, east, south, west

        /// Meters north and east. South and west are the same step with the sign flipped rather than
        /// separate arithmetic, so the four cannot come to disagree about the size of a step.
        var step: (northM: Double, eastM: Double) {
            switch self {
            case .north: return (nudgeStepM, 0)
            case .south: return (-nudgeStepM, 0)
            case .east: return (0, nudgeStepM)
            case .west: return (0, -nudgeStepM)
            }
        }
    }

    /// Meters in one degree of latitude, **on the sphere `Coordinate.distance` measures with**.
    ///
    /// `π · 6,371,008.8 / 180`, where the radius is the mean Earth radius `Coordinate.distance` uses
    /// (`Core/Models/Geometry.swift`).
    ///
    /// Deliberately *not* the 111,320 that `BoundingBox(around:radiusM:)` and
    /// `snappedToPublicPhotoGrid` use. Those two are pre-filters and grids, where being a tenth of a
    /// percent generous costs nothing; this one has to agree with the ruler, because the same meter
    /// appears on both sides of one comparison — the step that moves the pin and the distance that
    /// decides whether the pin is still inside the circle. With 111,320 a 5 m nudge measures 4.994 m,
    /// fifteen of them land 84 mm short of the limit, and the screen ends up printing `75 m` beside a
    /// pin that is not there. The discrepancy is far too small to matter to a tree and exactly large
    /// enough to matter to an assertion, which is how it was found.
    static let metersPerDegreeLatitude: Double = .pi * 6_371_008.8 / 180

    /// A coordinate displaced by a number of meters north and east.
    ///
    /// The flat approximation. Over the 75 m this screen works in the error against a proper geodesic
    /// is under a millimeter, six orders of magnitude below the accuracy of the fix it is measured
    /// from — and the pure-north and pure-east cases a nudge produces are exact.
    static func offset(_ origin: Coordinate, northM: Double, eastM: Double) -> Coordinate {
        // cos() collapses toward the poles; the floor keeps the step finite there, exactly as
        // `BoundingBox(around:radiusM:)` does.
        let cosLatitude = max(cos(origin.latitude * .pi / 180), 0.000_01)
        return Coordinate(
            latitude: origin.latitude + northM / metersPerDegreeLatitude,
            longitude: origin.longitude + eastM / (metersPerDegreeLatitude * cosLatitude)
        )
    }

    /// Where one press of a nudge control puts the pin, or `nil` when it would leave the circle.
    ///
    /// **Refused rather than clamped, and the two are not the same thing.** Clamping would slide the
    /// pin sideways along the boundary — press *north* at 74 m north-east and the pin moves *east* —
    /// which is a control doing something other than what it says. Refusing leaves the pin where the
    /// reader put it and lets the screen say why nothing happened, which is the half that matters: a
    /// pin that silently stops moving is the bug report this whole bound would otherwise generate.
    ///
    /// A continuous drag is the opposite case and gets the opposite treatment — see
    /// `VisitPinAdjustView`. Fighting a pan mid-gesture is not an option, so there the pin goes where
    /// the finger goes and the screen refuses the *confirm* instead. Both paths state the limit.
    static func nudge(_ pin: Coordinate, towards direction: Direction, from anchor: Coordinate) -> Coordinate? {
        let step = direction.step
        let moved = offset(pin, northM: step.northM, eastM: step.eastM)
        return isWithinBound(moved, of: anchor) ? moved : nil
    }

    /// The center of a viewport, which is where the pin is.
    ///
    /// The conversion lives here rather than on `BoundingBox` because this screen is its only caller,
    /// for the reason `PinSetPresentation` gives for keeping its own inverse local: adding it to a
    /// type the whole data layer shares would be a change to that type's surface for one use.
    static func center(of box: BoundingBox) -> Coordinate {
        Coordinate(
            latitude: (box.minLatitude + box.maxLatitude) / 2,
            longitude: (box.minLongitude + box.maxLongitude) / 2
        )
    }
}

// MARK: - What the screen says

/// The two sentences above the map, and the one the pin itself speaks.
///
/// Derived from exactly two coordinates — where the phone says you are, and where the pin is — so
/// there is no state here that can drift out of step with what is drawn.
struct VisitPinAdjustPresentation: Equatable {

    /// Meters from the fix to the pin.
    let distanceM: Double

    /// The pin has not been moved anywhere the record would notice.
    let isAtFix: Bool

    /// The pin is somewhere a tree may be recorded.
    let isWithinBound: Bool

    /// The claim: where the pin is, relative to the reader. `PinSetPresentation.subject`'s slot.
    let placement: String

    /// The qualifier: the rule that governs the claim above it. `PinSetPresentation.coverage`'s slot,
    /// and it is here for the same reason that one is — a statement whose limits are not stated in the
    /// same breath is a statement that will surprise somebody.
    ///
    /// **It draws whether or not the limit has been reached**, which is the decision. A circle drawn
    /// on the map would show where the wall is; a sentence that names the distance *and* the limit
    /// every time tells the reader where they are, which is the thing they are actually deciding
    /// about, and it is the only form of it a VoiceOver user can read. (A drawn circle would also be
    /// wrong the moment the map is rotated, which `MapKitBasemap` permits.)
    let rule: String

    init(anchor: Coordinate, pin: Coordinate) {
        let distance = pin.distance(to: anchor)
        self.distanceM = distance
        self.isAtFix = distance < VisitPinAdjust.fixToleranceM
        self.isWithinBound = VisitPinAdjust.isWithinBound(pin, of: anchor)
        self.placement = VisitPinAdjustCopy.placement(distanceM: distance, from: anchor, to: pin)
        self.rule = isWithinBound ? VisitPinAdjustCopy.withinLimit : VisitPinAdjustCopy.pastLimit
    }
}

// MARK: - Copy

/// Every string this screen renders. **None of it is verbatim from a mock** — there is no mock — so
/// each one is here to be argued with in one place, and each states a fact and stops
/// (ARCHITECTURE §5.7).
enum VisitPinAdjustCopy {

    /// The C1 title, and the label of the control that opens it, deliberately the same words. Screen
    /// 02's button says "Add this tree" and the screen it opens is called "Add this tree"; the same
    /// rule applies here, so nobody has to work out that the thing they pressed and the thing they
    /// landed on are one act.
    static let title = "Move the pin"

    /// The add screen's control. See `title`.
    static let openAction = title

    /// The confirm. Not "Save" and not "Add this tree": this screen writes nothing, it hands a
    /// coordinate back to the screen that does, and a CTA promising a save that has not happened is
    /// the sort of thing somebody presses and then goes to look for a tree that is not there.
    static let confirm = "Use this spot"

    /// Undo, in one press, without having to aim.
    static let recenter = "Back to where you are standing"

    /// The micro-label over the nudge controls, so four compass letters read as a control rather than
    /// as a legend.
    static let nudgeLabel = "NUDGE THE PIN · 5 M"

    /// The four nudge controls, **spoken**. Spelled out rather than `N`/`S`/`E`/`W`, because a
    /// VoiceOver user hears a bare `N` as the letter and a bare `E` as the start of a word.
    static func nudge(_ direction: VisitPinAdjust.Direction) -> String {
        "Move the pin \(direction.rawValue)"
    }

    /// The four nudge controls, **drawn**. `VisitBearing.compassPoints`' own vocabulary, and all that
    /// fits four across at the gutter's width. The spoken form above is what an assistive technology
    /// reads instead.
    static func nudgeGlyph(_ direction: VisitPinAdjust.Direction) -> String {
        switch direction {
        case .north: return "N"
        case .south: return "S"
        case .east: return "E"
        case .west: return "W"
        }
    }

    /// The pin's own accessibility label. The value beside it is `placement`.
    static let pinLabel = "This tree's pin"

    /// `Right where you are standing.` / `23 m north-east of where you are standing.`
    ///
    /// The compass point is `VisitBearing`'s, which is screen 02's own bearing arithmetic, spelled
    /// out. Meters are whole numbers for `VisitBearing.label`'s reason: a decimal on a number whose
    /// error bar is the GPS accuracy chip at the top of this screen would be false precision.
    static func placement(distanceM: Double, from anchor: Coordinate, to pin: Coordinate) -> String {
        guard distanceM >= VisitPinAdjust.fixToleranceM else { return atFix }
        let meters = Int(distanceM.rounded())
        let heading = spelledOut(VisitBearing.compass(from: anchor, to: pin))
        return "\(meters) m \(heading) of where you are standing."
    }

    static let atFix = "Right where you are standing."

    /// The qualifier, in both of its two forms.
    static var withinLimit: String {
        "A pin stays within \(Int(VisitPinAdjust.radiusM)) m of your fix, so a tree is only ever "
            + "recorded somewhere you could see it from."
    }

    static var pastLimit: String {
        "That is past the \(Int(VisitPinAdjust.radiusM)) m limit. Bring the pin back before you can "
            + "use this spot."
    }

    /// What a refused nudge says, out loud. See `VisitPinAdjust.nudge(_:towards:from:)` for why a
    /// nudge is refused rather than clamped, and why saying so is the point.
    static var nudgeRefused: String {
        "That is as far as the pin goes — \(Int(VisitPinAdjust.radiusM)) m from where you are standing."
    }

    /// `N` → `north`. Prose, not a mono field: the distance line on screen 02 is `6 m NE` because it
    /// is drawn as a mono readout in a card, and this is a sentence.
    static func spelledOut(_ compass: String) -> String {
        switch compass {
        case "N": return "north"
        case "NE": return "north-east"
        case "E": return "east"
        case "SE": return "south-east"
        case "S": return "south"
        case "SW": return "south-west"
        case "W": return "west"
        case "NW": return "north-west"
        // `VisitBearing.compassPoints` has exactly the eight above. A ninth would be a change there,
        // and returning it unchanged keeps this a sentence rather than a crash.
        default: return compass
        }
    }
}
