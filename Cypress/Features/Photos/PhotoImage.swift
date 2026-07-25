//
//  PhotoImage.swift
//  Cypress — Features/Photos
//
//  One photograph, wherever a screen wants one: it asks the store, draws the pixels when they
//  arrive, and draws the gradient the screen used to draw permanently when they do not (E37, E125).
//
//  The store arrives through the environment rather than as an argument, and optionally, for the
//  reason `router` does: every screen that shows a photograph would otherwise have to thread it
//  through its model, and every fixture would have to invent one. A `nil` store is a legitimate
//  state — a preview, a contact sheet — and it renders as the placeholder, which is what those
//  fixtures were rendering before this existed.
//

import SwiftUI

/// A photograph identified by its row, filling the box it is given.
struct PhotoImage: View {

    let photoID: UUID
    /// The gradient drawn while the bytes are loading, or in place of a photograph whose bytes are
    /// gone. Defaults to the profile hero's, which is the recipe these screens have always drawn.
    var placeholder: CypressGradientRecipe = CypressGradient.heroProfile
    /// Passed to `PhotoFill`. Decorative by default; the browser names its photographs.
    var label: String?

    @Environment(PhotoImageStore.self) private var store: PhotoImageStore?

    var body: some View {
        Group {
            if let image = store?.image(photoID) {
                PhotoFill(image: image, label: label)
            } else {
                CypressGradientField(placeholder)
                    .accessibilityHidden(true)
            }
        }
        // Keyed on the id, so a recycled row in a scroll view loads its own photograph rather than
        // keeping the one the cell had before.
        .task(id: photoID) { await store?.load(photoID) }
    }
}
