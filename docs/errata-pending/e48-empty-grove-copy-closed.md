### Unnumbered — E48's empty-grove copy, closed (owner-approved 2026-08-05, task #235)

**Closes ERRATA E48** ("the empty grove is a BUILD-PLAN §9 requirement, and no copy exists for it").

E48 recorded that BUILD-PLAN §9 requires an empty-grove state for screen 08, that no mock and no
line of SCREENS.md gives it copy, and that the honest minimum — the ring, the celebration callout
and the tile grid each absent because each derives from contributions, per
`GrovePresentation.isEmpty` — was what shipped while the sentence itself was flagged for design.

**The owner approved the following line verbatim on 2026-08-05:**

> Your grove is empty so far. The species you spot will gather here.

Not a character of it was changed. It renders in `GroveView.speciesTab` only when
`GrovePresentation.isEmpty` is true — the same gate E48 already built and shipped — positioned in
the empty column between the tab row and §6's bottom-pinned footnote, in the same `GroveNote` card
`treesTab` already uses for its own empty state (`GroveCopy.treesEmptyState`). The constant is
`GroveCopy.emptyGrove` (`Cypress/Features/Grove/GrovePresentation.swift`).

No styling was invented: `GroveNote` is the existing shared component for "a sentence where a list
would be" (screen 08's own doc comment), and no raw hex, font size or radius was introduced.

**Tests**, all in `CypressTests`:
- `GrovePresentationTests.oneKnownSpeciesIsNeverTheEmptyGrove` — `isEmpty` stays `false` the moment
  there is one known species, however incomplete the rest of the read is.
- `GrovePresentationTests.emptyGroveCopyIsVerbatim` — pins the exact string.
- `GrovePresentationTests.emptyGroveCopyIsItsOwnSentence` — distinct from the Trees pill's empty
  state, the footnote, and the failure sentence (E158's warning, applied across pills).
- `GroveEmptyStateTests.theSentenceIsOnScreen` — a real `UIHostingController` render of the empty
  grove compared against a real `GroveView` that never finished loading (an API whose
  `groveSpecies()` never returns), which is the one state `speciesTab` has no branch for at all and
  is produced by production code rather than a hand-reconstruction. Red-proved: watched fail with
  the `GroveNote(GroveCopy.emptyGrove)` branch removed from `speciesTab` — the two renders came back
  byte-identical (112658 bytes each) — then restored.
- `GroveEmptyStateTests.aKnownSpeciesDrawsSomethingElse` — a grove with one known species renders
  its tile, not the empty-grove sentence.

To be spliced under the real next E-number at merge.
