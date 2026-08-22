//
//  PhotoZoom.swift
//  Cypress — Features/Photos
//
//  Where the full-screen viewer's photograph is, and how far it may be pushed.
//
//  ── Why this is a value type and not four `@State` numbers ───────────────────────────────
//  A zoom is a scale *and* an offset and the two constrain each other: zooming back out has to pull
//  a panned picture back into the frame in the same gesture, or the reader lets go and finds a
//  whole-frame photograph sitting half off the display with nothing left to drag it back with. Kept
//  as two independent `@State`s, that coupling is a rule that lives in whichever `onChanged` closure
//  happened to be written last. Kept here it is one function, and `ZoomTests` can walk it without
//  rendering anything.
//
//  ── What "clamped" means, exactly ────────────────────────────────────────────────────────
//  The pan limit is computed from the **drawn** photograph and not from the box it is drawn in.
//  `PhotoFit` letterboxes, and **which axis it letterboxes is measured rather than assumed** — the
//  first draft of this header guessed the wrong one and `ZoomTests` said so. A 3:4 phone photograph
//  on a 393 × 852 pt phone is *wider* than the display in proportion, not narrower: it meets the
//  sides first and leaves 328 pt of bar split top and bottom. So at 1.2× it has grown past both
//  sides while still falling 223 pt short of the top and the bottom, and it has no business sliding
//  vertically.
//
//  Clamping against the box would have granted that slide — 85 pt of it, measured — and every point
//  of it drags bar into view. The amount of slack the box gives is right for a photograph that fills
//  it and wrong for every other one, which is the shape of defect ERRATA E125 records on the other
//  two photo components.
//

import CoreGraphics

/// The viewer's transform over `PhotoFit`: a scale about the center, and an offset from it.
///
/// At `rest` this is the identity and the screen draws exactly what it drew before there was a zoom
/// on it.
struct PhotoZoom: Equatable {

    /// How far in the photograph may be pushed.
    ///
    /// **NOT SPECIFIED** — there is no viewer in SCREENS.md, so there is no specified zoom either
    /// (see `PhotoViewerView`'s header). The floor is 1 because the screen's own promise is the whole
    /// frame and there is nothing under 1× to see: a photograph pinched to 0.6× would be a smaller
    /// whole frame in a larger letterbox. The ceiling is 5, which on a 12 MP phone photograph in a
    /// 393pt-wide frame is still short of the file's own resolution, so the reader runs out of zoom
    /// before the picture runs out of detail and never pinches their way into a blur.
    static let range: ClosedRange<CGFloat> = 1...5

    /// Identity: the photograph as `PhotoFit` drew it.
    static let rest = PhotoZoom(scale: 1, offset: .zero)

    var scale: CGFloat
    var offset: CGSize

    /// Whether the picture is where it started, which is what the double tap restores and what
    /// decides whether a drag on this screen means anything.
    var isAtRest: Bool { self == .rest }

    // MARK: - Clamps

    /// `proposed`, held inside `range`.
    static func clampScale(_ proposed: CGFloat) -> CGFloat {
        // A pinch can hand over a NaN when the two touches land on the same point; a NaN scale
        // propagates into the offset clamp and out into the layout, where it is not recoverable.
        guard proposed.isFinite else { return range.lowerBound }
        return min(max(proposed, range.lowerBound), range.upperBound)
    }

    /// The photograph's drawn size — `image` scaled until its *longer* edge meets `box`, which is
    /// what `scaledToFit` does and therefore what is actually on screen.
    ///
    /// A zero or non-finite edge (an image that failed to decode, a box measured before layout)
    /// gives up and reports nothing drawn, which makes every pan limit below it zero. A picture that
    /// cannot be measured is one that must not be draggable.
    static func fittedSize(image: CGSize, in box: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0,
              image.width.isFinite, image.height.isFinite, box.width.isFinite, box.height.isFinite
        else { return .zero }
        let ratio = min(box.width / image.width, box.height / image.height)
        return CGSize(width: image.width * ratio, height: image.height * ratio)
    }

    /// An overflow smaller than this is no overflow. See `panLimit`.
    ///
    /// Half a point, which is under one device pixel on every screen this app runs on — so the
    /// slack it discards is slack nothing could be drawn in.
    private static let negligibleOverflow: CGFloat = 0.5

    /// How far, on each axis, the center of the photograph may travel from the center of the box.
    ///
    /// Exactly the overflow: the scaled picture is `content × scale`, the window onto it is `box`,
    /// and half of whatever the first exceeds the second by is how far it can slide before an edge
    /// comes into view. An axis with no overflow gets zero — an axis the photograph does not fill
    /// stays centered however far it is zoomed, because there is nothing off that edge to go and
    /// look at except the letterbox.
    ///
    /// **The `negligibleOverflow` floor is not decoration, and `ZoomTests` found it.** `fittedSize`
    /// divides and multiplies, so a photograph fitted to exactly the width of the box comes back as
    /// 392.999999999999 94 pt rather than 393 — and half of that discrepancy is a legal pan. The
    /// visible consequence is nil and the semantic one is not: `isAtRest` went false after a pinch
    /// out and back, so a picture that was exactly where it started reported that it was not, and
    /// anything that came to key off that would have been keying off floating-point residue.
    static func panLimit(content: CGSize, scale: CGFloat, in box: CGSize) -> CGSize {
        func limit(_ content: CGFloat, _ box: CGFloat) -> CGFloat {
            let overflow = (content * scale - box) / 2
            return overflow > negligibleOverflow ? overflow : 0
        }
        return CGSize(
            width: limit(content.width, box.width),
            height: limit(content.height, box.height)
        )
    }

    /// `proposed`, held inside `panLimit`. A non-finite proposal is refused outright rather than
    /// clamped, for `clampScale`'s reason.
    static func clampOffset(
        _ proposed: CGSize,
        content: CGSize,
        scale: CGFloat,
        in box: CGSize
    ) -> CGSize {
        guard proposed.width.isFinite, proposed.height.isFinite else { return .zero }
        let limit = panLimit(content: content, scale: scale, in: box)
        return CGSize(
            width: min(max(proposed.width, -limit.width), limit.width),
            height: min(max(proposed.height, -limit.height), limit.height)
        )
    }

    // MARK: - Gestures, as arithmetic

    /// The state a pinch to `proposed` leaves behind.
    ///
    /// **The offset is re-clamped at the new scale**, which is the coupling this type exists for:
    /// pinching back out shrinks the overflow, and an offset that was legal at 4× is off the edge at
    /// 1.5×. Without this line the picture would be left hanging outside its own frame by the
    /// gesture that was putting it back.
    func scaled(to proposed: CGFloat, content: CGSize, in box: CGSize) -> PhotoZoom {
        let scale = Self.clampScale(proposed)
        return PhotoZoom(
            scale: scale,
            offset: Self.clampOffset(offset, content: content, scale: scale, in: box)
        )
    }

    /// The state a drag of `translation` leaves behind. At rest every limit is zero, so a drag on an
    /// un-zoomed photograph moves nothing — which is why the gesture needs no `if` around it.
    func panned(by translation: CGSize, content: CGSize, in box: CGSize) -> PhotoZoom {
        let proposed = CGSize(
            width: offset.width + translation.width,
            height: offset.height + translation.height
        )
        return PhotoZoom(
            scale: scale,
            offset: Self.clampOffset(proposed, content: content, scale: scale, in: box)
        )
    }
}
