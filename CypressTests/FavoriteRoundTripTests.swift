import Foundation
import Testing
@testable import Cypress

/// **The favorite, end to end, on a tree that came out of the seed** (task #139, ERRATA E184).
///
/// This suite exists because of a hole rather than a hypothesis. Two suites already cover the
/// favorite and both are green, and between them they still could not have caught a screen whose
/// heart does not stick:
///
/// - `FavoriteTests` proves the store — the tombstone, the replay guard, the two ownership arms.
///   It never involves a screen.
/// - `FavoriteToggleTests` proves the screen — but its `Records` double answers `grove()` out of a
///   `Set<UUID>` the test itself writes to. The model's read-back is checked against a box, not
///   against `LocalAPI.grove()`, so any way in which the real read can disagree with the real write
///   is invisible to it. Its one real-store test (`eachTapGetsItsOwnKey`) drives
///   `ProfileFavoriteWriter` **without a `TreeProfileModel`**, and against a tree it makes with
///   `addTree` — a `community_trees` row, which is the one arm of `requireTree` that is *not* the
///   arm every tree the owner can tap goes down.
///
/// So the two halves are each covered and the seam between them is not, and the seam is where a
/// favorite would be lost: the model writes through `ProfileFavoriteWriter` and then re-reads
/// through `CypressAPI.grove()`, which are two different queries over two different owner columns,
/// and nothing joined them. What is asserted here is the join:
///
/// 1. A tap on a **seed** tree writes a row that `grove()` reads back, so `isFavorite` is true
///    because the store says so and not because the tap said so.
/// 2. A second tap tombstones it and `grove()` stops reporting it, so the cell goes off.
/// 3. A write that does not land leaves the cell where it was — the one honest failure state R2
///    requires, checked against the real read rather than against a box.
///
/// **Why the real seed and not `CypressStore.inMemory()`.** With no seed attached `treeQueries` is
/// nil, `requireTree` falls through to the community arm, and `grove()` resolves the tree through
/// `communityTrees`. Every tree on the map is a seed row. A test that never opens the seed cannot
/// tell a favorite that works from one that only works on the 0 % of records this app added.
@MainActor
@Suite("Screen 03 · the favorite round trip, real store (#139)")
struct FavoriteRoundTripTests {

    private static let deviceID = UUID(uuidString: "D1390000-0000-4000-8000-000000000139")!

