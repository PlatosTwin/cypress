import SwiftUI
import Testing
@testable import Cypress

/// **The bar screen 01's tree card draws where the name will be, and the type ramp it has to ride.**
///
/// ── The report ────────────────────────────────────────────────────────────────────────────────
/// `MapLayout.cardTitlePlaceholderHeight` was a fixed `21`, documented as "`CypressFont
/// .listNameSerif`'s drawn line (17.5pt serif), so the row is the height it will be once the name
/// arrives". Both halves were wrong (PR #102 review). The 17.5 pt face draws **23.99 pt** of line
/// unscaled and **24.68 pt** at the default content size — 21 is `17.5 × 1.2`, a guess at a line
/// height rather than a measurement of one. And the title is `relativeTo: .headline`, so it grows
/// with Dynamic Type while the bar did not: at AX5 the title's line is **67.18 pt** against the
/// bar's 21.
///
/// ── What is asserted, and why not a table of points ───────────────────────────────────────────
/// The property that matters is not "the bar is 24.68 pt at `.large`" — that is a number that moves
/// the day anyone touches the face or its `relativeTo:`, and a test pinning it would then be
/// asserting the font's metrics back at itself. What matters is that **the bar is one line of the
/// title's own font, at whatever size the reader is running**. So both are measured, at both ends of
/// the ramp, and compared to each other.
///
/// That is also what makes this red-provable in the direction of the defect: against the old fixed
/// `21` the two disagree by 3.68 pt at `.large` and by 46.18 pt at AX5.
@Suite("The map card's title placeholder rides the title's own type ramp")
@MainActor
struct MapCardPlaceholderTests {

    /// The ends of the ramp, plus the two rungs the reviewer measured, so a failure says *where* the
    /// scaling came apart rather than only that it did.
    private static let ramp: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility5]

    /// One line of the real title, drawn in the real font, measured the way `AX5ReflowTests` measures
    /// everything else on this screen.
    ///
    /// `.lineLimit(1)` and a short name, because the comparison is against *one* line — the bar has
    /// never claimed to stand in for the second line `MapTreeCard` allows at accessibility sizes,
    /// and this suite's own doc says so.
    private static func titleLineHeight(at size: DynamicTypeSize) async -> CGFloat {
        await AX5ReflowTests.ax5Size(
            of: Text("Coast Live Oak")
                .font(CypressFont.listNameSerif)
                .lineLimit(1),
            size: size
        ).height
    }

    /// **The bar is one line of the title, at every size on the ramp.**
    ///
    /// A tolerance rather than equality: the card's row is laid out beside a thumbnail and rounds to
    /// the point grid, and the claim is "the same line", not "the same float". 1.5 pt is far tighter
    /// than the 3.68 pt the old constant was out by at the *smallest* size on this list.
    @Test("the title placeholder is one line of listNameSerif at every size on the ramp")
    func thePlaceholderMatchesTheTitlesLine() async {
        for size in Self.ramp {
            let line = await Self.titleLineHeight(at: size)
            // The metric the card itself declares, resolved through the same environment.
            let bar = ScaledMetricProbe.height(
                base: MapLayout.cardTitlePlaceholderHeight, at: size
            )
            #expect(
                abs(bar - line) <= 1.5,
                """
                at \(size) the title placeholder measures \(bar) pt against \(line) pt for one line \
                of CypressFont.listNameSerif — the bar is no longer the height of the name it \
                stands in for. A fixed constant here was the defect PR #102's review found (21 pt \
                against 24.68 at the default size and 67.18 at AX5); if the face or its relativeTo: \
                moved, move MapLayout.cardTitlePlaceholderHeight with it.
                """
            )
        }
    }

    /// **It actually grows** — the guard against the fix being reverted to a constant that happens to
    /// be right at one size.
    ///
    /// The old `21` passes any single-size check you write at the size you chose; what it cannot do
    /// is move. AX5 is ~2.7× the default here, so this is a wide, unambiguous margin.
    @Test("the placeholder is materially taller at AX5 than at the default size")
    func thePlaceholderScales() async {
        let small = ScaledMetricProbe.height(base: MapLayout.cardTitlePlaceholderHeight, at: .large)
        let large = ScaledMetricProbe.height(
            base: MapLayout.cardTitlePlaceholderHeight, at: .accessibility5
        )
        #expect(
            large > small * 2,
            """
            the title placeholder measures \(small) pt at .large and \(large) pt at AX5 — it is not \
            riding the type ramp. A fixed height here is the PR #102 defect: the bar held a fifth \
            of the row the title needs at AX5.
            """
        )
    }
}

/// Reads what `@ScaledMetric(relativeTo: .headline)` resolves to at a given `DynamicTypeSize`.
///
/// `@ScaledMetric` is only readable from inside a `View`'s body, so this mounts the smallest possible
/// one and reports what it saw. It is the same property wrapper `MapTreeCard` declares, at the same
/// `relativeTo:`, so the two cannot resolve differently.
@MainActor
enum ScaledMetricProbe {

    /// Measured out of the layout rather than reported through a callback: the probe draws itself
    /// `scaled` points tall and `sizeThatFits` is asked how tall that turned out to be. A callback
    /// (`onAppear`) is an edge-triggered channel out of the layout system, which is the family of
    /// mechanism `MapKitBasemap`'s #258 note records four flaking wirings of.
    static func height(base: CGFloat, at size: DynamicTypeSize) -> CGFloat {
        let host = UIHostingController(
            rootView: Probe(base: base).environment(\.dynamicTypeSize, size)
        )
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return host.sizeThatFits(
            in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        ).height
    }

    private struct Probe: View {
        // Declared bare and configured in `init`: the attribute cannot carry `relativeTo:` without
        // also carrying a `wrappedValue`, and the base is a parameter here.
        @ScaledMetric var scaled: CGFloat

        init(base: CGFloat) {
            _scaled = ScaledMetric(wrappedValue: base, relativeTo: .headline)
        }

        var body: some View {
            Color.clear.frame(width: 1, height: scaled)
        }
    }
}
