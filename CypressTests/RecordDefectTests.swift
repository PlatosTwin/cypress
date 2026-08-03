import Foundation
import Testing
@testable import Cypress

/// "This tree does not exist at all" — task **#125**, the kind `RULINGS R46` decided and AppSchema
/// v14 reserved a CHECK value for.
///
/// The rule this suite holds down is the one the ticket said would be easiest to break: **confirming
/// a `never_existed` report must never move `trees.status`.** `TreeStatus.vacantSite` exists and
/// reads like the truthful confirmed state, and pointing `confirmedStatus` at it would make the kind
/// resolvable in one line — and would enroll record defects in the lead's *status* queue, where a
/// confirmation writes `tree_status_overrides`. That is ERRATA **E170**'s defect in its worse form:
/// the queue would look right while the trees moved. So the seam is asserted as a property, and the
/// absence of a status row is asserted after a real confirmation rather than reasoned about.
///
/// Every load-bearing assertion reads the database or the boundary's own refusal, never the object
/// the test just configured.
@Suite("Record defect · never existed")
struct RecordDefectTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-000000000125")!

    /// West of Ocean Beach: the seed is the city's *street*-tree inventory, so nothing is inside the
    /// 10 m dedupe radius and the only records a test contends with are its own
    /// (`SpeciesCorrectionTests.offshore`'s argument).
    private static let offshore = Coordinate(latitude: 37.7605, longitude: -122.5405)

    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func member(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, userID: nil, role: .member)
    }

    private static func lead(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, userID: nil, role: .moderator)
    }

    private static func addTree(
        through api: LocalAPI,
        at spot: Coordinate = offshore
    ) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: spot,
            speciesID: nil,
            photoLocalPath: "/tmp/cypress-record-defect.jpg",
            attribution: .anonymous(deviceID: deviceID)
        ))
    }

    /// `community_trees.deleted_at` for one row, read straight out of SQL rather than through a
    /// method that filters it — the whole question is whether the column was written.
    private static func withdrawnAt(_ id: UUID, in store: CypressStore) async throws -> Date? {
        try await store.queue.read { connection -> Date? in
            let statement = try connection.prepare(
                "SELECT deleted_at FROM community_trees WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind([":id": id.uuidString])
            return try statement.fetchOne { try $0.dateIfPresent("deleted_at") } ?? nil
        }
    }

    /// Whether `tree_status_overrides` holds anything at all for this tree. The assertion this
    /// suite exists for.
    private static func statusOverride(_ id: UUID, in store: CypressStore) async throws -> TreeStatus? {
        try await store.queue.read { connection in
            try ContributionStore().statusOverrides(connection: connection)[id]
        }
    }

    private static func openFlag(on treeID: UUID, in store: CypressStore) async throws -> ReviewFlag? {
        try await store.queue.read { connection in
            try ContributionStore()
                .openReviewFlags(kinds: ReviewFlag.Kind.recordReviewKinds, connection: connection)
                .first { $0.treeID == treeID }
        }
    }

    // MARK: - The seam (ERRATA E170, RULINGS R45's shape)

    /// The property the ticket named as the one thing that must not be done to make this resolvable.
    ///
    /// Asserted as a property rather than as a list, so a later widening of `confirmedStatus` fails
    /// here rather than passing a test that only checked a queue was non-empty.
    @Test("a record defect resolves through its own seam and never through a status")
    func theSeamsStayApart() {
        #expect(ReviewFlag.Kind.neverExisted.resolution == .recordWithdrawal)
        #expect(ReviewFlag.Kind.neverExisted.confirmedStatus == nil,
                "confirming never_existed would move trees.status")

        let record = Set(ReviewFlag.Kind.recordReviewKinds)
        let status = Set(ReviewFlag.Kind.statusReviewKinds)
        let species = Set(ReviewFlag.Kind.speciesReviewKinds)
        #expect(record.contains(.neverExisted), "the record seam serves no record kind")
        #expect(record.isDisjoint(with: status),
                "a kind is served by both the record and the status seam: \(record.intersection(status))")
        #expect(record.isDisjoint(with: species),
                "a kind is served by both the record and the species seam: \(record.intersection(species))")
        for kind in record {
            #expect(kind.confirmedStatus == nil, "\(kind.rawValue) would move trees.status on confirm")
        }
    }

    // MARK: - The loop

    /// The whole of #125 end to end, read back out of both tables and out of the boundary.
    @Test("a reported record is withdrawn on confirmation, and no status is written")
    func theLoopCloses() async throws {
        let store = try await Self.seededStore()
        let reporter = Self.member(store)
        let tree = try await Self.addTree(through: reporter)

        // The offer before anything is reported.
        let before = try await reporter.treeProfile(id: tree.id)
        #expect(before.recordDefect == .reportable)

        try await reporter.flagNeverExisted(treeID: tree.id)

        let flag = try #require(try await Self.openFlag(on: tree.id, in: store),
                                "no open never_existed flag after the report")
        #expect(flag.kind == .neverExisted)

        // The record has not moved: reporting is a disagreement, not a decision.
        #expect(try await Self.withdrawnAt(tree.id, in: store) == nil,
                "the report withdrew the record on its own")
        let underReview = try await reporter.treeProfile(id: tree.id)
        #expect(underReview.recordDefect == .underReview(flagID: flag.id, canResolve: false),
                "a member was offered the resolve controls")

        // A lead answers it.
        let lead = Self.lead(store)
        let leadsView = try await lead.treeProfile(id: tree.id)
        #expect(leadsView.recordDefect == .underReview(flagID: flag.id, canResolve: true))
        try await lead.withdrawRecord(flagID: flag.id)

        let resolved = try #require(try await lead.debugReviewFlag(id: flag.id))
        #expect(resolved.status == .confirmed)
        #expect(try await Self.withdrawnAt(tree.id, in: store) != nil,
                "the confirmation did not withdraw the record")

        // The assertion this suite exists for.
        #expect(try await Self.statusOverride(tree.id, in: store) == nil,
                "confirming never_existed wrote a status override")

        // And the record is no longer a tree anywhere a reader can reach.
        await #expect(throws: APIError.notFound) { _ = try await lead.treeProfile(id: tree.id) }
    }

    /// The pin goes with it. Read through the map's own query rather than inferred from the column,
    /// because "the row says withdrawn" and "the map stopped drawing it" are two facts and this
    /// project has shipped the first without the second.
    @Test("a withdrawn record leaves the map")
    func theWithdrawnRecordLeavesTheMap() async throws {
        let store = try await Self.seededStore()
        let lead = Self.lead(store)
        let tree = try await Self.addTree(through: lead)
        let box = BoundingBox(around: Self.offshore, radiusM: 200)
        func drawn() async throws -> Bool {
            try await store.queue.read { connection in
                try CommunityTreeStore().inBounds(box, limit: nil, connection: connection)
                    .contains { $0.id == tree.id }
            }
        }
        #expect(try await drawn(), "the added record was never on the map to begin with")

        try await lead.flagNeverExisted(treeID: tree.id)
        let flag = try #require(try await Self.openFlag(on: tree.id, in: store))
        try await lead.withdrawRecord(flagID: flag.id)

        #expect(try await drawn() == false, "the withdrawn record is still drawn")
    }

    /// The second verb (ERRATA E170: a queue whose only verb is "agree" is not a review).
    @Test("keeping the record answers the report and changes nothing")
    func dismissingLeavesTheRecord() async throws {
        let store = try await Self.seededStore()
        let lead = Self.lead(store)
        let tree = try await Self.addTree(through: lead)
        try await lead.flagNeverExisted(treeID: tree.id)
        let flag = try #require(try await Self.openFlag(on: tree.id, in: store))

        try await lead.dismissRecordReview(flagID: flag.id)

        let answered = try #require(try await lead.debugReviewFlag(id: flag.id))
        #expect(answered.status == .dismissed)
        #expect(try await Self.withdrawnAt(tree.id, in: store) == nil, "a dismissal withdrew the record")
        #expect(try await Self.statusOverride(tree.id, in: store) == nil)
        // Still a tree, and reportable again now that nothing is open.
        let profile = try await lead.treeProfile(id: tree.id)
        #expect(profile.recordDefect == .reportable)
    }

    // MARK: - The refusals

    /// A city row cannot be withdrawn by this app, so the report is refused rather than raised into
    /// a queue nothing can answer — `RULINGS R45`'s refusal of `wrong_species` on a city row, for
    /// the same reason.
    @Test("a city record cannot be reported as never existing")
    func aCityRecordIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = Self.member(store)
        let seedTree = try #require(
            try await api.treesNear(Coordinate(latitude: 37.7749, longitude: -122.4194), radiusM: 400, limit: 1).first,
            "the seed answered no tree near the Civic Center"
        )
        await #expect(throws: APIError.forbidden) {
            try await api.flagNeverExisted(treeID: seedTree.id)
        }
        // And the profile does not offer the control it would refuse.
        let profile = try await api.treeProfile(id: seedTree.id)
        #expect(profile.recordDefect == .unavailable)
    }

    @Test("a second report on one record is refused")
    func aSecondReportIsRefused() async throws {
        let store = try await Self.seededStore()
        let api = Self.member(store)
        let tree = try await Self.addTree(through: api)
        try await api.flagNeverExisted(treeID: tree.id)
        await #expect(throws: APIError.conflict) {
            try await api.flagNeverExisted(treeID: tree.id)
        }
    }

    /// The role gate is on the write, so a surface drawn in error cannot withdraw a record.
    @Test("only a lead may answer a record report", arguments: [UserRole.member, .steward])
    func onlyALeadMayResolve(_ role: UserRole) async throws {
        let store = try await Self.seededStore()
        let reporter = Self.member(store)
        let tree = try await Self.addTree(through: reporter)
        try await reporter.flagNeverExisted(treeID: tree.id)
        let flag = try #require(try await Self.openFlag(on: tree.id, in: store))

        let notALead = LocalAPI(store: store, deviceID: Self.deviceID, userID: nil, role: role)
        await #expect(throws: APIError.forbidden) { try await notALead.withdrawRecord(flagID: flag.id) }
        await #expect(throws: APIError.forbidden) { try await notALead.dismissRecordReview(flagID: flag.id) }

        // Both refusals left the record and the report exactly as they were.
        #expect(try await Self.withdrawnAt(tree.id, in: store) == nil)
        let still = try #require(try await reporter.debugReviewFlag(id: flag.id))
        #expect(still.status == .open)
    }

    /// The status queue's two verbs will not touch a record defect, and the record does not move —
    /// the boundary half of `theSeamsStayApart`.
    @Test("the status queue can neither see nor resolve a record report")
    func theStatusQueueRefusesARecordReport() async throws {
        let store = try await Self.seededStore()
        let lead = Self.lead(store)
        let tree = try await Self.addTree(through: lead)
        try await lead.flagNeverExisted(treeID: tree.id)
        let flag = try #require(try await Self.openFlag(on: tree.id, in: store))

        let queue = try await lead.openReviews()
        #expect(queue.contains { $0.flagID == flag.id } == false,
                "a record defect reached the lead's status queue")

        await #expect(throws: APIError.validationFailed) { try await lead.confirmReview(flagID: flag.id) }
        await #expect(throws: APIError.validationFailed) { try await lead.dismissReview(flagID: flag.id) }
        #expect(try await Self.statusOverride(tree.id, in: store) == nil,
                "the status queue moved a tree on a record report")
        #expect(try await Self.withdrawnAt(tree.id, in: store) == nil)
    }

    /// And the record seam will not touch a status report, which is the same guard from the other
    /// side. Without it, `withdrawRecord` would be one missing `guard` away from soft-deleting a
    /// tree somebody reported as merely dead.
    @Test("the record seam refuses a status report")
    func theRecordSeamRefusesAStatusReport() async throws {
        let store = try await Self.seededStore()
        let lead = Self.lead(store)
        let tree = try await Self.addTree(through: lead)
        let flagID = try await lead.debugSeedReview(treeID: tree.id, kind: .appearsDead)

        await #expect(throws: APIError.validationFailed) { try await lead.withdrawRecord(flagID: flagID) }
        await #expect(throws: APIError.validationFailed) { try await lead.dismissRecordReview(flagID: flagID) }
        #expect(try await Self.withdrawnAt(tree.id, in: store) == nil,
                "a dead-tree report withdrew the record")
    }

    // MARK: - Where the report actually goes

    /// The copy, asserted as properties of the words.
    ///
    /// **Two claims are forbidden here, not one.** DECISIONS §3 constraint 3 (permanent under D16(a))
    /// forbids saying the city was told. The second is this round's: there is no contribution sync in
    /// beta — the outbox drains through `APIOutboxTransport` into `LocalAPI`, which writes this
    /// phone's own tables — so a sentence promising another reader names a destination the report
    /// does not reach, which is the banned claim with a different noun. E126 is why the notice says
    /// where the report *does* stay rather than falling silent about it.
    @Test("the report notice claims neither the city nor another reader")
    func theNoticeClaimsNoDestinationItCannotReach() {
        let notice = TreeProfileCopy.neverExistedNotice.lowercased()
        #expect(notice.contains("this phone"), "the notice does not say where the report stays")
        #expect(notice.contains("the city is not notified"), "the notice does not state the city limit")
        // The forbidden claim, as a substring — which is why the sentence above has to be the
        // sanctioned negation rather than "nothing is sent to the city", whose own words contain it.
        #expect(!notice.contains("sent to the city"))
        #expect(!notice.contains("notify the city"))
        #expect(!notice.contains("311"))
        #expect(!notice.contains("community reviewer"),
                "the notice promises a reader beta cannot deliver it to")
        #expect(!notice.contains("other contributors"))
    }

    /// The withdrawal is described before it is done, and described accurately: the row is kept.
    @Test("the withdrawal notice does not promise an erasure")
    func theWithdrawalNoticeDoesNotPromiseErasure() {
        let notice = TreeProfileCopy.withdrawRecordNotice.lowercased()
        #expect(notice.contains("map"), "the notice does not say the record leaves the map")
        #expect(!notice.contains("delete"), "the notice promises an erasure that does not happen")
        #expect(!notice.contains("permanently"))
        // The verb must not borrow `TreeStatus.removed`'s word — R46 in the label.
        #expect(!TreeProfileCopy.withdrawRecordAction.lowercased().contains("remove"))
        #expect(!TreeProfileCopy.reportNeverExistedAction.lowercased().contains("missing"))
    }
}
