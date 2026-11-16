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
/// `Policy.minimumInterval`**, counted from the start of the last attempt that was not cancelled,
/// whether it worked or not, so panning back and forth does not repeat requests for the same tiles.
///
/// **Passes run one at a time.** A pass that starts while another is still running waits for it
/// to end, then decides which tiles are due. So a tile in flight is never skipped by a second pass
/// that merely saw it marked: the second pass sees what the first one learned. If the first pass
/// was cancelled before its request came back, that tile is not marked, and the second pass asks
/// for it.
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
///   The failed tile counts as attempted, so the next pass skips it and asks for the next tile that
///   is due. **An offline phone therefore sends one request per settled map** (one per pass), until
///   every tile in view has been tried in the last `Policy.minimumInterval`; then it sends none
///   until the interval passes.
/// - **Cancellation** (the map moved on): the pass stops, and the tile in flight is not counted as
///   attempted, so the next refresh asks for it. A page that was written before the pass noticed
///   the cancellation is still counted in the pass's `Outcome`, so the caller can draw it.
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
        /// A viewport touching more tiles than this is zoomed out, and fetches nothing.
        ///
        /// Sixteen, from the owner's ruling of 2026-11-15 ("Neighborhood level": download when
        /// about 2 km is on screen, from the first zoom that draws cluster badges). That zoom is
        /// 15 (`MapViewport.highestClusteringZoom`). Counted with `MapZoom`'s formula, the map's
        /// full screen and the 8 % margin `MapModel.cameraDidChange` adds, on the four agent screens
        /// (390, 402, 420 and 440 pt wide) at the equator, 37.8° N and 64.1° N:
        /// - zoom 15 touches 2 to 8 tiles, so every zoom-15 map fetches;
        /// - a map a quarter step wider (zoom 14.25) touches 8 to 15, so it fetches too;
        /// - the widest zoom-14 map touches 8 to 18, so on the two larger screens some do not;
        /// - zoom 13 touches 32 to 50, so none fetches.
        /// `CommunityFetchZoomTests` pins three of those facts against this number: the most tiles
        /// any zoom-15.0 map and any zoom-14.25 map touches is within it, and the fewest any zoom-13
        /// map touches is above it. The ranges and the zoom-14 row are not pinned.
        public var maxTiles: Int
        /// How long a tile is left alone after an attempt starts, successful or not. A cancelled
        /// attempt does not count.
        public var minimumInterval: TimeInterval
        /// The most pages one tile is followed through in one pass. A page is up to 100 trees, so
        /// this is 1,000 trees per tile per pass; the next pass continues from the stored cursor.
        public var maxPagesPerTile: Int

        public init(maxTiles: Int = 16, minimumInterval: TimeInterval = 120, maxPagesPerTile: Int = 10) {
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
    /// Whether a pass is running, and the passes waiting for it, first come first served. An actor
    /// alone does not keep two passes apart: each `await` inside a pass lets another pass in.
    private var passRunning = false
    private var waitingPasses: [CheckedContinuation<Void, Never>] = []

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
        await beginPass()
        defer { endPass() }
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

    /// Waits until no other pass is running. A pass that ends hands its turn straight to the next
    /// waiting one, so a pass that arrives later cannot slip in between.
    private func beginPass() async {
        guard passRunning else {
            passRunning = true
            return
        }
        await withCheckedContinuation { waitingPasses.append($0) }
    }

    private func endPass() {
        if waitingPasses.isEmpty {
            passRunning = false
        } else {
            waitingPasses.removeFirst().resume()
        }
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
