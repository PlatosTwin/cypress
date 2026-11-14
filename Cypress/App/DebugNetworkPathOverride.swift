//
//  DebugNetworkPathOverride.swift
//  Cypress — App
//
//  A launch-time way to say which connection the phone is on, for screen checks and the UI test
//  target (F35).
//
//  The outbox holds photographs back on a metered connection when "Sync photos on wifi only" is on.
//  A simulator is always on the Mac's connection, which is unmetered, so without this seam the
//  "waiting for wi-fi" state of screen 17 cannot be produced on a simulator at all.
//
//      CYPRESS_NETWORK_PATH=metered      the phone is on cellular, a hotspot, or Low Data Mode
//      CYPRESS_NETWORK_PATH=unmetered    the phone is on wi-fi
//
//  Read from the process environment and `#if DEBUG`, for `DebugLocationOverride`'s reasons: only
//  whoever launched the process can set it, and a Release build does not contain it.
//
//  **A typo must not fall back to the real connection quietly** (`DebugLocationOverride`'s rule).
//  An unrecognized value stops the launch with a message that names the variable and the two words
//  it accepts.
//

#if DEBUG
import Foundation

enum DebugNetworkPathOverride {

    static let environmentKey = "CYPRESS_NETWORK_PATH"

    /// The pinned path the launching process asked for, or nil when it asked for none.
    static func requested(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PinnedNetworkPath? {
        guard let raw = environment[environmentKey]?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        switch raw {
        case "metered": return PinnedNetworkPath(unmetered: false)
        case "unmetered": return PinnedNetworkPath(unmetered: true)
        default:
            fatalError("\(environmentKey)=\(raw) is not a connection; expected metered | unmetered")
        }
    }
}
#endif
