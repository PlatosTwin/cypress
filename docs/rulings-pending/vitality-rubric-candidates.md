### The vitality rubric — three candidates, and the owner's decision

**Decision, 2026-08-07: the owner chose Candidate A.** Candidates B and C were not chosen. §0 below
records the decision and the condition on it; §§1–7 are the deliberation as it was written before the
decision and are kept unchanged, because the reasoning is what an advisor will be handed.

The original framing of this document follows. It was written before the decision and says, correctly
for its moment, that nothing in it is a decision — that is now true of §§1–7 only:

> Drafted for owner decision, following the pattern that closed E48's empty-grove copy (E239): draft
> candidates, the owner approves or redlines one, and the approved text ships verbatim. **Nothing here
> is a decision.** PRODUCT §3 calls the shipped scale "draft v0 — needs urban forestry advisor sign-off
> before launch" and DECISIONS §2.5 P-C1 calls the choice OPEN; no candidate below removes that
> requirement, and the one thing this document tries hardest to do is say which horticultural claims
> each candidate would be asking an advisor to underwrite.

---

## 0. The decision

**On 2026-08-07 the owner chose Candidate A**: ratify the current draft as a documented collapse of
the USFS i-Tree / Nowak crown-condition classes, with the band boundaries repaired. The five sentences
in §3, Candidate A, are the approved text.

**Candidate B was not chosen.** **Candidate C was not chosen.** Their write-ups stay in §3 unchanged:
they are the record of what was weighed, and §5's list of what needs an advisor's signature is partly
built out of them.

Two things the decision does **not** do, both restated from §4 because they are conditions and not
decoration:

- It does **not** discharge PRODUCT §3's "needs urban forestry advisor sign-off before launch", and it
  does not close DECISIONS §2.5 P-C1. §5 is the list the advisor is being asked to underwrite, and
  item 1 — that five Cypress classes are a faithful collapse of the seven i-Tree / Nowak classes — is
  the one Candidate A rests on entirely.
- It does **not** move E30. The five per-class reference photographs are still the M2 entry gate and
  still do not exist. §4's second condition stands: pursue NRS-194's Figures 8 and 9 regardless.

### The decision is gated on ticket #260

**Implementing Candidate A is blocked until #260 is resolved.** Candidate A is a repair of **PRODUCT
§3's** boundaries, and RULINGS R13 currently says `SCREENS.md`, not `PRODUCT.md`, is the wording
authority for exactly these five sentences. Landing Candidate A into `Vitality.swift` before that
conflict is settled would be writing repaired PRODUCT text into the app under a standing ruling that
says PRODUCT text is not what ships.

#260 is the investigation §6 asked for when it said "somebody who was there should say which". Its
findings are in `docs/errata-pending/` on branch `docs/260-r13-vitality-conflict`, and the two facts
that bear on this decision are:

- The two tables have disagreed since 1c469cf, because `PRODUCT.md` transcribes `SPEC-PHASE1.md` §6
  and `SCREENS.md` transcribes the `Cypress Screens.dc.html` design export, and those two handoff
  artifacts disagree. Neither distilled document is a transcription error, and neither table has
  changed since.
- R13's holding is sound but its worked example is wrong, and R13's own meaning/wording split puts the
  dieback bands on PRODUCT's side — a band is a class's operational definition, not its phrasing. The
  recommendation to the owner is therefore to correct R13's example rather than reverse the ruling,
  and to land Candidate A's sentences in **PRODUCT §3, `SCREENS.md` 05 §3 and `Vitality.swift`
  together**, closing the fork instead of adjudicating it. That is what §1 already required of
  whichever candidate won.

### One correction to §1's arithmetic, carried over from #260

§1's first defect ("the bands own their endpoints twice") is right in substance and overstated in
detail, and §5 item 2 repeats the overstatement. Read literally, "under 10%" excludes 10 and "over
50%" excludes 50, so:

- **25 percent** is genuinely double-owned — row 3's `10 to 25%` and row 2's `25 to 50%` are both
  inclusive.