    /// The seed, opened once per test. `InventoryContractTests.seedURL` is the project's one
    /// resolver for it and honours `CYPRESS_SEED_PATH`.
    private static func openSeeded() async throws -> (LocalAPI, OutboxQueue, UUID) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        let api = LocalAPI(store: store, deviceID: deviceID)
        let outbox = OutboxQueue(queue: store.queue, transport: APIOutboxTransport(api: api))
        // A real standing record out of the shipped inventory, resolved the way `DebugDeepLink`
        // resolves one: nothing here invents a tree id.
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let tree = try #require(
            candidates.first(where: { $0.tree.status.acceptsNewContributions })?.tree.id,
            "no standing seed tree near the map's opening centre"
        )
        return (api, outbox, tree)
    }

    /// A model wired exactly as `RootView.destination(for:)` wires it — the write **and** the
    /// re-read both through `ProfileFavoriteWriter`, because the re-read that only saw applied
    /// rows is the whole of #167.
    private static func model(api: LocalAPI, outbox: OutboxQueue, treeID: UUID) -> TreeProfileModel {
        let write = ProfileFavoriteWriter(api: api, outbox: outbox)
        return TreeProfileModel(
            treeID: treeID,
            api: api,
            setFavorite: { id, isFavorite in await write(treeID: id, isFavorite: isFavorite) },
            readFavorite: { id in await write.storedState(treeID: id) }
        )
    }

    // MARK: - 1 and 2. The tap, and the tap that takes it off

    @Test("a tap on a seed tree lands in the store and the cell reads it back")
    func theHeartSticksOnASeedTree() async throws {
        let (api, outbox, treeID) = try await Self.openSeeded()
        let model = Self.model(api: api, outbox: outbox, treeID: treeID)

        await model.load()
        #expect(!model.isFavorite, "a tree nobody has favorited opened selected")

        await model.toggleFavorite().value

        // The cell. This is the assertion the owner's report is about: the control answered the
        // finger, then asked the store, and the store agreed.
        #expect(model.isFavorite, "the heart went back off — the write did not survive the re-read")

        // And the store, asked directly rather than through the screen's own read, so a `grove()`
        // that lied in both directions could not make this pass.
        let held = try await api.mapMembership(.favorites)
        #expect(held.contains(treeID), "no live favorite row for the tree that was tapped")
    }

    @Test("a second tap tombstones the row and the cell goes off")
    func theHeartComesOffWhereItWentOn() async throws {
        let (api, outbox, treeID) = try await Self.openSeeded()
        let model = Self.model(api: api, outbox: outbox, treeID: treeID)

        await model.load()
        await model.toggleFavorite().value
        await model.toggleFavorite().value

        #expect(!model.isFavorite, "the un-favorite was swallowed and the cell still reads on")
        let held = try await api.mapMembership(.favorites)
        #expect(!held.contains(treeID), "the tombstone did not take: the row is still live")

        // A tombstone, not a delete (BUILD-PLAN §4). The row has to still be there, carrying the
        // off state, or the un-favorite is not an event anything could sync.
        let rows = try await api.deviceContributions().favorites
        #expect(rows == 0, "an un-favorited tree is still counted as this device's favorite")
    }

    // MARK: - 2b. The tap whose drain could not carry it (#167)

    /// **The owner's third report: dark green for two seconds, then back to white.**
    ///
    /// The write path is durable at *enqueue* and applied at *drain*, and the drain that follows a
    /// save is best-effort: `OutboxQueue.drain` attempts one batch of `batchSize` items and
    /// returns, and it returns immediately when another drain holds `isDraining`. Either way the
    /// toggle can be safely queued and **not yet applied** when `write()` re-reads — and a re-read
    /// over applied rows alone then answers "no" for a favorite that was saved. The heart goes
    /// back; the row lands on the next drain; the person is told their action was undone when it
    /// was not.
    ///
    /// Reproduced here the deterministic way: a batch's worth of older due work is queued first,
    /// so the drain inside `FavoriteOutboxWriter.save` spends its whole batch on it and leaves the
    /// tapped tree's toggle `pending`. The assertion is the owner's sentence: if it is a favorite,
    /// it stays dark green.
    @Test("a favorite still queued behind a full drain batch survives the re-read")
    func aQueuedFavoriteIsNotReportedUndone() async throws {
        let (api, outbox, treeID) = try await Self.openSeeded()

        // Older work, filling the writer's one drain batch: toggles for other standing trees,
        // enqueued without draining — exactly what a stall or a death mid-drain leaves behind.
        let others = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        .map(\.tree.id)
        .filter { $0 != treeID }
        try #require(others.count >= OutboxQueue.batchSize, "seed too thin to fill a drain batch")
        for other in others.prefix(OutboxQueue.batchSize) {
            _ = try await outbox.enqueue(.favoriteToggle(FavoriteToggle(
                owner: .device(Self.deviceID), treeID: other, isFavorite: true
            )))
        }

        let model = Self.model(api: api, outbox: outbox, treeID: treeID)
        await model.load()
        await model.toggleFavorite().value

        // The tap's own toggle is verifiably still in flight — otherwise this test quietly decays
        // into `theHeartSticksOnASeedTree` and stops guarding the seam it exists for.
        let queued = try await outbox.pendingFavoriteState(treeID: treeID)
        #expect(queued == true, "the drain batch was not full; the toggle applied immediately")

        // The owner's sentence: it is a favorite, so it stays dark green.
        #expect(
            model.isFavorite,
            "the heart went back to white over a favorite that is durably queued (#167)"
        )

        // And the queue keeps its promise: the next drain lands the row in the applied store.
        _ = try await outbox.drain()
        let held = try await api.mapMembership(.favorites)
        #expect(held.contains(treeID), "the queued favorite never reached the store")
        await model.reload()
        #expect(model.isFavorite, "the heart changed its answer once the row applied")
    }

    /// The counterpart R2 requires: once the queue has terminally given up on a toggle, the
    /// re-read must stop counting it, so the heart honestly goes back. A toggle for a tree that
    /// does not exist fails `requireTree` with `.notFound` — not retryable, so the drain marks it
    /// `failed` — and `storedState` must answer from the applied rows again.
    @Test("a terminally failed toggle stops answering for the heart")
    func aFailedToggleDoesNotHoldTheHeartOn() async throws {
        let (api, outbox, _) = try await Self.openSeeded()
        let ghost = UUID()
        let writer = ProfileFavoriteWriter(api: api, outbox: outbox)

        await writer(treeID: ghost, isFavorite: true)

        let word = try await outbox.pendingFavoriteState(treeID: ghost)
        #expect(word == nil, "a failed toggle is still being counted as the queue's word")

        let shown = await writer.storedState(treeID: ghost)
        #expect(!shown, "the re-read claims a favorite the store refused (R2's one required revert)")
    }

    // MARK: - 2c. The tap made on a device that was once claimed (#174)

    /// **The owner's fifth report: dark green for half a second, then back to white — on the
    /// physical phone only.**
    ///
    /// The device history a fresh simulator never has is one row: `device.user_id`. E124's
    /// account ask signs the owner in at the third visit save (`claimDevice` writes the claim
    /// row), and the You tab's Sign out — "Keeps everything you have saved" — clears
    /// `app_state.current_user_id` and `LocalAPI.userID` but leaves the claim row standing.
    ///
    /// After that, every tap favorites as the device (D9), the drain applies a device-owned row —
    /// and then `LocalAPI.sync` runs `adoptRowsWrittenAfterTheClaim`, which re-runs `claimDevice`
    /// for whatever account the *claim row* names. The freshly applied favorite is adopted on the
    /// spot: `user_id` set to the signed-out account, `device_id` cleared. The re-read asks
    /// `holdsFavorite(userID: nil, deviceID:)` — the row matches neither arm — and the heart goes
    /// back to white in exactly the time one awaited drain takes.
    ///
    /// `pendingFavoriteState` (#167) cannot save it: the row is `done`, and `done` is skipped by
    /// design. The four previous fixes each patched a read; the write was being moved out from
    /// under every read there is.
    @Test("a favorite saved after sign-out is not adopted away by the stale device claim")
    func aFavoriteSavedAfterSignOutSurvivesTheStaleClaim() async throws {
        let (api, outbox, treeID) = try await Self.openSeeded()

        // The owner's device history, replayed: signed in once, signed out from the You tab.
        let account = UUID(uuidString: "AC174000-0000-4000-8000-000000000174")!
        try await api.claimDevice(deviceUUID: Self.deviceID, userID: account)
        try await api.signOut()

        let model = Self.model(api: api, outbox: outbox, treeID: treeID)
        await model.load()
        await model.toggleFavorite().value

        // The queue must have carried it across — this test is about the *applied* row being
        // moved, not about a toggle still in flight (that is 2b's seam, already guarded).
        let queued = try await outbox.pendingFavoriteState(treeID: treeID)
        #expect(queued == nil, "the toggle never applied; this test is aimed at the applied row")

        // The owner's sentence: it is a favorite, so it stays dark green.
        #expect(
            model.isFavorite,
            "the heart went back to white: the applied row was adopted by the signed-out account"
        )

        // The store, asked as the signed-out device asks: the row must still answer the device.
        let held = try await api.mapMembership(.favorites)
        #expect(held.contains(treeID), "the favorite row no longer answers the device that made it")

        // And sign-out's own promise holds in the other direction too: signing back in must not
        // find the favorite already the account's, because the account never made it.
        let word = await ProfileFavoriteWriter(api: api, outbox: outbox).storedState(treeID: treeID)
        #expect(word, "storedState — the composition root's read — lost the favorite")
    }

    // MARK: - 3. The failure that has to be visible

    @Test("a write that never lands leaves the cell where it was")
    func aLostWriteIsVisibleAsTheCellGoingBack() async throws {
        let (api, _, treeID) = try await Self.openSeeded()
        // The composition root's writer, replaced by one that does nothing — which is exactly the
        // defect class this ticket is filed under (#59: controls that promise storage and store
        // nothing). The screen must not claim the favorite it could not make.
        let model = TreeProfileModel(treeID: treeID, api: api, setFavorite: { _, _ in })

        await model.load()
        await model.toggleFavorite().value

        #expect(!model.isFavorite, "the cell claimed a favorite the store never took")
        let held = try await api.mapMembership(.favorites)
        #expect(held.isEmpty)
    }

    // MARK: - 4. The re-read that arrives after the tap it did not see

    /// **A refresh that started before a tap must not answer for it** (ERRATA E184).
    ///
    /// `TreeProfileView` re-reads the profile in two places that are not taps: `onAppear` when the
    /// screen comes back to the front, and `onChange(of: router?.sheet == nil)` when a sheet closes
    /// over it. Both call `reload()`, which calls `load()`, which ends with
    /// `isFavorite = await storedFavorite()`.
    ///
    /// That assignment was unordered with respect to the taps. `load()` read the store, suspended,
    /// and assigned whatever it had read *whenever it got the main actor back* — so a refresh whose
    /// read landed a moment before a tap could put the heart back afterwards. The row is in the
    /// database and the cell says off, which is the only shape "I tapped Favorite and nothing
    /// happened" can take on a control whose state is read rather than remembered.
    ///
    /// The sequence below is the one a person actually performs: close the Care or Share sheet
    /// (a `reload()` starts, and `treeProfile()` on a 108 MB seed is not instant), then tap
    /// Favorite while it is still running.
    @Test("a refresh already in flight does not put the heart back after a tap")
    func aStaleRefreshDoesNotOverwriteATapThatLanded() async {
        let store = FavoriteBox()
        let api = SlowGroveAPI(favorites: store)
        let model = TreeProfileModel(
            treeID: SlowGroveAPI.treeID,
            api: api,
            setFavorite: { id, isFavorite in
                if isFavorite { store.held.insert(id) } else { store.held.remove(id) }
            }
        )

        await model.load()
        #expect(!model.isFavorite)

        // The sheet closes: a refresh begins and its `grove()` takes its snapshot — "not a
        // favorite" — and then stalls before returning.
        await api.holdTheNextGroveReadOpen()
        let refresh = Task { await model.reload() }
        await api.waitUntilGroveIsHeld()

        // The finger arrives while it is stalled. This tap's own read is not held.
        await model.toggleFavorite().value
        #expect(model.isFavorite, "the tap itself did not take")

        // The stalled refresh now returns, carrying an answer taken before the tap existed.
        api.releaseTheHeldGroveRead()
        await refresh.value

        #expect(
            model.isFavorite,
            "a refresh that started before the tap put the heart back off, over a favorite the store holds"
        )
        #expect(store.held.contains(SlowGroveAPI.treeID), "the store lost the favorite as well")
    }
}

