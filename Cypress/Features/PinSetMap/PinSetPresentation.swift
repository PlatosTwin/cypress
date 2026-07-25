//
//  PinSetPresentation.swift
//  Cypress — Features/PinSetMap
//
//  **NOT SPECIFIED.** ERRATA E129.
//
//  ── What this screen is, and what it is allowed to be ─────────────────────────────────────
//  `docs/ARCHITECTURE.md` rule 8: a screen or state that is in neither SCREENS.md nor BUILD-PLAN §9
//  is not specified, must say so, and must follow the nearest specified thing rather than invent.
//  There is no mock for "a list of the nine" and no mock for a map of anything except screen 01.
//
//  So the nearest specified thing is **screen 01**, and this screen is as close to it as a pushed
//  screen can be: the same MapKit basemap through `MapKitBasemap`, the same parchment wash, the same
//  C19 pins in the same vocabulary, and a tap on a pin going where a tap on that pin goes on 01
//  (`MapHomeView.route(for:)`). What it does not borrow is 01's chrome — no search, no filter chips,
//  no FAB, no bottom card — because none of those is a thing this screen is about, and 01 draws them
//  because 01 is the whole city.
//
//  Two decisions are mine and are argued where they are made:
//  - the screen's **title is the almanac's own micro-label** for the block that was tapped
//    (`Where eyes are needed` / `Where a tree could go`), so the name of this screen is a specified
//    string rather than one I chose;
//  - it is a **plain column** — header, two lines, map — rather than 01's full-bleed frame with
//    floating chrome. ERRATA E110 is the reason: 01's absolute positions are arithmetic against a
//    safe-area inset that reads 0 when a navigation bar is present, and this screen is pushed onto a
//    stack. A column cannot get that wrong, and the honest sentence about how many records are on
//    the map is the one thing here that must always be legible.
//
//  No SwiftUI in this file, so both the copy and the camera can be tested without a renderer
//  (`CypressTests/PinSetDestinationTests.swift`).
//

import Foundation

/// Everything the map screen draws, derived from one `PinSet`.
struct PinSetPresentation: Equatable {

    /// C1's title — the almanac's own label for the block the reader tapped.
    let title: String

    /// The sentence the row printed, repeated at the top of its own destination: `9 young trees with
    /// no visits since planting`, `1,474 empty planting sites`.
    ///
    /// Repeated rather than restated, and it is the same function that produced it on screen 12, so
    /// the two screens cannot come to disagree about the number. A destination that rephrased the
    /// claim would be a second place for the claim to be wrong.
    let subject: String

    /// What is actually on the map: `All nine are on this map.` or `The 20 nearest are on this map.`
    ///
    /// **This line is ERRATA E38 on this screen.** The count above it is a total the data stands
    /// behind; the pins are sometimes a page of that total, and a page presented as the series is the
    /// defect E38 is named for. So the page's size is stated, in the same breath, every time.
    let coverage: String

    /// The records, in the order they arrived — nearest first.
    let pins: [TreePin]

    /// The opening camera: a box that holds every pin, with room around it.
    let frame: BoundingBox

    /// C1's trailing pill, or nil when the group named no area.
    let neighborhoodName: String?

    init(set: PinSet, locale: Locale = .current) {
        self.title = PinSetCopy.title(for: set.subject)
        self.subject = PinSetCopy.subject(for: set, locale: locale)
        self.coverage = PinSetCopy.coverage(shown: set.pins.count, of: set.count, locale: locale)
        self.pins = set.pins
        self.frame = Self.frame(around: set.pins)
        self.neighborhoodName = set.neighborhoodName
    }

    // MARK: - The camera

