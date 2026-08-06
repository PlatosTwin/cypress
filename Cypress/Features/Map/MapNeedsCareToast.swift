//
//  MapNeedsCareToast.swift
//  Cypress — Features/Map
//
//  Screen 01's one transient sentence: **`Needs care` was pressed, and nothing on this map needs
//  care.**
//
//  ── The owner's instruction, verbatim (2026-08-06) ───────────────────────────────────────────
//
//  > Leave as is, but we can add a quick and light pop-up toast or the like (as long as it
//  > dismisses quick and doesn't pollute the map permanently) that says no trees need care.
//
//  ── What that changes, and what it deliberately does not ────────────────────────────────────
//  `RULINGS R41` is categorical — "no message ever accompanies a filter", its test being *"does
//  text appear because a filter did something?"* — and it names exactly one permitted form for
//  anything judged genuinely essential: a **single-dismiss popup**, "shown once, dismissed with one
//  tap, never recurring for the same cause, never persistent on the glass". R41 then judged that
//  nothing in the product qualified. The owner has now judged that this one state does, and has
//  chosen a briefer form than the one R41 sanctioned: it dismisses itself rather than waiting for a
//  tap. That is the owner's own ruling refining their own ruling, so the carve-out is not being
//  read down by anyone here.
//
//  **This is one state, not a category.** `In bloom`, the species legend, `Yours`, `Favorites`,
//  `Year` and `Site` all keep R41's silence when they empty the map — that is task #165's
//  settlement ("if nothing matches, fine"), re-audited clean by `ERRATA E205`, and nothing about it
//  moves. `isOwed` below is written so that widening it means writing a new condition into it by
//  hand, and `MapNeedsCareToastTests` fails if anything else can open it.
//
//  ── Why `ERRATA E244` is what makes this state real ─────────────────────────────────────────
//  Until #240 the two condition chips did nothing at all to a clustered map: the predicate was
//  applied to the pins already fetched, and at zoom ≤ 15 there are no pins to apply it to. E244
//  moved both into the `WHERE` clause, so `Needs care` now empties the map honestly — the shipped
//  seed carries zero `declining` rows, its only two statuses being `alive` and `vacant_site`. E244
//  closed with the product question open in terms: "whether `Needs care` is worth a chip at all
//  while the seed carries zero `declining` rows is a product question this task did not answer".
//  This is the owner's answer: keep the chip, and say the one thing the empty screen means.
//

import Foundation

/// Whether screen 01 owes the reader the one sentence R41's carve-out now permits.
///
/// A pure function of four facts `MapModel` already holds, for `MapInventoryNotice.isOwed`'s
/// reason: a decision that reads the model is a decision no test can pin down without building
/// one. **`MapModel` owns the other half** — *when* it may be asked, which is once per activation
/// of the chip. This function answers only "is this the state", never "is this the moment".
enum MapNeedsCareToast {

    /// - Parameters:
    ///   - filter: compared against `MapFilter.needsCare` **whole**, which is the scoping decision
    ///     rather than a shortcut for reading `condition`. Two things fall out of it, and both are
    ///     wanted. `In bloom` cannot open this, because `.inBloom != .needsCare` — R41's silence is
    ///     the default and this is the single exception to it. And a *conjunction* cannot open it
    ///     either: `Needs care` with a decade, a site kind, a membership or a legend species beside
    ///     it draws an empty map for a reason nobody can attribute, and "No trees need care" would
    ///     then be claiming more than the query asked. A tree on this block may well need care and
    ///     simply not have been planted in the 2010s. The sentence is true of exactly one query, so
    ///     it is shown for exactly that query.
    ///   - isSearching: the search bar is the sixth narrowing and is not on `MapFilter` (it is
    ///     `MapModel.search`), so it is passed separately and excluded for the same reason as
    ///     every dimension above. `MapModel.isNarrowed` counts it for R41 and so does this.
    ///   - readFailed: `MapInventoryNotice.isOwed`'s argument, unchanged and for its exact reason —
    ///     "no trees need care" is a claim about the record, and a read that threw has learned
    ///     nothing about the record. E126's own defect was a screen drawing its empty state for a
    ///     read that never finished.
    ///   - markerCount: what the map has to draw — pins *or* cluster badges. `markerCount` rather
    ///     than `pinCount` because the whole of E244 is that the answer at zoom ≤ 15 is badges, and
    ///     a version of this that could only see pins would be silent over exactly the zooms the
    ///     defect lived at.
    static func isOwed(
        filter: MapFilter,
        isSearching: Bool,
        readFailed: Bool,
        markerCount: Int
    ) -> Bool {
        guard !readFailed, !isSearching, filter == .needsCare else { return false }
        return markerCount == 0
    }
}

/// The words. Out of the view for the reason every other `*Copy` in this app is: the sentence a
/// state produces is a decision worth a test, and a test should not have to render a `View` to
/// read it.
enum MapNeedsCareToastCopy {

    /// **The owner's own words, as a sentence.** They wrote "says no trees need care"; this is that
    /// with a capital and nothing added. DECISIONS constraint 15 forbids inventing botanical or
    /// civic content, and the temptation this copy has to refuse is the *explanatory* second
    /// clause — why the inventory records no declining trees, what `declining` means, what the
    /// reader might do instead. Every one of those is prose invented here, and every one of them is
    /// the clutter R41 exists to keep off this map.
    ///
    /// It also carries no count, no "0", and no "here". A count is the first of the three surfaces
    /// R41 names as forbidden beside a filter, and "here" would make a claim about the ground
    /// rather than about the record — the distinction `MapInventoryCopy.title` spends its whole
    /// comment on.
    static let message = "No trees need care"
}
