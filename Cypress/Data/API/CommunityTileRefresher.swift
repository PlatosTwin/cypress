import Foundation

/// Fills the community cache from `GET /community-trees`, one tile at a time (round C2).
///
/// Round C1 built the cache (`CommunityTreeCacheStore`) and made the map, the shortlist and the
/// profile read it. This is what writes it, so another person's published tree reaches this phone.
/// This header states what the code does and why.
///
/// ── When it runs ──────────────────────────────────────────────────────────────────────────────
///
/// **When the map settles on a viewport**, and only for the zoom-14 tiles that viewport touches.
/// `MapModel` calls it after each read of the map; it never blocks that read, and the map paints
/// from the phone first. A viewport that touches more than `Policy.maxTiles` tiles is a zoomed-out
/// map, and nothing is fetched for it. **A tile is asked at most once per
/// `Policy.minimumInterval`**, whether the last attempt worked or not, so panning back and forth
/// does not repeat requests and an offline phone does not retry on every pan.
///
/// ── What one tile's refresh does ──────────────────────────────────────────────────────────────
///
/// It sends the tile's stored cursor (none for a tile never fetched, which asks for a snapshot),
/// applies the page and its cursor **in one transaction**, and follows `has_more` up to
/// `Policy.maxPagesPerTile` pages. **The cursor moves only when a page was applied**, so a failure
/// at any point leaves the cache and the cursor as they were, and the next refresh asks again from
/// the same place. The cursor, never a cached tree's `updatedAt`, decides what changed: the page's
/// trees are written as served (the S2 day-precision ruling).
///
/// ── Errors ────────────────────────────────────────────────────────────────────────────────────
///
/// - **`validation_failed` on a cursor**: the service no longer accepts it (a rotated key, a cursor
///   from another tile). The tile's cursor and every tree fetched through it are dropped together
///   (`CommunityTreeCacheStore.dropTile`), and the tile is fetched again as a snapshot, once.
/// - **Anything else** (offline, a timeout, a server error, a session that could not be refreshed,
///   a page this build cannot decode): the pass stops. Nothing is written for the tile that failed,
///   and the rest of the viewport waits for the next refresh. The cache keeps drawing what it holds.
/// - **Cancellation** (the map moved on): the pass stops, and the tile in flight is not counted as
///   attempted, so the next refresh asks for it.
///
/// ── What it never does ────────────────────────────────────────────────────────────────────────
///
/// It never evicts a tree except through the service's removal list or a refused cursor. That is
/// C1's rule for this cache (`AppSchema` v23: "No eviction except through the service's removal
/// list, so a visit to a cached tree always finds its tree"). The cache is bounded by the tiles a
/// reader looks at closely, because those are the only tiles fetched.
public actor CommunityTileRefresher {

    /// One page of one tile, from the service: `RemoteAPI.communityTile(_:cursor:)` in the app, a
    /// script in a test.
    public typealias Fetch = @Sendable (CommunityTile, String?) async throws -> CommunityTilePage

    /// The numbers the refresh runs by. The defaults are what ships.
    public struct Policy: Sendable, Equatable {
        /// A viewport touching more tiles than this is zoomed out, and fetches nothing. Nine is a
        /// 3 × 3 block, about 5.8 km across at San Francisco's latitude: the map at zoom 13 or
        /// closer, where community pins are drawn one by one or in small clusters.
        public var maxTiles: Int
        /// How long a tile is left alone after an attempt, successful or not.
        public var minimumInterval: TimeInterval
        /// The most pages one tile is followed through in one pass. A page is up to 100 trees, so
        /// this is 1,000 trees per tile per pass; the next pass continues from the stored cursor.
        public var maxPagesPerTile: Int

        public init(maxTiles: Int = 9, minimumInterval: TimeInterval = 120, maxPagesPerTile: Int = 10) {
            self.maxTiles = maxTiles
            self.minimumInterval = minimumInterval
            self.maxPagesPerTile = maxPagesPerTile
        }
    }

    /// What one pass did, in rows, so a caller or a test can check it rather than assume it.
    public struct Outcome: Sendable, Equatable {
        public enum Ending: Sendable, Equatable {
            /// Every tile due for a refresh was refreshed.
            case finished
            /// The viewport touched more than `Policy.maxTiles` tiles. Nothing was asked.
            case tooManyTiles
            /// A request failed; the pass stopped there and nothing was written for that tile.
            case stoppedOnError
            /// The task was cancelled.
            case cancelled
        }

        public var ending: Ending = .finished
        /// The tiles whose refresh completed, in the order they were asked.
        public var tilesRefreshed: [String] = []
        /// Trees written or refreshed in the cache.
        public var stored: Int = 0
        /// Cached trees a removal list dropped.
        public var removed: Int = 0
        /// Cached trees dropped with a refused cursor.
        public var dropped: Int = 0

        /// Whether the cache changed, which is when the map has something new to draw.
        public var changedCache: Bool { stored + removed + dropped > 0 }
    }

    private let queue: DatabaseQueue
    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private let policy: Policy
    private var lastAttempt: [CommunityTile: Date] = [:]

    public init(
        queue: DatabaseQueue,
        policy: Policy = Policy(),
        now: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping Fetch
    ) {
        self.queue = queue
        self.policy = policy
        self.now = now
        self.fetch = fetch
    }

    /// Refreshes every tile `bounds` touches that is due. See the type's header for the rules.
    public func refresh(covering bounds: BoundingBox) async -> Outcome {
        guard let tiles = CommunityTile.covering(bounds, limit: policy.maxTiles) else {
            return Outcome(ending: .tooManyTiles)
        }
        var outcome = Outcome()
        for tile in tiles {
            if Task.isCancelled {
                outcome.ending = .cancelled
                break
            }
            let moment = now()
            if let last = lastAttempt[tile], moment.timeIntervalSince(last) < policy.minimumInterval {
                continue
            }
            // Recorded before the request, so a second pass that starts while this one waits on
            // the network does not ask for the same tile again.
            lastAttempt[tile] = moment
            do {
                try await refresh(tile, into: &outcome)
                outcome.tilesRefreshed.append(tile.path)
            } catch {
                if Task.isCancelled || error is CancellationError {
                    // Not an attempt: nothing was learned, so the next pass asks again.
                    lastAttempt[tile] = nil
                    outcome.ending = .cancelled
                } else {
                    outcome.ending = .stoppedOnError
                }
                break
            }
        }
        return outcome
    }

    /// One tile: its pages, each applied with its cursor in one transaction.
    private func refresh(_ tile: CommunityTile, into outcome: inout Outcome) async throws {
        let cache = CommunityTreeCacheStore()
        let key = tile.path
        var cursor = try await queue.read { connection in
            try cache.cursor(tile: key, connection: connection)
        }
        var tookFreshSnapshot = false
        var pages = 0
        while pages < policy.maxPagesPerTile {
            try Task.checkCancellation()
            let page: CommunityTilePage
            do {
                page = try await fetch(tile, cursor)
            } catch APIError.validationFailed where cursor != nil && !tookFreshSnapshot {
                // The service refused the cursor. The cursor and the trees fetched through it go
                // together, so a removal missed while the cursor was bad cannot leave a pin
                // standing, and the tile is asked again from nothing (`server/testdata/README.md`).
                outcome.dropped += try await queue.write { connection in
                    try cache.dropTile(key, connection: connection)
                }
                cursor = nil
                tookFreshSnapshot = true
                continue
            }
            let moment = now()
            let applied = try await queue.write { connection in
                try cache.apply(
                    tile: key,
                    trees: page.trees,
                    withdrawnTreeIDs: page.withdrawnTreeIDs,
                    nextCursor: page.nextCursor,
                    at: moment,
                    connection: connection
                )
            }
            pages += 1
            outcome.stored += applied.stored
            outcome.removed += applied.removed
            guard page.hasMore else { return }
            cursor = page.nextCursor
        }
    }
}
