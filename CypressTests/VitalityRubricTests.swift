import Foundation
import Testing

@testable import Cypress

/// One class of the rubric, the whole percents of crown dieback it claims, and the phrase its
/// anchor sentence states that band with. Ticket #261, Candidate A.
private struct VitalityBand: Sendable, CustomStringConvertible {
    let vitality: Vitality
    let percents: ClosedRange<Int>
    let phrase: String

    var description: String { "\(vitality.classNumber) \u{00b7} \(vitality.label)" }
}

/// The rubric's five dieback bands: that the shipped copy states them, and that between them they
/// partition the scale.
///
/// This suite deliberately does not pin the anchor sentences. Their register — short, comma-spliced,
/// readable on a sidewalk — is `SCREENS.md`'s under RULINGS R13, and copy a designer may re-word is
/// not a test's business. What it pins is the part R13 reserves to `PRODUCT.md`: a class's dieback
/// band is its *operational definition*, it is what makes level 1 level 1, and it is a fact rather
/// than a phrasing. A re-word that keeps the band passes here; a re-word that drops or moves the
/// band does not.
///
/// The rule the suite exists to hold is that **the five bands partition the whole percents 0 through
/// 100 exactly once**. The rubric that shipped before ticket #261 did not: read literally, 0 percent
/// satisfied both "no visible dieback" (row 5) and "under 10% dieback" (row 4), and 25 percent
/// satisfied both "10 to 25%" (row 3) and "25 to 50%" (row 2). Ten and fifty were single-owned, so
/// it was one ambiguous interior boundary and one ambiguous endpoint — narrower than first reported,
/// and still two of the values a rater estimating in fives is most likely to produce.
///
/// The bands are stated in `bands` rather than parsed out of the anchors, because parsing prose for
/// numerals would be testing the parser. `everyClassStatesItsBand` is what ties that table to the
/// shipped copy; without it the partition check would be a test of its own fixture.
@Suite("Vitality rubric")
struct VitalityRubricTests {

    fileprivate static let bands: [VitalityBand] = [
        VitalityBand(vitality: .thriving, percents: 0...0, phrase: "No dead wood visible"),
        VitalityBand(vitality: .good, percents: 1...10, phrase: "1 to 10%"),
        VitalityBand(vitality: .fair, percents: 11...25, phrase: "11 to 25%"),
        VitalityBand(vitality: .poor, percents: 26...50, phrase: "26 to 50%"),
        VitalityBand(vitality: .severeDecline, percents: 51...100, phrase: "Over half"),
    ]

    // MARK: - The table describes the shipped copy

    @Test("every class's anchor states the band that class claims", arguments: VitalityRubricTests.bands)
    fileprivate func everyClassStatesItsBand(band: VitalityBand) {
        #expect(
            band.vitality.anchor.contains(band.phrase),
            "\(band) claims \(band.percents.lowerBound)\u{2013}\(band.percents.upperBound)% dieback, "
                + "but its anchor does not state that band: \u{201c}\(band.vitality.anchor)\u{201d}. "
                + "A class's band is its operational definition (RULINGS R13 reserves a class's "
                + "meaning to PRODUCT.md); a rater holding a percentage must find the row naming it."
        )
    }

    @Test("the band table names all five classes, worst first")
    func theTableCoversTheRubric() {
        #expect(Self.bands.map(\.vitality) == Array(Vitality.rubric.reversed()))
    }

    // MARK: - The bands partition the scale

    @Test("every whole percent from 0 to 100 belongs to exactly one class")
    func bandsPartitionTheWholePercents() {
        for percent in 0...100 {
            let owners = Self.bands.filter { $0.percents.contains(percent) }
            #expect(
                owners.count == 1,
                "\(percent)% crown dieback is claimed by \(owners.count) classes "
                    + "(\(owners.map(\.description).joined(separator: ", "))). A rater who reads "
                    + "that value off a crown has "
                    + (owners.isEmpty ? "no row to tap" : "more than one row that fits") + "."
            )
        }
    }

    // MARK: - The one clause the seasonality gate cannot rescue

    /// The single absence assertion here, and it earns its place: no gate change can fix this one.
    ///
    /// `Vitality.isRatingPermitted` suppresses the section only for a deciduous species out of leaf,
    /// and `Species.leafOnMonths` runs the deciduous window to the *close of the fall-color season*,
    /// so fall color sits inside leaf-on by construction — intended behavior, and the derivation
    /// ERRATA E33 repaired for a different bug. A tree in fall color is therefore in leaf, ratable
    /// and discolored. Draft v0's row 3 said "Noticeable thinning or discoloration" and pointed that
    /// rater at a decline class. Adding a second condition to the gate would suppress the rubric in
    /// the fall for trees that are in leaf, which is what E33 exists to prevent, so the repair is
    /// copy — and copy that has to stay repaired.
    @Test("no anchor asks about discoloration", arguments: Vitality.allCases)
    func noAnchorAsksAboutDiscoloration(vitality: Vitality) {
        #expect(
            !vitality.anchor.lowercased().contains("discolor"),
            "\(vitality.classNumber) \u{00b7} \(vitality.label) asks about discoloration: "
                + "\u{201c}\(vitality.anchor)\u{201d}. A deciduous species in fall color is in leaf, "
                + "so the seasonality gate does not and must not suppress the rubric for it "
                + "(ERRATA E33), and a rater in October reads seasonal color as decline."
        )
    }
}
