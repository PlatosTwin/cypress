import Foundation

/// The reads behind screen 12 — the neighborhood almanac.
///
/// Like `GroveQueries` these straddle the two databases: what a tree *is* lives in the attached
/// seed, what anybody did to it lives in `main`. That is why they are here rather than in
/// `TreeQueries` (the seed alone) or `ContributionStore` (`main` alone).
///
/// **There is no `COUNT(*)` in this file that counts a contribution.** Every count is over trees —
/// trees of a species, trees planted in a window, trees nobody has been to — with one exception,
/// `firstBloom`'s `COUNT(DISTINCT …)` over contributors, which is A8's headcount and is floored at
/// three before it can be spoken (D1, ARCHITECTURE §5.1). Nothing here can be ordered by
/// contributor, and nothing here returns a contributor's identity.
///
/// Every read is scoped to one `AlmanacScope`, which the caller resolves once — a named polygon
/// where the merged record holds one, a stated radius where it does not (RULINGS **R29**, ERRATA
/// **E182**). It used to be a bare `neighborhoodID: Int`, which is San Francisco's Analysis
/// Neighborhoods and nothing else, and which made every San Jose row invisible to this screen
/// (E176). `SpeciesQueries.resolveNeighborhood(near:)` still answers the first half and is still the
/// single seam A4 will move through when its stated mechanism exists (ERRATA E44).
///
/// **The scope is the only thing that changed.** Every predicate below it — `standing`,
/// `deleted_at IS NULL`, the species joins, the `NOT EXISTS` over visits — is untouched, so a
/// neighborhood asked for by id returns exactly the rows it returned before this pass.
public struct AlmanacQueries {
    private let schema: SeedSchema
    private let seed = SeedDatabase.schemaName

    public init(schema: SeedSchema) {
        self.schema = schema
    }

    /// A tree the almanac is willing to talk about: one the city believes is standing.
    ///
    /// Vacant planting sites are 6.4% of the inventory (ERRATA E11) and a basin with nothing in it
    /// is not an elder, not a newest neighbor and not a young tree anybody can go and look at. The
    /// dead and removed are excluded for the same reason: this screen is about what is growing.
    ///
    /// **This predicate, and not the species `JOIN`, is what keeps a vacant site off screen 12.**
    /// E107 and E113 both record the exclusion as a consequence of `speciesMix`'s inner join; it is
    /// not, and the difference decides what happens to somebody who "widens the join" on their
    /// advice. See ERRATA E115, and the note on `speciesMix` below.
    ///
    /// It is applied by **every** read in this file. `firstBloom` was the exception until E115 —
    /// it filtered `deleted_at` and nothing else — which left the one row on screen 12 that names a
    /// tree by address able to name a basin.
    private static let standing = "t.status IN ('alive','declining')"

