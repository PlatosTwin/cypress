//
//  GroveLocalFirstTests.swift
//  CypressTests
//
//  **My Grove paints from the phone and merges the account's half behind it** — the owner's ruling
//  of 2026-09-01, and the two gates that make it unrepeatable.
//
//  ── Why there is not a single number in this file ─────────────────────────────────────────────
//
//  The defect is "the first frame waits for a network round trip", and the tempting test is "the
//  read returned in under N milliseconds". That test is a coin toss on a loaded machine and it has
//  already cost this project a flaky suite once (`docs/whats-new/test-perf-margin-redesign.md`:
//  count work, do not race a clock). PR #140's principle is that **no clock is read anywhere**, and
//  what replaces it here are two structural facts, each doing a different job.
//
//  1. **The paint made zero requests.** `transport.calls` is the census, read *after* the read
//     returned. This is the assertion that carries the defect: a paint that awaited the service
//     would have a call in it, whatever the machine was doing. Nothing is compared to a threshold
//     and there is no margin to tune.
//  2. **The merge cannot arrive early.** `GateTransport` holds every request until this test opens
//     it, so "the second species appeared" can only be true after the release — which is what makes
//     the before/after pair below an ordering rather than a race, and what makes the call counts in
//     `aRepeatLoadStillRefreshes` exact rather than lucky.
//

import Foundation
import Testing
@testable import Cypress

// MARK: - A service that answers only when the test says so

/// A latch every waiter parks on until `open()` is called.
///
/// `open()` is safe to call before anybody has waited and safe to call twice — which is what makes a
/// test using it free of an ordering assumption between the background refresh reaching the wire and
/// the test releasing it. Without that property this file would be racing exactly the thing it
/// refuses to race.
actor RemoteGate {

    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let parked = waiting
        waiting = []
        for continuation in parked { continuation.resume() }
    }
}

/// `ScriptedTransport`, behind `RemoteGate`.
///
/// Scripting is delegated rather than reimplemented, so a route that is not scripted throws
/// `notFound` exactly as it does everywhere else in this target — after the gate opens, which is the
/// point: **nothing this transport can answer is reachable before `gate.open()`.**
final class GateTransport: AuthorizedTransport, @unchecked Sendable {

    let gate = RemoteGate()
    private let scripted = ScriptedTransport()

    func answer(_ route: String, with json: String) { scripted.answer(route, with: json) }

    var calls: [ScriptedTransport.Call] { scripted.calls }

    func send(_ request: URLRequest) async throws -> Data {
        await gate.wait()
        return try await scripted.send(request)
    }
}

// MARK: - The gates

@MainActor
@Suite("My Grove · the phone paints first and the account's half arrives behind it")
struct GroveLocalFirstTests {

    static let speciesID = UUID(uuidString: "5E000000-0000-4000-8000-000000000001")!
    static let accountSpeciesID = UUID(uuidString: "5E000000-0000-4000-8000-000000000002")!
    static let treeID = UUID(uuidString: "77000000-0000-4000-8000-000000000001")!
    static let accountTreeID = UUID(uuidString: "77000000-0000-4000-8000-000000000002")!

    static let firstMet = Date(timeIntervalSince1970: 1_700_000_000)
    static let laterMet = Date(timeIntervalSince1970: 1_780_000_000)

    /// A phone that knows one species and one tree, and a service that knows one more of each.
    static func localDouble() throws -> LocalDouble {
        var local = LocalDouble()
        local.speciesKnown = GroveSpecies(
            neighborhood: GroveNeighborhood(area: .radius(meters: 500), species: Series(complete: [speciesID])),
            known: Series(complete: [
                KnownSpecies(
                    speciesID: speciesID,
                    scientificName: "Platanus × acerifolia",
                    commonName: "London Plane",
                    firstMetAt: laterMet,
                    firstMetAddress: "Noriega St"
                )
            ])
        )
        local.speciesByID = [
            accountSpeciesID: try Species(
                id: accountSpeciesID,
                scientificName: "Quercus agrifolia",
                commonName: "Coast Live Oak",
                leafRetention: nil
            )
        ]
        local.groveEntries = [
            GroveEntry(
                treeID: treeID,
                displayName: "London Plane",
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                lastVisitedAt: firstMet,
                isFavorite: false
            )
        ]
        local.profilesByID = [
            accountTreeID: TreeProfile(
                tree: Tree(
                    id: accountTreeID,
                    source: .community,
                    coordinate: Coordinate(latitude: 37.76, longitude: -122.50)
                ),
                species: try Species(
                    id: accountSpeciesID,
                    scientificName: "Quercus agrifolia",
                    commonName: "Coast Live Oak",
                    leafRetention: nil
                )
            )
        ]
        return local
    }

