import Foundation
import Testing
@testable import Cypress

/// The vacant planting site — 12,518 of the seed's 195,309 records, no mocked screen, decided in
/// ERRATA E107 (closing E11).
///
/// What this suite is here to hold, in the order the screen would betray it:
///
/// 1. **A site is not a tree.** The map sends it to its own route, its card does not call it
///    `Unidentified`, and it never draws a badge saying something was planted in it.
/// 2. **Nothing on it is a write.** A site takes no contribution, and the one affordance it has is a
///    read that lands on a tree that is actually standing.
/// 3. **`nearest` is a claim, and it has to be true.** The nearest *standing* tree, skipping the
///    basins in front of it, keyed on the site's coordinate rather than the reader's.
/// 4. **No sentence promises an outcome.** Cypress does not plant trees and has notified nobody
///    (ARCHITECTURE §5.4).
/// 5. **A fact the record does not carry takes its card with it**, rather than rendering blank.
@MainActor
@Suite("Site · the vacant planting site")
struct SiteTests {

    // MARK: - Doubles and fixtures

    /// One profile, one nearby list, and either of them can be made to fail.
    private struct Records: CypressAPI {
        var profile: TreeProfile
        var nearby: [NearbyTree] = []
        var nearbyFails = false

        func treeProfile(id: UUID) async throws -> TreeProfile { profile }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] {
            if nearbyFails { throw APIError.serverError }
            return nearby
        }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    private static let siteID = UUID(uuidString: "5E000000-0000-4000-8000-0000000000C1")!
    private static let standingID = UUID(uuidString: "5E000000-0000-4000-8000-0000000000C2")!
    private static let coordinate = Coordinate(latitude: 37.7601, longitude: -122.4014)

    /// **Every fixture below is pinned to this instant, and that is not tidiness.**
    ///
    /// `Tree.init` defaults `createdAt` and `updatedAt` to `Date()`, so two fixtures built from the
    /// same helper are *not* equal — they differ by however long the test took to get from one line
    /// to the next. A test that compares a whole `TreeProfile` against a freshly built one is then
    /// asserting something stronger than "this is the same site": it is asserting that two clock
    /// readings match, which is true on a fast machine and false on a slow one. That is exactly the
    /// shape of a test that passes for a week and then fails on somebody else's laptop, and it
    /// failed for another agent running the full suite before it failed here.
    ///
    /// `SiteModel` reads no clock of its own — nothing on this screen formats a date — so the fix is
    /// not an injected `now:` but a fixture that holds still. The comparison is narrowed as well:
    /// what these tests mean is "the screen loaded this site", not "these two timestamps agree".
    private static let fixedInstant = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    private static func site(
        status: TreeStatus = .vacantSite,
        address: String? = "666 Rhode Island St",
        siteType: String? = "Sidewalk: Curb side : Cutout",
        externalRef: String? = "201-33",
        source: TreeSource = .cityImport,
        plantedYear: Int? = nil
    ) -> Tree {
        Tree(
            id: siteID,
            externalRef: externalRef,
            source: source,
            coordinate: coordinate,
            address: address,
            siteType: siteType,
            status: status,
            plantedYear: plantedYear,
            verificationState: .cityRecord,
            createdAt: fixedInstant,
            updatedAt: fixedInstant
        )
    }

    private static func profile(
        _ tree: Tree? = nil,
        neighborhood: String? = "Potrero Hill"
    ) -> TreeProfile {
        TreeProfile(tree: tree ?? site(), neighborhoodName: neighborhood)
    }

    private static func nearby(
        id: UUID,
        status: TreeStatus,
        distanceM: Double,
        commonName: String? = nil
    ) -> NearbyTree {
        NearbyTree(
            tree: Tree(
                id: id,
                source: .cityImport,
                coordinate: coordinate,
                status: status,
                createdAt: fixedInstant,
                updatedAt: fixedInstant
            ),
            distanceM: distanceM,
            speciesScientificName: nil,
            speciesCommonName: commonName,
            tell: nil
        )
    }

