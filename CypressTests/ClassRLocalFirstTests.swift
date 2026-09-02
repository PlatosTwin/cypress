//
//  ClassRLocalFirstTests.swift
//  CypressTests
//
//  The three Class R reads PR #144 did not reach: a tree's profile, the heart, and the map's
//  membership chip. Each awaited the service before it returned anything, so each put a network
//  round trip in front of a screen whose answer was already on the disk.
//
//  ── The instrument, and the one this file deliberately does not use ───────────────────────────
//  `GroveLocalFirstTests`' header argues this out and it is the argument here too, restated because
//  a reader arriving at this file should not have to find the other one first: **there is no
//  blocking transport in here.** Holding the service's answer behind a latch reads as the strongest
//  possible statement of the defect — assert while the far side is provably still in flight — and it
//  is the wrong instrument, because a regression to the blocking paint would **hang** on such a
//  latch rather than fail. A hang is not a red-proof; it is a stalled suite somebody has to kill and
//  interpret.
//
//  What replaces it is two facts and no clock:
//
//  1. **`transport.calls` after the read returns.** A read that painted from the phone made no
//     request, and a scripted transport records every one it did make. The service is scripted with
//     a *different* answer from the phone's throughout, so "the paint answered" and "the merge
//     answered" are distinguishable values and not just distinguishable timings.
//  2. **`await model.profileRefresh?.value`.** Every model here holds its background task so a test
//     can await the merge landing rather than sleep past it.
//
//  There are no wall-clock margins in this file.
//

import Foundation
import Testing
@testable import Cypress

@MainActor
@Suite("Class R · the phone answers first, and the service reconciles behind it")
struct ClassRLocalFirstTests {

    static let treeID = UUID(uuidString: "B1C2D3E4-0000-4000-8000-00000000C001")!
    static let myPhotoID = UUID(uuidString: "B1C2D3E4-0000-4000-8000-00000000C002")!
    static let theirPhotoID = UUID(uuidString: "B1C2D3E4-0000-4000-8000-00000000C003")!
    static let moment = Date(timeIntervalSince1970: 1_700_000_000)
    static let deviceID = UUID(uuidString: "B1C2D3E4-0000-4000-8000-00000000C004")!

    static func tree(_ id: UUID) -> Tree {
        Tree(id: id, source: .community, coordinate: Coordinate(latitude: 37.77, longitude: -122.44))
    }

    /// The phone's profile: one photograph, this device's.
    static func localProfile() -> TreeProfile {
        TreeProfile(
            tree: tree(treeID),
            photos: Series(complete: [
                Photo(id: myPhotoID, treeID: treeID, shotType: .fullTree, capturedAt: moment)
            ]),
            ownPhotoIDs: [myPhotoID],
            deletablePhotoIDs: [myPhotoID]
        )
    }

    static func localDouble() -> LocalDouble {
        var local = LocalDouble()
        local.profile = localProfile()
        return local
    }

    /// The router `DataLayer.boot` builds for these three reads.
    ///
    /// `GroveCityFileBatchTests.shippingRouter` exists for the same reason and this is its sibling:
    /// written as one helper so a test cannot accidentally exercise a hand-rolled composition while
    /// believing it is exercising the shipping one — the mistake PR #144's review found.
    static func router(
        _ local: LocalDouble,
        _ transport: ScriptedTransport,
        log: RemoteReadLog = RemoteReadLog()
    ) -> RoutedAPI {
        RoutedAPI(
            local: local,
            remote: RemoteAPI(
                baseURL: URL(string: "https://service.invalid/api/v1")!,
                transport: transport,
                session: .shared
            ),
            log: log
        )
    }

    /// A transport that answers the community half with somebody else's photograph.
    static func scriptedService() -> ScriptedTransport {
        let transport = ScriptedTransport()
        transport.answer(
            "GET /trees/\(treeID.uuidString)",
            with: """
            {"tree_uuid":"\(treeID.uuidString)","photos":[
              {"photo_id":"\(theirPhotoID.uuidString)","shot_type":"full_tree",
               "captured_at":"2026-08-09T18:41:46Z","is_publicly_visible":true}],
             "photo_count":1,"visit_count":9,"own_photo_ids":[],"deletable_photo_ids":[]}
            """
        )
        return transport
    }

    // MARK: - Calibration

