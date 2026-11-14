//
//  RenderSettle.swift
//  CypressTests
//
//  The one wait the off-screen render harnesses use before they draw or measure a hosted view.
//
//  ── What it replaced ──────────────────────────────────────────────────────────────────────
//  `ScreenSweepShots.capture`, `DynamicTypeScreenshotTests.render` and `AX5ReflowTests.ax5Size`
//  each slept eight times for 120 ms and laid the view out after each sleep. That is 0.96 s per
//  capture whatever the screen did, and the sweep makes about 200 captures. On main run
//  43543728441 the unit job spent its last 218 s of 283 s on about 35 `@MainActor` render tests.
//
//  ── The rule ──────────────────────────────────────────────────────────────────────────────
//  Lay the view out after short yields until it stops changing, then return. The view has
//  settled when all four of these hold after a pass:
//   1. at least the floor has passed since the first yield (`defaultFloor`, 160 ms, unless the
//      caller passes `legacyBudget` for a screen that loads with no spinner; see below);
//   2. no visible `UIActivityIndicatorView` is in the hierarchy (SwiftUI's circular
//      `ProgressView` is drawn by one, and screens such as 03, 07, 08 and 14b show a
//      `ProgressView` while their `.task` waits);
//   3. the layer tree's signature was the same for `stablePasses` passes in a row;
//   4. the caller's `ready` condition holds, when it gave one.
//  Whatever happens, it returns once `budget` has passed. The default budget is the old loop's
//  0.96 s, so a view that never settles waits as long as it did before, and not longer.
//
//  ── Why the spinner check is there ────────────────────────────────────────────────────────
//  A screen whose `.task` is waiting on an actor shows the same spinner pass after pass, so the
//  layer tree alone reads as "settled" while the load has not landed. On a starved CI runner that
//  wait can be long. `RenderSettleTests` holds a spinner for longer than the default floor plus
//  the stable window and checks that the settle waits it out.
//
//  ── Screens that load with no spinner ─────────────────────────────────────────────────────
//  Some screens show nothing, or a still notice, until their `.task` lands: 02 ("Finding you"),
//  12, 20 and the e12 states (an empty body until the almanac has a presentation), 05 and 09
//  (text filled in later), 12b and 12c (the pin map), 06 (land context) and 21 (three loads).
//  The layer tree is still for those during the load, so with the 160 ms floor they could be
//  drawn early. Their callers pass `floor: legacyBudget`, which keeps the old 0.96 s wait for
//  them. Where a cheap fact says the load landed, a caller passes `ready` as well.
//
//  ── What it does not prove ────────────────────────────────────────────────────────────────
//  A screen on the default floor that loads with no spinner, and takes longer than about
//  160 ms, is drawn early. Under the old loop the same screen got 0.96 s. Any new screen of that
//  kind must pass `floor: legacyBudget` or a `ready` condition. A view that shows a spinner on
//  purpose (a loading state under test) never settles and waits the whole budget; each such
//  wait prints a `SETTLE-BUDGET` line.
//

#if DEBUG
import QuartzCore
import UIKit

enum RenderSettle {

    /// How long each yield is. Short, because a settled view is found by seeing passes agree,
    /// and the old 120 ms per pass was most of the wait.
    static let interval: Duration = .milliseconds(40)

    /// The least time the settle waits by default, so a `.task` started on the first pass has
    /// room to run.
    static let defaultFloor: Duration = .milliseconds(160)

    /// How many passes in a row the signature must repeat.
    static let stablePasses = 3

    /// The old loop's total: 8 × 120 ms.
    static let legacyBudget: Duration = .milliseconds(960)

    struct Outcome: Equatable {
        /// Layout passes run.
        var passes: Int
        /// True when the budget ran out before the view settled.
        var reachedBudget: Bool
        /// True when a visible activity indicator was still in the hierarchy at the end.
        var spinnerVisible: Bool
    }

