//
//  RoutedAPITests.swift
//  CypressTests
//
//  Spec §3.1's router: which side answers, and what happens when the far side cannot (#158 step 4).
//
//  ── The two properties this file exists for ────────────────────────────────────────────────────
//
//  1. **No Class L read acquires a remote failure mode.** §4.3 states it as a line of its own, and
//     it is the invariant that keeps the map's failure surface exactly where two performance
//     campaigns left it. The gate for it uses a `RemoteAPI` whose transport refuses *everything*: a
//     Class L read that touched it would throw, and every Class L read here is expected to answer.
//
//  2. **A Class R read that could not ask falls back and says that it did.** "An empty state is a
//     claim, and this project has already drawn one over a failed read" (R72 ruling 1). The saying
//     is `RemoteReadLog`, because the *sentence* on the glass is a copy question that is not in the
//     mocks (§4.3, DECISIONS constraint 21).
//

import Foundation
import Testing
@testable import Cypress

// MARK: - The local side

/// Every `deleteAccount` that reached the phone, in order.
///
/// A reference type because `LocalDouble` is a struct and `RoutedAPI` holds its own copy of it: a
/// plain `var` counter would be incremented on a value the test cannot see, and the assertion "the
/// local half did not run" would pass whether or not it had. That assertion is the whole of the
/// abort-on-failure ruling, so it gets a seam that can actually be wrong.
final class DeletionRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [AccountDeletionChoice] = []

    var choices: [AccountDeletionChoice] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func record(_ choice: AccountDeletionChoice) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(choice)
    }
}

/// A `CypressAPI` standing in for the phone.
///
/// It answers only what the router asks of the local side and inherits the protocol's defaults for
/// everything else, which is exactly what a test double may do and a shipping conformance may not
/// (`APIConformanceGuardTests`' own note on this distinction).
struct LocalDouble: CypressAPI, @unchecked Sendable {

    var groveEntries: [GroveEntry] = []
    var favorite: Bool = false
    var membership: Set<UUID> = []
    var speciesKnown: GroveSpecies = .empty
    var journalPage: Page<JournalEntry> = Page(items: [])
    var profile: TreeProfile?
    var speciesByID: [UUID: Species] = [:]
    var profilesByID: [UUID: TreeProfile] = [:]
    var photoBytes: [UUID: Data] = [:]
    var content: MapContent = .pins([])
    var nearby: [NearbyTree] = []

    /// What reached the phone's `deleteAccount`. See `DeletionRecorder`.
    var deletions = DeletionRecorder()

    /// Makes the phone's half of a deletion fail, for the one arm that is not transactional.
    var deletionError: (any Error)?

    /// What the two grove reads report and answer, when a test cares — nil when none does, which is
    /// every test in this file. `GroveLocalFirstTests` is the caller: what a repeat visit does is a
    /// claim about both a count and the answer that comes back, and neither can live in a `var` on
    /// this struct because the router holds its own copy of it. See `GroveReadProbe`.
    var reads: GroveReadProbe?

    func mapContent(in viewport: MapViewport) async throws -> MapContent { content }
    func treesNear(_ coordinate: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { nearby }

    func treeProfile(id: UUID) async throws -> TreeProfile {
        if let match = profilesByID[id] { return match }
        guard let profile, profile.tree.id == id else { throw APIError.notFound }
        return profile
    }

    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.validationFailed }
    func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree { throw APIError.notFound }
    func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree { throw APIError.notFound }
    func flagWrongSpecies(treeID: UUID) async throws {}
    func dismissSpeciesReview(flagID: UUID) async throws {}
    func flagNeverExisted(treeID: UUID) async throws {}
    func withdrawRecord(flagID: UUID) async throws {}
    func dismissRecordReview(flagID: UUID) async throws {}

    func species(id: UUID) async throws -> Species {
        guard let match = speciesByID[id] else { throw APIError.notFound }
        return match
    }

    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide {
        SpeciesGuide(species: try await species(id: id))
    }
    func almanac(near coordinate: Coordinate?, in area: AreaSelection) async throws -> Almanac { .empty }
    func city(near coordinate: Coordinate?, in city: CitySelection) async throws -> CityAlmanac { .empty }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] {
        items.map { SyncResult(clientUUID: $0.clientUUID, status: .applied) }
    }
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        PhotoUploadTicket(photoID: UUID(), destination: URL(fileURLWithPath: "/tmp/local.jpg"))
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}

    func photoData(id: UUID) async throws -> Data {
        guard let bytes = photoBytes[id] else { throw APIError.notFound }
        return bytes
    }

    func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws {}
    func deletePhoto(id: UUID) async throws -> PhotoDeletion { throw APIError.notFound }
    func grove() async throws -> [GroveEntry] {
        reads?.takeTrees(or: groveEntries) ?? groveEntries
    }
    func isFavorite(treeID: UUID) async throws -> Bool { favorite }
    func groveSpecies() async throws -> GroveSpecies {
        reads?.takeSpecies(or: speciesKnown) ?? speciesKnown
    }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { journalPage }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        deletions.record(choice)
        if let deletionError { throw deletionError }
        var outcome = AccountDeletion.Outcome()
        outcome.choice = choice
        // A number no remote response carries, so a test can tell the local outcome from a
        // remote one that was mapped over it.
        outcome.deletedPrivateReminders = 7
        return outcome
    }
    func deviceContributions() async throws -> DeviceContributions { .none }
    func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> { membership }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data("local".utf8) }
}

// MARK: - The gates

@Suite("RoutedAPI — the §3.1 router")
struct RoutedAPITests {

    static func remote(_ transport: ScriptedTransport) -> RemoteAPI {
        RemoteAPI(baseURL: URL(string: "https://service.invalid/api/v1")!, transport: transport, session: .shared)
    }

    /// A service that refuses everything: no route is scripted, so the double throws `notFound`.
    static func unreachable() -> RemoteAPI { remote(ScriptedTransport()) }

    static func tree(_ id: UUID, latitude: Double = 37.77, longitude: Double = -122.44) -> Tree {
        Tree(id: id, source: .community, coordinate: Coordinate(latitude: latitude, longitude: longitude))
    }

    /// `leafRetention` is passed explicitly and as `nil`: it has no default on purpose (ERRATA
    /// **E9**) — "a species whose habit nobody has established passes nil deliberately; it must
    /// never arrive because a caller left the argument out."
    static func species(_ id: UUID, scientific: String, common: String) throws -> Species {
        try Species(id: id, scientificName: scientific, commonName: common, leafRetention: nil)
    }

