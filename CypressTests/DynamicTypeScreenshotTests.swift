#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// Renders every screen at both ends of the Dynamic Type ramp and writes the PNGs out.
///
/// ── Why this is a test and not a script ────────────────────────────────────────────────────
/// ARCHITECTURE §6 says to verify the field screens at AX1 and §7 says visual verification is by
/// running the app and comparing to SCREENS.md. Running the app gets you the map; the other
/// eighteen screens are behind taps, and driving the simulator's UI needs assistive access that a
/// build machine does not have. The `#if DEBUG` preview fixtures already stand every screen up
/// against real seed rows, so the cheapest honest way to *look* at screen 05 at AX5 is to render
/// the same view the preview renders, at that size, and open the file.
///
/// **This asserts almost nothing and that is deliberate.** ARCHITECTURE §7: "Snapshot-testing the
/// screens against the mocks is explicitly *not* set up yet." A snapshot suite with no baselines is
/// a suite that passes on a blank image, which is worse than no suite. What it does assert is
/// what a renderer can know without a baseline: that the view produced an image, and — via
/// `ShotBlankGuard` (task #93) — that the image is not a blank: a flat, transparent, or
/// unreadable capture makes `render` return nil, which fails the caller's `#expect`. The
/// rendered heights are printed beside it, because that is the number a reviewer wants before
/// opening anything.
///
/// Output goes to `CYPRESS_SHOT_DIR` if set, otherwise the temporary directory; the path of each
/// file is printed so a reviewer can open them.
@MainActor
@Suite("Dynamic Type · both extremes")
struct DynamicTypeScreenshotTests {

    /// The two ends of the ramp. `.xSmall` is the smallest the system offers; `.accessibility5` is
    /// the largest, and is the one that finds fixed frames.
    static let extremes: [(name: String, size: DynamicTypeSize)] = [
        ("xs", .xSmall),
        ("ax5", .accessibility5),
    ]

