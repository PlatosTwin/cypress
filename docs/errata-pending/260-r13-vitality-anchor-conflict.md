### R13 rules for SCREENS.md, the app draws PRODUCT.md, and the two tables have disagreed since the handoff

Ticket #260. The app's five vitality anchor sentences (`Cypress/Core/Rubric/Vitality.swift`, `anchor`)
are PRODUCT §3's, verbatim. RULINGS R13 says `SCREENS.md` holds screen 05's anchor sentences and "its
wording is what ships". `SCREENS.md` 05 §3 carries five different sentences. All five rows differ.

Everything below is read from git, from the handoff artifacts and from the code. Where a claim about
1c469cf or 156389e is made, the commit was read; where a table is quoted, it was quoted out of the
file at that commit, not from memory.

---

#### 1. The divergence arrived with the handoff. Neither distilled document invented it.

`docs/distilled/PRODUCT.md` and `docs/distilled/SCREENS.md` landed in the **same commit**, 1c469cf
(2026-07-21 15:43:07 -0700, "Add the Xcode project and the architecture contract"). Each is a faithful
transcription of a **different** primary artifact, and the two primaries disagree.

- `PRODUCT.md` §3's table is byte-identical to `SPEC-PHASE1.md` §6 (lines 174–178), which the design
  handoff supplied as prose spec.
- `SCREENS.md` 05 §3's table is byte-identical to `design_handoff_cypress/Cypress Screens.dc.html`
  inside `Cypress.zip` — the design-tool export `SCREENS.md`'s own preamble names as its source,
  including the en dashes in `25–50%` and the title `1 · Severe decline`. Extracted and grepped for
  this entry.

So there is no transcription error to correct in either distilled document, and no "wrong table" in
the repository's own sense. Two artifacts handed over on the same day state the rubric copy
differently, and both were distilled correctly.

One trap worth naming, because an agent will grep for it: `mocks/cypress-mocks.html` (lines 528–532)
carries a **third** variant — title `1 · Severe` rather than `1 · Severe decline`, and `25 to 50%
dieback` rather than `25–50% dieback`. That file is not `SCREENS.md`'s source. The `.dc.html` export
is, and `SCREENS.md` matches it exactly.

#### 2. The code has carried PRODUCT's sentences since the hour it was written, and never changed.

`Vitality.swift` was created in de47694 (2026-07-21 15:43:25), eighteen seconds after the distilled
docs landed. It shipped PRODUCT's five sentences and a doc comment reading "verbatim from the PRODUCT
§3 rubric table". The file has four commits in its whole life (de47694, 7978af4, 549750e, f268fdd);
the five `anchor` strings are byte-identical in all four and at `HEAD`. Screen 05 was built an hour
later, in 549750e (2026-07-21 16:40:56), and consumed `Vitality` rather than transcribing the export —
which was deliberate architecture, and is why replacing the rubric is still an edit to one `Core`
file.

`PRODUCT.md` has been touched **once ever**, by 1c469cf. `SCREENS.md` has four commits (1c469cf,
e48d81f, aba20c2, f268fdd) and its 05 §3 table is byte-identical in all four. **Neither table changed
before R13, after R13, or at any point since.** Nothing moved. The conflict was fully formed at
15:43:25 on 2026-07-21 and has been visible ever since.

#### 3. What R13 was actually deciding, and what the evidence will and will not support.

R13 is commit 156389e (2026-07-24 21:32:59), three days and five hours after screen 05 was built. It
changed one file, `docs/RULINGS.md`, +28/−1. **No code change accompanied it and none has followed.**

The question it answered had been standing in `RULINGS.md`'s own "What is still design's, and was not
delegated" list since f98fe4f, worded:

> The rubric wording on screen 05 — whether `PRODUCT.md` or `SCREENS.md` holds the anchor sentences.

That is a **document-authority** question. Nothing in the posing says the two documents contain
different text, and nothing in R13's commit message says the author compared them.

