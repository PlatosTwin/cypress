//
//  PhenologyOnProfileTests.swift
//  Cypress — CypressTests
//
//  TestFlight feedback on build 18, pulled 2026-08-07: a tester circled screen 04's whole tray —
//  the note field, the observed-state chips and `Log visit` — and asked
//  "Where do leaf out full leaf flowering etc go?"
//
//  The honest answer was: nowhere. `visits.phenology_tags` was written, stored and read back into
//  `Visit.phenologyTags`, and then the only surface that could have shown it — screen 03's activity
//  feed — built its `Visit` row's detail out of the note alone. A contributor who tapped
//  `Flowering` and logged the visit got a row reading `Visit`, with the observation they had just
//  made nowhere on the tree's page.
//
//  The fix is the mock's own pattern, not a new one. SCREENS 03 §8 draws two C9 rows:
//  `Visit · “Fog dripping off the crown”` and `Care · watered, mulched`. The second is a C9 detail
//  slot carrying a contribution's structured vocabulary as a comma-joined prose list — which is
//  exactly what an observed-state list is. See `TreeProfilePresentation.visitDetail(note:
//  phenologyTags:)`.
//
//  Two things this file guards that are easy to lose:
//
//  - **The words.** DECISIONS constraint 15 forbids the app inventing botanical content, so the
//    prose here is `PhenologyTagLabel`'s chip copy lowercased — the words the contributor tapped —
//    and the six of them are pinned below by value. A seventh state, a rename or a reorder fails
//    here before it reaches a screen.
//  - **The drawn row.** A visit with a note and no tags must still render byte-for-byte what the
//    mock draws.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("Phenology observations reach the tree profile (build 18 feedback)")
struct PhenologyOnProfileTests {

    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private static let now = date(2026, 8, 7)
    private static let treeID = UUID(uuidString: "7E000000-0000-4000-8000-0000000000F1")!
    private static let deviceID = UUID(uuidString: "D0000000-0000-4000-8000-0000000000F2")!
    private static var attribution: Attribution { Attribution(userID: nil, deviceID: deviceID) }

    private static let tree = Tree(
        id: treeID,
        externalRef: "222615",
        source: .cityImport,
        coordinate: Coordinate(latitude: 37.766, longitude: -122.448),
        address: "34 Carl St",
        status: .alive,
        verificationState: .cityRecord
    )

    private static func visit(
        note: String? = nil,
        tags: [PhenologyTag] = [],
        on day: Date = date(2026, 7, 12)
    ) -> Visit {
        Visit(
            treeID: treeID,
            attribution: attribution,
            note: note,
            phenologyTags: tags,
            capturedAt: day
        )
    }

    private static func presentation(
        visits: [Visit] = [],
        careEvents: [CareEvent] = []
    ) -> TreeProfilePresentation {
        TreeProfilePresentation(
            profile: TreeProfile(
                tree: tree,
                visits: Series(complete: visits),
                careEvents: Series(complete: careEvents)
            ),
            now: now,
            calendar: calendar
        )
    }

    // MARK: - The report: the tester's own visit, end to end

