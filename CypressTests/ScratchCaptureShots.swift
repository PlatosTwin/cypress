#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// SCRATCH — delete before merge. Renders screen 04 and the "Add this tree" composer so #98/#112/#113
/// can be judged in pixels rather than in prose.
@MainActor
@Suite("scratch · capture shots")
struct ScratchCaptureShots {

    static var out: URL {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CYPRESS_SHOT_DIR"]
            ?? NSTemporaryDirectory() + "cypress-scratch")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func shoot(
        _ name: String,
        _ size: DynamicTypeSize,
        _ content: () -> some View
    ) async {
        let w: CGFloat = 393, h: CGFloat = 852
        let host = UIHostingController(
            rootView: AnyView(content().environment(\.dynamicTypeSize, size).frame(width: w, height: h))
        )
        host.view.frame = CGRect(x: 0, y: 0, width: w, height: h)
        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: w, height: h))
        window.rootViewController = host
        window.isHidden = false
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(120))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        let url = out.appendingPathComponent("\(name).png")
        try? image.pngData()?.write(to: url)
        print("SHOT \(url.path)")
    }

    @MainActor
    static func addTree() -> VisitAddTreeView {
        VisitAddTreeView(
            api: VisitPreviewAPI(nearby: VisitPreviewFixtures.shortlistRows),
            location: VisitLocationProvider(
                pinnedFix: .located(VisitPreviewFixtures.origin, accuracyM: 9)
            ),
            attribution: VisitPreviewFixtures.attribution,
            onAdded: { _ in },
            onOpenExisting: { _ in },
            onBack: {}
        )
    }

    @Test("shoot 04 and 14")
    func shootThem() async {
        await Self.shoot("s04-large", .large) { VisitPreviewFixtures.camera() }
        await Self.shoot("s04-ax5", .accessibility5) { VisitPreviewFixtures.camera() }
        await Self.shoot("s14-large", .large) { Self.addTree() }
        await Self.shoot("s14-ax5", .accessibility5) { Self.addTree() }
    }

    /// The chip row on its own, at the width screen 04 gives it, so the label compression #112
    /// reports is visible without the viewfinder behind it.
    @Test("shoot the framing chips at the sizes the owner sees")
    func shootChips() async {
        for (name, size) in [("large", DynamicTypeSize.large), ("xxxl", .xxxLarge), ("ax5", .accessibility5)] {
            await Self.shoot("chips-\(name)", size) {
                VStack {
                    VisitShotTypeChips(framings: [
                        .init(id: .fullTree, label: "Full tree", isSelected: true, isCaptured: false),
                        .init(id: .trunk, label: "Trunk", isSelected: false, isCaptured: false),
                        .init(id: .leaf, label: "Leaf close-up", isSelected: false, isCaptured: true),
                    ])
                    .padding(.horizontal, VisitMetrics.Camera.trayPadding)
                    Spacer()
                }
                .background(Color.black)
            }
        }
    }

    /// What the well does to a portrait photograph — #113. A synthetic 3:4 frame with a grid on it,
    /// so a crop or a letterbox is unmistakable.
    @Test("shoot a portrait frame in the add-tree well")
    func shootWell() async {
        let portrait = Self.portraitTestImage()
        await Self.shoot("well-portrait", .large) {
            VStack(spacing: 12) {
                Text("well as built").font(.caption)
                RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                    .fill(CypressColor.surfaceEmptyThumb)
                    .aspectRatio(VisitMetrics.AddTree.wellAspectRatio, contentMode: .fit)
                    .overlay { PhotoFit(image: portrait) }
                    .clipShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
                Spacer()
            }
            .padding(.horizontal, CypressSpacing.gutter)
            .background(CypressColor.surfaceScreen)
        }
    }

    /// Screen 04 over a **curated deciduous** species — the state that offers the whole phenology
    /// vocabulary. `VisitPhenologyVocabulary` says the row is offered "for the curated 40 and nobody
    /// else", and London Plane is both curated and the commonest street tree in San Francisco.
    static let londonPlane = try! Species(
        scientificName: "Platanus × acerifolia",
        commonName: "London Plane",
        family: "Platanaceae",
        leafRetention: .deciduous,
        seasonal: SeasonalCalendar(
            bloomMonths: [4, 5],
            fallColorMonths: [10, 11],
            fruitMonths: [9, 10],
            newGrowthMonths: [3, 4]
        ),
        curated: true
    )

    @MainActor
    static func cameraOverPlane() -> VisitCameraView {
        var api = VisitPreviewAPI()
        api.profile = TreeProfile(tree: VisitPreviewFixtures.cypress, species: londonPlane)
        return VisitCameraView(
            treeID: VisitPreviewFixtures.cypress.id,
            treeDisplayName: "London Plane",
            gpsAccuracyM: 9,
            api: api,
            outbox: VisitPreviewFixtures.outbox(),
            attribution: VisitPreviewFixtures.attribution,
            onSaved: { _ in },
            onClose: {}
        )
    }

    @Test("shoot screen 04 with a full phenology row")
    func shootPhenology() async {
        await Self.shoot("s04-phenology-large", .large) { Self.cameraOverPlane() }
        await Self.shoot("s04-phenology-xxxl", .xxxLarge) { Self.cameraOverPlane() }
    }

    /// A 3:4 portrait frame with a numbered grid — a crop shows as missing rows, a letterbox as bars.
    static func portraitTestImage() -> UIImage {
        let size = CGSize(width: 300, height: 400)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            for row in 0..<8 {
                let y = CGFloat(row) * 50
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                path.lineWidth = 2
                path.stroke()
                ("\(row)" as NSString).draw(
                    at: CGPoint(x: 8, y: y + 6),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28), .foregroundColor: UIColor.black]
                )
            }
        }
    }
}
#endif
