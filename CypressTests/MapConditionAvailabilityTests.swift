import Foundation
import Testing
@testable import Cypress

/// **The two condition chips that cannot match render disabled, say why on their own surface, and
/// enable themselves the moment matching data exists** (task #136, RULINGS R31).
///
/// ── The premise this file corrects, measured rather than inherited ───────────────────────────
/// R31 (and R23, R23.1, E183 §5) say every `seasonal` in the shipped seed is `{}`. The seed this
/// build ships says otherwise: **11 species carry non-empty `bloom_months`**, ~34,000 trees stand
/// under them, and no month from October to December names a blooming tree anywhere. So `In bloom`
/// is not "impossible until the pipeline lands" — it is *seasonal*, and the availability read has
/// to carry the third state (`hasAnyBloomCalendar`) so the disabled chip's sentence does not claim
/// a debt the data has partly paid. `Needs care` is exactly as R31 describes: the seed's only
/// statuses are `alive` (174,425) and `vacant_site` (24,200), and the first declining tree can
/// only arrive through a community observation.
///
/// ── R30's rule, obeyed ────────────────────────────────────────────────────────────────────────
/// No test here asserts that a sentence contains a phrase. What is asserted is agreement between
/// the copy and the state that produces it: two different waits get two different sentences, the
/// out-of-season sentence differs from the debt sentence, and the sentence a chip carries is the
/// one its availability picked.
@Suite("Map condition availability (R31)")
struct MapConditionAvailabilityTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!

    private static func store() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    // MARK: - Against the shipped seed

    /// `Needs care` is unavailable against the shipped seed in every month — `declining` is a
    /// status no city in the seed publishes — and the bloom facts are pinned the way
    /// `MapYearFilterCopy.undatedShareOfSeed` pins coverage: so a re-ingest that moves them fails
    /// the build instead of leaving the chips lying.
    @Test("the shipped seed enables In bloom by season and Needs care never")
    func shippedSeedAvailability() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)

        let july = try await api.mapConditionAvailability(month: 7)
        #expect(!july.needsCare,
                "the seed carries only alive and vacant_site, so Needs care cannot have data")
        #expect(july.hasAnyBloomCalendar,
                "the seed carries bloom calendars for 11 species; R31's '{}' premise is stale")
        #expect(july.inBloom,
                "17,080 seed trees stand under species whose calendars name July")

        let november = try await api.mapConditionAvailability(month: 11)
        #expect(november.hasAnyBloomCalendar, "the calendars do not vanish with the season")
        #expect(!november.inBloom,
                "no species in the seed blooms in November, so the chip must not promise a match")
    }

    /// An implementation with no store says nothing can match — the chips' honest resting state.
    @Test("no seed means nothing can match")
    func noSeedMeansNone() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let availability = try await api.mapConditionAvailability(month: 7)
        #expect(availability == .none)
    }

    // MARK: - The enable flips on the data's arrival (R31: no flag, no release)

    /// **The first community observation standing a declining tree turns `Needs care` on.**
    ///
    /// The injected row is a `tree_status_overrides` entry, which is the one door a device-side
    /// decline has (E124-B): community adds are born `alive`, and the seed is immutable. A
    /// *removal* override is written first and must not flip the chip — the question is "does any
    /// tree need care", not "has moderation ever run".
    @Test("Needs care enables itself on the first declining observation")
    func needsCareFlipsOnInjectedData() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let tree = try await Self.anySeedTree(store: store)

        try await store.queue.write { connection in
            try ContributionStore().setStatusOverride(
                treeID: tree, status: .removed, setBy: nil, at: Date(), connection: connection
            )
        }
        let afterRemoval = try await api.mapConditionAvailability(month: 7)
        #expect(!afterRemoval.needsCare,
                "a removal stood a tree down, not up; Needs care has no data yet")

        try await store.queue.write { connection in
            try ContributionStore().setStatusOverride(
                treeID: tree, status: .declining, setBy: nil, at: Date(), connection: connection
            )
        }
        let afterDecline = try await api.mapConditionAvailability(month: 7)
        #expect(afterDecline.needsCare,
                "a declining tree is standing in the data and the chip still claims none exists")
    }

    /// **`In bloom`'s switch is the calendar meeting the month.** Same store, same calendars, two
    /// months — the injected variable is the month, and the enable follows the data rather than
    /// any flag. (The calendar side of the injection cannot run against the attached seed, which
    /// is read-only by design; `modelPlumbsAvailability` below injects a whole availability at the
    /// model seam instead.)
    @Test("In bloom follows the calendar into and out of season")
    func inBloomFollowsTheMonth() async throws {
        let store = try await Self.store()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        var byMonth: [Int: Bool] = [:]
        for month in [3, 7, 11] {
            byMonth[month] = try await api.mapConditionAvailability(month: month).inBloom
        }
        #expect(byMonth[3] == true && byMonth[7] == true && byMonth[11] == false,
                "the same calendars answered \(byMonth); the month is the only thing that moved")
    }

    // MARK: - The model and the chips

    /// The model publishes what the API answered, and nothing before the read lands. `.none` at
    /// rest is load-bearing: a chip may not look alive on the strength of data nobody checked for.
    @Test("the model rests on none and publishes the store's answer")
    func modelPlumbsAvailability() async throws {
        let injected = MapConditionAvailability(
            needsCare: true, inBloom: false, hasAnyBloomCalendar: true
        )
        let model = await MapModel(api: Answers(availability: injected))
        await #expect(MainActor.run { model.conditionAvailability } == .none,
                      "the chips claim data exists before anything has been read")

        await model.refreshConditionAvailability()
        await #expect(MainActor.run { model.conditionAvailability } == injected)

        // …and what that means for each chip, in one place (`isEnabled`).
        #expect(injected.isEnabled(.needsCare))
        #expect(!injected.isEnabled(.inBloom))
    }

    /// **Two waits, two sentences; three states, three sentences** — asserted as inequalities and
    /// as agreement with the availability that picks them, never as phrases (R30).
    @Test("every disabled state gets its own sentence")
    func reasonsDifferByFact() {
        let noData = MapConditionAvailability.none
        let outOfSeason = MapConditionAvailability(
            needsCare: false, inBloom: false, hasAnyBloomCalendar: true
        )

        let bloomDebt = MapFilterCopy.conditionUnavailableReason(.inBloom, availability: noData)
        let bloomSeason = MapFilterCopy.conditionUnavailableReason(.inBloom, availability: outOfSeason)
        let care = MapFilterCopy.conditionUnavailableReason(.needsCare, availability: noData)

        for sentence in [bloomDebt, bloomSeason, care] {
            #expect(!sentence.isEmpty, "a disabled chip with no reason is a control that just says no")
        }
        #expect(bloomDebt != care,
                "the two chips wait on different things (R31) and say the same sentence")
        #expect(bloomDebt != bloomSeason,
                "calendars-missing and out-of-season are different facts and say the same sentence")
        #expect(care == MapFilterCopy.conditionUnavailableReason(.needsCare, availability: outOfSeason),
                "Needs care's wait has nothing to do with bloom calendars, and its sentence moved")
    }

    // MARK: - Helpers

    private static func anySeedTree(store: CypressStore) async throws -> UUID {
        try await store.queue.read { connection in
            let statement = try connection.cachedStatement("""
            SELECT uuid AS tree_uuid FROM \(SeedDatabase.schemaName).trees
             WHERE deleted_at IS NULL AND status = 'alive'
             ORDER BY id LIMIT 1
            """)
            return try statement.fetchOne { try $0.uuid("tree_uuid") }!
        }
    }

    /// Answers the availability read and nothing else.
    private struct Answers: CypressAPI {
        let availability: MapConditionAvailability

        func mapConditionAvailability(month: Int) async throws -> MapConditionAvailability {
            availability
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }
}
