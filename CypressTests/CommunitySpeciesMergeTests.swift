//
//  CommunitySpeciesMergeTests.swift
//  CypressTests
//
//  ROADMAP 144: the profile lays the service's species answers over what the phone knows. The pure
//  merge first, then `RoutedAPI` over a real `LocalAPI` and a scripted service: the adder's phone
//  taking a species somebody else gave its tree, a queued act holding back that adoption, the
//  adder's keep of a report raised on another phone, and a cached tree showing the service's
//  species once the reader's answer has been sent.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@Suite("ROADMAP 144 · the service's species answers on the profile")
struct CommunitySpeciesMergeTests {

    typealias Served = RemoteAPI.TreeCommunityDelta.ServedSpecies

    static let tree = UUID(uuidString: "14400000-0000-4000-8000-000000000001")!
    static let flag = UUID(uuidString: "14400000-0000-4000-8000-0000000000F1")!
    static let localFlag = UUID(uuidString: "14400000-0000-4000-8000-0000000000F2")!
    static let species = UUID(uuidString: "14400000-0000-4000-8000-0000000000A1")!

    static func state(
        answer: Bool = false, report: Bool = false, keep: Bool = false, flag: UUID? = nil
    ) -> SpeciesAnswerState {
        SpeciesAnswerState(
            answerQueued: answer, reportQueued: report, keepQueued: keep,
            anyActQueued: answer || report || keep, openFlagID: flag
        )
    }

    static func offer(
        local: SpeciesCorrectionOffer = .reportable,
        served: Served?,
        state: SpeciesAnswerState? = Self.state(),
        isAdder: Bool = false,
        anotherPhone: Bool = false,
        shares: Bool = true
    ) -> SpeciesCorrectionOffer {
        CommunitySpeciesMerge.offer(
            local: local, served: served, state: state, isAdder: isAdder,
            addedOnAnotherPhone: anotherPhone, readerShares: shares, hasSpecies: true, treeID: tree
        )
    }

    static func served(reported: Bool = false, flag: UUID? = nil, namedByYou: Bool = false) -> Served {
        Served(speciesID: species, isReported: reported, reportFlagID: flag, namedByYou: namedByYou)
    }

    // MARK: - The pure merge

    /// No answer from the service (release v16) leaves the phone's own answer, whatever it was.
    ///
    /// Red-proof: drop the `guard let served else { return local }` — red, the offer is decided
    /// from no answer.
    @Test("with no service answer, the phone's own offer stands")
    func noServiceAnswerKeepsTheLocalOffer() {
        let local = SpeciesCorrectionOffer.underReview(flagID: Self.localFlag, canResolve: false)
        #expect(Self.offer(local: local, served: nil) == local)
        #expect(Self.offer(local: .unavailable, served: nil, shares: true) == .unavailable)
    }

