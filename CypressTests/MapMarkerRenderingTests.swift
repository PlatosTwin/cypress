import Foundation
import MapKit
import Testing
import UIKit
@testable import Cypress

/// **The markers, now that MapKit draws them instead of SwiftUI.**
///
/// Screen 01's pins moved from a SwiftUI `Annotation` per marker to recycled `MKAnnotationView`s
/// carrying a bitmap of the same C19 component. That swap has two failure modes a frame counter
/// cannot see and a screenshot would not obviously catch:
///
/// 1. **A pin kind that renders to nothing.** `ImageRenderer` returns an optional and a `nil` there
///    is an invisible marker, not a crash — the map would simply stop showing vacant sites, or
///    memorials, and look plausible while doing it.
/// 2. **A pin the diff cannot tell apart.** The layer adds and removes only what changed, keyed by
///    id, and a tree whose *kind* changes under a stable id — a lead confirming a removal turns a
///    green pin grey without moving it — has to be noticed by that comparison.
@MainActor
@Suite("Map marker rendering")
struct MapMarkerRenderingTests {

    /// Every kind the map can put on screen. The route pins belong to screen 18 and go through the
    /// same cache, so they are here too.
    private static let everyKind: [MapPin.Kind] = [
        .cityTree, .needsCare, .community, .removed, .vacantSite,
        .cluster(count: 3, large: false), .cluster(count: 42, large: true),
        .gps, .routeDone, .routeActive,
    ]

    @Test("every pin kind rasterises to a visible image in both appearances")
    func everyKindRenders() {
        for kind in Self.everyKind {
            for isDark in [false, true] {
                let image = MapPinImage.image(for: kind, isDark: isDark)
                #expect(
                    image != nil,
                    "\(kind) rendered no image in \(isDark ? "dark" : "light") — that marker is invisible on the map"
                )
                guard let rendered = image else { continue }
                // A pin is 16–18 pt and a cluster badge 30–32, plus the shadow padding on each side.
                // Anything smaller than the padding alone means the component drew nothing at all.
                #expect(
                    rendered.size.width > MapPinImage.shadowPadding * 2,
                    "\(kind) rendered a \(rendered.size) image — that is the padding and no pin"
                )
                #expect(rendered.size.height > MapPinImage.shadowPadding * 2)
            }
        }
        MapPinImage.flush()
    }

    /// The cache is what makes 280 markers cost a handful of bitmaps. If it ever stopped hitting,
    /// the map would rasterise a SwiftUI view per marker per pass, which is worse than what this
    /// replaced.
    @Test("the same kind is rendered once and reused")
    func theCacheIsUsed() {
        MapPinImage.flush()
        let first = MapPinImage.image(for: .cityTree, isDark: false)
        let second = MapPinImage.image(for: .cityTree, isDark: false)
        #expect(first != nil)
        #expect(first === second, "the second ask rendered a fresh image instead of reusing the first")
        MapPinImage.flush()
    }

    /// Light and dark are different pictures: `CypressColor.pinRingStroke` is white in light and
    /// `#0E1712` in dark, so a cache that ignored the appearance would draw a white ring on a dark
    /// basemap for the life of the process.
    @Test("light and dark are cached apart")
    func appearancesDoNotShareAnImage() {
        MapPinImage.flush()
        let light = MapPinImage.image(for: .cityTree, isDark: false)
        let dark = MapPinImage.image(for: .cityTree, isDark: true)
        #expect(light !== dark)
        MapPinImage.flush()
    }

    /// The annotation carries the kind it was built with, which is what the diff compares. Pinned
    /// here because the comparison in `sync(clusters:pins:on:)` is only as good as this mapping:
    /// a `TreePinAnnotation` that computed its kind lazily, or from something other than
    /// `MapPinKind.kind(for:)`, would let a status change go undrawn.
    @Test("an annotation's kind is the pin's kind, so a status change is a different marker")
    func annotationKindTracksStatus() {
        let id = UUID()
        func pin(_ status: TreeStatus) -> TreePin {
            TreePin(
                id: id,
                coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
                status: status,
                source: .cityImport,
                verificationState: .cityRecord,
                speciesID: nil
            )
        }
        let alive = TreePinAnnotation(pin: pin(.alive))
        let removed = TreePinAnnotation(pin: pin(.removed))
        #expect(alive.kind == .cityTree)
        #expect(removed.kind == .removed)
        #expect(
            alive.kind != removed.kind,
            "the same tree alive and removed produced the same marker kind, so the diff cannot notice"
        )
    }

    /// A cluster badge's identity is the absolute-grid cell (`TreeCluster.id`), which is what keeps
    /// the badge from re-keying on every pan (ERRATA E130). The annotation must not invent one.
    @Test("a cluster annotation keeps the grid's own id")
    func clusterKeepsItsGridID() {
        let cluster = TreeCluster(
            id: "16:171234:57891",
            coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
            count: 12
        )
        let annotation = TreeClusterAnnotation(cluster: cluster)
        #expect(annotation.cluster.id == "16:171234:57891")
        #expect(annotation.kind == .cluster(count: 12, large: true))
    }

    /// The marker view keeps the app's 44 pt tap target even though the drawn pin is 16–18 pt.
    /// `MKAnnotationView` sizes itself to its image, so without the override the map would be the
    /// one screen in the app that does not meet ARCHITECTURE §6.
    @Test("a marker's tap target is the app's 44 pt, not the drawn pin's 18")
    func markerKeepsTheHitTarget() {
        let view = MapMarkerView(
            annotation: TreePinAnnotation(pin: TreePin(
                id: UUID(),
                coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
                status: .alive,
                source: .cityImport,
                verificationState: .cityRecord,
                speciesID: nil
            )),
            reuseIdentifier: MapMarkerView.reuseIdentifier
        )
        view.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
        // 20 pt out from the centre of an 18 pt pin: outside the drawn dot, inside the 44 pt target.
        #expect(view.point(inside: CGPoint(x: 9, y: -11), with: nil))
        // And well outside it.
        #expect(!view.point(inside: CGPoint(x: 9, y: -40), with: nil))
    }
}