    /// **Calibrate the instrument before trusting any count below.**
    ///
    /// The phone answers one photograph and the merge answers two, and the scripted service really
    /// is reached by the merge. Without this, every "the paint did not call the service" assertion
    /// in this file could be passing because the route was misspelled and the merge never worked
    /// either — the two are indistinguishable from a `calls.isEmpty` alone.
    @Test("the fixture answers what it claims to")
    func theFixtureAnswersWhatItClaimsTo() async throws {
        let transport = Self.scriptedService()
        let log = RemoteReadLog()
        let routed = Self.router(Self.localDouble(), transport, log: log)

        #expect(try await routed.treeProfile(id: Self.treeID).photos.items.count == 1)
        let merged = try await routed.refreshedTreeProfile(id: Self.treeID)
        #expect(merged.photos.items.count == 2, "the scripted community half never reached the merge")
        #expect(transport.calls.count == 1)
        #expect(await log.outcome(of: .treeProfile) == .live)
    }

    // MARK: - The paint: these three reads do not touch the wire

    /// Opening any tree is sixteen call sites' worth of read, and every one of them used to wait.
    @Test("the profile read answers from the phone")
    func theProfileReadAnswersFromThePhone() async throws {
        let transport = Self.scriptedService()
        let log = RemoteReadLog()

        let profile = try await Self.router(Self.localDouble(), transport, log: log)
            .treeProfile(id: Self.treeID)

        #expect(profile.photos.items.count == 1, "the paint returned the merged answer")
        #expect(transport.calls.isEmpty, "opening a tree profile reached the service")
        // nil, not `.fellBackToLocal`: the service was not consulted, which is a different fact
        // from the service being unreachable. `RemoteReadLog.outcome(of:)` keeps them apart.
        #expect(await log.outcome(of: .treeProfile) == nil)
    }

    /// The heart, under the owner's ruling of 2026-09-02.
    @Test("the favorite read answers from the phone")
    func theFavoriteReadAnswersFromThePhone() async throws {
        var local = Self.localDouble()
        local.favorite = false

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove/\(Self.treeID.uuidString)/favorite", with: #"{"is_favorite":true}"#
        )
        let log = RemoteReadLog()

        let answer = try await Self.router(local, transport, log: log).isFavorite(treeID: Self.treeID)

