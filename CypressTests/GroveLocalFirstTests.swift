//
//  GroveLocalFirstTests.swift
//  CypressTests
//
//  **My Grove paints from the phone and merges the account's half behind it** — the owner's ruling
//  of 2026-09-01, and the gates that make it unrepeatable.
//
//  ── Why there is not a single number in this file ─────────────────────────────────────────────
//
//  The defect is "the first frame waits for a network round trip", and the tempting test is "the
//  read returned in under N milliseconds". That test is a coin toss on a loaded machine and it has
//  already cost this project a flaky suite once (`docs/whats-new/test-perf-margin-redesign.md`:
//  count work, do not race a clock). PR #140's principle is that **no clock is read anywhere**, and
//  what replaces it here are two censuses, neither of which can be nearly-right.
//
//  1. **The paint made zero requests, and the phone's answer is what it drew.** `transport.calls` is
//     read *after* the read returned, and the phone's grove holds one species where the merged one
//     holds two. A paint that awaited the service would have a call in the census and two species in
//     the answer, whatever the machine was doing at the time.
//  2. **The merge is awaited, not waited for.** `GroveModel.speciesRefresh` is the model's own handle
//     on the background task, so `await model.speciesRefresh?.value` returns exactly when the merge
//     has been applied. That is a structural fact about the work rather than a guess about how long
//     it takes, and it is what makes the call counts in `aRepeatLoadStillRefreshes` exact.
//
//  **A deliberately absent third idea: a transport that blocks.** Holding the service's answer behind
//  a latch reads as the strongest possible statement of the defect — assert while the far side is
//  provably still in flight — and it is the wrong instrument here. A regression to the blocking paint
//  would **hang** on such a latch rather than fail, and a hang is not a red-proof: it is a stalled
//  suite that has to be killed and interpreted. The censuses above go red, and say why.

import Foundation
import Testing
@testable import Cypress

// MARK: - The fixture's clock, outside the suite

/// The two instants the fixtures are built from.
///
/// **They live here rather than on the suite because the suite is `@MainActor`**, which makes its
/// static properties main-actor isolated — and `GroveModel(now:)` takes a `@Sendable () -> Date`, so
/// a closure reading one of them reads main-actor state from a `Sendable` context. That is a warning
/// today and an error in the Swift 6 language mode, and this repository holds a zero-warning line
/// across both targets. A free enum has no isolation to cross.
enum GroveFirstClock {
    static let firstMet = Date(timeIntervalSince1970: 1_700_000_000)
    static let laterMet = Date(timeIntervalSince1970: 1_780_000_000)
}

// MARK: - The gates

@MainActor
@Suite("My Grove · the phone paints first and the account's half arrives behind it")
struct GroveLocalFirstTests {

    static let speciesID = UUID(uuidString: "5E000000-0000-4000-8000-000000000001")!
    static let accountSpeciesID = UUID(uuidString: "5E000000-0000-4000-8000-000000000002")!
    static let treeID = UUID(uuidString: "77000000-0000-4000-8000-000000000001")!
    static let accountTreeID = UUID(uuidString: "77000000-0000-4000-8000-000000000002")!