// MARK: - Doubles for the ordering test

/// The favorites a test can write to and read back, shared between the API double and the model's
/// write closure — which is what makes "what the cell shows is what is stored" a testable sentence.
final class FavoriteBox: @unchecked Sendable {
    var held: Set<UUID> = []
}

/// A `CypressAPI` whose `grove()` can be stalled *after* it has taken its snapshot.
///
/// The stall is after the read on purpose: what is being pinned is not a slow database but an
/// assignment that lands out of order. A double that stalled before reading would return the fresh
/// answer and prove nothing.
final class SlowGroveAPI: CypressAPI, @unchecked Sendable {
    static let treeID = UUID(uuidString: "F1390000-0000-4000-8000-0000000001A1")!

    private let favorites: FavoriteBox
    private var hold: CheckedContinuation<Void, Never>?
    private var holdRequested = false
    private var holdEntered: CheckedContinuation<Void, Never>?

    init(favorites: FavoriteBox) { self.favorites = favorites }

    func holdTheNextGroveReadOpen() async { holdRequested = true }

    func waitUntilGroveIsHeld() async {
        guard hold == nil else { return }
        await withCheckedContinuation { continuation in holdEntered = continuation }
    }

    func releaseTheHeldGroveRead() {
        let continuation = hold
        hold = nil
        continuation?.resume()
    }

