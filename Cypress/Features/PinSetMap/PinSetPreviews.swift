//
//  PinSetPreviews.swift
//  Cypress — Features/PinSetMap
//
//  The two states this screen has, and they are the two E38 is about (ERRATA E129):
//
//  - **the whole group** — nine young trees, all of them on the map, and the sentence says `All nine
//    are on this map.`;
//  - **a page of it** — 1,474 basins in the neighborhood and 20 on the map, and the sentence says
//    which twenty. The count above it is still 1,474, because that number is a `COUNT(*)`.
//
//  Previewed rather than described, because the whole argument of this screen is what a reader can
//  see, and the difference between the two states is one line of copy over a different number of pins.
//

#if DEBUG
import SwiftUI

private enum PinSetPreviewFixtures {

    static let here = Coordinate(latitude: 37.7530, longitude: -122.4850)

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "12900000-0000-4000-8000-%012d", index))!
    }

    /// A city-inventory pin, laid along a couple of blocks from `here` — roughly the 197 m × 212 m the
    /// 20 nearest basins in Sunset/Parkside actually span (`AlmanacLimits.vacantSiteRowLimit`).
    static func pin(_ index: Int, status: TreeStatus = .alive) -> TreePin {
        TreePin(
            id: id(index),
            coordinate: Coordinate(
                latitude: here.latitude + Double(index % 5) * 0.000_45,
                longitude: here.longitude + Double(index / 5) * 0.000_70
            ),
            status: status,
            source: .cityImport,
            verificationState: .cityRecord,
            speciesID: nil
        )
    }

    /// §4's group, whole: the read proved it had all nine, which is why the card printed a number.
    static let coverage = PinSet(
        subject: .coverageGap,
        pins: (0..<9).map { pin($0) },
        count: 9,
        neighborhoodName: "Sunset/Parkside"
    )

    /// R10's group, a page: 20 of 1,474.
    static let vacant = PinSet(
        subject: .vacantSites,
        pins: (0..<20).map { pin(100 + $0, status: .vacantSite) },
        count: 1_474,
        neighborhoodName: "Sunset/Parkside"
    )

    /// One basin. E115 found no neighborhood like this, but §5.6 is a rule about the general case and
    /// `It is on this map.` has to be a sentence somebody can read.
    static let single = PinSet(
        subject: .vacantSites,
        pins: [pin(200, status: .vacantSite)],
        count: 1,
        neighborhoodName: "Sunset/Parkside"
    )
}

#Preview("group · walk the nine") {
    NavigationStack {
        PinSetMapView(
            set: PinSetPreviewFixtures.coverage,
            userCoordinate: PinSetPreviewFixtures.here,
            onBack: {},
            onOpenPin: { _ in }
        )
    }
}

#Preview("group · 20 of 1,474 basins") {
    NavigationStack {
        PinSetMapView(
            set: PinSetPreviewFixtures.vacant,
            userCoordinate: PinSetPreviewFixtures.here,
            onBack: {},
            onOpenPin: { _ in }
        )
    }
}

#Preview("group · one record") {
    NavigationStack {
        PinSetMapView(
            set: PinSetPreviewFixtures.single,
            userCoordinate: PinSetPreviewFixtures.here,
            onBack: {},
            onOpenPin: { _ in }
        )
    }
}

/// Dark. This screen has no specified dark appearance (E8), and the basemap's own dark wash is the
/// part worth looking at — `MapKitBasemap.parchmentWash` pushes MapKit dark toward D1's forest floor
/// and cannot get all the way there.
#Preview("group · dark") {
    NavigationStack {
        PinSetMapView(
            set: PinSetPreviewFixtures.vacant,
            userCoordinate: PinSetPreviewFixtures.here,
            onBack: {},
            onOpenPin: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
#endif
