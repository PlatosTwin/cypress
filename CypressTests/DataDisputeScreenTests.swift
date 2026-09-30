import CoreLocation
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
/// 6. the disclosure says the city has not been notified and claims nothing else about the city;
/// 7. PR #185's rulings: "There's no tree here" stands alone; the refusal is true about Precise
///    Location and about a radius CoreLocation never stated; a later fix replaces a refused one;
///    *Send* waits for a pending fix; each opened section quotes the record; the take-back ignores
///    a second tap.
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

    /// A provider reading: a fix with Precise Location on and a stated radius unless told otherwise.
    private static func located(
        _ accuracyM: Double, at coordinate: Coordinate? = nil, reduced: Bool = false, known: Bool = true
    ) -> DataDisputeFixReading {
        // `nil` rather than `= spot`: a default argument is evaluated outside the suite's actor.
        DataDisputeFixReading(
            availability: .located(coordinate ?? spot, accuracyM: accuracyM),
            precision: .init(isReduced: reduced, accuracyIsKnown: known)
        )
    }

    private static func state(_ availability: MapLocationProvider.Availability) -> DataDisputeFixReading {
        DataDisputeFixReading(availability: availability)
    }

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
        let good = DataDisputeLocation.reading(Self.located(6))
        #expect(good == .captured(.init(coordinate: Self.spot, accuracyM: 6)))

        let floor = DataDisputeLimits.positionResolutionRadiusM
        #expect(DataDisputeLocation.reading(Self.located(floor))
                == .captured(.init(coordinate: Self.spot, accuracyM: floor)),
                "a fix exactly at the floor was refused")

        let coarse = DataDisputeLocation.reading(Self.located(40))
        guard case let .refused(refusal) = coarse else {
            Issue.record("a 40 m fix was not refused: \(coarse)")
            return
        }
        #expect(refusal == .tooCoarse(accuracyM: 40, requiredM: floor, isReduced: false))

        var draft = DataDisputeDraft()
        draft.choices = [.wrongPlace]
        draft.location = coarse
        #expect(draft.suggestions(currentYear: Self.year).location == nil,
                "a refused fix travelled to the API anyway")
        #expect(draft.problem(currentYear: Self.year) == nil,
                "with the fix left out, 'the pin is wrong' on its own is a sendable report")
    }

    @Test("the refusal quotes both numbers and rounds the fix up")
    func theCoarseSentenceSaysWhy() {
        for isReduced in [false, true] {
            let sentence = DataDisputeCopy.locationRefusal(
                .tooCoarse(accuracyM: 40, requiredM: 10, isReduced: isReduced)
            )
            #expect(sentence.contains("40 m"))
            #expect(sentence.contains("10 m"))
            #expect(sentence.contains("was not used"))

            // 10.4 m is over a 10 m floor; rounded to nearest it would read "only good to within
            // 10 m … has to be good to within 10 m", a refusal contradicting itself.
            let edge = DataDisputeCopy.locationRefusal(
                .tooCoarse(accuracyM: 10.4, requiredM: 10, isReduced: isReduced)
            )
            #expect(edge.contains("within 11 m"), "the edge case read: \(edge)")
        }
    }

    /// Ruling 6. **Precise Location is named only when it is off**, because that is the one cause
    /// Settings can fix. With it on, a 20 m fix among buildings is the sky's doing, and a sentence
    /// sending the reader to Settings would send them to a switch that is already on — the review's
    /// finding 2, which is what this holds down.
    @Test("Precise Location and Settings are named only when accuracy is reduced")
    func theRemedyFollowsTheAccuracyAuthorization() {
        let reduced = DataDisputeLocation.reading(Self.located(40, reduced: true))
        let full = DataDisputeLocation.reading(Self.located(40, reduced: false))
        #expect(reduced == .refused(.tooCoarse(accuracyM: 40, requiredM: 10, isReduced: true)))
        #expect(full == .refused(.tooCoarse(accuracyM: 40, requiredM: 10, isReduced: false)))

        let reducedSentence = DataDisputeCopy.location(reduced)
        let fullSentence = DataDisputeCopy.location(full)
        #expect(reducedSentence.contains("Turn on Precise Location for Cypress in Settings"),
                "reduced accuracy did not name its remedy: \(reducedSentence)")
        #expect(reduced.offersSettings, "reduced accuracy did not offer the way to Settings")

        #expect(!fullSentence.contains("Precise Location"),
                "full accuracy was told to turn on Precise Location: \(fullSentence)")
        #expect(!fullSentence.contains("Settings"), "full accuracy was sent to Settings: \(fullSentence)")
        #expect(fullSentence.contains("Try again in the open, or wait a moment."),
                "full accuracy was not told what would help: \(fullSentence)")
        #expect(!full.offersSettings, "full accuracy offered a way to Settings, which cannot help it")

        // A good fix under reduced accuracy is still a good fix: the rule is the stated radius.
        #expect(DataDisputeLocation.reading(Self.located(6, reduced: true))
                == .captured(.init(coordinate: Self.spot, accuracyM: 6)))
    }

    /// Ruling 9. A negative `horizontalAccuracy` reaches the app as 25 m, the provider's pessimistic
    /// substitute. The fix is refused, and the sentence says the phone could not tell — it never
    /// quotes 25 m, a number CoreLocation did not state.
    @Test("a fix with no stated accuracy is refused, and the substitute is never quoted")
    func anUnknownAccuracyIsRefusedTruthfully() {
        let substitute = VisitShortlist.assumedAccuracyM
        let unknown = DataDisputeLocation.reading(Self.located(substitute, known: false))
        #expect(unknown == .refused(.accuracyUnknown(requiredM: 10, isReduced: false)),
                "an unstated radius was not refused as unknown: \(unknown)")
        let sentence = DataDisputeCopy.location(unknown)
        #expect(sentence.contains("couldn’t say how accurate"), "the sentence read: \(sentence)")
        #expect(!sentence.contains("\(DataDisputeCopy.meters(substitute)) m"),
                "the substitute radius was quoted as the phone's: \(sentence)")
        #expect(!sentence.contains("Settings"))
        #expect(!unknown.offersSettings)

        // Refused even when the substitute would pass: an unstated radius is not taken on trust.
        #expect(DataDisputeLocation.reading(Self.located(3, known: false))
                == .refused(.accuracyUnknown(requiredM: 10, isReduced: false)))

        let reducedUnknown = DataDisputeLocation.reading(Self.located(substitute, reduced: true, known: false))
        #expect(DataDisputeCopy.location(reducedUnknown).contains("Precise Location"))
        #expect(reducedUnknown.offersSettings)

        var draft = DataDisputeDraft()
        draft.choices = [.wrongPlace]
        draft.location = unknown
        #expect(draft.suggestions(currentYear: Self.year).location == nil,
                "a fix with no stated radius travelled to the API")
    }

    @Test("the location states the phone can be in each say their own thing")
    func everyLocationStateHasItsSentence() {
        let states: [DataDisputeLocation] = [
            .notAsked, .reading(Self.state(.waitingForFix)), .reading(Self.state(.denied)),
            .reading(Self.state(.servicesOff)), .reading(Self.located(6)), .reading(Self.located(40)),
            .reading(Self.located(40, reduced: true)), .reading(Self.located(25, known: false)),
            .unavailable,
        ]
        #expect(DataDisputeLocation.reading(Self.state(.notAsked)) == .waiting)
        let sentences = states.map(DataDisputeCopy.location)
        #expect(Set(sentences).count == sentences.count, "two location states share a sentence")
        #expect(states.map(\.offersSettings) == [false, false, true, true, false, false, true, false, false])
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
        model.useLocation(Self.located(6))
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
        #expect(stored.suggestions.status == nil)
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
        model.locationChanged(Self.located(7))
        #expect(model.draft.location == .notAsked, "a fix nobody asked for was taken")
        model.useLocation(Self.state(.waitingForFix))
        #expect(model.draft.location == .waiting)
        model.locationChanged(Self.located(7))
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 7)))
        let elsewhere = Coordinate(latitude: 37.78, longitude: -122.41)
        model.locationChanged(Self.located(3, at: elsewhere))
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 7)),
                "a later fix quietly replaced the position the reporter accepted")
    }

    /// Ruling 7, and the review's repro of finding 2 exactly: the first publish after `start()` is
    /// often coarse, and it used to fix the block on "only good to within 65 m" for good.
    @Test("a later, better fix replaces a refused one")
    func aBetterFixReplacesARefusedOne() async throws {
        let store = try await Self.seededStore()
        let model = DataDisputeModel(treeID: UUID(), api: Self.api(store), currentYear: Self.year)
        model.toggle(.wrongPlace)
        model.useLocation(Self.state(.waitingForFix))
        model.locationChanged(Self.located(65))
        #expect(model.draft.location == .refused(.tooCoarse(accuracyM: 65, requiredM: 10, isReduced: false)))
        // A second coarse fix restates the block with its own number rather than the stale one.
        model.locationChanged(Self.located(30))
        #expect(model.draft.location == .refused(.tooCoarse(accuracyM: 30, requiredM: 10, isReduced: false)))
        model.locationChanged(Self.located(5))
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 5)),
                "a 5 m fix arriving after a refused 30 m one was ignored: \(model.draft.location)")
        #expect(model.suggestions.location?.accuracyM == 5)

        // Location off, then granted in Settings: the block follows it back to a fix.
        let other = DataDisputeModel(treeID: UUID(), api: Self.api(store), currentYear: Self.year)
        other.useLocation(Self.state(.denied))
        other.locationChanged(Self.state(.waitingForFix))
        other.locationChanged(Self.located(4))
        #expect(other.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 4)))
    }

    /// Ruling 8, and the review's finding 3: `toggle(.wrongPlace)`, `useLocation(.waitingForFix)`,
    /// `raise()` used to file `wrong_location` with no position and pop the screen, while the block
    /// still said "Finding your location…".
    @Test("Send waits while the pin chip's fix is pending, and a resolved fix releases it")
    func aPendingFixHoldsTheSend() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        let model = DataDisputeModel(treeID: city.id, api: api, currentYear: Self.year)
        model.toggle(.wrongPlace)
        #expect(model.canSend, "the pin chip alone, not asked for a position, is a sendable report")

        model.useLocation(Self.state(.waitingForFix))
        #expect(DataDisputeCopy.location(model.draft.location) == DataDisputeCopy.locationWaiting)
        #expect(!model.canSend, "Send was offered while the position was still arriving")
        await model.raise()
        #expect(!model.didRaise, "a report was filed while the block said it was finding the location")
        let written = try await store.queue.read {
            try DataDisputeStore().disputes(treeID: city.id, connection: $0)
        }
        #expect(written.isEmpty, "a pending fix was dropped silently: \(written.count) dispute(s) written")

        // The chip off, the wait is over: nothing about a position is being promised any more.
        model.toggle(.wrongPlace)
        #expect(model.canSend)
        model.toggle(.wrongPlace)
        #expect(!model.canSend)

        // A refused fix ends the wait too (author call 1, which still holds once the fix resolves).
        model.locationChanged(Self.located(40))
        #expect(model.canSend)
        model.locationChanged(Self.located(6))
        await model.raise()
        #expect(model.didRaise)
        let stored = try await store.queue.read {
            try DataDisputeStore().disputes(treeID: city.id, connection: $0)
        }.first
        #expect(stored?.suggestions.location == .init(coordinate: Self.spot, accuracyM: 6),
                "the fix the reporter waited for was not the one filed")
    }

    // MARK: - Owner ruling 11: the wait for a fix is bounded

    /// A sleep the test releases by hand, so `fixTimeout` is asserted without being spent.
    @MainActor
    private final class ManualSleep {
        private(set) var requested: [Duration] = []
        private var waiting: [CheckedContinuation<Void, Error>] = []

        func sleep(_ duration: Duration) async throws {
            requested.append(duration)
            try await withCheckedThrowingContinuation { waiting.append($0) }
        }

        /// Lets every pending sleep return, as if the time had passed.
        func elapse() {
            let released = waiting
            waiting = []
            released.forEach { $0.resume() }
        }
    }

    /// Polls, bounded, for a condition a released sleep settles on the main actor.
    private static func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    private static func waitingReading(failures: Int = 0) -> DataDisputeFixReading {
        DataDisputeFixReading(availability: .waitingForFix, failureCount: failures)
    }

    @Test("15 s with no fix ends the wait: the block says so, Send works, and asking again waits again")
    func aFixThatNeverComesStopsHoldingSend() async throws {
        let store = try await Self.seededStore()
        let clock = ManualSleep()
        let model = DataDisputeModel(
            treeID: UUID(), api: Self.api(store), currentYear: Self.year,
            sleep: { try await clock.sleep($0) }
        )
        model.toggle(.wrongPlace)
        model.toggle(.wrongPlantedYear)
        model.useLocation(Self.waitingReading())
        #expect(!model.canSend)
        await Self.settle { !clock.requested.isEmpty }
        #expect(clock.requested == [.seconds(15)], "the wait asked for \(clock.requested), not 15 s")

        clock.elapse()
        await Self.settle { model.draft.location != .waiting }
        #expect(model.draft.location == .unavailable, "the timeout did not end the wait: \(model.draft.location)")
        #expect(model.canSend, "Send is still held after the block gave up on the location")
        #expect(DataDisputeCopy.location(model.draft.location) == DataDisputeCopy.locationUnavailable)
        #expect(!model.draft.location.offersSettings, "Settings cannot help a phone that found nothing")
        #expect(model.suggestions.location == nil)

        // A reading with still no fix in it does not put the block back to waiting on its own.
        model.locationChanged(Self.waitingReading())
        #expect(model.draft.location == .unavailable)

        // Asking again is the retry: a fresh wait, a fresh 15 s, Send held again.
        model.useLocation(Self.waitingReading())
        #expect(model.draft.location == .waiting)
        #expect(!model.canSend)
        await Self.settle { clock.requested.count == 2 }
        #expect(clock.requested.count == 2, "the retry did not start a fresh timeout")

        // A fix that arrives before the timeout wins, and the stale timeout then changes nothing.
        model.locationChanged(Self.located(6))
        clock.elapse()
        for _ in 0..<50 { await Task.yield() }
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 6)),
                "a timeout overwrote the fix that arrived before it: \(model.draft.location)")
    }

    @Test("an error CoreLocation reports after the ask ends the wait at once; an older one does not")
    func aLocationErrorStopsHoldingSend() async throws {
        let store = try await Self.seededStore()
        let clock = ManualSleep()
        let model = DataDisputeModel(
            treeID: UUID(), api: Self.api(store), currentYear: Self.year,
            sleep: { try await clock.sleep($0) }
        )
        model.toggle(.wrongPlace)
        // The provider had already failed twice before the reporter asked (on the map, say).
        model.useLocation(Self.waitingReading(failures: 2))
        #expect(model.draft.location == .waiting, "an error from before the ask answered it")

        model.locationChanged(Self.waitingReading(failures: 3))
        #expect(model.draft.location == .unavailable, "a didFailWithError after the ask was ignored")
        #expect(model.canSend)

        model.useLocation(Self.waitingReading(failures: 3))
        #expect(model.draft.location == .waiting, "the retry was answered by the error it retried")
        model.locationChanged(Self.waitingReading(failures: 4))
        #expect(model.draft.location == .unavailable)

        // A fix after an error still replaces it (ruling 7's rule, carried to the new state).
        model.locationChanged(DataDisputeFixReading(
            availability: .located(Self.spot, accuracyM: 5), failureCount: 4
        ))
        #expect(model.draft.location == .captured(.init(coordinate: Self.spot, accuracyM: 5)))
    }

    @Test("the provider counts didFailWithError, through the real delegate")
    func theProviderCountsLocationErrors() {
        let manager = StubManager()
        let provider = MapLocationProvider(manager: manager)
        #expect(provider.failureCount == 0)
        let error = CLError(.locationUnknown)
        manager.delegate?.locationManager?(manager, didFailWithError: error)
        manager.delegate?.locationManager?(manager, didFailWithError: error)
        #expect(provider.failureCount == 2, "didFailWithError is still ignored")
        #expect(provider.availability == .waitingForFix,
                "an error moved the map's own availability, which it must not")
    }

    // MARK: - 7. "There's no tree here" stands alone

    @Test("there's no tree here clears the other three and disables them until it is unticked")
    func noTreeStandsAlone() {
        var draft = DataDisputeDraft()
        draft.toggle(.wrongPlace)
        draft.toggle(.wrongSpecies)
        draft.toggle(.wrongPlantedYear)
        draft.plantedYearText = "1998"
        #expect(draft.choices == [.wrongPlace, .wrongSpecies, .wrongPlantedYear])

        draft.toggle(.noTree)
        #expect(draft.choices == [.noTree], "choosing no-tree left other chips on: \(draft.choices)")
        for other in [DataDisputeChoice.wrongPlace, .wrongSpecies, .wrongPlantedYear] {
            #expect(draft.isDisabled(other), "\(other) is still choosable beside no-tree")
            draft.toggle(other)
        }
        #expect(draft.choices == [.noTree], "a disabled chip was chosen anyway: \(draft.choices)")
        #expect(!draft.isDisabled(.noTree))
        // The review's finding 4: no-tree plus a year chip used to send only the status.
        #expect(draft.issues == [.wrongMetadata])
        #expect(draft.suggestions(currentYear: Self.year).plantedYear == nil)

        draft.toggle(.noTree)
        #expect(draft.choices.isEmpty, "unticking no-tree brought the cleared chips back")
        for other in [DataDisputeChoice.wrongPlace, .wrongSpecies, .wrongPlantedYear] {
            #expect(!draft.isDisabled(other), "\(other) stayed disabled after no-tree was unticked")
        }
        draft.toggle(.wrongPlantedYear)
        #expect(draft.suggestions(currentYear: Self.year).plantedYear == 1998,
                "the year typed before no-tree was not kept for when its chip came back")
    }

    // MARK: - 8. What the city has

    @Test("each opened section quotes the record's own value, and a missing one draws nothing")
    func theCityHasLinesQuoteTheRecord() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        let profile = try await api.treeProfile(id: city.id)

        let model = DataDisputeModel(treeID: city.id, api: api, currentYear: Self.year)
        await model.loadOnFile()
        let onFile = try #require(model.onFile, "the record was not read")

        // The species as the profile names it, the planted year and the address, from the record.
        let species = try #require(profile.species, "the chosen city tree has no species")
        #expect(onFile.value(for: .wrongSpecies) == SpeciesPickCopy.chosen(species))
        #expect(onFile.value(for: .wrongPlantedYear) == profile.tree.plantedYear.map(String.init))
        let address = try #require(profile.tree.address, "the chosen city tree has no address")
        #expect(onFile.value(for: .wrongPlace) == address)
        #expect(onFile.value(for: .noTree) == nil, "no-tree has no section, so no line")
        #expect(DataDisputeCopy.cityHas(address) == "The city has: \(address)")

        // Nothing on file draws nothing, rather than a sentence claiming the city has none.
        let bare = DataDisputeOnFile(species: nil, plantedYear: nil, position: nil)
        #expect(DataDisputeChoice.allCases.allSatisfy { bare.value(for: $0) == nil })
    }

    @Test("a record with no address is placed by its coordinate; an unread species is not quoted raw")
    func theOnFileFallbacks() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        let profile = try await api.treeProfile(id: city.id)
        var tree = profile.tree
        tree.address = "  "
        tree.coordinate = Coordinate(latitude: 37.774912, longitude: -122.419418)
        let unread = try Species(
            scientificName: Species.unreadScientificNameMarker + "Magnolia",
            commonName: "Magnolia", leafRetention: nil
        )
        let onFile = DataDisputeOnFile(tree: tree, species: unread)
        #expect(onFile.position == "37.77491, -122.41942")
        #expect(onFile.species == "Magnolia", "an unread species was not quoted in the city's wording")
    }

    // MARK: - 9. The take-back, once

    /// Ruling 10, and the review's finding 6: two take-backs in flight at once used to end with the
    /// second answered `notFound` — "That report was already taken back." beside the restored action.
    @Test("a second take-back while one is in flight does nothing")
    func aDoubleTapTakesBackOnce() async throws {
        let store = try await Self.seededStore()
        let api = Self.api(store)
        let city = try await Self.cityTree(api)
        let model = DataDisputeModel(treeID: city.id, api: api, currentYear: Self.year)
        model.toggle(.noTree)
        await model.raise()
        guard case let .raisedByYou(disputeID) = try await Self.offer(api, city.id) else {
            Issue.record("the raise did not stand")
            return
        }

        let profile = TreeProfileModel(treeID: city.id, api: api)
        await profile.load()
        async let first: Void = profile.withdrawDataDispute(disputeID: disputeID)
        async let second: Void = profile.withdrawDataDispute(disputeID: disputeID)
        _ = await (first, second)

        #expect(profile.recordDefectFailure == nil,
                "a double tap drew a failure beside the success: \(profile.recordDefectFailure ?? "")")
        #expect(profile.presentation?.recordDefect == .dataDispute(.raisable))
        #expect(!profile.isWithdrawingDataDispute)
    }

    // MARK: - 10. The provider's two new facts, through the real delegate

    /// A `CLLocationManager` that answers "allowed" with a stubbed accuracy authorization.
    private final class StubManager: CLLocationManager {
        var stubbedAccuracy: CLAccuracyAuthorization = .fullAccuracy
        override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
        override var accuracyAuthorization: CLAccuracyAuthorization { stubbedAccuracy }
        override func startUpdatingLocation() {}
        override func stopUpdatingLocation() {}
        override func requestWhenInUseAuthorization() {}
    }

    private static func fix(accuracy: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 1,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    /// Ruling 9 at its source. The provider substitutes 25 m for a negative `horizontalAccuracy`
    /// and must say it did, or the screen cannot know not to quote it.
    @Test("the provider marks a fix CoreLocation stated no radius for, and a later one that states it")
    func theProviderMarksAnUnstatedRadius() {
        let manager = StubManager()
        let provider = MapLocationProvider(manager: manager)
        #expect(provider.precision.accuracyIsKnown)

        manager.delegate?.locationManager?(manager, didUpdateLocations: [Self.fix(accuracy: -1)])
        #expect(provider.availability.accuracyM == VisitShortlist.assumedAccuracyM)
        #expect(!provider.precision.accuracyIsKnown, "a negative horizontalAccuracy was published as stated")

        // A stated 25 m at the same spot is the same `availability`; only `precision` changes.
        manager.delegate?.locationManager?(manager, didUpdateLocations: [Self.fix(accuracy: 25)])
        #expect(provider.precision.accuracyIsKnown, "a stated radius after an unstated one stayed unknown")
    }

    /// Ruling 6 at its source: `accuracyAuthorization` is read when the provider is built and again
    /// on every authorization callback, which iOS also sends when Precise Location changes.
    @Test("the provider reads Precise Location, and reads it again when it changes")
    func theProviderReadsPreciseLocation() {
        let manager = StubManager()
        manager.stubbedAccuracy = .reducedAccuracy
        let provider = MapLocationProvider(manager: manager)
        #expect(provider.precision.isReduced, "reduced accuracy was not read at construction")

        manager.stubbedAccuracy = .fullAccuracy
        manager.delegate?.locationManagerDidChangeAuthorization?(manager)
        #expect(!provider.precision.isReduced, "turning Precise Location on was not read")
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
