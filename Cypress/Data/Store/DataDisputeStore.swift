//
//  DataDisputeStore.swift
//  Cypress — Data/Store
//
//  `tree_data_disputes` and its two children (`AppSchema` v22, `RULINGS R79`).
//
//  ── Why this is its own store and not four methods on `ContributionStore` ──────────────────────
//
//  `ContributionStore` is 2,800 lines across a dozen tables and it is already the file every
//  contribution round widens. The deciding reason is not size, though: a dispute is the only record
//  in this app that is **assembled from three tables**, and every read and every write here has to
//  keep the parent and its two children in step. That is a single responsibility with an invariant
//  attached, and it belongs behind one door rather than distributed among methods that happen to
//  live near `review_flags`.
//
//  ── The invariant, and where it is enforced ───────────────────────────────────────────────────
//
//  A dispute is its parent row plus its checked issues plus its suggested values, always. Nothing
//  here writes one without the others, and `insert` takes the assembled `TreeDataDispute` rather
//  than three arguments so there is no call shape that could write half of one. The children are
//  `ON DELETE CASCADE` against the parent, which makes the database agree — and which is a hazard
//  for a future table rebuild that `AppSchema` v22's comment states at length.
//
//  ── No hard deletes ───────────────────────────────────────────────────────────────────────────
//
//  A withdrawal stamps `withdrawn_at` and leaves every row where it is (BUILD-PLAN §4's rule for
//  every table a user touches). The retraction is a fact about the dispute, not the absence of one:
//  a queue row for the withdrawal has already been written naming a dispute id, and a service that
//  received the raise has to be able to match the retraction to it.
//

import Foundation

/// Reads and writes the three tables one dispute is made of.
public struct DataDisputeStore {

    public init() {}

    // MARK: - Writing

