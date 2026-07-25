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

import SwiftUI

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

    var body: some View {
        Color.clear
            .overlay {
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
