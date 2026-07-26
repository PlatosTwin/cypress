//
//  GroveJournalShots.swift
//  CypressTests
//
//  The two personal lists, photographed beside each other.
//
//  ── Why this suite exists ─────────────────────────────────────────────────────────────────
//  The project owner, using the app: *"What's the diff between Trees and Journal? They look almost
//  identical."* That is a complaint about a picture, so the only thing that can answer it is a
//  picture — and specifically a picture of the two surfaces **in one image, with the same data
//  behind them**. `ScreenSweepShots` photographs each screen alone, which is exactly the framing in
//  which two screens that look alike look fine.
//
//  ── The fixture is the whole argument ─────────────────────────────────────────────────────
//  The two lists are only confusable while every tree has one record against it. `GroveTreesShotData`
//  is deliberately not that: one tree carries six contributions, one carries two, and one is a
//  favourite nobody has visited. So `Trees` draws three rows and `Journal` draws eight over the same
//  history, which is the difference the drawing has to make visible. A fixture of five trees with one
//  event each would have photographed the two screens agreeing, which proves nothing.
//
//  It asserts what the sweep it borrows asserts, and for the reason given there: that each capture
//  produced pixels. The images are the output.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("My Grove · Trees and the Journal, side by side")
struct GroveJournalShots {

    /// Tall enough to hold every row of both lists at the drawn size, and short enough that a
    /// **two-by-two sheet of it** stays inside the renderer's ceiling.
    ///
    /// That second clause is the load-bearing one and it cost a crash to learn. The images are fine
    /// at any of these heights; the *sheet* is `rows × (cell + caption)` tall, so a 2,400 pt cell in
    /// three rows asks `UIGraphicsImageRenderer` for a 21,930 px canvas — far past the ~8,192 px
    /// above which `drawHierarchy` stops producing pixels (ERRATA E145) and, at this size, past what
    /// the process survives at all. 1,200 pt in two rows is 7,428 px, which is inside it.
    static let viewport: CGFloat = 1_200

    @Test("the two personal lists, over one history, in one image")
    func theTwoListsTogether() async {
        print("SWEEP DIR \(ScreenSweepShots.outputDirectory.path)")

        var drawn: [(label: String, image: UIImage)] = []
        var accessible: [(label: String, image: UIImage)] = []

        for variant in ScreenSweepShots.variants {
            let trees = await ScreenSweepShots.capture(
                "j01-grove-trees-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                viewportHeight: Self.viewport
            ) { GroveJournalShotFixtures.treesTab }

            let journal = await ScreenSweepShots.capture(
                "j02-journal-yours-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                viewportHeight: Self.viewport
            ) { GroveJournalShotFixtures.journalTab }

            #expect(trees != nil, "the Trees pill photographed as a blank image")
            #expect(journal != nil, "the journal photographed as a blank image")

            // Two columns, so every row of a sheet is one appearance of both screens: the comparison
            // the complaint is about is a glance rather than two file-opens. Split in two, because
            // four rows of this cell height is a canvas the renderer will not draw.
            let isAccessibilitySize = variant.size >= .accessibility1
            if let trees {
                let row = ("TREES · \(variant.suffix)", trees)
                if isAccessibilitySize { accessible.append(row) } else { drawn.append(row) }
            }
            if let journal {
                let row = ("JOURNAL · \(variant.suffix)", journal)
                if isAccessibilitySize { accessible.append(row) } else { drawn.append(row) }
            }
        }

        ScreenSweepShots.contactSheet("j00-trees-vs-journal", drawn)
        ScreenSweepShots.contactSheet("j00b-trees-vs-journal-ax5", accessible)
    }
}

// MARK: - The history both screens are drawn from

/// One contribution history, handed to both surfaces.
///
/// The point of the fixture is the shape rather than the volume: **one tree with six records against
/// it**, which is the case where a set of trees and a stream of acts cannot be the same list. Grove
/// order is the store's (`last_visited DESC NULLS LAST`) and journal order is the store's
/// (`captured_at DESC`), so both are written here in the order their query would return them.
enum GroveJournalShotFixtures {