    /// Named here as well, so a fixture reads `Self.laterMet` like every other constant in the
    /// suite. See `GroveFirstClock` for why the values are not declared on this type.
    static let firstMet = GroveFirstClock.firstMet
    static let laterMet = GroveFirstClock.laterMet

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
        // **The nickname is load-bearing, not decoration** (PR #144 review, F1b). This row is a
        // `.community` record, and D15 does not name one after a species somebody asserted about it
        // — so with only the species it has no name the app will draw and *both* resolver arms drop
        // it, which would make every merge assertion below about a row that never arrives. A
        // nickname is what a contributor gives a tree they added, and it is what D15 names.
        local.profilesByID = [
            accountTreeID: TreeProfile(
                tree: Tree(
                    id: accountTreeID,
                    source: .community,
                    coordinate: Coordinate(latitude: 37.76, longitude: -122.50)
                ),
                activeName: TreeName(treeID: accountTreeID, name: "The Corner Oak", givenBy: nil),
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

    /// The phone's answer after a second species has been met on **this** device — the local write a
    /// repeat visit has to pick up.
    static func twoSpeciesLocally() throws -> GroveSpecies {
        GroveSpecies(
            neighborhood: GroveNeighborhood(area: .radius(meters: 500), species: Series(complete: [speciesID])),
            known: Series(complete: [
                KnownSpecies(
                    speciesID: speciesID,
                    scientificName: "Platanus × acerifolia",
                    commonName: "London Plane",
                    firstMetAt: GroveFirstClock.laterMet,
                    firstMetAddress: "Noriega St"
                ),
                KnownSpecies(
                    speciesID: accountSpeciesID,
                    scientificName: "Quercus agrifolia",
                    commonName: "Coast Live Oak",
                    firstMetAt: GroveFirstClock.laterMet,
                    firstMetAddress: nil
                )
            ])
        )
    }

    /// A service holding one species and one tree this phone has never met.
    static func scriptedService() -> ScriptedTransport {
        let transport = ScriptedTransport()
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

    /// A router over the `LocalDouble` fixture, with **no resolver providers** — deliberately the
    /// nil arm, and labelled as such because PR #144's review found this helper being read as though
    /// it were the shipping composition.
    ///
    /// It is not. `DataLayer.boot` fills `resolveGroveRows` and `resolveSpecies`, and the arm that
    /// ships is covered two ways rather than by pretending this one is it:
    /// `theShippingRouterMergesThroughTheBatchedResolver` below builds a router the way `boot` does,
    /// over a real `LocalAPI` and the real seed; and `GroveCityFileBatchTests` holds the two arms
    /// against each other row for row — calling `RoutedAPI.resolvedCityFileRows` itself for the loop,
    /// not a copy of it — over a fixture that carries the row shape they once disagreed on.
    static func router(_ local: LocalDouble, _ transport: ScriptedTransport, log: RemoteReadLog) -> RoutedAPI {
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
    /// - the phone really **answers** — one species, which is what the paint assertions are about;
    /// - the scripted routes really **decode** — an unscripted or malformed answer comes back as a
    ///   throw the router swallows into its documented fallback, so "the merge did not arrive"
    ///   would be true for a reason that has nothing to do with the code under test, and the whole
    ///   file would be green on a service that was never reached;
    /// - the two answers are **distinguishable** — one species against two. Without that, "the paint
    ///   drew the phone's grove" and "the merge landed" are the same observation.
    @Test("the phone answers one species, the service's route decodes, and two is not one")
    func theFixtureAnswersWhatItClaimsTo() async throws {
        let transport = Self.scriptedService()
        let log = RemoteReadLog()
        let router = Self.router(try Self.localDouble(), transport, log: log)

        #expect(try await router.groveSpecies().known.items.count == 1, "the phone's half is not one species")

        let merged = try await router.refreshedGroveSpecies()

        #expect(merged.known.items.count == 2, "the route did not decode, or the merge dropped a row")
        #expect(transport.calls.count == 1, "the refresh asked the service \(transport.calls.count) times")
        #expect(await log.outcome(of: .groveSpecies) == .live, "the refresh did not resolve every row")
    }

    // MARK: The paint

    /// **`groveSpecies()` answers from the phone and asks the service nothing.**
    ///
    /// This is the reported defect as a test. The Species pill is the tab My Grove opens on, and its
    /// read used to `await remote.groveSpeciesDelta()` before returning anything — so the first frame
    /// cost a round trip, and on an unreachable host it cost `URLSession`'s untouched 60-second
    /// default.
    ///
    /// The service here answers instantly and correctly, which is what makes the census decisive
    /// rather than incidental: there is nothing slow to notice, and the assertion is still that the
    /// paint did not ask.
    @Test("the species read answers from the phone and asks the service nothing")
    func theSpeciesReadAnswersFromThePhone() async throws {
        let transport = Self.scriptedService()
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

    }

    /// The Trees pill, on the same terms.
    @Test("the trees read answers from the phone and asks the service nothing")
    func theTreesReadAnswersFromThePhone() async throws {
        let transport = Self.scriptedService()
        let log = RemoteReadLog()
        let router = Self.router(try Self.localDouble(), transport, log: log)

        let painted = try await router.grove()

        #expect(painted.count == 1, "the paint did not answer with the phone's grove")
        #expect(painted.first?.treeID == Self.treeID)
        #expect(transport.calls.isEmpty, "the paint reached the service")
        #expect(await log.outcome(of: .grove) == nil)

    }

    // MARK: The model, which is where the two halves are visible at once

    /// **The screen is drawn from the phone, and the account's species appears when it arrives.**
    ///
    /// Both halves of the ruling in one test, and neither half reads a clock. The first assertion is
    /// a census — one species drawn, no request made — taken the instant `load()` returns; the second
    /// is taken after `speciesRefresh`, the model's own handle on the background task, has completed.
    /// A `load()` that awaited the merge would fail the first assertion with two species in hand,
    /// which is the shape this whole round is about.
    @Test("the model paints one species, then two when the service answers")
    func theModelPaintsThenMerges() async throws {
        let transport = Self.scriptedService()
        let router = Self.router(try Self.localDouble(), transport, log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { GroveFirstClock.laterMet },
            refreshSpecies: { try? await router.refreshedGroveSpecies() }
        )

        await model.load()

        guard case let .loaded(painted) = model.phase else {
            Issue.record("the first read did not paint: \(model.phase)")
            return
        }
        #expect(painted.known.items.count == 1, "the paint waited for the service")
        #expect(transport.calls.isEmpty, "the paint reached the service")

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
        let transport = Self.scriptedService()
        let router = Self.router(try Self.localDouble(), transport, log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { GroveFirstClock.laterMet },
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
        let router = Self.router(try Self.localDouble(), ScriptedTransport(), log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { GroveFirstClock.laterMet },
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

    /// **A refresh the model cancelled records nothing; one that was actually refused records the
    /// refusal.** PR #144's review, F4.
    ///
    /// `GroveModel` cancels an in-flight refresh whenever the tab is re-entered, and
    /// `try? await remote.groveSpeciesDelta()` answers nil for a cancellation exactly as it does for
    /// an unreachable host. Without the guard, flipping tabs twice quickly left `.fellBackToLocal` in
    /// the log against a service that was perfectly reachable — "we did not ask" reported as "we
    /// asked and could not reach it", which `RemoteReadLog.outcome(of:)` exists to keep apart.
    ///
    /// **The cancellation is ordered, not raced.** The suite is `@MainActor`; the child task cannot
    /// begin until this function suspends, and `cancel()` is called before it does. So the body runs
    /// already-cancelled, every time.
    ///
    /// The second half is the calibration and it is the whole test: an identical router that is *not*
    /// cancelled must still record the refusal, or "records nothing" would be true because nothing
    /// ever records anything.
    @Test("a cancelled refresh records nothing, and an uncancelled refusal still records")
    func aCancelledRefreshRecordsNothing() async throws {
        let cancelledLog = RemoteReadLog()
        let cancelledRouter = Self.router(try Self.localDouble(), ScriptedTransport(), log: cancelledLog)
        let task = Task { _ = try? await cancelledRouter.refreshedGroveSpecies() }
        task.cancel()
        await task.value

        let cancelled = await cancelledLog.outcome(of: .groveSpecies)
        #expect(
            cancelled == nil,
            "a refresh this app called off was recorded as \(String(describing: cancelled))"
        )

        // Calibration: the same unreachable service, not cancelled, still marks the read.
        let refusedLog = RemoteReadLog()
        let refusedRouter = Self.router(try Self.localDouble(), ScriptedTransport(), log: refusedLog)
        _ = try await refusedRouter.refreshedGroveSpecies()
        let refused = await refusedLog.outcome(of: .groveSpecies)
        #expect(
            refused == .fellBackToLocal,
            "an unreachable service recorded \(String(describing: refused)) — this gate is vacuous"
        )
    }

    // MARK: The lifetime, which is what a tab switch costs

    /// **A repeat visit re-reads the phone and never the service, and never blanks the screen.**
    ///
    /// `RootView.tabRoot` rebuilds the arm it selects, so `GroveView.task` fires on every return to
    /// the tab. With the model owned above the switch (`RootView.grove`) that is a repeat call on a
    /// model that already has an answer.
    ///
    /// **This test pinned the wrong contract in the first cut of this PR, and PR #144's review is
    /// why it now pins this one.** It asserted one local read for three visits — a model that, with
    /// no refresher wired, never re-read anything at all. That is every DEBUG build and the whole UI
    /// suite, and it meant the Grove tab was frozen for the life of the process: favorite a tree from
    /// the Map, come back, and the pill still said what it said. The contract is not "do not read", it
    /// is **"do not go back to the network, and do not go back to blank"**: the phone is re-read on
    /// every visit (≈6 ms), the phase never returns to `.loading` or `.idle`, and the service is
    /// reached only by the background refresh, which this model has none of.
    ///
    /// The second half is the one that would have caught the freeze, and it is asserted as a fact
    /// about the *answer* rather than about a count: the phone's answer changes between visits, and
    /// the screen has to change with it.
    @Test("a repeat visit re-reads the phone, never the service, and never blanks")
    func aRepeatVisitRepaintsFromThePhone() async throws {
        let probe = GroveReadProbe()
        var local = try Self.localDouble()
        local.reads = probe
        let model = GroveModel(api: local, now: { GroveFirstClock.laterMet }, tab: .trees)

        // Calibration: the probe counts. Without this, any number below and "the probe is broken"
        // agree with each other.
        await model.load()
        await model.loadTreesIfNeeded()
        #expect(probe.speciesReads == 1, "the probe did not see the first species read")
        #expect(probe.treeReads == 1, "the probe did not see the first trees read")

        // A local write lands between visits — a visit logged from a tree profile is exactly this.
        probe.setSpecies(try Self.twoSpeciesLocally())
        probe.setTrees([
            GroveEntry(
                treeID: Self.treeID,
                displayName: "London Plane",
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                lastVisitedAt: GroveFirstClock.laterMet,
                isFavorite: true
            ),
            GroveEntry(
                treeID: Self.accountTreeID,
                displayName: "The Corner Oak",
                coordinate: Coordinate(latitude: 37.76, longitude: -122.50),
                lastVisitedAt: nil,
                isFavorite: false
            )
        ])

        await model.load()
        await model.loadTreesIfNeeded()

        #expect(probe.speciesReads == 2, "the second visit made \(probe.speciesReads) species reads")
        #expect(probe.treeReads == 2, "the second visit made \(probe.treeReads) trees reads")

        guard case let .loaded(species) = model.phase, case let .loaded(trees) = model.treesPhase else {
            Issue.record("a repeat visit lost the grove: \(model.phase) / \(model.treesPhase)")
            return
        }
        #expect(species.known.items.count == 2, "the revisit did not pick up a species logged since")
        #expect(trees.count == 2, "the revisit did not pick up a tree logged since")

        // And no service was reached: this model has no refresher, so no task was started at all.
        #expect(model.speciesRefresh == nil)
        #expect(model.treesRefresh == nil)
    }

    /// **…and a repeat visit still refreshes.** The guard above must not be the reason a second
    /// device's work never shows up: the ruling is "paint the last data instantly *and* refresh in
    /// the background", and a guard that skipped both halves would deliver only the first.
    @Test("a repeat load still starts a background refresh")
    func aRepeatLoadStillRefreshes() async throws {
        let transport = Self.scriptedService()
        let router = Self.router(try Self.localDouble(), transport, log: RemoteReadLog())
        let model = GroveModel(
            api: router,
            now: { GroveFirstClock.laterMet },
            refreshSpecies: { try? await router.refreshedGroveSpecies() }
        )

        await model.load()
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
        let model = GroveModel(api: GrovePreviewAPI(), now: { GroveFirstClock.laterMet }, tab: .trees)

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

/// How many times the phone was asked, and what it should answer next.
///
/// A reference type because `LocalDouble` is a struct and the model holds its own copy — a plain
/// `var` counter would be incremented on a value the test cannot see, which is `DeletionRecorder`'s
/// argument in `RoutedAPITests` and its reason.
///
/// **It carries the answers as well as the counts**, because the contract a repeat visit has to keep
/// is not "how many reads" — it is "the screen shows what the phone now says". Counting alone was
/// what let the frozen-tab defect through PR #144's first cut: one read for three visits looked like
/// thrift and was a tab that never updated again.
final class GroveReadProbe: @unchecked Sendable {

    private let lock = NSLock()
    private var species = 0
    private var trees = 0
    private var speciesAnswer: GroveSpecies?
    private var treesAnswer: [GroveEntry]?

    var speciesReads: Int {
        lock.lock(); defer { lock.unlock() }
        return species
    }

    var treeReads: Int {
        lock.lock(); defer { lock.unlock() }
        return trees
    }

    /// What the phone answers from the next read onward. Nil until a test says otherwise, which
    /// means "whatever the `LocalDouble` was built with".
    func setSpecies(_ value: GroveSpecies) {
        lock.lock(); defer { lock.unlock() }
        speciesAnswer = value
    }

    func setTrees(_ value: [GroveEntry]) {
        lock.lock(); defer { lock.unlock() }
        treesAnswer = value
    }

    func takeSpecies(or fallback: GroveSpecies) -> GroveSpecies {
        lock.lock(); defer { lock.unlock() }
        species += 1
        return speciesAnswer ?? fallback
    }

    func takeTrees(or fallback: [GroveEntry]) -> [GroveEntry] {
        lock.lock(); defer { lock.unlock() }
        trees += 1
        return treesAnswer ?? fallback
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
/// Every name below is checked **against `RoutedAPI.resolvedCityFileRows` itself**, called with no
/// provider so it takes its loop arm. Not a copy of the loop lifted into this file: PR #144's review
/// found the arms disagreeing on a row shape the fixture did not contain, and a lifted copy is a
/// third implementation that would have hidden the disagreement a second time. Comparing the real
/// two is the distinction `GroveBatchReadTests` makes and this suite inherits.
///
/// **The row they disagreed on is now in the fixture**: a community record carrying a self-asserted
/// species and no nickname. D15 gives it no name — `LocalAPI.grove()` has always refused to name a
/// tree after somebody's claim about it — and both arms now say so.
@Suite("My Grove · the batched city-file resolver answers what the per-row loop answered")
struct GroveCityFileBatchTests {

    private static let deviceID = UUID(uuidString: "9E00B47C-0000-4000-8000-000000000901")!
    private static let phantom = UUID(uuidString: "F0000000-0000-4000-8000-0000000009FF")!

    private static func openSeeded() async throws -> (api: LocalAPI, store: CypressStore) {
        let url = try #require(InventoryContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        let store = try await CypressStore.inMemory(seedURL: url)
        return (LocalAPI(store: store, deviceID: deviceID), store)
    }

    /// Puts a tree in the grove the way a walk does — a visit, which is what `groveTreeIDs` reads.
    private static func visit(_ treeID: UUID, api: LocalAPI, store: CypressStore) async throws {
        let attribution = await api.attribution
        try await store.queue.write { connection in
            try ContributionStore().insert(
                Visit(treeID: treeID, attribution: attribution, capturedAt: Date()),
                connection: connection
            )
        }
    }

    private static func name(_ treeID: UUID, _ nickname: String, store: CypressStore) async throws {
        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                TreeName(treeID: treeID, name: nickname, givenBy: nil), connection: connection
            )
        }
    }

    /// **The real loop arm**, reached by building the router with no provider.
    ///
    /// `RoutedAPI.resolvedCityFileRows(for:)` is internal precisely so this is possible; its own
    /// comment says why. The remote half refuses everything and is never touched — this method does
    /// not go near the wire.
    private static func loopArm(over api: LocalAPI) -> RoutedAPI {
        RoutedAPI(
            local: api,
            remote: RemoteAPI(
                baseURL: URL(string: "https://service.invalid/api/v1")!,
                transport: ScriptedTransport(),
                session: .shared
            )
        )
    }

    /// The router `DataLayer.boot` builds: the same two providers, out of the same `LocalAPI`.
    ///
    /// Written as one helper so a test cannot accidentally exercise the fallback while believing it
    /// is exercising the shipping composition — which is the mistake PR #144's review found.
    static func shippingRouter(
        over api: LocalAPI,
        transport: ScriptedTransport,
        log: RemoteReadLog = RemoteReadLog()
    ) -> RoutedAPI {
        RoutedAPI(
            local: api,
            remote: RemoteAPI(
                baseURL: URL(string: "https://service.invalid/api/v1")!,
                transport: transport,
                session: .shared
            ),
            log: log,
            resolveGroveRows: { ids in await api.groveCityFileRows(for: ids) },
            resolveSpecies: { ids in await api.species(ids: ids) }
        )
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
        // **The row PR #144's review proved the two arms disagreed on.** A community record with a
        // *claimed* species and no nickname: `TreeDraft.speciesID` is the community-add screen's own
        // optional species (BUILD-PLAN §6), so this is a shape a contributor produces. The loop used
        // to name it after the claim, because `LocalAPI.treeProfile` fills `species` for a community
        // row out of `tree.speciesCurrentID`; D15 says a self-assertion is not a name the app puts
        // on a tree, and both arms now agree that it has none.
        let seedSpecies = try #require(
            try await api.searchSpecies(query: "oak", limit: 1).first,
            "the seed carries no species matching 'oak' to claim"
        )
        let communityClaimed = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7697, longitude: -122.4865),
                speciesID: seedSpecies.id,
                photoLocalPath: "/tmp/cypress-grove-cityfile-c.jpg",
                attribution: attribution
            )
        ).id

        try await Self.name(named.tree.id, "The Corner Elder", store: store)
        try await Self.name(communityNamed, "The Sapling", store: store)

        let ids = [
            named.tree.id, unnamed.tree.id, communityNamed, communityBare, communityClaimed, Self.phantom
        ]
        let rows = await api.groveCityFileRows(for: ids)

        // Calibration: the resolver answers at all, and it does not answer for everything. A
        // resolver returning nothing and one returning a row per id would each make the comparison
        // below agree with itself for the wrong reason.
        #expect(!rows.named.isEmpty, "the batched resolver named nothing — this gate is vacuous")
        #expect(
            rows.named[Self.phantom] == nil && !rows.unnamed.contains(Self.phantom),
            "an id neither the inventory nor this device holds was resolved"
        )

        #expect(rows.named[named.tree.id]?.displayName == "The Corner Elder", "the nickname lost")
        #expect(
            rows.named[unnamed.tree.id]?.displayName == unnamed.speciesCommonName,
            "a seed tree with no nickname did not fall back to its species' common name"
        )
        #expect(rows.named[named.tree.id]?.coordinate == named.tree.coordinate)
        #expect(rows.named[communityNamed]?.displayName == "The Sapling")
        #expect(
            rows.named[communityNamed]?.coordinate == Coordinate(latitude: 37.7695, longitude: -122.4863),
            "a community tree's coordinate did not survive the batch"
        )
        // D15, twice: a community tree with no nickname has no name the app will draw, whether or
        // not somebody has claimed a species for it.
        #expect(rows.named[communityBare] == nil)
        #expect(rows.named[communityClaimed] == nil, "a community tree was named after a claimed species")

        // **And the two are in `unnamed`, not merely absent** — the distinction that decides whether
        // the caller calls the read degraded. The phantom is in neither, which is what "the service's
        // answer lost a row" looks like.
        #expect(
            rows.unnamed == [communityBare, communityClaimed],
            "the D15 refusals were reported as \(rows.unnamed), which is not the pair that has no name"
        )

