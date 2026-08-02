# R31 correction — no message box ever stands in for an empty filter

**Unnumbered — pending splice by the orchestrator, as a correction under R31 (and a narrowing of
E126's application to the map's filters). Owner directive, verbatim, task #165 (2026-08-01):**

> We should NEVER display a message box in place of an empty filter. E.g. right now the Needs
> Care filter isn't visible as a pill and instead there's a box that says "No one has reported a
> struggling tree yet…" That wastes space and is generally stupid. Just have the Needs Care pill
> and if nothing matches, fine.

## What the owner struck

R31's **presentation clause**: "the chips render enabled-looking never; they render disabled with
the reason on the chip's own surface." The reasoning R31 built on — a control that promises and
cannot deliver is #59's defect in filter clothes — is overridden by the owner for this surface:
the pill's promise is the *narrowing*, not a non-empty result, and a 240 pt box carrying a
sentence where a pill should be costs more than the tap it saves. The same instruction reaches
the second message box on the same path: **E126's empty-notice card** ("a filtered map with no
matches must say why it is empty, and how to get out of it") no longer applies to the map's
filters. "If nothing matches, fine" — the empty map is the whole answer.

## What screen 01 does now (verified on the running simulator, Pro Max, 2026-08-01)

- `Yours`, `In bloom` and `Needs care` are ordinary tappable pills on every machine in every
  month, whatever the data holds. Tapping `Needs care` — which matches nothing against the
  shipped seed, `alive` and `vacant_site` being its only statuses — turns the pill on, empties
  the map, and draws nothing else: no card, no zero-count line, no sentence.
- The one way out is the `Clear filters` chip, which is in the row whenever any dimension is set
  (R23.1 §3 survives untouched — the way out never hides, and since this correction it is the
  *only* control wearing that label).
- The result line still draws over a non-empty filtered map (`31 trees`, `1458 trees—showing
  151`), and still draws nothing over an emptied one — previously because the notice was
  speaking, now because nothing should.

## What was removed with the presentation

The whole availability chain had no consumer once the pill stopped rendering disabled, and dead
plumbing that answers a question nobody asks is how stale premises fossilize (E189's lesson):
`MapConditionAvailability`, the `CypressAPI.mapConditionAvailability(month:)` requirement and its
default, `LocalAPI`'s read, `TreeQueries.anyTree(withStatus:)` / `anyTree(withSpeciesRowIDs:)`,
`SpeciesQueries.bloomSpecies(month:)`, `MapModel.conditionAvailability` /
`refreshConditionAvailability`, `MapFilterCopy.conditionUnavailableReason`, and the empty-notice
copy (`emptyTitle`, `emptyMessage`) plus `MapModel.isEmptiedByFilter` /
`membershipHasAnyMembers`. `MapConditionAvailabilityTests` went with the mechanism it pinned; the
bloom-calendar seed facts it also happened to pin (11 species with calendars, no Oct–Dec bloom)
lost their pin with it — if some later surface quotes those facts, it must re-pin them.

## What survives of R31

- The chips stay on the row, undemoted, in the owner's order — R31's first half was the owner's
  own fixing of the visible set, and #165 restates it ("just have the Needs Care pill").
- The self-enable clause is now trivially true: there is no disabled state to enable out of.
- R30's testing rule still governs what remains: the UI tests assert the pill is enabled, spends
  its tap, and that none of the deleted card's titles renders — facts, not phrasing.

## Note for the E126 record

E126 itself is not corrected — "a screen showing something other than what you asked for must
say why" still governs the location notices and the search status. What this correction removes
is its application to a *filter the reader just set themselves*: a map emptied by your own last
tap is not showing you something other than what you asked for.
