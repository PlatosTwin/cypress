//
//  MapInventoryNotice.swift
//  Cypress — Features/Map
//
//  Screen 01's fifth standing state: **the inventory answered this screenful with nothing, and
//  nothing narrowed it.**
//
//  ── Why this exists ─────────────────────────────────────────────────────────────────────────
//  Golden Gate Park draws no pins at any street zoom. Not few — none. The basemap keeps drawing
//  Apple's canopy artwork over the same ground, so the screen reads as an app that failed to load
//  rather than as one with nothing to load, and the largest green space in the city is the most
//  likely place a first-time reader opens the map. ERRATA E126 is the rule this is built under: a
//  screen showing nothing must say why.
//
//  The cause is not an ingest gap and there is nothing to retry. San Francisco has never counted
//  its park trees — SF Rec & Park publishes no tree inventory at any status, and the census the
//  `sf_city` list descends from excluded park trees by design (`ERRATA E214`, and the survey at
//  `docs/investigations/sf-park-trees.md`). So this is a boundary of a published municipal dataset,
//  which is why it is written like a map legend and not like an error.
//
//  ── Why the trigger is "the map drew nothing", and not a park ───────────────────────────────
//  A notice keyed to Golden Gate Park would be a lie about every other park, and — more to the
//  point — **the app cannot key on a park at all.** The seed carries exactly one set of polygons,
//  the 41 SF Analysis Neighborhoods (`neighborhoods.geom_geojson`, dataset `j2bu-swwd`); it carries
//  no Rec & Park property geometry of any kind. And the app never reads the polygons it does have:
//  `SpeciesQueries.resolveNeighborhood` answers "which area is this" through the **nearest
//  inventoried tree's** `neighborhood_id`, deliberately, so that no ray-cast of ours can disagree
//  with the city's own assignment (ERRATA E44). That mechanism returns nil at exactly the
//  coordinates this notice is for: with no tree within 400 m there is no nearest tree to ask. The
//  one fact available where the map is empty is that the map is empty.
//
//  So the trigger is the emptiness itself, which is general by construction: it fires inside Golden
//  Gate Park, over the Presidio, at Lake Merced, over the Pacific, and outside the window a
//  downloaded city file covers. It is a fact about the record, and the sentence is a fact about the
//  record.
//
//  ── RULINGS R41 reaches this, and that is why `isNarrowed` is a gate ────────────────────────
//  R41 is categorical: "no message ever accompanies a filter", and its test is *"does text appear
//  because a filter did something?"* A bare "no rows in view" trigger would answer yes — a species
//  chip that matches nothing empties the map, and a notice posted then would be the fourth
//  filter-adjacent message to be ruled out. It is also the exact state task #165 settled the other
//  way ("if nothing matches, fine") and that `ERRATA E205` re-audited as clean. So a narrowed map
//  is never owed this sentence, however empty it is, and R41's carve-out is not being read down:
//  what draws here is text about the *inventory*, on a map nobody has narrowed.
//
//  The reasoning is `RULINGS R53`, written under this ticket's
//  delegated design authority (SCREENS.md 01 lists `empty/no-GPS state` among its NOT SPECIFIED
//  states, which is the same door `MapOpening.Standing` was built through).
//

import Foundation

/// Whether screen 01 owes the reader a sentence about having drawn no trees at all.
///
/// A pure function of four facts `MapModel` already holds, for `MapOpening.standing`'s reason: a
/// decision that reads the model is a decision no test can pin down without building one.
enum MapInventoryNotice {

