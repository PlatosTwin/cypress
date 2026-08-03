//
//  TreeProfileDestination.swift
//  Cypress — Features/TreeProfile
//
//  **Which screen a tree record is** — asked once, of the record, after it has been read and before
//  anything is drawn (ERRATA E113).
//
//  ── Why this exists at all ────────────────────────────────────────────────────────────────
//  A vacant planting site is 12,518 rows of the seed and it has no tree in it. Screen 14 — the cold
//  profile — asserts one: an empty photo well captioned `No photos of this tree yet` over
//  `Be the first to photograph this tree`. E107 gave the site its own screen and routed the *map
//  card* to it, and named the residue in its own last paragraph: "Entrances other than the map —
//  the visit flow's nearest-candidate list, a stale link — still land a vacant site on the degraded
//  profile."
//
//  The fix that would have left that residue in place is a second `if` at a second call site. The
//  entrances are the almanac's season row and its "walk the nine" row, the journal's elder row, the
//  visit flow's open-tree callback, the site screen's own nearest-tree row, the map — six today and
//  no reason to think six is the number tomorrow. Every one of them pushes `Route.treeProfile`,
//  every one of them lands in `TreeProfileModel.load()`, and **the status is not known to any of
//  them**: it arrives with the payload, one read later, in one place. So the question is asked
//  there, and asked in the shape that cannot be half-answered — an exhaustive switch over
//  `TreeStatus`, so a sixth status is a compile error rather than a silent tree profile.
//
//  No SwiftUI in this file.
//

import Foundation

/// Where a record read by `TreeProfileModel` actually belongs.
enum TreeProfileDestination: Equatable {
    /// This screen. Screens 03 and 14 are one view and the variant is `TreeProfilePresentation`'s
    /// own call (`isCold`); nothing here chooses between them.
    case profile
    /// Another screen entirely, which the profile hands to the router rather than drawing.
    case elsewhere(Route)

    /// - Parameter record: the tree as the store holds it. `trees.status` and nothing else: an
    ///   observation never mutates it (DECISIONS §3.7), so this cannot be moved by somebody's
    ///   opinion of a basin — the same gate `SiteModel.load` applies from the other side.
    init(record: Tree) {
        switch record.status {
        case .alive, .declining, .deadReported:
            self = .profile

        case .vacantSite:
            // The screen E107 built for exactly this record. `Route.site` rather than a variant of
            // the profile, for the reason `Route` gives at the case: a tree profile with fields
            // missing still asserts a tree.
            self = .elsewhere(.site(record.id))

        case .removed:
            // **Deliberately the profile, and this is the interesting one.**
            //
            // A removed tree has screen 19 (`Route.memorial`), the map already sends a removed pin
            // there, and E95 records the almanac and the visit flow as still able to reach the
            // profile with one. Redirecting here would close E95 in one line — and would break
            // RULINGS R2 in the place R2 says matters most.
            //
            // The argument is E89's, and it survives the redirect being available: gating a
            // favorite on `acceptsNewContributions` makes the toggle one-way for anyone whose
            // favorite tree is later removed, because the gate that refuses the heart also refuses
            // *removing* it. Screen 19 has nothing to press, by design. So a redirect to 19 is that
            // same gate wearing a router: the person who favorited this tree while it stood would
            // have no surface anywhere in the app that could take the heart off.
            //
            // What the profile owes a removed tree instead is to offer nothing that writes to it,
            // which is `TreeProfilePresentation.acceptsContributions` and, since E112,
            // `quadActions`. See ERRATA (E95, E112, E113).
            self = .profile
        }
    }
}