- **0 percent** is genuinely double-owned — row 5's `no visible dieback` and row 4's `under 10%`. This
  was not previously reported.
- **10 percent** belongs to row 3 alone; **50 percent** belongs to row 2 alone.

So the shipped table has one ambiguous interior boundary and one ambiguous endpoint, not three
ambiguous boundaries. **This does not change the recommendation or the repair.** Candidate A's bands —
`No dead wood visible` / `1 to 10%` / `11 to 25%` / `26 to 50%` / `Over half` — were checked against
every integer from 0 to 100 and are exhaustive and non-overlapping, which the shipped table is not.

§1's second defect (row 3's discoloration clause against the seasonality gate) was re-checked against
`Vitality.isRatingPermitted` and `Species.leafOnMonths` and holds exactly as written. One thing #260
adds: E33 records that every `seasonal` in the shipped seed is empty, so every deciduous species takes
the documented April–October fallback, which contains October — the problem is live today, not latent.

---

## 1. What the question actually is

### The standing record

DECISIONS §2.5 P-C1 states the stake in one sentence: **every observation collected before the rubric
exists is permanently un-normalizable.** DECISIONS §2.8 lists it as blocking Phase 1 data collection.
PRODUCT §11's open-questions list asks it as a binary — adopt USFS urban FIA crown classes wholesale,
or ship a simplified five-class derivative validated against them. `docs/ROADMAP.md`'s "Also
outstanding" section repeats that the source documents themselves flag this as the highest-value
unresolved question.

### What ships today, read from the code rather than from the docs

`Cypress/Core/Rubric/Vitality.swift` is the whole rubric. Five cases, `severeDecline = 1` … `thriving
= 5`; `label` and `anchor` carry the copy; `rubric` carries the order, worst first. Nothing else in
the app authors a class label or an anchor sentence — `CheckInPresentation.vitalityRows` maps
`Vitality.rubric`, and `VitalityRow` has no initializer that accepts copy. The seam the ROADMAP
promised is real and I checked it: **replacing the anchor sentences is an edit to one file.**

The anchor sentences the app draws are PRODUCT §3's, verbatim:

| Level | Label | Anchor as shipped |
|---|---|---|
| 1 | Severe decline | Mostly bare in season; over 50% dieback; survival doubtful |
| 2 | Poor | Sparse canopy; major dead limbs; dieback 25 to 50%; stress obvious |
| 3 | Fair | Noticeable thinning or discoloration; dieback 10 to 25%; still clearly viable |
| 4 | Good | Canopy mostly full; minor thinning or isolated dead twigs (under 10% dieback) |
| 5 | Thriving | Full, dense canopy for the season; vigorous new growth; no visible dieback |

**Found while reading, and it needs its own correction independently of anything decided here.**
RULINGS R13 ruled that `SCREENS.md` owns the exact words under each vitality level and that "its
wording is what ships"; `PRODUCT.md` stays the authority on the rubric's *meaning*. `SCREENS.md` 05 §3
draws five different, shorter anchor lines (`Mostly bare crown, major dead limbs`; `Large dead
sections, 25–50% dieback`; `Noticeably thin, 10–25% dieback`; `Canopy mostly full, isolated dead
twigs`; `Dense canopy, vigorous new growth`). **The app ships PRODUCT's five, not SCREENS.md's five.**
R13 was recorded on 2026-07-24, three days after screen 05 was built, and the code was never brought
across; R13's own text quotes PRODUCT's level-1 sentence while ruling that SCREENS.md owns the
wording, so the ruling may itself have been written against the wrong table. Whichever candidate is
approved, the approved text has to land in **both** documents and the code, and the divergence should
be recorded as an erratum rather than quietly overwritten.

### What replacing the placeholder touches, measured

- **Free.** The five anchor sentences. `ReadingOrderAccessibilityTests
  .testCheckInVitalityRowsReadInRubricOrder` matches rows by `hasPrefix` on the *title* only, so
  anchor phrasing is genuinely not pinned by any test. This is what the brief means by "never
  phrasing-dependent", and it holds.
