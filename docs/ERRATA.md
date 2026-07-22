# Errata against the source documents

Facts in the handoff documents that turned out to be wrong when we went to build against them.
The source documents are left unedited; this file is the correction record. Anything here overrides
the corresponding statement in BUILD-PLAN.md / DESIGN.md / SPEC-PHASE1.md.

---

### E1 — The DataSF dataset id in BUILD-PLAN §7 is dead

BUILD-PLAN §7 names the Street Tree List as `tuvn-fjcn` (hedged with "use the current portal id at
build time"). That id returns **HTTP 404**.

The live dataset is **`tkzw-k3nq`**, 198,435 rows, last updated 2026-07-20:

```
https://data.sfgov.org/api/views/tkzw-k3nq/rows.csv?accessType=DOWNLOAD
```

`Tools/build_seed.py` uses the live id and verifies its row count against the SoQL `count(1)` before
importing, so this failure mode is now loud rather than silent.

### E2 — The obvious SF neighborhoods endpoint serves empty geometry

BUILD-PLAN §11 ambiguity A4 resolves neighborhood boundaries to "SF Analysis Neighborhoods". The
commonly cited id for that, `p5b7-5n3h`, is a **map visualization**: it returns 41 features with no
geometry at all. Point-in-polygon against it silently matches nothing.

The backing tabular view **`j2bu-swwd`** is the one that serves real MultiPolygons:

```
https://data.sfgov.org/resource/j2bu-swwd.geojson?$limit=200
```

41 polygons with `nhood` names. 195,301 of 195,309 trees match a neighborhood (8 unmatched, 0.004%).

### E3 — SQLite's R*Tree is a conservative pre-filter, not an answer

Not a document error, but a trap the design implies and nobody wrote down. SQLite stores R*Tree
bounding boxes as **float32 and rounds them outward**, so a bbox query returns a superset — measured
drift up to 1.5e-5° (≈1.7 m), and 3,870 rows returned where the exact answer is 3,866.

Every spatial query must re-check against `trees.lat/lon` after the rtree narrows the candidate set.
The required query shape is documented in `Fixtures/seed/schema.sql`. A verification check that only
asserts "the plan mentions VIRTUAL TABLE INDEX" passes on a full table scan too — the plan's trailing
constraint token must be non-empty.

### E4 — `trees.status` enum differs between BUILD-PLAN §4 and PRODUCT/DESIGN

BUILD-PLAN §4: `alive, declining, dead_reported, removed, vacant_site`.
DESIGN via PRODUCT §3: `alive, declining, dead_standing, removed, stump, vacant_site`.

Resolved by precedence — BUILD-PLAN wins, so `dead_reported` and no `stump`. Recorded here because
the DESIGN vocabulary is the one that appears in the mocks' copy, and a future reader will hit this.
Same resolution applied to `shot_type` (BUILD-PLAN's four over PRODUCT's five).

### E5 — The DataSF species placeholder set is larger than §7 documents

BUILD-PLAN §7 names three site-placeholder `qSpecies` values: `Tree(s) ::`, `::`, and empty. The live
data also contains `Tree :: Tree` (124 rows), `Potential Site :: Potential Site` (121 rows) and
several similar. All are site placeholders by §7's own logic and are treated as `vacant_site`. The
full set is a named constant in `Tools/build_seed.py`.

Unrelated but worth knowing: `DBH = 0` in this dataset means "not recorded", not a zero-inch trunk.
Bucketing it to `[0,5)` would fabricate a measurement, so it maps to NULL.

### E6 — `review_flags.kind` is missing a value its own spec uses

BUILD-PLAN §4 lists `appears_dead, appears_removed, duplicate_suspected, wrong_species`. BUILD-PLAN
§7 then requires opening a `removed_but_active` flag during the weekly diff — a kind the §4 list does
not contain. Added to the enum in `Cypress/Core/Models/CommunityNote.swift`.

### E11 — 12,518 map pins are vacant sites, and no screen was drawn for them

`status = vacant_site` is in BUILD-PLAN §4's enum and §7 explicitly creates these rows from DataSF
placeholder species strings. **12,518 of 195,309 seeded records — 6.4% of the map — are vacant
sites**: a planting basin with no tree in it.

No mocked screen covers one. Screen 14 (cold profile) is the nearest fit but its entire premise is a
tree that exists and simply hasn't been photographed: it offers "be the first to photograph this
tree" and shows a photo well, both of which assert a tree that is not there. Screen 19 (memorial) is
also wrong — a vacant site was never a specific tree, so there is nothing to memorialise and no
`site_lineage` to link back to.

Current handling is screen 14 with the photo well and CTA removed. That is a placeholder, not an
answer, and it needs design input per DECISIONS constraint 21. The interesting product question
underneath it: a vacant site is exactly the "coverage gap" the almanac (D1) is supposed to direct
attention toward, so this may want to be a first-class screen rather than a degraded profile.

### E9 — "Unknown leaf retention" is a real state and the type system denies it

`Core.Species.leafRetention` is non-optional, but the seed column is nullable and the sourced content
leaves **66 of 577 species null** — no authoritative source states their habit. Every proposed
default is a botanical claim we cannot support:

- defaulting to `deciduous` lets a fall-colour chip onto an unclassified tree, violating the spirit
  of D5 while satisfying its letter;
- defaulting to `evergreen` (the current `Data` fallback, chosen because it is the only value that
  *cannot* violate D5) asserts that 66 species keep their leaves, which is unsourced.

The honest model is `LeafRetention?`, with unknown rendering **no** phenology chips and **no** autumn
strip colours — the same treatment the long tail already gets for `id_tips`.

**Resolved.** `Species.leafRetention` is now `LeafRetention?` and the seed column round-trips SQL
NULL rather than a substitute. What each call site decided, since "what does nil mean here" is a
different question in each:

- `Species.availablePhenologyTags` returns the **empty set**. Every tag, `fullLeaf` included, is a
  claim about what the tree does over a year, and the whole vocabulary hangs off the one attribute
  nobody sourced.
- `Species.leafOnMonths` returns `nil`, not an empty set — "no window is known" and "in leaf no
  month of the year" are different facts.
- `Vitality.isRatingPermitted` **permits** the rating year-round. PRODUCT §3 suppresses *deciduous*
  species off-season, and suppression is itself an assertion — that this tree is out of leaf right
  now. The two errors do not cost the same: wrongly permitting costs one observation a rater can
  skip, wrongly suppressing removes the vitality UI from a tree for half the year.
- `FoliageStrip.enforcingD5` clamps a bare month away, exactly as for an evergreen. Drawing a bare
  cell is a claim; leaving it out is not.
- `SpeciesQueries.leafRetention` resolves nothing at all, and its `seasonal:` argument is gone — it
  existed only to pick between `.deciduous` and `.evergreen`.

D5's throw still fires for `evergreen` + non-empty `fall_color_months` and never fires for nil, in
`Species.init`, in the database CHECK and in `Tools/validate_species.py`. After the content load the
seed carries leaf retention for **510 of 569** species; the remaining 59 render no phenology surface
at all.

### E10 — Cal Poly SelecTree contradicts itself, and one of the contradictions is load-bearing

SelecTree is the canonical urban-forestry reference for California and the primary source for leaf
retention. **35 of its records declare `foliage_type = Evergreen` and `foliage_fall_color = 1`
simultaneously.** Sixteen of those species are in the SF inventory, covering 7,372 trees.

One of them is ***Prunus cerasifera*, the 6th most common street tree in San Francisco**, which is
deciduous. Taking the field at face value would have written `evergreen` onto it and — through the
D5 rule enforced in Swift, in the database CHECK, and in `FoliageStrip` — **permanently suppressed
its autumn colour everywhere in the app**, with every layer of the D5 machinery working exactly as
designed to enforce the wrong fact.

All 35 are quarantined and resolved against NC State Extension where possible; 10 with no second
source are left null. The general lesson is recorded here because the same failure mode applies to
every mechanically-scraped botanical field: a validated pipeline enforcing a wrong input is worse
than no pipeline, because the enforcement makes it look deliberate.

Also rejected during sourcing, for the record: SelecTree's `memo` field is machine-generated and
describes a fir as having "elongated, oval leaves"; the SF Public Works PDF's bold-means-evergreen
convention mislabels Jacaranda and the entire palm page; USA-NPN has 8 usable fall-colour records
for Ginkgo across California in 15 years; USDA PLANTS' documented API paths 404 and POWO returns 403.

### E8 — Dark mode is specified for four screens, but the app has more than four

SCREENS.md documents dark as a delta against light for D1 (map), D2 (tree profile), D3 (check-in)
and screen 04 (camera, always dark). Every other surface has no dark row, which leaves **59 of 137
color tokens with no documented dark value**.

Verified on device: in dark mode the paired tokens flip correctly, but `surface.sheet` (`#FDFDF8`)
stays near-white, so a bottom sheet would glare. The amber family — pill, selected chip, hazard
panel, 311 CTA — has no dark row either, and the `taped` method badge is light-only despite being
visually identical to the thriving badge, which *does* have a documented dark pair (`#1F3A2C` /
`#8EC3A5`) and almost certainly should share it.

Per DECISIONS constraint 21 ("when a screen or state is not in the mocks, stop and ask rather than
inventing it") no dark values were invented. Each gap was marked `// TODO: no dark value specified`
in `CypressColor.swift`. Dark mode is milestone M4; this needs a design answer before then.

**RESOLVED for 47 tokens, escalated for 17 rows, and the gap in SCREENS.md is still real.**
ROADMAP §3 took the decision: derive the missing values from the documented pairs rather than
invent them per token or ship a broken dark mode, and label every derived value so that review is
one screen. What follows is what the derivation found, because the finding is worth more than the
numbers are.

**The counts, recounted.** The 137 / 78 / 59 above was right when it was written and has drifted
since — E20 added a token, E27 and the taped badge converted three. `CypressColor` now holds **157
colour tokens** carrying a value of their own (plus five aliases that resolve through another
token), of which **62 carry a documented pair** — 55 before this pass, plus 7 found in the D1–D2
delta prose (below). Of the remaining 95, **32 have no second appearance by definition**: they ride
on imagery, they live on screen 04 which is dark always, they belong to the spec document or to W1,
or they are the six raw brand hues, whose scheme-dependent roles are carried by the paired role
tokens instead. That leaves **63 genuine gaps: 47 derived, 16 escalated** — 64 rows in the review
sheet, because the gradient callout is escalated too and is not a colour.

**Seven more dark values were documented in prose and missed by the table-driven transcription.**
E27 called itself the third instance of this; there are now ten. All seven below are `dynamic`,
not derived — they were never gaps, only unread:

| Token | Dark | Stated in |
|---|---|---|
| `border.pinRing` | `#2B3A2C` | D1, "Card thumb … border `#2B3A2C`" |
| `border.glass` (chip) | `#2B3A2C` | D1, "Filter chip off … border `#2B3A2C`" |
| `border.glass` (search) | `#2B3A2C` | D1, "Search bar … border `#2B3A2C`" |
| `border.glass` (bottom bar) | `#26332A` | D1, "Tab bar … top border `#26332A`" |
| `border.calloutGreen` | `#27352B` | D2, "Recognize-it callout … border `1px #27352B`" |
| `calloutGreen` border | `#27352B` | same sentence |
| `calloutGreen` text | `#B9C7B2` | D2, "… body `#B9C7B2`" |

Anyone auditing a token table against a screen should read the delta prose first. Every one of
these ten was in the document; none of them was in §1.

**The transform, and it is not one transform.** The 55 pairs were analysed in OKLCh rather than
sRGB, because lightness, chroma and hue are the three things a designer moves and sRGB mixes them.
Fitted per role, on documented pairs, with the map excluded (D1 paints every map layer by hand and
all of them are already specified):

| Role | Fit | n | Quality |
|---|---|---|---|
| Text | `L' = 1.174 − 0.970·L` | 6 | r² 0.94 — very nearly a reflection about L = 0.585 |
| Borders | `L' = 0.816 − 0.543·L` | 3 | r² 0.99, residual ≤ 0.005 |
| Accents | `L' = 0.73` (constant) | 5 | sd 0.031; a linear fit is worse (r² 0.27) |
| Foliage ramp | `L' = 0.184 + 0.498·L` | 3 | r² 0.998 — compressed, **not** inverted |
| Badge / tinted fills | `L' ≈ 0.30`, hue from the family's accent | 2 | both reproduced within 0.027 |

Chroma is kept where there is chroma to keep (×0.9 on average) and floored at ≈0.025 where there
is not — the dark neutrals are *more* chromatic than the light ones, which is D2's own caption
("green-tinted blacks, never neutral gray") stated as a number. Hue is preserved above C ≈ 0.06
(|ΔH| ≤ 8° on every documented pair) and pulled to the house green ≈150° below
C ≈ 0.02, ramped smoothly between the two.

**Where it does not hold, which is the part worth keeping.**

1. **Surfaces have no transform at all.** `L'` is not a function of `L` for them: r² 0.21, and the
   ordering is not even preserved. `surface.card` (`#FFFFFF`, L 1.000) and `calloutGreenFill`
   (`#EFF3E3`, L 0.957) both land at L ≈ 0.248, while `surface.screen` (L 0.970) and `tabBarFill`
   (L 0.983) — *between* them in light — both land at L ≈ 0.196. The dark surfaces are a
   quantised two-rung ladder set by elevation rather than by value: ground at L ≈ 0.20, raised at
   L ≈ 0.25. Every derived surface below snaps to a rung rather than computing one.
2. **The transform is a function of role AND value, never of value alone.** Five light hexes have
   more than one documented dark counterpart. `#FFFFFF` has three (`#0E1712`, `#18251D`,
   `#DFE8D6` — 0.73 apart in OKLab). `#77836F` has two (`#5F6F61` and `#94A496`, 0.178 apart),
   which is why the text rule's two worst residuals, 0.073 and 0.106, are both at that one hex.
   `#41522F` has two, `#2F6B4F` has two, `#1D4634` has three. A value-only transform is not
   merely imprecise here; it is contradicted by the data.
3. **The amber borders.** The border rule, which reproduces its three documented pairs to within
   0.005, extrapolates `#EBD3A8` to `#44361A` — a brown 0.40 in OKLab from `dark.accent.amber`,
   the only amber the dark palette contains. That is 8× the tolerance, so the rule was rejected
   and the amber family snapped onto the two documented ambers instead. See below.
4. **The chart series.** The accent rule reproduces every documented accent to within 0.043 and is
   still wrong for C23: it anchors lightness, so Canopy and New Growth — 0.117 apart in light —
   land 0.011 apart in dark and three series become two. Escalated as a set.

**The tolerance, and why 0.05.** A derivation is rejected where the fitted transform disagrees
with the documented pairs it claims to cover by more than **ΔE 0.05 in OKLab**. That is the 90th
percentile of the fit residual across all 26 covered pairs (median 0.027), and it is well under
the smallest step between two adjacent rungs of the documented dark text ladder (0.075), so a
prediction inside it lands unambiguously on one rung. A separate, tighter threshold — ΔE 0.02 —
decides when to stop minting: below it the fitted value and a hex the designer already wrote are
the same colour, so the designer's hex is used. **38 of the 47 derived values reuse a documented
hex; 9 are minted**, all of them borders and tinted panels for which the palette has no rung.

**The amber family, which is the one that changes a screen.** SCREENS.md gives it no dark row at
all. The dark palette answers it with exactly two values — `dark.accent.amber` `#D99A4E` for the
mark and `dark.accent.amberBg` `#2E271A` for the ground under it — and D1 and D2 send every amber
they draw to one of the two. So every amber fill derives to `#2E271A` and every amber mark to
`#D99A4E`, minting nothing. Measured on device: the amber pill text is **6.1:1** on its derived
fill (5.2:1 in light), the 311 panel body **6.3:1** (6.5:1), the 311 CTA label **7.6:1** (5.0:1).
The amber family does not fail WCAG after dark; it improves.

Two things it costs, and both are design questions rather than bugs:

- **Light has three amber border weights and dark now has one.** `border.amberSoft` / `amberStrong`
  / `amberMid` all become `#D99A4E`, so after dark the amber pill, the selected amber chip and the
  311 hazard panel no longer differ by border weight. Worth noting that `#D9A05B` — light's
  attention-card border — is ΔE **0.016** from `#D99A4E`, so one of the three was already sitting
  on the dark amber; it is the pale end of the range that has nowhere to go.
- **The 311 phone glyph and CTA label had to invert.** `#FDF3E3` on `#D99A4E` is 2.2:1 and
  unreadable; both now take `dark.bg.screen`, which is the move `ctaLabel` already documents.

**Other contrast findings, reported rather than fixed.**

- `speciesTileLockedGlyph` on `speciesTileLockedFill` is **2.1:1** after dark and **1.8:1** in
  light. Both fail. The `?` is decorative — the tile's meaning is in its label — and raising it
  is a change to a mocked screen, not a dark-mode question.
- The three C23 chart series are left light, so Canopy reads at **2.5:1** and Bark at **2.3:1** on
  a dark card. That is a stated failure rather than a hidden one; it is why they are escalated.
- Everything else derived clears AA: badges 4.9–6.2:1, the memorial banner 6.4:1.

**The 17 escalated rows**, with the reason on each in `CypressColor.swift` and in the gallery. The
seven amber borders are *not* among them — they are derived, above. The list is: the gradient
callout with its border, its border-alias and its ink (4, because a two-stop wash is a drawing and
D1–D3 never draw one), `text.onDark` (1, the `#FFFFFF` ambiguity), the muted-pin family (3 — D1
draws every pin in the dark and then says outright that the removed one is omitted), `toggleKnob`
(1, two tracks that move in opposite directions after dark), the three C23 chart series, and the
five C10 tile accents, whose lightness is set by the base under the radial rather than by their
own value.

**Where the work lives.**

- `CypressColor.derived(light:dark:)` and `CypressColor.escalated(_:)` sit beside `dynamic` and
  `lightOnly`, so the source itself says which of the four claims each token makes. Promoting a
  derived token to specified is one line: `derived` → `dynamic`.
- `CypressColor.reviewTokens` is the 64-row review sheet, and `TokenGallery` renders it as its
  first two sections — derived first to check, escalated second to answer. Design review of this
  entry is one screen, which was the point of the decision in ROADMAP §3.
- `CypressTests/DerivedTokenTests.swift` pins the three ways this fails quietly: a token that
  claims to be derived and still resolves to one colour, a review sheet that has drifted from the
  tokens it prints, and an amber or badge pair that stops clearing WCAG AA after dark.

**What remains, and it is the original entry.** SCREENS.md still documents dark for three screens
out of nineteen. 47 of these values are a considered guess and a designer may overturn any of
them; 17 rows have no answer at all. Nothing here promotes a derivation to a specification.

Verified on device (iPhone 16 Pro, dark): every derived value in `TokenGallery`, the D1 map home,
and the D2/D3 elements built from the real components. `border.dashed` — the token this entry
singles out as "the brightest element on the dark check-in screen" — now reads at 1.7:1 against
the dark ground, where it used to read at 11.6:1 and the mint CTA reads at 9.1:1. D3's caption
asks for the CTA to be the brightest thing on the screen; it now is.

### E7 — The leaf-on window that the seasonality rule depends on is never defined

PRODUCT §3 states that deciduous species are rated for vitality only in leaf-on season, and the app
suppresses the vitality UI off-season "using species leaf phenology". No document defines the
leaf-on window or where it comes from.

Current implementation derives it from the authored `new_growth_months`…`fall_color_months` window,
falling back to April–October when either is empty. **This fallback is invented**, which nothing else
in the botanical layer is, and it should go to the same urban-forestry advisor who has to settle the
open vitality-rubric question (DECISIONS §2.8).

### E12 — A1's pin threshold and San Francisco's tree density make the pin layer's first zoom its worst

BUILD-PLAN §11 ambiguity A1 resolves the map to clusters at zoom ≤ 15 and individual pins at
zoom ≥ 16. That resolution stands and is not the thing being corrected. What is being recorded is
that **zoom 16 — the first zoom at which A1 draws individual pins — is the zoom at which they are
least readable**, and no document anticipated it, because SCREENS.md 01 answers the question with a
drawing of 7 pins over roughly 3 km of city.

Measured against the shipped seed (195,309 rows) on an iPhone 16 Pro (402 × 874 pt). "Screen" is the
whole viewport; the median and p90 are over every non-empty position of that viewport across the
inventory's bounding box:

| Zoom | Screen covers | Trees/screen, median | p90 | max | 18 pt pin = |
|---|---|---|---|---|---|
| 16 | 759 × 1650 m | **1,899** | 4,261 | 6,422 | 34.0 m |
| 17 | 380 × 826 m | 487 | 1,119 | 2,108 | 17.0 m |
| 18 | 190 × 413 m | 140 | 326 | 720 | 8.5 m |
| 19 | 95 × 207 m | 36 | 86 | 324 | 4.3 m |

At 24th & Valencia a zoom-16 screen holds 4,695 trees; at Dolores Park, 4,757. The Outer Sunset, the
neighbourhood the mock actually draws, is the quiet case at 2,555.

**The pins fuse long before the count does.** Nearest-neighbour distance between street trees in the
seed (n = 19,969 sampled): p10 1.8 m, median **5.5 m**, p75 8.3 m, p90 13.4 m, mean 7.1 m. C19 draws
an 18 pt pin, so the share of trees whose nearest neighbour is closer than one pin diameter is:

| Zoom | 1 pt = | 18 pt = | Trees overlapping their nearest neighbour |
|---|---|---|---|
| 16 | 1.888 m | 34.0 m | **98.6 %** |
| 17 | 0.944 m | 17.0 m | 94.5 % |
| 18 | 0.472 m | 8.5 m | 76.3 % |
| 19 | 0.236 m | 4.2 m | 34.9 % |
| 20 | 0.118 m | 2.1 m | 13.1 % |
| 21 | 0.059 m | 1.1 m | 4.6 % |

**18 pt pins stop overlapping at zoom 18.63** — the scale at which one point is 0.306 m and a pin
covers the median 5.5 m gap between two trees. There is no integer zoom at that crossing: 18 leaves
three trees in four touching, 19 is already past it. Getting nine pins in ten to clear takes zoom
20.3 (18 pt = the p10 spacing of 1.8 m), and even zoom 21 still has 4.6 % of pins touching — SF
plants trees closer together than a pin is wide, and no zoom this map can reach undoes all of it.

So A1's threshold puts the pin layer's debut two and a half zoom levels before the pins can be told
apart. Zoom 16 does not render 1,899 trees; it renders a green ribbon along every street, and the
only structure a reader gets from it is the shape of the grid — the pins draw the map instead of the
map carrying the pins.

**What was done about it, and what was not.** A1 is not touched, no de-densification was invented
and the pins were not shrunk — an unmocked behaviour is a question for design, not something to
invent (DECISIONS constraint 21). The only lever inside the existing spec is where the camera opens,
so screen 01 now opens at **120 m across**: 0.298 m per point, an 18 pt pin covering 5.37 m, which
is the median tree spacing, and a median of 55 trees on screen (p90 129). That is about one
intersection and the four block faces around it.

**What still needs a design answer.** Zoom 16 and 17 remain reachable in one pinch, and they still
look the way the table says they look. Options a designer would have to choose between — a pin that
scales with zoom, a density-aware pin, raising the clustering threshold past 16, or accepting the
ribbon as an intentional "this street is planted" texture — are all outside the mocks. The
underlying fact for whoever picks: **San Francisco's street trees are 5.5 m apart, and 18 pt is
5.5 m only at zoom 18.6.** A pin size and a clustering threshold cannot both be chosen freely.

### E20 — Screen 06's 311 panel uses two values §1's token tables do not carry

SCREENS.md 06 §4 gives the 311 panel `radius 20px` and puts a phone glyph filled `#FDF3E3` inside a
54×54 `#B4711F` circle. Neither value has a row in §1:

- §1.4 (radii) runs `18 / 16 / 14 / 12` for cards and controls. **There is no 20.** The panel is the
  only surface in the app at that radius.
- §1.2 (colors) has no `#FDF3E3`. The hex reaches the document only in §1.1, as the *swatch text
  color* printed on the Signal Amber chip — a legibility choice on the palette board, borrowed here
  as a fill.

Both are transcription-complete, so this is a gap in the token tables rather than in screen 06.
Resolved by adding `CypressColor.hazardPanelGlyph` beside the other 311 tokens (a colour in a
feature is a bug, ARCHITECTURE §6) and by naming the radius in `ReportMetrics` with the rest of 06's
one-off geometry, the way `TreeProfileMetrics` already holds 03's.

### E21 — The hazard chips SCREENS.md 06 draws are not the hazard categories the product defines

Three sources name the hazard vocabulary and none of them agree with the mock:

| PRODUCT §5 M7 (the categories) | SCREENS.md 06 §2 (the chips drawn) |
|---|---|
| hanging or broken limb over a path | `Hanging limb` |
| uprooted | — |
| struck by vehicle | — |
| blocking a signal or sightline | `Blocking path` |
| — | `Split trunk` |

`Split trunk` is a hazard no category can hold; `Blocking path` renames a different one; two
categories are undrawn. This is load-bearing rather than cosmetic: the chip decides the
`HazardCategory` that a `POST /reports/hazard-redirect` and D4's private reminder both carry, so a
chip with no category either cannot be built or is stored as a hazard it is not.

Resolved by precedence. Categories are data, and on data BUILD-PLAN/PRODUCT outrank the drawing
(ARCHITECTURE §1), so the picker is driven by `HazardCategory.allCases` and labelled with PRODUCT's
own words shortened to chip length: `Hanging limb` · `Uprooted` · `Struck by vehicle` ·
`Blocking a sightline`. Four chips wrap to two rows where the mock draws one row of three.

Related, and left as drawn: the panel body ("A hanging or broken limb over a path needs the city's
crew…") is written for the one chip the mock selects. No per-category variant is written, because
none is specified and three invented paragraphs would be three invented states (DECISIONS
constraint 21). A designer picking this up owes 06 either generic panel copy or four bodies.

### E22 — 06's two unspecified states, and what was built for them

SCREENS.md 06 says it outright: "the 311 panel appears because a hazard chip is selected. **NOT
SPECIFIED:** what the screen looks like with only a neighborly chip selected, or with nothing
selected." Both were needed to ship the screen. What was chosen, and why it is a reading of the spec
rather than an invention:

- **Nothing selected.** Header and the two pickers. Everything below them — the 311 panel, the
  private-reminder button, the dashed disclosure — is one branch bound to a hazard selection, not
  three independent blocks: the disclosure's own sentences are about the call ("until you call"),
  and a private reminder's category *is* a `HazardCategory`, so neither is expressible without one.
- **Only a neighborly chip selected.** The same, with the chip on. Notably **no submit CTA**: the
  mock draws no primary button for the neighborly branch and BUILD-PLAN §9 asks for none, so posting
  a community note has no drawn affordance and none was added.

Also unspecified and needed: the *selected* appearance of a neighborly chip, since 06 draws all
three off. C4's "structure flag, on (05)" — `#2F6B4F` / `#fff` / 700 at the same `11px 16px` — is
the catalogue's existing partner for the idle variant 06 does specify, so it is used unchanged
rather than a new amber-free selected style being drawn.

Two smaller gaps in the same screen: the vertical gap between a section's micro-label and its chips
(the chips' own `gap:7px` is reused), and any pressed state on the 311 CTA (none, per C6's own
NOT SPECIFIED note in `Buttons.swift`).

### E23 — D4's private reminder cannot be written, because D4 and D9 disagree about who owns it

SCREENS.md 06 §5 draws `Save a private reminder for yourself`, and D4 makes that reminder the only
record a hazard is allowed to leave. It cannot be saved today, and the blocker is not the UI:

1. **`PrivateReminder` requires a `userID`,** deliberately: `private_reminders.user_id` is `NOT NULL`
   and `Core/Models/Hazard.swift` states the reason — "a private reminder belongs to an account, so
   there is no anonymous device-only variant that could later be attributed to the wrong person."
2. **There is no account.** D9 moved accounts later in the funnel: first saves are anonymous under a
   device id, and the ask arrives at the third save via screen 15, which is not built. `LocalAPI`
   ships with `userID == nil` and nothing in the app sets it.

So the reminder is unwritable *by construction* on every device the app currently runs on, and the
two decisions that produce that are both binding. Adding a write path does not fix it: a
`CypressAPI.savePrivateReminder` would throw `unauthorized` on every call, and the outbox has no
kind for one either (`OutboxPayload` covers visit, observation, measurement, care event, favourite).

Nothing was faked. The button is drawn as specified, `ReportModel` assembles a
`PrivateReminderDraft` (tree + hazard category — the part it can honestly know) and hands it to an
injected save action that `RootView` does not supply, so a tap claims nothing. No confirmation
state, no toast, no "saved" copy: DECISIONS constraint 3's principle is that the app never says it
did a thing it did not do, and that applies to the reminder as much as to the city.

**What a decision-owner has to settle:** either D4 relaxes to allow a device-scoped reminder before
sign-in (which is what D9 implies every other first save does), or screen 06's reminder button is
gated behind the account ask, which puts a sign-in wall inside a safety flow. Until then the
`CypressAPI` addition is not worth making.

**RESOLVED — private reminders are device-scoped.** The first branch was taken: D4's reminder can be
owned by a device, and the account ask stays where D9 put it. A sign-in wall inside a safety flow was
never a real option — someone is standing under a broken limb, and the product's premise is that
contributing is frictionless and everything is optional. The contradiction above is left standing
because the source documents still contain it: D4's reasoning in BUILD-PLAN §4 and `Hazard.swift`
argued for an account-only record, and this entry is why the code now says otherwise.

The reasoning, since it is the part worth keeping:

- **A device-scoped reminder is *more* private than an account-scoped one.** It never leaves the
  installation that wrote it, so nothing in DECISIONS §3 loosens. The device id stays exactly what
  D9 makes it — an anonymous handle for un-attributed contributions — and never becomes a user
  identifier.
- **The adoption mechanism already existed.** `claimDevice(deviceUUID:userID:)` is in `CypressAPI`
  for precisely this pattern. When screen 15 lands, reminders written before sign-in arrive on the
  account with the visits, observations, measurements and care events that D9 already migrates.

What changed:

1. **Schema, `AppSchema` v3.** `private_reminders.user_id` becomes nullable, `device_id` appears
   beside it, and `CHECK ((user_id IS NULL) <> (device_id IS NULL))` makes exactly one of them
   non-null. Not "nullable user plus non-null device": that leaves both populated after sign-in, so
   the owner becomes whichever column a query coalesces first, and it keeps a permanent
   device↔account link on the one table whose entire point is privacy. Exclusive ownership means the
   engine carries the invariant — a reminder is never ownerless and never doubly owned — and it makes
   adoption a *move*. `ReminderOwner` is the same rule in Swift: two cases, no third state.
2. **Migration.** v3 rebuilds the table (SQLite cannot drop a NOT NULL in place) and carries every
   existing row across as user-owned, which the new CHECK already accepts. v4 rebuilds `outbox` to
   widen its `kind` vocabulary by one value — the rebuild v2 declined to do for a cosmetic gain, done
   here because the alternative is that the row cannot be written at all. `seq`, state, fail counts,
   error text and photo lists are copied column for column, so a pending contributor's queue is
   unchanged in content and order.
3. **Adoption.** `claimDevice` gains one statement: `SET user_id = :user, device_id = NULL WHERE
   device_id = :device AND user_id IS NULL`. It is an UPDATE whose WHERE clause stops matching once
   it has run, so a second claim moves nothing, nothing is inserted (no duplicates) and nothing is
   deleted (no orphans). A claim by a *different* account leaves already-attributed reminders alone.
4. **The write path.** `OutboxItem.Kind` gains `private_reminder` and `OutboxPayload` a
   `.privateReminder` case, so the reminder is durable before it is attempted like every other
   mutation. `CypressAPI.savePrivateReminder(_:)` is the separate `private_reminders` POST that
   BUILD-PLAN §6 already names; `LocalAPI` implements it, `RemoteAPI` keeps the shape. The reminder's
   own id is the idempotency key, so two taps save one reminder.
5. **Screen 06.** `RootView` now supplies `onSaveReminder`, which resolves the owner from
   `LocalAPI.attribution` (the screen never sees an identity) and hands the mutation to
   `ReminderOutboxWriter`. On success the button is replaced by one line: `Saved. Your reminder stays
   yours alone.` — the screen's own sentence, taken from the dashed disclosure directly beneath it,
   which goes on saying the city has not been notified. A failed save says `Not saved. Tap to try
   again.` and keeps the button. The saved and failed states are **NOT SPECIFIED** by SCREENS.md 06,
   which draws the button and nothing after it; a control that acts and says nothing is the same
   dishonesty in the other direction, so this is the smallest answer that is not silence.

**One thing this hands to whoever builds account deletion.** DECISIONS §3.12 anonymizes attributed
rows — "user_id nulled, device link severed" — and a private reminder cannot survive both, since it
would then be owned by nobody. That path has to choose between deleting reminders with the account
and re-homing them onto the device. The CHECK forces the choice to be made rather than leaving a
hazard note no query can return; it is not made here. **OPEN.**

Proven by `CypressTests/PrivateReminderTests.swift`: a reminder saves with no user present and is
owned by the device; it survives a relaunch both drained and still queued; migrating a v2 database
preserves its reminders and its pending outbox rows and both new migrations replay as no-ops;
`claimDevice` adopts device-owned reminders and claiming twice changes nothing, including nobody
else's. `DataGates` adds the schema invariant: an ownerless or doubly-owned reminder is rejected by
the engine, and a device-owned one is accepted.

### E13 — The seed was declared byte-for-byte reproducible and was not

`.gitignore` says of the bundled seed: "an 88 MB build product of `Tools/build_seed.py`,
**byte-for-byte reproducible**. Regenerate with: `python3 Tools/build_seed.py`." It was not. Two
consecutive runs over the identical `Fixtures/raw/street_tree_list.csv` produced two different
files:

```
a2c95a33b664bb9a640671337fca460d31725aa730751ab6fef1b5a2c43c0f26
06ee5e2131197cf6faa14cea6915b897b868b718ed4b26b0f0edf442d3bb2dbf
```

The cause was one line: `NOW = datetime.now(timezone.utc)`, written into `created_at` and
`updated_at` on all 195,309 trees, all 569 species and all 41 neighborhoods, plus
`seed_meta.generated_at`. The uuids were stable, exactly as designed — nothing about identity was
wrong — so the claim looked true from every angle anybody had checked.

This is worse than an idle claim, because the seed is gitignored: the only way anyone verifies that
the file on their machine is the file the pipeline describes is to rebuild it and compare. A hash
that never matches makes that check useless, and a build product nobody can check is a build
product nobody can trust.

Timestamps now come from a frozen `SEED_EPOCH` — the DataSF snapshot date (E1), which is what these
rows are actually as-of — overridable with `SOURCE_DATE_EPOCH` for a newer download. Reproducibility
verified after the change: two runs, same sha256, seed and `Fixtures/sf_species_map.csv` alike.

### E14 — BUILD-PLAN §7 has no category for an occupied site whose label is not a taxon, and the file it tells you to fix is overwritten on every build

Two findings from the same corner of the ingest.

**The missing category.** §7 splits `qSpecies` into two outcomes: a species, or a site placeholder
that becomes `vacant_site` (E5 widened the placeholder set, and that is still a widening of the same
two-way split). Seven strings covering **312 trees** fit neither — `Shrub :: Shrub`,
`Private shrub :: Private Shrub`, `Privet ::`, `:: To Be Determine`,
`Palm (unknown Genus) :: Palm Spp`, `New Zealand Tea Tree :: New Zealand Tea Tree`,
`:: Brisbane Box`. Something is growing at each of these sites, so they are not vacant; none of the
strings names a taxon, so they are not species either. The parser minted a species row per string,
which meant a planting site labelled `Shrub` had a species uuid, a field-guide slot and a phenology
surface of its own — the shape of a botanical record, holding a growth habit.

They now map to **no species at all** (`NON_TAXON_SPECIES` in `Tools/build_seed.py`), keep
`status = alive`, and carry no `species_assertion`. `species_map.is_non_taxon` records which,
because a provenance fact belongs in a queryable column (DECISIONS §3.13). The profile falls back to
the street address, which is what the city actually recorded.

**The file that could not be fixed.** `build_seed.py`'s own fatal message for the 2 % stub ceiling
reads: "Extend the qSpecies parser or **hand-map the offenders in `Fixtures/sf_species_map.csv`**."
That file is written by `build_seed.py` on every run. Any hand edit survives until the next build
and then vanishes, silently, with the build reporting success. Corrections belong in the tables at
the top of the script; the CSV carries a comment saying so, and the message no longer sends anyone
to edit an output.

Same pass, same file: `patanus racemosa ::` (167 trees) carried a different species id from
`Platanus racemosa :: California Sycamore` (84 trees), so one species was held as two — recorded in
`Fixtures/species/SOURCES.md` §10.1, which says "fixing that belongs in the species map, not here."
It is now folded onto `Platanus racemosa` by `QSPECIES_NAME_CORRECTIONS`, at confidence 0.90 rather
than the 1.00 a clean binomial earns, because the correction is ours and not the city's.

### E15 — `SOURCES.md` names six strings that are not taxa; there are seven, and one of the six is not one of them

`Fixtures/species/SOURCES.md` §4 states "Eight species have no family: six placeholder strings that
are not taxa (`Shrub`, `:: To Be Determine`, `Private shrub`, `Palm (unknown Genus)`, `Privet`,
`Ficus laurel`) and two DataSF strings GBIF could not resolve (`patanus racemosa ::`,
`:: Brisbane Box`)", and §10.2 repeats the six as the set that "should probably map to null".

The eight species carrying no family in `leaf_retention.yaml` are: `Shrub`, `:: To Be Determine`,
`Palm (unknown Genus)`, `Private shrub`, `Privet`, **`New Zealand Tea Tree`**, `:: Brisbane Box`,
`patanus racemosa ::`. `Ficus laurel` is not among them and `New Zealand Tea Tree` is. Sorting the
eight by whether a taxon can be recovered from the string gives **seven** non-taxa, not six:
`:: Brisbane Box` and `New Zealand Tea Tree` are bare vernaculars with no genus in them, and the
one string of the eight that is a genuine misspelling of a real name is `patanus racemosa ::`,
which E14 merges.

**Why `Ficus laurel` stays a species.** It has a family — `Moraceae`, from GBIF — so the sourcing
pass did resolve it, and `Ficus` is a genus the city really did record. But look at how the family
arrived: `match_type: FUZZY`, `rank_matched: SPECIES`, `matched_name: Ficus laureola Warb. ex
C.C.Berg & Carauta`, confidence 95. A Southeast Asian fig nobody plants in San Francisco. The family
is right only because *Ficus laureola* is a *Ficus*; the match itself is wrong, and at any rank
below family it would have written a fact about the wrong plant. This is E10's failure mode in a
second source: a mechanically-scraped botanical field, validated, confidently wrong. Fuzzy matching
at species rank should not be allowed to write a field when the query string is not a binomial.

The `leaf_retention` null breakdown in §11 ("38 with no source found, 12 genus-only strings whose
genus is not uniform, 10 where SelecTree contradicted itself, 6 that are not taxa at all" = 66)
inherits the same off-by-one and does not re-add to 66 once the seventh is counted.

### E24 — Nothing in the mock set opens screen 05

Screen 05 is the highest-frequency contribution in the app (ROADMAP M1) and no mocked screen
contains an affordance that reaches it.

- **03 · Tree profile** has one primary CTA, `Visit · say hello with a photo`, and a quad action row
  of `Favorite` · `Care` · `Share` · `Report`. Its affordance list ends "`Report` → 06; DBH/Height
  cards → 11". No check-in.
- **The clickable prototype never reaches 05 at all.** PROTOTYPE-FLOW §1.2's `screen` enum is
  `'map' | 'identify' | 'profile' | 'camera' | 'saved' | 'grove'`.
- **18 · Next tree is 05's exit.** Its success block reads `Check-in saved`, and its caption opens
  "Saving a check-in immediately offers the next nearest tree." So the screen after 05 is drawn and
  the screen before it is not.

`Route.checkIn(UUID)` exists and `RootView` resolves it, so the destination is built and one line
away from being reachable. **No entry point was invented** — DECISIONS constraint 21. The two
candidates a decision-owner has to choose between are a fifth cell in C8's quad row (which is drawn
with exactly four) and a second primary CTA on 03 (which is drawn with exactly one); both change a
mocked screen, which is not a call to make inside a view file.

Screen 18 is also not wired as 05's confirmation, for a smaller reason: `VisitSavedView` takes a
`VisitSaveReceipt` and its model derives the next tree from a `Visit`. Generalising it over both
contribution kinds is real work in another feature's folder, and until an entry point exists there
is no flow to put it in. The check-in pops back to wherever it was pushed from.

### E25 — 05's optional well has no editor behind it

SCREENS.md 05 §6 draws C15 with the copy `Add photos · notes (optional)` and specifies nothing that
happens when it is tapped: no picker, no sheet, no note field, no target in the affordance list.
Screen 09's well carries the same ambiguity.

The well is drawn and is inert. Inventing a photo picker and a note editor would be inventing two
screens (DECISIONS constraint 21) — and the note editor in particular is not obvious, because 04's
note field is a single line inside a dark camera tray and 05 is neither.

`CheckInDraft` carries `note: String?` and `photos: [OutboxPhoto]` regardless, and
`CheckInOutboxWriter` already writes both through the outbox in the current payload shape — a photo
travels as `OutboxPhoto{path, shotType}` so `photos.shot_type` is recorded from the framing the
contributor chose rather than guessed at upload. When the editor is designed, the view is the only
file that changes.

### E26 — §1.3's type ramp has no 11.5px row, and two screens set one

The vitality anchor line is `11.5px` (SCREENS.md 05 §3) and screen 17's `Notes and numbers sync on
any connection` is `11.5px` (17 §4). §1.3's sans ramp goes 12 → 12.5 and never names 11.5.

`CypressFont.body115` was added rather than the anchor sentence being rounded to `body.12`. This is
the smallest type in the app that carries meaning a rating depends on: D3's whole argument is that
the anchor is legible at rating time, in sun glare, at 7 am. Rounding it is the kind of half-point
decision that is invisible in review and visible in a parking strip.

Same shape as the `body.15.5` / weight-800 gap the ramp already grew a row for (see
`CypressFont.body155ExtraBold`).

### E27 — `text.faintAlt` has a documented dark value; §1.2 does not carry it

§1.2's text table lists `text.faintAlt` `#77836F` with no dark counterpart, and `CypressColor`
transcribed it as light-only. D3's delta list states one in prose: "Footnote `#5F6F61`" — which is
`dark.text.faint`, the value `textFaint` already pairs with.

This is the third instance of the same failure mode: a dark value stated in a screen's delta prose
rather than in the §1.2 table, and therefore missed by a table-driven transcription. The `taped`
badge (D2) was the first two. Any audit of the 59 tokens marked "no dark value specified" (ERRATA
E8, ROADMAP §3) should read the D1–D3 delta lists before deriving anything, because a derived value
that overwrites a documented one is worse than no value at all.

`textFaintAlt` is now `dynamic(light: 0x77836F, dark: 0x5F6F61)`. Its other user is screen 18's
footnote, which has no dark mock and is improved by the pairing.

### E28 — The leaf-off vitality state is a required build with no copy

BUILD-PLAN §9 lists "vitality suppressed leaf-off state for deciduous species" as an M2 build
requirement. PRODUCT §3 states the rule — "deciduous species are rated only in leaf-on season. The
app suppresses the vitality UI off-season using species leaf phenology; structure flags remain
available year-round" — and no document gives the words the volunteer reads.

Written as: `Out of leaf this month, so there is no canopy to rate. Everything else on this card
still counts.` It says only what PRODUCT §3 says, asserts nothing about this tree's health, and
keeps the section so the card does not silently lose one between November and March. Flagged for
design review.

The section's micro-label drops its instruction clause in this state, from
`Vitality · tap the closest match` to `Vitality` — a subtraction from the verbatim label, because
there is nothing to tap and the full label would contradict the sentence directly beneath it.

The section is suppressed, never the screen. `Vitality.isRatingPermitted` is also re-checked in
`CheckInOutboxWriter` at enqueue time, so a rating collected while the species read was still in
flight cannot reach the record if the species that lands forbids it.

Note that a species with `leafRetention == nil` is rated year-round (ERRATA E9), and so is a tree
whose profile read failed — both reach `isRatingPermitted` as "no habit stated", which permits.

### E29 — C5's `status` convenience is typed on the wrong status vocabulary

`SegmentedControl.status(selection:)` in `DesignSystem/Components/SegmentedControl.swift` is
documented as "05 / D3 `Status`" and is typed on `TreeStatus`.

A check-in reports an `ObservationStatus`. The two are separate types on purpose:
`Core/Models/TreeObservation.swift` says so at the top — "An observation never mutates
`trees.status`: the last two cases open a review flag that a moderator or org coordinator confirms
(DECISIONS §3.7)" — and DECISIONS constraint 7 makes it binding. A screen that used the convenience
would have a `TreeStatus` in hand at the moment it built the observation, which is one careless
assignment away from a citizen observation editing the city's record.

Screen 05 builds the control from the generic `SegmentedControl` over `ObservationStatus` instead.
The convenience is left in place because it may be right for a moderator surface; it should not
claim screen 05 in its documentation, and its `.vacantSite` case has no segment on any mocked
screen.

### E30 — The five vitality anchor photographs do not exist, and they are an entry gate

BUILD-PLAN §8: "The five vitality anchor photos per class ship as app assets and are an entry gate
for M2: the check-in screen does not ship without them (screen 5 shows them inline)." DECISIONS
constraint 19 repeats it. PRODUCT §3 says each class shows a "reference photo per class shown inline
at rating time".

There are no such assets in the repository. What 05 draws, and what is built, is SCREENS.md §1.2's
`linear-gradient(140deg, …)` placeholder — the design export's own stand-in, transcribed exactly.

The gate is not satisfied. It is worth stating plainly what is missing: colour is explicitly
secondary coding (D3), so a gradient swatch carries none of the calibration the reference photo is
there to provide. What ships today is the label and the anchor sentence, always visible, which is
the part D3 could specify without photography.

### E31 — D3 drops three fields; the build keeps them

D3's delta list ends: "**Dropped vs. 05:** the `Foliage` segmented control, the optional
photos/notes well, and the fifth structure chip `Stake / tie issue`."

Those are not implemented as drops. A check-in that offers four structure flags at night and five in
the morning, and cannot record foliage density after dark, would make the record depend on the
device's appearance setting — and every one of the three is a field that reaches `observations`.

Read as drawing economy, which is what the neighbouring dark screens do with theirs: D1 omits
`48TH AVE` and the removed pin, D2 "drops" the regulars row and the season strip's month row. None
of those is a behaviour either. D3 is described as "Same structure as 05 with these deltas", and a
missing field is not a delta of appearance.

Everything else in D3's list — the mint selection, the weight-800 chips and CTA, the desaturated
swatch column, the shadowless selected row, `#D6E0CE` titles against `#E4EBE2` on the selected one —
is implemented, and resolves off the system colour scheme rather than being pinned dark.

### E32 — `awaitingWifiCount` counted items that were not waiting on wi-fi

`OutboxSnapshot.awaitingWifiCount` was `records.filter { $0.item.state != .done && !$0.item.photos.isEmpty }.count`,
under a doc comment reading "Items whose JSON went and whose photos are queued behind the wi-fi
toggle." The predicate checked neither clause.

It counted a visit enqueued two hundred milliseconds ago and never drained, whose note has not gone
anywhere. It counted an item that came back `validation_failed` and happens to carry a photo, which
is terminal and is asking for a tap, not for a connection. Screen 17's footnote — "an item that
cannot sync says so, says why, and waits for you" — is the contract that count feeds, and both cases
made it say the note was saved when it was not. That is the inverse of the screen's job.

The predicate now requires all four clauses of the sentence `awaitingWifi(photoCount:)` writes: the
JSON has been accepted (`jsonSynced`), binaries are still on the device, the row is still alive
(`pending` or `uploading`, so a terminal failure is counted by `failedCount` and nothing else), and
the toggle is on.

The toggle is the part worth stating. Nothing is "queued behind the wi-fi toggle" while the toggle is
off — with it off the binaries go on whatever connection there is, exactly as notes and numbers
always do (BUILD-PLAN §4). So `OutboxSnapshot.init` and `OutboxQueue.snapshot` now take
`syncPhotosOnWifiOnly`, with no default value: neither type owns the preference, `OutboxViewState`
and the store behind it do, and a default would let a caller that cannot know the answer give one
anyway. `OutboxViewState` also refreshes the snapshot when the toggle changes, because the count is
now a statement about the toggle as much as about the rows.

### E33 — a sorted month array cannot carry a phenological start or end

`SeasonalCalendar.init` sorts `bloom_months`, `fall_color_months`, `fruit_months` and
`new_growth_months`. `Species.leafOnMonths` read `newGrowthMonths.first` and `fallColorMonths.last`
as the opening and close of the leaf-on window. After the sort those are the numeric minimum and
maximum, so a deciduous species authored with a November-through-January fall — `[11, 12, 1]`,
stored as `[1, 11, 12]` — closed its leaf-on window in December. January became leaf-off,
`Vitality.isRatingPermitted` suppressed the vitality rows for a month the authored calendar says the
tree is still in leaf, and D3's anchored rows are not something a rater standing in front of the
tree can put back.

Sorting is not the mistake. BUILD-PLAN §4 stores each season as a bare month array, which is a *set*:
two spellings of the same season should be one value and `Hashable` should agree, and sorting is how
that is achieved. The mistake was reading an ordered meaning out of a collection whose order carries
none — and the alternative, preserving authoring order and calling it the season, only moves the trap
to the YAML, where `[1, 11, 12]` and `[11, 12, 1]` would silently mean different years and nothing
would tell an author which spelling was load-bearing.

So the window is recovered from the membership instead. `MonthRange.spanning(_:)` returns the one
wrapping run a set of months describes, by finding the month whose predecessor around the circle is
absent; every spelling of November-through-January yields `MonthRange(start: 11, end: 1)`, and
`MonthRange` already handles the wrap correctly from there. A set with a gap in it — two separate
bloom flushes — describes no single window and returns `nil` rather than a window invented across the
gap, which sends `leafOnMonths` to the documented April–October fallback.

This is latent, not live: every `seasonal` in the shipped seed is empty, so every deciduous species
takes the fallback today. It lands the moment the curated species pipeline authors a calendar that
wraps, which is most fall calendars in the northern hemisphere.

### E34 — a missed account ask could never fire again

`VisitSaveLedger.recordSave()` was `saveCount += 1; return saveCount == accountAskThreshold &&
!isAskResolved`. The equality is a faithful transcription of the prototype's `saves + 1 == 3`
(PROTOTYPE-FLOW §1.6.3), and the prototype was never backgrounded.

On a phone, the save that earns the ask and the answer to it are separated by a sheet presentation.
If the app is suspended and killed with the sheet up, or the sheet is swiped away without its
dismissal handler running, `isAskResolved` stays false while `saveCount` moves to four — past the
only value the guard could ever match. D9's account ask is then gone for the life of the install, and
D9 is the decision that gets anyone an account at all.

A plain `>=` is the other failure, and it is the one DECISIONS is more explicit about: it re-offers
the ask on every save until answered, and D9 exists precisely to keep the auth sheet off "second 8 of
a ten-second street-corner visit". An ask that returns every time somebody saves a tree hands that
friction back in instalments.

The ledger now counts presentations separately from resolution and bounds them at two: the ask is
owed from the third save (D9's threshold is the earliest save it may appear on, not the only one),
and an unanswered ask gets exactly one second chance on the next save. Silence is never written back
as a decline — `isAskResolved` still means the user answered, so `storageLine` keeps saying an
account can be added later.

Dismissal is made resolvable rather than left to the sheet's author to remember:
`VisitSavedModel.accountAskPresentation` is the `Binding<Bool>` screen 15 presents from, and SwiftUI
writes `false` through it for an interactive dismissal as well as a programmatic one, so a swipe-away
reaches `resolveAccountAsk()`. The bound and the binding are two halves of the same fix; neither is
meant to carry it alone.

### E35 — the 10 m proximity dedupe fired out to 14.1 m

`BoundingBox(around:radiusM:)` builds a square whose half-width is `radiusM` on **both** axes, so it
circumscribes the circle rather than inscribing it: a point on the diagonal is admitted out to
`radiusM·√2`. For the 10 m any-species dedupe DECISIONS §3.16 requires, that is 14.14 m.

`TreeQueries.nearest` never re-checked the true distance, and `LocalAPI.addTree` reads a non-empty
candidate list as the conflict. So standing 12 m from an inventoried tree — SF street trees sit
6–10 m apart (D6), so this is the common case rather than the edge — adding a genuinely new tree
returned `conflict`. `conflict` is not retryable (BUILD-PLAN §6), so the outbox item went terminal
on the first attempt and the contributor was refused permanently, with a real nearby tree named as
the reason, which made the refusal look correct.

`CommunityTreeStore.near` had the exact re-check from the start; the seed half never got it. It is
there now, on both index strategies, with the `LIMIT` left where it was: the SQL orders by distance,
so a row the circle rejects is farther than every row it keeps. This is the same shape as the R*Tree
rule in E3 — a conservative index filter, then the true predicate — and it is now what makes the box
a pre-filter rather than the answer.

Found in the same place: `CommunityTreeStore.near` passed the caller's limit down into `inBounds`,
which has no `ORDER BY`. A `LIMIT` there drops rows in storage order, so the row discarded can be
the 2 m duplicate the query exists to find. The box is now read whole and the limit applied to exact
metres afterwards; within any dedupe radius that table holds tens of rows.

### E36 — community-added trees were silently dropped from the map

`LocalAPI.mapContent`, `.pins` branch. Seed pins come back already capped at `viewport.pinLimit`;
community trees were appended after them and the result cut with `prefix(pinLimit)`. Whenever the
seed query reached its cap, every community tree was cut — no error, no log, nothing in the payload
to notice.

It reaches its cap in normal use. `MapModel` reads the viewport as five horizontal bands of 260 pins
each, and a zoom-16 band over SF measures around 264. So a contributor added a tree and their own
pin never appeared on screen 01, on the screen they added it from. DECISIONS §3.16 requires community
trees on a visually distinct layer; the layer was absent. The cluster branch merged correctly all
along, which is what made the pin branch look deliberate.

The community layer now takes its own share of the budget — `seedBudget = pinLimit − communityCount`
— rather than the tail of the seed's. The response stays the same size, and what it spends is one
seed pin per community tree. That is the right trade at any density: the 260th seed pin in a
viewport of 264 is worth less than the tree somebody stood in front of and added.

### E37 — no photograph was visible anywhere in the app

`Photo.isPubliclyVisible` required `moderation_state == 'approved'`, and `visiblePhotos` on screens
03/14 was gated on it. Nothing in the shipping app can set `.approved`: there is no moderation
service, `beginPhotoUpload` and `addTree` both construct photos as `.pending`, and the schema's
default is `'pending'`. So `visiblePhotos` was always empty — no hero, no season strip, no best
photo, on every tree, forever.

The failure was invisible because it was total. The visit still landed, so `isCold` was false and
the cold-start copy did not render either; what showed was a profile with no photograph and no
explanation, which reads exactly like a designed empty state.

**The decision, recorded because it is a product call and not a bug fix.** Moderation is a gate on
*publication*. DECISIONS §3 puts it on public timelines, published locations and the open export;
nothing in it says a contributor may not see the photograph they just took on the device they took
it with. So local display now includes this device's own photos, and the public predicate keeps
meaning exactly what it says.

What was **not** done: marking the photos `.approved`. Leaving them `.pending` is the honest state,
because nothing has in fact moderated them, and a fake approval would survive into whatever
publishes.

The two questions are now two names, in `Photo`: `isPubliclyVisible` / `isPublicBestPhotoCandidate`
for "the world can see this", `isVisibleToItsContributor` / `isBestPhotoShot` for "I can see this".
Which photos are the viewer's own is not a judgement a view can make and not one to infer from a
`.pending` state, so it travels on the payload as `TreeProfile.ownPhotoIDs`. `LocalAPI` fills it
with everything it read, because `main.photos` holds what this device wrote and nothing else;
`RemoteAPI` will fill it from the server's attribution, and everything it does not list stays gated
on `.approved`.

### E38 — a page of 30 was presented as the tree's whole photo series

`ContributionStore.photos` defaulted to `LIMIT 30 ORDER BY captured_at DESC`, and
`LocalAPI.treeProfile` called it with no limit — so `TreeProfile.photos` was page one, typed as a
bare array that could not say so.

`TreeProfilePresentation.heroMetaPill` then reported that page's size as the tree's photo count and
that page's earliest `capturedAt` as its "since" year. A tree with 214 photographs going back to
2019 rendered `30 photos · since 2024`. Both numbers wrong, both plausible, neither checkable from
the screen. A5's season strip was computed over the same 30, so a well-photographed tree stopped
filling its strip and could lose months it had shown the year before — and a thin cell is a claim
that no photograph exists for that month.

Same shape, lower harm: `visits(limit: 50)` and `careEvents(limit: 50)` feed A8's caretakers
threshold ("2 or more care events in 24 months, shown at 3 or more"), counted over at most the 50
most recent.

Fixed by making the type carry the fact. `Series<Element>` has `items` and `isComplete`, and no
`count` — the size of the series is `totalCount`, which is `nil` unless the read proved it had all of
it, which `ContributionStore` proves by asking for one row more than the caller wanted. Filtering
and sorting preserve completeness, so a visibility filter does not launder a page into a total. The
profile reads each series whole; everything that counts renders nothing when handed a page, which is
a state each of those surfaces already has.

### E39 — the export took page one and dropped the cursor

`LocalAPI.exportLatest` called `journal(cursor: nil, limit: 100)` and used `page.items`, discarding
`nextCursor`. Its own doc comment names the account-data request as a use case, so that is an
incomplete subject-access export presented as complete: capped at 100 rows, with no truncation
marker in the CSV or the GeoJSON and no way for the person holding it to tell.

It now follows the cursor to the end. Termination is a property of the query rather than an
assumption: `journal` returns a cursor only when the page came back full, and each page asks for
rows strictly older than the last one seen.

**Residual, not fixed here.** That strict `<` means contributions sharing a `captured_at` across a
page boundary are skipped. Timestamps carry fractional seconds, so it takes a batch write to
produce, but the honest fix is a keyset cursor on `(captured_at, id)` and that changes the cursor
format on a documented endpoint (BUILD-PLAN §6). Recorded rather than done.

### E40 — nothing strips EXIF, on the path DECISIONS §3.10 requires it on

DECISIONS §3.10: "Strip all EXIF server-side on ingest; store capture timestamp and the app's own
fuzzed coordinates in columns." §3.9: "Never collect birthdates, passwords, or exact photo GPS."

There is no server. The ingest path is `LocalAPI.uploadPhoto`, and it was a `FileManager.moveItem`:
the file that landed in the app's photo directory was the camera's file, byte for byte.
`AVCapturePhoto.fileDataRepresentation()` carries the full metadata sidecar — camera make and model,
lens, capture timestamp — and the photo-library fallback (`PhotosPicker`, `loadTransferable`) hands
over the original file from the library, which is the one that can carry a GPS fix from whatever app
took it. `Photo`'s own doc comment asserted the strip happens ("EXIF, including GPS, is stripped
server-side on ingest"), which is how it went unnoticed.

`PhotoBinary.writeStrippingMetadata` now rewrites the container with GPS, Exif, Exif-Aux, IPTC, TIFF,
Maker Notes and XMP dropped, through `CGImageDestinationCopyImageSource` — the compressed pixels are
copied, not re-encoded, so there is no generation loss.

Two passes, for one reason worth stating: ImageIO refuses an exclusion and an orientation in the same
call, and orientation is not personal data — it is which way up the picture goes. An iPhone portrait
photograph is landscape pixels plus an orientation tag, so a single-pass strip turns every portrait
shot on its side in the hero and behind the ghost overlay. So: strip everything, then put that one
value back. What survives is what ImageIO synthesises for any JPEG it writes — pixel dimensions,
colour space, an Exif version number — and `PhotoBinary.carriesIdentifyingMetadata` is the
postcondition, written against the fields that identify a person or a place rather than against the
presence of a container.

When the rewrite fails — a container ImageIO cannot re-emit — the original is moved across rather
than dropped, because refusing it fails the outbox item terminally and costs the contributor the only
copy of their photograph. Under `LocalAPI` the file never leaves the device and no surface reads it.
`RemoteAPI` must not inherit that reasoning: nothing may be **published** out of that fallback.

### E41 — a photo's pixel size was never recorded, so A3's tie-break never ran

`APIOutboxTransport.uploadPhoto` built its `PhotoUploadRequest` without `width` or `height`, and
`LocalAPI.beginPhotoUpload` ignored both fields even when they were set. Every `photos.width` and
`photos.height` was NULL, so `Photo.resolution` was 0 on every row and A3's "ties broken by
resolution" could not distinguish anything — on the one case the tie-break exists for, several
photographs sharing a capture date.

The transport now reads the size off the staged file before handing it over (`PhotoBinary.pixelSize`,
a header read rather than a decode), and `beginPhotoUpload` stores what it is given.

### E42 — `publicCoordinate` is deliberately not populated

The same request carries `publicCoordinate`, and it is left `nil`. This is a decision, not an
oversight, and it is recorded here so it is not "fixed" later by someone reading E41.

Storing it would mean writing where the contributor was standing when they took the photograph.
DECISIONS §3.10 requires a 25 m snap for **public photo locations**, and §3.11 plus D11 are explicit
about the threat: a public record of where a named person stands is what reconstructs their life.
The tree's own pin is already exact and already public — trees are public objects — so a photo
coordinate adds nothing a public surface needs, and adds a second, independent record of a person.

The safest place to keep a location is nowhere. `Photo.publicCoordinate` and its 25 m snap stay in
the model and are exercised, so the day a surface genuinely needs a photo location it snaps before it
is stored (`Photo.init` does it unconditionally); until then nothing writes one. Screen 10 (share) is
where this will be re-opened, and it should be re-opened as a product decision rather than as
plumbing.

### E43 — screen 07 draws four things the record cannot carry, and no state for the 529 species that carry almost nothing

`SCREENS.md` 07 is transcribed from a single drawn page for a single species. Building against it
turned up four values with no field behind them and three states with no drawing.

**Values.**

- **`Evergreen conifer`** (07 §2). The habit half comes from `species.leaf_retention`; `conifer` is a
  growth form, and BUILD-PLAN §4's `species` table has no column for one. The chip is built as
  `Evergreen` alone.
- **`Coastal`** (07 §2). A habitat. Same: no column, no curated field, and `Fixtures/species/curated.yaml`
  authors none. No chip is drawn. Inferring it from the family would be inventing botany
  (DECISIONS constraint 15).
- **`Hesperocyparis macrocarpa`** (07 §1). The seed carries `Cupressus macrocarpa` for the Monterey
  Cypress, which is what GBIF resolved and what `sf_species_map.csv` maps the DataSF string to. Both
  names are current in the literature; the page shows the record's, because the alternative is the
  screen and the database disagreeing about what the tree is called.
- **`In July: look for closed gray cones …`** (07 §4). This is per-species, per-month authored copy,
  and the only field that could hold it is `care_notes[].month_range`. **20 of the 21 seeded care
  notes have `{start: 1, end: 12}`**, which `curated.yaml`'s own header defines as "the source
  attaches no month restriction" — printing one of those under `In July:` would turn a year-round
  note into a claim about July. Exactly one seeded note is genuinely month-restricted (Jacaranda,
  March–May). So the callout draws for one species in three months of the year and is otherwise
  absent. The flagship the mock draws it *on* — Monterey Cypress — has `care_notes: []` and an
  entirely empty seasonal calendar, so the sentence in the mock has no source anywhere in the repo.

**States.** SCREENS.md draws none of these and none was invented (DECISIONS constraint 21):

- **The long tail.** 529 of 569 species carry no `id_tips`, no care notes and no seasonal calendar.
  Their page is the hero, the chips that have facts behind them, and the population cards. That is
  BUILD-PLAN §8's own rule for the long tail — "name, family, and a generic silhouette" — rendered
  rather than apologised for. There is no "we don't have this yet" copy, because a page that says so
  is a page about the app rather than about the tree.
- **The failed read.** `SpeciesCopy.loadFailed` / `loadRetry` say what happened and nothing about the
  species, since nothing about the species was read.
- **`Nearby individuals`' query.** 07 §6 is drawn as a finished list with no radius and no row count.
  `SpeciesGuideLimits` takes the narrowest reading of the drawing — two rows, 500 m, which clears the
  `400 m` row it draws. Both are guesses at a query, not a design.

Finally, 07 §6 declares `margin-top:auto`, pinning the list to the bottom of an 874 px frame. The
built screen lets it follow the content instead: the section's height depends on how many
individuals are actually nearby, and a spacer sized to the difference would open a gap that grows
with the device. SCREENS.md's own closing note already flags several screens as exceeding one
viewport in a real build.

### E44 — A4 fixes the *unit* of "your area" and not the mechanism, and the mechanism it does name does not exist

A4 (BUILD-PLAN §11) resolves "your area" as "SF Analysis Neighborhoods polygons, resident
neighborhood inferred from most-visited, overridable in settings". Screen 07 §5's `Near you` card is
the first surface that needs it.

Neither half of the mechanism is buildable today: there is no visit history to infer a resident
neighbourhood from on a fresh install — which is every install — and there is no settings screen to
override it in. The *unit* is available: the seed carries all 41 neighbourhoods and the city's own
assignment of every one of the 195,309 trees to one, in `trees.neighborhood_id`.

**`Near you` therefore counts the species inside the neighbourhood the caller is standing in, and
that neighbourhood is resolved through the nearest inventoried tree rather than through a
point-in-polygon test.** `neighborhoods.geom_geojson` is present, so the polygon test is available
in principle; what it would add is a *second* answer to a question the ingest already answered
195,309 times, and a ray-cast that disagreed with `neighborhood_id` on a boundary block would put
the count card and the map in different neighbourhoods for no gain. In SF the nearest inventoried
tree is metres away.

This is a derivation, not the resolution A4 states, and it is recorded rather than assumed. When a
visit history and a settings screen exist, `SpeciesQueries.resolveNeighborhood(near:)` is the one
place that changes.

Two consequences worth naming. Without a location fix there is no area, so the card does not draw at
all — "we could not tell" and "none near you" are different facts and only one of them is true.
And outside SF, or in the middle of the bay, no tree is within the search radius and the same
absence applies.

### E45 — screen 07 has no dark row, and two of its tokens are light-only by design rather than by oversight

E8 records that dark is documented for D1–D3 and screen 04 only. Screen 07 is one of the surfaces
that inherits nothing, and running it in dark turned up two specific things a designer has to rule
on rather than a general "it looks fine":

- **The hero has no dark counterpart.** `CypressGradient` carries `heroProfile` *and*
  `heroProfileDark` — D2 specifies a different radial stack and a deeper scrim for the tree profile
  in dark — but `heroSpecies` is alone. So 07's top 190 pt stays the light gradient against a
  `#0E1712` page. It is defensible, because the hero is a placeholder for a photograph and a
  photograph has no dark mode; it is also the single brightest thing in the app at night, and D2's
  existence shows the designer did not think that was acceptable for the other hero.
- **The recognize-it glyph tints are light-only and one of them nearly vanishes.** SCREENS.md 07 §3
  names `#2F6B4F`, `#4E8F6A` and `#7A4F33` for the three 10 pt leaf glyphs. All three are brand
  palette entries and all three are `lightOnly` tokens, correctly — they are the brand's colours,
  not surface colours. Against the light card they read clearly. Against `dark.surface.card`
  (`#18251D`) the Canopy glyph is very close to its own background, and it is the *first* bullet, so
  the card reads as though its top row lost its mark.

Neither was invented around. No literal was written and no token was re-tinted; both are recorded
here because inventing a dark value for a documented brand colour is precisely the failure the
`derived` / `escalated` labelling exists to prevent (ROADMAP, "Dark mode for the 59 unspecified
tokens").

### E46 — 08's tab row is not C5, and two of its three pills have nowhere to go

SCREENS.md §2's C5 (`SegmentedControl`) lists its users: "05 Status, 05 Foliage, 16
What-are-you-measuring, 16 Method, D3 Status". Screen 08 is not among them, and its own §2 describes
something else: three `flex:1` pills with `gap:8px` between them, each `padding:9px 2px` at radius
**11px**, each carrying its own border. C5 is one bordered container at radius 12px with
`border-left` dividers and no gap. They are different controls that look alike at a glance, and
building 08's as a C5 variant would have meant widening a shared component to hold something it is
not. It is built in `Features/Grove` from tokens (`CypressRadius.grovePill`, which §1.4 already
carries for exactly this).

The second half is behavioural. The three pills read `Trees`, `Journal`, `Species`, and only
`Species` — screen 08 itself — has been built or mocked. `Trees` corresponds to the grove screen in
the clickable prototype (PROTOTYPE-FLOW §1.7 "Grove fixtures": a `Your trees` list, a neighbourhood
callout and a steward card), which is a *different screen* from SCREENS.md 08 and is not in the
mock set; `Journal` is a BUILD-PLAN §9 M2 build requirement with no mock at all. The prototype's own
answer for this screen is explicit — PROTOTYPE-FLOW §1.5, `grove`: "Progress card, neighborhood
callout, steward card, tabs My Grove / Journal / You — **inert**".

**They are drawn and inert, and they are not buttons.** A pill that looks pressable and does nothing
is worse than a label, so no `Button` is constructed for them and nothing highlights on touch. What
they are *for* is a question for design, not for a view file (DECISIONS constraint 21).

### E47 — screen 08's own numbers do not agree, and the real denominator is 215, not 40

Three separate problems, all in SCREENS.md 08 §3's one sentence `12 of 40 species` /
`you can recognize in the Outer Sunset`.

**The mock does not add up.** The ring says twelve species are known. The grid immediately beneath
it (§5) draws **seven** known tiles and two locked. Both numbers are in the same figure, and nothing
reconciles them. The build derives both from one series, so they cannot disagree; the previews use
seven, because seven is what is drawn.

**San Francisco has no "Outer Sunset".** A4 fixes neighbourhood names to the SF Analysis
Neighborhoods polygons, and the seed carries all 41 of them. The Sunset is **two** of those
polygons, named `Sunset/Parkside` and `Inner Sunset`. "Outer Sunset" is the colloquial name for the
western half of `Sunset/Parkside` and is not a row in the dataset the product committed to. The
caption therefore renders the seed's own name, and the screen reads `you can recognize in the
Sunset/Parkside` — which is correct, and reads worse than the mock. Whether the app should carry a
display-name layer over SF's polygon names is a design question that reaches beyond 08 (07's
`Near you` card and 12's almanac need the same answer). Recorded, not invented around.

**Forty is a fixture; the real number is 215.** Counting distinct `species_current` over the
city-inventory trees the seed places in `Sunset/Parkside`:

```sql
SELECT COUNT(DISTINCT t.species_current) FROM trees t
  JOIN neighborhoods n ON n.id = t.neighborhood_id
 WHERE n.name = 'Sunset/Parkside' AND t.deleted_at IS NULL AND t.species_current IS NOT NULL;
-- 215
```

Fifty-six of those 215 are represented by a single tree in the whole neighbourhood, and the
distribution has a very long tail (1,561 New Zealand Xmas Trees at the head). The consequence on
screen is that a contributor who has met seven species sees **`7 of 215 species`** and a ring at
**3%** — a correct fraction that will read as near-empty for a very long time, where the mock's
`12 of 40` reads as a third of the way home.

The build renders the true number. Making the denominator smaller would mean choosing which species
"count", and every available rule for that (curated species only, species above some abundance
floor) is a botanical claim the record does not carry. **But the ring's readability at 3% is a real
design problem, not a rendering bug**, and it is the one thing on this screen that a designer should
look at before it ships.

### E48 — the empty grove is a BUILD-PLAN §9 requirement, and no copy exists for it

BUILD-PLAN §9 lists, under M2, "sign-in decline path; **empty grove, journal, collections**; …". So
the state is a sanctioned build requirement rather than something invented (ARCHITECTURE §5.8 admits
exactly two sources, SCREENS.md and BUILD-PLAN §9). What §9 does not give — and what no mock gives —
is a single word of copy for it.

This matters more here than it would elsewhere, because the empty grove is not an edge case. There
is no account (D9), contributions are device-scoped, and every screen on this list is empty on a
fresh install. **The empty grove is the state every new device is in.**

What was built is the restrained reading: the ring, the celebration callout and the tile grid are
each derived from contributions, so a device that has made none renders none of them
(ARCHITECTURE §5.6). What remains is the screen's specified chrome — the title, the three pills, and
§6's footnote, which `margin-top:auto` puts at the bottom of an otherwise empty column:

> Quiet collecting. There are no streaks and no leaderboards.

No sentence was written for the empty state. The alternative — one line of new copy explaining what
will appear here — is small, defensible, and still invented, and the sentence a product says to
somebody on their first launch is exactly the kind of thing that should come from the people who
wrote the other sentences. A screenshot of the state as built is attached to the build record.

**Flagged for design.** The honest minimum is what shipped; it is not a design.

### E49 — three rules screen 08 needs and SCREENS.md does not state

Recorded together because each is a small decision taken inside `GrovePresentation`, and each would
otherwise be invisible.

**Tile order.** §5 lists nine cells in a fixed order and states no rule. The mock is not
recency-ordered — its own "New species!" (Victorian Box) sits fourth — and it is not alphabetical.
The build draws them **oldest first**, so the grid reads in the order the collection was built and a
new find appends rather than reshuffling everything above it.

**How many locked tiles.** §5 draws two, at positions 7 and 9, interleaved among the known ones
under no stated pattern, and gives no rule for how many there are. Under the real denominator the
question becomes sharp: 208 remaining species cannot be 208 tiles. The build **pads the last row to
a multiple of three** — a layout rule, not a claim — and caps the padding at the number of species
actually left to meet, so a contributor one species short of the whole neighbourhood sees one locked
tile rather than two. A grid read from an incomplete page is never padded at all, because the last
row of a page is not the last row of the series.

**How new a "new species" is.** The caption promises "a new find gets a small celebration" and §4
draws one instance, reading `spotted yesterday`. No window is stated and no other relative phrasing
for this callout exists anywhere in the sources. Rather than invent a ramp ("3 days ago", "last
week") and a window to go with it, **the callout renders for exactly the two days the drawn copy can
describe** — today and yesterday — and says one of those two words. Nothing is generated for a day
the mock has no word for.

One smaller thing, in the same callout: §4 writes `on Noriega`, dropping both the house number and
the street type from an address the seed stores as `1450 Noriega St`. The build drops **only** the
leading house number, because stripping a street *type* means deciding which trailing words are
types, and getting that wrong renames a street. So it reads `on Noriega St`.

### E50 — 08 in dark, and one place the brand hues were being read directly

E8 records that dark is documented for D1–D3 and screen 04 only; 08 inherits nothing, and E45 makes
the same observation for 07. Running 08 in dark turned up one defect and one judgement call.

**The defect: C27 was reaching past the role tokens to the raw brand hues.** `ProgressRing` filled
its arc with `CypressColor.canopy` and drew its label in `CypressColor.cypressDeep`. Both are
`lightOnly`, correctly — they are two of the six brand colours, and `CypressColor`'s own header says
so, adding that "the scheme-dependent roles are carried by the paired role tokens further down
(`ctaFill`, `pinFill`, `selectionFill`, `accentAmber`), which is where a caller belongs". Reading the
hue directly meant that in dark the ring drew `#2F6B4F` against `#0E1712` and its `#1D4634` label was
very nearly invisible inside a `#0E1712` disc — the one number on the screen, unreadable.

Fixed by using the paired role tokens the design system already carries: `selectionFill`
(`#2F6B4F` ↔ `#8EC3A5`, §1.2's dark row says mint is "primary CTA fill, **selection**, active tab")
for the arc and `ctaFill` for the label. **No value was invented and the light rendering is
unchanged to the byte** — both pairs are documented, and both light halves are the hexes C27 already
drew. Verified by screenshot in both schemes.

**The judgement call, left alone: the celebration callout stays light.** C14's gradient fill,
its border and its ink are all `escalated` — the transform was run against them and rejected, and
§1.2 documents no dark counterpart for `linear-gradient(120deg,#EAF2E6,#F6F2DF)` anywhere. On 08
that is a full-width cream block on a near-black screen, and it is the brightest thing on the page
at night. It is the intended behaviour of an escalated token and it is not re-tinted here. It is
also, in practice, a glare, and 07's "In July" callout has the same problem. One designer decision
covers both.

### E51 — C29 wrote the *artwork's* species name onto the tile, not the species'

Found by running 08 against the real seed rather than against the mock's seven species.

`SpeciesTile.Content.known` took a `CypressGradient.SpeciesTileArt`, and the tile's label was
`art.label` — the name of the species the *gradient* was authored for. On the mock that is invisible,
because §2 authors artwork for exactly the seven species §5 draws and the label and the gradient are
the same species. The seed carries 569. Artwork is chosen by genus, with a stable hash for the rest
(`SpeciesTileArtwork`, the same approach `MapModel` already uses for C22's four thumbnails), so on
any real grove the two come apart immediately:

| The tree the contributor visited | Tile said | Should say |
|---|---|---|
| `Ginkgo biloba` | `Ginkgo` | `Maidenhair Tree` |
| `Platanus x hispanica` | `London Plane` | `Sycamore: London Plane` |
| `Metrosideros excelsa` | `Pōhutukawa` | `New Zealand Xmas Tree` |

Those three are same-genus renamings and merely wrong. The failure mode that matters is the hashed
fall-through: a species with no authored art gets whichever of the seven gradients the hash lands
on, and it was being **labelled with that gradient's species name**. A Silver Maple drawn with the
Pōhutukawa gradient read `Pōhutukawa`. That is fabricated botany on screen, which BUILD-PLAN §15
forbids, arriving through a component's default rather than through anything a feature wrote.

`SpeciesTile` now takes an optional `label` that overrides the artwork's, and 08 always passes the
species' own common name (falling back to the scientific name for the 11 seeded species that have
none, exactly as `SpeciesQueries` does). The gradient remains a placeholder that claims nothing; the
name is now the record's.

### E52 — the seed had no planting *date*, and screen 12 asks about a season

`trees.planted_year` is BUILD-PLAN §4's column and it is an integer year. SCREENS.md 12 §2's third
row reads `23 trees planted this spring`, which a year cannot answer: "this spring" is a three-month
window and `2026` is not.

Three ways out, and why the third was taken:

- **Substitute a different window** — render "planted in 2026" under the mock's label. That is
  answering a question nobody asked and calling it the mock's row.
- **Drop the row** and record the record as unable to carry it. Defensible, and it leaves a drawn
  row unbuilt for a reason that is fixable in an afternoon.
- **Carry the date.** DataSF's `PlantDate` is a full date (`03/08/2024 12:00:00 AM`) and the ingest
  already parsed it to take the year off it. `trees.planted_on TEXT` (ISO `YYYY-MM-DD`) now holds
  what the city actually recorded, `planted_year` stays exactly as §4 has it, and two CHECK
  constraints pin them together: both set or both NULL, and the year is the date's year. Filled on
  the same 70,067 of 195,309 rows the year was.

**What it changes on screen: almost nothing, and that is the finding.** DataSF's `PlantDate` is
sparse and lags. Spring 2026 (1 March – 31 May) holds **15 plantings in the whole city** — five in
Lone Mountain/USF, three in Bernal Heights, two each in Inner Sunset and the Marina, one each in
three more, and **none at all in the other 34 neighbourhoods**. So the row the mock draws with `23
trees` renders in seven neighbourhoods out of 41 and is absent everywhere else, permanently, until a
future data refresh says otherwise. That is the honest answer and the column is what makes it
provably the honest answer rather than a substitution nobody would have noticed.

Two smaller decisions inside the row, neither specified:

- **"This spring" is March, April and May** — the meteorological quarters, the convention phenology
  uses and the one that needs no equinox table. The astronomical reading moves the edge about three
  weeks and changes nothing else. `AlmanacWindow.springMonths`.
- **The row cannot draw in January or February**, because the current year has no spring yet and the
  drawn copy has a word for exactly one season. Nothing was generated for the other three
  (DECISIONS constraint 21).

Also fixed in the same pass, and unrelated to 12: `parse_planted_year`'s sentinel guard read
`datetime.now().year + 1`. It is `SEED_EPOCH`'s year now. Nothing about today's output moves — the
two agree in 2026 — but it was a wall-clock read inside a build the repo declares byte-for-byte
reproducible, which is exactly the shape of the defect E13 records.

Reproducibility re-verified after the change: two consecutive `python3 Tools/build_seed.py` runs
over the identical inputs both produced
`4cd9ccd61cb52c9ebde15d26affdb5a5ca3152115af341547fa7f2e53652d141` (95.3 MB, 195,309 trees).
`Tools/verify_seed.py` passes 32/32, including a new check 14b that the two planting columns agree.

### E53 — A4 for screen 12, and what a neighbourhood almanac does without a location

E44 records that A4 fixes the *unit* of "your area" and that neither half of its stated mechanism —
most-visited inference, settings override — exists. Screen 07 resolved it through the nearest
inventoried tree; screen 08 used contribution history, because A4's own mechanism is available to a
screen that is made of contribution history.

**Screen 12 uses the nearest inventoried tree, exactly as 07 does and through the same function.**
Three reasons, in order of weight:

1. **Four of its five blocks are city data that is complete on day one.** The elder, the species
   mix, the coverage list and the newest neighbours all exist on a device that has contributed
   nothing. Deriving the area from contribution history would blank the whole screen on every fresh
   install to protect a mechanism that has no data behind it either.
2. **The screen's own copy is about where you are standing.** §4's body says the trees are "within a
   15-minute walk", and §2's rows are the season *here*. That is a claim about a location, not about
   a habit.
3. **One seam.** `SpeciesQueries.resolveNeighborhood(near:)` is the single place A4 will land when
   its mechanism exists, and 07 and 12 now both go through it.

**The consequence is a state SCREENS.md does not draw: no fix, no area, no almanac.** Not an empty
neighbourhood — no neighbourhood. The header keeps its title and loses its pill, the footnote sits
at the bottom of an empty column, and nothing else renders. "We could not tell where you are" and
"nothing is happening in your neighbourhood" are different facts and only one of them is ever true;
drawing the second over the first is the same class of error as printing a page's size as a total.

Recorded rather than invented around, and flagged for design alongside E48's empty grove — these are
now two screens whose day-one state is the specified chrome and a footnote, and neither has a
sentence written for it by the people who wrote the other sentences.

### E54 — A9 says the coverage panel always renders; §5.6 says a zero never does

A9's sentence is "aggregate surfaces below threshold do not render: leaderless almanac cards need
their data (bloom sightings need 1, **species mix always renders from city data, coverage panel
always renders**)". ARCHITECTURE §5.6 is "aggregate surfaces below their cold-start threshold do not
render at all".

At zero they disagree, and screen 12 is where it shows. `0 young trees with no visits since
planting`, under a micro-label reading `Where eyes are needed`, with a `Walk the zero` button under
it, is a card whose entire function — sending somebody somewhere — has nowhere to send them.

**§5.6 wins, and A9 is read as being about the panel's *source* rather than its floor.** A9's three
clauses are each about where a card's data comes from: the bloom needs a contribution, the mix comes
from city data and therefore never waits for one, and the coverage panel likewise reads the city's
plantings rather than anybody's activity. None of them is a statement that a card should draw a
zero, and §5.6 says plainly that it should not.

So the coverage card is absent in two cases, and the second is the same rule:

- **there are none**, per the above;
- **the read came back a page** (ERRATA E38). The card is a count and nothing else; a page's size
  printed as a total would read `200 young trees` when the true figure is unknown. The read asks for
  one row more than its cap (`AlmanacLimits.coverageRowLimit`, 200 — the busiest neighbourhood in
  the seed holds 21) so that `isComplete` is a fact rather than a hope.

The same reading resolves the species mix: it renders from city data whenever there is city data,
and a neighbourhood whose inventory holds no species-bearing tree draws no card rather than a card
of zeroes. Treasure Island's eight trees are the closest the seed comes to testing it.

### E55 — three claims screen 12 makes that the record has to be checked against

Recorded together because each is a decision inside `AlmanacPresentation` that would otherwise be
invisible, and each is a sentence the mock states as though it were always true.

**"All nine are within a 15-minute walk" is verified, not asserted.** §4's body makes a claim about
distance from the reader. The coverage list is scoped to the neighbourhood — that is the screen's
unit — and a neighbourhood is bigger than a fifteen-minute walk: `Sunset/Parkside` is about 4 km
across. So the sentence renders only when the farthest tree on the list really is inside the radius,
and is simply left off when it is not. **NOT SPECIFIED**: no source states what distance a
"15-minute walk" is, so `AlmanacMetrics.walkRadiusM` is 1,200 m — fifteen minutes at the 4.8 km/h
that transport planning uses — and it is used only to *withhold* a sentence, never to choose trees,
so an imprecise number costs a true sentence rather than producing a false one. On the fresh-install
state it is withheld: the seed's 17 young Sunset/Parkside trees are spread across the neighbourhood.

**"The elder" is the oldest *recorded* planting, and the mock's own words are what make that
sayable.** DataSF fills `PlantDate` on 70,067 of 195,309 rows, so the oldest tree with a date is not
the oldest tree. `in the city record since 1898` says precisely that and is kept word for word; any
paraphrase ("the oldest tree here") would be a claim the record cannot support. In `Sunset/Parkside`
the row reads `Blackwood Acacia · in the city record since 1956` — the seed's oldest planting date
anywhere is 1956, so the mock's 1898 has no counterpart in the data at all.

**"three neighbors saw it" is A8's threshold, applied to a clause rather than to a card.** A9 floors
the bloom *sighting* at one; A8 floors a *headcount of people* at three. They are different claims
about the same event, so below three the row still says a first bloom was recorded and stops saying
how many people were there. At one or two, a headcount on a surface that also names the tree and the
day comes close to naming the person (D11). The number is spelled out by `NumberFormatter`'s
`.spellOut`, because the mock spells its people counts (`three neighbors`, and SCREENS.md 13's "six
people know this tree") and a table of my own number-words would stop somewhere.

One more, smaller: §2's `mostly ginkgo and tea tree` is written in lower case, which is right for
those two words and wrong for the seed, whose common names are title case and contain proper nouns
and initialisms. Lower-casing turns `NZ tea tree` into `nz tea tree`. The names are rendered as the
record holds them (E51's rule, in a sentence rather than on a tile).

### E56 — screen 12 in dark, and the four swatches that want deciding together

E8 records that dark is documented for D1–D3 and screen 04 only; E45 and E50 make the same
observation for 07 and 08. Screen 12 inherits nothing, and running it in dark turned up one thing
worth a designer's attention and one thing that was already right.

**The composition card's four swatches are a series, and after dark the darkest one disappears into
its own card.** SCREENS.md 12 §3 names `#1D4634`, `#4E8F6A`, `#7A4F33` and `#C2CAB4`. Three are
brand hues, which §1.1 says have no single dark answer; the fourth is the neutral that means
"everyone else". They are registered as **escalated as a set**, for the reason `chartSeriesPrimary`
already carries: a series palette is chosen for separation *between* its members, and the accent
transform anchors lightness, so running it per colour is the one operation guaranteed to break what
they are for. Left light, the honest consequence is visible in the dark screenshot: Cypress Deep
(`#1D4634`) against `dark.surface.card` (`#18251D`) is very nearly the same colour, so the most
common species in the neighbourhood has the least visible swatch and the least visible bar. That is
a stated failure rather than a hidden one, and the four want answering as one.

**The track behind the bars derives cleanly.** `#EDEFE3` goes to `dark.border` `#27352B`, which is
where `chartGridline` (`#EAEDDF`) already goes under the border rule; the two light values are three
RGB steps apart, so this is the rule agreeing with itself rather than a second guess. Registered as
derived.

Two tokens and one radius were added for this card, since SCREENS.md §2's catalogue has no C-number
for it and a feature may not write a hex (ARCHITECTURE §6): `CypressColor.compositionSwatches`,
`CypressColor.compositionOther`, `CypressColor.compositionTrack`, `CypressRadius.compositionTrack`,
and `CypressFont.LineSpacing.body125` for §4's 12.5px/1.45 body.

### E57 — nothing opens the almanac, and screen 14's footnote says what it opens

Screen 12 has no entrance. It is not one of C16's four tabs (`Map`, `My Grove`, `Journal`, `You`),
no mocked screen carries an affordance that reaches it, the clickable prototype's `screen` enum does
not contain it, and BUILD-PLAN §9 does not list one. This is the same situation E24 records for
screen 05 and E43 for screen 07 — a screen whose exit is drawn and whose entrance is not — and
inventing the button is what DECISIONS constraint 21 forbids.

The screen is built ready to wire and the wiring is reported rather than applied, because `RootView`
and `AppRouter` are owned by another agent this round. What it needs is one `Route` case with no
associated value and one `destination(for:)` arm; where the push comes *from* is a design question.

**Its one outbound affordance is drawn, and it is not new surface.** Screen 14's footnote reads "A
young tree nobody has visited. This is the almanac's 'walk the nine' list, one tree at a time" — so
`Walk the nine` opens one young tree's profile, and screen 14 is `Route.treeProfile` in its
cold-start form, which is already built and already routed. The almanac carries the coverage trees
nearest-first and the CTA opens the nearest.

The two season rows that are *about* a specific tree — the elder and the first bloom — take an
optional handler and are inert without one, because SCREENS.md 12 states no affordance for either.

### E58 — `CareAction` has five values and screen 09 draws four

BUILD-PLAN §4's `care_events.actions text[]` vocabulary is `watered, mulched, weeded,
litter_cleared, staked`. SCREENS.md 09 §4 draws four chips: `Watered ✓`, `Mulched ✓`,
`Weeded basin`, `Litter cleared`. There is no control anywhere in the mock set for `staked`, and
PRODUCT §3 records a third wording for the same list ("stake removed") that matches neither.

The four drawn chips are what ships. Adding a fifth would be inventing an affordance (DECISIONS
constraint 21); deleting the case from `Core` would narrow a stored column to fit one screen, and
V-M5 already has young-tree hardware (stakes, ties, girdling) queued as a Phase 2 age-adaptive form
where it plausibly belongs. So `CareAction.staked` stays in the vocabulary, uncollectable, and this
records that it is uncollectable on purpose rather than by oversight.

### E59 — screen 10's four destinations, its missing copied state, and the footnote the spec drops

Three separate gaps in one row of icons.

**1. Three of the four destinations have no direct API.** SCREENS.md 10 §4 draws `Messages`,
`Instagram`, `AirDrop` and `Copy link`. On iOS, `Copy link` is the only one that can be performed
exactly as labelled — it writes to `UIPasteboard`. AirDrop and Messages are reached through the
system share sheet and have no addressable API of their own; Instagram publishes none for links at
all. So the three non-pasteboard targets present `ShareLink`'s system sheet, which is the row those
three words name on this platform. **Judgment call**, recorded because the alternative readings are
both defensible: leaving them inert (honest, and three dead buttons) or hand-rolling three flows the
spec does not draw (constraint 21).

**2. There is no "Link copied" confirmation, and that is the spec's own instruction.** SCREENS.md 10
says it outright: the prototype's copied state is "**NOT SPECIFIED** in this spec file — no copied
state is drawn". PROTOTYPE-FLOW §"Share sheet" does carry one — `Copy link` → `Link copied`, fill
`#E2EFE2`, `2px solid #2F6B4F`, `czPop .3s` — but it is styling for a *full-width CTA*, and this
layout has no CTA to turn green. Transplanting it onto a 52pt circle would be designing. So the copy
happens with no visual acknowledgement, which is a real usability gap and is a question for design.

**3. The prototype's privacy footnote is not in this spec.** PROTOTYPE-FLOW's share sheet ends with
`The link opens the public tree page. Your name appears only if you opted in.` SCREENS.md 10
enumerates the sheet as grabber, title, preview card, destination row, and no footnote. SCREENS.md
is the visual truth (ARCHITECTURE §1), so the footnote is not rendered — **and the sentence it makes
is still true by construction**, because nothing on this screen renders an attribution at all
(`SharePresentation`'s header, and `SharePresentationTests.noAttributionSurface`). D11's
`User.isPublicAttributionEffective` therefore has no call site on screen 10. If design wants the
footnote back, it is one string; if design wants a name on the card, that predicate is the only way
to put one there.

### E60 — the mock's share slug cannot name a tree, and there is no page behind the link

SCREENS.md 10 §3 draws the URL as `cypress.app/sf/tree/9f3a`, and W1 draws
`cypress.app/sf/tree/9f3a-monterey-cypress`. Four hex digits are 65,536 values. The shipped seed
holds 195,309 trees, so a four-character slug cannot identify one of them — it is a mock fixture, and
rendering its *shape* would put a wrong identifier on a link somebody sends to a friend.

What is rendered instead is the tree's own `id`: the immutable, citable, public identifier the
product already commits to ("stable citable tree UUIDs", DECISIONS §2.5; "immutable UUIDs", §2.5
P-C3; the export is "keyed on `external_ref` + UUID"). `external_ref` was considered and rejected as
the public key because community-added trees have none.

Two consequences worth stating rather than absorbing:

- **The line takes two rows, not one.** 36 characters of mono 10.5 do not fit the drawn card beside
  a 72pt thumbnail. It wraps rather than truncating: half a link with an ellipsis is worse than a
  link on two lines, and this is the one string on the card somebody might read aloud or type. A
  short public slug (a base32 of the id, say) would restore the single line and is a design decision,
  not an implementation one.
- **Nothing answers the link yet.** W1, the public tree page, is a separate deliverable and is
  explicitly out of scope for the iOS app (ARCHITECTURE §8). So screen 10 copies and shares a URL
  that currently resolves to nothing. That is a shipping-order problem rather than a spec error, and
  it is recorded here because "the link opens the public web page with no login" is the screen's own
  caption and is not true on the day the app ships without the web page.

### E61 — screens 09, 10 and 11 have no dark row

SCREENS.md's Section D draws exactly four dark screens (D1 map, D2 profile, D3 check-in, plus the
always-dark camera on 04). ERRATA E8 already records that the app has more screens than that and
what the derivation does about it; this entry names the three that landed this round and the one
value in them that is newly derived rather than transcribed.

`surfaceShareCard` (`#FAF8EF`) is new. It takes `dark.surface.card` `#18251D` — the rung every
raised plane in the documented pairs lands on, and the same one `surfaceSheet` takes. The
consequence is that **after dark the share preview card is told apart from the sheet by
`borderShareCard` alone**, since both resolve to `#18251D`. That reads correctly in the render and
is still a judgment a designer should look at, because the light version distinguishes them by fill.

Also new and derived: `shareTargetWellFill` (`#EAF0E2` → `dark.surface.thumb` `#1F2E22`, a circular
recess), `shareTargetWellBorder` (`#DDE2D2` → `dark.border.alt`, the border rule, same light hex as
`borderSheetGrabber`), and `ctaDisabledFill` — see E64's neighbour below. All four are in
`CypressColor.derivedTokens`, so they appear on the TokenGallery review sheet and
`DerivedTokenTests` holds them to it.

### E62 — screen 11's measurement log draws a `role` column the payload cannot fill

SCREENS.md 11 §5 gives each log row as `value · method badge · role · date`, with `steward` and
`member` in the drawn rows. Nothing in the profile payload carries a role: `TreeMeasurement` holds a
nullable `userID`, `TreeProfile` holds no user records, and `GET /trees/{id}` as BUILD-PLAN §6
defines it returns none. Every measurement the shipping app can produce is anonymous under a device
id anyway (D9), so even with a join the column would read blank for all of them.

The column is absent rather than guessed. Two smaller notes on the same block:

- **The log lists both kinds**, DBH and height, interleaved by date. SCREENS.md's three drawn rows
  happen to be all DBH and the mock has no kind column; the entered unit (`64 cm` / `18 m`) is what
  tells them apart. If a kind label is wanted, it is design's call.
- **The log is wider than the charts.** A reading D6 excludes from charting still appears here,
  because the record is the record and hiding somebody's own contribution because their GPS was poor
  is worse than showing it with no dot. Nothing on the row says why it has no dot, and SCREENS.md
  draws no marker for it — see E63.

### E63 — screen 11 has no empty state, no "nothing chartable" state, and no entrance to either

SCREENS.md 11 draws one state: two full charts, a legend and three log rows. Three states the
shipping app produces are not drawn.

**Every tree in the inventory is empty.** The seed carries no `measurements` table at all — it has
`trees`, `species`, `neighborhoods`, `species_assertions`, `species_map`, `seed_meta` and the R*Tree,
and nothing else. Measurements can only come from screen 16, the measure sheet, which is not built.
So on launch day every tree's growth history is empty.

**And empty is unreachable.** 11's one drawn entrance is a measurement stat card on screen 03
(`opensGrowthHistory`), which exists only when a measurement does; the city's DBH is a 5 cm *bucket*
rendered as `.cityRecord` and is deliberately not tappable (D7). So the app never routes anybody to
the empty screen. The view still has to answer for it, because the route exists.

What was built, in the shape `TreeProfilePresentation.coldStartFootnote` already uses — say only
what the record supports and drop the rest of the screen:

- **No measurements at all** → the C1 header and one line, `No measurements on this tree yet.`
- **Readings exist, none chartable** → the header, one line explaining that the fixes were too weak
  to attribute, then the full log. The line sits where the charts would have been, not under the
  log, so it reads as the reason the cards are absent rather than as a footnote to the list.
- **A kind with no chartable reading** → no card for that kind. An empty plot asserts a series.

Both strings are **NOT SPECIFIED** and are written to state a fact and no more. They are the two
places on this screen where copy was invented, and they are the two questions for design.

### E64 — screen 11's footnote promises an affordance that does not exist, so it is not rendered

SCREENS.md 11 §6 ends the screen with `Tap any point to open the observation behind it.` There is
nothing behind a point to open. A measurement is not an observation — they are separate tables with
separate outbox kinds — `Route` has no case for either, and no screen in SCREENS.md is drawn as that
destination. Wiring one would be inventing a screen (DECISIONS constraint 21); rendering the sentence
over inert dots would print an instruction the app does not honour, which is the same class of claim
as "sent to the city" (ARCHITECTURE §5.4), smaller and still a promise.

So the footnote is absent. The string is kept verbatim in `GrowthHistoryCopy.unrenderedFootnote` so
it returns unedited the day the destination is designed, and the dots carry their value and method in
their accessibility labels in the meantime.

**Related, and also not invented:** SCREENS.md §5 gap 2 lists the disabled button state as
unspecified, and screen 09's `Done` needs one — PROTOTYPE-FLOW §1.3 `logCare` guards on "no-op if no
care chip is on". The style is specified, just not in SCREENS.md: §1.4's `careBtnStyle` gives
`disabled → background:#E9ECDE;color:#8B9482`. That is now `CypressColor.ctaDisabledFill` /
`ctaDisabledLabel` and `PrimaryButton(isEnabled:)`, transcribed rather than designed.

### E65 — no GPS accuracy reaches any field contribution, and D6 depends on one

D6 requires per-contribution GPS accuracy to be stored, and `FieldCaptured
.isEligibleForGrowthCharting` is the rule built on it: worse than 15 m is excluded from growth
charting, and — correctly — so is a fix that was never recorded, because "unknown accuracy is treated
as unusable rather than assumed good".

`MapLocationProvider.Availability` carries a `Coordinate` and nothing else, and `Coordinate` has two
fields. `CLLocation.horizontalAccuracy` is read and discarded. So every call site in `RootView`
passes `gpsAccuracyM: nil` — screen 05's check-in already did, and screen 09's care log now does too.

Today this changes nothing on any screen: care events are never charted, and observations are not
either. **The day screen 16 lands it changes everything on screen 11** — every measurement the
measure sheet writes would arrive with a nil accuracy, `isEligibleForGrowthCharting` would refuse all
of them, and the growth charts would be permanently empty on a tree somebody had just measured. The
failure would look exactly like the designed empty state (E63), which is how E37 went unnoticed for
as long as it did.

The fix is small and is not in this round's scope: `Availability.located` needs to carry the fix's
accuracy alongside its coordinate, and the provider needs to stop dropping it. Recorded so that
whoever builds 16 does it first.
