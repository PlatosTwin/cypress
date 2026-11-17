//
//  DebugDeepLinkSpotTests.swift
//  CypressTests
//
//  ROADMAP 193: two debug screens put their trees on the spots of two others. `othersTree` and
//  `othersTreeUnnamed` cached a tree exactly where `addTreeNearby` and `addTreeAlone` work, and
//  `addTreeAlone` refuses to open when any tree is within 10 m of its spot. So after
//  `OthersTreeUITests` ran on a simulator, `AddTreeNearbyUITests` failed there.
//
//  This holds every debug spot 100 m from every other. The spots come from
//  `DebugDeepLink.treeSpot(for:)`, whose switch has no `default`, so a new screen cannot compile
//  without saying where its tree goes, and this test then checks that place.
//
//  It checks the north-south distance, not only the straight-line one. A spot that starts a line of
//  slots runs west from it, out to sea, so two lines are as close as their latitudes are. It does
//  not check where a slot line ends, or the random 120 m patch `ownTreeSpeciesReported` spreads its
//  trees over north of its spot.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@Suite("Debug deep-link tree spots")
struct DebugDeepLinkSpotTests {

    /// The closest two spots may be, in meters.
    private static let minimumSeparationM: Double = 100

    /// One meter of latitude, in degrees (a degree of latitude is about 111 km).
    private static let degreesPerMeter = 1 / 111_320.0

    private static var spots: [(screen: String, spot: Coordinate)] {
        DebugDeepLink.Screen.allCases.compactMap { screen in
            DebugDeepLink.treeSpot(for: screen).map { (screen.rawValue, $0) }
        }
    }

    @Test("the list holds the cases that place trees at sea")
    func theListIsNotEmpty() {
        let screens = Set(Self.spots.map(\.screen))
        // Calibration: the four cases ROADMAP 193 is about must be in the list, or the test
        // below has nothing to compare them with.
        for screen in ["othersTree", "othersTreeUnnamed", "addTreeNearby", "addTreeAlone"] {
            #expect(screens.contains(screen), "\(screen) has no spot in DebugDeepLink.treeSpot(for:)")
        }
    }

    @Test("every two debug spots are at least 100 m apart, north to south")
    func everyTwoSpotsAreApart() {
        let spots = Self.spots
        for (index, first) in spots.enumerated() {
            for second in spots.dropFirst(index + 1) {
                let northSouthM = abs(first.spot.latitude - second.spot.latitude) / Self.degreesPerMeter
                #expect(
                    northSouthM >= Self.minimumSeparationM,
                    """
                    \(first.screen) (\(first.spot.latitude), \(first.spot.longitude)) and \
                    \(second.screen) (\(second.spot.latitude), \(second.spot.longitude)) are \
                    \(Int(northSouthM)) m apart north to south; debug spots must be \
                    \(Int(Self.minimumSeparationM)) m apart
                    """
                )
            }
        }
    }
}
#endif