- **Cheap but not free.** The five class **labels**. They exist in two places
  (`Vitality.label` and `CypressColor.Vitality.name`, the design-token gradient enum) and are
  hardcoded as five literals in `ReadingOrderAccessibilityTests`. A rename is three edits.
- **Expensive.** Renaming class 5. `StatusBadge.Kind.thriving` draws a `THRIVING` badge on screens
  01, 03, D1 and D2 whenever the latest observation is class 5, and that badge is documented in
  `SCREENS.md` §2 as one of exactly three. Renaming the top class renames a badge on the map.
- **A stop-and-report.** Changing the *number* of classes. `AppSchema`'s `observations.vitality` is
  `CHECK (vitality IS NULL OR vitality BETWEEN 1 AND 5)`, `SCREENS.md` §1.2 specifies exactly five
  reference-swatch gradients in light and dark, and `CypressColor.Vitality` has five cases. Per
  CLAUDE.md, a task that turns out to need a migration stops and reports. R13 also puts a level added
  or redefined in PRODUCT's hands, not SCREENS.md's.

### What choosing a rubric does *not* unblock

**E30.** BUILD-PLAN §8 and DECISIONS constraint 19 make the five per-class reference photographs an M2
entry gate — the check-in screen does not ship without them. There are no such assets in the
repository; what draws today is SCREENS.md §1.2's gradient placeholder, and D3 makes color secondary
coding only, so the swatch carries none of the calibration the photograph is there to provide. **The
words were never the gate. The photographs are.** Section 4 says what I think follows from that.

### Two defects in the shipped text that any candidate should fix

1. **The bands own their endpoints twice.** "under 10%", "10 to 25%", "25 to 50%", "over 50%": a
   rater who reads exactly 25 percent dieback has two rows that both fit, and a rater who reads
   exactly 10 percent has two more. The source these bands derive from does not do this (see §3,
   Candidate A). *(Overstated — see §0's correction. 25 percent and 0 percent are double-owned; 10 and
   50 are not. The defect and the repair stand.)*
2. **Row 3 asks about discoloration in a month when discoloration is normal.** The anchor says
   "Noticeable thinning or discoloration". `Vitality.isRatingPermitted` suppresses the section only
   for a deciduous species out of leaf, and `Species.leafOnMonths` is derived so that
   `fall_color_months` sit *inside* the leaf-on window (E33). A red maple in October is therefore
   ratable, in leaf, and noticeably discolored, and the shipped anchor points its rater at row 3. No
   candidate below keeps "discoloration" unqualified in a row that a seasonal color change satisfies.

A third, softer point: row 1 ends "survival doubtful", which is a **prognosis**, not an observation.
Screen 05 records what somebody saw. The register everywhere else in this app is to say the true thing
and stop (R12's lineage, `CheckInCopy.reviewNotice`, E239's empty grove). A volunteer predicting
whether a tree lives is a different act from a volunteer counting dead limbs, and the schema stores
one integer either way.

---

## 2. What the seed can support — a premise refuted

The brief offers "a rubric driven by what the seed data can already distinguish" as one of three
possible approaches. **The seed can distinguish nothing about tree condition, so this is not an
available axis.** Read from `Fixtures/seed/cypress-seed.sqlite`:

- `trees` has no condition, dieback, vigor or vitality column of any kind. Its `status` CHECK admits
  five values, and the shipped file contains exactly two: 174,425 `alive` and 24,200 `vacant_site`.
  (This is the same fact that keeps screen 19 out of `ReadingOrderAccessibilityTests`.)
- The six DataSF passthrough columns are free text about legal status, caretaker and permits.
  `city_raw` is NULL on all 198,625 rows.
- The quantitative columns that do exist are not condition: `dbh_city_cm_min`/`max` on 166,984 rows
  and `planted_year` on 38,184.
- Vitality lives only in `observations`, which is the *writable* database, created empty on first
  launch. Every vitality integer that will ever exist is one a volunteer is about to produce.

