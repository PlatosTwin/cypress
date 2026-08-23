import Foundation
import Testing
@testable import Cypress

/// Screens 03 and 14, derived. Two live defects met here, and both of them rendered as a screen
/// that looked designed:
///
/// - **No photograph was visible anywhere in the app** (ERRATA E37). `visiblePhotos` required
///   `.approved`, nothing in the shipping app can set `.approved`, so there was no hero, no season
///   strip and no best photo on any tree — and because the visit still landed, `isCold` was false
///   and the cold-start copy did not render either.
/// - **A page of 30 was presented as the whole series** (ERRATA E38). The hero printed that page's
///   size and that page's earliest year: `30 photos · since 2024` for a tree with 214 photographs
///   going back to 2019.
@Suite("Tree profile presentation")
struct TreeProfilePresentationTests {

    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private static let now = date(2025, 10, 20)
    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-0000000000E1")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000E2")!

    private static let tree = Tree(
        id: treeID,
        externalRef: "13284",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.799005143246, longitude: -122.443869066799),
        address: "2576 Lombard St",
        status: .alive,
        plantedYear: 1993,
        verificationState: .cityRecord
    )

    /// 214 photos across 2019–2025, newest first, exactly as the store hands them back — and
    /// `.pending`, because that is the only state anything in the app can produce.
    private static let photos: [Photo] = {
        var dates: [Date] = []
        for year in 2019...2025 {
            for month in [1, 2, 3, 6, 7, 9, 10, 11, 12] {
                for day in [5, 12, 19, 26] {
                    let captured = date(year, month, day)
                    if captured <= now { dates.append(captured) }
                }
            }
        }
        return dates.sorted().suffix(214).reversed().map { captured in
            Photo(
                treeID: treeID,
                shotType: .fullTree,
                moderationState: .pending,
                width: 3024,
                height: 4032,
                capturedAt: captured
            )
        }
    }()

    private static func profile(
        photos: Series<Photo>,
        ownPhotoIDs: Set<UUID>,
        visits: Series<Visit> = .empty,
        careEvents: Series<CareEvent> = .empty
    ) -> TreeProfile {
        TreeProfile(
            tree: tree,
            photos: photos,
            visits: visits,
            careEvents: careEvents,
            ownPhotoIDs: ownPhotoIDs
        )
    }

    private static func presentation(_ profile: TreeProfile) -> TreeProfilePresentation {
        TreeProfilePresentation(profile: profile, now: now, calendar: calendar)
    }

    private static var ownEverything: Set<UUID> { Set(photos.map(\.id)) }

    // MARK: - E37: a photo is visible to the person who took it

    @Test("this device's own pending photos are visible on this device")
    func ownPendingPhotosAreVisible() {
        let subject = Self.presentation(
            Self.profile(photos: Series(complete: Self.photos), ownPhotoIDs: Self.ownEverything)
        )

        #expect(subject.visiblePhotos.items.count == 214)
        #expect(!subject.isCold, "a tree with 214 photographs is not a cold-start profile")
        #expect(subject.bestPhoto != nil)
        #expect(subject.heroEyebrow == "Best photo · Oct 2025")
        #expect(subject.showsFoliageStrip)
        #expect(subject.photographedMonths == Set([1, 2, 3, 6, 7, 9, 10, 11, 12]))
        #expect(subject.foliageDensities.filter { $0 == .full }.count == 9)
        #expect(subject.ctaTitle == "Visit · add a photo")

        // Nothing was quietly promoted to approved to make that happen.
        #expect(subject.visiblePhotos.items.allSatisfy { $0.moderationState == .pending })
    }

    @Test("moderation still gates the public surface, on exactly the same payload")
    func publicVisibilityIsUnchanged() {
        let subject = Self.presentation(
            Self.profile(photos: Series(complete: Self.photos), ownPhotoIDs: Self.ownEverything)
        )
        #expect(subject.publiclyVisiblePhotos.items.isEmpty, "a pending photo reached a public surface")
        #expect(subject.publiclyVisiblePhotos.isComplete)
    }

    @Test("somebody else's pending photo is not visible; their approved one is")
    func otherContributorsPhotosStayGated() {
        let theirs = Photo(
            treeID: Self.treeID,
            shotType: .fullTree,
            moderationState: .pending,
            capturedAt: Self.date(2025, 9, 1)
        )
        let approved = Photo(
            treeID: Self.treeID,
            shotType: .fullTree,
            moderationState: .approved,
            capturedAt: Self.date(2025, 9, 2)
        )

        let subject = Self.presentation(
            Self.profile(photos: Series(complete: [approved, theirs]), ownPhotoIDs: [])
        )
        #expect(subject.visiblePhotos.items.map(\.id) == [approved.id])
    }

    @Test("a deleted photo of one's own is still deleted")
    func deletionOutranksOwnership() {
        let removed = Photo(
            treeID: Self.treeID,
            shotType: .fullTree,
            moderationState: .pending,
            capturedAt: Self.date(2025, 9, 1),
            deletedAt: Self.date(2025, 9, 3)
        )
        let subject = Self.presentation(
            Self.profile(photos: Series(complete: [removed]), ownPhotoIDs: [removed.id])
        )
        #expect(subject.visiblePhotos.items.isEmpty)
        #expect(subject.isCold)
    }

    @Test("a tree with no photograph and no visit still reads as cold-start")
    func coldStartStillRenders() {
        let subject = Self.presentation(Self.profile(photos: .empty, ownPhotoIDs: []))
        #expect(subject.isCold)
        #expect(subject.heroMetaPill == nil)
        #expect(subject.ctaTitle == "Add the first photo of this tree")
        #expect(!subject.showsFoliageStrip)
    }

    @Test("the best photo breaks its tie on resolution, which needs width and height stored")
    func bestPhotoTieBreak() {
        let sameMoment = Self.date(2025, 10, 12)
        let small = Photo(
            treeID: Self.treeID, shotType: .fullTree, moderationState: .pending,
            width: 800, height: 600, capturedAt: sameMoment
        )
        let large = Photo(
            treeID: Self.treeID, shotType: .fullTree, moderationState: .pending,
            width: 3024, height: 4032, capturedAt: sameMoment
        )
        let leaf = Photo(
            treeID: Self.treeID, shotType: .leaf, moderationState: .pending,
            width: 4032, height: 4032, capturedAt: sameMoment
        )

        let subject = Self.presentation(
            Self.profile(
                photos: Series(complete: [small, large, leaf]),
                ownPhotoIDs: [small.id, large.id, leaf.id]
            )
        )
        #expect(subject.bestPhoto?.id == large.id, "A3's resolution tie-break did not run")
        #expect(large.resolution > small.resolution)
        // A3 is a full-tree rule; the sharpest leaf close-up is still not the tree's best photo.
        #expect(subject.bestPhoto?.shotType == .fullTree)
    }

    // MARK: - E38: a page is not a total

    @Test("the whole series prints the whole series' numbers")
    func heroPillOverACompleteSeries() {
        let subject = Self.presentation(
            Self.profile(photos: Series(complete: Self.photos), ownPhotoIDs: Self.ownEverything)
        )
        #expect(subject.heroMetaPill == "214 photos · since 2019")
    }

    @Test("a page prints no numbers at all rather than the page's own")
    func heroPillOverAPage() {
        // Exactly what `LIMIT 30 ORDER BY captured_at DESC` used to hand the profile.
        let page = Series(items: Array(Self.photos.prefix(30)), isComplete: false)
        let subject = Self.presentation(Self.profile(photos: page, ownPhotoIDs: Self.ownEverything))

        #expect(subject.visiblePhotos.items.count == 30)
        #expect(subject.visiblePhotos.totalCount == nil)
        #expect(subject.heroMetaPill == nil, "a page's size was rendered as the tree's photo count")

        // The string that used to be printed, spelled out here so the regression is legible.
        let earliestOnThePage = page.items.map(\.capturedAt).min() ?? Self.now
        let yearOnThePage = Self.calendar.component(.year, from: earliestOnThePage)
        #expect(subject.heroMetaPill != "30 photos · since \(yearOnThePage)")
        #expect(yearOnThePage == 2024, "the fixture no longer reproduces the wrong year it was built for")

        // A5's strip is computed over the same rows, so it under-fills over a page — and a thin
        // cell is a claim that no photograph exists for that month.
        #expect(!subject.showsFoliageStrip)
    }

    @Test("one photo is one photo, not one photos")
    func heroPillIsSingular() {
        let one = Self.photos.prefix(1)
        let subject = Self.presentation(
            Self.profile(photos: Series(complete: Array(one)), ownPhotoIDs: Set(one.map(\.id)))
        )
        #expect(subject.heroMetaPill == "1 photo · since 2025")
    }

    @Test("A8 counts caretakers over the whole series or does not count them at all")
    func caretakersNeedTheWholeSeries() {
        let people = [
            UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
        ]
        // Two care events each, all inside A8's 24-month window: the threshold, exactly met.
        var events: [CareEvent] = []
        for (index, person) in people.enumerated() {
            for offset in 0...1 {
                events.append(
                    CareEvent(
                        treeID: Self.treeID,
                        attribution: Attribution(userID: person, deviceID: Self.deviceID),
                        capturedAt: Self.date(2025, 3 + index + offset * 3, 4),
                        actions: [.watered]
                    )
                )
            }
        }
        let sorted = events.sorted { $0.capturedAt > $1.capturedAt }

        let whole = Self.presentation(
            Self.profile(photos: .empty, ownPhotoIDs: [], careEvents: Series(complete: sorted))
        )
        #expect(whole.caretakers?.count == 3)
        #expect(whole.caretakerHeadline == "Three people know this tree")

        // The same rows as a page. The page happens to hold all of them, and it still may not be
        // counted: what a page cannot tell you is what is *not* in it.
        let page = Self.presentation(
            Self.profile(photos: .empty, ownPhotoIDs: [], careEvents: Series(items: sorted, isComplete: false))
        )
        #expect(page.caretakers == nil)
        #expect(page.caretakerHeadline == nil)
    }

    @Test("filtering a series keeps its completeness, and so does sorting it")
    func seriesFilteringPreservesCompleteness() {
        let complete = Series(complete: Self.photos)
        #expect(complete.filter { $0.shotType == .fullTree }.isComplete)
        #expect(complete.filter { _ in false }.totalCount == 0)

        let page = Series(items: Array(Self.photos.prefix(30)), isComplete: false)
        #expect(!page.filter { _ in true }.isComplete)
        #expect(page.filter { _ in true }.totalCount == nil)
        #expect(page.sorted { $0.capturedAt < $1.capturedAt }.totalCount == nil)
    }
}
