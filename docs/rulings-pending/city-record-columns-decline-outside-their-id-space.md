# R— · The two §9b cards that were reading one city's vocabulary against another's rows (task #186)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `p1/round8-b`. Latest numbered at time of writing: R49, E209.*

---

## What was decided

Two decisions, both under the standing delegation for copy and behaviour the mocks do not cover.

**1 · `CityRecordPresentation.listedAsText` declines outside `sf`.** It is a reading of DataSF's
`PlantType` — a column that says `Tree` on almost every row, so "suppress the agreement and draw the
disagreement" is the right rule for it. San Jose's `plant_type` is not that column; it is `GROWSPACE`
(`SanJoseStreetTreeAdapter.CITY_RECORD_COLUMNS`), a growing-space category. The rule declines rather
than being taught the other vocabulary.

**2 · A card is not drawn for a value that states no value.** `N/A`, `Unassigned`, and a string with
no letter or digit in it (San Francisco's bare `:`) draw nothing, on the `Site` card on screens 03/14
and 19 and on every card in the §9b section.

## Why R24 settles the first one, rather than a new judgment

R24 already says it: *a derivation over a publisher's own vocabulary is qualified by the id space it
was written for, and must decline outside it*, and the test is **"was this rule written from this
publisher's documentation"** — not "does it return something sensible for the new source". For
`GROWSPACE` it was not. This is the same shape as `pruningNote(idSpace:)` and
`LandContext.inferred(from:idSpace:)`, and it is applied here in the same words.

R24 was written about a function that *answered confidently and wrongly* for all 52,788 San Jose
rows. This is the identical failure one column to the left, and R24's own "what it does not decide"
paragraph names it: *whether the six `city_record` columns should be holding another publisher's
differently-meaning columns at all.* That deeper question is still open (see the pending errata and
#134); nothing here answers it.

### Why the card is not taught San Jose's vocabulary instead

Because Cypress has not read San Jose's published metadata for `GROWSPACE`. Writing a branch that
renders `Park Strip`, `Well/Pit`, `Tree Lawn` and `Open/Unrestricted` under some label would mean
this app stating what those codes mean in San Jose's asset system on the strength of one adapter's
column list. DECISIONS constraint 15 forbids exactly that, and R24 is the same rule for derivations.
A San Jose reader gets one fewer card, and that is the honest outcome rather than a gap to fill.

## Why the second decision is *not* an R24 case, which matters

`N/A` is not San Jose's dialect. It is what a data-entry form emits for "no answer", in any city, and
recognising it is not a reading of any publisher's vocabulary — which is why it carries no id-space
guard and applies everywhere, including to San Francisco's own `:`.

The argument is `plotSizeText`'s, already settled in this file for `Width 0ft` on 17,254 rows: **a
basin zero feet wide is not a measurement of a basin, it is the shape "not measured" takes in a form
that wanted a number.** `N/A` is that shape in a form that wanted a word. A card is a claim that the
city answered; drawing the placeholder is Cypress asserting an answer the city did not give.

Nothing is corrected, merged, re-ranked or filled. Real values pass through verbatim: `Park Strip`
and `Sidewalk: Curb side : Cutout` are printed as the city wrote them, because knowing that `N/A` is
not a place requires no opinion about what `Park Strip` is.

## What a San Jose reader is left with, checked rather than assumed

E126's half that governs here is *a surface with nothing on it must say why*. It is **not engaged**,
and that was measured rather than hoped: every one of the 52,788 San Jose rows carries `caretaker`,
and 50,630 carry `legal_status`, so the section still draws its cards, its header and its provenance
line on every row. Photographed on the simulator before and after on record `#100002`
(945 W JULIAN ST): the two `N/A` cards go, `Legal status — Private`, `Cared for by — General Fund`
and `From the City of San Jose Street Tree inventory, July 31, 2026.` stay.

This is `pruningNote`'s argument reused, and it is the reason no new copy was written. **No sentence
was invented for this state, because the state is not "we cannot tell you" — it is "the city did not
record this", which this screen already renders by drawing nothing** (E9; and `recognitionTip`,
`watchForText`, `badge`). A card reading `City lists this as — Not recorded` would be the first
`Unknown` on a screen whose whole grammar is absence, and it would be a claim about *this tree* where
the true claim is about the column.

## What this does not decide

- **What San Jose's `GROWSPACE` should be labelled**, or whether it should reach a card at all under
  a label of its own. It is a real signal — R24's own text calls it "a far better signal for where a
  San Jose tree stands than `OWNEDBY`" — and it now reaches the reader only through the `Site` card,
  verbatim, on the rows where it states something.
- **Whether the six `city_record` columns should hold another publisher's columns at all.** Open, and
  the subject of #134.
- **The other two E209 members.** `SharePresentation.ShareCopy.city` (Shape A, needs a source for a
  short civic name no table carries) and `MapKitBasemap.defaultCentre` (Shape B, needs a per-city
  centre the manifest does not carry) are untouched and still want their own tickets.
