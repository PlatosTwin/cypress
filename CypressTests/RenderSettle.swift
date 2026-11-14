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
//  settled when all three of these hold after a pass:
//   1. at least `floor` has passed since the first yield;
//   2. no visible `UIActivityIndicatorView` is in the hierarchy (SwiftUI's circular
//      `ProgressView` is drawn by one, and screens such as 03, 07, 08 and 14b show a
//      `ProgressView` while their `.task` waits);
//   3. the layer tree's signature was the same for `stablePasses` passes in a row.
//  Whatever happens, it returns once `budget` has passed. The default budget is the old loop's
//  0.96 s, so a view that never settles waits as long as it did before, and not longer.
//
//  ── Why the spinner check is there ────────────────────────────────────────────────────────
//  A screen whose `.task` is waiting on an actor shows the same spinner pass after pass, so the
//  layer tree alone reads as "settled" while the load has not landed. On a starved CI runner that
//  wait can be long. `RenderSettleTests` holds a spinner for longer than `floor` plus the stable
//  window and checks that the settle waits it out.
//
//  ── What it does not prove ────────────────────────────────────────────────────────────────
//  A load with no visible placeholder that is slower than `floor` plus the stable window is
//  still drawn early, the same as a load slower than 0.96 s was before. A view that shows a
//  spinner on purpose (a loading state under test) never settles and waits the whole budget;
//  each such wait prints a `SETTLE-BUDGET` line.
//

#if DEBUG
import QuartzCore
import UIKit

enum RenderSettle {

    /// How long each yield is. Short, because a settled view is found by seeing passes agree,
    /// and the old 120 ms per pass was most of the wait.
    static let interval: Duration = .milliseconds(40)

    /// The least time the settle waits, so a `.task` started on the first pass has room to run.
    static let floor: Duration = .milliseconds(160)

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
    /// - Parameter label: printed with `SETTLE-BUDGET` when the budget runs out, so a unit log
    ///   shows which captures waited the whole time.
    @MainActor
    @discardableResult
    static func settle(
        _ view: UIView,
        label: String,
        budget: Duration = legacyBudget
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
            let spinner = hasVisibleSpinner(view)
            let elapsed = clock.now - start

            if elapsed >= floor, !spinner, repeats >= stablePasses {
                return Outcome(passes: passes, reachedBudget: false, spinnerVisible: false)
            }
            if elapsed >= budget {
                print("SETTLE-BUDGET \(label) — \(passes) passes, spinner visible: \(spinner)")
                return Outcome(passes: passes, reachedBudget: true, spinnerVisible: spinner)
            }
        }
    }

    /// A hash of what a draw reads from the layer tree: each layer's class, geometry,
    /// visibility, sublayer count, and the identity of its backing contents. A load that lands
    /// adds, removes, moves or redraws layers, and each of those changes this value.
    ///
    /// It reads model values only. An animation (a spinner turning) runs on the presentation
    /// layer and does not change it, which is why the spinner needs its own check.
    @MainActor
    static func layerSignature(_ root: CALayer) -> Int {
        var hasher = Hasher()
        func visit(_ layer: CALayer) {
            hasher.combine(ObjectIdentifier(type(of: layer)))
            hasher.combine(layer.position.x)
            hasher.combine(layer.position.y)
            hasher.combine(layer.bounds.size.width)
            hasher.combine(layer.bounds.size.height)
            hasher.combine(layer.isHidden)
            hasher.combine(layer.opacity)
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
