import Foundation

/// A group of inventory records the almanac counted, carried to a screen that can show them
/// **together** (ERRATA E129).
///
/// ── Why this type exists ──────────────────────────────────────────────────────────────────
/// Screen 12 printed two counts and offered one record each. `Where eyes are needed` said
/// `9 young trees with no visits since planting`, its button said `Walk the nine`, and the button
/// opened *one* tree's profile — so the cold profile it landed on ended with the line "This is the
/// almanac's 'walk the nine' list, one tree at a time", which is the app apologizing in copy for a
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

        /// §2 row 3, `Newest neighbors` — this spring's plantings (ERRATA **E182**).
        ///
        /// The owner, walking the app: *"Clicking on newest neighbors on neighborhood almanac should
        /// show them on the map."* It was the last counted row on screen 12 that named a group and
        /// went nowhere, which is E129's defect and E144's, surviving on the one row neither entry
        /// happened to touch. It arrives here rather than at a fourth destination for exactly the
        /// reason those two arrived here: the question a count of trees raises is *where*, and this
        /// app answers that in one place.
        ///
        /// `sentence` is carried, not re-derived, for `.oneRecord`'s reason. The row's subtitle is
        /// assembled by `AlmanacCopy.newestSubtitle` out of a species list that this type does not
        /// hold and should not learn to hold; re-deriving it here would be a second read that can
        /// disagree with the row the reader just pressed.
        case newestNeighbors(sentence: String)
        /// **One record, because the reader asked where it is** (ERRATA E144).
        ///
        /// A group of one, which is what makes it belong here rather than in a screen of its own.
        /// The almanac, My Grove, the journal, the species list and search all name records and all
        /// hand the reader to a page that never says where the thing is; the answer to *where* is a
        /// map with the record on it, which is the answer E129 already built for the two counted
        /// rows. A second map screen for a group of one would be two answers to one question, and
        /// they would drift.
        ///
        /// The two strings are carried rather than re-derived: `name` is the display name the
        /// reader tapped, by whatever precedence the surface they came from used, and `address` is
        /// the street the city recorded, or nil. Deriving either here would mean a second read that
        /// can disagree with the screen the reader is looking at — the argument this whole type is
        /// built on.
        case oneRecord(name: String, address: String?)
    }

    public let subject: Subject

    /// The records on the map, **nearest first**.
    ///
    /// Ordering is load-bearing rather than cosmetic: when this is a page of a larger group, the
    /// sentence over the map says which page it is ("the 20 nearest"), and that sentence is only
    /// true because both reads behind this type order by distance from the reader's fix.
    public let pins: [TreePin]

    /// How many records the neighborhood holds — the number screen 12 printed.
    ///
    /// **This is a total, never a page size** (ERRATA E38). Both sources prove it: the coverage
    /// group's number is `Series.totalCount`, which is nil unless the read was whole, and the vacant
    /// group's is a `COUNT(*)` over the same predicate the rows came from.
    public let count: Int

    /// The neighborhood the group is inside, for the header pill. `nil` never happens today — a
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

    /// The one pin this set is *about*, when it is about one.
    ///
    /// Derived rather than stored, which is what makes it impossible to hold a focus that is not in
    /// the set — the defect a second `UUID` field would have invited. `.oneRecord` is built from
    /// exactly one pin, so `first` is that pin; the two counted groups are about all of their pins
    /// equally and have no focus at all.
    public var focusPinID: UUID? {
        guard case .oneRecord = subject else { return nil }
        return pins.first?.id
    }

    /// One record, asked about by name (ERRATA E144).
    ///
    /// `count` is 1 because there is one, and `isComplete` is therefore true: the map is showing the
    /// whole of what the sentence above it claims. Any other record drawn beside it is context and
    /// travels separately — see `PinSetPresentation.init(set:context:locale:)` — precisely so that
    /// this type keeps meaning "the records the sentence counts" (ERRATA E38).
    public static func locate(
        _ pin: TreePin,
        name: String,
        address: String?,
        neighborhoodName: String?
    ) -> PinSet {
        PinSet(
            subject: .oneRecord(name: name, address: address),
            pins: [pin],
            count: 1,
            neighborhoodName: neighborhoodName
        )
    }

    /// One record, out of the payload the screen asking is already holding.
    ///
    /// The three screens a record can be rendered on — the profile, the memorial, the vacant site —
    /// all derive from a `TreeProfile` and all now offer this, so the conversion into the map's
    /// vocabulary is written once. Three copies of it is how a memorial comes to be drawn with a
    /// living tree's pin (RULINGS R7) on one screen and not on another.
    ///
    /// - Parameter name: the display name the reader is looking at. It is a parameter rather than
    ///   something derived here because each of the three screens has its own precedence for it —
    ///   a given name on 03, the street address on a site — and this is the one place that must not
    ///   have a fourth opinion.
    public static func locate(_ profile: TreeProfile, name: String) -> PinSet {
        locate(
            TreePin(
                id: profile.tree.id,
                coordinate: profile.tree.coordinate,
                status: profile.tree.status,
                source: profile.tree.source,
                verificationState: profile.tree.verificationState,
                speciesID: profile.tree.speciesCurrentID
            ),
            name: name,
            address: profile.tree.address,
            neighborhoodName: profile.neighborhoodName
        )
    }

    public init(subject: Subject, pins: [TreePin], count: Int, neighborhoodName: String?) {
        self.subject = subject
        self.pins = pins
        self.count = count
        self.neighborhoodName = neighborhoodName
    }
}
