//
//  PhotoCropTests.swift
//  CypressTests
//
//  What survives a crop, and what a viewer must not crop at all.
//
//  ── Why these assert on pixels ───────────────────────────────────────────────────────────
//  Because nothing else can tell the two behaviours apart. A crop anchor changes no measurement:
//  `PhotoFill` reports the box it was proposed whichever part of the photograph it keeps — that is
//  its whole documented promise — so a test on `sizeThatFits` passes identically against a centred
//  crop and a crown-anchored one. Screenshot the thing and read the colours out, or assert on
//  something that is 393×224 either way.
//
//  This project has been bitten by the second kind: the font-registration test written last week
//  would have passed against the bug it was written for, because the value it asserted on was 0 in
//  the fixed *and* the broken case. So the fixture below is built to make the difference impossible
//  to miss — three flat bands, and the question is simply which of them reached the screen.
//

#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
struct PhotoCropTests {

    // MARK: - The fixture

    /// A 300×400 portrait photograph — a phone's shape — in three flat horizontal bands:
    ///
    ///     rows 0.000 … 0.333   RED     the canopy
    ///     rows 0.333 … 0.667   GREEN   the trunk
    ///     rows 0.667 … 1.000   BLUE    the ground
    ///
    /// Flat bands rather than a drawn tree because a test has to say *which part* in one word, and
    /// "there is blue on the screen" is that word. Fully saturated primaries so no amount of colour
    /// management, interpolation or JPEG can turn one into another.
    static func bandedPortrait() -> UIImage {
        let width = 300, height = 400
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            let cg = context.cgContext
            let bands: [(CGFloat, CGFloat, CGColor)] = [
                (0.0, 1.0 / 3.0, CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                (1.0 / 3.0, 2.0 / 3.0, CGColor(red: 0, green: 1, blue: 0, alpha: 1)),
                (2.0 / 3.0, 1.0, CGColor(red: 0, green: 0, blue: 1, alpha: 1)),
            ]
            for (top, bottom, colour) in bands {
                cg.setFillColor(colour)
                cg.fill(CGRect(
                    x: 0,
                    y: CGFloat(height) * top,
                    width: CGFloat(width),
                    height: CGFloat(height) * (bottom - top)
                ))
            }
        }
    }

    /// The hero's box on screen 03: the full width of a 393 pt phone, at §2 C2's 224 pt height.
    /// Every fixed photo frame in the app is this shape or wider, so it is the shape the crop
    /// question is asked in.
    static let heroBox = CGSize(width: 393, height: 224)

    /// A colour no band uses, so "this pixel is backdrop" is decidable.
    static let backdrop = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    // MARK: - The crop anchor

