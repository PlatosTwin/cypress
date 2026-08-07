### Candidate A is the vitality rubric; the fork closes; R13's worked example is corrected

Ticket #261. The owner chose **Candidate A** from `docs/rulings-pending/vitality-rubric-candidates.md`
and then ruled on the document conflict that blocked it (ticket #260): **close the fork.** The five
anchor sentences below now stand identically in `docs/distilled/PRODUCT.md` §3,
`docs/distilled/SCREENS.md` 05 §3 and `Cypress/Core/Rubric/Vitality.swift`, landed in one commit, so
the two source tables and the app state one rubric.

| Level | Label | Anchor | Dieback band |
|---|---|---|---|
| 1 | `Severe decline` | `Over half the crown is dead wood or bare in season; major limbs dead` | 51–100% |
| 2 | `Poor` | `26 to 50% of the crown is dead wood or bare; large dead sections` | 26–50% |
| 3 | `Fair` | `11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf` | 11–25% |
| 4 | `Good` | `1 to 10% of the crown is dead wood; canopy otherwise full` | 1–10% |
| 5 | `Thriving` | `No dead wood visible; canopy full for the season` | 0% |

Labels, level numbers and rubric order are unchanged. The text is Candidate A's §3 table verbatim.

#### 1. R13's holding stands. R13's worked example does not, and is corrected here.

R13 ruled that `SCREENS.md` holds screen 05's anchor sentences and that "its wording is what ships",
reserving a class's *meaning* to `PRODUCT.md`. That holding is sound and is not disturbed.

R13 illustrated itself with:

> `1 · Severe decline · Mostly bare in season; over 50% dieback; survival doubtful`

**That string exists in no document and in no mock.** `1 · Severe decline` is `SCREENS.md`'s title
column; `Mostly bare in season; over 50% dieback; survival doubtful` was `PRODUCT.md` §3's anchor. It
is what `VitalityRow.title` and `VitalityRow.anchor` compose at runtime
(`CheckInPresentation.swift`) — the example was read off the running app in the belief that what the
app drew was screen 05's copy. The correction is to the example, not to the ruling.

**Replace R13's example with the composed row as it now reads:**

> `1 · Severe decline · Over half the crown is dead wood or bare in season; major limbs dead`

That string is again what the app composes, and it is now also what both source tables say, which is
the point of closing the fork: the example can no longer diverge from a document.

#### 2. Why the fork closed toward `PRODUCT.md`'s quantities rather than the export's wording

The two handoff artifacts disagreed from the day both were distilled; neither distilled document was
a transcription error. `SCREENS.md`'s export copy stated a dieback band on rows 2 and 3 and none on
rows 1, 4 and 5, so a rater holding an estimate of 5 percent or of 60 percent found no row naming a
number they could match. **A class's dieback band is its operational definition, and R13 puts
definitions in `PRODUCT.md`'s hands.** What the export owns here is the register — short, readable on
a sidewalk — not the quantity. Candidate A keeps a quantity in every row and is written in that
register.

Both documents now carry a note saying the rubric copy is this decision rather than a transcription,
because both declare themselves verbatim transcriptions of their primaries and a reader who does not
know that will re-file the ticket.

#### 3. What this ruling does NOT decide, and must not be read as deciding

- It does **not** discharge PRODUCT §3's "draft v0 — needs urban forestry advisor sign-off before
  launch", and it does **not** close `DECISIONS.md` §2.5 P-C1. A rubric was chosen; its horticulture
  was not certified.
- It does **not** move ERRATA E30. The five per-class reference photographs are still the M2 entry
  gate under DECISIONS constraint 19 and still do not exist. The words were never the gate.
- The list of claims that need an authoritative botanical source is §5 of
  `docs/rulings-pending/vitality-rubric-candidates.md` and is unchanged by this ruling. In short: that
  five Cypress classes are a faithful collapse of seven i-Tree / Nowak classes and that merging
  critical with dying loses nothing a city needs; which side of 10, 25 and 50 the boundaries fall;
  whether crown dieback alone is the quantity, or discoloration and defoliation belong in it; how
  seasonal leaf color interacts with the rating; whether "vigorous new growth" belongs at the top of a
  crown scale; and whether a volunteer should be asked for a prognosis at all. Removing "survival
  doubtful" and "vigorous new growth" from the shipped copy is itself a judgment an advisor should
  ratify rather than a copy edit.
- Pursuing NRS-194's Figures 8 and 9, and their licensing, stays open and stays worth more to E30
  than any set of sentences.

#### 4. Scope held

No label changed, so nothing reached `CypressColor.Vitality.name`, `StatusBadge.Kind.thriving` and
its two token pairs, the token and component galleries, or `SpeciesPresentation.nearbySubtitle` —
which lowercases `Vitality.label` into screen 07's `214 photos · thriving`, a verbatim `SCREENS.md`
copy string on a second screen. No token, no schema, no migration, and the number of classes is
unchanged, so `observations.vitality`'s `CHECK (… BETWEEN 1 AND 5)` and the five reference-swatch
gradients are untouched.
