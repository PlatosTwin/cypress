import Foundation
import Testing
@testable import Cypress

/// A fix has to arrive carrying how much to trust it, because that number cannot be recovered later.
///
/// `MapLocationProvider` shipped without it: `Availability.located` held a coordinate and nothing
/// else, so `gpsAccuracyM` was nil everywhere it was the source. Harmless while nothing charted —
/// and the moment screen 16 records a measurement, D6 would exclude every single one, and an empty
/// growth chart would send someone looking in the charting code for a bug that lives in the
/// location provider.
@Suite("Location accuracy survives the provider")
struct LocationAccuracyTests {

    @Test("a map fix carries its accuracy, not just its coordinate")
    func mapFixCarriesAccuracy() {
        let fix = MapLocationProvider.Availability.located(
            Coordinate(latitude: 37.7561, longitude: -122.4967),
            accuracyM: 8
        )
        #expect(fix.coordinate != nil)
        #expect(fix.accuracyM == 8)
    }

    @Test("every non-fix state has no accuracy to give")
    func nonFixStatesCarryNothing() {
        let states: [MapLocationProvider.Availability] = [
            .notAsked, .waitingForFix, .denied, .servicesOff
        ]
        for state in states {
            #expect(state.accuracyM == nil)
            #expect(state.coordinate == nil)
        }
    }

    /// The load-bearing one. CoreLocation reports a negative `horizontalAccuracy` when it could not
    /// work one out, and both providers substitute the same pessimistic constant rather than nil.
    /// That choice only holds up if the constant lands the wrong side of D6's gate — otherwise an
    /// unknown fix would quietly pass as a good one.
    @Test("an unknown accuracy is excluded from charting by arithmetic, not by a special case")
    func unknownAccuracyFailsTheGate() {
        #expect(
            VisitShortlist.assumedAccuracyM > GPSAccuracy.growthChartingLimitM,
            """
            The substitute for an unrecoverable fix (\(VisitShortlist.assumedAccuracyM)m) is inside \
            D6's \(GPSAccuracy.growthChartingLimitM)m limit, so a fix CoreLocation could not measure \
            would be charted as if it had been.
            """
        )
    }

    @Test("D6's gate is inclusive at the limit and excludes a missing reading")
    func gateBoundaries() {
        let treeID = UUID()
        func visit(accuracy: Double?) -> Visit {
            Visit(
                treeID: treeID,
                attribution: .anonymous(deviceID: UUID()),
                gpsAccuracyM: accuracy,
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }

        #expect(visit(accuracy: 15).isEligibleForGrowthCharting)
        #expect(!visit(accuracy: 15.1).isEligibleForGrowthCharting)
        // Not "assumed good" — D6 says unusable, and that is the safe direction: a chart that omits
        // a point understates what is known, where one that invents it asserts something nobody
        // measured.
        #expect(!visit(accuracy: nil).isEligibleForGrowthCharting)
    }
}
