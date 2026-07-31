import Foundation
import Testing
@testable import Cypress

/// The local moderation route (ERRATA **E124-B**), end to end at the data layer: a "Removed?" check-in
/// opens an `appears_removed` review flag, a lead confirms it, and the tree becomes a memorial —
/// which is the whole of what makes screen 19 reachable from real data.
///
/// The flag is opened the *real* way in every test here — an observation with
/// `ObservationStatus.appearsRemoved` (screen 05's "Removed?" segment) flowing through the outbox and
/// opening the flag on apply — so this suite exercises the actual chain a person walks, not a
/// hand-inserted flag.
@MainActor
@Suite("Local moderation → memorial")
struct ModerationTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E1")!
    private static let moment = Date(timeIntervalSince1970: 1_780_000_000)

    /// A community add, which `requireTree` accepts with no seed present.
    private static func makeTree(api: LocalAPI) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
            photoLocalPath: "/tmp/cypress-mod-test.jpg",
            attribution: .anonymous(deviceID: deviceID)
        ))
    }

    /// Report the tree, the way screen 05 does: an observation carrying one of the two flagging
    /// statuses, queued and drained, which opens exactly one open flag of the matching kind.
    private static func report(
        _ status: ObservationStatus,
        outbox: OutboxQueue,
        treeID: UUID
    ) async throws {
        _ = try await outbox.enqueue(.observation(TreeObservation(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: moment,
            status: status
        )))
        _ = try await outbox.drain()
    }

    private static func reportRemoved(outbox: OutboxQueue, treeID: UUID) async throws {
        try await report(.appearsRemoved, outbox: outbox, treeID: treeID)
    }

    /// The two statuses screen 05 can report that open a flag, paired with the status a confirm must
    /// write and whether that status leaves the tree contributable.
    ///
    /// Driven off `ObservationStatus.opensReviewFlag` rather than a hand-written list, so a third
    /// flagging status added to the card cannot slip past this suite (ERRATA E170).
    private static var flaggingStatuses: [ObservationStatus] {
        ObservationStatus.allCases.filter(\.opensReviewFlag)
    }

    private static func harness(role: UserRole) async throws -> (LocalAPI, OutboxQueue) {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: deviceID, role: role)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        return (api, outbox)
    }

    // MARK: - The loop

    @Test("a lead confirms a removal, the flag closes and the tree becomes a memorial")
    func confirmMakesMemorial() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)

        // Before: alive, and one open review naming this tree.
        #expect(try await api.treeProfile(id: tree.id).tree.status == .alive)
        let reviews = try await api.openReviews()
        #expect(reviews.count == 1)
        #expect(reviews.first?.treeID == tree.id)

        try await api.confirmReview(flagID: reviews[0].flagID)

        // After: the profile is a memorial (what `MemorialModel` gates on), and the queue is empty.
        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.tree.status == .removed)
        #expect(profile.tree.status.isMemorial)
        #expect(!profile.tree.status.acceptsNewContributions, "a memorial takes no contribution")
        #expect(try await api.openReviews().isEmpty)
    }

    @Test("the confirmed removal shows up as a memorial pin on the map")
    func confirmedTreeIsAMemorialPin() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let reviews = try await api.openReviews()
        try await api.confirmReview(flagID: reviews[0].flagID)

        // A viewport around the tree; community adds are merged into `mapContent`'s pins.
        let viewport = MapViewport(
            bounds: BoundingBox(
                minLatitude: 37.76, maxLatitude: 37.78,
                minLongitude: -122.45, maxLongitude: -122.43
            ),
            zoom: 17
        )
        let content = try await api.mapContent(in: viewport)
        guard case let .pins(pins) = content else {
            Issue.record("expected pins at zoom 17, got clusters")
            return
        }
        let pin = pins.first { $0.id == tree.id }
        #expect(pin?.status == .removed, "the map still called a confirmed-removed tree alive")
    }

    // MARK: - The gate

    @Test("a member cannot confirm a removal, and the tree stays alive")
    func memberIsForbidden() async throws {
        let (api, outbox) = try await Self.harness(role: .member)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        await #expect(throws: APIError.forbidden) {
            try await api.confirmReview(flagID: flagID)
        }
        #expect(try await api.treeProfile(id: tree.id).tree.status == .alive)
        #expect(try await api.openReviews().count == 1, "a forbidden confirm must not close the flag")
    }

    @Test("a steward cannot confirm either — only a moderator or coordinator may")
    func stewardIsForbidden() async throws {
        let (api, outbox) = try await Self.harness(role: .steward)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        await #expect(throws: APIError.forbidden) {
            try await api.confirmReview(flagID: flagID)
        }
    }

    @Test("a second confirmation is a conflict and moves nothing")
    func doubleConfirmIsConflict() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        try await api.confirmReview(flagID: flagID)
        await #expect(throws: APIError.conflict) {
            try await api.confirmReview(flagID: flagID)
        }
        // Still removed exactly once.
        #expect(try await api.treeProfile(id: tree.id).tree.status == .removed)
    }

    // MARK: - Both kinds (ERRATA E170)

    /// **The defect, stated as a test.** Before E170 this failed at the first `#expect`: the flag was
    /// written by `apply`, and `openReviews` — then `openRemovalReviews`, with `.appearsRemoved`
    /// hard-coded in its body — could not see it. Screen 05 raised a report that reached no surface.
    @Test("both flagging statuses reach the lead's queue", arguments: ModerationTests.flaggingStatuses)
    func bothKindsReachTheQueue(_ status: ObservationStatus) async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.report(status, outbox: outbox, treeID: tree.id)

        let reviews = try await api.openReviews()
        #expect(reviews.count == 1, "\(status.rawValue) opened a flag no queue could see")
        #expect(reviews.first?.treeID == tree.id)
        #expect(reviews.first?.kind == status.reviewFlagKind, "the row must carry the kind it came from")
    }

    /// And confirming each writes the status that kind resolves to — the `.deadReported` half is what
    /// `confirmRemoval`'s `guard flag.kind == .appearsRemoved` made unreachable.
    @Test("a confirm writes the status the flag's kind resolves to", arguments: ModerationTests.flaggingStatuses)
    func confirmWritesTheKindsStatus(_ status: ObservationStatus) async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.report(status, outbox: outbox, treeID: tree.id)
        let item = try await api.openReviews()[0]

        try await api.confirmReview(flagID: item.flagID)

        let expected = try #require(status.reviewFlagKind?.confirmedStatus)
        #expect(try await api.treeProfile(id: tree.id).tree.status == expected)
        #expect(try await api.openReviews().isEmpty, "a confirmed flag leaves the queue")
    }

    /// Ruling (2): a dead tree is still there. This is the assertion that stops somebody "tidying up"
    /// by routing `deadReported` to screen 19 — which would take away the REPORT button on the one
    /// status where a hazard report matters most.
    @Test("a confirmed-dead tree keeps its profile and its actions — it is not a memorial")
    func confirmedDeadIsNotAMemorial() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.report(.appearsDead, outbox: outbox, treeID: tree.id)
        try await api.confirmReview(flagID: api.openReviews()[0].flagID)

        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.tree.status == .deadReported)
        #expect(!profile.tree.status.isMemorial, "a standing dead tree has not been removed")
        #expect(profile.tree.status.acceptsNewContributions, "a dead street tree is a hazard worth reporting")
        #expect(TreeProfileDestination(record: profile.tree) == .profile, "it keeps screen 03")

        // And the profile says so, rather than rendering as an ordinary live tree.
        let presentation = TreeProfilePresentation(profile: profile)
        #expect(presentation.deadNotice != nil)
        #expect(presentation.quadActions.contains(.report), "REPORT is the point of keeping the profile")
        #expect(presentation.quadActions.contains(.care))
    }

    /// A confirmed removal still becomes a memorial. The generalisation must not have flattened the
    /// two outcomes into one.
    @Test("the two confirmed statuses stay different — removal is still a memorial")
    func theTwoOutcomesDiffer() async throws {
        #expect(ReviewFlag.Kind.appearsRemoved.confirmedStatus == .removed)
        #expect(ReviewFlag.Kind.appearsDead.confirmedStatus == .deadReported)
        #expect(TreeStatus.removed.isMemorial)
        #expect(!TreeStatus.deadReported.isMemorial)
        #expect(!TreeStatus.removed.acceptsNewContributions)
        #expect(TreeStatus.deadReported.acceptsNewContributions)
    }

    /// A kind that is not a status claim must still be refused, and must never reach the queue.
    @Test("a non-status flag is neither queued nor confirmable")
    func nonStatusKindsAreRefused() async throws {
        let (api, _) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        let flagID = try await api.debugSeedReview(treeID: tree.id, kind: .wrongSpecies)

        #expect(try await api.openReviews().isEmpty, "wrong_species is not a status review")
        await #expect(throws: APIError.validationFailed) { try await api.confirmReview(flagID: flagID) }
        await #expect(throws: APIError.validationFailed) { try await api.dismissReview(flagID: flagID) }
        #expect(try await api.treeProfile(id: tree.id).tree.status == .alive)
    }

    @Test("a confirmed-dead tree draws a grey pin that does not call itself a memorial")
    func deadPinDoesNotSayMemorial() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.report(.appearsDead, outbox: outbox, treeID: tree.id)
        try await api.confirmReview(flagID: api.openReviews()[0].flagID)

        let viewport = MapViewport(
            bounds: BoundingBox(
                minLatitude: 37.76, maxLatitude: 37.78,
                minLongitude: -122.45, maxLongitude: -122.43
            ),
            zoom: 17
        )
        guard case let .pins(pins) = try await api.mapContent(in: viewport) else {
            Issue.record("expected pins at zoom 17, got clusters")
            return
        }
        let pin = try #require(pins.first { $0.id == tree.id })
        #expect(pin.status == .deadReported, "the map still called a confirmed-dead tree alive")
        let spoken = MapPinKind.accessibilityLabel(for: pin)
        #expect(!spoken.lowercased().contains("memorial"), "a standing dead tree is not a memorial: \(spoken)")
        #expect(!spoken.lowercased().contains("removed"), "it has not been removed: \(spoken)")
        #expect(spoken == MapPinCopy.deadReportedLabel)
    }

    // MARK: - Dismiss, the verb the queue never had (ERRATA E170)

    @Test("a lead dismisses a report: the flag closes and the tree does not move", arguments: ModerationTests.flaggingStatuses)
    func dismissClosesWithoutMoving(_ status: ObservationStatus) async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.report(status, outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        try await api.dismissReview(flagID: flagID)

        #expect(try await api.openReviews().isEmpty, "a dismissed flag leaves the queue")
        #expect(try await api.treeProfile(id: tree.id).tree.status == .alive, "a dismissal moves nothing")
        // And it is genuinely `dismissed`, not merely absent — the status the model has carried
        // unwritten since it was declared.
        let flag = try #require(try await api.debugReviewFlag(id: flagID))
        #expect(flag.status == .dismissed)
    }

    @Test("a dismissal after a confirm is a conflict")
    func dismissAfterConfirmIsConflict() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        try await api.confirmReview(flagID: flagID)
        await #expect(throws: APIError.conflict) { try await api.dismissReview(flagID: flagID) }
        #expect(try await api.treeProfile(id: tree.id).tree.status == .removed, "still removed")
    }

    @Test("a second dismissal is a conflict")
    func doubleDismissIsConflict() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        try await api.dismissReview(flagID: flagID)
        await #expect(throws: APIError.conflict) { try await api.dismissReview(flagID: flagID) }
    }

    // MARK: - The gate, over both kinds and both verbs (ERRATA E170)

    /// The ruling's own words: a member or steward must get `.forbidden` **on the write itself**, not
    /// merely a hidden button. `ModerationTests` proved that shape for one kind and one verb; four
    /// combinations of the two roles that must be refused, over both kinds, over both verbs.
    @Test(
        "neither a member nor a steward can resolve a review, either way, either kind",
        arguments: [UserRole.member, .steward], ModerationTests.flaggingStatuses
    )
    func nonLeadsAreForbidden(_ role: UserRole, _ status: ObservationStatus) async throws {
        let (api, outbox) = try await Self.harness(role: role)
        let tree = try await Self.makeTree(api: api)
        try await Self.report(status, outbox: outbox, treeID: tree.id)
        let flagID = try await api.openReviews()[0].flagID

        await #expect(throws: APIError.forbidden) { try await api.confirmReview(flagID: flagID) }
        await #expect(throws: APIError.forbidden) { try await api.dismissReview(flagID: flagID) }

        #expect(try await api.treeProfile(id: tree.id).tree.status == .alive)
        #expect(try await api.openReviews().count == 1, "a forbidden write must not close the flag")
    }

    /// The `ModerationModel` half: the queue a lead's You tab actually draws holds both kinds, and its
    /// two verbs reach the two writes.
    @Test("the You tab's model carries both kinds and both verbs")
    func modelCarriesBothKinds() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let dead = try await Self.makeTree(api: api)
        try await Self.report(.appearsDead, outbox: outbox, treeID: dead.id)

        let model = ModerationModel(api: api)
        await model.load()
        #expect(model.canModerate)
        let item = try #require(model.items.first { $0.treeID == dead.id })
        #expect(item.kind == .appearsDead)
        #expect(ModerationCopy.confirmAction(kind: item.kind) == "Confirm dead")

        await model.confirm(item)
        #expect(model.items.isEmpty)
        #expect(try await api.treeProfile(id: dead.id).tree.status == .deadReported)
    }

    // MARK: - The role

    @Test("promoting a member to lead persists across a relaunch")
    func rolePersists() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        #expect(await api.userRole == .member, "a fresh account is a member")

        try await api.setRole(.coordinator)
        #expect(await api.userRole == .coordinator)

        // A relaunch reads the role back from app_state, like the user id.
        let reread = (try await store.appState(.currentUserRole)).flatMap(UserRole.init(rawValue:))
        #expect(reread == .coordinator)
    }
}
