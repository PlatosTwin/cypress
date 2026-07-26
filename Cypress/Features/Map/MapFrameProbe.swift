//
//  MapFrameProbe.swift
//  Cypress — Features/Map
//
//  ── Why a frame counter lives in the app ─────────────────────────────────────────────────────
//  "The map gets SUPER slow when you zoom out a bit" is a complaint about frames, and a passing
//  test proves nothing about frames. Every other claim on this screen — 1,321 pins in a zoom-16
//  viewport, 104 ms for the whole city clustered, 0.18 for the parchment wash — was measured before
//  it was written down, and the annotation count is the one number on screen 01 that never was.
//
//  So this is the instrument. A `CADisplayLink` ticks once per composited frame on the main
//  run loop, which is the same run loop SwiftUI rebuilds the annotation layer on: when a camera
//  change makes MapKit re-host a few hundred SwiftUI annotations, the link does not fire, and the
//  gap it reports *is* the stall the user feels. It counts what it missed rather than what it did.
//
//  ── Why it is now also on the screen ─────────────────────────────────────────────────────────
//  The first round of this work was measured entirely on a simulator, said so, and was believed
//  anyway; the owner then installed the result on a real iPhone and reported the map still slow.
//  A Mac compositing for a desktop main thread cannot answer that, and neither can a `print` — the
//  person holding the phone is not holding a console. So the probe now publishes a one-second
//  snapshot that `MapProbeOverlay` draws in the corner of the map, and the number the owner reads
//  aloud is a measurement of *their* hardware rather than an inference from ours.
//
//  It counts three things besides frames, because on this screen a dropped frame has three
//  candidate causes and the counters tell them apart without a profiler:
//
//  - **`gps`** — how many times `MapLocationProvider` published a new `availability`. Every publish
//    used to re-run the whole basemap body, and a simulator sitting on one static `simctl location`
//    fix publishes exactly once, which is precisely how that went unseen for a round.
//  - **`body`** — how many times the basemap re-evaluated. This is the work.
//  - **`fetch`** — how many viewport reads completed. A pan that reads more than it draws is a
//    different defect from a pan that draws too much.
//
//  **It is off unless it is asked for.** `CYPRESS_MAP_PROBE=1` in the environment turns it on, which
//  is a thing only a `simctl launch` or a scheme does; there is no UI for it and no build ships with
//  it running. It is `#if DEBUG` on top of that, so it is not in the release binary at all — see
//  `.measurements/e139-compiled-out.txt` for the artifact comparison that proves it, taken the way
//  ERRATA E117 proved the same thing of `DebugDeepLink`.
//
//  What it still cannot tell you: read on a simulator, frames are composited by a Mac GPU and the
//  main thread is a desktop core. The *ratio* between two runs of the same gesture is worth
//  something; the absolute milliseconds are not a device measurement and must never be quoted as
//  one. Read on a phone, they are — which is the entire point of putting them on the screen.
//

#if DEBUG
import Foundation
import Observation
import QuartzCore

/// A main-thread frame-interval counter. Prints one line per second to stdout, and publishes the
/// same window to `MapProbeOverlay` for whoever is holding the device.
///
/// `simctl launch --console-pty` is where the printed lines come out.
@MainActor
@Observable
final class MapFrameProbe {

    /// The environment variable that arms it, and the only way it is armed.
    static let environmentKey = "CYPRESS_MAP_PROBE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static let shared = MapFrameProbe()

    /// One second of the map's health, as a value. Published once per window rather than per frame:
    /// an overlay that redrew itself sixty times a second would be measuring itself.
    struct Snapshot: Equatable {
        var fps: Double = 0
        var worstMS: Double = 0
        var p95MS: Double = 0
        var markers = 0
        var zoom = 0
        /// Location publishes, basemap body passes and completed viewport reads, per second.
        var gpsPerSecond = 0
        var bodyPerSecond = 0
        var fetchPerSecond = 0
        /// Whether the last window ever missed the display's own cadence. What the eye calls "slow".
        var isSmooth: Bool { worstMS < 34 }
    }

    /// The published window. Read by `MapProbeOverlay`, written once per second from the display
    /// link — never from inside a view's body, which is why the counters below are not observed.
    private(set) var snapshot = Snapshot()

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var intervals: [Double] = []
    @ObservationIgnored private var windowStart: CFTimeInterval = 0

    /// What the map is drawing right now, so a window's frame times can be read against the count
    /// that caused them. Set by `MapHomeView` as the annotation layer changes.
    @ObservationIgnored private(set) var markers = 0
    @ObservationIgnored private(set) var zoom = 0

    /// The three per-window counters. **`@ObservationIgnored` is load-bearing**: `noteBody()` is
    /// called from inside `MapKitBasemap.body`, and a tracked property written during a view update
    /// is both a SwiftUI runtime complaint and a feedback loop — the overlay would invalidate the
    /// map, which would re-run the body, which would bump the counter. They are plain storage that
    /// the display link folds into `snapshot` once a second.
    @ObservationIgnored private var gpsCount = 0
    @ObservationIgnored private var bodyCount = 0
    @ObservationIgnored private var fetchCount = 0

    func note(markers: Int, zoom: Int) {
        self.markers = markers
        self.zoom = zoom
    }

    /// A new `MapLocationProvider.availability` reached the view tree.
    func noteLocationPublish() { gpsCount += 1 }

    /// The basemap re-evaluated its body. Called from the body itself; see the note above.
    func noteBody() { bodyCount += 1 }

    /// A viewport read completed and its content was published.
    func noteFetch() { fetchCount += 1 }

    func start() {
        guard Self.isEnabled, link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        print("[probe] armed")
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else {
            windowStart = now
            return
        }
        intervals.append((now - lastTimestamp) * 1_000)
        guard now - windowStart >= 1 else { return }
        report(over: now - windowStart)
        intervals.removeAll(keepingCapacity: true)
        gpsCount = 0
        bodyCount = 0
        fetchCount = 0
        windowStart = now
    }

    /// One line per window, and one published snapshot. `worst` is the number that answers the
    /// complaint: a 250 ms frame is a quarter-second where the map did not move under the finger.
    private func report(over seconds: Double) {
        guard !intervals.isEmpty else { return }
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))] }
        // The display link's own cadence on this device, taken as the shortest frame actually seen —
        // a 120 Hz simulator reports 8.3 ms and a 60 Hz one 16.7, and hard-coding either would call
        // the other half-speed.
        let cadence = sorted[0]
        let dropped = intervals.reduce(0.0) { $0 + max(0, ($1 / cadence) - 1) }
        let fps = Double(intervals.count) / seconds

        snapshot = Snapshot(
            fps: fps,
            worstMS: sorted[sorted.count - 1],
            p95MS: percentile(0.95),
            markers: markers,
            zoom: zoom,
            gpsPerSecond: gpsCount,
            bodyPerSecond: bodyCount,
            fetchPerSecond: fetchCount
        )

        print(String(
            format: "[probe] z%d markers=%d frames=%d fps=%.1f p50=%.1fms p95=%.1fms worst=%.1fms dropped=%.0f gps=%d body=%d fetch=%d",
            zoom, markers, intervals.count, fps,
            percentile(0.5), percentile(0.95), sorted[sorted.count - 1], dropped,
            gpsCount, bodyCount, fetchCount
        ))
    }
}
#endif
