import Foundation
import Testing
@testable import Cypress

/// **The data-dispute screen** — RULINGS R79, part 2.
///
/// What this suite holds down:
///
/// 1. the owner's four choices file under R79's three stored issues, the last two under one;
/// 2. a suggestion reaches the API only under its own choice, so a typed year behind an un-chosen
///    chip is not sent;
/// 3. the 10 m floor refuses **out loud** — a coarse fix is never attached, and the sentence quotes
///    both numbers and names Precise Location;
/// 4. every `DataDisputeLimits.Refusal` and every raise failure has its own sentence;
/// 5. the model's raise lands in the store with what the screen showed, the profile's offer turns
///    into the reporter's own standing dispute, and the profile model's take-back turns it back;
/// 6. the disclosure says the city has not been notified and claims nothing else about the city.
///
/// Every load-bearing assertion reads the store or the boundary's own answer, not the draft the
/// test just configured.
@Suite("Data dispute screen · R79 part 2")
@MainActor
struct DataDisputeScreenTests {

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000007C2")!
    private static let year = 2026

    private static func seededStore() async throws -> CypressStore {
        let seedURL = try #require(SeedContractTests.seedURL, "no seed database; set CYPRESS_SEED_PATH")
        return try await CypressStore.inMemory(seedURL: seedURL)
    }

    private static func api(_ store: CypressStore) -> LocalAPI {
        LocalAPI(store: store, deviceID: deviceID, userID: nil, role: .member)
    }

