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

    /// The band between the pill row and the bottom tab bar, in points, measured off a capture
    /// rather than guessed: at `.large` on a 393 × 852 viewport the pills end at about 117 pt and
    /// C16 begins at about 800.
    ///
    /// Clearing the chrome is the whole requirement — a crop containing the pills or the tab bar
    /// would never be flat, and the test would pass on furniture that is drawn in every state.
    /// The other side of it is that the band must still contain the column's *top*, where a
    /// loading treatment sits: a band starting at 200 pt clears the pills comfortably and misses
    /// the spinner entirely, which is what the first draft of this file did.
    static let columnTop: CGFloat = 135
    static let columnBottom: CGFloat = 780

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
        let verdict = ShotBlankGuard.verdict(reading: column.cgImage)
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
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: Self.columnTop - 10))
            UIColor.black.setFill()
            context.fill(
                CGRect(
                    x: 0, y: Self.columnBottom + 10,
                    width: size.width, height: size.height - Self.columnBottom - 10
                )
            )
        }

        let column = try #require(Self.crop(flat))
        #expect(
            !ShotBlankGuard.verdict(reading: column.cgImage).isDrawn,
            """
            the crop reported a deliberately empty column as drawn. Either it is not landing on the \
            column, or the blank guard cannot see a flat frame — in both cases the test above is \
            vacuous
            """
        )
    }

    /// The band, redrawn into a bitmap of its own.
    ///
    /// **`CGImage.cropping(to:)` is deliberately not used**, and it is the kind of thing that would
    /// have made this whole file lie. A cropped `CGImage` keeps the *parent's* data provider: its
    /// `width` and `height` are the crop's, and `dataProvider.data` is still the full capture. A
    /// reader that walks `width × height` from offset zero — which is what
    /// `ShotBlankGuard.verdict(reading:)` correctly does for an ordinary bitmap — would therefore
    /// be reading the top-left corner of the screen, chrome and all, and answering `.ok` no matter
    /// what the column held. Redrawing produces a standalone buffer whose geometry is its own.
    ///
    /// The verdict is then taken at **full resolution**, not through
    /// `ShotBlankGuard.verdict(for:)`. That entry point downscales to 16 × 16 first, which is right
    /// for its own job — judging a whole screen — and wrong here: a 20 pt spinner in a 645 pt band
    /// is less than a pixel of a 16 × 16 thumbnail, so the drawn column and the blank one would
    /// downscale to the same flat frame. Measured: the first draft of this test did exactly that
    /// and reported "only 1 unique color" for a column with a spinner plainly in it.
    static func crop(_ image: UIImage) -> UIImage? {
        guard columnBottom <= image.size.height else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let size = CGSize(width: image.size.width, height: columnBottom - columnTop)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: CGPoint(x: 0, y: -columnTop))
        }
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
