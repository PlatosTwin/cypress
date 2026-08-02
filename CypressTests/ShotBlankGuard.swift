//
//  ShotBlankGuard.swift
//  CypressTests
//
//  The blank-capture guard for every screenshot harness in this target (task #93).
//
//  ── Why this exists ─────────────────────────────────────────────────────────────────────────
//  ERRATA E145: `drawHierarchy` into an off-screen window stops producing pixels past ~8,192 px of
//  backing store and hands back a fully transparent image instead of failing, so five PNGs of
//  nothing were written and every `#expect` around them passed. The first guard written against
//  that defect failed open in three ways of its own:
//    1. every unreadable-thumbnail exit returned "not blank",
//    2. its byte scan compared the whole `CFData` buffer — row padding included — against the
//       first pixel, so a padded buffer could declare a uniform image "not blank",
//    3. nothing anywhere proved it could reject a known-blank image.
//  `DynamicTypeScreenshotTests.render`, the older harness, had no guard at all.
//
//  ── The rule ────────────────────────────────────────────────────────────────────────────────
//  Fail CLOSED. Any capture this guard cannot positively read is treated as blank, because the
//  readback runs through the same renderer machinery the guard exists to distrust. A verdict is
//  a fact with a reason attached, so a red run says *which* way the capture was bad.
//

#if DEBUG
import CoreGraphics
import Foundation
import UIKit

/// What the guard concluded about one capture, with the fact that decided it.
enum ShotVerdict: Equatable {
    /// The capture has at least `ShotBlankGuard.minimumUniqueColors` distinct pixel values in its
    /// downscaled thumbnail.
    case ok(uniqueColors: Int)
    /// The capture must fail the test. The reason is printed by the harness.
    case blank(reason: String)

    var isBlank: Bool {
        if case .blank = self { return true }
        return false
    }
}

enum ShotBlankGuard {

    /// The thumbnail edge. 16 × 16 = 256 samples; a full 1,179 × 10,800 buffer is 50 MB and this
    /// runs on every capture.
    static let side = 16

    /// The unique-color floor, counted over the 256 thumbnail samples.
    ///
    /// The facts on each side of the line: every blank mode E145 produced — the transparent
    /// over-tall capture, a window that never drew, a solid fill — downscales to exactly **1**
    /// unique value. Every real screen in this app downscales to dozens: even the darkest (04's
    /// camera) has controls, and bilinear downscaling smears every edge into intermediate colors.
    /// Four is far above everything blank and far below everything real, so a capture between the
    /// two is *suspicious by definition* — a frame with at most three flat regions and no
    /// antialiased edge anywhere is not a screen this app draws.
    static let minimumUniqueColors = 4

    /// Judges a full-size capture by downscaling it and reading the pixels back.
    static func verdict(for image: UIImage) -> ShotVerdict {
        guard image.size.width > 0, image.size.height > 0 else {
            return .blank(reason: "the capture has zero size")
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // 16 pt must mean 16 px, or the sample count depends on the device.
        let size = CGSize(width: side, height: side)
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return verdict(reading: thumbnail.cgImage)
    }

    /// Judges a readback bitmap directly. Split out so the unreadable paths are testable —
    /// `verdict(for:)` always hands this a renderer-produced `CGImage`, but the whole point of
    /// task #93 is that "the renderer produced it" is not a reason to trust it.
    static func verdict(reading cgImage: CGImage?) -> ShotVerdict {
        guard let cgImage else {
            return .blank(reason: "the readback thumbnail has no CGImage — treated as blank, not as fine")
        }
        guard let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return .blank(reason: "the readback thumbnail's pixel buffer is unreadable — treated as blank")
        }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 1 else {
            return .blank(reason: "sub-byte pixel format (\(cgImage.bitsPerPixel) bpp) — unreadable, treated as blank")
        }
        let bytesPerRow = cgImage.bytesPerRow
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
              CFDataGetLength(data) >= (height - 1) * bytesPerRow + width * bytesPerPixel else {
            return .blank(reason: "the readback buffer is smaller than its own geometry claims — treated as blank")
        }

        // Walk pixels, not the raw buffer: rows may be padded past `width × bytesPerPixel`, and
        // padding bytes are garbage that must not count as image content.
        var unique = Set<[UInt8]>()
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * bytesPerRow + column * bytesPerPixel
                var pixel = [UInt8](repeating: 0, count: bytesPerPixel)
                for byte in 0..<bytesPerPixel { pixel[byte] = bytes[offset + byte] }
                unique.insert(pixel)
                if unique.count >= minimumUniqueColors {
                    return .ok(uniqueColors: unique.count)
                }
            }
        }
        return .blank(
            reason: "only \(unique.count) unique color\(unique.count == 1 ? "" : "s") in the \(width)×\(height) readback"
                + " (floor is \(minimumUniqueColors)) — a flat or near-flat frame, not a screen"
        )
    }

    /// Writes a capture's PNG and confirms the bytes landed. A `try?` here was the last silent
    /// exit: a failed write left no file, the harness printed the path anyway, and the test passed
    /// on evidence that did not exist.
    static func write(_ data: Data, to url: URL) -> Bool {
        guard !data.isEmpty else {
            print("EMPTY PNG \(url.lastPathComponent) — zero bytes, nothing written")
            return false
        }
        do {
            try data.write(to: url)
        } catch {
            print("WRITE FAILED \(url.path) — \(error)")
            return false
        }
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber,
            size.intValue == data.count else {
            print("WRITE FAILED \(url.path) — file on disk does not match the \(data.count) bytes written")
            return false
        }
        return true
    }
}
#endif
