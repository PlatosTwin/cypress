import Foundation
import Testing
@testable import Cypress

/// Screen 10, derived.
///
/// This is the one screen in the app that produces something public, so what is pinned here is the
/// boundary rather than the layout: which photos may cross it, what identifies the tree on the other
/// side of it, and what is *not* on the card at all.
///
/// The predicate is the thing most likely to be "fixed" by somebody who opens the app, sees a
/// gradient where the mock draws a gradient, and reaches for `isVisibleToItsContributor` because it
/// is the one screen 03 uses and it makes the card look busier (ERRATA E37, E59).
@Suite("Share presentation")
struct SharePresentationTests {

    // MARK: - Fixtures

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000A0")!

    private static let montereyCypress = try! Species(
        scientificName: "Hesperocyparis macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        curated: true
    )

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func photo(month: Int, _ moderation: ModerationState) -> Photo {
        Photo(
            treeID: treeID,
            shotType: .fullTree,
            moderationState: moderation,
            capturedAt: calendar.date(
                from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2025, month: month, day: 12)
            )!
        )
    }

    private static func presentation(
        name: String? = "Grandmother Cypress",
        address: String? = "Great Highway at Judah",
        // Defaulted rather than left nil so every test unrelated to the location line keeps
        // exercising a tree whose city IS known — the ordinary case (ERRATA E209/#233).
        // `locationLineTests` below is what exercises the honest-fallback branches explicitly.
        cityShortName: String? = "San Francisco",
        species: Species? = montereyCypress,
        photos: [Photo] = [],
        ownPhotoIDs: Set<UUID>? = nil
    ) -> SharePresentation {
        let tree = Tree(
            id: treeID,
            externalRef: "13284",
            source: .cityImport,
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
            address: address,
            verificationState: .cityRecord
        )
        return SharePresentation(
            profile: TreeProfile(
                tree: tree,
                activeName: name.map { TreeName(treeID: treeID, name: $0, givenBy: nil) },
                species: species,
                cityShortName: cityShortName,
                photos: Series(complete: photos),
                // The default is "this device took all of them", which is the state `LocalAPI` is
                // always in — and the state under which the wrong predicate would look right.
                ownPhotoIDs: ownPhotoIDs ?? Set(photos.map(\.id))
            ),
            calendar: calendar
        )
    }

    // MARK: - The public predicate

    @Test("a share card takes the public predicate, so a pending photo never reaches it")
    func pendingPhotosAreNotPublic() {
        let page = Self.presentation(photos: (1...12).map { Self.photo(month: $0, .pending) })

        // Twelve photographs on the timeline; none of them public.
        #expect(page.profile.photos.items.count == 12)
        #expect(page.publiclyVisiblePhotos.items.isEmpty)
        #expect(page.bestPublicPhoto == nil)
        #expect(page.publiclyPhotographedMonths.isEmpty)
        // And therefore twelve thin cells: the strip claims no public photograph in any month.
        #expect(page.foliageDensities == Array(repeating: FoliageStrip.Density.thin, count: 12))
    }

    @Test("the same photos on the contributor's own screen are visible, which is the whole point")
    func theTwoPredicatesDisagree() {
        let photos = (1...12).map { Self.photo(month: $0, .pending) }
        let profile = TreeProfile(
            tree: Tree(
                id: Self.treeID,
                source: .cityImport,
                coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
                verificationState: .cityRecord
            ),
            species: Self.montereyCypress,
            photos: Series(complete: photos),
            ownPhotoIDs: Set(photos.map(\.id))
        )

        // Screen 03 — the device that took them.
        #expect(TreeProfilePresentation(profile: profile).visiblePhotos.items.count == 12)
        // Screen 10 — a public surface.
        #expect(SharePresentation(profile: profile, calendar: Self.calendar)
            .publiclyVisiblePhotos.items.isEmpty)
        // If these two ever agree on a `.pending` photo, one of them is wrong.
    }

    @Test("an approved photo does reach the card, so the gate is a gate and not a wall")
    func approvedPhotosArePublic() {
        let page = Self.presentation(
            photos: [Self.photo(month: 3, .approved), Self.photo(month: 9, .approved)]
        )

        #expect(page.publiclyVisiblePhotos.items.count == 2)
        #expect(page.publiclyPhotographedMonths == [3, 9])
        #expect(page.foliageDensities[2] == .full)
        #expect(page.foliageDensities[8] == .full)
        #expect(page.foliageDensities[0] == .thin)
        #expect(page.bestPublicPhoto?.capturedAt == page.publiclyVisiblePhotos.items.map(\.capturedAt).max())
    }

    @Test("a rejected or deleted photo is not public either")
    func rejectedAndDeletedAreNotPublic() {
        var deleted = Self.photo(month: 5, .approved)
        deleted.deletedAt = Date()
        let page = Self.presentation(photos: [Self.photo(month: 4, .rejected), deleted])

        #expect(page.publiclyVisiblePhotos.items.isEmpty)
        #expect(page.bestPublicPhoto == nil)
    }

    @Test("the best public photo is chosen with the public candidate rule, not the framing one")
    func bestPhotoUsesThePublicCandidateRule() {
        // A newer pending full-tree shot must not beat an older approved one: `isBestPhotoShot`
        // would pick it, and it would be published without review.
        let approved = Self.photo(month: 2, .approved)
        let newerPending = Self.photo(month: 11, .pending)
        let page = Self.presentation(photos: [approved, newerPending])

        #expect(page.bestPublicPhoto?.id == approved.id)
        #expect(newerPending.isBestPhotoShot)
        #expect(newerPending.isPublicBestPhotoCandidate == false)
    }

    // MARK: - What identifies the tree publicly

    @Test("the public link is the tree's own stable UUID, not the mock's four-hex slug")
    func publicLinkNamesTheTree() {
        let page = Self.presentation()

        #expect(page.publicURL.absoluteString == "https://cypress.app/sf/tree/" + Self.treeID.uuidString.lowercased())
        #expect(page.publicURLText == "cypress.app/sf/tree/" + Self.treeID.uuidString.lowercased())
        // Four hex digits are 65,536 values and the seed holds 195,309 trees, so the mock's slug
        // cannot name one of them. See ERRATA (E60).
        #expect(page.publicURLText.hasSuffix("9f3a") == false)
    }

    @Test("the card names the tree the same way every other surface does")
    func displayNameFollowsTheProfileRule() {
        #expect(Self.presentation().treeDisplayName == "Grandmother Cypress")
        #expect(Self.presentation(name: nil).treeDisplayName == "Monterey Cypress")
        #expect(Self.presentation(name: nil, species: nil).treeDisplayName == "Great Highway at Judah")
    }

    @Test("the location line is the tree's address, never a person's")
    func locationLineIsTheTree() {
        #expect(Self.presentation().locationLine == "Great Highway at Judah · San Francisco")
        #expect(Self.presentation(address: nil).locationLine == "San Francisco")
        #expect(Self.presentation(address: "").locationLine == "San Francisco")
    }

    /// **ERRATA E209/#233, Shape A's one surviving member.** Until this fix `ShareCopy.city` was
    /// the literal `"San Francisco"`, true only while the seed held one city; a San Jose tree
    /// shared from screen 10 was captioned with the wrong city on every single share. The city
    /// half is no longer a constant — it is `profile.cityShortName`, so a tree whose row says
    /// San Jose gets San Jose.
    @Test("a San Jose tree's card names San Jose, not the old San Francisco constant")
    func aSanJoseTreeIsNotCaptionedSanFrancisco() {
        let page = Self.presentation(cityShortName: "San Jose")
        #expect(page.locationLine == "Great Highway at Judah · San Jose")
        #expect(page.locationLine.contains("San Francisco") == false)
    }

    /// **The honest fallback, both directions.** A city that is not known — an older seed with no
    /// `id_spaces.short_name` (`SeedSchema.hasCivicShortNames` false), a row that predates
    /// `id_space` entirely, or a community-added tree, which never has one — must not fall back to
    /// a fabricated or stale city name. R37.3 makes "not known yet" ordinary rather than an error:
    /// the bundled seed and a downloaded city file are legitimately different generations at once.
    @Test("with no known city, the line falls back to the address alone — never a guessed city")
    func noKnownCityFallsBackToAddressAlone() {
        let page = Self.presentation(cityShortName: nil)
        #expect(page.locationLine == "Great Highway at Judah")
        #expect(page.locationLine.contains("San Francisco") == false)
        #expect(page.locationLine.contains("·") == false, "a dangling separator with nothing after it")
    }

    /// The mirror of the existing "no address" fallback: with an address but no known city, the
    /// city clause simply does not appear — the same "no dangling separator" rule that already
    /// held for a missing address, now proved for a missing city too.
    @Test("with no known city and no address, the line says nothing rather than inventing something")
    func neitherAddressNorCityIsAnEmptyLine() {
        let page = Self.presentation(address: nil, cityShortName: nil)
        #expect(page.locationLine == "")
    }

    /// The city-known, address-known case is exercised by `locationLineIsTheTree`; this covers the
    /// remaining cell of the 2×2 the fallback logic actually branches on — a known city and NO
    /// address, which must still read as "city alone", not "· city" or the empty line.
    @Test("a known city with no address reads as the city alone")
    func knownCityNoAddressIsCityAlone() {
        #expect(Self.presentation(address: nil, cityShortName: "San Jose").locationLine == "San Jose")
        #expect(Self.presentation(address: "", cityShortName: "San Jose").locationLine == "San Jose")
    }

    /// ERRATA E42: `publicCoordinate` is deliberately unpopulated, and screen 10 is named as the
    /// place it would be re-opened. It is not re-opened. Nothing this screen renders is derived from
    /// a photo's location, and the snap stays unconditional in `Photo.init` for the day one exists.
    @Test("no photo coordinate is minted, read, or rendered by the share card")
    func noPhotoLocationLeaks() {
        let photos = (1...12).map { Self.photo(month: $0, .approved) }
        #expect(photos.allSatisfy { $0.publicCoordinate == nil })

        let page = Self.presentation(photos: photos)
        #expect(page.publiclyVisiblePhotos.items.allSatisfy { $0.publicCoordinate == nil })
        // Everything the card prints, and no coordinate in any of it.
        let rendered = [page.treeDisplayName, page.locationLine, page.publicURLText, page.accessibilityLabel]
        for text in rendered {
            #expect(text.contains("37.7") == false)
            #expect(text.contains("122.5") == false)
        }

        // And when a coordinate *is* supplied, `Photo.init` snaps it unconditionally — the 25 m grid
        // is not something a caller can forget (DECISIONS §3.10).
        let exact = Coordinate(latitude: 37.760123, longitude: -122.505456)
        let located = Photo(treeID: Self.treeID, shotType: .fullTree, capturedAt: Date(), publicCoordinate: exact)
        #expect(located.publicCoordinate == exact.snappedToPublicPhotoGrid())
        #expect(located.publicCoordinate != exact)
    }

    // MARK: - D11 · there is no attribution on this screen to gate

    /// D11 forces anonymous public attribution for under-18 accounts regardless of the stored
    /// preference, and `User.isPublicAttributionEffective` is the only predicate allowed to answer
    /// it. SCREENS.md 10 enumerates the sheet's contents and none of them is a person — so the
    /// compliance available here is that there is no call site. This test is what makes adding one
    /// without the predicate a failing change rather than a silent one.
    @Test("nothing the share sheet renders carries a contributor's identity")
    func noAttributionSurface() {
        let page = Self.presentation(photos: (1...12).map { Self.photo(month: $0, .approved) })
        let rendered = [page.treeDisplayName, page.locationLine, page.publicURLText, page.accessibilityLabel]
            .joined(separator: " ")
            .lowercased()

        for forbidden in ["shared by", "visitor", "steward", "member", "photo by", "@"] {
            #expect(rendered.contains(forbidden) == false, "the share card rendered '\(forbidden)'")
        }
    }

    @Test("the predicate D11 requires still says what it must, for whoever adds the first name here")
    func underEighteenIsAlwaysAnonymous() {
        let optedIn = User(email: "a@b.c", displayName: "N", birthYearBucket: .over18, publicAttribution: true)
        let minorOptedIn = User(email: "a@b.c", displayName: "N", birthYearBucket: .under18, publicAttribution: true)
        let unknownAge = User(email: "a@b.c", displayName: "N", birthYearBucket: .unknown, publicAttribution: true)

        #expect(optedIn.isPublicAttributionEffective)
        #expect(minorOptedIn.isPublicAttributionEffective == false)
        #expect(unknownAge.isPublicAttributionEffective)
        #expect(User(email: "a@b.c", displayName: "N").isPublicAttributionEffective == false)
    }

    // MARK: - Copy

    @Test("no destination promises something the app does not do")
    func destinationsAreHonest() {
        // Three, not the mock's four (ticket #146): Instagram had no API to be a button with, and
        // AirDrop could only ever open a general sheet, which is what `Share…` now says it does.
        // The exact ledger, in row order — a fourth button, a relabel, or a resurrected Instagram
        // all fail here by name.
        #expect(ShareDestination.allCases.map(\.label) == ["Messages", "Copy link", "Share…"])
        #expect(ShareDestination.copyLink.isPasteboard)
        #expect(ShareDestination.allCases.filter(\.isPasteboard).count == 1)
        // The title carries no tree name: SCREENS.md 10 §2 replaced the prototype's
        // `Share {{ treeName }}` with a fixed title and put the name on the card.
        #expect(ShareCopy.title == "Share this tree")
    }

    /// Ticket #146's owner requirement: the Messages button goes to Messages composition, not to
    /// the sheet AirDrop opens. The composer only exists where `canSendText()` is true — false on
    /// every simulator — so the decision is a pure function the suite can hold on both sides,
    /// which is what keeps the device behavior asserted from a machine that cannot exhibit it.
    @Test("the Messages button composes where it can and falls back where it cannot")
    func messagesRoute() {
        #expect(MessagesRoute(canSendText: true) == .composer)
        #expect(MessagesRoute(canSendText: false) == .systemShareSheet)
    }

    @Test("each destination's hint says what tapping it does, and no two claim the same thing")
    func destinationHints() {
        #expect(ShareDestination.messages.accessibilityHint == "Opens a new message with the link")
        #expect(ShareDestination.copyLink.accessibilityHint == "Copies the public link")
        #expect(ShareDestination.system.accessibilityHint == "Opens the system share sheet")
        #expect(Set(ShareDestination.allCases.map(\.accessibilityHint)).count == ShareDestination.allCases.count)
    }
}