The strongest single piece of evidence is R13's own illustrative example:

> `1 · Severe decline · Mostly bare in season; over 50% dieback; survival doubtful`

That string exists in **no document and in no mock**. `1 · Severe decline` is `SCREENS.md`'s title
column; `Mostly bare in season; over 50% dieback; survival doubtful` is PRODUCT's anchor. It is
exactly what `VitalityRow.title` and `VitalityRow.anchor` compose at runtime
(`CheckInPresentation.swift:94, 97`). **R13's example was read off the running app, in the belief that
what the app drew was screen 05's copy.**

What the evidence supports: R13 decided which document holds the copy without comparing the two
documents' contents, and illustrated its ruling with a sentence that the ruling, if applied, would
delete.

What the evidence does **not** support: that R13 would have been decided differently had the author
compared them. Its rationale is general and provenance-based — "the app's words must be traceable to
the screen that draws them, not assembled from a higher-tier document that never intended to be quoted
letter-for-letter" — and checked against the design export three days later, that rationale points at
the right artifact. The export really does draw those five short lines. **R13's holding is sound; its
example is wrong.**

Nor does git say whether the author opened `SCREENS.md` 05 §3 at all. There is no artifact of a
reading. The inference above rests on the composed example and on the commit being docs-only.

#### 4. Under R13's own split, the percentages were never SCREENS.md's to drop.

R13 divides the ground cleanly: **meaning is `PRODUCT.md`'s, wording is `SCREENS.md`'s**, and a
conflict about meaning — "a level added or redefined" — outranks `SCREENS.md`.

Set the two tables side by side and the divergence is not uniform:

| Level | `SCREENS.md` 05 §3 | PRODUCT §3 (shipped) | dieback band |
|---|---|---|---|
| 1 | `Mostly bare crown, major dead limbs` | `Mostly bare in season; over 50% dieback; survival doubtful` | dropped |
| 2 | `Large dead sections, 25–50% dieback` | `Sparse canopy; major dead limbs; dieback 25 to 50%; stress obvious` | kept |
| 3 | `Noticeably thin, 10–25% dieback` | `Noticeable thinning or discoloration; dieback 10 to 25%; still clearly viable` | kept |
| 4 | `Canopy mostly full, isolated dead twigs` | `Canopy mostly full; minor thinning or isolated dead twigs (under 10% dieback)` | dropped |
| 5 | `Dense canopy, vigorous new growth` | `Full, dense canopy for the season; vigorous new growth; no visible dieback` | dropped |

`SCREENS.md` keeps the quantity on rows 2 and 3 and drops it on 1, 4 and 5. So the export's copy
states a band for the middle of the scale and none at either end: a rater holding an estimate of 5
percent, or of 60 percent, finds no row on the card that names a number they can match. That is not a
rephrasing of the same five classes. **A class's dieback band is its operational definition — it is
what makes level 1 level 1 — and a definition is meaning, which R13 puts in PRODUCT's hands.**

The consequence matters beyond tidiness. Hallett, R.; Hallett, T. 2018, "Citizen science and tree
health assessment: how useful are the data?", *Arboriculture & Urban Forestry* 44(6): 236–247 — fetched
and read for this entry, not recalled — put 22 volunteers (17 high-school students and 5 adults, after
a two-hour training session led by a Forest Service research ecologist) against an expert on a
validation set of **59 living trees rated twice**. Fine-twig **dieback percentage** had the best
overall volunteer/expert agreement of any variable, mean difference 3 percent, the two estimates
within 10 percent of each other 76 percent of the time. The authors attribute that partly to the
dieback rating having 21 possible categories against 5 for the ocular-estimate variables — which is a
real caveat about scale granularity, and does not disturb the direction of the finding.

Resolving toward `SCREENS.md` verbatim would therefore delete the best-agreeing cue in the literature
from three of the five rows a volunteer reads at rating time, on a screen whose entire D3 argument is
that the anchor must be visible when the rating is made.

