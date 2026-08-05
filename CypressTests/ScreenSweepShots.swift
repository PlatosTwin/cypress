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
    /// `nonisolated` because it is the default argument of `capture` and `sweep`, and a default
    /// argument is evaluated at the call site rather than inside the isolated body.
    nonisolated static let height: CGFloat = 852

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
    /// - Parameter viewportHeight: the window's height. A phone's 852 by default, and taller for a
    ///   screen whose subject is below the fold — a `ScrollView` rendered off-screen cannot be
    ///   scrolled, so the only way to photograph the bottom of screen 03 is to give it a window with
    ///   room for all of it (ERRATA E145). It is not a device size and is not meant to look like one.
    static func capture(
        _ name: String,
        size: DynamicTypeSize,
        scheme: ColorScheme,
        viewportHeight: CGFloat = height,
        @ViewBuilder _ content: () -> some View
    ) async -> UIImage? {
        let host = UIHostingController(
            rootView: AnyView(
                content()
                    .environment(\.dynamicTypeSize, size)
                    .frame(width: width, height: viewportHeight)
                    .background(CypressColor.surfaceScreen)
            )
        )
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let frame = CGRect(x: 0, y: 0, width: width, height: viewportHeight)
        host.view.frame = frame

        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: viewportHeight))
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

        if case .blank(let reason) = ShotBlankGuard.verdict(for: image) {
            print("BLANK CAPTURE \(name) — \(Int(width))×\(Int(viewportHeight)) — \(reason)")
            return nil
        }
        guard let data = image.pngData() else {
            print("BLANK CAPTURE \(name) — pngData() returned nil")
            return nil
        }
        guard ShotBlankGuard.write(data, to: outputDirectory.appendingPathComponent("\(name).png")) else {
            return nil
        }
        return image
    }

    // The blank guard lives in `ShotBlankGuard` (task #93), shared with
    // `DynamicTypeScreenshotTests.render`, and it fails CLOSED: a capture it cannot positively
    // read is rejected. The E145 background — `drawHierarchy` past ~8,192 px of backing store
    // (2,730 pt at 3×, 4,096 pt at 2×) returns a fully transparent image instead of failing —
    // is documented there and in ERRATA E145.

    /// Lays four captures out 2×2 under their labels and writes one PNG.
    static func contactSheet(_ name: String, _ shots: [(label: String, image: UIImage)]) {
        guard !shots.isEmpty else { return }
        let caption: CGFloat = 26
        let gap: CGFloat = 8
        let columns = 2
        let rows = Int(ceil(Double(shots.count) / Double(columns)))
        let cellWidth = width + gap
        // The shots' own height, not the phone's — a tall capture must not be cropped by its sheet.
        let cellHeight = (shots.map(\.image.size.height).max() ?? height) + caption + gap
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

        guard let data = sheet.pngData() else {
            print("SHEET FAILED \(name) — pngData() returned nil")
            return
        }
        let url = outputDirectory.appendingPathComponent("\(name)-SHEET.png")
        guard ShotBlankGuard.write(data, to: url) else { return }
        print("SHEET \(url.path)")
    }

    /// One screen, four ways, plus its contact sheet.
    ///
    /// - Parameter ax5ViewportHeight: the window height for the two AX5 captures, when the AX5
    ///   layout needs more room than the drawn-size one (an AX5 screen is several times its drawn
    ///   height, and a capture that stops at 852 pt photographs only its header). Defaults to
    ///   `viewportHeight`. Keep it at or under `tallestViewport` — past 2,730 pt at 3× the
    ///   renderer hands back a transparent image (ERRATA E145) and the guard fails the sweep.
    ///
    /// A per-screen "the primary CTA exists in the AX5 accessibility tree" assertion was built
    /// and then removed here (task #144): SwiftUI serves accessibility over its own bridge and
    /// builds **no** in-process UIKit element tree — `accessibilityElements` is empty and
    /// `accessibilityElementCount()` is 0 on a laid-out hosting view, even with VoiceOver
    /// running. `AccessibilityTests`' header records the dead end at length; asserting against
    /// that tree needs an out-of-process client (XCUITest), not this harness.
    @discardableResult
    static func sweep(
        _ name: String,
        viewportHeight: CGFloat = height,
        ax5ViewportHeight: CGFloat? = nil,
        @ViewBuilder _ content: @escaping () -> some View
    ) async -> Bool {
        var shots: [(label: String, image: UIImage)] = []
        for variant in variants {
            let isAX5 = variant.size.isAccessibilitySize
            guard let image = await capture(
                "\(name)-\(variant.suffix)",
                size: variant.size,
                scheme: variant.scheme,
                viewportHeight: isAX5 ? (ax5ViewportHeight ?? viewportHeight) : viewportHeight,
                content
            ) else { return false }
            shots.append((variant.suffix, image))
        }
        contactSheet(name, shots)
        return true
    }

    // `pair` — light and dark at the drawn size only — is gone (task #144). The AX5 defect
    // family (#98, #132, E187's cousins) kept recurring because whole classes of screen state
    // were never rendered at an accessibility size; every swept state now goes through `sweep`
    // and gets the two `-ax5` captures with it.

    // MARK: - The drawn states

    @Test("01–19, plus the two tab roots, in four appearances each")
    func everyScreen() async throws {
        print("SWEEP DIR \(Self.outputDirectory.path)")

        // ── 02. Presented as a `fullScreenCover` (RootView `.identify`), so no NavigationStack. ──
        #expect(await Self.sweep("02-identify") { VisitPreviewFixtures.identify() })

        // ── The community add composer — the visit flow's other door, previewed since E174 but
        //    never swept, which is how #132 stayed a report from the owner's phone rather than a
        //    picture anyone could pull up (task #144). Rendered bare like 02: the flow is a
        //    `fullScreenCover`. Tall at AX5 so the form below the photo well is in the frame.
        #expect(await Self.sweep(
            "02b-add-tree",
            ax5ViewportHeight: Self.tallestViewport
        ) {
            VisitPreviewFixtures.addTree()
        })

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

        // Tall at AX5 (E199's flagged verification gap, #228): the log rows `GrowthHistoryView
        // .logRow`'s `ViewThatFits` fix touches sit below the fold in a phone-height capture, so
        // a default-height AX5 shot shows only the chart and never exercises the fix. Same
        // technique as `02b-add-tree` and `c06-city-record-full-ramp` below.
        #expect(await Self.sweep(
            "11-growth-history",
            ax5ViewportHeight: Self.tallestViewport
        ) {
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
                    onShowGroup: { _ in }
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

        // ── Screen 12's two counted rows go here (ERRATA E129). Both states are photographed,
        //    because the difference between them is one line of copy: the whole group says `All nine
        //    are on this map.` and a page says which twenty of 1,474 are, and E38 is the entry for
        //    what happens when a screen loses that distinction.
        #expect(await Self.sweep("12b-group-whole") {
            NavigationStack {
                PinSetMapView(
                    set: SweepFixtures.coverageGroup,
                    userCoordinate: SweepFixtures.coordinate,
                    onBack: {},
                    onOpenPin: { _ in }
                )
            }
            .environment(AppRouter())
        })

        #expect(await Self.sweep("12c-group-page") {
            NavigationStack {
                PinSetMapView(
                    set: SweepFixtures.vacantGroup,
                    userCoordinate: SweepFixtures.coordinate,
                    onBack: {},
                    onOpenPin: { _ in }
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
                    // signed in on (ERRATA E131).
                    account: AccountModel(api: nil)
                )
            }
                .environment(AppRouter())
        })
    }

    // MARK: - §9b · What the city has on file (ERRATA E145, E181)

    /// The five states of the city-record section, light and dark, default and AX5 (#144).
    ///
    /// The section is the last block on screen 03, so these are captured in a 1,500 pt window: an
    /// off-screen `ScrollView` cannot be scrolled, and a phone-height capture of a cold profile stops
    /// just above the header. The window is a photographic device, not a claimed screen size.
    ///
    /// Five, because between them they cover every branch: all six columns with `FUF` in them, the
    /// two-card floor, one of the 196 `Prune Opt Out` rows, one of the 318 rows the city does not
    /// call a tree, and a community tree with no city record at all — where the section must be
    /// absent and the land-context line must still be there, stated rather than inferred.
    @Test("the city-record section, five states, in four appearances each")
    func cityRecordStates() async throws {
        print("SWEEP DIR \(Self.outputDirectory.path)")
        let states: [(String, TreeProfile)] = [
            ("c01-city-record-full-fuf", TreeProfileSeedFixtures.fullCityRecord),
            ("c02-city-record-bare", TreeProfileSeedFixtures.bareCityRecord),
            ("c03-city-record-prune-opt-out", TreeProfileSeedFixtures.pruneOptOut),
            ("c04-city-record-landscaping", TreeProfileSeedFixtures.listedAsLandscaping),
            ("c05-city-record-community-none", TreeProfileSeedFixtures.communityAdded),
        ]
        for (name, profile) in states {
            #expect(await Self.sweep(
                name,
                viewportHeight: Self.tallViewport,
                ax5ViewportHeight: Self.tallestViewport
            ) {
                NavigationStack {
                    TreeProfileView(treeID: profile.tree.id, api: TreeProfilePreviewAPI(profile: profile))
                }
                .environment(AppRouter())
            })
        }

        // The fullest record at both ends of the type ramp as well. Five cards, three of which hold a
        // value long enough to wrap beside a `.fixedSize()` badge, is where AX5 has something to say —
        // it is the state that made C11's `ViewThatFits` necessary at the *drawn* size.
        let full = TreeProfileSeedFixtures.fullCityRecord
        #expect(await Self.sweep("c06-city-record-full-ramp", viewportHeight: Self.tallestViewport) {
            NavigationStack {
                TreeProfileView(treeID: full.tree.id, api: TreeProfilePreviewAPI(profile: full))
            }
            .environment(AppRouter())
        })
    }

    /// Enough room for a cold profile's whole scroll, section included.
    static let tallViewport: CGFloat = 1_500
    /// The same at AX5, where every block is several times its drawn height.
    ///
    /// **2,700 and not more.** At 3× this is 8,100 px, just under the 8,192 px limit above which
    /// `drawHierarchy` returns a transparent image rather than failing — the limit `isNotBlank` now
    /// catches. It is not enough for the whole of an AX5 profile; it reaches the section, which is
    /// what this shot is for.
    static let tallestViewport: CGFloat = 2_700

    // MARK: - The states a beta tester sees first

    /// Cold and empty. "A screen with no photographs, no check-ins, no measurements … is what a
    /// beta tester sees first and it is the least-exercised path in the app." At AX5 as well,
    /// since task #144: an empty state is mostly sentences, and sentences are what the ramp moves.
    @Test("the cold and empty states, in four appearances each")
    func coldStates() async throws {
        #expect(await Self.sweep("e02-identify-denied") {
            VisitPreviewFixtures.identify(fix: .denied)
        })
        #expect(await Self.sweep("e02-identify-no-tells") {
            VisitPreviewFixtures.identify(rows: VisitPreviewFixtures.untelledRows)
        })
        #expect(await Self.sweep("e06-report-nothing-selected") {
            NavigationStack {
                ReportView(
                    treeID: SweepFixtures.reportTreeID,
                    api: ReportPreviewAPI(),
                    dialer: ReportPreviewDialer()
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e07-species-uncurated") {
            NavigationStack {
                SpeciesPreviewFixtures.view(species: SpeciesPreviewFixtures.brushCherry)
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e08-grove-empty") {
            NavigationStack {
                GroveView(api: GrovePreviewAPI(grove: .empty), now: { SweepFixtures.now })
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e09-care-log-untouched") {
            CareLogPreviewFixtures.view()
        })
        #expect(await Self.sweep("e11-growth-empty") {
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
        #expect(await Self.sweep("e12-almanac-fresh") {
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
        #expect(await Self.sweep("e13-activity-empty") {
            NavigationStack {
                ActivityScreen(
                    presentation: ActivityPreviewFixtures.presentation(
                        ActivityPreviewFixtures.emptyProfile()
                    )
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e16-measure-first-reading") {
            NavigationStack {
                MeasureScreen(
                    presentation: MeasurePreviewFixtures.presentation(
                        draft: MeasurePreviewFixtures.draft(entry: "")
                    )
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e17-outbox-empty") {
            NavigationStack {
                OutboxScreen(
                    presentation: OutboxPreviewFixtures.presentation([]),
                    syncPhotosOnWifiOnly: .constant(true)
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e19-memorial-bare") {
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
        #expect(await Self.sweep("e08-grove-read-failed") {
            NavigationStack {
                GroveView(api: GrovePreviewAPI(fails: true), now: { SweepFixtures.now })
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e12-almanac-read-failed") {
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
        // Screen 12's two other ways of having little or nothing on it (RULINGS R29, ERRATA E182).
        // They join the sweep beside the failed read for the same reason that one did: all four of
        // this screen's near-empty states used to be two pictures, and the only way they stay four
        // is by being photographed.
        #expect(await Self.sweep("e12-almanac-radius-area") {
            NavigationStack {
                AlmanacView(
                    api: AlmanacPreviewAPI(payload: SweepFixtures.radiusAlmanac),
                    coordinate: SweepFixtures.coordinate,
                    now: { SweepFixtures.now },
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e12-almanac-out-of-range") {
            NavigationStack {
                AlmanacView(
                    api: AlmanacPreviewAPI(payload: .empty),
                    coordinate: SweepFixtures.coordinate,
                    now: { SweepFixtures.now },
                    onBack: {}
                )
            }
            .environment(AppRouter())
        })
        #expect(await Self.sweep("e14b-site-nothing-nearby") {
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

    /// `nonisolated` so the `@Sendable () -> Date` the models take, and the `#expect` autoclosures
    /// that read it, can do so: an immutable `Date` carries no isolation of its own.
    nonisolated static let now = Date(timeIntervalSince1970: 1_784_505_600) // 2026-07-20
    static let coordinate = Coordinate(latitude: 37.7533, longitude: -122.4934)
    static let reportTreeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000001")!

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "9F3A0000-0000-4000-8000-%012X", 0xE00 + index))!
    }

    // ── Screen 08 ────────────────────────────────────────────────────────────────────────────

    /// Twelve species met, in a neighborhood the city records 215 species in — R5's denominator,
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
        // The neighborhood's own species list has to contain the ones met, or the intersection
        // that produces the numerator is empty and the ring reads zero.
        let neighborhoodIDs = (0..<215).map { id($0) }
        return GroveSpecies(
            neighborhood: GroveNeighborhood(
                area: .named("Outer Sunset"),
                species: Series(complete: neighborhoodIDs)
            ),
            known: Series(complete: known)
        )
    }

    // ── Screen 12 ────────────────────────────────────────────────────────────────────────────

    /// A city-inventory pin, spread along a street in the Sunset (ERRATA E129). Screen 12's two
    /// counted rows carry pins rather than ids now, so the sweep's almanac has to hold real ones — a
    /// group with no coordinates is a group no map could draw.
    static func pin(_ index: Int, status: TreeStatus = .alive) -> TreePin {
        TreePin(
            id: id(index),
            coordinate: Coordinate(
                latitude: 37.7530 + Double(index % 40) * 0.000_35,
                longitude: -122.4850 + Double(index % 40) * 0.000_20
            ),
            status: status,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
    }

    /// The two groups screen 12 hands out (ERRATA E129), one whole and one a page of 1,474.
    static var coverageGroup: PinSet {
        PinSet(
            subject: .coverageGap,
            pins: (0..<9).map { pin(920 + $0) },
            count: 9,
            neighborhoodName: "Outer Sunset"
        )
    }

    static var vacantGroup: PinSet {
        PinSet(
            subject: .vacantSites,
            pins: (0..<20).map { pin(930 + $0, status: .vacantSite) },
            count: 1_474,
            neighborhoodName: "Outer Sunset"
        )
    }

    static var almanac: Almanac {
        Almanac(neighborhood: AlmanacNeighborhood(
            area: .named("Outer Sunset"),
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
                CoverageTree(pin: pin(920 + $0), distanceM: Double(120 + $0 * 60))
            })),
            vacantSites: VacantSites(count: 1_474, nearest: (0..<20).map { pin(930 + $0, status: .vacantSite) })
        ))
    }

    /// Every device on day one: the city's own facts are there, the two blocks that need a
    /// contribution are not.
    static var freshAlmanac: Almanac {
        Almanac(neighborhood: AlmanacNeighborhood(
            area: .named("Outer Sunset"),
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
                CoverageTree(pin: pin(920 + $0), distanceM: Double(120 + $0 * 60))
            })),
            vacantSites: VacantSites(count: 1_474, nearest: (0..<20).map { pin(930 + $0, status: .vacantSite) })
        ))
    }

    /// **The fallback area** (RULINGS R29): the same almanac a San Jose reader gets, with a distance
    /// in the pill instead of a place and the sentence that says so under the header.
    static var radiusAlmanac: Almanac {
        Almanac(neighborhood: AlmanacNeighborhood(
            area: .radius(meters: AlmanacLimits.fallbackRadiusM),
            elder: ElderTree(
                treeID: id(901),
                activeName: nil,
                speciesCommonName: "Ornamental Pear",
                address: "S 1st St",
                plantedYear: 2021
            ),
            newestNeighbors: RecentPlanting(
                treeCount: 5,
                leadingSpecies: ["Ornamental Pear"],
                nearest: (0..<5).map { pin(940 + $0) }
            ),
            composition: NeighborhoodComposition(
                distinctSpeciesCount: 167,
                treeCount: 5_963,
                leading: [
                    SpeciesShare(speciesID: id(910), name: "Platanus acerifolia", treeCount: 1_968),
                    SpeciesShare(speciesID: id(911), name: "California Fan Palm", treeCount: 358),
                    SpeciesShare(speciesID: id(912), name: "Mexican Fan Palm", treeCount: 298),
                ]
            ),
            coverage: CoverageGap(trees: Series(complete: (0..<4).map {
                CoverageTree(pin: pin(920 + $0), distanceM: Double(120 + $0 * 60))
            })),
            vacantSites: VacantSites(count: 1_000, nearest: (0..<20).map { pin(930 + $0, status: .vacantSite) })
        ))
    }

    // ── The You tab ──────────────────────────────────────────────────────────────────────────

    static func outboxViewState() -> OutboxViewState {
        OutboxViewState(queue: VisitPreviewFixtures.outbox())
    }
}
#endif