    private static func pin(status: TreeStatus, source: TreeSource = .cityImport) -> TreePin {
        TreePin(
            id: siteID,
            coordinate: coordinate,
            status: status,
            source: source,
            verificationState: .cityRecord,
            speciesID: nil
        )
    }

    /// Every string this screen can put on a phone, in one place, so the sweeps below cannot miss
    /// one by not knowing about it.
    private static func allCopy() -> [String] {
        [
            SiteCopy.headerTitle,
            SiteCopy.fallbackTitle,
            SiteCopy.kind,
            SiteCopy.provenance(.cityImport),
            SiteCopy.provenance(.community),
            SiteCopy.statementLeadIn,
            SiteCopy.statementBody,
            SiteCopy.siteLabel,
            SiteCopy.cityRecordLabel,
            SiteCopy.neighborhoodLabel,
            SiteCopy.neighbourDetail(metres: 24),
            SiteCopy.unidentified,
            SiteCopy.footnote,
            SiteCopy.cardTitle,
            SiteCopy.cardMeta,
            SiteCopy.cardAccessibilityHint,
            SiteCopy.pinAccessibilityLabel,
            SiteCopy.notASite,
            SiteCopy.noRecord,
            SiteCopy.couldNotLoad,
            SiteCopy.tryAgain
        ]
    }

    // MARK: - 1. A site is not a tree profile

    /// The entrance. Before E107 a vacant pin pushed `.treeProfile`, which is what put screen 14's
    /// photo well and its "be the first to photograph this tree" in front of 12,518 empty basins.
    @Test("a vacant pin opens the site, not a profile and not a memorial")
    func vacantPinRoutesToTheSite() {
        #expect(SiteTests.route(.vacantSite) == .site(SiteTests.siteID))
    }

    /// The branch it was added beside, which it must not have swallowed: screen 01's caption sends a
    /// removed pin to 19, and everything else to 03.
    @Test("every other pin keeps the destination it had", arguments: [
        (TreeStatus.removed, "memorial"),
        (TreeStatus.alive, "profile"),
        (TreeStatus.declining, "profile"),
        (TreeStatus.deadReported, "profile")
    ])
    func otherPinsAreUnchanged(status: TreeStatus, expected: String) {
        let route = SiteTests.route(status)
        if expected == "memorial" {
            #expect(route == .memorial(SiteTests.siteID))
        } else {
            #expect(route == .treeProfile(SiteTests.siteID))
        }
    }

    private static func route(_ status: TreeStatus) -> Route {
        MapHomeView.route(for: pin(status: status))
    }

    /// The card used to call a site `Unidentified` — the word for a tree whose species nobody
    /// resolved, said of a record with no tree to identify — and it read that off the pin's fallback
    /// before the profile even landed.
    @Test("the map card names a site rather than calling it unidentified")
    func cardNamesTheSite() {
        let subject = MapCardSubject(pin: SiteTests.pin(status: .vacantSite))

        #expect(subject.isVacantSite)
        #expect(subject.title == SiteCopy.cardTitle)
        #expect(subject.title != "Unidentified")
    }

    /// The one that would have shipped a lie. `StatusBadge.kind` badges a tree with no check-in and
    /// a planted year as `PLANTED <year>`, and DataSF hands plant dates to rows that are now empty
    /// basins — so the card drew a badge asserting a planting into a hole.
    @Test("a site never draws a badge saying something was planted in it")
    func siteDrawsNoPlantedBadge() {
        let tree = SiteTests.site(plantedYear: 2024)
        let subject = MapCardSubject(
            pin: SiteTests.pin(status: .vacantSite),
            profile: SiteTests.profile(tree)
        )

        #expect(subject.badge == nil)

        // The same record with a tree standing on it still badges, so the suppression is about the
        // site and not about a missing check-in.
        var standing = tree
        standing.status = .alive
        let living = MapCardSubject(
            pin: SiteTests.pin(status: .alive),
            profile: SiteTests.profile(standing)
        )
        #expect(living.badge == .planted(year: 2024))
    }

