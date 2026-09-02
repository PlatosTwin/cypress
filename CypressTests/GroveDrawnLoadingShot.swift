//
//  GroveDrawnLoadingShot.swift
//  CypressTests
//
//  **The one assertion in this repository that a column is not blank, made by looking at it.**
//
//  The owner's ruling of 2026-09-02 is that screen 08's `Trees` pill must never draw nothing. That
//  is a claim about pixels, and every instrument this project has for it is a value test:
//  `GroveTreesPagingTests` can prove `GroveModel.treesDrawing` answers `.loading`, and a view that
//  matched that case with `EmptyView()` would keep it green. The blank column survived two rounds
//  in exactly that gap — the model had a state the view had no arm for, and no test could see the
//  difference.
//
//  `ShotBlankGuard` already exists for the opposite problem (a screenshot harness that photographs
//  nothing and reports success, ERRATA E145) and it is the right instrument pointed the other way:
//  it downscales a capture to 16×16 and counts unique colors, and one flat region is exactly what
//  an empty column is. So this renders `GroveView` on the `Trees` pill with a read that has not
//  answered, crops away the title and the pill row and the tab bar — the chrome, which is drawn in
//  every state and would keep any crop containing it out of "blank" — and asks the guard about what
//  is left.
//
//  The crop is the whole of the rigor here, and it is calibrated rather than eyeballed: the same
//  crop over the same screen with the loading arm removed is what the red-proof reads, and it comes
//  back as one unique color.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("My Grove · the Trees column, photographed while it is loading")
struct GroveDrawnLoadingShot {

    /// The band between the pill row and the bottom tab bar, in points.
    ///
    /// Top: screen 08's title block plus the pill row is about 150 pt at `.large`; 200 clears it
    /// with room to spare, and clearing it is what matters — a crop that included the pills would
    /// never be flat and the test would pass on the chrome.
    ///
    /// Bottom: C16 is about 100 pt plus the home indicator. 700 is well above the column's floor at
    /// this viewport and well below the bar.
    static let columnTop: CGFloat = 200
    static let columnBottom: CGFloat = 700

    @Test("the column draws something while the first page is in flight")
    func theLoadingColumnIsNotBlank() async throws {
        let api = SuspendingGroveAPI()
        let model = GroveModel(api: api, tab: .trees)

        let image = try #require(
            await ScreenSweepShots.capture(
                "j02-grove-trees-loading", size: .large, scheme: .light
            ) { GroveView(model: model) },
            "the capture harness produced nothing at all — this test is about a different blank"
        )
        // Let the suspended read go, so nothing is left hanging on the executor after the test.
        api.answer([])

        let column = try #require(Self.crop(image), "the crop fell outside the capture")
        let verdict = ShotBlankGuard.verdict(for: column)
        #expect(
            verdict.isDrawn,
            """
            the Trees column drew nothing while its first page was in flight: \(verdict). This is \
            the blank the owner ruled out on 2026-09-02 — see `GroveModel.TreesDrawing`
            """
        )
    }

    /// **The calibration, and it is not optional.** `ShotBlankGuard` answering `.ok` for the crop
    /// above proves nothing unless the same crop can answer `.blank` — a crop that accidentally
    /// included the pill row, or a coordinate conversion that quietly clamped to the whole image,
    /// would be `.ok` forever.
    ///
    /// So: the same screen, same size, same crop, with the column genuinely empty. `GroveModel`
    /// cannot produce that any more, which is the point of the change; a plain `Color` behind the
    /// same geometry can, and it is the shape the old `treesTab` drew — chrome above, chrome below,
    /// one flat fill between.
    @Test("the crop can see a blank column, so seeing a drawn one means something")
    func theCropCanSeeABlank() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let size = CGSize(width: ScreenSweepShots.width, height: ScreenSweepShots.height)
        let flat = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Chrome at the top and the bottom, which is what a blank column has around it and
            // what a careless crop would find instead of the column.
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: Self.columnTop - 20))
            UIColor.black.setFill()
            context.fill(
                CGRect(
                    x: 0, y: Self.columnBottom + 20,
                    width: size.width, height: size.height - Self.columnBottom - 20
                )
            )
        }

        let column = try #require(Self.crop(flat))
        #expect(
            !ShotBlankGuard.verdict(for: column).isDrawn,
            """
            the crop reported a deliberately empty column as drawn. Either it is not landing on the \
            column, or the blank guard cannot see a flat frame — in both cases the test above is \
            vacuous
            """
        )
    }

    /// The band, in pixels, out of a capture whose `size` is in points.
    static func crop(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let scale = CGFloat(cgImage.width) / image.size.width
        let rect = CGRect(
            x: 0,
            y: columnTop * scale,
            width: CGFloat(cgImage.width),
            height: (columnBottom - columnTop) * scale
        )
        guard rect.maxY <= CGFloat(cgImage.height), let cropped = cgImage.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: cropped)
    }
}

extension ShotVerdict {
    /// `.ok` and nothing else. Written here rather than on the type because it is this suite's
    /// question: `ShotBlankGuard`'s own callers want the reason string, not a boolean.
    var isDrawn: Bool {
        if case .ok = self { return true }
        return false
    }
}
#endif
