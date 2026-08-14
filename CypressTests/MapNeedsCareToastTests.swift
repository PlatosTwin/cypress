//
//  MapNeedsCareToastTests.swift
//  CypressTests
//
//  Task #247 — the owner's 2026-08-06 instruction: "Leave as is, but we can add a quick and light
//  pop-up toast or the like (as long as it dismisses quick and doesn't pollute the map
//  permanently) that says no trees need care."
//
//  ── What each half of this suite can decide ───────────────────────────────────────────────────
//  `MapNeedsCareToast.isOwed` is a pure function of four facts, so *which state* is decidable
//  outright — including the half that matters most, which is every state that must stay silent
//  under `RULINGS R41`. What it cannot decide is *which moment*: the state holds for as long as
//  the chip is on over an empty map, and a toast posted every time it held would be the permanent
//  pollution the instruction excludes in its own words. That is `MapModel`'s re-arm rule, and the
//  second half of this file drives the real model through the real fetch path to pin it.
//
//  **None of it depends on the shipped seed carrying zero `declining` rows.** That is true today
//  (`ERRATA E244` counted it: the seed's only two statuses are `alive` and `vacant_site`) and it
//  is a fact about a published municipal dataset, not about this app — a re-ingest could change it
//  tomorrow and nothing here would move. Every answer below comes from a fake API.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@Suite("The Needs care toast (#247)")
struct MapNeedsCareToastTests {

    // MARK: - Which state