    /// The box the map opens on.
    ///
    /// Two rules, and the second is the one that matters. **It holds every pin**, because the whole
    /// promise of this screen is that the group is on it — a camera that framed the nearest three
    /// would reproduce the defect at one remove. And it is **never tighter than screen 01's own
    /// opening view**, `MapLayout.defaultSpanMetres`: below that scale ERRATA E12 measured pins
    /// beginning to fuse into each other, and a group of one would otherwise open at a zoom where
    /// there is nothing on screen but a single pin and no street to place it against.
    ///
    /// The padding is a fraction of the group's own extent rather than a fixed distance, so a group
    /// spread over a neighbourhood and a group on one block both get the same visual margin. It
    /// reuses `BoundingBox.expanded(by:)`, which the map already uses to fetch a little more than the
    /// screen.
    static func frame(around pins: [TreePin]) -> BoundingBox {
        let coordinates = pins.map(\.coordinate)
        guard let first = coordinates.first else {
            // No pins means no group, and the almanac does not build one — but a box has to exist, so
            // it is the city's own default view rather than the null island off the coast of Africa.
            return BoundingBox(around: MapLayout.defaultCentre, radiusM: MapLayout.defaultSpanMetres / 2)
        }

        let enclosing = coordinates.dropFirst().reduce(
            BoundingBox(
                minLatitude: first.latitude,
                maxLatitude: first.latitude,
                minLongitude: first.longitude,
                maxLongitude: first.longitude
            )
        ) { box, coordinate in
            BoundingBox(
                minLatitude: min(box.minLatitude, coordinate.latitude),
                maxLatitude: max(box.maxLatitude, coordinate.latitude),
                minLongitude: min(box.minLongitude, coordinate.longitude),
                maxLongitude: max(box.maxLongitude, coordinate.longitude)
            )
        }.expanded(by: PinSetMetrics.framePadding)

        let floor = BoundingBox(
            around: Coordinate(
                latitude: (enclosing.minLatitude + enclosing.maxLatitude) / 2,
                longitude: (enclosing.minLongitude + enclosing.maxLongitude) / 2
            ),
            radiusM: MapLayout.defaultSpanMetres / 2
        )

        return BoundingBox(
            minLatitude: min(enclosing.minLatitude, floor.minLatitude),
            maxLatitude: max(enclosing.maxLatitude, floor.maxLatitude),
            minLongitude: min(enclosing.minLongitude, floor.minLongitude),
            maxLongitude: max(enclosing.maxLongitude, floor.maxLongitude)
        )
    }
}

// MARK: - Copy

/// This screen's strings. Every one of them is either a specified string from screen 12 or a
/// statement about what is drawn below it.
enum PinSetCopy {

    /// C1's title.
    ///
    /// **The almanac's own micro-labels, verbatim** — `Where eyes are needed` is SCREENS.md 12 §4's
    /// and `Where a tree could go` is R10's, and both are already the name of the thing the reader
    /// tapped. Naming this screen anything else would mean inventing a screen title for a screen the
    /// design has not drawn, when there were two correct ones sitting in the block above the tap.
    static func title(for subject: PinSet.Subject) -> String {
        switch subject {
        case .coverageGap: return AlmanacCopy.coverageLabel
        case .vacantSites: return AlmanacCopy.vacantLabel
        }
    }

    /// The row's own sentence, from the row's own function.
    static func subject(for set: PinSet, locale: Locale) -> String {
        switch set.subject {
        case .coverageGap: return AlmanacCopy.coverageTitle(count: set.count, locale: locale)
        case .vacantSites: return AlmanacCopy.vacantTitle(count: set.count, locale: locale)
        }
    }

    /// How much of the group is on the map (ERRATA E38).
    ///
    /// Three forms and no fourth. `All nine are on this map.` when the map holds the whole group —
    /// spelled out, because §4's own body already writes `All nine are within a 15-minute walk` and
    /// this is the same number in the same register. `It is on this map.` for a group of one, because
    /// "all one" is not a sentence, the same judgement `AlmanacCopy.coverageCTA` makes about "walk
    /// the one". And `The 20 nearest are on this map.` for a page — *nearest* rather than *first*,
    /// which is a fact about the read: both queries behind a `PinSet` order by distance from the
    /// reader's fix, and the sentence would be false if either ever stopped.
    ///
    /// It says what is on the map and stops (ARCHITECTURE §5.7). It does not apologise for the ones
    /// that are not, does not offer to load more, and does not tell anybody to pan.
    static func coverage(shown: Int, of total: Int, locale: Locale) -> String {
        guard shown < total else {
            return total == 1
                ? "It is on this map."
                : "All \(AlmanacCopy.spelledOut(total, locale: locale)) are on this map."
        }
        return "The \(AlmanacCopy.grouped(shown, locale: locale)) nearest are on this map."
    }
}

// MARK: - Screen metrics

/// The one number this screen owns that no component and no other screen already names.
enum PinSetMetrics {
    /// How much room the camera leaves around the group, as a fraction of the group's own extent.
    ///
    /// **NOT SPECIFIED.** 0.25 is a quarter of the spread on each side, which keeps the outermost pin
    /// clear of the frame edge at the aspect ratios a phone actually has — a pin drawn hard against
    /// the edge reads as "there are more of these off screen", which is the one thing this map must
    /// not imply when it is showing the whole group.
    static let framePadding: Double = 0.25
}