    /// **How `firstBloom`'s visit meets the inventory, and why it stopped being `COLLATE NOCASE`.**
    ///
    /// The same finding `GroveQueries.treeJoin` carries at length, on the one join in this file that
    /// can take it. The two sides genuinely differ in case — `UUID.bind` stores Foundation's
    /// uppercase canonical string in `main`, every seed file `Tools/build_seed.py` writes stores
    /// `trees.uuid` lower case — so the comparison has to normalize one side or match nothing.
    ///
    /// It was `t.uuid = v.tree_uuid COLLATE NOCASE`, which is correct and cannot be answered by an
    /// index: `trees.uuid` is `NOT NULL UNIQUE`, so `sqlite_autoindex_trees_1` is a **BINARY** index
    /// and no NOCASE comparison can seek it, whichever operand carries the collation. `lower()` on
    /// the **contributions** side leaves the indexed column bare, so the seek is back.
    ///
    /// The two arms of R29 paid for it differently and both are fixed by the same line. Measured on
    /// the shipped seed, three readings each, through an instrument calibrated against a no-op at
    /// 0.0006 ms and a known 50 ms sleep at 53.9 ms:
    ///
    /// - **polygon** (Outer Richmond): `SEARCH t USING INDEX idx_trees_neighborhood | SEARCH v USING
    ///   AUTOMATIC PARTIAL COVERING INDEX` — the neighborhood walked and a transient index built over
    ///   `visits` per execution — **3.06–4.53 ms → 0.01–0.02 ms**;
    /// - **radius** (1,200 m): `SCAN v | … | SEARCH t USING AUTOMATIC PARTIAL COVERING INDEX
    ///   (uuid=?)` — a transient index built over the whole merged inventory per execution —
    ///   **22.9–33.7 ms → 0.12–0.26 ms**.
    ///
    /// Both figures are with **no** contributions on the device, which is the case worth stating:
    /// the old polygon plan drove from the inventory, so a reader who had never recorded anything
    /// still paid for a walk of their neighborhood every time screen 12 opened.
    ///
    /// Sound only while every inventory file stores its uuids lower case. That is asserted rather
    /// than assumed: `DataGates.armsWithUppercaseUUIDs` checks it per arm, `DataGates.seedContract`
    /// runs it on every CI run, and `GroveQueryPlanTests.theLowercaseUUIDContractCanFailOnAPack` is
    /// the negative control. `GroveQueries.treeJoin` carries the whole argument, including the
    /// owner's closed decision about packs downloaded at runtime.
    ///
    /// **`youngTreesWithoutVisits` deliberately does not get this treatment**, and the reason is on
    /// `youngTreesWithoutVisitsSQL(scope:)`.
    private var bloomTreeJoin: String {
        "t.\(schema.treeIdentityColumn) = lower(v.tree_uuid)"
    }

    // MARK: - Is there an almanac to have at all

    /// Whether the merged inventory holds **any** record inside this scope (ERRATA E182).
    ///
    /// A polygon proves its own existence: `resolveNeighborhood` only returns one it found through a
    /// tree. A radius does not — a reader in Sacramento, or in the middle of the bay, has a
    /// perfectly well-formed circle around them with nothing in it, and an almanac headed
    /// `A 15-minute walk` over five withheld blocks would be claiming an area the record has never
    /// heard of. So the fallback is only taken when this returns true, and when it does not the
    /// screen says the one true sentence available: no inventory reaches here yet.
    ///
    /// `LIMIT 1` with no ordering and no join, so SQLite stops at the first row inside the box
    /// rather than counting a city. Vacant sites count — `Self.standing` is deliberately **not**
    /// applied. The question is whether the record covers this ground, not whether anything is
    /// growing on it, and a block of empty basins is coverage: it is what the
    /// `Where a tree could go` row is made of.
    public func holdsAnyRecord(
        scope: AlmanacScope,
        connection: SQLiteConnection
    ) throws -> Bool {
        let statement = try connection.cachedStatement(holdsAnyRecordSQL(scope: scope))
        _ = try statement.bind(scope.bindings)
        return try statement.fetchOne { _ in true } ?? false
    }

    /// **The statements in this file are properties so the gate can explain the text the app runs.**
    ///
    /// `MapQueryPlanTests`' header records what happened when they were not: the plans were pinned
    /// against SQL hand-copied into `DataGates.swift`, so changing the real query left the gate
    /// explaining the paraphrase. `AlmanacQueryPlanTests` reads these, and nothing else builds them
    /// — and `AlmanacStatementCensusTests` proves that what screen 12 prepares is exactly this set,
    /// which is the half a property reference alone cannot establish (PR #143's review demonstrated
    /// that on the Journal).
    ///
    /// Each takes the scope because `AlmanacScope.predicate(_:)` is two different `WHERE` fragments
    /// with two different plans — R29's polygon arm seeks `idx_trees_neighborhood`, its radius arm
    /// seeks `idx_trees_lat_lon` — so a gate that explained one arm would be silent about the other.
    func holdsAnyRecordSQL(scope: AlmanacScope) -> String {
        """
        SELECT 1 AS present
          FROM \(seed).trees t
         WHERE \(scope.predicate("t"))
           AND t.deleted_at IS NULL
         LIMIT 1
        """
    }

