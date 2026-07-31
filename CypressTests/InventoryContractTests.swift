import CryptoKit
import Foundation
import Testing
@testable import Cypress

/// **The seed's half of the ingest contract** (`Tools/inventory_contract.py`).
///
/// The contract itself is Python, and so are its own tests
/// (`Tools/test_inventory_contract.py`, run with `python3`). What those cannot check is the thing
/// that actually ships: a 78 MB file in the app bundle whose 145,837 uuids are supposed to be a
/// pure function of San Francisco's own tree ids. This suite checks the file.
///
/// ── Why identity is derived here rather than pinned ───────────────────────────────────────
/// Writing down three known uuids would catch a rebuild that moved them and nothing else. The
/// property that matters is stronger and is worth the twenty lines of UUIDv5 below: **every row's
/// uuid is `uuid5(NS_TREE, identityPrefix + external_ref)`, for every row, with no exceptions and
/// no special cases.** That is what makes a source switch reversible (ERRATA E156, where 130,070
/// records kept their identity byte for byte across the DataSF → city change and back), and it is
/// what a second city would break silently if the prefix were not part of the derivation.
///
/// ── What "source-qualified" means, and what it deliberately does not ──────────────────────
/// The qualifier is the **id space** — the numbering scheme the ids come from — and not the
/// inventory. San Francisco's two inventories share a space on purpose: they publish the same
/// `TreeID` numbering, and their uuids colliding is the property that lets a photograph stay
/// attached to its tree when the seed is rebuilt from the other one. A second *city* gets its own
/// space and its own frozen prefix. `everyRowIsInTheSeedsDeclaredIdSpace` is the invariant that
/// fails the moment a build mixes two spaces into one file, which is the shape #107 would take if
/// it went wrong.
@Suite("Inventory contract")
struct InventoryContractTests {

    /// The frozen UUIDv5 namespace `Tools/build_seed.py` derives tree identity in. Restated rather
    /// than read from the seed, so that a receipt claiming a different namespace fails here instead
    /// of being believed.
    static let treeNamespace = UUID(uuidString: "6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")!

    // MARK: - UUIDv5

