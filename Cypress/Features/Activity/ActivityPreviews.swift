//
//  ActivityPreviews.swift
//  Cypress — Features/Activity
//
//  Previews for screen 13, including the state every tree in the shipped app is actually in — an
//  empty record — because SCREENS.md does not draw it and it is the one most people will see.
//
//  `ActivityScreen` is fed a finished `ActivityPresentation` rather than an API, so a preview is the
//  state it says it is: a view whose content arrives from an `async` read renders as the loading
//  state in a detached window and photographs as one too.
//

#if DEBUG
import SwiftUI

// MARK: - Fixtures

enum ActivityPreviewFixtures {

    static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000013")!
    static let deviceID = UUID(uuidString: "9F3A0000-0000-4000-8000-0000000000DE")!

    /// The year the mock is drawn in, and the year every derived string below is relative to.
    static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 18))!

    static let tree = Tree(
        id: treeID,
        externalRef: "114-88",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.7601, longitude: -122.5054),
        address: "Great Highway at Judah",
        plantedYear: 1898,
        verificationState: .cityRecord
    )

    static let montereyCypress = try! Species(
        scientificName: "Hesperocyparis macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        curated: true
    )

    static func date(_ year: Int, _ month: Int, _ day: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func photo(_ year: Int, _ month: Int, _ day: Int = 12) -> Photo {
        Photo(treeID: treeID, shotType: .fullTree, capturedAt: date(year, month, day))
    }

    static func visit(_ year: Int, _ month: Int, _ day: Int = 12, tags: [PhenologyTag] = []) -> Visit {
        Visit(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            phenologyTags: tags,
            capturedAt: date(year, month, day)
        )
    }

    static func observation(_ year: Int, _ month: Int, _ day: Int = 12) -> TreeObservation {
        TreeObservation(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: date(year, month, day),
            status: .alive,
            vitality: .thriving
        )
    }

    static func care(_ year: Int, _ month: Int, _ day: Int = 12, _ actions: [CareAction] = [.watered]) -> CareEvent {
        CareEvent(
            treeID: treeID,
            attribution: .anonymous(deviceID: deviceID),
            capturedAt: date(year, month, day),
            actions: actions
        )
    }

    /// Spreads `count` rows across one month, so a bar has a real height behind it.
    static func spread<T>(_ counts: [Int], _ make: (Int, Int, Int) -> T) -> [T] {
        var rows: [T] = []
        for (index, count) in counts.enumerated() where count > 0 {
            for n in 0..<count {
                rows.append(make(2026, index + 1, 1 + (n % 27)))
            }
        }
        return rows
    }

    static func profile(
        photos: [Photo] = [],
        visits: [Visit] = [],
        observations: [TreeObservation] = [],
        careEvents: [CareEvent] = [],
        complete: Bool = true
    ) -> TreeProfile {
        TreeProfile(
            tree: tree,
            activeName: TreeName(treeID: treeID, name: "Grandmother Cypress", givenBy: nil),
            species: montereyCypress,
            latestObservation: observations.max { $0.capturedAt < $1.capturedAt },
            observations: Series(items: observations, isComplete: complete),
            photos: Series(items: photos, isComplete: complete),
            visits: Series(items: visits, isComplete: complete),
            careEvents: Series(items: careEvents, isComplete: complete),
            ownPhotoIDs: Set(photos.map(\.id))
        )
    }

    /// **SCREENS.md 13's own year**, rebuilt from records rather than from bar heights.
    ///
    /// The mock draws heights, not counts, and stated exactly one count in words — `June’s 12
    /// photos set the ceiling`, in the §5 footnote the copy audit of 2026-08-23 struck. **That is
    /// where the 12 below came from and the strike does not move it**: the bar heights the number
    /// described are still drawn, so the photo month distribution is still chosen to peak at 12 in
    /// June and to total the drawn `41`; check-ins total the drawn `18`; care totals the drawn `9`
    /// and is absent in the five months the mock stars. Recorded here because a fixture whose
    /// source has been struck from the spec is one nobody can re-derive later.
    static func drawnProfile() -> TreeProfile {
        // June is 11 here and 12 on the chart: the twelfth is the one taken *this* week, which the
        // strip below needs and which `spread` would otherwise place early in the month.
        let photoMonths = [2, 1, 3, 4, 5, 11, 5, 3, 2, 2, 1, 1]       // 41 with the one below
        let checkInMonths = [1, 1, 2, 2, 3, 2, 2, 1, 1, 1, 1, 1]      // 18
        let careMonths = [0, 0, 1, 2, 1, 1, 0, 2, 1, 1, 0, 0]         // 9, five empty months

        return profile(
            photos: spread(photoMonths) { photo($0, $1, $2) }
                + [photo(2019, 3, 14), photo(2024, 6, 17), photo(2025, 6, 16), photo(2026, 6, 18)],
            visits: [visit(2026, 4, 3, tags: [.leafOut])] + spread(checkInMonths) { visit($0, $1, $2) },
            observations: spread(checkInMonths) { observation($0, $1, $2) },
            careEvents: spread(careMonths) { care($0, $1, $2) }
                + [care(2026, 6, 3), care(2026, 7, 9), care(2026, 8, 2)]
        )
    }

    /// **The state every tree in the shipped seed is in.** No visits, no check-ins, no care, no
    /// photographs — the seed carries none of those tables at all.
    static func emptyProfile() -> TreeProfile { profile() }

    /// The record is there and the read was a page. Nothing renders: the shared scale cannot be
    /// founded on a page and neither can a total (ERRATA E38).
    static func pagedProfile() -> TreeProfile {
        let drawn = drawnProfile()
        return TreeProfile(
            tree: tree,
            activeName: drawn.activeName,
            species: montereyCypress,
            latestObservation: drawn.latestObservation,
            observations: Series(items: drawn.observations.items, isComplete: false),
            photos: Series(items: drawn.photos.items, isComplete: false),
            visits: Series(items: drawn.visits.items, isComplete: false),
            careEvents: Series(items: drawn.careEvents.items, isComplete: false),
            ownPhotoIDs: drawn.ownPhotoIDs
        )
    }

    /// One visit, one photograph, this month. A year with something in it and nothing to say about
    /// spans, headcounts or other years.
    static func sparseProfile() -> TreeProfile {
        profile(photos: [photo(2026, 6, 14)], visits: [visit(2026, 6, 14)])
    }

    static func presentation(_ profile: TreeProfile) -> ActivityPresentation {
        ActivityPresentation(profile: profile, now: now)
    }
}

