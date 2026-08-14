import Foundation
import Testing
@testable import Cypress

/// Screen 19 · Memorial.
///
/// What this suite is here to hold, in the order the screen would betray it:
///
/// 1. **A removal never mutates `trees.status`.** An observation reporting one opens a review flag
///    and the tree is untouched (DECISIONS §3.7, BUILD-PLAN §6). `SQLiteStoreTests` pins the model's
///    half of that rule; this pins the write path end to end, because the model being right does not
///    stop `LocalAPI.apply` from writing a status.
/// 2. **A sentence with a fact the record does not hold is left out, not filled in.** The removal
///    date and reason have no column in BUILD-PLAN §4, and four separate pieces of copy depend on
///    the date.
/// 3. **Counts are honest.** A page renders nothing (ERRATA E38), and A8's headcount is floored.
/// 4. **Read-only is an absence.** The presentation has no CTA to offer, because it does not have
///    one to withhold.
@Suite("Memorial · screen 19")
struct MemorialPresentationTests {

    // MARK: - Fixtures

    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000C1")!
    private static let treeID = UUID(uuidString: "19000000-0000-4000-8000-0000000000C2")!
    private static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    private static func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter.date(from: iso)!
    }

    private static let species = try! Species(
        scientificName: "Corymbia ficifolia",
        commonName: "Red Flowering Gum",
        family: "Myrtaceae",
        leafRetention: .evergreen
    )

    private static func tree(status: TreeStatus = .removed, plantedYear: Int? = 2003) -> Tree {
        Tree(
            id: treeID,
            externalRef: "088-21",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.7605, longitude: -122.4931),
            address: "1450 Judah St",
            status: status,
            plantedYear: plantedYear,
            verificationState: .cityRecord
        )
    }

    private static func photos(_ count: Int) -> [Photo] {
        (0..<count).map { index in
            Photo(
                treeID: treeID,
                shotType: .fullTree,
                capturedAt: date(String(format: "%04d-%02d-15", 2019 + index / 12, index % 12 + 1))
            )
        }
    }

    private static let visit = Visit(
        treeID: treeID,
        attribution: Attribution(userID: UUID(), deviceID: deviceID),
        note: "The reddest bloom on the block, every January",
        capturedAt: date("2026-01-18")
    )

    private static func observation(verified: Bool) -> TreeObservation {
        TreeObservation(
            treeID: treeID,
            attribution: Attribution(userID: UUID(), deviceID: deviceID),
            capturedAt: date("2026-03-04"),
            vitality: .poor,
            verificationState: verified ? .orgVerified : .unverified
        )
    }

    /// Three people, two contributions each: A8's floor exactly.
    private static func careEvents(people: Int, each: Int = 2) -> [CareEvent] {
        (0..<people).flatMap { person -> [CareEvent] in
            let userID = UUID()
            return (0..<each).map { index in
                CareEvent(
                    treeID: treeID,
                    attribution: Attribution(userID: userID, deviceID: deviceID),
                    capturedAt: date("2025-0\(index + 5)-12"),
                    actions: [.watered]
                )
            }
        }
    }

    private static func profile(
        status: TreeStatus = .removed,
        photoCount: Int = 86,
        photosComplete: Bool = true,
        verifiedCheckIn: Bool = true,
        caretakers: Int = 3,
        plantedYear: Int? = 2003,
        named: Bool = true
    ) -> TreeProfile {
        let shots = photos(photoCount)
        let check = observation(verified: verifiedCheckIn)
        return TreeProfile(
            tree: tree(status: status, plantedYear: plantedYear),
            activeName: named
                ? TreeName(treeID: treeID, name: "Judah Street Gum", givenBy: nil)
                : nil,
            species: species,
            latestObservation: check,
            observations: Series(complete: [check]),
            photos: Series(items: shots, isComplete: photosComplete),
            visits: Series(complete: [visit]),
            careEvents: Series(complete: careEvents(people: caretakers)),
            ownPhotoIDs: Set(shots.map(\.id))
        )
    }

    private static let removedInMay = MemorialFacts(removedAt: date("2026-05-11"))

    // MARK: - 1. A removal never mutates the tree

    /// End to end: an anonymous device reports `appears_removed` through the outbox, the item is
    /// applied, and the tree is exactly as it was — with one open review flag beside it.
    @Test("an observation reporting a removal opens a review flag and leaves trees.status alone")
    func removalNeverMutatesStatus() async throws {
        let store = try await CypressStore.inMemory()
        let api = LocalAPI(store: store, deviceID: Self.deviceID)
        let outbox = OutboxQueue(queue: store.queue, apply: APIOutboxTransport(api: api))

        let tree = try await api.addTree(
            TreeDraft(
                coordinate: Coordinate(latitude: 37.77, longitude: -122.44),
                photoLocalPath: "/tmp/cypress-memorial-test.jpg",
                attribution: Attribution.anonymous(deviceID: Self.deviceID)
            )
        )
        #expect(tree.status == .alive)

        _ = try await outbox.enqueue(
            .observation(TreeObservation(
                treeID: tree.id,
                attribution: Attribution.anonymous(deviceID: Self.deviceID),
                capturedAt: Self.now,
                status: .appearsRemoved
            ))
        )
        _ = try await outbox.drain()

        // The tree did not move.
        let after = try await api.treeProfile(id: tree.id)
        #expect(after.tree.status == .alive, "an observation moved trees.status, which DECISIONS §3.7 forbids")
        #expect(after.tree.status.isMemorial == false)

        // And the flag it was supposed to open exists, open, once.
        let flags = try await store.queue.read { connection -> [(String, String)] in
            let statement = try connection.prepare("SELECT kind, status FROM review_flags")
            defer { statement.finalize() }
            return try statement.fetchAll { (try $0.string("kind"), try $0.string("status")) }
        }
        #expect(flags.count == 1)
        #expect(flags.first?.0 == "appears_removed")
        #expect(flags.first?.1 == "open")
    }

    /// The screen's own half of the same rule: it is `trees.status` that decides, so a tree nobody
    /// has confirmed removed does not get a memorial however grim its last check-in was.
    @Test("the memorial screen refuses a tree that is not removed")
    @MainActor
    func gateIsTheTreeStatus() async {
        let model = MemorialModel(
            treeID: Self.treeID,
            api: MemorialPreviewAPI(profile: Self.profile(status: .declining)),
            now: { Self.now }
        )
        await model.load()
        #expect(model.phase == .notMemorial)
        #expect(model.presentation == nil)
    }

    @Test("a removed tree loads, and its badge is REMOVED whatever its last vitality said")
    @MainActor
    func memorialLoads() async {
        let model = MemorialModel(
            treeID: Self.treeID,
            api: MemorialPreviewAPI(profile: Self.profile()),
            now: { Self.now }
        )
        await model.load()
        #expect(model.presentation != nil)
        #expect(model.presentation?.badge == .removed)
    }

    // MARK: - 2. What the record cannot say, it does not say

    @Test("with no removal date, four separate claims lose their clause rather than guess")
    func noRemovalDateNoClaims() {
        let presentation = MemorialPresentation(profile: Self.profile(), now: Self.now)

        // §2 — the banner keeps its sentence and loses its date.
        #expect(presentation.bannerLeadIn == "Removed by the city.")
        #expect(presentation.bannerBody.hasPrefix(" This profile is now read-only."))

        // §3 — no `2003–2026`, because half a span is not a span.
        #expect(!presentation.subtitle.contains("–"))
        #expect(presentation.subtitle == "Red Flowering Gum · Corymbia ficifolia")

        // §6 — no `On record · 23 years`.
        #expect(presentation.stats.map(\.id) == ["cityRecord"])

        // §4 — no city-record row at the foot of the timeline.
        #expect(!presentation.moments.contains { $0.kind == .cityRecord })
    }

    @Test("with a removal date, the drawn screen appears in full")
    func withARemovalDateEverythingIsSaid() {
        let presentation = MemorialPresentation(
            profile: Self.profile(),
            facts: Self.removedInMay,
            now: Self.now
        )

        #expect(presentation.bannerLeadIn == "Removed by the city, May 2026.")
        #expect(presentation.subtitle == "Red Flowering Gum · Corymbia ficifolia · 2003–2026")
        #expect(presentation.stats.first(where: { $0.id == "onRecord" })?.value == "23 years")
        #expect(presentation.stats.first(where: { $0.id == "cityRecord" })?.value == "#088-21")

        let cityRow = presentation.moments.first { $0.kind == .cityRecord }
        #expect(cityRow?.label == "City record")
        // The mock's ` · storm damage` has no column behind it and is not written.
        #expect(cityRow?.detail == " · marked removed")
        #expect(cityRow?.timestamp == "May 2026")
    }

    @Test("the timeline reads oldest first, which is what makes it a life rather than a feed")
    func timelineIsChronological() {
        let presentation = MemorialPresentation(
            profile: Self.profile(),
            facts: Self.removedInMay,
            now: Self.now
        )
        #expect(presentation.moments.map(\.label) == ["First photo", "Visit", "Check-in", "City record"])
        #expect(presentation.moments.map(\.timestamp) == ["Jan 2019", "Jan 2026", "Mar 2026", "May 2026"])
    }

    @Test("the steward clause is a provenance claim and needs the column that carries it")
    func stewardClauseNeedsVerification() {
        let verified = MemorialPresentation(profile: Self.profile(verifiedCheckIn: true), now: Self.now)
        #expect(
            verified.moments.first { $0.label == "Check-in" }?.detail
                == " · vitality 2 · a steward confirmed the decline"
        )

        let unverified = MemorialPresentation(profile: Self.profile(verifiedCheckIn: false), now: Self.now)
        #expect(unverified.moments.first { $0.label == "Check-in" }?.detail == " · vitality 2")
    }

    // MARK: - 3. Counts

    @Test("the hero pill states a whole series or nothing at all")
    func heroPillNeedsAWholeSeries() {
        let whole = MemorialPresentation(profile: Self.profile(), facts: Self.removedInMay, now: Self.now)
        #expect(whole.heroMetaPill == "86 photos · 2019–2026")
        #expect(whole.heroEyebrow == "Last photo · Feb 2026")

        // The same tree, read as a page: two claims about all the photographs, neither provable.
        let paged = MemorialPresentation(
            profile: Self.profile(photoCount: 30, photosComplete: false),
            facts: Self.removedInMay,
            now: Self.now
        )
        #expect(paged.heroMetaPill == nil)
    }

    @Test("a tree nobody photographed has no pill, no eyebrow and no first-photo row")
    func nothingRecorded() {
        let bare = TreeProfile(tree: Self.tree(), species: Self.species)
        let presentation = MemorialPresentation(profile: bare, facts: Self.removedInMay, now: Self.now)

        #expect(presentation.heroMetaPill == nil)
        #expect(presentation.heroEyebrow == nil)
        #expect(presentation.moments.map(\.label) == ["City record"])
        // The banner is the one thing this screen always has.
        #expect(presentation.bannerLeadIn == "Removed by the city, May 2026.")
    }

    @Test("A8's headcount is floored at three and spelled out")
    func caretakerFloor() {
        let three = MemorialPresentation(profile: Self.profile(caretakers: 3), now: Self.now)
        #expect(
            three.moments.first { $0.label == "First photo" }?.detail
                == " · the record begins · three people came to know it"
        )

        // Two caretakers: the clause goes, the row stays (DECISIONS constraint 1).
        let two = MemorialPresentation(profile: Self.profile(caretakers: 2), now: Self.now)
        #expect(two.moments.first { $0.label == "First photo" }?.detail == " · the record begins")

        // A page cannot be counted over at all.
        let partialPhotos = Self.photos(4)
        let partial = TreeProfile(
            tree: Self.tree(),
            species: Self.species,
            photos: Series(complete: partialPhotos),
            careEvents: Series(items: Self.careEvents(people: 4), isComplete: false),
            ownPhotoIDs: Set(partialPhotos.map(\.id))
        )
        #expect(
            MemorialPresentation(profile: partial, now: Self.now)
                .moments.first { $0.label == "First photo" }?.detail == " · the record begins"
        )
    }

    // MARK: - 3b. Photo visibility (ERRATA E215)

    /// Every fixture above is all-own (`profile()`'s `ownPhotoIDs: Set(shots.map(\.id))`), so the
    /// screen's non-own arm has never had a failing case. `MemorialPresentation` now reads
    /// `TreeProfile.visiblePhotos` (`isVisibleOnDevice`, ERRATA E215) rather than `photos` directly,
    /// the same predicate `PhotoVisibilityParityTests` pins for the hero and the browser — this pins
    /// it for the memorial, the third and last reader of that series.
    ///
    /// The stranger's photo is dated earliest, so under the old own-blind filter (every row read
    /// through `isVisibleToItsContributor` alone, the exact defect E215 names) it would win §4's
    /// "First photo" row; under the fixed predicate it must lose to the device's own, later photo.
    @Test("a memorial does not surface a stranger's pending photo")
    func strangersPendingPhotoDoesNotSurface() {
        // Day 15, not day 1 — `photos(_:)` above uses the same middle-of-month anchor so a
        // timezone offset cannot walk a date across a month boundary and flip the label read out.
        let ownPhoto = Photo(
            treeID: Self.treeID, shotType: .fullTree, moderationState: .approved,
            capturedAt: Self.date("2020-06-15")
        )
        let strangersPending = Photo(
            treeID: Self.treeID, shotType: .trunk, moderationState: .pending,
            capturedAt: Self.date("2019-01-15")
        )

        // Fixture sanity, same shape as `PhotoVisibilityParityTests`: the row really is visible to
        // its own contributor and really is unmoderated, or this is not the case E215 names.
        #expect(strangersPending.isVisibleToItsContributor)
        #expect(!strangersPending.isPubliclyVisible)

        let profile = TreeProfile(
            tree: Self.tree(),
            species: Self.species,
            photos: Series(complete: [ownPhoto, strangersPending]),
            ownPhotoIDs: [ownPhoto.id]
        )
        let presentation = MemorialPresentation(profile: profile, facts: Self.removedInMay, now: Self.now)

        let firstPhoto = presentation.moments.first { $0.kind == .firstPhoto }
        #expect(
            firstPhoto?.id != strangersPending.id,
            "screen 19's 'First photo' row showed a stranger's unmoderated photograph (\(strangersPending.id)) — the exact failure ERRATA E215 names"
        )
        #expect(firstPhoto?.id == ownPhoto.id)
        #expect(firstPhoto?.timestamp == "Jun 2020")
    }

    // MARK: - 4. Read-only is an absence

    /// SCREENS.md 19: "no Visit CTA, no quad action row, no foliage strip. That absence *is* the
    /// read-only state." Asserted over the presentation's own field list, because the way this
    /// regresses is somebody adding a disabled button rather than removing an enabled one.
    @Test("the memorial presentation has nothing to press")
    func nothingToPress() {
        let presentation = MemorialPresentation(profile: Self.profile(), now: Self.now)
        let fields = Mirror(reflecting: presentation).children.compactMap(\.label)
        for field in fields {
            let normalized = field.lowercased()
            for forbidden in ["cta", "action", "button", "visit"] where normalized.contains(forbidden) {
                Issue.record("screen 19 grew a \(field); read-only is the absence, not a disabled control")
            }
        }
        #expect(!fields.isEmpty)
    }

    /// The lineage promise is about a city replanting a site it owns; a community-added record has
    /// no city behind it.
    @Test("the lineage callout is not promised where there is no city to replant")
    func lineageOnlyForCityRecords() {
        let city = MemorialPresentation(profile: Self.profile(), now: Self.now)
        #expect(city.lineageLeadIn == "A new tree is coming.")
        #expect(city.lineageBody?.hasSuffix("the site keeps its lineage.") == true)

        let community = TreeProfile(
            tree: Tree(
                id: Self.treeID,
                source: .community,
                coordinate: Coordinate(latitude: 37.76, longitude: -122.49),
                status: .removed
            ),
            species: Self.species
        )
        let presentation = MemorialPresentation(profile: community, now: Self.now)
        #expect(presentation.lineageLeadIn == nil)
        #expect(presentation.stats.isEmpty, "there is no SF city record for a community-added tree")
    }

    /// ARCHITECTURE §5.7: no spaces around em dashes. Screen 19 carries two of the app's em dashes,
    /// both un-spaced in the source, and both easy to "fix" into wrongness.
    @Test("screen 19's em dashes carry no spaces")
    func emDashRule() {
        for line in [MemorialCopy.bannerBody, MemorialCopy.lineageBody] {
            #expect(line.contains("—"))
            #expect(!line.contains(" — "), "spaced em dash in: \(line)")
        }
    }
}

