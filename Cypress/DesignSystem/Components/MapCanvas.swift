//
//  MapCanvas.swift
//  Cypress — DesignSystem/Components
//
//  C18 · `MapCanvas` — SCREENS.md §2 (01, D1, and the reduced version on 15/18).
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  THE SEAM
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  The mocks draw a stylised abstract SF street grid. **We ship MapKit** (ARCHITECTURE §1): the
//  abstract grid is a placeholder, not the product.
//
//  So `MapCanvas` is two things stacked, and only one of them is real:
//
//      MapCanvas(basemap: { … }) { overlay }
//                 ▲                  ▲
//                 │                  └── OURS, permanently: pins, clusters, GPS dot, labels,
//                 │                      search bar, filter chips — everything in `CypressColor`.
//                 └── REPLACEABLE: today `StylizedBasemap` (the mock's grid). Tomorrow a
//                     `Map { }` from MapKit, or a MapLibre `UIViewRepresentable` if the abstract
//                     basemap ever becomes a hard requirement.
//
//  Nothing in this file imports MapKit and nothing here knows about coordinates. Wiring the real
//  basemap means passing a different `basemap:` view and giving the overlay real screen positions;
//  no styling moves. That is the next agent's job.
//  ══════════════════════════════════════════════════════════════════════════════════════════
//

import SwiftUI

struct MapCanvas<Basemap: View, Overlay: View>: View {
    @ViewBuilder var basemap: Basemap
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            basemap
            overlay
        }
        .background(CypressColor.surfaceMapPaper)
        .clipped()
    }
}

extension MapCanvas where Basemap == StylizedBasemap {
    /// The placeholder canvas: the mock's abstract SF grid behind your overlay.
    init(@ViewBuilder overlay: () -> Overlay) {
        self.init(basemap: { StylizedBasemap() }, overlay: overlay)
    }

    /// The reduced version on 15 and 18 — grid at 70 % opacity, no ocean, park or street bands.
    static func reduced(@ViewBuilder overlay: () -> Overlay) -> MapCanvas<StylizedBasemap, Overlay> {
        MapCanvas<StylizedBasemap, Overlay>(
            basemap: { StylizedBasemap(detail: .reduced) },
            overlay: overlay
        )
    }
}

// MARK: - The replaceable backdrop

/// The mock's abstract San Francisco: paper ground, street grid, ocean band, beach strip, Golden
/// Gate Park, two named street bands and their rotated mono labels.
///
/// **This is the placeholder half of the seam.** It renders every value from §2 C18 so the styling
/// is verifiable today, and it is the thing MapKit replaces. It draws in fractions of its own
/// bounds, so it fills whatever it is given.
struct StylizedBasemap: View {

    enum Detail {
        /// 01, D1 — the full canvas.
        case full
        /// 15, 18 — grid only, `opacity:.7`.
        case reduced
    }

    var detail: Detail = .full
    /// The five rotated labels of §2. Off for the reduced canvas.
    var showsLabels: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                CypressColor.surfaceMapPaper

                streetGrid(in: size)
                    .opacity(detail == .reduced ? 0.7 : 1)

                if detail == .full {
                    ocean(in: size)
                    beach(in: size)
                    park(in: size)
                    streetBands(in: size)
                    if showsLabels { labels(in: size) }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    // MARK: Grid

    /// `repeating-linear-gradient(90deg, transparent 0 58px, grid 58px 64px)` and its 66/72 sibling.
    private func streetGrid(in size: CGSize) -> some View {
        let stepX = CypressSpacing.Component.mapGridStepX
        let lineX = CypressSpacing.Component.mapGridLineX
        let stepY = CypressSpacing.Component.mapGridStepY
        let lineY = CypressSpacing.Component.mapGridLineY
        return ZStack(alignment: .topLeading) {
            ForEach(0..<Int(ceil(size.width / stepX)) + 1, id: \.self) { index in
                Rectangle()
                    .fill(CypressColor.surfaceMapGrid)
                    .frame(width: lineX, height: size.height)
                    .offset(x: CGFloat(index) * stepX + (stepX - lineX))
            }
            ForEach(0..<Int(ceil(size.height / stepY)) + 1, id: \.self) { index in
                Rectangle()
                    .fill(CypressColor.surfaceMapGrid)
                    .frame(width: size.width, height: lineY)
                    .offset(y: CGFloat(index) * stepY + (stepY - lineY))
            }
        }
    }

    // MARK: Water and park

    private func ocean(in size: CGSize) -> some View {
        LinearGradient(
            colors: [CypressColor.mapOceanStart, CypressColor.mapOceanEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: size.width * CypressSpacing.Component.mapOceanFraction, height: size.height)
    }

    private func beach(in size: CGSize) -> some View {
        Rectangle()
            .fill(CypressColor.mapBeach)
            .frame(width: CypressSpacing.Component.mapBeachWidth, height: size.height)
            .offset(x: size.width * CypressSpacing.Component.mapOceanFraction)
    }

    private func park(in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: CypressRadius.mapPark, style: .continuous)
            .fill(CypressColor.mapPark)
            .overlay {
                RoundedRectangle(cornerRadius: CypressRadius.mapPark, style: .continuous)
                    .strokeBorder(
                        CypressColor.mapParkRing,
                        lineWidth: CypressSpacing.Component.mapParkRingWidth
                    )
            }
            .frame(
                width: size.width * CypressSpacing.Component.mapParkWidthFraction,
                height: size.height * CypressSpacing.Component.mapParkHeightFraction
            )
            .offset(
                x: size.width * CypressSpacing.Component.mapParkLeftFraction,
                y: size.height * CypressSpacing.Component.mapParkTopFraction
            )
    }

    /// Full-width 9pt bands with a 1pt ring, at `top:46%` and `top:72%`.
    private func streetBands(in size: CGSize) -> some View {
        ForEach([0.46, 0.72], id: \.self) { fraction in
            Rectangle()
                .fill(CypressColor.surfaceMapStreetBand)
                .overlay {
                    Rectangle().strokeBorder(
                        CypressColor.mapStreetBandRing,
                        lineWidth: CypressSpacing.Component.hairline
                    )
                }
                .frame(
                    width: size.width * (1 - CypressSpacing.Component.mapOceanFraction),
                    height: CypressSpacing.Component.mapStreetBandHeight
                )
                .offset(
                    x: size.width * CypressSpacing.Component.mapOceanFraction,
                    y: size.height * fraction
                )
        }
    }

    // MARK: Labels

    private func labels(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Text("OCEAN BEACH")
                .cypressMapLabel(color: CypressColor.textMapLabelOcean, wide: true)
                .rotationEffect(.degrees(90), anchor: .topLeading)
                .offset(x: size.width * 0.015, y: size.height * 0.42)
            Text("GOLDEN GATE PARK")
                .cypressMapLabel(color: CypressColor.textMapLabelPark)
                .offset(x: size.width * 0.40, y: size.height * 0.13)
            Text("JUDAH ST")
                .cypressMapLabel(color: CypressColor.textMapLabelStreet)
                .offset(x: size.width * 0.20, y: size.height * 0.436)
            Text("NORIEGA ST")
                .cypressMapLabel(color: CypressColor.textMapLabelStreet)
                .offset(x: size.width * 0.52, y: size.height * 0.696)
            Text("48TH AVE")
                .cypressMapLabel(color: CypressColor.textMapLabelStreet)
                .rotationEffect(.degrees(90))
                .offset(x: size.width * 0.84, y: size.height * 0.33)
        }
    }
}
