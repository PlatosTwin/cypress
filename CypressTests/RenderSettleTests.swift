//
//  RenderSettleTests.swift
//  CypressTests
//
//  `RenderSettle` decides when the screen sweep may draw. If it returns early, the sweep draws
//  loading states and every test around it still passes, because the blank guard only asks
//  whether a capture has content, not whether it has the right content. These tests are the
//  only check on that.
//

#if DEBUG
import SwiftUI
import Testing
import UIKit

@MainActor
@Suite("RenderSettle waits for what a .task delivers")
struct RenderSettleTests {

    /// How long the late view holds its spinner. Longer than the settle's floor plus its stable
    /// window (160 ms + 3 × 40 ms), so a settle that only watched the layer tree would return
    /// while the spinner is still up.
    nonisolated static let delay: Duration = .milliseconds(400)

    /// A budget far above `delay`, so a starved runner cannot end the wait on time alone. These
    /// tests are about the settle's own decision, not about its budget.
    static let roomyBudget: Duration = .seconds(10)

    /// Read by the test after the settle returns. Set by the view's `.task`.
    @MainActor
    final class Delivery {
        var landed = false
    }

    /// A spinner until its `.task` lands, then content. The shape of screens 03, 07, 08 and 14b.
    struct LateContent: View {
        let delivery: Delivery
        @State private var loaded = false

        var body: some View {
            Group {
                if loaded {
                    VStack(spacing: 0) {
                        Text(verbatim: "Loaded")
                        Color.green.frame(height: 200)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                try? await Task.sleep(for: RenderSettleTests.delay)
                loaded = true
                delivery.landed = true
            }
        }
    }

    /// Mounts `content` the way `ScreenSweepShots.capture` does. The caller keeps the window.
    static func mount(_ content: some View) -> (UIWindow, UIView) {
        let frame = CGRect(x: 0, y: 0, width: ScreenSweepShots.width, height: ScreenSweepShots.height)
        let host = UIHostingController(rootView: AnyView(content.frame(width: frame.width, height: frame.height)))
        host.view.frame = frame
        let window = UIWindow(frame: frame.offsetBy(dx: -2_000, dy: 0))
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        return (window, host.view)
    }

    @Test("the settle does not return while a .task's spinner is still up")
    func waitsForLateContent() async {
        let delivery = Delivery()
        let (window, view) = Self.mount(LateContent(delivery: delivery))
        defer { window.isHidden = true; window.rootViewController = nil }

        let outcome = await RenderSettle.settle(view, label: "late-content", budget: Self.roomyBudget)

        #expect(
            delivery.landed,
            """
            the settle returned after \(outcome.passes) passes, before the view's .task delivered \
            its content: a capture taken now would show the spinner, not the screen
            """
        )
        #expect(!RenderSettle.hasVisibleSpinner(view), "the settle returned with the spinner still visible")
        #expect(!outcome.reachedBudget, "the settle never decided; it ran out its \(Self.roomyBudget) budget")
    }

    /// The calibration for the test above: the spinner check has to see a SwiftUI `ProgressView`
    /// at all. If SwiftUI stopped drawing it with `UIActivityIndicatorView`, the check would never
    /// fire and the settle would fall back to the layer tree alone.
    @Test("a SwiftUI ProgressView is seen as a visible spinner")
    func seesAProgressView() async {
        let (window, view) = Self.mount(ProgressView())
        defer { window.isHidden = true; window.rootViewController = nil }
        try? await Task.sleep(for: RenderSettle.interval)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(RenderSettle.hasVisibleSpinner(view), "no UIActivityIndicatorView found under a ProgressView")
    }

    /// The other direction: a still view must settle on its own decision. If the signature changed
    /// on every pass, every capture would wait the whole budget and the sweep would be as slow
    /// as before.
    @Test("a view that does not change settles before its budget")
    func stillViewSettles() async {
        let (window, view) = Self.mount(
            VStack(spacing: 0) {
                Text(verbatim: "Still")
                Color.blue.frame(height: 200)
            }
        )
        defer { window.isHidden = true; window.rootViewController = nil }

        let outcome = await RenderSettle.settle(view, label: "still", budget: Self.roomyBudget)
        #expect(!outcome.reachedBudget, "a still view never settled: \(outcome)")
        #expect(outcome.passes >= RenderSettle.stablePasses, "settled after \(outcome.passes) passes")
    }
}
#endif