So the rubric's job is not to describe data the project has. It is to **manufacture** the only
condition data this project will ever hold, which is exactly why P-C1 calls pre-rubric observations
permanently un-normalizable.

One thing the seed *can* support, and Candidate C uses it: species identity and neighbors.
`leaf_retention` is populated for 468 of 731 species, covering 157,088 of the 174,425 alive trees, and
the species screen already counts others nearby. A rubric that asks "compared with the same species
nearby" is answerable from data the app already holds.

---

## 3. The candidates

Each is given worst-to-best, which is `Vitality.rubric`'s order and is asserted by
`ReadingOrderAccessibilityTests`.

---

### Candidate A — ratify draft v0 as a documented collapse of the i-Tree / USFS crown-condition classes, with its boundaries repaired

**The approach.** Change as little as possible and make the existing derivation explicit and correct.
PRODUCT §3 already describes the scale as a "simplified derivative of USFS urban crown-condition
classes", and that claim checks out: the seven-class condition scale used by i-Tree Eco and published
in the urban-forestry literature by Nowak and colleagues runs excellent (<1 percent crown dieback),
good (1–10), fair (11–25), poor (26–50), critical (51–75), dying (76–99), dead (100). Draft v0 is that
scale with critical and dying merged and dead removed:

| i-Tree / Nowak class | percent dieback | Cypress row |
|---|---|---|
| excellent | under 1 | 5 · Thriving |
| good | 1–10 | 4 · Good |
| fair | 11–25 | 3 · Fair |
| poor | 26–50 | 2 · Poor |
| critical + dying | 51–99 | 1 · Severe decline |
| dead | 100 | not a vitality class — the `Appears dead` status segment |

That is a clean collapse, not an invention. What is wrong with the shipped text is the transcription:
the source's bands do not overlap and Cypress's do, and two of Cypress's sentences carry clauses the
source does not (discoloration, and a survival prognosis).

**The five rows.**

| Level | Label | Anchor |
|---|---|---|
| 1 | `1 · Severe decline` | `Over half the crown is dead wood or bare in season; major limbs dead` |
| 2 | `2 · Poor` | `26 to 50% of the crown is dead wood or bare; large dead sections` |
| 3 | `3 · Fair` | `11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf` |
| 4 | `4 · Good` | `1 to 10% of the crown is dead wood; canopy otherwise full` |
| 5 | `5 · Thriving` | `No dead wood visible; canopy full for the season` |

**What it costs.**

- *Of the volunteer:* a percentage estimate of crown dieback, from the sidewalk, with no card and no
  training. This is the real price. In the source protocol the same estimate is made by two observers
  from different viewpoints against a printed density-transparency card.
- *What it can distinguish:* five levels of dead wood as a fraction of the crown, and nothing else. It
  cannot distinguish a tree that is thin from drought from a tree that is thin from pruning, cannot
  see a hollow trunk (the structure chips carry that separately), and deliberately says nothing about
  leaf color.
- *What it needs that the project does not have:* an advisor's ratification that merging critical and
  dying into one row does not destroy a distinction a city needs, and a decision on which side of 10,
  25 and 50 the boundaries fall. The five reference photographs (E30) remain missing.
- *What it commits the project to:* percent crown dieback as the measured quantity, permanently, and
  therefore to joinability with any city's own i-Tree Eco run. That joinability is the concrete cash
  value of P-C1's "normalizable".
- *Mechanically:* zero label changes, zero test changes, zero token changes, no migration. One `Core`
  file, plus the SCREENS.md/PRODUCT reconciliation §1 describes.

---

### Candidate B — adopt USFS GTR NRS-194's crown vigor classes whole, inverted

