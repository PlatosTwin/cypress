import Foundation

/// The SQL half of `InventoryUnion`: the catalogs it materializes and the views over them.
///
/// Split from the type itself because it is text generation and nothing else — every function here
/// takes arms and returns a statement, so the shapes it produces can be read as SQL rather than
/// reconstructed from interpolation scattered through a builder.
///
/// # Tables for the small things, views for the big ones
///
/// `trees` and its two companions are views: nine hundred thousand rows cannot be copied at open,
/// and they do not need to be — the arms carry the indexes and the union prunes at them.
///
/// Everything else is **materialized into `temp`**, and the reason is the query planner rather than
/// tidiness. A compound view has no indexes of its own, so `species` would lose the four the files
/// carry and `id_spaces` would lose the `TEXT PRIMARY KEY` that
/// `CivicShortNameTests.queryPlanMatchesTheProfileQuery` pins by name. Rebuilding them as real
/// tables with the same constraints gets the same index names — `sqlite_autoindex_species_1`,
/// `sqlite_autoindex_id_spaces_1` — because SQLite derives those names from the constraints, and a
/// `CREATE TABLE … AS SELECT` copies columns while dropping every constraint there is. That is what
/// `SQLiteConnection.columnDefinitions(ofTable:in:)` exists for.
///
/// The cost is 731 species, 21,179 trigrams, 41 neighborhoods and six rows of dimension tables,
/// once, at open.
extension InventoryUnion {

    // MARK: - Catalogs