    /// The exact shape of the feedback — a tag, no note — through the presentation the profile
    /// renders. Before this change the row's detail was the empty string.
    @Test("a visit tagged and left unwritten still says what was observed")
    func taggedVisitWithNoNoteReachesTheFeed() {
        let subject = Self.presentation(visits: [Self.visit(tags: [.flowering])])
        let row = subject.activity.first

        #expect(row?.kind == .visit)
        #expect(row?.label == "Visit")
        #expect(
            row?.detail == " · flowering",
            "the observation the contributor recorded is not on the tree's page: \(row?.detail ?? "<no row>")"
        )
    }

    /// Every state the vocabulary holds survives the round trip from tap to profile row. Six
    /// assertions rather than one, because a lookup that is right for `flowering` and wrong for
    /// `fallColor` is the defect this class of change actually produces.
    @Test("every observed state the app can record reads back on the profile")
    func everyTagReachesTheFeed() {
        for tag in PhenologyTag.allCases {
            let subject = Self.presentation(visits: [Self.visit(tags: [tag])])
            #expect(
                subject.activity.first?.detail == " · " + PhenologyTagLabel.text(for: tag).lowercased(),
                "\(tag.rawValue) does not reach the profile"
            )
        }
    }

    // MARK: - Composition

    /// Both clauses present, observation first — the position `Care · watered, mulched` puts its own
    /// vocabulary in, and the position that keeps the unbounded free text last so a wrap lands
    /// inside the note rather than orphaning a separator. See `visitDetail(note:phenologyTags:)`.
    @Test("note and observation both appear, observation first, each after its own separator")
    func noteAndTagsCompose() {
        let subject = Self.presentation(
            visits: [Self.visit(note: "Fog dripping off the crown", tags: [.flowering])]
        )
        #expect(subject.activity.first?.detail == " · flowering · “Fog dripping off the crown”")
    }

    /// The row SCREENS 03 §8 actually draws. It must not have moved.
    @Test("a visit with a note and no observation renders exactly what the mock draws")
    func theDrawnRowIsUnchanged() {
        let subject = Self.presentation(visits: [Self.visit(note: "Fog dripping off the crown")])
        #expect(subject.activity.first?.detail == " · “Fog dripping off the crown”")
    }

    @Test("a visit with neither carries no separator at all")
    func bareVisitHasNoDetail() {
        #expect(Self.presentation(visits: [Self.visit()]).activity.first?.detail == "")
    }

    /// The chip row is tapped in whatever order the contributor's eye moved; the profile reads as a
    /// year regardless. `VisitPhenologyVocabulary.order` is the app's existing seasonal order — the
    /// same one screen 04 lays the chips out in — so this introduces no second ordering.
    @Test("observations read in seasonal order however they were tapped")
    func tagsRenderInSeasonalOrder() {
        let tappedBackwards = Self.presentation(
            visits: [Self.visit(tags: [.bare, .fruiting, .leafOut])]
        )
        #expect(tappedBackwards.activity.first?.detail == " · leaf out, fruiting, bare")

        let tappedForwards = Self.presentation(
            visits: [Self.visit(tags: [.leafOut, .fruiting, .bare])]
        )
        #expect(
            tappedForwards.activity.first?.detail == tappedBackwards.activity.first?.detail,
            "the row's reading order depends on tap order"
        )
    }

    // MARK: - What must not regress

    /// The other row on the same feed, whose pattern this borrows. Nothing about it changed, and a
    /// care event has no phenology to gain one.
    @Test("the care row is untouched")
    func careRowIsUnchanged() {
        let event = CareEvent(
            treeID: Self.treeID,
            attribution: Self.attribution,
            capturedAt: Self.date(2026, 6, 28),
            actions: [.watered, .mulched]
        )
        let row = Self.presentation(careEvents: [event]).activity.first
        #expect(row?.kind == .care)
        #expect(row?.label == "Care")
        #expect(row?.detail == " · watered, mulched")
    }

    /// A visit is still a visit for the purpose of the feed's other rules — it sorts by its own
    /// date and it opens the door to screen 13 — whether or not it carries an observation.
    @Test("an observation does not change what the feed does with the row")
    func feedMechanicsUnchanged() {
        let older = Self.visit(tags: [.leafOut], on: Self.date(2026, 4, 3))
        let newer = Self.visit(note: "Still going", on: Self.date(2026, 7, 12))
        let subject = Self.presentation(visits: [older, newer])

        #expect(subject.activity.map(\.id) == [newer.id, older.id], "the feed stopped sorting by date")
        #expect(subject.offersActivityLink)
    }
}

// MARK: - The vocabulary itself