// MARK: - Previews

/// The full state, and every block SCREENS.md 13 still specifies: the chart card, the moments and
/// the strip. 13 §5 put a footnote under them until the copy audit of 2026-08-23 removed it and
/// struck the section to match.
#Preview("13 · tree activity") {
    NavigationStack {
        ActivityScreen(
            presentation: ActivityPreviewFixtures.presentation(ActivityPreviewFixtures.drawnProfile())
        )
    }
}

/// **Empty.** Every tree in the shipped inventory, on launch day. **NOT SPECIFIED** by SCREENS.md;
/// see ERRATA.
#Preview("13 · empty") {
    NavigationStack {
        ActivityScreen(
            presentation: ActivityPreviewFixtures.presentation(ActivityPreviewFixtures.emptyProfile())
        )
    }
}

/// **A page.** The same rows as the full state, read as a page. The card, the moments and the strip
/// are all claims about a whole series, so none of them draws (ERRATA E38).
#Preview("13 · paged read") {
    NavigationStack {
        ActivityScreen(
            presentation: ActivityPreviewFixtures.presentation(ActivityPreviewFixtures.pagedProfile())
        )
    }
}

/// One photograph and one visit this month: a chart with a single bar in it, no moments, no strip.
#Preview("13 · one visit") {
    NavigationStack {
        ActivityScreen(
            presentation: ActivityPreviewFixtures.presentation(ActivityPreviewFixtures.sparseProfile())
        )
    }
}

/// Dark. SCREENS.md gives 13 no dark row, so this is evidence of what the token layer resolves the
/// screen to rather than a design. See ERRATA.
#Preview("13 · dark") {
    NavigationStack {
        ActivityScreen(
            presentation: ActivityPreviewFixtures.presentation(ActivityPreviewFixtures.drawnProfile())
        )
    }
    .preferredColorScheme(.dark)
}
#endif