        // …and every id against the real loop arm, which is the comparison rather than a restatement.
        let loop = await Self.loopArm(over: api).resolvedCityFileRows(for: ids)
        #expect(
            rows.named == loop.named,
            "batched \(rows.named.mapValues(\.displayName)) against loop \(loop.named.mapValues(\.displayName))"
        )
        #expect(
            rows.unnamed == loop.unnamed,
            "batched refused \(rows.unnamed) and the loop refused \(loop.unnamed)"
        )
    }

    /// **An empty set asks for nothing**, which is the guard the three statements carry and not a
    /// courtesy: `json_each('[]')` is legal, `IN ()` is not, and a single-device installation takes
    /// this path on every refresh it ever runs.
    @Test("no unresolved rows means no read")
    func anEmptySetReadsNothing() async throws {
        let (api, _) = try await Self.openSeeded()
        let nothing = await api.groveCityFileRows(for: [])
        #expect(nothing.named.isEmpty && nothing.unnamed.isEmpty)
        #expect(await api.species(ids: []).isEmpty)
    }

    // MARK: - The composition that ships

    /// **A merge through the router `DataLayer.boot` actually builds.**
    ///
    /// PR #144's review found every merge gate in this file running the *fallback* arm, because the
    /// helper that built the routers passed no providers. So the batched resolver — the one that
    /// ships — was exercised only by comparing it against a lifted copy of the loop. This test wires
    /// `boot`'s two closures over a real `LocalAPI` and the real seed, and asserts both halves of the
    /// join: a seed tree the account named reaches the screen, and the D15 refusal does **not** make
    /// the read degraded.
    @Test("the shipping router merges an account's tree and stays live through a D15 refusal")
    func theShippingRouterMergesThroughTheBatchedResolver() async throws {
        let (api, store) = try await Self.openSeeded()

        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let seedTree = try #require(
            candidates.first(where: { $0.speciesCommonName != nil }),
            "no seed tree near the opening center carries a species with a common name"
        )
        try await Self.name(seedTree.tree.id, "The Corner Elder", store: store)

        // The account also names a tree this phone holds as a nickname-less community record with a
        // claimed species — the shape D15 refuses. It is dropped, and the read is still live.
        let attribution = await api.attribution
        let seedSpecies = try #require(try await api.searchSpecies(query: "oak", limit: 1).first)
        let refused = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.7698, longitude: -122.4866),
                speciesID: seedSpecies.id,
                photoLocalPath: "/tmp/cypress-grove-shipping-a.jpg",
                attribution: attribution
            )
        ).id

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[
             {"tree_uuid":"\(seedTree.tree.id.uuidString)","last_visited_at":null,"is_favorite":true,
              "record":null,"hero_photo_id":null},
             {"tree_uuid":"\(refused.uuidString)","last_visited_at":null,"is_favorite":true,
              "record":null,"hero_photo_id":null}],"total":2}
            """
        )

        let log = RemoteReadLog()
        let entries = try await Self.shippingRouter(over: api, transport: transport, log: log).refreshedGrove()

        // Calibration: the account's row really did have to be resolved through the city file — this
        // phone's own grove is empty, so nothing here could have come from `local.grove()`.
        #expect(try await api.grove().isEmpty, "the phone's own grove is not empty; this gate is not testing the join")

        #expect(entries.count == 1, "the merge produced \(entries.map(\.displayName))")
        #expect(entries.first?.treeID == seedTree.tree.id)
        #expect(entries.first?.displayName == "The Corner Elder", "the batched resolver did not name the row")
        #expect(entries.first?.coordinate == seedTree.tree.coordinate)
        #expect(entries.contains { $0.treeID == refused } == false, "a community tree was named after a claim")

        // **The point of the whole `CityFileRows` split.** The service answered completely and a
        // local rule dropped one of its rows; that is not a fallback, and saying so would offer a
        // §4.3 surface "showing what's on this phone" about a read where nothing was missing.
        let outcome = await log.outcome(of: .grove)
        #expect(outcome == .live, "a D15 refusal was recorded as \(String(describing: outcome))")
    }

    /// **…and a row the inventories genuinely do not carry still marks the read degraded**, which is
    /// the other side of the same split and the reason it is not simply "never degrade".
    @Test("a tree no installed inventory carries still marks the read degraded")
    func anUncarriedTreeStillDegradesTheRead() async throws {
        let (api, _) = try await Self.openSeeded()
        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(Self.phantom.uuidString)","last_visited_at":null,
             "is_favorite":true,"record":null,"hero_photo_id":null}],"total":1}
            """
        )

        let log = RemoteReadLog()
        let entries = try await Self.shippingRouter(over: api, transport: transport, log: log).refreshedGrove()

        #expect(entries.isEmpty)
        let outcome = await log.outcome(of: .grove)
        #expect(
            outcome == .fellBackToLocal,
            "part of the service's answer was lost and the read reported \(String(describing: outcome))"
        )
    }

    /// **The batched arm does not grow with the number of rows the account named; the loop does.**
    ///
    /// The census (#143's `StatementCensus`) counts hops onto the database queue from the inside, so
    /// this is bound to what ran rather than to a string a test names. The control is the whole gate:
    /// a count that is constant proves nothing unless the form it replaced is shown to be the form
    /// that is not.
    @Test("the batched resolver costs the same for one account row as for five, and the loop does not")
    func theBatchedResolverDoesNotScaleWithTheAccountsRows() async throws {
        let (api, store) = try await Self.openSeeded()
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let named = candidates.filter { $0.speciesCommonName != nil }.prefix(5).map(\.tree.id)
        try #require(named.count == 5, "the fixture needs five named seed trees near the opening center")

        func delta(_ ids: [UUID]) -> ScriptedTransport {
            let transport = ScriptedTransport()
            let rows = ids.map {
                """
                {"tree_uuid":"\($0.uuidString)","last_visited_at":null,"is_favorite":true,
                 "record":null,"hero_photo_id":null}
                """
            }
            transport.answer(
                "GET /me/grove",
                with: "{\"entries\":[\(rows.joined(separator: ","))],\"total\":\(ids.count)}"
            )
            return transport
        }

        func hops(_ router: RoutedAPI, _ ids: [UUID]) async throws -> Int {
            let census = StatementCensus()
            await store.queue.installCensus(census)
            _ = try await router.refreshedGrove()
            await store.queue.installCensus(nil)
            return census.readCount
        }

        let oneID = [named[0]]
        let fiveIDs = Array(named)

        let batchedOne = try await hops(Self.shippingRouter(over: api, transport: delta(oneID)), oneID)
        let batchedFive = try await hops(Self.shippingRouter(over: api, transport: delta(fiveIDs)), fiveIDs)

        // Calibration: the census sees anything at all. A census reading zero would make the equality
        // below true for the reason that nothing was measured.
        #expect(batchedOne > 0, "the census recorded no reads — this gate is vacuous")
        #expect(
            batchedOne == batchedFive,
            "the batched resolver cost \(batchedOne) hops for one row and \(batchedFive) for five"
        )

        // The control, on the same instrument: the loop arm pays per row.
        let loopOne = try await hops(
            RoutedAPI(
                local: api,
                remote: RemoteAPI(
                    baseURL: URL(string: "https://service.invalid/api/v1")!,
                    transport: delta(oneID),
                    session: .shared
                )
            ),
            oneID
        )
        let loopFive = try await hops(
            RoutedAPI(
                local: api,
                remote: RemoteAPI(
                    baseURL: URL(string: "https://service.invalid/api/v1")!,
                    transport: delta(fiveIDs),
                    session: .shared
                )
            ),
            fiveIDs
        )
        #expect(
            loopFive > loopOne,
            "the per-row loop cost \(loopOne) hops for one row and \(loopFive) for five — if these are equal the control is broken and the equality above means nothing"
        )
    }

    // MARK: - The hero photograph, scoped without changing the rule

    /// **The scoped hero read returns what the unscoped one returns, anonymized rows included.**
    ///
    /// PR #144's review, F2. The first cut of this change pointed `LocalAPI.grove()` at
    /// `heroPhotoIDs(treeIDs:attribution:connection:)`, whose `own` comes from `removalPredicate()`,
    /// whose leading ownerless refusal (R3/E157) makes an anonymized photograph `own: false` — then
    /// `isPubliclyVisible`, then `.pending`, then dropped. `TreeProfile.isPhotoVisible`'s own doc
    /// rules the opposite for this screen: shown-and-not-deletable. So the grove takes the
    /// `treeIDs:` overload, which scopes the rows and leaves the predicate alone.
    @Test("an anonymized photograph is still the grove row's hero")
    func theScopedHeroReadKeepsAnAnonymizedPhotograph() async throws {
        let (api, store) = try await Self.openSeeded()
        let candidates = try await api.treesNear(
            Coordinate(latitude: 37.7694, longitude: -122.4862), radiusM: 900, limit: 200
        )
        let tree = try #require(candidates.first(where: { $0.speciesCommonName != nil })).tree.id
        let attribution = await api.attribution
        try await Self.visit(tree, api: api, store: store)

        // An anonymized photograph, written the way `AccountDeletion.anonymizeContributions` leaves
        // one: nobody's, and with the provenance column cleared in the same statement.
        let photoID = UUID()
        try await store.queue.write { connection in
            _ = try ContributionStore().insert(
                Photo(id: photoID, treeID: tree, shotType: .fullTree, capturedAt: Date()),
                localPath: "/tmp/cypress-anonymized.jpg",
                owner: .nobody,
                takenOnDevice: attribution.deviceID,
                connection: connection
            )
            let clear = try connection.cachedStatement(
                "UPDATE photos SET taken_on_device = NULL WHERE id = :id"
            )
            _ = try clear.bind([":id": photoID.uuidString])
            try clear.run()
        }

        // Calibration: the unscoped read — the rule this call site has always used — returns it.
        let unscoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(connection: connection)
        }
        #expect(unscoped[tree] == photoID, "the fixture is not an anonymized row the unscoped read returns")

        // The scoped read agrees, and the attribution-scoped read — the wrong one for this caller —
        // is the negative control that shows the two overloads really do differ here.
        let scoped = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(treeIDs: [tree], connection: connection)
        }
        #expect(scoped == unscoped.filter { $0.key == tree }, "the scoped read changed the rule")

        let byAttribution = try await store.queue.read { connection in
            try ContributionStore().heroPhotoIDs(
                treeIDs: [tree], attribution: attribution, connection: connection
            )
        }
        #expect(
            byAttribution[tree] == nil,
            """
            the attribution-scoped overload returned the anonymized row, so this test's negative \
            control is gone and it no longer shows which overload `grove()` must take
            """
        )

        // …and the grove row itself draws it, which is the behavior the ruling is about.
        let entry = try #require(try await api.grove().first { $0.treeID == tree })
        #expect(entry.heroPhotoID == photoID, "the grove row lost its hero to the scoping")
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
