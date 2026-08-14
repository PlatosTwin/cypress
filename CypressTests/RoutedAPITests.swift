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
    func almanac(near coordinate: Coordinate?) async throws -> Almanac { .empty }
    func city(near coordinate: Coordinate?) async throws -> CityAlmanac { .empty }
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
    func grove() async throws -> [GroveEntry] { groveEntries }
    func isFavorite(treeID: UUID) async throws -> Bool { favorite }
    func groveSpecies() async throws -> GroveSpecies { speciesKnown }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { journalPage }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        var outcome = AccountDeletion.Outcome()
        outcome.choice = choice
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
    /// sentence as a test — and the reason it is worth a test rather than a code review is that the
    /// failure it guards is silent in the other direction: a Class L read that quietly asked the
    /// service would still pass every other gate in this file, and would only show up as a map that
    /// stops drawing in a park.
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
        _ = try await router.almanac(near: here)
        _ = try await router.city(near: here)
        #expect(try await router.exportLatest(.csv) == Data("local".utf8))

        // Class D, on the same terms: the rows have not been sent, and their being unsent is what
        // the question is about.
        #expect(try await router.deviceContributions() == .none)
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
        let entries = try await router.grove()

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
        local.profilesByID = [
            treeID: TreeProfile(
                tree: Self.tree(treeID, latitude: 37.7601, longitude: -122.505),
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
        let entries = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log).grove()

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
        let entries = try await RoutedAPI(local: LocalDouble(), remote: Self.remote(transport), log: log).grove()

        #expect(entries.isEmpty, "a row was drawn for a tree with no name and no coordinate")
        #expect(
            await log.outcome(of: .grove) == .fellBackToLocal,
            "part of the answer was lost and the read reported itself live"
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
        let entries = try await RoutedAPI(local: local, remote: Self.unreachable(), log: log).grove()

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
        #expect(try await RoutedAPI(local: local, remote: Self.remote(transport), log: log).isFavorite(treeID: treeID))
        #expect(await log.outcome(of: .isFavorite) == .live)

        let offline = RemoteReadLog()
        #expect(
            try await RoutedAPI(local: local, remote: Self.unreachable(), log: offline).isFavorite(treeID: treeID) == false
        )
        #expect(await offline.outcome(of: .isFavorite) == .fellBackToLocal)
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

        let ids = try await RoutedAPI(local: local, remote: Self.remote(transport)).mapMembership(.favorites)
        #expect(ids == [queued, account], "a not-yet-drained favorite was dropped by the join")
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
        let grove = try await RoutedAPI(local: local, remote: Self.remote(transport), log: log).groveSpecies()

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
            deletablePhotoIDs: [mine]
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
            .treeProfile(id: treeID)

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

        #expect(await log.outcome(of: .treeProfile) == .live)
    }

    /// R-required's fallback: the phone's profile, unchanged, and a mark saying it is "this tree as
    /// this phone knows it" rather than the tree.
    @Test("an unreachable profile answers from the phone and marks it")
    func anUnreachableProfileAnswersFromThePhone() async throws {
        let treeID = UUID()
        var local = LocalDouble()
        local.profile = TreeProfile(tree: Self.tree(treeID))

        let log = RemoteReadLog()
        let profile = try await RoutedAPI(local: local, remote: Self.unreachable(), log: log).treeProfile(id: treeID)

        #expect(profile.tree.id == treeID, "screen 03 lost its tree because a service was unreachable")
        #expect(await log.outcome(of: .treeProfile) == .fellBackToLocal)
    }

    /// The phone is asked for bytes first, and the service only for what it never wrote.
    @Test("photoData prefers the bytes already on this disk")
    func photoDataPrefersTheBytesOnThisDisk() async throws {
        let ownID = UUID()
        let ownBytes = Data([0xFF, 0xD8, 0x01])
        var local = LocalDouble()
        local.photoBytes = [ownID: ownBytes]

        let transport = ScriptedTransport()
        let router = RoutedAPI(local: local, remote: Self.remote(transport))

        #expect(try await router.photoData(id: ownID) == ownBytes)
        #expect(transport.calls.isEmpty, "a photograph already on this disk was fetched over the network")
    }

    /// Neither half has the bytes, so it throws — `PhotoAccess.swift` is explicit that empty `Data`
    /// is not an acceptable stand-in, because "a zero-byte JPEG is a corrupt photograph".
    @Test("a photograph neither half holds throws rather than returning nothing")
    func aPhotographNeitherHalfHoldsThrows() async throws {
        let log = RemoteReadLog()
        let router = RoutedAPI(local: LocalDouble(), remote: Self.unreachable(), log: log)

        await #expect(throws: (any Error).self) { _ = try await router.photoData(id: UUID()) }
        #expect(await log.outcome(of: .photoData) == .fellBackToLocal)
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
        _ = try await RoutedAPI(local: LocalDouble(), remote: Self.unreachable(), log: log).mapMembership(.yours)

        #expect(await log.outcome(of: .mapMembership) != nil)
        #expect(await log.outcome(of: .treeProfile) == nil, "a read nobody performed reported an outcome")
    }
}
