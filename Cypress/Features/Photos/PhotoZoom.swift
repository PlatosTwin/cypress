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
//  happened to be written last. Kept here it is one function, and `PhotoZoomTests` can walk it
//  without rendering anything.
//
//  ── What "clamped" means, exactly ────────────────────────────────────────────────────────
//  The pan limit is computed from the **drawn** photograph and not from the box it is drawn in.
//  `PhotoFit` letterboxes: a portrait photograph on a portrait phone is short of the sides, so at
//  1.6× it may have grown taller than the display while still being narrower than it, and it has no
//  business sliding sideways. Clamping against the box would have allowed exactly that — the amount
//  of slack would have been right for a photograph that filled the box and wrong for every other
//  one, which is the shape of defect ERRATA E125 records on the other two photo components.
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

    /// How far, on each axis, the center of the photograph may travel from the center of the box.
    ///
    /// Exactly the overflow: the scaled picture is `content × scale`, the window onto it is `box`,
    /// and half of whatever the first exceeds the second by is how far it can slide before an edge
    /// comes into view. An axis with no overflow gets zero — a photograph narrower than the display
    /// stays centered horizontally however far it is zoomed, because there is nothing off the side
    /// to go and look at.
    static func panLimit(content: CGSize, scale: CGFloat, in box: CGSize) -> CGSize {
        CGSize(
            width: max(0, (content.width * scale - box.width) / 2),
            height: max(0, (content.height * scale - box.height) / 2)
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