    /// A real, **standing** row out of the shipped city inventory near the Civic Center.
    ///
    /// Standing, unlike `DataDisputeTests.cityTree`: the profile model is driven here, and a vacant
    /// site leaves the profile for `Route.site` (ERRATA E113) — the nearest record to that point is
    /// one, which is how the first version of this helper read a `nil` presentation.
    private static func cityTree(_ api: LocalAPI) async throws -> NearbyTree {
        try #require(
            try await api.treesNear(
                Coordinate(latitude: 37.7749, longitude: -122.4194), radiusM: 400, limit: 50
            ).first { $0.tree.source == .cityImport && $0.tree.status.acceptsNewContributions },
            "the seed answered no standing city tree near the Civic Center"
        )
    }

    private static func offer(_ api: LocalAPI, _ treeID: UUID) async throws -> DataDisputeOffer? {
        guard case let .dataDispute(offer) = try await api.treeProfile(id: treeID).recordDefect else {
            return nil
        }
        return offer
    }

    private static let spot = Coordinate(latitude: 37.7749, longitude: -122.4194)

    // MARK: - 1. The four choices

    @Test("the four choices file under the three stored issues, the last two under one")
    func theChoicesMapOntoTheStoredIssues() {
        #expect(DataDisputeChoice.allCases == [.wrongPlace, .wrongSpecies, .wrongPlantedYear, .noTree])
        #expect(DataDisputeChoice.wrongPlace.issue == .wrongLocation)
        #expect(DataDisputeChoice.wrongSpecies.issue == .wrongSpecies)
        #expect(DataDisputeChoice.wrongPlantedYear.issue == .wrongMetadata)
        #expect(DataDisputeChoice.noTree.issue == .wrongMetadata)
        // Every stored issue is reachable from some choice, so no R79 checkbox was lost.
        #expect(Set(DataDisputeChoice.allCases.map(\.issue)) == Set(TreeDataDispute.IssueKind.allCases))
    }

    @Test("every choice reads as its own words")
    func everyChoiceHasItsOwnLabel() {
        let labels = DataDisputeChoice.allCases.map(DataDisputeCopy.choice)
        #expect(Set(labels).count == labels.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    // MARK: - 2. A suggestion only under its own choice

    @Test("a value behind an un-chosen chip is not sent")
    func suggestionsAreFilteredByTheChoices() throws {
        let species = try Species(
            scientificName: "Platanus × acerifolia", commonName: "London plane", leafRetention: nil
        )
        var draft = DataDisputeDraft()
        draft.species = species
        draft.plantedYearText = "1998"
        draft.location = .captured(.init(coordinate: Self.spot, accuracyM: 5))

        // Nothing chosen: every value is held and none is sent.
        #expect(draft.suggestions(currentYear: Self.year).isEmpty)

        draft.choices = [.wrongPlantedYear]
        let yearOnly = draft.suggestions(currentYear: Self.year)
        #expect(yearOnly.plantedYear == 1998)
        #expect(yearOnly.speciesID == nil)
        #expect(yearOnly.location == nil)
        #expect(yearOnly.status == nil)

        draft.choices = [.wrongPlace, .wrongSpecies, .wrongPlantedYear, .noTree]
        let all = draft.suggestions(currentYear: Self.year)
        #expect(all.location?.accuracyM == 5)
        #expect(all.speciesID == species.id)
        #expect(all.status == .vacantSite)
        #expect(draft.issues == Set(TreeDataDispute.IssueKind.allCases))
        #expect(draft.problem(currentYear: Self.year) == nil, "a full, valid draft was refused")
    }

    @Test("a planted year is four digits and not in the future", arguments: [
        ("1998", DataDisputeDraft.PlantedYear.valid(1998)),
        (" 2026 ", .valid(2026)),
        ("", .empty),
        ("   ", .empty),
        ("2027", .invalid),
        ("998", .invalid),
        ("19980", .invalid),
        ("19a8", .invalid),
        ("١٩٩٨", .invalid),
    ])
    func plantedYearParsing(text: String, expected: DataDisputeDraft.PlantedYear) {
        var draft = DataDisputeDraft()
        draft.plantedYearText = text
        #expect(draft.plantedYear(currentYear: Self.year) == expected)
    }

    @Test("an unreadable year blocks the send only while its chip is on")
    func anInvalidYearIsTheScreensOwnRefusal() {
        var draft = DataDisputeDraft()
        draft.plantedYearText = "3000"
        draft.choices = [.noTree]
        #expect(draft.problem(currentYear: Self.year) == nil, "a year behind an off chip was judged")
        draft.choices = [.noTree, .wrongPlantedYear]
        #expect(draft.problem(currentYear: Self.year) == DataDisputeCopy.plantedYearInvalid)
        // An empty field under the chip is a real report: "wrong, and I do not know the year".
        draft.plantedYearText = ""
        #expect(draft.problem(currentYear: Self.year) == nil)
    }

    // MARK: - 3. The floor refuses out loud

    @Test("a fix under the floor is attached, and one over it is refused and not attached")
    func theFloorDecidesWhatIsAttached() throws {
        let good = DataDisputeLocation.reading(.located(Self.spot, accuracyM: 6))
        #expect(good == .captured(.init(coordinate: Self.spot, accuracyM: 6)))

        let floor = DataDisputeLimits.positionResolutionRadiusM
        #expect(DataDisputeLocation.reading(.located(Self.spot, accuracyM: floor))
                == .captured(.init(coordinate: Self.spot, accuracyM: floor)),
                "a fix exactly at the floor was refused")

        let coarse = DataDisputeLocation.reading(.located(Self.spot, accuracyM: 40))
        guard case let .refused(refusal) = coarse else {
            Issue.record("a 40 m fix was not refused: \(coarse)")
            return
        }
        #expect(refusal == .locationFixTooCoarse(accuracyM: 40, requiredM: floor))

        var draft = DataDisputeDraft()
        draft.choices = [.wrongPlace]
        draft.location = coarse
        #expect(draft.suggestions(currentYear: Self.year).location == nil,
                "a refused fix travelled to the API anyway")
        #expect(draft.problem(currentYear: Self.year) == nil,
                "with the fix left out, 'the pin is wrong' on its own is a sendable report")
    }

    @Test("the refusal quotes both numbers, rounds the fix up, and names Precise Location")
    func theCoarseSentenceSaysWhy() {
        let sentence = DataDisputeCopy.refusal(.locationFixTooCoarse(accuracyM: 40, requiredM: 10))
        #expect(sentence.contains("40 m"))
        #expect(sentence.contains("10 m"))
        #expect(sentence.contains("Precise Location"))

        // 10.4 m is over a 10 m floor; rounded to nearest it would read "only good to within 10 m …
        // has to be good to within 10 m", a refusal contradicting itself.
        let edge = DataDisputeCopy.refusal(.locationFixTooCoarse(accuracyM: 10.4, requiredM: 10))
        #expect(edge.contains("within 11 m"), "the edge case read: \(edge)")
    }

    @Test("the location states the phone can be in each say their own thing")
    func everyLocationStateHasItsSentence() {
        let states: [DataDisputeLocation] = [
            .notAsked, .reading(.waitingForFix), .reading(.denied), .reading(.servicesOff),
            .reading(.located(Self.spot, accuracyM: 6)), .reading(.located(Self.spot, accuracyM: 40)),
        ]
        #expect(DataDisputeLocation.reading(.notAsked) == .waiting)
        let sentences = states.map(DataDisputeCopy.location)
        #expect(Set(sentences).count == sentences.count, "two location states share a sentence")
        #expect(states.map(\.offersSettings) == [false, false, true, true, false, true])
    }

    // MARK: - 4. Every refusal and failure, its own sentence

    @Test("every refusal the rules can return reads as its own sentence")
    func everyRefusalHasItsOwnSentence() {
        let refusals: [DataDisputeLimits.Refusal] = [
            .noIssueChecked,
            .suggestionOutsideCheckedIssues([.plantedYear]),
            .locationFixTooCoarse(accuracyM: 40, requiredM: 10),
            .unsupportedStatusSuggestion(.removed),
        ]
        let sentences = refusals.map(DataDisputeCopy.refusal)
        #expect(Set(sentences).count == refusals.count, "two refusals collapsed into one sentence")
        let raiseFailures = [APIError.conflict, .forbidden, .notFound, .serverError]
            .map(DataDisputeCopy.raiseFailure)
        #expect(Set(raiseFailures).count == raiseFailures.count)
        #expect(Set(sentences).isDisjoint(with: raiseFailures))
        let takeBacks = [APIError.notFound, .forbidden, .serverError]
            .map(TreeProfileCopy.dataDisputeWithdrawFailure)
        #expect(Set(takeBacks).count == takeBacks.count)
    }

    @Test("an empty report is refused by the rule that names it")
    func anEmptyDraftNamesItsRule() {
        #expect(DataDisputeDraft().problem(currentYear: Self.year)
                == DataDisputeCopy.refusal(.noIssueChecked))
    }

    // MARK: - 5. The whole trip through the store

    @Test("the screen's raise lands what it showed, and the profile's take-back undoes it")
    func theModelRaisesAndTheProfileTakesBack() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        #expect(try await Self.offer(api, city.id) == .raisable)

        let model = DataDisputeModel(treeID: city.id, api: api, currentYear: Self.year)
        model.toggle(.wrongPlace)
        model.useLocation(.located(Self.spot, accuracyM: 6))
        model.toggle(.noTree)
        model.toggle(.wrongPlantedYear)
        model.draft.plantedYearText = "1998"
        model.draft.notes = "  The basin is paved over.  "
        await model.raise()

        #expect(model.problem == nil, "the raise was refused: \(model.problem ?? "")")
        #expect(model.didRaise)

        let stored = try #require(
            try await store.queue.read { try DataDisputeStore().disputes(treeID: city.id, connection: $0) }.first
        )
        #expect(stored.issues == [.wrongLocation, .wrongMetadata])
        #expect(stored.suggestions.location == .init(coordinate: Self.spot, accuracyM: 6))
        #expect(stored.suggestions.plantedYear == 1998)
        #expect(stored.suggestions.status == .vacantSite)
        #expect(stored.suggestions.speciesID == nil)
        #expect(stored.notes == "The basin is paved over.")

        let offer = try await Self.offer(api, city.id)
        #expect(offer == .raisedByYou(disputeID: stored.id), "the profile does not see its own dispute")

        let profile = TreeProfileModel(treeID: city.id, api: api)
        await profile.load()
        await profile.withdrawDataDispute(disputeID: stored.id)
        #expect(profile.recordDefectFailure == nil, "the take-back was refused: \(profile.recordDefectFailure ?? "")")
        #expect(profile.presentation?.recordDefect == .dataDispute(.raisable),
                "after the take-back the profile does not offer to report again")
        let reread = try #require(
            try await store.queue.read { try DataDisputeStore().dispute(id: stored.id, connection: $0) }
        )
        #expect(!reread.isOpen, "the take-back did not stamp the dispute withdrawn")

        // A second take-back of the same dispute is refused with its own sentence, not a success.
        await profile.withdrawDataDispute(disputeID: stored.id)
        #expect(profile.recordDefectFailure == TreeProfileCopy.dataDisputeWithdrawFailure(.notFound))
    }

    @Test("a refused raise writes nothing and says why")
    func aRefusedRaiseWritesNothing() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)

        let model = DataDisputeModel(treeID: city.id, api: api, currentYear: Self.year)
        await model.raise()
        #expect(model.problem == DataDisputeCopy.refusal(.noIssueChecked))
        #expect(!model.didRaise)

        model.toggle(.wrongPlantedYear)
        #expect(model.problem == nil, "an edit left a sentence about a draft that no longer exists")
        model.draft.plantedYearText = "20x6"
        await model.raise()
        #expect(model.problem == DataDisputeCopy.plantedYearInvalid)

        let written = try await store.queue.read {
            try DataDisputeStore().disputes(treeID: city.id, connection: $0)
        }
        #expect(written.isEmpty, "a refused raise wrote \(written.count) dispute(s)")
        #expect(try await Self.offer(api, city.id) == .raisable)
    }

    @Test("a second raise by the same reporter is a conflict, said as one")
    func aSecondRaiseIsAConflict() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        for expected in [nil, DataDisputeCopy.raiseFailure(.conflict)] {
            let model = DataDisputeModel(treeID: city.id, api: api, currentYear: Self.year)
            model.toggle(.noTree)
            await model.raise()
            #expect(model.problem == expected)
        }
    }

    @Test("a waiting location takes the next fix, and an accepted one is not replaced")
    func theLocationBlockTakesOnlyTheFixItAskedFor() async throws {
        let store = try await Self.seededStore()
        let model = DataDisputeModel(treeID: UUID(), api: Self.api(store), currentYear: Self.year)
        model.useLocation(.waitingForFix)
        #expect(model.draft.location == .waiting)
        model.locationChanged(.located(Self.spot, accuracyM: 7))
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 7)))
        let elsewhere = Coordinate(latitude: 37.78, longitude: -122.41)
        model.locationChanged(.located(elsewhere, accuracyM: 3))
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 7)),
                "a later fix quietly replaced the position the reporter accepted")
    }

    // MARK: - 6. Honest routing

    @Test("the screen and the profile say the city has not been told, and nothing else about it")
    func nothingClaimsTheCityWasTold() {
        let disclosure = (DataDisputeCopy.disclosureOpening + " " + DataDisputeCopy.disclosureEmphasis
            + DataDisputeCopy.disclosureContinuation).lowercased()
        #expect(disclosure.contains("the city has not been notified"))
        #expect(TreeProfileCopy.dataDisputeNotice.lowercased().contains("the city is not notified"))
        for text in [disclosure, TreeProfileCopy.dataDisputeNotice.lowercased(),
                     TreeProfileCopy.dataDisputeRaised.lowercased()] {
            #expect(!text.contains("sent to the city"))
            #expect(!text.contains("reported to the city"))
            #expect(!text.contains("311"))
        }
    }
}