    /// Waits for `view` to settle, as the file header defines it.
    ///
    /// - Parameters:
    ///   - label: printed with `SETTLE-BUDGET` when the budget runs out, so a unit log shows
    ///     which captures waited the whole time.
    ///   - floor: the least time to wait. Pass `legacyBudget` for a screen that loads with no
    ///     spinner (the file header lists them).
    ///   - ready: a fact the caller can read that says the load landed. Checked after each pass.
    @MainActor
    @discardableResult
    static func settle(
        _ view: UIView,
        label: String,
        floor: Duration = defaultFloor,
        budget: Duration = legacyBudget,
        ready: () -> Bool = { true }
    ) async -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        var previous: Int?
        var repeats = 0
        var passes = 0
        while true {
            try? await Task.sleep(for: interval)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            passes += 1

            let signature = layerSignature(view.layer)
            repeats = signature == previous ? repeats + 1 : 1
            previous = signature
            // The stable count starts again once `ready` holds, so the passes that count are the
            // ones after the load landed, not a still spinner-less screen before it.
            let isReady = ready()
            if !isReady { repeats = 0 }
            let spinner = hasVisibleSpinner(view)
            let elapsed = clock.now - start

            if elapsed >= floor, !spinner, repeats >= stablePasses, isReady {
                return Outcome(passes: passes, reachedBudget: false, spinnerVisible: false)
            }
            if elapsed >= budget {
                print("SETTLE-BUDGET \(label) — \(passes) passes, spinner visible: \(spinner), ready: \(isReady)")
                return Outcome(passes: passes, reachedBudget: true, spinnerVisible: spinner)
            }
        }
    }

    /// A hash of what a draw reads from the layer tree: each layer's class, geometry, transform,
    /// visibility, fill, border, corner radius, sublayer count, and the identity of its backing
    /// contents. A load that lands adds, removes, moves, recolors or redraws layers, and each of
    /// those changes this value. `RenderSettleTests` checks that a text swap and a color swap
    /// at the same size change it.
    ///
    /// It reads model values only. An animation (a spinner turning) runs on the presentation
    /// layer and does not change it, which is why the spinner needs its own check.
    @MainActor
    static func layerSignature(_ root: CALayer) -> Int {
        var hasher = Hasher()
        func combine(_ color: CGColor?) {
            guard let color, let components = color.components else {
                hasher.combine(-1)
                return
            }
            for component in components { hasher.combine(component) }
        }
        func visit(_ layer: CALayer) {
            hasher.combine(ObjectIdentifier(type(of: layer)))
            hasher.combine(layer.position.x)
            hasher.combine(layer.position.y)
            hasher.combine(layer.bounds.size.width)
            hasher.combine(layer.bounds.size.height)
            hasher.combine(layer.isHidden)
            hasher.combine(layer.opacity)
            hasher.combine(layer.cornerRadius)
            hasher.combine(layer.borderWidth)
            combine(layer.backgroundColor)
            combine(layer.borderColor)
            let t = layer.transform
            for value in [t.m11, t.m12, t.m21, t.m22, t.m41, t.m42, t.m43] { hasher.combine(value) }
            if let contents = layer.contents {
                hasher.combine(ObjectIdentifier(contents as AnyObject))
            } else {
                hasher.combine(0)
            }
            let sublayers = layer.sublayers ?? []
            hasher.combine(sublayers.count)
            for sublayer in sublayers { visit(sublayer) }
        }
        visit(root)
        return hasher.finalize()
    }

    /// True when a `UIActivityIndicatorView` that is not hidden, and not inside a hidden view,
    /// is in `root`'s hierarchy.
    @MainActor
    static func hasVisibleSpinner(_ root: UIView) -> Bool {
        if root.isHidden || root.alpha == 0 { return false }
        if root is UIActivityIndicatorView { return true }
        return root.subviews.contains { hasVisibleSpinner($0) }
    }
}
#endif
