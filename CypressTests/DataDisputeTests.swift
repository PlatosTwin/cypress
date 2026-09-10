import Foundation
import Testing
@testable import Cypress

/// **Disputing a city record's data** — `RULINGS R79` part 1, `AppSchema` v22.
///
/// R79's ruling in the owner's words: *"City data needs to be disputable via the UI. For now, we can
/// just store it in a separate DB, and later on we'll figure out how and whether to sync back to the
/// city's DB."* The refinement the same day made the city surface a checkbox set with suggested
/// values and free-text notes rather than a second pair of booleans.
///
/// What this suite holds down, in the order the round's contract states it:
///
/// 1. a city row is disputable and a community row is refused — the mirror image of
///    `flagWrongSpecies` / `flagNeverExisted`, and the R-b boundary this round is scoped to;
/// 2. the whole record lands in all three tables, and comes back out of them identical;
/// 3. every refusal is reachable and refuses for its own reason;
/// 4. **the inventory never moves** — the assertion this feature could most plausibly break, and
///    the one R79 defers explicitly;
/// 5. the raise and the withdrawal each queue their own kind, applied, and only when they committed;
/// 6. the two profile offers agree, so a later round draws one control and not two.
///
/// Every load-bearing assertion reads the database or the boundary's own refusal, never the object
/// the test just configured.
@Suite("Data disputes · R79 part 1")
struct DataDisputeTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-000000000079")!
    private static let otherDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000007A")!
    private static let accountA = UUID(uuidString: "AC000000-0000-4000-8000-0000000000A1")!
    private static let accountB = UUID(uuidString: "AC000000-0000-4000-8000-0000000000B1")!

    /// West of Ocean Beach: the seed is the city's *street*-tree inventory, so nothing is inside the
    /// 10 m dedupe radius and a community tree added here contends with no city record
    /// (`RecordDefectTests.offshore`'s argument, and the same coordinate).
    private static let offshore = Coordinate(latitude: 37.7605, longitude: -122.5405)

    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func api(
        _ store: CypressStore,
        device: UUID = deviceID,
        user: UUID? = nil
    ) -> LocalAPI {
        LocalAPI(store: store, deviceID: device, userID: user, role: .member)
    }

    /// A real row out of the shipped city inventory, near the Civic Center.
    private static func cityTree(_ api: LocalAPI) async throws -> NearbyTree {
        try #require(
            try await api.treesNear(
                Coordinate(latitude: 37.7749, longitude: -122.4194), radiusM: 400, limit: 1
            ).first,
            "the seed answered no tree near the Civic Center"
        )
    }

    private static func communityTree(_ api: LocalAPI) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: offshore,
            speciesID: nil,
            photoLocalPath: "/tmp/cypress-r79-dispute.jpg",
            attribution: .anonymous(deviceID: deviceID)
        ))
    }

    /// A suggestion set exercising every field the vocabulary has, with a fix good enough to place a
    /// tree. Used wherever a test wants "the fullest possible dispute" rather than a specific one.
    private static func everySuggestion(speciesID: UUID) -> TreeDataDispute.Suggestions {
        TreeDataDispute.Suggestions(
            location: TreeDataDispute.SuggestedLocation(
                coordinate: Coordinate(latitude: 37.7749295, longitude: -122.4194155),
                accuracyM: 4.5
            ),
            speciesID: speciesID,
            plantedYear: 1998,
            status: .vacantSite
        )
    }

    private static let everyIssue: Set<TreeDataDispute.IssueKind> = [
        .wrongLocation, .wrongSpecies, .wrongMetadata
    ]

    // MARK: - Raw reads, because the whole question is what is in the table

    /// The three tables' contents for one dispute, read straight out of SQL.
    ///
    /// Not through `DataDisputeStore`, deliberately: the store is what wrote them, and asking the
    /// writer whether it wrote is the shape of assertion this project's postmortem is about.
    private static func rows(
        _ disputeID: UUID,
        in store: CypressStore
    ) async throws -> (parent: [String: String?], issues: [String], suggestions: [String: String]) {
        try await store.queue.read { connection in
            let parentStatement = try connection.prepare("""
                SELECT CAST(id AS TEXT) AS id, CAST(client_uuid AS TEXT) AS client_uuid,
                       CAST(tree_id AS TEXT) AS tree_id, CAST(tree_source AS TEXT) AS tree_source,
                       CAST(raised_by AS TEXT) AS raised_by, CAST(notes AS TEXT) AS notes,
                       CAST(withdrawn_at AS TEXT) AS withdrawn_at
                  FROM tree_data_disputes WHERE id = :id COLLATE NOCASE
                """)
            defer { parentStatement.finalize() }
            _ = try parentStatement.bind([":id": disputeID.uuidString])
            let parent = try parentStatement.fetchOne { row -> [String: String?] in
                var values: [String: String?] = [:]
                for column in ["id", "client_uuid", "tree_id", "tree_source",
                               "raised_by", "notes", "withdrawn_at"] {
                    values.updateValue(try row.stringIfPresent(column), forKey: column)
                }
                return values
            } ?? [:]

            let issueStatement = try connection.prepare("""
                SELECT kind FROM tree_dispute_issues WHERE dispute_id = :id COLLATE NOCASE ORDER BY kind
                """)
            defer { issueStatement.finalize() }
            _ = try issueStatement.bind([":id": disputeID.uuidString])
            let issues = try issueStatement.fetchAll { try $0.string("kind") }

            let suggestionStatement = try connection.prepare("""
                SELECT field, value FROM tree_dispute_suggestions
                 WHERE dispute_id = :id COLLATE NOCASE
                """)
            defer { suggestionStatement.finalize() }
            _ = try suggestionStatement.bind([":id": disputeID.uuidString])
            var suggestions: [String: String] = [:]
            for pair in try suggestionStatement.fetchAll({
                (try $0.string("field"), try $0.string("value"))
            }) {
                suggestions[pair.0] = pair.1
            }
            return (parent, issues, suggestions)
        }
    }

    private static func queued(
        _ store: CypressStore,
        ofKind kind: OutboxItem.Kind
    ) async throws -> [OutboxStore.Record] {
        try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection).filter { $0.item.kind == kind }
        }
    }

    // MARK: - 1. The boundary R-b draws

    /// A city row is disputable and a community row is refused — the mirror image of the two flag
    /// verbs, and the whole of this round's scope.
    @Test("a city record is disputable and a community record is not, this round")
    func theRoundDisputesCityRowsOnly() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)

        let dispute = try await api.raiseDataDispute(
            treeID: city.id, issues: [.wrongLocation], suggestions: TreeDataDispute.Suggestions(),
            notes: nil
        )
        #expect(dispute.treeID == city.id)
        #expect(dispute.treeSource == .cityImport)

        let community = try await Self.communityTree(api)
        await #expect(throws: APIError.forbidden) {
            _ = try await api.raiseDataDispute(
                treeID: community.id, issues: [.wrongSpecies],
                suggestions: TreeDataDispute.Suggestions(), notes: nil
            )
        }

        // And the community row keeps exactly the flags it had: R-b, asserted rather than assumed.
        let communityProfile = try await api.treeProfile(id: community.id)
        #expect(communityProfile.recordDefect == .reportable)
        #expect(communityProfile.cityDataDispute == nil)
    }

    /// A record no half of the inventory holds is `.notFound`, not `.forbidden`.
    @Test("a record that is not there is not found")
    func anAbsentRecordIsNotFound() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        await #expect(throws: APIError.notFound) {
            _ = try await api.raiseDataDispute(
                treeID: UUID(), issues: [.wrongSpecies],
                suggestions: TreeDataDispute.Suggestions(), notes: nil
            )
        }
    }

    // MARK: - 2. The whole record lands, and comes back

    /// **Every field of the fullest possible dispute reaches all three tables**, read out of SQL,
    /// and the store reassembles the identical value from them.
    ///
    /// The suggestion set exercises all six stored fields, because a suggestion set left empty would
    /// pass through any writer at all — including one that dropped the child table entirely.
    @Test("a dispute reaches all three tables and comes back out of them unchanged")
    func theWholeDisputeRoundTripsThroughTheTables() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store, user: Self.accountA)
        let city = try await Self.cityTree(api)
        let species = try #require(await api.searchSpecies(query: "Platanus", limit: 1).first)

        let dispute = try await api.raiseDataDispute(
            treeID: city.id,
            issues: Self.everyIssue,
            suggestions: Self.everySuggestion(speciesID: species.id),
            notes: "The plot has been paved over."
        )

        let stored = try await Self.rows(dispute.id, in: store)
        #expect(stored.parent["tree_id"] ?? nil == city.id.uuidString)
        #expect(stored.parent["tree_source"] ?? nil == "city_import")
        #expect(stored.parent["raised_by"] ?? nil == Self.accountA.uuidString)
        #expect(stored.parent["notes"] ?? nil == "The plot has been paved over.")
        #expect(stored.parent["withdrawn_at"] ?? nil == nil, "a fresh dispute is already withdrawn")
        #expect(
            stored.issues == ["wrong_location", "wrong_metadata", "wrong_species"],
            "the checked issues in the table are \(stored.issues)"
        )
        #expect(
            Set(stored.suggestions.keys) == ["lat", "lon", "location_accuracy_m",
                                             "species_id", "planted_year", "status"],
            "the suggested fields in the table are \(stored.suggestions.keys.sorted())"
        )
        #expect(stored.suggestions["status"] == "vacant_site")
        #expect(stored.suggestions["planted_year"] == "1998")
        #expect(stored.suggestions["species_id"] == species.id.uuidString)

        // And the assembly is lossless in the other direction: the coordinates and the accuracy come
        // back as the same `Double`s, not as something a formatter rounded.
        let read = try #require(
            try await store.queue.read { try DataDisputeStore().dispute(id: dispute.id, connection: $0) }
        )
        #expect(read.issues == Self.everyIssue)
        #expect(read.suggestions == Self.everySuggestion(speciesID: species.id))
        #expect(read.notes == "The plot has been paved over.")
        #expect(read.raisedBy == Self.accountA)
        #expect(read.isOpen)
    }

    // MARK: - 3. The refusals, each for its own reason

    /// A dispute that checks nothing says nothing.
    @Test("an empty issue set is refused")
    func anEmptyIssueSetIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        await #expect(throws: APIError.validationFailed) {
            _ = try await api.raiseDataDispute(
                treeID: city.id, issues: [], suggestions: TreeDataDispute.Suggestions(), notes: nil
            )
        }
        #expect(try await Self.queued(store, ofKind: .dataDispute).isEmpty)
    }

    /// **A fix too coarse to pick out the tree it corrects is refused**, on the owner's instruction
    /// and on `AlmanacLimits.fixCanResolveAnArea`'s shape.
    ///
    /// The three cases are the rule's three arms and the middle one is the control: a fix *at* the
    /// bound is accepted, so "too coarse is refused" is not passing because everything is refused.
    /// The `nil` arm is the permitted one, for the reason the almanac's rule permits it — previews
    /// and tests driving a bare coordinate would otherwise be blanked.
    @Test("a suggested position is refused when its own fix cannot place a tree")
    func aCoarseFixIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        let bound = DataDisputeLimits.positionResolutionRadiusM
        #expect(bound == TreeDraft.proximityDedupeRadiusM, "the bound is not the dedupe radius")

        func raise(accuracyM: Double?) async throws -> TreeDataDispute {
            try await api.raiseDataDispute(
                treeID: city.id,
                issues: [.wrongLocation],
                suggestions: TreeDataDispute.Suggestions(
                    location: TreeDataDispute.SuggestedLocation(
                        coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                        accuracyM: accuracyM
                    )
                ),
                notes: nil
            )
        }

        await #expect(throws: APIError.validationFailed) { _ = try await raise(accuracyM: bound + 0.5) }
        // The control, in the same store: at the bound it is accepted, so the arm above is measuring
        // the accuracy and not the whole method.
        let accepted = try await raise(accuracyM: bound)
        #expect(accepted.suggestions.location?.accuracyM == bound)
        // And an unknown accuracy is permitted, which is the rule's own stated direction.
        try await api.withdrawDataDispute(disputeID: accepted.id)
        let unknown = try await raise(accuracyM: nil)
        #expect(unknown.suggestions.location?.accuracyM == nil)
    }

    /// A suggestion for an issue the dispute does not raise is refused.
    @Test("a suggestion for an unchecked issue is refused")
    func aSuggestionOutsideTheCheckedIssuesIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        let species = try #require(await api.searchSpecies(query: "Platanus", limit: 1).first)

        await #expect(throws: APIError.validationFailed) {
            _ = try await api.raiseDataDispute(
                treeID: city.id,
                issues: [.wrongLocation],
                suggestions: TreeDataDispute.Suggestions(speciesID: species.id),
                notes: nil
            )
        }
        // The control: the same suggestion, with the issue it speaks for checked.
        let allowed = try await api.raiseDataDispute(
            treeID: city.id,
            issues: [.wrongLocation, .wrongSpecies],
            suggestions: TreeDataDispute.Suggestions(speciesID: species.id),
            notes: nil
        )
        #expect(allowed.suggestions.speciesID == species.id)
    }

    /// Part 1 writes one status and refuses the rest.
    @Test("a status suggestion other than the empty plot is refused")
    func onlyTheVacantSiteStatusIsWritten() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)

        for status in TreeStatus.allCases where status != DataDisputeLimits.statusSuggestion {
            await #expect(throws: APIError.validationFailed) {
                _ = try await api.raiseDataDispute(
                    treeID: city.id, issues: [.wrongMetadata],
                    suggestions: TreeDataDispute.Suggestions(status: status), notes: nil
                )
            }
        }
        let allowed = try await api.raiseDataDispute(
            treeID: city.id, issues: [.wrongMetadata],
            suggestions: TreeDataDispute.Suggestions(status: DataDisputeLimits.statusSuggestion),
            notes: nil
        )
        #expect(allowed.suggestions.status == .vacantSite)
    }

    /// One open dispute per raiser per record; somebody else's does not block yours.
    @Test("a second dispute by the same raiser is a conflict, and a stranger's is not")
    func theConflictRuleIsPerRaiser() async throws {
        let store = try await Self.seededStore()
        let mine = Self.api(store, user: Self.accountA)
        let city = try await Self.cityTree(mine)

        let first = try await mine.raiseDataDispute(
            treeID: city.id, issues: [.wrongSpecies],
            suggestions: TreeDataDispute.Suggestions(), notes: nil
        )
        await #expect(throws: APIError.conflict) {
            _ = try await mine.raiseDataDispute(
                treeID: city.id, issues: [.wrongLocation],
                suggestions: TreeDataDispute.Suggestions(), notes: nil
            )
        }

        // Somebody else on this device, signed into their own account: a separate disagreement, and
        // the merged inventory has to be able to count both.
        let theirs = Self.api(store, device: Self.otherDeviceID, user: Self.accountB)
        let second = try await theirs.raiseDataDispute(
            treeID: city.id, issues: [.wrongLocation],
            suggestions: TreeDataDispute.Suggestions(), notes: nil
        )
        #expect(second.id != first.id)

        // And withdrawing mine frees the slot rather than leaving it wedged.
        try await mine.withdrawDataDispute(disputeID: first.id)
        let third = try await mine.raiseDataDispute(
            treeID: city.id, issues: [.wrongMetadata],
            suggestions: TreeDataDispute.Suggestions(), notes: nil
        )
        #expect(third.id != first.id)
    }

    /// Only the author may take a dispute back.
    @Test("another account cannot withdraw a dispute, and the row does not move")
    func onlyTheAuthorMayWithdraw() async throws {
        let store = try await Self.seededStore()
        let mine = Self.api(store, user: Self.accountA)
        let city = try await Self.cityTree(mine)
        let dispute = try await mine.raiseDataDispute(
            treeID: city.id, issues: [.wrongSpecies],
            suggestions: TreeDataDispute.Suggestions(), notes: nil
        )

        let theirs = Self.api(store, device: Self.otherDeviceID, user: Self.accountB)
        await #expect(throws: APIError.forbidden) {
            try await theirs.withdrawDataDispute(disputeID: dispute.id)
        }
        #expect(
            try await Self.rows(dispute.id, in: store).parent["withdrawn_at"] ?? nil == nil,
            "the refused withdrawal stamped the row anyway"
        )
        #expect(
            try await Self.queued(store, ofKind: .dataDisputeWithdrawal).isEmpty,
            "the refused withdrawal queued a retraction"
        )

        // The author's own succeeds, and stamps the column.
        try await mine.withdrawDataDispute(disputeID: dispute.id)
        #expect(try await Self.rows(dispute.id, in: store).parent["withdrawn_at"] ?? nil != nil)
        // Twice is `notFound`: "there is no open dispute with that id" is exactly true of it.
        await #expect(throws: APIError.notFound) {
            try await mine.withdrawDataDispute(disputeID: dispute.id)
        }
    }

    /// A dispute raised before this installation had an account stays its own to take back after
    /// signing in — D9's adoption, in the one place this table can express it.
    @Test("signing in does not strand a dispute this device raised anonymously")
    func anAnonymousDisputeSurvivesSigningIn() async throws {
        let store = try await Self.seededStore()
        let anonymous = Self.api(store)
        let city = try await Self.cityTree(anonymous)
        let dispute = try await anonymous.raiseDataDispute(
            treeID: city.id, issues: [.wrongSpecies],
            suggestions: TreeDataDispute.Suggestions(), notes: nil
        )
        #expect(dispute.raisedBy == nil)

        let signedIn = Self.api(store, user: Self.accountA)
        try await signedIn.withdrawDataDispute(disputeID: dispute.id)
        #expect(try await Self.rows(dispute.id, in: store).parent["withdrawn_at"] ?? nil != nil)
    }

    // MARK: - 4. The inventory does not move

    /// **The assertion this feature could most plausibly break.**
    ///
    /// R79 stores the disagreement and defers adjudication; a device that acted on an unadjudicated
    /// dispute would move city data on a say-so nobody weighed. So the fullest possible dispute is
    /// raised against a real seed row and every fact on the profile is compared before and after —
    /// species, status, coordinate, planted year — plus the two tables a status change would have to
    /// go through.
    @Test("a dispute changes nothing about the record it disputes")
    func aDisputeMovesNothingInTheInventory() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store, user: Self.accountA)
        let city = try await Self.cityTree(api)
        let species = try #require(await api.searchSpecies(query: "Platanus", limit: 1).first)
        let before = try await api.treeProfile(id: city.id)

        _ = try await api.raiseDataDispute(
            treeID: city.id,
            issues: Self.everyIssue,
            suggestions: Self.everySuggestion(speciesID: species.id),
            notes: "everything about this row is wrong"
        )

        let after = try await api.treeProfile(id: city.id)
        #expect(after.tree.speciesCurrentID == before.tree.speciesCurrentID, "the species moved")
        #expect(after.tree.status == before.tree.status, "the status moved")
        #expect(after.tree.coordinate == before.tree.coordinate, "the pin moved")
        #expect(after.tree.plantedYear == before.tree.plantedYear, "the planted year moved")
        #expect(after.species?.id == before.species?.id, "the resolved species moved")

        // The two tables a status or a species change would have to be written through, asked
        // directly — a profile can agree with itself while a row underneath it has changed.
        let override = try await store.queue.read { connection in
            try ContributionStore().statusOverrides(connection: connection)[city.id]
        }
        #expect(override == nil, "the dispute wrote a status override")
        let head = try await store.queue.read { connection in
            try SpeciesAssertionStore().current(treeID: city.id, connection: connection)
        }
        #expect(head == nil, "the dispute wrote a species assertion")
    }

    // MARK: - 5. The queue

    /// Each act queues its own kind, applied, carrying the facts a service would need.
    @Test("the raise and the withdrawal each queue their own kind, already applied")
    func eachActQueuesItsOwnKind() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store, user: Self.accountA)
        let city = try await Self.cityTree(api)
        let species = try #require(await api.searchSpecies(query: "Platanus", limit: 1).first)

        let dispute = try await api.raiseDataDispute(
            treeID: city.id,
            issues: Self.everyIssue,
            suggestions: Self.everySuggestion(speciesID: species.id),
            notes: "paved over"
        )

        let raises = try await Self.queued(store, ofKind: .dataDispute)
        #expect(raises.count == 1, "the raise queued \(raises.count) rows")
        let raised = try #require(raises.first)
        #expect(raised.locallyApplied, "the raise was queued unapplied and a drain would re-apply it")
        #expect(!raised.remoteSent)
        #expect(raised.item.photos.isEmpty, "a dispute grew a photo binary")
        #expect(raised.item.clientUUID == dispute.clientUUID)
        guard case let .dataDispute(payload) = try OutboxPayload.decode(
            kind: raised.item.kind, from: raised.item.payload
        ) else {
            Issue.record("the queued raise did not decode as a dispute")
            return
        }
        #expect(payload.disputeID == dispute.id)
        #expect(payload.treeID == city.id)
        #expect(payload.treeSource == .cityImport)
        #expect(payload.issues == Self.everyIssue)
        #expect(payload.suggestions == Self.everySuggestion(speciesID: species.id))
        #expect(payload.notes == "paved over")
        #expect(payload.attribution.userID == Self.accountA)

        try await api.withdrawDataDispute(disputeID: dispute.id)
        let withdrawals = try await Self.queued(store, ofKind: .dataDisputeWithdrawal)
        #expect(withdrawals.count == 1, "the withdrawal queued \(withdrawals.count) rows")
        let withdrawn = try #require(withdrawals.first)
        #expect(withdrawn.locallyApplied)
        guard case let .dataDisputeWithdrawal(retraction) = try OutboxPayload.decode(
            kind: withdrawn.item.kind, from: withdrawn.item.payload
        ) else {
            Issue.record("the queued withdrawal did not decode as one")
            return
        }
        #expect(retraction.disputeID == dispute.id, "the retraction does not name the dispute it took back")
        #expect(retraction.treeID == city.id)
        // Still one raise: the withdrawal did not remove the row that already left, which is what a
        // service matching the two has to be able to rely on.
        #expect(try await Self.queued(store, ofKind: .dataDispute).count == 1)
    }

    /// A refused raise queues nothing — the ordering that keeps the queue from asserting something
    /// the gates did not allow.
    @Test("a refused raise queues nothing and writes nothing")
    func aRefusedRaiseQueuesNothing() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let community = try await Self.communityTree(api)

        await #expect(throws: APIError.forbidden) {
            _ = try await api.raiseDataDispute(
                treeID: community.id, issues: [.wrongSpecies],
                suggestions: TreeDataDispute.Suggestions(), notes: nil
            )
        }
        #expect(try await Self.queued(store, ofKind: .dataDispute).isEmpty)
        let disputes = try await store.queue.read { connection in
            try DataDisputeStore().disputes(treeID: community.id, connection: connection)
        }
        #expect(disputes.isEmpty, "the refused raise wrote a dispute row")
    }

    // MARK: - 6. The two offers agree

    /// **Both profile offers carry the identical `DataDisputeOffer` for a city row.**
    ///
    /// R79's city surface is one sheet covering both seams, so both offers point at it — and a view
    /// that read them as two independent answers would draw two controls, which is exactly what
    /// those two enums' own headers exist to prevent. This is what keeps the pair from drifting, and
    /// `TreeProfile.cityDataDispute` is the single accessor it licenses.
    ///
    /// It walks the offer through all three of its states, because agreement on `.raisable` alone
    /// would be agreement on the state that needs no lookup.
    @Test("the two offers agree on a city row, in every state the dispute has")
    func theTwoOffersAgreeOnACityRow() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store, user: Self.accountA)
        let city = try await Self.cityTree(api)

        func offers() async throws -> (SpeciesCorrectionOffer, RecordDefectOffer, DataDisputeOffer?) {
            let profile = try await api.treeProfile(id: city.id)
            return (profile.speciesCorrection, profile.recordDefect, profile.cityDataDispute)
        }

        var (species, record, accessor) = try await offers()
        #expect(species == .dataDispute(.raisable))
        #expect(record == .dataDispute(.raisable))
        #expect(accessor == .raisable)

        let dispute = try await api.raiseDataDispute(
            treeID: city.id, issues: [.wrongLocation],
            suggestions: TreeDataDispute.Suggestions(), notes: nil
        )
        (species, record, accessor) = try await offers()
        #expect(species == .dataDispute(.raisedByYou(disputeID: dispute.id)))
        #expect(record == .dataDispute(.raisedByYou(disputeID: dispute.id)))
        #expect(accessor == .raisedByYou(disputeID: dispute.id))

        // Somebody else's open dispute leaves this viewer `.raisable`: the conflict rule is per
        // raiser, and an offer that hid the control would tell one person their disagreement had
        // already been made by another.
        let theirs = Self.api(store, device: Self.otherDeviceID, user: Self.accountB)
        let theirProfile = try await theirs.treeProfile(id: city.id)
        #expect(theirProfile.cityDataDispute == .raisable)

        try await api.withdrawDataDispute(disputeID: dispute.id)
        (species, record, accessor) = try await offers()
        #expect(species == .dataDispute(.raisable), "a withdrawn dispute still occupies the offer")
        #expect(record == .dataDispute(.raisable))
        #expect(accessor == .raisable)
    }

    // MARK: - 7. The pure rules, without a database

    /// The suggestion vocabulary survives its own text round trip, field by field.
    ///
    /// A coordinate is the one that matters: `Double.description` is the shortest representation
    /// that parses back to the same bit pattern, and a locale-aware formatter here would write a
    /// decimal comma that nothing could read.
    @Test("every suggested field survives the text round trip the table puts it through")
    func everySuggestedFieldRoundTrips() {
        let species = UUID()
        let suggestions = TreeDataDispute.Suggestions(
            location: TreeDataDispute.SuggestedLocation(
                coordinate: Coordinate(latitude: 37.774929496, longitude: -122.419415502),
                accuracyM: 4.6500000000000004
            ),
            speciesID: species,
            plantedYear: 1998,
            status: .vacantSite
        )
        let stored = suggestions.stored
        #expect(
            Set(stored.keys) == Set(TreeDataDispute.SuggestedField.allCases),
            """
            the fullest possible suggestion set writes \(stored.keys.map(\.rawValue).sorted()), \
            which is not the whole vocabulary — a field with no writer here is untested
            """
        )
        #expect(TreeDataDispute.Suggestions(stored: stored) == suggestions)

        // Half a location is no location, rather than a coordinate with an invented half.
        var half = stored
        half[.longitude] = nil
        #expect(TreeDataDispute.Suggestions(stored: half).location == nil)
    }

    /// Every field belongs to exactly one checkbox, and the mapping is total.
    @Test("every suggested field names the issue it speaks for")
    func everyFieldNamesItsIssue() {
        for field in TreeDataDispute.SuggestedField.allCases {
            let issue = field.issue
            #expect(
                TreeDataDispute.IssueKind.allCases.contains(issue),
                "\(field.rawValue) names \(issue.rawValue), which is not an issue kind"
            )
        }
        #expect(TreeDataDispute.SuggestedField.latitude.issue == .wrongLocation)
        #expect(TreeDataDispute.SuggestedField.speciesID.issue == .wrongSpecies)
        #expect(TreeDataDispute.SuggestedField.status.issue == .wrongMetadata)
    }

    /// `isAuthored(by:)`'s two arms, including the asymmetry that is the point of it.
    @Test("authorship admits this installation's anonymous rows and never another account's")
    func authorshipHasTwoArmsAndOneAsymmetry() {
        func dispute(raisedBy: UUID?) -> TreeDataDispute {
            TreeDataDispute(
                treeID: UUID(), treeSource: .cityImport, raisedBy: raisedBy,
                issues: [.wrongSpecies], createdAt: Date(), updatedAt: Date()
            )
        }
        #expect(dispute(raisedBy: nil).isAuthored(by: nil), "this device cannot take back its own")
        #expect(dispute(raisedBy: nil).isAuthored(by: Self.accountA), "signing in stranded it")
        #expect(dispute(raisedBy: Self.accountA).isAuthored(by: Self.accountA))
        #expect(!dispute(raisedBy: Self.accountA).isAuthored(by: Self.accountB))
        #expect(
            !dispute(raisedBy: Self.accountA).isAuthored(by: nil),
            "a signed-out reader was handed an account's dispute"
        )
    }
}