    /// Writes a dispute and both of its children in one go.
    ///
    /// `ON CONFLICT(client_uuid) DO NOTHING` on the parent, matching every other contribution write
    /// in this project: the idempotency key is what a replay dedupes on. When the parent is a
    /// duplicate the children are **not** written, because the dispute this call describes is
    /// already in the table with children of its own — writing them again would either collide on
    /// the composite primary key or, worse, attach this call's issues to the earlier dispute's row.
    ///
    /// Called inside the caller's transaction, like every other write in `Data`. There is no
    /// arrangement in which the parent commits and the children do not.
    @discardableResult
    public func insert(
        _ dispute: TreeDataDispute,
        connection: SQLiteConnection
    ) throws -> ContributionStore.WriteOutcome {
        let parent = try connection.cachedStatement("""
            INSERT INTO tree_data_disputes
                (id, client_uuid, tree_id, tree_source, raised_by, notes,
                 created_at, updated_at, withdrawn_at)
            VALUES (:id, :client, :tree, :source, :by, :notes, :created, :updated, :withdrawn)
            ON CONFLICT(client_uuid) DO NOTHING
            """)
        _ = try parent.bind([
            ":id": dispute.id,
            ":client": dispute.clientUUID,
            ":tree": dispute.treeID,
            ":source": dispute.treeSource.rawValue,
            ":by": dispute.raisedBy,
            ":notes": dispute.notes,
            ":created": dispute.createdAt,
            ":updated": dispute.updatedAt,
            ":withdrawn": dispute.withdrawnAt
        ])
        try parent.run()
        let wrote = connection.changes > 0
        _ = try parent.reset()
        guard wrote else { return .duplicate }

        // Sorted, so the rows land in a deterministic order. `Set` iteration order is not stable
        // across runs, and a test comparing two dumps of this table would otherwise be flaky for a
        // reason that has nothing to do with what it is testing.
        for kind in dispute.issues.map(\.rawValue).sorted() {
            let issue = try connection.cachedStatement("""
                INSERT INTO tree_dispute_issues (dispute_id, kind) VALUES (:dispute, :kind)
                """)
            _ = try issue.bind([":dispute": dispute.id, ":kind": kind])
            try issue.run()
            _ = try issue.reset()
        }

        for (field, value) in dispute.suggestions.stored.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let suggestion = try connection.cachedStatement("""
                INSERT INTO tree_dispute_suggestions (dispute_id, field, value)
                VALUES (:dispute, :field, :value)
                """)
            _ = try suggestion.bind([
                ":dispute": dispute.id, ":field": field.rawValue, ":value": value
            ])
            try suggestion.run()
            _ = try suggestion.reset()
        }
        return .inserted
    }

    /// Stamps `withdrawn_at` on one open dispute this raiser owns, and answers how many rows moved.
    ///
    /// **The authorship gate is in the `WHERE` clause and not only in Swift**, which is
    /// `deletePhoto`'s ordering kept beat for beat because it was paid for: a read-then-write leaves
    /// a window in which the row changes under the caller, and the predicate that matched at read
    /// time is the one that has to match at write time. `LocalAPI.withdrawDataDispute` checks the
    /// same rule in Swift first so it can throw the right refusal; this is what makes the write
    /// safe when it does.
    ///
    /// `withdrawn_at IS NULL` in the predicate makes a second withdrawal a no-op that reports 0
    /// rather than a silent re-stamp with a later timestamp — the moment a dispute was taken back is
    /// a fact, not a value to overwrite.
    ///
    /// The anonymous arm — `raised_by IS NULL` — is this device's own contributor and nobody else's:
    /// this database belongs to one installation, and nothing syncs another person's disputes down.
    /// `review_flags.raised_by` carries the same nullable account id for the same D9 reason.
    public func withdraw(
        id: UUID,
        raisedBy: UUID?,
        at date: Date,
        connection: SQLiteConnection
    ) throws -> Int {
        let statement = try connection.cachedStatement("""
            UPDATE tree_data_disputes
               SET withdrawn_at = :now, updated_at = :now
             WHERE id = :id COLLATE NOCASE
               AND withdrawn_at IS NULL
               AND (raised_by = :by COLLATE NOCASE OR (:by IS NULL AND raised_by IS NULL))
            """)
        _ = try statement.bind([":id": id, ":now": date, ":by": raisedBy])
        try statement.run()
        let changed = connection.changes
        _ = try statement.reset()
        return changed
    }

    // MARK: - Reading

    /// One dispute by id, children included, or nil when there is no such row.
    public func dispute(id: UUID, connection: SQLiteConnection) throws -> TreeDataDispute? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM tree_data_disputes WHERE id = :id COLLATE NOCASE
            """)
        _ = try statement.bind([":id": id])
        guard let bare = try statement.fetchOne(Self.decode) else { return nil }
        return try withChildren(bare, connection: connection)
    }

    /// Every dispute on one tree, newest first, children included.
    ///
    /// Withdrawn ones are here too: a caller that wants only the standing objections filters on
    /// `isOpen`, and the read that wants the whole history — the adjudication surface a later round
    /// builds — needs both. Filtering here would make the second read a second query with a
    /// different name for the same thing.
    public func disputes(treeID: UUID, connection: SQLiteConnection) throws -> [TreeDataDispute] {
        let statement = try connection.cachedStatement("""
            SELECT * FROM tree_data_disputes
             WHERE tree_id = :tree COLLATE NOCASE
             ORDER BY created_at DESC, id
            """)
        _ = try statement.bind([":tree": treeID])
        return try statement.fetchAll(Self.decode).map { try withChildren($0, connection: connection) }
    }

    /// The open dispute this raiser has on this tree, or nil.
    ///
    /// **Per raiser, not per tree**, which is the rule `raiseDataDispute` refuses `.conflict` on:
    /// two people disagreeing with one record is two disagreements, and the merged inventory has to
    /// be able to count them. What nobody may have is two of their own standing at once, on
    /// `flagWrongSpecies`' reasoning — the person can see their own objection on the screen they are
    /// tapping from.
    ///
    /// Children are **not** read: every caller of this wants the id and whether there is one, and
    /// the profile's offer carries nothing else. `dispute(id:)` is the whole-record read.
    public func openDispute(
        treeID: UUID,
        raisedBy: UUID?,
        connection: SQLiteConnection
    ) throws -> TreeDataDispute? {
        let statement = try connection.cachedStatement("""
            SELECT * FROM tree_data_disputes
             WHERE tree_id = :tree COLLATE NOCASE
               AND withdrawn_at IS NULL
               AND (raised_by = :by COLLATE NOCASE OR (:by IS NULL AND raised_by IS NULL))
             ORDER BY created_at DESC, id
             LIMIT 1
            """)
        _ = try statement.bind([":tree": treeID, ":by": raisedBy])
        return try statement.fetchOne(Self.decode)
    }

    // MARK: - Assembly

    /// Fills in the two child tables for a parent row read without them.
    private func withChildren(
        _ dispute: TreeDataDispute,
        connection: SQLiteConnection
    ) throws -> TreeDataDispute {
        let issueRows = try connection.cachedStatement("""
            SELECT kind FROM tree_dispute_issues WHERE dispute_id = :dispute COLLATE NOCASE
            """)
        _ = try issueRows.bind([":dispute": dispute.id])
        // A stored value the enum does not know is dropped rather than thrown on. The `CHECK` makes
        // it unreachable from this build; what it protects against is a database written by a
        // *later* build and opened by this one — which `MigrationError.databaseIsAhead` already
        // refuses, so this arm is belt beside braces rather than a decision about behavior.
        let issues = Set(
            try issueRows.fetchAll { try $0.string("kind") }
                .compactMap(TreeDataDispute.IssueKind.init(rawValue:))
        )

        let suggestionRows = try connection.cachedStatement("""
            SELECT field, value FROM tree_dispute_suggestions WHERE dispute_id = :dispute COLLATE NOCASE
            """)
        _ = try suggestionRows.bind([":dispute": dispute.id])
        var stored: [TreeDataDispute.SuggestedField: String] = [:]
        for row in try suggestionRows.fetchAll({ (try $0.string("field"), try $0.string("value")) }) {
            guard let field = TreeDataDispute.SuggestedField(rawValue: row.0) else { continue }
            stored[field] = row.1
        }

        return TreeDataDispute(
            id: dispute.id,
            clientUUID: dispute.clientUUID,
            treeID: dispute.treeID,
            treeSource: dispute.treeSource,
            raisedBy: dispute.raisedBy,
            issues: issues,
            suggestions: TreeDataDispute.Suggestions(stored: stored),
            notes: dispute.notes,
            createdAt: dispute.createdAt,
            updatedAt: dispute.updatedAt,
            withdrawnAt: dispute.withdrawnAt
        )
    }

    /// The parent row, with empty children. Every caller either fills them in or does not need them.
    static func decode(_ row: SQLiteRow) throws -> TreeDataDispute {
        TreeDataDispute(
            id: try row.uuid("id"),
            clientUUID: try row.uuid("client_uuid"),
            treeID: try row.uuid("tree_id"),
            // A `tree_source` the enum does not know cannot exist: the column's `CHECK` admits
            // exactly `TreeSource`'s two raw values. `.community` is the safe fallback rather than a
            // throw, because the city arm is the one that unlocks a surface.
            treeSource: TreeSource(rawValue: try row.string("tree_source")) ?? .community,
            raisedBy: try row.uuidIfPresent("raised_by"),
            issues: [],
            notes: try row.stringIfPresent("notes"),
            createdAt: try row.date("created_at"),
            updatedAt: try row.date("updated_at"),
            withdrawnAt: try row.dateIfPresent("withdrawn_at")
        )
    }
}
