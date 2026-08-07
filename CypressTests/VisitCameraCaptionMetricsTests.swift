//
//  VisitCameraCaptionMetricsTests.swift
//  CypressTests
//
//  A defect reported by a real TestFlight tester on build 18, through the App Store Connect
//  feedback API: the ghost caption on screen 04 is "cut off and flows poorly".
//
//  What was actually wrong. SCREENS 04 draws the caption as mono 10.5px at `line-height:1.4`.
//  CSS `line-height` is a multiple of the font size that INCLUDES the glyph box; SwiftUI's
//  `.lineSpacing()` is only the extra gap added BETWEEN lines. `CypressFont.LineSpacing` states
//  the conversion — `size × (lineHeight − 1.2)` — and every token defined there obeys it.
//  `VisitMetrics.Camera.ghostCaptionLineSpacing` did not: it was `4.2`, which is `10.5 × 0.4`,
//  the same arithmetic with the `− 1.2` dropped, and therefore double the leading the mock asks
//  for. At the caption's `max-width:80px` the no-ghost string wraps to four lines, so the error
//  was multiplied across three gaps and the column read as four floating words.
//
//  Why this test is shaped the way it is. Asserting `ghostCaptionLineSpacing == 2.1` on its own
//  would be a restatement of the source file: it would pass for a wrong rule as happily as for a
//  right one. So the rule is applied here to the four `CypressFont.LineSpacing` tokens FIRST,
//  whose values this branch did not choose. If the conversion this file believes in is not the
//  project's conversion, that check fails and says so before the caption is ever judged by it.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Screen 04 · the ghost caption's leading is the mock's, not double it")
struct VisitCameraCaptionMetricsTests {

    /// The conversion documented on `CypressFont.LineSpacing`: CSS `line-height` counts the glyph
    /// box, `.lineSpacing()` does not, and a custom face's own line box is about 1.2× its size.
    private static func lineSpacing(size: Double, lineHeight: Double) -> Double {
        size * (lineHeight - 1.2)
    }

    /// The calibration. These four values are not this branch's to pick — they are the shipped
    /// tokens — and each is stated in SCREENS' type ramp with the line-height used here. If this
    /// goes red, the formula below is wrong and nothing else in this file means anything.
    @Test("the documented conversion reproduces every shipped line-spacing token")
    func conversionMatchesShippedTokens() {
        // (token value, font size, SCREENS line-height)
        let ramp: [(String, Double, Double, Double)] = [
            ("body.15", Double(CypressFont.LineSpacing.body15), 15, 1.55),
            ("body.13.5", Double(CypressFont.LineSpacing.body135), 13.5, 1.50),
            ("body.12.5", Double(CypressFont.LineSpacing.body125), 12.5, 1.45),
            ("body.11.5", Double(CypressFont.LineSpacing.body115), 11.5, 1.30),
        ]
        for (name, shipped, size, lineHeight) in ramp {
            let derived = Self.lineSpacing(size: size, lineHeight: lineHeight)
            #expect(
                abs(shipped - derived) < 0.001,
                "\(name): token is \(shipped), the documented conversion gives \(derived)"
            )
        }
    }

    /// The defect itself. `mono105` is 10.5pt and SCREENS 04 gives the caption `line-height:1.4`,
    /// so the only value consistent with the rule above is 2.1.
    @Test("the ghost caption converts line-height 1.4 the same way every other token does")
    func ghostCaptionLeadingFollowsTheRule() {
        let expected = Self.lineSpacing(size: 10.5, lineHeight: 1.4)
        let actual = Double(VisitMetrics.Camera.ghostCaptionLineSpacing)
        #expect(
            abs(actual - expected) < 0.001,
            "ghostCaptionLineSpacing is \(actual); mono 10.5 at line-height 1.4 converts to "
                + "\(expected). \(actual) is what dropping the − 1.2 produces."
        )
    }
}

// A third check was drafted here and removed: it asserted that the four-line caption block still
// clears the framing corner at `bottom:120px`. It reaches 100.7pt now and reached 107pt with the
// wrong leading, so it passed either way — a constant-true assertion wearing a guard's clothes,
// which is the failure mode this project has filed twice. The caption's WIDTH, which is the other
// half of the tester's report, is a mock-specified 80pt and is a question for the owner rather
// than a value a test should pin from here.
