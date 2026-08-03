import Foundation
import Testing
@testable import Cypress

/// Correcting a species claim — tickets **#86** (your own claim) and **#124** (somebody else's), on
/// the `species_assertions` chain AppSchema **v14** put in `main`.
///
/// The rule these hold down is `docs/rulings-pending/species-supersession.md`: an assertion is
/// superseded without review only by the identity that made it; every other correction is a report
/// against somebody's statement and is recorded as one. Two things follow that this suite proves
/// separately, because each has passed while the other was broken in an earlier shape of this work:
///
/// - **the chain is real.** A correction appends and stamps; nothing is overwritten, and the
///   engine — not a comment — refuses a second unsuperseded head.
/// - **the seams stay apart.** Confirming a wrong-species report must never write `trees.status`.
///   `ReviewFlag.Kind.statusReviewKinds` is derived from `confirmedStatus != nil`, so a one-line
///   "fix" pointing `wrongSpecies` at a status would silently enrol species reports in the removal
///   queue (ERRATA E170).
///
/// Every load-bearing assertion reads the database or the boundary's own refusal, never the object
/// the test just configured.
@Suite("Species correction")
struct SpeciesCorrectionTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AD14")!
    private static let strangerDeviceID = UUID(uuidString: "D0000000-0000-4000-8000-00000000AD15")!
    private static let moment = Date(timeIntervalSince1970: 1_800_000_000)

    /// West of Ocean Beach: the seed is the city's *street*-tree inventory, so nothing is inside the
    /// 10 m dedupe radius and the only trees a test contends with are its own
    /// (`SpeciesClaimTests.offshore`'s argument).
    private static let offshore = Coordinate(latitude: 37.7600, longitude: -122.5400)

    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func addTree(through api: LocalAPI, at spot: Coordinate, species: UUID? = nil) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: spot,
            speciesID: species,
            photoLocalPath: "/tmp/cypress-species-correction.jpg",
            attribution: .anonymous(deviceID: deviceID)
        ))
    }

    private static func twoSpecies(_ api: LocalAPI) async throws -> (Species, Species) {
        let plane = try #require(await api.searchSpecies(query: "Platanus", limit: 5).first,
                                 "the catalogue answered no Platanus")
        let oak = try #require(
            await api.searchSpecies(query: "Quercus", limit: 5).first { $0.id != plane.id },
            "the catalogue answered no second species"
        )
        return (plane, oak)
    }

    private static func chain(of treeID: UUID, in store: CypressStore) async throws -> [SpeciesAssertion] {
        try await store.queue.read { connection in
            try SpeciesAssertionStore().chain(treeID: treeID, connection: connection)
        }
    }

    private static func storedSpecies(of id: UUID, in store: CypressStore) async throws -> String? {
        try await store.queue.read { connection -> String? in
            let statement = try connection.prepare(
                "SELECT species_current FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind([":id": id.uuidString])
            return try statement.fetchOne { try $0.stringIfPresent("species_current") } ?? nil
        }
    }

    // MARK: - #86 · your own claim

    /// The whole of #86, through the boundary and read back out of both tables.
    ///
    /// Two rows, not one edited row: the point of the chain is that the corrected claim survives, so
    /// this asserts the *first* assertion is still there and now points forward, rather than only
    /// asserting the second one arrived.
    @Test("a claim you made is yours to correct, and the claim it replaces keeps its row")
    func yourOwnClaimIsCorrectable() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, oak) = try await Self.twoSpecies(api)
        let tree = try await Self.addTree(through: api, at: Self.offshore)
        _ = try await api.claimSpecies(treeID: tree.id, speciesID: plane.id)

        let corrected = try await api.correctSpecies(treeID: tree.id, speciesID: oak.id)
        #expect(corrected.speciesCurrentID == oak.id)

        let chain = try await Self.chain(of: tree.id, in: store)
        #expect(chain.count == 2, "the correction did not append: the chain holds \(chain.count) rows")
        let first = try #require(chain.first)
        let second = try #require(chain.last)
        #expect(first.speciesID == plane.id, "the first claim no longer names what was claimed")
        #expect(first.supersededBy == second.id, "the first claim was not stamped with its successor")
        #expect(second.speciesID == oak.id)
        #expect(second.isCurrent, "the correction is not the head of the chain")
        #expect(second.owner == .device(Self.deviceID), "the correction records the wrong author")

        // The read cache followed the chain, in the same transaction.
        let stored = try await Self.storedSpecies(of: tree.id, in: store)
        #expect(
            stored?.caseInsensitiveCompare(oak.id.uuidString) == .orderedSame,
            "community_trees.species_current holds \(stored ?? "NULL"), not the correction"
        )
    }

    /// The other half of the same guarantee: a tree added *with* a species opens the chain too, or
    /// the person who named it at the add screen could not correct it afterwards.
    @Test("a species stated at the add screen opens the chain, owned by whoever stated it")
    func theAddScreenOpensTheChain() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, oak) = try await Self.twoSpecies(api)
        let tree = try await Self.addTree(
            through: api,
            at: VisitPinAdjust.offset(Self.offshore, northM: 300, eastM: 0),
            species: plane.id
        )

        let opened = try await Self.chain(of: tree.id, in: store)
        #expect(opened.count == 1, "the add wrote \(opened.count) assertions")
        #expect(opened.first?.owner == .device(Self.deviceID))

        _ = try await api.correctSpecies(treeID: tree.id, speciesID: oak.id)
        #expect(try await Self.chain(of: tree.id, in: store).count == 2)
    }

    // MARK: - #124 · somebody else's claim

    /// A second device may not overwrite the first one's statement, and the refusal leaves the row
    /// exactly as it was — asserted on the column, because "it threw" and "it threw *and changed
    /// nothing*" are different guarantees.
    @Test("a claim somebody else made is refused as forbidden and survives untouched")
    func somebodyElsesClaimIsNotYoursToOverwrite() async throws {
        let store = try await Self.seededStore()
        let namer = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, oak) = try await Self.twoSpecies(namer)
        let tree = try await Self.addTree(through: namer, at: Self.offshore)
        _ = try await namer.claimSpecies(treeID: tree.id, speciesID: plane.id)

        let stranger = LocalAPI(store: store, deviceID: Self.strangerDeviceID)
        await #expect(throws: APIError.forbidden) {
            _ = try await stranger.correctSpecies(treeID: tree.id, speciesID: oak.id)
        }
        let stored = try await Self.storedSpecies(of: tree.id, in: store)
        #expect(
            stored?.caseInsensitiveCompare(plane.id.uuidString) == .orderedSame,
            "the refused correction moved the species anyway: \(stored ?? "NULL")"
        )
        #expect(try await Self.chain(of: tree.id, in: store).count == 1, "the refusal appended an assertion")
    }

    /// #124's own verb: the report lands as an open `wrong_species` flag and the tree does not move.
    @Test("reporting somebody else's species raises a flag and changes nothing about the tree")
    func reportingRaisesAFlagAndNothingElse() async throws {
        let store = try await Self.seededStore()
        let namer = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, _) = try await Self.twoSpecies(namer)
        let tree = try await Self.addTree(through: namer, at: Self.offshore)
        _ = try await namer.claimSpecies(treeID: tree.id, speciesID: plane.id)

        let stranger = LocalAPI(store: store, deviceID: Self.strangerDeviceID)
        try await stranger.flagWrongSpecies(treeID: tree.id)

        let flags = try await store.queue.read { connection in
            try ContributionStore().openReviewFlags(kinds: [.wrongSpecies], connection: connection)
        }
        #expect(flags.count == 1, "the report raised \(flags.count) flags")
        #expect(flags.first?.treeID == tree.id)
        #expect(flags.first?.status == .open)

        let stored = try await Self.storedSpecies(of: tree.id, in: store)
        #expect(
            stored?.caseInsensitiveCompare(plane.id.uuidString) == .orderedSame,
            "the report moved the species: \(stored ?? "NULL")"
        )
        #expect(try await namer.treeProfile(id: tree.id).tree.status == .alive,
                "the report moved the tree's status")

        // A second report says nothing the first did not.
        await #expect(throws: APIError.conflict) {
            try await stranger.flagWrongSpecies(treeID: tree.id)
        }
    }

    /// Reporting your own claim is refused: you correct it. The two acts are offered by the same
    /// block on the profile and exactly one of them is ever available.
    @Test("reporting your own species claim is refused rather than queued")
    func reportingYourOwnClaimIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, _) = try await Self.twoSpecies(api)
        let tree = try await Self.addTree(through: api, at: Self.offshore)
        _ = try await api.claimSpecies(treeID: tree.id, speciesID: plane.id)

        await #expect(throws: APIError.validationFailed) {
            try await api.flagWrongSpecies(treeID: tree.id)
        }
    }

    /// A city row's species is the city's, in a read-only database — and the report is refused for
    /// the same reason the correction is. A report nothing can resolve is the E170 defect, and the
    /// read path a community counter-claim would need does not exist yet.
    @Test("a city inventory row refuses both the correction and the report, as forbidden")
    func aCityRowRefusesBoth() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let cityTreeID = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare(
                "SELECT uuid FROM \(SeedDatabase.schemaName).trees WHERE deleted_at IS NULL LIMIT 1"
            )
            defer { statement.finalize() }
            return try statement.fetchOne { try $0.uuidIfPresent("uuid") } ?? nil
        }
        let target = try #require(cityTreeID, "the seed has no trees")
        let (plane, _) = try await Self.twoSpecies(api)

        await #expect(throws: APIError.forbidden) {
            _ = try await api.correctSpecies(treeID: target, speciesID: plane.id)
        }
        await #expect(throws: APIError.forbidden) {
            try await api.flagWrongSpecies(treeID: target)
        }
    }

    // MARK: - Resolving a report

    /// Correcting the species **is** confirming the report — one transaction, no second verb to
    /// forget — and the lead arm needs a report to exist before it may act.
    @Test("a lead may correct only in answer to a report, and the correction closes it")
    func aLeadResolvesByCorrecting() async throws {
        let store = try await Self.seededStore()
        let namer = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, oak) = try await Self.twoSpecies(namer)
        let tree = try await Self.addTree(through: namer, at: Self.offshore)
        _ = try await namer.claimSpecies(treeID: tree.id, speciesID: plane.id)

        let lead = LocalAPI(store: store, deviceID: Self.strangerDeviceID, role: .moderator)
        // A lead with an opinion and no report in front of them is a contributor.
        await #expect(throws: APIError.forbidden) {
            _ = try await lead.correctSpecies(treeID: tree.id, speciesID: oak.id)
        }

        try await lead.flagWrongSpecies(treeID: tree.id)
        _ = try await lead.correctSpecies(treeID: tree.id, speciesID: oak.id)

        let open = try await store.queue.read { connection in
            try ContributionStore().openReviewFlags(kinds: [.wrongSpecies], connection: connection)
        }
        #expect(open.isEmpty, "the correction left the report open")
        let stored = try await Self.storedSpecies(of: tree.id, in: store)
        #expect(stored?.caseInsensitiveCompare(oak.id.uuidString) == .orderedSame)
    }

    /// The second verb, and its promise: the species stays where it is and nothing is appended.
    @Test("keeping the species closes the report, appends nothing and writes no status")
    func dismissingChangesNothing() async throws {
        let store = try await Self.seededStore()
        let namer = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, _) = try await Self.twoSpecies(namer)
        let tree = try await Self.addTree(through: namer, at: Self.offshore)
        _ = try await namer.claimSpecies(treeID: tree.id, speciesID: plane.id)

        let stranger = LocalAPI(store: store, deviceID: Self.strangerDeviceID)
        try await stranger.flagWrongSpecies(treeID: tree.id)
        let flagID = try await #require(
            store.queue.read { connection in
                try ContributionStore().openReviewFlags(kinds: [.wrongSpecies], connection: connection).first
            },
            "the report was not raised"
        ).id

        // The stranger who raised it may not answer it; the author of the disputed claim may.
        await #expect(throws: APIError.forbidden) { try await stranger.dismissSpeciesReview(flagID: flagID) }
        try await namer.dismissSpeciesReview(flagID: flagID)

        let answered = try await store.queue.read { connection in
            try ContributionStore().reviewFlag(id: flagID, connection: connection)
        }
        #expect(answered?.status == .dismissed, "the report is \(String(describing: answered?.status))")
        #expect(try await Self.chain(of: tree.id, in: store).count == 1, "the dismissal appended an assertion")
        let stored = try await Self.storedSpecies(of: tree.id, in: store)
        #expect(stored?.caseInsensitiveCompare(plane.id.uuidString) == .orderedSame)
        #expect(try await namer.treeProfile(id: tree.id).tree.status == .alive)
    }

    // MARK: - The seam (ERRATA E170)

    /// The property this round must not break, asserted as a property rather than as a list.
    ///
    /// `wrongSpecies` resolves through the species seam, so it is not in the queue a confirm serves
    /// and `confirmedStatus` is nil for it — which is what makes `confirmReview` refuse it. A change
    /// that gave it a status to "make it resolvable" would pass a test that only checked the queue
    /// was non-empty; this checks the two derived lists are disjoint and that the refusal survives.
    @Test("the species seam and the status seam never serve the same kind")
    func theSeamsStayApart() async throws {
        let species = Set(ReviewFlag.Kind.speciesReviewKinds)
        let status = Set(ReviewFlag.Kind.statusReviewKinds)
        #expect(species.contains(.wrongSpecies), "the species seam serves no species kind")
        #expect(species.isDisjoint(with: status), "a kind is served by both seams: \(species.intersection(status))")
        for kind in species {
            #expect(kind.confirmedStatus == nil, "\(kind.rawValue) would move trees.status on confirm")
        }
        for kind in status {
            #expect(kind.resolution != .speciesAssertion)
        }
    }

    /// And the refusal at the boundary, on a real flag: the status queue's two verbs will not touch
    /// a species report, and the tree does not move.
    @Test("the status queue cannot confirm or dismiss a species report")
    func theStatusQueueRefusesASpeciesReport() async throws {
        let store = try await Self.seededStore()
        let namer = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, _) = try await Self.twoSpecies(namer)
        let tree = try await Self.addTree(through: namer, at: Self.offshore)
        _ = try await namer.claimSpecies(treeID: tree.id, speciesID: plane.id)

        let lead = LocalAPI(store: store, deviceID: Self.strangerDeviceID, role: .moderator)
        try await lead.flagWrongSpecies(treeID: tree.id)
        let flagID = try await #require(
            store.queue.read { connection in
                try ContributionStore().openReviewFlags(kinds: [.wrongSpecies], connection: connection).first
            }
        ).id

        #expect(try await lead.openReviews().isEmpty, "a species report reached the status queue")
        await #expect(throws: APIError.validationFailed) { try await lead.confirmReview(flagID: flagID) }
        await #expect(throws: APIError.validationFailed) { try await lead.dismissReview(flagID: flagID) }
        #expect(try await lead.treeProfile(id: tree.id).tree.status == .alive)
    }

    // MARK: - The chain's invariant, in the engine

    /// One current claim per tree, enforced by the partial unique index rather than by the code that
    /// happens to write it. Asserted by writing round the API, because that is the only way to prove
    /// the *database* refuses it.
    @Test("the database refuses a second unsuperseded assertion on one tree")
    func oneHeadPerTree() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, oak) = try await Self.twoSpecies(api)
        let tree = try await Self.addTree(through: api, at: Self.offshore)
        _ = try await api.claimSpecies(treeID: tree.id, speciesID: plane.id)

        await #expect(throws: SQLiteError.self) {
            try await store.queue.write { connection in
                try SpeciesAssertionStore().insert(
                    SpeciesAssertion(
                        treeID: tree.id,
                        speciesID: oak.id,
                        source: .community,
                        owner: .device(Self.deviceID),
                        createdAt: Self.moment,
                        updatedAt: Self.moment
                    ),
                    connection: connection
                )
            }
        }
    }

    // MARK: - The upgrade (AppSchema v14)

    /// The path that can destroy somebody's data, and the only one a fresh install never exercises:
    /// a database written by the previous build, with real rows in it, migrated.
    ///
    /// The claim goes in against the v13 schema — no `species_assertions` table exists to write,
    /// which is the point — and must come out the other side intact, with a chain head that belongs
    /// to **nobody**. That is the ruling's third arm, and it is asserted as a refusal at the
    /// boundary rather than only as a column value, because "the column is null" and "the claim is
    /// therefore not correctable by this phone" are two different things and only the second is the
    /// behaviour anybody experiences.
    @Test("a species claimed before v14 survives the upgrade and belongs to nobody")
    func theUpgradePreservesClaimsAndAttributesThemToNobody() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        _ = try SchemaMigrator.migrate(AppSchema.migrations.filter { $0.version <= 13 }, on: connection)
        #expect(
            try connection.columnNames(ofTable: "species_assertions").isEmpty,
            "a v13 database already had the table"
        )

        let named = UUID()
        let unnamed = UUID()
        let speciesID = UUID()
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        for (id, species) in [(named, "'\(speciesID.uuidString)'"), (unnamed, "NULL")] {
            try connection.execute("""
                INSERT INTO community_trees
                    (id, client_uuid, source, lat, lon, address, status, species_current,
                     verification_state, created_at, updated_at)
                VALUES ('\(id.uuidString)','\(UUID().uuidString)','community',
                        37.7599,-122.4148,'1 Folsom St','alive',\(species),
                        'unverified','\(stamp)','\(stamp)')
                """)
        }
        // A flag written against the pre-rebuild `review_flags`, to prove the rebuild copies rows.
        let flagID = UUID()
        try connection.execute("""
            INSERT INTO review_flags (id, tree_uuid, kind, status, created_at, updated_at)
            VALUES ('\(flagID.uuidString)','\(named.uuidString)','appears_dead','open','\(stamp)','\(stamp)')
            """)

        // Every step above 13, not literally `[14]`: this gate is about existing rows surviving, and
        // it must not fail the day an unrelated migration is added.
        let expected = AppSchema.migrations.map(\.version).filter { $0 > 13 }
        let applied = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        #expect(applied == expected, "migrating a v13 database applied \(applied), expected \(expected)")
        #expect(try connection.userVersion == AppSchema.currentVersion)

        let store = SpeciesAssertionStore()
        let head = try #require(
            try store.current(treeID: named, connection: connection),
            "the claimed species gained no chain head"
        )
        #expect(head.speciesID == speciesID, "the backfilled assertion names the wrong species")
        #expect(head.source == .community)
        #expect(head.owner == .nobody, "the migration guessed an author: \(head.owner)")
        #expect(head.createdAt == Self.moment, "the backfill invented a time")
        #expect(
            !head.isSupersedable(by: Attribution.anonymous(deviceID: Self.deviceID)),
            "a claim owned by nobody was supersedable by this device"
        )

        // A tree with no species gains nothing: the backfill writes claims, not rows.
        #expect(try store.current(treeID: unnamed, connection: connection) == nil,
                "an unnamed tree was given an assertion")

        // The community tree itself is untouched.
        let survivor = try #require(try CommunityTreeStore().tree(id: named, connection: connection))
        #expect(survivor.speciesCurrentID == speciesID)
        #expect(survivor.address == "1 Folsom St", "the migration disturbed a column it does not own")

        // The rebuilt `review_flags` kept its rows and its index.
        let flag = try #require(
            try ContributionStore().reviewFlag(id: flagID, connection: connection),
            "the review_flags rebuild lost a row"
        )
        #expect(flag.kind == .appearsDead)
        #expect(flag.status == .open)

        // Replaying the step must be a no-op rather than "table already exists", because a run
        // interrupted between the DDL and the version bump replays.
        try AppSchema.migrations.first(where: { $0.version == 14 })?.migrate(connection)
        #expect(try store.chain(treeID: named, connection: connection).count == 1,
                "replaying v14 backfilled a second assertion")
    }

    /// #125's reservation, from both sides. The column takes the value; the enum does not offer it,
    /// so nothing in the app can write one until #125 says what it means.
    @Test("never_existed is reserved in the column and not yet in the enum")
    func neverExistedIsReservedNotReachable() async throws {
        #expect(ReviewFlag.Kind(rawValue: "never_existed") == nil,
                "the enum gained a case #125 has not defined yet")

        let connection = try SQLiteConnection(path: ":memory:")
        _ = try SchemaMigrator.migrate(AppSchema.migrations, on: connection)
        let stamp = SQLiteTimestamp.string(from: Self.moment)
        try connection.execute("""
            INSERT INTO review_flags (id, tree_uuid, kind, status, created_at, updated_at)
            VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','never_existed','open','\(stamp)','\(stamp)')
            """)
        // And the CHECK still refuses everything outside the vocabulary.
        #expect(throws: SQLiteError.self) {
            try connection.execute("""
                INSERT INTO review_flags (id, tree_uuid, kind, status, created_at, updated_at)
                VALUES ('\(UUID().uuidString)','\(UUID().uuidString)','not_a_kind','open','\(stamp)','\(stamp)')
                """)
        }
    }

    // MARK: - The offer and the boundary agree

    /// A control that offered an act the boundary would refuse is the defect `VisitAddTreeModel.canAdd`
    /// exists to avoid; this suite's version of it, on the correction block.
    @Test("the profile offers exactly the correction the boundary would accept")
    func theOfferMatchesTheBoundary() async throws {
        let store = try await Self.seededStore()
        let namer = LocalAPI(store: store, deviceID: Self.deviceID)
        let (plane, _) = try await Self.twoSpecies(namer)
        let tree = try await Self.addTree(through: namer, at: Self.offshore)

        // No species yet: the claim is offered, the correction is not.
        var presentation = TreeProfilePresentation(profile: try await namer.treeProfile(id: tree.id))
        #expect(presentation.speciesCorrection == .unavailable)
        #expect(presentation.offersSpeciesClaim)

        _ = try await namer.claimSpecies(treeID: tree.id, speciesID: plane.id)
        presentation = TreeProfilePresentation(profile: try await namer.treeProfile(id: tree.id))
        #expect(presentation.speciesCorrection == .correctable, "the namer is not offered the correction")
        #expect(!presentation.offersSpeciesClaim)

        let stranger = LocalAPI(store: store, deviceID: Self.strangerDeviceID)
        presentation = TreeProfilePresentation(profile: try await stranger.treeProfile(id: tree.id))
        #expect(presentation.speciesCorrection == .reportable, "a stranger is offered the correction")

        try await stranger.flagWrongSpecies(treeID: tree.id)
        presentation = TreeProfilePresentation(profile: try await stranger.treeProfile(id: tree.id))
        guard case let .underReview(_, strangerCanResolve) = presentation.speciesCorrection else {
            Issue.record("the open report is not on the screen: \(presentation.speciesCorrection)")
            return
        }
        #expect(!strangerCanResolve, "the raiser was offered the verdict on their own report")

        presentation = TreeProfilePresentation(profile: try await namer.treeProfile(id: tree.id))
        guard case let .underReview(_, namerCanResolve) = presentation.speciesCorrection else {
            Issue.record("the namer does not see the report against their claim")
            return
        }
        #expect(namerCanResolve, "the author of the disputed claim cannot answer the report")
    }
}
