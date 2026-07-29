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

    @Test("every tree's uuid is derived from its source id under the seed's declared prefix")
    func identityIsAPureFunctionOfTheSourceId() async throws {
        let (store, meta) = try await Self.openSeed()
        // A seed built before the contract existed carries no prefix. It was built in one id space
        // with an empty one, so that is the honest fallback — and it is stated here rather than
        // silently assumed anywhere else.
        let prefix = meta["identity_prefix"] ?? ""

        let rows = try await store.queue.read { connection -> [(String, Int)] in
            let statement = try connection.prepare("""
                SELECT uuid, external_ref FROM \(SeedDatabase.schemaName).trees
                 WHERE external_ref IS NOT NULL
                """)
            defer { statement.finalize() }
            return try statement.fetchAll { (try $0.string("uuid"), try $0.int("external_ref")) }
        }

        #expect(rows.count > 100_000, "only \(rows.count) rows carry an external_ref; the corpus is not the seed")

        var mismatches: [String] = []
        for (uuid, ref) in rows {
            let expected = Self.uuidV5(namespace: Self.treeNamespace, name: "\(prefix)\(ref)")
                .uuidString.lowercased()
            if expected != uuid.lowercased() {
                if mismatches.count < 5 { mismatches.append("ref \(ref): seed \(uuid), derived \(expected)") }
            }
        }
        let detail = mismatches.joined(separator: "\n")
        #expect(
            mismatches.isEmpty,
            "\(mismatches.count)+ rows have a uuid that is not uuid5(NS_TREE, prefix + external_ref). Every public tree URL is derived this way, so this is a citation break, not a cosmetic one:\n\(detail)"
        )
    }

    @Test("the seed's rows all come from one id space, and it is the one its uuids were derived in")
    func everyRowIsInTheSeedsDeclaredIdSpace() async throws {
        let (store, meta) = try await Self.openSeed()
        // A seed built before the contract existed declares no id space. That is a legitimate
        // state and not a failure — it was built from one, in one, with an empty prefix — and it
        // is the same accommodation `InventorySource.init(id:seedMeta:)` already makes for a
        // receipt that predates per-row provenance. The check below is what a *rebuilt* seed owes.
        guard let declared = meta["identity_id_space"] else { return }

        let inventories = try await store.queue.read { connection -> [String] in
            let statement = try connection.prepare(
                "SELECT DISTINCT inventory_source AS s FROM \(SeedDatabase.schemaName).trees ORDER BY s"
            )
            defer { statement.finalize() }
            return try statement.fetchAll { try $0.string("s") }
        }
        #expect(!inventories.isEmpty, "no row names an inventory")

        for inventory in inventories {
            // Two claims, and both matter. The row's inventory must be one the receipt can
            // describe — otherwise the provenance line on screen draws another inventory's name and
            // snapshot date, which is the defect per-row provenance was added to end. And its id
            // space must be the one the file's uuids were derived in — a seed mixing two spaces has
            // uuids derived two ways, and half of them are wrong.
            let space = meta["inventory_\(inventory)_id_space"]
            #expect(
                space == declared,
                "rows say inventory_source='\(inventory)', whose id space is \(space ?? "undeclared") but whose uuids were derived in '\(declared)'"
            )
            #expect(
                InventorySource(id: inventory, seedMeta: meta) != nil,
                "no inventory named '\(inventory)' can be described from this seed's receipt"
            )
        }
    }

    @Test("San Francisco's identity prefix is empty, and that is frozen")
    func theSanFranciscoPrefixIsFrozenEmpty() async throws {
        let (_, meta) = try await Self.openSeed()
        guard meta["identity_id_space"] == "sf" else { return }
        #expect(
            meta["identity_prefix"] == "",
            "the 'sf' identity prefix is no longer empty. Every one of the seed's uuids moves, and every photograph, favourite and citation that referenced one is orphaned."
        )
    }

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
        let source = meta["trees_source"] ?? "datasf"

        let noBucket = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE inventory_source = ? AND dbh_city_cm_min IS NULL
                """)
            defer { statement.finalize() }
            try statement.bind(source, at: 1)
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }

        if source == "city" {
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
        // Absent on a seed built before the contract; see `everyRowIsInTheSeedsDeclaredIdSpace`.
        guard let statedText = meta["planting_sites_stated_by_source"],
              let inferredText = meta["planting_sites_inferred_from_absent_species"] else { return }
        let stated = try #require(Int(statedText))
        let inferred = try #require(Int(inferredText))

        let vacant = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees WHERE status = 'vacant_site'
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }

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
        guard let text = meta["records_not_a_tree"], let notATree = Int(text) else { return }
        // `trees.status` has no value meaning "the source says this is a shrub", so
        // `build_seed.STATUS_FOR_KIND` maps them to `alive` and the count is written down instead.
        // These are exactly the rows with no species and a living status.
        let aliveWithNoSpecies = try await store.queue.read { connection -> Int in
            let statement = try connection.prepare("""
                SELECT COUNT(*) AS n FROM \(SeedDatabase.schemaName).trees
                 WHERE species_current IS NULL AND status = 'alive'
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.int("n") } ?? -1
        }
        #expect(
            notATree == aliveWithNoSpecies,
            "the receipt counts \(notATree) not-a-tree records but \(aliveWithNoSpecies) rows are alive with no species; one of the two has drifted"
        )
        #expect(notATree > 0, "no record is classified not-a-tree; either #94 landed or the classifier broke")
    }

    @Test("a receipt that names a contract names this one")
    func theReceiptNamesItsContract() async throws {
        let (_, meta) = try await Self.openSeed()
        guard let named = meta["ingest_contract"] else { return }
        #expect(
            named == "Tools/inventory_contract.py",
            "the seed says it was filtered through '\(named)', which is not the contract in this repo"
        )
    }
}
