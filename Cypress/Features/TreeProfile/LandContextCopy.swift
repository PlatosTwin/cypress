//
//  LandContextCopy.swift
//  Cypress — Features/TreeProfile
//
//  The words for `LandContext`, in one place, because three screens say them and one act must have
//  one name.
//
//  ── Why the vocabulary is here and not in `Core` ──────────────────────────────────────────────
//  `Core` is pure Foundation and holds no display strings anywhere in this app — `CareAction` is
//  spelled out by `TreeProfilePresentation`, `HazardCategory` by `HazardCategoryLabel`. This follows
//  that, and it sits in the feature that shows all four values rather than in the one that writes
//  three: the add flow states a context, the profile and the report *read* one, and a city row can
//  carry a value the add flow never offers. `PinSetCopy` is the same arrangement seen from the other
//  side — the screen that owns the concept owns the sentence, and other features reach in.
//
//  No SwiftUI in this file.
//

import Foundation

enum LandContextCopy {

    /// The noun, identical wherever the value appears.
    ///
    /// The add flow's chips, the profile's card and the report's panel all use these, so a
    /// contributor who taps `Private property` reads `Private property` back on the tree page and in
    /// the panel that explains why 311 is not the destination. Three spellings of one answer would be
    /// three chances for a reader to think they were looking at three different facts.
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
    /// sidewalk* is not a sentence anybody writes. Both screens that put this fact into prose — the
    /// composer's row and the report's panel — take it from here rather than each gluing a
    /// preposition onto the noun and disagreeing about which.
    static func standing(_ context: LandContext) -> String {
        switch context {
        case .street: return "in the street or on the sidewalk"
        case .cityPark: return "in a city park"
        case .privateProperty: return "on private property"
        case .otherPublic: return "on other public land"
        }
    }

    /// How Cypress knows, in the fewest words that keep an inference from wearing an observation's
    /// confidence — `KnownLandContext`'s whole reason for existing (E143), carried to the screen.
    ///
    /// **`read from` rather than `from`.** A city row's context is not a field San Francisco
    /// published: the city wrote `qLegalStatus = 'Property Tree'`, and `LandContext.inferred(from:)`
    /// is Cypress's rule for turning that into a place. `Private property · from the city record`
    /// would put Cypress's reading in the city's mouth, which is the same overstatement D7 refuses
    /// for the DBH bucket in the other direction. Naming the act — a reading — attributes it to
    /// nobody and claims nothing the record does not support.
    ///
    /// **`a contributor`, not `the contributor`,** for `speciesNamedByContributor`'s own reason:
    /// `community_trees` records no author, so the row cannot say which person.
    ///
    /// Both arms print, always, and neither is the marked case — E138's symmetry rule, which does
    /// carry here unlike on the species line (E141): a land context that exists always came from one
    /// of exactly these two ways of knowing, so marking one would rank it against the other.
    static func source(_ source: KnownLandContext.Source) -> String {
        switch source {
        case .statedByContributor: return "said by a contributor"
        case .inferredFromCityRecord: return "read from the city record"
        }
    }

    /// `Private property · said by a contributor` — the profile card's whole value.
    static func attributed(_ known: KnownLandContext) -> String {
        noun(known.context) + " · " + source(known.source)
    }
}