    // MARK: Calibration

    /// **Calibrate the instrument.** The unreachable service really does refuse, and the local
    /// double really does answer — without both, "the read fell back" and "the read never happened"
    /// look identical from here.
    @Test("the unreachable service refuses and the local double answers")
    func theUnreachableServiceRefusesAndTheLocalDoubleAnswers() async throws {
        await #expect(throws: APIError.notFound) { _ = try await Self.unreachable().groveDelta() }

        let id = UUID()
        var local = LocalDouble()
        local.groveEntries = [
            GroveEntry(
                treeID: id,
                displayName: "London Plane",
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                lastVisitedAt: nil,
                isFavorite: false
            )
        ]
        #expect(try await local.grove().count == 1)
    }

    // MARK: Class L — no remote failure mode, ever

    /// Every Class L read answers against a service that refuses everything.
    ///
    /// §4.3: "**No Class L read is allowed to acquire a remote failure mode.**" This is that
    /// sentence as a test.
    ///
    /// ── What this gate does NOT catch, found by red-proving it ─────────────────────────────────
    ///
    /// Breaking `species(id:)` into `do { remote } catch { local }` left this test **green**, and
    /// that is not a hole in the assertions — it is the invariant being narrower than its name. A
    /// Class L read that asks the service and falls back does not acquire a remote *failure* mode;
    /// it acquires the remote *latency* §4.1 costs at length, and there is nothing observable at
    /// this seam to tell it from the read that never asked, because `RemoteAPI`'s Class L bodies
    /// refuse locally without touching the wire.
    ///
    /// So the behavioral half is asserted here and the shape half is asserted from the source, in
    /// `theClassLBodiesNeverNameTheService` below. Neither is sufficient alone, which is why both
    /// exist and why this paragraph is here instead of a comment claiming one of them is.
    @Test("no Class L read acquires a remote failure mode")
    func noClassLReadAcquiresARemoteFailureMode() async throws {
        let speciesID = UUID()
        var local = LocalDouble()
        local.speciesByID = [speciesID: try Self.species(speciesID, scientific: "Platanus × acerifolia", common: "London Plane")]
        local.content = .pins([])

        let router = RoutedAPI(local: local, remote: Self.unreachable())
        let viewport = MapViewport(
            bounds: BoundingBox(minLatitude: 37.7, maxLatitude: 37.8, minLongitude: -122.5, maxLongitude: -122.4),
            zoom: 16
        )
        let here = Coordinate(latitude: 37.77, longitude: -122.44)

        #expect(try await router.mapContent(in: viewport).markerCount == 0)
        #expect(try await router.treesNear(here, radiusM: 50, limit: 10).isEmpty)
        #expect(try await router.species(id: speciesID).commonName == "London Plane")
        #expect(try await router.searchSpecies(query: "plane", limit: 5).isEmpty)
        #expect(try await router.speciesGuide(id: speciesID, near: here).species.id == speciesID)
        _ = try await router.almanac(near: here, in: .here)
        _ = try await router.city(near: here, in: .here)
        #expect(try await router.exportLatest(.csv) == Data("local".utf8))

        // Class D, on the same terms: the rows have not been sent, and their being unsent is what
        // the question is about.
        #expect(try await router.deviceContributions() == .none)
    }

