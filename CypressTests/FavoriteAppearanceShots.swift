#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// Photographs C8's first cell in both of its states (RULINGS R2, ERRATA E112).
///
/// **Why this is a rendered test and not a walk through the simulator.** R2 is a visual state and it
/// has to be looked at. It cannot be looked at by launching the app: the quad row is drawn only on
/// the warm variant of screen 03, and per D8 *every* tree in the shipped seed renders the cold
/// variant, because the city inventory carries no community content at all. There is no tap sequence
/// on a fresh install that puts the row on screen. The `#if DEBUG` fixture that stands a populated
/// profile up beside a real seed row is the only place the row exists, which makes rendering it the
/// honest way to see it — the same argument, in the same words, that `DynamicTypeScreenshotTests`
/// makes for the other eighteen screens.
///
/// It asserts almost nothing, deliberately, for that suite's reason: ARCHITECTURE §7 says snapshot
/// testing against the mocks is not set up, and a baseline-free snapshot suite passes on a blank
/// image. What it asserts is that an image was produced; the images are the output, and the paths
/// are printed for a reviewer.
@MainActor
@Suite("Screen 03 · the favourite cell, photographed")
struct FavoriteAppearanceShots {

    @Test("the quad row renders in both states, light and dark")
    func bothStates() async {
        let shots: [(name: String, favourite: Bool, scheme: ColorScheme)] = [
            ("03-favorite-off-light", false, .light),
            ("03-favorite-on-light", true, .light),
            ("03-favorite-off-dark", false, .dark),
            ("03-favorite-on-dark", true, .dark),
        ]

        for shot in shots {
            let rendered = await DynamicTypeScreenshotTests.render(shot.name, .large, scheme: shot.scheme) {
                TreeProfileView(
                    treeID: TreeProfileSeedFixtures.populated.tree.id,
                    api: TreeProfilePreviewAPI(
                        profile: TreeProfileSeedFixtures.populated,
                        isFavorite: shot.favourite
                    ),
                    caretakerInitials: ["N", "M", "J"]
                )
            }
            #expect(rendered != nil, "\(shot.name) produced no image")
        }
    }
}
#endif