#### 5. Two defects in the shipped rubric text, confirmed — one of them narrower than reported.

**(a) The bands overlap, but at one interior boundary, not three.** The pending candidates document
states that 10, 25 and 50 each belong to two rows. Read literally, they do not:

- **0 percent** satisfies row 5 (`no visible dieback`) *and* row 4 (`under 10% dieback`). Genuinely
  double-owned, and not previously reported.
- **10 percent**: row 4 says *under* 10, which excludes it; row 3 says `10 to 25%`, which includes it.
  Single owner, row 3.
- **25 percent**: row 3 says `10 to 25%` and row 2 says `25 to 50%`. Both inclusive. **Genuinely
  double-owned.**
- **50 percent**: row 2 says `25 to 50%`, which includes it; row 1 says *over* 50, which excludes it.
  Single owner, row 2.

So the accurate statement is: **one interior boundary is ambiguous (25 percent) and one endpoint is
(0 percent)**. `SCREENS.md`'s table has the same 25-percent overlap in its two numbered rows and, as
§4 above says, no numeric statement at all outside them.

The repair is the one Candidate A already carries: bands that partition the range with no shared
endpoint — `No dead wood visible` / `1 to 10%` / `11 to 25%` / `26 to 50%` / `Over half`. Checked
against every integer from 0 to 100, that assignment is exhaustive and non-overlapping, which the
shipped table is not. (It leaves fractional values between bands undefined; volunteers estimating in
whole percents or 5-percent bins never produce one, and the source protocol bins likewise.)

**(b) Row 3 asks about discoloration in a month when discoloration is normal. Confirmed against the
code, not the prose.** The shipped row 3 reads `Noticeable thinning or discoloration; dieback 10 to
25%; still clearly viable`. `Vitality.isRatingPermitted` suppresses the section only for a
`.deciduous` species whose month is outside `leafOnMonths`. `Species.leafOnMonths` derives the window
as running "from the opening of the new-growth season to the **close of the fall-color season**", so
`fall_color_months` sit *inside* the leaf-on window by construction — the same derivation E33
rewrote when it replaced `fallColorMonths.last` with `MonthRange.spanning(_:)`. A red maple in October
is therefore in leaf, ratable, and noticeably discolored, and the shipped anchor points its rater at
row 3.

Two things E33 makes precise and which should be stated rather than assumed. E33 did not create this;
it corrected a *different* bug in the same derivation, and the fall-color-inside-leaf-on relationship
is the intended behavior, not the defect. And E33 records that every `seasonal` in the shipped seed is
empty, so every deciduous species currently takes the documented April–October fallback — which
contains October, so the problem is live today rather than latent.

The repair is copy, not gating: no candidate keeps "discoloration" unqualified in a row a seasonal
color change satisfies. Adding a second condition to the gate would suppress the rubric in the fall
for trees that are in leaf, which is what E33 exists to prevent.

#### 6. Blast radius, measured.

Both resolutions were measured by grep over `Cypress`, `CypressTests`, `CypressUITests`, `docs` and
`Tools`. Nothing outside `docs/RULINGS.md` and `docs/rulings-pending/vitality-rubric-candidates.md`
cites R13 by number.

**Rewriting the code to `SCREENS.md`'s five sentences.**
- `Cypress/Core/Rubric/Vitality.swift`: five string literals, plus three doc comments that name
  PRODUCT §3 as the source (file header, `label`, `anchor`).
- **Zero test edits.** `ReadingOrderAccessibilityTests.testCheckInVitalityRowsReadInRubricOrder` is the
  only test in either target carrying literal rubric copy, and it matches `hasPrefix` on
  `VitalityRow.title` (`"1 · Severe decline"` … `"5 · Thriving"`) — six string sites, all titles, none
  an anchor. No other test file contains an anchor fragment.
- **No authored accessibility label.** `CheckInView.vitalityRow` is a `Button` with two `Text`
  children, so VoiceOver reads title-then-anchor synthesized; the `hasPrefix` match survives.
