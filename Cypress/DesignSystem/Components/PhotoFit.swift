//
//  PhotoFit.swift
//  Cypress — DesignSystem/Components
//
//  One photograph, whole, at its own shape, inside the box it is given — and, like `PhotoFill`
//  beside it, **never reporting a size larger than that box**.
//
//  ── NOT SPECIFIED ────────────────────────────────────────────────────────────────────────
//  SCREENS.md has no component that shows an uncropped photograph, because until now no screen did.
//  Every photograph in the app went through `PhotoFill` into a fixed frame. That is right for a hero
//  and right for a row in a browser — a list whose rows change height is a list nobody can scan —
//  and it is wrong for the two places where the photograph is not decoration but the subject:
//
//  1. the full-screen viewer, where the tap that opened it means *let me see it*, and
//  2. the well on screen 14, where the picture is a volunteer checking what they actually captured
//     before they commit it.
//
//  In both, a crop is not a layout, it is a lie about what the file contains.
//
//  ── Why a second component and not a flag on `PhotoFill` ─────────────────────────────────
//  `PhotoFill`'s whole documented promise is that the photograph *fills* the box and is *cropped* to
//  it; ERRATA E125 is two separate bugs that came from that promise being only half kept. A boolean
//  that turns the promise off leaves one type whose header argues for a behaviour it may not have,
//  and leaves every reader of a call site to work out which one they are looking at. Two types, each
//  named for what it does, cost one file.
//
//  ── What it keeps from `PhotoFill`, and why ──────────────────────────────────────────────
//  The `Color.clear` base. `scaledToFit` cannot overflow, so there is nothing here to clip — but it
//  can still report a size *smaller* than the proposal along one axis, and a letterbox that shrinks
//  to the picture is not a letterbox. Sizing from `Color.clear` means the backdrop is the box, the
//  photograph is centred in it, and the bars are wherever the shape says they are.
//
//  The `contentShape`. A viewer wants its whole backdrop to answer a tap, not just the lit part.
//

import SwiftUI

/// A photo drawn whole inside its box, letterboxed, reporting the size it was proposed.
///
/// Decorative by default, on the same reasoning as `PhotoFill`: the screens that show a photograph
/// as the subject name it, and pass a label.
struct PhotoFit: View {

    let image: UIImage
    /// `nil` — the default — hides it from VoiceOver as decoration.
    var label: String?

    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    // The one line this component exists for. `.fit` scales until the *longer* edge
                    // meets the box, so a portrait photograph in a landscape box is short of the
                    // sides and a landscape photograph in a tall box is short of the top and
                    // bottom. Nothing leaves the frame in either direction.
                    .scaledToFit()
            }
            .contentShape(Rectangle())
            .modifier(PhotoFitAccessibility(label: label))
    }
}

/// The same two treatments `PhotoFill` applies, applied the same way — without an `if` that would
/// change the view's type, and therefore its identity, between them.
private struct PhotoFitAccessibility: ViewModifier {
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