    /// A service holding one species and one tree this phone has never met.
    static func gatedService() -> GateTransport {
        let transport = GateTransport()
        transport.answer(
            "GET /me/grove/species",
            with: """
            {"known":[{"species_id":"\(accountSpeciesID.uuidString)",
             "first_met":"\(ISO8601DateFormatter().string(from: laterMet))"}],"total":1}
            """
        )
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(accountTreeID.uuidString)","last_visited_at":null,
             "is_favorite":true,"record":null,"hero_photo_id":null}],"total":1}
            """
        )
        return transport
    }

    static func router(_ local: LocalDouble, _ transport: GateTransport, log: RemoteReadLog) -> RoutedAPI {
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

    // MARK: Calibration

    /// **Calibrate the fixture before believing anything it certifies.**
    ///
    /// Three things have to be true or every gate below is vacuous, and each of them is a way a
    /// green suite here would mean nothing:
    ///
    /// - the gate really **releases** — a gate that never opened would make every merge assertion
    ///   unreachable rather than wrong, and this file would be asserting only that nothing happened;
    /// - the scripted routes really **decode** — an unscripted or malformed answer comes back as a
    ///   throw the router swallows into its fallback, so "the merge did not arrive" would be true
    ///   for a reason that has nothing to do with the code under test;
    /// - the phone's answer and the merged answer are **distinguishable** — one species against two.
    ///   Without that, "the paint drew the phone's grove" and "the merge landed" are the same
    ///   observation.
    @Test("the gate releases, the routes decode, and one species is not two")
    func theFixtureAnswersWhatItClaimsTo() async throws {
        let transport = Self.gatedService()
        let log = RemoteReadLog()
        let router = Self.router(try Self.localDouble(), transport, log: log)

        #expect(try await router.groveSpecies().known.items.count == 1, "the phone's half is not one species")

        let held = Task { try await router.refreshedGroveSpecies() }
        await transport.gate.open()
        let merged = try await held.value

        #expect(merged.known.items.count == 2, "the gate never released, or the route did not decode")
        #expect(transport.calls.count == 1, "the refresh asked the service \(transport.calls.count) times")
        #expect(await log.outcome(of: .groveSpecies) == .live, "the refresh did not resolve every row")
    }

    // MARK: The paint

    /// **`groveSpecies()` answers from the phone while the service is still held.**
    ///
    /// This is the reported defect as a test. The Species pill is the tab My Grove opens on, and its
    /// read used to `await remote.groveSpeciesDelta()` before returning anything — so the first frame
    /// cost a round trip, and on an unreachable host it cost `URLSession`'s untouched 60-second
    /// default.
    ///
    /// The gate is never opened in this test. If the paint asked the service, this `await` would not
    /// return at all.
    @Test("the species read answers from the phone with the service still held")
    func theSpeciesReadAnswersFromThePhone() async throws {
        let transport = Self.gatedService()
        let log = RemoteReadLog()
        let router = Self.router(try Self.localDouble(), transport, log: log)

        let painted = try await router.groveSpecies()

        #expect(painted.known.items.count == 1, "the paint did not answer with the phone's grove")
        #expect(painted.known.items.first?.speciesID == Self.speciesID)
        #expect(transport.calls.isEmpty, "the paint reached the service")
        // Nil, not `.fellBackToLocal`: the service was not asked, which is a different fact from
        // being asked and unreachable. `RemoteReadLog.outcome(of:)`'s own note says so.
        #expect(
            await log.outcome(of: .groveSpecies) == nil,
            "the paint recorded an outcome for a service it never consulted"
        )

        await transport.gate.open()
    }

    /// The Trees pill, on the same terms.
    @Test("the trees read answers from the phone with the service still held")
    func theTreesReadAnswersFromThePhone() async throws {
        let transport = Self.gatedService()
        let log = RemoteReadLog()
        let router = Self.router(try Self.localDouble(), transport, log: log)

        let painted = try await router.grove()

        #expect(painted.count == 1, "the paint did not answer with the phone's grove")
        #expect(painted.first?.treeID == Self.treeID)
        #expect(transport.calls.isEmpty, "the paint reached the service")
        #expect(await log.outcome(of: .grove) == nil)

        await transport.gate.open()
    }

    // MARK: The model, which is where the two halves are visible at once

    /// **The screen is drawn from the phone, and the account's species appears when it arrives.**
    ///
    /// Both halves of the ruling in one test, and neither half reads a clock: the first assertion is
    /// made while the gate is shut, and the second is made after `speciesRefresh` — the model's own
    /// handle on the background task — has completed. "Await the task" is a structural fact about
    /// the work, not a guess about how long it takes.
    @Test("the model paints one species, then two when the service answers")
    func theModelPaintsThenMerges() async throws {
        let transport = Self.gatedService()
        let router = Self.router(try Self.localDouble(), transport, log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { Self.laterMet },
            refreshSpecies: { try? await router.refreshedGroveSpecies() }
        )

        await model.load()

        guard case let .loaded(painted) = model.phase else {
            Issue.record("the first read did not paint: \(model.phase)")
            return
        }
        #expect(painted.known.items.count == 1, "the paint waited for the service")
        #expect(transport.calls.isEmpty, "the paint reached the service")

        await transport.gate.open()
        await model.speciesRefresh?.value

        guard case let .loaded(merged) = model.phase else {
            Issue.record("the refresh did not publish: \(model.phase)")
            return
        }
        #expect(merged.known.items.count == 2, "the account's species never reached the screen")
        #expect(
            merged.known.items.contains { $0.speciesID == Self.accountSpeciesID },
            "the merged grove is missing the species only the account knew about"
        )
        // The phone's denominator survived the merge — it is a fact about the installed inventory
        // and the service declines to answer it (D16).
        #expect(merged.neighborhood?.species.items == [Self.speciesID])
    }

    /// The Trees pill's half of the same property.
    @Test("the trees pill paints one tree, then two when the service answers")
    func theTreesPillPaintsThenMerges() async throws {
        let transport = Self.gatedService()
        let router = Self.router(try Self.localDouble(), transport, log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { Self.laterMet },
            tab: .trees,
            refreshTrees: { try? await router.refreshedGrove() }
        )

        await model.loadTreesIfNeeded()

        guard case let .loaded(painted) = model.treesPhase else {
            Issue.record("the first read did not paint: \(model.treesPhase)")
            return
        }
        #expect(painted.count == 1, "the paint waited for the service")
        #expect(transport.calls.isEmpty, "the paint reached the service")

        await transport.gate.open()
        await model.treesRefresh?.value

        guard case let .loaded(merged) = model.treesPhase else {
            Issue.record("the refresh did not publish: \(model.treesPhase)")
            return
        }
        #expect(merged.count == 2, "the account's tree never reached the screen")
        #expect(
            merged.contains { $0.treeID == Self.accountTreeID },
            "the merged grove is missing the tree only the account knew about"
        )
    }

    /// **A refresh that could not reach the service leaves the painted grove standing.**
    ///
    /// R72 ruling 1: an empty state is a claim. There is a whole grove on the glass, and a second
    /// read that did not land is not evidence against it.
    @Test("a refresh that fails does not blank the screen")
    func aFailedRefreshLeavesThePaintStanding() async throws {
        let router = Self.router(try Self.localDouble(), GateTransport(), log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { Self.laterMet },
            // What `DataLayer.boot` builds: the throw is swallowed to nil.
            refreshSpecies: { nil }
        )

        await model.load()
        await model.speciesRefresh?.value

        guard case let .loaded(standing) = model.phase else {
            Issue.record("a failed refresh took the grove off the screen: \(model.phase)")
            return
        }
        #expect(standing.known.items.count == 1)
        #expect(!model.hasFailed)
    }

    // MARK: The lifetime, which is what a tab switch costs

    /// **A second `load()` does not read again.**
    ///
    /// `RootView.tabRoot` rebuilds the arm it selects, so `GroveView.task` fires on every return to
    /// the tab. With the model owned above the switch (`RootView.grove`) that is a *repeat* call on
    /// a model that already has an answer, and the answer is what should be drawn — not a second
    /// read of the same question. `loadTreesIfNeeded()` has had this guard since it was written;
    /// `load()` did not, which is why every visit to My Grove was a cold read.
    @Test("a repeat load paints the answer it already has instead of reading again")
    func aRepeatLoadDoesNotReadAgain() async throws {
        let counter = ReadCounter()
        var local = try Self.localDouble()
        local.reads = counter
        let model = GroveModel(api: local, now: { Self.laterMet }, tab: .trees)

        // Calibration: the counter counts. Without this, "1" and "the counter is broken" agree.
        await model.load()
        #expect(counter.speciesReads == 1, "the counter did not see the first read")

        await model.load()
        await model.load()
        await model.loadTreesIfNeeded()
        await model.loadTreesIfNeeded()

        #expect(counter.speciesReads == 1, "the species read ran \(counter.speciesReads) times for three visits")
        #expect(counter.treeReads == 1, "the trees read ran \(counter.treeReads) times for two visits")
        guard case .loaded = model.phase, case .loaded = model.treesPhase else {
            Issue.record("a repeat visit lost the grove: \(model.phase) / \(model.treesPhase)")
            return
        }
    }

    /// **…and a repeat visit still refreshes.** The guard above must not be the reason a second
    /// device's work never shows up: the ruling is "paint the last data instantly *and* refresh in
    /// the background", and a guard that skipped both halves would deliver only the first.
    @Test("a repeat load still starts a background refresh")
    func aRepeatLoadStillRefreshes() async throws {
        let transport = Self.gatedService()
        let router = Self.router(try Self.localDouble(), transport, log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { Self.laterMet },
            refreshSpecies: { try? await router.refreshedGroveSpecies() }
        )

        await model.load()
        await transport.gate.open()
        await model.speciesRefresh?.value

        // The second visit: nothing is re-read, and the refresh runs again.
        await model.load()
        await model.speciesRefresh?.value

        #expect(
            transport.calls.count == 2,
            "the second visit asked the service \(transport.calls.count - 1) times instead of once"
        )
        guard case let .loaded(merged) = model.phase else {
            Issue.record("the repeat visit lost the grove: \(model.phase)")
            return
        }
        #expect(merged.known.items.count == 2)
    }

    /// **No refresher means no background task at all.**
    ///
    /// This is the shape every preview, every screenshot fixture and — because `DataLayer.boot`
    /// leaves both nil when the remote gate is shut — the whole UI suite runs in. A model that
    /// started a task anyway would be doing a second read of the phone on every appearance of the
    /// tab for a merge that has nothing to merge.
    @Test("a model with no refresher starts no task")
    func aModelWithNoRefresherStartsNoTask() async throws {
        let model = GroveModel(api: GrovePreviewAPI(), now: { Self.laterMet }, tab: .trees)

        await model.load()
        await model.loadTreesIfNeeded()

        #expect(model.speciesRefresh == nil, "a model with no species refresher started one")
        #expect(model.treesRefresh == nil, "a model with no trees refresher started one")
    }

    // MARK: The wiring, so the refresh cannot go missing silently

    /// **`DataLayer.boot` fills both refreshers when the gate is open, and neither when it is shut.**
    ///
    /// Without this the local-first paint would be indistinguishable from a router that simply
    /// stopped asking the service — which is the same defect class `DataLayerWiringTests` exists for
    /// and the reason the send sink is asserted there rather than assumed.
    @Test("the composition root wires the refreshes with the gate open and omits them with it shut")
    func theCompositionRootWiresTheRefreshes() async throws {
        let live = try await DataLayer.boot(
            databaseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cypress-grove-localfirst-live-\(UUID().uuidString).sqlite"),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            transport: ScriptedTransport(),
            credentials: InMemoryCredentialStore(),
            storageSession: OfflineSession.make()
        )
        #expect(live.refreshGroveSpecies != nil, "a live layer has no species refresh to run")
        #expect(live.refreshGrove != nil, "a live layer has no trees refresh to run")

        let offline = try await DataLayer.boot(
            databaseURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cypress-grove-localfirst-off-\(UUID().uuidString).sqlite"),
            seedURL: nil,
            baseURL: URL(string: "https://cypress-sync.invalid/api/v1")!,
            remoteAccess: .disabled,
            credentials: InMemoryCredentialStore(),
            storageSession: OfflineSession.make()
        )
        #expect(offline.refreshGroveSpecies == nil, "the gate is shut and a refresh was wired anyway")
        #expect(offline.refreshGrove == nil, "the gate is shut and a refresh was wired anyway")
    }

    /// **The service's own session has a request timeout, and `URLSession.shared` does not.**
    ///
    /// The negative control is the whole test: `.shared`'s configuration is a copy that cannot be
    /// written to, so it carries the platform default forever — which is what every request to this
    /// service used to travel under, and why an unreachable host cost a minute rather than a moment.
    /// Comparing the two is what makes this a measurement rather than a restatement of the literal.
    @Test("the service's session times a stalled request out, unlike the shared one")
    func theServiceSessionHasATimeout() {
        let configured = SyncService.makeSession().configuration.timeoutIntervalForRequest
        #expect(configured == SyncService.requestTimeout)
        #expect(
            configured < URLSession.shared.configuration.timeoutIntervalForRequest,
            "the session this app builds is no tighter than the shared one it replaced"
        )
    }
}

// MARK: - Counting the phone's reads

/// How many times the phone was asked. A reference type because `CountingLocal` is a struct and the
/// model holds its own copy — `DeletionRecorder`'s argument, for `DeletionRecorder`'s reason.
final class ReadCounter: @unchecked Sendable {

    private let lock = NSLock()
    private var species = 0
    private var trees = 0

    var speciesReads: Int {
        lock.lock(); defer { lock.unlock() }
        return species
    }

    var treeReads: Int {
        lock.lock(); defer { lock.unlock() }
        return trees
    }

    func countSpecies() {
        lock.lock(); defer { lock.unlock() }
        species += 1
    }

    func countTrees() {
        lock.lock(); defer { lock.unlock() }
        trees += 1
    }
}

// `LocalDouble.reads` is where this is attached; see that property.

// MARK: - The batched resolver answers what the per-row loop answered

/// **`LocalAPI.groveCityFileRows(for:)` reads the whole set in three statements and answers what
/// `RoutedAPI`'s per-row loop answered.**
///
/// `GroveBatchReadTests`' argument, one layer up. The loop this replaces ran
/// `LocalAPI.treeProfile(id:)` once per row the service named that the phone did not have — the
/// app's most expensive single-row read, for a row that draws a string and a pin — and it ran it
/// through `any CypressAPI`, which is why it survived the two rounds that removed the same N+1 from
/// `LocalAPI.grove()` and `speciesGuide`.
///
/// Every name below is checked **against the per-row form itself**, which is still in `RoutedAPI`
/// as the fallback for a router with no provider. That is a comparison rather than a restatement of
/// what the new code does — the distinction `GroveBatchReadTests` makes and this suite inherits.
@Suite("My Grove · the batched city-file resolver answers what the per-row loop answered")
struct GroveCityFileBatchTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000901")!
    private static let phantom = UUID(uuidString: "F0000000-0000-4000-8000-0000000009FF")!

    private static func openSeeded() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        return (LocalAPI(store: store, deviceID: deviceID), store)
    }

    private static func name(_ treeID: UUID, _ nickname: String, store: CypressStore) async throws {
        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                TreeName(treeID: treeID, name: nickname, givenBy: nil), connection: connection
            )
        }
    }

    /// The per-row form, lifted out of `RoutedAPI.resolvedCityFileRows(for:)` so the two can be
    /// compared. It is the same three lines, and if it drifts from that method this suite is
    /// comparing the batch against a copy — which is why it is written here as narrowly as possible
    /// and why `RoutedAPI`'s own tests exercise the real one.
    private static func perRow(_ treeID: UUID, api: LocalAPI) async -> RoutedAPI.CityFileRow? {
        guard let profile = try? await api.treeProfile(id: treeID) else { return nil }
        guard let name = profile.activeName?.name ?? profile.species?.commonName, !name.isEmpty else {
            return nil
        }
        return RoutedAPI.CityFileRow(displayName: name, coordinate: profile.tree.coordinate)
    }

    @Test("seed trees named and unnamed, a community tree, and an id nobody holds")
    func theBatchedResolverKeepsEveryRule() async throws {
        let (api, store) = try await Self.openSeeded()

        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let named = try #require(
            candidates.first(where: { $0.speciesCommonName != nil }),
            "no seed tree near the opening center carries a species with a common name"
        )
        let unnamed = try #require(
            candidates.first(where: { $0.speciesCommonName != nil && $0.tree.id != named.tree.id }),
            "the fixture needs two distinct seed trees with a species common name"
        )

        let attribution = await api.attribution
        let communityNamed = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7695, longitude: -122.4863),
                photoLocalPath: "/tmp/cypress-grove-cityfile-a.jpg",
                attribution: attribution
            )
        ).id
        let communityBare = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7696, longitude: -122.4864),
                photoLocalPath: "/tmp/cypress-grove-cityfile-b.jpg",
                attribution: attribution
            )
        ).id

        try await Self.name(named.tree.id, "The Corner Elder", store: store)
        try await Self.name(communityNamed, "The Sapling", store: store)

        let ids = [named.tree.id, unnamed.tree.id, communityNamed, communityBare, Self.phantom]
        let rows = await api.groveCityFileRows(for: ids)

        // Calibration: the resolver answers at all, and it does not answer for everything. A
        // resolver returning `[:]` and one returning a row per id would each make the comparison
        // below agree with itself for the wrong reason.
        #expect(!rows.isEmpty, "the batched resolver answered for nothing — this gate is vacuous")
        #expect(
            rows[Self.phantom] == nil,
            "an id neither the inventory nor this device holds was given a name and a coordinate"
        )

        #expect(rows[named.tree.id]?.displayName == "The Corner Elder", "the nickname lost")
        #expect(
            rows[unnamed.tree.id]?.displayName == unnamed.speciesCommonName,
            "a seed tree with no nickname did not fall back to its species' common name"
        )
        #expect(rows[named.tree.id]?.coordinate == named.tree.coordinate)
        #expect(rows[communityNamed]?.displayName == "The Sapling")
        #expect(
            rows[communityNamed]?.coordinate == Coordinate(latitude: 37.7695, longitude: -122.4863),
            "a community tree's coordinate did not survive the batch"
        )
        // D15, which is `LocalAPI.grove()`'s rule for the same fallback: a community tree with no
        // nickname has no name the app is willing to put on it, so it is absent rather than empty.
        #expect(rows[communityBare] == nil)

        // …and every id against the per-row form, which is the comparison rather than a restatement.
        for id in ids {
            let loop = await Self.perRow(id, api: api)
            #expect(
                rows[id] == loop,
                "\(id): batched \(String(describing: rows[id])) against per-tree \(String(describing: loop))"
            )
        }
    }

    /// **An empty set asks for nothing**, which is the guard the three statements carry and not a
    /// courtesy: `json_each('[]')` is legal, `IN ()` is not, and a single-device installation takes
    /// this path on every refresh it ever runs.
    @Test("no unresolved rows means no read")
    func anEmptySetReadsNothing() async throws {
        let (api, _) = try await Self.openSeeded()
        #expect(await api.groveCityFileRows(for: []).isEmpty)
        #expect(await api.species(ids: []).isEmpty)
    }

    /// The species half of the same batch: the same answer `species(id:)` gives, one call instead of
    /// one call per id, and an id the inventories do not carry simply absent.
    @Test("the batched species read answers what the single read answers")
    func theBatchedSpeciesReadAgrees() async throws {
        let (api, _) = try await Self.openSeeded()
        // Real seed species rather than invented ids — nothing here fabricates botany.
        let found = try await api.searchSpecies(query: "oak", limit: 5)
        let speciesIDs = found.map(\.id)
        try #require(speciesIDs.count >= 2, "the seed carries fewer than two species matching 'oak'")

        let missing = UUID()
        let batched = await api.species(ids: speciesIDs + [missing])

        #expect(batched.count == speciesIDs.count, "the batch answered for an id nothing holds")
        #expect(batched[missing] == nil)
        for id in speciesIDs {
            let single = try await api.species(id: id)
            #expect(batched[id]?.scientificName == single.scientificName)
            #expect(batched[id]?.commonName == single.commonName)
        }
    }
}
