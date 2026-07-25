//
//  ScreenSweepShots.swift
//  CypressTests
//
//  Every screen in the app, photographed in light and dark at the two ends of the Dynamic Type
//  ramp, so that somebody can look at them.
//
//  ── Why this suite exists ─────────────────────────────────────────────────────────────────
//  `DynamicTypeScreenshotTests` renders six screens and `FavoriteAppearanceShots` renders one
//  component's two states. Nineteen screens exist. The two defects found in this project by looking
//  rather than by testing — the 91pt navigation bar on screen 01 (E110) and the caption ramp's
//  contrast failure across 61 call sites (E106/R1) — were both invisible to a suite of 405 passing
//  tests, and both were on screens nobody had ever photographed. This extends the existing harness
//  to the rest of them.
//
//  **It asserts almost nothing, and that is inherited rather than invented.** ARCHITECTURE §7:
//  "Snapshot-testing the screens against the mocks is explicitly *not* set up yet." A baseline-free
//  snapshot suite passes on a blank image. What it asserts is that each screen produced an image;
//  the images are the output and the contact sheets are what a reviewer opens.
//
//  ── Two things this harness does that the older one does not ──────────────────────────────
//  1. **It wraps pushed screens in a `NavigationStack`, exactly as `RootView` does.** E110 was a
//     navigation bar inherited from that stack, and a screen rendered bare cannot inherit one — so
//     rendering bare is rendering something the app never shows. Screens presented as a
//     `fullScreenCover` (04, 09, 10, and the visit flow's 02 and 18) are rendered without it, for
//     the same reason.
//  2. **It writes a 2×2 contact sheet per screen**, so the four appearances of one screen are one
//     image and the comparison is a glance rather than four file-opens.
//
//  Output goes to `CYPRESS_SHOT_DIR` if set, otherwise a temporary directory. Paths are printed.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Every screen · light and dark, default and AX5")
struct ScreenSweepShots {

    // MARK: - Harness

    static let width: CGFloat = 393
    static let height: CGFloat = 852

    static var outputDirectory: URL {
        let base = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("cypress-sweep")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The four ways every screen is looked at.
    ///
    /// `.large` rather than `.xSmall` for the "default" end: `.large` is the system default and is
    /// the size the mocks were drawn at, so it is the one a discrepancy against SCREENS.md can be
    /// measured from. `.xSmall` finds nothing that `.large` does not.
    static let variants: [(suffix: String, size: DynamicTypeSize, scheme: ColorScheme)] = [
        ("light", .large, .light),
        ("dark", .large, .dark),
        ("light-ax5", .accessibility5, .light),
        ("dark-ax5", .accessibility5, .dark),
    ]

    /// Renders `content` through a real `UIHostingController` in a real off-screen window.
    ///
    /// The mechanism and the reasons for it are `DynamicTypeScreenshotTests.render`'s; this returns
    /// the `UIImage` as well, because the contact sheet needs the pixels and not just the file.
    static func capture(
        _ name: String,
        size: DynamicTypeSize,
        scheme: ColorScheme,
        @ViewBuilder _ content: () -> some View
    ) async -> UIImage? {
        let host = UIHostingController(
            rootView: AnyView(
                content()
                    .environment(\.dynamicTypeSize, size)
                    .frame(width: width, height: height)
                    .background(CypressColor.surfaceScreen)
            )
        )
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.frame = frame

        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: height))
        window.overrideUserInterfaceStyle = host.overrideUserInterfaceStyle
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()

        // `await`, not `RunLoop.run(until:)` — a run-loop spin does not drain the cooperative
        // executor a `.task` is suspended on, so every screen that loads asynchronously would be
        // captured in its `ProgressView` state.
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        let image = UIGraphicsImageRenderer(bounds: frame).image { _ in
            host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil

        guard let data = image.pngData() else { return nil }
        try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        return image
    }