    /// Materializes every small table and the two translations that map each arm's own integers
    /// onto them.
    ///
    /// **Species merge on `uuid`; neighborhoods do not merge at all.** A species uuid is `uuid5` of
    /// a scientific name, so the same species carries the same uuid in every file ever built and
    /// two arms naming it are naming one thing. A neighborhood is keyed by a name unique only
    /// *within* a file, and two cities may each have a `Downtown` — merging those would put San
    /// Jose's trees in a San Francisco neighborhood. Species are shared authored content and merge;
    /// neighborhoods are city data and do not.
    ///
    /// **Every statement that reads an arm is wrapped in `InventoryUnion.contributing`**, so a
    /// failure carries the file that caused it back to `build` and is refused as that file rather
    /// than as the launch. This is the phase that made a bad pack fatal, and the reason is visible
    /// in the shape of the code: the statements below write into `temp` and read from `invN`, so
    /// SQLite's own error names the destination and says nothing about the source. Nothing here may
    /// call `connection.execute` against an arm outside a `contributing` block.
    static func createCanonicalCatalogs(
        arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws {
        guard let first = arms.first else { return }

        try createSpecies(arms: arms, first: first, on: connection)
        try createSpeciesTranslation(arms: arms, on: connection)
        try createSpeciesTrigrams(arms: arms, on: connection)
        try createNeighborhoods(arms: arms, first: first, on: connection)
        try createDimensionTables(arms: arms, on: connection)
    }

    // MARK: Species

    private static func createSpecies(
        arms: [InventoryArm],
        first: InventoryArm,
        on connection: SQLiteConnection
    ) throws {
        let temp = SeedDatabase.schemaName
        let (columns, list) = try InventoryUnion.contributing(first) {
            // `uuid TEXT NOT NULL UNIQUE` is what makes SQLite name the index
            // `sqlite_autoindex_species_1`, which `TreeQueries.speciesRowIDs` and
            // `SpeciesQueries.projection` both document as the plan they run on. A file in the
            // original TEXT-primary-key shape has no `uuid` column at all and gets no such
            // constraint, exactly as it has none today.
            var constraints = ["id": "PRIMARY KEY"]
            if first.schema.speciesIdentityColumn == "uuid" {
                constraints["uuid"] = "NOT NULL UNIQUE"
            }
            try mirrorTable("species", from: first, inlineConstraints: constraints, on: connection)

            let columns = try connection.columnNames(ofTable: "species", in: temp)
            let list = columns.joined(separator: ", ")
            // See `renumbered(_:)`: a table whose only column is `id` projects nothing after it, and
            // `SELECT x, FROM t` is a syntax error rather than an empty projection.
            try connection.execute("""
            INSERT INTO \(temp).species (\(list)) SELECT \(list) FROM \(first.schemaName).species
            """)
            return (columns, list)
        }

        // The three named indexes the files carry, each created only if the column it names is
        // actually there. Same posture as the view's projection: ask the file what it has. A
        // fixture whose `species` is `(id, uuid)` is a legitimate inventory — it simply has no
        // scientific name to index.
        //
        // **Created before the later arms insert, and that ordering is load-bearing.**
        // `idx_species_scientific_name` is UNIQUE. Built afterwards, a pack carrying a species whose
        // `uuid` and `scientific_name` disagree with the catalog's makes the `CREATE UNIQUE INDEX`
        // throw — a statement that belongs to no arm, at a point where the offending rows are
        // already merged and unattributable. Built first, the same pack's own `INSERT` is what
        // fails, inside its own `contributing` block, so the file that caused it is the file that is
        // refused. Maintaining three indexes across 731 rows is not a cost worth trading that for.
        let indexed: [(String, String, Bool)] = [
            ("idx_species_scientific_name", "scientific_name", true),
            ("idx_species_common_name", "common_name", false),
            ("idx_species_curated", "curated", false)
        ]
        for (name, column, unique) in indexed where columns.contains(column) {
            try InventoryUnion.contributing(first) {
                try connection.execute(
                    "CREATE \(unique ? "UNIQUE " : "")INDEX \(temp).\(name) ON species(\(column))"
                )
            }
        }

        // Later arms contribute only species the catalog does not already know, numbered above
        // the current maximum. `ROW_NUMBER() OVER (ORDER BY s.id)` makes that deterministic, so two
        // runs over the same files build the same catalog.
        let tail = Self.renumbered(columns, alias: "s")
        for arm in arms.dropFirst() {
            try InventoryUnion.contributing(arm) {
                try connection.execute("""
                INSERT INTO \(temp).species (\(list))
                SELECT (SELECT COALESCE(MAX(id), 0) FROM \(temp).species)
                       + ROW_NUMBER() OVER (ORDER BY s.id)\(tail)
                  FROM \(arm.schemaName).species s
                 WHERE s.\(arm.schema.speciesIdentityColumn)
                       NOT IN (SELECT \(first.schema.speciesIdentityColumn) FROM \(temp).species)
                """)
            }
        }
    }

    /// `(inv, local_id) -> (canonical id, uuid)`.
    ///
    /// `WITHOUT ROWID` with the pair as the primary key, because every read of it is a seek on the
    /// whole key: the trees view joins `sx.inv = <k> AND sx.local_id = t.species_current`, which
    /// the planner answers `SEARCH sx USING PRIMARY KEY`. Measured against an arm whose species
    /// numbering was deliberately permuted, a species-narrowed viewport still resolves through
    /// `idx_trees_species_current` on every arm — the `LEFT JOIN` converts to an inner one because
    /// the caller's `WHERE` constrains the right-hand side, and the planner is then free to drive
    /// from this table.
    ///
    /// The `uuid` column rides along so the trees view can project a tree's species uuid without a
    /// second join.
    private static func createSpeciesTranslation(
        arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws {
        let temp = SeedDatabase.schemaName
        try connection.execute("""
        CREATE TABLE \(temp).cypress_species_xlat (
            inv INTEGER NOT NULL, local_id INTEGER NOT NULL,
            canon_id INTEGER NOT NULL, uuid TEXT NOT NULL,
            PRIMARY KEY (inv, local_id)
        ) WITHOUT ROWID
        """)
        for arm in arms {
            try InventoryUnion.contributing(arm) {
                let identity = arm.schema.speciesIdentityColumn
                try connection.execute("""
                INSERT INTO \(temp).cypress_species_xlat (inv, local_id, canon_id, uuid)
                SELECT \(arm.ordinal), s.id, c.id, c.\(identity)
                  FROM \(arm.schemaName).species s
                  JOIN \(temp).species c ON c.\(identity) = s.\(identity)
                """)
            }
        }
    }

    /// The search index, re-keyed through the translation.
    ///
    /// De-duplicated on `(trigram, species_id)`, which is the table's own primary key in every
    /// file. A species only one arm carries keeps its trigrams, so search recall is the union's
    /// rather than the first arm's.
    private static func createSpeciesTrigrams(
        arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws {
        let temp = SeedDatabase.schemaName
        // **Only when some arm actually carries one.** Creating it unconditionally would make
        // `SeedSchema.hasSpeciesTrigrams` read true for a union of files that have no trigram
        // index, and the species search would take the similarity path against an empty table
        // instead of the substring fallback ERRATA E165 shipped.
        guard arms.contains(where: { $0.schema.hasSpeciesTrigrams }) else { return }
        try connection.execute("""
        CREATE TABLE \(temp).species_trigrams (
            trigram TEXT NOT NULL, species_id INTEGER NOT NULL,
            PRIMARY KEY (trigram, species_id)
        ) WITHOUT ROWID
        """)
        for arm in arms where arm.schema.hasSpeciesTrigrams {
            try InventoryUnion.contributing(arm) {
                try connection.execute("""
                INSERT OR IGNORE INTO \(temp).species_trigrams (trigram, species_id)
                SELECT g.trigram, x.canon_id
                  FROM \(arm.schemaName).species_trigrams g
                  JOIN \(temp).cypress_species_xlat x
                    ON x.inv = \(arm.ordinal) AND x.local_id = g.species_id
                """)
            }
        }
    }

    // MARK: Neighborhoods

    /// Every arm's neighborhoods, appended whole and renumbered — see `createCanonicalCatalogs`
    /// for why they are not merged by name.
    ///
    /// The offset is read back between arms rather than computed inside the statement, so the
    /// numbering the table gets and the numbering the translation records come from the same
    /// `ORDER BY n.id` and cannot disagree.
    private static func createNeighborhoods(
        arms: [InventoryArm],
        first: InventoryArm,
        on connection: SQLiteConnection
    ) throws {
        let temp = SeedDatabase.schemaName
        let (list, tail) = try InventoryUnion.contributing(first) {
            try mirrorTable(
                "neighborhoods", from: first, inlineConstraints: ["id": "PRIMARY KEY"],
                on: connection
            )
            let columns = try connection.columnNames(ofTable: "neighborhoods", in: temp)
            return (columns.joined(separator: ", "), Self.renumbered(columns, alias: "n"))
        }
        try connection.execute("""
        CREATE TABLE \(temp).cypress_hood_xlat (
            inv INTEGER NOT NULL, local_id INTEGER NOT NULL, canon_id INTEGER NOT NULL,
            PRIMARY KEY (inv, local_id)
        ) WITHOUT ROWID
        """)

        for arm in arms {
            // **The column list comes from the first arm and the rows come from this one**, which
            // is exactly where a pack that is one column short of the bundle throws:
            // `no such column: n.geom_geojson`. `CityLibrary.validateCityFile` cannot see it — it
            // checks four table names and three `trees` columns and never looks at `neighborhoods` —
            // so this is where such a file is finally refused, and it is refused as *this* file
            // rather than as the boot.
            try InventoryUnion.contributing(arm) {
                let offset = try scalar(
                    "SELECT COALESCE(MAX(id), 0) AS n FROM \(temp).neighborhoods", on: connection
                )
                try connection.execute("""
                INSERT INTO \(temp).neighborhoods (\(list))
                SELECT \(offset) + ROW_NUMBER() OVER (ORDER BY n.id)\(tail)
                  FROM \(arm.schemaName).neighborhoods n
                """)
                try connection.execute("""
                INSERT INTO \(temp).cypress_hood_xlat (inv, local_id, canon_id)
                SELECT \(arm.ordinal), n.id, \(offset) + ROW_NUMBER() OVER (ORDER BY n.id)
                  FROM \(arm.schemaName).neighborhoods n
                """)
            }
        }
    }

    // MARK: Dimension tables

    /// `dim_city`, `id_spaces`, `inventories`, `species_map` and `seed_meta`.
    ///
    /// Each is merged first-arm-wins on its own key, because these describe the same civic facts
    /// rather than per-city data: two files that both carry the id space `sf` describe it the same
    /// way, and whichever got there first is as good an answer as the other.
    ///
    /// **`dim_city` is renumbered and `id_spaces.city_id` is re-pointed through the slug.** The two
    /// are joined as `dc.id = isp.city_id` (`TreeQueries.treeSQL`), and `dim_city.id` is an integer
    /// local to its file — so a second arm's `city_id` would otherwise name whichever row of the
    /// merged table happened to land on that integer. The slug is the stable key (`us-ca-sf`), and
    /// it is what the re-pointing goes through.
    private static func createDimensionTables(
        arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws {
        let temp = SeedDatabase.schemaName

        if let first = arms.first(where: { $0.schema.hasDimCity }) {
            let columns = try InventoryUnion.contributing(first) {
                try mirrorTable(
                    "dim_city", from: first,
                    inlineConstraints: ["id": "PRIMARY KEY", "slug": "NOT NULL UNIQUE"],
                    on: connection
                )
                return try connection.columnNames(ofTable: "dim_city", in: temp)
            }
            let tail = Self.renumbered(columns, alias: "d")
            for arm in arms where arm.schema.hasDimCity {
                try InventoryUnion.contributing(arm) {
                    let offset = try scalar(
                        "SELECT COALESCE(MAX(id), 0) AS n FROM \(temp).dim_city", on: connection
                    )
                    try connection.execute("""
                    INSERT INTO \(temp).dim_city (\(columns.joined(separator: ", ")))
                    SELECT \(offset) + ROW_NUMBER() OVER (ORDER BY d.id)\(tail)
                      FROM \(arm.schemaName).dim_city d
                     WHERE d.slug NOT IN (SELECT slug FROM \(temp).dim_city)
                    """)
                }
            }
        }

        // **Mirrored on the TABLE being there, not on `trees.id_space`.** A file can carry
        // `id_spaces.short_name` and no `trees.id_space` at all — that shape is exactly what
        // `CivicShortNameTests` exists for — and gating this on `hasIdSpace` hid the very column
        // `SeedSchema.hasCivicShortNames` is read from.
        let withIDSpaces = try armsCarrying("id_spaces", among: arms, on: connection)
        if let first = withIDSpaces.first {
            let columns = try InventoryUnion.contributing(first) {
                try mirrorTable(
                    "id_spaces", from: first, inlineConstraints: ["id": "PRIMARY KEY"],
                    on: connection
                )
                return try connection.columnNames(ofTable: "id_spaces", in: temp)
            }
            for arm in withIDSpaces {
                try InventoryUnion.contributing(arm) {
                    // Asked of the arm rather than inferred from the first one: `city_id` arrived
                    // with s16, and an s15 file beside an s16 one is a configuration this build
                    // supports.
                    let armColumns = try connection.columnNames(
                        ofTable: "id_spaces", in: arm.schemaName
                    )
                    let select = columns.map { column -> String in
                        guard column == "city_id" else {
                            return armColumns.contains(column) ? "s.\(column)" : "NULL"
                        }
                        guard armColumns.contains("city_id"), arm.schema.hasDimCity else {
                            return "NULL"
                        }
                        // The one column that points into a table this build just renumbered, so it
                        // is re-pointed through the slug, which is the key that survives the
                        // renumbering.
                        return """
                        (SELECT c.id FROM \(temp).dim_city c
                           JOIN \(arm.schemaName).dim_city d2 ON d2.slug = c.slug
                          WHERE d2.id = s.city_id)
                        """
                    }.joined(separator: ", ")
                    try connection.execute("""
                    INSERT INTO \(temp).id_spaces (\(columns.joined(separator: ", ")))
                    SELECT \(select) FROM \(arm.schemaName).id_spaces s
                     WHERE s.id NOT IN (SELECT id FROM \(temp).id_spaces)
                    """)
                }
            }

            try mirrorFirstWins(
                "inventories", key: "id", arms: withIDSpaces,
                inlineConstraints: ["id": "PRIMARY KEY"], on: connection
            )
        }

        // `dim_region` — the s17 pack dimension. Keyed on `pack_id`, which is a pack's identity
        // and deliberately not `dim_city.slug`.
        try mirrorFirstWins(
            "dim_region", key: "pack_id", arms: arms,
            inlineConstraints: ["id": "PRIMARY KEY", "pack_id": "NOT NULL UNIQUE"], on: connection
        )

        try mirrorFirstWins(
            "species_map", key: "qspecies_string", arms: arms,
            inlineConstraints: ["qspecies_string": "PRIMARY KEY"], on: connection
        )

        // The build receipts, merged key by key. `CypressStore.inventories(in:)` reads every
        // `inventory_<id>_name` out of this, so merging is what lets a tree from a downloaded pack
        // name the inventory that listed it. The file-scoped keys — `generated_at`,
        // `identity_prefix` — resolve to the bundle's, which is what `seedProvenance` already
        // documents itself as: the file's *primary* inventory, and the wrong answer for any row
        // whose `inventory_source` says otherwise.
        try mirrorFirstWins(
            "seed_meta", key: "key", arms: arms,
            inlineConstraints: ["key": "PRIMARY KEY"], on: connection
        )
    }

    // MARK: - Views

    /// **Not a boot-failure vector, and it was checked rather than assumed.** SQLite accepts a
    /// `CREATE VIEW` over a missing table or a missing column and resolves the references at query
    /// time, so none of the four statements below can throw on account of an arm's shape. That is
    /// why the containment `createCanonicalCatalogs` carries stops here: there is no per-arm
    /// statement to attribute, because there is no per-arm statement.
    ///
    /// The projections defend themselves anyway — `treesSQL` and `treesRtreeSQL` name a column only
    /// when that arm has it — so what reaches a reader through a malformed arm is `NULL`, not an
    /// error at the next map pan.
    static func createViews(arms: [InventoryArm], on connection: SQLiteConnection) throws {
        guard !arms.isEmpty else { return }
        let temp = SeedDatabase.schemaName
        try connection.execute("CREATE VIEW \(temp).trees AS \(treesSQL(arms: arms))")
        try connection.execute("CREATE VIEW \(temp).trees_geo AS \(treesGeoSQL(arms: arms))")
        try connection.execute("CREATE VIEW \(temp).trees_area AS \(treesAreaSQL(arms: arms))")
        try connection.execute("CREATE VIEW \(temp).trees_rtree AS \(treesRtreeSQL(arms: arms))")
        try connection.execute(
            "CREATE VIEW \(temp).species_assertions AS \(assertionsSQL(arms: arms))"
        )
    }

    /// The full union. Every column the query layer reads, normalized across generations, plus the
    /// three the union itself adds: `inv`, `local_id` and the composite `id`.
    ///
    /// An arm that predates a column projects `NULL` for it rather than being refused — the same
    /// posture `SeedSchema` takes everywhere else.
    static func treesSQL(arms: [InventoryArm]) -> String {
        // **A column is projected when SOME arm has it, and omitted entirely when none does.**
        //
        // Two rules in one, and both are load-bearing. A `UNION ALL` needs every arm to project the
        // same columns, so an arm that predates one projects `NULL` for it rather than naming it —
        // without that, `CREATE VIEW` over an older generation throws `no such column` and takes
        // the whole union down. But a column NO arm has must not appear either, because
        // `SeedSchema.introspect` reads the view to decide what the inventory carries: project a
        // NULL `id_space` for a file that has none and `hasIdSpace` reads true, the profile query
        // joins `id_spaces`, and a half-migrated file starts claiming a shape it does not have.
        // `CivicShortNameTests`, `DimCityTests` and `RegionGenerationTests` each pin one of those
        // shapes.
        let present = arms.reduce(into: Set<String>()) { $0.formUnion($1.treeColumns) }
        func has(_ column: String) -> Bool { present.contains(column) }
        return arms.map { arm in
            let s = arm.schema
            func tree(_ column: String) -> String {
                arm.treeColumns.contains(column) ? "t.\(column)" : "NULL"
            }
            /// A column and its alias, or nothing at all when the union does not carry it.
            func optional(_ column: String) -> String {
                has(column) ? "\(tree(column)) AS \(column)," : ""
            }
            return """
            SELECT \(arm.ordinal) AS inv, t.id AS local_id,
                   (\(InventoryUnion.armStride) * \(arm.ordinal) + t.id) AS id,
                   t.\(s.treeIdentityColumn) AS uuid,
                   \(optional("id_space"))
                   \(optional("region_id"))
                   \(tree("external_ref")) AS external_ref,
                   \(tree("source")) AS source,
                   \(optional("inventory_source"))
                   t.lat AS lat, t.lon AS lon,
                   \(tree("address")) AS address, \(tree("site_type")) AS site_type,
                   \(arm.treeColumns.contains("neighborhood_id") ? "hx.canon_id" : "NULL")
                       AS neighborhood_id,
                   \(tree("status")) AS status,
                   \(arm.treeColumns.contains("species_current") ? "sx.canon_id" : "NULL")
                       AS species_current,
                   \(arm.treeColumns.contains("species_current") ? "sx.uuid" : "NULL")
                       AS species_uuid,
                   \(tree("planted_year")) AS planted_year, \(tree("planted_on")) AS planted_on,
                   \(tree("dbh_city_cm_min")) AS dbh_city_cm_min, \(tree("dbh_city_cm_max")) AS dbh_city_cm_max,
                   \(has("site_lineage")
                       ? (arm.treeColumns.contains("site_lineage")
                          ? "(\(InventoryUnion.armStride) * \(arm.ordinal) + t.site_lineage) AS site_lineage,"
                          : "NULL AS site_lineage,")
                       : "")
                   \(tree("verification_state")) AS verification_state,
                   \(tree("legal_status")) AS legal_status, \(tree("caretaker")) AS caretaker,
                   \(tree("care_assistant")) AS care_assistant, \(tree("plant_type")) AS plant_type,
                   \(tree("plot_size")) AS plot_size, \(tree("permit_notes")) AS permit_notes,
                   \(optional("city_raw"))
                   \(tree("created_at")) AS created_at, \(tree("updated_at")) AS updated_at,
                   \(tree("deleted_at")) AS deleted_at
              FROM \(arm.schemaName).trees t
              \(arm.treeColumns.contains("species_current")
                ? """
                  LEFT JOIN \(SeedDatabase.schemaName).cypress_species_xlat sx
                         ON sx.inv = \(arm.ordinal) AND sx.local_id = t.species_current
                  """
                : "")
              \(arm.treeColumns.contains("neighborhood_id")
                ? """
                  LEFT JOIN \(SeedDatabase.schemaName).cypress_hood_xlat hx
                         ON hx.inv = \(arm.ordinal) AND hx.local_id = t.neighborhood_id
                  """
                : "")
             \(whereClause(arm.shadowed, alias: "t"))
            """
        }.joined(separator: "\nUNION ALL\n")
    }

    /// The map's relation: exactly the columns `idx_trees_lat_lon` covers, and nothing else.
    ///
    /// **A view's width is paid per row.** SQLite materializes a compound view as a co-routine and
    /// does not prune result columns the outer query never reads, so a view carrying
    /// `species_current` loses `COVERING INDEX idx_trees_lat_lon` and probes the table once per
    /// candidate. Measured over the whole of San Francisco: 72–81 ms through this view, ~100 ms
    /// through `trees`, against a 58–60 ms floor at the bare table.
    ///
    /// **Soft-deleted rows are excluded here rather than by a predicate on the query.**
    /// `deleted_at` is not in the covering index, so a caller-side `AND t.deleted_at IS NULL` would
    /// cost a table probe per row to change nothing on a file that has no such row. Only the arms
    /// that actually hold one pay anything.
    ///
    /// That removes a wrinkle rather than preserving it: `markerCells` used to be able to hand a
    /// cell to a soft-deleted tree, which `pins(rowIDs:)` then dropped, leaving the cell empty. The
    /// cell now goes to the next tree in it.
    static func treesGeoSQL(arms: [InventoryArm]) -> String {
        arms.map { arm in
            var predicates = shadowPredicates(arm.shadowed, alias: "t")
            if arm.hasSoftDeletedTrees { predicates.append("t.deleted_at IS NULL") }
            let clause = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
            return """
            SELECT \(arm.ordinal) AS inv, t.id AS local_id,
                   (\(InventoryUnion.armStride) * \(arm.ordinal) + t.id) AS id,
                   t.lat AS lat, t.lon AS lon
              FROM \(arm.schemaName).trees t\(clause)
            """
        }.joined(separator: "\nUNION ALL\n")
    }

    /// **The Grove's area relation: each arm's OWN `neighborhood_id` and `species_current`.**
    ///
    /// `trees` projects `hx.canon_id AS neighborhood_id` and `sx.canon_id AS species_current`, so a
    /// `WHERE t.neighborhood_id = ?` against it is a predicate on a **join output** and cannot reach
    /// `idx_trees_neighborhood` inside the arm. That is not a hypothetical: it is what PR #120's
    /// `schemaName` flip did to `GroveQueries.speciesIDs` without editing a line of it — measured
    /// 92 ms through `trees` against 2 ms here, for the identical 186-species answer over the
    /// bundled seed's Castro/Upper Market.
    ///
    /// This is the same move `trees_geo` makes for the map and the same reason: **a narrow relation
    /// beside the wide one so the predicate lands on a column an arm actually indexes.** The
    /// difference is which column — the map needs `(lat, lon, id)` because that is what
    /// `idx_trees_lat_lon` covers; the Grove needs the untranslated neighborhood and species keys
    /// because those are the columns the arms' own indexes are built on.
    ///
    /// **The ids here are arm-local and are useless on their own.** A caller filters with them and
    /// then translates through `cypress_hood_xlat` / `cypress_species_xlat`, never the other way
    /// round — two arms may both hold a `neighborhood_id` of 3 and they are not the same place
    /// (`createCanonicalCatalogs` on why neighborhoods do not merge). `lat`/`lon` need no
    /// translation and are carried so `AlmanacScope.radius` reaches `idx_trees_lat_lon` on the same
    /// relation.
    ///
    /// Shadowing and soft deletes are applied inside the arm, exactly as `trees_geo` does, so the
    /// caller carries neither predicate: a downloaded pack still hides the bundle's rows for the id
    /// space it covers, on this path as on every other.
    static func treesAreaSQL(arms: [InventoryArm]) -> String {
        arms.map { arm in
            var predicates = shadowPredicates(arm.shadowed, alias: "t")
            if arm.hasSoftDeletedTrees { predicates.append("t.deleted_at IS NULL") }
            let clause = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
            func local(_ column: String) -> String {
                arm.treeColumns.contains(column) ? "t.\(column)" : "NULL"
            }
            return """
            SELECT \(arm.ordinal) AS inv, t.id AS local_id,
                   \(local("neighborhood_id")) AS neighborhood_local,
                   \(local("species_current")) AS species_local,
                   t.lat AS lat, t.lon AS lon
              FROM \(arm.schemaName).trees t\(clause)
            """
        }.joined(separator: "\nUNION ALL\n")
    }

    /// The R\*Tree arms, carrying `inv` and the arm-local join key so the pre-filter can be joined
    /// back on `(inv, local_id)` rather than on the composite id, which is not sargable.
    static func treesRtreeSQL(arms: [InventoryArm]) -> String {
        arms.map { arm in
            func box(_ column: String) -> String {
                arm.rtreeColumns.contains(column) ? "r.\(column)" : "NULL"
            }
            return """
            SELECT \(arm.ordinal) AS inv, r.id AS id,
                   \(box("min_lat")) AS min_lat, \(box("max_lat")) AS max_lat,
                   \(box("min_lon")) AS min_lon, \(box("max_lon")) AS max_lon
              FROM \(arm.schemaName).trees_rtree r
            """
        }.joined(separator: "\nUNION ALL\n")
    }

    /// Species assertions, re-keyed onto the union's tree ids and canonical species ids.
    ///
    /// Nothing in `Cypress/` queries this — only `DataGates.seedContract` does, and it checks that
    /// every assertion's tree and species resolve. Re-keying is what keeps that check meaningful
    /// under a union instead of comparing one arm's integers against another's.
    static func assertionsSQL(arms: [InventoryArm]) -> String {
        arms.map { arm in
            """
            SELECT \(arm.ordinal) AS inv,
                   (\(InventoryUnion.armStride) * \(arm.ordinal) + a.id) AS id,
                   (\(InventoryUnion.armStride) * \(arm.ordinal) + a.tree_id) AS tree_id,
                   x.canon_id AS species_id,
                   a.source AS source, a.confidence AS confidence,
                   a.asserted_by AS asserted_by,
                   a.superseded_by AS superseded_by, a.created_at AS created_at
              FROM \(arm.schemaName).species_assertions a
              LEFT JOIN \(SeedDatabase.schemaName).cypress_species_xlat x
                     ON x.inv = \(arm.ordinal) AND x.local_id = a.species_id
             \(assertionShadowClause(arm))
            """
        }.joined(separator: "\nUNION ALL\n")
    }

    /// An assertion belongs to a tree, so it is shadowed exactly when its tree is — and the
    /// predicate has to be written against `trees`, because `species_assertions` carries neither
    /// `id_space` nor an id in the same numbering.
    private static func assertionShadowClause(_ arm: InventoryArm) -> String {
        guard !arm.shadowed.isEmpty else { return "" }
        let inner = shadowPredicates(arm.shadowed, alias: "st").joined(separator: " AND ")
        return """
        WHERE EXISTS (SELECT 1 FROM \(arm.schemaName).trees st
                       WHERE st.id = a.tree_id AND \(inner))
        """
    }

    // MARK: - Shadow predicates

    static func shadowPredicates(_ shadowed: [ShadowedSpace], alias: String) -> [String] {
        var predicates: [String] = []
        var spaceNames: [String] = []
        for space in shadowed {
            switch space.mechanism {
            case let .rowIDRange(low, high):
                predicates.append("\(alias).id NOT BETWEEN \(low) AND \(high)")
            case .idSpacePredicate:
                spaceNames.append(space.idSpace)
            }
        }
        if !spaceNames.isEmpty {
            // The names come from `trees.id_space` in a file this build just opened, never from
            // anything a reader typed; the quote-doubling keeps that true rather than assuming it.
            let list = spaceNames
                .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
                .joined(separator: ", ")
            predicates.append("\(alias).id_space NOT IN (\(list))")
        }
        return predicates
    }

    private static func whereClause(_ shadowed: [ShadowedSpace], alias: String) -> String {
        let predicates = shadowPredicates(shadowed, alias: alias)
        return predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
    }

    // MARK: - Small helpers

    /// Recreates one of an arm's tables in `temp` with the same columns and the constraints named,
    /// so the indexes SQLite derives from them keep the names the plan gates assert.
    private static func mirrorTable(
        _ table: String,
        from arm: InventoryArm,
        inlineConstraints: [String: String],
        on connection: SQLiteConnection
    ) throws {
        let columns = try connection.columnDefinitions(ofTable: table, in: arm.schemaName)
        let body = columns.map { column in
            let type = column.type.isEmpty ? "" : " \(column.type)"
            let constraint = inlineConstraints[column.name].map { " \($0)" } ?? ""
            return "\(column.name)\(type)\(constraint)"
        }
        try connection.execute("""
        CREATE TABLE \(SeedDatabase.schemaName).\(table) (\(body.joined(separator: ", ")))
        """)
    }

    /// A table merged across arms with the first arm that carries a key winning it.
    private static func mirrorFirstWins(
        _ table: String,
        key: String,
        arms: [InventoryArm],
        inlineConstraints: [String: String],
        on connection: SQLiteConnection
    ) throws {
        let temp = SeedDatabase.schemaName
        let present = try armsCarrying(table, among: arms, on: connection)
        guard let first = present.first else { return }
        let (columns, list) = try InventoryUnion.contributing(first) {
            try mirrorTable(table, from: first, inlineConstraints: inlineConstraints, on: connection)
            let columns = try connection.columnNames(ofTable: table, in: temp)
            return (columns, columns.joined(separator: ", "))
        }
        for arm in present {
            try InventoryUnion.contributing(arm) {
                try connection.execute("""
                INSERT INTO \(temp).\(table) (\(list))
                SELECT \(columns.map { "d.\($0)" }.joined(separator: ", "))
                  FROM \(arm.schemaName).\(table) d
                 WHERE d.\(key) NOT IN (SELECT \(key) FROM \(temp).\(table))
                """)
            }
        }
    }

    /// The arms that carry one table, each `tableExists` question attributed to the arm it is asked
    /// of.
    ///
    /// Written as a loop rather than `try arms.filter { … }` for exactly that reason: a throwing
    /// `filter` closure loses which element was being tested, and that element is the whole answer
    /// `build` needs to refuse a pack instead of a launch.
    private static func armsCarrying(
        _ table: String,
        among arms: [InventoryArm],
        on connection: SQLiteConnection
    ) throws -> [InventoryArm] {
        var present: [InventoryArm] = []
        for arm in arms {
            let carries = try InventoryUnion.contributing(arm) {
                try connection.tableExists(table, in: arm.schemaName)
            }
            if carries { present.append(arm) }
        }
        return present
    }

    /// The columns after `id`, aliased and prefixed with the comma that separates them from the
    /// renumbered id — or the empty string when there are none.
    ///
    /// A table whose only column is `id` is a legitimate inventory shape (a fixture's
    /// `neighborhoods(id)` is one), and `SELECT x, FROM t` is a syntax error rather than a
    /// projection of nothing.
    private static func renumbered(_ columns: [String], alias: String) -> String {
        let tail = columns.dropFirst().map { "\(alias).\($0)" }.joined(separator: ", ")
        return tail.isEmpty ? "" : ", \(tail)"
    }

    private static func scalar(_ sql: String, on connection: SQLiteConnection) throws -> Int64 {
        let statement = try connection.prepare(sql)
        defer { statement.finalize() }
        return try statement.fetchOne { try $0.int64("n") } ?? 0
    }
}
