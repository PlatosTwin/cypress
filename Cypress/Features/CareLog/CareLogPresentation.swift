//
//  CareLogPresentation.swift
//  Cypress — Features/CareLog
//
//  Screen 09 · Care log. SCREENS.md lines 961–981.
//
//  The thirty-second record of something done *for* a tree. It is deliberately not a health
//  observation: "Care performed and conditions observed stay separate records, which matters for
//  coordinators later" (SCREENS.md 09 caption), and that separation is a data fact — `CareEvent` and
//  `TreeObservation` are different tables with different outbox kinds (BUILD-PLAN §4, V-M3).
//
//  ── What this file will not do ────────────────────────────────────────────────────────────
//  Count anything. A care event is the archetype of "a countable user action", and D1 forbids
//  streaks, points and public counts of exactly this (DECISIONS §3.1, `CareEvent`'s own header:
//  "Never publicly counted or ranked"). Nothing here exposes a total, a tally or a history length.
//
//  No SwiftUI in this file. Everything the view draws is decided here, so the rules can be reasoned
//  about — and tested — without a renderer.
//

import Foundation

// MARK: - Draft

/// What the contributor has toggled so far.
///
/// **It opens empty.** SCREENS.md 09 §4 draws `Watered ✓` and `Mulched ✓` in their on-state, and
/// that is the mock depicting a sheet mid-use, not a default. A pre-selected chip would write a
/// watering nobody did into an append-only record the moment the CTA is tapped, and the contributor
/// would have to notice and undo it. Previews carry the drawn state instead; see `CareLogPreviews`.
struct CareLogDraft: Hashable {

    /// Multi-select over the four actions screen 09 draws. Stored as a `Set` because the toggles are
    /// independent; ordering for the record comes from `orderedActions`.
    var actions: Set<CareAction> = []

    /// 09 §5's optional well covers "Photo or note". E25 recorded the well drawn with no editor
    /// behind it; these two were carried here anyway because `CareEvent` already takes both.
    /// Task #147 wired them behind a reveal tap; task #168 made the fields directly visible and
    /// `photos` genuinely plural — the writer's shape needed no change either time, which is what
    /// carrying them bought.
    var note: String?
    var photos: [OutboxPhoto] = []

    /// The CTA's guard. PROTOTYPE-FLOW §1.3 `logCare` is explicit — "Guard: no-op if no care chip is
    /// on" — and §1.4 `careBtnStyle` gives the disabled fill and label for that state. An empty care
    /// event asserts that somebody did something for the tree and names nothing they did.
    var isEmpty: Bool { actions.isEmpty }

    /// Declaration order, so the record does not reorder with the taps that produced it.
    var orderedActions: [CareAction] {
        CareAction.allCases.filter { actions.contains($0) }
    }
}

// MARK: - Presentation

/// The derivation the view renders.
struct CareLogPresentation: Equatable {

    /// The tree's display name, once `GET /trees/{id}` lands. Nil while the read is in flight or
    /// after it failed — the title falls back rather than the sheet refusing to open, because the
    /// sheet's whole promise is thirty seconds and a name is not what it is collecting.
    let treeDisplayName: String?
    let draft: CareLogDraft

    /// `Care log · Monterey Cypress` — 09 §2, with the tree's own display name in place of the
    /// mock's fixture. Without a name the middle dot would separate the title from nothing, so the
    /// title is the lead alone.
    var title: String {
        guard let treeDisplayName, !treeDisplayName.isEmpty else { return CareLogCopy.titleLead }
        return "\(CareLogCopy.titleLead) · \(treeDisplayName)"
    }

    /// The four chips 09 §4 draws, in its order.
    var chips: [CareChip] {
        CareLogCopy.drawnActions.map { action in
            CareChip(action: action, isOn: draft.actions.contains(action))
        }
    }

    /// Whether the `Done` CTA does anything (PROTOTYPE-FLOW §1.3 `logCare`).
    var canSave: Bool { !draft.isEmpty }
}

/// One care toggle. Carries the `CareAction` rather than a label, so the chip cannot be built for a
/// verb the record has no column for — `Chip.care(_:isOn:)` derives the words, including the `✓`
/// that §2's C4 table makes part of the on-state label string.
struct CareChip: Hashable, Identifiable {
    let action: CareAction
    let isOn: Bool

    var id: CareAction { action }
}

// MARK: - Copy

/// Every string screen 09 renders, verbatim from SCREENS.md 09 unless noted.
enum CareLogCopy {

    /// 09 §2's title, before the middle dot.
    static let titleLead = "Care log"

    /// 09 §3, verbatim.
    static let subtitle = "Toggle what you did. Thirty seconds, then back to your walk."

    /// 09 §5's well copy, verbatim. Since task #168 it is the caption over the always-visible
    /// fields rather than a control — the reveal step was the owner-reported awkwardness. The
    /// fields themselves (and their strings) are `ContributionExtras`, shared with screen 05.
    static let optionalWell = "Photo or note (optional)"

    /// Screen 04's own prompt, verbatim, so "a sentence you may leave" asks the same way on every
    /// contribution surface. Read off the shared block so the agreement cannot drift.
    static let notePrompt = ContributionExtrasCopy.notePrompt

    /// 09 §6.
    static let doneCTA = "Done"

    /// 09 §7, verbatim — including the em dash with no spaces around it (ARCHITECTURE §5.7).
    ///
    /// PROTOTYPE-FLOW §"Care sheet" records an earlier wording of the same sentence ("…care history,
    /// kept separate from health observations."). SCREENS.md is the visual truth (ARCHITECTURE §1),
    /// so this is the one that ships.
    static let footnote = "This joins the tree’s care history—separate from health observations."

    /// The four actions SCREENS.md 09 §4 draws, in its order.
    ///
    /// `CareAction` carries a fifth value, `staked`, which BUILD-PLAN §4 lists in the stored
    /// vocabulary and which no mocked screen offers a control for. Adding a fifth chip would be
    /// inventing an affordance (DECISIONS constraint 21); dropping the case from `Core` would be
    /// narrowing the stored vocabulary to fit one screen. So the vocabulary keeps it and this screen
    /// does not offer it. Recorded in ERRATA (E58).
    static let drawnActions: [CareAction] = [.watered, .mulched, .weeded, .litterCleared]

    /// The failed-save line. **NOT SPECIFIED** by SCREENS.md 09, which draws no error state — the
    /// same gap screen 05 has, answered the same way. It never claims a save that did not happen.
    static let saveFailed = "This care log was not saved. Try again."
}