    static var outputDirectory: URL {
        let base = ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("cypress-dynamic-type")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// iPhone 16 Pro's points. Height is a *minimum*: the renderer is given an unbounded height so a
    /// screen that grows past the display grows in the image instead of being cut off, which is the
    /// difference between seeing the overflow and seeing the crop.
    static let width: CGFloat = 393
    static let height: CGFloat = 852

    /// Renders `content` through a real `UIHostingController` in a real window.
    ///
    /// **Not `ImageRenderer`.** That was the first attempt and it produces a convincing lie: it
    /// lays out a `ScrollView` to whatever height is asked for and then draws *nothing inside it*,
    /// so screen 05 came out as 3,114 pt of empty page with the sticky CTA at the bottom — which
    /// reads as "the card vanished at AX5" rather than as "the renderer does not do scroll views".
    /// It also renders synchronously, so every screen that loads through `.task` was captured in
    /// its `ProgressView` state.
    ///
    /// A hosting controller in a window goes through UIKit's own layout and draw, which handles
    /// both: scroll content is real, and a run-loop turn before the capture lets an `async` load
    /// land. The window sits off-screen so a run does not flash onto a shared simulator.
    static func render(
        _ name: String,
        _ size: DynamicTypeSize,
        scheme: ColorScheme = .light,
        @ViewBuilder _ content: () -> some View
    ) async -> CGSize? {
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
        // `await`, not `RunLoop.run(until:)`. Screen 03 loads its profile through the API actor,
        // and a run-loop spin does not drain the cooperative executor the `.task` is suspended on —
        // so every capture of 03 came back as a viewport containing one spinner, which is a real
        // state but not the one being audited. Awaiting yields the main actor properly.
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

        // The blank guard (task #93, shared with `ScreenSweepShots`): this harness previously
        // asserted only that a `UIImage` existed, and a `UIImage` of nothing exists happily —
        // E145's transparent over-tall captures would have sailed through here. Fail CLOSED.
        if case .blank(let reason) = ShotBlankGuard.verdict(for: image) {
            print("BLANK CAPTURE \(name) — \(reason)")
            return nil
        }
        guard let data = image.pngData() else {
            print("BLANK CAPTURE \(name) — pngData() returned nil")
            return nil
        }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        guard ShotBlankGuard.write(data, to: url) else { return nil }
        print("SHOT \(url.path) \(Int(image.size.width))x\(Int(image.size.height))")
        return image.size
    }

    /// Every screen the preview fixtures can stand up, rendered at both ends.
    ///
    /// The name is the screen number from SCREENS.md, so the output directory sorts into the same
    /// order as the spec.
    @Test("every screen renders at both ends of the ramp")
    func everyScreenRendersAtBothExtremes() async {
        var heights: [String: [CGFloat]] = [:]

        for (suffix, size) in Self.extremes {
            func shoot(_ screen: String, @ViewBuilder _ content: () -> some View) async {
                let rendered = await Self.render("\(screen)-\(suffix)", size, content)
                #expect(rendered != nil, "\(screen) produced no image at \(suffix)")
                if let rendered { heights[screen, default: []].append(rendered.height) }
            }

            await shoot("03-tree-profile") {
                TreeProfileView(
                    treeID: TreeProfileSeedFixtures.populated.tree.id,
                    api: TreeProfilePreviewAPI(profile: TreeProfileSeedFixtures.populated),
                    caretakerInitials: ["N", "M", "J"]
                )
            }
            await shoot("05-check-in") {
                CheckInPreviewFixtures.view(draft: CheckInPreviewFixtures.drawnState)
            }
            await shoot("13-activity") {
                ActivityScreen(
                    presentation: ActivityPreviewFixtures.presentation(
                        ActivityPreviewFixtures.drawnProfile()
                    )
                )
            }
            await shoot("16-measure") {
                MeasureScreen(
                    presentation: MeasurePreviewFixtures.presentation(
                        draft: MeasurePreviewFixtures.draft(entry: "64"),
                        previous: MeasurePreviewFixtures.previousDBH()
                    )
                )
            }
            // The vacant planting site (ERRATA E107). No screen number, because SCREENS.md draws
            // none — it sorts beside 14, which is the profile it replaces for 12,518 records. Every
            // block on it is prose that has to wrap rather than truncate, and one of them is the
            // city's free-text site vocabulary, which is the longest string on the screen and not
            // ours to shorten.
            await shoot("14b-site") {
                SiteScreen(
                    presentation: SitePresentation(
                        profile: SiteFixtures.profile,
                        nearest: SiteFixtures.nearby.last
                    )
                )
            }
            await shoot("17-outbox") {
                OutboxScreen(
                    presentation: OutboxPreviewFixtures.presentation([
                        OutboxPreviewFixtures.visit,
                        OutboxPreviewFixtures.checkIn,
                        OutboxPreviewFixtures.expiredMeasurement,
                    ]),
                    syncPhotosOnWifiOnly: .constant(true)
                )
            }
        }

        // Every capture is one device viewport, which is the frame a person actually holds — so
        // there is no size to assert and the images are the output. ARCHITECTURE §7 is explicit
        // that snapshot testing against the mocks is not set up, and a baseline-free snapshot
        // suite passes on a blank image; this renders, prints the paths, and leaves the judgement
        // to a reviewer.
        _ = heights
    }

    /// The one screen ERRATA and the M4 brief both single out. 05's rubric anchors are D3 content
    /// and are long by design, so the optional well is already below the fold at the drawn size;
    /// this renders it at both ends so the *degree* is on record rather than guessed at.
    @Test("05 · the check-in card at both ends, and what it costs")
    func checkInAtBothExtremes() async {
        var heights: [CGFloat] = []
        for (suffix, size) in Self.extremes {
            let rendered = await Self.render("05-check-in-detail-\(suffix)", size) {
                CheckInPreviewFixtures.view(draft: CheckInPreviewFixtures.drawnState)
            }
            #expect(rendered != nil)
            if let rendered { heights.append(rendered.height) }
        }
        #expect(heights.count == 2)
    }

    /// Dark is done (ERRATA E8) and is not re-litigated here, but a Dynamic Type change can only be
    /// judged in the appearance it ships in, and there are two. One pass of the same screens.
    @Test("the same screens at AX5 in dark")
    func darkAtTheLargeEnd() async {
        let screens: [(String, () -> AnyView)] = [
            ("03-tree-profile-dark", {
                AnyView(TreeProfileView(
                    treeID: TreeProfileSeedFixtures.populated.tree.id,
                    api: TreeProfilePreviewAPI(profile: TreeProfileSeedFixtures.populated),
                    caretakerInitials: ["N", "M", "J"]
                ))
            }),
            ("05-check-in-dark", {
                AnyView(CheckInPreviewFixtures.view(draft: CheckInPreviewFixtures.drawnState))
            }),
        ]
        for (name, content) in screens {
            #expect(
                await Self.render("\(name)-ax5", .accessibility5, scheme: .dark) { content() } != nil,
                "\(name) produced no image"
            )
        }
    }
}
#endif