    /// Not `@MainActor`, so the `@Sendable` clock closure `GroveView` takes can capture it.
    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20

    private static func day(_ daysAgo: Int) -> Date {
        now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
    }

    private static func treeID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "08970000-0000-4000-8000-%012d", index))!
    }

    private static let cypress = treeID(1)
    private static let ginkgo = treeID(2)
    private static let zelkova = treeID(3)

    // ── The grove: three trees ───────────────────────────────────────────────────────────────

    /// The records are the journal below, counted — three visits, a check-in and two care logs
    /// against the cypress; a visit and a measurement against the ginkgo; nothing at all against the
    /// zelkova, which is in the grove because somebody hearted it. Kept in step by hand here because
    /// this is a double; `LocalAPI` derives both from the same tables in one read.
    static let trees: [GroveEntry] = [
        GroveEntry(
            treeID: cypress,
            displayName: "Grandmother Cypress",
            coordinate: Coordinate(latitude: 37.7601, longitude: -122.5089),
            lastVisitedAt: day(2),
            isFavorite: true,
            record: GroveRecord(visits: 3, checkIns: 1, careEvents: 2)
        ),
        GroveEntry(
            treeID: ginkgo,
            displayName: "Ginkgo on Judah",
            coordinate: Coordinate(latitude: 37.7615, longitude: -122.5040),
            lastVisitedAt: day(21),
            isFavorite: false,
            record: GroveRecord(visits: 1, measurements: 1)
        ),
        GroveEntry(
            treeID: zelkova,
            displayName: "Zelkova on 44th",
            coordinate: Coordinate(latitude: 37.7628, longitude: -122.4990),
            lastVisitedAt: nil,
            isFavorite: true,
            record: .none
        )
    ]

    // ── The journal: eight acts against those same three trees ───────────────────────────────

    private static func entry(
        _ index: Int,
        _ kind: JournalEntry.Kind,
        _ tree: UUID,
        _ name: String,
        daysAgo: Int,
        _ summary: String
    ) -> JournalEntry {
        JournalEntry(
            id: UUID(uuidString: String(format: "08970000-0000-4000-8000-%012d", 500 + index))!,
            kind: kind,
            treeID: tree,
            treeDisplayName: name,
            capturedAt: day(daysAgo),
            summary: summary
        )
    }

    static let entries: [JournalEntry] = [
        entry(1, .visit, cypress, "Grandmother Cypress", daysAgo: 2, "Fog on the crown"),
        entry(2, .careEvent, cypress, "Grandmother Cypress", daysAgo: 2, "watering, weeding"),
        entry(3, .observation, cypress, "Grandmother Cypress", daysAgo: 9, "healthy · vitality 4"),
        entry(4, .visit, cypress, "Grandmother Cypress", daysAgo: 16, ""),
        entry(5, .measurement, ginkgo, "Ginkgo on Judah", daysAgo: 21, "dbh 31 cm, taped"),
        entry(6, .visit, ginkgo, "Ginkgo on Judah", daysAgo: 21, "First leaves turning"),
        entry(7, .visit, cypress, "Grandmother Cypress", daysAgo: 96, "Winter, bare branches on the neighbours"),
        entry(8, .careEvent, cypress, "Grandmother Cypress", daysAgo: 400, "watering")
    ]

    // ── The two screens ──────────────────────────────────────────────────────────────────────

    /// My Grove, opened on the pill this round is about.
    @MainActor
    static var treesTab: some View {
        NavigationStack {
            GroveView(
                api: GrovePreviewAPI(grove: SweepFixtures.grove, trees: trees),
                now: { now },
                tab: .trees,
                onOpenSpecies: { _ in },
                onOpenTree: { _ in }
            )
        }
        .environment(AppRouter())
    }

    /// The Journal tab, on its own segment.
    @MainActor
    static var journalTab: some View {
        NavigationStack {
            JournalTabView(
                api: JournalPreviewAPI(page: Page(items: entries)),
                coordinate: nil,
                onOpenTree: { _ in }
            )
        }
        .environment(AppRouter())
    }
}
#endif