**The approach.** Stop deriving and adopt a published federal field guide verbatim. Roman et al.
(2020), *Urban Tree Monitoring: A Field Guide*, Gen. Tech. Rep. NRS-194, USDA Forest Service Northern
Research Station, §2.11 and Table 10, defines **crown vigor** as five classes from a visual
examination of the crown, reflecting the proportion of the crown showing fine-twig dieback, foliage
discoloration and/or defoliation, plus major branch loss. Class 1 is healthy (under 10 percent
cumulative, no major branch mortality), class 2 is slightly unhealthy (10–25 percent), class 3
moderately unhealthy (26–50), class 4 severely unhealthy (over 50, foliage still present), class 5
dead. It explicitly excludes trunk condition and structural stability, and it is written for urban
forest managers, interns and **citizen scientists** — the same audience as this app.

It runs the opposite direction from Cypress, so it inverts. Inverted, its five classes fill Cypress's
five rows exactly, with no invention and no schema change.

**The five rows.**

| Level | Label | Anchor |
|---|---|---|
| 1 | `1 · Dead` | `No green leaves, no live buds, no green tissue under the bark` |
| 2 | `2 · Severely unhealthy` | `Over half the crown shows dead twigs, discolored or missing leaves; some foliage still present` |
| 3 | `3 · Moderately unhealthy` | `26 to 50% of the crown shows dead twigs, discolored or missing leaves` |
| 4 | `4 · Slightly unhealthy` | `10 to 25% of the crown shows dead twigs, discolored or missing leaves` |
| 5 | `5 · Healthy` | `Under 10%; no major branch loss and no large broken branches` |

**What it costs.**

- *Of the volunteer:* the same percentage estimate as Candidate A, over a **compound** quantity —
  dieback, discoloration and defoliation added together. Harder to hold in the head, and it reopens
  the October problem: a deciduous tree in fall color is discolored by definition, and NRS-194's
  users are assumed to be running a defined monitoring season that this app does not have.
- *What it can distinguish:* the same five bands, plus a dead tree — which is the collision. Screen
  05 already has an `Appears dead` segment two sections above the rubric, and it is a different kind
  of statement: `ObservationStatus.appearsDead` opens a `review_flags` row for a community reviewer
  (E170, `CheckInCopy.reviewNotice`), while a vitality integer opens nothing. A card that asks the
  same question twice with two different consequences is a card that will get two different answers.
  E29 and DECISIONS constraint 7 exist because these two vocabularies have already been confused once.
- *What it needs that the project does not have:* an advisor's confirmation that the inversion is the
  right presentation for a volunteer app, and a resolution for the dead-row collision. It needs
  **less** botanical sourcing than any other candidate, because the sentences are a federal
  publication, and US Government works are not under copyright.
- *What it commits the project to:* NRS-194's vocabulary in the app's own voice. "Slightly unhealthy"
  and "moderately unhealthy" are clinical where Cypress is warm, and there is no room to soften them
  without ceasing to be the standard.
- *Mechanically:* all five labels change. That is `Vitality.label`, `CypressColor.Vitality.name`,
  five literals in `ReadingOrderAccessibilityTests` — **and** `StatusBadge`, because there is no
  longer a "Thriving" class for the `THRIVING` badge on screens 01, 03, D1 and D2 to key on. The badge
  is documented in `SCREENS.md` §2, so that is a stop-and-ask under DECISIONS constraint 21, not an
  edit. No migration.

**The reason to want B anyway, which is not about the words.** NRS-194 ships **per-class reference
photographs**: Figure 8 gives all five classes for young, recently planted trees; Figure 9 gives the
four live classes for mature street trees. That is the exact artifact E30 says does not exist and
DECISIONS constraint 19 makes an entry gate. Figure 9's photographs are credited to R.A. Hallett,
USDA Forest Service; Figure 8's are credited to B.S. Breger, "used with permission", which is a
permission granted to the Forest Service and not automatically to us. See §6.

---

### Candidate C — what a volunteer can see from the sidewalk, with no percentages at all

**The approach.** Assume the percentage is the thing that goes wrong, and remove it. Anchor every row
on something a person can check by looking, without estimating a fraction: whole limbs with no leaves,
whether leaves reach the branch tips, whether this year's shoots are visible, and comparison with the
same species nearby. The last of these is the reference-tree device the ICP Forests crown-condition
manual uses for defoliation, and it is answerable from data the app already has (§2).