    /// Lays four captures out 2×2 under their labels and writes one PNG.
    static func contactSheet(_ name: String, _ shots: [(label: String, image: UIImage)]) {
        guard !shots.isEmpty else { return }
        let caption: CGFloat = 26
        let gap: CGFloat = 8
        let columns = 2
        let rows = Int(ceil(Double(shots.count) / Double(columns)))
        let cellWidth = width + gap
        let cellHeight = height + caption + gap
        let sheetSize = CGSize(
            width: cellWidth * CGFloat(columns) + gap,
            height: cellHeight * CGFloat(rows) + gap
        )

        let sheet = UIGraphicsImageRenderer(size: sheetSize).image { context in
            UIColor(white: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: sheetSize))
            for (index, shot) in shots.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = gap + CGFloat(column) * cellWidth
                let y = gap + CGFloat(row) * cellHeight
                (shot.label as NSString).draw(
                    at: CGPoint(x: x, y: y),
                    withAttributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 17, weight: .bold),
                        .foregroundColor: UIColor.white,
                    ]
                )
                shot.image.draw(at: CGPoint(x: x, y: y + caption))
            }
        }

        guard let data = sheet.pngData() else { return }
        let url = outputDirectory.appendingPathComponent("\(name)-SHEET.png")
        try? data.write(to: url)
        print("SHEET \(url.path)")
    }

    /// One screen, four ways, plus its contact sheet.
    @discardableResult
    static func sweep(_ name: String, @ViewBuilder _ content: @escaping () -> some View) async -> Bool {
        var shots: [(label: String, image: UIImage)] = []
        for variant in variants {
            guard let image = await capture(
                "\(name)-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                content
            ) else { return false }
            shots.append((variant.suffix, image))
        }
        contactSheet(name, shots)
        return true
    }

    /// One screen, two ways — light and dark at the drawn size. Used for the cold and empty states,
    /// where the question is "what does this say when there is nothing" rather than "does it hold
    /// together at AX5".
    @discardableResult
    static func pair(_ name: String, @ViewBuilder _ content: @escaping () -> some View) async -> Bool {
        var shots: [(label: String, image: UIImage)] = []
        for variant in variants.prefix(2) {
            guard let image = await capture(
                "\(name)-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                content
            ) else { return false }
            shots.append((variant.suffix, image))
        }
        contactSheet(name, shots)
        return true
    }

    // MARK: - The drawn states

    @Test("01–19, plus the two tab roots, in four appearances each")
    func everyScreen() async throws {
        print("SWEEP DIR \(Self.outputDirectory.path)")

        // ── 02. Presented as a `fullScreenCover` (RootView `.identify`), so no NavigationStack. ──
        #expect(await Self.sweep("02-identify") { VisitPreviewFixtures.identify() })

        // ── 03. Pushed. ──────────────────────────────────────────────────────────────────────
        #expect(await Self.sweep("03-tree-profile") {
            NavigationStack {
                TreeProfileView(
                    treeID: TreeProfileSeedFixtures.populated.tree.id,
                    api: TreeProfilePreviewAPI(profile: TreeProfileSeedFixtures.populated),
                    caretakerInitials: ["N", "M", "J"]
                )
            }
            .environment(AppRouter())
        })

        // ── 04. Forced dark in both appearances; the two dark shots should be identical to the
        //       two light ones, which is itself the check.
        #expect(await Self.sweep("04-visit-camera") { VisitPreviewFixtures.camera() })

        #expect(await Self.sweep("05-check-in") {
            NavigationStack { CheckInPreviewFixtures.view(draft: CheckInPreviewFixtures.drawnState) }
                .environment(AppRouter())
        })

        #expect(await Self.sweep("06-report") {
            NavigationStack {
                ReportView(
                    treeID: SweepFixtures.reportTreeID,
                    api: ReportPreviewAPI(),
                    dialer: ReportPreviewDialer(),
                    initialSelection: .hazard(.hangingOrBrokenLimb)
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("07-species") {
            NavigationStack {
                SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.montereyCypress)
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("08-grove") {
            NavigationStack {
                GroveView(
                    api: GrovePreviewAPI(grove: SweepFixtures.grove),
                    now: { SweepFixtures.now },
                    onOpenSpecies: { _ in }
                )
            }
            .environment(AppRouter())
        })

        // ── 09 and 10 are `fullScreenCover`s and draw their own scrim. ───────────────────────
        #expect(await Self.sweep("09-care-log") {
            CareLogPreviewFixtures.view(draft: CareLogPreviewFixtures.drawnState)
        })

        #expect(await Self.sweep("10-share") {
            ShareView(treeID: SharePreviewFixtures.treeID, api: SharePreviewAPI())
        })

        #expect(await Self.sweep("11-growth-history") {
            NavigationStack {
                GrowthHistoryView(
                    treeID: GrowthHistoryPreviewFixtures.treeID,
                    api: GrowthHistoryPreviewAPI()
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("12-almanac") {
            NavigationStack {
                AlmanacView(
                    api: AlmanacPreviewAPI(payload: SweepFixtures.almanac),
                    coordinate: SweepFixtures.coordinate,
                    now: { SweepFixtures.now },
                    onBack: {},
                    onOpenTree: { _ in },
                    onWalk: { _ in }
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("13-activity") {
            NavigationStack {
                ActivityScreen(
                    presentation: ActivityPreviewFixtures.presentation(
                        ActivityPreviewFixtures.drawnProfile()
                    )
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("14-cold-profile") {
            NavigationStack {
                TreeProfileView(
                    treeID: TreeProfileSeedFixtures.coldStart.tree.id,
                    api: TreeProfilePreviewAPI(profile: TreeProfileSeedFixtures.coldStart)
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("14b-site") {
            NavigationStack {
                SiteScreen(
                    presentation: SitePresentation(
                        profile: SiteFixtures.profile,
                        nearest: SiteFixtures.nearby.last
                    ),
                    onBack: {},
                    onOpenTree: { _ in }
                )
            }
            .environment(AppRouter())
        })

        // ── 15 is a sheet over 18. Gated out of the beta by R4, and photographed anyway: it is
        //    built, and the day a server exists it is what a contributor sees.
        #expect(await Self.sweep("15-account-ask") {
            AccountAskScreen(
                presentation: AccountAskPresentation(
                    contributions: DeviceContributions(visits: 3),
                    isConsentAccepted: true
                )
            )
        })

        #expect(await Self.sweep("16-measure") {
            NavigationStack {
                MeasureScreen(
                    presentation: MeasurePreviewFixtures.presentation(
                        draft: MeasurePreviewFixtures.draft(entry: "64"),
                        previous: MeasurePreviewFixtures.previousDBH()
                    )
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("17-outbox") {
            NavigationStack {
                OutboxScreen(
                    presentation: OutboxPreviewFixtures.presentation([
                        OutboxPreviewFixtures.visit,
                        OutboxPreviewFixtures.checkIn,
                        OutboxPreviewFixtures.expiredMeasurement,
                        OutboxPreviewFixtures.syncedVisit,
                        OutboxPreviewFixtures.syncedCare,
                    ]),
                    syncPhotosOnWifiOnly: .constant(true)
                )
            }
            .environment(AppRouter())
        })

        // 18 (next-tree), 19 (memorial) and the two tab roots (20, 21) are in `afterTheSave`,
        // pulled out because 18's fixture writes a receipt and a write can throw — keeping it here
        // would put the whole 21-screen sweep behind one fallible enqueue.
    }

    /// The four screens that come after the throwing `receipt()` call in `everyScreen`, pulled out
    /// so a failure in the receipt does not cost the whole 17-minute sweep to re-verify. 18 is the
    /// next-tree confirmation; 19 the memorial; 20 and 21 the two tab roots.
    @Test("18–21, the screens past the save receipt")
    func afterTheSave() async throws {
        let receipt = try await VisitPreviewFixtures.receipt()
        #expect(await Self.sweep("18-next-tree") {
            VisitPreviewFixtures.saved(receipt: receipt)
        })
        #expect(await Self.sweep("19-memorial") {
            NavigationStack {
                MemorialScreen(
                    presentation: MemorialPresentation(
                        profile: MemorialFixtures.profile,
                        facts: MemorialFixtures.removedInMay,
                        now: MemorialFixtures.now
                    ),
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("20-journal-tab") {
            NavigationStack {
                JournalTabView(
                    api: AlmanacPreviewAPI(payload: SweepFixtures.almanac),
                    coordinate: SweepFixtures.coordinate
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("21-you-tab") {
            NavigationStack {
                YouTabView(
                    outbox: SweepFixtures.outboxViewState(),
                    moderation: ModerationModel(api: nil),
                    // An inert account model, like the moderation one beside it: no store, so the
                    // account block and the reminder list draw the state of a device nobody has
                    // signed in on (ERRATA E130).
                    account: AccountModel(api: nil)
                )
            }
                .environment(AppRouter())
        })
    }

    // MARK: - The states a beta tester sees first

    /// Cold and empty. "A screen with no photographs, no check-ins, no measurements … is what a
    /// beta tester sees first and it is the least-exercised path in the app."
    @Test("the cold and empty states, light and dark")
    func coldStates() async throws {
        #expect(await Self.pair("e02-identify-denied") {
            VisitPreviewFixtures.identify(fix: .denied)
        })
        #expect(await Self.pair("e02-identify-no-tells") {
            VisitPreviewFixtures.identify(rows: VisitPreviewFixtures.untelledRows)
        })
        #expect(await Self.pair("e06-report-nothing-selected") {
            NavigationStack {
                ReportView(
                    treeID: SweepFixtures.reportTreeID,
                    api: ReportPreviewAPI(),
                    dialer: ReportPreviewDialer()
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e07-species-uncurated") {
            NavigationStack {
                SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.brushCherry)
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e08-grove-empty") {
            NavigationStack {
                GroveView(api: GrovePreviewAPI(grove: .empty), now: { SweepFixtures.now })
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e09-care-log-untouched") {
            CareLogPreviewFixtures.view()
        })
        #expect(await Self.pair("e11-growth-empty") {
            NavigationStack {
                GrowthHistoryView(
                    treeID: GrowthHistoryPreviewFixtures.treeID,
                    api: GrowthHistoryPreviewAPI(
                        profile: GrowthHistoryPreviewFixtures.emptyProfile()
                    )
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e12-almanac-fresh") {
            NavigationStack {
                AlmanacView(
                    api: AlmanacPreviewAPI(payload: SweepFixtures.freshAlmanac),
                    coordinate: SweepFixtures.coordinate,
                    now: { SweepFixtures.now },
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e13-activity-empty") {
            NavigationStack {
                ActivityScreen(
                    presentation: ActivityPreviewFixtures.presentation(
                        ActivityPreviewFixtures.emptyProfile()
                    )
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e16-measure-first-reading") {
            NavigationStack {
                MeasureScreen(
                    presentation: MeasurePreviewFixtures.presentation(
                        draft: MeasurePreviewFixtures.draft(entry: "")
                    )
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e17-outbox-empty") {
            NavigationStack {
                OutboxScreen(
                    presentation: OutboxPreviewFixtures.presentation([]),
                    syncPhotosOnWifiOnly: .constant(true)
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e19-memorial-bare") {
            NavigationStack {
                MemorialScreen(
                    presentation: MemorialPresentation(
                        profile: MemorialFixtures.bare,
                        facts: MemorialFixtures.removedInMay,
                        now: MemorialFixtures.now
                    ),
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
        // The two reads that can fail with nothing else on the screen to say so (ERRATA E126).
        // Photographed next to `e08-grove-empty` and `e12-almanac-fresh` above, because until E126
        // each of these pairs was one image drawn twice.
        #expect(await Self.pair("e08-grove-read-failed") {
            NavigationStack {
                GroveView(api: GrovePreviewAPI(fails: true), now: { SweepFixtures.now })
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e12-almanac-read-failed") {
            NavigationStack {
                AlmanacView(
                    api: AlmanacPreviewAPI(fails: true),
                    coordinate: SweepFixtures.coordinate,
                    now: { SweepFixtures.now },
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.pair("e14b-site-nothing-nearby") {
            NavigationStack {
                SiteScreen(
                    presentation: SitePresentation(profile: SiteFixtures.profile),
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
    }
}

// MARK: - Fixtures this suite owns

/// Values for the three screens whose own preview fixtures are `private` to their file, plus the
/// two ids this suite needs. Built from the public `Data/API` types rather than by widening
/// somebody else's `private enum`, so nothing outside `CypressTests/` changes to run this.
@MainActor
enum SweepFixtures {

    static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    static let coordinate = Coordinate(latitude: 37.7533, longitude: -122.4934)
    static let reportTreeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000001")!

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "9F3A0000-0000-4000-8000-%012X", 0xE00 + index))!
    }

    // ── Screen 08 ────────────────────────────────────────────────────────────────────────────

    /// Twelve species met, in a neighbourhood the city records 215 species in — R5's denominator,
    /// not the mock's 40, because R5 ruled the true number stays.
    static var grove: GroveSpecies {
        let names: [(String, String)] = [
            ("Hesperocyparis macrocarpa", "Monterey Cypress"),
            ("Ginkgo biloba", "Ginkgo"),
            ("Platanus × hispanica", "London Plane"),
            ("Pittosporum undulatum", "Victorian Box"),
            ("Corymbia ficifolia", "Red Flowering Gum"),
            ("Metrosideros excelsa", "Pōhutukawa"),
            ("Lophostemon confertus", "Brisbane Box"),
            ("Leptospermum scoparium", "NZ Tea Tree"),
            ("Prunus cerasifera", "Cherry Plum"),
            ("Olea europaea", "Olive"),
            ("Tristaniopsis laurina", "Water Gum"),
            ("Magnolia grandiflora", "Southern Magnolia"),
        ]
        let known = names.enumerated().map { index, pair in
            KnownSpecies(
                speciesID: id(index),
                scientificName: pair.0,
                commonName: pair.1,
                // The last one met yesterday, which is what raises 08's celebration callout.
                firstMetAt: now.addingTimeInterval(-Double(names.count - index) * 86_400),
                firstMetAddress: index == names.count - 1 ? "Noriega St" : nil
            )
        }
        // The neighbourhood's own species list has to contain the ones met, or the intersection
        // that produces the numerator is empty and the ring reads zero.
        let neighbourhoodIDs = (0..<215).map { id($0) }
        return GroveSpecies(
            neighborhood: GroveNeighborhood(
                name: "Outer Sunset",
                species: Series(complete: neighbourhoodIDs)
            ),
            known: Series(complete: known)
        )
    }

    // ── Screen 12 ────────────────────────────────────────────────────────────────────────────

    static var almanac: Almanac {
        Almanac(neighborhood: AlmanacNeighborhood(
            name: "Outer Sunset",
            firstBloom: BloomFirst(
                treeID: id(900),
                speciesCommonName: "Red flowering gum",
                address: "44th Ave",
                firstSeenAt: Date(timeIntervalSince1970: 1_769_040_000), // 2026-01-22
                observerCount: 3
            ),
            elder: ElderTree(
                treeID: id(901),
                activeName: "Grandmother Cypress",
                speciesCommonName: "Monterey Cypress",
                address: "Great Highway at Judah",
                plantedYear: 1898
            ),
            newestNeighbors: RecentPlanting(treeCount: 23, leadingSpecies: ["ginkgo", "tea tree"]),
            composition: NeighborhoodComposition(
                distinctSpeciesCount: 64,
                treeCount: 4_000,
                leading: [
                    SpeciesShare(speciesID: id(910), name: "Monterey cypress", treeCount: 720),
                    SpeciesShare(speciesID: id(911), name: "NZ tea tree", treeCount: 440),
                    SpeciesShare(speciesID: id(912), name: "Ginkgo", treeCount: 360),
                ]
            ),
            coverage: CoverageGap(trees: Series(complete: (0..<9).map {
                CoverageTree(id: id(920 + $0), distanceM: Double(120 + $0 * 60))
            })),
            vacantSites: VacantSites(count: 1_474, nearestID: id(930))
        ))
    }

    /// Every device on day one: the city's own facts are there, the two blocks that need a
    /// contribution are not.
    static var freshAlmanac: Almanac {
        Almanac(neighborhood: AlmanacNeighborhood(
            name: "Outer Sunset",
            elder: ElderTree(
                treeID: id(901),
                activeName: nil,
                speciesCommonName: "Monterey Cypress",
                address: "Great Highway at Judah",
                plantedYear: 1898
            ),
            newestNeighbors: RecentPlanting(treeCount: 23, leadingSpecies: ["ginkgo", "tea tree"]),
            composition: NeighborhoodComposition(
                distinctSpeciesCount: 64,
                treeCount: 4_000,
                leading: [
                    SpeciesShare(speciesID: id(910), name: "Monterey cypress", treeCount: 720),
                ]
            ),
            coverage: CoverageGap(trees: Series(complete: (0..<9).map {
                CoverageTree(id: id(920 + $0), distanceM: Double(120 + $0 * 60))
            })),
            vacantSites: VacantSites(count: 1_474, nearestID: id(930))
        ))
    }

    // ── The You tab ──────────────────────────────────────────────────────────────────────────

    static func outboxViewState() -> OutboxViewState {
        OutboxViewState(queue: VisitPreviewFixtures.outbox())
    }
}
#endif
