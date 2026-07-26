//
//  PhotoFill.swift
//  Cypress — DesignSystem/Components
//
//  One photograph, filling the box it is given, and — this is the whole point — **never reporting a
//  size larger than the box**.
//
//  ── The bug this exists to make unwritable ────────────────────────────────────────────────
//  `Image.resizable().scaledToFill()` does not clip and does not clamp: it reports the *scaled*
//  size, which for a portrait phone photo is far wider than the width it was offered. Inside a
//  `ZStack` that measurement becomes the stack's, the stack's becomes its parent's, and every
//  sibling laid out against it is stretched to a width the display does not have.
//
//  On screen 04 that is not theoretical. Measured, at a 393×852 proposal, with a 3024×4032 photo:
//
//      naive ZStack + scaledToFill … 627 × 852     ← 234 pt of note field and "Log visit" off-screen
//      this component            … 393 × 852
//
//  which is exactly the report that found it: once the ghost overlay appeared, the note box and the
//  Log visit button ran off the right edge and were cut off (ERRATA E125).
//
//  `Color.clear` is the fix and it is not a trick. A colour takes the size it is proposed and no
//  other, an `.overlay` is sized by its parent rather than the other way round, and `.clipped()`
//  keeps the overspill inside. So the reported size is the proposal, always, whatever the aspect
//  ratio of the photograph — the same guarantee `.aspectRatio(contentMode: .fill)` cannot give.
//
//  ── The second half of the same bug, found on screen 20 (ERRATA E125) ─────────────────────
//  `.clipped()` clips *drawing*. It does not clip *touches*: the overflowing `Image` keeps its own
//  scaled layout footprint for hit testing, and SwiftUI will happily route a tap to a view whose
//  pixels were never painted. The overhang is not small — measured on screen 20, a 361 pt wide box
//  217 pt tall holding a 3:4 photograph reports an element 361 × 481.3, so 132 pt of invisible photo
//  hangs off the top and another 132 off the bottom.
//
//  In a list that is fatal, and silently. Screen 20 stacks a photograph, then its caption row with
//  two thumb buttons, then the next photograph. The next photograph is *later* in the `VStack`, so
//  it is later in z-order, so its invisible lower overhang sits on top of the previous card's thumbs
//  and swallows every tap on them. Every thumb in the list was dead except the two on the last card,
//  which is the one with nothing drawn after it — measured exactly that way before this line existed.
//  Nothing looked wrong, nothing errored, and no vote was ever written.
//
//  `.contentShape(Rectangle())` is the answer, and it belongs here rather than at the call site: the
//  promise this component makes is that a photograph occupies the box it was given and not one pixel
//  more, and a touch footprint is one of the ways a view occupies space. A caller that has to
//  remember to fence off its own photograph has not been given that promise.
//
//  ── Which part of the photograph survives the crop (ERRATA E141) ──────────────────────────
//  **NOT SPECIFIED.** SCREENS.md gives the hero a height (§2 C2 — 224 px on 03) and never says which
//  part of the photograph that height is taken from. The default was `.center`, which is SwiftUI's,
//  and nobody chose it.
//
//  It is the wrong default *for this app*, and the arithmetic says why. A phone photograph held
//  upright is 3:4. Scaled to fill a 393 pt wide hero it is 524 pt tall, of which 224 is drawn — 43%
//  of the picture, taken from the middle, so rows 28.5% to 71.5% survive and everything outside them
//  is thrown away. A street tree photographed from the pavement has its crown in the top third and
//  its trunk and the kerb in the bottom third; the middle 43% of that frame is upper trunk and the
//  underside of the canopy. The crown — the part that says which species this is, and whether it is
//  in leaf, in flower or dead — is exactly the part a centred crop removes. The tree is tall and
//  portrait is the right way to photograph it, so this is the common case and not an edge one.
//
//  So the default anchor is the crown: the alignment guide sits one third of the way down both the
//  box and the photograph, which on the numbers above keeps rows 19% to 62% — the canopy and the top
//  of the trunk. A third rather than the top edge because `.top` is sky: a photographer framing a
//  whole tree leaves headroom above the crown, and an anchor that keeps the headroom and drops the
//  tree has swapped one bad crop for another.
//
//  `.centre` stays available and screen 04 uses it, for a reason that is not taste — see
//  `PhotoCropAnchor.centre`.
//

import SwiftUI

/// Which part of a photograph survives being cropped to a box that is a different shape.
///
/// Vertical only. Every fixed frame in this app is wider than a phone photograph is, so the crop
/// that matters is the one along the tall edge; the horizontal crop of a landscape shot takes
/// equally from two sides of a subject that is centred in the frame anyway.
enum PhotoCropAnchor {

    /// One third of the way down: the canopy and the top of the trunk. The default, and the reason
    /// is in this file's header.
    case crown

    /// The middle of the photograph — SwiftUI's own default.
    ///
    /// **Screen 04 needs this and must keep it.** The camera screen draws the frame just taken and,
    /// under it, a 30% ghost of the last visit's photograph, and the whole point of the screen is
    /// that the two line up. It draws both through `PhotoFill`, and behind them a live
    /// `AVCaptureVideoPreviewLayer` whose `videoGravity` is `.resizeAspectFill` — which centres, and
    /// is not a thing this app gets to change. An anchor that disagrees with the layer would move
    /// the crown of the ghost away from the crown in the viewfinder, which is the one measurement
    /// that screen exists to make.
    case centre

    var alignment: Alignment {
        switch self {
        case .crown: return Alignment(horizontal: .center, vertical: .photoCrown)
        case .centre: return .center
        }
    }
}

/// The fraction of the way down a photograph — and of the way down the box it is drawn in — that the
/// crown anchor pins together.
///
/// Not a spacing, a font size or a radius, so it is not one of the token families ARCHITECTURE §6
/// names; it is named and stated once here rather than written as a literal at a call site, which is
/// the rule that section is an instance of.
private enum PhotoCrownAlignment: AlignmentID {
    static let fraction: CGFloat = 1.0 / 3.0
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height * fraction
    }
}

extension VerticalAlignment {
    /// One third of the way down whatever it is asked about — the box, and the photograph over it.
    static let photoCrown = VerticalAlignment(PhotoCrownAlignment.self)
}

/// A photo drawn to fill its box, cropped to it, reporting the size it was proposed.
///
/// Decorative by default: a photograph of a tree on a screen that already names the tree in text
/// says nothing to a listener that the text does not. Callers that *are* showing the photograph as
/// the subject — the browser on screen 20, where the picture is the thing being judged — pass a
/// label and get an image element instead.
struct PhotoFill: View {

    let image: UIImage
    /// `nil` — the default — hides it from VoiceOver as decoration.
    var label: String?
    /// Which part of the photograph survives the crop. See `PhotoCropAnchor`.
    var anchor: PhotoCropAnchor = .crown

    var body: some View {
        Color.clear
            .overlay(alignment: anchor.alignment) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            // Touches stop where the drawing does. Without this the unpainted overhang of a
            // `scaledToFill` photograph stays hittable and covers whatever the layout put after it
            // (ERRATA E125).
            .contentShape(Rectangle())
            .modifier(PhotoFillAccessibility(label: label))
    }
}

/// Two different accessibility treatments, applied without an `if` that would change the view's
/// type — and therefore its identity — between them.
private struct PhotoFillAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