        #expect(answer == false, "the heart waited for the service before answering the finger")
        #expect(transport.calls.isEmpty, "a favorite read reached the service")
        #expect(await log.outcome(of: .isFavorite) == nil)
    }

    /// The membership chip, which narrows a map over 145,837 trees and used to do it second.
    @Test("the membership read answers from the phone")
    func theMembershipReadAnswersFromThePhone() async throws {
        let queued = UUID()
        let account = UUID()
        var local = Self.localDouble()
        local.membership = [queued]

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/map-membership",
            with: #"{"kind":"yours","tree_ids":["\#(account.uuidString)"]}"#
        )
        let log = RemoteReadLog()

        let ids = try await Self.router(local, transport, log: log).mapMembership(.yours)

        #expect(ids == [queued], "the chip waited for the service before narrowing the map")
        #expect(transport.calls.isEmpty, "the membership chip reached the service")
        #expect(await log.outcome(of: .mapMembership) == nil)
    }

    // MARK: - A cancelled refresh records nothing

    /// **A refresh this app called off records nothing; one that was actually refused records the
    /// refusal.** `GroveLocalFirstTests.aCancelledRefreshRecordsNothing`, over the three reads this
    /// round split — each of which is cancelled by an ordinary gesture: dismissing a profile,
    /// tapping a second pin, pressing a different chip.
    ///
    /// **The cancellation is ordered, not raced.** The suite is `@MainActor`; the child task cannot
    /// begin until this function suspends, and `cancel()` is called before it does. So the body runs
    /// already-cancelled, every time.
    ///
    /// The second half of each pair is the calibration and it is the whole test: an identical router
    /// that is *not* cancelled must still record the refusal, or "records nothing" would be true
    /// because nothing ever records anything.
    @Test("a cancelled refresh records nothing, and an uncancelled refusal still records")
    func aCancelledRefreshRecordsNothing() async throws {
        // ── The profile ──────────────────────────────────────────────────────────────────────
        let cancelledProfileLog = RemoteReadLog()
        let cancelledProfile = Self.router(Self.localDouble(), ScriptedTransport(), log: cancelledProfileLog)
        let profileTask = Task { _ = try? await cancelledProfile.refreshedTreeProfile(id: Self.treeID) }
        profileTask.cancel()
        await profileTask.value
        let profileOutcome = await cancelledProfileLog.outcome(of: .treeProfile)
        #expect(
            profileOutcome == nil,
            "a profile refresh this app called off was recorded as \(String(describing: profileOutcome))"
        )

        let refusedProfileLog = RemoteReadLog()
        _ = try await Self.router(Self.localDouble(), ScriptedTransport(), log: refusedProfileLog)
            .refreshedTreeProfile(id: Self.treeID)
        let refusedProfile = await refusedProfileLog.outcome(of: .treeProfile)
        #expect(
            refusedProfile == .fellBackToLocal,
            "an unreachable service recorded \(String(describing: refusedProfile)) — this gate is vacuous"
        )

        // ── The heart ────────────────────────────────────────────────────────────────────────
        let cancelledHeartLog = RemoteReadLog()
        let cancelledHeart = Self.router(Self.localDouble(), ScriptedTransport(), log: cancelledHeartLog)
        let heartTask = Task { _ = try? await cancelledHeart.reconciledIsFavorite(treeID: Self.treeID) }
        heartTask.cancel()
        await heartTask.value
        let heartOutcome = await cancelledHeartLog.outcome(of: .isFavorite)
        #expect(
            heartOutcome == nil,
            "a reconcile this app called off was recorded as \(String(describing: heartOutcome))"
        )

        let refusedHeartLog = RemoteReadLog()
        _ = try await Self.router(Self.localDouble(), ScriptedTransport(), log: refusedHeartLog)
            .reconciledIsFavorite(treeID: Self.treeID)
        let refusedHeart = await refusedHeartLog.outcome(of: .isFavorite)
        #expect(
            refusedHeart == .fellBackToLocal,
            "an unreachable service recorded \(String(describing: refusedHeart)) — this gate is vacuous"
        )

        // ── The membership chip ──────────────────────────────────────────────────────────────
        let cancelledChipLog = RemoteReadLog()
        let cancelledChip = Self.router(Self.localDouble(), ScriptedTransport(), log: cancelledChipLog)
        let chipTask = Task { _ = try? await cancelledChip.refreshedMapMembership(.yours) }
        chipTask.cancel()
        await chipTask.value
        let chipOutcome = await cancelledChipLog.outcome(of: .mapMembership)
        #expect(
            chipOutcome == nil,
            "a membership union this app called off was recorded as \(String(describing: chipOutcome))"
        )

        let refusedChipLog = RemoteReadLog()
        _ = try await Self.router(Self.localDouble(), ScriptedTransport(), log: refusedChipLog)
            .refreshedMapMembership(.yours)
        let refusedChip = await refusedChipLog.outcome(of: .mapMembership)
        #expect(
            refusedChip == .fellBackToLocal,
            "an unreachable service recorded \(String(describing: refusedChip)) — this gate is vacuous"
        )
    }

    // MARK: - Screen 03: paint, then merge

    @Test("the profile model paints the phone's tree, then merges the community half")
    func theProfileModelPaintsThenMerges() async throws {
        let transport = Self.scriptedService()
        let routed = Self.router(Self.localDouble(), transport)
        let model = TreeProfileModel(
            treeID: Self.treeID,
            api: routed,
            refreshProfile: { id in try? await routed.refreshedTreeProfile(id: id) }
        )

        await model.load()

        let painted = try #require(model.presentation)
        #expect(painted.profile.photos.items.count == 1, "the first frame waited for the merge")
        #expect(transport.calls.isEmpty, "the painted profile reached the service")

        await model.profileRefresh?.value

        let merged = try #require(model.presentation)
        #expect(merged.profile.photos.items.count == 2, "the community half never landed")
        #expect(
            merged.profile.photos.items.contains { $0.id == Self.theirPhotoID },
            "the photograph this device never wrote is missing from the merged profile"
        )
    }

    /// A refresh that could not reach the service must leave the painted profile standing — "an
    /// empty state is a claim, and this project has already drawn one over a failed read"
    /// (R72 ruling 1).
    @Test("a failed profile refresh leaves the paint standing")
    func aFailedProfileRefreshLeavesThePaintStanding() async throws {
        let model = TreeProfileModel(
            treeID: Self.treeID,
            api: Self.router(Self.localDouble(), ScriptedTransport()),
            refreshProfile: { _ in nil }
        )

        await model.load()
        await model.profileRefresh?.value

        let painted = try #require(model.presentation)
        #expect(painted.profile.photos.items.count == 1, "a failed refresh emptied the profile")
    }

    /// Every preview, screenshot fixture and unit test that builds this model passes nothing and
    /// gets the pure-local model it has always had — **no background task at all**.
    @Test("a model with no refreshers starts no task")
    func aModelWithNoRefreshersStartsNoTask() async throws {
        let model = TreeProfileModel(
            treeID: Self.treeID,
            api: Self.router(Self.localDouble(), ScriptedTransport())
        )
        await model.load()

        #expect(model.profileRefresh == nil, "a model with no refresher started a profile task")
        #expect(model.favoriteReconcile == nil, "a model with no reconciler started a heart task")
    }

    // MARK: - The heart: the R2 amendment

    /// **The tap answers before the service does, and the reconcile moves the heart both ways.**
    ///
    /// Both directions matter and they fail differently. A reconcile that only ever turned the heart
    /// *on* would be indistinguishable from one that never ran on a fixture where the phone already
    /// said `false`; a reconcile that only ever turned it *off* would look correct on the other. So
    /// the same model is driven against a service that disagrees in each direction.
    @Test("the heart answers from the phone, then reconciles a divergent server answer both ways")
    func theHeartReconcilesBothWays() async throws {
        // ── The phone says no and the service says yes ───────────────────────────────────────
        var offLocally = Self.localDouble()
        offLocally.favorite = false
        let turnsOn = TreeProfileModel(
            treeID: Self.treeID,
            api: Self.router(offLocally, ScriptedTransport()),
            readFavorite: { _ in false },
            reconcileFavorite: { _ in true }
        )

        await turnsOn.load()
        #expect(turnsOn.isFavorite == false, "the heart waited for the service before painting")
        await turnsOn.favoriteReconcile?.value
        #expect(turnsOn.isFavorite, "a favorite set on another phone never reached this one")

        // ── The phone says yes and the service says no ───────────────────────────────────────
        var onLocally = Self.localDouble()
        onLocally.favorite = true
        let turnsOff = TreeProfileModel(
            treeID: Self.treeID,
            api: Self.router(onLocally, ScriptedTransport()),
            readFavorite: { _ in true },
            reconcileFavorite: { _ in false }
        )

        await turnsOff.load()
        #expect(turnsOff.isFavorite, "the phone's favorite never painted")
        await turnsOff.favoriteReconcile?.value
        #expect(
            turnsOff.isFavorite == false,
            "a favorite removed on another phone was not reconciled back off here"
        )
    }

    /// **A nil reconcile changes nothing**, which is the answer for both an unreached service and a
    /// toggle the outbox is still holding (`ProfileFavoriteWriter.reconciledState`). Replacing the
    /// painted heart with `false` because a network failed is R72 ruling 1's defect.
    @Test("a reconcile that answers nil leaves the painted heart alone")
    func aNilReconcileLeavesTheHeartAlone() async throws {
        var local = Self.localDouble()
        local.favorite = true
        let model = TreeProfileModel(
            treeID: Self.treeID,
            api: Self.router(local, ScriptedTransport()),
            readFavorite: { _ in true },
            reconcileFavorite: { _ in nil }
        )

        await model.load()
        await model.favoriteReconcile?.value

        #expect(model.isFavorite, "a nil reconcile took the heart off a tree this device holds")
    }

    /// **The tap still wins, and in the shipping wiring the queue is what makes it win** (#167).
    ///
    /// The reconcile is the slowest read on this screen and therefore the one most likely to hold a
    /// stale answer when a finger arrives. A reconcile that skipped the outbox would answer with the
    /// state *before* the tap — the toggle is durable at enqueue and the service has not heard it
    /// yet — and put the heart back off over a favorite the reader had just set. That is exactly the
    /// "my favoriting got undone" report of #139, #153 and #167, arriving from the one direction
    /// those three tickets did not close.
    ///
    /// So `ProfileFavoriteWriter.reconciledState` declines to answer at all while the queue holds a
    /// toggle, and nil is what `TreeProfileModel` reads as leave-the-heart-alone. All three arms are
    /// here because nil has two causes and they must not be confused: a pending toggle, and no
    /// service at all.
    @Test("the reconcile defers to a toggle the queue is still holding")
    func theReconcileDefersToAPendingToggle() async throws {
        let store = try await CypressStore.inMemory()
        let local = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: local))

        // ── Calibration: with nothing queued, the service's answer comes straight through ─────
        let clean = ProfileFavoriteWriter(
            api: local, local: local, outbox: outbox, reconcile: { _ in true }
        )
        let answered = await clean.reconciledState(treeID: Self.treeID)
        #expect(
            answered == true,
            """
            the reconcile answered \(String(describing: answered)) with an empty queue — if this is \
            nil the two arms below are nil for the wrong reason and prove nothing
            """
        )

        // ── A toggle the queue is still holding: the contributor's last word stands ───────────
        // **Enqueued and deliberately not drained**, which is the window #167 is about: the write is
        // durable at enqueue and applied at drain, and in between the queue holds the contributor's
        // last word. `FavoriteOutboxWriter.save` drains as its second step, so calling it here would
        // leave the item `done` and nothing pending at all — this test asserted against exactly that
        // by mistake on its first run, and the reconcile duly answered.
        _ = try await outbox.enqueue(
            .favoriteToggle(
                FavoriteToggle(
                    owner: FavoriteOwner(await local.attribution),
                    treeID: Self.treeID,
                    clientUUID: UUID(),
                    isFavorite: true,
                    occurredAt: Self.moment
                )
            )
        )
        let pending = ProfileFavoriteWriter(
            api: local, local: local, outbox: outbox, reconcile: { _ in false }
        )
        let deferred = await pending.reconciledState(treeID: Self.treeID)
        #expect(
            deferred == nil,
            """
            the reconcile answered \(String(describing: deferred)) over a toggle the queue is still \
            holding — the heart goes back off over a favorite the reader just set (#167)
            """
        )

        // ── No service at all: nil for the other reason ──────────────────────────────────────
        let shut = ProfileFavoriteWriter(api: local, local: local, outbox: outbox, reconcile: nil)
        #expect(await shut.reconciledState(treeID: Self.treeID) == nil)
    }

    // MARK: - The map's membership chip

    @Test("the chip narrows from the phone, then unions the account's set behind it")
    func theChipNarrowsThenUnions() async throws {
        let queued = UUID()
        let account = UUID()
        var local = Self.localDouble()
        local.membership = [queued]

        let model = MapModel(
            api: Self.router(local, ScriptedTransport()),
            refreshMembership: { _ in [queued, account] }
        )

        model.filter = MapFilter(membership: .yours)
        // **Two tasks, in order, and neither is timed.** The chip's narrow read is the first and it
        // is what starts the union — so awaiting the union alone would find nothing to await, which
        // is exactly how this test failed when it was first written.
        //
        // **What is deliberately not asserted between them is the narrowed-but-not-yet-unioned set.**
        // A refresh closure that answers without suspending can land while `membershipTask.value` is
        // being awaited, so the intermediate value is not reliably observable from here — asserting
        // it passed or failed on scheduling rather than on behavior. That the paint is the phone's
        // alone is pinned where it *is* observable, at the router:
        // `theMembershipReadAnswersFromThePhone` above reads `transport.calls`.
        await model.membershipTask?.value
        _ = try #require(model.membershipIDs, "the chip never narrowed from the phone")
        await model.membershipRefresh?.value

        let ids = try #require(model.membershipIDs)
        #expect(
            ids == [queued, account],
            "the account's membership never joined the chip's set — got \(ids.count) ids"
        )
    }

    /// A model with no refresher starts no union task at all — every preview and unit test.
    @Test("a map model with no membership refresher starts no task")
    func theChipStartsNoTaskWithNoRefresher() async throws {
        let queued = UUID()
        var local = Self.localDouble()
        local.membership = [queued]

        let model = MapModel(api: Self.router(local, ScriptedTransport()))
        model.filter = MapFilter(membership: .yours)
        await Task.yield()

        #expect(model.membershipRefresh == nil, "a model with no refresher started a union task")
    }

    // MARK: - The composition root

    /// **The wiring, from the shipping boot** — the three closures exist when the gate is open and
    /// are nil when it is shut, which is how each model knows not to start a background task at all.
    @Test("the composition root wires the three refreshes, and nils them with the gate shut")
    func theCompositionRootWiresTheRefreshes() async throws {
        let live = try await DataLayer.boot(
            databaseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cypress-classr-live-\(UUID().uuidString).sqlite"),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            transport: ScriptedTransport(),
            credentials: InMemoryCredentialStore(),
            storageSession: OfflineSession.make()
        )
        #expect(live.refreshTreeProfile != nil, "screen 03 has no community half to merge")
        #expect(live.reconcileFavorite != nil, "the heart has no service to reconcile against")
        #expect(live.refreshMapMembership != nil, "the chip has no account half to union")

        let shut = try await DataLayer.boot(
            databaseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cypress-classr-off-\(UUID().uuidString).sqlite"),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            remoteAccess: .disabled,
            credentials: InMemoryCredentialStore(),
            storageSession: OfflineSession.make()
        )
        #expect(shut.refreshTreeProfile == nil, "a gate-shut build refreshes a profile from nothing")
        #expect(shut.reconcileFavorite == nil, "a gate-shut build reconciles the heart against nothing")
        #expect(shut.refreshMapMembership == nil, "a gate-shut build unions the chip against nothing")
    }
}
