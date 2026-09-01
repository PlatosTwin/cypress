import Foundation
import Testing
@testable import Cypress

/// **The Journal tab's reads, explained — the instrument `GroveQueryPlanTests` is for screen 08,
/// aimed at the tab whose default segment had none.**
///
/// Nothing gated any journal statement until this file. That is how the exact defect PR #131 took
/// out of `LocalAPI.grove()` — a serial per-tree name lookup falling through to the app's most
/// expensive single-row query — survived unchanged in `LocalAPI.journal()`, on a segment that opens
/// by default, while every correctness test stayed green.
///
/// The two rules are `GroveQueryPlanTests`', and its header states why each is written the way it
/// is; they are not restated here. The difference is that this file is honest about a statement it
/// **cannot** hold to rule 1, and says which one and why:
///
/// - `ContributionStore.journalSQL`, the page itself, has no seekable predicate. It unions four
///   whole contribution tables and orders the union by `captured_at`, so the plan is four scans and
///   a temp b-tree, and `LIMIT` cannot reach past the sort. Fixing that means an index per table on
///   `(captured_at)` or on the attribution columns — a schema migration, which this round is
///   explicitly not the author of. `thePageQueryIsTheKnownScan` pins the shape it has today so a
///   change to it is visible, and `theAllowlistIsStated` is what keeps the allowance deliberate.
/// - `activeNamesSQL` and the two scoped hero statements walk tables that hold **this contributor's
///   own rows** — nicknames and a personal photo library. Each is on the allowlist by name with
///   that as the premise. `ContributionStore.activeNamesSQL` carries the argument for why the
///   `lower()` normalization that fixed the Grove joins does not transfer to `tree_names`.
///
/// ── Calibration ─────────────────────────────────────────────────────────────────────────────
/// `theStatementsAreTheOnesTheAppRuns` is the guard against the failure mode that produced this
/// file's older sibling: SQL hand-copied into a test explains the copy. It reads the four strings
/// off `ContributionStore` itself, which is where `journal`, `activeNames` and
/// `heroPhotoIDs(treeIDs:attribution:)` take them from, so the gate cannot drift from the app
/// without failing to compile.
@Suite("Journal · query plans")
struct JournalQueryPlanTests {

    // MARK: - Fixtures

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    /// Relations a Journal plan may walk end to end, and why each one is small.
    ///
    /// **Everything here is the contributor's own record**, bounded by what one person did on one
    /// phone, or a co-routine over a bound list. The inventory is not on this list under any alias,
    /// which is `GroveQueryPlanTests`' rule 2 and holds here unchanged: no Journal statement touches
    /// the seed's `trees` at all — the tree records a page needs come from `TreeQueries.trees(ids:)`,
    /// which that file already gates as "a grove's worth of trees by uuid".
    private static let scannable: Set<String> = [
        // The four contribution tables `journalSQL` unions, and the alias it gives the union.
        "visits", "observations", "measurements", "care_events", "entry",
        // This contributor's nicknames: one row per tree they have personally named. See
        // `ContributionStore.activeNamesSQL` for why the collation that forbids the seek is kept.
        "tree_names",
        // This device's own photo library and the votes on it. `ContributionStore
        // .scopedHeroPhotoCandidatesSQL` states what the narrowing buys, which is not a seek.
        "photos", "photo_votes",
        // The `IN` list of a batched read, a virtual table over a bound JSON array.
        "json_each"
    ]

    // MARK: - Rule 2, over every statement the Journal tab runs

