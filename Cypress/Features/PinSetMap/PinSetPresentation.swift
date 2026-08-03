//
//  PinSetPresentation.swift
//  Cypress — Features/PinSetMap
//
//  **NOT SPECIFIED.** ERRATA E129, and E144 for the group of one.
//
//  ── The group of one (E144) ───────────────────────────────────────────────────────────────
//  The project owner, from their own iPhone: *"In almanac under this season need a way to find the
//  tree mentioned. Right now clicking just takes to tree page but I have no idea where tree is"*.
//
//  That is the same sentence E129 answered for the two counted rows, one record smaller, so it gets
//  the same screen rather than a second one. Three things differ and all three are argued where they
//  are made: the camera is the 120 m floor centred on the record rather than a box around a group;
//  the record is drawn **selected**, because a group of one is invisible in a street of thirty; and
//  the rest of the block is drawn behind it as context, which is the one thing this screen reads for
//  itself (`PinSetNeighbours`).
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

    /// The records, in the order they arrived — nearest first, then any context behind them.
    let pins: [TreePin]

    /// The one pin drawn selected, or nil when the map is about all of them equally.
    let focusPinID: UUID?

    /// The opening camera: a box that holds every pin, with room around it.
    let frame: BoundingBox

    /// C1's trailing pill, or nil when the group named no area.
    let neighborhoodName: String?

    /// - Parameter context: records that are on the map but are **not** what the sentence above it
    ///   counts — the rest of the block around a single record the reader asked to be shown. Empty
    ///   for the two counted groups, and empty for a locate map until the read behind it returns.
    ///
    ///   It is a second argument rather than more pins on the `PinSet` for one reason, and it is
    ///   E38's: `PinSet.count` is a claim about how many records there are, `PinSet.isComplete`
    ///   compares the pins against it, and folding scenery into `pins` would make both of those
    ///   sentences false about the two screens that already depend on them.
    init(set: PinSet, context: [TreePin] = [], locale: Locale = .current) {
        self.title = PinSetCopy.title(for: set.subject)
        self.subject = PinSetCopy.subject(for: set, locale: locale)
        self.coverage = PinSetCopy.coverage(for: set, context: context, locale: locale)
        // The set's own records first, and a context pin the set already holds is dropped rather
        // than drawn twice. The order is load-bearing on the way in as well as out: the record the
        // reader asked about must be in the array from the first frame, because the read that
        // fetches its neighbours has not returned yet and a map that flies somewhere and shows
        // nothing for a beat is exactly the failure this screen exists to avoid.
        let known = Set(set.pins.map(\.id))
        self.pins = set.pins + context.filter { !known.contains($0.id) }
        self.focusPinID = set.focusPinID
        // **Around the set, never around the context.** For a group this is the whole group, as it
        // always was. For one record it is `frame(around:)`'s floor — `MapLayout.defaultSpanMetres`,
        // the 120 m ERRATA E12 measured as the scale where San Francisco's street trees stop fusing
        // into a mat — centred on the record itself. Framing the neighbours instead would pull the
        // camera out to whatever the read happened to return and put the subject somewhere off
        // centre, which is the opposite of the ask.
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
        // The row's own title, `Newest neighbors`, for the same reason the two above it are the
        // labels over their blocks: it is the string the reader pressed (ERRATA E182).
        case .newestNeighbors: return AlmanacCopy.newestTitle
        // The record's own display name, carried from the screen the reader pressed the control on.
        // Same rule as the two above it: the title of this screen is a string that already existed
        // and that the reader has just read, rather than one invented at the destination.
        case let .oneRecord(name, _): return name
        }
    }

    /// The row's own sentence, from the row's own function.
    static func subject(for set: PinSet, locale: Locale) -> String {
        switch set.subject {
        case .coverageGap: return AlmanacCopy.coverageTitle(count: set.count, locale: locale)
        case .vacantSites: return AlmanacCopy.vacantTitle(count: set.count, locale: locale)
        // Carried, not rebuilt. `newestSubtitle` needs the leading species and the two other cases
        // here need only a count, so re-deriving it would mean this screen holding a species list
        // whose only job is to agree with the row it came from (ERRATA E182).
        case let .newestNeighbors(sentence): return sentence
        // **The street, because the reader is on foot.** A person holding this screen is trying to
        // walk to the thing, and the address is the one fact that gets them onto the right block
        // without reading the map at all. 8,943 of the seed's rows carry no address; that is said
        // plainly rather than papered over with the neighbourhood, which is already in the pill
        // beside the title and would answer a question nobody asked.
        case let .oneRecord(name, address):
            guard let address, !address.isEmpty else { return noAddress }
            // **Nothing twice.** A vacant site's H1 *is* its street address (`SiteCopy.title`), and a
            // city tree with no species falls back to the same string on the profile, so on those
            // records this line was printing the title again one line below the title. Seen on the
            // simulator: `601 Dolores St` under `601 Dolores St`. An empty string here draws no line
            // at all rather than a paraphrase — the address is already on screen, and saying it
            // differently the second time would be the app filling a slot instead of answering.
            return address == name ? "" : address
        }
    }

    /// What stands in for the street when the city recorded none.
    static let noAddress = "The city recorded no street address for this one."

    // MARK: The control that opens this screen

    /// What the three screens that render one record press to get here (`ShowWhereButton`).
    ///
    /// The owner's own words, near enough: they wrote *"I have no idea where tree is"*. It says
    /// **where** rather than "map", because the map is how the answer is delivered and the question
    /// is about the street; and it cannot be misread as the profile hero's "show me more of this",
    /// which is the one other thing on that screen somebody might press to see.
    ///
    /// One sentence for all three screens, including the memorial and the vacant site: *this* is a
    /// pronoun and takes whatever the record is, where "Show me where this tree is" would be a claim
    /// about 12,518 basins that have no tree in them (ERRATA E107, E113).
    static let showWhereAction = "Show me where this is"

    // MARK: The control that goes back to the subject

    /// It names what it centres on rather than what it looks like, for `MapRecentreCopy.label`'s
    /// reason: a reader who cannot see the crosshair learns nothing from the word "locate".
    static func recentreLabel(_ name: String) -> String { "Center the map on \(name)" }

    static let recentreHint = "Returns to the larger pin at street level"

    /// Said out loud after the press. The map has moved under a VoiceOver reader's finger and
    /// nothing else reports it — `MapRecentreCopy.spokenCentred`'s argument, on the screen next door.
    static let spokenRecentred = "The map is back on it, at street level."

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
    static func coverage(for set: PinSet, context: [TreePin], locale: Locale) -> String {
        guard case let .oneRecord(name, _) = set.subject else {
            return coverage(shown: set.pins.count, of: set.count, locale: locale)
        }
        // **It names the mark, and it names it by the name at the top of the screen.** A selected
        // pin is 1.25× its neighbours (`MapLayout.selectedPinScale`) and that is the app's whole
        // vocabulary for "this one" — a second, louder highlight invented here would be a second
        // vocabulary. What the sentence adds is the thing a size cannot say on its own: which of the
        // pins is the larger one, in words, for a reader who is comparing thirty green dots on one
        // block or who is not looking at the map at all.
        //
        // The second half is only true once the read behind it has returned, so it is only said
        // then. Claiming the block is drawn while it is still one pin would be the same defect at
        // one remove.
        guard !context.isEmpty else { return "The larger pin is \(name)." }
        return "The larger pin is \(name). The rest of the block is drawn around it."
    }

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
