import CoreGraphics
import Foundation
import Testing
@testable import Cypress

/// The two zooms the owner ruled in on 2026-08-21, as arithmetic.
///
/// Both were reported from TestFlight and both are gestures, which is the hard thing to test: a
/// pinch cannot be synthesized in the unit suite, and the one this suite could reach — screen 04's —
/// runs on hardware no simulator has. So each feature is built with its clamp as a pure value type
/// beside the view (`PhotoZoom`, `VisitCameraZoom`), and what is asserted here is the rule the
/// gesture asks. What is *not* asserted here, and is said out loud rather than implied: that the
/// fingers reach the rule. That is the screenshot's job, and it is in the PR.
@Suite("Pinch zoom, on the viewer and on the camera")
struct ZoomTests {

    // MARK: - The photo viewer (item 4)

    /// A 3:4 photograph in a 393 × 852 pt frame — a phone photograph held upright on an iPhone 16
    /// Pro, which is what `PhotoViewerView`'s own header says the screen exists for.
    private static let box = CGSize(width: 393, height: 852)
    private static let portrait = CGSize(width: 3024, height: 4032)

    @Test("the viewer's scale is held inside its range, and a NaN is refused")
    func viewerScaleIsClamped() {
        #expect(PhotoZoom.clampScale(2.5) == 2.5)
        #expect(PhotoZoom.clampScale(0.2) == PhotoZoom.range.lowerBound)
        #expect(PhotoZoom.clampScale(99) == PhotoZoom.range.upperBound)
        // A pinch whose two touches land on one point hands over a NaN, and a NaN scale reaches the
        // layout, where it is not recoverable.
        #expect(PhotoZoom.clampScale(.nan) == PhotoZoom.range.lowerBound)
        #expect(PhotoZoom.clampScale(.infinity) == PhotoZoom.range.lowerBound)
    }

    /// The measurement the whole pan clamp rests on: `PhotoFit` letterboxes, so the drawn
    /// photograph is not the box it is drawn in.
    @Test("the fitted size is the photograph, not the frame around it")
    func fittedSizeIsTheDrawnPhotograph() {
        let fitted = PhotoZoom.fittedSize(image: Self.portrait, in: Self.box)

        #expect(fitted.height <= Self.box.height + 0.001)
        #expect(fitted.width <= Self.box.width + 0.001)
        // A 3:4 picture in a 393 × 852 box meets the *sides* first: 393 × 524, with 328 pt of
        // letterbox split above and below. If this ever reported 393 × 852 the clamp below would be
        // granting slack for bars.
        #expect(abs(fitted.width - 393) < 0.5, "fitted width was \(fitted.width)")
        #expect(abs(fitted.height - 524) < 1, "fitted height was \(fitted.height)")
        // A picture that cannot be measured is one that must not be draggable.
        #expect(PhotoZoom.fittedSize(image: .zero, in: Self.box) == .zero)
    }

    @Test("an un-zoomed photograph cannot be dragged anywhere")
    func atRestThereIsNoPan() {
        let content = PhotoZoom.fittedSize(image: Self.portrait, in: Self.box)
        let dragged = PhotoZoom.rest.panned(
            by: CGSize(width: 400, height: 400), content: content, in: Self.box
        )

        #expect(dragged == .rest, "a whole-frame photograph was dragged off its own frame")
    }

