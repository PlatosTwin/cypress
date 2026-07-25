import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The implementation that ships (ARCHITECTURE §4).
///
/// Reads the bundled SF seed, writes to the local database, and drains the outbox into that same
/// local store. The app is fully functional with no network. When the Fastify service exists,
/// `RemoteAPI` implements the same protocol and `LocalAPI` becomes the offline cache behind it —
/// nothing in `Features` changes.
public actor LocalAPI: CypressAPI {
    private let store: CypressStore
    private let treeQueries: TreeQueries?
    private let speciesQueries: SpeciesQueries?
    private let communityTrees = CommunityTreeStore()
    private let contributions = ContributionStore()
    private let groveQueries: GroveQueries?
    private let almanacQueries: AlmanacQueries?
    private let now: @Sendable () -> Date

    /// This installation's device id (D9). Contributions made before sign-in are attributed here.
    public let deviceID: UUID
    /// The signed-in user, when there is one.
    public private(set) var userID: UUID?
    /// The signed-in account's role (ERRATA E124-B). `.member` until promoted; a lead
    /// (`canConfirmReviewFlag`) is who the local moderation route lets confirm a removal. Read from
    /// `app_state` at boot, like `userID`, because there is no `users` table on device (ERRATA E86).
    public private(set) var userRole: UserRole
    /// Where photo binaries live once "uploaded". `LocalAPI`'s upload is a move into this
    /// directory, which is what makes the outbox's photo phase exercisable with no network.
    private let photoDirectory: URL

    /// `tree_status_overrides`, held between the writes that can change it.
    ///
    /// The table is read on every `mapContent` — a whole-table `SELECT` with no predicate, because a
    /// row is keyed by a tree uuid and the map has a box, not a list of ids. That is a cheap query on
    /// a table that is usually empty, and the map asks it every time the camera moves, which made it
    /// one of the fifteen serialised round-trips per pan (ERRATA E130).
    ///
    /// **The invalidation is the whole safety of this.** `nil` means "ask", and exactly one thing
    /// writes the table — `ContributionStore.setStatusOverride`, reached only through this actor's
    /// two moderation routes — so both of those clear it and there is no other way for the answer to
    /// change under us. It is per-`LocalAPI` and this actor is the only writer of its own database,
    /// so no second process can invalidate it either.
    private var overrideCache: [UUID: TreeStatus]?

    public init(
        store: CypressStore,
        deviceID: UUID,
        userID: UUID? = nil,
        role: UserRole = .member,
        photoDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.deviceID = deviceID
        self.userID = userID
        self.userRole = role
        self.now = now
        self.treeQueries = store.seed.map {
            TreeQueries(schema: $0, seedHasSoftDeletedTrees: store.seedHasSoftDeletedTrees)
        }
        self.speciesQueries = store.seed.map { SpeciesQueries(schema: $0) }
        self.groveQueries = store.seed.map { GroveQueries(schema: $0) }
        self.almanacQueries = store.seed.map { AlmanacQueries(schema: $0) }
        self.photoDirectory = photoDirectory
            ?? store.databaseURL.deletingLastPathComponent().appendingPathComponent("Photos", isDirectory: true)
    }

    public func setUserID(_ id: UUID?) {
        userID = id
    }

    /// Who a contribution written right now belongs to: the signed-in user when there is one, this
    /// device otherwise (D9).
    ///
    /// Public because the composition root has to stamp it onto a mutation *before* the mutation
    /// reaches the outbox, and identity is not a view's question to answer — screen 06's reminder is
    /// the first write whose owner depends on it (ERRATA E23).
    public var attribution: Attribution {
        Attribution(userID: userID, deviceID: deviceID)
    }

    // MARK: - Map

    /// One viewport, **one** trip to the database.
    ///
    /// It used to be three: the seed query, the community layer, and the status overrides, each its
    /// own `queue.read` and so each its own hop onto and off the store's serial queue. `MapModel`
    /// then called this five times per camera change, one per latitude band — fifteen round-trips
    /// where the map needed one, ten of them returning results already in hand, all of it serialised
    /// on a single connection while the user's thumb was still on the glass (ERRATA E130).
    ///
    /// The bands are gone and the three reads are one closure. Nothing about *what* is read changed;
    /// what changed is that the three statements now run back to back inside one acquisition of the
    /// connection instead of queueing behind each other three times.
    public func mapContent(in viewport: MapViewport) async throws -> MapContent {
        let overrideCache = self.overrideCache
        let (seedContent, added, overrides) = try await store.queue.read {
            connection -> (MapContent, [Tree], [UUID: TreeStatus]) in
            let seedContent: MapContent = try treeQueries.map {
                try $0.mapContent(in: viewport, connection: connection)
            } ?? (viewport.shouldCluster ? .clusters([]) : .pins([]))

            // Community-added trees live in `main` and are merged here rather than unioned in SQL.
            // See `CommunityTreeStore` for why.
            //
            // **The narrowing has to be applied to them too, in Swift, or "only" leaks.** The seed
            // half of a narrowed viewport is filtered in SQL; this half is a separate table that
            // knows nothing about it, so a search for London Planes would have drawn every community
            // tree in the box on top of the matches — and drawn them *dashed*, which reads as "the
            // community found you these", the most convincing possible way to be wrong. Filtering
            // here rather than in `CommunityTreeStore.inBounds` keeps the narrowing in one place per
            // layer and costs nothing: the table holds one row per tree this device added.
            let allAdded = try communityTrees.inBounds(
                viewport.bounds,
                limit: viewport.pinLimit,
                connection: connection
            )
            let added = viewport.speciesIDs.map { wanted in
                allAdded.filter { tree in tree.speciesCurrentID.map(wanted.contains) ?? false }
            } ?? allAdded

            // Local status overrides (ERRATA E124-B): a lead-confirmed removal makes a tree a
            // memorial pin even though the inventory still calls it alive. Applied to `.pins` only —
            // a removed tree inside a zoomed-out cluster stays part of the count; the memorial
            // matters at the pin zoom where it can be tapped through to screen 19.
            //
            // The statement has no predicate at all, so it is a scan of the whole table — which is
            // fine, because the table holds one row per locally-moderated tree and is usually empty,
            // and not fine to run on every camera change for the life of the app. `overrideCache`
            // holds the answer between the writes that can change it.
            let overrides = try overrideCache ?? contributions.statusOverrides(connection: connection)
            return (seedContent, added, overrides)
        }
        self.overrideCache = overrides
        func applyingOverrides(_ content: MapContent) -> MapContent {
            guard !overrides.isEmpty, case let .pins(answer) = content else { return content }
            // `withItems`, not a fresh `PinAnswer`: an override changes what a pin *is*, never how
            // many trees the query found, so whatever the answer knew about being a sample survives.
            return .pins(answer.withItems(answer.items.map { pin in
                guard let status = overrides[pin.id] else { return pin }
                return TreePin(
                    id: pin.id,
                    coordinate: pin.coordinate,
                    status: status,
                    source: pin.source,
                    verificationState: pin.verificationState,
                    speciesID: pin.speciesID
                )
            }))
        }

        guard !added.isEmpty else { return applyingOverrides(seedContent) }

        switch seedContent {
        case let .pins(answer):
            // The community layer gets its own share of the budget rather than the tail of the
            // seed's.
            //
            // `pins` already comes back capped at `viewport.pinLimit`, so appending community trees
            // and then taking `prefix(pinLimit)` dropped **every one of them** whenever the seed
            // query hit its cap — which it does in normal SF density: `MapModel` reads each band at
            // 260 and a zoom-16 band measures around 264. A contributor added a tree and their own
            // pin never appeared on the screen they added it from, with no error and no log
            // (ERRATA E36).
            //
            // Reserving the space instead keeps the response the same size and cannot starve the
            // layer DECISIONS §3.16 requires to be visually distinct. What it spends is seed pins,
            // one for each community tree — and the 260th seed pin in a viewport of 264 is worth
            // less than the tree somebody stood in front of and added.
            let communityPins = added.map {
                TreePin(
                    id: $0.id,
                    coordinate: $0.coordinate,
                    status: $0.status,
                    source: $0.source,
                    verificationState: $0.verificationState,
                    speciesID: $0.speciesCurrentID
                )
            }
            let seedBudget = max(viewport.pinLimit - communityPins.count, 0)
            let kept = Array(answer.items.prefix(seedBudget)) + communityPins
            // Reserving the community layer's space spends seed pins, and on a narrowed map those
            // are matches — so if this cut anything, the answer is a sample whether or not the grid
            // already made it one. `PinAnswer` collapses a "sample" that dropped nothing, so an
            // untouched answer still reports itself complete.
            let dropped = answer.items.count - min(answer.items.count, seedBudget)
            return applyingOverrides(.pins(PinAnswer(
                kept,
                matchesInView: answer.matchesInView.map { $0 + communityPins.count }
                    ?? (dropped > 0 ? answer.items.count + communityPins.count : nil)
            )))

        case var .clusters(clusters):
            let centreLatitude = (viewport.bounds.minLatitude + viewport.bounds.maxLatitude) / 2
            let cell = TreeQueries.cellSize(zoom: viewport.zoom, centreLatitude: centreLatitude)
            var byCell = Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, $0) })
            for tree in added {
                let cellY = Int((tree.coordinate.latitude + 90.0) / cell.latitude)
                let cellX = Int((tree.coordinate.longitude + 180.0) / cell.longitude)
                let id = "z\(viewport.zoom):\(cellY):\(cellX)"
                if let existing = byCell[id] {
                    // Weighted mean, so adding one community tree to a cell of 2,000 does not move
                    // the badge.
                    let total = existing.count + 1
                    byCell[id] = TreeCluster(
                        id: id,
                        coordinate: Coordinate(
                            latitude: (existing.coordinate.latitude * Double(existing.count) + tree.coordinate.latitude) / Double(total),
                            longitude: (existing.coordinate.longitude * Double(existing.count) + tree.coordinate.longitude) / Double(total)
                        ),
                        count: total
                    )
                } else {
                    byCell[id] = TreeCluster(id: id, coordinate: tree.coordinate, count: 1)
                }
            }
            clusters = Array(byCell.values)
            return .clusters(clusters)
        }
    }

    public func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
        let fromSeed = try await store.queue.read { connection -> [NearbyTree] in
            guard let treeQueries else { return [] }
            return try treeQueries.nearest(to: coordinate, radiusM: radiusM, limit: limit, connection: connection)
        }
        let added = try await store.queue.read { connection in
            try communityTrees.near(coordinate, radiusM: radiusM, limit: limit, connection: connection)
        }
        guard !added.isEmpty else { return Array(fromSeed.prefix(limit)) }

        let addedRows = added.map {
            NearbyTree(
                tree: $0,
                distanceM: coordinate.distance(to: $0.coordinate),
                speciesScientificName: nil,
                speciesCommonName: nil,
                tell: nil
            )
        }
        return (fromSeed + addedRows).sorted { $0.distanceM < $1.distanceM }.prefix(limit).map { $0 }
    }

    // MARK: - Profile

    public func treeProfile(id: UUID) async throws -> TreeProfile {
        let moment = now()
        return try await store.queue.readConsistently { connection -> TreeProfile in
            let record = try treeQueries?.tree(id: id, connection: connection)
            let inventoryTree = try record?.tree ?? communityTrees.tree(id: id, connection: connection)
            guard var tree = inventoryTree else { throw APIError.notFound }

            // Layer any local status override (ERRATA E124-B): a lead-confirmed removal makes this a
            // memorial record — `status.isMemorial` gates `MemorialModel`, and `acceptsNewContributions`
            // goes false — exactly as the same override makes the map pin a memorial. One row per
            // moderated tree, so the lookup is a scan of a handful of rows (usually none).
            if let overridden = try contributions.statusOverrides(connection: connection)[id] {
                tree.status = overridden
            }

            // Each series is read whole (`limit: nil`), because everything the profile derives from
            // one is a statement about all of it: the hero's count and its `since` year, A5's
            // season strip, A8's caretakers over 24 months. A page would answer each of those with
            // a number that is wrong and looks right (ERRATA E38). These are one tree's own
            // contributions — tens of rows, indexed on `tree_uuid` — not a corpus.
            let photos = try contributions.photos(treeID: id, connection: connection)
            // Read whole for the same reason, and one read rather than two: the newest row of this
            // series *is* `latestObservation`, so asking the database twice for facts that have to
            // agree is a way for them to stop agreeing.
            let observations = try contributions.observations(treeID: id, connection: connection)

            return TreeProfile(
                tree: tree,
                activeName: try contributions.activeName(treeID: id, connection: connection),
                species: try Self.resolveSpecies(
                    record: record,
                    speciesID: tree.speciesCurrentID,
                    queries: speciesQueries,
                    connection: connection
                ),
                neighborhoodName: record?.neighborhoodName,
                latestObservation: observations.items.first,
                observations: observations,
                photos: photos,
                measurements: try contributions.measurements(treeID: id, connection: connection),
                visits: try contributions.visits(treeID: id, connection: connection),
                careEvents: try contributions.careEvents(treeID: id, connection: connection),
                communityNotes: try contributions.communityNotes(treeID: id, at: moment, connection: connection),
                siteLineageTreeID: record?.siteLineageID,
                // Every row in `main.photos` was written by this installation — `beginPhotoUpload`
                // and `addTree` are the only two writers and both run here, and nothing syncs
                // anybody else's photos down. So this device may show its owner all of them, and
                // `.pending` stays `.pending`, because nothing has in fact moderated them.
                ownPhotoIDs: Set(photos.items.map(\.id)),
                // Read in the same transaction as the photographs, so the hero and the list that
                // can change it are computed from one consistent picture (ERRATA E125).
                photoTallies: try contributions.photoTallies(
                    treeID: id, owner: FavoriteOwner(attribution), connection: connection
                )
            )
        }
    }

    private static func resolveSpecies(
        record: TreeQueries.TreeRecord?,
        speciesID: UUID?,
        queries: SpeciesQueries?,
        connection: SQLiteConnection
    ) throws -> Species? {
        if let species = record?.species { return species }
        guard let speciesID, let queries else { return nil }
        return try queries.species(id: speciesID, connection: connection)
    }

    /// `POST /trees`. Requires a photo; runs the 10 m proximity dedupe against any species.
    public func addTree(_ draft: TreeDraft) async throws -> Tree {
        guard !draft.photoLocalPath.isEmpty else { throw APIError.validationFailed }

        let candidates = try await treesNear(
            draft.coordinate,
            radiusM: TreeDraft.proximityDedupeRadiusM,
            limit: 10
        )
        if !candidates.isEmpty {
            // Every candidate here is inside the circle, not merely inside the box `treesNear`
            // searched: both halves re-check the exact metres (`TreeQueries.nearest`,
            // `CommunityTreeStore.near`). That is load-bearing — this line turns a candidate into a
            // permanent refusal, and it used to fire out to 14.1 m on the diagonal (ERRATA E35).
            //
            // §6 returns `conflict` with the candidate list. `ProximityConflict` carries the list;
            // the taxonomy code is what the outbox and the error banner read, and `conflict` is not
            // retryable, so the item will not burn 48 h on an answer the user has to give.
            throw ProximityConflict(candidates: candidates)
        }

        let moment = now()
        let tree = Tree(
            source: .community,
            coordinate: draft.coordinate,
            address: draft.address,
            status: .alive,
            speciesCurrentID: draft.speciesID,
            verificationState: .unverified,
            createdAt: moment,
            updatedAt: moment
        )

        try await store.queue.write { connection in
            try communityTrees.insert(tree, clientUUID: draft.clientUUID, connection: connection)
            let photo = Photo(
                treeID: tree.id,
                shotType: .fullTree,
                capturedAt: moment,
                createdAt: moment,
                updatedAt: moment
            )
            try contributions.insert(photo, localPath: draft.photoLocalPath, connection: connection)
        }
        return tree
    }

    // MARK: - Species

    public func species(id: UUID) async throws -> Species {
        let found = try await store.queue.read { connection -> Species? in
            try speciesQueries?.species(id: id, connection: connection)
        }
        guard let found else { throw APIError.notFound }
        return found
    }

    public func searchSpecies(query: String, limit: Int) async throws -> [Species] {
        try await store.queue.read { connection -> [Species] in
            guard let speciesQueries else { return [] }
            return try speciesQueries.search(query: query, limit: min(limit, Page<Species>.maximumLimit), connection: connection)
        }
    }

    /// Screen 07's payload: the field-guide entry, plus how common the species is nearby.
    ///
    /// Read in one `readConsistently` block for the same reason `treeProfile` is — the counts, the
    /// neighbourhood they are scoped to and the individuals listed under them are one statement
    /// about the inventory, and three separate reads could straddle a write and disagree.
    ///
    /// **Every population fact here is a whole read.** `cityTreeCount` is a `COUNT(*)`, not the size
    /// of a page; each nearby tree's photo count comes from `photos(treeID:)` with no limit, so
    /// `Series.totalCount` is non-nil and the screen may print it (ERRATA E38). The nearby list
    /// itself *is* limited, and says so — it is the one series on this screen nothing counts.
    ///
    /// Without a fix there is no "your area" and no distance to draw, so `nearYou` and `nearby` are
    /// simply absent. That is not a degraded state to apologise for on screen; it is two surfaces
    /// whose subject does not exist.
    public func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        try await store.queue.readConsistently { connection -> SpeciesGuide in
            guard let speciesQueries, let species = try speciesQueries.species(id: id, connection: connection) else {
                throw APIError.notFound
            }

            let cityCount = try speciesQueries.cityTreeCount(speciesID: id, connection: connection)

            guard let coordinate else {
                return SpeciesGuide(species: species, cityTreeCount: cityCount)
            }

            let neighborhood = try speciesQueries.resolveNeighborhood(near: coordinate, connection: connection)
            let nearYou = try neighborhood.map { area in
                SpeciesNeighborhoodCount(
                    neighborhoodName: area.name,
                    count: try speciesQueries.neighborhoodTreeCount(
                        speciesID: id,
                        neighborhoodID: area.id,
                        connection: connection
                    )
                )
            }

            let candidates = try treeQueries?.nearest(
                to: coordinate,
                radiusM: SpeciesGuideLimits.nearbyRadiusM,
                limit: SpeciesGuideLimits.nearbyRowLimit + 1,
                speciesID: id,
                connection: connection
            ) ?? []

            // One row more than the screen draws was asked for, so `isComplete` is a fact about the
            // read rather than a guess — the same proof `ContributionStore` uses.
            let isComplete = candidates.count <= SpeciesGuideLimits.nearbyRowLimit
            let rows = try candidates.prefix(SpeciesGuideLimits.nearbyRowLimit).map { candidate in
                NearbySpeciesTree(
                    treeID: candidate.tree.id,
                    title: try contributions.activeName(treeID: candidate.tree.id, connection: connection)?.name
                        ?? candidate.tree.address,
                    distanceM: candidate.distanceM,
                    photoCount: try contributions.photos(treeID: candidate.tree.id, connection: connection).totalCount,
                    vitality: try contributions.latestObservation(treeID: candidate.tree.id, connection: connection)?.vitality
                )
            }

            return SpeciesGuide(
                species: species,
                cityTreeCount: cityCount,
                nearYou: nearYou,
                nearby: Series(items: rows, isComplete: isComplete)
            )
        }
    }

    /// The curated field-guide list (BUILD-PLAN §8). Not a §6 endpoint; screen 08 needs it and it
    /// is a filter on `GET /species?` in every meaningful sense.
    public func curatedSpecies(limit: Int = 100) async throws -> [Species] {
        try await store.queue.read { connection -> [Species] in
            guard let speciesQueries else { return [] }
            return try speciesQueries.curated(limit: limit, connection: connection)
        }
    }

    // MARK: - Almanac

    /// Screen 12's payload: what is happening to the trees in one neighbourhood.
    ///
    /// **A4, for this screen.** The area is resolved through the nearest inventoried tree — the same
    /// derivation screen 07 uses and the same one line of SQL, `SpeciesQueries.resolveNeighborhood`,
    /// so A4's real mechanism lands in one place when it exists (ERRATA E44). Screen 08 could use
    /// A4's stated "most-visited" inference because a grove with no contributions renders nothing
    /// anyway; screen 12 cannot, because four of its five blocks are city data that is complete on
    /// day one and a fresh install has no history to infer from. Its own copy settles it too: §4
    /// says the trees are "within a 15-minute walk", which is a claim about where the reader is
    /// standing now, not about where they usually go.
    ///
    /// Read in one `readConsistently` block for the reason `speciesGuide` is: the elder, the mix,
    /// the bloom and the coverage list are one statement about one neighbourhood, and five separate
    /// reads could straddle a write and disagree about it.
    ///
    /// Without a fix there is no area and the whole payload is empty. That is not a degraded state
    /// to apologise for; it is a screen whose subject does not exist.
    public func almanac(near coordinate: Coordinate?) async throws -> Almanac {
        guard let coordinate, let speciesQueries, let almanacQueries else { return .empty }
        let moment = now()
        let calendar = Calendar.current

        return try await store.queue.readConsistently { connection -> Almanac in
            guard let area = try speciesQueries.resolveNeighborhood(near: coordinate, connection: connection) else {
                return .empty
            }

            // --- Who lives here. City data, so this is the one block a fresh install draws whole
            // (A9: "species mix always renders from city data").
            let mix = try almanacQueries.speciesMix(neighborhoodID: area.id, connection: connection)
            let composition = mix.isEmpty ? nil : NeighborhoodComposition(
                distinctSpeciesCount: mix.count,
                treeCount: mix.reduce(0) { $0 + $1.treeCount },
                leading: mix
            )

            // --- The elder. The active name is a `main` row and the tree is a `seed` row, so the
            // two are read separately and joined here rather than across the attach boundary.
            let elder = try almanacQueries.elder(neighborhoodID: area.id, connection: connection)
                .map { found in
                    ElderTree(
                        treeID: found.treeID,
                        activeName: try contributions.activeName(treeID: found.treeID, connection: connection)?.name,
                        speciesCommonName: found.speciesCommonName,
                        address: found.address,
                        plantedYear: found.plantedYear
                    )
                }

            // --- Newest neighbours. Absent outside spring, because the drawn copy has a word for
            // exactly one season and inventing the others is inventing (DECISIONS constraint 21).
            var newestNeighbors: RecentPlanting?
            if let spring = AlmanacWindow.currentSpring(now: moment, calendar: calendar) {
                let planted = try almanacQueries.plantings(
                    neighborhoodID: area.id,
                    from: spring.from,
                    to: spring.to,
                    connection: connection
                )
                let total = planted.reduce(0) { $0 + $1.treeCount }
                if total > 0 {
                    newestNeighbors = RecentPlanting(
                        treeCount: total,
                        leadingSpecies: planted.compactMap(\.name)
                    )
                }
            }

            // --- The first bloom of the year.
            let bloom = try almanacQueries.firstBloom(
                neighborhoodID: area.id,
                since: AlmanacWindow.yearStart(now: moment, calendar: calendar),
                connection: connection
            ).map { found in
                BloomFirst(
                    treeID: found.treeID,
                    speciesCommonName: found.speciesCommonName,
                    address: found.address,
                    firstSeenAt: found.firstSeenAt,
                    observerCount: found.observerCount
                )
            }

            // --- Where eyes are needed. One row more than the cap is read, so `isComplete` is a
            // fact about the read rather than a guess — the same proof `ContributionStore` uses, and
            // it has to hold here because this card is nothing but a count (ERRATA E38).
            let found = try almanacQueries.youngTreesWithoutVisits(
                neighborhoodID: area.id,
                plantedOnOrAfter: AlmanacWindow.youngSince(now: moment, calendar: calendar),
                limit: AlmanacLimits.coverageRowLimit + 1,
                connection: connection
            )
            let isComplete = found.count <= AlmanacLimits.coverageRowLimit
            let coverage = CoverageGap(
                trees: Series(
                    items: found.prefix(AlmanacLimits.coverageRowLimit)
                        .map { CoverageTree(pin: $0, distanceM: coordinate.distance(to: $0.coordinate)) }
                        .sorted { $0.distanceM < $1.distanceM },
                    isComplete: isComplete
                )
            )

            // --- Where a tree could go. The one block that inverts `standing`: the planting sites
            // with no tree in them. A count of city records, so it draws on a fresh install like the
            // species mix does — no contribution needed (R10, ERRATA E121).
            //
            // The rows are capped and the count is not, deliberately: the count is what the row
            // prints and the rows are what its map can hold (ERRATA E38, E129). See
            // `AlmanacLimits.vacantSiteRowLimit`.
            let sites = try almanacQueries.vacantSites(
                neighborhoodID: area.id,
                near: coordinate,
                limit: AlmanacLimits.vacantSiteRowLimit,
                connection: connection
            )
            let vacantSites = sites.count > 0
                ? VacantSites(count: sites.count, nearest: sites.nearest)
                : nil

            return Almanac(
                neighborhood: AlmanacNeighborhood(
                    name: area.name,
                    firstBloom: bloom,
                    elder: elder,
                    newestNeighbors: newestNeighbors,
                    composition: composition,
                    coverage: coverage,
                    vacantSites: vacantSites
                )
            )
        }
    }

    // MARK: - Sync

    /// `POST /sync`, locally.
    ///
    /// Applies each item to the local store and reports per-item status. Dedupe is on
    /// `client_uuid`, exactly as the server does it: the unique index plus `ON CONFLICT DO NOTHING`
    /// means a replayed item comes back `.duplicate`, which is a success, and no second row exists.
    ///
    /// Each item commits in its own transaction. One bad item must not roll back the twenty good
    /// ones behind it — that would be loss, and zero loss is the acceptance criterion.
    public func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
        var results: [SyncResult] = []
        results.reserveCapacity(items.count)

        for item in items {
            do {
                let payload = try OutboxPayload.decode(kind: item.kind, from: item.payload)
                let outcome = try await apply(payload)
                results.append(SyncResult(clientUUID: item.clientUUID, status: outcome.syncStatus))
            } catch let error as APIError {
                results.append(SyncResult(clientUUID: item.clientUUID, status: .failed, error: error))
            } catch let error as SQLiteError {
                results.append(SyncResult(clientUUID: item.clientUUID, status: .failed, error: error.asAPIError))
            } catch {
                // A payload that will not decode is a client bug, not a transient one. Reporting it
                // as `validation_failed` keeps the item out of a 48 h retry loop it cannot escape.
                results.append(SyncResult(clientUUID: item.clientUUID, status: .failed, error: .validationFailed))
            }
        }

        try await adoptRowsWrittenAfterTheClaim(hadItems: !items.isEmpty)
        return results
    }

    /// Re-runs the device claim once per batch, for rows that were queued before sign-in and applied
    /// after it.
    ///
    /// `claimDevice` sweeps what is in the tables when it runs. A mutation lives in the outbox
    /// between being written and being applied, and that gap can straddle a sign-in: queued in a
    /// dead zone on Tuesday, account linked on Wednesday, drained on Thursday. The payload carries
    /// the anonymous `Attribution` it was built with — payloads are immutable, and rewriting one
    /// after the fact would change a mutation the outbox has already promised to send verbatim — so
    /// the row lands with `user_id IS NULL` and the sweep that would have adopted it has already
    /// run. The contributor was told their work came with them, and the tail of their queue did not.
    ///
    /// So the claim is re-applied after every batch that had anything to apply. It is the same
    /// statement set, whose WHERE clauses stop matching once they have run: nothing inserts, nothing
    /// deletes, and rows belonging to a different account are not touched. When the device has never
    /// been claimed this is one indexed SELECT and no writes.
    private func adoptRowsWrittenAfterTheClaim(hadItems: Bool) async throws {
        guard hadItems else { return }
        let moment = now()
        let device = deviceID
        try await store.queue.write { connection in
            guard let user = try contributions.claimedUser(forDevice: device, connection: connection)
            else { return }
            try contributions.claimDevice(deviceUUID: device, userID: user, at: moment, connection: connection)
        }
    }

    private func apply(_ payload: OutboxPayload) async throws -> ContributionStore.WriteOutcome {
        try await store.queue.write { connection -> ContributionStore.WriteOutcome in
            switch payload {
            case let .visit(visit):
                try requireTree(visit.treeID, connection: connection)
                return try contributions.insert(visit, connection: connection)

            case let .observation(observation):
                try requireTree(observation.treeID, connection: connection)
                let outcome = try contributions.insert(observation, connection: connection)
                // "An observation with status appears_removed does not mutate trees.status directly;
                // it opens a review_flag" (BUILD-PLAN §6, DECISIONS §3.7). Only on first apply, so a
                // replay does not open a second flag.
                if outcome == .inserted, let kind = observation.raisesReviewFlagKind {
                    try contributions.insert(
                        ReviewFlag(
                            treeID: observation.treeID,
                            kind: kind,
                            raisedBy: observation.userID,
                            createdAt: observation.capturedAt,
                            updatedAt: observation.capturedAt
                        ),
                        connection: connection
                    )
                }
                return outcome

            case let .measurement(measurement):
                try requireTree(measurement.treeID, connection: connection)
                return try contributions.insert(measurement, connection: connection)

            case let .careEvent(event):
                try requireTree(event.treeID, connection: connection)
                return try contributions.insert(event, connection: connection)

            case let .privateReminder(reminder):
                try requireTree(reminder.treeID, connection: connection)
                // The owner arrives on the payload and is written as it stands. Nothing here
                // upgrades a device-owned reminder to a user: that only happens at
                // `POST /devices/claim`, where it is one statement with one WHERE clause (D9).
                return try contributions.insert(reminder, connection: connection)

            case let .favoriteToggle(toggle):
                // Not gated on `TreeStatus.acceptsNewContributions`, unlike a visit or a check-in: a
                // favourite asserts nothing about the tree, and gating it would make the toggle
                // one-way for anyone whose favourite tree is later removed — they could no longer
                // take the heart off. See ERRATA E89.
                try requireTree(toggle.treeID, connection: connection)
                // The owner arrives on the payload and is written as it stands. Nothing here
                // upgrades a device-owned favourite to a user: that happens only at
                // `POST /devices/claim` (D9, E23's mechanism).
                return try contributions.applyFavoriteToggle(
                    owner: toggle.owner,
                    treeID: toggle.treeID,
                    clientUUID: toggle.clientUUID,
                    isFavorite: toggle.isFavorite,
                    at: toggle.occurredAt,
                    connection: connection
                )
            }
        }
    }

    /// No foreign key can span the attached seed (see `AppSchema`), so referential integrity
    /// against the inventory is checked here instead. A contribution about a tree that does not
    /// exist is `not_found`, which is not retryable — the right answer, since retrying will not
    /// make the tree appear.
    private func requireTree(_ id: UUID, connection: SQLiteConnection) throws {
        let inSeed = (try? treeQueries?.exists(id: id, connection: connection)) ?? false
        if inSeed == true { return }
        if try communityTrees.exists(id: id, connection: connection) { return }
        throw APIError.notFound
    }

    // MARK: - Photos

    /// `POST /photos/begin`. Locally, the "presigned URL" is a destination inside the app container.
    public func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        let moment = now()
        let photo = Photo(
            treeID: request.treeID,
            visitID: request.visitID,
            shotType: request.shotType,
            // The request has carried these all along and this method dropped them, so the columns
            // were NULL even once the transport started measuring the file (ERRATA E41).
            width: request.width,
            height: request.height,
            capturedAt: request.capturedAt,
            publicCoordinate: request.publicCoordinate,
            createdAt: moment,
            updatedAt: moment
        )
        try await store.queue.write { connection in
            try contributions.insert(photo, localPath: request.localPath, connection: connection)
        }
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        let destination = photoDirectory.appendingPathComponent("\(photo.id.uuidString).jpg")
        return PhotoUploadTicket(photoID: photo.id, destination: destination)
    }

    public func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {
        let source = URL(fileURLWithPath: localPath)
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else {
            // The binary is gone. Not retryable: no amount of waiting brings a deleted file back.
            throw APIError.notFound
        }
        try manager.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        if manager.fileExists(atPath: ticket.destination.path) {
            try manager.removeItem(at: ticket.destination)
        }

        // Ingest, in DECISIONS §3.10's sense: "strip all EXIF ... on ingest". §3.10 says
        // server-side, and there is no server — this method is where a captured file stops being
        // the camera's and becomes the app's record, so it is the ingest path (ERRATA E40).
        // Nothing else in the app ever did it: `AVCapturePhoto.fileDataRepresentation()` carries
        // the full metadata sidecar, and the photo-library fallback carries whatever the original
        // file had, which is the one that can hold GPS.
        //
        // On failure the original is moved across rather than dropped. A file this cannot rewrite
        // is a file whose format ImageIO does not know, and refusing it would fail the outbox item
        // terminally and lose the contributor the only copy of their photograph — a worse outcome
        // than metadata sitting in the app's own container, which no surface reads and which never
        // leaves the device under `LocalAPI`. `RemoteAPI` must not inherit that reasoning: nothing
        // may be *published* out of this fallback.
        do {
            try PhotoBinary.writeStrippingMetadata(from: source, to: ticket.destination)
            try manager.removeItem(at: source)
        } catch {
            try manager.moveItem(at: source, to: ticket.destination)
        }

        let moment = now()
        try await store.queue.write { connection in
            try contributions.markPhotoUploaded(
                id: ticket.photoID,
                storageKey: ticket.destination.lastPathComponent,
                at: moment,
                connection: connection
            )
        }
    }

    /// The bytes of one photograph (see `PhotoAccess` for why this is on the API at all).
    ///
    /// Two places to look, because a photograph is in one of two for a while: `local_path` from the
    /// shutter until the outbox drains it, then `storage_key` inside this actor's own photo
    /// directory. Looking only in the second would blank the tree you just photographed for exactly
    /// as long as the drain takes — the one moment somebody is certain to be looking at it.
    ///
    /// `storage_key` is resolved against `photoDirectory` here rather than being trusted as a path:
    /// the column holds a filename (`markPhotoUploaded` writes `lastPathComponent`), and treating a
    /// stored string as a path is how a directory traversal gets in when these rows one day arrive
    /// from somewhere other than this device.
    public func photoData(id: UUID) async throws -> Data {
        let location = try await store.queue.read { connection in
            try contributions.photoBinaryLocation(id: id, connection: connection)
        }
        guard let location else { throw APIError.notFound }

        let candidates = [
            location.storageKey.map { photoDirectory.appendingPathComponent(($0 as NSString).lastPathComponent) },
            location.localPath.map { URL(fileURLWithPath: $0) }
        ].compactMap { $0 }

        for url in candidates {
            if let data = try? Data(contentsOf: url) { return data }
        }
        // The row exists and the file does not — a photograph whose binary was lost. `notFound` is
        // the truthful answer and the screen draws its placeholder; inventing an empty `Data` would
        // hand a decoder something to fail on later and further away.
        throw APIError.notFound
    }

    /// A thumb up or down on a photograph, or `nil` to take it back (ERRATA E125, `AppSchema` v8).
    ///
    /// The owner is `attribution`'s — the account when there is one, this device otherwise — so a
    /// vote cast before sign-in is adopted by `claimDevice` exactly as a favourite is, and never
    /// counted twice.
    public func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws {
        let moment = now()
        let owner = FavoriteOwner(attribution)
        try await store.queue.write { connection in
            // Voting on a photograph that is not there is `notFound`, not a silent success. The
            // insert's own `SELECT FROM photos` would already write nothing, but "wrote nothing" and
            // "there was nothing to write about" have to reach the caller as different answers.
            guard try contributions.photoBinaryLocation(id: photoID, connection: connection) != nil else {
                throw APIError.notFound
            }
            guard let vote else {
                return try contributions.clearPhotoVote(photoID: photoID, owner: owner, connection: connection)
            }
            try contributions.setPhotoVote(
                photoID: photoID, owner: owner, vote: vote, at: moment, connection: connection
            )
        }
    }

    // `outboxStatus()` was here, and is gone with the protocol requirement it answered — see the
    // note at the foot of `CypressAPI`. It mapped every outbox row to a `SyncResult` so screen 17's
    // "says why" line would have the same shape against the real service; screen 17 reads
    // `OutboxViewState` instead, and always did.

    // MARK: - Personal surfaces

    public func grove() async throws -> [GroveEntry] {
        let rows = try await store.queue.read { connection in
            try contributions.groveTreeIDs(userID: userID, deviceID: deviceID, connection: connection)
        }
        var entries: [GroveEntry] = []
        entries.reserveCapacity(rows.count)
        for row in rows {
            guard let profileTree = try await treeIfPresent(row.treeID) else { continue }
            entries.append(
                GroveEntry(
                    treeID: row.treeID,
                    displayName: (try await displayNameIfPresent(for: row.treeID)) ?? "",
                    coordinate: profileTree.coordinate,
                    lastVisitedAt: row.lastVisitedAt,
                    isFavorite: row.isFavorite
                )
            )
        }
        return entries
    }

    /// `GET /me/grove`, Species tab — screen 08.
    ///
    /// Both reads run with no limit, on purpose. Screen 08 prints the size of each of them, so a
    /// page would be printed as a total the moment one was taken (ERRATA E38); `GroveQueries` still
    /// accepts a limit so the incomplete case stays representable and testable, and this is the
    /// caller that must not pass one.
    ///
    /// A device with no seed attached has no city inventory to compare against and no tree to
    /// resolve a species from, so it has an empty grove rather than a wrong one.
    public func groveSpecies() async throws -> GroveSpecies {
        guard let groveQueries else { return .empty }
        let userID = userID
        let deviceID = deviceID
        return try await store.queue.read { connection -> GroveSpecies in
            let known = try groveQueries.knownSpecies(
                userID: userID,
                deviceID: deviceID,
                connection: connection
            )
            // A4's inference reads the same contributions, so a contributor with none has no
            // neighbourhood and the ring has nothing to be a fraction of.
            guard let resident = try groveQueries.residentNeighborhood(
                userID: userID,
                deviceID: deviceID,
                connection: connection
            ) else {
                return GroveSpecies(neighborhood: nil, known: known)
            }
            let species = try groveQueries.neighborhoodSpeciesIDs(
                neighborhoodID: resident.id,
                connection: connection
            )
            return GroveSpecies(
                neighborhood: GroveNeighborhood(name: resident.name, species: species),
                known: known
            )
        }
    }

    public func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> {
        let cursorDate = cursor.flatMap(SQLiteTimestamp.date(from:))
        let capped = min(limit, Page<JournalEntry>.maximumLimit)
        let rows = try await store.queue.read { connection in
            try contributions.journal(
                userID: userID,
                deviceID: deviceID,
                before: cursorDate,
                limit: capped,
                connection: connection
            )
        }

        // One name lookup per distinct tree, not per row: a journal page is usually several
        // contributions about the same handful of trees.
        let names = await displayNames(for: Array(Set(rows.map(\.treeID))))

        let entries = rows.map { row in
            JournalEntry(
                id: row.id,
                kind: row.kind,
                treeID: row.treeID,
                treeDisplayName: names[row.treeID] ?? "",
                capturedAt: row.capturedAt,
                summary: Self.humanize(kind: row.kind, storedSummary: row.summary)
            )
        }
        // The cursor is the last row's capture time. Contributions are append-only and never
        // back-dated across a page boundary, so this is stable under concurrent writes.
        let nextCursor = entries.count == capped
            ? entries.last.map { SQLiteTimestamp.string(from: $0.capturedAt) }
            : nil
        return Page(items: entries, nextCursor: nextCursor)
    }

    /// `care_events.actions` is stored as a JSON array; the journal query hands it back raw rather
    /// than teaching SQL to write English.
    static func humanize(kind: JournalEntry.Kind, storedSummary: String) -> String {
        guard kind == .careEvent else { return storedSummary }
        let actions = JSONColumn.decodeRawValues(CareAction.self, storedSummary)
        return actions.map(\.rawValue.replacingUnderscores).joined(separator: ", ")
    }

    public func claimDevice(deviceUUID: UUID, userID: UUID) async throws {
        let moment = now()
        try await store.queue.write { connection in
            try contributions.claimDevice(deviceUUID: deviceUUID, userID: userID, at: moment, connection: connection)
        }
        self.userID = userID
        try await store.setAppState(.currentUserID, to: userID.uuidString)
        // A claim that was not screen 15's — the DEBUG deep links, a future server exchange — leaves
        // no consent record, and must not leave a stale one either. See `linkAccount`.
        try await store.clearAppState(.signedOutUserID)
    }

    // MARK: - The account (local, ERRATA E131)

    /// Screen 15's sign-in, with the two things the screen collects (ERRATA **E131**).
    ///
    /// `claimDevice` plus the consent record, because the request screen 15 assembles has to land
    /// somewhere a later read can find it: the composition root used to throw the whole
    /// `AccountLinkRequest` away, which made `AccountAskModel`'s own justification for leaving the
    /// checkbox ungated ("the answer travels on the request instead") untrue. See
    /// `AccountLinkRecord` for why the license is stored as a version and not a flag.
    ///
    /// Not on `CypressAPI`, for `deleteAccount`'s reason: the protocol carries `POST /devices/claim`
    /// because a server has that endpoint, and has no `/auth/*` at all. Recording what a person
    /// agreed to on *this* device is the local half, and it is not a stub.
    ///
    /// Written after the claim rather than before it: a claim that throws leaves no account, and a
    /// consent record for an account that does not exist would be read back on the next sign-in as
    /// if the person had already agreed to something.
    public func linkAccount(
        deviceUUID: UUID,
        userID: UUID,
        provider: String,
        acceptsLicense: Bool,
        licenseVersion: String = LicenseConsent.currentVersion
    ) async throws {
        try await claimDevice(deviceUUID: deviceUUID, userID: userID)
        try await store.setAppState(.accountProvider, to: provider)
        if acceptsLicense {
            try await store.setAppState(.accountLicenseVersion, to: licenseVersion)
        } else {
            // Cleared rather than written as an empty string, so a declined consent reads back as
            // the nil `User.hasAcceptedLicense` already tests for, and a re-link that declines
            // cannot leave the previous agreement standing.
            try await store.clearAppState(.accountLicenseVersion)
        }
    }

    /// What the signed-in account agreed to, read back from `app_state`.
    ///
    /// Nil when nobody is signed in, rather than an empty record: "no consent recorded" and "no
    /// account" are different sentences and the caller renders them differently.
    public func accountLink() async throws -> AccountLinkRecord? {
        guard userID != nil else { return nil }
        return AccountLinkRecord(
            provider: try await store.appState(.accountProvider),
            licenseVersion: try await store.appState(.accountLicenseVersion)
        )
    }

    /// The account this device could sign back in as, having signed out of it
    /// (`AppStateKey.signedOutUserID`).
    ///
    /// Nil while signed in — the question only means anything when there is no current account — so
    /// a caller cannot accidentally resume an id while another one is live.
    public func resumableUserID() async throws -> UUID? {
        guard userID == nil else { return nil }
        return (try await store.appState(.signedOutUserID)).flatMap(UUID.init(uuidString:))
    }

    /// Sign out: stop acting as this account, keep everything it wrote (ERRATA **E131**).
    ///
    /// **Nothing is deleted here and that is the entire distinction from `deleteAccount`.** The rows
    /// stay exactly as they are, still carrying the account's id; what changes is that this
    /// installation stops presenting itself as that account, so `attribution` goes back to the
    /// device and the reads that ask for "my" reminders and favourites stop returning the account's.
    ///
    /// The id is remembered under `AppStateKey.signedOutUserID` so signing in again resumes it. A
    /// local account has no credential to sign back in *with* — `accountLink` mints a `UUID` when it
    /// finds none — so forgetting the id would leave every account-owned row unreadable by any query
    /// and unremovable by any deletion, which is the litter RULINGS R3 spent its length refusing to
    /// create. Sign-out is not a quiet, unlabelled deletion.
    ///
    /// The role goes with it for `deleteAccount`'s reason: a lead's authority is the account's, and
    /// a device with nobody signed in is not a lead. The consent record stays put — it is the
    /// account's, it is resumed with the account, and a re-link overwrites it with whatever the
    /// person agrees to that time.
    public func signOut() async throws {
        guard let account = userID else { return }
        try await store.setAppState(.signedOutUserID, to: account.uuidString)
        try await store.clearAppState(.currentUserID)
        userID = nil
        userRole = .member
        try await store.setAppState(.currentUserRole, to: UserRole.member.rawValue)
    }

    // MARK: - Moderation (local, ERRATA E124-B)

    /// Set the signed-in account's role, persisted like `userID`.
    ///
    /// In the shipping product a role is granted server-side by an org coordinator (PRODUCT §2); the
    /// local beta has no server, so the promote path is the DEBUG affordance in the You tab — a
    /// person stepping into the mocked city-lead role to verify removals. `.member` is the ground
    /// state a fresh local account signs in as; nothing else grants a role.
    public func setRole(_ role: UserRole) async throws {
        self.userRole = role
        try await store.setAppState(.currentUserRole, to: role.rawValue)
    }

    /// The open `appears_removed` flags a lead has to act on, resolved for display: each tree's name
    /// (active name, else species common name), address and coordinate, newest concern first.
    ///
    /// A read, so it is ungated — a non-lead simply never reaches the surface that calls it (the You
    /// tab shows the section only when `userRole.canConfirmReviewFlag`). The *write* is what carries
    /// the authority check; see `confirmRemoval`.
    public func openRemovalReviews() async throws -> [RemovalReviewItem] {
        try await store.queue.read { connection -> [RemovalReviewItem] in
            let flags = try contributions.openReviewFlags(kind: .appearsRemoved, connection: connection)
            return try flags.compactMap { flag -> RemovalReviewItem? in
                // The tree may be a seed row or a community add; resolve through the same two-step the
                // profile uses. A flag whose tree cannot be found is skipped rather than shown nameless.
                let record = try treeQueries?.tree(id: flag.treeID, connection: connection)
                guard let tree = try record?.tree ?? communityTrees.tree(id: flag.treeID, connection: connection)
                else { return nil }
                let name = try contributions.activeName(treeID: flag.treeID, connection: connection)?.name
                    ?? Self.resolveSpecies(
                        record: record,
                        speciesID: tree.speciesCurrentID,
                        queries: speciesQueries,
                        connection: connection
                    )?.commonName
                    ?? "This tree"
                return RemovalReviewItem(
                    flagID: flag.id,
                    treeID: flag.treeID,
                    treeName: name,
                    address: tree.address,
                    coordinate: tree.coordinate,
                    raisedAt: flag.createdAt
                )
            }
        }
    }

    /// A lead confirms an `appears_removed` flag: the flag moves to `confirmed` and the tree gains a
    /// local status override of `removed`, in one transaction (see `AppSchema.v7`). That is the whole
    /// of what makes screen 19 reachable from real data — the map pin becomes a memorial and the
    /// profile becomes a memorial record, because `mapContent` and `treeProfile` layer this override
    /// over the inventory's status.
    ///
    /// Gated: only `userRole.canConfirmReviewFlag` (moderator, admin, coordinator) may confirm a flag
    /// into a status transition (DECISIONS §3.7). A `member` or `steward` gets `.forbidden` — the
    /// authority lives on the write, so even a surface shown in error cannot move a tree.
    public func confirmRemoval(flagID: UUID) async throws {
        guard userRole.canConfirmReviewFlag else { throw APIError.forbidden }
        let moment = now()
        let confirmer = userID
        try await store.queue.write { connection in
            guard let flag = try contributions.reviewFlag(id: flagID, connection: connection),
                  flag.deletedAt == nil else {
                throw APIError.notFound
            }
            // Only a removal flag becomes a removal. A confirm arriving for any other kind is a bug in
            // the caller, not a silent status change on the wrong grounds.
            guard flag.kind == .appearsRemoved else { throw APIError.validationFailed }
            guard flag.status == .open else { throw APIError.conflict }

            try contributions.confirmReviewFlag(id: flagID, at: moment, connection: connection)
            try contributions.setStatusOverride(
                treeID: flag.treeID,
                status: .removed,
                setBy: confirmer,
                at: moment,
                connection: connection
            )
        }
        // The map holds this table between writes; this is one of the two writes. See `overrideCache`.
        overrideCache = nil
    }

    #if DEBUG
    /// Test seam (ERRATA E124-B): open a removal review on a real seed tree, returning its flag id, so
    /// the deep-link harness can put the moderation surface in front of a screenshot with a genuine
    /// record behind it. Inserts the same `appears_removed` flag a "Removed?" check-in would, without
    /// the outbox round trip.
    @discardableResult
    public func debugSeedRemovalReview(treeID: UUID) async throws -> UUID {
        let moment = now()
        let flag = ReviewFlag(treeID: treeID, kind: .appearsRemoved, raisedBy: nil, createdAt: moment, updatedAt: moment)
        try await store.queue.write { connection in
            try contributions.insert(flag, connection: connection)
        }
        return flag.id
    }

    /// Test seam (ERRATA E124-B): force a tree to a memorial by writing its status override directly,
    /// so the harness can open screen 19 against a real seed record. The shipping path is
    /// `confirmRemoval`, which requires a lead and an open flag; this skips both because the harness is
    /// proving the *screen renders*, not the moderation gate — `ModerationTests` proves the gate.
    public func debugMarkRemoved(treeID: UUID) async throws {
        let moment = now()
        try await store.queue.write { connection in
            try contributions.setStatusOverride(treeID: treeID, status: .removed, setBy: nil, at: moment, connection: connection)
        }
        // The other write. See `overrideCache`.
        overrideCache = nil
    }

    /// Test seam (ERRATA E125): give a real seed tree some photographs, so the deep-link harness can
    /// open screen 20 and the profile hero against records that exist.
    ///
    /// The shipping path is the shutter — `beginPhotoUpload` then `uploadPhoto`, through the outbox —
    /// and it needs a camera. This writes the same rows and the same files directly. The images are
    /// generated rather than bundled: a fixture JPEG in the app's resources would ship in Release,
    /// and what these screens have to prove is that *a photograph* renders, not which one.
    ///
    /// Returns the ids, newest first, in the order the profile reads them.
    ///
    /// **Idempotent per tree, and it has to be.** Every launch of the `photos` or `photoHero` deep
    /// link calls this, and both the rows and the JPEGs outlive the launch — so an append-only seam
    /// would leave six photographs after two launches and nine after three, and any vote cast on the
    /// way past would still be sitting there. That is not a hypothetical: it broke a run of
    /// `testAThumbActuallyVotes`, which reasonably requires the hero to start on the top card and
    /// found it on the second, because a photograph voted up by hand an hour earlier was still the
    /// hero. A harness whose state depends on how many times it has been run before is not a harness.
    /// So this clears the tree first: its photographs, their votes, and their files.
    @discardableResult
    public func debugSeedPhotos(treeID: UUID, count: Int = 3) async throws -> [UUID] {
        var ids: [UUID] = []
        try await debugClearPhotos(treeID: treeID)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        for index in 0..<count {
            // Portrait, like a phone's, and each one a different hue so a browser of three
            // photographs is visibly a browser of three photographs.
            let data = Self.debugJPEG(hue: Double(index) / Double(max(count, 1)))
            let moment = now().addingTimeInterval(TimeInterval(-86_400 * index))
            let photo = Photo(
                treeID: treeID,
                shotType: index == 0 ? .fullTree : (index == 1 ? .trunk : .leaf),
                width: 1_200,
                height: 1_600,
                capturedAt: moment,
                createdAt: moment,
                updatedAt: moment
            )
            let destination = photoDirectory.appendingPathComponent("\(photo.id.uuidString).jpg")
            try data.write(to: destination, options: .atomic)
            try await store.queue.write { connection in
                try contributions.insert(photo, localPath: nil, connection: connection)
                try contributions.markPhotoUploaded(
                    id: photo.id,
                    storageKey: destination.lastPathComponent,
                    at: moment,
                    connection: connection
                )
            }
            ids.append(photo.id)
        }
        return ids
    }

    /// Takes one tree back to having never been photographed — rows, votes and bytes.
    ///
    /// The files go first and the rows second, because the reverse order loses the filenames: a
    /// photograph's bytes are found through its row, so deleting the row strands the JPEG in the
    /// container with nothing left pointing at it.
    private func debugClearPhotos(treeID: UUID) async throws {
        let existing = try await store.queue.read { connection in
            try contributions.photos(treeID: treeID, connection: connection).items
        }
        for photo in existing {
            let location = try await store.queue.read { connection in
                try contributions.photoBinaryLocation(id: photo.id, connection: connection)
            }
            guard let name = location?.storageKey else { continue }
            try? FileManager.default.removeItem(
                at: photoDirectory.appendingPathComponent((name as NSString).lastPathComponent)
            )
        }
        try await store.queue.write { connection in
            // The votes first: `photo_votes` refers to the photographs, and a delete in the other
            // order would leave rows pointing at nothing for as long as the transaction is open.
            let votes = try connection.cachedStatement("""
                DELETE FROM photo_votes WHERE tree_uuid = :tree COLLATE NOCASE
                """)
            _ = try votes.bind([":tree": treeID.uuidString])
            try votes.run()
            _ = try votes.reset()

            let photos = try connection.cachedStatement("""
                DELETE FROM photos WHERE tree_uuid = :tree COLLATE NOCASE
                """)
            _ = try photos.bind([":tree": treeID.uuidString])
            try photos.run()
            _ = try photos.reset()
        }
    }

    /// A small portrait JPEG that could not be mistaken for any view in this app.
    ///
    /// ── Why it is garish, and why that is the whole point (ERRATA E125) ───────────────────────
    /// The first version filled a flat dark green. Sensible-looking, and useless: a flat green
    /// photograph behind the hero's legibility scrim renders as a dark green vertical ramp — which is
    /// *exactly* what `CypressGradientField` draws when there is no photograph. Verifying by eye
    /// could not tell the fixed app from the broken one, and the bug this seam exists to catch is
    /// precisely "every photograph silently fell back to the gradient".
    ///
    /// So: a saturated hue swept off the green axis, plus a white bar across the middle. Cypress has
    /// no magenta, no cyan, and nothing anywhere draws a hard white band inside a photo frame. If
    /// that band is on the screen, bytes came through `photoData` and were decoded. If it is not,
    /// they did not — no interpretation required.
    ///
    /// CoreGraphics and ImageIO, not UIKit: `Data` may import the system libraries its own job is
    /// defined in terms of, and no UI framework (ARCHITECTURE §2, and see `PhotoBinary`'s note on
    /// the same line). A `#if DEBUG` seam is not a reason to cross a layer boundary.
    private static func debugJPEG(hue: Double) -> Data {
        let width = 300, height = 400
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return Data() }
        // Three hues a third of the wheel apart, started at magenta so none of them lands on the
        // app's greens: magenta, orange, cyan for count == 3.
        let (red, green, blue) = Self.saturatedRGB(hue: (hue + 0.85).truncatingRemainder(dividingBy: 1))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2 - 20, width: width, height: 40))

        guard let image = context.makeImage() else { return Data() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return output as Data
    }

    /// Fully saturated, fully bright RGB for a hue in `0..<1`. Written out rather than taken from
    /// `UIColor(hue:…)` for the layering reason above: `Data` imports no UI framework.
    private static func saturatedRGB(hue: Double) -> (Double, Double, Double) {
        let sector = hue * 6
        let fraction = sector - sector.rounded(.down)
        switch Int(sector) % 6 {
        case 0: return (1, fraction, 0)
        case 1: return (1 - fraction, 1, 0)
        case 2: return (0, 1, fraction)
        case 3: return (0, 1 - fraction, 1)
        case 4: return (fraction, 0, 1)
        default: return (1, 0, 1 - fraction)
        }
    }
    #endif

    /// `DELETE /me` — deletion, in the two-part sense RULINGS R3 settles (see `AccountDeletion`).
    ///
    /// **Not on `CypressAPI`, and that is deliberate.** The protocol's header lists `DELETE /me`
    /// among its omissions because there is no auth server; that reasoning still holds for the
    /// server half — telling a backend to forget an account — and adding a throwing stub to
    /// `RemoteAPI` would suggest a sign-in flow exists. What *is* implementable today is the local
    /// half, which is not a stub: the rows are on this device and this is the only code that can
    /// reach them. When the service lands, `DELETE /me` joins the protocol and this method becomes
    /// the local half of it, unchanged. It sits beside `privateReminders` and `curatedSpecies`,
    /// which are `LocalAPI`'s for the same kind of reason.
    ///
    /// Requires a signed-in account: deleting "the current account" when there is none would be a
    /// no-op that reports success, and there is nothing else it could honestly mean — a device's own
    /// rows are not an account's (see `AccountDeletion`).
    ///
    /// The signed-in state goes with it, in the same transaction as the rows, so there is no instant
    /// at which the app believes it is signed in as an account whose records are gone.
    @discardableResult
    public func deleteAccount() async throws -> AccountDeletion.Outcome {
        guard let account = userID else { throw APIError.unauthorized }
        let moment = now()
        let outcome = try await store.queue.write { connection in
            try AccountDeletion().delete(userID: account, at: moment, connection: connection)
        }
        userID = nil
        // The role went with the account: a deleted account is not a lead. Cleared here rather than
        // in `AccountDeletion` because it is device state (`app_state`), not one of the account's rows.
        userRole = .member
        try await store.setAppState(.currentUserRole, to: UserRole.member.rawValue)
        // Device state again, and the same argument one step further (ERRATA E131). A deleted account
        // must not be resumable: `signedOutUserID` exists so that signing back in returns to the same
        // identity, and an id left here after `AccountDeletion` has emptied it would hand the next
        // sign-in an account whose rows are gone. The consent record goes for the plainer reason —
        // it is a sentence about a person who asked to be forgotten.
        try await store.clearAppState(.signedOutUserID)
        try await store.clearAppState(.accountProvider)
        try await store.clearAppState(.accountLicenseVersion)
        return outcome
    }

    /// What this device is holding under its own id, for screen 15's one sentence with a number in
    /// it. See `DeviceContributions` for why this is a read rather than the ledger's save counter.
    ///
    /// It counts only rows that are still unattributed, so after `claimDevice` it goes to zero —
    /// which is correct: there is then nothing left on the phone that an account would rescue.
    public func deviceContributions() async throws -> DeviceContributions {
        let device = deviceID
        return try await store.queue.read { connection in
            try contributions.deviceContributions(deviceUUID: device, connection: connection)
        }
    }

    // MARK: - Reports and export

    public func logHazardRedirect(_ event: HazardRedirectEvent) async throws {
        try await store.queue.write { connection in
            try contributions.log(event, connection: connection)
        }
    }

    /// The separate `private_reminders` POST (BUILD-PLAN §6, D4).
    ///
    /// Expressed in terms of the same applier the batch uses, so the single-item endpoint and the
    /// queued item cannot diverge: one statement, one idempotency rule, one referential check. The
    /// reminder reaches here already owned — by the signed-in user, or by this device (D9) — and
    /// this method does not second-guess that.
    ///
    /// Writing a reminder tells the city nothing, and nothing about this call may be rendered as if
    /// it had (ARCHITECTURE §5.4).
    @discardableResult
    public func savePrivateReminder(_ reminder: PrivateReminder) async throws -> SyncResult.Status {
        try await apply(.privateReminder(reminder)).syncStatus
    }

    /// This contributor's own reminders: the account's, plus the ones this device wrote before there
    /// was an account. Never anyone else's — there is no query that could return one (D4, D11).
    public func privateReminders(limit: Int = 50) async throws -> [PrivateReminder] {
        try await store.queue.read { connection in
            try contributions.privateReminders(
                userID: userID,
                deviceID: deviceID,
                limit: limit,
                connection: connection
            )
        }
    }

    /// `GET /export/latest.csv` / `.geojson`.
    ///
    /// The nightly export is a server job over the whole corpus (BUILD-PLAN §6); on device this
    /// exports **this device's own contributions**, which is what a coordinator's "export my
    /// morning" and the account-data request both need. It carries `verification_state` and the
    /// structure-flag disclaimer in the header, per D12 and BUILD-PLAN §4.
    public func exportLatest(_ format: ExportFormat) async throws -> Data {
        let entries = try await wholeJournal()
        switch format {
        case .csv:
            var lines = [
                "# \(StructureFlag.disclaimer)",
                "kind,tree_id,captured_at,summary,verification_state"
            ]
            for entry in entries {
                lines.append(
                    [
                        entry.kind.rawValue,
                        entry.treeID.uuidString,
                        SQLiteTimestamp.string(from: entry.capturedAt),
                        Self.csvEscape(entry.summary),
                        VerificationState.unverified.rawValue
                    ].joined(separator: ",")
                )
            }
            return Data(lines.joined(separator: "\n").utf8)

        case .geojson:
            var features: [[String: Any]] = []
            for entry in entries {
                guard let tree = try await treeIfPresent(entry.treeID) else { continue }
                features.append([
                    "type": "Feature",
                    "geometry": [
                        "type": "Point",
                        "coordinates": [tree.coordinate.longitude, tree.coordinate.latitude]
                    ],
                    "properties": [
                        "kind": entry.kind.rawValue,
                        "tree_id": entry.treeID.uuidString,
                        "captured_at": SQLiteTimestamp.string(from: entry.capturedAt),
                        "summary": entry.summary,
                        "verification_state": VerificationState.unverified.rawValue
                    ]
                ])
            }
            let root: [String: Any] = [
                "type": "FeatureCollection",
                "note": StructureFlag.disclaimer,
                "features": features
            ]
            return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        }
    }

    /// Every journal row this contributor owns, followed across the cursor to the end.
    ///
    /// The export used to take page one and drop the cursor, so a subject-access request — which
    /// this method's own doc comment names as a use case — came back capped at 100 rows with
    /// nothing saying so (ERRATA E39). An export that silently stops is worse than one that fails:
    /// the person holding it has no way to tell it is short.
    ///
    /// Termination is not an assumption: `journal` only returns a cursor when the page came back
    /// full, and each page asks for rows strictly older than the last one seen, so the window moves
    /// backwards every time and the rows are finite.
    private func wholeJournal() async throws -> [JournalEntry] {
        var entries: [JournalEntry] = []
        var cursor: String?
        repeat {
            let page = try await journal(cursor: cursor, limit: Page<JournalEntry>.maximumLimit)
            entries.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return entries
    }

    static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Name resolution

    private func treeIfPresent(_ id: UUID) async throws -> Tree? {
        try await store.queue.read { connection -> Tree? in
            if let record = try treeQueries?.tree(id: id, connection: connection) { return record.tree }
            return try communityTrees.tree(id: id, connection: connection)
        }
    }

    /// The name a tree shows: its one active nickname, else the species common name (D15). Never a
    /// fabricated label.
    public func displayNameIfPresent(for id: UUID) async throws -> String? {
        try await store.queue.read { connection -> String? in
            if let name = try contributions.activeName(treeID: id, connection: connection) {
                return name.name
            }
            guard let record = try treeQueries?.tree(id: id, connection: connection) else { return nil }
            return record.species?.commonName
        }
    }

    /// Resolves several tree names in one pass, for `OutboxViewState`.
    public func displayNames(for ids: [UUID]) async -> [UUID: String] {
        var names: [UUID: String] = [:]
        for id in ids {
            if let name = try? await displayNameIfPresent(for: id), !name.isEmpty {
                names[id] = name
            }
        }
        return names
    }
}

private extension String {
    var replacingUnderscores: String { replacingOccurrences(of: "_", with: " ") }
}
