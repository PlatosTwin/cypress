//
//  CypressGradient.swift
//  Cypress — DesignSystem/Tokens
//
//  Source of truth: docs/distilled/SCREENS.md §2 — C2 (`HeroPhotoHeader`), C22
//  (`ThumbnailGradient`), C29 (`SpeciesTile`), plus the per-screen gradient stacks on 03, 04, 07,
//  08, 13, 19 and D1/D2.
//
//  §2's preamble is explicit: "All imagery is a CSS gradient placeholder. Gradients are transcribed
//  exactly so you can either reproduce them as SwiftUI `Gradient`s for the placeholder build or
//  swap in real photography." This file is that transcription — every stop is a token, so no
//  component file contains an image hex.
//
//  ── CSS → SwiftUI conversion ──────────────────────────────────────────────────────────────
//  `radial-gradient(circle at X% Y%, C 0%, transparent N%)` with no size keyword defaults to
//  `farthest-corner`: the gradient ray runs from the centre point to the corner furthest from it,
//  and N% is a percentage of *that* length. `CypressRadialStop` stores X, Y and N as fractions and
//  `CypressGradientField` resolves the pixel radius per layout, so a recipe is size-independent.
//
//  `transparent` is transcribed as `color.opacity(0)` rather than `Color.clear`. They are the same
//  colour in CSS, but SwiftUI interpolates toward `Color.clear`'s black, which greys the falloff.
//

import SwiftUI

// MARK: - Recipe types

/// One `radial-gradient(circle at x% y%, color 0%, transparent extent%)` layer.
struct CypressRadialStop {
    /// Centre, as a fraction of the box width.
    let x: Double
    /// Centre, as a fraction of the box height.
    let y: Double
    let color: Color
    /// The `transparent N%` stop, as a fraction of the farthest-corner distance.
    let extent: Double

    init(_ x: Double, _ y: Double, _ color: Color, _ extent: Double) {
        self.x = x
        self.y = y
        self.color = color
        self.extent = extent
    }
}

/// A layered image placeholder: radial layers over a linear base, back to front.
struct CypressGradientRecipe {
    let base: LinearGradient
    let radials: [CypressRadialStop]

    init(base: LinearGradient, radials: [CypressRadialStop] = []) {
        self.base = base
        self.radials = radials
    }
}

/// Renders a `CypressGradientRecipe`. Resolution-independent: the radial radii are derived from
/// the laid-out size, exactly as CSS `farthest-corner` does.
struct CypressGradientField: View {
    let recipe: CypressGradientRecipe

    init(_ recipe: CypressGradientRecipe) {
        self.recipe = recipe
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                recipe.base
                ForEach(Array(recipe.radials.enumerated()), id: \.offset) { _, stop in
                    RadialGradient(
                        gradient: Gradient(colors: [stop.color, stop.color.opacity(0)]),
                        center: UnitPoint(x: stop.x, y: stop.y),
                        startRadius: 0,
                        endRadius: max(1, stop.extent * Self.farthestCorner(from: stop, in: size))
                    )
                }
            }
        }
    }

    /// CSS `farthest-corner`: the distance from the gradient centre to the furthest box corner.
    static func farthestCorner(from stop: CypressRadialStop, in size: CGSize) -> CGFloat {
        let cx = stop.x * size.width
        let cy = stop.y * size.height
        let corners: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        return corners.map { hypot($0.x - cx, $0.y - cy) }.max() ?? 0
    }
}

// MARK: - Tokens

enum CypressGradient {

    /// `linear-gradient(<deg>, …)` with explicit stop positions.
    static func linear(_ degrees: Double, _ stops: [(UInt32, Double)]) -> LinearGradient {
        let points = CypressColor.cssGradientPoints(degrees)
        return LinearGradient(
            gradient: Gradient(stops: stops.map {
                Gradient.Stop(color: Color(cypressHex: $0.0), location: $0.1)
            }),
            startPoint: points.start,
            endPoint: points.end
        )
    }

    /// `linear-gradient(<deg>, A, B)`.
    static func linear(_ degrees: Double, _ a: UInt32, _ b: UInt32) -> LinearGradient {
        linear(degrees, [(a, 0), (b, 1)])
    }

