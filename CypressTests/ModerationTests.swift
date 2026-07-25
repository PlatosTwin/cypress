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

    /// Report the tree as gone, the way screen 05 does: an `appears_removed` observation, queued and
    /// drained, which opens exactly one open removal flag.
    private static func reportRemoved(outbox: OutboxQueue, treeID: UUID) async throws {
        _ = try await outbox.enqueue(.observation(TreeObservation(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: moment,
            status: .appearsRemoved
        )))
        _ = try await outbox.drain()
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
        let reviews = try await api.openRemovalReviews()
        #expect(reviews.count == 1)
        #expect(reviews.first?.treeID == tree.id)

        try await api.confirmRemoval(flagID: reviews[0].flagID)

        // After: the profile is a memorial (what `MemorialModel` gates on), and the queue is empty.
        let profile = try await api.treeProfile(id: tree.id)
        #expect(profile.tree.status == .removed)
        #expect(profile.tree.status.isMemorial)
        #expect(!profile.tree.status.acceptsNewContributions, "a memorial takes no contribution")
        #expect(try await api.openRemovalReviews().isEmpty)
    }

    @Test("the confirmed removal shows up as a memorial pin on the map")
    func confirmedTreeIsAMemorialPin() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let reviews = try await api.openRemovalReviews()
        try await api.confirmRemoval(flagID: reviews[0].flagID)

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
        let flagID = try await api.openRemovalReviews()[0].flagID

        await #expect(throws: APIError.forbidden) {
            try await api.confirmRemoval(flagID: flagID)
        }
        #expect(try await api.treeProfile(id: tree.id).tree.status == .alive)
        #expect(try await api.openRemovalReviews().count == 1, "a forbidden confirm must not close the flag")
    }

    @Test("a steward cannot confirm either — only a moderator or coordinator may")
    func stewardIsForbidden() async throws {
        let (api, outbox) = try await Self.harness(role: .steward)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openRemovalReviews()[0].flagID

        await #expect(throws: APIError.forbidden) {
            try await api.confirmRemoval(flagID: flagID)
        }
    }

    @Test("a second confirmation is a conflict and moves nothing")
    func doubleConfirmIsConflict() async throws {
        let (api, outbox) = try await Self.harness(role: .coordinator)
        let tree = try await Self.makeTree(api: api)
        try await Self.reportRemoved(outbox: outbox, treeID: tree.id)
        let flagID = try await api.openRemovalReviews()[0].flagID

        try await api.confirmRemoval(flagID: flagID)
        await #expect(throws: APIError.conflict) {
            try await api.confirmRemoval(flagID: flagID)
        }
        // Still removed exactly once.
        #expect(try await api.treeProfile(id: tree.id).tree.status == .removed)
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
