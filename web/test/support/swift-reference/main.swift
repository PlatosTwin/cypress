// Reference values printed by the REAL Swift, for the TypeScript port to be checked against.
//
// WHY A FIXTURE AT ALL. `web/test/*.test.ts` asserts that the ports in `web/src/lib/` produce the
// same numbers as `Cypress/Core`. The honest way to establish "the same" is to run the Swift, and
// the web suite cannot: it runs on ubuntu with no toolchain, and CLAUDE.md's rule is that an
// artifact you did not watch being produced is not evidence. So the Swift is run ONCE, by hand, on
// a machine with Xcode, and what it printed is checked in beside the tests that read it.
//
// HOW TO REGENERATE, from the repository root:
//
//     swiftc -O -o /tmp/cypress-swift-ref \
//       web/test/support/swift-reference/main.swift \
//       Cypress/Core/Units/Quantity.swift \
//       Cypress/Core/Models/Geometry.swift \
//       Cypress/Core/Models/CoreEntity.swift
//     /tmp/cypress-swift-ref > web/test/support/swift-reference.json
//
// Those three Swift files are compiled UNMODIFIED — that is the whole point, and it is why this
// file holds no copy of the rules, only calls into them.
//
// WHAT KEEPS THE FIXTURE FROM GOING STALE. It records derived OUTPUTS, which cannot drift on their
// own; what can drift is the constants they were derived from. `web/test/*.test.ts` therefore
// parses `publicPhotoGridM`, `growthChartingLimitM`, the `metersPerUnit` table and both
// `PlausibleRange` bounds out of the live Swift and asserts the fixture still agrees with them. A
// constant that moves turns those red with "regenerate the fixture" rather than leaving a green
// suite comparing today's TypeScript against last month's Swift.
//
// WHY IT IS IN A DIRECTORY OF ITS OWN, NAMED `main.swift`. Swift allows top-level statements in a
// file with exactly that name and in no other, so `swift-reference.swift` beside the JSON does not
// compile — `error: expressions are not allowed at the top level`. Found by running the command
// above rather than by reading it.
//
// NOT PART OF THE APP. `Cypress.xcodeproj` synchronizes exactly `Cypress`, `CypressTests` and
// `CypressUITests` (`PBXFileSystemSynchronizedRootGroup`); nothing under `web/` is in the Xcode
// project, and `tsc` does not look at `.swift`. This file compiles only when the command above is
// typed.

import Foundation

// Reference values produced by the REAL Swift sources, compiled unmodified alongside this file.
// Emitted as JSON with full Double precision so the TS port can be checked against measured
// output rather than against a reading of the source.

func j(_ d: Double) -> String {
    // Shortest round-trippable representation: Swift's Double description is round-trip exact.
    return "\(d)"
}

var lines: [String] = []
lines.append("{")

// ── Quantity: metersPerUnit, siValue, converted ────────────────────────────
var unitRows: [String] = []
for u in LengthUnit.allCases {
    unitRows.append("    {\"unit\": \"\(u.rawValue)\", \"metersPerUnit\": \(j(u.metersPerUnit)), \"isMetric\": \(u.isMetric)}")
}
lines.append("  \"lengthUnits\": [\n" + unitRows.joined(separator: ",\n") + "\n  ],")

let quantityCases: [(Double, LengthUnit, MeasurementMethod)] = [
    (5, .feet, .tape), (12.5, .inches, .caliper), (64, .centimeters, .tape),
    (900, .centimeters, .tape), (0.5, .millimeters, .estimate), (1, .meters, .laser),
    (40, .feet, .estimate), (0.1, .inches, .tape), (3.7, .meters, .laser),
    (-2.5, .feet, .tape), (0, .centimeters, .estimate),
]
var qRows: [String] = []
for (v, u, m) in quantityCases {
    let q = Quantity(value: v, unit: u, method: m)
    var conv: [String] = []
    for t in LengthUnit.allCases { conv.append("\"\(t.rawValue)\": \(j(q.converted(to: t)))") }
    qRows.append("""
        {"value": \(j(v)), "unit": "\(u.rawValue)", "method": "\(m.rawValue)", \
    "siValue": \(j(q.siValue)), "series": "\(q.series.rawValue)", \
    "plausibleDBH": \(q.isPlausible(within: Quantity.PlausibleRange.dbhM)), \
    "plausibleHeight": \(q.isPlausible(within: Quantity.PlausibleRange.heightM)), \
    "converted": {\(conv.joined(separator: ", "))}}
    """)
}
lines.append("  \"quantities\": [\n    " + qRows.joined(separator: ",\n    ") + "\n  ],")