    /// A site is neither drawn nor announced as a memorial (RULINGS R7).
    ///
    /// E107 fixed the label and left the pin: C19 had no pin for a site, so 12,518 basins drew as the
    /// memorial's grey dot while saying they were not one. R7 made the design decision E107 had no
    /// standing to make, so both halves now agree — which is what the `kind` expectations below pin,
    /// and what this test could not say before.
    @Test("a site pin is neither drawn nor announced as a memorial")
    func sitePinAnnouncesItself() {
        let site = MapPinKind.accessibilityLabel(for: SiteTests.pin(status: .vacantSite))
        let memorial = MapPinKind.accessibilityLabel(for: SiteTests.pin(status: .removed))

        #expect(site == SiteCopy.pinAccessibilityLabel)
        #expect(site != memorial)
        #expect(memorial == MapPin.Kind.removed.accessibilityLabel)

        // The drawn half, which is what R7 added.
        #expect(MapPinKind.kind(for: SiteTests.pin(status: .vacantSite)) == .vacantSite)
        #expect(MapPinKind.kind(for: SiteTests.pin(status: .removed)) == .removed)

        // A basin has no fill, and that absence is the whole distinction — so it is asserted rather
        // than left to a screenshot nobody diffs.
        #expect(MapPin.Kind.vacantSite.fill == .clear)
        #expect(MapPin.Kind.vacantSite.fill != MapPin.Kind.removed.fill)
    }

    /// A community-added site keeps the dashed community pin and its own label: the override is
    /// scoped to the pin it actually shares, not to the status.
    @Test("the label override does not leak onto the community layer")
    func communitySiteKeepsItsLabel() {
        let pin = TreePin(
            id: SiteTests.siteID,
            coordinate: SiteTests.coordinate,
            status: .vacantSite,
            source: .community,
            verificationState: .unverified,
            speciesID: nil
        )

        #expect(MapPinKind.kind(for: pin) == .community)
        #expect(MapPinKind.accessibilityLabel(for: pin) == MapPin.Kind.community.accessibilityLabel)
    }

    // MARK: - 2. Nothing on the screen is a write

    /// The gate, and the reason this screen exists rather than a variant of 03.
    @Test("a site takes no contribution")
    func siteTakesNoContribution() {
        #expect(!TreeStatus.vacantSite.acceptsNewContributions)
    }

    /// The stat grid is the city's record and nothing else. Screen 03's grid offers an *empty*
    /// measurement card as the entrance to screen 16; if this screen ever derived its cards from
    /// that one, the invitation to measure a trunk would arrive on a record with no trunk.
    @Test("the grid holds the city's facts and no invitation to fill one in")
    func gridIsTheCityRecordOnly() {
        let subject = SitePresentation(profile: SiteTests.profile())

        #expect(subject.stats.map(\.id) == ["site", "cityRecord", "neighborhood"])
        #expect(subject.stats.allSatisfy { !$0.value.isEmpty })
        #expect(!subject.stats.contains { $0.label == "Height" || $0.label == "DBH" })
        #expect(!subject.stats.contains { $0.label == "Planted" })
    }

    /// A card whose fact the record does not carry is absent, not blank. Most of the seed's sites
    /// carry a `qSiteInfo` string and a reference; some carry neither.
    @Test("a fact the record does not hold takes its card with it")
    func absentFactsTakeTheirCards() {
        let bare = SiteTests.site(address: nil, siteType: nil, externalRef: nil)
        let subject = SitePresentation(profile: SiteTests.profile(bare, neighborhood: nil))

        #expect(subject.stats.isEmpty)
        // …and the screen still says the one thing it exists to say.
        #expect(!subject.statementLeadIn.isEmpty)
        #expect(!subject.footnote.isEmpty)
    }

    /// A community-added row has no city reference to cite, under the same rule 03, 14 and 19 apply.
    @Test("only a city row carries a city record number")
    func onlyCityRowsCiteTheCity() {
        let community = SiteTests.site(source: .community)
        let subject = SitePresentation(profile: SiteTests.profile(community))

        #expect(!subject.stats.contains { $0.id == "cityRecord" })
        #expect(subject.subtitle.hasSuffix(SiteCopy.provenance(.community)))
    }