    @Test("A crown-anchored crop of a portrait tree keeps the canopy and spends nothing on the ground")
    func crownAnchorKeepsTheCanopy() async throws {
        let sheet = try #require(await Self.render(anchor: .crown))

        #expect(
            sheet.contains(.red),
            "the top band — the canopy — did not reach the screen at all"
        )
        #expect(
            !sheet.contains(.blue),
            """
            the bottom third of the photograph (the ground) is on screen, so the crop is not \
            crown-anchored: at 393×224 a 3:4 photograph has only 42.7% of its height to spend and \
            spending any of it below row 0.667 means that much less canopy. Sampled bottom-centre \
            pixel: \(sheet.describe(x: 0.5, y: 0.97)).
            """
        )
        #expect(
            sheet.band(x: 0.5, y: 0.97) == .green,
            "the foot of the hero should be trunk; it is \(sheet.describe(x: 0.5, y: 0.97))"
        )
    }

    /// The other half of the same assertion, and the thing that makes the one above meaningful: the
    /// two anchors have to actually differ. If this passed with the same colours as the test above,
    /// both would be measuring nothing.
    @Test("A centred crop of the same photograph reaches the ground, which is what was reported")
    func centreAnchorReachesTheGround() async throws {
        let sheet = try #require(await Self.render(anchor: .centre))

        #expect(
            sheet.contains(.blue),
            """
            `.centre` is SwiftUI's own default and the behaviour that was reported; if the ground \
            no longer reaches the screen through it, the two anchors have stopped differing and \
            `crownAnchorKeepsTheCanopy` is asserting on nothing.
            """
        )
        #expect(
            sheet.band(x: 0.5, y: 0.97) == .blue,
            "expected the foot of a centred crop to be ground; it is \(sheet.describe(x: 0.5, y: 0.97))"
        )
    }

    @Test("Screen 04's centre anchor is not the default, so it cannot be changed by accident")
    func theCameraScreenMustAskForCentre() {
        // `PhotoCropAnchor.centre` exists for the ghost overlay, which has to agree with an
        // `AVCaptureVideoPreviewLayer` this app does not get to reconfigure. Stated as a test so
        // that "the default is the crown" is a fact the suite holds rather than a comment.
        #expect(PhotoFill(image: Self.bandedPortrait()).anchor == .crown)
    }

    // MARK: - The viewer

    @Test("The viewer shows the whole photograph, letterboxed, at the shape of the file")
    func photoFitCropsNothing() async throws {
        let sheet = try #require(await Self.render(fit: true))

        // Every band is on screen. This is the report — "should show full view" — as an assertion.
        #expect(sheet.contains(.red), "the viewer cropped the top of the photograph away")
        #expect(sheet.contains(.green), "the viewer is not drawing the middle of the photograph")
        #expect(sheet.contains(.blue), "the viewer cropped the bottom of the photograph away")

        // And the picture is still its own shape rather than the box's: a portrait photograph in a
        // landscape box has bars down both sides, and the lit part is 3:4.
        #expect(
            sheet.band(x: 0.02, y: 0.5) == .backdrop && sheet.band(x: 0.98, y: 0.5) == .backdrop,
            "a 3:4 photograph in a 393×224 box must letterbox; the box is lit to both edges instead"
        )
        let drawn = try #require(sheet.drawnBounds(), "nothing but backdrop was drawn")
        let aspect = drawn.width / drawn.height
        #expect(
            abs(aspect - 0.75) < 0.03,
            "the photograph is drawn at \(aspect) rather than its own 0.75 — it has been stretched"
        )
    }

    /// The contrast that names the defect: one component through the other, same photograph, same
    /// box. A fill has no bars and has lost a third of the picture; a fit has bars and has lost none.
    @Test("A filled frame loses what a fitted frame keeps — the same photograph, the same box")
    func fillAndFitDisagreeAboutTheSamePhotograph() async throws {
        let filled = try #require(await Self.render(anchor: .crown))
        let fitted = try #require(await Self.render(fit: true))

        #expect(filled.band(x: 0.02, y: 0.5) != .backdrop, "a fill must reach the edge of its box")
        #expect(fitted.band(x: 0.02, y: 0.5) == .backdrop, "a fit must not")
        #expect(!filled.contains(.blue) && fitted.contains(.blue))
    }

    @Test("PhotoFit reports the box it was offered, exactly as PhotoFill does")
    func photoFitReportsTheProposal() {
        // The guarantee `PhotoFill` was written for (ERRATA E125), restated for the new component:
        // `scaledToFit` cannot overflow, but a photograph narrower than its box would still report
        // its own width and leave the letterbox no bars to draw.
        let proposal = CGSize(width: 393, height: 852)
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            PhotoFit(image: Self.bandedPortrait())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Color.clear.frame(height: 100)
        })
        #expect(host.sizeThatFits(in: proposal).width == proposal.width)
    }

    // MARK: - Rendering

    /// Draws one component over a known backdrop, through a real hosting controller in a real
    /// window, and reads the pixels back.
    ///
    /// A hosting controller rather than `ImageRenderer`, for the reason
    /// `DynamicTypeScreenshotTests.render` sets out at length: `ImageRenderer` lays views out and
    /// then declines to draw parts of them, which here would be indistinguishable from a crop.
    static func render(anchor: PhotoCropAnchor? = nil, fit: Bool = false) async -> PixelSheet? {
        let image = Self.bandedPortrait()
        let content = ZStack {
            Color(cgColor: Self.backdrop)
            if fit {
                PhotoFit(image: image)
            } else {
                PhotoFill(image: image, anchor: anchor ?? .crown)
            }
        }
        .frame(width: Self.heroBox.width, height: Self.heroBox.height)
        .clipped()

        let host = UIHostingController(rootView: content)
        let frame = CGRect(origin: .zero, size: Self.heroBox)
        host.view.frame = frame

        let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: frame.width, height: frame.height))
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(60))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        let shot = UIGraphicsImageRenderer(bounds: frame).image { _ in
            host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil

        return PixelSheet(shot)
    }
}