lines.append("  \"plausible\": {\"dbhLow\": \(j(Quantity.PlausibleRange.dbhM.lowerBound)), \"dbhHigh\": \(j(Quantity.PlausibleRange.dbhM.upperBound)), \"heightLow\": \(j(Quantity.PlausibleRange.heightM.lowerBound)), \"heightHigh\": \(j(Quantity.PlausibleRange.heightM.upperBound))},")

// ── The 25 m grid ──────────────────────────────────────────────────────────
lines.append("  \"publicPhotoGridM\": \(j(Coordinate.publicPhotoGridM)),")
let coords: [(Double, Double)] = [
    (37.760123, -122.505456),   // the SharePresentationTests specimen
    (37.7601, -122.5054),
    (0, 0),
    (37.0, -122.0),
    (-33.8688, 151.2093),       // southern hemisphere, positive longitude
    (51.5074, -0.1278),
    (89.9, 100.0),              // near the pole, where cos collapses
    (-89.9, -100.0),
    (40.7128, -74.0060),        // NYC
    (37.3382, -121.8863),       // San Jose
    (0.0001, -0.0001),
]
var cRows: [String] = []
for (lat, lon) in coords {
    let c = Coordinate(latitude: lat, longitude: lon)
    let s = c.snappedToPublicPhotoGrid()
    // TWICE, as well as once. The snap is NOT idempotent: the longitude step is derived from the
    // latitude, and the first pass moves the latitude, so the second pass measures the longitude
    // against a different grid. Recorded rather than assumed -- see docs/errata-pending/.
    let s2 = s.snappedToPublicPhotoGrid()
    let s3 = s2.snappedToPublicPhotoGrid()
    cRows.append(
        "{\"lat\": \(j(lat)), \"lon\": \(j(lon))"
        + ", \"snappedLat\": \(j(s.latitude)), \"snappedLon\": \(j(s.longitude))"
        + ", \"twiceLat\": \(j(s2.latitude)), \"twiceLon\": \(j(s2.longitude))"
        + ", \"thriceLat\": \(j(s3.latitude)), \"thriceLon\": \(j(s3.longitude))"
        + ", \"driftM\": \(j(s.distance(to: s2)))}"
    )
}
lines.append("  \"snapped\": [\n    " + cRows.joined(separator: ",\n    ") + "\n  ],")

// Distances, for the haversine port.
var dRows: [String] = []
let pairs: [((Double, Double), (Double, Double))] = [
    ((37.760123, -122.505456), (37.7601, -122.5054)),
    ((0, 0), (0, 1)),
    ((0, 0), (1, 0)),
    ((37.7601, -122.5054), (40.7128, -74.0060)),
    ((37.7601, -122.5054), (37.7601, -122.5054)),
]
for (a, b) in pairs {
    let d = Coordinate(latitude: a.0, longitude: a.1).distance(to: Coordinate(latitude: b.0, longitude: b.1))
    dRows.append("{\"a\": [\(j(a.0)), \(j(a.1))], \"b\": [\(j(b.0)), \(j(b.1))], \"meters\": \(j(d))}")
}
lines.append("  \"distances\": [\n    " + dRows.joined(separator: ",\n    ") + "\n  ],")

// ── Swift's rounding rule, stated by measurement ───────────────────────────
var rRows: [String] = []
for x in [2.5, -2.5, 0.5, -0.5, 1.5, -1.5, 2.4, -2.4, 3.5, -3.5] {
    rRows.append("{\"x\": \(j(x)), \"rounded\": \(j(x.rounded()))}")
}
lines.append("  \"rounded\": [" + rRows.joined(separator: ", ") + "],")

// ── Growth charting ────────────────────────────────────────────────────────
lines.append("  \"growthChartingLimitM\": \(j(GPSAccuracy.growthChartingLimitM))")
lines.append("}")
print(lines.joined(separator: "\n"))