**The five rows.**

| Level | Label | Anchor |
|---|---|---|
| 1 | `1 · Severe decline` | `More bare branches than leafy ones; whole limbs carry no leaves` |
| 2 | `2 · Poor` | `Several whole limbs are bare; wide gaps you can see sky through` |
| 3 | `3 · Fair` | `Thinner than others of the same species nearby; bare twig ends throughout` |
| 4 | `4 · Good` | `Leafy throughout; a few dead twigs at the branch tips` |
| 5 | `5 · Thriving` | `Leafy right out to the branch tips; this year's shoots easy to see` |

**What it costs.**

- *Of the volunteer:* the least of the three. No fraction, no card, no arithmetic. Row 3 asks for a
  comparison, which needs another tree of the same species in sight and is the one row that can fail
  to be answerable.
- *What it can distinguish:* honestly, fewer than five things. "More bare than leafy" and "several
  whole limbs bare" are not separated by any defined quantity, and rows 4 and 5 differ by the presence
  of new shoots, which is a shoot-extension judgment rather than a crown judgment — Bond (2010) and
  the CTLA guide both treat average shoot extension as its own parameter, not as the top of a crown
  scale.
- *What it needs that the project does not have:* **the most sourcing of the three.** Every one of
  these five sentences is a horticultural claim with no citation behind it, which is precisely what
  DECISIONS constraint 15 forbids inventing. It is also un-normalizable by construction: no mapping
  to i-Tree, to NRS-194, or to anything a city collects, which is the harm P-C1 names.
- *The evidence cuts against it.* Hallett and Hallett (2018) is the one published study of volunteers
  running exactly this protocol on exactly this population: 22 volunteers, mostly high-school
  students, two hours of training, checked against an expert on 59 living trees. Fine-twig dieback —
  the percentage — showed the *best* agreement of any variable. Crown transparency, computed from
  photographs, was the worst. That is evidence that the percentage is not the hard part, and that this
  candidate spends comparability to fix a problem smaller than it assumes.
- *Mechanically:* labels unchanged, so it is as cheap as Candidate A. One `Core` file.

---

## 4. Recommendation

**Take Candidate A, and pursue Candidate B's photographs separately.** Reasoning, in the order that
decided it:

1. **P-C1 names the harm as un-normalizable data, and only A preserves the normalization PRODUCT
   already claims.** The scale's value to a city is that its numbers can be joined to that city's own
   i-Tree Eco run. C throws that away outright. B keeps a different normalization but pays for it with
   a dead row that collides with the Status control on the same card.
2. **The one measurement of volunteers doing this work says the percentage is not the failure mode.**
   Hallett and Hallett (2018) found best agreement on fine-twig dieback. Candidate C's whole premise
   is that the percentage is what breaks; the published evidence says otherwise.
3. **A is the only candidate with no stop-and-ask in it.** B renames a badge documented in SCREENS.md
   §2, which DECISIONS constraint 21 makes a stop-and-ask, and puts "Dead" on a card that already
   reports dead trees through a review flag. A touches one `Core` file.
4. **The words were never the gate.** E30 is the gate, and E30 is about photographs. Adopting a
   different set of sentences does not move it one inch, so the criterion for choosing between
   sentences should be "which is cheapest to be wrong about", and that is A.

Two conditions on that recommendation, and they are not decorative:

- **A is a recommendation about what to send an advisor, not a substitute for one.** PRODUCT §3 says
  draft v0 needs sign-off; §5 below lists exactly what the advisor is being asked to underwrite.
- **Go after NRS-194's Figures 8 and 9 regardless of which candidate wins.** They are published
  per-class reference photographs of urban street trees, from a federal field guide aimed at citizen
  scientists, in a five-class scale that maps onto ours by inversion. If those photographs can be
  cleared, E30's entry gate becomes a licensing question with an identified source rather than a
  photo shoot with no brief — and that is worth more to this project than any of the three sets of
  sentences above.

