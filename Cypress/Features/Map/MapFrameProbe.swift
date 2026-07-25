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
//  change makes MapKit re-host 1,300 SwiftUI annotations, the link does not fire, and the gap it
//  reports *is* the stall the user feels. It counts what it missed rather than what it did.
//
//  **It is off unless it is asked for.** `CYPRESS_MAP_PROBE=1` in the environment turns it on, which
//  is a thing only a `simctl launch` or a scheme does; there is no UI for it and no build ships with
//  it running. It is `#if DEBUG` on top of that, so it is not in the release binary at all.
//
//  What it cannot tell you: this runs on a simulator, where frames are composited by a Mac GPU and
//  the main thread is a desktop core. The *ratio* between two runs of the same gesture is worth
//  something; the absolute milliseconds are not a device measurement and must never be quoted as
//  one.
//

#if DEBUG
import Foundation
import QuartzCore

/// A main-thread frame-interval counter, printed to stdout in one-second windows.
///
/// `simctl launch --console-pty` is where the lines come out.
@MainActor
final class MapFrameProbe {

    /// The environment variable that arms it, and the only way it is armed.
    static let environmentKey = "CYPRESS_MAP_PROBE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static let shared = MapFrameProbe()

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var windowStart: CFTimeInterval = 0

    /// What the map is drawing right now, so a window's frame times can be read against the count
    /// that caused them. Set by `MapKitBasemap` as the annotation layer changes.
    private(set) var markers = 0
    private(set) var zoom = 0

    func note(markers: Int, zoom: Int) {
        self.markers = markers
        self.zoom = zoom
    }

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
        windowStart = now
    }

    /// One line per window. `worst` is the number that answers the complaint: a 250 ms frame is a
    /// quarter-second where the map did not move under the finger.
    private func report(over seconds: Double) {
        guard !intervals.isEmpty else { return }
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(p * Double(sorted.count)))] }
        // The display link's own cadence on this device, taken as the shortest frame actually seen —
        // a 120 Hz simulator reports 8.3 ms and a 60 Hz one 16.7, and hard-coding either would call
        // the other half-speed.
        let cadence = sorted[0]
        let dropped = intervals.reduce(0.0) { $0 + max(0, ($1 / cadence) - 1) }
        print(String(
            format: "[probe] z%d markers=%d frames=%d fps=%.1f p50=%.1fms p95=%.1fms worst=%.1fms dropped=%.0f",
            zoom, markers, intervals.count, Double(intervals.count) / seconds,
            percentile(0.5), percentile(0.95), sorted[sorted.count - 1], dropped
        ))
    }
}
#endif
