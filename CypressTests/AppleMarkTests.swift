//
//  AppleMarkTests.swift
//  CypressTests
//
//  The owner's ruling 6 of 2026-08-14: screen 15's `Continue with Apple` carries Apple's logo,
//  drawn as a `Shape` in this repo, per Apple's own custom-button guidelines.
//
//  ── What is worth asserting here, and what is not ──────────────────────────────────────────────
//  SwiftUI builds no render tree a test can walk, so "the mark is on the button" is not a question
//  this suite can ask directly — the UI test `AppleSignInUITests` and a look at the running screen
//  are the evidence for that, and a drawn glyph's defects are visual besides. What *is* checkable in
//  process, and is what goes wrong silently, is the arithmetic: a `Path` whose control points drift,
//  a mark sized off a number that no longer matches the label beside it, a `Shape` that stretches
//  when it is handed the wrong aspect ratio, and a later round quietly reaching for
//  `ASAuthorizationAppleIDButton` instead.
//
//  Every figure below is Apple's, from `AppleMark`'s own cited source, and each is written as a
//  literal here rather than read back off the type it is checking — a test that recomputes the
//  thing it is testing measures nothing.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("Screen 15's Apple mark (owner ruling 6, 2026-08-14)")
struct AppleMarkTests {

    // MARK: - The artwork