**Not recommended, and worth saying so explicitly: do not ship draft v0 unchanged.** The overlapping
boundaries and the October discoloration problem in §1 are defects in the current text whichever
rubric eventually wins, and both are cheap to fix now.

---

## 5. What needs an authoritative botanical source

Named plainly, because flagging these is part of the deliverable. Each is a claim I am not qualified
to make and the project cannot presently stand behind.

1. **That five Cypress classes are a faithful collapse of the seven i-Tree / Nowak classes** — and
   specifically that merging critical (51–75 percent) and dying (76–99 percent) into one `Severe
   decline` row does not destroy a distinction a city needs. This underwrites Candidate A entirely.
2. **Where the boundaries fall.** 25 percent and 0 percent currently belong to two rows each; 10 and
   50 do not (§0's correction amends this item, which originally named 10, 25 and 50). The arithmetic
   problem is mine to point at; the fix is an advisor's to pick.
3. **Whether crown dieback alone is the right quantity, or whether discoloration and defoliation
   belong in it.** A uses dieback alone; B follows NRS-194 and adds the other two. These give
   different answers on the same tree in the same month.
4. **How seasonal leaf color interacts with the rating.** `Vitality.isRatingPermitted` gates only on
   leaf-on/leaf-off, and `fall_color_months` fall inside the leaf-on window by construction (E33). If
   the rubric mentions discoloration at all, either the gate needs a second condition or the anchor
   needs a seasonal qualifier. This is the same advisor who owes an answer on E7's invented
   April-to-October leaf-on fallback.
5. **Whether "vigorous new growth" belongs at the top of a crown scale.** It is a shoot-extension
   judgment, which Bond (2010) and the CTLA guide treat as a separate parameter. It appears in draft
   v0's row 5, in SCREENS.md 05 §3's row 5, and in Candidate C's row 5.
6. **Whether a volunteer should be asked for a prognosis at all.** "Survival doubtful" (draft v0, row
   1) is a prediction. Removing it, as all three candidates do, is itself a judgment an advisor should
   ratify rather than a copy edit.
7. **Every sentence in Candidate C.** None of them has a source. If C is chosen, all five need
   writing by somebody qualified, not redlining.

---

## 6. What I could not resolve

- **The photograph licensing.** NRS-194 is a USDA Forest Service publication and the *text* of Table
  10 is a US Government work. The photographs are credited individually: Figure 9's four mature-street-
  tree images to R.A. Hallett, USDA Forest Service; Figure 8's five young-tree images to B.S. Breger,
  "used with permission". A permission granted to the Forest Service is not a permission granted to
  us. This needs a real answer before E30 leans on them.
- **The HTHC field guide itself.** "Tree Health Metrics: A Brief Field Guide" (R. Hallett), the
  Healthy Trees Healthy Cities protocol document, 404s at its Conservation Gateway URL. Secondary
  descriptions say its crown vigor classes are the same five as NRS-194 Table 10, which is consistent
  with Hallett being an author of both, but I could not read the guide directly and am not asserting
  it.
- **Whether an urban-forestry advisor is engaged.** PRODUCT §3, PRODUCT §11 and DECISIONS §2.5 all
  route this to one, and I have no visibility into whether that person exists yet. If they do not,
  that — not the choice between these three — is the blocking item.
- **The R13 divergence's history.** I established that the app draws PRODUCT's sentences, that
  SCREENS.md draws different ones, and that R13 says SCREENS.md's ship. I did not establish whether
  R13 was written knowing that, or whether it was written against PRODUCT's table by mistake. Somebody
  who was there should say which, because it determines whether this is a code defect or a ruling
  defect. **Answered by ticket #260** — see §0. Nobody was there; git was. The two tables came in
  disagreeing from two different handoff artifacts, R13 illustrated itself with a string that only the
  running app produces, and its holding survives while its example does not.
- **Anything requiring a build.** This is a documentation branch; nothing was compiled and no test was
  run. Every mechanical claim in §1 comes from reading `Vitality.swift`, `CheckInPresentation.swift`,
  `CheckInView.swift`, `StatusBadge.swift`, `CypressColor.swift`, `AppSchema.swift` and
  `ReadingOrderAccessibilityTests.swift`, and from querying the seed directly. The seed figures are
  from `Fixtures/seed/cypress-seed.sqlite` in this worktree and are reproducible with `sqlite3`.
- **Whether five is the right number at all.** Bond (2010) argues from Roloff that four classes suffice
  for urban work, and that finer resolution is misplaced precision — no evidence exists that tree
  health actually changes across a 5 percent dieback boundary. NRS-194 has four *live* classes.
  Cypress has five, pinned by a schema CHECK, five design tokens and a design export. Changing that
  number is a migration, and per CLAUDE.md this task stops and reports rather than proposing one. It
  is recorded here because it is a real question that an advisor may well raise, and the answer will
  cost more than any of the three candidates above.

---

## 7. Sources

Every citation below was fetched and read for this document, not recalled.

- Roman, L.A.; van Doorn, N.S.; McPherson, E.G.; Scharenbroch, B.C.; Henning, J.G.; Östberg, J.P.A.;
  Mueller, L.S.; Koeser, A.K.; Mills, J.R.; Hallett, R.A.; Sanders, J.E.; Battles, J.J.; Boyer, D.J.;
  Fristensky, J.P.; Mincey, S.K.; Peper, P.J.; Vogt, J. 2020. *Urban tree monitoring: a field guide.*
  Gen. Tech. Rep. NRS-194. Madison, WI: USDA Forest Service, Northern Research Station. 48 p.
  Crown vigor is §2.11, Table 10, p. 28; reference photographs are Figures 8 (p. 29) and 9 (p. 30).
  <https://research.fs.usda.gov/treesearch/60818>
- Hallett, R.; Hallett, T. 2018. Citizen science and tree health assessment: how useful are the data?
  *Arboriculture & Urban Forestry* 44(6): 236–247. doi:10.48044/jauf.2018.021.
  <https://auf.isa-arbor.com/content/44/6/236>
- Bond, J. 2010. Tree condition: health. *Arborist News*, February 2010: 34–38. International Society
  of Arboriculture. Reviews CTLA and FIA, and argues for four classes in urban work.
- Schomaker, M.E.; Zarnoch, S.J.; Bechtold, W.A.; Latelle, D.J.; Burkman, W.G.; Cox, S.M. 2007.
  *Crown-condition classification: a guide to data collection and analysis.* Gen. Tech. Rep. SRS-102.
  Asheville, NC: USDA Forest Service, Southern Research Station. 78 p. This is the "USFS urban FIA
  crown classes" PRODUCT §11 names. <https://research.fs.usda.gov/treesearch/27730>
- Nowak, D.J.; Crane, D.E.; Stevens, J.C.; Hoehn, R.E.; Walton, J.T.; Bond, J. 2008. A ground-based
  method of assessing urban forest structure and ecosystem services. *Arboriculture & Urban Forestry*
  34(6): 347–358. The seven condition classes i-Tree Eco uses.
- ICP Forests. *Manual on methods and criteria for harmonized sampling, assessment, monitoring and
  analysis of the effects of air pollution on forests*, Part IV: Visual Assessment of Crown Condition.
  The reference-tree device Candidate C borrows. <https://www.icp-forests.org/>
- Healthy Trees, Healthy Cities, USDA Forest Service / The Nature Conservancy.
  <https://research.fs.usda.gov/nrs/nrs/centers/nyc/hthc>

Internal, cited by number as CLAUDE.md requires: DECISIONS §2.5 P-C1, §2.8, constraints 15, 19, 21;
PRODUCT §3, §11; SCREENS.md 05 §3 and §1.2; RULINGS R12, R13; ERRATA E7, E9, E28, E29, E30, E33, E170,
E239.