    // MARK: - This season · the elder

    /// The oldest recorded planting date in the neighborhood (SCREENS.md 12 §2 row 2).
    ///
    /// ```
    /// SEARCH t USING INDEX idx_trees_neighborhood_planted (neighborhood_id=? AND planted_on>?)
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
    /// ```
    ///
    /// The index exists for this read and for `recentPlanting`: without it the elder is a sort of
    /// every tree in the neighborhood, which is 16,176 rows in the Mission.
    ///
    /// `nil` when no tree here carries a planting date at all. That is a real outcome — DataSF fills
    /// `PlantDate` on 36% of rows — and it means the row does not draw, rather than drawing a tree
    /// whose age nobody recorded.
    public func elder(
        scope: AlmanacScope,
        connection: SQLiteConnection
    ) throws -> (treeID: UUID, speciesCommonName: String?, address: String?, plantedYear: Int)? {
        let statement = try connection.cachedStatement(elderSQL(scope: scope))
        _ = try statement.bind(scope.bindings)
        return try statement.fetchOne { row in
            (
                treeID: try row.uuid("tree_uuid"),
                speciesCommonName: try row.stringIfPresent("species_name"),
                address: try row.stringIfPresent("address"),
                plantedYear: try row.int("planted_year")
            )
        }
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    func elderSQL(scope: AlmanacScope) -> String {
        """
        SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.address AS address,
               t.planted_year AS planted_year,
               COALESCE(s.common_name, s.scientific_name) AS species_name
          FROM \(seed).trees t
          LEFT JOIN \(seed).species s ON s.id = t.species_current
         WHERE \(scope.predicate("t"))
           AND t.planted_on IS NOT NULL
           AND t.deleted_at IS NULL
           AND \(Self.standing)
         ORDER BY t.planted_on
         LIMIT 1
        """
    }

    // MARK: - This season · newest neighbors

    /// The trees planted in the neighborhood inside a date window, grouped by species
    /// (SCREENS.md 12 §2 row 3).
    ///
    /// Bounds are `YYYY-MM-DD` strings compared against `trees.planted_on`, which is stored at that
    /// grain. The column exists because this row asks about a *season* and `planted_year` cannot
    /// answer a question about a season — see the seed schema's note beside it.
    ///
    /// Returns one entry per species, most common first, plus the trees whose city label names no
    /// taxon (312 rows city-wide, ERRATA E14), which arrive with a `nil` name and are counted but
    /// never named.
    public func plantings(
        scope: AlmanacScope,
        from: String,
        to: String,
        connection: SQLiteConnection
    ) throws -> [(name: String?, treeCount: Int)] {
        let statement = try connection.cachedStatement(plantingsSQL(scope: scope))
        _ = try statement.bind(scope.bindings.merging([":from": from, ":to": to] as [String: SQLiteBindable?]) { a, _ in a })
        return try statement.fetchAll { row in
            (name: try row.stringIfPresent("species_name"), treeCount: try row.int("tree_count"))
        }
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    func plantingsSQL(scope: AlmanacScope) -> String {
        """
        SELECT COALESCE(s.common_name, s.scientific_name) AS species_name,
               COUNT(*) AS tree_count
          FROM \(seed).trees t
          LEFT JOIN \(seed).species s ON s.id = t.species_current
         WHERE \(scope.predicate("t"))
           AND t.planted_on BETWEEN :from AND :to
           AND t.deleted_at IS NULL
           AND \(Self.standing)
         GROUP BY t.species_current
         ORDER BY tree_count DESC, species_name
        """
    }

    /// The same trees `plantings` counted, as pins a map can draw, nearest first (ERRATA **E182**).
    ///
    /// **A second read of the same predicate, deliberately, and the split is `vacantSites`'.** The
    /// grouped read above prints two things the reader sees — a total and the leading species — and
    /// the total may never become the size of a page (ERRATA E38). So the count comes from the
    /// aggregate over the whole window and the rows come from here, capped, and `PinSet.isComplete`
    /// compares the two rather than either one claiming to be the other.
    ///
    /// The `WHERE` clause is copied from `plantings` word for word and must stay that way: the row's
    /// sentence counts one set and its map draws another only if these two drift apart. The `LEFT`
    /// join and `Self.standing` are there for the reasons they are there in every other read in this
    /// file, so a newly planted tree with no species is still on the map the row's own count included
    /// it in.
    public func plantingPins(
        scope: AlmanacScope,
        from: String,
        to: String,
        near coordinate: Coordinate,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> [TreePin] {
        // Longitude degrees are shorter than latitude degrees by cos(lat); squaring the ratio makes
        // the two terms comparable, exactly as `TreeQueries.nearest` does it.
        let longitudeWeight = pow(cos(coordinate.latitude * .pi / 180), 2)
        let statement = try connection.cachedStatement(plantingPinsSQL(scope: scope))
        _ = try statement.bind(scope.bindings.merging([
            ":from": from,
            ":to": to,
            ":lat": coordinate.latitude,
            ":lon": coordinate.longitude,
            ":lonWeight": longitudeWeight,
            ":limit": limit
        ] as [String: SQLiteBindable?]) { a, _ in a })
        return try statement.fetchAll { row in try Self.pin(from: row) }
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    func plantingPinsSQL(scope: AlmanacScope) -> String {
        """
        SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.lat AS lat,
               t.lon AS lon,
               t.status AS status,
               t.source AS source,
               t.verification_state AS verification_state,
               s.\(schema.speciesIdentityColumn) AS species_uuid
          FROM \(seed).trees t
          LEFT JOIN \(seed).species s ON s.id = t.species_current
         WHERE \(scope.predicate("t"))
           AND t.planted_on BETWEEN :from AND :to
           AND t.deleted_at IS NULL
           AND \(Self.standing)
         ORDER BY (t.lat - :lat) * (t.lat - :lat)
                + (t.lon - :lon) * (t.lon - :lon) * :lonWeight
         LIMIT :limit
        """
    }

    // MARK: - Who lives here

    /// Every species the city inventory records in the neighborhood, most common first
    /// (SCREENS.md 12 §3).
    ///
    /// ```
    /// SEARCH t USING INDEX idx_trees_neighborhood (neighborhood_id=?)
    /// SEARCH s USING INTEGER PRIMARY KEY (rowid=?)
    /// ```
    ///
    /// Read whole rather than `LIMIT 3`, because the card prints two numbers a page cannot support:
    /// the header's species count and the "Everyone else" remainder, which is one minus the shares
    /// above it. A limited read would make the remainder wrong in the flattering direction. The cost
    /// is the size of a neighborhood's species list — 215 rows in Sunset/Parkside, the largest in
    /// the city — which is nothing next to being wrong.
    ///
    /// The `JOIN` (not `LEFT JOIN`) excludes **the non-taxon rows**: a mix of species is a mix of
    /// species, and a tree the city labeled `Shrub` belongs in neither the numerator nor the
    /// denominator of a share.
    ///
    /// **It does not exclude vacant sites, and widening it would not admit one** (ERRATA E115).
    /// `Self.standing` is what excludes them, one line below; `species_current` is NULL on all
    /// 12,518 of them, and `s.id = t.species_current` is NULL rather than true for a NULL, so a
    /// site cannot survive the inner join in the first place. Measured on the shipped seed in
    /// Sunset/Parkside, replacing this join with a `LEFT JOIN` admits **zero** vacant sites and
    /// **52** non-taxon trees: 215 species rows become 216, the last of them nameless, and the
    /// denominator every share is divided by moves from 11,026 to 11,078. That last number is
    /// RULINGS **R5**, which fixed screen 08's denominator at 215 and ruled it stays there. It
    /// would also throw before it drew: `row.uuid("species_uuid")` on the nameless group raises
    /// `unexpectedNull`, `AlmanacModel.load()` catches it as `.failed`, and screen 12 renders
    /// `AlmanacCopy.loadFailed` and a retry in place of the almanac (ERRATA E126) — so widening
    /// this join costs the reader the whole screen, not one group.
    public func speciesMix(
        scope: AlmanacScope,
        connection: SQLiteConnection
    ) throws -> [SpeciesShare] {
        let statement = try connection.cachedStatement(speciesMixSQL(scope: scope))
        _ = try statement.bind(scope.bindings)
        return try statement.fetchAll { row in
            SpeciesShare(
                speciesID: try row.uuid("species_uuid"),
                name: try row.string("species_name"),
                treeCount: try row.int("tree_count")
            )
        }
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    func speciesMixSQL(scope: AlmanacScope) -> String {
        """
        SELECT s.\(schema.speciesIdentityColumn) AS species_uuid,
               COALESCE(s.common_name, s.scientific_name) AS species_name,
               COUNT(*) AS tree_count
          FROM \(seed).trees t
          JOIN \(seed).species s ON s.id = t.species_current
         WHERE \(scope.predicate("t"))
           AND t.deleted_at IS NULL
           AND \(Self.standing)
         GROUP BY s.id
         ORDER BY tree_count DESC, species_name
        """
    }

    // MARK: - Where eyes are needed

    /// Young trees in the neighborhood that carry no visit since they were planted
    /// (SCREENS.md 12 §4).
    ///
    /// `NOT EXISTS` rather than a `LEFT JOIN … IS NULL`, so SQLite stops at the first visit it finds
    /// for a tree instead of materialising every visit that tree ever had.
    ///
    /// **The visit predicate names no contributor.** It asks whether the tree has been visited at
    /// all, which is the question §4's copy asks; scoping it to the caller would turn the app's one
    /// directed ask into a private to-do list, and would make two people standing on the same block
    /// see different trees. `captured_at >= planted_on` is §4's "since planting", literally — an
    /// ISO-8601 timestamp and a `YYYY-MM-DD` date compare correctly as text because the first is a
    /// prefix-extension of the second.
    ///
    /// Reads one row more than `limit` so the caller can prove whether the series is whole.
    ///
    /// **Returns whole pins since ERRATA E129.** The two extra columns and the species join are what
    /// let §4's row hand its nine trees to a map instead of handing over one id: a pin the
    /// destination draws has to be the pin screen 01 would draw for the same record, and `MapPinKind`
    /// answers that from `status`, `source` and `verification_state`. The coordinate was already
    /// being selected here — `LocalAPI` needs it to check the "within a 15-minute walk" claim — and
    /// was thrown away one line later, which is how §4 came to know where all nine trees were while
    /// being able to send the reader to only one of them.
    ///
    /// The join is `LEFT`, as `elder`'s is and for the same reason: 312 trees city-wide carry a city
    /// label that names no taxon (ERRATA E14), and a young tree with no species is still a young tree
    /// nobody has visited. It must not drop out of a count the card prints.
    public func youngTreesWithoutVisits(
        scope: AlmanacScope,
        plantedOnOrAfter: String,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> [TreePin] {
        let statement = try connection.cachedStatement(youngTreesWithoutVisitsSQL(scope: scope))
        _ = try statement.bind(scope.bindings.merging([
            ":since": plantedOnOrAfter,
            ":limit": limit
        ] as [String: SQLiteBindable?]) { a, _ in a })
        return try statement.fetchAll { row in try Self.pin(from: row) }
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    ///
    /// ── **Why the `COLLATE NOCASE` in here stays, when `firstBloom`'s went** ────────────────────
    /// ROADMAP asked for both of this file's collated joins to take `GroveQueries.treeJoin`'s
    /// `lower()` treatment. `bloomTreeJoin` took it; this one cannot, and the difference is which
    /// side of the comparison the index that would answer it lives on.
    ///
    /// `firstBloom` drives from `visits` and probes the **seed**, so `lower()` on the contributions
    /// side leaves `trees.uuid` bare and `sqlite_autoindex_trees_1` answers — and the value it is
    /// compared against is lower case by a contract `DataGates.armsWithUppercaseUUIDs` asserts per
    /// published file.
    ///
    /// This subquery is the other way round. It is correlated on `t`, so it runs per candidate tree
    /// and the index that would answer it is `idx_visits_tree` — over a column in **`main`**. To
    /// seek that, `v.tree_uuid` has to be left bare, which means normalizing the seed side *up*:
    /// `v.tree_uuid = upper(t.uuid)`. That is only correct while every row in `visits` stores its
    /// `tree_uuid` upper case, and **nothing asserts that.** Today's single writer
    /// (`ContributionStore.insert`, binding a `UUID` through `SQLiteValue`) does produce Foundation's
    /// uppercase spelling, but the column is plain `TEXT` with `BINARY` collation, no gate examines
    /// it, and `AppSchema`'s own note beside `anonymized_contributions` records why that is not
    /// enough: a uuid reaches these tables by two routes, `SQLiteValue`'s uppercase `uuidString` and
    /// `JSONEncoder`'s, "and the whole guarantee would turn on those two agreeing about case for
    /// ever". That table's answer was `COLLATE NOCASE` **on the column**, which makes its index
    /// case-insensitive and seekable — and doing the same here is a schema migration, which this
    /// change is not the author of.
    ///
    /// The failure mode decides it. A wrong `lower()` in `firstBloom` returns **nothing**, which is
    /// loud. A wrong `upper()` here returns young trees that *have* been visited, as trees nobody
    /// has been to — the app's one directed ask (D1), sending readers to trees that need no eyes,
    /// silently and only on a device whose rows spell a uuid the other way. Trading that for a seek
    /// over one contributor's own visits is not a trade worth making without the migration that
    /// makes it true.
    ///
    /// `AlmanacQueryPlanTests.theYoungTreeSubqueryIsTheKnownScan` pins the plan this leaves, so the
    /// day the migration lands this paragraph goes red rather than staying wrong.
    func youngTreesWithoutVisitsSQL(scope: AlmanacScope) -> String {
        """
        SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.lat AS lat,
               t.lon AS lon,
               t.status AS status,
               t.source AS source,
               t.verification_state AS verification_state,
               s.\(schema.speciesIdentityColumn) AS species_uuid
          FROM \(seed).trees t
          LEFT JOIN \(seed).species s ON s.id = t.species_current
         WHERE \(scope.predicate("t"))
           AND t.planted_on >= :since
           AND t.deleted_at IS NULL
           AND \(Self.standing)
           AND NOT EXISTS (
                 SELECT 1 FROM visits v
                  WHERE v.tree_uuid = t.\(schema.treeIdentityColumn) COLLATE NOCASE
                    AND v.deleted_at IS NULL
                    AND v.captured_at >= t.planted_on
               )
         ORDER BY t.planted_on, t.id
         LIMIT :limit
        """
    }

    /// One `TreePin` out of a row of `seed.trees`.
    ///
    /// Shared by the two reads that feed a map (ERRATA E129) so that the vocabulary a pin is drawn in
    /// is decided in one place, and the same place `TreeQueries.pins` decides it — a group whose
    /// members were built differently from the map's own would be a second answer to "what kind of
    /// pin is this record", which is the shape of defect RULINGS R7 closed.
    private static func pin(from row: SQLiteRow) throws -> TreePin {
        TreePin(
            id: try row.uuid("tree_uuid"),
            coordinate: Coordinate(
                latitude: try row.double("lat"),
                longitude: try row.double("lon")
            ),
            status: try row.value("status", TreeStatus.self),
            source: try row.value("source", TreeSource.self),
            verificationState: try row.value("verification_state", VerificationState.self),
            speciesID: try row.uuidIfPresent("species_uuid")
        )
    }

    // MARK: - This season · the first bloom

    /// The earliest flowering visit recorded in the neighborhood this year (SCREENS.md 12 §2 row 1).
    ///
    /// `flowering` is `PhenologyTag`'s own raw value and `visits.phenology_tags` is a JSON array of
    /// them, so the membership test is `json_each` rather than a `LIKE` over the serialized array —
    /// a `LIKE '%flowering%'` would also match a tag that merely contained the word.
    ///
    /// **What this counts, and what it refuses to count.** `MIN(captured_at)` is an event, not an
    /// activity level. `COUNT(DISTINCT COALESCE(user_id, device_id))` is A8's headcount — distinct
    /// people, never occasions, so somebody who photographs the same blossom nine times is one
    /// person here, which is exactly why D1 permits the number at all. Neither value can be turned
    /// back into who: no identity column is projected.
    ///
    /// Which tree wins is the earliest sighting, ties broken on the tree's uuid so the answer does
    /// not flicker between two trees that bloomed the same second.
    ///
    /// **`Self.standing` applies here too, and did not until ERRATA E115.** This is the only read
    /// in the file that starts from a contribution rather than from the inventory, and it was the
    /// only one that filtered nothing but `deleted_at`. A `flowering` visit recorded against a
    /// vacant site therefore drew `First bloom of the year` over a planting basin, named by its
    /// street, tappable — the one row on screen 12 that names a specific record was the one that
    /// could name a record with no tree in it. Nothing in the app can create that visit today, but
    /// only because E113 redirects a site away from the profile the camera opens from: the almanac
    /// was relying on a guard in another feature to keep its own rule. The same predicate also
    /// drops a bloom recorded on a tree since removed, which is the rule saying what it always
    /// said — the row invites you to go and look at the tree.
    public func firstBloom(
        scope: AlmanacScope,
        since: Date,
        connection: SQLiteConnection
    ) throws -> (treeID: UUID, speciesCommonName: String?, address: String?, firstSeenAt: Date, observerCount: Int)? {
        let statement = try connection.cachedStatement(firstBloomSQL(scope: scope))
        _ = try statement.bind(scope.bindings.merging([
            ":since": since,
            ":flowering": PhenologyTag.flowering.rawValue
        ] as [String: SQLiteBindable?]) { a, _ in a })
        return try statement.fetchOne { row in
            (
                treeID: try row.uuid("tree_uuid"),
                speciesCommonName: try row.stringIfPresent("species_name"),
                address: try row.stringIfPresent("address"),
                firstSeenAt: try row.date("first_seen_at"),
                observerCount: try row.int("observer_count")
            )
        }
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property, and `bloomTreeJoin` for why the
    /// join in it normalizes the contributions side rather than collating the comparison.
    func firstBloomSQL(scope: AlmanacScope) -> String {
        """
        SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.address AS address,
               COALESCE(s.common_name, s.scientific_name) AS species_name,
               MIN(v.captured_at) AS first_seen_at,
               COUNT(DISTINCT COALESCE(v.user_id, v.device_id)) AS observer_count
          FROM visits v
          JOIN \(seed).trees t ON \(bloomTreeJoin)
          LEFT JOIN \(seed).species s ON s.id = t.species_current
         WHERE v.deleted_at IS NULL
           AND v.captured_at >= :since
           AND \(scope.predicate("t"))
           AND t.deleted_at IS NULL
           AND \(Self.standing)
           AND EXISTS (
                 SELECT 1 FROM json_each(v.phenology_tags)
                  WHERE json_each.value = :flowering
               )
         GROUP BY t.id
         ORDER BY first_seen_at, tree_uuid
         LIMIT 1
        """
    }

    // MARK: - Where a tree could go · the vacant planting sites

    /// How many planting sites in the neighborhood have no tree in them, and the nearest one to the
    /// reader (RULINGS R10, closing the proposal ERRATA E115 made and did not build).
    ///
    /// **This is the one read in the file that inverts `Self.standing`.** Every other read asks for a
    /// tree the city believes is standing; this asks for the basins that are the opposite — a
    /// `vacant_site` is exactly a mapped hole with nothing growing in it, and screen 12's
    /// `Where a tree could go` block is the one honest thing the almanac can say about the 12,518 rows
    /// the rest of the screen excludes by design. It counts *records the city holds*, not anything
    /// anybody did, so ARCHITECTURE §5.1's "a count of user actions wearing a different noun" trap
    /// does not apply and it needs no A8 floor.
    ///
    /// The count and the nearest come from one scan of `idx_trees_neighborhood`: `COUNT(*)` over the
    /// filtered set and, from the same set, the id with the smallest squared distance. E115 measured
    /// every one of the 41 neighborhoods carrying between 4 and 1,474 sites, so `count` is never zero
    /// where a neighborhood resolved — but the caller still treats zero as "no block", because §5.6
    /// is a rule about the general case rather than about today's seed.
    ///
    /// `nearest` is empty only if `count` is zero. Every row in it is a `vacant_site` in *this*
    /// neighborhood, so the destination can never show the reader a basin in the next neighborhood
    /// over — the block's subject and its destination are the same set.
    ///
    /// **`nearest` is a list rather than one id since ERRATA E129**, and the two halves are
    /// deliberately separate reads of the same index. The count is a `COUNT(*)` over the whole
    /// filtered set and has to stay that way: it is the number screen 12 prints, so it may never
    /// become the size of a page (ERRATA E38). The rows are the nearest `limit` of that set, which is
    /// all a map can hold — E115 measured neighborhoods at between 4 and 1,474 sites. Because the
    /// total is read independently, the caller can prove whether the page is the whole group by
    /// comparing the two, which is what `PinSet.isComplete` does.
    public func vacantSites(
        scope: AlmanacScope,
        near coordinate: Coordinate,
        limit: Int,
        connection: SQLiteConnection
    ) throws -> (count: Int, nearest: [TreePin]) {
        let counted = try connection.cachedStatement(vacantSiteCountSQL(scope: scope))
        _ = try counted.bind(scope.bindings)
        let count = try counted.fetchOne { try $0.int("site_count") } ?? 0
        guard count > 0 else { return (count: 0, nearest: []) }

        // Longitude degrees are shorter than latitude degrees by cos(lat); squaring the ratio makes
        // the two terms comparable, exactly as `TreeQueries.nearest` does it.
        let longitudeWeight = pow(cos(coordinate.latitude * .pi / 180), 2)
        let statement = try connection.cachedStatement(vacantSitePinsSQL(scope: scope))
        _ = try statement.bind(scope.bindings.merging([
            ":lat": coordinate.latitude,
            ":lon": coordinate.longitude,
            ":lonWeight": longitudeWeight,
            ":limit": limit
        ] as [String: SQLiteBindable?]) { a, _ in a })
        // `species_uuid` is a literal NULL rather than a join, and that is a measurement rather than
        // a shortcut: `species_current` is NULL on all 12,518 vacant sites (`AlmanacVacantSiteTests`
        // asserts it against the shipped seed), so a `LEFT JOIN` here could only ever return NULL.
        // A basin has nothing to identify — the reason `SiteCopy` exists at all (ERRATA E107).
        return (count: count, nearest: try statement.fetchAll { row in try Self.pin(from: row) })
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    func vacantSiteCountSQL(scope: AlmanacScope) -> String {
        """
        SELECT COUNT(*) AS site_count
          FROM \(seed).trees t
         WHERE \(scope.predicate("t"))
           AND t.status = 'vacant_site'
           AND t.deleted_at IS NULL
        """
    }

    /// See `holdsAnyRecordSQL(scope:)` for why this is a property.
    func vacantSitePinsSQL(scope: AlmanacScope) -> String {
        """
        SELECT t.\(schema.treeIdentityColumn) AS tree_uuid,
               t.lat AS lat,
               t.lon AS lon,
               t.status AS status,
               t.source AS source,
               t.verification_state AS verification_state,
               NULL AS species_uuid
          FROM \(seed).trees t
         WHERE \(scope.predicate("t"))
           AND t.status = 'vacant_site'
           AND t.deleted_at IS NULL
         ORDER BY (t.lat - :lat) * (t.lat - :lat)
                + (t.lon - :lon) * (t.lon - :lon) * :lonWeight
         LIMIT :limit
        """
    }
}
