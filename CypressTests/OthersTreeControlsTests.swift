//
//  OthersTreeControlsTests.swift
//  CypressTests
//
//  The profile of a community tree somebody else added. Round C3's answers: the same controls as a
//  city tree (visit, check-in, care, favorite, share, measure), Move pin never. ROADMAP 144 brings
//  the two species controls back, for a reader who is signed in and agreed to share tree records
//  (the owner's answer of 2026-11-16, "Only people who share"): "Say what species you think this
//  is" on an unnamed tree, and "Report the species as wrong" on a named one. The first answer names
//  the tree for everyone, its namer may correct it, and a report names the species it disputes.
//
//  Also the DEBUG seam that puts such a tree into the community cache, which the UI tests use.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@Suite("Other people's community trees on the profile")
struct OthersTreeControlsTests {

    static let readerDevice = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3A01")!
    static let otherDevice = UUID(uuidString: "D0000000-0000-4000-8000-0000000C3A02")!
    static let sharer = UUID(uuidString: "0E000000-0000-4000-8000-0000000C3A10")!
    /// At sea, west of Ocean Beach, where the street inventory has no rows.
    static let spot = Coordinate(latitude: 37.7600, longitude: -122.5400)

    static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    static func plane(_ api: LocalAPI) async throws -> Species {
        try #require(await api.searchSpecies(query: "Platanus", limit: 1).first, "the catalog answered no Platanus")
    }

