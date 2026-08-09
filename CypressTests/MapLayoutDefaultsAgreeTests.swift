import Foundation
import Testing
@testable import Cypress

/// **The map's opening default is written twice, and `Tools/run_tests.sh` now rests on both.**
///
/// `MapLayout.defaultCenter` is the app's own opening coordinate. `DebugLocationFixtures
/// .missionDolores` is a hand-written string spelling of the same point, whose doc comment says so
/// in as many words. Until task #71 the duplication was harmless prose; it is now load-bearing.
///
/// **Why the harness needs two copies.** `run_tests.sh` normalizes a device's remembered
/// `map.lastCamera` onto the app's opening default, and it *parses* that coordinate out of
/// `MapKitBasemap.swift` rather than carrying a literal — a literal in a shell script goes stale
/// the day the app moves and nothing tells anyone (CLAUDE.md's schema-version bullet is the
/// standing example). But a parser has its own failure mode, and the review of PR #62 found the
/// bad one: a **doc comment** above the declaration that mentions a historical coordinate parses
/// cleanly to the wrong number, and every downstream check then agrees with it, because they all
/// compare against the same wrong parse. Self-consistent, confident, wrong.
///
/// So the script cross-checks its parse of `MapKitBasemap.swift` against its parse of
/// `DebugLocationOverride.swift` and refuses when they disagree. Two files, two unrelated
/// declaration shapes: a mis-parse of one does not coincidentally equal a correct read of the
/// other.
///
/// **What this test is for.** That cross-check rests on a premise the script cannot verify — that
/// the two declarations are genuinely *meant* to be the same coordinate. This asserts the premise.
/// Move the default for real and this goes red until both places are updated, which makes the
/// change deliberate; let them drift by accident and this catches it here, in a suite that runs on
/// every branch, rather than as a harness refusal on somebody's machine at 2 a.m.
///
/// It deliberately does **not** re-assert the coordinate's own value. A test that pinned
/// `37.7596` would have to be edited by the same person making the same move, and would prove only
/// that they edited it twice.
@Suite("The map's opening default, and its second spelling")
struct MapLayoutDefaultsAgreeTests {

    /// One metre. The two are written to different precisions — `Coordinate(latitude: 37.7596, …)`
    /// against `"37.7596,-122.4269"` — so this is an agreement check, not a bit-for-bit one, and a
    /// metre is far below any distance at which the harness's choice of camera would differ.
    private static let toleranceM = 1.0

    private static func metersApart(
        _ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)
    ) -> Double {
        let metersPerDegree = 111_320.0
        let dy = (a.lat - b.lat) * metersPerDegree
        let dx = (a.lon - b.lon) * metersPerDegree * cos(b.lat * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }

    @Test("the debug fixture and the map's own default name the same point")
    func missionDoloresIsTheDefaultCenter() throws {
        let parts = DebugLocationFixtures.missionDolores.split(separator: ",")
        #expect(parts.count == 2, "missionDolores is not a 'lat,lon' pair: \(DebugLocationFixtures.missionDolores)")
        let lat = try #require(Double(parts.first ?? ""), "missionDolores latitude is not a number")
        let lon = try #require(Double(parts.last ?? ""), "missionDolores longitude is not a number")

        let center = MapLayout.defaultCenter
        let apart = Self.metersApart(
            (lat: lat, lon: lon), (lat: center.latitude, lon: center.longitude)
        )
        // One interpolated literal, not a `+` chain: Swift Testing's message parameter is
        // `Comment?`, which a string LITERAL becomes for free and a concatenation does not — and
        // the chain also timed out the type checker outright. Both errors were live here.
        let complaint: Comment = """
            DebugLocationFixtures.missionDolores (\(lat), \(lon)) is \(Int(apart)) m from \
            MapLayout.defaultCenter (\(center.latitude), \(center.longitude)). Its own doc comment \
            says they are the same point, and Tools/run_tests.sh cross-checks its parse of one \
            against the other to catch a mis-parse — that check is only as good as this agreement. \
            Update both, or change the script's cross-check deliberately.
            """
        #expect(apart <= Self.toleranceM, complaint)
    }

    /// The other half of what the harness parses. It is not duplicated anywhere to cross-check
    /// against, so what is asserted is the weaker property the script actually depends on: that the
    /// span is a positive number of metres narrow enough to draw individual pins rather than
    /// clusters. `MapViewport.highestClusteringZoom` is the app's own boundary, and a default span
    /// on the wrong side of it would make the harness normalize every device onto a camera that
    /// draws cluster badges — E202-B's failure, arrived at from the app's side instead.
    @Test("the default span is narrow enough to draw pins rather than clusters")
    func defaultSpanDrawsPins() {
        #expect(MapLayout.defaultSpanMeters > 0)
        // 742 m is zoom 16 on a 402 pt screen by `MapLayout.defaultSpanMeters`' own doc comment,
        // which is the first zoom that draws individual pins.
        let complaint: Comment = """
            the map's opening span is \(MapLayout.defaultSpanMeters) m, which is wider than the \
            zoom-16 pin threshold. Tools/run_tests.sh normalizes every device onto this span.
            """
        #expect(MapLayout.defaultSpanMeters <= 742, complaint)
    }
}