/// A record that cannot take a contribution must not offer one.
///
/// The profile is reachable with a removed tree from paths that are not the map — the almanac's
/// elder row, the visit flow's open-tree — and it used to draw a REMOVED badge beside a live
/// "say hello with a photo" button. Gating both affordances on one property means a third such
/// status cannot be added without answering the question. See ERRATA (E95).
@Suite("A read-only record offers nothing to press")
struct ReadOnlyRecordTests {

    @Test("neither a memorial nor a vacant site invites a contribution", arguments: [
        TreeStatus.removed, TreeStatus.vacantSite
    ])
    func closedStatusesAcceptNothing(status: TreeStatus) {
        #expect(!status.acceptsNewContributions)
    }

    @Test("a living tree still does", arguments: [
        TreeStatus.alive, TreeStatus.declining, TreeStatus.deadReported
    ])
    func openStatusesAcceptContributions(status: TreeStatus) {
        #expect(status.acceptsNewContributions)
    }

    /// The point of the property. If a status is added and nobody decides which side it falls on,
    /// this fails rather than silently defaulting to "yes, offer a write".
    @Test("every status has been classified deliberately")
    func everyStatusIsClassified() {
        #expect(TreeStatus.allCases.count == 5, "a status was added — decide whether it takes contributions")
    }
}