    // MARK: - 3. `nearest` is a claim

    /// The whole reason the row is filtered rather than taken off the top of the list: 6.4% of the
    /// inventory is a vacant site and sites cluster, so the rows in front of the answer are very
    /// often other basins. `nearby.first` — which is what one writes without thinking — points this
    /// site at another empty hole 11 m away.
    @Test("the nearest tree is the nearest *standing* one")
    func nearestSkipsWhatIsNotThere() async throws {
        let model = SiteModel(
            treeID: SiteTests.siteID,
            api: Records(
                profile: SiteTests.profile(),
                nearby: [
                    SiteTests.nearby(id: SiteTests.siteID, status: .vacantSite, distanceM: 0),
                    SiteTests.nearby(id: UUID(), status: .vacantSite, distanceM: 11),
                    SiteTests.nearby(id: UUID(), status: .removed, distanceM: 18),
                    SiteTests.nearby(
                        id: SiteTests.standingID,
                        status: .alive,
                        distanceM: 24,
                        commonName: "London Plane"
                    ),
                    SiteTests.nearby(id: UUID(), status: .alive, distanceM: 31)
                ]
            )
        )

        await model.load()

        let neighbour = try #require(model.presentation?.neighbour)
        #expect(neighbour.id == SiteTests.standingID)
        #expect(neighbour.title == "London Plane")
        #expect(neighbour.detail == "24 m away · the nearest tree to this site")
    }

    /// A site is never its own nearest tree. It is in its own nearby list at distance zero, and it
    /// is excluded by the same test that excludes every other basin rather than by its id.
    @Test("a site does not point at itself")
    func siteIsNotItsOwnNeighbour() async {
        let model = SiteModel(
            treeID: SiteTests.siteID,
            api: Records(
                profile: SiteTests.profile(),
                nearby: [SiteTests.nearby(id: SiteTests.siteID, status: .vacantSite, distanceM: 0)]
            )
        )

        await model.load()

        #expect(model.presentation?.neighbour == nil)
    }

    /// The row is absent rather than reworded when there is nothing standing within reach — the same
    /// answer every other surface gives to a fact it does not hold.
    @Test("nothing standing nearby means no row")
    func noStandingTreeMeansNoRow() async {
        let model = SiteModel(treeID: SiteTests.siteID, api: Records(profile: SiteTests.profile()))
        await model.load()

        // What is meant is "the screen loaded this site", not "two `TreeProfile` values are equal
        // in every stored property" — the second is a stronger claim that drags two clock readings
        // into it. See `fixedInstant`.
        guard case let .loaded(profile) = model.phase else {
            Issue.record("the site did not load")
            return
        }
        #expect(profile.tree.id == SiteTests.siteID)
        #expect(model.presentation?.neighbour == nil)
    }

    /// The accessory read must not take the screen down with it. Written as `try await` inside the
    /// same `do` block — the natural way to write it — a failed nearby read would blank the sentence
    /// this screen exists to say.
    @Test("a failed nearby read costs one row, not the screen")
    func nearbyFailureCostsOneRow() async {
        let model = SiteModel(
            treeID: SiteTests.siteID,
            api: Records(profile: SiteTests.profile(), nearbyFails: true)
        )

        await model.load()

        #expect(model.presentation != nil)
        #expect(model.presentation?.neighbour == nil)
        if case .failed = model.phase { Issue.record("a nearby read failed the whole screen") }
    }

    /// Standing is not the same question as "may this take a contribution", even though the five
    /// statuses happen to split the same way today. A tree reported dead is still standing until
    /// somebody confirms it, and it is still the nearest tree to this basin.
    @Test("a tree reported dead is still a tree that is there")
    func deadReportedStillStands() {
        #expect(SiteModel.isStanding(.deadReported))
        #expect(SiteModel.isStanding(.alive))
        #expect(SiteModel.isStanding(.declining))
        #expect(!SiteModel.isStanding(.removed))
        #expect(!SiteModel.isStanding(.vacantSite))
    }

