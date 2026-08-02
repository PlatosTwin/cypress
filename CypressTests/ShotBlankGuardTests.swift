//
//  ShotBlankGuardTests.swift
//  CypressTests
//
//  Proof the blank-capture guard can fail (task #93). The previous guard had never been seen
//  rejecting anything — it had "the shape of the bug it fixed" — so every blank mode E145 and
//  this ticket name is stood up here for real: a flat fill, a fully transparent frame, a
//  zero-size image, an unreadable readback, a near-flat frame under the unique-color floor,
//  and a featureless capture pushed through each harness end to end.
//

#if DEBUG
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("The blank-capture guard, made to say no")
struct ShotBlankGuardTests {

    // MARK: - Bitmaps with known pixel content

    /// A 16 × 16, scale-1 image of horizontal bands, one solid color per band, pixel-aligned so
    /// no antialiasing invents extra colors. `colors.count` is exactly the unique-color count.
    private static func banded(_ colors: [UIColor]) -> UIImage {
        let side = ShotBlankGuard.side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bandHeight = side / colors.count
            for (index, color) in colors.enumerated() {
                color.setFill()
                let top = index * bandHeight
                let bottom = index == colors.count - 1 ? side : top + bandHeight
                context.fill(CGRect(x: 0, y: top, width: side, height: bottom - top))
            }
        }
    }

    // MARK: - The blank modes, one by one

    @Test("a solid fill is blank — the mode the first guard was written against")
    func solidFillIsBlank() {
        let verdict = ShotBlankGuard.verdict(for: Self.banded([.systemRed]))
        #expect(verdict.isBlank, "one flat color passed the guard: \(verdict)")
    }

    @Test("a fully transparent frame is blank — E145's actual output past 8,192 px")
    func transparentFrameIsBlank() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let transparent = UIGraphicsImageRenderer(
            size: CGSize(width: 393, height: 852), format: format
        ).image { _ in
            // Draw nothing, exactly as drawHierarchy does past its backing-store ceiling.
        }
        let verdict = ShotBlankGuard.verdict(for: transparent)
        #expect(verdict.isBlank, "a frame of nothing passed the guard: \(verdict)")
    }

    @Test("a zero-size image is blank, not a crash and not a pass")
    func zeroSizeIsBlank() {
        #expect(ShotBlankGuard.verdict(for: UIImage()).isBlank)
    }

    @Test("an unreadable readback fails CLOSED — the first guard's three open exits")
    func unreadableReadbackIsBlank() {
        let verdict = ShotBlankGuard.verdict(reading: nil)
        #expect(verdict.isBlank, "no CGImage must mean blank, never \"fine\": \(verdict)")
    }

    @Test("the unique-color floor is a fact: 3 flat bands fail, 4 pass")
    func floorIsExactlyFour() {
        let three = ShotBlankGuard.verdict(
            for: Self.banded([.black, .white, .systemRed])
        )
        #expect(three.isBlank, "3 unique colors is under the floor of 4, got \(three)")

        let four = ShotBlankGuard.verdict(
            for: Self.banded([.black, .white, .systemRed, .systemBlue])
        )
        #expect(four == .ok(uniqueColors: 4), "4 unique colors meets the floor, got \(four)")
    }

    @Test("a real screen-shaped image passes — the guard must not cry blank at content")
    func contentPasses() {
        // A gradient the way a screen is: many values, smeared edges.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let content = UIGraphicsImageRenderer(
            size: CGSize(width: 393, height: 852), format: format
        ).image { context in
            for row in 0..<32 {
                UIColor(white: CGFloat(row) / 32, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row * 27, width: 393, height: 27))
            }
        }
        let verdict = ShotBlankGuard.verdict(for: content)
        #expect(!verdict.isBlank, "a 32-band gradient was called blank: \(verdict)")
    }

    // MARK: - The write path

    @Test("zero bytes is a failed write, not a written file")
    func emptyDataFailsWrite() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shot-guard-empty-\(UUID().uuidString).png")
        #expect(!ShotBlankGuard.write(Data(), to: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("an unwritable destination is a failed write, loudly")
    func unwritableDestinationFailsWrite() {
        let url = URL(fileURLWithPath: "/no-such-root-\(UUID().uuidString)/shot.png")
        #expect(!ShotBlankGuard.write(Data([0x89, 0x50, 0x4E, 0x47]), to: url))
    }

    @Test("a good write is confirmed against the bytes on disk")
    func goodWriteSucceeds() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shot-guard-good-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(ShotBlankGuard.write(data, to: url))
        #expect(try Data(contentsOf: url) == data)
    }

    // MARK: - End to end: each harness refuses a featureless capture

    /// `Color.clear` over the harness's own `surfaceScreen` background is one flat color — the
    /// closest a real capture path can come to E145's output without breaking the renderer. Both
    /// harnesses must return nil AND leave no PNG behind: a rejected capture that still writes
    /// its file is evidence planted for a reviewer.
    @MainActor
    @Test("ScreenSweepShots.capture refuses a featureless view and writes nothing")
    func sweepHarnessFailsClosed() async {
        let name = "guard-probe-sweep-blank"
        let url = ScreenSweepShots.outputDirectory.appendingPathComponent("\(name).png")
        try? FileManager.default.removeItem(at: url)
        let image = await ScreenSweepShots.capture(name, size: .large, scheme: .light) {
            Color.clear
        }
        #expect(image == nil, "a one-color capture came back as an image")
        #expect(!FileManager.default.fileExists(atPath: url.path), "the rejected capture was still written")
    }

    @MainActor
    @Test("DynamicTypeScreenshotTests.render refuses a featureless view and writes nothing")
    func dynamicTypeHarnessFailsClosed() async {
        let name = "guard-probe-render-blank"
        let url = DynamicTypeScreenshotTests.outputDirectory.appendingPathComponent("\(name).png")
        try? FileManager.default.removeItem(at: url)
        let rendered = await DynamicTypeScreenshotTests.render(name, .large) {
            Color.clear
        }
        #expect(rendered == nil, "a one-color render came back as a size")
        #expect(!FileManager.default.fileExists(atPath: url.path), "the rejected render was still written")
    }

    /// And the positive control for the pair above: the same harness, handed actual content,
    /// still produces an image — so the two refusals are the guard's doing, not a broken window.
    @MainActor
    @Test("ScreenSweepShots.capture still accepts a view with content")
    func sweepHarnessStillPassesContent() async {
        let name = "guard-probe-sweep-content"
        let image = await ScreenSweepShots.capture(name, size: .large, scheme: .light) {
            VStack(spacing: 0) {
                ForEach(0..<16, id: \.self) { row in
                    Color(white: Double(row) / 16).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        #expect(image != nil, "a 16-band view was rejected as blank")
    }
}
#endif
