import Foundation

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
    /// Where photo binaries live once "uploaded". `LocalAPI`'s upload is a move into this
    /// directory, which is what makes the outbox's photo phase exercisable with no network.
    private let photoDirectory: URL

    public init(
        store: CypressStore,
        deviceID: UUID,
        userID: UUID? = nil,
        photoDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.deviceID = deviceID
        self.userID = userID
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

    public func mapContent(in viewport: MapViewport) async throws -> MapContent {
        let seedContent = try await store.queue.read { connection -> MapContent in
            guard let treeQueries else {
                return viewport.shouldCluster ? .clusters([]) : .pins([])
            }
            return try treeQueries.mapContent(in: viewport, connection: connection)
        }

        // Community-added trees live in `main` and are merged here rather than unioned in SQL. See
        // `CommunityTreeStore` for why.
        let added = try await store.queue.read { connection in
            try communityTrees.inBounds(viewport.bounds, limit: viewport.pinLimit, connection: connection)
        }
        guard !added.isEmpty else { return seedContent }

        switch seedContent {
        case let .pins(pins):
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
            return .pins(Array(pins.prefix(seedBudget)) + communityPins)

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
            guard let tree = inventoryTree else { throw APIError.notFound }

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
                ownPhotoIDs: Set(photos.items.map(\.id))
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
                        .map { CoverageTree(id: $0.treeID, distanceM: coordinate.distance(to: $0.coordinate)) }
                        .sorted { $0.distanceM < $1.distanceM },
                    isComplete: isComplete
                )
            )

            // --- Where a tree could go. The one block that inverts `standing`: the planting sites
            // with no tree in them. A count of city records, so it draws on a fresh install like the
            // species mix does — no contribution needed (R10, ERRATA E121).
            let sites = try almanacQueries.vacantSites(neighborhoodID: area.id, near: coordinate, connection: connection)
            let vacantSites = sites.count > 0
                ? VacantSites(count: sites.count, nearestID: sites.nearestID)
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

    /// `GET /me/outbox-status`.
    ///
    /// The local store has no separate server-side record of recent sync results; the outbox rows
    /// are that record. This returns the settled state of every row so screen 17's "says why" line
    /// has the same shape it will have against the real service.
    public func outboxStatus() async throws -> [SyncResult] {
        let records = try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection)
        }
        return records.map { record in
            switch record.item.state {
            case .done:
                return SyncResult(clientUUID: record.item.clientUUID, status: .applied)
            case .failed:
                return SyncResult(
                    clientUUID: record.item.clientUUID,
                    status: .failed,
                    error: record.item.lastErrorCode ?? .serverError
                )
            case .pending, .uploading:
                return SyncResult(clientUUID: record.item.clientUUID, status: .failed, error: record.item.lastErrorCode)
            }
        }
    }

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
    }

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
