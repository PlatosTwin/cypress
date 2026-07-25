import Foundation

/// A group of inventory records the almanac counted, carried to a screen that can show them
/// **together** (ERRATA E129).
///
/// ── Why this type exists ──────────────────────────────────────────────────────────────────
/// Screen 12 printed two counts and offered one record each. `Where eyes are needed` said
/// `9 young trees with no visits since planting`, its button said `Walk the nine`, and the button
/// opened *one* tree's profile — so the cold profile it landed on ended with the line "This is the
/// almanac's 'walk the nine' list, one tree at a time", which is the app apologising in copy for a
/// missing destination. `Where a tree could go` (RULINGS R10, ERRATA E121) shipped the same defect
/// four commits later: `1,474 empty planting sites`, tapping through to the nearest basin.
///
/// Neither row answered the question it raised, which is *where*. Both are spatial claims — one of
/// them ("All nine are within a 15-minute walk") is a claim about distance — so the destination is a
/// map, and a map needs the whole group rather than one id.
///
/// ── Why the group travels rather than being re-read ───────────────────────────────────────
/// The destination could resolve the same query again from an id. It must not: the almanac's row has
/// already printed a number, and a second read a second later can disagree with it. Carrying the
/// records the row counted makes the map and the sentence above it the same statement by
/// construction, which is the property that a re-read cannot have.
///
/// ── Why `pins` ────────────────────────────────────────────────────────────────────────────
/// `TreePin` is the app's one existing noun for "a record standing at a coordinate", and it is the
/// only one that covers both of these groups honestly: `TreePin.status` distinguishes a living tree
/// from a mapped basin with nothing in it, and C19 draws each with its own pin (RULINGS R7). Calling
/// the members trees would be the noun-slip ERRATA E107 and E113 spent two rounds removing — 12,518
/// of these records have no tree in them.
public struct PinSet: Hashable, Sendable {

    /// Which of screen 12's blocks this group came from.
    ///
    /// The screen takes its title and its headline sentence from the block, so nothing on the
    /// destination is a new claim: the reader sees the label they tapped and the sentence they
    /// tapped, over a map of what it was counting.
    public enum Subject: Hashable, Sendable {
        /// §4, the coverage gap — the app's only directed ask (D1).
        case coverageGap
        /// `Where a tree could go`, the vacant planting sites (RULINGS R10).
        case vacantSites
    }

    public let subject: Subject

    /// The records on the map, **nearest first**.
    ///
    /// Ordering is load-bearing rather than cosmetic: when this is a page of a larger group, the
    /// sentence over the map says which page it is ("the 20 nearest"), and that sentence is only
    /// true because both reads behind this type order by distance from the reader's fix.
    public let pins: [TreePin]

    /// How many records the neighbourhood holds — the number screen 12 printed.
    ///
    /// **This is a total, never a page size** (ERRATA E38). Both sources prove it: the coverage
    /// group's number is `Series.totalCount`, which is nil unless the read was whole, and the vacant
    /// group's is a `COUNT(*)` over the same predicate the rows came from.
    public let count: Int

    /// The neighbourhood the group is inside, for the header pill. `nil` never happens today — a
    /// group can only be built from a resolved almanac — and is carried as an optional because C1's
    /// pill is optional and an area we could not name must not be named.
    public let neighborhoodName: String?

    /// Whether the map is showing the whole group.
    ///
    /// A comparison rather than a stored flag, and sound because `count` is an independent total
    /// rather than the size of this read. That is the one situation where `Series`' proof idiom —
    /// asking for one row more than you wanted — buys nothing: there is already a number to compare
    /// against.
    public var isComplete: Bool { pins.count >= count }

    public init(subject: Subject, pins: [TreePin], count: Int, neighborhoodName: String?) {
        self.subject = subject
        self.pins = pins
        self.count = count
        self.neighborhoodName = neighborhoodName
    }
}