/// DECISIONS constraint 15, pinned by value: the app may print the observed states it records and
/// no others, spelled the way the chip that recorded them is spelled.
///
/// This is deliberately a table of literals rather than a loop over `PhenologyTagLabel`. A loop
/// would agree with any rename, which is the thing that must not pass quietly — a stage renamed on
/// screen 04 is a stage renamed in the record, and that is a decision, not a refactor.
@Suite("The observed-state vocabulary is fixed (DECISIONS constraint 15)")
struct PhenologyStageVocabularyTests {

    @Test("the six states, their raw values, and the prose the profile prints for each")
    func theSixStates() {
        let expected: [(PhenologyTag, String, String)] = [
            (.leafOut, "leaf_out", "leaf out"),
            (.fullLeaf, "full_leaf", "full leaf"),
            (.flowering, "flowering", "flowering"),
            (.fruiting, "fruiting", "fruiting"),
            (.fallColor, "fall_color", "fall color"),
            (.bare, "bare", "bare"),
        ]

        #expect(
            Set(PhenologyTag.allCases) == Set(expected.map(\.0)),
            "the vocabulary gained or lost a state — that is a product decision, not a code change"
        )
        #expect(
            VisitPhenologyVocabulary.order == expected.map(\.0),
            "the seasonal order the chip row and the profile row share has changed"
        )

        for (tag, rawValue, prose) in expected {
            #expect(tag.rawValue == rawValue, "\(tag) no longer stores as \(rawValue)")
            #expect(TreeProfilePresentation.phenologyTagLabel(tag) == prose)
            // The words on the profile are the words on the chip, differing only in case.
            #expect(PhenologyTagLabel.text(for: tag).lowercased() == prose)
        }
    }
}

// MARK: - Photographed

#if DEBUG
/// Screen 03 with the row this change adds, in four appearances.
///
/// A string assertion says the words are there; it cannot say that a note and an observation on one
/// C9 row still read as one line rather than as a run-on, or that the pair survives AX5 in a row
/// whose body has no line limit. That is the part of this only a person looking can settle, and this
/// is how every other state on 03 gets looked at.
///
/// The tags are ones a Monterey Cypress can carry: it is `.evergreen`, so D5's exclusion means the
/// write path would strip `fallColor` and `bare` from this very fixture
/// (`PhenologyTag.validated(_:for:)`), and photographing a row the app cannot produce would be
/// photographing nothing.
@MainActor
@Suite("Observations on the tree profile · photographed")
struct PhenologyOnProfileShots {

    /// `TreeProfileSeedFixtures.populated`, with observations added to the two visits it already
    /// holds — one beside a note, one on its own, which are the two compositions.
    private static var withObservations: TreeProfile {
        let base = TreeProfileSeedFixtures.populated
        var visits = base.visits.items
        visits[0].phenologyTags = [.flowering]
        visits[1].note = nil
        visits[1].phenologyTags = [.leafOut, .fruiting]

        return TreeProfile(
            tree: base.tree,
            activeName: base.activeName,
            species: base.species,
            neighborhoodName: base.neighborhoodName,
            latestObservation: base.latestObservation,
            photos: base.photos,
            measurements: base.measurements,
            visits: Series(complete: visits),
            careEvents: base.careEvents,
            ownPhotoIDs: base.ownPhotoIDs
        )
    }

    @Test("03's activity feed carrying an observation beside a note, and one on its own")
    func photograph() async {
        print("SHOT DIR \(ScreenSweepShots.outputDirectory.path)")

        // The feed sits below every other section on 03, so at AX5 a phone-height window
        // photographs the hero and the name and never reaches the rows this is about — the same
        // reason `11-growth-history` and `02b-add-tree` ask for the tall viewport.
        #expect(await ScreenSweepShots.sweep(
            "phen-03-profile-observations",
            ax5ViewportHeight: ScreenSweepShots.tallestViewport
        ) {
            NavigationStack {
                TreeProfileView(
                    treeID: Self.withObservations.tree.id,
                    api: TreeProfilePreviewAPI(profile: Self.withObservations)
                )
            }
            .environment(AppRouter())
        })
    }
}
#endif