// MARK: - Reading pixels back

/// Which of the fixture's bands a pixel came from.
enum PhotoBand: Equatable {
    case red, green, blue, backdrop, other

    /// Classified by dominant channel with a wide margin, so antialiasing along a band edge lands in
    /// `.other` rather than being miscalled as a neighbour.
    static func of(red r: Double, green g: Double, blue b: Double) -> PhotoBand {
        if r < 0.2, g < 0.2, b < 0.2 { return .backdrop }
        if r > 0.6, g < 0.4, b < 0.4 { return .red }
        if g > 0.6, r < 0.4, b < 0.4 { return .green }
        if b > 0.6, r < 0.4, g < 0.4 { return .blue }
        return .other
    }
}

/// A rendered frame, addressable in fractions of its own size so the assertions read in the same
/// units the crop arithmetic is done in.
struct PixelSheet {
    private let bytes: [UInt8]
    private let width: Int
    private let height: Int

    init?(_ image: UIImage) {
        guard let source = image.cgImage else { return nil }
        width = source.width
        height = source.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// The band at a point given as fractions of the frame — `(0.5, 0.97)` is bottom-centre.
    func band(x: Double, y: Double) -> PhotoBand {
        let column = min(width - 1, max(0, Int(x * Double(width))))
        let row = min(height - 1, max(0, Int(y * Double(height))))
        let offset = (row * width + column) * 4
        return PhotoBand.of(
            red: Double(bytes[offset]) / 255,
            green: Double(bytes[offset + 1]) / 255,
            blue: Double(bytes[offset + 2]) / 255
        )
    }

    func describe(x: Double, y: Double) -> String { String(describing: band(x: x, y: y)) }

    /// Whether any pixel in the frame came from that band. Sampled on a grid rather than every
    /// pixel — a band that reached the screen at all occupies a full-width stripe, so a 60×60 net
    /// cannot pass through one.
    func contains(_ band: PhotoBand) -> Bool {
        for row in stride(from: 0.005, to: 1.0, by: 1.0 / 60.0) {
            for column in stride(from: 0.005, to: 1.0, by: 1.0 / 60.0) where self.band(x: column, y: row) == band {
                return true
            }
        }
        return false
    }

    /// The rectangle, in points of the frame, actually covered by the photograph rather than by the
    /// backdrop behind it. `nil` when nothing was drawn.
    func drawnBounds() -> CGRect? {
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        let step = 1.0 / 200.0
        for row in stride(from: 0.0, to: 1.0, by: step) {
            for column in stride(from: 0.0, to: 1.0, by: step) {
                let band = band(x: column, y: row)
                guard band != .backdrop, band != .other else { continue }
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return CGRect(
            x: minX * Double(width),
            y: minY * Double(height),
            width: (maxX - minX) * Double(width),
            height: (maxY - minY) * Double(height)
        )
    }
}
#endif
