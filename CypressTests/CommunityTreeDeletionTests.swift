import Foundation
import Testing
@testable import Cypress

/// Account deletion over the rows `AppSchema` v23 gave an owner — `community_trees`' adder and
/// `tree_locations`' mover — and over `species_assertions`, which neither door reached until this
/// round (`ROADMAP` chip 79).
///
/// `AccountDeletionCoverageTests` already asserts each table's classified fate on a lone row. This
/// file is the part a lone row cannot show: the owner's decision 6 turns on what *else* is on the
/// tree, and the species chain has neighbors a deletion must not strand.
@Suite("Community trees · account deletion")
struct CommunityTreeDeletionTests {

    private typealias Fixture = LocationCorrectionTests

    /// **With the city file attached**, for the species tests: the attached seed carries a
    /// `species_assertions` *view*, so an unqualified `UPDATE species_assertions` fails with
    /// "cannot modify species_assertions because it is a view" — which a store with no seed never
    /// shows. `SpeciesAssertionStore` writes `main.` for this reason, and so does `AccountDeletion`.
    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func signedIn(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: Fixture.deviceID, userID: Fixture.userID)
    }

    private static func communityTree(_ store: CypressStore, _ id: UUID) async throws -> Tree? {
        try await store.queue.read { try CommunityTreeStore().tree(id: id, connection: $0) }
    }

    /// Somebody else's visit, written as a row: another installation, never this account's.
    private static func strangersVisit(on treeID: UUID, _ store: CypressStore) async throws {
        let stamp = SQLiteTimestamp.string(from: Date())
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO visits (id, tree_uuid, device_id, client_uuid, captured_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)', '\(treeID.uuidString)',
                        '\(Fixture.otherDeviceID.uuidString)', '\(UUID().uuidString)',
                        '\(stamp)', '\(stamp)', '\(stamp)');
                """)
        }
    }

    // MARK: - The leaving door

    /// Red-proof: delete the `UPDATE community_trees` statement from `forgetCommunityTrees` — red on
    /// "the tree still names the account".
    @Test("the leaving door keeps the account's tree with no adder, and its positions with no mover")
    func theLeavingDoorAnonymizes() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let tree = try await Fixture.add(api)
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 30),
            placement: .gps,
            locationAccuracyM: nil
        )
        #expect(try await Fixture.chain(store, tree.id).count == 2, "fixture: the move did not land")

        let outcome = try await api.deleteAccount(.leaveRecords)

        #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
        #expect(outcome.deletedCommunityTrees == 0, "\(outcome)")
        #expect(outcome.anonymizedTreeLocations == 2, "\(outcome)")
        let adder = try await Fixture.adder(store, tree.id)
        #expect(adder == .nobody, "the tree still names the account: \(String(describing: adder))")
        let chain = try await Fixture.chain(store, tree.id)
        #expect(chain.count == 2, "the leaving door removed positions")
        #expect(chain.allSatisfy { $0.owner == .nobody }, "a position still names its mover: \(chain.map(\.owner))")
        #expect(try await Self.communityTree(store, tree.id) != nil)
    }

    // MARK: - The erasing door

    /// Red-proof: skip the `DELETE FROM community_trees` in `forgetCommunityTrees` — red on
    /// "deletedCommunityTrees" and on the tree still being there.
    @Test("the erasing door deletes a tree nobody else has met, with every position it held")
    func theErasingDoorDeletesAnUnmetTree() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let tree = try await Fixture.add(api)
        _ = try await api.correctLocation(
            treeID: tree.id,
            to: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 30),
            placement: .gps,
            locationAccuracyM: nil
        )

        let outcome = try await api.deleteAccount(.eraseEverything)

        #expect(outcome.deletedCommunityTrees == 1, "\(outcome)")
        #expect(outcome.anonymizedCommunityTrees == 0, "\(outcome)")
        #expect(try await Self.communityTree(store, tree.id) == nil, "the tree survived the erasure")
        let chain = try await Fixture.chain(store, tree.id)
        #expect(chain.isEmpty, "\(chain.count) positions outlived their tree")
    }

    /// Decision 6's other arm. Red-proof: drop the `builtOnTables` predicate from the doomed read
    /// (select every tree the account added) — red on "a tree somebody else visited was deleted".
    @Test("the erasing door keeps a tree somebody else has met, anonymized")
    func theErasingDoorKeepsAMetTree() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let tree = try await Fixture.add(api)
        try await Self.strangersVisit(on: tree.id, store)

        let outcome = try await api.deleteAccount(.eraseEverything)

        #expect(try await Self.communityTree(store, tree.id) != nil, "a tree somebody else visited was deleted")
        #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
        #expect(outcome.deletedCommunityTrees == 0, "\(outcome)")
        #expect(try await Fixture.adder(store, tree.id) == .nobody)
        let chain = try await Fixture.chain(store, tree.id)
        #expect(chain.count == 1 && chain.allSatisfy { $0.owner == .nobody }, "\(chain.map(\.owner))")
    }

    // MARK: - The species chain (chip 79)

    /// Three chains, one per shape a deletion can cut: the account's statement at the head, a run of
    /// two at the head, and one in the middle.
    ///
    /// Red-proof: delete the splice loop in `eraseSpeciesAssertions` — the deletion's `COMMIT` fails
    /// on the deferred foreign key (`FOREIGN KEY constraint failed`), and the test fails on the throw.
    /// Delete the resync instead — red on `species_current`.
    @Test("the erasing door removes the account's species statements and splices each chain shut")
    func theErasingDoorSplicesSpeciesChains() async throws {
        let store = try await Self.seededStore()
        let api = Self.signedIn(store)
        let stranger = ContributionOwner.device(Fixture.otherDeviceID)
        let account = ContributionOwner.user(Fixture.userID)
        let s1 = UUID(), s2 = UUID(), s3 = UUID()

        // Three community trees nobody on this account added, so the tree rows are not the door's.
        let trees = (0..<3).map { index in
            Tree(
                source: .community,
                coordinate: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: Double(index) * 100)
            )
        }
        // (tree, [(owner, species)] oldest first)
        let shapes: [(Tree, [(ContributionOwner, UUID)])] = [
            (trees[0], [(stranger, s1), (account, s2)]),
            (trees[1], [(stranger, s1), (account, s2), (account, s3)]),
            (trees[2], [(stranger, s1), (account, s2), (stranger, s3)])
        ]
        var ids: [[UUID]] = []
        try await store.queue.write { connection in
            for (tree, statements) in shapes {
                try CommunityTreeStore().insert(tree, clientUUID: UUID(), connection: connection)
                let rowIDs = statements.map { _ in UUID() }
                for (index, statement) in statements.enumerated() {
                    try SpeciesAssertionStore().insert(
                        SpeciesAssertion(
                            id: rowIDs[index],
                            treeID: tree.id,
                            speciesID: statement.1,
                            source: .community,
                            owner: statement.0,
                            supersededBy: index + 1 < rowIDs.count ? rowIDs[index + 1] : nil,
                            createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                            updatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
                        ),
                        connection: connection
                    )
                }
                _ = try CommunityTreeStore().setSpecies(
                    treeID: tree.id, speciesID: statements.last!.1, at: Date(), connection: connection
                )
                ids.append(rowIDs)
            }
        }

        let outcome = try await api.deleteAccount(.eraseEverything)
        #expect(outcome.deletedAttributions == 4, "\(outcome)")

        let chains = try await store.queue.read { connection in
            try trees.map { try SpeciesAssertionStore().chain(treeID: $0.id, connection: connection) }
        }
        let species = try await store.queue.read { connection in
            try trees.map { try CommunityTreeStore().tree(id: $0.id, connection: connection)?.speciesCurrentID }
        }

        // Head cut: the stranger's statement is the head again, and the tree says so.
        #expect(chains[0].map(\.id) == [ids[0][0]], "\(chains[0].map(\.id))")
        #expect(chains[0].first?.supersededBy == nil)
        #expect(species[0] == s1, "the tree still carries the erased species")

        // A run of two at the head.
        #expect(chains[1].map(\.id) == [ids[1][0]], "\(chains[1].map(\.id))")
        #expect(chains[1].first?.supersededBy == nil)
        #expect(species[1] == s1)

        // A statement in the middle: the stranger's older row now points past it.
        #expect(Set(chains[2].map(\.id)) == [ids[2][0], ids[2][2]], "\(chains[2].map(\.id))")
        let oldest = try #require(chains[2].first { $0.id == ids[2][0] })
        #expect(oldest.supersededBy == ids[2][2], "the chain was not spliced past the erased statement")
        #expect(species[2] == s3)

        // Nothing anywhere still names the account.
        #expect(chains.joined().allSatisfy { $0.owner != account })
    }

    /// Red-proof: delete the `UPDATE species_assertions` in `anonymizeContributions` — red on the owner.
    @Test("the leaving door keeps the account's species statements with no author")
    func theLeavingDoorAnonymizesSpeciesStatements() async throws {
        let store = try await Self.seededStore()
        let api = Self.signedIn(store)
        let tree = Tree(source: .community, coordinate: Fixture.offshore)
        let statement = SpeciesAssertion(
            treeID: tree.id, speciesID: UUID(), source: .community, owner: .user(Fixture.userID)
        )
        try await store.queue.write { connection in
            try CommunityTreeStore().insert(tree, clientUUID: UUID(), connection: connection)
            try SpeciesAssertionStore().insert(statement, connection: connection)
        }

        _ = try await api.deleteAccount(.leaveRecords)

        let chain = try await store.queue.read {
            try SpeciesAssertionStore().chain(treeID: tree.id, connection: $0)
        }
        #expect(chain.map(\.id) == [statement.id], "the leaving door removed the statement")
        #expect(chain.first?.owner == .nobody, "the statement still names the account")
    }
}