    /// The point of the exhaustive switch. If a sixth status is added and nobody decides which side
    /// it falls on, this fails rather than the map silently pointing at it.
    @Test("every status has been classified deliberately")
    func everyStatusIsClassified() {
        #expect(
            TreeStatus.allCases.count == 5,
            "a status was added — decide whether a tree stands at it"
        )
    }

    // MARK: - 4. The gate, and the two states that are not the screen

    /// A record with a tree standing on it. A moderator can move a status (DECISIONS §3.7), so can
    /// the weekly city diff, and a link is followed later than it was made — so this screen can be
    /// opened on a tree, and the one thing it must never do is say "no tree at this site" over one.
    @Test("opened on a standing tree, the screen says so and draws nothing")
    func standingTreeIsNotASite() async {
        let tree = SiteTests.site(status: .alive)
        let model = SiteModel(treeID: SiteTests.siteID, api: Records(profile: SiteTests.profile(tree)))

        await model.load()

        #expect(model.phase == .notASite)
        #expect(model.presentation == nil)
    }

    /// A memorial is not a site either. Both are records with no living tree, and 19 is a screen
    /// about a tree that was — routing one here would delete its timeline behind a sentence saying
    /// nothing was ever here.
    @Test("a memorial is not a site")
    func memorialIsNotASite() async {
        let tree = SiteTests.site(status: .removed)
        let model = SiteModel(treeID: SiteTests.siteID, api: Records(profile: SiteTests.profile(tree)))

        await model.load()

        #expect(model.phase == .notASite)
    }

    // MARK: - 5. No sentence promises an outcome

    /// ARCHITECTURE §5.4: never render copy implying an authority was notified. Cypress does not
    /// plant trees and cannot promise one, and this is the screen where that temptation is largest —
    /// a person standing at an empty basin is exactly who wants to be told a tree is coming.
    @Test("nothing on this screen notifies anybody or promises a tree")
    func noSentencePromisesAnOutcome() {
        let forbidden = [
            "sent to the city",
            "notified",
            "notify",
            "report it",
            "reported to",
            "request a tree",
            "we'll plant",
            "will be planted",
            "coming soon",
            "on the way",
            "311"
        ]

        for line in SiteTests.allCopy() {
            let lowercased = line.lowercased()
            for phrase in forbidden {
                #expect(!lowercased.contains(phrase), "\(phrase) appears in: \(line)")
            }
        }
    }

    /// The one sentence that has to be exactly right says what Cypress does and stops.
    @Test("the screen states plainly that this app does not plant trees")
    func theStatementIsHonest() {
        #expect(SiteCopy.statementBody.contains("it does not plant"))
        #expect(SiteCopy.statementLeadIn == "No tree at this site.")
    }

    /// ARCHITECTURE §5.7: no spaces around em dashes.
    @Test("copy follows the em-dash rule")
    func emDashRule() {
        for line in SiteTests.allCopy() {
            #expect(!line.contains(" — "), "spaced em dash in: \(line)")
        }
        #expect(SiteCopy.statementBody.contains("—"))
    }

    // MARK: - Identity

    /// The address is the only thing that identifies a site, and it is the H1 — the profile's
    /// precedence collapses to its last rung, because a site has no species and D15's naming is
    /// something people do to trees.
    @Test("the address is the title and the record's kind sits under it")
    func identityLeadsWithTheAddress() {
        let subject = SitePresentation(profile: SiteTests.profile())

        #expect(subject.title == "666 Rhode Island St")
        #expect(subject.subtitle == "Vacant planting site · SF city inventory")
    }

    /// A site the city listed without an address falls back to the noun — and then the italic line
    /// must not repeat it, or the screen reads `Planting site` twice with a dot between.
    @Test("with no address the title becomes the noun and the line below it does not repeat it")
    func titleFallsBackWithoutRepeating() {
        let subject = SitePresentation(profile: SiteTests.profile(SiteTests.site(address: nil)))

        #expect(subject.title == SiteCopy.fallbackTitle)
        #expect(subject.subtitle == SiteCopy.provenance(.cityImport))
        #expect(!subject.subtitle.contains(SiteCopy.kind))
        #expect(!subject.subtitle.hasPrefix(" · "))
    }
}