    private static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(cypressHex: value, alpha: alpha)
    }

    /// A recipe that is *only* radial layers — the 04 ghost overlay sits on top of the viewfinder
    /// and must not paint a base of its own.
    static let transparentBase = LinearGradient(
        colors: [.clear, .clear], startPoint: .top, endPoint: .bottom
    )

    // MARK: - C2 · Hero photo headers

    /// 03 tree profile hero.
    static let heroProfile = CypressGradientRecipe(
        base: linear(180, [(0xEAF0E2, 0), (0xCFE0D2, 0.55), (0x9DBFA6, 1)]),
        radials: [
            CypressRadialStop(0.28, 0.46, hex(0x4E8F6A), 0.36),
            CypressRadialStop(0.54, 0.32, hex(0x35704F), 0.42),
            CypressRadialStop(0.74, 0.50, hex(0x24513B), 0.40),
            CypressRadialStop(0.44, 0.58, hex(0x2F6B4F), 0.38),
        ]
    )

    /// 07 species page hero.
    static let heroSpecies = CypressGradientRecipe(
        base: linear(180, [(0xEAF0E2, 0), (0xCBDCCE, 0.60), (0x96BAA1, 1)]),
        radials: [
            CypressRadialStop(0.30, 0.48, hex(0x4E8F6A), 0.38),
            CypressRadialStop(0.58, 0.34, hex(0x35704F), 0.44),
            CypressRadialStop(0.76, 0.52, hex(0x24513B), 0.42),
        ]
    )

    /// 19 memorial hero — the desaturated set.
    static let heroMemorial = CypressGradientRecipe(
        base: linear(180, [(0xEDEEE6, 0), (0xD6D9CC, 0.60), (0xB4BAA9, 1)]),
        radials: [
            CypressRadialStop(0.30, 0.46, hex(0x9AA58E), 0.38),
            CypressRadialStop(0.58, 0.34, hex(0x8A9483), 0.44),
        ]
    )

    /// D2 tree profile hero, dark.
    static let heroProfileDark = CypressGradientRecipe(
        base: linear(180, [(0x22301F, 0), (0x182417, 0.55), (0x111A11, 1)]),
        radials: [
            CypressRadialStop(0.28, 0.46, hex(0x4E8F6A, 0.55), 0.36),
            CypressRadialStop(0.54, 0.32, hex(0x35704F, 0.60), 0.42),
            CypressRadialStop(0.74, 0.50, hex(0x24513B, 0.65), 0.40),
        ]
    )

    /// C2 scrim — `linear-gradient(180deg, rgba(16,32,22,0) 48%, rgba(16,32,22,.5) 100%)` and its
    /// three siblings. Drawn over the hero, under the chrome.
    enum Scrim {
        /// 03 — `rgba(16,32,22,0) 48% → .5`.
        static let profile = scrim(0x102016, from: 0.48, to: 0.50)
        /// 07 — `rgba(16,32,22,0) 42% → .56`.
        static let species = scrim(0x102016, from: 0.42, to: 0.56)
        /// 19 — `rgba(30,34,28,0) 46% → .5`.
        static let memorial = scrim(0x1E221C, from: 0.46, to: 0.50)
        /// D2 — `rgba(8,14,10,0) 48% → .62`.
        static let dark = scrim(0x080E0A, from: 0.48, to: 0.62)

        private static func scrim(_ value: UInt32, from: Double, to: Double) -> LinearGradient {
            let points = CypressColor.cssGradientPoints(180)
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(cypressHex: value, alpha: 0), location: from),
                    .init(color: Color(cypressHex: value, alpha: to), location: 1),
                ]),
                startPoint: points.start,
                endPoint: points.end
            )
        }
    }

    // MARK: - C22 · ThumbnailGradient

    /// The four canonical species thumbnails of §2 C22, plus the D1 dark ginkgo card thumb.
    enum Thumbnail: String, CaseIterable, Identifiable {
        case cypress
        case ginkgo
        case londonPlane
        case victorianBox
        /// D1 tree card thumb — the ginkgo set re-mixed for the dark map.
        case ginkgoDark

        var id: String { rawValue }

        /// Display name, for the gallery.
        var name: String {
            switch self {
            case .cypress: return "Cypress"
            case .ginkgo: return "Ginkgo"
            case .londonPlane: return "London Plane"
            case .victorianBox: return "Victorian Box"
            case .ginkgoDark: return "Ginkgo (D1 dark)"
            }
        }

        var recipe: CypressGradientRecipe {
            switch self {
            case .cypress:
                return CypressGradientRecipe(
                    base: CypressGradient.linear(170, 0xE4EBD8, 0xB9CDBC),
                    radials: [
                        CypressRadialStop(0.32, 0.40, CypressGradient.hex(0x4E8F6A), 0.44),
                        CypressRadialStop(0.66, 0.32, CypressGradient.hex(0x35704F), 0.48),
                        CypressRadialStop(0.52, 0.60, CypressGradient.hex(0x24513B), 0.54),
                    ]
                )
            case .ginkgo:
                return CypressGradientRecipe(
                    base: CypressGradient.linear(170, 0xEAEFDC, 0xC4D2B2),
                    radials: [
                        CypressRadialStop(0.34, 0.36, CypressGradient.hex(0xC9B44A), 0.42),
                        CypressRadialStop(0.64, 0.30, CypressGradient.hex(0x8A9A3F), 0.46),
                        CypressRadialStop(0.50, 0.58, CypressGradient.hex(0x5E7D3A), 0.52),
                    ]
                )
            case .londonPlane:
                return CypressGradientRecipe(
                    base: CypressGradient.linear(170, 0xEFEDDC, 0xCFD3B4),
                    radials: [
                        CypressRadialStop(0.36, 0.38, CypressGradient.hex(0xB9A268), 0.44),
                        CypressRadialStop(0.62, 0.32, CypressGradient.hex(0x7C8A4E), 0.48),
                        CypressRadialStop(0.50, 0.60, CypressGradient.hex(0x5C6B3A), 0.52),
                    ]
                )
            case .victorianBox:
                return CypressGradientRecipe(
                    base: CypressGradient.linear(170, 0xE6EEDE, 0xBFD4BE),
                    radials: [
                        CypressRadialStop(0.36, 0.36, CypressGradient.hex(0x6FB380), 0.44),
                        CypressRadialStop(0.62, 0.34, CypressGradient.hex(0x3E8E5C), 0.48),
                        CypressRadialStop(0.50, 0.60, CypressGradient.hex(0x2C6B45), 0.52),
                    ]
                )
            case .ginkgoDark:
                return CypressGradientRecipe(
                    base: CypressGradient.linear(170, 0x2A331F, 0x1A2313),
                    radials: [
                        CypressRadialStop(0.34, 0.36, CypressGradient.hex(0x9B8A38), 0.42),
                        CypressRadialStop(0.64, 0.30, CypressGradient.hex(0x5E7030), 0.46),
                    ]
                )
            }
        }
    }

    // MARK: - C9 · Activity thumbnails

    /// 03 visit thumb — `radial(40% 40%, #4E8F6A 0→50%)` over `linear-gradient(170deg,#DCE5D2,#A9C4AE)`.
    static let activityVisit = CypressGradientRecipe(
        base: linear(170, 0xDCE5D2, 0xA9C4AE),
        radials: [CypressRadialStop(0.40, 0.40, hex(0x4E8F6A), 0.50)]
    )

    /// D2 visit thumb — `radial(40% 40%, rgba(78,143,106,.6) 0→50%)` over `#1F2E22`.
    static let activityVisitDark = CypressGradientRecipe(
        base: linear(170, 0x1F2E22, 0x1F2E22),
        radials: [CypressRadialStop(0.40, 0.40, hex(0x4E8F6A, 0.6), 0.50)]
    )

    /// 19 first-photo thumb.
    static let activityFirstPhoto = CypressGradientRecipe(
        base: linear(170, 0xE8E9DE, 0xC9CDBB),
        radials: [CypressRadialStop(0.42, 0.44, hex(0x9FB582), 0.52)]
    )

    /// 19 bloom-visit thumb.
    static let activityBloom = CypressGradientRecipe(
        base: linear(170, 0xE3E5D9, 0xC2C7B4),
        radials: [CypressRadialStop(0.40, 0.40, hex(0xC0523E), 0.50)]
    )

    // MARK: - C29 · SpeciesTile backgrounds

    /// The nine tiles drawn on 08, in grid order. `nil` radials mark the locked tiles.
    enum SpeciesTileArt: String, CaseIterable, Identifiable {
        case montereyCypress
        case ginkgo
        case londonPlane
        case victorianBox
        case redFloweringGum
        case pohutukawa
        case brisbaneBox

        var id: String { rawValue }

        /// Label verbatim from screen 08.
        var label: String {
            switch self {
            case .montereyCypress: return "Monterey Cypress"
            case .ginkgo: return "Ginkgo"
            case .londonPlane: return "London Plane"
            case .victorianBox: return "Victorian Box"
            case .redFloweringGum: return "Red Flowering Gum"
            case .pohutukawa: return "Pōhutukawa"
            case .brisbaneBox: return "Brisbane Box"
            }
        }

        /// `radial(40% 34%, A 0→46%)`, `radial(62% 52%, B 0→52%)`, `linear-gradient(180deg, C, D)`.
        private var stops: (UInt32, UInt32, UInt32, UInt32) {
            switch self {
            case .montereyCypress: return (0x4E8F6A, 0x24513B, 0x5B8A6C, 0x1D4634)
            case .ginkgo: return (0xC9B44A, 0x5E7D3A, 0x98A44F, 0x4E6030)
            case .londonPlane: return (0xB9A268, 0x5C6B3A, 0x8D9459, 0x4C5530)
            case .victorianBox: return (0x6FB380, 0x2C6B45, 0x5A9A6F, 0x245239)
            case .redFloweringGum: return (0xC0523E, 0x356B4A, 0x67885F, 0x2C4A34)
            case .pohutukawa: return (0xB33A4A, 0x2C5340, 0x5E7E62, 0x233F2F)
            case .brisbaneBox: return (0xD9CDA8, 0x4A7D55, 0x7E9B72, 0x3A5B3E)
            }
        }

        var recipe: CypressGradientRecipe {
            let (a, b, c, d) = stops
            return CypressGradientRecipe(
                base: CypressGradient.linear(180, c, d),
                radials: [
                    CypressRadialStop(0.40, 0.34, CypressGradient.hex(a), 0.46),
                    CypressRadialStop(0.62, 0.52, CypressGradient.hex(b), 0.52),
                ]
            )
        }
    }

    // MARK: - 04 · Camera viewfinder

    /// 04 viewfinder base.
    static let cameraViewfinder = CypressGradientRecipe(
        base: linear(180, 0x26332A, 0x131B14),
        radials: [
            CypressRadialStop(0.34, 0.44, hex(0x4E8F6A, 0.50), 0.40),
            CypressRadialStop(0.62, 0.34, hex(0x35704F, 0.55), 0.46),
            CypressRadialStop(0.50, 0.62, hex(0x24513B, 0.60), 0.50),
        ]
    )

    /// 04 ghost overlay of the previous photo — the 30 %-opacity alignment layer.
    static let cameraGhost = CypressGradientRecipe(
        base: transparentBase,
        radials: [
            CypressRadialStop(0.36, 0.40, hex(0xD6E5D0, 0.16), 0.34),
            CypressRadialStop(0.58, 0.32, hex(0xD6E5D0, 0.13), 0.38),
            CypressRadialStop(0.48, 0.58, hex(0xD6E5D0, 0.12), 0.42),
        ]
    )

    // MARK: - 13 · "Same week, other years" photo strip

    static let photoStrip2024 = CypressGradientRecipe(
        base: linear(175, 0xE8EDDB, 0xC5D2B8),
        radials: [CypressRadialStop(0.40, 0.44, hex(0x8FB573), 0.55)]
    )
    static let photoStrip2025 = CypressGradientRecipe(
        base: linear(175, 0xE3E8DC, 0xBFC9BA),
        radials: [CypressRadialStop(0.55, 0.40, hex(0x7FA284), 0.55)]
    )
    static let photoStripThisWeek = CypressGradientRecipe(
        base: linear(175, 0xDFE8D6, 0xAFC4AC),
        radials: [CypressRadialStop(0.45, 0.42, hex(0x4E8F6A), 0.52)]
    )
}