    /// **The shape half of §4.3's invariant, read off `RoutedAPI.swift` itself.**
    ///
    /// The gate above cannot see a Class L read that consults the service and falls back, because
    /// the two are indistinguishable through this seam. What *is* distinguishable is the body: a
    /// Class L method is one `try await local.…` and names `remote` nowhere. This reads that from
    /// the source, so the invariant is held by something other than a reviewer remembering it.
    ///
    /// It is the same instrument `APIConformanceGuardTests` uses and it carries the same obligation:
    /// **a parser that finds nothing agrees with everything**, so the calibration below runs first.
    @Test("the Class L bodies never name the service")
    func theClassLBodiesNeverNameTheService() throws {
        let source = try String(
            contentsOf: AppSourceLiterals.repositoryRoot()
                .appendingPathComponent("Cypress/Data/API/RoutedAPI.swift"),
            encoding: .utf8
        )

        /// A method's body, from its `func` line to the line that closes it at the same indent.
        func body(of signature: String) -> String? {
            let lines = source.components(separatedBy: "\n")
            guard let start = lines.firstIndex(where: { $0.contains("func \(signature)") }) else { return nil }
            let indent = lines[start].prefix { $0 == " " }
            guard let end = lines[(start + 1)...].firstIndex(where: { $0 == indent + "}" }) else { return nil }
            return lines[(start + 1)..<end].joined(separator: "\n")
        }

        // Calibration, in three parts. The extractor must find a body, that body must be the right
        // one, and — the negative control — a Class R method's body must contain what this gate
        // forbids. Without the last of these an extractor returning the empty string would report
        // every method clean.
        //
        // **`refreshedGrove()` and not `grove()`.** Since the local-first round `grove()` is the
        // paint: it names no service, so using it as the negative control would prove nothing — a
        // body that does not contain what this gate forbids cannot show that the gate can see it.
        // The join, and the only mention of the wire, is in the refresh.
        let grove = try #require(
            body(of: "refreshedGrove()"), "the body extractor found nothing — this gate is vacuous"
        )
        #expect(grove.contains("remote.groveDelta()"), "the extractor did not read refreshedGrove()'s body")
        #expect(
            body(of: "notAMethodOnThisType()") == nil,
            "the extractor answered for a method that does not exist"
        )

        // §3.1's Class L list, verbatim, plus Class D.
        let classL = [
            "mapContent(in viewport:", "treesNear(_ coordinate:", "species(id:", "searchSpecies(query:",
            "speciesGuide(id:", "almanac(near coordinate:", "city(near coordinate:", "exportLatest(_ format:",
            "deviceContributions()"
        ]
        for signature in classL {
            let found = try #require(body(of: signature), "no body found for \(signature)")
            #expect(found.contains("local."), "\(signature) does not read the phone at all")
            #expect(
                !found.contains("remote"),
                "\(signature) is Class L and names the service — §4.3: no Class L read may acquire a remote failure mode"
            )
        }
    }

    /// Writes stay local, including `sync`.
    ///
    /// §3.1: "**Writes** are their own path: outbox first, both sinks." Routing `sync` remotely does
    /// not add a network to a local write — **it removes the local write** (ERRATA E261 §2), and
    /// every layer carries on behaving exactly as written while the person's own grove goes blank.
    /// The send sink is `OutboxSendSink` and `DataLayer` leaves it unwired on purpose.
    @Test("writes do not route, sync included")
    func writesDoNotRoute() async throws {
        let router = RoutedAPI(local: LocalDouble(), remote: Self.unreachable())
        let item = try OutboxPayload.visit(
            Visit(treeID: UUID(), attribution: .anonymous(deviceID: UUID()), capturedAt: Date())
        ).makeItem()

        let results = try await router.sync([item])
        #expect(results.count == 1)
        #expect(results[0].status == .applied, "sync did not reach the local apply sink")

        // The §3.4 nine reach the local side and refuse there, not at a service with no route.
        await #expect(throws: APIError.notFound) { _ = try await router.claimSpecies(treeID: UUID(), speciesID: UUID()) }
        try await router.flagWrongSpecies(treeID: UUID())
        try await router.logHazardRedirect(HazardRedirectEvent(treeID: UUID(), category: .uprooted))
        #expect(try await router.deleteAccount(.leaveRecords).choice == .leaveRecords)
    }

    // MARK: Class R — the join

    /// The grove joins: the phone supplies the name and the coordinate, the service supplies the
    /// account's favorite bit, its tally and its hero.
    @Test("the grove joins the account's half onto the phone's row")
    func theGroveJoinsTheAccountsHalf() async throws {
        let treeID = UUID()
        let heroID = UUID()
        var local = LocalDouble()
        local.groveEntries = [
            GroveEntry(
                treeID: treeID,
                displayName: "London Plane",
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                lastVisitedAt: Date(timeIntervalSince1970: 1_780_000_000),
                isFavorite: false,
                record: GroveRecord(visits: 1)
            )
        ]

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(treeID.uuidString)","last_visited_at":"2026-08-09T18:41:46Z",
             "is_favorite":true,"record":{"visits":3,"checkIns":1,"measurements":0,"careEvents":0},
             "hero_photo_id":"\(heroID.uuidString)"}],"total":1}
            """
        )

        let log = RemoteReadLog()
        let router = RoutedAPI(local: local, remote: Self.remote(transport), log: log)
        let entries = try await router.refreshedGrove()

        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        // The phone's half survives — a name and a coordinate the service never sent.
        #expect(entry.displayName == "London Plane")
        #expect(entry.coordinate.latitude == 37.77)
        // The account's half wins where it is the wider fact.
        #expect(entry.isFavorite, "the account's favorite did not reach the row")
        #expect(entry.record?.visits == 3, "the phone's tally overwrote the account's")
        #expect(entry.heroPhotoID == heroID)
        // The later of the two visits: the account may have been here from another phone.
        #expect(entry.lastVisitedAt == ISO8601DateFormatter().date(from: "2026-08-09T18:41:46Z"))

        #expect(await log.outcome(of: .grove) == .live)
    }

    /// A tree only the account knows about is resolved through the city file — name, coordinate and
    /// all — because that is where a name and a coordinate live.
    ///
    /// This is what an account buys on a **second device**, which §4.2 calls "the account's whole
    /// point".
    @Test("a tree from another device is named from the city file")
    func aTreeFromAnotherDeviceIsNamedFromTheCityFile() async throws {
        let treeID = UUID()
        let speciesID = UUID()
        var local = LocalDouble()
        // **`.cityImport`, and the source is load-bearing** (PR #144 review, F1). "Resolved through
        // the city file" means an inventory row, and D15's species fallback is only for one: a
        // *community* record's species is a self-assertion by whoever added it, and
        // `LocalAPI.grove()` has always refused to name a tree after one. The fixture said
        // `.community` and asserted the species name, which is the pair the reviewer's probe found
        // the two resolver arms disagreeing over.
        local.profilesByID = [
            treeID: TreeProfile(
                tree: Tree(
                    id: treeID,
                    source: .cityImport,
                    coordinate: Coordinate(latitude: 37.7601, longitude: -122.505)
                ),
                species: try Self.species(speciesID, scientific: "Quercus agrifolia", common: "Coast Live Oak")
            )
        ]

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(treeID.uuidString)","last_visited_at":null,"is_favorite":true,
             "record":null,"hero_photo_id":null}],"total":1}
            """
        )

        let log = RemoteReadLog()
        let entries = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log).refreshedGrove()

        let entry = try #require(entries.first)
        #expect(entry.treeID == treeID)
        // `LocalAPI.displayNameIfPresent`'s rule: the active nickname, else the species common name,
        // and never a fabricated label.
        #expect(entry.displayName == "Coast Live Oak")
        #expect(entry.coordinate.longitude == -122.505)
        #expect(entry.isFavorite)
        // Nil record, not zero: "this read did not answer that" (ERRATA E38).
        #expect(entry.record == nil)
        #expect(await log.outcome(of: .grove) == .live)
    }

    /// A tree the installed city file does not carry is **left out and the read is marked**, not
    /// drawn nameless at an invented coordinate.
    ///
    /// Under D16 this is an ordinary case rather than an error: the other device may have been in a
    /// city this installation has not installed.
    @Test("an unresolvable row is dropped and the read says so")
    func anUnresolvableRowIsDroppedAndTheReadSaysSo() async throws {
        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(UUID().uuidString)","last_visited_at":null,"is_favorite":true,
             "record":null,"hero_photo_id":null}],"total":1}
            """
        )

        let log = RemoteReadLog()
        let entries = try await RoutedAPI(local: LocalDouble(), remote: Self.remote(transport), log: log).refreshedGrove()

        #expect(entries.isEmpty, "a row was drawn for a tree with no name and no coordinate")
        #expect(
            await log.outcome(of: .grove) == .fellBackToLocal,
            "part of the answer was lost and the read reported itself live"
        )
    }

    /// A tree the city file **has** but cannot name is dropped too, and this is a second case
    /// rather than a restatement of the one above.
    ///
    /// Red-proving the previous gate found that out: replacing the name resolution with a `"Tree"`
    /// placeholder left it **green**, because its row is unresolvable for the earlier reason — the
    /// city file has no such tree, so the name rule is never reached. A conformance that named an
    /// unnameable tree would have shipped past it. "Never a fabricated label"
    /// (`LocalAPI.displayNameIfPresent`) needs a tree that exists and has no name, which is this.
    ///
    /// **And the read stays `.live`, which is the half PR #144's review changed.** Dropping this row
    /// is D15 being applied to an answer that arrived whole, not a piece of the answer going
    /// missing; `.fellBackToLocal` would offer a §4.3 surface the sentence "showing what's on this
    /// phone" about a read where nothing was. The case that *does* degrade is
    /// `anUnresolvableRowIsDroppedAndTheReadSaysSo` above — a tree no installed inventory carries at
    /// all — and the two being told apart is what `RoutedAPI.CityFileRows` exists for.
    @Test("a tree the city file cannot name is dropped rather than labeled, and the read stays live")
    func aTreeTheCityFileCannotNameIsDropped() async throws {
        let treeID = UUID()
        var local = LocalDouble()
        // A real profile, with neither a nickname (D15) nor a species — 12,830 of the seed's rows
        // carry `species_current IS NULL`, so this is an ordinary row and not a contrived one.
        local.profilesByID = [treeID: TreeProfile(tree: Self.tree(treeID))]

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove",
            with: """
            {"entries":[{"tree_uuid":"\(treeID.uuidString)","last_visited_at":null,"is_favorite":true,
             "record":null,"hero_photo_id":null}],"total":1}
            """
        )

        let log = RemoteReadLog()
        let entries = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log).refreshedGrove()

        #expect(entries.isEmpty, "a tree with no name and no species was given a fabricated label")
        let outcome = await log.outcome(of: .grove)
        #expect(
            outcome == .live,
            "a D15 refusal on a complete answer was recorded as \(String(describing: outcome))"
        )
    }

    /// The service being unreachable answers from the phone, and records that it did.
    @Test("an unreachable grove falls back and marks it")
    func anUnreachableGroveFallsBackAndMarksIt() async throws {
        let treeID = UUID()
        var local = LocalDouble()
        local.groveEntries = [
            GroveEntry(
                treeID: treeID,
                displayName: "London Plane",
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                lastVisitedAt: nil,
                isFavorite: true
            )
        ]

        let log = RemoteReadLog()
        let entries = try await RoutedAPI(local: local, remote: Self.unreachable(), log: log).refreshedGrove()

        #expect(entries.count == 1, "a failed remote read emptied the grove")
        #expect(entries[0].isFavorite)
        #expect(await log.outcome(of: .grove) == .fellBackToLocal)
        #expect(await log.degradedReads.contains(.grove))
    }

    /// `isFavorite` prefers the service and falls back to the phone.
    @Test("isFavorite takes the service's answer, and the phone's when it cannot ask")
    func isFavoriteTakesTheServicesAnswer() async throws {
        let treeID = UUID()
        var local = LocalDouble()
        local.favorite = false

        let transport = ScriptedTransport()
        transport.answer("GET /me/grove/\(treeID.uuidString)/favorite", with: #"{"is_favorite":true}"#)

        let log = RemoteReadLog()
        #expect(
            try await RoutedAPI(local: local, remote: Self.remote(transport), log: log)
                .reconciledIsFavorite(treeID: treeID)
        )
        #expect(await log.outcome(of: .isFavorite) == .live)

        let offline = RemoteReadLog()
        #expect(
            try await RoutedAPI(local: local, remote: Self.unreachable(), log: offline)
                .reconciledIsFavorite(treeID: treeID) == false
        )
        #expect(await offline.outcome(of: .isFavorite) == .fellBackToLocal)

        // **The paint, which is the half the owner's ruling of 2026-09-02 moved.** The same router
        // whose service says `true` answers the phone's `false` from `isFavorite`, and asks nothing:
        // a `.live` outcome here would mean the tap was still waiting on the wire.
        let painted = RemoteReadLog()
        let paintTransport = ScriptedTransport()
        paintTransport.answer(
            "GET /me/grove/\(treeID.uuidString)/favorite", with: #"{"is_favorite":true}"#
        )
        let paint = try await RoutedAPI(
            local: local, remote: Self.remote(paintTransport), log: painted
        ).isFavorite(treeID: treeID)
        #expect(paint == false, "the heart waited for the service before answering the finger")
        #expect(paintTransport.calls.isEmpty, "the painted heart reached the wire")
        #expect(await painted.outcome(of: .isFavorite) == nil)
    }

    /// `mapMembership` **unions** rather than replacing.
    ///
    /// A tree hearted on this phone and not yet drained is in the local set and not the service's.
    /// Replacing would take the heart off a tree the person just tapped.
    @Test("mapMembership unions the phone's set with the account's")
    func mapMembershipUnionsTheSets() async throws {
        let queued = UUID()
        let account = UUID()
        var local = LocalDouble()
        local.membership = [queued]

        let transport = ScriptedTransport()
        transport.answer("GET /me/map-membership", with: #"{"kind":"favorites","tree_ids":["\#(account.uuidString)"]}"#)

        let ids = try await RoutedAPI(local: local, remote: Self.remote(transport))
            .refreshedMapMembership(.favorites)
        #expect(ids == [queued, account], "a not-yet-drained favorite was dropped by the join")

        // **The paint answers the phone's set and asks nothing.** The chip narrows the map from the
        // local table; the account's half joins through the union above, behind the narrowing.
        let paintTransport = ScriptedTransport()
        paintTransport.answer(
            "GET /me/map-membership",
            with: #"{"kind":"favorites","tree_ids":["\#(account.uuidString)"]}"#
        )
        let painted = try await RoutedAPI(local: local, remote: Self.remote(paintTransport))
            .mapMembership(.favorites)
        #expect(painted == [queued], "the chip waited for the service before narrowing")
        #expect(paintTransport.calls.isEmpty, "the painted membership read reached the wire")
    }

    /// The species grove joins the numerator and keeps the phone's denominator.
    ///
    /// The ring's denominator is a fact about the city's inventory, and under D16 about which cities
    /// are installed — which the service does not know and declines to guess at (`reads.go`).
    @Test("groveSpecies joins the numerator and keeps the local denominator")
    func groveSpeciesJoinsTheNumerator() async throws {
        let known = UUID()
        let onlyOnTheAccount = UUID()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_780_000_000)

        var local = LocalDouble()
        local.speciesByID = [
            onlyOnTheAccount: try Self.species(onlyOnTheAccount, scientific: "Quercus agrifolia", common: "Coast Live Oak")
        ]
        local.speciesKnown = GroveSpecies(
            neighborhood: GroveNeighborhood(area: .radius(meters: 500), species: Series(complete: [known])),
            known: Series(complete: [
                KnownSpecies(
                    speciesID: known,
                    scientificName: "Platanus × acerifolia",
                    commonName: "London Plane",
                    firstMetAt: later,
                    firstMetAddress: "Noriega St"
                )
            ])
        )

        let transport = ScriptedTransport()
        transport.answer(
            "GET /me/grove/species",
            with: """
            {"known":[{"species_id":"\(known.uuidString)","first_met":"\(ISO8601DateFormatter().string(from: earlier))"},
             {"species_id":"\(onlyOnTheAccount.uuidString)","first_met":"\(ISO8601DateFormatter().string(from: later))"}],
             "total":2}
            """
        )

        let log = RemoteReadLog()
        let grove = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log).refreshedGroveSpecies()

        #expect(grove.known.items.count == 2)
        #expect(grove.neighborhood?.species.items == [known], "the denominator came from somewhere other than the phone")

        let joined = try #require(grove.known.items.first { $0.speciesID == known })
        // The *first* meeting across every device: an account that met a species on an older phone
        // met it then, not when this one caught up.
        #expect(joined.firstMetAt == earlier)
        #expect(joined.firstMetAddress == "Noriega St")

        let fromTheAccount = try #require(grove.known.items.first { $0.speciesID == onlyOnTheAccount })
        #expect(fromTheAccount.commonName == "Coast Live Oak", "the name did not come from the city file")
        // The address of a meeting that happened on another phone is not a fact this one holds.
        #expect(fromTheAccount.firstMetAddress == nil)

        #expect(grove.known.totalCount == 2, "the joined series claimed to be a page")
        #expect(await log.outcome(of: .groveSpecies) == .live)
    }

    // MARK: R-required — the acceptance criterion

    /// **The acceptance criterion, in one test.**
    ///
    /// *"we need to be in a spot where when I add a photo on my device, the photo propagates to all
    /// other users"* — this is the other device's read, returning a photograph it never wrote, on a
    /// profile whose tree, species and inventory row all still come from the city file.
    @Test("treeProfile carries a photograph this device never wrote")
    func treeProfileCarriesAPhotographThisDeviceNeverWrote() async throws {
        let treeID = UUID()
        let mine = UUID()
        let theirs = UUID()

        var local = LocalDouble()
        local.profile = TreeProfile(
            tree: Self.tree(treeID),
            species: try Self.species(UUID(), scientific: "Quercus agrifolia", common: "Coast Live Oak"),
            photos: Series(complete: [
                Photo(id: mine, treeID: treeID, shotType: .fullTree, capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
            ]),
            ownPhotoIDs: [mine],
            deletablePhotoIDs: [mine],
            // Not decoration. `statusProvenance` is a **local** fact — this device's
            // `tree_status_overrides` table, which the service has no view of — so the merge has to
            // carry it over from `mine` the way it carries `tree` itself. It defaults to `.record`
            // on the initializer, which means a *dropped* argument in the merge compiles silently.
            // See `treeProfileMergeKeepsThisDevicesStatusProvenance` below for what that would put
            // on screen.
            statusProvenance: .communityReview
        )

        let transport = ScriptedTransport()
        transport.answer(
            "GET /trees/\(treeID.uuidString)",
            with: """
            {"tree_uuid":"\(treeID.uuidString)","photos":[
              {"photo_id":"\(theirs.uuidString)","shot_type":"full_tree",
               "captured_at":"2026-08-09T18:41:46Z","is_publicly_visible":true}],
             "photo_count":1,"visit_count":9,"own_photo_ids":[],"deletable_photo_ids":[]}
            """
        )

        let log = RemoteReadLog()
        let profile = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log)
            .refreshedTreeProfile(id: treeID)

        #expect(profile.tree.id == treeID, "the city half did not survive the join")
        #expect(profile.species?.commonName == "Coast Live Oak")
        #expect(profile.photos.items.count == 2)

        let arrived = try #require(profile.photos.items.first { $0.id == theirs })
        #expect(arrived.isPubliclyVisible, "the arriving photograph would not be drawn")
        #expect(!profile.isOwnPhoto(arrived), "somebody else's photograph was claimed as this device's")
        #expect(profile.isVisibleOnDevice(arrived), "the arriving photograph is not visible on this screen")

        // Ordering is newest first, which is what a timeline is.
        #expect(profile.photos.items.first?.id == theirs)
        // This device's own photograph is still its own, and still deletable.
        #expect(profile.isOwnPhoto(try #require(profile.photos.items.first { $0.id == mine })))
        #expect(profile.deletablePhotoIDs == [mine])
        #expect(
            profile.statusProvenance == .communityReview,
            "the merge dropped a fact only this device holds"
        )

        #expect(await log.outcome(of: .treeProfile) == .live)
    }

    /// **`RoutedAPI` is the shipping path, and the merge rebuilds the payload field by field.**
    ///
    /// `DataLayer` wires `RoutedAPI(local:remote:log:)`, so every profile read goes through the
    /// reconstruction above whenever the service answers. That reconstruction lists its arguments by
    /// name, and `TreeProfile.init` gives `statusProvenance` a `.record` default — so a line deleted
    /// from it compiles, and the whole unit target stays green while the live app quietly
    /// re-attributes a death.
    ///
    /// This asserts the **visible** consequence rather than the field alone, because the field is
    /// only interesting for what it makes the screen say. A community-confirmed death that comes back
    /// from the merge as `.record` renders as *"Recorded dead in the …"* over a city inventory that
    /// never said any such thing — the mirror of the falsehood this whole change is about, arriving
    /// one layer above where `ModerationTests` watches for it.
    ///
    /// The remote half is scripted to answer, because a fallback returns `mine` untouched and would
    /// pass no matter what the merge does.
    @Test("the merge keeps a status provenance only this device can know")
    func treeProfileMergeKeepsThisDevicesStatusProvenance() async throws {
        let treeID = UUID()
        // **A city-import row, deliberately.** This is the case the whole change turns on: an
        // inventory row that shipped `alive` and was confirmed dead by a reviewer *here*. Its
        // `source` is identical to a row the city itself published as dead, so if the merge loses the
        // provenance the notice does not merely go vague — it names the inventory as the author of a
        // death the inventory never recorded, which is the mirror of the falsehood being fixed.
        var tree = Self.tree(treeID)
        tree.status = .deadReported
        tree.source = .cityImport

        var local = LocalDouble()
        local.profile = TreeProfile(
            tree: tree,
            inventorySource: InventorySource(
                id: "testburgh_register",
                name: "Testburgh municipal tree register",
                url: "",
                snapshotDate: nil
            ),
            // What a real `confirmReview` leaves behind: the seed says `alive`, the override says
            // dead, and only this device holds the row that explains which.
            statusProvenance: .communityReview
        )

        let transport = ScriptedTransport()
        transport.answer(
            "GET /trees/\(treeID.uuidString)",
            with: """
            {"tree_uuid":"\(treeID.uuidString)","photos":[],
             "photo_count":0,"visit_count":0,"own_photo_ids":[],"deletable_photo_ids":[]}
            """
        )

        let log = RemoteReadLog()
        let profile = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log)
            .refreshedTreeProfile(id: treeID)

        #expect(await log.outcome(of: .treeProfile) == .live, "this test proves nothing on the fallback path")
        #expect(profile.statusProvenance == .communityReview)

        let notice = try #require(TreeProfilePresentation(profile: profile).deadNotice)
        #expect(notice.text.contains("community reviewer"))
        #expect(
            !notice.text.contains("Testburgh municipal tree register"),
            "the merge credited the city's inventory with a death a reviewer here confirmed"
        )
        #expect(notice.leadIn == TreeProfilePresentation.deadNoticeConfirmedLeadIn)
    }

    /// R-required's fallback: the phone's profile, unchanged, and a mark saying it is "this tree as
    /// this phone knows it" rather than the tree.
    @Test("an unreachable profile answers from the phone and marks it")
    func anUnreachableProfileAnswersFromThePhone() async throws {
        let treeID = UUID()
        var local = LocalDouble()
        local.profile = TreeProfile(tree: Self.tree(treeID))

        let log = RemoteReadLog()
        let profile = try await RoutedAPI(local: local, remote: Self.unreachable(), log: log)
            .refreshedTreeProfile(id: treeID)

        #expect(profile.tree.id == treeID, "screen 03 lost its tree because a service was unreachable")
        #expect(await log.outcome(of: .treeProfile) == .fellBackToLocal)

        // **The paint answers the same profile and asks nothing.** Opening a tree is the read all
        // sixteen call sites make, and before the split every one of them awaited the community
        // half first — a sheet that wanted only the tree's name paid for photographs it never drew.
        let painted = RemoteReadLog()
        let transport = ScriptedTransport()
        let quick = try await RoutedAPI(local: local, remote: Self.remote(transport), log: painted)
            .treeProfile(id: treeID)
        #expect(quick.tree.id == treeID)
        #expect(transport.calls.isEmpty, "the painted profile reached the wire")
        #expect(await painted.outcome(of: .treeProfile) == nil)
    }

    /// The phone is asked for bytes first, and the service only for what it never wrote.
    ///
    /// **The log must say nothing here**, and review of PR #78 is why that is asserted rather than
    /// assumed: this recorded `.live` — "the service answered" — for bytes read off local disk with
    /// the service never asked, and the test that covered the path never constructed a log at all,
    /// so flipping the label left everything green.
    @Test("photoData prefers the bytes already on this disk, and records nothing")
    func photoDataPrefersTheBytesOnThisDisk() async throws {
        let ownID = UUID()
        let ownBytes = Data([0xFF, 0xD8, 0x01])
        var local = LocalDouble()
        local.photoBytes = [ownID: ownBytes]

        let transport = ScriptedTransport()
        let log = RemoteReadLog()
        let router = RoutedAPI(local: local, remote: Self.remote(transport), log: log)

        #expect(try await router.photoData(id: ownID) == ownBytes)
        #expect(transport.calls.isEmpty, "a photograph already on this disk was fetched over the network")
        #expect(
            await log.outcome(of: .photoData) == nil,
            "the log claims something about a service that was never asked"
        )
        #expect(await log.degradedReads.isEmpty, "a complete answer off this disk was reported degraded")
    }

    /// Bytes this device never wrote arrive from the service, and **that** is `.live`.
    ///
    /// The acceptance criterion's last mile at the byte level: the profile carries the photograph
    /// (`treeProfileCarriesAPhotographThisDeviceNeverWrote`), and this is the read that draws it.
    @Test("a photograph only the service holds is fetched and recorded live")
    func aPhotographOnlyTheServiceHoldsIsRecordedLive() async throws {
        let photoID = UUID()
        let source = URL(string: "https://storage.invalid/read/\(photoID.uuidString).jpg")!
        let bytes = Data([0xFF, 0xD8, 0x09, 0x09])
        StubStorageProtocol.park(source, status: 200, body: bytes)

        let transport = ScriptedTransport()
        transport.answer(
            "GET /photos/\(photoID.uuidString)",
            with: """
            {"photo_id":"\(photoID.uuidString)","url":"\(source.absoluteString)","expires_in":1800,
             "shot_type":"full_tree","captured_at":"2026-08-09T18:41:46Z"}
            """
        )

        let log = RemoteReadLog()
        let router = RoutedAPI(
            local: LocalDouble(),
            remote: RemoteAPI(
                baseURL: URL(string: "https://service.invalid/api/v1")!,
                transport: transport,
                session: StubStorageProtocol.session()
            ),
            log: log
        )

        #expect(try await router.photoData(id: photoID) == bytes)
        #expect(await log.outcome(of: .photoData) == .live)
    }

    /// Neither half has the bytes, so it throws — `PhotoAccess.swift` is explicit that empty `Data`
    /// is not an acceptable stand-in, because "a zero-byte JPEG is a corrupt photograph".
    ///
    /// **The outcome is `.unanswered`, not `.fellBackToLocal`,** and the difference is the whole of
    /// review's second finding: `fellBackToLocal` is documented as "the value is what this phone
    /// knows", and there is no value — this call threw. `degradedReads` is the set a later round
    /// draws §4.3 copy from, so the old label would have offered "showing what's on this phone" for
    /// a read that returned nothing.
    @Test("a photograph neither half holds throws, and is recorded unanswered")
    func aPhotographNeitherHalfHoldsThrows() async throws {
        let log = RemoteReadLog()
        let router = RoutedAPI(local: LocalDouble(), remote: Self.unreachable(), log: log)

        await #expect(throws: (any Error).self) { _ = try await router.photoData(id: UUID()) }
        #expect(await log.outcome(of: .photoData) == .unanswered)
        #expect(
            await !log.degradedReads.contains(.photoData),
            "a read that returned no value was reported as answering from this phone"
        )

        // ── And it is visible in an aggregate, which round 2 of PR #78's review found it was not ──
        //
        // The line above is right about `degradedReads` and was, on its own, the whole of the log's
        // account of this read: correctly labeled and invisible to any consumer that did not already
        // know to ask for `.photoData` by name. §4.3's ruling is that "a screen that collapses the
        // third into an empty state is telling somebody their work is gone", and a surface cannot
        // avoid that with a set it has to guess the contents of.
        #expect(
            await log.unansweredReads == [.photoData],
            "the third outcome of §4.3 is in no aggregate — it is reachable only by name"
        )
        #expect(
            await log.readsNotAnsweredLive.contains(.photoData),
            "the union a §4.3 surface reads does not contain a read that could not be answered"
        )
    }

    /// The three aggregates say three different things, on one log holding all three outcomes.
    ///
    /// Written as one log rather than three, because the property under test is that the sets do not
    /// **overlap** where they must not and do overlap where they must — which a per-outcome test
    /// cannot see. `.live` is the control: it belongs to none of the three, and without it a
    /// `readsNotAnsweredLive` that simply returned every recorded read would pass.
    @Test("degraded, unanswered and not-live are three different sets")
    func theThreeAggregatesAreDistinct() async {
        let log = RemoteReadLog()
        await log.record(.isFavorite, .live)
        await log.record(.grove, .fellBackToLocal)
        await log.record(.journal, .fellBackToLocal)
        await log.record(.photoData, .unanswered)

        #expect(await log.degradedReads == [.grove, .journal])
        #expect(await log.unansweredReads == [.photoData])
        #expect(await log.readsNotAnsweredLive == [.grove, .journal, .photoData])
        #expect(
            await !log.readsNotAnsweredLive.contains(.isFavorite),
            "a read the service answered is in the set a surface draws a fallback sentence from"
        )
    }

    /// **`readsNotAnsweredLive` is a complement, and this is what makes that a property rather than
    /// a claim.**
    ///
    /// ── Why the obvious test would have been worthless ─────────────────────────────────────────
    ///
    /// `theThreeAggregatesAreDistinct` above exercises all three outcomes and passes just as happily
    /// against `degradedReads.union(unansweredReads)` — review of PR #79 made exactly that
    /// substitution and the whole suite stayed green. It has to: with three cases, "everything that
    /// is not `.live`" and "the two named sets" are the *same set*. No test written against today's
    /// enum can separate them, so a test that enumerated the three cases by hand would be pinning
    /// the coincidence and not the property.
    ///
    /// So this one enumerates **`Outcome.allCases`** and derives what it expects from the same list.
    /// It is still green today — the two implementations agree — and it is the arrival of a fourth
    /// case that makes them disagree, at which point this test fails and the hand-written union does
    /// not silently drop the new outcome out of the one aggregate a §4.3 surface reads. That is the
    /// whole of what it is for: it is written to fail in a future that has not happened yet, and it
    /// was red-proved by making that future happen (a fourth case added, the union restored) and
    /// watching it fail while the complement passed.
    ///
    /// The `#require` on the arity is not decoration. Each outcome needs its own `Read` to be
    /// recorded against — the log stores one outcome per read — so if the enum ever outgrows the
    /// read list this test would quietly stop covering the excess, which is the failure mode it
    /// exists to prevent, one level up.
    @Test("readsNotAnsweredLive covers every outcome that is not live, including ones not yet written")
    func theNotLiveAggregateIsAComplementAndNotAList() async throws {
        let reads = RemoteReadLog.Read.allCases
        let outcomes = RemoteReadLog.Outcome.allCases
        try #require(
            outcomes.count <= reads.count,
            """
            \(outcomes.count) outcomes and only \(reads.count) reads to record them against — this \
            test can no longer cover every case, which is the thing it exists to notice
            """
        )
        try #require(outcomes.contains(.live), "the control case is gone; a complement of nothing is everything")

        let log = RemoteReadLog()
        var expected: Set<RemoteReadLog.Read> = []
        for (read, outcome) in zip(reads, outcomes) {
            await log.record(read, outcome)
            if outcome != .live { expected.insert(read) }
        }
        #expect(!expected.isEmpty, "nothing was recorded — this gate is vacuous")

        #expect(
            await log.readsNotAnsweredLive == expected,
            """
            readsNotAnsweredLive is not the complement of .live over Outcome.allCases. A case this \
            aggregate does not know about is a §4.3 outcome no surface can see: `degradedReads` and \
            `unansweredReads` are deliberately narrow, and this is the set that is supposed to need \
            no maintenance when a fourth outcome lands.
            """
        )
    }

    /// The journal answers from the phone and **says so every time**.
    ///
    /// `JournalEntry.summary` is built by `ContributionStore.journal`'s `UNION ALL` out of the local
    /// tables' own columns; the service sends the raw mutation and no summary. Rebuilding the
    /// sentence here would be a second implementation of it in a second place, and writing a
    /// different one would be inventing copy the mocks do not have.
    @Test("the journal is local and reports itself degraded")
    func theJournalIsLocalAndReportsItselfDegraded() async throws {
        var local = LocalDouble()
        local.journalPage = Page(
            items: [
                JournalEntry(
                    id: UUID(),
                    kind: .visit,
                    treeID: UUID(),
                    treeDisplayName: "London Plane",
                    capturedAt: Date(),
                    summary: "Checked in"
                )
            ],
            nextCursor: nil
        )

        let transport = ScriptedTransport()
        let log = RemoteReadLog()
        let page = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log)
            .journal(cursor: nil, limit: 20)

        #expect(page.items.count == 1)
        #expect(page.items[0].summary == "Checked in")
        #expect(transport.calls.isEmpty, "the journal reached a route whose answer it cannot use")
        #expect(await log.outcome(of: .journal) == .fellBackToLocal)
    }

    /// A read that has not been performed is nil, not `.fellBackToLocal`.
    ///
    /// "We have not asked" and "we asked and could not reach it" are different facts, and this
    /// project has drawn an empty state over the first of them before.
    @Test("an unasked read has no outcome at all")
    func anUnaskedReadHasNoOutcome() async throws {
        let log = RemoteReadLog()
        _ = try await RoutedAPI(local: LocalDouble(), remote: Self.unreachable(), log: log)
            .refreshedMapMembership(.yours)

        #expect(await log.outcome(of: .mapMembership) != nil)
        #expect(await log.outcome(of: .treeProfile) == nil, "a read nobody performed reported an outcome")
    }

    // MARK: - Deletion: remote first, and nothing local unless the service said yes

    /// ERRATA **E272**, closed by the owner's ruling of 2026-08-23.
    ///
    /// The router used to send this to the phone, so an account deleted in the You tab was deleted
    /// here and left standing on the service. It now sends `DELETE /me` **first** and runs the local
    /// half only on success. The four tests below are the two doors against the two answers, and the
    /// property they share is the one the ruling turns on: **on a failure the phone is untouched.**
    ///
    /// `deletions.choices` is what makes that assertable — see `DeletionRecorder` for why a struct
    /// double could not have carried it.

    /// A signed-in remote, with the outbox seam filled so `RemoteAPI.deleteAccount` does not refuse.
    static func signedInRouter(
        local: LocalDouble,
        transport: ScriptedTransport,
        queued: [UUID] = []
    ) -> RoutedAPI {
        let remote = RemoteAPI(
            baseURL: URL(string: "https://service.invalid/api/v1")!,
            transport: transport,
            session: .shared,
            pendingOutboxKeys: { queued }
        )
        return RoutedAPI(local: local, remote: remote, signedInUserID: { Self.accountID })
    }

    static let accountID = UUID(uuidString: "0E000000-0000-4000-8000-00000000E272")!

    static func deletionAccepted(_ choice: AccountDeletionChoice) -> String {
        """
        {"deleted":true,"choice":"\(choice.rawValue)","contributions":3,"photos":1,"tombstones":2}
        """
    }

    @Test("a signed-in deletion reaches the service before it reaches the phone", arguments: AccountDeletionChoice.allCases)
    func aSignedInDeletionReachesTheServiceFirst(choice: AccountDeletionChoice) async throws {
        let local = LocalDouble()
        let transport = ScriptedTransport()
        transport.answer("DELETE /me", with: Self.deletionAccepted(choice))
        let queued = UUID()

        let outcome = try await Self.signedInRouter(local: local, transport: transport, queued: [queued])
            .deleteAccount(choice)

        let sent = try #require(transport.call("DELETE /me"), "the deletion never left the phone")
        let body = try #require(sent.body).asJSONObject()
        #expect(body["choice"] as? String == choice.rawValue, "the service was told a different door")
        #expect(
            (body["pending_client_uuids"] as? [String]) == [queued.uuidString],
            "the queued keys did not travel, so work in flight could resurrect the account"
        )

        #expect(local.deletions.choices == [choice], "the phone's half did not run after the service accepted")
        #expect(outcome.choice == choice)
        #expect(
            outcome.deletedPrivateReminders == 7,
            "the returned outcome is not the local one — a remote tally was mapped over it"
        )
    }

    /// **The ruling, stated as a test.** The owner chose abort-on-failure over delete-locally-anyway
    /// because the other order destroys somebody's records on the phone while their account stands
    /// on the service, silently and with nothing left that could retry.
    @Test("a deletion the service refused deletes nothing on the phone", arguments: AccountDeletionChoice.allCases)
    func aRefusedDeletionDeletesNothingLocally(choice: AccountDeletionChoice) async throws {
        let local = LocalDouble()
        let transport = ScriptedTransport()
        transport.answer("DELETE /me", throwing: APIError.serverError)

        await #expect(throws: APIError.serverError) {
            _ = try await Self.signedInRouter(local: local, transport: transport).deleteAccount(choice)
        }

        #expect(
            local.deletions.choices.isEmpty,
            "the phone deleted the account after the service refused — the failure mode the ruling forbids"
        )
        #expect(transport.call("DELETE /me") != nil, "fixture: the deletion should have been attempted")
    }

    /// The signed-out arm, which is not a fallback: there is no account on the service to delete, so
    /// asking would turn a working local deletion into `me.go`'s `forbidden`.
    @Test("a signed-out deletion stays on the phone and never asks the service")
    func aSignedOutDeletionStaysLocal() async throws {
        let local = LocalDouble()
        let transport = ScriptedTransport()
        let remote = RemoteAPI(
            baseURL: URL(string: "https://service.invalid/api/v1")!,
            transport: transport,
            session: .shared,
            pendingOutboxKeys: { [] }
        )
        let router = RoutedAPI(local: local, remote: remote, signedInUserID: { nil })

        let outcome = try await router.deleteAccount(.leaveRecords)

        #expect(outcome.choice == .leaveRecords)
        #expect(local.deletions.choices == [.leaveRecords])
        #expect(transport.calls.isEmpty, "a signed-out deletion asked the service to delete an account it has none of")
    }

    /// A router built without the seam — every preview, and every test written before it existed —
    /// keeps the local path rather than acquiring a remote failure mode.
    @Test("no signed-in provider means the deletion is local")
    func noProviderMeansLocal() async throws {
        let local = LocalDouble()
        let transport = ScriptedTransport()
        let router = RoutedAPI(local: local, remote: Self.remote(transport))

        _ = try await router.deleteAccount(.eraseEverything)

        #expect(local.deletions.choices == [.eraseEverything])
        #expect(transport.calls.isEmpty)
    }

    /// The arm that is not transactional, pinned so the order cannot be quietly reversed: when the
    /// *local* half throws, the service has already deleted and the error still reaches the caller.
    @Test("a local failure after a successful remote deletion still throws")
    func aLocalFailureAfterTheRemoteStillThrows() async throws {
        var local = LocalDouble()
        local.deletionError = APIError.notFound
        let transport = ScriptedTransport()
        transport.answer("DELETE /me", with: Self.deletionAccepted(.leaveRecords))

        await #expect(throws: APIError.notFound) {
            _ = try await Self.signedInRouter(local: local, transport: transport).deleteAccount(.leaveRecords)
        }

        #expect(transport.call("DELETE /me") != nil, "the service was never asked, so this is not the arm under test")
        #expect(local.deletions.choices == [.leaveRecords], "the local half was never attempted")
    }
}

private extension Data {
    /// The request body as a dictionary, for asserting what went on the wire.
    func asJSONObject() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: self)) as? [String: Any] ?? [:]
    }
}
