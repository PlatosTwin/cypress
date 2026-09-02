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
/// - `ContributionStore.journalSQL`, the page itself, held that place until `AppSchema` v19. It had
///   no row-selecting predicate an index could answer: four whole contribution tables unioned and
///   the union ordered, so the plan was four scans, a scan of the union, and a temp b-tree that
///   `LIMIT` could not reach past. **That is fixed and this file is the record of it.** v19's
///   `idx_<table>_captured` family plus the per-arm `ORDER BY`/`LIMIT` push-down make each arm an
///   early-terminating seek, and `thePageQueryStops` asserts the four seeks by index name, the
///   absence of any table scan, and the one bounded merge that is left. The paragraph this replaces
///   said the fix "is a schema migration, which this round is explicitly not the author of" — the
///   next round was.
/// - `activeNamesSQL` walks `tree_names`, which holds **this contributor's own rows** — one per
///   tree they have personally named. It is on the allowlist by name with that as the premise.
///   `ContributionStore.activeNamesSQL` carries the argument for why the `lower()` normalization
///   that fixed the Grove joins does not transfer to `tree_names`, and `AppSchema` v19 adds the
///   second reason it was left alone when its two neighbours were fixed: the only index on
///   `tree_uuid` there is `idx_tree_names_one_active`, a partial UNIQUE index that *is* D15 —
///   recollating it would change which pairs of rows the schema calls a conflict, which is a
///   decision about the invariant and not about an access path.
///
/// **The two scoped hero statements used to be on that list beside it and are not any more.**
/// `AppSchema` v19 recollated `idx_photos_tree` and added `idx_photo_votes_photo`, so both now
/// seek: `SEARCH photos USING INDEX idx_photos_tree (tree_uuid=?)` and `SEARCH photo_votes USING
/// INDEX idx_photo_votes_photo (photo_id=?)`. `theNarrowedStatementsNarrow` asserts the seek, and
/// `photos`/`photo_votes` were taken off `scannable` in the same edit, so a regression to a walk
/// fails twice rather than being quietly permitted by a list that outlived its reason.
///
/// ── What binds these strings to the app, and what does not ──────────────────────────────────
/// **This header used to claim the coupling was the compiler's, and that was false.** It said the
/// gate "cannot drift from the app without failing to compile", on the grounds that it reads the
/// strings off `ContributionStore` rather than copying them. PR #143's review disproved it in one
/// edit: make `ContributionStore.journal` run `Self.journalSQL + " -- drift"` and the app executes
/// a statement this file has never seen, while the whole suite stays green. Referencing a property
/// from a test makes the *property* exist; it does not make the property be what runs. That is
/// exactly the `MapQueryPlanTests` failure mode this file cites as the thing it avoids, reached
/// from the other side.
///
/// The coupling is real now and it lives next door. **`JournalStatementCensusTests`** records what
/// `LocalAPI.journal()` prepares, as it prepares it, and asserts the set is precisely the texts
/// these properties hold — so the reviewer's drift edit is red there. This file explains plans;
/// that file is what makes "these are the statements the app runs" a measurement rather than a
/// sentence.
///
/// `theStatementsAreTheOnesTheAppRuns` below stays, narrowed to what it can honestly do on its
/// own: prove each string still parses and plans against the real schema.
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
        // This contributor's nicknames: one row per tree they have personally named. See
        // `ContributionStore.activeNamesSQL` for why the collation that forbids the seek is kept,
        // and the file header for why `AppSchema` v19 fixed its two neighbours and not this one.
        "tree_names",
        // The `IN` list of a batched read, a virtual table over a bound JSON array.
        "json_each"
        //
        // **Four names came off this list in v19 and one alias with them.** `visits`,
        // `observations`, `measurements` and `care_events` were here because the page query walked
        // all four, and `entry` was the alias it gave their union; `photos` and `photo_votes` were
        // here because the two scoped hero statements walked them. Every one of those now seeks.
        // Leaving a relation on a list of things that *may* be walked, after it stopped needing to
        // be, is how a gate goes quietly vacuous — so the page query's four arms are asserted as
        // seeks by `thePageQueryStops` instead, and the derived tables it produces are permitted by
        // shape through `isPermittedScan`.
    ]

    /// Whether a `SCAN` of this relation is allowed in a Journal plan.
    ///
    /// Two forms: a table on `scannable` by name, or **a derived table, matched by shape**. The
    /// restructured page query is a union of four `(SELECT … ORDER BY … LIMIT …)` subqueries, and
    /// SQLite reports scanning each as `SCAN (subquery-2)`, `SCAN (subquery-5)` and so on. Those
    /// scans are the co-routine drain of an already-bounded arm — at most `:limit` rows apiece —
    /// and not a table walk at all.
    ///
    /// **Matched by shape and not by number, deliberately.** The numbers are SQLite's internal
    /// select ids and they shift whenever an arm is edited: adding a fifth contribution kind, or
    /// even reordering the four, renumbers every one of them. A gate pinned to `(subquery-12)`
    /// would fail on a change that altered nothing about its cost, which trains the reader to
    /// re-baseline it, which is how a gate stops being read.
    private static func isPermittedScan(_ relation: String) -> Bool {
        if scannable.contains(relation) { return true }
        return relation.hasPrefix("(subquery-") && relation.hasSuffix(")")
            && relation.dropFirst("(subquery-".count).dropLast().allSatisfy(\.isNumber)
    }

    // MARK: - Rule 2, over every statement the Journal tab runs

    /// **Nothing a journal page reads walks anything but this contributor's own rows.**
    ///
    /// Rule 1 is not asserted over the whole set here, because `activeNamesSQL` has no seekable
    /// predicate and saying "they all seek" would be false; the three that do seek are held to it
    /// by `thePageQueryStops` and `theNarrowedStatementsNarrow`. What is asserted over the set is
    /// the half that holds for all four: no inventory relation is walked, and nothing outside the
    /// permitted forms is.
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
                let unexpected = scanned.filter { !Self.isPermittedScan($0) }
                #expect(
                    unexpected.isEmpty,
                    """
                    \(label): walks \(unexpected.sorted()) end to end, which is neither on the \
                    permitted list \(Self.scannable.sorted()) nor a bounded derived table — \(plan)
                    """
                )
            }
        }
    }

    /// **The page query stops early, and this is the four facts that say so.**
    ///
    /// This test replaces `thePageQueryIsTheKnownScan`, which pinned the opposite: it asserted that
    /// the page walked all four contribution tables and sorted the result, so that the day somebody
    /// made it cheaper the claim would have to be rewritten deliberately rather than left to rot.
    /// That is what happened. `AppSchema` v19 added the ordering indexes and
    /// `ContributionStore.journalSQL` pushed `ORDER BY`/`LIMIT` into each arm; the old test went red
    /// on every one of its assertions, which is the whole reason it was written that way round.
    ///
    /// Four facts, each part of why a page now costs the page and not the history:
    ///
    /// 1. **each of the four arms seeks its own `idx_<table>_captured`.** Asserted by index name
    ///    per table, and as a `SEARCH` — `GroveQueryPlanTests`' rule 1 exists because
    ///    `SCAN t USING INDEX x` contains the index's name while walking the whole thing;
    /// 2. **no contribution table is walked.** The only scans left are the co-routine drains of the
    ///    four bounded arms and of their union, permitted by shape through `isPermittedScan`;
    /// 3. **one temp b-tree, and it is bounded.** The outer `ORDER BY` merges the arms, and each
    ///    arm has already been cut to `:limit`, so the sort is over at most `4 × :limit` rows —
    ///    100 at `JournalLimits.pageSize`. That is why this one is allowed where the old one was
    ///    the defect: the old sort was over every row the contributor had ever written. **The
    ///    count is asserted**, so a second sort appearing — a per-arm `USE TEMP B-TREE FOR LAST
    ///    TERM OF ORDER BY`, which is exactly what a `(captured_at)` index without `id` produces —
    ///    fails here rather than passing as "still one b-tree, more or less";
    /// 4. **no `MULTI-INDEX OR`.** Same rule and same reason as
    ///    `GroveQueryPlanTests.noPlanUsesMultiIndexOr`: an owner index on `device_id`/`user_id`
    ///    needs no query change to be adopted, and it costs the arms their ordering — the
    ///    restructured query measured 8.46 ms with both index sets present against 0.17 with only
    ///    the ordering set. It is the one regression that would look like an optimization in the
    ///    diff.
    @Test("the page query seeks each arm, walks no table, and sorts a bounded merge")
    func thePageQueryStops() async throws {
        let store = try await Self.store()
        try await store.queue.read { connection in
            let steps = try connection.queryPlan(for: ContributionStore.journalSQL)
            let plan = steps.joined(separator: " | ")

            // 1. One seek per arm, by index name.
            for table in ["visits", "observations", "measurements", "care_events"] {
                let index = "idx_\(table)_captured"
                let seeks = steps.filter { $0.contains("SEARCH") && $0.contains(index) }
                #expect(
                    !seeks.isEmpty,
                    """
                    the \(table) arm does not SEARCH \(index). Without that seek the arm cannot \
                    stop after :limit rows and the page is back to costing the contributor's whole \
                    history — which is what this query looked like before `AppSchema` v19 — \(plan)
                    """
                )
            }

            // 2. No contribution table is walked end to end.
            let scanned = steps.compactMap { GroveQueryPlanTests.scannedRelation(in: $0) }
            let walked = scanned.filter { !Self.isPermittedScan($0) }
            #expect(
                walked.isEmpty,
                """
                the page query walks \(walked.sorted()) end to end. The arms are supposed to be \
                bounded seeks and their drains the only scans — \(plan)
                """
            )

            // 3. Exactly one temp b-tree, and the reason it is allowed.
            let sorts = steps.filter { $0.contains("TEMP B-TREE") }
            #expect(
                sorts.count == 1,
                """
                the page query has \(sorts.count) temp b-trees, not 1: \
                \(sorts.joined(separator: " | ")). Exactly one is correct and bounded — the outer \
                merge of four arms already cut to :limit, so at most 4 × :limit rows. A second one \
                is a per-arm sort, which means an arm's index stopped answering its ORDER BY (drop \
                `id` from `idx_<table>_captured` and this is what you get). Zero would be a \
                different query — \(plan)
                """
            )

            // 4. No MULTI-INDEX OR.
            let multiIndex = steps.filter { $0.contains("MULTI-INDEX OR") }
            #expect(
                multiIndex.isEmpty,
                """
                the page query answers its owner predicate through MULTI-INDEX OR — \
                \(multiIndex.joined(separator: " | ")). That is what an index on device_id or \
                user_id buys, with no query change: the arms lose their ordering and the page goes \
                from 0.17 ms back to 8.46. See `AppSchema` v19's doc comment — \(plan)
                """
            )

            // The tombstone lookup is still one indexed probe per candidate row, not a scan.
            #expect(
                steps.contains(where: {
                    $0.contains("SEARCH") && $0.contains("anonymized_contributions")
                }),
                """
                the tombstone check no longer seeks its index. It runs once per candidate row, so \
                losing that index turns each bounded arm into a scan per row — \(plan)
                """
            )
        }
    }

    /// **The three narrowed statements, and what each of their plans actually is.**
    ///
    /// Written as the plan each one has rather than as the plan one might want. That produced the
    /// right answer twice over: the first draft asserted a walk for all three because none of them
    /// could seek, and `AppSchema` v19 then made two of them seek — so the same rule, unchanged,
    /// caught the improvement and had to be rewritten to say what is true now. Three things are
    /// pinned per statement:
    ///
    /// - each narrows through `json_each` over its own bound list, which is the property that keeps
    ///   a page of 25 trees from decoding this device's whole photo library, and nothing is
    ///   materialized;
    /// - each **reaches its own table the way named beside it** — a `SEARCH` on the index named, or
    ///   a walk. Both directions fail: a seek that becomes a walk is a lost index, and a walk that
    ///   becomes a seek means a doc comment somewhere says something that stopped being true.
    ///
    /// `tree_names` is the one still walked, and its two reasons are on `scannable` and in the file
    /// header. `photos` and `photo_votes` are the two v19 fixed, and their `SEARCH`es are asserted
    /// by index name rather than by the word — `GroveQueryPlanTests`' rule 1 exists because
    /// `SCAN t USING INDEX …` contains the index's name and walks the whole thing.
    @Test("the three narrowed statements narrow through their bound list and reach their own table")
    func theNarrowedStatementsNarrow() async throws {
        let store = try await Self.store()

        /// How a statement is expected to reach its table: `SEARCH`ing the named index, or walking.
        enum Access {
            case seeks(index: String)
            case walks
        }
        let statements: [(label: String, sql: String, table: String, access: Access)] = [
            ("the page's nicknames", ContributionStore.activeNamesSQL, "tree_names", .walks),
            (
                "the page's hero candidates",
                ContributionStore.scopedHeroPhotoCandidatesSQL,
                "photos",
                .seeks(index: "idx_photos_tree")
            ),
            (
                "the page's hero vote tallies",
                ContributionStore.scopedHeroPhotoTalliesSQL,
                "photo_votes",
                .seeks(index: "idx_photo_votes_photo")
            )
        ]

        try await store.queue.read { connection in
            for (label, sql, table, access) in statements {
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

                let scanned = Set(steps.compactMap { GroveQueryPlanTests.scannedRelation(in: $0) })
                switch access {
                case let .seeks(index):
                    let seeks = steps.filter { $0.contains("SEARCH") && $0.contains(index) }
                    #expect(
                        !seeks.isEmpty,
                        """
                        \(label) no longer SEARCHes \(index). That index is `AppSchema` v19's, and \
                        the collation on it is what lets a `COLLATE NOCASE` predicate reach it — a \
                        plan that lost the seek has lost the migration's whole effect — \(plan)
                        """
                    )
                    #expect(
                        !scanned.contains(table),
                        "\(label) walks \(table) end to end as well as seeking it — \(plan)"
                    )
                case .walks:
                    #expect(
                        scanned.contains(table),
                        """
                        \(label) no longer walks \(table) end to end. If it now seeks, the doc \
                        comment on this statement saying it cannot is wrong and has to go — \(plan)
                        """
                    )
                }
            }
        }
    }

    // MARK: - The calibration

    /// **Every string above still parses and plans against the real schema.**
    ///
    /// That is all this one proves, and the header says why the stronger claim it used to carry —
    /// that these are the statements the app runs — is `JournalStatementCensusTests`' to make and
    /// was never this file's. What is left is still worth having: a string naming a column a
    /// migration dropped fails here, on the shipped schema, rather than being explained forever.
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
