//
//  PhotoGlyphTests.swift
//  CypressTests
//
//  #130 drew screen 20's vote control by hand. One `PhotoThumbGlyph` serves all four states — a
//  downvote is the same mark turned a half turn — so the only thing left to get wrong is which
//  vote turns it, and that mapping lives in `TreePhotosPresentation.thumb` where a test can reach
//  it (E164's lesson: a mapping only the renderer can call is a mapping no test can check).
//
//  The mark's *geometry* is not asserted here and could not usefully be: E163 is the errata about
//  two path defects in this app that no test could have seen, and both were found by looking at
//  the running screen. The ruling `RULINGS R57` records what was looked
//  at, at which type sizes.
//

#if DEBUG
import Foundation
import SwiftUI
import Testing
@testable import Cypress

@Suite("Screen 20 · the drawn vote mark (#130)")
struct PhotoGlyphTests {

    @Test("an upvote draws the mark upright and a downvote turns it a half turn")
    func theVoteDecidesTheRotation() {
        #expect(TreePhotosPresentation.thumb(.up, filled: false).halfTurn == false)
        #expect(TreePhotosPresentation.thumb(.down, filled: false).halfTurn == true)
    }

    /// The fill is the whole of "this is your vote", so it has to follow the argument and nothing
    /// else — in particular it must not be entangled with the direction.
    @Test("the fill follows the reader's own vote, in both directions")
    func theFillFollowsOwnership() {
        for vote in PhotoVote.allCases {
            #expect(TreePhotosPresentation.thumb(vote, filled: true).isFilled == true)
            #expect(TreePhotosPresentation.thumb(vote, filled: false).isFilled == false)
        }
    }

    /// The two votes must not draw the same thing. Stated as its own fact because "up and down are
    /// different" is exactly the kind of invariant a refactor breaks silently — both arms of a
    /// `switch` returning the same value compiles and looks fine.
    @Test("the two votes are distinguishable at the same fill")
    func theVotesAreDistinguishable() {
        #expect(
            TreePhotosPresentation.thumb(.up, filled: true)
                != TreePhotosPresentation.thumb(.down, filled: true)
        )
        #expect(
            TreePhotosPresentation.thumb(.up, filled: false)
                != TreePhotosPresentation.thumb(.down, filled: false)
        )
    }

    /// The stroke scales with the mark. A 1.8 pt line is the app's weight *in a 24 pt box*; left
    /// unscaled in the 17 pt frame these are drawn at it is half again too heavy, which is the
    /// difference between the mark and a blob.
    @Test("the stroke keeps its proportion to the box")
    func theStrokeScales() {
        #expect(PhotoGlyphMetrics.stroke(for: PhotoGlyphMetrics.box) == PhotoGlyphMetrics.strokeInBox)
        let atSeventeen = PhotoGlyphMetrics.stroke(for: 17)
        #expect(atSeventeen < PhotoGlyphMetrics.strokeInBox)
        #expect(abs(atSeventeen - 1.275) < 0.001, "the 17 pt stroke is \(atSeventeen)")
        #expect(VisitLibraryGlyph.style(for: VisitLibraryGlyph.box).lineWidth == VisitLibraryGlyph.strokeInBox)
    }

    /// Every mark has to put something in the rect it is given. A `Shape` that returns an empty
    /// path draws nothing, breaks no build, and fails no other test in this file.
    @Test("every drawn mark produces a path inside the box it is given")
    func everyMarkDrawsSomething() {
        let box = CGRect(x: 0, y: 0, width: 24, height: 24)
        let marks: [(String, Path)] = [
            ("PhotoTrashGlyph", PhotoTrashGlyph().path(in: box)),
            ("PhotoThumbGlyph", PhotoThumbGlyph().path(in: box)),
            ("PhotoCloseGlyph", PhotoCloseGlyph().path(in: box)),
            ("VisitLibraryGlyph", VisitLibraryGlyph().path(in: box)),
            ("VisitCloseGlyph", VisitCloseGlyph().path(in: box)),
        ]
        for (name, path) in marks {
            #expect(!path.isEmpty, "\(name) drew nothing")
            let bounds = path.boundingRect
            #expect(bounds.width > 8 && bounds.height > 8, "\(name) drew \(bounds), which is not a mark")
            #expect(box.insetBy(dx: -0.01, dy: -0.01).contains(bounds), "\(name) drew outside its box: \(bounds)")
        }
    }

    /// The marks are drawn from a box-relative origin, so a shape asked to draw in an offset rect
    /// has to land there. Getting this wrong puts the glyph in the corner of the screen, and it is
    /// the one geometric error a headless test can actually catch.
    @Test("a mark drawn in an offset rect lands in that rect")
    func marksHonorTheirOrigin() {
        let offset = CGRect(x: 100, y: 40, width: 24, height: 24)
        for (name, path) in [
            ("PhotoTrashGlyph", PhotoTrashGlyph().path(in: offset)),
            ("PhotoThumbGlyph", PhotoThumbGlyph().path(in: offset)),
            ("PhotoCloseGlyph", PhotoCloseGlyph().path(in: offset)),
            ("VisitLibraryGlyph", VisitLibraryGlyph().path(in: offset)),
        ] {
            #expect(
                offset.insetBy(dx: -0.01, dy: -0.01).contains(path.boundingRect),
                "\(name) ignored the rect's origin: \(path.boundingRect)"
            )
        }
    }
}
#endif