- No stored reference images anywhere in the repository, so no shot suite needs rebaselining.
- No token, schema or migration change.
- Cost: the rubric loses its dieback band on rows 1, 4 and 5 (§4), and keeps the 25-percent overlap on
  rows 2 and 3 (§5a). It does drop `survival doubtful`, which is a gain.

**Amending R13 and leaving the code alone.**
- `docs/RULINGS.md` only. Zero code, zero test, zero token change.
- Leaves `SCREENS.md` 05 §3 stating copy the app does not draw. That has to be annotated or
  reconciled, or the next agent to read the two files re-files this ticket.

**For completeness, since a future rubric may relabel rather than re-anchor.** A *label* change is
more than the three edits previously measured. `Vitality.label`; `CypressColor.Vitality.name`;
`ReadingOrderAccessibilityTests` (six literal sites); `StatusBadge.Kind.thriving` and its `title`,
which draws the `THRIVING` badge on screens 01, 03, D1 and D2 documented in `SCREENS.md` §2 as one of
exactly three; `CypressColor.thrivingBadgeFill`/`thrivingBadgeText` and their `Dark` pair;
`TokenGallery` and `ComponentGallery` entries; and — not previously reported —
`SpeciesPresentation.nearbySubtitle`, which lowercases `Vitality.label` into screen 07's nearby row
(`214 photos · thriving`), so a relabel changes a verbatim `SCREENS.md` copy string on a **second**
screen.

#### 7. Which is the defect.

**The code is not the defect, and R13 should not be reversed. R13 is defective in its example, and
R13's holding, correctly applied, already decides the substance for PRODUCT's quantities.**

1. R13's parenthetical quotes PRODUCT's sentence as though it were screen 05's copy (§3). That is a
   factual error inside the ruling and should be corrected in place — it is a correction, not a
   reversal.
2. R13's holding stands: `SCREENS.md` owns screen copy, and the design export's five short lines are
   genuinely the drawn copy. That was the right call on the right reasoning.
3. But R13 reserves *meaning* to PRODUCT, and a dieback band is meaning (§4). `SCREENS.md` never had
   authority to drop the quantity from rows 1, 4 and 5. What `SCREENS.md` does own here is the
   register — short, comma-spliced, readable on a sidewalk — not the definition.
4. So neither table ships as written. Both are draft v0 by PRODUCT §3's own words, both carry the
   defects in §5, and both are superseded by the rubric the owner chose on 2026-08-07 (Candidate A,
   `docs/rulings-pending/vitality-rubric-candidates.md`). Candidate A keeps a quantity in every row,
   repairs the boundaries, and drops the discoloration clause and the prognosis.
5. The resolution is therefore to close the fork rather than adjudicate it: **Candidate A's five
   sentences land in PRODUCT §3, `SCREENS.md` 05 §3 and `Vitality.swift` together**, which is what
   the candidates document already required of whichever candidate won.
6. Until that lands, the app keeps PRODUCT's sentences. Rewriting `Vitality.anchor` to the export's
   copy now would ship the weaker text — no band on three of five rows, against a published finding
   that the band is the best-agreeing cue volunteers produce — and Candidate A would throw the work
   away within the round.

The one thing that should not happen is leaving the record as it stands, with a ruling whose example
contradicts its holding and a screen spec that states copy the app does not draw.

#### 8. What was not established

- Whether R13's author opened `SCREENS.md` 05 §3. Git records the ruling and the code, not a reading.
- Whether the two handoff artifacts disagreed deliberately. `SPEC-PHASE1.md` §6 and the `.dc.html`
  export both predate this repository; nothing in `design_handoff_cypress/README.md` states a
  precedence between prose spec and design export.
- Nothing here was compiled and no test was run. This is a documentation branch; every mechanical
  claim is from `git show`, from grep over the working tree, and from `unzip` of the committed
  `Cypress.zip`.