    /// The state the owner's instruction is about, and the only one that opens the gate: the
    /// `Needs care` chip on, nothing else narrowing anything, and a settled read with nothing to
    /// draw. `ERRATA E244` is what made it reachable — before it the chip did nothing at all to a
    /// clustered map.
    @Test("the needs-care chip alone over an empty map is owed the sentence")
    func theStateIsAnEmptyMapUnderTheChipAlone() {
        #expect(
            MapNeedsCareToast.isOwed(
                filter: .needsCare,
                isSearching: false,
                readFailed: false,
                markerCount: 0
            )
        )
    }

    /// **RULINGS R41 is the default and this is its single exception.** The owner refined R41 for
    /// one state; every other filter that empties the map keeps task #165's settlement ("if
    /// nothing matches, fine"), which `ERRATA E205` re-audited as clean. `In bloom` is the one
    /// that would be reached first by a generalization, because it is the other half of
    /// SCREENS.md 01 §12 and sits in the same enum.
    @Test("no other filter can open the gate, however empty it leaves the map (R41)")
    func everyOtherNarrowingKeepsR41sSilence() {
        let others: [(String, MapFilter)] = [
            ("In bloom", .inBloom),
            ("Yours", MapFilter(membership: .yours)),
            ("Favorites", MapFilter(membership: .favorites)),
            ("Year: 2010s", MapFilter(decade: .twentyTens)),
            ("a legend species", MapFilter(speciesID: UUID())),
            ("Site: empty planting site", MapFilter(siteKind: .emptySite)),
            ("the un-narrowed map", .all)
        ]
        for (name, filter) in others {
            #expect(
                !MapNeedsCareToast.isOwed(
                    filter: filter,
                    isSearching: false,
                    readFailed: false,
                    markerCount: 0
                ),
                """
                \(name) emptied the map and was given the needs-care toast. RULINGS R41 is \
                categorical and the owner refined it for one state only; this is the fourth \
                mechanism a filter-adjacent message has tried to survive under.
                """
            )
        }
    }

    /// **A conjunction cannot open it either, and that is an honesty gate rather than a scope
    /// gate.** `Needs care` beside a decade draws an empty map for a reason nobody can attribute:
    /// a tree on this block may well need care and simply not have been planted in the 2010s. The
    /// sentence is true of exactly one query, so it is shown for exactly that query.
    @Test("needs care with anything beside it says nothing")
    func aConjunctionSaysNothing() {
        let conjunctions: [(String, MapFilter)] = [
            ("+ Yours", MapFilter(membership: .yours, condition: .needsCare)),
            ("+ Year", MapFilter(decade: .nineties, condition: .needsCare)),
            ("+ a legend species", MapFilter(speciesID: UUID(), condition: .needsCare)),
            ("+ Site", MapFilter(condition: .needsCare, siteKind: .hasTree))
        ]
        for (name, filter) in conjunctions {
            #expect(
                !MapNeedsCareToast.isOwed(
                    filter: filter,
                    isSearching: false,
                    readFailed: false,
                    markerCount: 0
                ),
                """
                needs care \(name) posted "\(MapNeedsCareToastCopy.message)" over a map that was \
                emptied by two questions at once. The sentence claims more than that query asked.
                """
            )
        }
    }

    /// The search bar is the sixth narrowing and lives on `MapModel` rather than on `MapFilter`,
    /// so it is excluded through its own argument. `MapModel.isNarrowed` counts it for R41 and so
    /// does this.
    @Test("a typed species beside the chip says nothing")
    func aSearchBesideTheChipSaysNothing() {
        #expect(
            !MapNeedsCareToast.isOwed(
                filter: .needsCare,
                isSearching: true,
                readFailed: false,
                markerCount: 0
            ),
            "a searched map was told nothing needs care, when nothing matching the search does"
        )
    }

    /// **`markerCount`, not `pinCount`** — the whole of E244 is that the answer at zoom ≤ 15 is
    /// cluster badges. A single badge standing for 29,390 trees is emphatically not an empty
    /// screen, and a map with anything drawn on it has already answered the press.
    @Test("a map with anything drawn on it says nothing")
    func aDrawnMapSaysNothing() {
        for drawn in [1, 2, 171, 400] {
            #expect(
                !MapNeedsCareToast.isOwed(
                    filter: .needsCare,
                    isSearching: false,
                    readFailed: false,
                    markerCount: drawn
                ),
                "a map drawing \(drawn) markers was told that no trees need care"
            )
        }
    }

    /// `MapInventoryNotice.isOwed`'s argument, unchanged: "no trees need care" is a claim about the
    /// record, and a read that threw has learned nothing about the record. E126's own defect was a
    /// screen drawing its empty state for a read that never finished.
    @Test("a failed read is not an empty answer (E126)")
    func aFailedReadIsNotAnEmptyAnswer() {
        #expect(
            !MapNeedsCareToast.isOwed(
                filter: .needsCare,
                isSearching: false,
                readFailed: true,
                markerCount: 0
            ),
            "a read that threw was reported to the reader as a city with nothing needing care"
        )
    }

    // MARK: - The words

    /// Facts about the string, not its phrasing. Three facts: it carries no count (the first of the
    /// three surfaces R41 names as forbidden beside a filter), it makes no claim about the ground
    /// (`MapInventoryCopy`'s whole argument, one notice over), and it is not any other sentence on
    /// this screen — E158 is what it costs to let two different facts reach the reader in the same
    /// words.
    @Test("the sentence carries no count, no ground claim, and no other notice's words")
    func theSentenceIsItsOwnAndCountsNothing() {
        let message = MapNeedsCareToastCopy.message
        #expect(!message.isEmpty)
        // Reduced to a `Bool` before the macro sees it: `#expect` rewrites `contains(where:)` into
        // a `rethrows` call it then cannot type-check (same family as CLAUDE.md's `Data ==` hang).
        let carriesADigit = message.contains(where: \.isNumber)
        #expect(
            !carriesADigit,
            """
            the toast carries a number. RULINGS R41 names a count among the surfaces forbidden \
            beside a filter, and "on the chip is the chip's voice, not a companion message".
            """
        )
        #expect(
            !message.lowercased().contains("here"),
            """
            the toast says "here", which makes it a claim about the ground rather than about the \
            record — the distinction MapInventoryCopy.title spends its whole comment on.
            """
        )
        let showing = MapOpening.Showing.whereYouLeftOff
        let othersOnThisScreen = [
            MapInventoryCopy.title, MapInventoryCopy.message,
            MapOpeningCopy.notAskedTitle, MapOpeningCopy.notAskedMessage(showing),
            MapOpeningCopy.searchingTitle, MapOpeningCopy.searchingMessage(showing),
            MapLocationCopy.title(.denied), MapLocationCopy.message(showing),
            MapRecenterCopy.waitingTitle, MapRecenterCopy.waitingMessage
        ]
        #expect(
            !othersOnThisScreen.contains(message),
            "the toast reads as one of screen 01's standing notices; they are different facts (E158)"
        )
        // The three titles task #165 struck, which `MapEmptyInventoryTests` also refuses by name.
        // This is not that message box coming back under a new mechanism.
        for struck in ["No trees of yours here", "No favorites here", "Nothing matches here"] {
            #expect(message != struck)
        }
    }

    // MARK: - Which moment

    /// **The half a pure function cannot see, and the half the owner's instruction is really
    /// about.** `ERRATA E126`'s own warning applies verbatim: every test above passes with the
    /// gate written and nothing calling it. This drives the real `MapModel` through the real fetch
    /// path — press the chip, watch the toast, watch it let go of the screen by itself, and watch
    /// a pan afterwards fail to bring it back.
    @MainActor
    @Test("one activation of the chip posts one toast, which then lets go of the screen")
    func theChipIsAnsweredOnceAndTheAnswerGoesAway() async throws {
        let api = ToastAnswers()
        let model = MapModel(api: api, needsCareToastDuration: .milliseconds(400))

        // A settled, un-narrowed, empty screenful. R41 and task #165 both apply and the toast must
        // not be up: an empty map that nobody narrowed is `MapInventoryNotice`'s state, not this one.
        await api.answer(with: .pins(PinAnswer([])))
        model.cameraDidChange(bounds: Self.box, zoom: 18)
        try await Self.waitUntil { model.hasSettled }
        #expect(
            !model.needsCareToastIsShowing,
            "the toast was posted over a map nobody had narrowed (R41, task #165)"
        )

        // The press.
        model.filter = .needsCare
        try await Self.waitUntil { model.needsCareToastIsShowing }

        // "as long as it dismisses quick and doesn't pollute the map permanently" — the owner's own
        // condition, as an assertion. Nothing is pressed; the toast leaves on its own.
        try await Self.waitUntil { !model.needsCareToastIsShowing }

        // **The re-arm rule.** One pan later, over ground that is just as empty and with the chip
        // still on, and nothing is posted: the toast is the answer to the press, not a running
        // commentary on the map. The second answer carries a distinguishable `matchesInView` so
        // this waits on the read having actually landed rather than on a sleep — `markerCount` is
        // still 0, which is the state the gate reads.
        await api.answer(with: Self.secondEmptyAnswer)
        model.cameraDidChange(bounds: Self.boxNorth, zoom: 18)
        try await Self.waitUntil { model.content == Self.secondEmptyAnswer }
        #expect(
            !model.needsCareToastIsShowing,
            """
            a pan re-posted the toast. The re-arm rule is one activation of the chip, one answer; \
            a toast that fires on every camera move is the permanent pollution the owner's \
            instruction excludes.
            """
        )
    }

    /// Turning the chip off takes its answer with it. So does anything else that changes what the
    /// map is being asked — the sentence described one query's result and this is a different
    /// query.
    @MainActor
    @Test("turning the chip off takes the toast with it")
    func turningTheChipOffTakesTheToastWithIt() async throws {
        let api = ToastAnswers()
        // Long enough that nothing here is racing the auto-dismiss: what is under test is the
        // filter press, not the clock.
        let model = MapModel(api: api, needsCareToastDuration: .seconds(30))

        await api.answer(with: .pins(PinAnswer([])))
        model.cameraDidChange(bounds: Self.box, zoom: 18)
        try await Self.waitUntil { model.hasSettled }
        model.filter = .needsCare
        try await Self.waitUntil { model.needsCareToastIsShowing }

        model.filter = .all
        #expect(
            !model.needsCareToastIsShowing,
            "the toast outlived the chip that caused it, on a map that is no longer narrowed"
        )
    }

    /// A read that comes back with trees answers the press just as completely as an empty one, and
    /// must post nothing at all.
    @MainActor
    @Test("a map that has trees on it never raises the toast")
    func aMapWithTreesOnItNeverRaisesIt() async throws {
        let api = ToastAnswers()
        let model = MapModel(api: api, needsCareToastDuration: .seconds(30))

        // The opening read is deliberately a *different* value from the one the press gets back.
        // The first draft answered both with the badges, so `waitUntil { content == badges }` was
        // already true before the press was made and the assertion ran against the un-pressed
        // model — a test that could not fail. Caught by its own red-proof (`return true` in the
        // gate left it green), which is the whole reason CLAUDE.md asks for one.
        await api.answer(with: .pins(PinAnswer([])))
        model.cameraDidChange(bounds: Self.box, zoom: 18)
        try await Self.waitUntil { model.hasSettled }

        let badges = MapContent.clusters([
            TreeCluster(id: "z18:1:1", coordinate: Self.center, count: 27)
        ])
        await api.answer(with: badges)
        model.filter = .needsCare
        try await Self.waitUntil { model.content == badges }
        #expect(
            !model.needsCareToastIsShowing,
            "a map drawing 1 badge for 27 trees was told that no trees need care"
        )
    }

    /// **A press whose read failed has still had its answer, and must not carry credit forward.**
    ///
    /// Found in review of this ticket and reproduced there against a fake API that throws once;
    /// this is that probe made permanent. `noteReadFinished` was `noteSettledContent` and only the
    /// success path of `fetch()` called it, so a read that threw left `needsCareToastArmed` live
    /// *indefinitely* — and the next unrelated successful read, a plain pan with the chip
    /// untouched, consumed the stale arm and posted the toast. The sentence then answered the pan
    /// rather than the press, screens and minutes later: the "fires on every pan" pollution the
    /// owner's instruction excludes by name, reached through a transient network failure.
    ///
    /// **None of the other nine tests could see it.** `aFailedReadIsNotAnEmptyAnswer` drives the
    /// pure gate with `readFailed: true` and never goes near `fetch()`'s catch blocks; the two
    /// re-arm tests drive the success path only. This is the one that drives a throw through the
    /// real model.
    ///
    /// Three assertions, and the third is what keeps the fix from being an over-correction: the
    /// failed read itself says nothing (E126), the pan after it says nothing, and a **fresh press**
    /// still works — disarming on failure must not cost the chip its next legitimate activation.
    @MainActor
    @Test("a read that failed spends the press, and does not leave it for the next pan to collect")
    func aFailedReadSpendsThePress() async throws {
        let api = ToastAnswers()
        // Long enough that nothing here races the auto-dismiss: what is under test is the arming.
        let model = MapModel(api: api, needsCareToastDuration: .seconds(30))

        await api.answer(with: .pins(PinAnswer([])))
        model.cameraDidChange(bounds: Self.box, zoom: 18)
        try await Self.waitUntil { model.hasSettled }

        // 1 · The press, whose read throws.
        await api.failNextRead()
        model.filter = .needsCare
        try await Self.waitUntil { model.loadFailure != nil }
        #expect(
            !model.needsCareToastIsShowing,
            """
            a read that threw was reported to the reader as a city with nothing needing care. \
            "No trees need care" is a claim about the record, and a failed read has learned \
            nothing about the record (E126).
            """
        )

        // 2 · A plain pan. The chip is untouched — `needsCareChipDidChange` does not fire, because
        // the filter did not change — so nothing re-arms here. This read succeeds and comes back
        // just as empty, which is the state that would show a toast if the press were still owed
        // one.
        await api.answer(with: Self.secondEmptyAnswer)
        model.cameraDidChange(bounds: Self.boxNorth, zoom: 18)
        try await Self.waitUntil { model.content == Self.secondEmptyAnswer }
        #expect(
            !model.needsCareToastIsShowing,
            """
            a pan collected an arm left over from a press whose read had already failed, and \
            posted the toast as the answer to the pan. One activation of the chip is one answer, \
            and the failed read was that answer.
            """
        )

        // 3 · And the chip still works. A disarm that cost the next real activation would have
        // traded one defect for another.
        model.filter = .all
        model.filter = .needsCare
        try await Self.waitUntil { model.needsCareToastIsShowing }
        #expect(
            model.needsCareToastIsShowing,
            "disarming on a failed read left the chip unable to answer its next press"
        )
    }

    // MARK: - Fixtures

    /// One street-sized screenful, and one screenful north of it. The coordinates carry no meaning
    /// here — the fake API answers whatever it was last handed, so the subject is the model's
    /// bookkeeping and not the ground.
    private static let box = BoundingBox(
        minLatitude: 37.7680, maxLatitude: 37.7708,
        minLongitude: -122.4878, maxLongitude: -122.4846
    )
    private static let boxNorth = BoundingBox(
        minLatitude: 37.7740, maxLatitude: 37.7768,
        minLongitude: -122.4878, maxLongitude: -122.4846
    )
    private static let center = Coordinate(latitude: 37.7694, longitude: -122.4862)

    /// A second empty answer that is a *different value* from the first, so a wait can be made on
    /// the read having landed rather than on a sleep. `markerCount` is 0 either way — the pins are
    /// what the map draws, and there are none.
    private static let secondEmptyAnswer = MapContent.pins(PinAnswer([], matchesInView: 3))

    /// Polls rather than sleeping a fixed span, and shares `TestWait.ceiling` with every other map
    /// suite: a fake API removes the I/O, not the scheduler, and CI's runners have starved a
    /// five-second wait on this exact shape of test before (`MapEmptyInventoryTests.waitUntil`).
    private static func waitUntil(
        timeout: Duration = TestWait.ceiling,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let started = ContinuousClock.now
        let deadline = started + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let settled = await condition()
        TestWait.timedOut(
            after: started.duration(to: .now), sourceLocation: sourceLocation, { settled }
        )
    }
}

/// A `CypressAPI` that answers `mapContent` with whatever it was last handed, so an empty
/// screenful and a populated one can both be driven without the 103 MB seed — and so that nothing
/// here depends on the shipped seed's zero `declining` rows staying zero.
private actor ToastAnswers: CypressAPI {
    private var content: MapContent = .pins(PinAnswer([]))
    /// One read, and one only, throws. A flag rather than a mode, because what
    /// `aFailedReadSpendsThePress` is about is precisely what happens on the read *after* the
    /// failure — an API stuck in a failing state could never show it.
    private var failsNextRead = false

    func answer(with content: MapContent) { self.content = content }

    func failNextRead() { failsNextRead = true }

    func mapContent(in viewport: MapViewport) async throws -> MapContent {
        if failsNextRead {
            failsNextRead = false
            throw APIError.serverError
        }
        return content
    }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
    func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
    func species(id: UUID) async throws -> Species { throw APIError.notFound }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
    func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
        throw APIError.forbidden
    }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
    func grove() async throws -> [GroveEntry] { [] }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
    func deleteAccount(_ choice: AccountDeletionChoice) async throws -> AccountDeletion.Outcome {
        throw APIError.unauthorized
    }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
    func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
}
#endif
