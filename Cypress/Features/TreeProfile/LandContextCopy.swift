//
//  LandContextCopy.swift
//  Cypress — Features/TreeProfile
//
//  The words for `LandContext` as a *value a contributor picks*, in one place, because one act must
//  have one name.
//
//  ── Why the vocabulary is here and not in `Core` ──────────────────────────────────────────────
//  `Core` is pure Foundation and holds no display strings anywhere in this app — `CareAction` is
//  spelled out by `TreeProfilePresentation`, `HazardCategory` by `HazardCategoryLabel`. This follows
//  that. `PinSetCopy` is the same arrangement seen from the other side — the screen that owns the
//  concept owns the sentence, and other features reach in.
//
//  ── What is here, and what is deliberately not ────────────────────────────────────────────────
//  The composer's chips and the sentence above them. The tree profile does *not* read from this
//  file: it states the ground in prose that names whoever concluded it, and those two sentences are
//  `TreeProfileCopy.landContextInferred`/`landContextStated`. That is not an oversight — a noun and
//  a prepositional phrase are different grammar, and the screen that has to attribute a claim needs
//  the phrase. See `TreeProfilePresentation.landContextNote`.
//
//  No SwiftUI in this file.
//

import Foundation

enum LandContextCopy {

    /// The noun, identical wherever the value appears.
    ///
    /// The add flow's chips and the sentence above them, so the label on the chip a contributor taps
    /// and the sentence confirming what was tapped cannot disagree. Two spellings of one answer would
    /// be two chances for a reader to think they were looking at two different facts.
    ///
    /// `Street or sidewalk` rather than `Street`, because the value is the public right-of-way and a
    /// bare `Street` on a tree page reads like a fragment of an address. The sidewalk is where 93.35%
    /// of the seed's trees actually stand.
    ///
    /// Sentence case (ARCHITECTURE §5.7).
    static func noun(_ context: LandContext) -> String {
        switch context {
        case .street: return "Street or sidewalk"
        case .cityPark: return "City park"
        case .privateProperty: return "Private property"
        case .otherPublic: return "Other public land"
        }
    }

    /// The same answer as a phrase that follows the verb *stands*.
    ///
    /// Not a lower-cased `noun`: English does not let one preposition serve all four. *Stands on
    /// private property* and *stands in a city park* take different ones, and *stands on street or
    /// sidewalk* is not a sentence anybody writes. The composer's row takes it from here rather than
    /// gluing a preposition onto the noun at the call site. The tree profile needs the same shape and
    /// has its own — `TreeProfileCopy.landContextPlace` — because its four phrases follow *a tree*
    /// rather than *it stands*, and `on a street` is not `in the street or on the sidewalk`.
    static func standing(_ context: LandContext) -> String {
        switch context {
        case .street: return "in the street or on the sidewalk"
        case .cityPark: return "in a city park"
        case .privateProperty: return "on private property"
        case .otherPublic: return "on other public land"
        }
    }

    // There is no `source(_:)` here, and no `attributed(_:)` that glued a noun to one with a middle
    // dot. Both existed to fill a `Where it stands` stat card on the tree profile, and that card is
    // gone: two parallel rounds each put the ground under the tree on screen 03, and the one that
    // survived says it in a sentence that names its own speaker — `TreeProfileCopy.landContextInferred`
    // and `landContextStated`, reasoned about on `TreeProfilePresentation.landContextNote`. A source
    // reduced to four words after a dot was the weakest part of the losing design, so it is not kept
    // here against a future caller.
}