    static func oak(_ api: LocalAPI, besides plane: Species) async throws -> Species {
        try #require(
            await api.searchSpecies(query: "Quercus", limit: 5).first { $0.id != plane.id },
            "the catalog answered no second species"
        )
    }

    /// Signs the reader in, sharing tree records unless told otherwise.
    static func signIn(_ api: LocalAPI, shares: Bool = true) async throws {
        try await api.linkAccount(
            deviceUUID: readerDevice, userID: sharer, provider: "apple", acceptsLicense: shares
        )
    }

    /// A tree somebody else added, as a tile page would store it.
    static func cached(_ api: LocalAPI, species: UUID?, at coordinate: Coordinate = spot) async throws -> UUID {
        let id = UUID()
        try await api.debugSeedCommunityCache(
            Tree(id: id, source: .community, coordinate: coordinate, speciesCurrentID: species)
        )
        return id
    }

    static func add(_ api: LocalAPI, device: UUID, at coordinate: Coordinate, species: UUID? = nil) async throws -> Tree {
        try await api.addTree(TreeDraft(
            coordinate: coordinate,
            speciesID: species,
            photoLocalPath: LocationCorrectionTests.capture("others-tree"),
            attribution: .anonymous(deviceID: device)
        ))
    }

    /// Every queued payload, in order.
    static func queued(_ store: CypressStore) async throws -> [OutboxPayload] {
        try await store.queue.read { connection in
            try OutboxStore().allItems(connection: connection).map {
                try OutboxPayload.decode(kind: $0.item.kind, from: $0.item.payload)
            }
        }
    }

    /// Every queued item answered, as a drain that heard back from the service leaves it.
    static func answerEverything(_ store: CypressStore) async throws {
        try await store.queue.write { connection in
            try connection.execute("UPDATE outbox SET state = 'failed'")
        }
    }

    /// The cache's own species for a tree: the row only the tile refresher writes.
    static func cacheSpecies(_ id: UUID, in store: CypressStore) async throws -> String? {
        try await store.queue.read { connection -> String? in
            let statement = try connection.prepare(
                "SELECT species_current FROM community_tree_cache WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind([":id": id.uuidString])
            return try statement.fetchOne { try $0.stringIfPresent("species_current") } ?? nil
        }
    }

    // MARK: - A named cached tree

    /// A sharing reader on somebody else's named tree: the city tree's controls, no Move pin, no
    /// claim, and the report with the owner's note that names the adder.
    ///
    /// Red-proof: return `.unavailable` for `!isAdder && !isNamer` in `SpeciesAnswerFacts.offer` —
    /// red on "the report is offered".
    @Test("a sharer on somebody else's named tree is offered the report, with the note that names the adder")
    func namedCachedTree() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        try await Self.signIn(api)
        let id = try await Self.cached(api, species: try await Self.plane(api).id)

        let profile = try await api.treeProfile(id: id)
        let presentation = TreeProfilePresentation(profile: profile)
        #expect(profile.species != nil, "calibration: the cached species resolved")
        #expect(!profile.isAddedHere)
        #expect(!profile.addedByYou)
        #expect(profile.readerSharing == .sharing, "calibration: the reader shares")
        #expect(!presentation.offersMovePin, "Move pin is offered")
        #expect(presentation.speciesCorrection == .reportable, "the report is offered: \(presentation.speciesCorrection)")
        #expect(!presentation.offersSpeciesClaim)
        #expect(presentation.reportSpeciesNote
                == "This goes to the person who added the tree and to a reviewer. The city is not notified.")
        #expect(presentation.quadActions == QuadActionRow.Action.allCases)
        #expect(presentation.offersCheckIn)
        #expect(presentation.activity.map(\.label) == ["Added"])
    }

    /// Nobody else gets a species control: a signed-out reader, and a signed-in one who declined.
    /// The verb says the same thing the screen does.
    ///
    /// Red-proof: drop `readerShares` from the last line of `SpeciesAnswerFacts.offer` (answer
    /// `.reportable` always) — red on "a signed-out reader is offered a report".
    @Test("a reader who does not share gets no species control, and the report is refused")
    func namedCachedTreeWithoutSharing() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let id = try await Self.cached(api, species: try await Self.plane(api).id)

        var presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        #expect(presentation.speciesCorrection == .unavailable, "a signed-out reader is offered a report: \(presentation.speciesCorrection)")
        await #expect(throws: APIError.forbidden) { try await api.flagWrongSpecies(treeID: id) }

        try await Self.signIn(api, shares: false)
        presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        #expect(presentation.profile.readerSharing == .notSharing, "calibration: the reader declined")
        #expect(presentation.speciesCorrection == .unavailable, "a reader who declined is offered a report")
        await #expect(throws: APIError.forbidden) { try await api.flagWrongSpecies(treeID: id) }
        #expect(try await Self.queued(store).isEmpty, "a refused report was queued")
    }

    /// Signed in, with no answer on record about sharing (`ContributionSharing.unknown`: an account
    /// linked before the record existed). It is not "shares", so nothing is offered and the verbs
    /// refuse, on a named tree and on an unnamed one.
    ///
    /// Red-proof: make the reader's sharing gate read `!= .notSharing` in `SpeciesAnswerFacts`'
    /// callers — red on "an unknown reader is offered a report".
    @Test("a reader whose sharing answer is unknown gets no species control, and the verbs refuse")
    func unknownSharing() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        try await Self.signIn(api)
        try await store.clearAppState(.accountProvider)
        let plane = try await Self.plane(api)
        let named = try await Self.cached(api, species: plane.id)
        let unnamed = try await Self.cached(api, species: nil, at: VisitPinAdjust.offset(Self.spot, northM: 40, eastM: 0))

        let onNamed = TreeProfilePresentation(profile: try await api.treeProfile(id: named))
        #expect(onNamed.profile.readerSharing == .unknown, "calibration: \(String(describing: onNamed.profile.readerSharing))")
        #expect(onNamed.speciesCorrection == .unavailable, "an unknown reader is offered a report: \(onNamed.speciesCorrection)")
        let onUnnamed = TreeProfilePresentation(profile: try await api.treeProfile(id: unnamed))
        #expect(!onUnnamed.offersSpeciesClaim, "an unknown reader is offered the claim")
        await #expect(throws: APIError.forbidden) { try await api.flagWrongSpecies(treeID: named) }
        await #expect(throws: APIError.forbidden) { _ = try await api.claimSpecies(treeID: unnamed, speciesID: plane.id) }
        #expect(try await Self.queued(store).isEmpty, "a refused act was queued")
    }

    /// The report: a flag, queued with the species it disputes, and the line on the profile. A
    /// second report while the first is still queued says nothing new; once the first is answered,
    /// a new one may be raised (the adder's keep makes room for "a later report").
    ///
    /// Red-proof: drop `disputedSpeciesID: disputed` from the report in `flagWrongSpecies` — red on
    /// "the report names no disputed species".
    @Test("a report on somebody else's tree names the species it disputes, and draws the line")
    func reportOnACachedTree() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        try await Self.signIn(api)
        let plane = try await Self.plane(api)
        let id = try await Self.cached(api, species: plane.id)

        try await api.flagWrongSpecies(treeID: id)

        let reports = try await Self.queued(store).compactMap { payload -> ReviewReport? in
            if case let .wrongSpeciesReport(report) = payload { return report }
            return nil
        }
        let report = try #require(reports.first, "no report was queued")
        #expect(reports.count == 1)
        #expect(report.treeID == id)
        #expect(report.disputedSpeciesID == plane.id, "the report names no disputed species: \(String(describing: report.disputedSpeciesID))")
        #expect(report.attribution.userID == Self.sharer)

        let presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        guard case let .underReview(_, canResolve) = presentation.speciesCorrection else {
            Issue.record("the reporter does not see the line: \(presentation.speciesCorrection)")
            return
        }
        #expect(!canResolve, "the reporter may keep or correct somebody else's species")
        #expect(try await Self.cacheSpecies(id, in: store)?.caseInsensitiveCompare(plane.id.uuidString) == .orderedSame,
                "the report moved the cache's species")

        await #expect(throws: APIError.conflict) { try await api.flagWrongSpecies(treeID: id) }
        try await Self.answerEverything(store)
        try await api.flagWrongSpecies(treeID: id)
    }

    // MARK: - An unnamed cached tree

    /// The first answer: offered to a sharer, queued with the cached tree's id, laid over the
    /// profile, and the cache itself untouched (it keeps one writer). The namer may then correct
    /// it, and may not report it.
    ///
    /// Red-proof: remove the `.cached` arm of `claimSpecies` (throw `.notFound` there) — red on
    /// the claim, "notFound".
    @Test("a sharer names somebody else's unnamed tree; the answer is queued and overlaid, and the cache is untouched")
    func namingACachedTree() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        try await Self.signIn(api)
        let plane = try await Self.plane(api)
        let oak = try await Self.oak(api, besides: plane)
        let id = try await Self.cached(api, species: nil)

        var presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        #expect(presentation.profile.species == nil, "calibration: the tree has no species")
        #expect(presentation.offersSpeciesClaim, "the claim is not offered")
        #expect(presentation.speciesCorrection == .unavailable)

        _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)

        let claims = try await Self.queued(store).compactMap { payload -> SpeciesStatement? in
            if case let .speciesClaim(statement) = payload { return statement }
            return nil
        }
        #expect(claims.map(\.treeID) == [id], "the claim was not queued for the cached tree")
        #expect(claims.first?.speciesID == plane.id)
        #expect(try await Self.cacheSpecies(id, in: store) == nil, "the claim wrote the cache")

        presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        #expect(presentation.profile.species?.id == plane.id, "the reader's answer is not on the profile")
        #expect(presentation.speciesClaimNote == TreeProfilePresentation.speciesNamedByContributor)
        #expect(!presentation.offersSpeciesClaim, "the claim is still offered after naming")
        #expect(presentation.speciesCorrection == .correctable, "the namer cannot correct: \(presentation.speciesCorrection)")
        await #expect(throws: APIError.validationFailed) { try await api.flagWrongSpecies(treeID: id) }

        // The namer's correction: appended, queued, overlaid, and still not written to the cache.
        _ = try await api.correctSpecies(treeID: id, speciesID: oak.id)
        let corrections = try await Self.queued(store).compactMap { payload -> SpeciesStatement? in
            if case let .speciesCorrection(statement) = payload { return statement }
            return nil
        }
        #expect(corrections.map(\.speciesID) == [oak.id], "the correction was not queued")
        #expect(try await api.treeProfile(id: id).species?.id == oak.id)
        #expect(try await Self.cacheSpecies(id, in: store) == nil, "the correction wrote the cache")
    }

    /// The overlay holds only while the reader's answer is in force. Once nothing is queued and the
    /// cache brings a species that is neither the reader's nor the one their correction replaced,
    /// the cache wins: a race lost, or the adder stepping in. The reader is then a reporter.
    ///
    /// Red-proof: make `localSpeciesAnswers` treat every head of the reader's as in force — red on
    /// "the cache's species did not win".
    @Test("the cache's species wins once the reader's answer is sent and the cache disagrees")
    func theCacheWinsOverAnAnswerNoLongerInForce() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        try await Self.signIn(api)
        let plane = try await Self.plane(api)
        let oak = try await Self.oak(api, besides: plane)
        let id = try await Self.cached(api, species: nil)
        _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)

        // Sent, and the cache catches up with the reader's own answer: still the namer.
        try await Self.answerEverything(store)
        try await api.debugSeedCommunityCache(Tree(id: id, source: .community, coordinate: Self.spot, speciesCurrentID: plane.id))
        #expect(try await api.treeProfile(id: id).speciesCorrection == .correctable)

        // Then somebody else's species arrives.
        try await api.debugSeedCommunityCache(Tree(id: id, source: .community, coordinate: Self.spot, speciesCurrentID: oak.id))
        let profile = try await api.treeProfile(id: id)
        #expect(profile.species?.id == oak.id, "the cache's species did not win: \(String(describing: profile.species?.id))")
        #expect(profile.speciesCorrection == .reportable, "\(profile.speciesCorrection)")
        await #expect(throws: APIError.forbidden) { _ = try await api.correctSpecies(treeID: id, speciesID: plane.id) }
    }

    /// Every queued item accepted by the service at `date`, as a drain that sent it leaves it.
    static func acceptEverything(_ store: CypressStore, at date: Date) async throws {
        try await store.queue.write { connection in
            let statement = try connection.prepare(
                "UPDATE outbox SET remote_sent = 1, state = 'done', updated_at = :at WHERE state <> 'done'"
            )
            defer { statement.finalize() }
            _ = try statement.bind([":at": date])
            try statement.run()
        }
    }

    /// A tile page serves the tree with `species` at `date`.
    static func serve(_ api: LocalAPI, _ store: CypressStore, id: UUID, species: UUID, at date: Date) async throws {
        try await api.debugSeedCommunityCache(Tree(id: id, source: .community, coordinate: spot, speciesCurrentID: species))
        try await store.queue.write { connection in
            let statement = try connection.prepare(
                "UPDATE community_tree_cache SET fetched_at = :at WHERE id = :id COLLATE NOCASE"
            )
            defer { statement.finalize() }
            _ = try statement.bind([":at": date, ":id": id.uuidString])
            try statement.run()
        }
    }

    /// The namer corrects plane to oak, and the adder sets it back to plane. While the cache was
    /// last served before the service accepted the namer's correction, the cache's plane is the
    /// species the correction replaced, and the namer's oak is in force. Once a page serves plane
    /// after that, plane is the adder's word, and the cache wins.
    ///
    /// Red-proof: drop the `fetched <= $0.acceptedAt` bound in `localSpeciesAnswers` (accept any
    /// `replaced` match) — red on "the adder's species did not win".
    @Test("the adder setting back the species the namer's correction replaced wins once the cache is served again")
    func theAdderSettingTheReplacedSpeciesBackWins() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        try await Self.signIn(api)
        let plane = try await Self.plane(api)
        let oak = try await Self.oak(api, besides: plane)
        let id = try await Self.cached(api, species: nil)
        let day = { (n: Double) in Date(timeIntervalSince1970: 1_790_000_000 + n * 86_400) }

        // The namer names it plane; the service accepts it, and a page serves plane.
        _ = try await api.claimSpecies(treeID: id, speciesID: plane.id)
        try await Self.acceptEverything(store, at: day(1))
        try await Self.serve(api, store, id: id, species: plane.id, at: day(2))
        // The namer corrects it to oak; the service accepts it at day 3.
        _ = try await api.correctSpecies(treeID: id, speciesID: oak.id)
        try await Self.acceptEverything(store, at: day(3))

        // No page since: the namer sees their own correction, and may still correct it.
        var profile = try await api.treeProfile(id: id)
        #expect(profile.species?.id == oak.id, "calibration: the sent correction is not shown before the next page")
        #expect(profile.speciesCorrection == .correctable, "\(profile.speciesCorrection)")

        // The adder sets plane back, and a page serves it at day 4.
        try await Self.serve(api, store, id: id, species: plane.id, at: day(4))
        profile = try await api.treeProfile(id: id)
        #expect(profile.species?.id == plane.id, "the adder's species did not win: \(String(describing: profile.species?.id))")
        #expect(profile.speciesCorrection == .reportable, "\(profile.speciesCorrection)")
        await #expect(throws: APIError.forbidden) { _ = try await api.correctSpecies(treeID: id, speciesID: oak.id) }
    }

    /// The claim on an unnamed cached tree is for sharers only, on the screen and at the verb.
    ///
    /// Red-proof: drop the sharing guard in `claimCachedSpecies` — red on the verb, which succeeds.
    @Test("a reader who does not share is not offered the claim, and the claim is refused")
    func unnamedCachedTreeWithoutSharing() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let plane = try await Self.plane(api)
        let id = try await Self.cached(api, species: nil)

        let presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: id))
        #expect(!presentation.offersSpeciesClaim, "the claim is offered to a signed-out reader")
        await #expect(throws: APIError.forbidden) { _ = try await api.claimSpecies(treeID: id, speciesID: plane.id) }
        #expect(try await Self.queued(store).isEmpty)
    }

    // MARK: - A tree on this phone that somebody else added

    /// The same rules on this phone's own table: a tree another person added here (another device
    /// id stands in for another account) offers a sharing reader the report on a named tree and
    /// the claim on an unnamed one, and offers a reader who does not share neither. The verbs say
    /// what the screen says.
    ///
    /// Red-proof: drop the sharing check from the `.own` arm of `claimSpecies` — red on "a
    /// signed-out stranger named the tree". Red-proof: drop `guard isAdder || shares` from the
    /// `.own` arm of `flagWrongSpecies` — red on the report, which is not refused as forbidden.
    @Test("a tree another person added on this phone follows the same rules")
    func anotherPersonsTreeHere() async throws {
        let store = try await Self.seededStore()
        let adder = LocalAPI(store: store, deviceID: Self.otherDevice)
        let plane = try await Self.plane(adder)
        let named = try await Self.add(adder, device: Self.otherDevice, at: Self.spot, species: plane.id)
        let unnamed = try await Self.add(
            adder, device: Self.otherDevice, at: VisitPinAdjust.offset(Self.spot, northM: 40, eastM: 0)
        )
        let queuedBefore = try await Self.queued(store).count

        let reader = LocalAPI(store: store, deviceID: Self.readerDevice)
        var onNamed = TreeProfilePresentation(profile: try await reader.treeProfile(id: named.id))
        #expect(onNamed.profile.isAddedHere, "calibration: the tree is in this phone's table")
        #expect(onNamed.speciesCorrection == .unavailable, "a signed-out reader is offered: \(onNamed.speciesCorrection)")
        #expect(!TreeProfilePresentation(profile: try await reader.treeProfile(id: unnamed.id)).offersSpeciesClaim)
        await #expect(throws: APIError.forbidden, "a signed-out stranger named the tree") {
            _ = try await reader.claimSpecies(treeID: unnamed.id, speciesID: plane.id)
        }
        await #expect(throws: APIError.forbidden) { try await reader.flagWrongSpecies(treeID: named.id) }
        #expect(try await Self.queued(store).count == queuedBefore, "a refused act was queued")

        try await Self.signIn(reader)
        onNamed = TreeProfilePresentation(profile: try await reader.treeProfile(id: named.id))
        #expect(onNamed.speciesCorrection == .reportable, "a sharer is not offered the report: \(onNamed.speciesCorrection)")
        let onUnnamed = TreeProfilePresentation(profile: try await reader.treeProfile(id: unnamed.id))
        #expect(onUnnamed.offersSpeciesClaim, "a sharer is not offered the claim")
    }

    /// The reader's own tree keeps both controls whatever they agreed: the claim while it has no
    /// species, and the correction once it has one.
    @Test("your own tree keeps the claim and the correction")
    func ownTreeKeepsBoth() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let plane = try await Self.plane(api)
        let tree = try await Self.add(api, device: Self.readerDevice, at: Self.spot)

        var presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: tree.id))
        #expect(presentation.offersSpeciesClaim)
        _ = try await api.claimSpecies(treeID: tree.id, speciesID: plane.id)
        presentation = TreeProfilePresentation(profile: try await api.treeProfile(id: tree.id))
        #expect(presentation.speciesCorrection == .correctable)
        #expect(presentation.offersMovePin)
        // The adder who does not share still corrects; a report of their own tree is refused as
        // the adder's (`.validationFailed`), not as a stranger's (`.forbidden`).
        let oak = try await Self.oak(api, besides: plane)
        _ = try await api.correctSpecies(treeID: tree.id, speciesID: oak.id)
        await #expect(throws: APIError.validationFailed) { try await api.flagWrongSpecies(treeID: tree.id) }
        #expect(presentation.reportSpeciesNote == TreeProfileCopy.reportSpeciesNotice,
                "the reader's own tree took the note for somebody else's")
    }

    // MARK: - The seam

    /// The seam writes a tree the way a tile page does: it reads back as somebody else's tree,
    /// it is on the map, and seeding it again replaces the row.
    @Test("the debug cache seam writes a cached tree that the profile and the map both read")
    func theSeam() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)
        let id = try await Self.cached(api, species: nil)

        let profile = try await api.treeProfile(id: id)
        #expect(profile.tree.source == .community)
        #expect(!profile.isAddedHere)
        let near = try await api.treesNear(Self.spot, radiusM: 5, limit: 5)
        #expect(near.map(\.tree.id) == [id])

        try await api.debugSeedCommunityCache(
            Tree(id: id, source: .community, coordinate: Self.spot, status: .alive)
        )
        #expect(try await api.treesNear(Self.spot, radiusM: 5, limit: 5).count == 1, "a re-seed added a second row")
    }

    /// `unsharedNotSharing` signs a debug account in, and the simulator keeps it. Any other deep
    /// link signs exactly that account out first; another account stays signed in.
    ///
    /// Red-proof: remove the sign-out at the top of `DebugDeepLink.open` — red on "the not-sharing
    /// debug account is still signed in".
    @MainActor
    @Test("a deep link after unsharedNotSharing starts signed out, and leaves other accounts alone")
    func theDebugAccountDoesNotLeak() async throws {
        let store = try await Self.seededStore()
        let api = LocalAPI(store: store, deviceID: Self.readerDevice)

        // The state `unsharedNotSharing` leaves, set the way that link sets it. The link itself
        // also adds a tree from a photograph, which the UI suite covers.
        try await api.linkAccount(
            deviceUUID: Self.readerDevice, userID: DebugDeepLink.notSharingAccount,
            provider: "apple", acceptsLicense: false
        )
        #expect(await api.userID == DebugDeepLink.notSharingAccount, "calibration: the debug account is signed in")

        let next = await DebugDeepLink.open(.othersTree, api: api, router: AppRouter())
        #expect(next == nil, "othersTree failed: \(String(describing: next))")
        #expect(await api.userID == nil, "the not-sharing debug account is still signed in")

        let someoneElse = UUID(uuidString: "0E000000-0000-4000-8000-0000000C3A03")!
        try await api.linkAccount(deviceUUID: Self.readerDevice, userID: someoneElse, provider: "apple", acceptsLicense: true)
        _ = await DebugDeepLink.open(.othersTree, api: api, router: AppRouter())
        #expect(await api.userID == someoneElse, "a deep link signed out an account that is not the debug one")
    }
}
#endif