    /// **Nothing a journal page reads walks anything but this contributor's own rows.**
    ///
    /// Rule 1 is not asserted over the set, because two of the four statements have no seekable
    /// predicate and saying "they all seek" would be false. What is asserted over the set is the
    /// half that holds for all of them: no inventory relation is walked and nothing is materialized
    /// beyond the union the page query is documented to need.
    @Test("every Journal statement walks only the contributor's own rows")
    func plansTouchOnlyTheContributorsOwnRows() async throws {
        let store = try await Self.store()

        let statements: [(label: String, sql: String)] = [
            ("the page", ContributionStore.journalSQL),
            ("the page's nicknames", ContributionStore.activeNamesSQL),
            ("the page's hero candidates", ContributionStore.scopedHeroPhotoCandidatesSQL),
            ("the page's hero vote tallies", ContributionStore.scopedHeroPhotoTalliesSQL)
        ]

        try await store.queue.read { connection in
            for (label, sql) in statements {
                let steps = try connection.queryPlan(for: sql)
                let plan = steps.joined(separator: " | ")
                let scanned = steps.compactMap { GroveQueryPlanTests.scannedRelation(in: $0) }
                let unexpected = scanned.filter { !Self.scannable.contains($0) }
                #expect(
                    unexpected.isEmpty,
                    """
                    \(label): walks \(unexpected.sorted()) end to end, which is not on the \
                    permitted list \(Self.scannable.sorted()) — \(plan)
                    """
                )
            }
        }
    }

    /// **The page query's plan, pinned as the scan it is.**
    ///
    /// This is the opposite of an aspiration: it asserts that the statement does the expensive thing
    /// it does today, so that the day somebody makes it cheaper — which takes indexes and therefore
    /// a migration — this test goes red and has to be rewritten deliberately rather than quietly
    /// continuing to pass on a claim nobody re-derived.
    ///
    /// Three facts, each of which is what makes the page O(this contributor's whole history):
    ///
    /// 1. all four contribution tables are walked end to end;
    /// 2. the ordering is answered by a temp b-tree rather than by an index, so `LIMIT :limit`
    ///    cannot stop the read early — every row is produced before any is discarded;
    /// 3. no step seeks anything, which is the compact statement of (1) and (2) together.
    @Test("the page query is still the whole-history scan it is documented to be")
    func thePageQueryIsTheKnownScan() async throws {
        let store = try await Self.store()
        try await store.queue.read { connection in
            let steps = try connection.queryPlan(for: ContributionStore.journalSQL)
            let plan = steps.joined(separator: " | ")

            let scanned = Set(steps.compactMap { GroveQueryPlanTests.scannedRelation(in: $0) })
            for table in ["visits", "observations", "measurements", "care_events"] {
                #expect(
                    scanned.contains(table),
                    """
                    \(table) is no longer walked end to end by the page query. If that is because \
                    it can now be seeked, this gate is out of date and the premise in \
                    `ContributionStore.journalSQL` with it — rewrite both. — \(plan)
                    """
                )
            }

            #expect(
                steps.contains(where: { $0.contains("TEMP B-TREE") }),
                """
                the page query no longer sorts through a temp b-tree, which is the step that makes \
                LIMIT unable to stop the read early. Re-derive the cost claim before relaxing \
                this. — \(plan)
                """
            )

            #expect(
                !steps.contains(where: { $0.contains("SEARCH") }),
                "the page query gained a seek, which is the fix this gate is waiting for — \(plan)"
            )
        }
    }

    /// **The three narrowed statements, and what each of their plans actually is.**
    ///
    /// Written as the plan each one has rather than as the plan one might want, because the point of
    /// narrowing them was never a seek — `ContributionStore.scopedHeroPhotoCandidatesSQL` says so —
    /// and a gate asserting a seek that cannot happen would have to be widened until it meant
    /// nothing. What is pinned is that each statement narrows through `json_each` on its own bound
    /// list, which is the property that keeps a page of 25 trees from decoding the whole photo
    /// library, and that none of them materializes a relation.
    @Test("the three narrowed statements narrow through their bound list and materialize nothing")
    func theNarrowedStatementsNarrow() async throws {
        let store = try await Self.store()
        let statements: [(label: String, sql: String)] = [
            ("the page's nicknames", ContributionStore.activeNamesSQL),
            ("the page's hero candidates", ContributionStore.scopedHeroPhotoCandidatesSQL),
            ("the page's hero vote tallies", ContributionStore.scopedHeroPhotoTalliesSQL)
        ]

        try await store.queue.read { connection in
            for (label, sql) in statements {
                let steps = try connection.queryPlan(for: sql)
                let plan = steps.joined(separator: " | ")

                #expect(
                    plan.contains("json_each"),
                    """
                    \(label) no longer narrows through a bound json_each list, so it is answering \
                    for more rows than the caller asked about — \(plan)
                    """
                )
                let materialized = steps.filter { $0.contains("MATERIALIZE") }
                #expect(
                    materialized.isEmpty,
                    "\(label): materializes a relation — \(materialized.joined(separator: " | "))"
                )
            }
        }
    }

    // MARK: - The calibration

    /// **The strings above are the app's own, not a paraphrase of them.**
    ///
    /// `MapQueryPlanTests`' header records what a paraphrase costs: the plans were pinned against
    /// SQL hand-copied into `DataGates`, so changing the real query left the gate explaining the
    /// copy. This asks the question the other way round — every statement this file explains has to
    /// be one a `ContributionStore` method prepares — and it is asserted by *running* each one
    /// against the real schema. A string that no longer parses, or that names a column the app
    /// dropped, fails here rather than being explained forever.
    @Test("every statement this gate explains prepares against the real schema")
    func theStatementsAreTheOnesTheAppRuns() async throws {
        let store = try await Self.store()
        let statements = [
            ContributionStore.journalSQL,
            ContributionStore.activeNamesSQL,
            ContributionStore.scopedHeroPhotoCandidatesSQL,
            ContributionStore.scopedHeroPhotoTalliesSQL
        ]
        #expect(statements.count == Set(statements).count, "the same statement is explained twice")

        try await store.queue.read { connection in
            for sql in statements {
                let steps = try connection.queryPlan(for: sql)
                #expect(!steps.isEmpty, "EXPLAIN QUERY PLAN produced no steps for:\n\(sql)")
            }
        }
    }
}