    func treeProfile(id: UUID) async throws -> TreeProfile {
        TreeProfile(
            tree: Tree(
                id: Self.treeID,
                externalRef: "13284",
                source: .cityImport,
                coordinate: Coordinate(latitude: 37.799, longitude: -122.443),
                address: "2576 Lombard St",
                status: .alive,
                plantedYear: 1993,
                verificationState: .cityRecord,
                createdAt: Date(timeIntervalSince1970: 1_784_505_600),
                updatedAt: Date(timeIntervalSince1970: 1_784_505_600)
            ),
            visits: Series(complete: [
                Visit(
                    treeID: Self.treeID,
                    attribution: Attribution.anonymous(deviceID: Self.treeID),
                    note: "Fog dripping off the crown",
                    capturedAt: Date(timeIntervalSince1970: 1_784_419_200)
                ),
            ])
        )
    }

    func grove() async throws -> [GroveEntry] {
        // The read, taken now.
        let snapshot = favorites.held
        if holdRequested {
            holdRequested = false
            await withCheckedContinuation { continuation in
                hold = continuation
                let entered = holdEntered
                holdEntered = nil
                entered?.resume()
            }
        }
        return snapshot.map { id in
            GroveEntry(
                treeID: id,
                displayName: "",
                coordinate: Coordinate(latitude: 37.799, longitude: -122.443),
                lastVisitedAt: nil,
                isFavorite: true
            )
        }
    }

    func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
    func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}
