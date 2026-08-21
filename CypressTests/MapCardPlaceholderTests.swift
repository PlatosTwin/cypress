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
/// ── What is asserted, and what turned out not to be assertable ────────────────────────────────
/// The bar's job is to hold **the title's row** open, and that is what is measured: the awaiting
/// card's own height against one drawn line of `CypressFont.listNameSerif` plus the card's padding.
///
/// **It is only observable at accessibility sizes, and saying so is half the finding.** At the
/// default size the card's row is sized by the 58 pt thumbnail beside the title, which is taller
/// than any ordinary title line and absorbs the whole difference: the reviewer measured the card's
/// white surface at 769.0 → 850.7 pt in both the awaiting and the resolved frame, and a bar of 21 pt
/// or of 2 pt would have measured the same. At AX5 the line is 67.18 pt, past the thumbnail, so the
/// title drives the row and the bar's height is finally visible in the card's.
///
/// **The old doc's "nothing under the card moves when the name arrives" is not rescued by this and
/// is not asserted.** Measured at AX5, an awaiting card is 93.2 pt and the same card with a name on
/// it is 140.5 pt — a 47.3 pt jump that has nothing to do with the bar. It is the *meta* line:
/// `MapTreeCard.meta` carries the scientific name, which does not exist until the profile read
/// lands, so the resolved card grows a line the awaiting card never had. No placeholder height can
/// close that, and the constant's doc now says what it does and does not buy instead of claiming
/// this.
///
/// A first version of this suite compared its own `@ScaledMetric` probe against the same constant
/// the card uses and **passed with the card reverted to the fixed 21** — it was measuring the
/// constant, not the card. This one mounts `MapTreeCard`.
@Suite("The map card's title placeholder rides the title's own type ramp")
@MainActor
struct MapCardPlaceholderTests {

    private static let treeID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000101")!
    private static let speciesID = UUID(uuidString: "C0FFEE00-0000-4000-8000-000000000102")!

    private static func pin() -> TreePin {
        TreePin(
            id: treeID,
            coordinate: Coordinate(latitude: 37.7599, longitude: -122.4148),
            status: .alive,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: speciesID
        )
    }

    /// The whole card, measured at `size`. `profile: nil` is the awaiting state that draws the bar.
    private static func cardHeight(profile: TreeProfile?, at size: DynamicTypeSize) async -> CGFloat {
        await AX5ReflowTests.ax5Size(
            of: MapTreeCard(
                subject: MapCardSubject(pin: pin(), profile: profile),
                userCoordinate: nil,
                action: {}
            ),
            width: AX5ReflowTests.phoneWidth - 2 * MapLayout.cardInset,
            size: size
        ).height
    }

    /// One drawn line of the title's own font, measured rather than derived.
    private static func titleLine(at size: DynamicTypeSize) async -> CGFloat {
        await AX5ReflowTests.ax5Size(
            of: Text("Elm").font(CypressFont.listNameSerif).lineLimit(1),
            size: size
        ).height
    }

    /// **The bar holds a full line of the title, at AX5.**
    ///
    /// The awaiting card carries no meta line (`MapTreeCard.meta` is nil with no profile, no fix and
    /// no visit), so its height is exactly the title row plus the card's own vertical padding —
    /// which makes the bar's contribution readable off the card without reaching inside it.
    ///
    /// At AX5 the line is past the 58 pt thumbnail, so the title row is what sizes the card. With
    /// the old fixed `21` the thumbnail won instead and the card measured 84 pt at *every* size.
    @Test("the awaiting card stands a full title line tall at AX5")
    func theBarHoldsTheTitlesRow() async {
        let card = await Self.cardHeight(profile: nil, at: .accessibility5)
        let line = await Self.titleLine(at: .accessibility5)
        let expected = line + 2 * MapLayout.cardPaddingV

        #expect(
            abs(card - expected) <= 2,
            """
            at AX5 the awaiting card measures \(card) pt against \(expected) pt for one line of \
            CypressFont.listNameSerif (\(line)) plus the card's own \(MapLayout.cardPaddingV) pt of \
            padding top and bottom. The bar is not the height of the name it stands in for — a \
            fixed height here was PR #102's finding, and it left the card 84 pt at every size \
            because the 58 pt thumbnail beside the title won instead.
            """
        )
    }

    /// **The bar actually grows with the ramp**, which is what a single-size check cannot say.
    ///
    /// The old `21` satisfies any one measurement taken at the size it was chosen for; what it
    /// cannot do is move. Measured on the card rather than on the constant, for the reason this
    /// suite's header gives.
    @Test("the awaiting card is materially taller at AX5 than at the default size")
    func theAwaitingCardScales() async {
        let small = await Self.cardHeight(profile: nil, at: .large)
        let large = await Self.cardHeight(profile: nil, at: .accessibility5)

        #expect(
            large > small,
            """
            the awaiting card measures \(small) pt at .large and \(large) pt at AX5 — the \
            placeholder is not riding the type ramp, so the card that stands in for a name is the \
            same size whatever size the reader has asked for.
            """
        )
    }

    /// **The constant is the face's own drawn line**, which is the half of the old doc that was a
    /// guess: `21` is `17.5 × 1.2`, and the 17.5 pt `SourceSerif4-SemiBold` actually draws 23.99 pt.
    ///
    /// Asserted against `UIFont` rather than against a literal, so this stays true if the face or
    /// its size ever moves and fails if the constant stops tracking it.
    @Test("the placeholder's base is the unscaled line the serif face actually draws")
    func theBaseIsTheFacesOwnLine() throws {
        let face = try #require(
            UIFont(name: CypressFont.Face.serifSemiBold, size: 17.5),
            "CypressFont.Face.serifSemiBold is not registered, so nothing below measures the face"
        )
        #expect(
            abs(MapLayout.cardTitlePlaceholderHeight - face.lineHeight) <= 0.01,
            """
            MapLayout.cardTitlePlaceholderHeight is \(MapLayout.cardTitlePlaceholderHeight) against \
            a drawn line of \(face.lineHeight) for the 17.5 pt serif face. The old value was 21, \
            which is 17.5 × 1.2 — a guess at a line height rather than a measurement of one.
            """
        )
    }
}
