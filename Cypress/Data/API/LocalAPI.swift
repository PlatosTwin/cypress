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
    private let assertions = SpeciesAssertionStore()
    private let groveQueries: GroveQueries?
    private let almanacQueries: AlmanacQueries?
    private let cityQueries: CityQueries?
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
    /// one of the fifteen serialized round-trips per pan (ERRATA E130).
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
        self.cityQueries = store.seed.map { CityQueries(schema: $0) }
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
    /// where the map needed one, ten of them returning results already in hand, all of it serialized
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
            //
            // **Every narrowing, not just the species one (#116).** Each is the same leak in a
            // different color: a `Favorites` map that drew every community tree in the box would
            // be claiming the reader had hearted them, and a `2010s` map that drew a community tree
            // with no planting year would be claiming the city planted it in a decade nobody
            // recorded. The year clause is deliberately `false` for a nil year, matching the SQL's
            // `planted_year IS NOT NULL` on the seed side exactly — see ERRATA E175.
            //
            // **The two `siteKind` clauses mirror `TreeQueries.Narrowing.predicate` term for term**
            // (tasks #178, #179), and they have to: a narrowing that reached the seed's SQL but not
            // this filter would draw community vacant sites under a year while the city's own were
            // correctly excluded — one filter telling two stories depending on who added the row.
            // `MapSiteKind.of` is the single definition both sides call.
            //
            // **The two condition chips are here for the same reason** (task #240). `In bloom` is a
            // species narrowing, so it is resolved to the same uuid set the seed's SQL resolves —
            // through `TreeQueries.bloomingSpeciesIDs`, the one definition — and intersected with
            // any typed or tapped species exactly as `TreeQueries.narrowing` intersects them. A
            // community tree drawn under `Needs care` while the city's own were correctly excluded
            // would be the dashed layer claiming *the community found you a tree that needs
            // something*, which is the most convincing possible way to be wrong.
            // `?? []` rather than `flatMap`: with no seed attached there is no bloom calendar, and
            // the honest answer to "which species bloom this month" is then *none*. Letting it
            // collapse to nil would read as "no narrowing" and draw the whole community layer under
            // a chip that admitted nothing — the `[]` versus `nil` distinction R23 spends three
            // paragraphs on, one layer down.
            let bloomingSpecies: Set<UUID>? = try viewport.bloomMonth.map { month in
                try treeQueries?.bloomingSpeciesIDs(month: month, connection: connection) ?? []
            }
            let added = allAdded.filter { tree in
                if let wanted = viewport.speciesIDs {
                    guard let id = tree.speciesCurrentID, wanted.contains(id) else { return false }
                }
                if let blooming = bloomingSpecies {
                    guard let id = tree.speciesCurrentID, blooming.contains(id) else { return false }
                }
                if viewport.needsCare, !tree.status.needsCare { return false }
                if let wanted = viewport.treeIDs, !wanted.contains(tree.id) { return false }
                if let years = viewport.plantedYears {
                    guard let planted = tree.plantedYear, years.contains(planted) else { return false }
                    // Task #178: a planting date on a site with no tree is the date of a tree that
                    // is gone, so it never answers "planted in the 2010s".
                    guard MapSiteKind.of(tree.status) == .hasTree else { return false }
                }
                if let wanted = viewport.siteKind, MapSiteKind.of(tree.status) != wanted {
                    return false
                }
                return true
            }

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
            let centerLatitude = (viewport.bounds.minLatitude + viewport.bounds.maxLatitude) / 2
            let cell = TreeQueries.cellSize(zoom: viewport.zoom, centerLatitude: centerLatitude)
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

            // A withdrawn community record is not a tree (task **#125**). `CommunityTreeStore.tree`
            // is the one read in that file which does *not* filter `deleted_at`, deliberately, so a
            // withdrawal can be read back; every other read already skips the row, so the pin is
            // already gone. This is the screen that would otherwise still draw the whole profile —
            // reachable from a favorite, a deep link or a back stack — with every contribution
            // control on it, which is exactly the state the confirmation exists to end. Scoped to
            // community rows: the seed's own soft deletes are `seedHasSoftDeletedTrees`' question
            // and are answered a layer down, in `TreeQueries`.
            if tree.source == .community, tree.deletedAt != nil { throw APIError.notFound }

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
                cityShortName: record?.cityShortName,
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
                // A narrower set, and the narrowing is the whole of it: seeing a photograph and
                // being allowed to unmake it are two questions (`TreeProfile.deletablePhotoIDs`).
                // Read in the same transaction as the photographs so a control cannot be drawn on a
                // row that has since gone.
                deletablePhotoIDs: try contributions.deletablePhotoIDs(
                    treeID: id, attribution: attribution, connection: connection
                ),
                // *Why* a row is in the first set and not the second, read off the row itself
                // rather than worked out from the difference between the two (task #131). Same
                // transaction again, so the sentence a screen draws about a photograph and the
                // control it draws beside it cannot come from two different moments.
                anonymizedPhotoIDs: try contributions.anonymizedPhotoIDs(
                    treeID: id, connection: connection
                ),
                // Read in the same transaction as the photographs, so the hero and the list that
                // can change it are computed from one consistent picture (ERRATA E125).
                photoTallies: try contributions.photoTallies(
                    treeID: id, owner: FavoriteOwner(attribution), connection: connection
                ),
                // Where this record came from and when it was read, from the seed's own build
                // receipt. `record` is nil for a community-added tree — that one is nobody's city
                // record and gets no provenance line, rather than one crediting an inventory it was
                // never in.
                //
                // **This row's inventory, not the file's.** The seed holds rows from both of San
                // Francisco's street-tree inventories: the living trees are SF Public Works'
                // operational layer, and the 12,260 vacant planting sites are the DataSF export's,
                // because the layer has no vacant-site category to have listed them in. The
                // seed-wide `seedProvenance` would put the city's name and the city's snapshot date
                // over every one of those sites, which is a sentence about a record the city has
                // never held. A seed built before `trees.inventory_source` existed reports nil there
                // and falls back to the file's answer, which is correct for it.
                inventorySource: Self.provenance(of: record, in: store),
                // Read in the same transaction as the tree it is about: the offer is a statement
                // about the chain's head and the reports against it, and a control drawn from one
                // moment's answer against another moment's species is a control that offers to
                // correct something that has already been corrected.
                speciesCorrection: try speciesCorrectionOffer(tree: tree, connection: connection),
                // Same transaction, same reason (task #125): the offer is a statement about the
                // open reports against this record, and a control drawn from one moment's answer
                // over another moment's record offers to withdraw something already withdrawn.
                recordDefect: try recordDefectOffer(tree: tree, connection: connection)
            )
        }
    }

    /// The inventory that listed one seed row, or nil for a tree no inventory listed.
    ///
    /// Nil for a community-added tree (`record` is nil) for the reason at the call site. Nil also
    /// when the row names an inventory the receipt does not describe, which is a seed built by a
    /// pipeline this build has never seen: an unnameable source renders as no provenance line at
    /// all, never as the other inventory's name.
    static func provenance(of record: TreeQueries.TreeRecord?, in store: CypressStore) -> InventorySource? {
        guard let record else { return nil }
        guard let id = record.inventorySourceID else { return store.seedProvenance }
        return store.seedInventories[id]
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
            // searched: both halves re-check the exact meters (`TreeQueries.nearest`,
            // `CommunityTreeStore.near`). That is load-bearing — this line turns a candidate into a
            // permanent refusal, and it used to fire out to 14.1 m on the diagonal (ERRATA E35).
            //
            // §6 returns `conflict` with the candidate list. `ProximityConflict` carries the list;
            // the taxonomy code is what the outbox and the error banner read, and `conflict` is not
            // retryable, so the item will not burn 48 h on an answer the user has to give.
            throw ProximityConflict(candidates: candidates)
        }

        // ── The one ingest this method *is* ────────────────────────────────────────────────────────
        // Every other photograph in the app becomes a record by being uploaded, and `uploadPhoto`
        // strips it on the way past. This one never is: the row below keeps `local_path` pointing at
        // the staged capture for the life of the installation, so nothing downstream was ever going
        // to clean it and nothing did, from E127 until E148. The capture path strips at the shutter
        // now, which makes this a header read that finds nothing — and it is here anyway,
        // because the column belongs to this layer and a privacy invariant that lives only in the
        // screen that happens to fill the field in is one the next screen will not know about.
        //
        // Deliberately after the dedupe: a photograph whose tree is a duplicate is not being ingested
        // at all, and rewriting a file for a record that is about to be refused is work for nothing.
        try PhotoBinary.stripMetadataInPlace(atPath: draft.photoLocalPath)

        let moment = now()
        let tree = Tree(
            source: .community,
            coordinate: draft.coordinate,
            address: draft.address,
            status: .alive,
            speciesCurrentID: draft.speciesID,
            verificationState: .unverified,
            placement: draft.placement,
            statedLandContext: draft.landContext,
            createdAt: moment,
            updatedAt: moment
        )

        try await store.queue.write { connection in
            try communityTrees.insert(tree, clientUUID: draft.clientUUID, connection: connection)
            // The "at the same time" half of the species request opens the chain, exactly as
            // `claimSpecies` does for the "after" half (AppSchema v14). A tree added *with* a species
            // and a tree named afterwards must end in the same state, or one of the two would be
            // uncorrectable by the person who named it — which is the whole of ticket #86.
            if let speciesID = draft.speciesID {
                try assertions.insert(
                    SpeciesAssertion(
                        treeID: tree.id,
                        speciesID: speciesID,
                        source: .community,
                        owner: ContributionOwner(attribution),
                        createdAt: moment,
                        updatedAt: moment
                    ),
                    connection: connection
                )
            }
            let photo = Photo(
                treeID: tree.id,
                shotType: .fullTree,
                capturedAt: moment,
                createdAt: moment,
                updatedAt: moment
            )
            try contributions.insert(
                photo,
                localPath: draft.photoLocalPath,
                owner: PhotoOwner(attribution),
                connection: connection
            )
        }
        return tree
    }

    /// Names the species on a community tree that has none. `SpeciesClaim` carries the argument for
    /// why this is the only species write on device and why it refuses the other two cases.
    ///
    /// The species id is checked against the catalog **first**. `community_trees.species_current`
    /// is a bare TEXT column with no foreign key — it cannot have one, because the `species` table it
    /// would point at is in an ATTACHed database and SQLite does not do cross-database references —
    /// so nothing but this line stops a caller from writing a uuid that resolves to no species at
    /// all. That row would decode fine and then render as a tree with a species nobody can look up.
    public func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        _ = try await species(id: speciesID)
        let moment = now()

        let subject = try await store.queue.read { connection -> Tree? in
            try communityTrees.tree(id: treeID, connection: connection)
        }
        guard let subject else {
            // Not in `main`. If the seed has it then it is a city row, and the refusal is
            // `.forbidden` rather than `.notFound` — the tree is real and this is not allowed, which
            // is a different sentence from "there is no such tree" and the screen says both.
            let isCityRow = try await store.queue.read { connection -> Bool in
                let record = try treeQueries?.tree(id: treeID, connection: connection)
                return record.flatMap { $0 } != nil
            }
            throw isCityRow ? APIError.forbidden : APIError.notFound
        }
        guard subject.speciesCurrentID == nil else { throw APIError.conflict }

        let owner = ContributionOwner(attribution)
        try await store.queue.write { connection in
            guard try communityTrees.claimSpecies(
                treeID: treeID, speciesID: speciesID, at: moment, connection: connection
            ) else {
                // The UPDATE's own `species_current IS NULL` refused what the read above allowed:
                // somebody claimed it in between, or the row is soft-deleted. Both are conflicts, and
                // this branch is why the guard is in the SQL and not only in Swift.
                throw APIError.conflict
            }
            // The chain's head, in the same transaction as the read cache it is the head of
            // (AppSchema v14). Two writes that could land apart would leave a species with no
            // assertion behind it — the one state `correctSpecies` cannot append to, and the state
            // every pre-v14 row is already stuck in.
            try assertions.insert(
                SpeciesAssertion(
                    treeID: treeID,
                    speciesID: speciesID,
                    source: .community,
                    owner: owner,
                    createdAt: moment,
                    updatedAt: moment
                ),
                connection: connection
            )
        }

        return try await treeProfile(id: treeID).tree
    }

    /// Corrects the species on a community tree — the transition `SpeciesClaim` refused for want of
    /// a chain, and the chain now exists (AppSchema v14). Tickets **#86** and **#124**.
    ///
    /// Nothing is overwritten. The claim in force is stamped `superseded_by` and keeps its row, a new
    /// assertion is appended, and `community_trees.species_current` is moved to match — one
    /// transaction, because the column is a read cache of the chain's head and a cache that can land
    /// without its source is a cache that can disagree with it.
    ///
    /// ── Who may do it ───────────────────────────────────────────────────────────────────────────
    /// `RULINGS R45` carries the argument; the rule is two arms:
    ///
    /// 1. **The author of the claim in force, always.** D15's "first namer wins" exists to stop one
    ///    contributor discarding another's statement; where the two are the same person there is no
    ///    statement to protect, and refusing is only a refusal to admit a mistake. Identity is
    ///    `Attribution` — the account when signed in, this device otherwise (D9) — through
    ///    `ContributionOwner.isOwned(by:)`.
    /// 2. **A lead, but only in answer to a report.** `canConfirmReviewFlag` is not a license to
    ///    rewrite anybody's species at will: it is the authority to resolve a `wrong_species` flag
    ///    somebody actually raised, which is why the second arm requires one to be open. A lead with
    ///    an opinion and no report in front of them is a contributor, and takes arm 1's route.
    ///
    /// Everybody else gets `.forbidden` and the `flagWrongSpecies` route. An assertion owned by
    /// **nobody** — every claim made before v14, whose author the database never recorded — is
    /// nobody's to overwrite either, and takes the same route.
    ///
    /// Resolving the report *is* the correction, so an open `wrong_species` flag on this tree moves
    /// to `confirmed` here rather than through a second verb somebody could forget. **No status is
    /// written**, by either arm: a wrong species is not a statement about whether the tree is alive,
    /// and `ReviewFlag.Kind.Resolution` keeps the two seams apart so this cannot drift into the one
    /// that moves `trees.status` (ERRATA E170).
    public func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree {
        // The catalog check first, for `claimSpecies`' reason: `species_current` and
        // `species_uuid` are bare TEXT with no foreign key available to them, so nothing but this
        // line stops a uuid that resolves to no species from being written and rendering as a tree
        // whose species nobody can look up.
        _ = try await species(id: speciesID)
        let moment = now()
        let mine = attribution
        let isLead = userRole.canConfirmReviewFlag

        let (head, openFlags) = try await store.queue.read {
            connection -> (SpeciesAssertion?, [ReviewFlag]) in
            guard try communityTrees.tree(id: treeID, connection: connection) != nil else {
                // Same two-armed refusal `claimSpecies` makes, and for the same reason: a city row is
                // real and this is not allowed, which is a different sentence from "no such tree".
                let record = try treeQueries?.tree(id: treeID, connection: connection)
                throw record.flatMap { $0 } != nil ? APIError.forbidden : APIError.notFound
            }
            return (
                try assertions.current(treeID: treeID, connection: connection),
                try Self.openSpeciesReviews(treeID: treeID, store: contributions, connection: connection)
            )
        }

        // No head is not "nothing to correct by accident": it is a tree nobody has named, and naming
        // one is `claimSpecies`. Saying so is better than appending a first assertion here and
        // letting two verbs write the same row for different reasons.
        guard let head else { throw APIError.validationFailed }
        guard head.isSupersedable(by: mine) || (isLead && !openFlags.isEmpty) else {
            throw APIError.forbidden
        }

        let successor = SpeciesAssertion(
            treeID: treeID,
            speciesID: speciesID,
            source: .community,
            owner: ContributionOwner(mine),
            createdAt: moment,
            updatedAt: moment
        )
        try await store.queue.write { connection in
            // Stamp before insert, never after. The partial unique index allows one unsuperseded row
            // per tree, so inserting first would be refused by the engine — which is the index doing
            // its job, and is also why the order is not a matter of taste.
            guard try assertions.supersede(
                id: head.id, with: successor.id, at: moment, connection: connection
            ) else {
                // Somebody superseded this head between the read and the write. Their correction
                // stands; this one is not silently layered on top of it.
                throw APIError.conflict
            }
            try assertions.insert(successor, connection: connection)
            guard try communityTrees.setSpecies(
                treeID: treeID, speciesID: speciesID, at: moment, connection: connection
            ) else {
                throw APIError.conflict
            }
            for flag in openFlags {
                try contributions.confirmReviewFlag(id: flag.id, at: moment, connection: connection)
            }
        }

        return try await treeProfile(id: treeID).tree
    }

    /// Reports the species on a community tree as wrong — ticket **#124**, the half of the
    /// correction path that belongs to somebody who is not the namer.
    ///
    /// Raises a `wrong_species` review flag and **changes nothing else**. `species_current` still
    /// says what the namer said, because a report is a disagreement on the record and not a decision;
    /// deciding is `correctSpecies`, and who may decide is the ruling.
    ///
    /// Refused when the claim is **yours** (`.validationFailed`): reporting your own statement to be
    /// reviewed is not a thing to do with it, you correct it, and a surface offering both would be
    /// offering a worse version of the same act.
    ///
    /// Refused when a report is already open (`.conflict`). BUILD-PLAN §6's "two offline users
    /// flagging the same tree produce two flags on one thread, not a conflict" is about the *sync
    /// merge* — two devices that could not see each other — and this write is neither. Here the
    /// person can see the open report on the screen they are tapping from, and a second one says
    /// nothing the first did not.
    public func flagWrongSpecies(treeID: UUID) async throws {
        let moment = now()
        let mine = attribution
        let raiser = userID

        let head = try await store.queue.read { connection -> SpeciesAssertion? in
            guard try communityTrees.tree(id: treeID, connection: connection) != nil else {
                let record = try treeQueries?.tree(id: treeID, connection: connection)
                throw record.flatMap { $0 } != nil ? APIError.forbidden : APIError.notFound
            }
            guard try Self.openSpeciesReviews(
                treeID: treeID, store: contributions, connection: connection
            ).isEmpty else { throw APIError.conflict }
            return try assertions.current(treeID: treeID, connection: connection)
        }

        guard let head else { throw APIError.validationFailed }
        guard !head.isSupersedable(by: mine) else { throw APIError.validationFailed }

        let flag = ReviewFlag(
            treeID: treeID,
            kind: .wrongSpecies,
            raisedBy: raiser,
            createdAt: moment,
            updatedAt: moment
        )
        try await store.queue.write { connection in
            try contributions.insert(flag, connection: connection)
        }
    }

    /// Closes a `wrong_species` report without changing the species — the second verb E170 taught
    /// this queue to have, on the species seam rather than the status one.
    ///
    /// Nothing is appended and no status is written: dismissing says the species on record is right
    /// after all, and it already says what it says. The flag row records that somebody looked.
    ///
    /// Same two arms as `correctSpecies`, minus the report requirement on the second: a lead may
    /// dismiss any species report, and the author of the disputed claim may answer one raised against
    /// their own statement. The author's arm is what keeps this loop closed on a phone with no lead
    /// on it — the alternative is a report nobody present can resolve, which is precisely the state
    /// E170 exists about.
    public func dismissSpeciesReview(flagID: UUID) async throws {
        let moment = now()
        let mine = attribution
        let isLead = userRole.canConfirmReviewFlag

        let (flag, head) = try await store.queue.read {
            connection -> (ReviewFlag, SpeciesAssertion?) in
            guard let flag = try contributions.reviewFlag(id: flagID, connection: connection),
                  flag.deletedAt == nil else { throw APIError.notFound }
            return (flag, try assertions.current(treeID: flag.treeID, connection: connection))
        }
        guard flag.kind.resolution == .speciesAssertion else { throw APIError.validationFailed }
        guard flag.status == .open else { throw APIError.conflict }
        guard isLead || (head?.isSupersedable(by: mine) ?? false) else { throw APIError.forbidden }

        try await store.queue.write { connection in
            try contributions.dismissReviewFlag(id: flagID, at: moment, connection: connection)
        }
    }

    /// The open species reports on one tree. Read through `speciesReviewKinds` rather than naming
    /// `.wrongSpecies`, so this cannot drift out of step with the seam the way the removal queue did
    /// before E170.
    private static func openSpeciesReviews(
        treeID: UUID,
        store: ContributionStore,
        connection: SQLiteConnection
    ) throws -> [ReviewFlag] {
        try store.openReviewFlags(kinds: ReviewFlag.Kind.speciesReviewKinds, connection: connection)
            .filter { $0.treeID == treeID }
    }

    /// What this viewer may do about the species on this tree, decided where the identity and the
    /// role live rather than in a view (`SpeciesCorrectionOffer`).
    private func speciesCorrectionOffer(
        tree: Tree,
        connection: SQLiteConnection
    ) throws -> SpeciesCorrectionOffer {
        guard tree.source == .community, tree.speciesCurrentID != nil else { return .unavailable }
        let head = try assertions.current(treeID: tree.id, connection: connection)
        let isMine = head?.isSupersedable(by: attribution) ?? false
        let reported = try Self.openSpeciesReviews(
            treeID: tree.id, store: contributions, connection: connection
        ).first
        if let reported {
            return .underReview(
                flagID: reported.id,
                canResolve: isMine || userRole.canConfirmReviewFlag
            )
        }
        guard head != nil else { return .unavailable }
        return isMine ? .correctable : .reportable
    }

    // MARK: - The record itself (task #125)

    /// Reports a record as never having held a tree — the owner's *"a way to flag that a tree that
    /// is listed on the map doesn't appear to exist at all"*.
    ///
    /// Raises a `never_existed` flag and **changes nothing else**, exactly as `flagWrongSpecies`
    /// does: a report is a disagreement on the record, not a decision about it.
    ///
    /// **Community rows only, and the refusal is load-bearing rather than a limitation to be lifted
    /// later without thought.** A city row lives in the ATTACHed read-only seed; nothing on this
    /// device can withdraw one, and there is no suppression path parallel to `tree_status_overrides`
    /// for a row that should not be in the inventory. So a report against a city row is a report
    /// nothing can resolve, which is the E170 defect being shipped deliberately. `RULINGS R45`
    /// refuses `wrong_species` on a city row in the same words, and `RULINGS R50` names the ticket
    /// that would lift this one.
    ///
    /// Refused when a report is already open (`.conflict`), on `flagWrongSpecies`' reasoning:
    /// BUILD-PLAN §6's "two offline users flagging the same tree produce two flags on one thread"
    /// governs the sync merge between devices that could not see each other, and this is a local
    /// write by somebody looking at the open report on their own screen.
    public func flagNeverExisted(treeID: UUID) async throws {
        let moment = now()
        let raiser = userID

        try await store.queue.read { (connection: SQLiteConnection) -> Void in
            // `let` and then the `deletedAt` check, not one optional-chained comparison: a missing
            // row makes `tree(id:)?.deletedAt` nil, and `nil == nil` would have read a record that
            // is not there as a live one.
            guard let community = try communityTrees.tree(id: treeID, connection: connection),
                  community.deletedAt == nil else {
                // Either there is no community row, or it has already been withdrawn. A seed row
                // reaching here is the city case and is refused; anything else is simply not there.
                let record = try treeQueries?.tree(id: treeID, connection: connection)
                throw record.flatMap { $0 } != nil ? APIError.forbidden : APIError.notFound
            }
            guard try Self.openRecordReviews(
                treeID: treeID, store: contributions, connection: connection
            ).isEmpty else { throw APIError.conflict }
        }

        let flag = ReviewFlag(
            treeID: treeID,
            kind: .neverExisted,
            raisedBy: raiser,
            createdAt: moment,
            updatedAt: moment
        )
        try await store.queue.write { connection in
            try contributions.insert(flag, connection: connection)
        }
    }

    /// A lead confirms a `never_existed` report: the flag moves to `confirmed` and the record is
    /// withdrawn — the `community_trees` row is soft-deleted — in one transaction.
    ///
    /// **`trees.status` is not touched, and this is the whole of R46.** Confirming `appears_removed`
    /// writes `TreeStatus.removed`, which is a memorial (screen 19, gray pin, no new
    /// contributions); a record that never had a tree behind it must not get a memorial for a tree
    /// that never lived. `TreeStatus.vacantSite` is the other tempting answer and is refused for
    /// R7's reason — a vacant site is a planting site with its tree missing, and a duplicate pin or
    /// a record inside a building is not one. `ReviewFlag.Kind.confirmedStatus` stays nil here, so
    /// this flag never enters `openReviews`, and no status can be written by accident.
    ///
    /// Gated on `userRole.canConfirmReviewFlag` (DECISIONS §3.7), and the gate is on the write, so a
    /// surface drawn in error cannot withdraw a record. There is no author's arm the way the species
    /// seam has one: `community_trees` records no author at all (R45's finding, unchanged), so there
    /// is nobody whose own record this is to take back.
    public func withdrawRecord(flagID: UUID) async throws {
        guard userRole.canConfirmReviewFlag else { throw APIError.forbidden }
        let moment = now()
        try await store.queue.write { connection in
            guard let flag = try contributions.reviewFlag(id: flagID, connection: connection),
                  flag.deletedAt == nil else {
                throw APIError.notFound
            }
            guard flag.kind.resolution == .recordWithdrawal else { throw APIError.validationFailed }
            guard flag.status == .open else { throw APIError.conflict }

            try contributions.confirmReviewFlag(id: flagID, at: moment, connection: connection)
            // `false` means the row was withdrawn between the read and this write. The flag is still
            // correctly confirmed — the record is gone, which is what the report asked for — so this
            // is not an error, and raising one would roll back a confirmation of a true report.
            _ = try communityTrees.withdraw(treeID: flag.treeID, at: moment, connection: connection)
        }
    }

    /// A lead closes a `never_existed` report leaving the record where it is.
    ///
    /// Nothing is withdrawn and no status is written, on `dismissReview`'s argument: dismissing says
    /// the reported defect is not there, and the record already says what it says. The flag row
    /// records who looked. Same gate as the confirm, for the same reason — both are the resolution
    /// of somebody else's report.
    public func dismissRecordReview(flagID: UUID) async throws {
        guard userRole.canConfirmReviewFlag else { throw APIError.forbidden }
        let moment = now()
        try await store.queue.write { connection in
            guard let flag = try contributions.reviewFlag(id: flagID, connection: connection),
                  flag.deletedAt == nil else {
                throw APIError.notFound
            }
            guard flag.kind.resolution == .recordWithdrawal else { throw APIError.validationFailed }
            guard flag.status == .open else { throw APIError.conflict }

            try contributions.dismissReviewFlag(id: flagID, at: moment, connection: connection)
        }
    }

    /// The open record-defect reports on one tree. Read through `recordReviewKinds` rather than by
    /// naming `.neverExisted`, so this cannot drift out of step with the seam the way the removal
    /// queue did before E170.
    private static func openRecordReviews(
        treeID: UUID,
        store: ContributionStore,
        connection: SQLiteConnection
    ) throws -> [ReviewFlag] {
        try store.openReviewFlags(kinds: ReviewFlag.Kind.recordReviewKinds, connection: connection)
            .filter { $0.treeID == treeID }
    }

    /// What this viewer may do about the record itself, decided where the role lives rather than in
    /// a view (`RecordDefectOffer`).
    ///
    /// A city row is `.unavailable` rather than `.reportable`, matching what `flagNeverExisted`
    /// would do with the tap: a control that exists only to be refused is worse than no control.
    private func recordDefectOffer(
        tree: Tree,
        connection: SQLiteConnection
    ) throws -> RecordDefectOffer {
        guard tree.source == .community, tree.deletedAt == nil else { return .unavailable }
        if let reported = try Self.openRecordReviews(
            treeID: tree.id, store: contributions, connection: connection
        ).first {
            return .underReview(flagID: reported.id, canResolve: userRole.canConfirmReviewFlag)
        }
        return .reportable
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
    /// neighborhood they are scoped to and the individuals listed under them are one statement
    /// about the inventory, and three separate reads could straddle a write and disagree.
    ///
    /// **Every population fact here is a whole read.** `cityTreeCount` is a `COUNT(*)`, not the size
    /// of a page; each nearby tree's photo count comes from `photos(treeID:)` with no limit, so
    /// `Series.totalCount` is non-nil and the screen may print it (ERRATA E38). The nearby list
    /// itself *is* limited, and says so — it is the one series on this screen nothing counts.
    ///
    /// Without a fix there is no "your area" and no distance to draw, so `nearYou` and `nearby` are
    /// simply absent. That is not a degraded state to apologize for on screen; it is two surfaces
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

            // --- Which area `Near you` is about (RULINGS R29, the same resolution `almanac` makes).
            //
            // The polygon first, because a named place is a better subject than a distance; then
            // the stated radius, so a city whose inventory is merged but whose boundaries are not
            // still has a `Near you` card the day its trees land — the card silently not drawing
            // for every San Jose reader was this screen's share of the defect family E182 closed.
            // Then nothing: a circle around a reader the record does not cover is not an area, and
            // `holdsAnyRecord` is what keeps a true `0` (none of these grow in your covered area)
            // distinct from a card counting ground the inventory has never seen.
            let scope: AlmanacScope?
            if let polygon = try speciesQueries.resolveNeighborhood(near: coordinate, connection: connection) {
                scope = .neighborhood(id: polygon.id, name: polygon.name)
            } else if let almanacQueries {
                let fallback = AlmanacScope.radius(
                    center: coordinate,
                    meters: AlmanacLimits.fallbackRadiusM
                )
                scope = try almanacQueries.holdsAnyRecord(scope: fallback, connection: connection)
                    ? fallback : nil
            } else {
                scope = nil
            }

            let nearYou = try scope.map { scope in
                SpeciesNeighborhoodCount(
                    area: scope.area,
                    count: try speciesQueries.treeCount(
                        speciesID: id,
                        scope: scope,
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
            let drawnCandidates = candidates.prefix(SpeciesGuideLimits.nearbyRowLimit)

            // Which photograph each row draws, one statement for the whole section (ERRATA E204) —
            // not `heroPhotoIDs()`'s unscoped shape, which would scan this device's entire photo
            // library to answer a two-or-three-tree question. See that method's own comment.
            // `attribution` is required here and not on `heroPhotoIDs()` above (ERRATA E215): these
            // candidates are not "this device's own trees", so a photograph the read finds may be a
            // stranger's, and only `attribution`'s own rows may lead with an unmoderated one.
            let heroPhotoIDs = try contributions.heroPhotoIDs(
                treeIDs: Set(drawnCandidates.map(\.tree.id)),
                attribution: attribution,
                connection: connection
            )

            let rows = try drawnCandidates.map { candidate in
                NearbySpeciesTree(
                    treeID: candidate.tree.id,
                    title: try contributions.activeName(treeID: candidate.tree.id, connection: connection)?.name
                        ?? candidate.tree.address,
                    distanceM: candidate.distanceM,
                    photoCount: try contributions.photos(treeID: candidate.tree.id, connection: connection).totalCount,
                    vitality: try contributions.latestObservation(treeID: candidate.tree.id, connection: connection)?.vitality,
                    heroPhotoID: heroPhotoIDs[candidate.tree.id]
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

    /// Screen 12's payload: what is happening to the trees in one neighborhood.
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
    /// the bloom and the coverage list are one statement about one neighborhood, and five separate
    /// reads could straddle a write and disagree about it.
    ///
    /// Without a fix there is no area and the whole payload is empty. That is not a degraded state
    /// to apologize for; it is a screen whose subject does not exist.
    public func almanac(near coordinate: Coordinate?) async throws -> Almanac {
        guard let coordinate, let speciesQueries, let almanacQueries else { return .empty }
        let moment = now()
        let calendar = Calendar.current

        return try await store.queue.readConsistently { connection -> Almanac in
            // --- What this almanac is about (RULINGS R29, ERRATA E182).
            //
            // The polygon first, because a named place is a better subject than a distance: its
            // boundary is the city's, it has a name the reader knows, and — the part a radius cannot
            // do — it is the *same area for everybody standing in it*, so the elder and the nine
            // young trees are facts about a place rather than about where one person happens to be.
            //
            // Then the radius, because under D16 the record is every municipal inventory in the
            // country and most of those cities publish no boundary set we hold. Requiring one would
            // make a city's trees invisible until somebody sourced it — which is exactly the state
            // San Jose's 52,788 rows were in (E176).
            //
            // Then nothing, and the screen says so. A circle drawn around a reader in Sacramento is
            // a perfectly well-formed area with no record in it, and heading a blank screen with a
            // distance would be claiming ground the inventory has never covered.
            let scope: AlmanacScope
            if let polygon = try speciesQueries.resolveNeighborhood(near: coordinate, connection: connection) {
                scope = .neighborhood(id: polygon.id, name: polygon.name)
            } else {
                let fallback = AlmanacScope.radius(
                    center: coordinate,
                    meters: AlmanacLimits.fallbackRadiusM
                )
                guard try almanacQueries.holdsAnyRecord(scope: fallback, connection: connection) else {
                    return .empty
                }
                scope = fallback
            }

            // --- Who lives here. City data, so this is the one block a fresh install draws whole
            // (A9: "species mix always renders from city data").
            let mix = try almanacQueries.speciesMix(scope: scope, connection: connection)
            let composition = mix.isEmpty ? nil : NeighborhoodComposition(
                distinctSpeciesCount: mix.count,
                treeCount: mix.reduce(0) { $0 + $1.treeCount },
                leading: mix
            )

            // --- Which photograph each season row leads with, if either subject has one on this
            // device (#176). One statement, reused for both rows below — `heroPhotoIDs` is already
            // built for "the whole grove in one read" and two lookups cost nothing extra.
            let heroPhotoIDs = try contributions.heroPhotoIDs(connection: connection)

            // --- The elder. The active name is a `main` row and the tree is a `seed` row, so the
            // two are read separately and joined here rather than across the attach boundary.
            let elder = try almanacQueries.elder(scope: scope, connection: connection)
                .map { found in
                    ElderTree(
                        treeID: found.treeID,
                        activeName: try contributions.activeName(treeID: found.treeID, connection: connection)?.name,
                        speciesCommonName: found.speciesCommonName,
                        address: found.address,
                        plantedYear: found.plantedYear,
                        heroPhotoID: heroPhotoIDs[found.treeID]
                    )
                }

            // --- Newest neighbors. Absent outside spring, because the drawn copy has a word for
            // exactly one season and inventing the others is inventing (DECISIONS constraint 21).
            var newestNeighbors: RecentPlanting?
            if let spring = AlmanacWindow.currentSpring(now: moment, calendar: calendar) {
                let planted = try almanacQueries.plantings(
                    scope: scope,
                    from: spring.from,
                    to: spring.to,
                    connection: connection
                )
                let total = planted.reduce(0) { $0 + $1.treeCount }
                if total > 0 {
                    // The pins are a second read of the same predicate, so the row's count stays a
                    // total and the map stays a page of it (ERRATA E38, E182). The owner asked for
                    // this row to say where its trees are; it could not, because the count was all
                    // that was ever read.
                    newestNeighbors = RecentPlanting(
                        treeCount: total,
                        leadingSpecies: planted.compactMap(\.name),
                        nearest: try almanacQueries.plantingPins(
                            scope: scope,
                            from: spring.from,
                            to: spring.to,
                            near: coordinate,
                            limit: AlmanacLimits.recentPlantingRowLimit,
                            connection: connection
                        )
                    )
                }
            }

            // --- The first bloom of the year.
            let bloom = try almanacQueries.firstBloom(
                scope: scope,
                since: AlmanacWindow.yearStart(now: moment, calendar: calendar),
                connection: connection
            ).map { found in
                BloomFirst(
                    treeID: found.treeID,
                    speciesCommonName: found.speciesCommonName,
                    address: found.address,
                    firstSeenAt: found.firstSeenAt,
                    observerCount: found.observerCount,
                    heroPhotoID: heroPhotoIDs[found.treeID]
                )
            }

            // --- Where eyes are needed. One row more than the cap is read, so `isComplete` is a
            // fact about the read rather than a guess — the same proof `ContributionStore` uses, and
            // it has to hold here because this card is nothing but a count (ERRATA E38).
            let found = try almanacQueries.youngTreesWithoutVisits(
                scope: scope,
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
                scope: scope,
                near: coordinate,
                limit: AlmanacLimits.vacantSiteRowLimit,
                connection: connection
            )
            let vacantSites = sites.count > 0
                ? VacantSites(count: sites.count, nearest: sites.nearest)
                : nil

            return Almanac(
                neighborhood: AlmanacNeighborhood(
                    area: scope.area,
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

    // MARK: - City

    /// The Journal tab's `City` segment: a species contrast against the reader's own street, the
    /// city's whole composition, and the oldest planting dates the city has on file.
    ///
    /// **The fused-bundle guarantee, in one sentence: every read below either takes an `idSpace` and
    /// predicates on it, or is used only to resolve one.** `CityQueries`'s own header states why —
    /// the shipped seed holds two cities under one attached schema with no `city_id` column, and a
    /// read that forgot the predicate would be R48's defect, a count spanning both cities under one
    /// city's name (here, under no name, which does not make an unscoped count honest — it is still
    /// the wrong population).
    public func city(near coordinate: Coordinate?) async throws -> CityAlmanac {
        guard let coordinate, let speciesQueries, let almanacQueries, let cityQueries else { return .empty }

        return try await store.queue.readConsistently { connection -> CityAlmanac in
            // --- Which city. A fact off the nearest row, never a guess from the coordinate alone
            // (`CityQueries.resolveIDSpace`'s own doc comment). Bounded by the same radius the
            // almanac's own fallback area uses, so a reader this resolves a city for is a reader the
            // almanac itself would not call out of range.
            guard let citySpace = try cityQueries.resolveIDSpace(
                near: coordinate,
                radiusM: AlmanacLimits.fallbackRadiusM,
                connection: connection
            ) else {
                return .empty
            }

            // --- The local scope, resolved exactly as the almanac resolves its own area (RULINGS
            // R29): a named neighborhood where the seed carries one, a stated radius where it does
            // not. This is what lets card 1 ask about the same "near you" the almanac already means,
            // and what keeps this read from claiming ground the record has never covered — a city
            // resolved above does not by itself prove the immediate area does too (a reader could be
            // 1,199 m from the nearest tree and still resolve a city while `holdsAnyRecord` finds
            // nothing inside a *tighter* box centered differently); in practice for this seed's two
            // cities the two agree, and where they would not, the honest answer is no local mix
            // rather than one borrowed from farther away than the almanac itself would use.
            let localScope: AlmanacScope?
            if let polygon = try speciesQueries.resolveNeighborhood(near: coordinate, connection: connection) {
                localScope = .neighborhood(id: polygon.id, name: polygon.name)
            } else {
                let fallback = AlmanacScope.radius(center: coordinate, meters: AlmanacLimits.fallbackRadiusM)
                localScope = try almanacQueries.holdsAnyRecord(scope: fallback, connection: connection)
                    ? fallback : nil
            }

            // --- Card 1's local half, and card 1 & 2's citywide half. `AlmanacQueries.speciesMix`
            // unmodified for the local read (ERRATA E38's whole-read discipline is already built into
            // it); `CityQueries.speciesMix(idSpace:)` for the city-scoped one.
            let localMix = try localScope.map { try almanacQueries.speciesMix(scope: $0, connection: connection) } ?? []
            let localComposition = localMix.isEmpty ? nil : NeighborhoodComposition(
                distinctSpeciesCount: localMix.count,
                treeCount: localMix.reduce(0) { $0 + $1.treeCount },
                leading: localMix
            )

            let cityMix = try cityQueries.speciesMix(idSpace: citySpace, connection: connection)
            let cityComposition = cityMix.isEmpty ? nil : NeighborhoodComposition(
                distinctSpeciesCount: cityMix.count,
                treeCount: cityMix.reduce(0) { $0 + $1.treeCount },
                leading: cityMix
            )

            // --- Card 3, the oldest on file. One row more than the card draws (`CityLimits
            // .oldestRowLimit + 1`), so `CityPresentation` can tell whether the row just past its cut
            // shares the last drawn row's year.
            let heroPhotoIDs = try contributions.heroPhotoIDs(connection: connection)
            let oldest = try cityQueries.oldestOnFile(
                idSpace: citySpace,
                limit: CityLimits.oldestRowLimit + 1,
                connection: connection
            ).map { found in
                ElderTree(
                    treeID: found.treeID,
                    activeName: try contributions.activeName(treeID: found.treeID, connection: connection)?.name,
                    speciesCommonName: found.speciesCommonName,
                    address: found.address,
                    plantedYear: found.plantedYear,
                    heroPhotoID: heroPhotoIDs[found.treeID]
                )
            }

            return CityAlmanac(
                snapshot: CityAlmanac.Snapshot(
                    localComposition: localComposition,
                    cityComposition: cityComposition,
                    oldest: oldest
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
    ///
    /// **Only while that account is the one signed in** (#174). The claim row outlives the sign-in —
    /// `signOut()` clears `app_state.current_user_id` and leaves `device.user_id` standing, which is
    /// what lets the account be resumed — so the row alone is history, not authority. Re-claiming
    /// against it while nobody is signed in adopted every device-owned row a drain had just applied:
    /// the favorite the owner tapped landed as the device's, was moved to the signed-out account
    /// (`user_id` set, `device_id` cleared) in the same `sync` call, and the re-read over
    /// `(userID: nil, deviceID:)` found nothing — the heart flashed dark green for one awaited drain
    /// and went back to white, on any device that had ever signed in and out, and on no fresh
    /// simulator. The straddle this method exists for ("queued Tuesday, signed in Wednesday, drained
    /// Thursday") has the person signed in at drain time, so the guard costs that case nothing; a
    /// tail drained while signed out is adopted by the next re-claim after they resume.
    private func adoptRowsWrittenAfterTheClaim(hadItems: Bool) async throws {
        guard hadItems else { return }
        guard let current = userID else { return }
        let moment = now()
        let device = deviceID
        try await store.queue.write { connection in
            guard let user = try contributions.claimedUser(forDevice: device, connection: connection),
                  user == current
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
                // favorite asserts nothing about the tree, and gating it would make the toggle
                // one-way for anyone whose favorite tree is later removed — they could no longer
                // take the heart off. See ERRATA E89.
                try requireTree(toggle.treeID, connection: connection)
                // The owner arrives on the payload and is written as it stands. Nothing here
                // upgrades a device-owned favorite to a user: that happens only at
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
            try contributions.insert(
                photo,
                localPath: request.localPath,
                owner: PhotoOwner(attribution),
                connection: connection
            )
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

    /// Removes one photograph this person contributed — task #78, ERRATA E147.
    ///
    /// ── Why this is a real delete and not `AccountDeletionChoice`'s two doors ─────────────────
    /// E136 made "leave the work, unlink the name" the *default* for deleting an account, on the
    /// owner's explicit ruling, and the reasoning is good: a person leaving is making a statement
    /// about their identity, and the check-ins, measurements and votes they leave behind are worth
    /// something to the forest whoever made them. None of that transfers to one photograph deleted
    /// on purpose. A photograph is deleted **because of what is in it** — a face, a license plate,
    /// the inside of somebody's front garden, a house number — and anonymizing it addresses none of
    /// that. It would leave the picture on the tree and take the name off the picture, which is
    /// answering a question nobody asked. That is E136's own test for a door worth offering, applied
    /// here and failed: it refuses to offer "keep my favorites" because a favorite nobody owns is
    /// a row no query returns and no person can remove — a decorative control. "Keep this
    /// photograph, unnamed" is the same control in the other direction: it looks like it honors the
    /// request and does not.
    ///
    /// So there is one outcome and it is destructive, and what the design owes instead is **intent**:
    /// the control is on screen 20, where each photograph is already being judged one at a time, and
    /// it raises a confirmation naming the consequence before anything happens. One tap destroys
    /// nothing. See `TreePhotosView`.
    ///
    /// ── The bytes go, and that is the point ──────────────────────────────────────────────────
    /// Soft delete is the house verb and `deleted_at` is what the row gets, but a tombstone alone
    /// would be the wrong answer to *this* request: leaving the JPEG in the container after somebody
    /// asked for it to be gone is precisely the failure E136 refused to ship in the account case. So
    /// the files are removed from disk, the row is stripped of `storage_key`, `local_path`, its pixel
    /// dimensions and its fuzzed coordinate, and what survives is a tombstone that cannot find a
    /// picture (`ContributionStore.deletePhoto` says what is left and why the row survives at all).
    ///
    /// **Files first, on E136's ruling**, which is a ruling and not a detail: `FileManager` cannot
    /// join a SQLite transaction, so one half is outside the atomic part and one of two failure
    /// modes will happen. Files-first fails as a row pointing at bytes that are gone — visible,
    /// retryable, cosmetic, and `photoData` already draws the placeholder for it. Rows-first fails as
    /// a JPEG somebody asked to have destroyed, stranded in the container and unreachable by every
    /// query that could find it again. A deletion path takes the loud failure.
    ///
    /// ── The hero, which is derived and therefore cannot dangle ───────────────────────────────
    /// Nothing stores a hero id. `PhotoHero.choose` ranks the set it is handed and already excludes
    /// `deletedAt != nil`, and `ContributionStore.photos` never returns a tombstone, so deleting the
    /// photograph a tree leads with promotes the next one by the same rule that chose the first —
    /// an up-voted photograph, else the most recent `full_tree`, else the most recent of any kind —
    /// and deleting the last one returns the tree to the cold, photograph-less profile it had before
    /// anybody photographed it. That the votes go with it matters here: a tombstone left holding a
    /// positive tally would be a deleted photograph winning a hero election.
    ///
    /// ── The last photograph on a community-added tree ────────────────────────────────────────
    /// BUILD-PLAN §6 says "Community add: requires photo", so deleting the only photograph of a tree
    /// that exists *because* of that photograph is a genuine conflict, and it is settled in favor of
    /// the person: **allowed, named, and recorded**.
    ///
    /// Refusing was the other candidate and it is the wrong answer. "Requires photo" is a rule about
    /// *making* a record — evidence at the point of creation, and the anti-spam gate on a table any
    /// phone can write to — not an invariant the row must satisfy forever. Enforcing it afterwards
    /// would mean the app telling somebody it will not remove a photograph of their neighbor's
    /// window because the tree's paperwork needs it, which subordinates the exact request this
    /// feature exists to honor to a data-completeness rule. It would also be trivially defeated:
    /// photograph the pavement, then delete the first one.
    ///
    /// What the record means afterwards is stated rather than left to be discovered. The tree stays
    /// — deleting it would remove a real tree from the map, possibly one other people have since
    /// visited, and "everything I contributed" has never meant the forest (`AccountDeletion`). It
    /// stays `unverified`, which is already the right word for it and the reason no state change is
    /// invented here. And the tombstone stays on the row, so the tree's own record still says a
    /// photograph was taken for it and withdrawn, rather than looking like a tree that was added
    /// with no evidence at all. `PhotoDeletion.leftACommunityTreeWithoutAPhotograph` reports it, and
    /// screen 20 says it in words *before* the tap, not after.
    ///
    /// ── Votes and queued uploads ─────────────────────────────────────────────────────────────
    /// Every vote on the photograph goes, whoever cast it: they were judgments about a thing that
    /// no longer exists, which is `AccountDeletion`'s argument for the same deletion. The at-most-one
    /// owner CHECK v9 gave `photo_votes` means an anonymized vote is deleted by photo id like any
    /// other, with no owner arm to strand. And any queued mutation still carrying the staged binary
    /// has it taken out of its list, or the next drain would upload a photograph that had been
    /// deleted.
    public func deletePhoto(id: UUID) async throws -> PhotoDeletion {
        let moment = now()
        let who = attribution

        // 1. Establish what this is and whose it is, before anything is removed.
        let subject = try await store.queue.read { connection in
            try contributions.photoForDeletion(id: id, connection: connection)
        }
        guard let subject else { throw APIError.notFound }
        guard subject.owner.isOwned(by: who) else { throw APIError.forbidden }

        // 2. Whether this is the last photograph of a tree that needed one to exist. Read before the
        //    delete, because afterwards the answer is the same for a tree that never had one.
        let lastOnACommunityAdd = try await store.queue.read { connection -> Bool in
            guard try communityTrees.tree(id: subject.treeID, connection: connection) != nil else { return false }
            return try contributions.photos(treeID: subject.treeID, connection: connection).items.count == 1
        }

        // 3. The bytes, before the rows. `lastPathComponent` on the storage key rather than the
        //    stored string, the same directory-traversal guard `photoData` makes on the way in.
        let manager = FileManager.default
        var removedFiles = 0
        let files = [
            subject.storageKey.map { photoDirectory.appendingPathComponent(($0 as NSString).lastPathComponent) },
            subject.localPath.map { URL(fileURLWithPath: $0) }
        ].compactMap { $0 }
        for url in files where manager.fileExists(atPath: url.path) {
            do {
                try manager.removeItem(at: url)
                removedFiles += 1
            } catch {
                // A file that will not go is the one failure this method must not swallow: the row
                // would be tombstoned and the picture would still be on the disk, which is the
                // outcome the whole ordering exists to prevent. Nothing has been written yet, so
                // throwing here leaves the photograph exactly as it was and the person can try again.
                throw APIError.serverError
            }
        }

        // 4. The rows, in one transaction.
        let counts = try await store.queue.write { connection -> ContributionStore.PhotoDeletionCounts in
            var counts = try contributions.deletePhoto(
                id: id, attribution: who, at: moment, connection: connection
            )
            if let path = subject.localPath {
                counts.stagedBinaries = try OutboxStore().discardStagedPhoto(
                    atPath: path, at: moment, connection: connection
                )
            }
            return counts
        }
        // The predicate in the UPDATE matched nothing although the read said it would: another
        // deletion won the race. Reported as `notFound` rather than as a success, because a success
        // would be this call claiming to have done something it did not do.
        guard counts.photos == 1 else { throw APIError.notFound }

        return PhotoDeletion(
            photoID: id,
            treeID: subject.treeID,
            removedFiles: removedFiles,
            deletedVotes: counts.votes,
            dequeuedBinaries: counts.stagedBinaries,
            leftACommunityTreeWithoutAPhotograph: lastOnACommunityAdd
        )
    }

    /// A thumb up or down on a photograph, or `nil` to take it back (ERRATA E125, `AppSchema` v8).
    ///
    /// The owner is `attribution`'s — the account when there is one, this device otherwise — so a
    /// vote cast before sign-in is adopted by `claimDevice` exactly as a favorite is, and never
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

    /// `GET /me/grove`, Trees pill — the list of trees this contributor has a relationship with.
    ///
    /// The two reads run in **one** `read` block, so the rows and the tally they carry are answered
    /// against the same snapshot of the database. Two blocks would leave a window in which a visit
    /// saved between them appears in the tally of a tree the first read did not return — a small
    /// inconsistency that would be indistinguishable from a counting bug and impossible to reproduce.
    ///
    /// Both are complete reads with no limit on either, which is what entitles the screen to print
    /// the tally at all (ERRATA E38, and `GroveRecord`).
    /// `GET /me/grove` narrowed to one tree (#167) — the read screen 03's heart re-checks after a
    /// write. One indexed SELECT over both ownership arms instead of the whole grove: the wide read
    /// resolves every held tree through `treeIfPresent` before it can answer one membership bit,
    /// and skips any row whose tree it cannot resolve — two costs this question never asked for.
    public func isFavorite(treeID: UUID) async throws -> Bool {
        let userID = userID
        let deviceID = deviceID
        return try await store.queue.read { connection in
            try contributions.holdsFavorite(
                userID: userID, deviceID: deviceID, treeID: treeID, connection: connection
            )
        }
    }

    public func grove() async throws -> [GroveEntry] {
        let userID = userID
        let deviceID = deviceID
        let (rows, records, heroPhotoIDs) = try await store.queue.read { connection in
            (
                try contributions.groveTreeIDs(userID: userID, deviceID: deviceID, connection: connection),
                try contributions.groveRecords(userID: userID, deviceID: deviceID, connection: connection),
                // One statement for every row on the pill, not one per tree (#176). See
                // `ContributionStore.heroPhotoIDs`.
                try contributions.heroPhotoIDs(connection: connection)
            )
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
                    isFavorite: row.isFavorite,
                    // A tree with no key in the map has no contributions against it — a favorite
                    // nobody has visited. An empty record and not nil: the read *did* answer for
                    // this tree, and the answer is that there is nothing yet. Nil is reserved for an
                    // implementation that could not answer at all.
                    //
                    // **Spelled `GroveRecord.none`, and it has to be.** Written `?? .none` against a
                    // `GroveRecord?` the leading dot resolves to `Optional.none`, so every favorite
                    // nobody had visited came back as "could not answer" and drew nothing — the same
                    // picture as an unproven read, which is the one distinction this field exists to
                    // keep. It compiled, and `aFavoriteWithNoContributionsIsEmptyNotUnknown` is what
                    // caught it.
                    record: records[row.treeID] ?? GroveRecord.none,
                    heroPhotoID: heroPhotoIDs[row.treeID]
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
            // --- Which area the ring is about (RULINGS R29, the same order `almanac` resolves in).
            //
            // A4's inference reads the same contributions, so a contributor with none has no
            // area at all and the ring has nothing to be a fraction of. The polygon first — the
            // most-visited neighborhood, the exact query this screen has always run, so San
            // Francisco cannot move. Where no touched tree carries a polygon (every contribution
            // in San Jose, whose 52,788 rows hold `neighborhood_id IS NULL`), the same inference
            // still names a most-visited *tree*, and R29's stated radius around it is the area.
            // No coverage guard is needed the way `almanac` and `speciesGuide` need one: the
            // center is itself an inventoried tree, so the circle covers record by construction.
            let scope: AlmanacScope
            if let resident = try groveQueries.residentNeighborhood(
                userID: userID,
                deviceID: deviceID,
                connection: connection
            ) {
                scope = .neighborhood(id: resident.id, name: resident.name)
            } else if let center = try groveQueries.mostVisitedTree(
                userID: userID,
                deviceID: deviceID,
                connection: connection
            ) {
                scope = .radius(center: center, meters: AlmanacLimits.fallbackRadiusM)
            } else {
                return GroveSpecies(neighborhood: nil, known: known)
            }
            let species = try groveQueries.speciesIDs(scope: scope, connection: connection)
            return GroveSpecies(
                neighborhood: GroveNeighborhood(area: scope.area, species: species),
                known: known
            )
        }
    }

    public func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> {
        let cursorDate = cursor.flatMap(SQLiteTimestamp.date(from:))
        let capped = min(limit, Page<JournalEntry>.maximumLimit)
        let (rows, heroPhotoIDs) = try await store.queue.read { connection in
            (
                try contributions.journal(
                    userID: userID,
                    deviceID: deviceID,
                    before: cursorDate,
                    limit: capped,
                    connection: connection
                ),
                // One statement for every row on the page, not one per row (#176). See
                // `ContributionStore.heroPhotoIDs`.
                try contributions.heroPhotoIDs(connection: connection)
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
                summary: Self.humanize(kind: row.kind, storedSummary: row.summary),
                heroPhotoID: heroPhotoIDs[row.treeID]
            )
        }
        // The cursor is the last row's capture time. Contributions are append-only and never
        // back-dated across a page boundary, so this is stable under concurrent writes.
        let nextCursor = entries.count == capped
            ? entries.last.map { SQLiteTimestamp.string(from: $0.capturedAt) }
            : nil
        return Page(items: entries, nextCursor: nextCursor)
    }

    /// `care_events.actions` is stored as a JSON array, and `observations.status` is stored as its
    /// raw value; the journal query hands both back raw rather than teaching SQL to write English.
    static func humanize(kind: JournalEntry.Kind, storedSummary: String) -> String {
        switch kind {
        case .careEvent:
            let actions = JSONColumn.decodeRawValues(CareAction.self, storedSummary)
            return actions.map(\.rawValue.replacingUnderscores).joined(separator: ", ")
        case .observation:
            // The stored shape is `<status>` with an optional ` · vitality N` suffix. The status
            // is an `ObservationStatus` raw value — `appears_removed`, `appears_dead` — which is
            // what the owner read under a check-in in the Yours tab (#170). Underscores appear in
            // no other part of the string, so one pass humanizes every kind on this path.
            return storedSummary.replacingUnderscores
        default:
            return storedSummary
        }
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
    /// device and the reads that ask for "my" reminders and favorites stop returning the account's.
    ///
    /// The id is remembered under `AppStateKey.signedOutUserID` so signing in again resumes it. A
    /// local account has no credential to sign back in *with* — `accountLink` mints a `UUID` when it
    /// finds none — so forgetting the id would leave every account-owned row unreadable by any query
    /// and unremovable by any deletion, which is the litter RULINGS R3 spent its length refusing to
    /// create. Sign-out is not a quiet, unlabeled deletion.
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

    /// The open status-review flags a lead has to act on, resolved for display: what was reported,
    /// each tree's name (active name, else species common name), address and coordinate, newest
    /// concern first.
    ///
    /// **Every kind a confirm can resolve, not one** (ERRATA E170). This read used to name
    /// `.appearsRemoved` in its own body while screen 05 raised `.appearsDead` beside it with an
    /// identical affordance, so half of what the check-in card offered to report landed in
    /// `review_flags` and was never shown to anybody again. The list comes from
    /// `ReviewFlag.Kind.statusReviewKinds`, which is derived from the same switch the confirm uses.
    ///
    /// A read, so it is ungated — a non-lead simply never reaches the surface that calls it (the You
    /// tab shows the section only when `userRole.canConfirmReviewFlag`). The *write* is what carries
    /// the authority check; see `confirmReview` and `dismissReview`.
    public func openReviews() async throws -> [ReviewQueueItem] {
        try await store.queue.read { connection -> [ReviewQueueItem] in
            let flags = try contributions.openReviewFlags(
                kinds: ReviewFlag.Kind.statusReviewKinds,
                connection: connection
            )
            return try flags.compactMap { flag -> ReviewQueueItem? in
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
                return ReviewQueueItem(
                    flagID: flag.id,
                    treeID: flag.treeID,
                    kind: flag.kind,
                    treeName: name,
                    address: tree.address,
                    coordinate: tree.coordinate,
                    raisedAt: flag.createdAt
                )
            }
        }
    }

    /// A lead confirms a status-review flag: the flag moves to `confirmed` and the tree gains a local
    /// status override of whatever that kind resolves to, in one transaction (see `AppSchema.v7`).
    ///
    /// **The status comes from the flag, not from this method's name** (ERRATA E170). It used to be a
    /// literal `.removed` under a `guard flag.kind == .appearsRemoved`, which is the whole of why
    /// `appears_dead` was a flag nothing could ever resolve. `ReviewFlag.Kind.confirmedStatus` decides
    /// now: `appears_removed` → `.removed`, `appears_dead` → `.deadReported`. No migration and no new
    /// enum case were needed for the second one — `tree_status_overrides` carries any `TreeStatus`, and
    /// `TreeStatus.deadReported` has existed since the type was written (`Tree.swift`).
    ///
    /// The two outcomes are not the same shape and must not be read as one. A confirmed removal makes
    /// screen 19 reachable from real data — the map pin becomes a memorial and the profile becomes a
    /// memorial record. A confirmed death makes neither: `deadReported.acceptsNewContributions` is
    /// `true` on purpose, so the tree keeps its profile, its REPORT and CARE actions and its pin. A
    /// dead street tree is still standing over a pavement, and reporting it is the most useful thing a
    /// passer-by can do; a memorial page would take that button away.
    ///
    /// A kind with no `confirmedStatus` — `duplicate_suspected`, `wrong_species`, `removed_but_active`
    /// — still throws `.validationFailed`. That is not a status claim, and confirming one must not
    /// move a tree on grounds nobody made.
    ///
    /// Gated: only `userRole.canConfirmReviewFlag` (moderator, admin, coordinator) may confirm a flag
    /// into a status transition (DECISIONS §3.7). A `member` or `steward` gets `.forbidden` — the
    /// authority lives on the write, so even a surface shown in error cannot move a tree.
    public func confirmReview(flagID: UUID) async throws {
        guard userRole.canConfirmReviewFlag else { throw APIError.forbidden }
        let moment = now()
        let confirmer = userID
        try await store.queue.write { connection in
            guard let flag = try contributions.reviewFlag(id: flagID, connection: connection),
                  flag.deletedAt == nil else {
                throw APIError.notFound
            }
            guard let status = flag.kind.confirmedStatus else { throw APIError.validationFailed }
            guard flag.status == .open else { throw APIError.conflict }

            try contributions.confirmReviewFlag(id: flagID, at: moment, connection: connection)
            try contributions.setStatusOverride(
                treeID: flag.treeID,
                status: status,
                setBy: confirmer,
                at: moment,
                connection: connection
            )
        }
        // The map holds this table between writes; this is one of the two writes. See `overrideCache`.
        overrideCache = nil
    }

    /// A lead dismisses a status-review flag: the flag moves to `dismissed` and **nothing else
    /// happens** (ERRATA E170).
    ///
    /// `ReviewFlag.Status.dismissed` has been in the model since it was written and no code path
    /// wrote it, so a lead who thought a report was wrong had exactly one move available — leave it
    /// open — and the queue accumulated reports that were never going to be confirmed. A queue whose
    /// only verb is "agree" is not a review.
    ///
    /// **No status override, deliberately.** Dismissing says the reported change did not happen, and
    /// the tree's status is already what it was; writing an override to say so would replace an
    /// inventory value with a device-side row asserting the same thing, and `tree_status_overrides`
    /// would start carrying rows that mean "somebody looked" rather than "this changed". The flag row
    /// records who looked and when.
    ///
    /// Same gate as the confirm, and for the same reason: both are the resolution of somebody else's
    /// report, and a `member` or `steward` gets `.forbidden` on the write itself.
    public func dismissReview(flagID: UUID) async throws {
        guard userRole.canConfirmReviewFlag else { throw APIError.forbidden }
        let moment = now()
        try await store.queue.write { connection in
            guard let flag = try contributions.reviewFlag(id: flagID, connection: connection),
                  flag.deletedAt == nil else {
                throw APIError.notFound
            }
            guard flag.kind.confirmedStatus != nil else { throw APIError.validationFailed }
            guard flag.status == .open else { throw APIError.conflict }

            try contributions.dismissReviewFlag(id: flagID, at: moment, connection: connection)
        }
    }

    #if DEBUG
    /// Test seam (ERRATA E141): a community tree with a contributor's species on it, so the deep-link
    /// harness can put the claim in front of a screenshot.
    ///
    /// **It goes through `addTree`, not around it.** The point of looking at this screen is to check
    /// that a claim made the whole trip — screen, draft, boundary, column, presentation — so a seam
    /// that inserted a row directly would be photographing a state the app cannot actually produce.
    /// The species comes from `searchSpecies`, which is the path the picker takes.
    ///
    /// - Parameter query: what to look the species up by. Nil adds a tree with no species, which is
    ///   the other state worth photographing: the one that offers to be named.
    public func debugAddCommunityTree(
        near coordinate: Coordinate,
        speciesQuery query: String?
    ) async throws -> UUID {
        // `Optional.map` is `rethrows`, not `async`, so this is spelled out rather than chained.
        var species: Species?
        if let query { species = try await searchSpecies(query: query, limit: 1).first }
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        let staged = photoDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try Self.debugJPEG(hue: 0.3).write(to: staged, options: .atomic)

        let tree = try await addTree(
            TreeDraft(
                coordinate: coordinate,
                speciesID: species?.id,
                photoLocalPath: staged.path,
                attribution: attribution
            )
        )
        return tree.id
    }

    /// Test seam (ERRATA E170): read one flag back, including a resolved one.
    ///
    /// `openReviews` returns open flags only, so a dismissal is invisible through the shipping read —
    /// which is exactly what a test of the dismissal must not accept as proof. "The row left the
    /// queue" is also what a soft-delete, a lost write or a `notFound` would look like. This reads
    /// the row and lets the test assert `.dismissed` rather than absence.
    public func debugReviewFlag(id: UUID) async throws -> ReviewFlag? {
        try await store.queue.read { connection in
            try contributions.reviewFlag(id: id, connection: connection)
        }
    }

    /// Test seam (ERRATA E124-B, widened by E170): open a status review of a given kind on a real seed
    /// tree, returning its flag id, so the deep-link harness can put the moderation surface in front of
    /// a screenshot with a genuine record behind it. Inserts the same flag a screen 05 check-in would,
    /// without the outbox round trip.
    ///
    /// Takes the kind because the queue now serves two, and the two rows read differently — a
    /// screenshot of a queue holding only removals would not show that.
    @discardableResult
    public func debugSeedReview(treeID: UUID, kind: ReviewFlag.Kind = .appearsRemoved) async throws -> UUID {
        let moment = now()
        let flag = ReviewFlag(treeID: treeID, kind: kind, raisedBy: nil, createdAt: moment, updatedAt: moment)
        try await store.queue.write { connection in
            try contributions.insert(flag, connection: connection)
        }
        return flag.id
    }

    /// Test seam (ERRATA E124-B, widened by E170): force a tree to a status by writing its override
    /// directly, so the harness can open screen 19 — or a confirmed-dead profile — against a real seed
    /// record. The shipping path is `confirmReview`, which requires a lead and an open flag; this skips
    /// both because the harness is proving the *screen renders*, not the moderation gate —
    /// `ModerationTests` proves the gate.
    public func debugMarkStatus(treeID: UUID, _ status: TreeStatus) async throws {
        let moment = now()
        try await store.queue.write { connection in
            try contributions.setStatusOverride(treeID: treeID, status: status, setBy: nil, at: moment, connection: connection)
        }
        // The other write. See `overrideCache`.
        overrideCache = nil
    }

    /// Test seam (task #173): the local status overrides this device holds, by tree id.
    ///
    /// **It exists because `treesNear` does not apply them and `treeProfile` does**, which made the
    /// deep-link harness's own resolution disagree with the screen it opened. `debugMarkStatus` above
    /// writes an override; `treesNear` reads the inventory row and returns the *seed's* status; so a
    /// harness case that picked "the nearest tree that accepts contributions" kept picking the same
    /// record after `.memorial` had marked it removed, and `CYPRESS_SCREEN=treeProfile` opened a
    /// removed tree — no primary CTA, no check-in — on every device that had ever opened screen 19.
    /// Found by `CypressUITests/PrimaryCTAReachabilityTests` on its first run.
    ///
    /// **Not a change to `treesNear`.** The map runs that query on every camera change and layers
    /// overrides itself through `overrideCache`, precisely so the join is paid once rather than per
    /// viewport; folding it in would spend #130's pin budget to serve a `#if DEBUG` harness. What the
    /// harness needs is the table, and this hands it over.
    public func debugStatusOverrides() async throws -> [UUID: TreeStatus] {
        try await store.queue.read { connection in
            try contributions.statusOverrides(connection: connection)
        }
    }

    /// Test seam (ERRATA E217 "Still open"): empty `tree_status_overrides`.
    ///
    /// **Why this has to exist at all.** `.memorial` and `.deadProfile` are the only two cases that
    /// write here, and neither ever un-writes: `.memorial` marks the nearest standing tree removed and
    /// `standingTree` — through `candidates(_:)` — correctly excludes it next time, so a device driven
    /// for long enough walks its `.memorial` slot outward one record per run with nothing to stop it.
    /// The errata that found this left it explicitly unfixed and named the shape: a seam the harness
    /// calls before the walk can start, not a change to how the walk works.
    ///
    /// The other write. See `overrideCache` — same rule as `debugMarkStatus` and `confirmReview`, and
    /// for the same reason: this changes what the table holds, and nothing else invalidates the cache
    /// on this actor's behalf.
    public func debugClearStatusOverrides() async throws {
        try await store.queue.write { connection in
            try contributions.clearStatusOverrides(connection: connection)
        }
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
                try contributions.insert(
                    photo, localPath: nil, owner: PhotoOwner(attribution), connection: connection
                )
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

    /// Test seam (task #131): take one photograph's owner off it, leaving the row the way the
    /// leaving door leaves it.
    ///
    /// The shipping path is `deleteAccount(.leaveRecords)`, and it is the wrong instrument for a
    /// harness: it anonymizes *every* row of the account at once, so a deep-link case using it
    /// would reach across into whatever the other cases had contributed on the way past. This
    /// writes the same end state on one named row — both owner columns null, which is what
    /// `AccountDeletion.anonymizeContributions` leaves behind on a photograph contributed while
    /// signed in (`photos` carries at most one owner, so nulling `user_id` leaves nothing).
    ///
    /// It does not write the `anonymized_contributions` tombstone, which is deliberate and worth
    /// stating: that table exists to stop `claimDevice` re-adopting a row, and a photograph with no
    /// `device_id` is already outside `claimDevice`'s predicate (see `ContributionStore.claimDevice`).
    /// A harness that wrote it would be asserting a mechanism rather than reproducing a state.
    public func debugAnonymizePhoto(id: UUID) async throws {
        try await store.queue.write { connection in
            let statement = try connection.cachedStatement("""
                UPDATE photos SET user_id = NULL, device_id = NULL, updated_at = :now
                 WHERE id = :id COLLATE NOCASE
                """)
            _ = try statement.bind([":id": id.uuidString, ":now": now()])
            try statement.run()
            _ = try statement.reset()
        }
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
    /// ── And since the crop fix, it is shaped like its subject ────────────────────────────────
    /// The band alone proved *that* bytes arrived. It could not prove *which part of them* did, and
    /// that is the question the crop anchor turns on: a centered crop of a portrait tree keeps the
    /// trunk and throws the canopy away, and against a flat rectangle with one stripe on it both
    /// crops look identical. A screenshot of this screen was the evidence, and it was evidence of
    /// nothing.
    ///
    /// So the fixture is now a crude tree, drawn where a real one sits in a portrait frame: canopy
    /// across the top half, trunk down the middle, ground at the foot. Anybody — or any test —
    /// looking at a hero can now say which part survived, because a hero showing only trunk and a
    /// hero showing the canopy are different pictures.
    ///
    /// **1200×1600, matching the `width`/`height` the row records.** It was 300×400 under a row
    /// claiming 1200×1600, which is a fixture that lies about itself in the one column A3's
    /// resolution tie-break reads; and at 300 px the full-screen viewer had nothing to show, so a
    /// screenshot of it could not tell a correct decode from a blurred one.
    private static func debugJPEG(hue: Double) -> Data {
        let width = 1_200, height = 1_600
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return Data() }

        let w = CGFloat(width), h = CGFloat(height)
        // CoreGraphics puts the origin at the bottom-left, so every `y` below is measured up from
        // the foot of the picture. Named once here because getting it backwards silently draws the
        // tree upside down, which is precisely the class of mistake this fixture is meant to expose.
        func band(fromTop top: CGFloat, toTop bottom: CGFloat) -> CGRect {
            CGRect(x: 0, y: h * (1 - bottom), width: w, height: h * (bottom - top))
        }

        // Sky: near-white, so the letterbox bars of a viewer are obviously bars and not photograph.
        context.setFillColor(CGColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Three hues a third of the wheel apart, started at magenta so none of them lands on the
        // app's greens: magenta, orange, cyan for count == 3.
        let (red, green, blue) = Self.saturatedRGB(hue: (hue + 0.85).truncatingRemainder(dividingBy: 1))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        // Canopy: an ellipse over the top half, inset from the sides, with headroom above it —
        // where a photographer standing at the curb puts the crown of a street tree.
        context.fillEllipse(in: CGRect(
            x: w * 0.08, y: h * (1 - 0.60), width: w * 0.84, height: h * 0.52
        ))

        // Trunk and ground: dark, and unmistakably not canopy.
        context.setFillColor(CGColor(red: 0.20, green: 0.14, blue: 0.10, alpha: 1))
        context.fill(CGRect(x: w * 0.44, y: h * (1 - 0.94), width: w * 0.12, height: h * 0.39))
        context.fill(band(fromTop: 0.94, toTop: 1.0))

        // The white bar stays, and stays in the middle, because it is still the "bytes arrived"
        // signal and nothing else in Cypress draws one. It now doubles as the marker for *where the
        // middle is*: a centered crop keeps it dead center, a crown-anchored crop pushes it low.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(band(fromTop: 0.48, toTop: 0.52))

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
    ///
    /// ── The bytes, and why they go before the rows ────────────────────────────────────────────
    /// `eraseEverything` has to remove photographs from disk as well as from the database, and a
    /// `FileManager` call cannot join a SQLite transaction. So one of the two has to happen outside
    /// the atomic part, and which one is not a matter of taste.
    ///
    /// **Files first.** The rule is already written down in `debugClearPhotos`, whose reason is that
    /// a photograph's bytes are *found through its row* — delete the row first and the JPEG is
    /// stranded in the container with nothing left pointing at it. For an erasure that reason is not
    /// merely tidiness, it is the whole promise: a stranded file is a photograph belonging to a person
    /// who asked to be forgotten, sitting on disk forever, unreachable by any query that could find it
    /// again and therefore undetectable. The opposite failure — files removed, transaction rolls back —
    /// leaves rows pointing at missing bytes, which is a visible, retryable, cosmetic inconsistency
    /// whose data loss is exactly the data the person asked to destroy. Between a silent privacy
    /// failure and a loud cosmetic one, a deletion path takes the loud one.
    ///
    /// It is also idempotent in the direction it can fail: a retry re-reads the same rows, tries to
    /// remove files that are already gone (`try?`, and a missing file is not an error worth failing a
    /// deletion over), and completes the transaction that did not commit last time.
    ///
    /// The default door removes nothing from disk, because there is nothing to remove: a photograph
    /// has no owner column, so anonymizing the visit is the whole of un-naming it. See
    /// `AccountDeletion.photoBytes`.
    @discardableResult
    public func deleteAccount(
        _ choice: AccountDeletionChoice = .default
    ) async throws -> AccountDeletion.Outcome {
        guard let account = userID else { throw APIError.unauthorized }
        let moment = now()

        if choice == .eraseEverything {
            let bytes = try await store.queue.read { connection in
                try AccountDeletion().photoBytes(userID: account, connection: connection)
            }
            let manager = FileManager.default
            // `lastPathComponent`, not the stored string: a storage key is resolved against this
            // app's photo directory rather than trusted as a path, the same guard `photoData` makes
            // on the way in.
            for key in bytes.storageKeys {
                try? manager.removeItem(
                    at: photoDirectory.appendingPathComponent((key as NSString).lastPathComponent)
                )
            }
            for path in bytes.absolutePaths {
                try? manager.removeItem(at: URL(fileURLWithPath: path))
            }
        }

        let outcome = try await store.queue.write { connection in
            try AccountDeletion().delete(
                userID: account, choice: choice, at: moment, connection: connection
            )
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

    /// Screen 01's `Yours` and `Favorites` sets (#116, RULINGS R23).
    ///
    /// One read per press of the chip, not one per pan: `MapModel` holds the answer for as long as
    /// the chip is on, and the map refetches *through* it. The sets are bounded by what one person
    /// tapped, so reading them whole is the cheap option as well as the simple one.
    public func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> {
        let device = deviceID
        let user = userID
        return try await store.queue.read { connection in
            switch kind {
            case .yours:
                return try contributions.contributedTreeIDs(
                    userID: user, deviceID: device, connection: connection
                )
            case .favorites:
                return try contributions.favoriteTreeIDs(
                    userID: user, deviceID: device, connection: connection
                )
            }
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