    /// The service's "not reported" ends a report this phone sent, and a report still queued keeps
    /// the line.
    ///
    /// Red-proof: drop `|| (state?.reportQueued ?? false)` in `CommunitySpeciesMerge.offer` — red
    /// on "a queued report lost its line".
    @Test("the service decides the reported line, except over a report still queued")
    func theServiceDecidesTheLine() {
        let sentReport = SpeciesCorrectionOffer.underReview(flagID: Self.localFlag, canResolve: false)
        #expect(Self.offer(local: sentReport, served: Self.served(), state: Self.state(flag: Self.localFlag)) == .reportable)
        let queued = Self.offer(local: sentReport, served: Self.served(), state: Self.state(report: true, flag: Self.localFlag))
        #expect(queued == .underReview(flagID: Self.localFlag, canResolve: false), "a queued report lost its line: \(queued)")
        #expect(Self.offer(served: Self.served(reported: true))
                == .underReview(flagID: Self.tree, canResolve: false), "somebody else's report drew no line")
    }

    /// The adder: the service's flag id is what "Keep the species" names. A queued correction of the
    /// adder's ends the line (the service clears every report on it), and a queued keep does not
    /// (the service clears only up to the report the keep names, and says so in a later read).
    ///
    /// Red-proof: treat a queued keep as clearing (`!(state?.keepQueued ?? false) &&` in front of
    /// `reported`) — red on "a queued keep cleared the line".
    @Test("the adder keeps through the service's flag id; a queued correction ends the line, a queued keep does not")
    func theAdder() {
        let reported = Self.served(reported: true, flag: Self.flag)
        #expect(Self.offer(local: .correctable, served: reported, isAdder: true, shares: false)
                == .underReview(flagID: Self.flag, canResolve: true))
        #expect(Self.offer(local: .correctable, served: reported, state: Self.state(answer: true), isAdder: true)
                == .correctable, "the adder's queued correction left the line")
        #expect(Self.offer(local: .correctable, served: reported, state: Self.state(keep: true), isAdder: true)
                == .underReview(flagID: Self.flag, canResolve: true), "a queued keep cleared the line")
    }

    /// The namer, while `species_named_by_you` says so: the correction, and with a report on their
    /// answer the line and the correction but no keep. A namer who stopped sharing gets neither.
    ///
    /// Red-proof: return `.underReview(..., canResolve: true)` for a reported namer in
    /// `SpeciesAnswerFacts.offer` — red on the reported namer.
    @Test("the namer corrects their own answer, and a report on it draws the line without the keep")
    func theNamer() {
        #expect(Self.offer(served: Self.served(namedByYou: true)) == .correctable)
        #expect(Self.offer(served: Self.served(reported: true, namedByYou: true)) == .reportedYoursToCorrect)
        #expect(Self.offer(served: Self.served(namedByYou: true), shares: false) == .unavailable)
        // A naming still queued is the namer's before the service has said so.
        #expect(Self.offer(served: Self.served(), state: Self.state(answer: true)) == .correctable)
    }

    /// A tree the reader added on another phone reaches this one only through the cache, and
    /// nothing here can act as its adder.
    @Test("a tree the reader added on another phone offers nothing")
    func addedOnAnotherPhone() {
        #expect(Self.offer(served: Self.served(reported: true, flag: Self.flag), anotherPhone: true) == .unavailable)
    }

    /// A cached tree shows the service's species, unless the reader's own answer is still queued.
    @Test("a cached tree shows the service's species once nothing of the reader's is queued")
    func shownSpecies() {
        let mine = UUID()
        #expect(CommunitySpeciesMerge.shownSpecies(local: mine, served: Self.served(), state: Self.state()) == Self.species)
        #expect(CommunitySpeciesMerge.shownSpecies(local: mine, served: Self.served(), state: Self.state(answer: true)) == mine)
        #expect(CommunitySpeciesMerge.shownSpecies(local: mine, served: nil, state: Self.state()) == mine)
    }

    // MARK: - RoutedAPI over a real LocalAPI

    static let base = URL(string: "https://service.invalid/api/v1")!
    static let device = UUID(uuidString: "D0000000-0000-4000-8000-000000014401")!

    static func router(_ local: LocalAPI, _ transport: ScriptedTransport) -> RoutedAPI {
        RoutedAPI(
            local: local,
            remote: RemoteAPI(baseURL: base, transport: transport, session: .shared),
            speciesSeam: CommunitySpeciesSeam(
                state: { id in await local.speciesAnswerState(treeID: id) },
                adopt: { id, observed, served in
                    await local.adoptServedSpecies(treeID: id, observed: observed, served: served)
                },
                keep: { treeID, flagID in try await local.keepServedSpeciesReport(treeID: treeID, flagID: flagID) }
            )
        )
    }

    /// `GET /trees/{id}` as release v17 answers it, with the tree and the three keys.
    static func profileBody(
        _ tree: Tree, addedByYou: Bool, reported: Bool = false, flag: UUID? = nil, namedByYou: Bool = false
    ) throws -> String {
        let encoded = String(decoding: try RemoteCoding.encoder.encode(tree), as: UTF8.self)
        let flagJSON = flag.map { "\"\($0.uuidString.lowercased())\"" } ?? "null"
        return """
            {"added_by_you":\(addedByYou),"community_tree":\(encoded),"deletable_photo_ids":[],
             "is_published":true,"own_photo_ids":[],"photo_count":0,"photos":[],
             "species_named_by_you":\(namedByYou),"species_report_flag_id":\(flagJSON),
             "species_reported":\(reported),"tree_uuid":"\(tree.id.uuidString.lowercased())","visit_count":0}
            """
    }

    static func ownSpecies(_ id: UUID, in store: CypressStore) async throws -> UUID? {
        try await store.queue.read { connection in
            try CommunityTreeStore().tree(id: id, connection: connection)?.speciesCurrentID
        }
    }

    /// The adder's phone takes a contributor's naming onto its own row, owned by nobody, and the
    /// adder may still correct it.
    ///
    /// Red-proof: make the seam's `adopt` answer false without writing — red on "the adder's row
    /// did not take the service's species".
    @Test("the adder's phone takes a species somebody else gave its tree, and may correct it")
    func theAdderAdopts() async throws {
        let store = try await OthersTreeControlsTests.seededStore()
        let local = LocalAPI(store: store, deviceID: Self.device)
        let plane = try await OthersTreeControlsTests.plane(local)
        let oak = try await OthersTreeControlsTests.oak(local, besides: plane)
        let added = try await OthersTreeControlsTests.add(local, device: Self.device, at: OthersTreeControlsTests.spot)

        var served = added
        served.speciesCurrentID = plane.id
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(added.id.uuidString)", with: try Self.profileBody(served, addedByYou: true))

        let merged = try await Self.router(local, transport).refreshedTreeProfile(id: added.id)

        #expect(try await Self.ownSpecies(added.id, in: store) == plane.id, "the adder's row did not take the service's species")
        #expect(merged.species?.id == plane.id)
        #expect(merged.speciesCorrection == .correctable, "\(merged.speciesCorrection)")
        let head = try await store.queue.read { connection in
            try SpeciesAssertionStore().current(treeID: added.id, connection: connection)
        }
        #expect(head?.owner == .nobody, "the adopted species claims an author: \(String(describing: head?.owner))")
        _ = try await local.correctSpecies(treeID: added.id, speciesID: oak.id)
        #expect(try await Self.ownSpecies(added.id, in: store) == oak.id)
    }

    /// An answer of the adder's still queued is newer than anything the service sent, so the row
    /// keeps it.
    ///
    /// Red-proof: drop `!speciesState.anyActQueued` in `refreshedTreeProfile` and the queue check in
    /// `adoptServedSpecies` — red on "the service's answer overwrote a queued claim".
    @Test("a queued species act keeps the adder's row from taking the service's species")
    func aQueuedActBlocksAdoption() async throws {
        let store = try await OthersTreeControlsTests.seededStore()
        let local = LocalAPI(store: store, deviceID: Self.device)
        let plane = try await OthersTreeControlsTests.plane(local)
        let oak = try await OthersTreeControlsTests.oak(local, besides: plane)
        let added = try await OthersTreeControlsTests.add(local, device: Self.device, at: OthersTreeControlsTests.spot)
        _ = try await local.claimSpecies(treeID: added.id, speciesID: plane.id)

        var served = added
        served.speciesCurrentID = oak.id
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(added.id.uuidString)", with: try Self.profileBody(served, addedByYou: true))
        _ = try await Self.router(local, transport).refreshedTreeProfile(id: added.id)

        #expect(try await Self.ownSpecies(added.id, in: store) == plane.id, "the service's answer overwrote a queued claim")
    }

    /// The adder's keep of a report raised on another phone names the service's flag id, and the
    /// line stays until the service says otherwise.
    ///
    /// Red-proof: route `dismissSpeciesReview` straight to the local verb in `RoutedAPI` — red,
    /// `notFound`.
    @Test("the adder keeps a report the service named, by its flag id, and the line waits for the service")
    func theAdderKeepsAServedReport() async throws {
        let store = try await OthersTreeControlsTests.seededStore()
        let local = LocalAPI(store: store, deviceID: Self.device)
        let plane = try await OthersTreeControlsTests.plane(local)
        let added = try await OthersTreeControlsTests.add(
            local, device: Self.device, at: OthersTreeControlsTests.spot, species: plane.id
        )
        let transport = ScriptedTransport()
        transport.answer("GET /trees/\(added.id.uuidString)",
                         with: try Self.profileBody(added, addedByYou: true, reported: true, flag: Self.flag))
        let router = Self.router(local, transport)

        let reported = try await router.refreshedTreeProfile(id: added.id)
        #expect(reported.speciesCorrection == .underReview(flagID: Self.flag, canResolve: true), "\(reported.speciesCorrection)")

        try await router.dismissSpeciesReview(flagID: Self.flag)
        let keeps = try await OthersTreeControlsTests.queued(store).compactMap { payload -> ReviewDismissal? in
            if case let .speciesReviewDismissal(keep) = payload { return keep }
            return nil
        }
        #expect(keeps.map(\.flagID) == [Self.flag], "the keep does not name the service's flag")
        #expect(keeps.first?.treeID == added.id)

        // The service has not answered yet: the line stays.
        let after = try await router.refreshedTreeProfile(id: added.id)
        #expect(after.speciesCorrection == .underReview(flagID: Self.flag, canResolve: true),
                "the phone cleared the line before the service did: \(after.speciesCorrection)")
    }

    /// Somebody else's keep is not one: the verb refuses a reader who did not add the tree.
    @Test("only the adder may send a keep for a served report")
    func onlyTheAdderKeeps() async throws {
        let store = try await OthersTreeControlsTests.seededStore()
        let adder = LocalAPI(store: store, deviceID: OthersTreeControlsTests.otherDevice)
        let added = try await OthersTreeControlsTests.add(adder, device: OthersTreeControlsTests.otherDevice, at: OthersTreeControlsTests.spot)
        let stranger = LocalAPI(store: store, deviceID: Self.device)
        await #expect(throws: APIError.forbidden) {
            try await stranger.keepServedSpeciesReport(treeID: added.id, flagID: Self.flag)
        }
    }

    /// A cached tree whose naming lost a race: once the reader's claim is sent, the profile shows the
    /// species the service holds, and offers the report.
    ///
    /// Red-proof: return `local` from `CommunitySpeciesMerge.shownSpecies` always — red on "the
    /// service's species is not shown".
    @Test("a cached tree shows the service's species once the reader's naming has been sent")
    func aLostRaceShowsTheWinner() async throws {
        let store = try await OthersTreeControlsTests.seededStore()
        let local = LocalAPI(store: store, deviceID: OthersTreeControlsTests.readerDevice)
        try await OthersTreeControlsTests.signIn(local)
        let plane = try await OthersTreeControlsTests.plane(local)
        let oak = try await OthersTreeControlsTests.oak(local, besides: plane)
        let id = try await OthersTreeControlsTests.cached(local, species: nil)
        _ = try await local.claimSpecies(treeID: id, speciesID: plane.id)
        try await OthersTreeControlsTests.answerEverything(store)

        let transport = ScriptedTransport()
        let winner = Tree(id: id, source: .community, coordinate: OthersTreeControlsTests.spot, speciesCurrentID: oak.id)
        transport.answer("GET /trees/\(id.uuidString)", with: try Self.profileBody(winner, addedByYou: false))

        let merged = try await Self.router(local, transport).refreshedTreeProfile(id: id)
        #expect(try await local.treeProfile(id: id).species?.id == plane.id, "calibration: the phone alone still shows the reader's naming")
        #expect(merged.species?.id == oak.id, "the service's species is not shown: \(String(describing: merged.species?.id))")
        #expect(merged.speciesCorrection == .reportable, "\(merged.speciesCorrection)")
    }
}
#endif