    /// RFC 4122 §4.3. Twenty lines because the alternative is trusting the generator.
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var hasher = Insecure.SHA1()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize())
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @Test("the UUIDv5 derivation used by this suite is RFC 4122's")
    func derivationIsCorrect() {
        // The control for every assertion below. Without it a broken hasher would make the whole
        // suite agree with itself and prove nothing — the failure ARCHITECTURE §7 records about a
        // grep with no control string.
        //
        // TreeID 276198, `1 TWIN PEAKS BLVD`: the 36-inch Monterey Pine the owner found on the
        // city's own map and could not find in ours, which is why #91 exists. Its uuid is read out
        // of the shipped seed and independently reproduced by `Tools/test_inventory_contract.py`.
        #expect(
            Self.uuidV5(namespace: Self.treeNamespace, name: "276198").uuidString.lowercased()
                == "80a237b1-ba0a-515b-8c96-3da5a790c69d"
        )
        // And a name that differs by one character must not land anywhere near it.
        #expect(
            Self.uuidV5(namespace: Self.treeNamespace, name: "276199").uuidString.lowercased()
                != "80a237b1-ba0a-515b-8c96-3da5a790c69d"
        )
    }

    // MARK: - The seed

    static var seedURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CYPRESS_SEED_PATH"] {
            return URL(fileURLWithPath: path)
        }
        return SeedDatabase.urlInBundle(Bundle(for: BundleToken.self)) ?? SeedDatabase.urlInBundle()
    }

    private final class BundleToken {}

    static func openSeed() async throws -> (CypressStore, [String: String]) {
        let url = try #require(seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let meta = try await store.queue.read { CypressStore.readSeedMeta(connection: $0) }
        return (store, meta)
    }

    @Test("every tree's uuid is derived from its source id under ITS OWN id space's prefix")
    func identityIsAPureFunctionOfTheSourceId() async throws {
        let (store, meta) = try await Self.openSeed()
        let seed = try #require(store.seed)

        // ── Why the prefix is read per row and not once per file ──────────────────────────────
        // It used to be `meta["identity_prefix"] ?? ""` for all 145,837 rows, which was right while
        // the whole file was one id space and became WRONG for one of them the moment a second city
        // landed: San Jose's uuids are derived under `us-ca-sj:` and San Francisco's under the
        // frozen empty string. A single file-wide prefix cannot be right for both, and a test that
        // used one would either fail on every San Jose row or, if somebody "fixed" it by taking the
        // majority, stop checking San Jose at all.
        //
        // So the prefix comes from `id_spaces`, joined on the row's own `id_space`. A seed built
        // before the v14 pass has neither table nor column; it was built in one space with an empty
        // prefix, and that is the honest fallback, stated here rather than assumed elsewhere.
        let rows = try await store.queue.read { connection -> [(String, String, String)] in
            let sql = seed.hasIdSpace
                ? """
                  SELECT t.uuid AS uuid, t.external_ref AS external_ref,
                         s.identity_prefix AS prefix
                    FROM \(SeedDatabase.schemaName).trees t
                    JOIN \(SeedDatabase.schemaName).id_spaces s ON s.id = t.id_space
                   WHERE t.external_ref IS NOT NULL
                  """
                : """
                  SELECT uuid, CAST(external_ref AS TEXT) AS external_ref, '' AS prefix
                    FROM \(SeedDatabase.schemaName).trees
                   WHERE external_ref IS NOT NULL
                  """
            let statement = try connection.prepare(sql)
            defer { statement.finalize() }
            return try statement.fetchAll {
                (try $0.string("uuid"), try $0.string("external_ref"), try $0.string("prefix"))
            }
        }

        #expect(rows.count > 100_000, "only \(rows.count) rows carry an external_ref; the corpus is not the seed")

        // On a seed built before v14 this falls back to the file-wide empty prefix, which is what
        // that file's rows were derived with.
        let fallbackPrefix = meta["identity_prefix"] ?? ""

        var mismatches: [String] = []
        for (uuid, ref, prefix) in rows {
            let effective = seed.hasIdSpace ? prefix : fallbackPrefix
            let expected = Self.uuidV5(namespace: Self.treeNamespace, name: "\(effective)\(ref)")
                .uuidString.lowercased()
            if expected != uuid.lowercased() {
                if mismatches.count < 5 {
                    mismatches.append("ref '\(effective)\(ref)': seed \(uuid), derived \(expected)")
                }
            }
        }
        let detail = mismatches.joined(separator: "\n")
        #expect(
            mismatches.isEmpty,
            "\(mismatches.count)+ rows have a uuid that is not uuid5(NS_TREE, prefix + external_ref). Every public tree URL is derived this way, so this is a citation break, not a cosmetic one:\n\(detail)"
        )
    }

    /// **The collision the id space exists to prevent, asserted against the shipped file.**
    ///
    /// ERRATA E169's worked example is Los Angeles TreeID 276198 against San Francisco TreeID
    /// 276198. San Jose supplies the real one: `FACILITYID` and `TreeID` are both small-integer
    /// asset numberings and they overlap outright. Before the v14 pass this was not a wrong answer,
    /// it was `sqlite3.IntegrityError: UNIQUE constraint failed: trees.external_ref` partway through
    /// the second city.
    ///
    /// Two things are checked and they fail differently: that the same ref really does occur in both
    /// spaces (otherwise the second assertion is vacuous), and that the two rows are different trees
    /// with different uuids.
    @Test("two cities' identical ids are two different trees")
    func twoCitiesShareIdsAndNotIdentities() async throws {
        let (store, _) = try await Self.openSeed()
        let seed = try #require(store.seed)
        guard seed.hasIdSpace else { return }

        let shared = try await store.queue.read { connection -> [(String, String, String)] in
            let statement = try connection.prepare("""
                SELECT t.external_ref AS external_ref, t.id_space AS id_space, t.uuid AS uuid
                  FROM \(SeedDatabase.schemaName).trees t
                 WHERE t.external_ref IN (
                       SELECT external_ref FROM \(SeedDatabase.schemaName).trees
                        GROUP BY external_ref HAVING COUNT(DISTINCT id_space) > 1
                       )
                 ORDER BY CAST(t.external_ref AS INTEGER), t.id_space
                 LIMIT 200
                """)
            defer { statement.finalize() }
            return try statement.fetchAll {
                (try $0.string("external_ref"), try $0.string("id_space"), try $0.string("uuid"))
            }
        }

        // The control. If no ref is shared, everything below passes without measuring anything —
        // which is exactly the inert-test failure this project has had once already.
        #expect(
            shared.count >= 2,
            "no external_ref occurs in two id spaces, so this test proves nothing. Either the seed holds one city, or the id spaces are not what they claim."
        )

        var byRef: [String: [String: String]] = [:]
        for (ref, space, uuid) in shared { byRef[ref, default: [:]][space] = uuid }
        for (ref, bySpace) in byRef where bySpace.count > 1 {
            #expect(
                Set(bySpace.values).count == bySpace.count,
                "external_ref '\(ref)' has the same uuid in \(bySpace.keys.sorted()); two cities' asset ids collided into one identity"
            )
        }
    }

    /// Every row's declared id space is one the file itself declares, and its inventory's space is
    /// the same one. A row whose `id_space` is not in `id_spaces` is a uuid derived with a prefix
    /// nothing in the file records.
    @Test("every row's id space and inventory are declared by the file")
    func theFileDeclaresItsOwnVocabulary() async throws {
        let (store, _) = try await Self.openSeed()
        let seed = try #require(store.seed)
        guard seed.hasIdSpace else { return }

        let orphans = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees t
                 WHERE t.id_space NOT IN (SELECT id FROM \(SeedDatabase.schemaName).id_spaces)
                    OR t.inventory_source NOT IN (SELECT id FROM \(SeedDatabase.schemaName).inventories)
                    OR t.id_space <> (SELECT id_space FROM \(SeedDatabase.schemaName).inventories
                                       WHERE id = t.inventory_source)
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        #expect(orphans == 0, "\(orphans) rows name an id space or inventory the file does not declare, or disagree with their own inventory's space")

        // And every declared inventory really did contribute rows. `inventories` is written for
        // exactly the contributors, so a row for an inventory with no trees means the build wrote a
        // vocabulary it did not use — and `SELECT * FROM inventories` stops describing the file.
        let idle = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare("""
                SELECT i.id AS id FROM \(SeedDatabase.schemaName).inventories i
                 WHERE NOT EXISTS (SELECT 1 FROM \(SeedDatabase.schemaName).trees t
                                    WHERE t.inventory_source = i.id)
                """)
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("id") }
        }
        #expect(idle.isEmpty, "inventories \(idle) are declared but contributed no row")
    }

    @Test("the seed's rows all come from one id space, and it is the one its uuids were derived in")
    func everyRowIsInTheSeedsDeclaredIdSpace() async throws {
        let (store, meta) = try await Self.openSeed()
        // `identity_id_space` is absent on a seed built before the contract. That is a legitimate
        // state — it was built from one inventory family, in one space, with an empty prefix — and
        // it is the same accommodation `InventorySource.init(id:seedMeta:)` already makes for a
        // receipt that predates per-row provenance.
        //
        // The half that does NOT depend on it runs either way, and it is the half with teeth: a row
        // whose inventory the receipt cannot describe draws another inventory's name and snapshot
        // date on screen, which is exactly the defect per-row provenance was added to end.
        let declared = meta["identity_id_space"]

        let inventories = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare(
                "SELECT DISTINCT inventory_source AS s FROM \(SeedDatabase.schemaName).trees ORDER BY s"
            )
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("s") }
        }
        #expect(!inventories.isEmpty, "no row names an inventory")

        for inventory in inventories {
            // Runs against every seed, old receipt or new.
            #expect(
                InventorySource(id: inventory, seedMeta: meta) != nil,
                "no inventory named '\(inventory)' can be described from this seed's receipt"
            )
            // And on a seed the contract built, the receipt's declared space for this inventory must
            // be the one its own rows carry.
            //
            // ── What this used to assert, and why it could not stay ────────────────────────────
            // It compared every inventory's space against the file-wide `identity_id_space`, on the
            // reasoning that "a seed mixing two spaces has uuids derived two ways and half are
            // wrong". That was right while a file could only hold one space and is the exact
            // assumption the v14 pass removed: the shipped seed now holds `sf` and `us-ca-sj`, both
            // derived correctly, each under its own frozen prefix. Keeping the old comparison would
            // have made the correct outcome the red one.
            //
            // The property that actually matters survives and is stronger, because it is per row
            // rather than per file: an inventory's declared space must equal the space its own rows
            // were written with. `identityIsAPureFunctionOfTheSourceId` then re-derives every uuid
            // through that space's prefix, so a mislabelled inventory fails there too, over 198,625
            // rows.
            guard declared != nil else { continue }
            // Folded in from what used to be a test of its own. A receipt that names a contract
            // must name the one in this repo — a seed filtered through some other file is a seed
            // whose rules nobody here can read. It lives inside a live test rather than beside one
            // so that on the shipped seed, which names no contract, the enclosing test still
            // asserts something.
            if let named = meta["ingest_contract"] {
                #expect(
                    named == "Tools/inventory_contract.py",
                    "the seed says it was filtered through '\(named)', which is not the contract in this repo"
                )
            }
            let declaredSpace = meta["inventory_\(inventory)_id_space"]
            let rowSpaces = try await store.queue.read { connection -> [String] in
                guard store.seed?.hasIdSpace == true else { return [] }
                let statement = try connection.prepare("""
                    SELECT DISTINCT id_space AS s FROM \(SeedDatabase.schemaName).trees
                     WHERE inventory_source = ? ORDER BY s
                    """)
                defer { statement.finalize() }
                try statement.bind(inventory, at: 1)
                return try statement.fetchAll { try $0.string("s") }
            }
            if rowSpaces.isEmpty {
                // A seed built before v14: no per-row space to compare against, so the receipt's
                // own claim is all there is and the file-wide one is right for it.
                #expect(
                    declaredSpace == meta["identity_id_space"],
                    "rows say inventory_source='\(inventory)', whose id space is \(declaredSpace ?? "undeclared") but whose uuids were derived in '\(meta["identity_id_space"] ?? "")'"
                )
            } else {
                #expect(
                    rowSpaces == [declaredSpace ?? ""],
                    "inventory '\(inventory)' is declared in id space \(declaredSpace ?? "undeclared") but its rows carry \(rowSpaces)"
                )
            }
        }
    }

    // ── A deleted test, and why ───────────────────────────────────────────────────────────────
    // There was a `theSanFranciscoPrefixIsFrozenEmpty` here, asserting
    // `meta["identity_prefix"] == ""`. It was removed rather than repaired.
    //
    // On the shipped seed that key is absent — the file predates the contract — so the test
    // returned without asserting, and an inert test is one that cannot fail. This project has had
    // one positively ratify a defect for weeks. The obvious repair, asserting against a
    // hand-built receipt dictionary, is worse than useless: it would check that a dictionary
    // holds the value the test just put in it.
    //
    // The property is not lost, it is asserted in three live places already.
    // `identityIsAPureFunctionOfTheSourceId` re-derives all 145,837 uuids through
    // `meta["identity_prefix"] ?? ""` and goes red for every row if that prefix is wrong —
    // demonstrated, by substituting `"us-ca-sf:"` and watching it fail. And
    // `Tools/test_inventory_contract.py` pins `ID_SPACES["sf"].identity_prefix == ""` directly
    // and refuses an empty prefix for any *other* space. A fourth statement of it that cannot
    // fail was cost without cover.

    // MARK: - A missing optional field does not become a lie

    @Test("no optional column holds an empty string where the source said nothing")
    func absentIsNullAndNeverEmptyText() async throws {
        let (store, _) = try await Self.openSeed()
        // The contract refuses a blank string in an optional field, because '' and NULL are the
        // same fact to the source and two different facts to every reader downstream: the tree page
        // draws a card for a value it has and nothing for a value it does not.
        let columns = [
            "address", "site_type", "legal_status", "caretaker", "care_assistant",
            "plant_type", "plot_size", "permit_notes", "planted_on"
        ]
        for column in columns {
            let blanks = try await store.queue.read { connection -> Int in
                let statement = try connection.prepare("""
                    SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                     WHERE \(column) IS NOT NULL AND TRIM(\(column)) = ''
                    """)
                defer { statement.finalize() }
                return try statement.fetchOne { try $0.int("n") } ?? -1
            }
            #expect(blanks == 0, "\(blanks) rows carry a blank \(column); absent must be NULL")
        }
    }

    @Test("the source's DBH=0 became no measurement, not a zero-width trunk")
    func theDBHSentinelDidNotLeak() async throws {
        let (store, meta) = try await Self.openSeed()

        // ── What this is measuring, and the mistake it replaces ─────────────────────────────
        // Both SF inventories write `DBH = 0` for "not recorded". The contract refuses a
        // non-positive `dbh_in` and `inventory_adapters.parse_dbh_inches` resolves the sentinel to
        // None first, so those rows must reach the seed with NO bucket at all.
        //
        // The obvious check — "no row sits in the [0,5) cm bucket" — is WRONG, and it failed here
        // before this comment existed. A 1-inch trunk is 2.54 cm and lands in [0,5) legitimately;
        // 5,673 city rows do. The bucket a leaked zero would land in is already occupied by real
        // measurements, so the leak is not visible from that side.
        //
        // It is visible from the other side. The city layer's own field distribution
        // (docs/investigations/city-tree-source.md §2) is 2,647 rows with `DBH = 0` and 6,372 with
        // `DBH` null. If the sentinel leaked, the zeros would acquire a bucket and only the 6,372
        // nulls would lack one. So the count of city rows with NO bucket is the discriminator, and
        // it has to be the sum.
        // `sf_city` since the v14 pass renamed it; `city` on any seed built before.
        let source = meta["trees_source"] ?? "sf_datasf"

        let noBucket = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE inventory_source = ? AND dbh_city_cm_min IS NULL
                """)
            defer { statement.finalize() }
            try statement.bind(source, at: 1)
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }

        if source == "sf_city" || source == "city" {
            #expect(
                noBucket == 9_019,
                "\(noBucket) city rows carry no DBH bucket, expected 2,647 zeros + 6,372 nulls = 9,019. Below 9,019 means the 'not recorded' zero was read as a measurement."
            )
        } else {
            // The export's own zeros and blanks, measured on the rebuilt corpus.
            #expect(
                noBucket == 44_584,
                "\(noBucket) export rows carry no DBH bucket, expected 44,584"
            )
        }

        // The ladder itself: every rung is a half-open 5 cm interval on a multiple of 5. A bucket
        // that is not is a corrupted ladder, which no count above would notice.
        let malformed = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE dbh_city_cm_min IS NOT NULL
                   AND (dbh_city_cm_max <> dbh_city_cm_min + 5
                        OR dbh_city_cm_min < 0
                        OR dbh_city_cm_min % 5 <> 0)
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        #expect(malformed == 0, "\(malformed) trees carry a DBH bucket that is not a 5 cm rung")
    }

    // MARK: - What the contract made countable (task #94)

    @Test("the receipt accounts for every vacant site by who said it was one")
    func vacancyIsAccountedForByWhoSaidSo() async throws {
        let (store, meta) = try await Self.openSeed()

        let vacant = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees WHERE status = 'vacant_site'
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }

        // Runs against every seed: the rows and the receipt's own total must agree. This is the
        // half that catches an ingest whose accounting has drifted from what it wrote.
        #expect(
            meta["vacant_site_rows"] == String(vacant),
            "\(vacant) rows are vacant sites but the receipt says \(meta["vacant_site_rows"] ?? "nothing")"
        )

        // The split by who said so needs a receipt the contract wrote; absent on an older seed,
        // see `everyRowIsInTheSeedsDeclaredIdSpace`.
        guard let statedText = meta["planting_sites_stated_by_source"],
              let inferredText = meta["planting_sites_inferred_from_absent_species"] else { return }
        let stated = try #require(Int(statedText))
        let inferred = try #require(Int(inferredText))

        // The arithmetic has to close, or the split is decoration rather than an account.
        #expect(
            stated + inferred == vacant,
            "\(vacant) vacant sites but the receipt splits them \(stated) stated + \(inferred) inferred"
        )

        // And the inferred count is a defect with a size. It is not asserted to be zero — fixing it
        // is #94 and changes the corpus — but it is asserted to be *known*, so that a rebuild which
        // makes it worse is visible in the diff of this file rather than in a screenshot months
        // later. 1,326 of the export's `::` rows carry `qLegalStatus = DPW Maintained`: the city
        // says it maintains a street tree there and our map draws a hole in the pavement.
        #expect(
            inferred > 0,
            "no vacancy is inferred any more. If #94 landed, update this number and the errata; if the classification quietly stopped working, that is the bug."
        )
        #expect(
            inferred < vacant / 2,
            "\(inferred) of \(vacant) vacant sites are our inference rather than the source's statement; that is past the point where the vacant-site feature describes the city"
        )
    }

    @Test("records the source calls not-a-tree are counted, not hidden")
    func shrubsAreCounted() async throws {
        let (store, meta) = try await Self.openSeed()
        // `trees.status` has no value meaning "the source says this is a shrub", so
        // `build_seed.STATUS_FOR_KIND` maps them to `alive` and the count is written down instead.
        // These are exactly the rows with no species and a living status, and that population is
        // readable from any seed — it does not need a receipt the contract wrote.
        let aliveWithNoSpecies = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE species_current IS NULL AND status = 'alive'
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        // ── The identity this used to assert, and why it was San Francisco's ──────────────────
        // It was `non_taxon_rows == aliveWithNoSpecies`, on the reasoning that the only way to be
        // alive with no species is to be a record whose source named no taxon. That held because
        // neither of San Francisco's inventories can say "a tree is here and I do not know which".
        // **San Jose can, and does**: `NAMESCIENTIFIC = 'Unknown'` on a row the vacancy flag calls
        // occupied is a tree of unknown species, which is R18's own answer — treating it as a
        // placeholder would delete those trees from the map, and minting a species from it would put
        // `Unknown` in the field guide.
        //
        // So the population is now a sum of two different facts and is asserted as one. Equality
        // still holds inside `sf`, where it is still true.
        // `treesOfUnknownSpecies` is pinned as a literal per corpus, so this is not the tautology it
        // would be if the test derived the remainder and then asserted it equals the remainder. A
        // build that started minting a species called `Unknown` (#103's mechanism), or that started
        // dropping those 705 trees off the map, moves one side and not the other.
        let corpus = try await SeedCorpus.current(store)
        let notATreeCount = Int(meta["non_taxon_rows"] ?? "") ?? -1
        let unknownSpecies = corpus.treesOfUnknownSpecies
        #expect(
            notATreeCount + unknownSpecies == aliveWithNoSpecies,
            "\(aliveWithNoSpecies) rows are alive with no species; the receipt counts \(notATreeCount) non-taxon rows and \(unknownSpecies) are trees the source called a tree of unknown species, which do not add up"
        )
        #expect(
            aliveWithNoSpecies > 0,
            "no row is alive with no species; either #94 landed — update this and the errata — or the classifier broke"
        )

        guard let text = meta["records_not_a_tree"], let notATree = Int(text) else { return }
        #expect(
            notATree + unknownSpecies == aliveWithNoSpecies,
            "the receipt counts \(notATree) not-a-tree records and \(unknownSpecies) trees of unknown species, but \(aliveWithNoSpecies) rows are alive with no species; one of the three has drifted"
        )
    }

}