    /// Apple's `small` file is 24 × 44 and its button crop is the centered 12 × 44. Inside that
    /// crop the mark measures 11.825 × 14.532, sitting 13.634 from the top and 15.834 from the
    /// bottom — **not centered**, which is the padding that puts it on the title's optical center
    /// and the reason the whole file is transcribed rather than the glyph alone.
    @Test("the transcribed path is Apple's artwork, padding and all")
    func theTranscribedPathIsApplesArtwork() {
        let box = CGRect(origin: .zero, size: AppleMark.pathBox)
        #expect(AppleMark.pathBox == CGSize(width: 12, height: 44))

        let drawn = AppleMark().path(in: box).boundingRect
        #expect(abs(drawn.width - 11.825) < 0.01, "the mark measures \(drawn.width) pt wide in a 12 pt crop")
        #expect(abs(drawn.height - 14.532) < 0.01, "the mark measures \(drawn.height) pt tall in a 44 pt file")
        #expect(abs(drawn.minY - 13.634) < 0.01, "the file's top padding is \(drawn.minY), not Apple's 13.634")
        #expect(
            abs((44 - drawn.maxY) - 15.834) < 0.01,
            "the file's bottom padding is \(44 - drawn.maxY), not Apple's 15.834"
        )
        // The asymmetry itself, stated as the fact it is: trimming the file to the glyph and
        // centering it would move the mark down by a point and nothing else would notice.
        #expect(drawn.minY < 44 - drawn.maxY)
    }

    /// The `Shape` scales uniformly and centers, so a caller that hands it a square — or anything
    /// else off Apple's ratio — gets an undistorted mark rather than a stretched apple.
    @Test("the mark keeps its proportions in a rect that is not its own")
    func theMarkKeepsItsProportions() {
        let referenceRect = CGRect(origin: .zero, size: AppleMark.pathBox)
        let reference = AppleMark().path(in: referenceRect).boundingRect
        let referenceRatio = reference.width / reference.height

        for rect in [
            CGRect(x: 0, y: 0, width: 44, height: 44),
            CGRect(x: 0, y: 0, width: 12, height: 200),
            CGRect(x: 7, y: 11, width: 24, height: 88),
        ] {
            let drawn = AppleMark().path(in: rect).boundingRect
            #expect(
                abs(drawn.width / drawn.height - referenceRatio) < 0.001,
                "in \(rect) the mark drew at \(drawn.width / drawn.height) against Apple's \(referenceRatio)"
            )
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(drawn), "the mark drew outside \(rect)")
            // The file is centered in the axis it does not fill, so the mark keeps whatever offset
            // from center Apple gave it, scaled — never a different one.
            let scale = drawn.height / reference.height
            #expect(
                abs((drawn.midX - rect.midX) - (reference.midX - referenceRect.midX) * scale) < 0.01,
                "in \(rect) the mark sits \(drawn.midX - rect.midX) off center against \((reference.midX - referenceRect.midX) * scale)"
            )
            #expect(
                abs((drawn.midY - rect.midY) - (reference.midY - referenceRect.midY) * scale) < 0.01,
                "in \(rect) the mark sits \(drawn.midY - rect.midY) off center against \((reference.midY - referenceRect.midY) * scale)"
            )
        }
    }

    /// Apple's two placement minimums, from the layout in its own JS SDK:
    /// `leftMargin = floor(0.5 * logoWidth)` and `middleMargin = floor(0.7 * logoWidth)`.
    @Test("the placement margins are Apple's fractions of the file's width")
    func thePlacementMarginsAreApples() {
        #expect(AppleMark.leadingMargin(forFileWidth: 20) == 10)
        #expect(AppleMark.titleMargin(forFileWidth: 20) == 14)
        // Written as the multiplication rather than as `== 12.0 / 44.0`: the ratio is not
        // representable, and the literal division landed a few ulps off the stored value while both
        // printed the same seventeen digits — a comparison whose failure message read
        // `0.2727272727272727 == 0.2727272727272727`.
        #expect(abs(AppleMark.aspectRatio * 44 - 12) < 1e-9)
    }

    /// "the button's height would be 233% of the title's font size", composed with "match the height
    /// of the logo file to the height of the button".
    @Test("the logo file's height is 233% of the title's size")
    func theFileHeightIsApplesProportionOfTheTitle() {
        #expect(abs(AppleMark.fileHeight(forTitleSize: 100) - 233) < 0.001)
        #expect(abs(AppleMark.fileHeight(forTitleSize: 15) - 34.95) < 0.001)
    }

    // MARK: - The number the mark is sized from is the number the label is drawn at

    /// `AppleMark.fileHeight(forTitleSize:)` takes a `CGFloat`, and the button hands it
    /// `AccountAskMetrics.providerTitleSize`. Nothing in `CypressFont` publishes a size, so the two
    /// can disagree in silence — and if they do, the mark is proportioned for a label that is not
    /// the one beside it.
    ///
    /// Measured rather than declared: the same string is laid out twice, once through the SwiftUI
    /// token the button actually uses and once through a `UIFont` built at
    /// `providerTitleSize`, and the two widths have to agree. **Calibrated first** — the control
    /// builds the same `UIFont` two points larger and requires the widths to *dis*agree, so a
    /// measurement that could not tell 15 from 17 cannot report the main assertion as a pass.
    @MainActor
    @Test("the mark is sized from the size the button's title is drawn at")
    func theMarkIsSizedFromTheTitleTheButtonDraws() {
        let specimen = "Continue with Apple"

        func swiftUIWidth() -> CGFloat {
            let host = UIHostingController(
                rootView: AnyView(
                    Text(specimen)
                        .font(CypressFont.body15Bold)
                        .fixedSize()
                        .environment(\.dynamicTypeSize, .large)
                )
            )
            let unbounded = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            return host.sizeThatFits(in: unbounded).width
        }

        func uiKitWidth(at size: CGFloat) -> CGFloat {
            let font = UIFont(name: CypressFont.Face.sansBold, size: size)
            // A nil here means the face never registered, which would make both arms below measure
            // the system font and agree for the wrong reason.
            #expect(font != nil, "\(CypressFont.Face.sansBold) is not registered in this process")
            guard let font else { return .nan }
            return (specimen as NSString).size(withAttributes: [.font: font]).width
        }

        let drawn = swiftUIWidth()
        let control = uiKitWidth(at: AccountAskMetrics.providerTitleSize + 2)
        #expect(
            abs(drawn - control) > 1,
            """
            the calibration failed: the label measured \(drawn) pt and a deliberately wrong \
            \(AccountAskMetrics.providerTitleSize + 2) pt layout of the same string measured \
            \(control) pt. This measurement cannot tell two point sizes apart, so its verdict below \
            means nothing.
            """
        )

        let matched = uiKitWidth(at: AccountAskMetrics.providerTitleSize)
        #expect(
            abs(drawn - matched) < 0.5,
            """
            the button draws its title at some size other than \
            AccountAskMetrics.providerTitleSize (\(AccountAskMetrics.providerTitleSize)): the label \
            measured \(drawn) pt and that size measures \(matched) pt. AppleMark sizes the logo file \
            from that number, so the mark is proportioned for a label that is not this one.
            """
        )
    }

    // MARK: - No borrowed button, either

    /// Every spelling that puts Apple's own sign-in button — and therefore Apple's own drawing of
    /// the mark — on a screen in this app.
    ///
    /// **Two of them, and the second was found by PR #88's reviewer compiling it (F4).**
    /// `ASAuthorizationAppleIDButton` is the UIKit view; `SignInWithAppleButton` is
    /// `AuthenticationServices`' SwiftUI one, which is the API a SwiftUI codebase actually reaches
    /// for. The first draft of this guard named only the UIKit spelling, and the reviewer put
    /// `SignInWithAppleButton(.continue, …)` inside `AccountProviderButton` — the exact control
    /// ruling 6 governs — with **this guard and `DrawnGlyphGuardTests` both green**.
    ///
    /// The list is what the guard is, so it is asserted non-empty and each token is controlled
    /// separately below; a shared control would let a new token ride on an old token's prose.
    static let borrowedAppleButtonSpellings = [
        "ASAuthorizationAppleIDButton",
        "SignInWithAppleButton",
    ]

    /// `DrawnGlyphGuardTests` already refuses an SF Symbol anywhere in the app target, including
    /// this button — nothing needed extending for that half of ruling 6, and it was proved rather
    /// than assumed. The half it cannot see is the other one the ruling names: neither spelling
    /// above is a glyph API and neither contains `systemName:` or `systemImage:`, so a later round
    /// could swap the drawn control for Apple's own view with that whole suite green.
    ///
    /// It reuses `BorrowedGlyphAPI.codeOnly`, which that suite's own controls already calibrate,
    /// because this file names both types in prose in the paragraph above and `AppleMark`'s header
    /// names them too — a scanner that stopped stripping comments would fail here on its own
    /// documentation.
    @Test("no Apple-provided sign-in button is constructed anywhere in the app target")
    func theAppConstructsNoSystemAppleButton() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let files = AppSourceLiterals.sourceFiles(root: root)
        #expect(
            files.count >= AppSourceLiterals.swiftFileCountFloor,
            "the scan swept \(files.count) files, so it checked next to nothing"
        )
        #expect(!Self.borrowedAppleButtonSpellings.isEmpty, "an empty token list passes everything")

        var hits: [String] = []
        var proseMentions: [String: Int] = [:]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            var code: [String]?
            for token in Self.borrowedAppleButtonSpellings where source.contains(token) {
                proseMentions[token, default: 0] += 1
                let lines = code ?? BorrowedGlyphAPI.codeOnly(in: source).components(separatedBy: "\n")
                code = lines
                for (index, line) in lines.enumerated() where line.contains(token) {
                    hits.append("\(relative):\(index + 1): \(token)")
                }
            }
        }

        #expect(
            hits.isEmpty,
            """
            \(hits) constructs Apple's own sign-in button. Ruling 6 of 2026-08-14 draws the mark \
            into screen 15's own control instead; changing that is the owner's, not this file's.
            """
        )
        // The control, per token. Sharing one counter would let a newly added spelling be
        // "controlled" by an older one's prose mention while matching nothing at all itself.
        for token in Self.borrowedAppleButtonSpellings {
            #expect(
                proseMentions[token, default: 0] >= 1,
                """
                no file in the app target mentions `\(token)`, so the scan for it is a grep for a \
                string this repository does not contain and it would pass on an empty tree. \
                `AppleMark`'s header names both spellings deliberately; if that was edited, this \
                control needs a new anchor rather than deleting.
                """
            )
        }
    }
}