    /// The axis that is the reason for measuring the photograph rather than the box.
    ///
    /// A 3:4 picture on a 393 × 852 phone is **wider** than it is tall relative to the display: it
    /// meets the sides first and letterboxes top and bottom, so at 1.2× it has grown past the sides
    /// and is still 223 pt short of the top and bottom. The letterboxed axis is the vertical one.
    /// Clamping against the box rather than against the drawn picture would have granted 100 pt of
    /// vertical slack here, and every point of it would have dragged bar into view.
    @Test("the letterboxed axis stays centered, however far the photograph is zoomed")
    func aLetterboxedAxisStaysCentered() {
        let content = PhotoZoom.fittedSize(image: Self.portrait, in: Self.box)
        let zoomed = PhotoZoom.rest.scaled(to: 1.2, content: content, in: Self.box)
        let dragged = zoomed.panned(
            by: CGSize(width: 500, height: 500), content: content, in: Self.box
        )

        // The fixture's own preconditions, so a changed box or photograph fails here rather than
        // quietly turning the two assertions below into a different test.
        #expect(content.height * 1.2 < Self.box.height, "the fixture stopped being letterboxed")
        #expect(content.width * 1.2 > Self.box.width, "the fixture stopped overflowing the sides")
        // Had the clamp used the box, this would be up to 100 pt of bar.
        #expect(dragged.offset.height == 0, "dragged the letterbox into view")
        #expect(dragged.offset.width > 0, "could not be dragged along the axis that does overflow")
    }

    /// The coupling `PhotoZoom` exists for. Pan to a corner at 5×, pinch back to 1×, and the picture
    /// must be back in the frame — not left hanging outside it by the gesture that was putting it
    /// away.
    @Test("zooming back out pulls a panned photograph back into the frame")
    func zoomingOutRecentersWhatWasPanned() {
        let content = PhotoZoom.fittedSize(image: Self.portrait, in: Self.box)
        let cornered = PhotoZoom.rest
            .scaled(to: 5, content: content, in: Self.box)
            .panned(by: CGSize(width: 2000, height: 2000), content: content, in: Self.box)

        #expect(cornered.offset != .zero, "the fixture never left the center")

        let restored = cornered.scaled(to: 1, content: content, in: Self.box)
        #expect(restored == .rest, "a photograph was left outside its frame at 1×: \(restored)")
        #expect(restored.isAtRest)
    }

    // MARK: - The capture screen (item 5)

    private static let lens: ClosedRange<CGFloat> = 1...6

    @Test("the lens factor is held inside the device's range, and a NaN takes the floor")
    func cameraZoomIsClamped() {
        #expect(VisitCameraZoom.clamp(3, to: Self.lens) == 3)
        #expect(VisitCameraZoom.clamp(0.1, to: Self.lens) == 1)
        #expect(VisitCameraZoom.clamp(120, to: Self.lens) == 6)
        // `AVCaptureDevice` traps on a NaN `videoZoomFactor`, and a pinch can produce one.
        #expect(VisitCameraZoom.clamp(.nan, to: Self.lens) == 1)
        #expect(VisitCameraZoom.clamp(-.infinity, to: Self.lens) == 1)
    }

    /// Multiplicative, which is what makes a pinch feel like a pinch: the same hand movement is the
    /// same *proportional* change wherever it started.
    @Test("a pinch multiplies the factor it started from, and the same pinch is the same change")
    func cameraZoomIsMultiplicative() {
        #expect(VisitCameraZoom.factor(base: 1, magnification: 2, in: Self.lens) == 2)
        #expect(VisitCameraZoom.factor(base: 2, magnification: 2, in: Self.lens) == 4)
        // Doubling from 1 and doubling from 2 are both a doubling, which an additive gesture would
        // not have been.
        let fromOne = VisitCameraZoom.factor(base: 1, magnification: 2, in: Self.lens)
        let fromTwo = VisitCameraZoom.factor(base: 2, magnification: 2, in: Self.lens)
        #expect(fromTwo / fromOne == 2)
        // And it stops at the ceiling rather than running past it.
        #expect(VisitCameraZoom.factor(base: 4, magnification: 4, in: Self.lens) == 6)
    }

    /// `preferredMaxZoom` is this app's ceiling over the hardware's, and it exists to keep a
    /// volunteer from attaching an upscaled smear to a record. If it ever rose above the range the
    /// tests above assume, they would go on passing while asserting nothing about the shipped one.
    @Test("the app's own zoom ceiling is the one these cases were written against")
    func theCeilingIsWhatTheseTestsAssume() {
        #expect(VisitCameraController.preferredMaxZoom == Self.lens.upperBound)
    }
}
