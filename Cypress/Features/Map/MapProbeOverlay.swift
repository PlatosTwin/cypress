//
//  MapProbeOverlay.swift
//  Cypress — Features/Map
//
//  ── The instrument the owner can read ────────────────────────────────────────────────────────
//  Screen 01's frame health has been measured twice now, both times on a simulator, and both times
//  the simulator was named as a limit in the write-up and believed anyway. The second time the owner
//  installed the result on their own iPhone and reported the map still slow, which is the only
//  measurement in this project that has ever come from the hardware anybody actually uses.
//
//  `MapFrameProbe` had the numbers all along and printed them to stdout. A person holding a phone
//  has no stdout. So this draws the same window in the corner of the map: rolling fps, the worst
//  frame in the last second, what is on screen, and the three counters that tell the causes apart.
//  It turns "it feels slow" into "worst 180 ms, body 41" — a sentence somebody can send us.
//
//  ── Why it cannot ship ───────────────────────────────────────────────────────────────────────
//  The whole file is `#if DEBUG`, as is its call site in `MapHomeView`, which is exactly how
//  `DebugDeepLink` is kept out of Release (ERRATA E117). On top of that it draws nothing at all
//  unless `CYPRESS_MAP_PROBE=1` is in the environment, so even a Debug build a tester is holding is
//  the normal map until somebody arms it. Two gates, one of which the compiler enforces.
//
//  ── Why it is drawn the way it is ────────────────────────────────────────────────────────────
//  It is deliberately ugly and deliberately small. A debug readout that looks like part of the app
//  is a readout somebody will eventually screenshot into a design review. It is also
//  `allowsHitTesting(false)` and outside the accessibility tree: the screen it sits on has a
//  VoiceOver reading-order suite (`AccessibilityTreeTests`) and an instrument must not be a
//  participant in what it measures.
//

#if DEBUG
import SwiftUI

/// The corner readout. One line of frame health, one of what is on screen, one of causes.
struct MapProbeOverlay: View {

    /// The probe publishes a new snapshot once a second; this view is the only reader.
    var probe: MapFrameProbe = .shared

    var body: some View {
        let snapshot = probe.snapshot
        VStack(alignment: .trailing, spacing: MapProbeLayout.lineGap) {
            Text(String(format: "%.0f fps · worst %.0f ms", snapshot.fps, snapshot.worstMS))
                .foregroundStyle(snapshot.isSmooth ? CypressColor.Dark.textPrimary : CypressColor.Dark.accentAmber)
            Text("z\(snapshot.zoom) · \(snapshot.markers) markers")
                .foregroundStyle(CypressColor.Dark.textSecondary)
            // The three counters, per second. `gps` is how often the location provider republished,
            // `body` how often the basemap re-evaluated, `fetch` how many viewport reads landed.
            // A `body` far above `fetch` is the annotation layer being rebuilt for nothing, which is
            // the defect this readout was built to make visible from the outside.
            Text("gps \(snapshot.gpsPerSecond) · body \(snapshot.bodyPerSecond) · fetch \(snapshot.fetchPerSecond)")
                .foregroundStyle(CypressColor.Dark.textSecondary)
        }
        .font(CypressFont.mono11)
        .padding(.horizontal, MapProbeLayout.paddingH)
        .padding(.vertical, MapProbeLayout.paddingV)
        .background(
            RoundedRectangle(cornerRadius: CypressRadius.badge, style: .continuous)
                .fill(CypressColor.Dark.surfaceCard.opacity(MapProbeLayout.scrimOpacity))
        )
        // An instrument must not be a participant. It cannot be tapped, and VoiceOver — which this
        // screen has a reading-order suite over — never sees it.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The four numbers this overlay needs that no component owns. Colours, fonts and radii are tokens
/// (ARCHITECTURE §6); these are the geometry of a corner badge that is not in any mock because it
/// is not part of the product.
enum MapProbeLayout {
    static let lineGap: CGFloat = 1
    static let paddingH: CGFloat = CypressSpacing.gapRows
    static let paddingV: CGFloat = CypressSpacing.gapVitality
    /// Legible over both the parchment wash and a dark basemap, without hiding the map under it.
    static let scrimOpacity: Double = 0.86
    /// Clear of the filter chips, which end around 126 pt below the safe area on the widest phone.
    static let topOffset: CGFloat = 96
}
#endif
