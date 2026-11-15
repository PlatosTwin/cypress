import Foundation

// The client-side shapes of the community-tree reads (round C2, the sync down): a calendar day, a
// tile, one page of a tile, and a tree's public history. The wire forms are in `RemoteWire.swift`;
// the contract they follow is `server/testdata/README.md`, "The community-tree reads".

// MARK: - A calendar day

/// A date with no time and no zone: a year, a month and a day in the Gregorian calendar.
///
/// **Two things on the community wire are calendar days and travel as instants.** A community
/// tree's `createdAt` and `updatedAt`, and a history event's `occurred_at`, are sent as midnight UTC
/// of the day (the S2 day-precision ruling). A photograph's `captured_on` is sent as `YYYY-MM-DD`
/// (decision 14a). Formatted in the reader's own zone, midnight UTC is the day before anywhere in
/// the Americas, so a `Date` is the wrong type to hold either. This type holds the day itself, and
/// a surface formats it without consulting any zone.
public struct CalendarDay: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Nil for a day that does not exist (February 30th, month 13).
    public init?(year: Int, month: Int, day: Int) {
        let calendar = Self.utcGregorian
        guard let instant = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        // `Calendar` rolls an impossible day over into the next month rather than refusing it.
        guard parts.year == year, parts.month == month, parts.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`, exactly, as `captured_on` travels. Nil for anything else.
    public init?(isoDate: String) {
        let parts = isoDate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The **UTC** day an instant falls on. This is how a community-tree date that the service
    /// sent as midnight UTC becomes the day it names, in every reader's zone.
    public init(utcDayOf instant: Date) {
        let parts = Self.utcGregorian.dateComponents([.year, .month, .day], from: instant)
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    /// `YYYY-MM-DD`.
    public var isoDate: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public var description: String { isoDate }

    /// Noon of this day in `zone`: an instant that every formatter set to `zone` renders as this
    /// day. Noon rather than midnight, so a daylight-saving change on the day cannot move it across
    /// a day boundary.
    public func midday(in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return calendar.date(from: components) ?? Self.utcGregorian.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// The instant nearest to `instant` that `zone` renders as this day: `instant` itself when it
    /// already falls on this day in `zone`, else the first second of the day (when `instant` is
    /// earlier) or its last second (when it is later). A photograph dated this way prints as this
    /// day and keeps its place among other photographs of the same day wherever it can.
    public func instant(nearest instant: Date, in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let noon = midday(in: zone)
        let start = calendar.startOfDay(for: noon)
        guard let next = calendar.date(byAdding: .day, value: 1, to: start) else { return noon }
        let last = next.addingTimeInterval(-1)
        if instant < start { return start }
        if instant > last { return last }
        return instant
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

// MARK: - A tile

/// One tile of the community layer: zoom 14 in the web-map ("slippy") scheme every basemap uses.
///
/// The service answers `GET /community-trees?tile=14/x/y` at zoom 14 only (`communityTileZoom` in
/// `server/internal/api/community_reads.go`). A tile is about 1.9 km across at San Francisco's
/// latitude (40,075 km × cos 37.8° ÷ 16,384). Membership is half-open, west and north edges inclusive, which is what `floor` in the
/// standard formula gives, so a point on a shared edge belongs to exactly one tile.
public struct CommunityTile: Hashable, Sendable, Comparable, CustomStringConvertible {
    public static let zoom = 14
    /// Tiles per side at `zoom`.
    public static let side = 1 << zoom

    /// Web Mercator's latitude limit. A latitude past it has no tile row.
    static let maxLatitude = 85.05112878

    public let x: Int
    public let y: Int

    /// Nil outside the grid.
    public init?(x: Int, y: Int) {
        guard (0..<Self.side).contains(x), (0..<Self.side).contains(y) else { return nil }
        self.x = x
        self.y = y
    }

    /// The tile a point falls in. A latitude beyond Web Mercator's limit is clamped to the edge row.
    public init(containing coordinate: Coordinate) {
        let n = Double(Self.side)
        let latitude = min(max(coordinate.latitude, -Self.maxLatitude), Self.maxLatitude)
        let radians = latitude * .pi / 180
        let column = Int(((coordinate.longitude + 180) / 360 * n).rounded(.down))
        let row = Int(((1 - asinh(tan(radians)) / .pi) / 2 * n).rounded(.down))
        self.x = min(max(column, 0), Self.side - 1)
        self.y = min(max(row, 0), Self.side - 1)
    }

    /// The route's spelling, `14/x/y`, which is also the service's canonical echo and the key the
    /// cache stores a cursor under.
    public var path: String { "\(Self.zoom)/\(x)/\(y)" }

    public var description: String { path }

    /// Every tile a box touches, west to east and north to south — or nil when there are more
    /// than `limit`, so a zoomed-out map never builds a list of thousands only to discard it.
    public static func covering(_ bounds: BoundingBox, limit: Int) -> [CommunityTile]? {
        let northWest = CommunityTile(
            containing: Coordinate(latitude: bounds.maxLatitude, longitude: bounds.minLongitude)
        )
        let southEast = CommunityTile(
            containing: Coordinate(latitude: bounds.minLatitude, longitude: bounds.maxLongitude)
        )
        // A box that crosses the antimeridian would come back with the columns reversed. No city
        // Cypress serves is near it, so such a box is answered with nothing rather than with the
        // whole width of the world.
        guard southEast.x >= northWest.x, southEast.y >= northWest.y else { return [] }
        let columns = southEast.x - northWest.x + 1
        let rows = southEast.y - northWest.y + 1
        guard columns * rows <= limit else { return nil }
        var tiles: [CommunityTile] = []
        for y in northWest.y...southEast.y {
            for x in northWest.x...southEast.x {
                if let tile = CommunityTile(x: x, y: y) { tiles.append(tile) }
            }
        }
        return tiles
    }

    public static func < (lhs: CommunityTile, rhs: CommunityTile) -> Bool {
        (lhs.y, lhs.x) < (rhs.y, rhs.x)
    }
}

// MARK: - One page of a tile

/// One answer of `GET /community-trees`: the trees it served, the ids it reports as removed, and
/// the cursor to send next time.
public struct CommunityTilePage: Hashable, Sendable {
    /// The service's canonical spelling of the tile.
    public let tile: String
    /// Published community trees. **A tree here can lie outside the tile** (a pin moved out of it
    /// after going live), so a reader keys on `Tree.id` and never on the tile.
    public let trees: [Tree]
    /// Trees that were public and are not now. Ids from anywhere in the world: an erased tree's
    /// tombstone carries no position, so every tile reports it.
    public let withdrawnTreeIDs: [UUID]
    /// Sealed and opaque. Stored and sent back unchanged, never parsed.
    public let nextCursor: String
    /// True only when the page overflowed **and** the cursor moved, so a loop on it ends.
    public let hasMore: Bool

    public init(tile: String, trees: [Tree], withdrawnTreeIDs: [UUID], nextCursor: String, hasMore: Bool) {
        self.tile = tile
        self.trees = trees
        self.withdrawnTreeIDs = withdrawnTreeIDs
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

// MARK: - A tree's public history

/// `GET /trees/{id}/history`: a community tree's public record, newest first, with no actor.
///
/// Carried through the data layer for the round that draws it (C3). Nothing in this round draws
/// it. It starts where the tree went live (decision 13), so a move made while the tree was private
/// is never in it.
public struct CommunityTreeHistory: Hashable, Sendable {

    /// What happened. **Tolerant**: the service serves an allow-list that can widen, and a kind
    /// this build does not know must not fail the whole history (`community_reads.go`).
    public enum Kind: Hashable, Sendable {
        /// The tree was added: dated by the day its adder's phone added it (the owner's ruling of
        /// 2026-11-15), and placed at the position it held when it went live. The service serves
        /// its `published` event under this name.
        case added
        case locationCorrected
        case speciesNamed
        case speciesCorrected
        case unrecognized(String)

        init(wire: String) {
            switch wire {
            case "added": self = .added
            case "location_corrected": self = .locationCorrected
            case "species_named": self = .speciesNamed
            case "species_corrected": self = .speciesCorrected
            default: self = .unrecognized(wire)
            }
        }
    }

    /// How a position was arrived at, tolerant for `Kind`'s reason.
    public enum Placement: Hashable, Sendable {
        case known(TreePlacement)
        case unrecognized(String)

        init(wire: String) {
            self = TreePlacement(rawValue: wire).map(Placement.known) ?? .unrecognized(wire)
        }
    }

    public struct Event: Hashable, Sendable, Identifiable {
        public let id: UUID
        public let kind: Kind
        /// **A calendar day**, never an instant. The service sends midnight UTC of the day.
        public let day: CalendarDay
        public let fromCoordinate: Coordinate?
        public let toCoordinate: Coordinate?
        public let fromSpeciesID: UUID?
        public let toSpeciesID: UUID?
        public let placement: Placement?

        public init(
            id: UUID,
            kind: Kind,
            day: CalendarDay,
            fromCoordinate: Coordinate? = nil,
            toCoordinate: Coordinate? = nil,
            fromSpeciesID: UUID? = nil,
            toSpeciesID: UUID? = nil,
            placement: Placement? = nil
        ) {
            self.id = id
            self.kind = kind
            self.day = day
            self.fromCoordinate = fromCoordinate
            self.toCoordinate = toCoordinate
            self.fromSpeciesID = fromSpeciesID
            self.toSpeciesID = toSpeciesID
            self.placement = placement
        }
    }

    public let treeID: UUID
    /// Newest first, as served.
    public let events: [Event]
    /// False when the service capped the list (200 events).
    public let isComplete: Bool

    public init(treeID: UUID, events: [Event], isComplete: Bool) {
        self.treeID = treeID
        self.events = events
        self.isComplete = isComplete
    }
}