    /// - Parameters:
    ///   - hasSettled: whether a read for the current viewport has actually *completed*. `MapModel`
    ///     starts life at `.pins([])`, which is indistinguishable from an answered-and-empty
    ///     viewport by inspection; posting the sentence off that initial value would put it on
    ///     screen for the first frames of every launch, including over the densest street in the
    ///     city. This is `MapOpening.patience`'s lesson in a different currency — a notice that is
    ///     wrong for a moment on every launch teaches the reader to stop reading the slot.
    ///   - isNarrowed: whether a filter or a search is narrowing the map. **RULINGS R41.** See the
    ///     header.
    ///   - readFailed: whether the last read threw. E126's own defect was a screen that drew its
    ///     empty state for a read that never finished; "nothing is on record here" is a claim about
    ///     the record, and a failed read has learned nothing about the record.
    ///   - markerCount: what the map has to draw — pins, or cluster badges. `MapContent.markerCount`
    ///     rather than `pinCount`, because a clustered viewport holding one badge for 29,390 trees
    ///     is emphatically not an empty screen, and both numbers are zero together only when the
    ///     answer really was empty.
    static func isOwed(
        hasSettled: Bool,
        isNarrowed: Bool,
        readFailed: Bool,
        markerCount: Int
    ) -> Bool {
        guard hasSettled, !isNarrowed, !readFailed else { return false }
        return markerCount == 0
    }
}

/// The words. Out of the view for the reason every other `*Copy` in this app is: the sentence a
/// state produces is a decision worth a test, and a test should not have to render a `View` to
/// read it.
enum MapInventoryCopy {

    /// **"on record", not "here".** The subject of the sentence is the record, not the ground. A
    /// title reading `No trees here` would be the one thing this notice must never say: Golden Gate
    /// Park has upwards of a hundred thousand trees in it and the app knows about none of them.
    static let title = "No trees on record here"

    /// **Three things, in the order a reader needs them.**
    ///
    /// 1. *What the map is drawing* — a city street-tree inventory. That is the inventory's own
    ///    published name rather than a characterization invented here: all three inventories the
    ///    ingest contract registers are named one (`SF Public Works street tree inventory`,
    ///    `DataSF Street Tree List`, `City of San Jose Street Tree inventory`), which is also why
    ///    the sentence does not name *which* — it is true of whichever file is attached, and
    ///    threading the attached inventory's name out to screen 01 is precisely the plumbing
    ///    `ERRATA E205` has just finished deleting.
    /// 2. *Why this screenful is blank* — the ground is not on it. Said as a fact about the
    ///    inventory's extent, so it reads as a boundary rather than as a failure. Nothing here is
    ///    a verb the reader could have done wrong, and nothing here is a state that resolves.
    /// 3. *That the trees are real* — the half the ticket is actually about. A park is full of
    ///    trees and empty on this map, and a sentence that let the reader infer otherwise would be
    ///    worse than the silence it replaces.
    ///
    /// **What it deliberately does not say.** No date, no "yet", no "coming soon", no "we are
    /// working on it": SF Rec & Park publishes no tree inventory at any status and no parks phase
    /// of the Urban Forest Plan has ever published data (E214), so a promise would be the invented
    /// destination claim `ERRATA E212` records two shipped examples of. And no retry and no way
    /// out: nothing failed, and there is nothing to clear. The way to put a tree here that the app
    /// does have — the `What tree is this?` FAB — is the largest control on the screen and sits
    /// directly above this card whether it draws or not, so repeating it in prose would be a
    /// second, weaker copy of a control the reader is already looking at.
    ///
    /// **It is as short as it is because of AX5, and the measurement is in the test.** The first
    /// draft ended `…; the inventory has never listed them.` and measured **502.3 pt** tall at
    /// accessibility5 on a 393 pt phone, against **456.7 pt** for the tallest location notice
    /// already shipping in this slot — a full line taller than the precedent, in a slot whose
    /// unfixed defect (`ERRATA E183 §2`) is that it lays out from its bottom edge and grows off
    /// the *top* of the display. `MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` holds the
    /// budget, so a copy edit that spends the line back fails rather than ships.
    ///
    /// `may well stand here` is doing load-bearing work and is not a hedge to be tidied away: the
    /// trigger fires wherever the record is empty, which includes the Pacific and the ground
    /// outside a downloaded city's window. `Trees stand here` would be a stronger sentence and a
    /// false one in those places; `may well` is true in all of them and still refuses the reading
    /// the ticket is about — that the park has no trees.
    ///
    /// No spaces around em dashes (ARCHITECTURE §5.7) — there are none to space.
    static let message =
        "Cypress draws a city street-tree inventory, and this ground is not on it. "
        + "Trees may well stand here, unlisted."
}
