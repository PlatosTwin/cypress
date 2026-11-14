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
        try await deviceVisit(on: treeID, by: Fixture.otherDeviceID, store)
    }

    /// A device-owned visit (`user_id` NULL), by the installation named.
    private static func deviceVisit(on treeID: UUID, by device: UUID, _ store: CypressStore) async throws {
        let stamp = SQLiteTimestamp.string(from: Date())
        try await store.queue.write { connection in
            try connection.execute("""
                INSERT INTO visits (id, tree_uuid, device_id, client_uuid, captured_at, created_at, updated_at)
                VALUES ('\(UUID().uuidString)', '\(treeID.uuidString)',
                        '\(device.uuidString)', '\(UUID().uuidString)',
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

    // MARK: - The service's answer (`ROADMAP` 104 and 105)

    /// `ROADMAP` 104. The service deleted the account's tree under the leaving door (decision 12: it
    /// was never published), so the phone deletes it too, with its chain, instead of keeping a pin
    /// the service dropped.
    ///
    /// Red-proof: in `forgetCommunityTrees`, ignore `serviceTrees.deleted` — red on "the leaving
    /// door kept a tree the service deleted".
    @Test("the leaving door deletes a tree the service reported deleted, with its chain")
    func theLeavingDoorFollowsTheServicesDeletion() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let dropped = try await Fixture.add(api)
        let kept = try await Fixture.add(
            api, at: ProximityDedupeTests.diagonal(from: Fixture.offshore, meters: 200)
        )

        let outcome = try await api.deleteAccount(
            .leaveRecords,
            actingOn: AccountDeletion.ServiceTreeVerdicts(deleted: [dropped.id], anonymized: [kept.id])
        )

        #expect(try await Self.communityTree(store, dropped.id) == nil, "the leaving door kept a tree the service deleted")
        #expect(try await Fixture.chain(store, dropped.id).isEmpty, "positions outlived the deleted tree")
        #expect(outcome.deletedCommunityTrees == 1, "\(outcome)")
        #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
        #expect(try await Self.communityTree(store, kept.id) != nil, "the kept tree went too")
        #expect(try await Fixture.adder(store, kept.id) == .nobody)
    }

    /// `ROADMAP` 105(a). Somebody else's visit that never reached this phone kept the tree on the
    /// service. The phone holds no such visit, so its own rule would delete the tree; it keeps it,
    /// anonymized, because the service did.
    ///
    /// Red-proof: in `forgetCommunityTrees`, ignore `serviceTrees.anonymized` — red on "the erasing
    /// door deleted a tree the service kept".
    @Test("the erasing door keeps a tree the service kept, though nobody built on it here")
    func theErasingDoorFollowsTheServicesKeep() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let tree = try await Fixture.add(api)

        let outcome = try await api.deleteAccount(
            .eraseEverything, actingOn: AccountDeletion.ServiceTreeVerdicts(anonymized: [tree.id])
        )

        #expect(try await Self.communityTree(store, tree.id) != nil, "the erasing door deleted a tree the service kept")
        #expect(try await Fixture.adder(store, tree.id) == .nobody)
        #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
        #expect(outcome.deletedCommunityTrees == 0, "\(outcome)")
    }

    /// `ROADMAP` 105(b). This installation's own unclaimed visit is on the tree. The phone's rule
    /// reads it as somebody else's and would keep the tree; the service read it as the account's
    /// after the claim, erased it, and deleted the tree. The phone deletes the tree too.
    ///
    /// Red-proof: in `forgetCommunityTrees`, ignore `serviceTrees.deleted` — red on "the erasing
    /// door kept a tree the service deleted".
    @Test("the erasing door deletes a tree the service deleted, though this device's own visit is on it")
    func theErasingDoorFollowsTheServicesDeletion() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let tree = try await Fixture.add(api)
        try await Self.deviceVisit(on: tree.id, by: Fixture.deviceID, store)

        let outcome = try await api.deleteAccount(
            .eraseEverything, actingOn: AccountDeletion.ServiceTreeVerdicts(deleted: [tree.id])
        )

        #expect(try await Self.communityTree(store, tree.id) == nil, "the erasing door kept a tree the service deleted")
        #expect(try await Fixture.chain(store, tree.id).isEmpty)
        #expect(outcome.deletedCommunityTrees == 1, "\(outcome)")
    }

    /// The control for the test above: with no answer, the same rows keep the tree, so the device's
    /// own visit really is what the phone's rule reads as "built on". Without this, the test above
    /// could pass on a fixture whose visit never landed.
    @Test("with no answer, this device's own visit keeps the tree under the erasing door")
    func withNoAnswerTheOwnRuleKeepsTheTree() async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let tree = try await Fixture.add(api)
        try await Self.deviceVisit(on: tree.id, by: Fixture.deviceID, store)

        let outcome = try await api.deleteAccount(.eraseEverything, actingOn: nil)

        #expect(try await Self.communityTree(store, tree.id) != nil)
        #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
    }

    /// A tree the answer does not name (the service never received it) keeps the phone's own rule,
    /// under both doors: deleted under the erasing door when nobody built on it here, kept under the
    /// leaving door.
    ///
    /// Red-proof: in `forgetCommunityTrees`, decide an unnamed tree as "keep" — red on "an unnamed
    /// tree nobody met survived the erasure".
    @Test("a tree the answer does not name gets the phone's own rule", arguments: AccountDeletionChoice.allCases)
    func anUnnamedTreeGetsTheOwnRule(choice: AccountDeletionChoice) async throws {
        let store = try await CypressStore.inMemory()
        let api = Self.signedIn(store)
        let unnamed = try await Fixture.add(api)

        let outcome = try await api.deleteAccount(
            choice, actingOn: AccountDeletion.ServiceTreeVerdicts(deleted: [UUID()], anonymized: [UUID()])
        )

        switch choice {
        case .leaveRecords:
            #expect(try await Self.communityTree(store, unnamed.id) != nil, "the leaving door deleted an unnamed tree")
            #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
        case .eraseEverything:
            #expect(try await Self.communityTree(store, unnamed.id) == nil, "an unnamed tree nobody met survived the erasure")
            #expect(outcome.deletedCommunityTrees == 1, "\(outcome)")
        }
    }

    /// The whole path a signed-in deletion takes: `DELETE /me` answers with `community_trees`, and
    /// `RoutedAPI` hands it to the real `LocalAPI`. This is what proves the answer is not dropped at
    /// the protocol boundary: `RoutedAPI` holds its local half as `any CypressAPI`, and a witness
    /// that did not reach `LocalAPI` would delete with the phone's own rule and keep the tree.
    ///
    /// Red-proof: in `RoutedAPI.deleteAccount`, pass `actingOn: nil` — red on "the routed deletion
    /// dropped the service's answer".
    @Test("a routed deletion acts on the service's answer")
    func aRoutedDeletionActsOnTheAnswer() async throws {
        let store = try await CypressStore.inMemory()
        let local = Self.signedIn(store)
        let tree = try await Fixture.add(local)
        let transport = ScriptedTransport()
        transport.answer("DELETE /me", with: """
            {"deleted":true,"choice":"leaveRecords","contributions":0,"photos":0,"tombstones":0,
             "community_trees":{"deleted":["\(tree.id.uuidString.lowercased())"],"anonymized":[]}}
            """)
        let remote = RemoteAPI(
            baseURL: URL(string: "https://service.invalid/api/v1")!,
            transport: transport,
            session: .shared,
            pendingOutboxKeys: { [] }
        )
        let router = RoutedAPI(local: local, remote: remote, signedInUserID: { Fixture.userID })

        let outcome = try await router.deleteAccount(.leaveRecords)

        #expect(transport.call("DELETE /me") != nil, "fixture: the service was never asked")
        #expect(try await Self.communityTree(store, tree.id) == nil, "the routed deletion dropped the service's answer")
        #expect(outcome.deletedCommunityTrees == 1, "\(outcome)")
    }

    /// The other half of interoperating with the service as deployed today: an answer with no
    /// `community_trees` leaves the phone's own rule in charge, so the leaving door keeps the tree
    /// exactly as it did before the field existed.
    @Test("a routed deletion against an older service keeps the phone's own rule")
    func aRoutedDeletionAgainstAnOlderService() async throws {
        let store = try await CypressStore.inMemory()
        let local = Self.signedIn(store)
        let tree = try await Fixture.add(local)
        let transport = ScriptedTransport()
        transport.answer(
            "DELETE /me",
            with: #"{"deleted":true,"choice":"leaveRecords","contributions":0,"photos":0,"tombstones":0}"#
        )
        let remote = RemoteAPI(
            baseURL: URL(string: "https://service.invalid/api/v1")!,
            transport: transport,
            session: .shared,
            pendingOutboxKeys: { [] }
        )
        let router = RoutedAPI(local: local, remote: remote, signedInUserID: { Fixture.userID })

        let outcome = try await router.deleteAccount(.leaveRecords)

        #expect(try await Self.communityTree(store, tree.id) != nil, "an older service's answer deleted a tree")
        #expect(outcome.anonymizedCommunityTrees == 1, "\(outcome)")
        #expect(try await Fixture.adder(store, tree.id) == .nobody)
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
