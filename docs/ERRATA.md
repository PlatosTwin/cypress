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

**Resolved in E107**, which is where the screen that was built, the one thing it offers, the two
affordances that were declined and the three defects found alongside it are all written down. The
placeholder is gone: a site now has its own route and its own feature, and it is no longer a tree
profile with fields missing.

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

**RESOLVED — the entrances round.** Screen 03 now carries a **C7 secondary outline button under its
primary CTA**, reading `Check in · under a minute`. Neither candidate above was taken: the quad row
still has exactly four cells and the screen still has exactly one primary button. C7 is the
component whose entire job is the quieter thing beside the loud one, which is the honest
relationship between a photograph and ninety seconds with no camera.

**Invented under a one-time, explicit authorization from the project owner** covering the entrances
of the six unreachable screens, and marked as invented in `TreeProfilePresentation.checkInCTATitle`
so a designer can delete or move it from one place. The copy is assembled from words screen 05
already uses — its own title and its `under a minute` header pill — in the `X · Y` shape the primary
CTA above it is drawn in. It is gated on `TreeStatus.acceptsNewContributions`, so a memorial and a
vacant site are not offered it. See E98.

Screen 18 is still not wired as 05's confirmation, for the reason given above; that is unchanged.
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

**RESOLVED — the entrances round.** The **Journal tab renders screen 12 as its root.** BUILD-PLAN
§12 groups "collections, almanac, journal, share cards, phenology notifications" as one layer and
names the almanac and the journal in one M4 acceptance line, so the pairing is the plan's own; what
is invented is making the almanac the tab's *content*, under the one-time authorization (E98). The
tab was a `NotBuiltYetView` before it, so nothing was displaced.

`Route.almanac` stays wired and now has no caller, which is recorded rather than tidied away: the
route is the app's name for the screen, and a future second entrance would push it. Its header draws
no back circle, because a tab root has nothing to go back to. See E98 and E99.
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

**RESOLVED — the entrances round**, and the resolution is a *pair*. The stat card on 03 now has two
destinations rather than one:

- a card **with** a reading opens 11, which is the drawn affordance and was never invented;
- a card **without** one opens 16, the measure sheet, which is (E74's half of this, and invented).

So the entrance that could not fire now can, because the thing it needed — a way to write a
measurement at all — is reachable from the card beside it. Verified on device: a DBH reading saved
through the outbox flipped the seeded tree's DBH card from the city's `5–10 cm city record` bucket
to `31 cm taped`, and that card opened screen 11 with a chart on it, which no device had ever
rendered before.

The three empty states above are unchanged and still carry invented copy; they are still questions
for design. What changed is only that the app can now reach them. See E98.
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

### E66 — nothing opens screen 13, which is the fourth screen this is true of

SCREENS.md 13 is named as a destination nowhere. Screen 03's affordance list ends at `hero → photo
timeline (NOT SPECIFIED)`, `Visit → 04`, `Care → 09`, `Share → 10`, `Report → 06`, `DBH/Height → 11`
and `activity row → the observation behind it` — that last one is not this screen and, per E64, is
not a screen at all. The clickable prototype's `screen` enum is `map | identify | profile | camera |
saved | grove` and never held 13. BUILD-PLAN §9 lists no entry for it.

So the count is now four: 05 (E24), 12 (E57), 11 (E63, whose entrance exists but can never fire on
the shipped seed) and 13. Their exits are drawn and their entrances are not.

The two least-invented candidates are both design decisions and neither was taken (DECISIONS
constraint 21):

- **A "see the whole year" link under 03's activity feed.** 03 draws two C9 rows and no more, and
  SCREENS.md states no control under them. Adding one is adding a control to a screen whose parts
  are enumerated.
- **A tap on 03's foliage strip.** The strip is A5's photo-coverage strip and 13 is a year of
  activity; they are two different years of two different things, and making one open the other is a
  claim about their relationship that nothing states.

`Route.activity(UUID)` exists and `RootView` resolves it, because the route has to exist before the
affordance can be designed and because the screen has to answer for its empty state — which, per E67,
is the state every tree in the shipped app is in.

**RESOLVED — the entrances round.** The first candidate above was built: a **`See the whole year`
link under 03's activity feed**, invented under the one-time authorization (E98) and marked as such
in `TreeProfilePresentation.activityLinkTitle`. The second candidate — a tap on the foliage strip —
stays rejected for the reason given: two different years of two different things.

The link draws **only where the feed draws**, which is the same threshold rule ARCHITECTURE §5.6
states: on the shipped seed no tree has any activity, so no tree offers a door onto the empty state
E67 describes.
### E67 — screen 13 has no empty state, and the empty state is the whole shipped app

SCREENS.md 13 draws one state: a full chart card, three moments, a three-up photo strip and a
footnote. It is a year in the life of a tree that 41 photographs, 18 check-ins and 9 care visits have
happened to.

**No tree in the shipped app has any of that.** The seed carries `trees`, `species`,
`neighborhoods`, `species_assertions`, `species_map`, `seed_meta` and the R*Tree — no visits, no
observations, no care events, no photos. Combined with E66 (nothing opens the screen) and E63 (the
same is true of 11), the shipped state of screen 13 is: a C1 header, a trailing pill naming the tree,
and one line.

What was built, in the shape `GrowthHistoryCopy.emptyState` and
`TreeProfilePresentation.coldStartFootnote` already use — state a fact and drop the rest of the
screen:

- **Nothing on the record at all** → the header and `Nothing has been recorded on this tree yet.`
- **A year with nothing in it, on a tree with older records** → no chart card. Thirty-six empty bars
  under `This year at a glance` is exactly the zero ARCHITECTURE §5.6 forbids, and E54 already
  settled that argument at zero in §5.6's favour on screen 12.
- **A page rather than a series** → nothing at all. See E68.

The empty string is **NOT SPECIFIED** and is the one place copy was invented on this screen. It is a
question for design.

### E68 — screen 13's shared scale means a page in one series takes down all three

ERRATA E38 established that a page's size is not a total. Screen 13 raises the stakes, because D2
puts **one vertical scale** across its three small multiples: "the three remaining charts share one
scale", and the mock's own footnote is `One scale across all three charts, so a tall bar means the
same amount everywhere.`

That scale is the tallest month anywhere in the thirty-six. A page understates it, and the two rows
the page did **not** come from are then drawn against a ceiling that is too low — they render too
tall, and the card's one stated claim becomes false with nothing on screen to hint at it. A wrong
total is a wrong number; a wrong scale is three wrong charts.

So `ActivityPresentation.glance` needs all three series complete or it renders nothing, and every
other block on the screen holds the same line: the moments list states a first date, a span and a
month range, and the photo strip states which years hold a photograph from this week — all of them
claims about a whole series. `LocalAPI.treeProfile` reads every one of them with `limit: nil`, so on
the shipping implementation the card always has what it needs; the guard is there because
`RemoteAPI` will not, and because the failure is invisible.

### E69 — the check-in series was not on the profile payload, and A8 was quietly short because of it

`TreeProfile` carried `photos`, `visits` and `careEvents` as whole `Series` and carried observations
as `latestObservation` — one row. Screen 13's middle small multiple is a twelve-month `Check-ins` bar
row, which one row cannot draw: a single check-in in October renders as a year in which one check-in
happened, and it would have set the shared scale for the other two rows as well (E68).

**The same gap was already costing A8 on screen 03**, where it was recorded as a limitation rather
than a bug: A8 counts "distinct users with 2 or more care_events **or observations** on the tree in
24 months", and with only the latest observation in hand the observation half could contribute
exactly one person. `TreeProfilePresentation.caretakers` said so in a comment and called it a payload
limit.

Fixed additively rather than with a new endpoint, which is what the shape of the thing asks for: a
check-in belongs to a tree's profile exactly the way a visit does. `TreeProfile.observations:
Series<TreeObservation>` (defaulted to `.empty`), `ContributionStore.observations(treeID:limit:)`,
and `LocalAPI.treeProfile` reading it whole. `CypressAPI` grew no method. `latestObservation` is now
taken from the head of that series rather than from a second query, so the two facts cannot disagree.

`TreeProfilePresentation.caretakers` now counts over both whole series and de-duplicates the latest
observation by id, so a caller that filled only `latestObservation` still gets it counted once.

### E70 — SCREENS.md 13 prints a care total; BUILD-PLAN §4 says care events are never counted

SCREENS.md 13 §2 draws three legend lines with three totals — `Photos 41`, `Check-ins 18`,
`Care 9` — and §3's second moment reads `Jun–Aug · five care visits kept it going`.

BUILD-PLAN §4, `care_events`, in full: "actions text[]: watered, mulched, weeded, litter_cleared,
staked. Photo optional. **Never publicly counted or ranked (D1)**." It is the only one of the three
series the data model singles out. BUILD-PLAN sits above SCREENS.md in the precedence order
(ARCHITECTURE §1), and `CareEvent`'s own doc comment already reads it that way: "nothing may
aggregate it into a user-visible total".

**Resolved in BUILD-PLAN's favour, and narrowly.** The Care row draws its twelve bars — D2 keeps the
chart, the caption's whole subject is the *rhythm* of care read against the photo spike, and a shape
is not a tally — and prints no total. The moments row becomes `Watered through the dry weeks` /
`Jun–Aug`. §5's ceiling sentence names the month that set the scale, so when that month is a care
month the sentence is a care count in prose and is not written; the first sentence stands alone.

**Why the other two totals stay.** Read literally, DECISIONS §3.1 ("no public counts of user actions
anywhere") forbids the Photos and Check-ins series as well, since photographs and check-ins are also
things users did — and that reading makes D2, a binding decision written specifically about this
screen, unimplementable. D1's stated reason is entirely about ranking and farming *people*, and every
number on screen 13 describes one tree and is attributable to nobody. That is the same reconciliation
`TreeProfilePresentation.heroMetaPill` already ships with (`214 photos · since 2019`).

The asymmetry is deliberate and will look like a bug to anyone who has the mock open, which is why it
is written down. If the reviewers want the `9` back, it is one `mayPrintTotal` and two call sites.

### E71 — C26 · AvatarStack cannot honestly show anything, on 13 or on 03

Worth recording because 13 reads as the screen an avatar stack belongs on — it is the screen about
who has been looking after a tree — and it does not have one.

**SCREENS.md 13 draws no AvatarStack.** C26's catalogue entry names screen 03 and only 03; 13's parts
are a header, a chart card, three C10 rows, a photo strip and a footnote. So nothing was removed.

**And on 03, where it *is* drawn, it shows nothing either.** Three facts stack up:

- **There is no account system (D9).** Every contribution the app writes is anonymous under a device
  id: `RootView` passes `.anonymous(deviceID:)` at every call site, so `userID` is nil on every
  visit, observation and care event. A8 counts *distinct users*, so its count is zero on every tree
  in the shipped app, and at zero the surface does not render (ARCHITECTURE §5.6). `TreeProfileView`
  is already correct about this; `TreeProfileModel.caretakerInitials` defaults to `[]` and nothing in
  `RootView` passes any.
- **Contribution feeds are private by default (D11).** Even with accounts, another person's initial
  on this tree's page requires their opt-in public attribution, and
  `User.isPublicAttributionEffective` is the only predicate allowed to answer that — it refuses for
  under-18 accounts whatever the stored toggle says. Nothing on the profile payload carries a `User`,
  so the predicate has no subject here.
- **A blank stack is worse than no stack.** Circles with no letters in them, on a screen about who
  knows a tree, is a claim that people are there.

So screen 13 renders no name, no initial and no avatar, which is the strongest form of D11 compliance
available: there is nothing for the predicate to gate. `SharePresentation` reached the same answer
for screen 10 (E59) by the same route. The risk this leaves is **forward** — the day somebody adds an
attribution row here, `publicAttribution` is the field autocomplete offers — so the predicate is
pinned in `CypressTests/ActivityPresentationTests.swift` alongside the screen, as
`SharePresentationTests` pins it alongside 10.

### E72 — screen 13 has no dark row, and it is where the three-series palette visibly collapses

Same class as E61 (09, 10 and 11 have no dark row) and E56 (12's four swatches want deciding
together). SCREENS.md's dark deltas are D1–D3 plus 04; 13 is not among them, so what the token layer
resolves it to is evidence rather than a design.

One thing is worse here than a missing row, and it was predicted in the token file itself.
`CypressColor.chartSeriesPrimary` records that the E8 accent transform "anchors lightness, so Canopy
and New Growth — 0.117 apart in light — land 0.011 apart in dark and C23's three series become two",
and the three are escalated as a set for that reason. Screen 11 draws one series at a time and never
showed it. **Screen 13 draws all three at once, and it shows.** In the dark screenshot the `Photos`
and `Check-ins` rows are told apart by position and by their labels, not by colour; only `Care`
(Bark) separates. Left light, which is a stated failure rather than a hidden one, and it is now a
failure with a picture of it.

Two smaller derivations this screen introduces:

- **`photoStripChipFill`** — §4's `rgba(255,255,255,.85)` year chip. Classified `lightOnly` rather
  than derived, on the same grounds as `heroMetaPillFill`: it is a scrim punched into a photograph so
  a date can be read off it, and a photograph does not get darker because the phone did.
- **§4's current-week tile** takes `selectionFill` / `onSelectionFill` for its 2pt border and its
  inverted chip rather than raw Canopy, so it follows the documented `#2F6B4F → #8EC3A5` selection
  pair after dark instead of staying a brand hue.

### E73 — three rules screen 13 needs and SCREENS.md does not state

Recorded together because each is a decision inside `ActivityPresentation` that would otherwise be
invisible, and each is something the mock states once as though it were a rule.

**The bar heights are pixels, and the mock's own numbers do not reconcile.** §2 gives twelve heights
per series (`8, 4, 10, 13, 17, 34, …`) and one count, in §5: `June’s 12 photos set the ceiling.`
There is no linear map from those heights to counts that also sums to the drawn `41`. So the heights
were treated as what they are — a drawing of one tree's year — and the rule was rebuilt from the two
things the mock does state: one shared scale, and `4` for a month with nothing in it. A count of `n`
draws `4 + 30·n/peak`; the peak reaches `34`; an empty month keeps the `4` stub and is told apart by
colour, which is exactly how the mock's Care row distinguishes its starred bars from its unstarred
ones at the same height.

**"Watered through the dry weeks" is checked, not asserted.** §3's second row is the mock's `Jun–Aug`
for one tree in one year, with no rule behind either the window or the word "through". The window is
named as `ActivityMetrics.dryMonths` (6...8) — narrower than San Francisco's actual dry season, which
is the direction that cannot overclaim — and the row needs waterings in **two** distinct months
before it will say "through", because waterings inside one month are not a season of them. Same shape
as A9's fifteen-minute-walk sentence on 12 (E55): a claim about duration is only written when it has
been verified.

**"Same week, other years" needs another year in it.** §4 draws three tiles: `2024`, `2025` and a
bordered `this week`. A strip holding only the current week's photograph would draw one bordered tile
under a heading that is false, so the block needs at least one prior year before it renders at all,
and it never fills the row out with a tile for a week nobody photographed. The mock's third tile is
also the answer to what the border means: it marks now, without printing a word.

### E74 — nothing opens screen 16, and the one place it could open from is a screen whose parts are enumerated

SCREENS.md 16 is named as a destination nowhere. Screen 03's affordance list ends at
`DBH/Height cards → 11`; screen 11 draws a chart, a legend and a measurement log and no control at
all (its one footnote promises a destination that does not exist and is deliberately unrendered,
E64); the clickable prototype's `screen` enum is `map | identify | profile | camera | saved | grove`
and never held 16; BUILD-PLAN §9 lists no entry for it.

So the count is now six: 05 (E24), 11 (E63, whose entrance exists but can never fire on the shipped
seed), 12 (E57), 13 (E66), and now 16 and 17 (E75). Their exits are drawn and their entrances are
not.

The least-invented candidate is an "add a reading" control under 11's measurement log, and it is a
design decision rather than a gap: 11's parts are enumerated in SCREENS.md and adding a control to
them is adding a control (DECISIONS constraint 21). It is also not obviously the right place — the
measure sheet is a field surface and 11 is a history surface, and the tree profile is where every
other field action on this app starts.

`Route.measure(UUID)` exists and `RootView` resolves it, because the route has to exist before the
affordance can be designed, because the screen has to answer for a tree with no previous reading
(which is every tree in the shipped seed), and because until it is reachable **nothing in the app can
write a measurement at all** — which is why screen 11 has never had a chart on any device.

**RESOLVED — the entrances round**, and not with the candidate above. The control is on **screen 03,
not screen 11**: an *empty* measurement stat card, reading `Add a reading` in the faint mono of
screen 16's own empty readout (E77), which opens the measure sheet. 11 keeps its enumerated parts and
gains no control.

The argument for the profile over the history screen is the one this entry already makes — "the tree
profile is where every other field action in this app starts", and a contributor holding a tape has
no reason to have opened a history screen first. The copy is this entry's own phrase.

**Invented under the one-time authorization** (E98) and gated on
`TreeStatus.acceptsNewContributions`, so a memorial and a vacant site draw no slot at all: verified
on device, a vacant site's stat grid is `Site` and `City record` and nothing else. Note that the
city's DBH *bucket* is still not a door — where the city published a range, that card renders as
`.cityRecord` and is inert, and the Height slot beside it is the entrance.
### E75 — screen 17's entrance is named in BUILD-PLAN §9 and sits on a screen that does not exist

Unlike 16, screen 17's entrance is written down. BUILD-PLAN §9's M2 list includes "the You tab
(profile, settings, **outbox entry point**, privacy toggles)". That is a specification, not an
invention, and it outranks the fact that no mocked screen reaches 17.

It is also not buildable yet. The You tab has no mock — no drawn layout, no copy, no settings
inventory — and `RootView` renders it as `NotBuiltYetView(label: "you")`. Adding an outbox row to a
placeholder would mean designing the first row of an undesigned screen in order to reach a built one,
which is the same trade DECISIONS constraint 21 refuses.

So `Route.outbox` is wired and the affordance waits for the screen it belongs on. The consequence is
worth stating plainly: today the outbox is invisible to a contributor, and the outbox is the one
subsystem whose whole promise ("nothing here disappears silently") is a promise about being visible.

**RESOLVED — the entrances round.** The You tab exists, and the row is on it. This entry's own
sentence is what built it: BUILD-PLAN §9's "the You tab (profile, settings, outbox entry point,
privacy toggles)" is a specification, so **the outbox row is specified, not invented** — what was
invented is only the tab's layout, which no document draws.

The tab is deliberately thin, and each absence has a reason: no profile block and no sign-in entry
point, because there is no account on any device this app runs on (E86) and a header over a person
who does not exist is worse than no header; no counts of anything, because a "You" tab is the single
most likely place in this app to drift into a profile-with-stats, which D1 forbids. What it carries
is the outbox row, the wi-fi preference (the only setting `AppStateKey` persists, shared with screen
17 so the two surfaces cannot disagree), and a stated privacy position. See E98 and E100.
### E76 — 16's "sure about that?" is a dialog in the copy, and a dialog is the one thing it must not be

SCREENS.md §5 gap 10 lists "the 'sure about that?' anomaly confirmation on 16 — described in copy
only". §7's footnote is the description: `A shrinking trunk gets a “sure about that?” before it
saves.`

Built as drawn — a modal that intercepts the save — it would contradict two rules at once. DECISIONS
§2.5 resolves Open Question 3 with "accept both, always; record which per field via a mandatory
method flag; **never block submission**", and §3.5 repeats it: "Submission is otherwise never blocked
for lack of rigor". `TreeMeasurement.isPlausible` already documents itself as "warn the user, never
reject". A gate in front of the save is exactly the thing those sentences forbid, and it is worse
here than elsewhere: the person holding the tape is the only one who knows whether the trunk really
did shrink, and a dialog asks them to argue with the app before their reading is allowed through.

So the confirmation is a **line above the CTA**, in Signal Amber, and the CTA stays live. Two cases
raise it, and both are the rule DECISIONS §3.6 already states ("range validation on entry"):

- the reading is smaller than the last one of the same kind (`MeasureCopy.anomalyShrunkTrunk`);
- the reading falls outside `MeasurementKind.plausibleSIRange` (`MeasureCopy.anomalyOutOfRange`).

The footnote is kept **verbatim**, because what it describes is what happens: a shrinking trunk does
get a "sure about that?" before it saves. Only its form is different from the one a reader might
imagine, and the form was never drawn.

### E77 — three states 16's readout needs and SCREENS.md does not draw

Recorded together because each is a decision inside `MeasureDraft` that would otherwise be invisible.

**The empty readout.** §3 draws `64` and no empty state. A blank space where a 56pt number goes
reads as a broken screen; a plain `0` reads as a measurement of zero. The readout draws
`MeasureCopy.readoutPlaceholder` — a `0` in `text.faint` rather than `text.ink` — and the CTA is
disabled until a key is pressed. `MeasureDraft.value` also refuses a typed `0`, for the reason
`CareLogModel.save` refuses an empty care event: an empty keypad is not an imprecise reading, it is
no reading.

**Switching the unit clears the entry.** §3's `switch to inches` has no stated behaviour. Keeping the
digits and swapping the label turns `64 cm` into `64 in`, a 2.5× error written to an append-only
record with nothing on screen to catch it. Converting them makes `Quantity.value` — "the number as
the human typed it… never silently converted" — false in the other direction. So the entry is
cleared: the number was an answer in the old unit, and the new unit needs a new one. Four digits is
the cheap half of that trade.

**Height's unit pair.** §3 draws only the trunk's `cm ⇄ in`. A height in centimetres is nobody's
reading, so the pair is `m ⇄ ft`, chosen per kind in `MeasureMetrics.alternateUnit`. Changing what is
being measured therefore also changes the unit, and clears the entry for the same reason.

### E78 — 16's sanity pill has no anchor on any tree in the shipped app, and the city's DBH is not one

16's caption is "the previous value sits under the readout as a sanity check", and §3 draws
`Last recorded 62 cm, Jun 2024 · +2 cm in a year sounds right`.

**There is no previous value.** The seed carries `trees`, `species`, `neighborhoods`,
`species_assertions`, `species_map`, `seed_meta` and the R*Tree, and no `measurements` at all — and
screen 16 is the only thing in the app that can write one (E74). So on launch day the pill is absent
on every tree, which is `ARCHITECTURE §5.6` applied to a surface with nothing behind it.

**The city's DBH is deliberately not used to fill it.** `trees.dbh_city_cm_range` exists on every
imported row and would make the pill render everywhere. It is a 5 cm bucket — "seed data is a range,
never a point" (BUILD-PLAN §4), which is why `TreeProfilePresentation` renders it through
`StatCard.Value.cityRecord` and not as a `Quantity`. Subtracting an entered number from a bucket
manufactures a delta nobody measured, and printing `+2 cm` off it would be a measured claim built
from an unmeasured one. The pill anchors on a real reading or it does not draw.

**The verdict clause is written only when the record supports it.** `+2 cm in a year sounds right` is
three claims: a direction, a span, and a judgement. It is written only when the reading went up, at
least `MeasureMetrics.minimumVerdictMonths` have passed (two readings a fortnight apart say nothing
about a rate), and the annualised change is inside `MeasureMetrics.maxAnnualGrowthM` — 10 cm a year
for a trunk, which is far outside anything ordinary for an SF street tree while staying clear of
calling an unusual but real year a mistake. **That ceiling is a judgment call and is not in any
document.** Outside it the pill states the previous reading and stops; nothing is blocked and no
alarm is raised, because "grew faster than expected" is not an anomaly the way "shrank" is.

The pill also carries the previous reading's C12 method badge, which §3 does not draw. D7 is that a
number carries how it was obtained wherever it appears, and a `62 cm` that turns out to have been an
estimate is a different sanity check from one that was taped.

### E79 — 16 has no state for a fix D6 will not chart, and that silence is how E65 hides

D6 excludes readings with GPS accuracy worse than 15 m from growth charting, and
`FieldCaptured.isEligibleForGrowthCharting` also excludes a reading whose accuracy was never
recorded. `GPSAccuracy.growthChartingLimitM` is 15 and `VisitShortlist.assumedAccuracyM` is 25, so a
fix CoreLocation could not measure is excluded by arithmetic rather than by a special case
(`LocationAccuracyTests`).

SCREENS.md 16 says nothing about any of this. Saving in an urban canyon would therefore write a
reading that can never appear on screen 11, and screen 11 would draw its designed empty state (E63)
with nothing anywhere saying why — which is precisely the failure mode E65 describes: "the failure
would look exactly like the designed empty state, which is how E37 went unnoticed for as long as it
did."

So the sheet says it before the save, in one sentence above the footnote:

- a real fix outside the limit — `This fix is good to about 40 m, so the reading is saved but stays
  off the growth chart.`
- no fix at all — `Without a location fix the reading is saved but stays off the growth chart.`

**The save is not blocked and the reading is not discarded.** Screen 11 settled that side already:
its measurement log shows every non-deleted reading including the ones D6 keeps off the chart,
because "hiding somebody's own contribution because the GPS was poor when they made it would be worse
than showing it" (`GrowthLogRow`). Screen 16 is the same principle one step earlier. **NOT SPECIFIED**
by SCREENS.md; recorded here rather than treated as a gap to leave open.

### E80 — the count behind "N photos are waiting for wi-fi" counts items, and the sentence says photos

`OutboxSnapshot.awaitingWifiCount` is the number E32 rebuilt clause by clause, and it is a count of
**rows**: "Items whose JSON went and whose photos are queued behind the wi-fi toggle."

`OutboxFailureReason.awaitingWifi(photoCount:)` writes `The note is saved. N photos are waiting for
wi-fi.` Per item, `OutboxQueue.drain` passes that item's own `photos.count`, so the sentence on a row
was always right. Screen 17 also says it once for the whole queue, and there the only number to hand
was the item count: two visits carrying two photographs each would have said `2 photos` with four
sitting on the device.

E32's own standard is the fix — "every clause of it has to be true before the count claims it" — and
`photos` is a clause. `OutboxSnapshot` now carries `awaitingWifiPhotoCount` beside the item count,
summed across exactly the same filtered rows, and the screen's sentence reads that one.
`awaitingWifiCount` keeps its meaning and its tests.

### E81 — 17's header pill claims a connectivity state the app has no way to know

SCREENS.md 17 §1 draws the trailing amber pill as `3 waiting · offline`.

Nothing in this app knows whether it is offline. There is no reachability monitor, no
`NWPathMonitor`, and no plan for one in BUILD-PLAN; the closest thing available is a failure sentence
reading `No connection.`, which is a record of what happened at the last attempt and not a statement
about now. A pill reading `offline` beside a live connection is the same class of untrue label as
"sent to the city" (ARCHITECTURE §5.4) — small, and still a claim the app cannot support.

So the pill renders `3 waiting` and stops, and it is absent entirely at zero, because `0 waiting` is
the zero ARCHITECTURE §5.6 does not draw. The dropped clause is a real design question — a
volunteer in a dead zone genuinely wants to know it is the dead zone and not the app — and it needs a
reachability source before it can be answered.

### E82 — 17's summary line names a week the store keeps for a day, and links to a screen that does not exist

§5 draws `this week · 14 synced · 0 lost`, with a trailing `full history` link.

**The week is not available.** `OutboxQueue.completedRetention` is 24 hours and `pruneCompleted`
deletes `done` rows past it — deliberately, because §4's own section is headed `Synced earlier
today`. A week's figure would have to come from somewhere that does not exist, so the line says
`today · 14 synced · 0 lost`: the window the store can actually answer for. `0 lost` is computed from
the rows rather than hard-coded, which is the only reason it is worth printing at all.

The line is absent when nothing has synced today, because `0 synced` is a zero (§5.6).

**`full history` is not rendered.** There is no history screen, no `Route` case for one, and the
Journal tab that would host it is an unbuilt M2 requirement. This is the same subtraction E64 made to
screen 11's footnote: printing a control that goes nowhere is a small promise the app does not keep.

### E83 — `failed` is two terminal states and SCREENS.md draws one

`OutboxRetryPolicy.nextState` produces `.failed` for two different reasons: the 48 h cap ran out, or
the API returned a taxonomy code that is not retryable (`validation_failed`, `conflict`,
`moderation_rejected`, `forbidden`). `OutboxFailureReason.describe` already writes two different
sentences for them — `Tried for 48 hours without getting through. Tap retry when you have a
connection.` against `<cause> This one will not go through on its own.`

SCREENS.md 17 §2 draws one treatment: an amber C24 card with the mono word `retry`. BUILD-PLAN §4 is
where the control comes from — "cap 48 h then state failed with **a visible retry button** (screen
17)" — and it attaches that button to the cap, not to the taxonomy.

Offering `retry` on a row whose own sentence says it will not go through on its own is a promise
BUILD-PLAN §6's taxonomy says will not be kept. So the terminal state renders in two forms:

- **`retry`** — the drawn one. Amber card, amber mono word, and the word is a real control with a
  44pt hit area (BUILD-PLAN §4's "visible retry button", which the mock draws only as a label).
- **`stopped`** — **NOT SPECIFIED**. Same amber card and the same sentence, no control.

Both are clearly separated from `waiting`, which is the state an item keeps however many times it has
failed while it is still inside its window. That separation is the point: a row that has failed four
times and will try again in an hour is not the same fact as a row that has stopped, and the mock's
single amber treatment cannot say which.

### E84 — 17's rows draw what is inside an item, and the snapshot threw it away

SCREENS.md 17 §2's three rows read `2 photos · 11:42 am`, `vitality 3, thinning · 11:18 am` and
`DBH 31 cm, tape · upload failed twice`. None of that is recoverable from a kind and a timestamp, and
`OutboxItemSnapshot` carried only those.

`OutboxSnapshot.init` was already decoding each row's payload — to find `treeID` — and discarding
everything else. It now keeps it (`OutboxItemSnapshot.payload`), which costs nothing and is what lets
the third row render its reading through `MeasuredValue`, with the C12 badge D7 requires rather than
the mock's spelled-out `, tape`. Screen 17 is the last surface a queued number passes before it
reaches the record, so it is the last place a method could go missing.

Two smaller corrections came with it:

- **`updatedAt` was missing.** §4's receipts read `✓ 9:56 am`, which is when the item *went*, and the
  snapshot only carried `createdAt`. On an item that waited out a dead zone those are different
  hours, and the capture time is the wrong one to stamp a receipt with.
- **`OutboxPayload` is now `Hashable`**, which is what carrying it on a `Hashable` snapshot needs.
  Every associated value already was, through `CoreEntity`.

Two of §2's three leading glyphs are **not built**: the camera and the check-in ring are drawn in
SCREENS.md 17 and are not in the C1–C30 catalogue, and adding two icons to the design system to draw
one screen is not this round's work. Every non-measurement row takes C21's leaf, which is the app's
only bespoke mark; the measurement row draws its reading in mono inside the tile, as the mock does.
The tile's amber fill follows the *terminal state* rather than the kind, because Signal Amber is
reserved for "this tree needs something" (§1.1) and the mock's amber tile is on its failed row.

### E85 — screens 16 and 17 have no dark row

SCREENS.md §3's dark section is D1 (map), D2 (profile) and D3 (check-in). Screens 09, 10 and 11
(E61), 12 (E56), 13 (E72) and now 16 and 17 have none, which is the same finding E8 recorded about
the token layer: dark is specified for four screens and the app has more than four.

Both screens are built entirely from `dynamic` and `derived` token pairs, so both resolve in dark
without a line of screen-specific code, and both carry a dark preview as evidence of what that
resolution looks like rather than as a design. Two things are worth a designer's eye before M4:

- **16's readout.** A 56pt mono number in `text.ink` over `surface.screen` is the largest single piece
  of type in the app, and the dark pair (`#E4EBE2` on `#0E1712`) has not been looked at at that size.
- **17's amber.** The terminal row is `border.amberMid` on `surface.card` with `signal.amber` text,
  and in dark all three of those collapse toward the single `#D99A4E` the palette gives dark amber.
  The card, its word and its tile glyph are then the same hue at three different weights, which is
  exactly the collapse E72 recorded for 13's three chart series.

### E86 — screen 15 asks for an account the app has no way to create

Screen 15 draws three sign-in routes. None of them can work in this build, and the reason is written
into `CypressAPI`'s own header: "`POST /auth/*`, `POST /auth/refresh`, `POST /auth/logout`,
`DELETE /me` — there is no auth server and no local equivalent of a token exchange. Adding throwing
stubs would suggest a sign-in flow exists."

Nor can any of the three be made to work from inside the app:

- **Apple** needs the Sign in with Apple entitlement, which is a project-file change, and a server to
  verify the identity token against.
- **Google** needs a third-party SDK, and the project has zero external dependencies by decision
  (BUILD-PLAN §3).
- **Email** is magic link only (DECISIONS §3.9, A10), which needs somewhere to send the link from.

A fourth option was considered and rejected: minting a local user id and calling `claimDevice`, which
would make the screen "work" end to end today. It is rejected because the sheet's own second sentence
is `An account backs them up and lets them join each tree's public timeline`, and a local id backs
nothing up and joins nothing. That is the same class of untruth ARCHITECTURE §5.4 forbids about the
city, applied to an account, and it would be worse than the city case because it is irreversible in
the contributor's head: they would believe their photographs were somewhere else.

So the screen presents, is drawn as specified, and its three buttons are wired to an injected action
(`AccountAskLink`) that the composition root does not supply — the shape screen 06's reminder used
before E23 settled it. A tap therefore claims nothing.

**Two sentences of new copy, and SCREENS.md has none.** 15 draws the buttons and nothing after them.
E23 already made this call once in the other direction: "a control that acts and says nothing is the
same dishonesty in the other direction, so this is the smallest answer that is not silence." Both
sentences end on the screen's own §7 promise:

- `Accounts are not ready yet. Everything you have saved stays on this phone.`
- `That did not go through. Everything you have saved stays on this phone.`

**What a decision-owner has to settle:** whether an ask that cannot be honoured should be presented
at all. The argument for presenting it is that the decline path is real, it works, and the ledger's
resolution is what stops the ask returning for ever (E34). The argument against is §5.6's principle —
a surface that cannot state its own truth does not render — and that interrupting the third save to
offer three buttons that do not work spends D9's one interruption on nothing. The interruption is
currently spent; suppressing the sheet until an auth service exists is a two-line change in
`VisitSavedView` and would need the ledger to stop counting the presentation, which is the part that
needs the decision rather than the code.

### E87 — `Keep your three visits` needed a count that nothing in the app could prove

Screen 15 §1's headline carries a number about the person reading it. Three candidate sources
existed and all three were wrong:

1. **`VisitSaveLedger`'s save counter.** It is a `UserDefaults` funnel value, and the ledger's own
   comment refuses to expose it: "this number is **never rendered**… it is deliberately not exposed
   as a string anywhere", citing ARCHITECTURE §5.1. It is also wrong on the second offer — E34 lets
   the ask return on the fourth save, when the counter says four and the phone holds four.
2. **`journal(cursor:limit:)`.** Returns a `Page`, and a page's size is not a total (E38).
3. **`grove()`.** Returns trees, not visits, and a contributor who visited one tree three times has
   one grove entry.

So the protocol grew a method, as ARCHITECTURE §4 requires when a screen needs data: `CypressAPI
.deviceContributions()`, returning a `DeviceContributions` of the five record kinds `claimDevice`
moves. A `COUNT(*)` is a total in a way a page never is, so it may be rendered.

**Whether this is the count D1 forbids was the real question.** D1 kills "streaks, points, ranks,
badges, or **public** counts of user actions" and DECISIONS §3.1 adds "recency and identity phrasing
only". This count is not public — the rows exist on one phone and are attributed to nobody — it is
never compared or ordered, and it is not a reward: it is the inventory of what somebody would lose,
stated once, in the one moment the app asks for anything. The judgment is recorded here rather than
only in the type's doc comment because a second caller of `deviceContributions()` is the moment to
re-read D1, and this is where a reviewer will look.

The headline drops its number rather than saying nought (`Keep your visits`), and reads `Keep your
visit` at one. Pinned in `AccountAskSheetTests`.

### E88 — a contribution queued before sign-in and applied after it stayed the device's

`claimDevice` sweeps the rows that are in the tables when it runs. The outbox means a mutation exists
for a while before it is in a table at all: written on Tuesday in a dead zone, drained on Thursday.
If sign-in happens on the Wednesday, the row lands on Thursday carrying the anonymous `Attribution`
it was built with — payloads are immutable, and rewriting one after the fact would change a mutation
the outbox has already promised to send verbatim — and the sweep that would have adopted it has been
and gone.

The contributor is told, by screen 15, that their work comes with them. The tail of their queue
silently does not. It is the worst-shaped bug this feature could have: invisible, permanent, and
proportional to how bad the signal was when they were working.

**RESOLVED.** The claim is a fact with a lifetime, not an event, and the `device` row `claimDevice`
already writes is where that fact is durable. `ContributionStore.claimedUser(forDevice:)` reads it,
and `LocalAPI.sync` re-runs the claim once after any non-empty batch. It is the same statement set,
whose WHERE clauses stop matching once they have run — nothing inserts, nothing deletes, and rows
belonging to another account are not touched — so re-running it is free of consequence when there is
nothing to adopt, and one indexed SELECT when the device was never claimed.

Two tests in `DeviceClaimTests` hold it: a visit and a private reminder, each queued before the claim
and drained after it.

### E89 — an anonymous device cannot favourite a tree, so sign-in carries no favourites

`favorites` is the one contribution table with a `NOT NULL user_id` and no `device_id` column
(`AppSchema`), and `ContributionStore.groveTreeIDs` only reads favourites when a user is present. So
on every device the app currently runs on, the heart on screen 03's quad-action row has nowhere to
write to. `RootView` says as much at the call site — `onFavorite: { _ in /* outbox mutation — wired
with the grove, M2 */ }` — so nothing is lost today, because nothing is written.

It matters here because "everything you have already done survives signing in" is screen 15's
promise, and favourites are the one thing on that list which survives by being impossible rather than
by being adopted. `DeviceContributions` says so in a named constant rather than by omission.

This is the same decision E23 settled for private reminders — give the row a device owner, with a
`CHECK` making ownership exclusive so adoption is a move — and it should be taken the same way,
deliberately, rather than by a second quiet precedent. It also has a wrinkle E23 did not: favourites
are tombstone toggles with a `UNIQUE (user_id, tree_uuid)`, so the pair becomes
`(owner, tree_uuid)` and the uniqueness has to survive the move.

**RESOLVED — favourites are device-scoped, on E23's terms.** The decision was taken the same way and
for the same reason: D9 is what makes every device anonymous, and a first save that cannot be made
is not a deferred account ask, it is a missing feature. PRODUCT §Conflicts 22 had already named the
hole — "offline favorites are listed as outbox mutations, but favoriting is also the account-gate
trigger — behavior for an anonymous offline favorite is undefined" — and D9 defines it: the device
holds it until an account arrives, exactly as it holds a visit.

**The schema, `AppSchema` v5.** `favorites.user_id` becomes nullable, `device_id` appears beside it,
and `CHECK ((user_id IS NULL) <> (device_id IS NULL))` makes exactly one of them non-null. Not
"nullable user plus a NOT NULL device", for E23's reasons restated: that shape leaves both columns
populated after sign-in, so the owner is whichever column a query coalesces first, and it keeps a
permanent device↔account link. Exclusive ownership makes adoption a *move*, so the row carries
strictly less about the device afterwards than before. `FavoriteOwner` is the same rule in Swift —
two cases, no third state — and it is a separate type from `ReminderOwner` on purpose: the two have
the same shape and different invariants, since a reminder's owner is a privacy boundary and a
favourite's owner is half of a uniqueness key with a merge rule attached.

**What the UNIQUE constraint became, which is the part E23 never had to answer.** Two partial unique
indexes:

```sql
CREATE UNIQUE INDEX idx_favorites_user_tree   ON favorites(user_id, tree_uuid)   WHERE user_id   IS NOT NULL;
CREATE UNIQUE INDEX idx_favorites_device_tree ON favorites(device_id, tree_uuid) WHERE device_id IS NOT NULL;
```

One owner cannot favourite a tree twice; two different owners can each favourite it. The obvious
one-line alternative, `UNIQUE (user_id, device_id, tree_uuid)`, enforces **nothing** on the device
arm: SQL compares NULLs as distinct inside a unique index, so `(NULL, this device, this tree)` would
be storable any number of times, and the constraint would look present in the DDL while doing half
its job. A single expression index over `COALESCE(user_id, device_id)` does work, and was rejected
because it puts two id spaces into one comparison and re-introduces the coalesced owner v3 refused;
two indexes state the two sentences separately. The cost is that an upsert names one conflict target,
so `applyFavoriteToggle` prepares one of two statements — which is not a guess, because the owner is
known at the call site. That is what exclusive ownership buys.

**The collision at sign-in, which is real and is now a merge.** A device favourites a tree that the
account it is about to claim had *already* favourited. Two rows then say one thing, and after the
claim only one owner exists — so the plain `UPDATE` would hit the user index and abort the whole
claim, meaning sign-in fails for the contributor whose grove overlaps most. `claimDevice` runs three
statements instead, each an UPDATE or a narrowly-predicated DELETE whose WHERE stops matching once
it has run:

1. **The later statement wins.** Where both hold a tree and the device's row is the more recent, its
   state, its `client_uuid` and its timestamp move onto the account's row. A favourite is a toggle
   event with a tombstone (BUILD-PLAN §4 and §6) and a toggle resolves by time: whichever the person
   said last is what they meant. So a device that un-favourited in June overrides an account that
   favourited in January, and an account that un-favourited in June overrides a device that
   favourited in January. Timestamps compare as strings because `SQLiteTimestamp` writes fixed-width
   UTC ISO-8601, where lexicographic order is chronological order.
2. **The superseded device row is deleted** — the one delete this table permits. Keeping it would
   leave the account and the device each holding a row for one tree, which is the permanent
   device↔account link exclusive ownership exists to prevent. The device's row is the one dropped
   rather than the account's because the account's may have an identity beyond this phone; the
   device's has never left it.
3. **Everything else moves**, as a reminder does: `user_id` set, `device_id` cleared, `user_id IS
   NULL` guarding against a claim by a different account stealing an attributed row.

**The tombstone trigger keeps its job and gains exactly one exception.** Its stated reason is that a
stray `DELETE` loses the un-favourite *event*, so the row comes back on the next sync from another
device. Step 2 above loses no event: it has just been folded onto the surviving row for the same
tree, in the same transaction. The trigger's `WHEN` clause permits precisely that case — a
device-owned row for a tree an account already holds — and refuses everything else, including a
device-owned row with no account row beside it, which `DataGates` now asserts so the exception cannot
quietly widen into a hole.

**Whether a memorial or a vacant site can be favourited: yes, and it is not gated.**
`TreeStatus.acceptsNewContributions` gates the visit, the photo, the check-in and the measure sheet,
and the property says why: those are observations of a tree that has to exist. A favourite observes
nothing — it writes to the person's grove, not to the tree's record, which is exactly why it is the
one non-append-only row in the model (DECISIONS §3.7) and why D1 had to kill the version of it that
was a public vote. The deciding argument is reversibility: **gating the write would make the toggle
one-way for anyone whose favourite tree is later removed**, since the same gate that refuses the
heart refuses taking it off. A rule that turns a reversible thing into an irreversible one is worse
than what it was preventing. It also costs nothing to allow, because a favourite adds no row anyone
else can read: the grove that lists it is the person's own.

Where the affordance actually is, stated exactly rather than reassuringly: 03 draws the quad row only
on the **warm** variant, so a vacant site — which renders cold, every one of the 12,518 in the seed
(E11) — never shows it, and the map sends a removed pin to screen 19 rather than to the profile
(E95). What E95 leaves open is that the almanac's rows and the visit flow can still reach
`.treeProfile` with a removed tree, and a *photographed* removed tree would then draw the quad row
with a live `Favorite` cell. That residual is E95's to close and is latent either way — no tree in
the shipped seed is removed (E93) — and under the reasoning above the heart is the one cell in that
row it would be safe to leave standing there anyway.

**The write path.** `FavoriteToggle` carries a `FavoriteOwner` instead of a `userID`, and
`RootView.onFavorite` hands the mutation to `FavoriteOutboxWriter`: durable in the outbox first,
attempted after, keyed on a client-generated UUID (ARCHITECTURE §4). Changing the payload's shape
cost nothing, which is worth stating once because it will not be free again — no build has ever
enqueued a `favorite_toggle`, precisely because this entry's bug meant there was nowhere to write it,
so there are no rows on any disk in the old shape. `outbox.kind` already carried `favorite_toggle`
from v1, so no outbox rebuild was needed.

**What else now reads a device-owned favourite.** `groveTreeIDs` read favourites only when a user was
present, which is what made the absence invisible; it now reads both arms, like its own visits arm
and like `privateReminders`. `DeviceContributions` gains `favorites` and loses
`favouritesAreAccountOnly` — screen 15's headline still counts visits only, so no drawn sentence
changes, but the type's claim that these are "exactly the record kinds `claimDevice` moves" is true
again.

**Where favourites are still not visible, and why nothing was built for it.** Screen 08 is the
*Species* tab of My Grove: a progress ring and species tiles, and it never shows a favourited tree.
The surface that would is the `Trees` pill beside it, which E46 records as drawn and inert because
the screen behind it belongs to the clickable prototype and is not in the mock set. `CypressAPI
.grove()` — the read that returns favourited and visited trees, and which now returns the device's —
still has no caller anywhere in the app. Building the Trees list would be inventing a screen
(DECISIONS constraint 21), so it was not built; the read is correct for the day somebody draws it.

Proven by `CypressTests/FavoriteTests.swift`: a favourite saves with no user present and is owned by
the device, and reaches the grove and the device holdings; two taps of one heart save one favourite;
migrating a v4 database preserves live rows and tombstones alike and the migration replays as a
no-op; `claimDevice` adopts device-owned favourites, claiming twice changes nothing and nobody else's
moves; the sign-in collision merges in both directions and leaves one row per tree; uniqueness holds
per owner on both arms; a replayed toggle does not flip the state and an un-favourite tombstones
rather than deletes; a removed tree can be favourited and, more to the point, un-favourited.
`DataGates` adds the schema invariants: an ownerless or doubly-owned favourite is rejected by the
engine, a second row for one owner and one tree is rejected on both arms, two owners holding one tree
is accepted, and the tombstone trigger still refuses every delete except the adoption merge.

**One thing this hands to whoever builds account deletion**, unchanged from E23 and now true of a
second table: DECISIONS §3.12 anonymizes attributed rows — "user_id nulled, device link severed" —
and an exclusively-owned row cannot survive both. That path has to choose, for reminders and
favourites alike, between deleting them with the account and re-homing them onto the device. **OPEN.**

### E90 — 15's consent box has no unchecked state, and no rule for what refusing it means — OPEN

SCREENS.md 15 says "**States:** checkbox drawn checked. **NOT SPECIFIED:** unchecked styling,
dismissal gesture." Two gaps, and only one of them is visual.

**The styling** is answered with the smallest possible thing: the same 20pt box, without the glyph.
Nothing else moves.

**What refusing the licence means is not answered, and is not this screen's to answer.** The three
sign-in buttons stay live when the box is unchecked, because 15 states no rule that they should not
and a disabled primary CTA would be inventing one. The answer travels on `AccountLinkRequest
.acceptsLicense`, so an account can record honestly that nothing was agreed to — `User
.licenseVersion` is optional and `hasAcceptedLicense(version:)` already returns false for a nil.

What nobody has decided is what a contribution carrying no licence consent may then be used for. D12
pins `verification_state` into the export and BUILD-PLAN §5 pins the export's headers, and neither
says anything about a row whose contributor declined the ODbL. The plausible answers — exclude those
rows from the export, or refuse the sign-in until the box is ticked — are a licence decision and a
product decision respectively, and both belong to whoever owns the licence declaration.

### E91 — 15's logo is not in the bundle, and its map backdrop is drawn with the pins the app has

Two small substitutions on screen 15, both recorded because they are visible and neither is worth a
resource or a component to fix:

- §1 specifies "40×40 Cypress logo PNG". There is no logo in `Cypress/Resources` and no asset
  catalogue; `mocks/assets/logo-192.png` exists in the repo but is not a build input. The mark is C21
  `LeafGlyph` — "the app's only bespoke mark" — at 40pt. Swapping in the artwork is one line at the
  call site.
- The frame's three pins are specified as 16×16 in `#4E8F6A`. `MapPin.cityTree` is 18pt in Canopy
  `#2F6B4F`. The backdrop is decorative — C18's own header calls the stylised grid the replaceable
  half of the seam — so the component that means "a tree on the map" was used rather than adding a
  fourth pin kind for a layer that is behind a scrim.

### E92 — `trees` records that a tree was removed and nothing about when or why — OPEN

Screen 19 draws four claims that need a removal date, and one that needs a removal reason:

| SCREENS.md 19 | needs |
|---|---|
| §2 `Removed by the city, May 2026.` | the date |
| §3 `… · 2003–2026` | the year |
| §6 `On record · 23 years` | the year |
| §4 `City record · marked removed · storm damage` · `May 2026` | the date **and** a reason |

BUILD-PLAN §4's `trees` carries `status`, `created_at` and `updated_at`, and nothing else that could
answer either. `updated_at` is not the date: it moves on any write, so reading it as a removal month
would put a date on screen that a later species correction could silently change.

So all five clauses are withheld. The banner reads `Removed by the city.`, the identity line stops
after the scientific name, the `On record` card does not render, and the timeline has no city-record
row. `MemorialFacts` is the seam — one optional date, `nil` today, threaded through the presentation
so every one of those sentences already knows how to be written both ways, and both ways are
previewed.

**What a decision-owner has to settle** is which of two sources fills it, because both are schema
work (DECISIONS constraint 20):

1. **`trees.removed_at`**, set by the weekly diff (BUILD-PLAN §7). Direct, exportable, and answers
   for every removed row including the ones nobody ever visited.
2. **The confirmed `review_flags` row.** §7 opens `removed_but_active` for exactly the trees with a
   timeline worth memorialising, and the moment a moderator confirms it *is* the moment the status
   changed. It needs no new column, but it answers only for trees that had community activity, and
   it needs `TreeProfile` to carry the flag.

The reason has no candidate at all. `review_flags` has a `kind` and no free text, and DataSF publishes
no removal cause, so `storm damage` is a sentence the mock can say and the record cannot. It is not
written, on the same principle that keeps invented botany out of the species pages (BUILD-PLAN §15).

### E93 — no tree in the shipped seed is removed, so screen 19 cannot be reached

The seed holds 182,791 `alive` rows and 12,518 `vacant_site` rows. There are **no `removed` rows at
all**, and there is no path in the app that can create one: a tree becomes removed either through the
weekly city diff (BUILD-PLAN §7, not built) or through a moderator confirming a review flag
(DECISIONS §3.7, a web surface that is out of scope for iOS per ARCHITECTURE §8).

Two consequences worth stating plainly:

- **Screen 01's memorial pins have nothing behind them.** The caption promises "removed trees draw as
  gray dash-marked pins, memorials, tappable to screen 19", `MapPin.removed` is built and correct,
  and no pin on any device will ever take that kind today.
- **Screen 19 is verifiable only from fixtures.** Its previews build SCREENS.md's own Judah Street
  Gum by hand out of real record types. That is not a shortcut around a missing screen; it is the
  only way to see the drawn state, and it is worth knowing when reading the previews.

This is the same shape as E63 (nothing routes to screen 11 because the seed carries no measurements)
and E24 (nothing opens screen 05). The screen is built because the record type demands an answer for
the state, not because the state is reachable.

### E94 — 19's timeline is four kinds of moment, and the spec gives one instance and no rule

SCREENS.md 19 §4 draws four rows: a first photo, a visit, a check-in, a city-record sync. It does not
say what selects them, and the obvious reading — "the four most recent rows, as on screen 03" — is
contradicted by its own first row, which is the *oldest* thing on the tree, and by its ordering,
which runs Mar 2019 → Jan 2026 → Mar 2026 → May 2026 while 03's feed runs newest first.

What was built is the reading that needs the least invention: four **kinds** of moment rather than
four slots in a feed — the beginning, the last time somebody came, the last time anybody looked
closely, and the end — each present only when it happened. A memorial reads as a life, which is also
why it is chronological. This is a judgment call and is recorded as one.

Two smaller decisions inside it:

- **A8's 24-month window is not applied here.** A8 wrote it for a living tree, where "who knows this
  tree" is a question about now. A tree removed in 2026 would score zero caretakers within two months
  of its own memorial being read, and §4's clause (`six people came to know it`) is past tense and
  about the whole life. The window is the tree's life; the floor of three is kept exactly.
- **A8's rule now exists in two presentations**, `TreeProfilePresentation.caretakers` and
  `MemorialPresentation.caretakerCount`. One feature's presentation type reaching into another's is
  the sibling dependency ARCHITECTURE §3 keeps out of `Features/`, so the rule is stated twice rather
  than shared badly. If a third screen needs it, it should move — `Core` is the obvious home, since
  A8 is a product rule rather than a screen's.

### E95 — screen 19 has no route, and the only surface that knows a tree is removed is the map

`Route.treeProfile(UUID)` is annotated "03 (14 when the tree is cold, 19 when removed)", so the
original intent was one destination resolving all three. That works for 14, whose variant is decided
*inside* `TreeProfileView` after the read. It does not work for 19, because 19 is a different screen
with different copy, a different hero and no affordances — deciding between them after the read would
put one feature in charge of constructing another's view.

The entrance SCREENS.md actually draws is a map pin, and the map already holds the fact: `TreePin
.status` travels on every pin, `MapPinKind` already renders `.removed` as the gray dash-marked
memorial, and `MapHomeView`'s selected-tree card is one `router.push` away from either destination.
So the wiring is three small changes, in two files this task does not own:

1. **`AppRouter.swift`** — add `case memorial(UUID) // 19` to `Route`.
2. **`RootView.swift`**, in `destination(for:)` — add
   `case .memorial(let id): MemorialView(treeID: id, api: data.api, onBack: { router.pop() })`.
3. **`MapHomeView.swift`**, in `bottomSlot` — push `.memorial(subject.pin.id)` when
   `subject.pin.status == .removed`, and `.treeProfile` otherwise.

`MemorialView` needs no router of its own; it takes `onBack` as a closure, the way `AlmanacView`
does.

**The residual, which the above does not close:** other paths into `.treeProfile` — the almanac's
elder and bloom rows, the visit flow's "open tree" — can reach a removed tree, and `TreeProfileView`
will draw it as a profile with a `REMOVED` badge and a live `Visit · say hello with a photo` CTA.
That is a read-only tree offering a write, which is the one thing 19's "read-only enforcement" note
exists to prevent. Closing it means either routing on status at every push site, or having
`TreeProfileView` refuse a memorial tree the way `MemorialModel` refuses a living one. The second is
one line and one screen's decision; it is not made here because it belongs with whoever applies the
routing above. Nothing is currently reachable through those paths on the shipped seed (E93), so this
is latent rather than live.

### E96 — a memorial link can arrive at a tree that is still standing

`trees.status` can move in both directions: a moderator confirms a review flag, and a moderator can
dismiss one. A link, a pushed route, or a stale map read can therefore arrive at screen 19 for a tree
that is not removed.

**NOT SPECIFIED**, and it cannot be silently redirected to screen 03 — that would be this feature
constructing another's view (ARCHITECTURE §3), and would leave a memorial link opening a living
profile with nothing to explain it. `MemorialModel.Phase.notMemorial` is its own case, distinct from
`.failed`, and the screen says `This tree is still standing.` and offers nothing.

It is a case rather than an error on purpose: "this tree is not removed" and "this profile could not
be loaded" are different facts, and this is the screen where conflating them would be worst.

### E97 — screen 16 has no state after the save, and screen 18 is not it

SCREENS.md 16 ends at its CTA. Nothing says what the sheet does once `Save measurement` is tapped,
and the obvious neighbour is not a candidate: screen 18's success block reads `Check-in saved` and
its whole content is "which tree is next" on a route, which is a different flow from standing at one
trunk with a tape.

So the sheet stays open, the entry clears, and the reading it just wrote becomes the sanity pill's
anchor: after saving `64 cm` the pill reads `Last recorded 64 cm, <this month>`. That is a real
receipt — the number is visibly on the record now — and it is what a second reading on the same
standing needs, because DBH and height are two separate saves and a volunteer taking both would
otherwise have to re-enter the screen between them.

It is also thin. There is no confirmation, no toast and no exit, and a contributor who taps once and
looks away has only a changed pill to tell them it worked. A designed post-save state for 16 is a
real gap; inventing one, or borrowing 18's, is what DECISIONS constraint 21 forbids. **OPEN.**

### E98 — six screens had no entrance, and the entrances were invented under a one-time authorization

**This entry is the authorization and its boundary. Read it before overruling anything it covers.**

Six built, tested, routed screens had no affordance anywhere in the app that opened them: **05**
(E24), **11** (E63, whose entrance existed and could never fire), **12** (E57), **13** (E66), **16**
(E74) and **17** (E75). Every one of them was recorded rather than fixed, and correctly so —
DECISIONS constraint 21 says an unmocked affordance is a question for design, not a case to invent,
and six entries in this file say exactly that.

**The project owner granted a one-time, explicit exception covering these six entrances and nothing
else.** It does not cover new screens, new states, new data, new copy beyond a short label, or an
affordance for anything else. Everything invented under it is marked in code and listed here, so any
of it can be overruled without archaeology.

**What was invented, and where the decision lives:**

| Screen | Entrance | Decided in |
|---|---|---|
| 05 · Check-in | C7 outline button under 03's primary CTA, `Check in · under a minute` | `TreeProfilePresentation.checkInCTATitle` |
| 13 · Activity | `See the whole year` link under 03's activity feed | `TreeProfilePresentation.activityLinkTitle` |
| 16 · Measure | an *empty* measurement stat card on 03, `Add a reading` | `TreeProfilePresentation.StatDestination` |
| 12 · Almanac | the Journal tab renders it as the tab's root | `JournalTabView` |

**What was specified and only looked invented:**

- **11 · Growth history.** `DBH/Height cards → 11` is drawn in SCREENS.md 03's affordance list and
  was built long before this round. It could not fire because nothing in the app could write a
  measurement (E63, E74). One control now carries both directions — a reading opens its history, an
  empty slot opens the sheet that writes one.
- **17 · Outbox.** BUILD-PLAN §9's M2 list names "the You tab (profile, settings, **outbox entry
  point**, privacy toggles)". The row is that sentence. Only the tab's layout is new (E100).
- **12's placement in the Journal tab.** BUILD-PLAN §12 groups the almanac and the journal in one
  layer and one acceptance line; making the almanac the tab's *content* is the invented half.

**Three rules constrained every one of them, and each was checked:**

1. **A read-only record gains no write.** `TreeStatus.acceptsNewContributions` is false for a
   memorial and a vacant site, so neither is offered the check-in button or the empty measurement
   slot. Tested for every non-contributing status at once, and confirmed on device: a vacant site's
   stat grid is `Site` and `City record`, with no invitation to fill anything.
2. **§5.6 — a surface below its threshold renders nothing.** The activity link draws only where the
   feed draws, so no tree in the shipped seed offers a door onto screen 13's empty state (E67).
3. **§5.1 — no counts of user actions.** Nothing added here counts anything. The You tab in
   particular carries no visit count, no species tally and no queue count; screen 17's own header
   pill says how many items are waiting, on the screen that can also say why.

**One new component case was needed.** `StatCard.Value.placeholder(String)` renders an empty
measurement slot in `text.faint` rather than `text.ink`, exactly as screen 16's empty readout does
and for the same reason (E77): a value drawn in ink reads as a reading. It is the only change to
`DesignSystem` in this round.

**Visual verification.** Every entrance and every newly reachable screen was photographed in the
simulator against the bundled seed. Synthetic touch input was unavailable in the environment the
round ran in — the process was denied accessibility, so no click could be posted to the Simulator —
so the walk was driven through the same `AppRouter` the buttons drive, with the affordances
themselves photographed as they render. That is weaker than a finger and is recorded as such: what
was proved is that each affordance draws where it should and each destination renders behind it, on
real seed rows. The one full loop that was exercised end to end was the measurement: a DBH reading
written through the outbox turned the seeded tree's DBH card from the city's bucket into
`31 cm taped` and put a chart on screen 11 for the first time on any device.

### E99 — the Journal tab hosts the almanac and not the journal, and the journal list is still unbuilt

`CypressAPI.journal(cursor:limit:)` exists, returns `Page<JournalEntry>`, and is not called by any
screen. The Journal tab renders screen 12 (E57, E98) and nothing else.

**The list was not built, deliberately.** SCREENS.md draws no journal list — no layout, no row, no
empty state, no copy — and BUILD-PLAN §9 asks only for an "empty journal". Building one would be
inventing a screen, and the authorization in E98 covers entrances, not screens. The name of the tab
promising something it does not yet contain is the honest cost of that, and it is smaller than the
cost of guessing.

Two things whoever builds it will need, recorded now:

- **A page is not a series.** `journal` returns a `Page`, which carries `nextCursor` and no total.
  Nothing on that screen may print a count off it — E38 is the entry that explains what happens when
  something does.
- **D1 applies with unusual force.** A personal list of your own contributions, ordered by time, is
  one design decision away from a streak. `JournalEntry` carries no counts by construction; keep it
  that way.

**OPEN.**

### E100 — D11's privacy toggle is modelled, unstorable, and therefore stated rather than switched

BUILD-PLAN §9 asks the You tab for "privacy toggles". There is exactly one privacy toggle in the
data model — `User.publicAttribution`, D11's "contribution feeds private by default with opt-in
public attribution" — and **nothing can set it**:

- `AppSchema` has no `users` table. The local store carries `device`, `app_state`,
  `community_trees`, `visits`, `photos`, `observations`, `measurements`, `care_events`, `favorites`,
  `private_reminders`, `community_notes`, `review_flags`, `tree_names`, `outbox` and
  `hazard_redirects`, and no row anywhere that could hold the flag.
- `CypressAPI` has no method that reads or writes it.
- There is no account on any device the app runs on, because screen 15 cannot create one (E86).

A switch on the You tab would therefore be a control that forgets what it was told — worse than no
control, and the exact failure the outbox screen's footnote is written against. So the tab **states
the position instead**: `Private by default: everything you save stays on this phone. Public
attribution is opt-in, it is off, and there is nothing in the app yet that can turn it on.` Every
clause is checkable — the default is `false`, `LocalAPI` writes only to this device, and no code
path flips it.

The one setting that *is* persisted, `AppStateKey.syncPhotosOnWifiOnly`, is on the tab under
`Settings` and labelled as what it is. **It is not a privacy setting** — it decides when photo
binaries leave the phone, not who may see them — and it is deliberately not filed under the privacy
heading. It is the same `OutboxViewState` screen 17 binds, held once in `RootView`, because two
copies of one preference would agree only until somebody used one of them.

**OPEN**, and the thing that closes it is an account, not a toggle.

### E101 — the heart has an on state and nothing draws it, so the favourite is one-way — RESOLVED by RULINGS R2, built in E112

Falls out of E89, and is a gap in the mock set rather than in the fix. Now that a favourite can be
written, screen 03 needs an answer to two questions it never had to have one for, and SCREENS.md
gives neither:

- **What a favourited tree looks like.** C8's four cells are drawn once each — `Favorite` · `Care` ·
  `Share` · `Report`, 12px semibold on a card fill — and §2 C8's own NOT SPECIFIED note is about the
  *icons*, not about state. No selected variant, no filled heart, no colour change, no label change.
  Care, Share and Report open something, so a cell that changes nothing on the screen is the right
  drawing for them; a favourite changes only itself.
- **Where the heart comes off.** Nothing in the mock set un-favourites a tree. The `Trees` pill on 08
  that would list favourites is drawn inert (E46), 13 cut the favourites series outright (D2), and
  the profile draws one cell whose label is a noun.

So `RootView` writes `isFavorite: true` and never `false`. The tombstone path is real and tested —
the payload carries the resulting state rather than a verb, the store toggles through `deleted_at`,
and `claimDevice` merges an un-favourite across sign-in — but no drawn control produces one. **A tap
is a statement that can be made and not taken back**, which is the shape of thing DECISIONS §3.7 went
out of its way to avoid for exactly this record: favourites are the one contribution the model allows
to be reversed.

Two smaller consequences, recorded so they are not read as bugs:

- **The tap says nothing back.** E23's answer for screen 06 was one line of copy after the save, on
  the argument that a control which acts and says nothing is dishonest in the other direction. The
  same answer here would be a state on a mocked component, which is a design change rather than a
  view file's decision (DECISIONS constraint 21). `RootView` therefore claims nothing: the write is
  fire-and-forget and its error is dropped, because there is no drawn state in which the screen could
  honestly report one.
- **A second tap is deliberately not a second event.** The composition root keeps the client UUID it
  minted for each tree, so an impatient double tap replays one key and stores one favourite — the
  trick screen 06 plays with `PrivateReminderDraft.reminderID`. Without it a control with no visible
  on-state would queue one "favorited" event per tap, all true and all pointless.

What a decision-owner owes this screen: a selected appearance for C8's first cell, or a surface that
lists favourites and can remove one. Either closes it; neither may be invented here.

**RESOLVED — the first of the two, under RULINGS R2, built and recorded in E112.** C8's first cell has
a selected appearance and a second tap removes the favourite. Read E112 before trusting the two
"deliberate" notes above: both of them were consequences of this entry's own gap rather than
independent decisions, and both are reversed. The write is no longer fire-and-forget — the state
reverts, which reports the failure without needing a drawn error state — and the replayed client UUID
is retired, because with an on-state the second tap is a different statement and a reused key turns
un-favouriting into a silent no-op against `applyFavoriteToggle`'s replay guard.

### E102 — the six named animation curves were in the handoff and not in the spec, and three literals had drifted in their place

SCREENS.md §5 gap 1 lists animation as **NOT SPECIFIED** and then names six curves it does not
define: `czFade` .32s, `czSheet`, `czPinDrop`, `czPulse` 2.4s, `czFlash`, `czPop`, easing
`cubic-bezier(.22,.9,.3,1)`. ARCHITECTURE §1 cites "six named animation curves" as part of the
written reason for building native. Nothing in `docs/` carried their definitions.

They are in the handoff. `_unzipped/design_handoff_cypress/Cypress Prototype.dc.html` lines 17–22
hold the `@keyframes`, and `README.md` line 119 holds the names, the durations and the instruction
"Keep them subtle." Two easings appear in the `animation:` shorthands and nowhere else — the house
deceleration `cubic-bezier(.22,.9,.3,1)` and an overshoot `cubic-bezier(.22,1.18,.36,1)` whose
second control point sits above 1. Both transcribe onto `Animation.timingCurve`, which takes the
same four numbers, so nothing here is a fit or a guess.

**What existed before this pass:** three animations, all literals in `Features/`, none matching each
other. `MapHomeView` recentred on a fix with `easeInOut(0.4)` and zoomed into a cluster with
`easeInOut(0.35)`; `MapKitBasemap` scaled a selected pin with `snappy(0.18)`. ARCHITECTURE §6 bans a
raw hex or font size inside a feature and a duration is the same kind of literal — with more force,
because six curves used in eleven places drift apart the moment each place owns its own number.

`Cypress/DesignSystem/Tokens/CypressMotion.swift` is the transcription, and it carries the keyframe
*offsets* beside the curves (`CypressMotionOffset`) so a caller cannot animate the right duration
through the wrong distance.

**Where each applies, and the two that deliberately do not.**

| Curve | Applied to |
|---|---|
| `czFade` | 02's candidate cards, staggered 0.07 s apart as they arrive; the scrim under C17 |
| `czSheet` | C17 `BottomSheet` — 09, 10, 15 — rising 90 pt |
| `czPinDrop` | 18's `VisitRouteMap` pins, staggered down the route |
| `czPulse` | C19's `needsCare` pin, everywhere it is drawn, including 01's live MapKit layer |
| `czFlash` | 04's shutter |
| `czPop` | 18's success check; 05's selection check, keyed on which row is selected |

`czFade` is **not** applied to screen roots, which is where the prototype puts it. A static HTML
prototype draws a navigation push that way; `NavigationStack` already animates the push, and a
second fade over the system transition is two animations for one event. SCREENS.md §5 gap 1 lists
navigation transitions as NOT SPECIFIED and nothing is invented for them.

`czPinDrop` is **not** applied to screen 01's pins. They are `Annotation`s inside a live `Map` that
recycles them on every camera change, so a per-pin appearance animation fires continuously during a
pan — the same class of problem `MapHomeView.bottomSlot` already documents, and left alone for the
same reason. `czPulse` *is* safe there and is applied: a continuous loop has no "first appearance"
for a recycle to re-fire. `bottomSlot` itself is unchanged and still has no transition.

**Two tokens that are not among the six.** `CypressMotion.camera` and `.selection` replace the three
literals above. A camera move is the same gesture as `czFade` — a thing settling into place — so
both take the house easing rather than a seventh curve being invented for them.

**Reduce Motion.** Every curve resolves through `CypressMotion.resolved(_:reduceMotion:)`, which
returns `nil` rather than a shorter curve: `Animation` has no "off", and `nil` is how SwiftUI is told
to apply a state change without one. A faster animation is still an animation. What Reduce Motion
does *not* remove is a final state — a pin that drops is at rest in the same place either way, and
the amber pulse still draws its ring at a resting radius, because the meaning is in the colour and
the motion was only emphasis. `AccessibilityTests` pins that every named curve can be switched off.

### E103 — every label on a bare `Shape` was silent, and three of them were the app's visual encodings

Three components carried `.accessibilityLabel` on a view that is not an accessibility element, so
the label attached to nothing and VoiceOver read past it. A `Shape` — `RoundedRectangle`, `Circle`,
a `GeometryReader` containing only fills — is not focusable, and a label on one is not an error at
compile time or at run time. It is invisible in both directions: the source says the component is
labelled, and the device says nothing.

- **C3 `FoliageStrip`** (`FoliageStrip.swift:156`) labelled each of twelve `RoundedRectangle` cells.
- **C23 `LineChart`** (`ChartCard.swift:209`) labelled each data dot, which is a `Circle` in a
  `Group`.
- **C28 `ConfidenceBar`** (`ProgressRing.swift:100`) labelled a `GeometryReader` of two fills — and
  was then silent twice over, because the 02 candidate row that hosts it applies
  `children: .combine`, which walks a subtree that had no element in it to collect.

All three now take `.accessibilityElement(children: .ignore)` before the label. What changed with
them is what the label *says*, because a working per-cell label would still have been the wrong
shape for the information:

- **C3 speaks the year in runs, not months.** `full canopy January to February, partial canopy
  March, thin canopy April to May, …` — five clauses where there were twelve stops. The strip is a
  picture of one sentence (when this tree carries leaves) and a spoken equivalent has to be that
  sentence. D5's clamp reaches the spoken form because the label is built from the clamped
  densities: an evergreen cannot announce a bare month any more than it can draw one.
- **C23 speaks one clause per series and never one across both.** `2 readings measured with a tape:
  58 cm to 64 cm. 2 readings estimated: 47 cm to 52 cm.` D7 is not only a drawing rule — a summary
  running from the oldest estimate to the newest tape reading manufactures the same trend the
  forbidden polyline would, in words. The per-point dots are deliberately not elements: screen 11
  lists every reading underneath in its measurement log, one stop each, carrying the value and its
  badge.
- **C28 speaks its qualification.** `Nearest tree match, 88 percent, from GPS distance alone.`
  `VisitShortlist.confidence` is explicit that this is distance geometry against the fix's own
  error, not a species certainty. A sighted user reads that off the screen around the bar, which is
  drawn under a card headed `CONFIRM BY EYE` beside a distinguishing trait; a listener had a bare
  "Confidence 88 percent".
- **C27 `ProgressRing`** was not silent but said the same number two ways: `label ?? "N percent"`
  read the glyph `30%` when a caller passed one and the sentence "30 percent" when it did not. One
  phrasing now, and the 08 call site hides the ring outright — it sits beside "12 of 40 species you
  can recognize in the Outer Sunset", which is the same fact in better words.

**C23's `BarChart` took the opposite fix: its label is a required initialiser parameter.** The
component cannot write this one and must not try. `heights` are drawing units in the mock's 0…34
viewBox, already scaled against a maximum the caller chose — and on screen 13 that maximum is shared
across three series so the rows can be compared (D2). Reading a height back out would announce a
fraction of someone else's maximum, which is a wrong count rather than no count. C25 `CypressToggle`
was already the only component in the catalogue that forces a label at the call site; C23's bar row
is now the second.

**C12 was already right and is worth saying so.** `taped` speaks as "measured with a tape" and
`est.` as "estimated", and `MeasuredValue` combines the number with its badge into one element so no
navigation order can put a bare value in a listener's ear. That is D7 surviving into a modality it
was not written for. The generator is now internal rather than private, because C23 names a series'
method and has to name it the same way.

### E104 — a component that renders nothing was announcing itself, which is §5.6 inverted

ARCHITECTURE §5.6 and DECISIONS constraint 1: an aggregate surface below its cold-start threshold
does not render at all. The rule was being kept at the presentation layer — `TreeProfilePresentation`
returns no `Caretakers` below three, so screen 03's regulars row does not exist — and broken one
level down.

**C26 `AvatarStack` carried an unconditional `.accessibilityElement(children: .ignore)` plus the
literal "Regulars".** With no bubbles in it that is a focusable empty box that says a row exists.
And no bubbles is the shipping case: E71 records that the API hands caretakers over as bare UUIDs
with no initials to draw, so the stack renders one `+6` overflow bubble at most and frequently
nothing. Sighted users saw no row; listeners were told there was one.

Two changes. The stack is `accessibilityHidden` when it has nothing in it, and when it does have
something it says what it drew — `Regulars: N, M, J, 3 more` rather than the noun, and `+6` speaks as
"6 regulars" rather than as a glyph. Separately, screen 03 hides it at the call site: the bubbles and
the headline are the same fact twice, and "Six people know this tree" is the better half.

The same principle produced the rest of the decoration pass, which is one rule applied consistently:
**an element that duplicates adjacent text is not an element.** C2's hero photograph and its scrim
(the eyebrow, the name block and the pill on top of them are the content); C22's thumbnail gradients
when they are not tappable, because SCREENS.md §5 gap 13 says outright that every image in the spec
is a CSS gradient placeholder and every shipping call site draws one beside the name of the thing it
stands for; C16's hand-drawn tab icons, which sit directly above their own labels; C23's legend
swatches, which are the colour key for the row that names itself in the same breath. `AccessibilityTests`
pins the empty case, the §5.6 threshold and `Series.totalCount`'s nil.

### E105 — Dynamic Type: the ramp scaled and six layouts did not

Every font already used `.custom(_:size:relativeTo:)`, so the type scaled correctly everywhere. What
had never been looked at is what the type scales *into*. Rendered at `.xSmall` and
`.accessibility5` through `UIHostingController` (see the note below), six layouts broke, and the two
worst were not the fixed frames the audit expected.

**The two structural ones, both the same bug in two places.** A row of `[thing] [growing text]
[`.fixedSize()` thing]` gives the text whatever is left, and at AX5 that is nothing.

- `ScreenHeader.swift` (C1) — `[back circle] [title] [pill]`. At AX5 the circle takes 44 pt, `under
  a minute` takes ~300, and the 22 pt serif title gets ~60 — into which it wrapped **one letter per
  line**. Screen 05 rendered as a vertical column spelling `C-h-e-c-k-–-i` down the whole viewport
  with the card pushed off the bottom. This is C1, so it was every screen with a header pill: 02, 05,
  06, 11, 12, 13, 14, 16, 17 and D3.
- `TreeProfileView.swift` identity block — `[27 pt tree name] [StatusBadge]`, same cause, and
  `Grandmother Cypress` wrapped three characters at a time.

Both now stack above the accessibility sizes. Neither truncates and neither scales down: the pill is
real information on every screen that has one and the title is what the screen *is*, so at a size
where both will not fit across, one goes under the other.

**The other four.**

- `SegmentedControl.swift` (C5) — four segments across 393 pt at AX5 rendered `Alive | Decli… |
  Appe… | Rem…`. "Appears dead" and "Removed?" are different claims about a tree and a 0.8 scale
  floor does not save them. Stacked above the accessibility sizes; the 1 pt divider becomes a
  horizontal rule.
- `OutboxView.swift` — the row is `[38 pt tile] [title/detail/reason] [state]` and the detail line is
  three text pieces in an `HStack(spacing: 0)`. At AX5 they interleaved: `2 phot / os, a / note`
  running down the left with `11:42 am` overprinting it. Detail line stacks; the state word moves
  under the row rather than beside it; the 38 pt tile's mono reading gains the `lineLimit(1)` it
  needed for `minimumScaleFactor` to do anything at all.
- `Chip.swift` (C4) — the background is a `Capsule`, which rounds by half the *shorter* side, so 16's
  sanity pill wrapped to four lines was drawn as a circle with the text spilling out of both ends.
  Above the accessibility sizes the shape becomes `radius.card.sm`. This is a shape change to a
  mocked component, taken deliberately: SCREENS.md draws these at one line and has no state for a
  chip that has wrapped, and holding the capsule means keeping the drawn shape and the wrong picture.
- `TreeProfileView.swift:179` — 14's empty photo well was `height: 170`, a hard cap around a sentence
  that needs four lines at AX5. Now `minHeight`, which renders identically at the drawn size.
  `HeroPhotoHeader.swift` had the same shape of problem with a different mechanism: the eyebrow, the
  07 name block and the meta pill were `.overlay`s on a fixed-height photo, and an overlay does not
  contribute to its parent's height, so at AX5 the 25 pt serif species name simply drew past the
  bottom edge onto the strip below. A `ZStack` with the photo on `minHeight` makes the content a real
  child; nothing moves at the drawn sizes.

**What deliberately does not scale, and why.** `cypressTypographicFurniture()` caps Dynamic Type at
`.accessibility1` — not at `.large`, because the point is to keep these legible for someone who needs
larger type rather than to freeze them at the mock's size. It is applied to four things and to
nothing that is a sentence:

1. **The mono micro-labels with wide letter-spacing** (`cypressMicroLabel`, `cypressMicroLabel10`,
   `cypressMonoSectionLabel`, `cypressMapLabel`). There is a concrete failure behind this and not a
   preference: `CypressFont.Tracking` is in *points*, fixed at the mock's size, and its own note says
   tracking is intentionally not scaled. So an unclamped 9.5 pt label at AX5 renders ~3× with the
   same 1.33 pt of letter-spacing — the wide tracking that makes it read as a rule is gone and what
   is left is large cramped uppercase.
2. **The twelve month letters** under C3's strip and C23's axis. Twelve letters at AX5 need more
   width than any iPhone has, at which point they stop lining up with the twelve cells above them —
   and that alignment is the entire information in a season strip.
3. **The count inside a map pin** (C19). A pin is positioned by coordinate on a map that cannot
   reflow around it.
4. **C16's four tab labels.** `My Grove` and `Journal` at AX5 need more width than the bar has, and
   the 0.8 scale floor turns them into specks rather than letting them overflow. This is the call
   Apple's own tab bar makes and it is only defensible because the bar is not where anything is
   read: four destinations, each opening a screen that scales the whole way.

A tap target is the fifth thing that does not scale, and it was already right — `cypressHitArea()`
grows the hit area to 44 pt without moving the drawn size, which is ARCHITECTURE §6's rule, and 44 pt
is 44 pt at every text size.

**05 at the extremes, measured rather than guessed.** At `.xSmall` the whole card — five anchor rows,
both segmented controls, the chip row and the optional well — fits above the fold with room to spare.
At `.accessibility5` the card is 3,114 pt against a 852 pt viewport: one anchor row and part of a
second are visible, and the optional well is roughly two and a half screens down. The long rubric
anchors are D3 content and are not shortened (E30). What the number says is that 05's known
tightness is a scroll depth, not a clipped layout — nothing on it is cut off at either end.

**A note on how the screenshots were taken, because the obvious way is wrong.** `ImageRenderer` lays
a `ScrollView` out to whatever height is asked for and then draws *nothing inside it*, so 05 came
back as 3,114 pt of empty page with the sticky CTA at the bottom — which reads as "the card vanished
at AX5" rather than as "the renderer does not do scroll views". It also renders synchronously, so
every screen that loads through `.task` was captured mid-`ProgressView`. `DynamicTypeScreenshotTests`
uses a `UIHostingController` in an off-screen window and `await`s between layout passes;
`RunLoop.run(until:)` is not enough, because it does not drain the cooperative executor a `.task` is
suspended on.

### E106 — the contrast sweep: the caption ramp fails AA in both appearances, and nothing here re-tints it

> **Closed by RULINGS R1; see E108.** Five of the seven failures below were retinted rather than
> reassigned: `text.faint`, `text.faintAlt` and `text.muted` were re-spaced so all four rungs of the
> ramp clear their floors on every surface in both appearances, and the `est.` badge and the C24
> border were lifted over theirs. The 311 panel border, the C10 locked glyph and the C23 chart series
> are unchanged and still pinned. The ratios recorded in this entry are what those pairs read
> *before* that ruling; E108 carries the current ones.

ROADMAP M4 asks for "contrast verification on the amber family, which is the palette most likely to
fail". E8 already measured the amber family *after dark* and found it improves. This is the same
question asked in light — where nothing was derived and nothing was therefore checked — and asked of
every other drawn pair on the way past. `CypressTests/ContrastTests.swift` holds the sweep.

**The amber family clears AA in both appearances.** Pill text 5.18:1 light / 6.11:1 dark; selected
chip the same; 311 panel body 6.51 / 6.28; 311 CTA label 5.00 / 7.55; the phone glyph on Signal Amber
3.59 / 7.55. E8's finding stands and the light half is fine too.

**The rest of the palette clears it comfortably.** `text.ink` 13.8–15.0:1, `text.body` 7.9–9.4:1,
`text.muted` 4.6–7.0:1, the CTA label 9.1–10.6:1, every badge 4.8–7.3:1, the memorial banner 6.4–6.9,
and every map mark against the paper at 3.1:1 or better.

**Seven pairs fail, and they are reported rather than fixed.** Every light hex below is transcribed
from SCREENS.md §1.2 — not derived and not invented. E8's rule for a *derived* value is that it may
be corrected; the rule for a transcribed one is stronger, because changing it is overruling the
designer, and ARCHITECTURE §5.8 says an unanswered question is a question for design rather than a
value to pick. The ratios are pinned to ±0.05 in the test instead, so that a number getting worse and
a number quietly getting *better* both fail.

| Pair | Light | Dark | Floor |
|---|---|---|---|
| `text.faint` micro-label on the screen | **2.90** | **3.42** | 4.5 |
| `text.faint` micro-label on a card | **3.16** | **2.98** | 4.5 |
| `text.faintAlt` footnote on the screen | **3.67** | **3.42** | 4.5 |
| `est.` badge text on its fill (C12) | **4.19** | 6.11 | 4.5 |
| C24 attention card border on the card it identifies | **2.30** | 6.57 | 3.0 |
| 311 hazard panel border against the page | **1.82** | 7.55 | 3.0 |
| C10 species-tile locked glyph (E8, unchanged) | **1.84** | **2.12** | 3.0 |
| C23 series 1 / series 3 on a dark card (E8, unchanged) | 6.29 / 7.01 | **2.53 / 2.27** | 3.0 |

**The caption ramp is the finding.** It is not one badge — `text.faint` is every mono micro-label,
every timestamp and every meta line in the app, and it fails in *both* appearances. It is also the
easiest to answer: `text.muted`, one rung up, clears at 4.62:1 light and 6.97:1 dark, so the palette
already contains the fix and taking it is a visual change to nineteen mocked screens rather than a
new colour. That is a designer's call.

**The `est.` badge misses by a third of a point and is the one with meaning attached.** D7 makes
"estimated" the difference between a reading and a guess, and it is the half of the pair that is
harder to read — its partner `taped` is 6.08:1.

**The borders carry no contrast in light as a house style, not as a defect.** `border.cool`, the
default card edge on every screen, is 1.15:1 against the page; the amber panel fills are 1.05:1.
WCAG 1.4.11 asks for 3:1 only where a boundary is *required* to identify a component, and for almost
all of these it is not — a card is identified by the type in it. The exception is C24: the attention
card is `surface.card` on `surface.screen`, 1.09:1, so its 1.5 pt amber border is the only thing
saying "this one is different", at 2.30:1. That is the row to look at first.

Nothing in this pass changed a colour token. **Dark mode was not re-opened** — E8's derivation stands
and the only dark-mode observation to add is that `text.faint` on a card is *worse* after dark
(2.98:1) than in light (3.16:1), which is the one place the transform moved a ratio the wrong way.

### E107 — the vacant site is its own screen, and everything it can honestly offer is a statement rather than a write (closes E11)

E11 left 12,518 rows — 6.4% of the map — rendering as screen 14 with the photo well and the CTA
deleted, and called that a placeholder rather than an answer. ROADMAP §1 took the decision that a
site gets a state of its own, on the grounds that modelling it as a degraded tree is what produced
the wrong copy in the first place, and flagged the surface itself for design. This entry is what was
built under that delegation and what a designer would overrule to change it.

**The screen is `Cypress/Features/Site/`, reached by `Route.site`.** It is split into `SiteView` and
`SiteScreen` for the reason screen 19 is: a layout whose content arrives after an `async` read cannot
be photographed offscreen. Its entrance is the map card, beside the memorial branch that screen 01's
own caption draws, and it is composed entirely from C1, C10, C11 and C14 — no new component, and no
variant of one.

**What it says, in four blocks.** A C1 header titled `Site`, which is 14's `Tree` with the noun
corrected. An identity block whose H1 is the street address, because a site has no species and no
name and the address is the only thing that identifies it, over an italic line reading
`Vacant planting site · SF city inventory`. A C14 **dashed** callout — the design's own vocabulary
for absence, which is what 14's empty well, C15 and 06's disclosure all use — saying `No tree at this
site.` and then that Cypress keeps the record of what is planted and does not plant. A C11 grid of
what the city actually recorded: the `qSiteInfo` string verbatim, the citable `SF #` reference, and
the neighbourhood when the payload carries one. No `StatusBadge`: C13 has three kinds, and the only
one that could fire here is `PLANTED <year>`, which would assert a planting on an empty basin.

**What it offers is one row, and the finding underneath that is the entry.** Every contribution this
app can express asserts a tree. A visit is a photograph of one, an observation carries a vitality
rating of one, a measurement measures a trunk, a care event waters something living, and the private
reminder — the one write that is neither public nor a contribution in RULINGS R3's sense — requires a
`HazardCategory`, whose four values are a hanging limb, an uprooting, a vehicle strike and a blocked
sightline. There is no vocabulary in the schema for a statement about a *site*. So the screen offers
no write at all, and that is not a degraded memorial: it is the honest shape of a record this app's
own vocabulary has nothing true to say about. What it offers instead is a C10 row naming **the
nearest standing tree** and its distance, which pushes screen 03. That is a true statement about the
site made out of facts the record already holds, it promises nothing, and it turns the one screen in
the app with nothing to do into a place you can leave in the direction of a real tree. The claim
`the nearest tree` survives the query's `LIMIT` because `TreeQueries.nearest` returns rows in
ascending distance: a standing tree the limit dropped is farther than every row it kept.

**Two affordances were considered and declined.** The favourite would work — `FavoriteTests` already
records deliberately that a vacant site can be favourited — and it is the only writable statement
left that asserts nothing about a tree. It is not offered because the only control that would carry
it here is C7, which has no selected appearance, and a heart that cannot show that it is on is the
defect RULINGS R2 has just closed on C8. Reopening it on a brand-new screen to gain one control is a
bad trade. A link to the almanac was the more tempting one, since E11's own question is whether a
site is the coverage gap D1 points at; it is not offered because `Route.almanac` carries no
coordinate and `AlmanacView` reads the *reader's* fix, so the link would silently change subject on a
site the reader is nowhere near.

**Three things were found on the way and are not fixed here.** `AlmanacQueries` excludes vacant sites
by construction — its `JOIN` to species is inner, which is what drops them — so the surface E11
nominates as the one that should be pointing at these 12,518 rows is currently the surface that
cannot see them; that is a query change in a file this task did not own, and it is the first thing to
look at if the coverage-gap reading is the one design wants. **The mechanism in that sentence is
wrong and the conclusion it invites does not survive checking: see E115.** The inner join is not what
drops a site — `AlmanacQueries.standing` is, deliberately — widening it admits no site at all and
empties the screen, and D1's coverage panel turns out to be about gaps in *observation* rather than
gaps in the canopy. E115 fixes the one read that really was wrong (`firstBloom`, which applied no
status filter at all) and proposes the block screen 12 would need, rather than inventing it.
C19 has no pin for a site, and the map
therefore still draws one as `removed`, a grey dot with a bar struck through it, which says *was and
is no longer* about a basin that never held a tree; a new pin is a drawn decision and was not
invented, so the distinction is carried by the card and by the VoiceOver label instead — the card now
titles itself `Planting site`, drops the badge that would have said `PLANTED`, and leads its meta
line with `no tree at this site`, and the pin announces itself as a planting site rather than as a
memorial. Entrances other than the map — the visit flow's nearest-candidate list, a stale link — still
land a vacant site on the degraded profile, because `TreeProfileView` is where that redirect belongs
and it was being edited elsewhere.

**What a designer overrules to change this.** The copy is all in `SiteCopy`; the layout is
`SiteScreen`; whether the nearest-tree row exists at all is `SitePresentation.neighbour`; and the
decision to route the map card here rather than at screen 14 is three lines in `MapHomeView`. If the
answer is that a site should be able to say something about itself, that is a new outbox payload, a
new table and a moderation path — a schema decision (DECISIONS constraint 20), not a screen's.

### E108 — the caption ramp is retinted under R1, and five of E106's failures close

E106 swept every drawn pair for WCAG AA and found seven failing, and it fixed none of them, because
every light hex it found was transcribed from SCREENS.md §1.2 and E8's rule for a transcribed value
is that it may not be changed. RULINGS R1 changes five of them anyway, under the delegation recorded
at the top of that file, and **R1a** extends that to three more grounds R1 was written without —
E106's sweep never measured them, so they were missing from the ruling rather than declined by it.
This entry is what moved and what it now measures.

**Seven values carry a new claim.** E8 established a vocabulary — a value is *transcribed*, or it is
*derived* — and R1 needs a third word. `CypressColor.overruled(light:dark:)` sits beside `dynamic`,
`derived`, `escalated` and `lightOnly`, and it means: this hex is in the document, and it is being
replaced anyway. There are seven after R1a, they are listed in `CypressColor.overruledTokens`, and `TokenGallery`
renders them as a third review section between the derived rows and the escalated ones — the only
section on that screen where a designer is being shown their own value substituted for rather than
a gap filled in. Reversing one is two lines and brings E106's failure back with it.

**The retint moves lightness in OKLCh and holds chroma and hue**, which is E8's machinery run for a
different purpose: E8 fitted a light→dark transform, this fits nothing and solves for one coordinate.
`Tools/retint_ramp.py` is the derivation, so every number below is reproducible rather than a value
that appeared in a diff. Across the five tokens chroma moves by at most 0.0013 and hue by at most
0.7°, both of which are under a single 8-bit step; the palette is the same palette with three of its
greys and two of its ambers set darker.

| Token | Light was | Light now | Dark was | Dark now |
|---|---|---|---|---|
| `text.faint` | `#8B9482` | **`#697260`** | `#5F6F61` | **`#7E8F80`** |
| `text.faintAlt` | `#77836F` | **`#5D6855`** | `#5F6F61` | **`#7E8F80`** |
| `text.muted` | `#66735F` | **`#535F4C`** | `#94A496` | `#94A496` — unmoved |
| `est.` badge text | `#8A6A2A` | **`#836324`** | `#D99A4E` | `#D99A4E` — unmoved |
| C24 attention card border | `#D9A05B` | **`#B8803A`** | `#D99A4E` | `#D99A4E` — unmoved |
| `searchGlyph` (R1a) | `#77836F` | **`#6C7764`** | `#94A496` | `#94A496` — unmoved |
| `Dark.textFaint` (R1a) | — | — | `#5F6F61` | **`#7E8F80`** |

`Dark.textFaint` has one value and no pair, because screen 04 is dark in both appearances; it is in
the review sheet on those terms. One further value moved and is **not** an overrule —
`surfaceEmptyThumb`'s derived dark, corrected from `#1F2E22` to `#18251D` under E8's own rule. See
item 3 below.

**Measured, on every ground each token is drawn on, in both appearances.** Nothing here is inferred
from the other half. E106's sharpest observation was that `text.faint` on a card was *worse* after
dark (2.98) than in light (3.16) — the one place E8's transform moved a ratio the wrong way — and
the reason it could happen is that the two appearances do not share a binding surface: in light the
screen is the hard ground and in dark the card is, because the dark card is a *raised* plane and
therefore lighter than the screen while the light card is white and therefore darker than it.

| Pair | Light before | Light after | Dark before | Dark after |
|---|---|---|---|---|
| `text.faint` on `surface.screen` | 2.90 | **4.62** | 3.42 | **5.33** |
| `text.faint` on `surface.card` | 3.16 | **5.03** | 2.98 | **4.64** |
| `text.faint` on `surface.sheet` | 3.09 | **4.93** | 2.98 | **4.64** |
| `text.faintAlt` on `surface.screen` | 3.67 | **5.40** | 3.42 | **5.33** |
| `text.faintAlt` on `surface.card` | 3.99 | **5.87** | 2.98 | **4.64** |
| `text.muted` on `surface.screen` | 4.62 | **6.21** | 6.97 | 6.97 |
| `text.muted` on `surface.card` | 5.02 | **6.75** | 6.06 | 6.06 |
| `est.` badge text on its fill (C12) | 4.19 | **4.64** | 6.11 | 6.11 |
| C24 border on the card it identifies | 2.30 | **3.39** | 6.57 | 6.57 |
| C24 border against the page behind it | 2.12 | **3.12** | 7.55 | 7.55 |

`text.body` (8.6–9.4 light, 7.9–9.1 dark) and `text.ink` (13.8–15.0 / 13.1–15.0) do not move, and
the ramp now reads 4.6 / 6.2 / 8.6 / 13.8 on the light screen and 5.3 / 7.0 / 9.1 / 15.0 on the dark
one — roughly even in perceived lightness, as R1 asks, and monotonic on all three grounds in both
appearances.

**Three of the ten halves were not overruled, and that is deliberate.** `text.muted` after dark
already read 6.97 on the screen and 6.06 on a card, so it clears R1's 6.0 floor without a change;
the dark `est.` badge reads 6.11 and the dark C24 border 6.57. An overrule is spent where it is
needed and nowhere else, and there is a second reason in the muted case: `#94A496` is
`dark.text.muted` by name, and three derived badge labels point at it. Moving it to buy 0.1 would
have desynchronised four tokens for nothing.

**Two placements needed a rule rather than a floor.**

- `text.faintAlt` solved against 4.5 alone lands 0.03 from `text.faint` — which is R1's own objection
  to E106's proposed fix, reappearing one rung lower. So it instead keeps the fraction of the
  faint→muted lightness interval §1.2 gave it (0.52, near enough the midpoint) reapplied to the two
  retinted ends. The three-way spacing the designer drew survives the move, and the two footnote
  colours stay one colour after dark exactly as D3 wrote them.
- The C24 border is solved against `surface.card` **and** `surface.screen`. A boundary is adjacent to
  a surface on each side of it, the page is the harder of the two by 0.27, and C24 is the one place
  in this palette where WCAG 1.4.11 genuinely binds — the card is `surface.card` on `surface.screen`
  at 1.09:1, so the border is the only thing saying this card is different.

**What is still failing, and it is the list R1 named plus one.** The 311 panel border stays at 1.82
in light: the panel has its own fill and its own amber body copy, so the border is not what identifies
it, and that is house style rather than a defect. The default card edge stays at 1.15 for the same
reason. The C10 locked glyph (1.84 / 2.12) and the C23 chart series on a dark card (2.53 / 2.27) stay
exactly where E8 left them; both are drawn decisions — a glyph and a data encoding — rather than a
text ramp, and R1 leaves them as the first thing on a designer's list. All of them stay pinned to
±0.05 in `ContrastTests`, as do the ten retinted ratios above, because a number that quietly gets
*better* means somebody changed a token without reading this and is as much a failure as one that
gets worse.

**Five things R1 did not anticipate, found by measuring rather than assuming — and R1a, which
picked up three of them.** R1 was written from E106's table, and E106's sweep did not reach three of
the grounds below, so they were absent from the ruling rather than declined by it. RULINGS R1a
extends R1 to cover them; the other two are decisions to leave them alone, recorded here so they are
decisions rather than oversights.

**1 · The forced-dark palette did not move with the ramp — R1a, fixed.** `CypressColor.Dark.textFaint`
is the transcribed `dark.text.faint` `#5F6F61`, and screen 04 draws its note-field prompt and
micro-labels in it directly. 04 is dark whether or not the phone is, so R1's retint of the resolving
token never reached it: the same label was legible when the phone was in dark mode and illegible when
the *screen* was dark, which is R1's own argument — that the ramp is every micro-label in the app and
not one badge — failing on its own terms. Overruled to **`#7E8F80`**, which is `textFaint`'s retinted
dark half exactly, so it mints nothing and the two halves of the ramp are one colour again.

| Screen 04 pair | Before | After |
|---|---|---|
| `Dark.textFaint` prompt on `Dark.surfaceCardAlt` | 2.99 | **4.66** |
| `Dark.textFaint` on `Dark.bgCameraTray` | 3.23 | **5.03** |
| `Dark.textFaint` on `Dark.bgCamera` | 3.44 | **5.36** |
| `Dark.textMuted` offline line on the tray | 6.57 | 6.57 — unmoved |

`Dark.textMuted` `#94A496` already read 6.09 / 6.57 / 7.00 on those three grounds, so the rung above
faint does not collapse and does not need an overrule to avoid it. One ground was deliberately left
out of the solve: 04's disabled `Log visit` label rides this token on `Dark.surfaceThumb` and reads
4.16 — see 4 below.

**2 · The search placeholder wore a hex R1 retired — R1a, fixed.** C20's placeholder and magnifier
were `#77836F`, `text.faintAlt`'s light value, held by coincidence rather than by alias; after R1 it
was the only thing left in the app wearing it. It is placeholder text, which is text, on screen 01,
which is the default screen. Overruled to **`#6C7764`**: **3.93 → 4.63**. Measured on the ground it
sits on rather than on the token — the search fill is `rgba(255,255,255,.94)`, so the ratio is
against that fill composited over the map paper (`#FEFDFC`), which costs 0.06 against measuring it
opaque. The dark half `#94A496` reads 6.06 on the composited dark fill and is not touched.

**3 · `text.faint` was drawn on a fourth ground, and there it still failed — R1a, fixed from the
other side.** 14's empty photo well sets a 13 pt sentence on `surfaceEmptyThumb`. The R1 retint took
it from 3.03 to 4.83 in light and from 2.67 to only 4.16 in dark, and it was **not** fixable in the
token: lifting `text.faint` far enough to clear 4.5 on that ground would put it 0.042 from
`text.muted` in OKLCh lightness, inside the 0.075 step of the documented dark ladder (E8), which is
the rung collapse R1 re-spaced the ramp to prevent. So the ground moved instead, and that required no
overrule at all — **`surfaceEmptyThumb`'s dark value was derived, and E8's rule is that a derived
value may be corrected.** It is now a *corrected derivation*, `#1F2E22` → `dark.surface.card`
`#18251D`: E8 had read the well as a recess inside a card, which is what `dark.surface.thumb` is for,
but 14's well is not in a card — it is a dashed well on the screen, and its light value `#FAFBF4` is a
card-level plane. The near-identical `surfaceShareCard` `#FAF8EF` was derived onto `dark.surface.card`
on exactly that reading. `text.faint` on it now reads **4.83 / 4.64** and `text.muted` **6.49 / 6.06**,
where it was 5.44 after dark.

**4 · The disabled labels are under 4.5 on purpose, and stay there.** `ctaDisabledLabel` is an alias
of `text.faint`, so 09's disabled `Done` moved with it, from 2.63 to **4.19** in light and 2.98 to
**4.64** after dark; 04's disabled `Log visit` rides `Dark.textFaint` on `Dark.surfaceThumb` and moved
from 2.67 to **4.16**. Neither is solved for and neither is a failure: WCAG 1.4.3 exempts "text that
is part of an inactive user interface component", and a disabled control that reads exactly as
strongly as an enabled one is a different defect — the one this app would actually ship, since its
camera CTA is gated on having taken a photo. Both are pinned two-sided in `ContrastTests` as exempt
rather than as failures, so the number moving is still loud.

**5 · The three light amber border weights have come apart, and that is design's to reconcile.** E8
recorded that `borderAmberSoft`, `borderAmberMid` and `borderAmberStrong` collapse onto one value
*after dark*. R1 has now split them in *light*, at the other end: C24's attention-card border left
`#D9A05B` for `#B8803A`, and `borderAmberMid` and `amberChipSelectedBorder` — which were the same hex
and the same 1.5 pt weight — did not follow it. **The attention card's border is now visibly darker
than the selected amber chip's, where before this pass they were one colour.** That is correct under
1.4.11, which asks for 3:1 only where a boundary is required to identify a component: a selected chip
is identified by its fill and its label, and the attention card is identified by nothing else. R1a's
line is that an accessibility floor justifies an overrule and a matching set does not, so no further
transcribed hex is moved for consistency alone. **The specific question for design is whether the two
chip borders should now follow C24 down to `#B8803A`** — which would restore the set at the cost of a
darker amber on a chip that does not need one — or whether the attention card is meant to read as the
heavier of the two. Nothing in SCREENS.md answers it, because nothing in SCREENS.md anticipated one
of the three moving.

Verified by `CypressTests/ContrastTests.swift`, which gained the assertions that could not exist
before the retint: every rung of the ramp against all three surfaces in both appearances, the
monotonicity of the ramp so that no future edit can collapse two rungs into each other silently,
`text.faintAlt` held between the two bottom rungs, `text.muted` held at 6.0 rather than merely above
the floor, and — after R1a — the four grounds that are not one of the three surfaces, including
screen 04's forced-dark palette and C20's fill measured as it is actually composited. The lesson
underneath all three R1a items is the suite's own: **a pair that is never measured is a pair that
never fails.** `Tools/retint_ramp.py --check` covers every value above, so the derivation stays
reproducible rather than becoming a number in a diff. E106 is amended to point here.

### E109 — §3.12 anonymizes and the exclusive-ownership CHECK forbids it, so account deletion had to choose; R3 chose, and the tombstone trigger had to be widened to let it

The conflict E23 and E89 each recorded as OPEN and handed to whoever built account deletion is now
closed by RULINGS **R3**, and this entry records what closing it cost.

**The conflict, stated once more because it is the reason for everything below.** DECISIONS §3.12
says account deletion anonymizes attributed rows — "user_id nulled, device link severed" — rather
than deleting them, and it ships from day one. `AppSchema` v3 and v5 then gave `private_reminders`
and `favorites` a `CHECK ((user_id IS NULL) <> (device_id IS NULL))`, so exactly one of the two owner
columns is ever non-null. An account-owned row cannot satisfy both sentences. Nulling its `user_id`
leaves it owned by nobody, which the engine refuses outright; re-homing it onto the device satisfies
the CHECK and hands one person's private records to whoever picks the phone up next. There was no
third answer available in the schema and no document said which of the two to take.

**R3's answer, which is the one implemented: these rows are deleted.** §3.12 anonymizes
*contributions*, and the word carries the argument. A photograph, a measurement, a check-in have
value to the forest independent of who made them, which is the entire reason for keeping them past
the account. A private reminder and a favourite have no such value: nobody but their owner could ever
read them, and after anonymization nobody at all can, so what survives is not a preserved
contribution but an unreachable row that no query returns and no person can remove. Anonymize what
the forest keeps; delete what only one person could ever see.

**The tombstone trigger had to gain a second exception, `AppSchema` v6.** v5's trigger refuses every
`DELETE FROM favorites` except the adoption merge, and its leading arm is `OLD.device_id IS NULL` —
which is exactly the shape of an account-owned row. So the erasure R3 orders was unwritable against
the shipped schema, the same class of bug E89 fixed in the other direction. v6 drops and recreates
the trigger with a second permitted case: a row whose `user_id` matches the account named in an
`app_state` sentinel that `AccountDeletion` writes, uses and clears inside one transaction. The
permission therefore exists only for the statements that need it, only for one named account, and
cannot outlive the transaction — a rollback takes the sentinel with it, so an interrupted deletion
cannot leave a standing hole. A `temp` table would have been the tidier scratch space and is not
available: SQLite forbids a trigger from referencing a table in another database.

**The `WHEN` clause is written with `EXISTS`, and the natural spelling is a hole.**
`OLD.user_id = (SELECT value FROM app_state WHERE key = …)` reads correctly and is wrong: with no
sentinel row the subquery is NULL, the comparison is NULL, `NOT (0 OR NULL)` is NULL, and a `WHEN`
clause that evaluates to NULL does not fire. That form permits every hard delete of every
account-owned favourite on every database where nobody is being deleted at all — the trigger would
have looked present in the DDL while doing none of its job, which is the same failure mode E89
recorded for `UNIQUE (user_id, device_id, tree_uuid)` and the reason that warning was worth carrying
forward. It was verified rather than reasoned about: the naive form leaves zero rows where the
shipped `EXISTS` form leaves them all. `DataGates` and `AccountDeletionTests` both assert the
no-sentinel case, which is the assertion that catches it.

**What happens to the outbox, and why.** A mutation lives in the queue between being written and
being applied, and that gap can straddle a deletion exactly as it can straddle a sign-in — the gap
`LocalAPI.adoptRowsWrittenAfterTheClaim` already documents in the other direction. Straddling a
deletion is worse, because an item that drains afterwards re-creates, under the name of an account
that no longer exists, precisely what the deletion just removed. The two kinds of queued row take the
two answers R3 gives:

- **A queued favourite toggle or private reminder belonging to the account is deleted from the
  outbox.** Its only possible destination is a row that may not exist: an ownerless one fails the
  CHECK, and a device-owned one is the re-homing R3 refused. There is nothing left for the mutation
  to mean, so the row goes rather than failing in the queue for ever where screen 17 would keep
  reporting a record the person was told was gone.
- **A queued visit, check-in, measurement or care event stays, with `userID` removed from its
  payload.** The contribution survives deletion — that is §3.12 — but it has to arrive anonymous, and
  an untouched payload would re-attribute it on drain, silently undoing the anonymization for exactly
  the rows that were in flight. `json_remove` leaves the payload byte-identical to one written before
  sign-in, because `JSONEncoder` omits a nil optional rather than writing a null; the `client_uuid`,
  the photo list, the retry state and the FIFO position are untouched, so nothing about the queue's
  guarantees moves.

Both statements run over every state, not only the pending ones. A `done` row is screen 17's receipt
and its payload is a second copy of the attribution sitting on disk, so anonymizing the table and
leaving the receipt would leave the account's id on the device; a `done` favourite's receipt is worse
still, because it names a tree this person kept, which is the record R3 says nobody else could read.

**What happens to the tombstones, and why.** A favourite un-favourites through `deleted_at` rather
than a `DELETE` because a stray delete loses the un-favourite *event*, so the row returns on the next
sync from another device (v1, restated in E89). That reason does not survive an account deletion.
There is no next sync: the account those other devices would sync as no longer exists, and the same
transaction removes the account's queued toggles. A tombstone is also exactly as exclusively owned
as a live row and exactly as unreadable once its owner is gone — it is a sentence about a person
("this account stopped keeping this tree") that no query can return and nobody can remove. So the
tombstones are deleted on the same argument as the rows they are tombstones for, and the v6 exception
is keyed on the row's owner rather than on its `deleted_at` so that it covers both without a second
clause.

**A device's own reminders and favourites are not touched.** They were written before there was an
account and were never the account's; `claimDevice` moves such a row *onto* an account and nothing
has moved these. Deleting them would delete the next person's records, or the same person's
pre-sign-in work, on the strength of a shared installation id.

**Three things R3 did not anticipate, found while implementing it.**

1. **There is no account-deletion surface anywhere in the app, and there was no deletion path at
   all.** `CypressAPI` omits `DELETE /me` by name, `AppSchema` has no `users` table, and nothing in
   `Features` draws a confirmation. So this is the path's first existence rather than a change to it.
   The local half is not a stub and is not on the protocol: the rows are on this device and
   `LocalAPI.deleteAccount()` is the only code that can reach them, so it sits beside
   `privateReminders` and `curatedSpecies` until a server makes the endpoint real. The copy R3
   requires is written as `AccountDeletionCopy` in `Core` and is presented nowhere — inventing the
   screen would be inventing (DECISIONS constraint 21), and copy that does not exist cannot be
   reviewed by whoever eventually draws it.
2. **`community_notes.user_id` is `NOT NULL`, so a public note cannot be anonymized either.** It is
   the same conflict with §3.12 as the two exclusive-ownership tables and it wants the *opposite*
   answer — a community note is a public contribution, exactly the thing §3.12 exists to keep — but
   the column that stops it being kept ownerless predates the decision and no migration has made it
   nullable. Nothing in the app writes a community note today, so no such row can exist, and
   rebuilding the table for zero rows would ripple `CommunityNote.userID` into an optional across
   `Core` for no present gain. `AccountDeletion.Outcome.communityNotesLeftAttributed` counts what the
   path could not anonymize and is zero on every database the app can produce, so the day something
   writes one this is a number somebody can see rather than a silence. **OPEN**, and it is the next
   thing to settle if community notes are ever built.
3. **`FavoriteTests` pinned the migration list as a literal `[5]`** — the exact mistake that test's
   neighbours (`PrivateReminderTests`, `DataGates.outboxPhotoShotTypes`) each carry a comment
   warning against, written by the entry that added v5. Adding v6 failed it. It now filters
   `$0 > 4` like the others.

Proven by `CypressTests/AccountDeletionTests.swift`: a contribution of each of the four kinds
survives with its `user_id` nulled and its device id and its place on the tree intact, and so do the
two nullable attributions (`tree_names.given_by`, `review_flags.raised_by`); the device link and the
signed-in state are severed and a second deletion is refused; a reminder, a favourite and a favourite
tombstone do not survive, and are not re-homed onto the device; the device's own rows and a second
account's are untouched; a failure injected part-way through — an aborting trigger on
`private_reminders`, which fires after the anonymization has already run — leaves every row, the
signed-in state and the sentinel exactly as they were, and the same call succeeds once the failure is
removed; a queued toggle does not re-create the deleted favourite when the queue is drained
afterwards and a queued visit lands anonymous with its idempotency key unmoved; the trigger still
refuses a hard delete when no erasure is in progress and after one has finished; a v5 database
migrates with its live rows and its tombstones intact and replays as a no-op; and the copy names the
reminders and the favourites in the one sentence that tells a person their observations stay.
`DataGates` adds the schema invariants: the erasure exception is refused with no sentinel set,
refused when the sentinel names a different account, and accepted for the account it names, and the
sentinel does not outlive the transaction that wrote it.

### E110 — screen 01 was drawing a system navigation bar, and it is the one screen that must not have one

`RootView` wraps every tab root in a `NavigationStack`, and a root that does not opt out inherits an
empty navigation bar. **Sixteen screens opt out** — grep `toolbar(.hidden, for: .navigationBar)` and
it is in TreeProfile, Memorial, Grove, Almanac, Activity, Outbox, Measure, Report, Species,
GrowthHistory, CheckIn, the Journal and You tab roots, and in the site screen E107 adds. `MapHomeView`
was the only screen missing it, and it is the app's default screen and the one SCREENS.md 01
explicitly describes as full-bleed: "no 62px status padding — content is absolutely positioned below
the notch".

Photographed on an iPhone 16e rather than reasoned about: **an opaque 91pt band above the map** — a
47pt status area plus a 44pt bar — with the map beginning under it and the search bar 8pt below that.

**The second half is the interesting one, and it was checked rather than assumed.** `MapHomeView`
positions the search bar at `proxy.safeAreaInsets.top + MapLayout.searchTopInset`, and
`searchTopInset` is 8 with a note reading "on a device the bar hangs off the top safe area instead,
which is the same 8pt gap below the status bar". With the navigation bar present that inset reads
**0** — the bar has already consumed it — so the arithmetic was not compensating for the bar, it was
being starved by it. Measured off the two screenshots: the search bar's top edge was at 99pt with the
bar and is at 55pt without it, which is 47 + 8 exactly. Hiding the bar restores the number the code
was written for; it does not overshoot.

The bottom was checked at the same time and is not doing this. C16 is pinned to the bottom with its
own 30pt padding over the home indicator, and the before and after screenshots of the tab bar are
identical.

The finding worth keeping is the shape of the defect rather than the defect: **it built green and
passed the whole suite for the entire run of M1 through M4 while the app's default screen was wrong**,
because nothing in a unit test can see a navigation bar and no snapshot test exists (ARCHITECTURE §7:
"Snapshot-testing the screens against the mocks is explicitly *not* set up yet"). The fix is one
modifier that sixteen other files already carry. What a suite of 375 tests cannot tell you is what
the screen looks like, and the only thing that found this was somebody photographing it.

### E111 — screen 15 asks for an email address the beta cannot send anything to, so it is gated rather than deleted

Screen 15 is the account ask. It is built, it is tested by `AccountAskTests`, and it **cannot sign
anyone in**: authentication is magic-link only (DECISIONS §3, no passwords ever), a magic link needs a
server to send it, and the local beta has no backend. Presenting it would take an email address from
somebody and give nothing back, which is the failure the whole of §3 is written to prevent.

**Resolved by RULINGS R4**, which the project owner delegated. The screen stays built and stays
unreachable behind `BetaCapability.accountsAvailable`, false, in one place. A route commented out is
indistinguishable from a route somebody forgot to write; a named constant says that 15 exists, works,
and is waiting on a server rather than on an engineer.

**Where the gate went is the finding, and the first placement was wrong.** The obvious spot is inside
`VisitSaveLedger.recordSave()`, which is where the ask is earned. Putting it there breaks six tests in
`AccountAskTests`, and those tests are *right*: they pin D9 — the ask comes at the third save, gets
exactly one second chance, then stops for good — and D9 is true whether or not this particular build
has a server behind it. **A capability flag that has to rewrite six tests about a product decision is
sitting in the wrong place.** The ledger answers "has the ask earned its interruption"; the capability
answers "can this build honour it"; they are different questions and they now live in different
types. `recordSave(mayAsk:)` takes the answer to the second one from its caller and defaults to
`true`, so the D9 suite is untouched.

**The half that is invisible if you get it wrong.** A gate placed *after* `askPresentationCount`
increments would silently spend both of a person's two goes while the feature is switched off — so on
the day auth ships, they are never asked at all. Nothing in the current build can show that symptom:
it only appears once the thing it breaks is turned on. `BetaCapabilityTests` asserts it through the
`UserDefaults` the ledger writes rather than through the ledger's own accessors, so a gate that stops
the reader instead of the writer still fails. The save itself is still counted, because the count is a
fact about somebody's field work rather than about this build's capabilities — otherwise D9 would
later be measured from the wrong zero.

### E112 — the heart now comes off where it went on, and three things E101 recorded as forced were consequences of the missing state rather than of the design

E101 recorded a favourite that could be written and not removed, and left the closure to a
decision-owner: "a selected appearance for C8's first cell, or a surface that lists favourites and can
remove one." **RULINGS R2 chose the first**, on the grounds that a list is a new screen and the
authorization that covered inventing entrances (E98) did not cover inventing screens, while a state on
a drawn component is a variant of something the designer already drew. This entry is what that cost,
and the interesting part is that every one of E101's three "deliberate" notes turned out to be a
consequence of the missing state rather than an independent decision. Adding the state retired all
three at once.

**What the selected cell is, and the one clause of R2 that could not be built.** The fill is
`callout.green.fill` — the app's existing tinted green surface, which C14 and C4's sanity pill already
sit on — and the label and border take `cta.fill`, the accent. R2's sentence also says "the heart
glyph fills", and **there is no heart glyph to fill**: §2 C8 marks the four icons NOT SPECIFIED and §5
gap 3 repeats it, so this row has drawn text and only text since it was built. Inventing a heart for
one of four text cells is a drawn decision (DECISIONS constraint 21) on the very component R2 is
careful to treat as already-drawn, and one iconned cell beside three bare ones is a visual change
nobody asked for. So the glyph clause is unbuilt and named here rather than quietly satisfied; the day
design lands the four icons, the filled/outline pair is one line in `QuadActionRow.appearance`. The
label is `Favorite` in both states, per R2 and for R2's reason.

**The state is not carried by colour, and that is not decoration.** The selected cell also takes a
`hairlineStrong` border against the idle `hairline`, and 12/800 against 12/600. Those are the two
channels that survive greyscale, and with no glyph the hue would otherwise be the whole encoding —
which is E103's finding arriving by a different road. VoiceOver gets the label unchanged and the state
as a *value*: `Favorite, On, selected, button`, and `Favorite, Off, button`. The off state is spoken
too, deliberately. A listener who hears only "Favorite, button" has been told nothing about whether
this tree is already one of theirs, which is the same failure as two cells drawn identically. The
three cells that open something have no spoken value and no trait, because a `Share` announcing "Off"
would be describing a state it does not have — `QuadActionRow.Action.hasOnState` is the exhaustive
switch that says so.

**1. The write stopped being fire-and-forget, and the error did not have to be reported to be
visible.** E101 dropped the write's error because "there is no drawn state in which the screen could
honestly report one." There is now, and it is not an alert: `TreeProfileModel` writes the desired
state through immediately so the control answers the finger, then **re-reads what is stored** and
shows that. A write that does not land is a heart that goes back where it was. This is stronger than
propagating the error would have been, because the failure it catches includes the ones that never
throw — `FavoriteOutboxWriter` swallows a drain failure by design (the row is durable and the outbox
owns retrying it), so a thrown error is not the same question as a stored favourite.

**2. The double-tap trick is retired, and it had become the bug it was preventing.** The composition
root kept the client UUID it minted per tree and replayed it, so an impatient double tap on a control
with no on-state stored one favourite rather than two identical ones. `applyFavoriteToggle`'s replay
guard is `WHERE favorites.client_uuid <> excluded.client_uuid` — the mechanism that makes a re-sent
outbox item a no-op — so with an on-state that same reused key makes *un-favouriting* a silent no-op:
tap, tap, and the row is still live. Each call now mints its own key, and idempotency stays where
ARCHITECTURE §4 puts it, on the mutation rather than on the control. The write lives in
`ProfileFavoriteWriter` rather than in a private method of `RootView`, because a rule held privately by
a view is a rule no test can state.

**Two taps in one run are now ordered rather than absorbed.** With one key per tap, "on" and "off"
issued before either has been awaited can interleave — two writes and two re-reads, and the cell ends
up showing whichever read landed last. `TreeProfileModel.toggleFavorite` chains each tap onto the
previous one, so the last tap is the last word. This is a new failure mode created by the fix, and it
is the one thing here that the old replayed key genuinely did prevent.

**3. The initial state has to be read, and the read it uses is one E89 left correct and callerless.**
`grove()` is `GET /me/grove` — favourited and visited trees, both ownership arms — and E89 records that
nothing in the app called it, because the surface that would (screen 08's `Trees` pill) is drawn inert
(E46). Screen 03 calls it now. **The tidier read would be a per-tree `isFavorite` on `CypressAPI`**,
which ARCHITECTURE §4 explicitly sanctions ("if a screen needs data, the protocol grows a method");
that is a change to the backend boundary rather than to a screen and was not this task's to make, and
the cost of the substitute is that opening a profile reads the whole grove. On a device holding a
handful of contributions that is a few rows. It is the first thing to change if the grove ever gets
large. A read that fails is `false`: "not known to be yours" and "not yours" draw the same way, and the
drawn way is the state the cell has always had.

**A memorial keeps the heart, and loses the two cells that write.** E89 settled that a removed tree can
be favourited and the reason is reversibility — gating the write makes the toggle one-way for anyone
whose favourite tree is later removed, because the gate that refuses the heart also refuses removing
it. Nothing here changes that. What did change is the rest of the row: `Care` writes a care event and
`Report` opens screen 06, whose subject is a `HazardCategory` whose four values are all statements
about a standing tree. Both were being offered on a photographed removed tree — the residual E95 names
and E89 repeats — while the visit CTA, the check-in button and the empty measurement slot beside them
were all correctly withheld by `acceptsNewContributions`. The quad row was the last control on the
screen offering a write to a record that cannot take one. `TreeProfilePresentation.quadActions` is now
the one property that decides, and it drops `Care` and `Report` while keeping `Favorite` and `Share`.
`SiteView` reached the same answer from the other side and wrote it down first: "no quad action row,
because three of its four cells act on a tree."

**What this could not be verified by.** The quad row is drawn only on the warm variant of 03, and per
D8 every tree in the shipped seed renders the *cold* variant — the city inventory carries no community
content at all — so there is no tap sequence on a fresh install that puts this row on screen. Launching
the app cannot photograph R2. `FavoriteAppearanceShots` renders the `#if DEBUG` populated fixture at
both states in both appearances instead, which is `DynamicTypeScreenshotTests`' own argument for the
other eighteen screens. Both states were looked at in light and dark before this was called done.

Proven by `CypressTests/FavoriteToggleTests.swift`: a tree the store already holds opens selected and
one it does not opens idle; a store that cannot be read draws the idle cell without taking the profile
down with it; the second tap writes `false` and the store takes it; two taps issued together land in
the order they were made; a write that does not land puts the cell back, in both directions; the label
is `Favorite` in both states and the state is spoken in both directions; the selected appearance
differs from the idle one in border weight and font weight as well as in hue, and its label clears
4.5:1 on its own fill in both appearances; a removed tree keeps `Favorite` and `Share` and loses `Care`
and `Report`; and `ProfileFavoriteWriter`, driven twice against a real store and a real outbox, leaves
a tombstoned row, an empty grove and two outbox items under two distinct client UUIDs.

### E113 — a vacant site could still be opened as a tree profile from every entrance except the one that was fixed

E107 gave the vacant planting site its own screen and routed the map card to it, and named what it was
leaving behind in its own last paragraph: "Entrances other than the map — the visit flow's
nearest-candidate list, a stale link — still land a vacant site on the degraded profile, because
`TreeProfileView` is where that redirect belongs and it was being edited elsewhere." That is 12,518
records, 6.4% of the map, still able to render as screen 14 — an empty photo well captioned `No photos
of this tree yet` over `Be the first to photograph this tree`, both of which assert a tree that is not
there.

**The entrances are the finding.** `Route.treeProfile` is pushed from the map's card, the almanac's
season row, the almanac's "walk the nine" row, the journal tab's rows, the visit flow's open-tree
callback and — since E107 — the site screen's own nearest-tree row. Six, with no reason to think six is
the number next month. **None of them knows the status**: it arrives with the payload, one read later,
in `TreeProfileModel.load()`. So a redirect written at a call site is a redirect written where the
answer is not yet known, and the second call site to be forgotten looks exactly like the first.

**The chokepoint is the load, and the shape is an exhaustive switch.** `TreeProfileDestination(record:)`
is asked once, after the read and before any derivation, and switches over `TreeStatus` without a
`default`, so a sixth status cannot be added without somebody answering for it. A vacant site becomes
`.elsewhere(.site(id))`, the model's phase carries the route rather than a presentation, and the view
draws nothing while the router swaps the screen. Nothing about a site is ever computed as a tree
profile — `model.presentation` is `nil`, which is what the view draws from.

**The stronger version of this fix was tried and rejected, and the reason is worth recording.** Making
`TreeProfilePresentation.init` failable would make a vacant site unrepresentable at compile time, which
is this project's preferred shape. It cannot be done here: five feature files construct that type for
one thing only — `GrowthHistoryPresentation`, `ActivityPresentation`, `CareLogModel`, `MeasureModel` and
`SharePresentation` all build one to read `.title`. Refusing construction there would mean refusing a
site a *name*, which is a different and wrong answer, and would push the failure into four screens that
have nothing to do with this. The gate went where the question is actually asked instead. What did
come out is `isVacantSite`, a predicate on that presentation that nothing read and that can now only be
false; it was deleted rather than left standing beside a comment describing a screen the app does not
draw.

**Replace, not push.** `AppRouter.replace(_:with:)` swaps the route in place, so `Back` from the site
returns to the entrance rather than to the profile that should never have opened, and no swipe-back
lands on it. It is targeted at the route being replaced rather than at the top of the stack, because an
`async` load can return after the reader has gone somewhere else; if the profile is no longer on the
path at all, it pushes, which is the same destination by a longer road rather than a silent no-op.

**The redirect that was deliberately not built is the one that would have been one more line.** A
removed tree can reach this screen from the almanac and the visit flow too — E95's own open residual —
and `Route.memorial` exists, so sending `.removed` to screen 19 from the same switch would close E95
here. It would also break RULINGS R2 in the place R2 says matters most. Screen 19 is drawn with
deliberately nothing to press, so a redirect to it takes away the last surface in the app that can take
a favourite off a tree somebody loved before it was felled — which is E89's deciding argument for not
gating the heart, arriving by a different road. **A redirect can be a gate wearing a router.** So
`.removed` stays on the profile, explicitly and with the reasoning at the case, and what the profile
owes it instead is to offer nothing that writes: see E112 for the two quad-row cells that went.

**The redirect takes nothing away from the site, either.** A vacant site could never be favourited from
any screen: the quad row is drawn only on the warm variant, and a site is always cold because nothing
can contribute to it. E107 declined to put a heart on the site screen for its own reason — the only
control available there is C7, which has no selected appearance, which is the defect R2 has just closed
on C8. That reasoning is unchanged and this entry does not reopen it.

**What is still open and was not touched.** `AlmanacQueries` excludes vacant sites by construction (an
inner `JOIN` to species), which E107 flags as the surface that ought to be pointing at these 12,518
rows being the one that cannot see them — **repeated here from E107 and wrong in both places; E115
has the mechanism (a status predicate, not the join), what widening the join actually does, and the
one read that was genuinely missing it**; C19 still has no pin for a site, so the map draws one as
`removed` and the distinction is carried by the card and the VoiceOver label; and E95's residual for
removed trees stays open by the decision above rather than by omission.

Proven by `CypressTests/VacantSiteRedirectTests.swift`: a vacant site — fixtured *with* a visit, so a
regression would draw the loud warm variant rather than the quiet cold one — leaves as `.site` and
derives no presentation; alive, declining and dead-reported records still open the profile; every case
of `TreeStatus` has an answer and the loop grows with the enum; the replace lands the site where the
profile was and leaves `Back` pointing at the entrance; a replace against a stack that has moved on
pushes rather than dropping a screen; and a removed tree keeps its profile, keeps `Favorite` on the
row, and offers no write.

### E115 — the almanac's blindness to vacant sites is a status predicate doing its job, and the coverage gap D1 names is not the gap a basin is

E107 recorded, and E113 repeated, that `AlmanacQueries` "excludes vacant sites by construction (an
inner `JOIN` to species)" — and both entries name it as the first thing to look at if the almanac is
meant to be the surface pointing at these 12,518 rows. The diagnosis is wrong in its mechanism and
the conclusion it invites is wrong in its product reading. Both matter, and the mechanism matters
first, because it is the one somebody would act on.

**The join is not the gate.** Four of the five reads in the file join species with a `LEFT JOIN` or
do not join species at all, and every one of them still returns no vacant site. What returns none is
`AlmanacQueries.standing` — `t.status IN ('alive','declining')` — which is applied by every read and
whose own doc comment has said since it was written that "a basin with nothing in it is not an elder,
not a newest neighbour and not a young tree anybody can go and look at". The inner join in
`speciesMix` excludes something else entirely: the 312 city rows whose label names no taxon (E14).

**Widening it admits no site, moves two numbers that are load-bearing, and takes the screen down.**
Measured on the shipped seed in Sunset/Parkside, replacing that `JOIN` with a `LEFT JOIN` admits
**zero** vacant sites — `species_current` is NULL on all 12,518 of them and `s.id = t.species_current`
evaluates to NULL rather than to true, so a site cannot reach the join condition at all, never mind
survive it — and admits **52** non-taxon trees. `Who lives here · 215 species` becomes 216, the last
of them nameless, and the denominator every share is divided by moves from **11,026 to 11,078**.
11,026 is the population behind RULINGS **R5**, which fixed screen 08's denominator at 215 and ruled
it stays there; a join widened on screen 12's behalf reopens a ruling taken about screen 08. It never
gets that far in practice: `SpeciesShare.name` is not optional, `row.uuid("species_uuid")` on the
nameless group raises `unexpectedNull`, `AlmanacModel.load()` catches it as `.failed`, and screen 12
draws its header and its footnote with nothing between them. The recommendation in two entries, taken
literally, empties the screen it was trying to fill.

**The one read that really was wrong is `firstBloom`, and it is fixed here.** It is the only read in
the file that starts from a contribution rather than from the inventory, and it filtered `deleted_at`
and nothing else — no status at all. A `flowering` visit recorded against a vacant site therefore
produced `First bloom of the year` over a planting basin, named by its street and tappable: the one
row on screen 12 that names a specific record was the only one that could name a record with no tree
in it. Reproduced against the real seed at `2501 Lincoln Way`. That the app cannot write such a visit
today is not a defence — it cannot only because E113 redirects a site away from the tree profile the
camera opens from, which is the almanac's own rule being enforced in another feature's router, one
release after the almanac was written. `Self.standing` now applies to all five reads. The same
predicate also drops a bloom recorded on a tree since removed, which is the rule saying what it
always said: the row invites you to go and look at the tree.

**And the product reading, which is the part E11 guessed at and nobody has checked.** E11 wrote that
"a vacant site is exactly the 'coverage gap' the almanac (D1) is supposed to direct attention
toward", hedged with a *may*. It is not, and the two senses of the word are worth separating. D1's
coverage panel is enumerated in D1 itself — "young trees unvisited since planting, blocks unseen for
months" — and both are gaps in **observation**: places the record has no recent eyes on. The
justification D1 gives is "chasing coverage produces exactly the data you want". A vacant basin is a
gap in the **canopy**, and chasing it produces no data at all, because E107 established that this
app's vocabulary has nothing true to say about a site: no visit, no observation, no measurement, no
care event, and a private reminder that requires a `HazardCategory`. `Where eyes are needed` is an
ask, and an ask with no receiver is the same defect as "sent to the city" — the honest copy problem
D4 exists to prevent. So a site does not belong in §4, and a `Walk to it` that ends at a hole in the
pavement is not a smaller version of `Walk the nine`; it is a different kind of sentence.

**What screen 12 should say about them, and why this entry proposes it rather than building it.**
There is one honest statement — *N planting sites in this neighbourhood have no tree in them* — and
one honest destination, the nearest of them on `Route.site`. That is one number and one row, and it
has nowhere on screen 12 to go. §2 is `This season`, and 1,474 basins are not seasonal and are not a
first, an elder or a newcomer, which is what the screen's own caption says that block holds. §3 is
`Who lives here · 215 species`, whose rows are species shares over a denominator that admitting sites
would move. §4 is the ask, above. A fourth C10 row under `This season` would cost four inventions at
once — a title, a subtitle, a tile accent SCREENS.md has not assigned to this screen, and a fourth
row where the mock draws three — and a new micro-label with its own row is a **block SCREENS.md does
not draw**. DECISIONS constraint 21, and RULINGS' closing note that the one-time exception to it is
spent, put that with design. **Proposed: a block titled for the canopy rather than for attention —
`Where a tree could go` is ROADMAP §1's own phrase for these rows — carrying one C10 row reading
`1,474 planting sites with no tree in them`, tapping through to the nearest site.** It needs a title,
a subtitle rule, a tile accent and a position relative to §4; all four are drawn decisions.

Two facts a designer answering this will want. The count itself is D1-legal without qualification: it
counts *records the city holds*, not anything anybody did, so ARCHITECTURE §5.1's trap — a number
that is a count of user actions wearing a different noun — does not apply, and unlike §2's headcount
it needs no A8 floor. And it never renders as a zero: every one of the 41 neighbourhoods carries
between 4 and 1,474 sites, so ARCHITECTURE §5.6 would never suppress this block anywhere in the city.
No query was added for it, because a read nothing draws is the thing E113 deleted `isVacantSite` for;
the destination it would need already exists as `TreeQueries.nearest` filtered on status, which is
how `SiteModel` finds its neighbour today.

Proven by `CypressTests/AlmanacVacantSiteTests.swift`, all of it against the shipped 195,309-row seed
rather than a fixture: the population (12,518, every one inside a neighbourhood, none with a species,
none in a neighbourhood that has no others, 1,474 in Sunset/Parkside); the join arithmetic above,
including the NULL comparison proved by query rather than reasoned about, per E89 and E109; that the
live mix is still 215 species over 11,026 trees and every row can name itself; that the elder, the
plantings and the coverage read return no site even though **9,294 of the 12,518 carry a planting
date** and would otherwise qualify for two of them; and that a flowering visit on a basin is no
longer the first bloom while the same visit on a standing tree still is.

**Not fixed, and not this entry's.** C19 still has no pin for a site, so the map draws one as
`removed` (E107, E113). `firstBloom` remains the only read here that could name a tree the reader
cannot reach in the state the row implies — it now excludes the removed, but a bloom row is still a
claim about a tree made out of one visit, which is A9's floor of one working as specified.

### E114 — the whole app was photographed for the first time, and looking found no rendering lie and two design questions

E110 and E106 were both found by photographing a running screen after four green milestones had missed
them, and both were on screens nobody had ever photographed. This is the sweep that closes that gap:
every screen SCREENS.md draws — 01 through 19, plus the two tab roots the build added (the Journal tab,
which is the almanac's invented entrance, and the You tab) — rendered in **light and dark at the default
size and at AX5**, read back as images, and compared against SCREENS.md. Twenty-one screens, four
appearances each, plus thirteen cold-and-empty states in the two appearances a beta tester meets first.

**The headline is a negative, and it is a real finding rather than the absence of one.** Nothing renders
a lie. No copy asserts a write that did not happen, no control is dead, "sent to the city" appears
nowhere and §5.4's honest "the city has not been notified" is on screen 06 in both appearances and at
AX5. Nothing is inset where SCREENS.md says full-bleed — 01 was the one that was, and E110 already fixed
it; the sixteen `toolbar(.hidden)` opt-outs and the new site screen all hold. Dark mode is coherent on
every screen: cards sit at `#18251D` on `#0E1712`, no surface vanishes into its ground, and MapKit's
navy never shows through the parchment wash (checked on a booted device, not only in the renderer). And
AX5, which E105 said would keep breaking as screens were added, does not break on any of the twenty-one —
the two structural fixes E105 made to C1 and the identity block hold everywhere they are reused, the
mono furniture clamps at `.accessibility1` as designed, and every long screen becomes a scroll rather
than a clip. Six screens had been photographed before this; the finding is that the other fifteen were
right, and that is worth stating because it is the result of looking rather than of not looking.

**What the sweep needed built, because three screens had no way to be photographed at all.** 02, 04 and
18 were the only screens with no `#if DEBUG` preview fixture, which is exactly why they were unphotographed:
02's content is a function of a GPS fix a detached renderer has no way to supply (`CLLocationManager` in a
test host reports `notDetermined` forever, so every capture of 02 was its `Finding you` notice), 04 is a
camera a simulator does not have, and 18 needs a `VisitSaveReceipt` the save produces. `VisitPreviews.swift`
adds the three doubles, and `VisitLocationProvider` grows a `#if DEBUG init(pinnedFix:)` seam — the same
shape every other feature already had as a `PreviewAPI` — so 02 can be handed the ranked shortlist the spec
draws instead of the permission prompt. The photographs are produced by `ScreenSweepShots`, which extends
the `UIHostingController`-in-an-offscreen-window harness E105 built (not `ImageRenderer`, for E105's reason),
wraps every pushed screen in the `NavigationStack` `RootView` gives it — the bar E110 was about is inherited
from that stack and a screen rendered bare cannot inherit it — and writes a 2×2 light/dark × default/AX5
contact sheet per screen. It asserts only that an image was produced: ARCHITECTURE §7 still says snapshot
baselines are not set up, and a baseline-free assertion passes on a blank image.

**The first design question: screen 17's queue tiles do not carry the glyphs SCREENS.md 17 draws.** The
spec gives the visit row a camera SVG and the check-in row a rotated ring; the build draws C21's leaf on
both, and only the measurement row — whose mock *is* a mono reading in the tile — matches. This is a
knowing decision recorded in `OutboxView.swift` ("§2's camera and ring glyphs are not in C1–C30 and are
not invented here"), taken under constraint 21, and it is defensible as far as it goes. But it is still a
visible divergence from the source of truth on the one screen whose whole job is to say *what* each queued
item is, and at a glance a visit and a check-in are now indistinguishable by their tile. It is design's to
answer whether C21's leaf is the right stand-in or whether C1–C30 should grow the two glyphs 17 already
assumes; it is flagged here rather than fixed because drawing them is exactly the invention constraint 21
forbids an agent.

**The second: the cold path is a header, one faint sentence, and a screenful of nothing.** Growth history,
tree activity, the grove and the outbox each render their empty state as a title and a single line of
`text.muted` prose over an otherwise blank viewport (`No measurements on this tree yet.`, `Nothing has been
recorded on this tree yet.`, the bare grove tab row, `Nothing is waiting to send.`). Every one of these is
honest and every one is what a beta tester meets first — and for growth and activity it is what *every*
shipped tree shows, because the seed carries no measurements table and no community rows at all (D8), so
the cold state is not an edge case on those two screens, it is the only state. None of these is a bug: each
is a documented "NOT SPECIFIED" empty state that declined to invent an illustration or a call to action
(constraint 21 again). But a first run that is four blank screens deep is a product question SCREENS.md
never had to answer because SCREENS.md only ever drew the populated screens, and it is the thing most likely
to decide whether a beta tester takes a second look. Design's to answer what, if anything, those four
screens should say when they are empty; not an agent's to draw.

The images are under
`/private/tmp/claude-501/-Users-nikitabogdanov-PycharmProjects-cypress/0d7c1eed-65e3-4ed3-b24f-b64dc9fb8b1c/scratchpad/sweep`,
one `*-SHEET.png` per screen. The one surprise worth recording is how little there was to find: the
defect rate on fifteen never-before-photographed screens was zero, which says the token layer and the
component catalogue are carrying dark and AX5 correctly on their own, and that the two defects that were
found by eye earlier were failures of *coverage* — screens nobody had looked at — rather than of a
class of screen that keeps going wrong.

### E116 — the accessibility tree was never checked as a tree, only one label at a time

Every accessibility fix in this project — E103's labels on bare `Shape`s that reached nobody, E104's
component announcing an empty row, the VoiceOver values on the favourite toggle (E112) — was verified
against `CypressTests`, which is a **unit** suite. A unit test can assert that a modifier is present
on a value. It cannot assert that the element the modifier is on is in the accessibility tree at all,
that a screen's elements are reachable in the order a VoiceOver user hears them, or that an
interactive control is actually hittable by an assistive technology. **SwiftUI builds no in-process
accessibility tree**, so nothing in a unit test can see one. The whole class of "the label exists in
the source and the element is not in the tree" was unfalsifiable.

`CypressUITests` is the net under that. It is a third target — `com.apple.product-type.bundle.ui-testing`,
`TEST_TARGET_NAME = Cypress`, added to the shared scheme's test action so `xcodebuild test` runs it —
and it is black-box on purpose: it imports nothing from `Cypress` and sees the app the way VoiceOver
does, as a tree of elements with traits, labels and an order. `AccessibilityTreeTests` pins that the
four C16 tabs are present *and hittable* (a tab that is drawn and labelled but not activatable by an
assistive technology is the failure a screenshot cannot show), that the map's search field is exposed
as a field rather than as anonymous pixels, and that no hittable control on launch has an empty label.

**The target was verified to be able to fail, not merely to pass.** A UI test green against correct
code proves nothing, so one tab's label was hidden as a negative control: the tab test reported "the
My Grove tab is not in the accessibility tree" and went red, then the control was reverted. That is
the same discipline every behavioural fix in this file was held to — prove the failure against the
broken code before trusting the pass — applied to the tool itself.

**What this does not yet cover, and is the next work.** Three screens, all reachable without a
contribution: the map and its chrome. The nineteen feature screens sit behind navigations XCUITest
must *drive* to reach, and driving them needs either accessibility identifiers as stable anchors or a
launch argument that deep-links a screen for test — neither of which exists yet. Until it does, this
is a spine check, not a full audit: it proves the app's front door is navigable and leaves the rooms
for a later pass. Structural VoiceOver on every screen is still owed; what changed is that there is
now somewhere to write it.

### E117 — the fourteen rooms behind the front door, read at last; and the seed has no dead tree in it

E116 closed with a debt written into its own last paragraph: `CypressUITests` could reach the map and
nothing else, "and driving them needs either accessibility identifiers as stable anchors or a launch
argument that deep-links a screen for test — neither of which exists yet." This is that, and the
fourteen screens behind the map have now had their accessibility tree read for the first time.

**The door is an environment variable, deliberately.** `DebugDeepLink` reads `CYPRESS_SCREEN` out of
`ProcessInfo.processInfo.environment` and drives `AppRouter`. Three alternatives were rejected. A
registered **URL scheme** is product surface — it ships in `Info.plist`, and every other app on the
phone can then drive this one; a test seam must not be a public entrance. A **launch argument** of the
form `-name value` is also consumed by `NSUserDefaults` as a registered default, so the seam would be
writing to the user's preferences as a side effect of being read. **Accessibility identifiers** would
have meant scattering test anchors through nineteen production views, which is the tax E116 was
already trying not to pay. `CYPRESS_SEED_PATH` and `CYPRESS_SHOT_DIR` had already established the
environment convention in this codebase; this follows it.

**It resolves real records, not fixtures.** The requested screen gets a tree pulled out of the shipped
195,309-row seed, nearest `MapLayout.defaultCentre` — the map's own opening camera — so the trees these
tests read are the trees a beta tester sees on launch. `ScreenSweepShots` already photographs the
preview fixtures; a UI test that also used them would prove the fixtures are accessible. Ordering is
`TreeQueries.nearest`'s, by distance from a fixed point, so the same record is chosen every launch and
a failing test names a tree somebody can go and look at.

**A failure draws itself.** This is the part that matters most and is easiest to get wrong. The
obvious behaviour when resolution finds no record is to do nothing and leave the app on screen 01 —
at which point all fourteen tests pass, because screen 01 *is* accessible, while each reports the name
of a screen it never visited. So `DebugDeepLink.Failure` is rendered over the app in words, and the
test reads the banner: a typo'd screen name produced
`DEEP LINK FAILED · activityy · no screen by that name` rather than a green run. `RootView` applies
the link exactly once per launch, because `.task` re-fires on reappearance and a re-fired deep link
pushes a second copy of the screen under the first — which also looks exactly like a passing test.

**What the fourteen tests found: nothing unlabelled, anywhere.** The accessibility tree of each screen
was dumped and read before a single assertion was written — 188 interactive elements across the
fourteen, every one of them labelled. (188 is the count in the dumped trees; the tests assert over the
*hittable* subset of that, which excludes what is scrolled off or behind a cover.) The M4 VoiceOver
pass and E103/E104 held. Two things were confirmed rather than fixed, and both are worth naming
because the suite now pins them: the `fullScreenCover` behind 09 and 10 **does** take the map out of
reach of assistive technology (`testAModalIsolatesTheScreenBehindIt` — the map's chrome stays in the
hierarchy by design, but nothing behind the cover is hittable), and every pushed screen carries a
Back control that is both present and activatable, so no screen is a trap for a user who cannot
perform a swipe-back gesture.

**Screen 19 could not be tested, and the reason is the data.** The shipped seed holds exactly two
statuses — 182,791 `alive` and 12,518 `vacant_site`. There is no `removed` tree in it and therefore no
record on any device that `MemorialView` could honestly be opened with. Resolving a memorial against a
living tree would draw a REMOVED record over a standing tree, which is a lie of precisely the kind
this suite exists to catch, so the harness has no `memorial` case at all. Screen 19 stays covered by
`ScreenSweepShots`' fixture and by its unit tests, and it is **unreachable from real data until a
status transition can occur** — which needs the moderation path (DECISIONS §3.7), not a test. Screen
04 is absent for a different reason: presenting the camera raises a system permission alert, and what
the test would then read is Springboard's accessibility tree rather than Cypress's. Screen 15 is
absent because `BetaCapability.accountsAvailable` is false (R4) and a harness that opened it would be
reaching past the gate the build ships behind.

**Three negative controls, because a UI suite green against correct code proves nothing.** Each was
run, seen red with its intended message, and reverted: a typo'd screen name (the failure banner, as
above); the modal test pointed at a tab root, where the bar *is* reachable, reporting "the Map tab
behind the cover can still be activated"; and `ScreenHeader`'s Back label blanked in the app itself,
reporting "a button at (18.0, 69.0, 44.0, 44.0) has no accessibility label". That third one is the
E103 failure mode reproduced deliberately, and the suite named the offending frame.

**Proved compiled out of Release.** The whole of `DebugDeepLink.swift` and its `RootView` call site
are `#if DEBUG`. Xcode 16 puts Debug app code in `Cypress.debug.dylib` beside a 57 KB stub, so an
early check that grepped the Debug *stub* found zero occurrences and looked like a pass while
measuring nothing — the control string was absent too, which is what caught it. Against the right
artifacts: the Debug dylib carries `CYPRESS_SCREEN` (1), `DEEP LINK FAILED` (1) and 169
`DebugDeepLink` symbols; the Release binary carries zero of all three while carrying the control
string. A comparison whose control does not fire is not a comparison.

**One pre-existing warning fixed in passing.** `ProfileFavoriteWriter` called `try? await
FavoriteOutboxWriter.save(...)` bare. `save` is `@discardableResult`, but `try?` re-wraps its receipt
in an `Optional` that is not, so the app target had been building with a "result of 'try?' is unused"
warning since E112. It is `_ = try? await` now. The zero-warning line this project holds had been
verified on the test targets and not on the app.

### E118 — a caption read twice; and a reading-order test that invented a defect out of an API's match order

E117 closed by naming what it had not checked: "**reading order and grouping** — that the elements come
in the sequence a person expects." Going after that found one real defect and one imaginary one, and
the imaginary one is the more useful entry.

**Real: a caption announced twice, on screen 03 / 14.** The empty photo well is a decorative circle, a
camera glyph and the sentence `No photos of this tree yet`. SwiftUI exposed the *container* carrying
that sentence as its synthesized label **and** the caption inside it carrying the same words, so
VoiceOver read the sentence and then read it again. This is E104's failure mode, and it survived E104,
the M4 VoiceOver pass, E116 and E117 — because every one of those asked whether a label *exists*, and
none asked whether the same words appear twice on one screen. Fixed with
`.accessibilityElement(children: .ignore)` and an explicit label: `.ignore` drops the descendants
rather than merging them, which is right because the glyph is decoration in the sense C16's tab icons
are — it repeats the sentence directly beneath it.

The check is written as **containment, not repetition**. Two different rows may legitimately say the
same words; one element drawn *inside* another saying them is the defect. Written as adjacency it
would have fired on the species-share rows, which are correct.

**Imaginary: `XCUIElementQuery.allElementsBoundByIndex` is not reading order.** A companion test
asserted that every pushed screen leads with `Back` and its own title, and it reported that screen 05
leads with `Save check-in` and its intro sentence instead. That was written up as a real defect and
pinned with `XCTExpectFailure` — and it was wrong. The accessibility hierarchy has `Back` at position
19 and `Save check-in` at position 65; geometrically Back is at y=69 and Save is pinned at y=710. A
direct probe confirmed `Back` is `exists=true hittable=true` and that the query nonetheless returns
`Save check-in` first. **The sequence of `allElementsBoundByIndex` is the query engine's match order,
and it agrees with neither the element tree nor the screen.** Any reading-order assertion built on it
manufactures defects.

The test was deleted rather than repaired, because a sound version needs VoiceOver's actual traversal —
a recursion over the element tree — and inventing one under a budget is how the first mistake happened.
`testNothingIsAnnouncedTwice` still calls `allElementsBoundByIndex`, but only as a **set**; the
restriction is written at the call site so the next person does not re-derive this the expensive way.

**What almost happened is the point.** An `XCTExpectFailure` is a durable claim that a defect exists: it
sits in the suite, prints its message every run, and tells every future reader that screen 05 is broken.
Shipping one for a defect that does not exist is worse than having no test, because it corrupts the
record rather than merely failing to improve it — and it would have looked *especially* trustworthy,
since the suite stays green and the log carries a confident explanation. It survived a full green run
(434 tests, 433 passed, 1 expected failure) before the dump was re-read and the claim collapsed. The
thing that caught it was not a test: it was noticing that two artifacts disagreed and refusing to
believe the newer one just because it was mine.

**Resolved, in the same session.** The sound version of the deleted test now exists, and the fix was
the *source of the order* rather than the assertion. `XCUIApplication.debugDescription` is a depth-first
rendering of the real element tree — the same artifact E117's screen dumps were read from — and one
call returns all of it, which matters because recursing `children(matching:)` costs an IPC round trip
per node.

The method was validated **before** it was trusted, against the fourteen dumps already on disk: the
parser was run over them offline and predicted `Back` first and the correct title on all nine pushed
screens. The live run then agreed. That is the ordering of operations E118 got wrong the first time —
predict from an independent artifact, then run — rather than run, believe, and write it up.

Two costs are accepted and written at the call site. `debugDescription` is a debugging format Apple
does not version, so an Xcode upgrade can change it; the failure is at least loud, because a format
change parses to nothing and trips a count assertion rather than passing vacuously on an empty list.
And a green order test is worth exactly what the deleted one was worth unless something proves it can
see a *wrong* order — so `testTreeOrderParserReportsAnInvertedTree` feeds the parser a synthetic tree
in which the save button precedes Back, and asserts the inversion is reported. It needs no simulator
and runs in 0.16 s, so the logic stays verified without a three-minute launch, and it pins the awkward
real cases too: a trailing `, Selected` trait, a `, value: 0%` suffix, an apostrophe inside a cultivar
name, and the `Path to element` footer that must not be counted twice.

**Screen 05 is confirmed correct** by the method that replaced the one that accused it.

**Grouping, the third and last structural question — and the same trap a second time.** E116 and E117
asked whether elements are *labelled*; the duplication check above asked whether anything is said
*twice*; grouping asks whether things that belong together arrive together.

Screen 03's stat grid did not. Its one **interactive** card read as a single element — a `Button` forms
one out of its content — while the four beside it, drawn identically, read as two and three: `DBH`,
then `30–35 cm`, then `from the city record`, three unrelated fragments with the number severed from
the word that says what it measures. Two cards that look the same behaved differently, and the
difference was invisible to everyone who could see them. `StatCard` now carries
`.accessibilityElement(children: .combine)` — `.combine` and not `.ignore`, because the value is the
point rather than decoration.

**The first version of the test failed on correct code, for E118's exact reason.** It asserted the
*absence* of the bare caption: after combining, `DBH` should survive only inside a longer label. That
can never hold, and the evidence was already on disk before the test was written — E117's dump shows
`Button 'Height, Add a reading'` listing `StaticText 'Height'` and `StaticText 'Add a reading'` as its
children, and a `Button` unquestionably forms one accessibility element. **XCUITest enumerates the
children of combined elements too.** Its tree is not VoiceOver's stop list, which is the same fact that
invalidated the reading-order test, met from a different direction.

So the assertion is positive: an element reading `DBH, 30–35 cm, …` exists only if the caption and its
value were merged, so the test asserts the *whole is present* rather than that the parts are gone. Its
negative control needs no run — the pre-fix dump contains zero labels of the form `DBH, `, so the test
would have failed before the change.

**The generalisable rule, now twice paid for:** XCUITest can prove an element *is* in the tree with a
given label. It cannot prove an element is *not a VoiceOver stop*, because the tree lists elements the
accessibility runtime merges away. Every assertion here must therefore be phrased as the presence of
something correct, never as the absence of something wrong.

### E119 — the map was the last surface still calling a planting basin a dead tree (R7)

E107 gave the vacant planting site its own screen; E113 stopped the tree profile from opening one;
E115 stopped the almanac from naming one as a tree. Each of those removed the same claim — that a tree
had been here and was gone — from a surface that was making it about 12,518 records that never held
one. The map kept making it, and the map is where those records actually live.

`MapPinKind.kind(for:)` returned `.removed` for `.vacantSite`, so a basin drew as the memorial's grey
dot. **E107 fixed only half of this and said so**: it wrote the `accessibilityLabel` override, so the
pin *said* `Planting site, no tree` while *drawing* a memorial, and recorded why it stopped there — "a
new pin is a design decision and C1–C30 is a closed catalogue". That is a constraint-21 refusal, and
it was the right call at the time. The decision has since been delegated (RULINGS R7), so the drawn
half is now fixed and the two halves agree.

**Hollow, not a second grey.** `MapPin.Kind.vacantSite` keeps the memorial's 16pt footprint and its
muted shadow, and draws with **no fill at all** — a ring in `borderDashedStrong`, the token the
vacant-site screen and the empty photo well already speak, so nothing is added to the palette. An
absence of fill reads as an absence of tree without anyone having to learn a colour, and it cannot be
confused with a filled dot at any size, which a second grey could.

**Solid ring, not dashed**, even though the ruling reached for the dashed *family*. Dashes already mean
the community layer (DECISIONS §3.16), and a dashed hollow ring would read as an unverified community
tree — trading one wrong claim for another. `borderDashedStrong` is used here as a colour, not as a
stroke style.

**The label override survives on purpose.** With a dedicated kind it looks redundant, and
`MapPin.Kind.vacantSite` does carry a sane default. But the words a basin says belong to the feature
that owns basins, and a `DesignSystem` component must not reach into `Features` for a string — so the
catalogue keeps a default that must never claim a tree was here, and `MapPinKind` keeps overriding it
with `SiteCopy`'s wording. The override's guard changed from `pin.status == .vacantSite, kind == .removed`
to `kind(for:) == .vacantSite`, which preserves the case E107 was careful about: a *community-added*
vacant site still resolves to `.community` first, keeps the dashed pin, and keeps the community label.

**The test now pins both halves.** `sitePinAnnouncesItself` asserted only the spoken label, and its
doc comment still said the drawn pin "is still the memorial's grey dot" — true when written, false
after this change, and the kind of stale comment that outlives the thing it describes. It now asserts
the kind as well, and that `vacantSite.fill` is `.clear` and differs from `.removed`'s — because the
absence of fill *is* the distinction, and an absence is exactly what a screenshot nobody diffs will
not catch.

### E120 — the C10 exemption rested on a label nobody can see; C23 is deferred on a measurement, not on taste

R8 delegated the two contrast pairs R1 left to design — the C10 locked glyph and the C23 chart series
on a dark card, both under 3:1. One turned out to be a mislabelled defect and the other turned out to
be a genuinely harder problem than the ruling assumed.

**C10: the exemption was wrong.** E8 recorded the `?` at 1.84:1 light and 2.12:1 dark and exempted it
because "the `?` is decorative, the tile's meaning is in its label". Checking that sentence against
`SpeciesTile` is what reopened it: the `.locked` case draws the `?` **and nothing else**. The label the
exemption means is `accessibilityLabel`, which returns `Species not yet learned` to VoiceOver and is
invisible to a sighted reader. So the glyph is not decoration sitting beside a caption — it is the
entire visible content of the tile, and the only thing that distinguishes a locked tile from a blank
plane. WCAG 1.4.11 binds, and a low-vision user was being asked to find a 1.84:1 mark with nothing else
to go on.

Fixed by **lightness only**, holding chroma and hue in OKLCh — R1's method, so the glyph stays the grey
green it always was. `#A8B29C ↔ #4C584B` → `#7F8974 ↔ #647062`, landing at 3.06:1 and 3.05:1. The tile
fill does not move. The pair left `knownFailures` for `retinted`, where the suite pins the exact
ratios — which is what independently confirmed the arithmetic, rather than the arithmetic confirming
itself.

**C23: deferred, and the reason is a number.** The ruling assumed a lightness move would do, with a
dash pattern as an optional extra. Measured, the move is not free: taking series 1 (Canopy `#2F6B4F`)
to 3.05:1 on the dark card means `#3C785B`, which costs **38% of its OKLab separation from series 2**
— 0.117 down to 0.073, and both are greens. `ActivityView` draws all three series at once (photos,
check-ins, care), so that separation is load-bearing rather than theoretical.

R8 pre-authorised the compensator: a non-colour encoding, which is owed anyway because a chart
separated only by hue is unreadable to a colour-blind reader at *any* ratio. But a dash belongs to a
**stroked** mark, `ChartCard`'s `LineChart` strokes polylines while 13's three series are drawn through
a different path, and applying a stroke dash to the wrong mark type is a design change made by
guessing. **Shipping the lightness move alone would trade one failure for another** — better contrast,
worse discrimination — so neither half ships until both can.

The `knownFailures` entries now carry that reasoning and the measurement instead of E8's original
"escalated as a set", so the next person picks it up knowing what it costs rather than re-deriving it.

**A note on how this went, because it is the fourth time today.** Four premises were checked against
the code before building and three were wrong: R6's defect was already fixed, R9's "weights" were
colours, and C10's exemption was backwards. The one that nearly slipped through was the opposite —
a grep suggested `chartSeriesSecondary` and `chartSeriesTertiary` were drawn nowhere, which would have
made the separation question moot and the whole C23 fix trivial. That conclusion was written down
before the output was read properly: `ActivityView` uses both, on screen 13. **The check is worth
nothing if its result is announced before it is read.**

### E121 — screen 12 now says the one true thing it can about the 12,518 basins (R10)

E115 proposed a block and did not build it, listing exactly what a designer would have to decide: a
title, a subtitle rule, a tile accent SCREENS.md never assigned, and a position relative to §4. R10
made those calls and this builds it.

**What it says.** A micro-label `Where a tree could go` — ROADMAP §1's own phrase for these rows,
chosen over anything with `needed` or `gap` in it — over one C10 row: `1,474 empty planting sites`,
subtitle `The city has mapped them. Nothing is growing there.`, tapping to the nearest site on
`Route.site`. The subtitle inherits `SitePresentation`'s two-part line and stops where it does: no
`yet`, no ask to plant, no implication anyone has been told (ARCHITECTURE §5.4). Cypress keeps the
record of what is planted; it does not plant.

**Where it sits, and why not in §4.** After §3, before §4. §3 says what lives in the neighbourhood;
this says where nothing does — two readings of the same canopy, kept adjacent. §4 stays the screen's
one *directed ask*, the last thing before the footnote, and a plain row before its amber card reads as
the statement it is rather than as a second ask. E115 drew this line first: a vacant site takes no
visit, observation, measurement or care event, so an ask pointed at one is a `Walk to it` ending at
bare pavement — the "sent to the city" defect. This block only counts and offers to show the nearest.

**The query is the one read in `AlmanacQueries` that inverts `standing`.** Every other read asks for a
tree the city believes is standing; `vacantSites` asks for the basins that are its opposite, counting
`status = 'vacant_site'` in the neighbourhood and returning the nearest by squared distance from one
scan. The nearest is scoped to the *same* neighbourhood, so the tap can never route the reader from
one basin to a basin in the next neighbourhood over — subject and destination are one set. Because it
counts city records rather than user actions, ARCHITECTURE §5.1's "a count of actions wearing a
different noun" trap does not apply and it needs no A8 floor; it draws on a fresh install exactly as
the species mix does.

**The tile accent adds no hue.** `TileAccent.vacantSite` is composed from tokens the vacant-site
family already owns — `surfaceEmptyThumb` as its ground, `borderDashedStrong` as its mark — the same
dashed-ring vocabulary R7 gave the map pin, the site screen and the empty photo well (E119). Reusing
`elder` or `newGrowth` would paint a hole in the pavement in a living tree's colour, the exact
category error R7 removed from the map.

**Proven, all against the shipped seed.** `AlmanacVacantSiteTests` gains: the count is 1,474 in
Sunset/Parkside (E115's own measurement, now the query's), the nearest really is a `vacant_site` and
really is in that neighbourhood, the presentation states the count and inherits the site line, a count
with no destination does not draw (no statement the reader cannot act on), a neighbourhood with no
basins does not draw (§5.6, though E115 found none like it), and one basin reads in the singular.

**A note on a self-inflicted near-miss.** A grep for `chartSeriesSecondary` in the previous entry
looked empty and I wrote the conclusion before reading the output — it was not empty. Here the same
discipline was applied correctly the other way: the first cut of the query test failed not because the
query was wrong (the count was already 1,474) but because the verification lookup compared an
uppercase `uuidString` against the seed's lowercase ids without `COLLATE NOCASE`. The failing
assertion named which side was empty, so the test's own bug was visible rather than the code's. A test
that fails loudly about itself is worth more than one that passes quietly about nothing.

**Looked at, on a real device against real data.** Verified not from a fixture but by deep-linking the
running app (`CYPRESS_SCREEN=journal`, E117's own harness, with the simulator's location set inside
Sunset/Parkside): the block draws `1,474 empty planting sites` — the seed's true count, the same number
the query test pins — sitting between `Who lives here · 215 species` and the amber `Where eyes are
needed`, exactly where R10 placed it.

**One observation the screenshot made that no test would have.** The tile is *very* faint: its ground
is `surfaceEmptyThumb` on a `surfaceCard`, about 1.05:1, so it reads as an almost-blank square with a
pale smudge in it. Semantically that is the point — it is the empty photo well's vocabulary, and a hole
in the pavement should not glow — but it sits close to reading as a failed image load rather than as a
deliberate absence. It is left as drawn, and recorded here as the one part of this block a designer
should look at with fresh eyes. The alternative (lifting the ground toward the other five accents)
would buy legibility by making a basin look like a living thing, which is the trade R7 and E119 both
refused.

**The screenshot suites did not run in this verification, and were not made to.** Four tests failed in
the full run — `01–19 …`, `18–21 …`, `the cold and empty states`, `every screen renders at both ends of
the ramp` — every one of them killed with `signal term` rather than failing an assertion, after the
machine throttled far enough that single sweep tests were taking 600–2,950 s. They assert nothing (they
write PNGs), the other **435 tests passed**, and the visual claim above rests on the live render rather
than on them. Recorded so that a later reader does not mistake a green count for a suite that ran whole.

### E122 — C23 needed no dash, the vacant tile needed to be visible, and R9's collapse turned out to be a trap

Three of the delegated design calls, resolved together because all three are token-layer.

**C23 (R8): a plain lightness fix, not the deferred dash.** E120 deferred C23 believing the three chart
series were "separated by hue alone" and would need a non-colour encoding. Looking at `ActivityView`
showed the premise was wrong: screen 13 draws the series as **three spatially-separate, text-labelled
strips** — each `ChartSeriesLegend` names its series (`Photos` / `Check-ins` / `Care`), and each
`BarChart` carries a VoiceOver label reading its months. A colour-blind reader already tells them apart
three ways before hue enters it, so the pre-authorised dash solves a problem that does not exist, and
the 38%-separation-loss E120 measured is moot because the series never share a visual space.

So C23 is the same fix as C10: **lightness-only in OKLCh, dark value only.** `chartSeriesPrimary`
`#2F6B4F ↔ dark #3C785B` (2.53 → 3.05), `chartSeriesTertiary` `#7A4F33 ↔ #8F6346` (2.27 → 3.06); light
is untouched (6.29 / 7.01) and `chartSeriesSecondary` already passed (4.13). Both moved from
`knownFailures` to `retinted`, which pins the exact ratios. The tokens changed from `escalated` to
`overruled`, which meant relocating their registry rows from `escalatedTokens` to `overruledTokens` —
the escalated invariant is "resolves the same in both appearances", and these now deliberately do not.

**The vacant tile (R10 follow-up): visible, still not alive.** Looking at the shipped screen 12 showed
`TileAccent.vacantSite` reading as an almost-blank square: its ground was `surfaceEmptyThumb`, ≈1.05:1
on the card. Base and highlight are swapped — `borderDashedStrong` is the ground now, `surfaceEmptyThumb`
the dished centre — so the tile is a present muted grey-green basin, clearly distinct from the card and
from the living elder tile beside it, while adding no new hue and no life colour. Verified by
deep-linking the running app to the journal tab against the real seed.

**R9 (amber borders): declined, and the reason is a trap the ruling could not see.** R9 read "three
amber border weights come apart; collapse to one." Checking the tokens before building — the discipline
that has now caught six of these — found the collapse to be some mix of no-op, already-done, and
actively harmful:

- The tokens R9 *names* (`borderAmberMid`, `borderAmberStrong`) have **zero call-site uses**. Collapsing
  them changes nothing drawn.
- The amber borders actually drawn are a different set, and two are load-bearing. `amberAttentionCardBorder`
  was **deliberately darkened by R1** (`overruled` to `#B8803A`) for contrast; `hazardPanelBorder`
  (`#E0B070`) is the 311 panel's whole boundary, pinned in `knownFailures` because "the border is the
  whole boundary". Collapsing either toward the paler ambers **undoes deliberate contrast work** —
  R9 would re-break what R1 fixed.
- **Dark is already collapsed.** Every amber border derives to `#D99A4E` after dark (E8). The only
  divergence is among light decorative pales on non-adjacent components.

There is no beneficial collapse to make: the redundant tokens are dead, the distinct ones are distinct
on purpose. Executing R9 as written would have weakened two contrast decisions for a cosmetic change
invisible in normal use. It is declined rather than built, recorded here and in RULINGS R9. This is the
sixth ruling this session whose premise did not survive contact with the code — and the first where the
right answer was to *not* do the requested change, because doing it would have caused harm a screenshot
on a throttled machine might not even have caught.

### E123 — the one empty state a tap can fill now offers the tap (R11 residual, #4)

R11's survey (recorded in RULINGS) found the app's empty states already discharged by §5.6 restraint
plus explicit `…yet.` copy — with **one residual**: a device with no location fix leaves the almanac
and screen 07's `Near you` blank, and that is the single empty state a *user action* would fill, because
granting location is something the reader can do. E44 chose silence there, but its reasoning was about
the header *pill* naming an area it could not determine, not about a prompt beneath it. The project
owner ruled to show the prompt; this builds it.

**`LocationPrompt`** is a tappable card in the dashed-ring vocabulary the vacant-site family already
speaks (`borderDashedStrong`, `surfaceEmptyThumb`) — so the one place the app breaks §5.6 silence still
looks like the rest of it. The almanac shows `See your neighbourhood / Turn on location and the almanac
fills with the trees around you`; screen 07 shows `See it near you / Turn on location to find this
species on the blocks around you`. Tapping calls `onRequestLocation`, wired by the composition root to
`MapLocationProvider.start()` — the same provider screen 01 asks with, so a grant here reports fixes
everywhere. On a device that already refused, `start()` is a safe no-op.

**The condition is `coordinate == nil`, computed at the view layer, not in the presentation.** A nil
fix yields no neighbourhood and therefore an empty almanac, so "no fix" and "the screen would be blank"
are the same condition — the prompt takes the place of the blank rather than sitting beside content.
Because it is a view decision rather than a derived value, it carries no presentation test; it was
verified by **looking** — deep-linking the running app to the journal tab with location cleared, and
seeing the prompt stand where the blank used to be.

**One known limitation, left as-is.** `AlmanacModel` loads once from the coordinate it was built with,
so granting location while standing on the almanac does not reactively reload it — the content appears
on the next visit to the tab rather than the instant the permission is granted. Reworking the almanac
to observe location changes is a larger change than this prompt, and the prompt is honest either way:
it says "turn on location", which remains true, and the reader reaches the filled screen by the next
navigation. Noted here so it is a known behaviour rather than a surprise.

### E124 — screen 15 signs people in, locally (RULINGS R4, #1/#2 Part A)

RULINGS **R4** gated screen 15 behind `BetaCapability.accountsAvailable = false`: the ask was built
and tested but could not *complete*, because authentication is magic-link only (DECISIONS §3.9, no
passwords ever) and a magic link needs a server the local beta does not have. The project owner ruled
to unblock it — "can we not just live with having no backend for now… it's me on my phone playing
around" — with the correction that mattered: the dead-end was never the account, it was the round
trip. A local account needs no server.

**What this changes.** `accountsAvailable` flips to `true`, and the composition root supplies the
`onLink` action screen 15 was always written to receive (`AccountAskModel` has taken an injected
`AccountAskLink` since it was built). `RootView.accountLink()` mints a `userID` and calls the existing
`claimDevice(deviceUUID:userID:)` seam, which moves this device's anonymous contributions onto that id
and persists it in `app_state` — the same mechanism `DeviceClaimTests` already proves. No email is
sent and none is stored: the request's address is ignored, so §3.9's "no passwords, ever" and §3.11's
"private by default" are kept by construction. The action is `nonisolated` and threads
`RootView → VisitFlowView → VisitSavedView → AccountAskView`, because who performs a sign-in is the
composition root's question, the same boundary that already resolves `attribution` there.

**A local account is an identity, not a backup.** There is no cloud behind it, so screen 18's storage
line stays "saving to this phone only" after sign-in — which is now honest rather than a placeholder.
When the magic-link service lands, `accountLink()` swaps its body for the client half of the token
exchange and nothing on the call path changes. Sign-in is idempotent on identity: if the device
already carries a `userID` (ERRATA E34 can re-present the ask once), it is reused, so a second link
sweeps freshly-anonymous rows onto the same account rather than minting a rival.

**Tests.** `BetaCapabilityTests` is rewritten from "this build cannot sign anyone in" to the live
wiring (the shipped flag earns the ask by the third save) while keeping the `mayAsk:` contract that
outlives the flag's value. `AccountLinkTests` is new and closes the one gap the flag flip invited: the
model is correct and `claimDevice` is correct, so a build that flipped the flag but left `onLink` nil
would present a sheet whose every button says "not ready yet" and *no existing test would fail*. It
exercises `RootView.accountLink()` directly and asserts sign-in completes, persists, and carries the
device's work across.

**What is deferred.** Screen 15's only entrance is the third visit-save, which runs through the camera
(deferred to the owner's hardware), so live end-to-end verification waits on that. The seam is proven
by tests at every layer instead. This is Part A of the accounts/moderation work; Part B — a role on
the local account, mocked city-lead accounts, and a moderation surface that flips a flagged tree to
`removed` so screen 19's memorial goes live — is the larger build still ahead.

### E124-B — the local moderation route: report → confirm → memorial (#1/#2 Part B)

The project owner's moderation route ("designate some people as community leads and they can verify
removals"), which finally makes screen 19 reachable from real data. It crosses a boundary the app was
built behind, so the design is deliberate: **the iOS client never transitioned a tree's status**, by
construction. Seed trees are read-only (ATTACHed), `community_trees` is insert-only, and confirming a
review flag into a status change was a web `/admin/*` deliverable `CypressAPI` omits on purpose. The
local beta has no web, so the confirmation happens on-device — without corrupting the read-only seed.

**A status-override layer, not an UPDATE.** A new `tree_status_overrides` table (migration v7) records
that a tree's status has been locally moved, keyed on its stable UUID. `LocalAPI.mapContent` and
`treeProfile` read the inventory, then layer the override on top — so a confirmed-removed tree becomes
a memorial pin and a memorial record while the seed row it came from is never touched. This is the
exact shape the future weekly city diff would take; when a real diff or moderator service lands, it
writes through the same table.

**The loop.** A "Removed?" check-in (screen 05's `appears_removed` segment) opens a review flag, the
way it always did. A lead sees it in a new **Reviews** section on the You tab — drawn only when the
signed-in account `canConfirmReviewFlag`. Confirming moves the flag to `confirmed` and writes a
`removed` override in one transaction (`LocalAPI.confirmRemoval`), gated so a member or steward gets
`.forbidden` on the write itself, not merely a hidden button. The tree's map pin becomes a memorial,
its profile becomes a memorial record, and screen 19 — unreachable since E117 for want of a removed
tree — opens over it.

**The role, with no `users` table (ERRATA E86).** Carried in `app_state` like the user id, read at
boot, cleared on account deletion. There is no server to grant it and no separate account to seed a
mock lead into, so the promote path is a DEBUG-only row in the You tab: the owner stepping into the
mocked city-personnel lead role to verify removals. `#if DEBUG`, so Release has no self-promote — a
real moderation grant is never the account's own to make.

**Verification.** `ModerationTests` (6, data layer) prove the full loop, the map memorial pin, the
role gate (member *and* steward forbidden), the double-confirm conflict, and role persistence.
`DeepLinkVoiceOverTests` gains `testMemorial` and `testModerationReview` — screen 19 finally has its
accessibility tree read like every other deep screen, discharging E117's
"unreachable-until-the-data-changes". Both surfaces were also looked at running: the memorial renders
"Removed by the city…" over a real Southern Magnolia; the You tab shows the review card with a Confirm
button and the DEBUG lead controls. 426 unit tests pass.

**Known boundary, left as-is.** The override is applied where the memorial loop needs it — the map's
pins and the tree profile — not in every aggregate read. A locally-removed tree can still be counted
in an almanac stat or a "near you" list until those layer the override too. Noted so it is a known
edge rather than a surprise; the loop that delivers the memorial is complete.

### E125 — the app had never drawn a photograph, and the reason was a protocol extension

Four owner reports from a phone, which turned out to be one shallow bug, one layout bug, and two
halves of a hole where a whole feature belonged: the ghost overlay showed the tree even when the
subject was TRUNK or LEAF; the log-visit tray ran off the right edge once the ghost appeared; a tree
had no hero image; and there was no way to browse a tree's photographs or say which one should lead.

**The ghost.** `VisitCameraModel` decided the overlay, the subject pill and the caption in three
places, so they could disagree — and did. One rule now: `shotType.supportsGhostOverlay` gates the
layer, and the caption says "overlay off · full-tree only" rather than describing a layer that is not
there. Ghosting a trunk against a whole tree's silhouette was never guidance; it was noise over the
one thing the photographer was trying to frame.

**The tray.** `Image.resizable().scaledToFill()` reports the *scaled* size, not the proposal, so a
3024×4032 photograph measured 627 pt wide against a 393 pt proposal — and the parent laid the note
field and the Log visit button out against 627. Measured with `NSHostingController.sizeThatFits`
before touching anything, and again after. `PhotoFill` is the fix and the reason it exists:
`Color.clear.overlay { … }.clipped()` reports the proposal, so a photograph can never again push a
sibling off the screen. Camera, hero and browser all draw through it.

**The hole, and the trap under it.** There was no hero because **no photograph rendered anywhere in
the app except screen 04**, which holds the image it just captured in memory. E37 gave `Photo` the
predicates that say who may see what and never gave anybody the bytes. So `photoData(id:)` and
`setPhotoVote(photoID:vote:)` went onto the API, `PhotoImageStore` downsamples and caches them,
screen 03 leads with one, and screen 20 — new — is the only screen in the app where a photograph is
the subject rather than the backdrop. The vote is A3's long-dead "a manual pin by any org member
overrides", finally spelled as the thing a person actually does: keep this one, not that one.
`PhotoHero.choose` in `Core` is the single rule both screens ask, and `AppSchema` v8 (`photo_votes`,
exactly-one-owner CHECK, two partial unique indexes) is where it is written down.

**The lesson, which cost a shipped defect.** Both methods were first declared *only* in
`public extension CypressAPI`. That compiles, reads as a protocol with defaults, and is a trap: a
member that exists solely in an extension has no witness-table entry and dispatches **statically**.
Every screen holds `any CypressAPI`, so every call reached the extension's `throw APIError.notFound`
and `LocalAPI`'s real implementation was unreachable code. The whole suite was green — my tests held
the concrete type, and the two UI tests anchored on the string "Best photo", which renders perfectly
while every image on the screen is a gradient. The owner found it in thirty seconds on a phone:
"i did rebuilt and i did a photo all i see is the standard blurry image". Both are now declared
requirements; `PhotoHeroTests.worksThroughTheProtocol` erases to `any CypressAPI` on purpose and
fails if anyone reverts it; and `speciesGuide`, `almanac`, `groveSpecies` and `deviceContributions`
were audited and were already declared, so the hole was confined to this work.

**A second rule, learned from a suite that went red.** The photo deep links seeded photographs onto
`standingTree` — the tree nine other cases open — and seeding is persistent, so screen 03 stopped
being cold and four `DeepLinkVoiceOverTests` began failing on a title that had become a species name.
They failed only in whole-suite order, which no single-test run reproduces. `photographedTree` takes
`.last` instead, mutating from the far end while `.memorial` mutates from the near end, with 456
standing records between them. The rule, for whoever adds the next case: **a case that writes
persistent state must not write it onto a tree another case reads.**

And its corollary, which took a second red run to learn: **a case that writes persistent state must be
idempotent.** `debugSeedPhotos` was append-only, so two launches left six photographs and three left
nine — a container reached twelve during one suite run — and a vote cast by hand on the way past
outlived every launch after it. `testAThumbActuallyVotes` requires the hero to start on the top card
and found it on the second, because an hour-old manual up-vote was still the hero. It now clears the
tree first: its photographs, their votes, and their files, verified stable at three across repeated
launches starting from the twelve-photograph container that broke it. A harness whose state depends on
how many times it has been run before is not a harness.

**Verification, and why the fixture is garish.** The seeded JPEGs were at first a flat dark green —
sensible-looking and useless, because a flat green photograph behind the hero's legibility scrim
renders as a dark green vertical ramp, which is exactly what `CypressGradientField` draws when there
is *no* photograph. Looking could not tell the fixed app from the broken one. They are now saturated
magenta, orange and cyan with a hard white bar across the middle; nothing in Cypress draws that.
Screens 03 and 20 were then launched over a freshly installed container and photographed, with a
cold tree as the negative control: the control shows the dashed "No photos of this tree yet" well,
screen 03 leads with the magenta frame, and screen 20 lists all three. The full suite passes — unit
tests plus 26 UI tests, including the four that the seeding defect had broken.

**And then the thumbs did not work, for a third reason nobody would have guessed.** Every tap on
every thumb in the list did nothing: no vote, no error, no filled glyph. The buttons were in the
accessibility tree, correctly labelled, and `isHittable` reported true. The cause is the other half
of the bug `PhotoFill` was built to prevent — **`.clipped()` clips drawing, not touches.** The
overflowing `Image` keeps its full scaled footprint for hit testing, so SwiftUI routes taps to pixels
it never painted. Measured on screen 20: a 361 × 217 pt box holding a 3:4 photograph reports an
element 361 × 481.3, leaving 132 pt of invisible photograph hanging off each end. Screen 20 stacks
photograph, then caption-and-thumbs, then the next photograph — and the next photograph is later in
the `VStack`, so later in z-order, so its unpainted upper overhang lay on top of the previous card's
thumb row and swallowed every tap. Every thumb in the list was dead *except the two on the last
card*, which has nothing drawn after it; that asymmetry is what proved the diagnosis before a line
was changed. The fix is `.contentShape(Rectangle())`, and it belongs in `PhotoFill` rather than at
the call site: the promise that component makes is that a photograph occupies the box it was given
and not one pixel more, and a touch footprint is one of the ways a view occupies space. Screen 04
had already patched the same leak by hand with a local `.allowsHitTesting(false)`.

Two lessons compound here, and they are the same lesson. `isHittable` was true throughout, because
the accessibility hit test resolved to the button while the touch hit test resolved to the photograph
on top of it — so a test could confirm the control was reachable by every measure it knew how to
take, and the control still did nothing. Both defects in this entry were found by a person tapping a
running build. The regression test that now guards it, `testAThumbActuallyVotes`, therefore asserts
the *consequence* — it votes the top card down and requires the `Hero` badge to move off it — and it
targets the top card deliberately, because a test that had picked the last card would have passed
throughout the entire period the feature was broken. 447 unit tests and 27 UI tests pass.
### E126 — the two tab roots that drew a blank when they could not read

Both `GroveModel.Phase` and `AlmanacModel.Phase` keep `.failed` as its own case, and both say why in a
comment: an empty grove means "you have not met a species yet" and an empty almanac means "nothing is
happening in your neighbourhood", while a failed read means "we could not tell". `AlmanacModel` calls
its screen "the last place to conflate them". Both views then conflated them, by having exactly one
branch: `if let presentation` with no `else`, and `presentation` is nil for `.loading` and `.failed`
alike. `hasFailed` was written for this and had **zero readers anywhere in the codebase**. A failed
read therefore drew the cold-start screen — title, tab row, footnote, nothing between them — which is
a designed, legitimate, common state, so the failure was invisible by construction rather than ugly.

**The fix is the shape every other failed read in the app already has.** One sentence, then a `SecondaryOutlineButton`
that re-runs the load, exactly as `ShareView.failure`, `SiteView`, `SpeciesView`, `GrowthHistoryView`
and `MemorialView` do; `retry()` on each model, which is free because neither load writes anything.
The copy is in `GroveCopy`/`AlmanacCopy` with the rest, and says only that the read failed — it
borrows no word from the empty states, because a read that did not finish has not earned a sentence
about the subject. `AlmanacScreen` takes `hasFailed` and `onRetry` as values rather than reading the
model, for the reason it takes `presentation` as one: a state the screen cannot be handed is a state
nobody can photograph.

**The verification is the point of this entry.** A test asserting `hasFailed == true` passes on the
broken app — the property was always correct — and so does a test asserting the copy string exists.
What can only pass on the fixed app is a comparison of the two *pictures*. `FailedReadTests` renders
each screen through a `UIHostingController` in an off-screen window (the harness
`DynamicTypeScreenshotTests` established) after a read that failed and after a read that succeeded and
returned nothing, and asserts the PNGs differ, with a control render proving the harness is
byte-stable first. With the two `else if` arms deleted, both went red — `(failed → 117027 bytes) !=
(empty → 117027 bytes)` for screen 08, `105045` for 12 — while all five value-level tests in the same
file stayed green. That is the defect stated as an assertion. Both screens were also looked at
running: `LocalAPI.groveSpecies` and `almanac(near:)` were made to throw temporarily, the app was deep
linked to `grove` and `journal`, and both drew the sentence and a legible `Try again` above the
footnote. The injection was removed before commit; `e08-grove-read-failed` and
`e12-almanac-read-failed` join the screenshot sweep so the states stay photographed in light and dark.

**One known limitation, left as-is.** On screen 12 a missing location fix still wins over a failed
read: `showsLocationPrompt` is checked first, so a device with no fix sees E123's prompt rather than
this sentence. That is the right order — without a fix there is no neighbourhood to have failed to
read — but it means the two cannot be seen at once, and the prompt is the one that has an action
behind it.

### E127 — a tree nobody had touched offered nothing to press, and the camera kept asking which tree

Three reports from the project owner's phone and one from the audit, all landing on screen 03. Taken
together they describe a screen that was built for a tree with a history and quietly useless for a
tree without one — which is every tree in the seed, all 195,309 of them, until somebody arrives.

**The quad row was gated on content.** Favorite, Care, Share and Report only drew once a tree had a
photograph, so the first person to stand in front of a tree had nothing to press. The owner's ruling
was "a tree no one has touched should at least offer a REPORT and CARE"; all four ship, and the two
extra deserve their reasons. Favorite is a private grove write that E89 and R2 already refuse to gate
on anything. Share renders *identically* on a cold tree: `SharePresentation` takes
`isPubliclyVisible`, nothing in the app can set `.approved`, so screen 10 draws its C22 gradient
thumbnail for every tree in the app today — which is what SCREENS.md 10 §3 specifies anyway. This
overrides SCREENS.md 14's "no quad-action row" delta, deliberately, and the reasoning lives on
`offersQuadActionRow`, the one property that decides it. The regulars row and the activity feed stay
behind `isCold`, because they genuinely would draw nothing.

**The measurement history had no entrance for the person most likely to want it** — someone who has
just taken a tree's first reading. It has one now, as a link under the stat grid rather than by
making the stat card itself navigate: a stat card is drawn as a *fact*, beside "Planted 1898", and a
card that silently changes from "Add a reading → 16" to "64 cm → 11" depending on the data is a
control that cannot be learned. The link follows the *record* and not the chart, so a reading D6 will
not plot still has a log to open.

**But the load-bearing half was that the profile never re-read itself.** `.onAppear` covers a pushed
screen; a `fullScreenCover` dismissal fires no appearance event at all. So the camera closed and the
profile went on saying "Be the first to photograph this tree" about a tree that had, seconds earlier,
been photographed. Every downstream symptom — the missing hero, the CTA that would not update, the
history link that appeared only on the next visit — was this. Found by using the app, not by a test.

**The camera kept asking which tree.** The owner, in capitals: *"it's weird to be taken to a screen
that forces me to select a tree after clicking the take a photo button WHEN I'VE ALREADY SELECTED THE
TREE."* `Route.identify` now carries an optional id — `nil` opens the identify list, an id opens the
camera for that tree — and `RootView` turned out to have been handed that id all along and to have
discarded it. `VisitFlowView` gains a `Subject` value in place of `VisitCandidate`, because a
candidate carries a distance measured from a GPS fix and this entrance has no shortlist to measure
against.

**And the way back in was a lie.** The same report insisted the add-a-tree path stay reachable. It was
worse than unreachable: "None of these? Add this tree" drew at full opacity and was wired to
`router.sheet = nil`, so it dismissed the whole flow and recorded nothing, while `LocalAPI.addTree`
sat fully implemented and tested with no caller. PROTOTYPE-FLOW drew that button *inert*, at opacity
.55, labelled "· not in this prototype"; the build kept the label and dropped the honesty. It is built
now — BUILD-PLAN §9 M2 names the duplicate-proximity warning as required and §7 specifies the
endpoint, so this is a deliverable that was skipped rather than a screen invented here, and with no
mock every part is borrowed from a specified one. The screen never pre-checks the 10 m circle: it
renders `ProximityConflict`'s own candidates, so the warning cannot disagree with the refusal. Adding
a second tree on the same spot answers "Something is already on record within 10 m of here", names
the tree at 0 m, and opens it.

**Nobody could reach any of this from the map.** `MapHomeView`'s "What tree is this?" FAB — the
largest control on the default screen — called `router.push(.identify)`, and a *pushed* `.identify`
was answered by `NotBuiltYetView`. The feature was built and presented as a sheet; only the map's
entrance was wrong, and it had been wrong long enough that the audit found it before any user
complained about it by name. `ScreenEntranceTests` asserts each route's entrance as a hand-written
string, which is exactly why the one test built to catch this passed on a lie.

**The recurring lesson, now at four.** Two defects in this entry were found by tapping a running
build with a green suite over it: the stale profile above, and — on the brand-new add screen — a
chosen photograph pushing the whole column wider than the phone. That is E125's `scaledToFill`
measurement bug, reproduced from scratch in code written days after E125 was written down. A rule
recorded in an ERRATA entry is not a rule the next screen obeys; `PhotoFill` exists so that it is
unnecessary to remember, and the new screen did not use it. 468 unit tests and 27 UI tests pass.

**Open.** The add screen has no preview fixture, so `ScreenSweepShots` does not photograph it — every
other feature has one. And screen 16 still gives no confirmation on save; the keypad clears and
nothing else happens, which is why the measure round-trip still feels broken even with the profile
now re-reading itself.

### E129 — two rows that stated a group and delivered one record, and the test that ratified it

The project owner, on screen 12: *"Where eyes are needed is nice but kind of useless: the button says
walk the 11 but doesn't tell me where they are or open a map; just takes me right to a tree's page."*
Correct, and it was true twice. `coverageCTA` said "Walk the nine" and carried `firstTreeID`,
singular. `vacantTitle(count:)` said "1,474 empty planting sites" and `VacantBlock` carried
`nearestID`, singular. The second one shipped four commits after the first, under R10/E121 — the
pattern was repeated rather than noticed, which is the argument for both rows now sharing one
destination type instead of each owning a single id.

**The destination is a pushed map, `Route.pinSet`.** The question both rows provoke is *where*, both
are spatial claims — one is literally about walking distance — and a map is the only answer in this
app's vocabulary. Three decisions inside it are worth recording. Its title is the almanac's *own*
micro-label for the block that was tapped, "Where eyes are needed" or "Where a tree could go", rather
than an invented screen name: both are specified strings and both already name the thing the reader
pressed. Its headline is the row's own sentence, produced by the row's own function, so the two
screens cannot come to disagree about the number. And it is a plain column rather than screen 01's
full-bleed frame, because E110: 01's absolute positions are arithmetic against a safe-area inset that
reads 0 under a navigation bar, and this screen is pushed.

**The group travels on the route rather than being re-read**, which is not an optimisation. The row
has already printed a count; a read a second later can disagree with the sentence the reader tapped,
and then the screen contradicts the control that opened it. A consequence worth having: the
destination never calls `mapContent`, so it costs no query however far it is panned, and the map's
pin budget is untouched.

**E38 decided the copy.** Coverage is provably whole — `Series.totalCount` is why the card draws at
all — so its map holds all of it and says "All seventeen are on this map." The vacant group cannot
be, because E115 measured between 4 and 1,474 basins per neighbourhood, so its map holds the 20
nearest and says exactly that, while the count above it remains the `COUNT(*)`. The limit of 20 was
chosen against two measurements rather than taste: the busiest neighbourhood's coverage set is 21
trees, and the 20 nearest basins in Sunset/Parkside span 197 m × 212 m — close to screen 01's own
120 m opening view, which E12 measured as the scale where 18 pt pins stop fusing.

**A green test was holding the defect in place, and that is the new thing here.** Every other defect
this week was something the suite *failed to notice*. This one it had positively ratified:
`AlmanacPresentationTests` contained `@Test("the CTA opens the nearest of them")`, asserting
`coverage?.firstTreeID == near.id` — against a button whose visible label reads "Walk the nine". It
passed every run since the coverage card shipped. A test named after the wrong behaviour is worse
than no test, because it converts the defect into a requirement and the next person to touch the card
has to argue with the suite to fix it. It has been rewritten, with a note recording what it used to
say.

A second trap, caught in review rather than shipped: the first version of `theCameraHoldsEveryPin`
iterated `block.group.pins`, so a bug that dropped records from the group also dropped them from the
loop, and the frame trivially contained whatever was left. It passed against the restored defect. It
now iterates the trees the *card counted* — assert against what the source said, not against what the
buggy path produced.

**And the data was always there.** `youngTreesWithoutVisits` has selected `lat` and `lon` since it was
written, because `LocalAPI` needs them to check the "within a 15-minute walk" claim, and discarded
them one line later. This map could have been drawn at any point since §4 was built.

**Open.** The new screen has no `DebugDeepLink` case, so `DeepLinkVoiceOverTests` does not read its
accessibility tree the way it reads the other sixteen. Its only interactive elements are
`ScreenHeader`'s Back circle and `MapPin`s, both covered by components that suite already exercises,
but it is a gap in that sweep. Also: `Route` now carries a payload for the first time. `AppRouter`'s
`replace(_:with:)` uses `path.lastIndex(of:)`, which is fine on a `Hashable` payload, and nothing
serialises `Route` — noted so the next payload-carrying case is not added blind.

### E130 — screen 01 had no level of detail, and the annotation count tracked the viewport's area

The project owner: *"the map gets SUPER slow when you zoom out a bit; that's bad and we should fix."*
The phrasing turned out to be the diagnosis. Not *when you zoom out* — *a bit*. At zoom ≤15 the map
flips to cluster badges and gets fast again, so the stall lives in the narrow band the camera actually
opens into. That reversal is also the proof it was never the SQL: the clustered query is the *more*
expensive one, 104 ms for the whole city against a few milliseconds for a viewport, and the map got
faster the moment it started running it.

What was slow was 1,300 SwiftUI `Annotation`s, each a Button with a 44 pt hit area, a shadow, a
`contentShape`, a `strokeBorder`, a `scaleEffect` and an animation keyed on the selected pin — so one
tap armed a transaction on all 1,300 — plus a `cypressPulse` that built a `Circle().fill(...)` per
pin whether or not it was pulsing. Twelve hundred invisible circles. There was no level-of-detail
rule anywhere between zoom 16 and zoom 21; the only boundary in the app was
`highestClusteringZoom = 15`. The camera opens at 120 m ≈ zoom 18 and about 130 trees, and two
pinches out is sixteen times the ground: 130 → 525 → the 1,300 cap. That is the whole of "a bit".

**The fix is a screen-space grid, expressed in SQL.** `MapViewport` carries an optional
`markerCellPoints`; `TreeQueries.pins` divides the box into cells that many points square *at that
zoom* and returns one tree per occupied cell — `MIN(t.rowid), COUNT(*) … GROUP BY cell`, the cluster
query's own plan, answered out of `idx_trees_lat_lon` as a covering index without touching the table,
then hydrated by rowid through `json_each` so the statement text stays cacheable. The drawn count is
then bounded by screen area ÷ cell area, which is 264–288 markers at *every* zoom, because both terms
scale together. The number the viewport controls is no longer how many markers exist.

**44 pt, because that is the app's own tap target.** Two pins closer together than 44 pt could never
both be tapped; the second one was never a control, only paint. Choosing the tap target as the cell
size means the thinning removes exactly what the reader could not have used, which is a different and
better argument than picking a number that happened to run fast. It is a ceiling and not a rule: the
same statement counts the box while it groups it, so a viewport already inside the 400-row budget is
answered un-thinned and nothing is dropped from a zoomed-in map at all.

**Measured, because a passing test says nothing about frames.** A `CADisplayLink` probe
(`MapFrameProbe`, `#if DEBUG` and off unless `CYPRESS_MAP_PROBE=1`) counts the frames the main run
loop missed — the same run loop SwiftUI rebuilds the annotation layer on, so the gap it reports *is*
the stall. Identical scripted pinch, same build config, same device, location declined both times so
the camera opens the same way. Raw logs are in `.measurements/`.

| window | before | after |
|---|---|---|
| idle, zoom 18, 10 markers | 60.0 fps | 60.0 fps |
| the pinch itself | 38.0 fps, worst 325 ms | 44.6 fps, worst 138 ms |
| settling at zoom 16 | 14.3 fps, worst 753 ms | 59.3 fps, worst 28 ms |
| the second after that | 0.5 fps, worst 2,061 ms | 60.0 fps |
| one drag at zoom 16 | 18.7 fps, worst 1,286 ms | 57.0 fps, worst 54 ms |

Marker counts over the densest zoom-16 screenful in the seed: 1,300 → 277 at zoom 16, 1,300 → 220 at
17, 543 → 136 at 18. Zoom 19 is 109 both ways, which is the ceiling declining to bite.

**None of this was measured on hardware.** It is a simulator, compositing on a Mac GPU with a desktop
main thread. A 2,061 ms frozen frame becoming 28 ms is not an ambiguous ratio, but the absolute
milliseconds are not a claim about an iPhone and should not be quoted as one.

**The grid was not absolute, and its own comment said it was.** This is the part worth remembering.
The cells are `CAST((lat + 90) / latCell AS INTEGER)` — origin at the south pole, so a San Francisco
index is around 171,000 — and `cellSize` took the *viewport's own* centre latitude for its `cos()`
term. `cos` is continuous, so `latCell` moved a little with every pan, and a relative change of one
part in five thousand slides an index of 171,000 by more than thirty whole cells. The new stability
test measured the consequence: **67 of about 190 interior pins picked a different tree after a
quarter-box pan.** `TreeCluster.id`'s comment has promised an absolute grid since it was written, and
it was half right — the `+90`/`+180` offsets do make the grid independent of the box's *corner*. What
nobody noticed for the life of the cluster layer is that the cell **size** was still a function of the
box. The badges have been re-keying on every pan since they shipped. `cellSize` now snaps to the
middle of the whole-degree band, which no pan of a city-sized map crosses; `cos` varies 1.4 % across a
degree here, so a cell is 44 × 44.1 pt instead of 44 × 44.0.

Two things follow from finding it this way. It was invisible to the eye — a pin swapping to a
different tree of the same species half a block away looks like a map, not a bug — and it was
invisible to every test, because no test had ever asked whether the same ground produces the same
answer twice. It surfaced only because the fix needed a *stability* property and stability had to be
written down before it could be checked.

**The bands are gone, and so is their artifact.** The old code split the viewport into five latitude
strips and gave each 260 rows, and `LIMIT` truncates in latitude order — so the 1,300 pins were five
stripes bunched at the bottom of each band. That was visible in every screenshot of the map ever
taken and had never been named.

Seven secondary fixes came along with it: one `queue.read` per viewport instead of fifteen (each
`mapContent` was doing three, five times over); `tree_status_overrides` — a full-table scan with no
predicate — cached in the `LocalAPI` actor and invalidated on both writers; `Task.isCancelled` checked
during a fetch rather than only after it returned; a one-frame floor under the clustering-threshold
read, which a pinch oscillating across zoom 15/16 used to hammer with unthrottled whole-city queries;
`MapModel.pins` stored instead of recomputed on every body pass; the selected pin lifted into its own
`Annotation` so the other N−1 carry no `scaleEffect` and no animation; and `cypressPulse` no longer
building a circle it will not draw.

**Declined, with reasons, rather than done for completeness.** A spatial LRU: a refetch is now one
read of ≤300 rows and the measured pan holds 57 fps, and an absolute grid means most annotation ids
now survive a refetch anyway, which was most of what a cache would have bought. Slimming `MapPin`
itself: after the count fix the map holds 57–60 fps at every zoom, and `MapPin` is a DesignSystem
component shared with screens 15 and 18 where its `Button` carries the 44 pt target and the
accessibility trait — blast radius for no measured gain. `MapLocationProvider`'s 5 m `distanceFilter`:
5 m is the distance screen 02 identifies a tree from.

**And a correction to this project's own record.** Two comments claimed test coverage that did not
exist in the shape described — `SQLiteConnection.queryPlan(for:)` calls a degradation to `SCAN trees`
a regression, and `TreeQueries` claimed the seed contract test ran both spatial strategies and
asserted set equality. The gap was narrower than it first looked: `SeedContractTests` delegates to
`DataGates.seedContract`, which does check plans and does compare strategies. But the plans were
checked over SQL **hand-copied into `DataGates`** rather than over the statements the app actually
runs, and the strategy comparison covered `pins` alone over one viewport. Both comments have been
rewritten to say what is true, and the missing gates added. A comment asserting a test exists is not a
test, and it is worse than silence, because it stops the next person looking.

**Open.** Two of the new budget assertions would also pass under a plain `LIMIT` — they guard the
budget constant, not the grid. The grid itself is held by the stripe assertion and the cell-bound
assertion, and that is worth knowing before anyone trusts the budget tests to protect the mechanism.

### E131 — the account existed, and the only screen about you never mentioned it

Part B built a local account: screen 15 could create one, `claimDevice` wrote it, moderation
depended on it. The You tab — the one screen in this app whose subject is the person using it — said
nothing about any of it. There was no way to see whether you were signed in, no way to sign out, no
way to delete, and the private reminders written on screen 06 went into the database and were never
read back by anything. Every one of those is the same defect in a different place: a thing the app
does, with no surface saying it does it.

**Sign-out and delete are different promises, and the app now keeps both distinctly.** Sign-out
records `signed_out_user_id`, so signing in again resumes the same account and everything it wrote
stays attributed. Delete does not: it clears the id and a later sign-in mints a new one. That was
verified rather than assumed — the account deleted in testing was `C6C025E1…` and the one that came
back was `9FED047C…`. A "delete" that quietly behaves like a sign-out is the version of this feature
that would have been worst to ship, because nothing on screen would ever reveal it.

**The deletion surface was driven by hand against the live database, because R3 is a destructive
promise and a passing test is not evidence about a destructive promise.** One tap on the row destroys
nothing — it raises the dialog, and a read of the app's own sqlite immediately afterwards showed the
reminder, the observation, the two outbox items and `current_user_id` all still present. Cancelling
changes nothing; dismissing by tapping outside changes nothing; both were checked against the
database rather than the screen. And what it deletes matches what its copy promises, clause by
clause: the private reminder went 1 → 0, the observation stayed on its tree with `user_id` NULL and
`device_id` intact — which is exactly the sentence "stay on the trees they were made about, with
nothing left on them saying they were yours" — and the queued outbox item for the deleted reminder
went with it, which is "anything still waiting to sync is included".

**One record kind is deleted without being named.** `AccountDeletion` also removes `photo_votes`
(schema v8), and `AccountDeletionCopy.whatHappens` lists only reminders and favourites. R3's whole
rule is that deleting *more* than the person expected is the failure mode, so an unnamed record kind
is a gap in that defence — narrow, because a vote is invisible to its owner and the aggregate it
feeds is public either way, but the sentence should probably grow a clause. Left open deliberately
rather than fixed in passing.

**A string in the app said "screen 06" to the person reading it.** The reminder list's empty state
read: *"A reminder you keep on screen 06 after a 311 handoff shows up here, and stays yours alone."*
Every clause of that was true and one word of it was unreadable, because "screen 06" is a coordinate
in SCREENS.md and not a thing anybody using this app has ever seen. A grep confirmed it was the only
user-facing string in the app carrying one; every other screen number in this codebase lives in a
comment, which is where they belong. It had crossed over because the person writing the sentence was
reading the mock while they wrote it. It now says "after reporting an issue and calling 311" — "Report
an issue" is screen 06's own C1 title and "Call 311 now" is the button directly above the save this
list exists to explain, so both halves name something the reader has actually looked at.

Worth recording *how* it was found: by looking at the running screen. The string is asserted nowhere,
and the screenshot sweep photographs it faithfully every run without ever reading it. That is the
third defect this week that only a person looking at pixels could have caught, and it is the argument
for the rule rather than an exception to it.

**A harness fragility that costs an hour if you meet it cold.** `VisitCameraModel.load()` calls
`AVCaptureDevice.requestAccess` when permission is `.notDetermined`, and in the unit-test host there
is nobody to answer — so it hangs forever with no timeout, wedging the whole suite. Two full runs were
lost to it. `xcrun simctl uninstall` is what causes it, because uninstalling resets TCC; `xcrun simctl
privacy <udid> grant camera app.cypress.Cypress` fixes it and the test then passes in 2.5 s. **This is
not a defect in the shipping app** — there the system alert appears and is answerable, and a *denied*
camera is handled properly: `needsLibraryFallback` becomes true and screen 04 offers the photo
library instead. It is purely that a test host cannot answer a prompt, and the failure mode is an
indefinite hang rather than an error, which is the part that wastes the time.

**Open.** A favourite was never driven through deletion by hand (there were none in the session);
`AccountDeletionTests` covers the row, and the reminder and observation paths stand in for the
behaviour. Screen 06's 311 redirect card showed hanging-limb body text while "Uprooted" was selected —
the *saved* category was correct on disk, so it is a cosmetic copy-selection bug in the redirect card,
pre-existing and untouched here.

### E132 — the pin the reader places, not the pin the phone guessed

The project owner: *"the ability to adjust the pin/location of where the 'What tree is this' tree
location is; making it right where you stand is super limiting."* `VisitAddTreeModel.add()` passed
`location.fix.coordinate` to the draft verbatim, and the screen's own footnote said as much — "the
coordinate is the phone's current fix". E127 made that a deliberate choice. Using it revealed three
cases it cannot serve: a tree photographed from the far kerb, from a car or through a window; a fix
20–40 m out, which is ordinary in an SF street canyon; and a row of street trees shot from one
standing spot, every one landing on the same point and every one after the first refused by the 10 m
dedupe.

**`Phase.placingPin`, and a row that states where the tree will go before offering to change it.**
The add screen now says "This tree will be recorded where you are standing" above a **Move the pin**
control — the statement comes first, so a reader who is standing at the tree reads a confirmation
rather than a question. `VisitPinAdjustView` is `PinSetMapView`'s shape with a different subject: the
same basemap, the same header, the same statement-then-qualifier pair above the map, the fix drawn as
the GPS dot.

**The fast path is untouched, and that was the constraint.** With no pin placed, `coordinate` is still
`location.fix.coordinate` and the CTA writes exactly what it wrote before, so stand-shoot-save is
still one tap and nobody is routed through a map they did not need. A fix is still required to
*start*: `canAdjustPin` is false without one, so this changes where the pin ends, not whether the app
will invent a location it does not have.

**The pin is the centre of the map and the map moves under it.** Three reasons, and the first is the
one that decided it: the pin under your thumb is the pin you cannot see, and the thing being aimed at
is a tree in the street. The second is that it makes every point on screen a handle rather than an
18 pt dot. The third is that MapKit's own pan recogniser is the only thing that moves a map smoothly,
and a hand-rolled drag on an annotation competes with it.

**75 m, and the number is argued rather than picked.** It absorbs the two errors the owner named
*where they compose*: a 40 m street-canyon fix plus SF's standard 68'9" right-of-way — 61 m — with
room over. It is about half a block face, so a row of trees 6–10 m apart is reachable without walking.
And it stops short of the distance at which you are pointing at a rooftop rather than a trunk.

It is deliberately far larger than the 10 m dedupe, and **that ordering is load-bearing**. The dedupe
runs on whatever coordinate the draft carries, so a pin moved onto an existing tree is still refused
with its candidate list. Widening the pin's reach does not widen the hole in the dedupe — it makes
the dedupe *reachable*, which is exactly what the row-of-trees case needed.

**The limit is on screen the whole time, not only when it is met.** The qualifier under the position
names the distance and the limit in one breath. Past it the qualifier changes, the pin fades and the
confirm goes dead. A nudge that would leave the circle is **refused rather than clamped** — a clamp
slides the pin sideways, so pressing *north* moves you *east*, which is a control lying about what it
did — and the refusal replaces the qualifier with "That is as far as the pin goes". A control that
stops working never stops silently. There is no drawn circle: it would be wrong under the basemap's
rotation and invisible to the reader who most needs the bound.

**VoiceOver got a real answer rather than a label.** A pan is a gesture the screen reader owns; no
amount of labelling fixes that, so the pin has a second way to move that needs no gesture at all —
four nudge buttons at 5 m a press, spelled out in words because a bare "N" is heard as a letter. The
pin carries its position as its `accessibilityValue`, the two sentences sit above the map in reading
order so the whole state is met before any control, every press posts an announcement, and one press
returns to the fix.

**A defect the tests found, and the size of it is the point.** `VisitPinAdjust.offset` first used the
111,320 m per degree that `BoundingBox(around:radiusM:)` uses, while `Coordinate.distance` measures on
a 6,371,008.8 m sphere — 111,194.9 m per degree. So a 5 m nudge measured 4.994 m, and fifteen of them
landed **84 mm** inside a limit the screen was printing as reached. Far too small to matter to a tree
and exactly large enough to matter to an assertion. Two units of length for the same globe in one
codebase is the kind of thing that stays invisible until something counts.

**Verified by touch, then read out of the database.** Two community trees added through the real flow
at a simulated Folsom Street fix: one placed by drag, screen reading "64 m east", stored at 64.186 m
on bearing 90.00°; one placed by nine south and nine east nudges, screen reading "64 m south-east",
stored at 63.640 m on bearing 135.00° — matching the nudge arithmetic to 0.0000 m. A third pass
placed a pin, left the map without confirming, and the row reverted to the default; the tree count
stayed at two. Had either placement been discarded on the write path, both rows would have sat exactly
on the fix at 0.000 m, which is what makes this a proof rather than a screenshot.

Two behaviours the drive surfaced that no unit test would have: MapKit's pan **decelerates**, so a
flick keeps travelling after the finger lifts — one run read 46 m mid-glide and settled at 92 m, with
the confirm correctly disabling itself on the way. And on a tree-lined street a moved pin frequently
lands within 10 m of a seeded tree and is refused by the dedupe, which is the API doing its job and
the reader meeting it for the first time.

**Open, and deliberately not decided here: the provenance of the coordinate is not recorded.**
`community_trees` has `lat` and `lon` and no column that could honestly carry whether the pair was
placed or measured. `address` is a street address, `external_ref` is the city's identifier, `site_type`
is where a tree is planted; writing a flag into any of them makes that column mean two things. It
needs a `placement` column and an `AppSchema` v9, and inventing a migration was not this change's to
make. The distinction *is* modelled in `VisitAddTreeModel.Placement` and *is* stated on screen, which
is the honest half that does not require the schema.

**Also open.** Correcting an existing community tree's location is not cheap: `community_trees` is
insert-only by design, so it needs an update path, an outbox kind (there is none for trees at all), a
patch on `CypressAPI` and an entrance on screen 03 gated on `source == .community`.
`VisitPinAdjustView` takes a coordinate and two closures and owns no draft, so the *screen* is already
reusable verbatim — the work is entirely the write path. And neighbouring trees are not drawn on the
pin map: they would genuinely help, since they are what the dedupe is about to refuse against, but a
pin there is a labelled button with nowhere to go, and opening a profile from inside a placement
abandons a photograph.

### E133 — the rule said "case", and the writer was a test

E125 ended with a rule, written down so the next person would not repeat it: **a case that writes
persistent state must not write it onto a tree another case reads.** It was repeated today anyway,
because the rule named the wrong actor.

`DebugDeepLink.measure` opened `standingTree` — the tree nine other cases open — and the case writes
nothing at all, which is exactly why it looked safe and survived review. The writer is the *test*.
`testSavingAMeasurementLeavesTheScreen`, added with E131, taps a digit and taps save, and a saved
reading is a row in the device container that outlives the launch.

**What broke was three screens away from what changed.** Screen 03's DBH card prefers a reading over
the city's bucket, and a card holding a reading has somewhere to go — screen 11 — so it is wrapped in
a `Button`. `StatCard` combines its children either way, so the joint label E118 asked for was still
there and still correct. It had simply moved from `staticTexts` into `buttons`, and
`testAStatCardIsOneStop` was only looking in the first. Nothing about the app was wrong. The
assertion had stopped being able to see a correct answer.

**The failure mode is the part worth remembering.** It was not order-dependent and it was not
intermittent. From the first full suite run onward the test failed on *every* subsequent run, and it
passed the instant the app was uninstalled. That is the signature of persistent pollution, and it is
indistinguishable from a flake to anyone whose first instinct is to re-run — which is everyone's
first instinct. It also survives a single-test run, so the usual isolation check *confirms* the false
diagnosis rather than refuting it: running the one test alone still failed, because the poison was
already on disk. Only clearing the container separates the two, and nothing prompts you to try that.

**Two defects, two fixes.** `.measure` now takes the **middle** standing tree: `.memorial` marches in
from the near end and the photo cases from the far end, so the middle is the one place neither
reaches. And `testAStatCardIsOneStop` now accepts a `Button` as well as a `StaticText`, because a
`Button` *is* one stop — arguably more so. Looking only in `staticTexts` had quietly asserted
something narrower than the test's own name: that a stat card is not interactive. That premise was
false when it was written; it took a reading on the opened tree to make it visible.

**Verified in the shape that proves it**: the suite twice back to back on one container, 28 tests
green both times, where the same sequence previously went green then red. And the widened assertion
still bites — removing `StatCard`'s `.accessibilityElement(children: .combine)` turns it red, so it
was widened rather than weakened.

**The rule, restated.** A case that writes persistent state must not write it onto a tree another
case reads — **and the writer includes the test driving the case.** The harness being pure is not
enough; what matters is what is on disk when the next test launches.

### E134 — the search bar was a binding nothing read, and narrowing after the grid could not have worked

C20 shipped as decoration. `grep -rn searchText` returned exactly two lines repo-wide — the
declaration on `MapModel` and the binding in the view — and `CypressAPI.searchSpecies` existed with
no caller at all. The placeholder read `Species, street, or neighborhood…`, which is three promises
against zero deliveries, and every unit test in the suite passed while typing into the field did
nothing whatever. The owner's ask was that typing a tree name "brought up all and only those trees".

**The result surface was never specified, so it was designed here.** SCREENS.md 01:664 states the
intent — "search opens species/street/neighborhood search" — and 01:667, three lines later, says
"NOT SPECIFIED: search results"; PROTOTYPE-FLOW.md:105 lists the bar as inert, which is what shipped.
The ruling, under ARCHITECTURE §8 rule 8, is that **there is no results screen: the map is the
result.** A list behind a sheet is a second surface to design, it covers the thing the answer is
drawn on, and it is not what was asked for. It also keeps C20 a real `TextField` in the accessibility
tree, which `AccessibilityTreeTests` and `DeepLinkVoiceOverTests` both require — and the obvious
"tap to open a results sheet" design is precisely what would have broken that.

**Filtering the answer afterwards could not have worked, and the reason is E130's grid.** Since E130,
`TreeQueries.pins` divides the viewport into 44 pt cells and returns one tree per occupied cell once
the un-thinned answer would overrun `pinLimit`; the cell's winner is whichever tree holds
`MIN(rowid)`. Apply a species predicate downstream of that and **both halves of the ask break at
once**: the winner of a cell need not be a match, so "only" fails, and six London Planes sharing a
cell come back as at most one, so "all" fails too. That is the same class as E36 and E38 — a
predicate applied downstream of a budget that was already spent on the wrong rows.

**So the predicate goes into `markerCells` as well as into the pin query, and that one detail is the
fix.** The number the grid decides on stops being "trees in view" and becomes "trees in view *that
match*", which is a far smaller number, so the un-thinned query runs in every case where the matches
fit — and there the answer is exactly all of them and only them. Over the shipped seed the densest
zoom-16 screenful of the city holds 7,042 trees, of which 1,458 are London Planes: un-narrowed it
grids to 304 cells and thins, narrowed it counts 1,458 and still thins, but one zoom in there are 632
matches and by zoom 18 there are 268 and the viewport comes back whole. Most searches are answered
un-thinned at every zoom, because 12,830 of the 195,309 rows carry no species at all and even the
commonest species is 6 % of the inventory spread across the city rather than packed into one screen.

**Where it still thins, "only" holds absolutely and "all" does not, and the answer has to say so.**
`mapContent`'s pin case now carries a `PinAnswer` rather than a `[TreePin]`, because *"fewer pins"*
and *"all the pins there are"* are identical in an array: 151 can mean "there are 151" or "there are
1,458 and these won their cells". `PinAnswer.matchesInView` is `nil` when the answer is complete —
and `nil` means complete, **not unknown**, so a caller may treat it as a guarantee — and the count is
the sum `markerCells` already computed, so it is free. E38's rule, applied to a map. It is a
`RandomAccessCollection` and `ExpressibleByArrayLiteral` so the fifteen preview doubles and five test
doubles that write `.pins([])` compiled untouched.

**The narrowing rides on `MapViewport` rather than arriving as a second argument to
`mapContent(in:)`**, for two reasons, and the second is the load-bearing one. The signature does not
change, so none of the twenty conformances have to be edited. And `MapViewport` is `Hashable`, which
is what `MapModel`'s fetch debounce dedupes on — so a changed query is a *different viewport* and is
refetched, while an unchanged one coalesces exactly as a pan already does. A parameter would have
left the debounce unable to tell the same box searched two ways apart.

**The species ids are interpolated into the statement text, which nothing else in `TreeQueries`
does.** Every other list travels through `json_each` on a bound parameter so the text stays constant
and `cachedStatement` holds one prepared copy across every camera change. That is the right trade
everywhere else and the wrong one here, because **the planner cannot cost what it cannot see.**
`sqlite_stat1` records `idx_trees_species_current | 195309 343` — 343 rows per species — and that
estimate is what lets SQLite choose between walking the box and walking the species. Hidden behind
`json_each` it is unavailable and the box wins by default. Measured over the whole city, one species:

    literal `IN (24)`                          18.8 ms   SEARCH … idx_trees_species_current
    `IN (SELECT value FROM json_each(?))`     399.8 ms   SEARCH … idx_trees_lat_lon
    `IN (SELECT id FROM species WHERE uuid …)` 400.4 ms   SEARCH … idx_trees_lat_lon

The cost is one prepared statement per distinct species set, which is one per query the user types
rather than one per pan — the ids are sorted, so the same set always spells the same text. It is not
an injection surface: they are integers the same method read out of the seed a moment earlier, never
anything typed.

**And deliberately no `+` barrier on the column.** The unary `+` that forbids SQLite an index is the
standard move for pinning a hot query to the plan it was tuned for, and here it is wrong by a lot:
whole-city clusters narrowed to the London Plane cost 386 ms with it and 21 ms without, whole-city
marker cells 419 against 19, zoom-16 marker cells 28 against 15. A species predicate is *selective*
in a way none of the map's other predicates are. The fear the `+` answers — that a broad query drags
the map onto a bad plan — does not survive measurement either: given the hundred densest species at
once, 85 % of the inventory, the planner picks `idx_trees_lat_lon` on its own and lands within 3 % of
what the `+` would have forced. Forcing it can only lose.

**Which makes `sqlite_stat1` load-bearing for the first time in this app.** Zoom-16 marker cells
narrowed to the hundred densest species measure 18.3 ms with the seed's `ANALYZE` statistics and
266.0 ms without — fourteen times slower, on the map's critical path, from a table that does not
survive a seed rebuild which forgets to run `ANALYZE`, and which only `Tools/build_seed.py` puts
there. Nothing else in the app would notice it go missing, which is exactly why
`MapQueryPlanTests.theSeedCarriesItsStatistics` asserts it rather than trusting it.

**The query-plan gate deliberately does not pin an index, and that is why it exists.** Anyone
arriving at `MapQueryPlanTests:299` from a citation should know that the section is *not* there
because a query went quadratic or dropped an index — no regression of that kind happened. It is there
because the narrowed statements are the only ones in the app whose *right* plan depends on the data.
Two rules are asserted over `everyPinSQL`, `markerCellsSQL` and `clustersSQL` in both spatial
strategies: no step may be a `SCAN` that is not a covering index or a virtual table, and the plan
must reach either `idx_trees_lat_lon` or `idx_trees_species_current`. Never which one. Every other map
query is pinned to `idx_trees_lat_lon`, because there is one spatial index worth using and no
predicate selective enough to beat it; pinning either index here would pin the wrong one half the
time.

**A collation defect that compiled, ran, and answered zero.** The uuid-to-rowid lookup was first
written the way the rest of the file writes an equality — `sp.uuid IN (…) COLLATE NOCASE` — where the
collation binds to the *subquery* rather than to the comparison. The seed stores uuids in lower case
and `UUID.uuidString` produces upper, so every narrowed query matched nothing and the map went empty.
`COLLATE NOCASE` now sits on the left operand. It was caught because `MapSearchTests` checks the
drawn set against a second, independent read of the seed — raw SQL that shares no code with
`TreeQueries`, naming the species by uuid and taking the bounding box literally — rather than against
a pin count. A pin-count assertion would have read an empty map as a very effective narrowing.

**And a measured result that contradicts the obvious assertion.** A narrowed map can draw *more* pins
than an un-narrowed one at the same zoom, because narrowing brings the count under the budget and
switches the grid off entirely. Anyone tempted to write "narrowing draws fewer pins" is writing a
false statement; `narrowingActuallyNarrows` asserts on the trees answered for, under a budget nothing
can reach, for that reason.

**Clustering is untouched by a search, and that was measured rather than assumed.** An earlier design
forced the pin regime whenever a query was running, on the grounds that a species-filtered badge would
put the predicate on the `GROUP BY` at the 3.4× a non-index column costs there. Measured, that was an
argument against a query nobody has to write: the narrowed badge costs 21 ms, not 355, because the
planner answers it through `idx_trees_species_current` instead. So A1's rule stands unbroken, the
*shape* of the answer never depends on what is typed, and a zoomed-out search gets badges counting the
species asked for rather than every tree underneath them.

**Four states, because "nothing drawn" would otherwise answer a different question each time.** Typed
nothing; typed a word the catalogue has no prefix match for; typed a real species with none in *this
viewport*; typed a real species with more here than the map can draw. The middle two are the pair that
matter — "No species matches “sycamore”" tells the reader the app understood them and the catalogue
does not have it, where "No Platanus in view" tells them to move the map rather than doubt their
spelling. `MapSearchCopy.status` returns `nil` for the ordinary success case, because a map showing
every match it found does not need a banner over it announcing that it did.

**The placeholder was cut from three promises to one**, and that is part of the fix rather than a
tidy-up. `Search a species…`. A street search wants `trees.address`, which carries no index — every
keystroke would be a scan of 195,309 rows on the map's critical path, the one thing `TreeQueries`
forbids outright. A neighbourhood search wants boundary geometry the seed does not ship;
`TreeProfile.neighborhoodName` exists precisely because a neighbourhood has no identity in this
database beyond a name hanging off a tree. Both are `Tools/build_seed.py`'s work before they can be
the client's. A bar that offers three kinds of search and answers one is *worse* than a bar that
offers one, because a reader who types a street and watches the map empty out has been told, wrongly,
that their street has no trees.

**The only test that could have caught the original defect is a UI test.** `MapSearchTests` proves the
query — that the set the map draws equals the set the seed holds — and it never touches a search bar,
because it builds its own `MapViewport` and hands it to the API. It would have gone on passing.
`MapSearchUITests` launches the real app, taps the real field, types `Platanus`, and watches the pin
count change and come back when the field is cleared. Two of its three cases **skip** rather than fail
without a simulated GPS fix: screen 01 opens on the whole city without one, the whole city is zoom
≤ 15, which is A1's clustered side, so a narrowing that is plainly visible with a fix has nothing to
be visible *on* without one. A skip says "not checked here", which is true; a failure says "broken",
which is not.

**What could not be established, and is recorded as unknown rather than guessed.**

The merge removed two `CypressAPI` protocol requirements, `outboxStatus()` and
`savePrivateReminder(_:)`, along with their `RemoteAPI` stubs and their answers in every preview
double. **No commit message on the branch or on the merge says why.** Neither had a caller, which is
the likely reason and is not a recorded one. The removal is visible only in the merge diff, and it
caught a second branch out: `317c586` had to drop the same two members from preview mocks the
incoming work had added, where they had quietly stopped being requirements and become ordinary
methods nobody calls.

It also left an artifact that is still there. `savePrivateReminder` carried `@discardableResult`;
deleting the declaration left the attribute behind, and `RemoteAPI.swift:147` now applies it to
`exportLatest(_:)`, which returns `Data` that nobody discards. Harmless, wrong, and not deliberate.

Every performance number above comes from doc comments in `TreeQueries` and `MapQueryPlanTests` and
from the commit messages. Unlike E130, **nothing was written into `.measurements/`** — that directory
holds only the E130 before/after logs — so the harness, the device, the build configuration and the
number of runs behind "18.8 ms" and "399.8 ms" are not recorded anywhere and cannot be reproduced from
this repository. They are consistent with each other and with the plans asserted in the tests, and
that is the whole of what can be said for them.

`MapSearchUITests:47` refers to "the live verification for ERRATA E134". The only surviving record of
it is `ca46647`'s message — with a simulated fix all three cases pass, without one two skip and the
third still runs. What was seen on screen was not written down, so unlike E132 there is no read-back
proving the *drawn* map matched the database on a device; the read-back proof here is
`MapSearchTests`, in the simulator, against the seed.

Finally, the numbering. The branch was written as E131 and renumbered at the merge because the account
work took that number first, so `15bb695`, `2a180ae` and `7debba6` all still say E131 in their subject
lines. There is no E131 search entry and never was.

### E135 — My Grove's two dead pills, and an export button with no test on the button

The project owner: *"when are we building out the journal and tree tabs on my grove?"* Both segment
pills were inert. `api.grove()` had worked all along; `api.journal(cursor:limit:)` had existed with no
screen at all, marked OPEN by E99 because there is no mock for a journal list. So the journal's
presentation was unspecified and is now designed and marked as such.

**The Journal tab holds two segments — your own journal and the neighbourhood almanac — and that is
structural rather than cosmetic.** `Route.almanac` has no push call site anywhere; the Journal tab is
what renders screen 12. A journal that simply took the tab would have silently deleted the almanac's
only entrance. The segment is router state, so a deep link can still ask for either.

**E38 is honoured at the source rather than in the copy.** `hasOlder` derives from `nextCursor != nil`
and nothing else, and the empty state is gated on the *cursor* rather than on `rows.isEmpty` — so a
read that stopped early cannot tell somebody they have recorded nothing. There is no count, no total
and no "N entries" anywhere, held by a blunt test that refuses digits in any of those strings.

Three states, not two: nothing recorded yet, the read failed, and — kept deliberately separate — a
failed `Show earlier` that keeps the rows already on screen. E126 established that a blank screen and
an empty life are different sentences; this adds the third case, where part of the answer arrived.

**And the export.** `CypressAPI.exportLatest` had been implemented, tested and callerless — a privacy
commitment with no surface, since its own documentation ties it to an account-data request. It now has
a control in the You tab, and the bytes were read rather than assumed: 202 bytes of CSV carrying the
D12 disclaimer, a header row, and this device's real measurement, correctly quoted because the summary
contains a comma.

**The part worth keeping is what the tests could not do.** This work was verified by a second agent
after the first was cut off, and what it found was not in the implementation:

- `JournalExportRow`'s own comment argued that two `Transferable` types make format confusion "part of
  what the compiler checks" and that "the suite asserts each carries its own". **It did not.** Both
  export tests built their own payloads inside the test body. Swapping the two `ShareLink` arguments —
  so the spreadsheet control handed over the map export's bytes, the exact defect the comment warns
  about — left every export assertion green.
- Every assertion called the payload's `load` closure rather than resolving it through
  `transferRepresentation`. A representation returning `Data()` would have shipped an empty file with
  the suite passing: the failure that looks identical to working until somebody opens the file.
- `GroveTab.hasDestination` was written `{ true }`. Two suites read it as proof that every pill leads
  somewhere, so both were asserting a literal — and a fourth inert pill would have been welcomed in
  silence by the very property added to prevent one.
- `exportPayloadIsReal` checked for the summary, the tree id and the disclaimer, all three of which the
  GeoJSON document also contains, so it too survived the swapped-format mutation.

The general rule, which is the reason to record any of this: **when a test constructs the thing under
test, it is testing its own construction.** For a control, the assertion has to start from what the
control builds. The fix is a seam — the payloads the view body builds are now built by a named
function the suite can call, the format each row asks for is recorded and asserted, and one test
resolves the payload through `NSItemProvider` the way the system does. `hasDestination` became an
exhaustive `switch` with no `default`, which moves the obligation to the compiler: a new pill does not
compile until somebody answers for it.

Thirty of thirty-three tests were killed by a twenty-five-mutation sweep; the three survivors are the
ones listed above, and all three now die too.

**Open.** The map export saves as `cypress-journal.geojson.json`, because the system appends the UTType
extension to the suggested name. The bytes are correct; software looking for `.geojson` sees a double
extension. Fixing it properly means declaring a custom UTI in `Info.plist`. Also noted and not claimed:
two saves against the pre-fix binary produced 0-byte files and two against the fixed binary produced
202 bytes, which is suggestive of a real intermittent in that path and is not evidence of one at
n = 2 against n = 2. The new representation test guards the path either way.

### E136 — deletion asks a question now, and the safe answer is already chosen

The project owner, ruling on the open item E131 left behind: *"account deletion should have an
option—one kills all photos, up votes, etc, the other leaves them in place and tags them to an
anonymous/deleted account, with that being the default."*

E131 had recorded that `AccountDeletion` removed `photo_votes` while R3's copy named only reminders and
favourites, and asked whether the sentence should grow a clause. The answer turned out to be neither:
stop deciding it for the person. The behaviour the safe door describes already existed for
observations — they stay on their tree with `user_id` nulled — so this generalises it rather than
inventing it, and makes the other option explicit instead of implicit.

**"Anonymous" means NULL, not a stand-in id.** A sentinel deleted-account id is a *pseudonym*, and
these rows carry a tree, a date and a time: a stable key joining one person's whole history
reconstructs where they walked, at street-tree resolution, in one city. Deletion is a privacy promise,
and a promise that leaves behind a key relinking everything it claimed to unlink is the version that
would be worst to ship — because nothing on screen would reveal it. The cost is real and is accepted
rather than hidden: a moderator can no longer tell that forty anonymised observations were one
person's.

**Reminders and favourites are outside the choice** and go under both doors. R3's original argument
survives intact: an ownerless favourite is a row no query returns and no person can remove, so
offering to keep one is a decorative control. The copy says so unconditionally, above both doors,
opening with "Either way".

**Photo bytes go files-first**, and the ordering is a ruling rather than a detail. `FileManager` cannot
join a SQLite transaction, so one half of the delete is outside the atomic part and one of the two
failure modes is going to happen. Files-first fails as rows pointing at missing bytes — visible,
retryable, cosmetic. Rows-first fails as a JPEG belonging to somebody who asked to be forgotten,
stranded on disk and unreachable by any query. A deletion path takes the loud failure.

**A vote survives its voter, and that forced a migration.** `AppSchema` v8 constrained `photo_votes`
with `CHECK ((user_id IS NULL) <> (device_id IS NULL))`, which made an anonymous vote literally
unstorable — so R3 deleted votes not because anyone had decided they should go, but because the schema
left no other option. A constraint had been wearing a ruling's clothes. v9 relaxes it to at-most-one
owner, and hero selection is unchanged on the default door.

**The surface is a sheet rather than a `confirmationDialog`**, because both paragraphs have to be
readable *before* either is chosen and a dialog cannot do that. Each confirming button names its own
door — "Delete account, leave my records" against "…and erase everything" — so the destructive path
cannot be taken without the word *erase* under your thumb, and it gets a second gate besides.

**Verified against the database and the disk, on a real account** holding three visits with
photographs, a check-in, a vote, a favourite, a private reminder and two queued outbox rows. Default
door: three visits still present with none naming a user, **three JPEGs still on disk**, the vote row
surviving with both owner columns NULL, favourite and reminder gone, outbox six to four. Destructive
door, from the same state restored from a container snapshot: every contribution row gone and **the
photo directory empty**. One tap on the row destroys nothing; both ways out leave everything intact; a
destructive selection does not survive dismissal. Signing in afterwards minted a different id.

**Two holes, pinned rather than hidden.**

`addTree` writes a photograph with no `visit_id`, and `community_trees` has no owner column at all — so
a photograph on a tree you added is attributable to nobody, and **neither door can reach it**. "Erase
everything" leaves it on disk. Closing this needs an owner column; there is now a test that fails the
day somebody adds one and forgets this path.

And `claimDevice` re-adopts anonymised rows onto the *next* account signed in on that phone, because
they keep their `device_id`. That is pre-existing D9 behaviour and predates this change, but it means
the default door's promise is weaker than its sentence: records unlinked from you can become linked to
whoever signs in next on the same device. Recorded here because it is a privacy promise rather than an
implementation detail, and the ruling belongs to the owner.

**Closed by E157**, on the owner's ruling of 2026-07-26. The hole was also wider than this paragraph
says: `claimDevice` was not the only place `device_id` means "this phone's work" — four read queries
say it too, so a fix confined to the claim would have stopped the rows moving while still showing
them to the next person. E157 keys the tombstone on `client_uuid` and guards all five sites.

### E137 — twelve fonts handed to Core Text that Core Text already had, and the test that would have passed against the bug

The project owner, watching Xcode's console with their own iPhone attached, saw twelve
`GSFont: file already registered` lines on every single launch and reported them.

Cypress registers its fonts twice over. `Cypress/Resources/Info.plist` lists all twelve faces under
`UIAppFonts` — four Source Serif 4, five Alegreya Sans, three Spline Sans Mono — and
`CypressApp.swift:11` then calls `CypressFont.registerBundledFonts()`. Both halves were deliberate.
The plist is how iOS loads fonts. The call exists so the design system does not depend on an
Info.plist edit at all (ARCHITECTURE §2: the project file is not hand-edited), which makes it a safety
net rather than the mechanism. In the shipping app every face is therefore already registered by the
time the registrar runs, and every one of its twelve `CTFontManagerRegisterFontsForURL` calls is
refused.

**The old comment called that "harmless", and it was right about the wrong property.** Nothing is
missing, the call returns false, the error is dropped. It is harmless. It is not *silent*, and that is
what was missed. Twelve lines per launch in a console somebody is reading to find real problems, and a
log nobody trusts is a log nobody reads.

**The fix asks before it registers.** `CypressFont.unregisteredBundledFonts(in:)` reads each bundled
`.ttf`'s PostScript name through `CGDataProvider`/`CGFont` and keeps only the files whose face does
not already resolve via `UIFont(name:size:)`; `registerBundledFonts` iterates that instead of the raw
bundle listing. In the shipping app the list is empty and Core Text is not called at all.

**Fail-open, and the asymmetry is the whole justification.** A file whose name cannot be read reports
*not registered* and is handed over anyway. A missing face is a far worse defect than a console line,
because `Font.custom` falls back to the system font **silently** — a face that failed to load does not
look like a bug, it looks like a design choice, and nothing on screen says otherwise. So the check is
allowed to be wrong in the direction that costs a log line and never in the direction that costs a
typeface.

**And now the part this entry exists for: the obvious test would have passed against the broken
version.** `registerBundledFonts()` returns the number of faces *newly* registered. That number was 0
before this change and is 0 after — 0 because every call failed with `alreadyRegistered`, and 0
because every call is now skipped. `#expect(CypressFont.registerBundledFonts() == 0)` is green against
the version that printed twelve lines on every launch, and it would have been written with a
straight face, because it is the assertion the function's own signature invites. The return value
cannot see the difference, because **the difference is not in the outcome; it is in whether the call
happened at all.**

So the test asserts on the *inputs to Core Text* instead. `BundleContractTests`' "the registrar asks
Core Text for nothing it already has" requires `unregisteredBundledFonts()` to be empty, and its
failure message names the offending files. Empty means Core Text is never asked, which is the only
thing that actually makes the console quiet.

Stated as the rule it is: **when the defect is that a call is being made, the assertion has to be
about the call and not about what it returned.** A function that fails harmlessly returns exactly what
a function that was never invoked returns, so every "the count came back right" assertion over such a
function is blind by construction, and blind in a way that reads as thorough. `unregisteredBundledFonts`
exists as a separate, non-private member for this reason and for no other: it is the seam that lets a
test see the argument list rather than the result. Any function whose failure mode is a side effect
needs one.

**Verified by breaking it.** Disabling the skip turns the new test red naming all twelve files — the
same twelve the owner saw in the console. 585 unit tests pass, build warning-free.

**One thing found and deliberately left alone.** `CypressFont.debugDumpAvailableFamilies()` has no
callers. The only three mentions of it in the repository are the file's own header comment
(`CypressFont.swift:21`), its doc comment (:297) and its declaration (:299) — nothing invokes it, in
the app, in a preview or in a test. It is dead weight by the usual measure and it is kept anyway: it is
exactly the tool you want the moment a face goes missing, and this change is precisely the kind that
could make one go missing. Recorded here so that the next person to run a dead-code sweep knows it was
seen rather than overlooked, and knows what they would be giving up.

### E138 — a coordinate now says how it was arrived at, and neither answer is the marked one

The project owner, ruling on the item E132 left open: *"yes we should track and surface when location
was added via pin by hand instead of by gps."*

E132 gave the add screen a movable pin and then wrote down, at length, why the record could not say
which of the two it had got. `community_trees` has `lat` and `lon` and nothing that could honestly
carry the provenance of the pair: `address` is a street address, `external_ref` is the city's own
identifier for an inventory row, `site_type` is where a tree is planted, and a flag written into any
of them makes that column mean two things — which the next reader finds out the hard way. The
distinction lived in `VisitAddTreeModel.Placement` and was stated on screen, and stopped at the
boundary. So on disk a coordinate somebody had walked over and placed by hand was indistinguishable
from one the phone had guessed.

**Placement is provenance, not a grade, and every other decision here follows from that sentence.**
`community_trees.placement` is filed beside `source` and `verification_state` because it is the same
kind of fact — how the record came to say what it says — and BUILD-PLAN §5 requires every provenance
fact to be a queryable column rather than something a screen knows. It is emphatically *not* a fourth
vocabulary of trustworthiness. A contributor who moved the pin was very often **more** accurate than
the phone: they could see the tree and the phone could not, and a GPS fix in a San Francisco street
canyon is routinely 20–40 m out, which is the argument the movable pin was built on in the first
place. The column exists so that somebody correcting a coordinate later, or a moderator looking at
one, can tell a judgement from a reading. It does not exist so that either can be doubted on sight.

**Which is why the tree profile states both arms.** `position from GPS` and `position placed by hand`,
appended as the last element of screen 03's provenance line, where `source` and `verification_state`
are already read out. It would have been cheaper to print something only for the placed case, and that
is exactly what turns a label into a warning: the marked case is the exceptional one, and an
exceptional coordinate reads as a suspect coordinate. Both arms name the instrument and neither
evaluates it, the way `SF city inventory` names a source without praising it — and there is a test
asserting that property by name, "neither placement line evaluates the coordinate it describes".
A badge or a stat card of its own was declined for the same reason the line was chosen: a second,
parallel vocabulary elsewhere on the screen would be the app describing one kind of fact twice.
Community rows only — a city-import row has no `placement` behind it, the city arrived at its
coordinate by neither of these means, and printing `position from GPS` over an inventory row is a
claim nothing in the seed supports. The words are the owner's own, kept rather than improved.

**The migration's four rulings, distilled — `AppSchema.applyV10` carries each argument in full, and
that is the file to read before editing it.**

*A CHECK, not a bare TEXT column.* E132's note proposed `placement TEXT NOT NULL DEFAULT 'gps'`. Every
other closed vocabulary in this schema also carries its vocabulary in a CHECK — `source`, `status`,
`verification_state`, `shot_type`, `moderation_state`, `kind`, `category`, `unit_entered`, `method` —
because the invariant has to hold against a hand-written `INSERT` in a debugger and not merely against
the DAO. A bare column accepts `'GPS'`, `'true'` and `''`, and `CommunityTreeStore.decode` would then
throw on a row the engine had cheerfully accepted.

*`ALTER TABLE ADD COLUMN`, not a table rebuild.* v3, v5 and v9 each rebuilt their table because SQLite
cannot drop a NOT NULL, replace a UNIQUE or widen a CHECK in place. None of that applies here: nothing
existing changes, and SQLite does accept a CHECK on an added column — it declines only PRIMARY KEY and
UNIQUE — and enforces it from that moment. A rebuild would copy every community tree in the database
to gain nothing, and copying rows is the one thing in a migration that can lose them.

*The `'gps'` default is a true statement about every row it backfills, not a plausible guess.* Every
community tree written before this column existed was written at `location.fix.coordinate` verbatim,
because the add screen had no other behaviour until E132 gave it one. The backfill records what
happened. That is the **opposite** of v2's situation, where the old rows' real value was unrecorded and
the plausible guess was the harmful one, and the distinction is worth keeping in mind the next time a
migration needs a default: the question is not whether the value is likely, it is whether the history
is known. It also fails in the safe direction if it is ever wrong — a row mislabelled `gps`
under-claims, and the failure this column must never have is a coordinate silently claiming to have
been placed by somebody who never touched it.

*No distance column, argued rather than skipped.* A pin dropped 3 m from the fix and one dropped 74 m
away are different claims, and storing the offset was genuinely on the table. Three things decided
against it. The offset is measured from an anchor whose own error is the reason the pin exists — a
40 m street-canyon fix — so "74 m" is 74 ± 40, and `community_trees` is the one contribution table
with no `gps_accuracy_m` column to say so; storing a REAL to millimetres against an anchor that vague
dresses an estimate as a measurement, which is precisely what D7 refuses for the city's DBH buckets.
It would be the only continuous quantity in a provenance vocabulary that is otherwise categorical, and
a number invites ranking in a way a category does not — 74 m starts to look like a worse tree. And the
coordinate plus the offset puts the person who added the tree on a circle of known radius around it,
which is the fact A7 fuzzes photo coordinates to a 25 m grid to avoid. If a moderator surface later
needs the distance, that is a migration with `gps_accuracy_m` and the anchor in it, and the anchor is a
record of where somebody stood.

The migration is idempotent by guard, in v3's shape, because `ALTER TABLE ADD COLUMN` has no
`IF NOT EXISTS` and a replay after an interrupted run would fail on "duplicate column name" and strand
the database one version short.

**`contributor_placed`, not `manual` and not `user`.** It names the author of the fact, the way
`tree_names.given_by` and `review_flags.raised_by` already do. "Manual" carries a whiff of an
override, which is exactly the reading this column must not invite.

**Two `Placement` types, and keeping them apart is deliberate.** `TreePlacement` is the record's: two
cases, raw values frozen by v10's CHECK, defaulting to `.gps` so that a caller with no pin to offer is
not obliged to have an opinion and so that the default on the boundary and the default in the column
say the same thing. `VisitAddTreeModel.Placement` is the *screen's*, and it carries two coordinates the
record does not keep — the pin, and the fix it was placed against — which is what lets the screen say
"23 m north-east" while the reader can still change their mind. The mapping is one-way and lossy on
purpose, and it lives in a derived `treePlacement` property rather than inside `add()`, so that what
the record *will* say can be asserted without performing a write. A pin nudged back onto the fix reads
`.gps`, because a reader who moved nothing made no judgement to record.

**The value is bound on the insert rather than left to the column default**, and the comment in
`CommunityTreeStore` says why: the default is what an upgraded row that predates the column gets, and a
row written now states its own provenance. A writer that let the default answer for it would record
`gps` for a pin somebody placed by hand — the one direction this column must never fail in.

**Verified by reading the column, not by asking the object.** 594 unit tests pass. `TreePlacementTests`
drives the real screen, the real `addTree` and the real store, then reads `placement` back out of
`community_trees` with SQL, and its header names the reason as a defect this project has produced
twice: a test that asks the object it just configured whether it holds the right value proves nothing
about the write. Both arms are asserted, because a column with a DEFAULT is very easy to get backwards
and a suite that only ever checked the hand-placed case would pass with the value hard-coded. The CHECK
is exercised against a value that is neither of the two, and an upgraded pre-column row is exercised
for reading back as GPS.

**The break test is what says the suite bites.** Forcing `treePlacement` to return `.gps` always fails
three assertions, and the spread is the point: one on the model, one on the stored SQL text, and one on
the value decoded back out. Three layers, so no single mock, no single decode and no single accessor
can be the thing holding the property up.

**Still open, and inherited rather than introduced.** E132's other open item is untouched:
`community_trees` is insert-only by design, so a placement can now be recorded and still cannot be
revised, and the same is true of the coordinate it describes. A contributor who realises afterwards
that the pin went in the wrong place has nowhere to say so.

---

### E139 — the map was measured with the location turned off, twice

E130 cut screen 01 from 1,300 markers to under 300 and measured a 2,061 ms frame down to 28. It was
real and it helped. The project owner installed it on their own iPhone and said the map was still
slow. E130's own note argued that rebuilding the annotation layer on every GPS fix "costs nothing
SwiftUI cannot diff away". The owner's phone disproved that sentence, and it took a third round to
find out why nobody had seen it.

**Both prior measurements were taken with location permission declined.** That opens the camera at
the fixed fallback centre — Mission Dolores **Park**, a park, in a *street* tree inventory — with ten
markers on screen. Neither run was ever a measurement of a full screen of pins, and a static
`simctl location` fires `didUpdateLocations` once and never again, so neither *could* have exercised
the GPS path. With a fix granted and 167 markers, the same build idles at **1 fps with a worst frame
of 862 ms**, rebuilding an annotation layer that has not changed, twelve to eighteen times a second,
with nobody touching the glass.

**Three defects, found in the order they were hiding behind each other.**

**A `@State` default expression that opened a GPS session.** `MapHomeView` declared
`@State private var location = MapLocationProvider()`. A SwiftUI `@State` default expression is
re-evaluated on *every initialisation of the view struct*; `RootView.body` initialises this one on
every pass; and `MapLocationProvider.init` called `startUpdatingLocation()` right there. So screen 01
stood up and discarded roughly **fifty `CLLocationManager` sessions a second**, each delivering a
cached fix and rewriting observable state on its way out — 336 provider instances in seven measured
seconds. The provider now comes from the composition root, which `ARCHITECTURE.md` §3 already
required; the app had been running two providers and two GPS sessions against that sentence.
`RootView`'s own comment claiming its provider "is never `start()`ed here" had been false since it
was written. **A comment asserting an invariant is not a test of it.**

**`distanceFilter = 5` is not honoured.** Measured on a simulated 4 m/s walk: 24–42 fixes a second,
one every fifteen centimetres. The fix is not to coarsen anything — `desiredAccuracy` stays at
`Best` and `distanceFilter` stays at 5, because 5 m is what screen 02 needs to tell two trees on one
block apart — but to keep, in the write, the promise the setting was already making.

**And underneath both, ~200 SwiftUI-hosted annotations that never settle.** Ablations, each built,
installed and run: remove the GPS dot, no change; disable the amber pin's `repeatForever` pulse, no
change; decline location and draw nine markers, a flat 60 fps and zero rebuilds. The variable is the
count of hosted views, and the failure is not "a bit more per pan" — it is a map that never comes to
rest. `MapCanvas` has advertised a replaceable basemap since C18; `MapAnnotationLayer` takes that
seam with an `MKMapView` and `dequeueReusableAnnotationView`, each marker a bitmap of the C19 pin
rendered **once per kind** by `ImageRenderer`, so the design system stays the single source of truth
and there is no hand-drawn second copy of the pin. MapKit's own `clusteringIdentifier` is declined
and the reason is written where somebody will look for it: this app clusters in SQL on an absolute
grid, and MapKit's is screen-space, so it would lay a second grid on top of the first and undo E130.

**Verified independently of the agent that did the work**, because two rounds of measurement had
already been believed and been wrong. The frame probe was cherry-picked alone onto *unmodified*
`main`, both builds were driven over one route in the Mission at 4 m/s on the same simulator with
location **granted**, and the overlay was read off screenshots:

| | before (main) | after |
|---|---|---|
| frame rate | **1 fps** | **46 fps** |
| worst frame | **862 ms** | **49 ms** |
| GPS writes per second | 36 | 0 |
| markers on screen | 167 | 159 |

**The instrument moved onto the glass.** `MapFrameProbe` had the numbers and printed them to stdout;
a person holding a phone has no stdout, which is exactly how two rounds of "measured on a simulator,
stated as a limit" were believed anyway. It now publishes a one-second snapshot that
`MapProbeOverlay` draws in the corner — fps, worst frame, marker count, zoom, and three counters
(`gps` / `body` / `fetch`) that tell the three candidate causes apart from the outside. `#if DEBUG`
in both files and at every call site, off unless `CYPRESS_MAP_PROBE=1`, and proved absent from
Release against the right artifacts with a control that fires — the trap E117 records.

**What is honestly still open.**

The basemap still re-evaluates its body around 200 times a second at rest once a fix has arrived.
`Self._printChanges()` puts the trigger at or above `RootView`, not in the map. It now costs about a
fifth of the frame budget rather than ninety-eight per cent of it, because a pass is ~1 ms instead of
~77 ms — so it is cheap, and it is still wrong. It is not fixed here.

And the limit on every number above: these are **simulator** figures. The *rate* of 24–42 callbacks
a second at walking pace is a simulator artifact — no GNSS receiver produces a fix every fifteen
centimetres; a phone gives roughly 1 Hz. What transfers is the per-publish cost and the mechanism,
not the absolute frame rate. The overlay exists precisely so that the claim can be checked on the
owner's own hardware instead of inferred from a Mac, which is what went wrong twice.

### E140 — the map could not be moved off the reader's own location

The owner, on their own iPhone, on the build that shipped that morning:

> "the center me on the map button PREVENTS THE MAP FROM BEING MOVED OFF THE CURRENT LOCATION. Every
> time I moved the map, in a second I got brought back to where I am centered and there was no way I
> could figure out around this. STUPID AND BAD"

The default screen of the app could not be panned. It had shipped that way in the merge of two rounds
that both touched the camera — the recentre control (#66) and the `MKMapView` rewrite (E139).

**The gesture was landing all along.** The first reproduction attempts drew a blank: a synthetic drag
left the geography unchanged and `mapViewDidChangeVisibleRegion` never fired, which looked like a
swallowed gesture — a different defect. It was an artifact of the drag. A two-point swipe does nothing
to MapKit; a ten-point path with 70 ms between points does. With one of those, and the counters on
screen, the reproduction is unambiguous: **44 region changes during the drag, three app-driven camera
writes after it, and a screenshot identical to the one before it.** The map moved and was driven back
inside a frame.

**What drove it back.** When the camera settled, the coordinator asked whether the map had drifted far
from the last camera the app had requested, and if it had — a real pan — it cleared its record of that
request. The intent was to stop a second press of the recentre control being swallowed as a duplicate
value. But nothing upstream had changed: a pan writes `region`, never `position`, and `position` still
held the one-shot centring on the first GPS fix. So the next `updateUIView` found a position that
differed from an empty record, took it for a fresh request, and drove the camera to the fix. Ablating
that single line, the same drag left the map on Shotwell St with no camera write at all.

**Two fixes were wrong before the third was right, and the probe caught both.**

The first made the two sides agree: write the reader's region into the coordinator's record *and* into
`position`. It passed a test asserting the map stays panned. On the device it was worse than the bug —
`mapViewDidChangeVisibleRegion` firing 2,196 times and the camera re-applied 527 times in a few idle
seconds, the map drifting across the city untouched. Two independently constructed
`MapCameraPosition.region` values do not compare equal; what had been established earlier was only the
weaker claim that a *copy* equals its original.

Copying one value fixed that and the map still came back — 39 camera writes per pan. The instrument
answered the question directly: at the moment the guard let a write through, the record was **not**
empty, and the two cameras were **147 metres apart**, which is the length of the pan. Reading
`position` straight back after writing it returned exactly what had been written. The write was fine;
the *reader* was stale. `updateUIView` is called with the view value from a body pass, and that pass
read the app's state when it ran — so after a pan there is an update already in flight carrying the
camera from before the pan. On this screen, at 240 body passes a second, there always is.

**No comparison of camera values can survive that, so the fix does not make one.** A camera request
now carries a monotonic ticket (`MapCameraRequest`), and the layer applies a request only when its
ticket is newer than the last one it applied. A stale value carries a ticket already applied and is
ignored on sight. The drift heuristic is gone entirely: a press mints a ticket whether or not it names
the same place, so #66's second press works by construction and a settle has no opinion about the
camera at all.

**Measured, iPhone 16 simulator, location granted, 161 markers, the same ten-point drag:**

| | before | after |
|---|---|---|
| region changes during the drag | 44 | 40 |
| app-driven camera writes after it | 3 | **0** |
| where the map ended up | back on the GPS fix | where it was put |
| basemap body passes per second, at rest | 240 | **0** |
| frame rate at rest / worst frame | 56 fps / 34 ms | **60 fps / 17 ms** |

The last two rows were not the goal. E139 left it recorded that the basemap re-evaluated its body
around 200 times a second at rest with `Self._printChanges()` blaming something at or above
`RootView`, and called it cheap and still wrong. It was the camera: swapping the bound
`MapCameraPosition` for a small `Equatable` struct took it to **zero**. E139 guessed these might share
a root cause. They did.

**The recentre control, checked by hand afterwards, four presses on the device.** Panned away at z15:
first press centres and keeps z15, second press zooms to z18 — the 120 m opening scale, which is what
`MapRecentre` specifies. Already at 120 m: both presses are honoured and drive the camera rather than
being swallowed. A pinch produces no app-driven write at all.

**Two other screens had the same defect and are fixed by the same change**, because they share the
coordinator: the visit pin-adjust map (02) and the pin-set map. Neither had been reported, and neither
had a test that would have found it.

**What this cost, and the general form of it.** The bug was one line, and the two wrong fixes were
each one line, and all three were defensible from reading the code. What separated them was an
instrument — three counters drawn in the corner of the map — read off a screenshot. A test asserting
"the map stays where it was put" passed against a build that was writing the camera 527 times a
second. **An assertion about the outcome is not an assertion about the work done to reach it**, and on
this screen the second one is where the defects live.
### E141 — a contributor may now say what the tree is, and the record says who said it

The project owner, from real use: *"Should be possible to add tree species after/at same time as
adding a custom tree"*.

`VisitAddTreeModel.add()` deliberately sent no species, and the comment saying why was on the record
and was right about the case it was written for: this app cannot confirm a species from a photograph,
BUILD-PLAN §15 forbids fabricated botany, and the row it writes says `community-added, unverified` for
exactly that reason. **What that reasoning covers is a species the app guesses. It never covered a
species the contributor states.** Somebody who planted the tree in their own yard, or who knows a
London plane on sight, is a legitimate source, and declining to record what they said is not caution —
it is discarding evidence to avoid having to say where it came from. The schema already had the place
to say where it came from.

**No migration, and establishing that was the first job.** `community_trees.species_current` has
existed since the table did. `TreeDraft.speciesID` has always been on the boundary, `LocalAPI.addTree`
has always copied it onto the `Tree`, and `CommunityTreeStore.insert` has always bound it. The column
had no caller, not no column, and AppSchema stays at **v10**.

A `species_source` column was considered and refused, with E136's caution applied in the direction it
actually points here. On `community_trees` the provenance of a species claim is already two columns:
`source` is CHECK-pinned to `'community'` and `verification_state` defaults to `'unverified'`, so every
row says *a person put this here and nobody has stood behind it* by construction. A third column would
have had exactly one reachable value in this client — there is no organisation confirming botany here
and no classifier suggesting it — and a CHECK over a vocabulary guessed for futures that do not exist
is E136's mistake written in advance rather than discovered afterwards.

**Optional, and the reason is not convenience.** BUILD-PLAN §6 already settled it at the boundary
("requires photo, species optional") and a screen stricter than its own endpoint is a screen inventing
a rule. The argument that decides it is what a required field would *produce*: put a mandatory 569-row
picker in front of the CTA and a contributor who does not know has two ways forward, and the cheaper
one is to pick something plausible. A required species field does not collect more botany, it collects
**guessed** botany — the exact thing the original omission existed to prevent. Optional is the setting
under which "I'm not sure" costs nothing.

**The symmetry rule from E138 was tested against this line and deliberately not applied.** E138 prints
*both* arms of `placement` — "position from GPS" and "position placed by hand" — because marking only
the unusual one turns a label into a warning. Here only one arm is printed, and the shapes differ. A
coordinate always exists and always came from one of two instruments, so those are two provenances of
one fact and marking one ranks it against the other. A species does not always exist: the alternative
to "species named by a contributor" is not a second way of arriving at a species, it is **no species at
all**, which prints nothing because there is nothing to attribute. A symmetric second arm would have to
be a sentence about a species that does not exist. The symmetry E138 is really about is honoured one
level up and already — a city row reads `SF city inventory` and a community row reads
`community-added, unverified`, on the same line, neither of them the marked case. The new element only
says which *part* of a community record the contributor authored, and it names an author without
grading one, which is `placementNote`'s own test asserted again by name for this line.

It is "a contributor", not "the contributor": `community_trees` records no author at all — no
`user_id`, no `device_id` — so the row cannot say which person, and the definite article would imply
the one who added the tree and be quietly wrong the moment somebody else names the species on it.

**"After" was built, and the two refusals in it are the interesting part.** `CypressAPI.claimSpecies`
is a real protocol requirement with a default in `SpeciesClaim.swift` — an extension-only method has no
witness-table entry, dispatches statically, and would be unreachable through the `any CypressAPI` every
caller in this app holds. It refuses a city row with `.forbidden` (the species is the city's, in a
read-only ATTACHed database) and a second claim with `.conflict`. That second refusal is the honest
one: §6's species write is `POST /trees/{id}/species-assertions`, appending to the versioned chain
`SpeciesAssertion` models, and **`species_assertions` lives only in the seed** — `main` has no copy. So
a *correction* cannot be recorded with history on device, and overwriting without history is precisely
what the append-only chain exists to prevent. First claim wins, the way `tree_names` already rules for
the given name (D15), and the `WHERE species_current IS NULL` is in the UPDATE rather than in a
preceding SELECT so the rule is the engine's and not a race.

**What was reused.** `CypressAPI.searchSpecies` — the same protocol requirement `MapModel` calls,
backed by `SpeciesQueries.search`'s covering prefix scan over both names — and C20's own `SearchBar`.
No second search and no second query were written. `MapSearch` itself was *not* reused: its states are
claims about a viewport ("no sycamore in view", "showing 30 of 214 here") and a picker that borrowed
them would be answering questions nobody asked it. The prefix gap is stated rather than hidden: the
catalogue matches a prefix of either name, so the empty state says nothing *starts with* the query
rather than claiming no such tree exists.

**Not built, stated plainly.** Correcting a species already claimed, on any tree. It needs
`species_assertions` in `main` and a moderation surface to resolve competing claims, and standing that
up on a two-clause feature request would be inventing a product. `claimSpecies` returns `.conflict`
and the screen says so in words rather than failing silently.
### E142 — the app could crop a photograph four ways and show one zero ways, and the capture path was innocent

Two reports from the project owner, from their own iPhone, on the same day:

> Clicking on photo from tree page should show full view, current is horizontal which cuts off
> photos taken in vertical orientation.

> Photo for custom tree should be standard photo style, right now it's horizontal and cuts off
> vertical frame.

One root cause, and it is worth saying plainly which half of the system it is in.

**The capture path was already correct, and nothing in it was changed.** That was checked first,
because if the camera were constrained to landscape or the saved file were losing its orientation
tag, every display fix would be a cosmetic over a data loss. It is not:

- `VisitCameraController.configureAndRun` sets `sessionPreset = .photo` — the full sensor frame,
  4:3, no crop and no aspect constraint anywhere in the session.
- `capturePhoto` returns `AVCapturePhoto.fileDataRepresentation()`, the container as the ISP wrote
  it, orientation tag included.
- The photo-library fallback asks `PhotosPickerItem` for `Data.self`, not for an image, so it too
  gets the original container.
- `VisitPhotoStaging.write` does `data.write(to:)` and nothing else. No re-encode, no resize.
- `PhotoBinary.writeStrippingMetadata` empties the EXIF, GPS, IPTC, TIFF and Maker Note containers
  and then makes a **second pass** for the sole purpose of putting `kCGImagePropertyOrientation`
  back, with a comment saying exactly why: "an iPhone photograph taken in portrait is landscape
  pixels plus an orientation tag, so dropping it turns every portrait shot on its side".
- `PhotoImageStore.downsample` passes `kCGImageSourceCreateThumbnailWithTransform: true`, so the
  tag is applied to the pixels on the way out.

Every stage of that was written by somebody who had thought about portrait photographs. The bytes on
disk are the bytes the camera produced, the right way up. **The defect is entirely in what the app
chose to draw of them**, which is the less serious half — and it should be recorded that the more
serious half was looked for rather than assumed absent.

**The app had four fixed photo frames and no unfixed one.** The hero on 03 is 393×224. Screen 20's
rows are the same 224. The well on 14 is 268 tall in a column about 361 wide. All three are
`PhotoFill`, which is right — a hero has to be a known height or the page under it moves, and a list
whose rows change height cannot be scanned. The arithmetic is what makes it a defect: a 3:4
photograph scaled to fill 393 pt of width is 524 pt tall, so a 224 pt band keeps **42.7%** of the
picture, and it kept the middle 42.7% because `.center` is SwiftUI's default and nobody had ever
chosen it. Rows 28.5% to 71.5% survive. A street tree photographed from the pavement has its crown
in the top third and the kerb in the bottom third, so what survived was upper trunk — the part of a
tree that identifies nothing.

And the tap that should have escaped all of this had nowhere to go. Pressing the hero pushed screen
20, which is the same crop repeated down a page. **There was no last tap that produced a
photograph.** The owner's first sentence is precisely that: the "full view" they expected does not
exist anywhere in the app.

**Two fixes, because they are two different questions.**

*The crop, where a crop is correct.* `PhotoCropAnchor` — a custom `VerticalAlignment` that pins one
third of the way down both the box and the photograph. On the numbers above it keeps rows 19% to
62%: the canopy and the top of the trunk. A third rather than `.top`, because `.top` is sky —
a photographer framing a whole tree leaves headroom, and an anchor that keeps the headroom and drops
the tree has swapped one bad crop for another. `.crown` is the default because every fixed frame in
this app has a tree in it. **Screen 04 asks for `.centre` explicitly and must keep it**: its ghost
overlay, the frame just taken and the live `AVCaptureVideoPreviewLayer` behind both are three
drawings of one scene that only mean anything if they agree, and the layer's `.resizeAspectFill`
centres and is not ours to reconfigure.

*The absence of a viewer.* `PhotoFit` is `PhotoFill`'s counterpart — the whole frame, letterboxed,
at the shape of the file, still reporting the box it was proposed. `PhotoViewerView` is the screen
built on it, presented rather than pushed because it is a closer look at what is already on screen
rather than a place in the app. The well on 14 uses `PhotoFit` too, which is the second report: that
photograph is not being displayed, it is being **checked**, by somebody standing in front of the
tree in the last second before they commit a record they cannot amend. A crop there does not restyle
the picture, it withholds the evidence — a finger over the lens, a cut-off crown, next door's tree.

**The hero was one control doing two jobs, and that is why it could do neither.** It is now two: the
photograph opens the photograph, and the pill that already reads `3 photos · since 2024` opens the
three. Giving both jobs to the whole header is what left the picture unviewable; giving both to the
picture would have left screen 20 with no entrance at all. The pill grows to a 44 pt target with its
drawn capsule unmoved, per ARCHITECTURE §6 — it was a caption until now, so nothing was owed.

**Screen 20's photograph is a gesture and a named action, not a `Button`.** `PhotoFill` publishes it
as an *image* carrying the photograph's subject and date, because on that one screen the picture is
the thing being judged. A `Button` folds that label into itself and the element stops being an
image — and `DeepLinkVoiceOverTests.testAThumbActuallyVotes` finds the top card via `app.images`
matching `Photo · ` and reads the `Hero` badge's position against its frame. A button there would
have silently turned that test's subject into something it could no longer find.

**Verified by breaking it, because a crop is invisible to every measurement.** This is the E137
lesson in a second costume. `PhotoFill` reports the box it was proposed *whichever* part of the
photograph it keeps — that is its whole documented promise — so `sizeThatFits` is identical against a
centred crop and a crown-anchored one, and any test written on it would have been green against the
bug. The assertion has to be on pixels. `PhotoCropTests` renders a 300×400 fixture of three flat
bands (red canopy, green trunk, blue ground) into the hero's own 393×224 box and reads the colours
back out; the discriminating fact is that a crown-anchored crop contains **no blue at all** and a
centred one does. Setting the anchor fraction back to 0.5 turns it red.

**A third defect, found only by looking, that every test was blind to.** The viewer came up on the
device with its close button, its caption pill and the sentence "That photograph could not be opened"
across the middle. `PhotoImageStore` reaches the pushed destinations through `.environment(_:)` on
the `NavigationStack`, and it does not reach a `fullScreenCover`, which is presented in its own
hosting context. Nothing had ever noticed, because every sheet before this one — 09, 10, 15, and the
visit flow — takes what it needs as an argument, so no presented screen had ever read the
environment. The store is now handed to the cover's content explicitly.

What makes it worth its own paragraph is that **an absent store and a photograph whose bytes are gone
are the same state** to a view holding `PhotoImageStore?`, so the screen reported the second while
suffering the first, in fluent English, with correct chrome around it. 637 unit tests passed against
that build. The only thing that caught it was opening the screen and looking at it.

**And the fixture itself was evidence of nothing.** `LocalAPI.debugJPEG` drew a flat rectangle with
one white bar, which proved bytes had arrived and could not prove *which part of them* had — both
crops of it look identical. It is now a crude tree at 1200×1600, matching the `width`/`height` the
row had always claimed while producing 300×400. A screenshot of a hero can now be looked at and
answered.

### E143 — the six columns the seed was throwing away, and the mapping that would have mislabelled 150,000 street trees

The project owner asked for two things: *"Want to see more city details about trees e.g. when planted
next pruning last pruning and others"* (#68), and a way for a new tree to say *"whether it stands on a
street, in a city park, or on private property"* (#69). Both needed data the seed builder was
discarding. This entry lands the data and the schema; neither screen is built here.

**Seven columns were being dropped, not five.** The list carried into this round — `qCaretaker`,
`qLegalStatus`, `PlotSize`, `PermitNotes`, `PlantType` — was recorded from a reading of
`build_seed.py` rather than from the dataset, and the dataset is the authority. Checked against
DataSF `tkzw-k3nq`'s own published column metadata, it also omitted **`qCareAssistant`** (25,199 rows,
of which 22,879 say `FUF` — Friends of the Urban Forest, who planted them) and **`SiteOrder`** (99.1%
populated). Six are now ingested. `SiteOrder` is refused: it is an ordinal disambiguating several
trees at one address, a key inside the city's table rather than a fact about a tree, and "tree 3 of 7"
answers nothing anybody asked. `XCoord`/`YCoord`/`Location` are the same point as `lat`/`lon`, and the
six `Fire Prevention Districts`-style columns are Socrata `:@computed_region_*` join artifacts whose
values are opaque row ids into other datasets — the "Zip Codes" column's commonest value is `28859`.

**`qLegalStatus` was "explicitly retained" into a column that ships empty.** The comment above
`MAPPED_COLUMNS` claimed it was retained per BUILD-PLAN §7. It was — into `city_raw`, which is `NULL`
in the shipped seed because the passthrough costs ~74 MB, and which no code path in the app has ever
read. It was retained the way something is retained by being written to a column nobody populates.
This is the same defect class the ROADMAP already names: the most confident comment in the file.

Populations over all 195,309 seed rows: `legal_status` 195,252 (99.97%), `caretaker` 195,309 (100%),
`care_assistant` 25,199 (12.90%), `plant_type` 195,309 (100%), `plot_size` 146,951 (75.24%),
`permit_notes` 52,580 (26.92%).

**THERE IS NO PRUNING DATA, AND THE ANSWER IS DEFINITIVE.** `tkzw-k3nq` has eighteen real columns and
not one records a pruning event, date or schedule — verified against the dataset's live column
metadata, not only against a downloaded copy. The nearest things in the data are two `qLegalStatus`
values, `Prune Opt Out` (196 rows) and `Street Tree Maintenance Opt Out` (58), which say somebody
withdrew a site from the city's maintenance programme. That is a **standing policy about a tree, not a
date on which anything happened to it**, and it must never render as one. Pruning history would have
to come from a different city system. `CityRecordTests.thereIsNoPruningData` asserts no seed column
mentions pruning, so the day DataSF starts publishing one the test fails and #68's question is
reopened deliberately rather than staying quietly unanswerable.

**The mapping for #69, and the trap in it.** DataSF describes `qCaretaker` as "Agency or person that
is primary caregiver to tree. **Owner of Tree**", and 163,955 of 195,309 rows say `Private` — 84%.
Read as a location it is catastrophic and it looks entirely reasonable: 112,955 of those same rows
carry `qLegalStatus = 'DPW Maintained'`. They stand in the sidewalk, in the public right-of-way, and
the private party named is the adjacent owner who waters them. Measured both ways over the whole seed:

|                     | jurisdiction leads | caretaker leads |
|---------------------|-------------------:|----------------:|
| `.street`           |            182,320 |          30,080 |
| `.privateProperty`  |             11,856 |         164,096 |

A caretaker-led mapping mislabels **152,240 street trees as private property**. Those two columns are
the actual measured output of `LandContext.inferred(from:)` and of a deliberately broken version of
it, so the number is observed rather than estimated.

**So jurisdiction leads and care fills in.** `qLegalStatus` decides wherever it names a jurisdiction.
`Significant Tree` and `Landmark tree` are protective designations SF's Public Works Code attaches on
either side of the property line, and `Undocumented`/blank say nothing by construction; for those
12,286 rows the caretaker is the only signal left and answers for them alone. Final distribution over
all 195,309 rows, re-derived from every row by `bucketsMatchTheDocumentedDistribution` so the table
cannot rot: `.street` 182,320 (93.35%), `.privateProperty` 11,856 (6.07%), `.otherPublic` 956 (0.49%),
`.cityPark` 177 (0.09%), unresolved 0.

**`.cityPark` is 177 rows and that is the finding, not a bug.** This is the *Street* Tree List. 720
rows name `Rec/Park` as caretaker but 543 of them also carry a DPW jurisdiction — a street tree along
a park's edge that Rec/Park waters — and calling that "in a city park" is the error a person standing
on the sidewalk can see. San Francisco's actual park trees are largely not in this dataset. For #69
that is a feature: somebody adding a tree in Golden Gate Park is adding something the city does not
have.

**Four values where three were asked for, and E136 is the whole reason.** The ask was street / city
park / private property. The city's inventory contains 956 rows that are none of them — SFUSD, the
Port, the PUC, the Housing Authority, the Fire Department, the Arts Commission: public land that is
neither street nor park. A CHECK pinned to three makes those unstorable, which is E136's `photo_votes`
failure repeated exactly: a constraint wearing a ruling's clothes, forbidding a state the product
turns out to need. The asymmetry decides it — a permitted value no screen offers costs nothing, a
forbidden value the data contains costs a migration. `.otherPublic` exists; #69's picker is free to
offer three.

**One migration, and working out that it was only one was the first job.** All six city columns land
on `seed.trees`, and the seed is a **bundled read-only** database ATTACHed beside `main`. It is a
build product replaced wholesale on install, with no user data to carry forward, so a schema change
there needs no migration and cannot have one. What is not covered by that is a fact a *contributor*
states, which must be written and must survive an upgrade. **AppSchema v11** adds
`community_trees.land_context` for exactly that and nothing else.

**The six seed columns carry no CHECK, and that is a decision.** Every closed vocabulary in the app
schema carries its vocabulary in a CHECK because that database is written by a DAO and by whoever
opens it in a debugger. None of that reaches the seed: the only writer is `build_seed.py`, and the
hand-written `INSERT` a CHECK would catch is one nobody can perform against a database shipped inside
an `.app`. What a CHECK would do instead is pin twelve legal statuses and twenty-seven caretakers that
belong to San Francisco rather than to Cypress — a list reading `Asian Arts Commission`, `Mission
Verde`, `Office of Mayor`, which grows whenever a department is renamed — and turn the next weekly
diff into a build failure over a string the city was entitled to add. BUILD-PLAN §7 settled the same
question the same way for `site_type`. The vocabulary that *is* Cypress's is CHECK-pinned where it is
actually written: `land_context`.

**`land_context` is nullable with no default, unlike v10's `placement`.** Every community tree written
before v10 *had* a placement — `gps`, because the screen had no other behaviour — so backfilling
recorded what happened. No tree written before v11 has ever been asked what ground it stands on, so
there is no true value and any default would be Cypress putting words in a contributor's mouth.
`'street'` is the plausible guess and the harmful one: it is the answer that makes a tree look like
the city's business, and a wrong `'street'` on a tree in somebody's front yard ends in a 311 call
about a tree 311 does not handle.

**`plot_size` is TEXT and is never parsed.** 588 distinct values in three incompatible notations plus
a bare integer of unstated unit: `Width 3ft` (36,866), `3x3` (31,760), `3X3` (12,135), `60` (782),
`10x10` (367). DataSF's published description of the field reads "date tree was planted", copied from
`PlantDate` — the field is under-curated at the source. Deriving an area would be D7's forbidden move,
dressing an estimate as a measurement.

**Nothing is normalised on the way in.** `PlantType` holds `Tree` 194,988 times, `Landscaping` 318
times and `tree` 3 times. Correcting that case would be editing the city's record to make it tidier,
which is not the builder's job; readers compare case-folded. Blank becomes `NULL`, because storing
`''` makes "the city recorded nothing" indistinguishable from "the value is nothing".

**Provenance is carried, not inferred at the point of display.** A contributor who tapped "city park"
observed it; a city row's context is Cypress's *reading* of two strings, and that reading can be wrong
about any individual tree. `Tree.landContext` returns a `KnownLandContext` naming its own source
rather than a bare `LandContext`, so a screen cannot show an inference with the confidence of an
observation — BUILD-PLAN §5's requirement that every provenance fact be a queryable column rather than
something a screen remembers.

**The land context is derived for city rows, not stored.** Storing it would put Cypress's inference
inside a table that otherwise holds San Francisco's record, create a derived column that can disagree
with its own inputs, and make revising the mapping a 95 MB rebuild instead of a code change. It lives
in `LandContext.inferred(from:)`, in `Core`, under test.

**The seed grew 95.3 MB → 103.6 MB**, +8.7%, which is the honest price of six columns over 195,309
rows and is stated rather than buried. Row counts did not move — 195,309 trees, 569 species — and
`ANALYZE` still runs, so `sqlite_stat1` survives and E134's 14× map regression stays fixed. If bundle
size later becomes the binding constraint, `legal_status`, `caretaker` and `plant_type` are 42
distinct strings across 585,927 cells and normalise into a lookup table cleanly; that was not done now
because nobody has asked for the bytes back.

**A consequence #69 must know about, flagged and not fixed.** `ReportPresentation.showsHazardBranch`
is `selection.hazard != nil` and nothing more. The 311 panel — *"This may be a public-safety hazard"*,
`Call 311 now` — is gated on the chip alone; `ReportModel` holds a `treeID` and never looks at the
tree. So a tree marked private property today gets the identical 311 handoff, and 311 is the city's
line for *city* trees. Nobody can reach that state yet, because nothing writes `land_context` until
#69 ships a picker — which is exactly why it is written down now. The moment a contributor can mark a
tree private, screen 06 is routing them to a number that will not take the report. That is a product
decision (does the panel change its copy, offer a different destination, or say plainly that the city
does not handle this tree?) and belongs to whoever builds #69, not to this round.

### E144 — every screen that named a record, and none of them said where it was

The project owner, from real use on their own iPhone:

> "In almanac under this season need a way to find the tree mentioned. Right now clicking just takes
> to tree page but I have no idea where tree is"

**The almanac is where it was noticed and not where it is.** Six surfaces in the app name a record —
the almanac's season rows, My Grove, the journal, the species screen's nearby list, the map's own
card, and search — and every one of them pushes the tree profile, the memorial or the vacant site.
None of those three said where the record was. An affordance built on the almanac's rows would have
had to be built five more times: five more places to word it differently, five more destinations to
drift apart. So the control goes on the junction — one button, on the three screens a record can be
drawn on — and there is one destination behind it.

**The destination already existed.** E129 answered the identical sentence for screen 12's two
*counted* rows and built `PinSetMapView` to do it. A group of one is a `PinSet`, so this is a third
subject on that type rather than a second map screen; the alternative is two answers to one question,
which is the shape of defect E129 was itself closing.

**Three things separate a map from an answer**, and each is a defect that a correct-looking map still
has:

- **The camera opens at `MapLayout.defaultSpanMetres`** — E12's 120 m, measured as the scale where
  San Francisco's street trees stop fusing into a mat — **centred on the record and never on what the
  read returned.** Framing the neighbours instead opens at whatever they happen to span: with the
  camera deliberately broken that way the assertion measured **1,080 m**, nine times out, with the
  subject a dot among dots.
- **The record is on the map from the first frame.** It travels on the route as a payload and is
  drawn without any read having happened, so there is no window in which the camera has arrived and
  the pin has not — a map that flies somewhere and shows nothing for a beat is the failure mode here,
  and on a slow or failed read it would never fill in at all.
- **The record is drawn selected**, through `selectedPinID` and `MapAnnotationLayer.applySelection`,
  the app's existing 1.25×. No second highlight was invented: a second way to say "this one" is a
  second thing to keep in step with C19.

**The rest of the block is read, once, and is the only query this screen has ever made.** A single
pin answers "which street" and stops; a person standing on that street is asking *which one*, and a
pin drawn alone cannot be counted along a block. E129's rule against re-reading is not broken by
this, and the reason is precise: that rule exists because the almanac's row has **printed a count**,
and a second read can disagree with it. Nothing here is counted. The context is scenery, the sentence
over the map only mentions it once it has arrived, and if the read fails the screen is the one-pin
map it would have been anyway.

**A basin and a memorial get the same control, unchanged.** Both are reachable from the same lists,
both are places, and C19 already draws each in its own vocabulary (R7, E107) — so the map states what
kind of record stands there without a word of copy changing. On the memorial it is also the only
thing on screen 19 there is to press, which does not break 19's rule: everything else a profile
offers *writes*, and there is nothing left to contribute to a felled tree. This writes nothing. It
answers where the tree stood, which is a fact the record already holds.

**The one camera write on this screen is a press.** A pushed map opens on `MapCameraRequest.opening`,
sequence zero, because that getter runs on every pass and a ticket there would be a new request sixty
times a second. What mints a ticket is the control that goes back to the subject after a pan —
`.move(to:)`, from a main-thread gesture handler, exactly as the recentre press does (E140). Nothing
in the file drives the camera off a state change, which is the property E140 paid for; checked by
hand on the device with a ten-point drag, the map stayed where it was put and the press brought it
back.

**Found by looking rather than by asserting:** a vacant site's H1 *is* its street address, so the
map's street line printed `601 Dolores St` one line under `601 Dolores St`. The line is absent now
rather than paraphrased — the address is already on screen, and saying it differently the second time
would be the app filling a slot instead of answering. It has a test now; it never would have had one,
because nothing was wrong with either string.

**Verified end to end on the simulator, location granted**, over the owner's own route: almanac →
`The elder` → the profile → `Show me where this is` → a map of 21st St in the Mission with the
Brazilian Pepper at 3426 21st St the larger pin among some thirty neighbours. The vacant site and the
memorial were driven the same way and drew the basin pin and the grey dash-marked pin respectively,
each enlarged, each centred.

### E145 — the city's record on the tree page, and the pruning answer the data cannot give

The project owner asked for two things and this entry draws both. *"Want to see more city details
about trees e.g. when planted next pruning last pruning and others"* (#68), and *"need to see this
distinction on tree's landing page too, along with other tree metadata"* — the distinction being
street / city park / private property, task #69. E143 landed the six DataSF columns and
`LandContext.inferred(from:)` and drew neither; this is the screen.

**Screen 03/14 §9b, `What San Francisco has on file`.** Five cards at most: what the city lists the
record as, the legal status, who cares for the tree, who assists, the plot size. Under them, a
sentence or two. Above them, one sentence about where the tree stands. No new component: it is
`StatGrid`/`StatCard` (C11), which is what already renders labelled facts on this screen, under a
`.cypressMicroLabel()` header, which is how the You tab labels a section.

**Every card is a `StatCard.Value.cityRecord`, and that is the whole design.** D7 built that case for
the DBH bucket — the value in mono with C12's `city record` badge beside it, reading out to VoiceOver
as "from the city record". Reusing it means a card of this section cannot be drawn, screenshotted or
listened to without its source attached, and it means no second vocabulary was invented for a
distinction the app already draws. A plain `.text` card would have been Cypress asserting
`DPW Maintained`.

**`plotSize`: the notation is read, the numbers are not touched, and 20,540 rows draw nothing.**
588 distinct values in three incompatible notations plus junk. Printing them verbatim is not showing
the city's record, it is handing the reader the city's data-entry problem. So `Width 3ft` renders
`3 ft wide` and `3x3`/`3X3` render `3 × 3` — **with no unit appended to the pair**, because the city
named none and feet is a guess that would be right most of the time and invisible when it was wrong.
No area is derived: `CityRecord.plotSize` forbids it and D7 is why.

Three classes draw no card at all, and each is a decision rather than a parser limit. **`Width 0ft`,
17,254 rows** — a basin zero feet wide is not a measurement of a basin, it is the shape "not measured"
takes in a form that wanted a number, which is E77's argument about a plain `0` reading as a
measurement of zero. **A bare integer, 2,726 rows** — `60`, `20`, `5`: no dimension, no unit, sixty of
what across what. **560 strings that are not sizes** — `M6`, `TR`, `POT`, `Plaza`, `aaa`, `?`, plot
codes from inside a Public Works workflow. They render exactly like the 48,358 rows where the city
wrote nothing, because in the sense that matters they are the same thing. 126,411 of 146,951
populated rows draw a plot size (86.0%), and both totals are re-derived from every row by
`everyPlotSizeInTheSeedIsShownOrRefusedOnPurpose` so the paragraph cannot rot.

**`permitNotes` is refused entirely, and it is two columns wearing one name.** 52,114 of its 52,580
rows are a permit reference — a key into a permitting system this app cannot query or link to, which
is the test E143 used to refuse `SiteOrder`. The other 466 are staff working notes: `I believe these
were planted in 2010 by FUF. C.Buck` · `Resulted descion 9/7/16 -DE` · `privately planted on dpw
street; unpermitted` · `Maintenance agreement ends 8/17/2010`. Publishing those under a badge reading
`city record` would dress a named clerk's guess as San Francisco's finding, and would put an
employee's initials and an unverified accusation about a private owner on a public screen. The two
cannot be told apart by a renderer, only guessed at by prefix — the same class of mistake as parsing
`plotSize` — and neither belongs on its own merits, so neither is drawn.

**`plantType` speaks only when it disagrees with the screen.** 194,991 rows say `Tree`; a card
reading `City lists this as — Tree`, on a tree page reached from a tree map, is a row of the panel
spent saying nothing. The 318 `Landscaping` rows are the only place the inventory says a record on
the tree map is not a tree, and they lead the section. This is **not** `placementNote`'s "only the
unusual case" mistake: that argument is about two provenances of one fact, where marking one ranks it
against the other. `Tree` restates what the rest of the screen has already said and `Landscaping`
contradicts it — suppressing an echo is not suppressing an alternative.

**`caretaker` is labelled `Cared for by`, never `Owner`, and that label is load-bearing.** DataSF's
own description ends "Owner of Tree", and reading it that way is the 152,240-tree error E143 measured.
163,955 rows say `Private` and 112,955 of those also say `DPW Maintained`: sidewalk trees whose
adjacent owner waters them. A card labelled `Caretaker` invites the reader to make by hand exactly the
inference `LandContext.inferred(from:)` exists not to make.

**Codes are expanded; nothing else is.** `FUF` → `Friends of the Urban Forest` (22,879 trees, and the
one value in these columns worth telling somebody about), plus `DPW`, `PUC`, `MTA`, `SFUSD`,
`Rec/Park`, and `Private` → `A private party` because a bare adjective in a card labelled `Cared for
by` reads as a category and the category a reader reaches for is the property line. **Unknown values
pass through verbatim** — `Port`, `Mission Verde`, `CAN` — which is what keeps this safe against the
weekly refresh, the same shape of answer E143 gave when it refused a CHECK on these columns.
Expanding an acronym says the same thing at length; it is not the tidying E143 rules out.

**The pruning question is answered on screen, once, as a fact about the dataset.** E143 verified
against `tkzw-k3nq`'s own published column metadata that not one of eighteen columns records a pruning
event, date or schedule. The section closes with `The city's street tree inventory records no pruning
dates or schedule.` — the *inventory*, not the city, because San Francisco certainly prunes its trees
and a sentence saying otherwise would be false about a public works department.

The alternative — a `Last pruned · Unknown` card — was rejected on grounds that are not taste.
`Unknown` in a card is a claim about **this tree**: the value exists and Cypress has not got it. What
is true is a claim about the **source**. Only one of those is true, and the card version would be the
first `Unknown` on a screen whose entire grammar for "no such fact" is to draw nothing, on all 195,309
city rows. Silence was rejected too: the owner asked, and an answer that lives only in an errata entry
means the question gets asked again from the same wrong premise, which this project has paid for more
than once. **The line this must not cross:** the inventory also records no watering schedule, no soil
volume, no root barrier and no inspection date, and none of those get a line. If a second one is ever
wanted, the honest move is one "what the city does not record" sentence, not a growing list.

**The 254 opt-out trees get a sentence of their own**, because `Prune Opt Out` (196) and `Street Tree
Maintenance Opt Out` (58) are real facts about specific trees and are exactly the strings a reader
looking for pruning history will read as pruning history. The status renders verbatim on its card, and
under the grid: `This site is withdrawn from the city's pruning programme — a standing arrangement,
with no date on the record.`

**Land context is a sentence, outside the city's section, naming whoever concluded it.** A city row's
context is Cypress's *reading* of two strings — a rule that can be wrong about any individual tree —
so it reads `Cypress reads the city's record as a tree on a street.` A community row's is an
observation and reads `A contributor said this tree stands in a city park.` A `StatCard` was rejected
because it has nowhere to put a source but a badge, and C12's two cases do not fit: stamping
`city record` on Cypress's own inference is precisely the failure this round exists to avoid, and
adding cases would need a colour ramp ranking the two ways of knowing. There is no such ranking — a
contributor who was standing there beats the seed, and the seed covers 195,309 trees nobody has
visited. A sentence has room to name its speaker in words, which is `speciesClaimNote`'s grammar one
block up the same screen. Putting it inside a section headed with the city's name would have been the
app's inference wearing the city's authority.

**E146 built the same fact at the same time, as a stat card, and the two met in a merge.** Both rounds
were answering the same clause of the same request, neither saw the other, and for the length of one
branch screen 03 said where the tree stands twice. The card was removed and this sentence kept, on the
argument above — which E146's round had not been in a position to read, and whose own measurement (the
subtitle was already five elements long) rules out the subtitle without choosing between a card and a
sentence. The full account, including what of E146 stayed, is in that entry.

**A community tree draws no section and no empty state for one.** The subtitle already reads
`community-added, unverified`; a second sentence saying the city has nothing would be the app
apologising for a tree somebody added on purpose.

**Two defects that only a rendered screen could show, both in C11.** The `.cityRecord` case had held
one shape of value since it was written — `30–35 cm`, six characters — and §9b put whole strings in it
inside a half-width grid cell beside a badge that is `.fixedSize()` and never yields. The badge parked
itself *between* two lines of the value it qualifies, so a card read `Prune · city record · Opt Out`;
and `Landscaping` broke mid-word as `Landscapin / g`. The badge now sits on the last text baseline,
and a `ViewThatFits` drops it below the value when the two cannot share a line. No
`minimumScaleFactor` and no truncation: both make the city's own string harder to read to protect a
layout, and the section exists to show that string. Neither was visible to 689 passing tests, and both
were obvious in the first contact sheet.

**`ScreenSweepShots.capture` gained a `viewportHeight`, and then a reason to distrust it.** The
section is the last block on screen 03 and an off-screen `ScrollView` cannot be scrolled, so a
phone-height capture of a cold profile stops just above the header — the harness was photographing
every state of this section as empty space. Raising the window fixed that at 1,500 pt and broke
silently at 3,600: `drawHierarchy` into an off-screen window stops producing pixels somewhere past
8,192 px of backing store (3× a 2,730 pt window) and returns a **fully transparent image rather than
failing**. Five 1,179 × 10,800 PNGs of nothing were written and every `#expect` around them passed,
because this harness's only assertion was that a capture *happened* — which is not the same claim as
a capture having a screen in it. `isNotBlank` now refuses a capture that comes back as one flat
colour, so `sweep`/`pair` return false and the expectation fails. The AX5 shot sits at 2,700 pt,
under the limit. The states are `c01`–`c05` light and dark, and `c06` across the type ramp.

23 tests, 689 total.
### E146 — the ground under the tree, and the telephone number that stopped being automatic

The project owner asked for it twice, the second time from real use: *"When adding a tree need option
to mark it as a tree on private property vs city park vs street tree. and need to see this distinction
on tree's landing page too, along with other tree metadata"*, and then *"I don't see option to select
city or park or private yard when adding tree. still being built?"*.

**No migration and no new column.** E143 landed all of it — `community_trees.land_context` at
AppSchema **v11**, CHECK-pinned to four values plus NULL, `TreeDraft.landContext` on the existing
`addTree` requirement, `LandContext.inferred(from:)` in `Core`, and `Tree.landContext` returning a
`KnownLandContext` that names its own source. This round is the three screens that were left
deliberately unbuilt, plus the consequence E143 wrote down and handed forward (task #88).

**Three chips on the composer, and not a fourth phase.** `VisitAddTreeModel` already has two phases
that replace the whole screen — the pin map and the species catalogue — because each is a screen with
its own interaction. Three chips are not, and a separate step between the photograph and the CTA that
existed to hold three chips would be the second step this flow was told not to grow. The row is C4's
chip flow in `CypressChipFlow`, sitting between `placementRow` and `speciesRow`, and the order is the
argument: the pin decides the coordinate, this decides the ground under it, and only then does the
screen ask what the tree *is*. It uses C4's neutral selected/idle pair rather than screen 06's amber
one, because the amber means "this tree needs something" (§1.1) and a tree in a garden is not a worse
tree than a tree on a kerb.

**Optional — and E141's argument is not what decides it, which is worth saying plainly.** E141 made
the species optional because a mandatory 569-row picker collects *guessed* botany: somebody who cannot
name a tree has two ways forward and the cheaper is to pick something plausible. **That argument is
genuinely weaker here.** A person standing at a tree can nearly always see whether they are on a
pavement, in a park or in somebody's front garden; land context is not specialist knowledge the way
botany is. If "they might not know" were the only consideration, this field would be required.

Three other things decide it, and they are stronger than the one that does not apply:

1. **A required picker cannot remove the unanswered state, only slow the flow down.** Every community
   row written before v11 has `land_context` NULL, and a city row with neither `legal_status` nor
   `caretaker` infers nothing. `Tree.landContext` is an optional forever, every reader already handles
   nil, and a mandatory field buys the read side nothing while costing the field flow a tap.
2. **A mandatory answer is the screen-level version of the column default v11 refused.** E143 gave the
   column no DEFAULT because no tree written before v11 had ever been asked, and any default would be
   Cypress putting words in a contributor's mouth. A picker nobody can leave produces a value for every
   row whether or not anybody knew one — and it destroys the *not asked* / *street* distinction in the
   harmful direction, because a wrong `street` is what routes somebody to 311 about a tree 311 does not
   handle.
3. **BUILD-PLAN §6's endpoint requires a photo and nothing else**, and a screen stricter than its own
   boundary is a screen inventing a rule — E141's opening move, which does carry.

**Optional is not the same as hidden, and that is the difference from the species row.** Naming a
species costs a trip to a catalogue, so that row is a sentence and a link. This is three chips, always
visible, one tap to answer and no taps to skip. The question is asked as plainly as a required field
would ask it; only the refusal is free. Tapping the lit chip is the retraction — there is no second
screen to back out of, so `skipSpecies`'s distinction between *leaving* and *saying you are not sure*
has nothing here to attach to.

**Three of the four values are offered, and `.otherPublic` is the one held back.** E143 settled the
asymmetry — a permitted value no screen offers costs nothing, a forbidden value the data contains costs
a migration. The three that are offered are answers to *look down*: pavement, park, garden.
`Other public land` is a statement about which agency holds the parcel — a school's frontage strip, a
Port pier, a PUC right-of-way — and a contributor standing on it sees grass or concrete, not a
jurisdiction. Offering it would ask for a guess about a municipal fact, which is what optionality
exists here to avoid. The **profile still renders all four**, because 956 city rows carry the fourth;
display is not input, and `VisitAddTreeModel.offered` is only input. The model refuses a value outside
that list rather than merely omitting it from a list the view reads.

**On the profile this round built a `Where it stands` stat card, and the card did not survive the
merge. E145 had built the same fact as a sentence, in parallel, and both landed on one branch.** This
happened and is worth recording rather than tidying away: two rounds ran at the same time on the same
two-clause request from the project owner, neither saw the other's screen, and screen 03 briefly said
where the tree stands twice — once in the stat grid as `Private property · said by a contributor`, and
once in §9b as `A contributor said this tree stands on private property.` The sentence was kept.

The reason is the one E145 had already written down and this round had not been in a position to read.
A `StatCard`'s only place for a source is a badge; C12's badge vocabulary is `city record`; and
stamping `city record` on Cypress's own inference from `qLegalStatus` is the exact failure both rounds
existed to avoid. Adding badge cases would need a colour ramp ranking observation against inference,
and there is no such ranking. The card's best available shape was therefore a `·`-joined tail — four
words after a middle dot — and that is thinnest on the distinction that is the whole point: *Cypress
reads* and *A contributor said* are different verbs by different speakers, and the tail flattens them
into two interchangeable-looking suffixes. A sentence has room to name its speaker; that is
`speciesClaimNote`'s grammar one block up the same screen.

**What this round measured is kept, because it was never the losing half of the argument.** The
`·`-joined subtitle was the obvious home — `placementNote` and `speciesClaimNote` both live there — and
a community tree with a given name, a species and a moved pin already renders **five** elements:
`Monterey cypress · Hesperocyparis macrocarpa · community-added, unverified · species named by a
contributor · position placed by hand`. Three wrapped lines of italic serif before this adds anything,
and a sixth element would push the two notes that *are* about authorship into the middle of a list that
had stopped being one sentence. `theSubtitleCouldNotCarryIt` still asserts the count of five, so the
reason cannot rot. That finding rules the subtitle out; it never compared a card against a sentence,
because there was no sentence in front of it. Nothing else of this round moved: the v11 column, the
composer's three chips, `Tree.landContext`, and the whole 311 handoff below are untouched.

Dead with the card: `TreeProfilePresentation.landContextStat` and `landContextLabel`, and
`LandContextCopy.attributed`/`.source` — the two helpers that spelled a source in four words. They are
not kept against a future caller. `LandContextCopy` is now the composer's vocabulary only; the profile
has its own phrases, because *stands in the street or on the sidewalk* and *a tree on a street* are
different grammar and one function cannot serve both.

**Symmetric, and E138's rule does carry here where E141's did not.** All four values are said and none
is marked; `on a street` reads exactly as `on private property` does. E141 refused E138's symmetry
because the alternative to "a contributor named it" is *no species*, which has nothing to attribute.
A land context that exists always came from one of exactly two ways of knowing, so both arms name
their own speaker and marking one would rank it against the other. Nothing here is a door and nothing
needs to be — there is no update path on this field, which is the same reason the card would have been
inert.

---

**The consequence E143 handed forward, which is the part that could have shipped confidently wrong.**
`ReportPresentation.showsHazardBranch` was `selection.hazard != nil` and nothing else; `ReportModel`
held a `treeID` and never read the tree. Every tree got the same `Call 311 now`, and 311 is the city's
line for *city* trees. Unreachable only because nothing wrote the column — until this round.

**311 is San Francisco's front door for city-owned anything**, so the split is not four-way. A street
tree, a Rec/Park tree and an SFUSD yard tree all reach a crew through it, by queues the caller never
sees. It is one bit: `LandContext.isPublicLand`, in `Core`, which knows about ground and not about
telephone numbers.

**Only an observation may redirect a safety call. An inference may only inform.** This is the rule, and
it is `KnownLandContext` earning the reason E143 built it. **The seed says why, and the number was
measured here rather than assumed.** 11,856 city rows infer `.privateProperty` — and **11,153 of them,
94%, come from `caretaker == 'Private'` with no jurisdiction on file**: 8,126 whose `legal_status` reads
`Undocumented`, 2,964 `Significant Tree`, 48 `Landmark tree`, 15 blank. Only **703** come from San
Francisco recording `Private` or `Property Tree` as the legal status. E143 built the mapping so
jurisdiction leads precisely because leading on `caretaker` mislabels ~152,000 street trees; for these
11,153 rows there is no jurisdiction to lead and the caretaker decides alone. On the *Street* Tree List,
"no legal status on file and a private party waters it" describes a great many ordinary street trees
whose neighbour holds the hose.

So the harms are not symmetric and the design follows the asymmetry. Suppressing the call on a misread
street tree means somebody with a hanging limb over a pavement was told by an app that the city will
not help — a safety harm. Showing the call on a genuinely private tree means a wasted call and an
operator saying "not ours" — a friction harm. Three handoffs:

| `hazardHandoff` | when | what changes |
|---|---|---|
| `.city` | every public context, **and every unknown one** | nothing at all |
| `.cityWithInferredPrivateLand` | the *city's* record reads as private | `Call 311 now` untouched; one line under it says what was read |
| `.notCityMaintained` | a *contributor* said private property | panel says the city is not the party that fixes it; the call demotes to `Call 311 anyway` |

**Nothing is ever removed.** `Call 311` is reachable on all three branches, and a failed read falls back
to `nil`, which is `.city`, which is the screen that shipped — *the failure mode of the new code is the
old code*. Shipping this picker therefore cannot make a safety report harder for any tree in the app;
`theNumberIsNeverUnreachable` asserts it over every context and both sources. `showsHazardBranch` itself
is unchanged: a hazard is a hazard on any ground, and a branch that vanished for a private tree would
delete the private reminder along with the call.

**Naming the caretaker was considered and the seed refuses it.** `caretaker` is populated on 100% of
city rows, which is what makes the idea attractive — and it collapses on exactly the branch it would
serve: of the 11,856 rows that infer `.privateProperty`, **11,715 (98.8%) say `caretaker = 'Private'`**.
A panel reading "the city says the caretaker is Private" names nobody. `care_assistant` is worse — 112 of
the 703 jurisdiction-arm rows carry one and 80 of those say `FUF`, the volunteers who *planted* it, who
are not a hazard line. So the private panel says what Cypress cannot do instead: *"Cypress has no way to
reach whoever is"*. Leaving that sentence out would let a silence imply somebody is handling it.

`ReportModel.load` reads through `CypressAPI.treeProfile`, the requirement the tree page already calls —
no new protocol requirement, because E141's bar for adding one is that nothing existing answers the
question, and one does. `logHazardRedirect` still fires on the private branch: the event carries the
`treeID`, so *how often does a hazard land on a tree the city does not maintain* is a join rather than a
gap, and suppressing it would silently delete the rows that measure this round.

**Not built, stated plainly.** There is no way to *change* a land context after the save — no update
path on `community_trees.land_context`, and a city row's context is derived in `Core` from a read-only
database. The profile card is inert for that reason. Correcting it needs the same append-only assertion
chain E141 wanted for the species and could not have, and standing that up here would be inventing a
product on a two-clause request.

**Verified on the simulator by walking it**: map → `What tree is this?` → `None of these? Add this tree`
→ three chips visible where the owner said they were missing → `Private property` lit and the sentence
above it changing → photo from the library → the 10 m dedupe refusing twice, honestly, until the pin was
30 m east → save → the profile showing `WHERE IT STANDS · Private property · said by a contributor` →
`Report` → `Blocking a sightline` → the panel saying the city does not fix this one, with `Call 311
anyway` under it. A deep-linked city tree drew `Street or sidewalk · read from the city record` beside
its `SITE` and `SF #229291` cards, and its report drew `Call 311 now` unchanged.

**That walk is left as it was written, and two of its lines no longer describe the app.** The two card
readings above are what the screen showed on this branch before the merge with E145; the same two trees
now read `A contributor said this tree stands on private property.` and `Cypress reads the city's record
as a tree on a street.`, in §9b rather than in the stat grid, and the stat grid carries one card fewer.
Everything else the walk found — the chips, the dedupe, the save, all three report branches — is
unchanged, which is the point of leaving it. `LandContextShots` photographs the three report branches
and both profile arms; the two profile shots moved to the 1,500 pt window `cityRecordStates` already
used, because §9b is the last block on the screen and a phone-height capture of it stops above the
sentence.

30 tests on this round's own branch; **719 total on the merged branch**, which is E145's 689 plus
those 30. No test was deleted resolving the collision. Four moved from asserting a stat card to
asserting the sentence, keeping the intent each was written to protect — *the profile states where
the tree stands, and names who concluded it*, on both arms — and `absentWhenNothingIsKnown` gained
the assertion that no tree ever gets a `landContext` card again, so the duplicate cannot come back
without a test going red.
its `SITE` and `SF #229291` cards, and its report drew `Call 311 now` unchanged. Both appearances, and
the three report branches are photographed by `LandContextShots` because two of them cannot be reached
from the shipped seed by any deep link.
### E147 — a photograph on a tree you added belonged to nobody, and now you can take it back

Two tasks, and one problem underneath them. **#73** is the hole ERRATA E136 pinned when it built the
two doors of account deletion: `LocalAPI.addTree` writes a photograph with **no `visit_id`**, and
`community_trees` carries no owner column at all, so a photograph on a tree you added was
attributable to nobody and *neither door could reach it*. "Erase everything I contributed" left that
JPEG on the disk. **#78** is the project owner's ask, verbatim — *"Allow photo deletions for your own
photos"* — which cannot be built at all until "your own" is a question the schema can answer.

#### Part A — where the owner went, and why not where E136 said

`AppSchema` **v12** adds `photos.user_id` and `photos.device_id`.

E136 and `AccountDeletion.photoBytes` both wrote that closing this "needs an owner on
`community_trees`", and that sentence is departed from deliberately. An owner on the *tree* answers
the question only by **derivation** — "the photographs of a tree you added, that have no visit" — and
`photoBytes` is itself the standing warning about derived predicates here: widen one by a clause and
it starts deleting other people's work. That derivation also stops being true the moment anything
else writes a visitless photograph, and it cannot answer for the *ordinary* case at all — a
photograph taken on a visit to a city tree, which is most photographs in the app and which #78 has to
cover too. One column pair on the row being deleted answers all of it with one predicate.

The tree row still records no author, and that is a decision rather than an omission: a community
tree is a public object, no screen names its contributor (screen 03 says "a contributor"), and
neither door needs it — a community-added tree survives **both** doors today and still does, because
"everything I have added" has never meant the forest. Adding a personal-data column that nothing
reads would have been a privacy cost dressed as a privacy fix.

**The CHECK is `NOT (user_id IS NOT NULL AND device_id IS NOT NULL)` — at most one owner, not exactly
one — and this is the whole of E136's lesson about constraints.** `private_reminders` (v3) and
`favorites` (v5) are exactly-one-owner, and copying them here would have been the obvious move and a
migration already scheduled behind it. Those two tables are *deleted* with their account under both
doors, so an ownerless row is a state they never need. A photograph is the opposite: the default
door's entire promise is that the work stays and the name comes off, so an ownerless photograph is
not a hole in the rule, it is the rule's terminal state. Exactly-one-owner would have **forbidden
anonymisation**, leaving the leaving-door a choice between deleting the photograph (breaking its own
promise) and re-homing it onto the device (handing one person's picture to whoever picks the phone up
next) — which is precisely what v8 did to `photo_votes` and v9 had to be written to undo. Ask what a
constraint forbids, not only what it permits.

**The backfill has three jobs and states its assumption.** Every row in `main.photos` was written by
this installation (`beginPhotoUpload` and `addTree` are the only writers; nothing syncs anybody
else's down, which `LocalAPI.treeProfile` already relies on for `ownPhotoIDs`). So a photograph on a
visit takes the visit's owner; a visitless one takes this installation's identity, the signed-in
account first and `app_state.device_uuid` otherwise; anything left over stays ownerless, which the
CHECK permits. The second rule can over-attribute in one case — a photograph taken on this phone
before a *different* person signed in — and that is the same over-attribution `claimDevice` already
performs on every visit, which E136 recorded as the owner's to rule on. It is not a new hole.

`PhotoOwner` is the CHECK in Swift, and it has **three** cases where `FavoriteOwner` and
`ReminderOwner` have two. E89 kept those two apart on purpose — same shape, different invariants —
and this is the third of them for the same reason.

**Both doors now reach it.** The erasing door deletes by `photos.user_id`, tombstones included. The
anonymising door nulls it, which it never had to do before because there was no name on the row to
take off — `AccountDeletion`'s comment saying "the anonymizing door does not name `photos` once, and
that is correct rather than an omission" was true when it was written and is now the opposite, and it
says so. `claimDevice` adopts a device-owned photograph on the reminder's terms: the account gains it
and the device link drops in one statement, and the `user_id IS NULL` guard leaves an *anonymised*
photograph alone so it cannot be re-attributed to the next person to sign in.

**The test E136 planted did its job.** `anUnattributablePhotographSurvivesBothDoors` existed "so that
the gap is a failing assertion the day somebody adds that column and forgets this path". It failed on
the first run after v12 landed. It is now `theAddedTreesPhotographIsReachableByBothDoors` and asserts
the sentence the deletion copy always claimed — on the row *and* on the bytes.

#### Part B — deleting one photograph, and the five questions it asks

**1. It is a real delete, and it does not get E136's two doors.** The two doors exist because leaving
an account is a statement about *identity*, and the check-ins, measurements and votes left behind are
worth something to the forest whoever made them. None of that transfers. A single photograph is
deleted **because of what is in it** — a face, a licence plate, the inside of somebody's front
garden — and anonymising it addresses none of that: it would leave the picture on the tree and take
the name off the picture, answering a question nobody asked. That is E136's own test for a door worth
offering, applied and failed; E136 refuses to offer "keep my favourites" on the grounds that an
ownerless favourite is a decorative control, and "keep this photograph, unnamed" is the same control
facing the other way. What the design owes instead is **intent**: the trash control opens a
confirmation naming the consequence, the verb is on the button (`Delete photo`), and the button that
does nothing says what nothing means (`Keep it`). One tap destroys nothing.

**2. The hero cannot dangle, because nothing stores one.** `PhotoHero.choose` ranks the set it is
handed and already excludes `deletedAt != nil`; `ContributionStore.photos` never returns a tombstone.
So deleting the photograph a tree leads with promotes the next by the same rule that chose the first,
and deleting the last returns the tree to the cold profile it had before anybody photographed it.
That the votes go with it is load-bearing here: a tombstone left holding a positive tally would be a
deleted photograph winning a hero election.

**3. The last photograph of a community-added tree is deletable — allowed, named, and recorded.**
BUILD-PLAN §6 says "Community add: requires photo", so this is a genuine conflict and it is settled
in favour of the person. "Requires photo" is a rule about *making* a record — evidence at the point
of creation, and the anti-spam gate on a table any phone can write to — not an invariant the row must
satisfy forever. Refusing would mean the app declining to remove a photograph of somebody's window
because the tree's paperwork needs it, which subordinates the exact request this feature exists to
honour; it is also defeated by photographing the pavement first. So: the tree stays (deleting it
would remove a real tree from the map that other people may have visited), it stays `unverified`
because that word is already correct, and the stripped tombstone stays on the row so the record still
says a photograph was taken for it and withdrawn. The confirmation says so **before** the tap: *"It
is the only photo of a tree a contributor added. The tree stays on the map with no photo."*

**4. Soft delete, and the bytes go.** The row is tombstoned — `private_reminders.photo_id` and
`community_notes.photo_id` reference `photos(id)`, so a hard delete would take a *private reminder*
down with a photograph, and the surviving row is what carries the sentence in (3). But a tombstone
alone would be a lie about the request, so the files are removed from disk **first** on E136's
ruling — files-first fails as a row pointing at bytes that are gone, which is visible, retryable and
cosmetic; rows-first fails as a JPEG somebody asked to destroy, stranded and unreachable by every
query that could find it — and the row loses `storage_key`, `local_path`, `width`, `height` and its
fuzzed coordinate in the same statement that sets `deleted_at`. What survives is an id, a tree, a
shot type, a date and an owner: the same facts the visit beside it already carries, and none of them
a picture. `PhotoImageStore.forget` drops the decoded copy too — that cache never evicts, on the
sound argument that a photograph is immutable once written, and a deletion is the one event that
breaks the argument.

**5. Votes and outbox rows.** Every vote on the photograph is deleted, whoever cast it — they were
judgements about a thing that no longer exists, which is `AccountDeletion`'s argument for the same
deletion under the erasing door. v9's at-most-one-owner CHECK means an already-anonymised vote is
deleted by photo id like any other, with no owner arm to strand. And any queued mutation still
carrying the staged binary has it taken out of its `photo_paths` list, or the next drain would upload
a photograph that had been deleted; the mutation itself stays queued, because the person deleted a
picture and not the record of having stood in front of the tree.

**No outbox kind, and no sync, stated rather than skipped.** BUILD-PLAN §6 has `POST /photos/begin`
and nothing that unmakes a photograph. Queuing a `photo_delete` would need the `outbox.kind` CHECK
widened for a payload nothing can ever post — a durable row no drain could settle. So the deletion is
local and immediate, `CypressAPI.deletePhoto(id:)` is the shape `DELETE /photos/{id}` will take, and
the sync half is **OPEN** for whoever builds the service.

`deletePhoto` is a **protocol requirement**, not an extension member. E125 is the reason and it cost
this project a build where every photograph failed to load and every vote failed to save while every
test passed: an extension member has no witness-table entry, so an implementation's override is
unreachable through `any CypressAPI`, which is what every screen holds. `PhotoDeletionTests` erases a
`LocalAPI` to the protocol and asserts the file is gone, because every other test in that file holds
the concrete type and would pass against exactly that bug.

**Seeing and unmaking are two questions, so they are two sets.** `TreeProfile.ownPhotoIDs` stays what
it was — every row this device holds, because moderation does not stand between a contributor and
their own picture (E37) — and `deletablePhotoIDs` is the narrower one. They differ on exactly one
kind of row and it is the one that matters: a photograph anonymised by an account deletion is still
*shown*, because that is what the leaving door promised, and is nobody's to take back.

#### Verified on the simulator, and one thing that was only visible by looking

679 tests before, **700 after**, and each new assertion was made to fail on purpose first: removing
the `removeItem` call turns four deletion tests red on the *file*, deleting the migration's visitless
backfill turns the upgrade test red on the row E136 was written about, and restoring the old
visit-join predicate in both doors turns Part A's test red on both the row and the bytes.

Walked on the iPhone 16e over the `communityPhotos` and `photoHero` deep links: a contributor-added
tree with the one photograph that made it addable, deleted, leaving the cold profile — dashed well,
*No photos of this tree yet*, *Be the first to photograph this tree* — with the tree still on the map
and still reading "community-added, unverified". Then three photographs on a city tree: the hero
deleted, the `Hero` badge moved to the next row on screen 20, and screen 03 came back with the new
hero drawn and its pill down to `2 photos`. The container was read afterwards: `user_version` 12, the
JPEG gone from `Application Support/Cypress/Photos`, the row a tombstone with every locating column
NULL, and a *pre-existing* visitless photograph from an earlier build carrying a `device_id` — the
backfill, on a real database that had been written before v12 existed.

**The thing worth writing down** is a harness defect that looked exactly like an app defect. The
first version of the `communityPhotos` deep link pushed screen 03 and screen 20 in one go, so the
profile was covered before it had ever been on screen; it therefore got no appearance event, E127's
reload-on-reappear never armed, and coming back from the deletion drew a stale `1 photo · since 2026`
over a tree that no longer had one. A screenshot of that would have been filed as a bug in the app.
The real path — 03, tap the pill, delete, back — refreshes correctly, and the deep link now ends
where a person starts.

**What was not built.** The sync half, above. No delete affordance in the full-screen viewer or on
the hero: screen 20 is the only surface that shows a tree's photographs as a set with per-photograph
controls, and a delete on the hero would act on whichever photograph the rule happened to pick.
And an `addTree` photograph still never passes through `PhotoBinary.writeStrippingMetadata`, because
that path stages a file and never calls `uploadPhoto` — so a community add's EXIF is stripped by
nothing. That is a separate defect, found while reading this path, and it is not this entry's to fix.

### E148 — the coordinate the app fuzzed to 25 m, shipped exactly, in the photograph

E147's closing paragraph is this entry's brief, and it named the defect correctly:

> And an `addTree` photograph still never passes through `PhotoBinary.writeStrippingMetadata`, because
> that path stages a file and never calls `uploadPhoto` — so a community add's EXIF is stripped by
> nothing.

**What leaked, and through which path.** `VisitAddTreeModel.apply(imageData:)` stages the capture with
`VisitPhotoStaging.write`, which was `data.write(to:)` and nothing else, and `LocalAPI.addTree` then
inserted the photo row with `local_path` pointing at that staged file. There is no upload on that
path — `addTree` is the only mutation in the app that is not enqueued, and `photos.storage_key` stays
NULL for the life of the installation — so the one function that strips metadata was never reached,
not late but *never*. The file on disk was the camera's own container: `GPS.Latitude`,
`GPS.Longitude`, `GPS.TimeStamp`, `GPS.DateStamp`, `MakerApple`, `TIFF.Make`, `TIFF.Model`,
`TIFF.DateTime`, `Exif.DateTimeOriginal`, `Exif.LensModel`, `Exif.BodySerialNumber`. Read off a real
written file, before and after, with `CGImageSourceCopyPropertiesAtIndex`; all eleven are gone now and
`Orientation` and `TIFF.Orientation` are not.

**Why the fuzzing made this worse rather than better.** D11 snaps a photograph's public coordinate to
a 25 m grid, and E42 went further and stores no photo coordinate at all, on the argument that a second
independent record of where the contributor stood is the thing the fuzz exists to prevent. Every one
of those decisions is about a *column*. The file sat beside them carrying a latitude good to about
eleven centimetres. A mitigation is a claim about what the system will not reveal, and a system that
rounds a number in one place while shipping it unrounded in another has not made the number private,
it has made the rounding decorative — and it has done so in the way that misleads its own authors,
because the code that reads as careful is the code that was audited. The community add is the worst
place for it to have happened: a city tree's coordinate is already public in the city's inventory, but
a tree somebody adds is by definition one the city does not have, which in this app usually means a
garden. The photograph of a tree in a front yard carried the yard.

Two further things make the exposure real rather than notional. Application Support is **backed up**,
to iCloud and to any host the phone is plugged into, so the file leaves the device even though nothing
in the app publishes it. And `RemoteAPI` is a stub that will one day upload what these rows point at.

**The check-in path was not accused and was checked anyway.** It was *eventually* clean —
`uploadPhoto` strips on the way into the photo directory — but it staged the camera's bytes first and
served them from `local_path` for as long as the drain took, or failed for, and a queued visit on a
bus is a designed state that can last days. Enumerated in full, the ways image bytes reach storage are:
`VisitAddTreeModel` and `VisitCameraModel`, both through `VisitPhotoStaging.write`; `uploadPhoto`, on
the way from staging into the photo directory; `VisitGhostStore.record`, which re-encodes a downscaled
`UIImage` and so has never carried a sidecar; and `LocalAPI.debugSeedPhotos`/`debugAddCommunityTree`,
DEBUG seams over generated images. Every one of them strips or never had anything to strip.

**The strip moved to the shutter, because a screen cannot know whether its path ends in an upload.**
`PhotoBinary.write(_:strippingMetadataTo:)` is the new entry point: it takes `Data`, so there is no
step between "the camera handed us bytes" and "the bytes are clean on disk" for a caller to skip. It
**throws** when the bytes are not a container ImageIO can rewrite, and that is deliberately the
opposite of `uploadPhoto`'s documented fallback. `uploadPhoto` moves the original across rather than
lose it, because by then the staged file is the only copy and the row exists; at the shutter neither is
true, both capture screens already render "that photo could not be saved to this phone" with the CTA
disabled, and a contributor answers that by taking the photograph again. Writing bytes we could not
examine would be the leak with a comment on it.

`addTree` also repairs, rather than trusts, the path it is handed —
`PhotoBinary.stripMetadataInPlace` — because `photos.local_path` belongs to the `Data` layer and a
privacy invariant that lives only in the screen that happens to fill a field in is one the next screen
will not know about. It repairs instead of refusing: a refusal at that point is one the contributor
can only answer by retaking a photograph that would be refused identically, which is a flow with no
way out. On the shipping path it is one header read that finds nothing.

**What the test now guarantees, and how it was made to fail.** `PhotoMetadataTests` builds a JPEG that
genuinely carries a GPS fix, a maker note, camera identification and `Orientation = 6`, proves the
fixture carries them (without which every later assertion passes trivially), and then asserts on
**files, after paths**: the staged file, the file `photos.local_path` points at after a real
`VisitAddTreeModel.useLibraryImage` → `add()`, the bytes `photoData` serves, and the file in the photo
directory after a real outbox drain. Every assertion is a named key read back with
`CGImageSourceCopyPropertiesAtIndex`, and the failure message prints every key the file does contain.
Nothing spies on `writeStrippingMetadata` being called: a test on the call site would have been green
against this bug for the whole of its life, which is not a hypothetical about the failure mode, it is
the failure mode.

Reverting the strip fails six of the seven tests with 57 issues, naming the eleven keys above on
`the file photos.local_path points at`. And **E142 is asserted in the same breath as every GPS
assertion**: setting `needsOrientationRestored` to `false` — deleting the second pass whose only job is
to put `kCGImagePropertyOrientation` back — fails four tests with `orientation is nil and not 6`. That
pass had **no test at all** before this entry. It could have been deleted as dead weight by anybody
tidying the file, and the whole suite would have stayed green while every portrait photograph in the
app went back on its side.

**Two fixtures had to become photographs.** `CommunityAddTests` and `VisitPreviews` staged
`Data([0xFF, 0xD8, 0xFF, 0xD9])` — two markers, chosen when staging only had to produce a path on
disk. Staging refuses that now, which is the behaviour under test, so both supply a real 1×1 JPEG.

**A misdiagnosis, recorded because it is ARCHITECTURE §7's own warning and it was walked into anyway.**
The full suite came back red four times over the course of this work, always in
`SpeciesClaimTests.theClaimIsDrawn`, always `SQLiteError(6922): disk I/O error` on a `SELECT` against
the attached seed, always preceded by a storm of `invalidated open fd` from four threads at once, and
never reproducible when that suite was run alone. 6922 is `SQLITE_IOERR_VNODE`. It was attributed to
memory pressure — this suite's fixtures were 3024×4032, two 48 MB bitmaps in a host that has the 103 MB
seed attached many times over — and the fixtures were duly shrunk, and two green runs followed, and the
diagnosis looked confirmed.

It was wrong. `ps` showed another agent running `xcodebuild test-without-building` against the **same
iPhone 16 Pro**, with no `-only-testing`, so its install and its UI tests were landing on the device in
the middle of these runs. That is precisely the failure ARCHITECTURE §7 describes — "a concurrent agent
installing its build mid-run can crash the host out from under your tests", reported as "whichever suite
was running", and "the slowest suite is the usual casualty" — and `theClaimIsDrawn` is the slowest test
in the suite, at twelve seconds of off-screen SwiftUI rendering over a seeded store. The two green runs
were quiet windows, not evidence for the theory they appeared to confirm.

What makes it worth an entry rather than a shrug: the memory theory was *plausible, cheap to act on, and
produced a passing suite*, which is everything a wrong diagnosis needs to become permanent. The check
that settled it costs one command and was not run for an hour. **Before believing anything about a red
suite, run `ps aux | grep xcodebuild`.** The fixtures stayed small, because small fixtures are right on
their own merits, but not for the reason they were shrunk.

The proving run was moved to its own simulator — a private device as well as a private DerivedData —
which is what §7's "boot your own device" buys once you notice that the sentence about it only ruling
out *looking* was written about sharing one device, not about having two.

### E149 — thirty green dots on one street, and the 569-colour legend that is not a design

Task **#80**, the project owner's words: *"Add ability to color different species differently so it's
easy to tell which trees are same on a local zoom."* One sentence, and the first thing to do with it
is refuse the literal reading.

**There are 569 species in the seed.** A colour per species is a colour wheel, not an encoding — the
fortieth hue and the forty-first are the same hue to anybody's eye, and a reader who *thinks* they can
tell two pins apart when they cannot has been handed a wrong answer rather than no answer. So the
question the map answers is the one the owner actually asked, which is narrower than the words: *which
of these are the same tree?* That is a question about **matching**, and matching needs colours unique
among the ones on screen right now. It does not need a colour that means *Platanus* forever.

#### What the encoding is

Four **slots** (`MapSpeciesSlot`), handed to the four species with the most drawn pins in the current
viewport (`MapSpeciesPalette`). Everything else keeps the pin it has today.

Counted against the shipped seed over ten neighbourhoods, using the pins as `TreeQueries` actually
thins them (one per 44 pt cell, `MapModel.markerCellPoints`) rather than the trees in the box:

```
zoom 19 · 0–75 pins/screen  ·  6–31 species  ·  top 4 cover 32–90 % of pins
zoom 18 · 14–133 pins       · 10–53 species  ·  top 4 cover 29–76 %
zoom 17 · 93–222 pins       · 27–64 species  ·  top 4 cover 27–64 %
```

**There is no zoom at which a screenful of San Francisco is four species**, so the residual class is
not an edge case — it is often most of the screen, and what it draws is the load-bearing decision.
It draws **today's pin, unchanged**: Canopy green, no glyph. And Canopy green is deliberately *not*
one of the four slot colours, which is what makes the residual honest rather than a fifth group.
Green says "a street tree"; it has never said "the same tree as that one" and it still does not.
`ContrastTests.slotsStayOutOfTheReservedFills` is that sentence as an assertion.

Three further rules, each of which is a decision:

- **A species with one pin in view gets no slot.** A singleton has nothing to be the same as, so a
  slot spent on it is spent on a question nobody asked. At zoom 19 in the Excelsior the tail is almost
  entirely singletons, and this is the difference between four useful colours and one.
- **Only a pin that would already draw as `.cityTree` can take a colour**, and the others are not
  even *counted*. Amber is "reserved solely for 'this tree needs something'" (SCREENS.md §1.1); the
  dashed ring is the community layer, which "never renders as part of the official city inventory
  until verified" (DECISIONS §3.16); grey and hollow mean there is no living tree. A species whose
  visible pins are nine memorials and two live trees is not two-thirds of a street's canopy.
- **Slots are sticky.** A palette recomputed from scratch permutes on every fetch: nudge the camera
  one block west, the third and fourth species swap counts, and every pin changes colour while the
  reader watches. That is E130's cluster badges re-keying on every pan, in another costume, and the
  answer has the same shape — a species that already holds a slot keeps it while it still qualifies,
  and newcomers take what is free. A reader who has learnt "the purple ones are the Victorian Box"
  keeps that for the length of a walk. `slotsAreSticky` and `slotsAreReusedWhenVacated` pin it.

#### A cluster badge is not given a species colour, and that is a refusal rather than an omission

A cluster is a **count**, produced by an absolute SQL grid that knows nothing about species (E130).
Nine trees under one badge are usually nine different trees, so any colour on that badge would assert
homogeneity the data does not support — and the honest colour for "mixed" is the one it already has.
`TreeQueries.cellSize` is untouched, MapKit's `clusteringIdentifier` is still not used, and a
clustered viewport draws no legend at all because there are no pins to rank.

#### The second channel, which was owed regardless

**RULINGS R8** settled this for C23 in a sentence that generalises: "a chart that distinguishes its
lines only by hue is unreadable to a colour-blind reader at *any* contrast ratio, so the redundant
encoding is owed regardless". A map is a data encoding on the same terms. So each slot carries a
**glyph** in the ring colour inside the pin — a dot, a triangle, a cross, a standing bar — chosen to
differ in silhouette rather than in detail, and the legend chip shows the same mark beside the name.
A reader who sees no hue at all still sees four different marks.

This is not R6's forbidden move. R6 refused a glyph that *replaced a word* on screen 17's queue rows.
Nothing on an 18 pt map pin has ever been a word, and the word still exists in the two places a word
belongs: `MapSpeciesLegend` names the species, and `MapPinKind.accessibilityLabel(for:palette:)`
speaks it — `City tree, Victorian Box` from every Victorian Box on the block, which answers the
owner's question better than either drawn channel does.

**The standing bar is vertical**, because a memorial is a grey pin with a *horizontal* bar across it.
Two bars at right angles cannot be read for each other; two parallel ones could. No slot uses a
hollow inner ring, because a hollow pin is a vacant planting site (R7), and none uses a check,
because a check is screen 18's visited route pin.

#### The palette, and the five constraints it had to clear at once

Four `derived` tokens — `pinSpeciesA`…`D`. **They are the only tokens in `CypressColor` whose light
half is ours too**; every other `derived` value is a documented light hex with a computed dark
counterpart, and SCREENS.md draws no species colouring at all. `derived` is still the right claim,
because it is the constructor that puts a value in `reviewTokens`, and `TokenGallery` renders those
first — four swatches on one screen for a designer to answer, rather than a palette to audit.

Chosen by search in OKLCh (`Tools/map_species_palette.py`), against:

1. **≥ 3:1 on every ground screen 01 draws**, in both appearances — map paper, map grid, street band,
   park block, park inset ring, ocean, beach. Fifty-six measurements, all in
   `ContrastTests.speciesPinsInLight`/`InDark`. **The binding grounds are the water in light (4.81,
   3.81) and the park inset ring in dark (3.15)**, with the park block next in both; the paper
   everybody would have measured against is the easiest of the seven. The suite previously measured
   the city pin and the amber pin against the paper and stopped there, which is how a palette passes
   on paper and vanishes over Golden Gate Park.
2. **≥ 0.10 OKLab ΔE from each other**, five times the ~0.02 just-noticeable difference. Measured as
   ΔE and not as WCAG contrast: contrast is a luminance ratio, so two colours of the same lightness
   and opposite hue read 1.0:1, which is the right tool for "can I see this on that" and the wrong
   one for "can I tell these two apart".
3. **≥ 0.099 ΔE from every mark whose hue already means something** — Canopy, Signal Amber, the GPS
   dot, the cluster badge, a memorial's grey. No slot sits in the amber arc (hue 20–115°), the Canopy
   arc (125–200°) or the GPS arc (232–272°) at all. **Removing those three arcs from the wheel is
   also why there are four slots and not six**: what is left will not hold six hues this far apart.
4. **The ring and the glyph read on every fill** — `pinRingStroke` is 5.4:1 or better on all eight.
5. Lightness descends A→D in light and ascends in dark, so the four are separated in luminance as well
   as in hue and no pair collapses for a reader with a severe deficiency. This is **not** a ranking
   channel — slots are sticky, so `a` is the commonest species only until the reader pans.

The tightest separation in the whole set is slot B in light against the **cluster badge**, ΔE 0.099 —
and a badge is a filled 28 pt circle carrying a number, which is not a thing a reader confuses with an
18 pt dot at any hue. The tightest against another *pin* is slot B after dark against the GPS dot,
ΔE 0.110, separated by three further channels: the dot carries no glyph, it is the only mark with an
8 pt halo, and it is drawn *under* every tree (`zPriority = .min`). Both numbers come off
`Tools/map_species_palette.py`, which prints them and re-derives all eight hexes from their (hue, L).

#### The number this whole design exists to keep small

`MapPinImage` caches one bitmap per `MapPin.Kind` per appearance, and "once per kind" is what makes a
screenful of 280 markers a handful of images. **Keying that cache on a species would make it 1,138
rasterised SwiftUI views against a 256-entry ceiling** — not a slower version of the MapKit swap, but
the defect the swap was made to fix, reintroduced, with the cache thrashing its own `removeAll`
mid-pan.

So `cityTreeSpecies` takes a **slot**, and the fixed pin vocabulary goes from 8 kinds to 12: **16
cached bitmaps before, 24 after**, in both appearances, and the number does not move with the 569
species, with the pin count, or with the length of the session. Cluster badges are still one per
distinct count. `theBitmapCountIsBounded` asserts the 24 rather than the argument.

It is a **separate enum case rather than an associated value on `.cityTree`**, which is why this
change touches no existing `== .cityTree` anywhere in the app or the suite, and why "no slot" is still
spellable as the pin that was already there.

#### Measured, on a booted simulator, with the probe armed

Twice, on two different machine states, and the pair is worth more than either half.

**Quiet machine, iPhone 16 Pro, the Mission, `CYPRESS_MAP_PROBE=1`**, camera settled, nobody touching
the glass, the same walk on the build before this change and the build after:

```
                                   fps   worst frame   gps/body/fetch per sec
before · z16, 245 markers        60.0        17 ms            0 / 0 / 0
before · z18, 218 markers        60.0        17 ms            0 / 0 / 0
after  · z16, 197 markers        60.0        17 ms            0 / 0 / 0
after  · z18, 194 markers        60.0        17 ms            0 / 0 / 0   ← all four slots in use
after  · z20,  13 markers        60.0        17 ms            0 / 0 / 0
after  · z14,  91 badges         60.0        17 ms            0 / 0 / 0
after  · z12,  27 badges         60.0        17 ms            0 / 0 / 0
```

**Loaded machine, iPhone 16 Pro Max, Hayes Valley** (37.77462,-122.42244 — 199 alive city trees and 21
species inside one opening viewport), `cc01e32` and this branch installed onto the same booted device
back to back:

```
                                        fps   worst frame   gps/body/fetch per sec
before (cc01e32) · z18, 139 markers      49        35 ms            0 / 0 / 0
before (cc01e32) · z15,  49 badges       45        40 ms            0 / 0 / 0
after            · z18, 169 markers      53        37 ms            0 / 0 / 0
after            · z18, 292 markers      53        33 ms            0 / 0 / 0   ← all four slots in use
after            · z21,   3 markers      45        52 ms            0 / 0 / 0
```

The second table is not a contradiction of the first and is not a measurement of this change either:
that machine was carrying six booted simulators, a second agent's `xcodebuild`, and a load average of
17–22, and the overlay read 45–55 fps with a 33–52 ms worst frame on *every* combination of build, zoom
and marker count — including three markers, and including a build that predates this change. It is
recorded because it is the state a verification run is likely to be attempted in, and because reading
an absolute frame rate off it is how a load average gets reported as a regression.

**The column that discriminates in both tables is the last one.** `body` and `fetch` are 0 per second at
rest on every row of both, which is the property the design rests on: the palette is computed once per
*fetch* rather than per pass, and `recomputeSpeciesPalette` drops a palette equal to the one it already
had rather than republishing observable state, so a pan across a block re-derives the palette it has and
tells nobody. On the loaded machine the after build at **292 markers with all four slots in use** is not
worse than `cc01e32` at 139.

#### The label refresh had to be gated, and a nudge test is what said so

The spoken channel needs one thing the drawn channels do not: a **second pass**. `MapModel` ranks the
palette from the pins it has, then reads the four species' names asynchronously, so the palette a pin
is born under has no name in it and the label it stores is the plain `City tree`. A name arriving
changes no pin's *kind*, so `Coordinator.sync`'s kind comparison correctly leaves every annotation
where it is — which means a label stored once at init is the label that pin keeps forever, and every
coloured pin in the running app is in exactly that position. The third channel named nothing, ever,
while `voiceOverNamesTheSpecies` passed, because that test asks `MapPinKind` directly and never goes
through the layer.

Refreshing it in `sync` fixes that and costs something, and the first version of the fix did not notice
what: a string built per pin per pass, against a screen that runs **240 body passes a second at rest**
(E139) — ~70,000 string constructions a second on a 292-pin screenful, in the one file whose first
promise is that an update whose pins are the same pins does no work at all.

**What noticed was `DeepLinkVoiceOverTests.testThePinSaysWhenItHasGoneAsFarAsItGoes`** — a test about
screen 16's *nudge control*, which has nothing to do with species colours. Fifteen 5 m nudges landed
the pin at 74 m instead of 75, three runs out of three, because that screen reads the pin's position
off the settled MapKit camera and the camera settles differently when the update pass costs more. It
is green on `cc01e32` and green two runs out of two once the refresh is gated on the palette having
actually moved (`Coordinator.appliedPalette`). On the two other screens that draw this basemap the
palette is always `.empty`, so the loop does not run there at all and their passes are byte-identical
to what they were.

The lesson is the one §7 keeps making in a different costume: the test that catches a performance
regression is rarely a test about performance, and "unrelated suite went red" is a thing to explain
rather than a thing to re-run.

#### What was looked at, because tests cannot say whether it reads

Twelve screenshots off the booted device, both appearances, every one checked for an opaque alpha
channel and a colour count (9,069–37,418 distinct colours) rather than trusted because a file was
written — the shot harness has returned fully transparent PNGs while every test passed. Compared by
eye and never by hash or `cmp`: the probe's own text ticks once a second, so a byte comparison always
reports "different".

The one that is the whole argument for the task is `11-light-localzoom.png` — **292 markers over the
Oak/Page/Lily grid**, in which Brisbane Box reads as plum dots down Gough St, Sycamore: London Plane as
lagoon triangles along the south side of Page, Swamp Myrtle as iris crosses on Oak, and Maidenhair Tree
as cherry bars in a run of eight, over a residual green that claims nothing. "Which of these are the
same?" is answerable at a glance, and before the change every one of those 292 dots was the same green.

**And the crops were converted to greyscale and looked at again**, in both appearances, which is the
check the glyph exists to pass: with every hue removed, the dot, the triangle, the cross and the
standing bar are still four different marks — and the residual pin, which carries no mark at all, is
still a fifth thing. The legend chips key them with the same four marks.

The legend's empty and near-empty states were seen rather than reasoned about: at z21 with three
markers it drew a single chip, and at z15 the map is badges and it drew nothing.

#### What was not built

**No legend for the residual class.** `MapSpeciesLegend` names the four coloured species and says
nothing about the rest, because there is nothing true and short to say — "and 27 others" is a number
that changes with every pan and answers no question. The honest surface for "what is this green one"
is the one that already exists: tap it.

**Genus was weighed and rejected.** It would have collapsed 569 species to ~130 and bought about a
tenth of a slot's worth of coverage (11 genera against 12 species in a Mission zoom-19 screenful),
while making "same colour" mean "same genus" — so two *Prunus* species would share a hue and a reader
would read "same tree" and be wrong. The whole point of the constraint is that the map must not be
able to say something false.

**The other two basemaps are left alone.** `MapKitBasemap` takes the palette with a default of
nothing, so 16's pin adjust and the pin-set map draw what they drew: both are about *one* tree and its
neighbours rather than about the mix of species on a street, and four hues there would be answering a
question nobody asked.

### E150 — "this one" was a pin two and a half points wider than its thirty neighbours

Task **#89**. A tapped pin was distinguished by `MapLayout.selectedPinScale` and nothing else, and
that constant's own comment says why it was defensible: **NOT SPECIFIED** in SCREENS.md, so it was
"deliberately the smallest change that still answers the tap".

The smallest change stopped being enough when the map started drawing a street. 1.25 × 18 pt is
22.5 pt, and screen 01 draws up to 288 pins on one screenful (`MapModel.markerCellPoints`) — so the
reader was being asked to find the *marginally larger* dot among thirty identical ones. The card at
the bottom of the screen names the tree and the map does not say which dot it is talking about, which
is the whole of the defect: a tap that is answered somewhere the reader cannot connect to what they
touched.

#### The reticle

Two concentric rings **outside** the pin, at 1.7× and 2.0× its diameter, in `textInk` and
`pinRingStroke`. The scale stays, because it is what makes the pin and the card read as one selection.

Three properties make it unconfusable with the species colours above, and they are properties by
construction rather than by taste:

1. **It is achromatic.** The two ring colours carry OKLCh chroma ≤ 0.026 (`textInk` in light, the
   highest of the four values); every species slot carries ≥ 0.080. No overlap, no near miss, and
   `MapSpeciesColourTests.theReticleCannotBeASpeciesColour` asserts the gap rather than describing it.
   The reader for whom four hues are the *hardest* thing on the map finds this the easiest.
2. **It is outside the pin's own footprint**, in a band where no pin of any kind draws fill. A species
   colour is always a fill *inside* a pin. It is also inside the 44 pt tap target, so the mark never
   claims ground the finger does not own.
3. **It is a ring rather than a fill**, and there is only ever one of them on the map.

**Two rings and not one, because the ground is a live MapKit basemap.** A white ring disappears on the
paper and an ink one disappears over a park polygon after dark, so the mark carries both ends of the
ramp and one of them always reads — the crossed-over trick C19's FAB glyph already uses. It is
redrawn on a scheme flip, because a `CGColor` in a `CALayer` is the one thing on a marker view that
cannot resolve itself.

**The selected marker also comes to the front** (`zPriority = .max`). Two pins 20 pt apart overlap
across 36 pt of reticle, and a reticle half-covered by the neighbour it is distinguishing itself from
is not a mark.

#### It costs no bitmaps, which is why it is layers

`MapPinImage` is keyed on `MapPin.Kind`, so a *selected* variant of every kind would double the cache
the species slots just spent their whole design keeping countable — 24 entries to 48, for a state that is true of one
marker at a time. The rings are `CALayer`s on the one selected view, the way the amber pulse already
is. `selectionIsFreeOfTheCache` asserts that selecting, deselecting and reselecting rasterises
nothing.

#### Looked at

Screenshotted selected in both appearances at z18 with 169 markers, on a **residual green** pin — which
is the case that matters, since the pin a reader taps is more often than not one of the many rather
than one of the four. In light the outer ink ring is the only black mark on the map and the eye lands
on it; the inner white ring is nearly invisible against the paper, which is exactly the failure the
second ring exists to cover, and after dark the two swap roles — the pale outer ring carries it and the
near-black inner one is the faint one. One of the two always reads, which was the claim.

The card below named `Kwanzan Flowering Cherry · Prunus serrulata 'Kwanzan' · 50 m E`, so the tap and
the card and the mark are one selection.

One thing the drawing got wrong and the screenshot did not catch, which is why there is now a test for
it: the reticle's `CALayer`s are children of a view carrying `selectedPinScale`, so a ring built at
2.0 × 18 pt was landing on the glass at **45 pt** — outside the 44 pt tap target the test believed it
had checked, because the test restated the constant instead of measuring the layer times the
transform. The sizes are divided by the scale now.

### E151 — The way out of the camera was however deep you happened to be, and one of the ways out went nowhere

The report is #76: "need a back to map button/functionality after taking photo/checking in". It reads
like a missing button and it is not. Every route out of the capture flow existed; none of them was a
*destination*.

**The routes, and what each of them actually did.** `VisitFlowView` hands its container four exits and
the container is `RootView`'s one `fullScreenCover`. Three of the four were relative:

- the shortlist's back chevron and the camera's ✕ → `onExit` → `router.sheet = nil`;
- screen 18's "Done for today" → **also `onExit`**, the same closure, the same one line;
- screen 18's "See it on the tree's timeline" → `sheet = nil` then `push(.treeProfile(id))`.

`sheet = nil` dismisses the cover onto whatever the tab root plus `router.path` happened to be when the
flow opened. From the map's FAB that is the map, and the whole thing looks correct. From **screen 03's
own photo CTA** — the app's primary call to action on a tree page, and the entrance E127 built — the
stack is `[.treeProfile(id)]`, so finishing a contribution lands on the profile of the tree you have
just photographed, which is the one screen a person who is *done* has no further business on. Every
screen in this app hides the system navigation bar (`toolbar(.hidden, for: .navigationBar)`, twelve
files), so there is no `‹ Back`; the only way to the map from there is a 40 pt translucent circle
drawn on top of the hero photograph, and the bottom tab bar — the thing that names the map — is drawn
only by the four tab roots and so is not on screen at all.

**And the third route made "back" appear to be broken.** From the profile entrance,
`push(.treeProfile(id))` pushed the profile of the tree that was *already on top of the stack*. Two
identical screens, so the first Back looked like nothing happening, and only the second reached the
map. A control that appears not to work is a stronger reason to report "there is no way back" than a
control that is missing.

**A fourth route did nothing at all, and this one is a plain defect.** `AppRouter` keeps **one** `path`
for all four tabs. Screen 18's "Route done · see your grove" was `sheet = nil; router.tab = .grove`,
which swaps the tab root *underneath* whatever is pushed. From the map entrance the stack is empty and
the grove appears. From the profile entrance the stack is `[.treeProfile]`, so the grove arrived behind
the tree profile and the only evidence anything had happened was that Back now went somewhere new.
Nothing in the app rendered wrong; the screen the person asked for was simply not on top.

**The fix is a destination, not a button.** `AppRouter.goToTab(_:)` clears `sheet`, clears `path`, then
sets `tab` — all three, in that order — and `goToMap()` is that for the map. `VisitFlowView` grew
`onDone`, separate from `onExit`, because *abandoning* and *finishing* mean different things and the
container cannot act on the difference unless it can see it: abandoning is relative (nothing was
contributed, so go back where you were) and finishing is absolute. `onDone` defaults to `onExit`, so a
caller with no opinion behaves exactly as before rather than silently doing nothing.

Worth recording: **`popToRoot()` had been sitting in `AppRouter` with no caller anywhere in the app.**
The operation that means "back to the map" existed and nothing had ever asked for it. That is not the
same defect as a missing operation and it is a more interesting one — the router was complete and the
flow simply never made a decision about where finishing goes.

`push(_:unlessAlreadyOnTop:)` is the timeline link's half. The plain `push` is unchanged, because
everything else in the app relies on stacking two of a kind being allowed.

### #87, the directed hypothesis: refuted, and then closed anyway

The hypothesis handed to this work was "no sheet or cover receives the environment the NavigationStack
carries". As a statement about the code it is **false, and has been since E142**: the app has exactly
one `fullScreenCover`, and its content was explicitly given both values the stack carries —
`.environment(router)` and `.environment(photoImages)` — which is precisely what E142 was recorded to
fix. Nor could it have caused #76: nothing in `Features/Visit` reads `AppRouter` from the environment
at all (`git grep "Environment(AppRouter.self)"` lists thirteen files and none of them is in that
folder). The visit flow is driven entirely by closures handed down from the composition root, so the
stranding was a wiring decision and not a missing environment value.

What #87 *did* still describe correctly was a hazard, and it is worth closing rather than arguing
with. E142 fixed the two values that were missing by writing them out a second time at the cover, which
left the list of shared environment values existing in two places with nothing making them agree. A
third shared value added to the `NavigationStack` would have reached every pushed destination and
silently reached no sheet — the same defect, the same silence, one value later. Those two sites are now
one `SharedEnvironment` modifier applied to both, so adding to the list reaches both by construction.

**Verdict: #87 is resolved, but not by the fix #76 needed.** Its literal claim was already false; its
underlying risk is now structurally impossible rather than merely currently absent.

### How each of these was made to fail

`goToMapIsAbsolute` and `goToTabClearsTheStack` are the ones that matter, because both assert the field
that looks optional. Deleting `path.removeAll()` from `goToTab` fails both with "the map is behind 2
pushed screens" / "the grove arrived underneath 1 pushed screens"; deleting `sheet = nil` fails both
with "the visit flow's cover is still up". Reverting `push(_:unlessAlreadyOnTop:)` to an unconditional
append fails `theTimelineLinkDoesNotDuplicateTheProfile` with "a second identical profile was pushed".
And the flows were walked on a running simulator, because no unit test can say whether a person can get
out of a screen — screenshots and the route are in the branch's report.

### E152 — Three photographs of one tree, and the two the third one used to destroy

The report is #81: "should be possible to take a full and then trunk and then leaf photo from one
camera screen without having to leave and come back". The screen already drew the three chips. What it
did not have was three photographs — the chips were three ways of *labelling* one.

**The data model was narrow in exactly one place.** `OutboxItem.photos` has been `[OutboxPhoto]` since
it was written and `outbox.enqueue(_:photos:)` has always taken a list; `VisitDraft.photo` was a single
`OutboxPhoto?`. The draft was the narrow section of a pipe that was wide at both ends, so pressing the
shutter under a second chip replaced the photograph that was there.

**The filename is where this became silent data loss.** `VisitPhotoStaging.url(for:)` was
`"\(visitID.uuidString).jpg"` under a comment that read "one file per visit id, so a re-save of the
same draft overwrites rather than accumulating" — true, and the bug. Three captures in one session were
three writes to **one path**, and `PhotoBinary.write` removes the destination before moving the new
bytes in. So the third photograph deleted the first two from disk. Nothing in the app reads a staged
file between the shutter and the drain, so there was no moment at which the loss could surface: no
error, no missing thumbnail, nothing. A contributor who photographed a tree three ways kept the leaf.

The name is now `"\(visitID.uuidString)-\(shotType.rawValue).jpg"` — the visit **and the framing**.
`ShotType.rawValue` rather than a counter, an index or a fresh UUID, because the framing is the thing
that actually distinguishes these files: a visit holds at most one photograph per framing, which is
what makes a *retake* of the trunk overwrite the trunk and nothing else. A counter would make every
retake a new file and leave orphans in a directory iCloud backs up.

**Everything that reads that path was checked rather than assumed.** `photos.local_path` takes one row
per photograph, each with its own path (`beginPhotoUpload`). `OutboxStore.removePhoto(atPath:from:)`
keys on the path, so draining one of the three does not take its siblings out of the row — the
invariant its own comment states, "a row cannot stage the same file twice", is *more* true now, not
less. `LocalAPI.uploadPhoto` moves each staged file to `<photoID>.jpg` under a fresh photo id, so three
staged files land as three stored files with three distinct `storage_key`s. Had the three paths still
collided, the second upload would have found its source already moved and failed `notFound` — which is
why `storageKey` is the load-bearing assertion in the round-trip test rather than a nicety.

**E148 is not routed around, and the new path carries the same coverage.** `VisitPhotoStaging.write`
took a visit id and now takes a visit id and a framing; it is still the one funnel, it still calls
`PhotoBinary.write(_:strippingMetadataTo:)`, and three shots in one session are three calls to it.
`PhotoMetadataTests` grew two tests that assert on **files, after paths**, never on which function was
called: `stagingKeepsThreeFramingsApartAndStripsEachOne` writes all three framings of one visit and
then, with all three on disk at once, checks that there are three distinct paths, that each file still
measures the photograph it was written from, and that each one has lost its GPS and kept its
orientation. The "all three at once" ordering is the whole design of it — every pre-existing assertion
in that file looks at the one file it was just handed, so all of them would have passed against a
collision. `stagingRetakeReplacesOnlyItsOwnFraming` is the other half: the retake lands on the same
path (no orphan) and the full-tree photograph beside it is untouched.

**Two of three is a complete contribution.** Nothing in BUILD-PLAN or PROTOTYPE-FLOW asks for a set;
the only stated gate on this screen is §1.6.1's "Log visit is disabled until snapped". So the gate
stayed at *any* photograph rather than becoming *all three*, and a contributor who does not find a leaf
worth photographing saves two. Refusing would have thrown away the two they did take, and there is no
draft state in this app, so there was never a third option to nag from: what was taken is what is
queued. A retake discards **only its own framing** — re-shooting the trunk has never meant "and throw
the full tree away" — and its replacement writes to the trunk's own path, which is the invariant the
filename buys.

**Three surfaces on screen 04 are NOT SPECIFIED and are marked as such.** SCREENS 04 draws the chips
with no captured state, the CTA reading `Log visit` and nothing else, and no line about what a session
could still hold; when it was drawn a visit held one photograph. Invented, under the project owner's
own request for this feature: a tick on a photographed chip (`CypressCheckmark`, the same shape screen
18's success circle and screen 05's selected row already draw, sized off 05's check circle), a CTA that
counts what it is about to save (`Log visit · 3 photos` — a count of the thing on screen, not of the
person, which is the line D1 draws), and one muted line naming the framings still open. The chips also
carry the fact in their accessibility labels — "Trunk, photographed" — because a mark is not read out
and the chip's own label no longer carries its whole meaning.

**#45's overflow, under the pressure a third control adds — and the two things that were wrong about
how it was checked.** The chip row moved from an `HStack` to a `CypressChipFlow`, on the stated grounds
that three chips wearing ticks at AX5 are wider than the phone and the third would go off the right
edge, the way #45's tray once did. Both halves of that turned out to be wrong, and only measuring found
it.

*The test could not fail.* `theTrayStaysOnTheScreenWithThreeCaptures` hosted the whole of screen 04 at
AX5 and asserted the result measured no wider than 393 pt. The chip row is an `.overlay` on the
viewfinder and **an overlay never enlarges what it is over**, so the row's width was never in the
number being asserted on. Putting the row back to an `HStack` left the test green. This is the same
class of thing E148 recorded — a test that agrees with the code rather than with the world — and it was
found the same way, by breaking the code on purpose and watching nothing happen.

*And then the defect was not the defect.* Once the row was extracted into `VisitShotTypeChips` and
hosted on its own, an `HStack` measured **326 pt in the 361 pt this row is given**. It fits. SwiftUI
compresses children rather than overflowing a proposal. What it costs is the chips themselves: each
squeezed from its natural 158 pt to about 103, its label wrapping into a column of stacked syllables —
which is exactly what the phenology row below it already looks like at AX5, and what a screenshot shows
in a second and no assertion in this project can see. Height does not separate them either: the
compressed `HStack` measures 203 pt tall against the wrapping flow's 175, for the same reason.

So the flow stays, for **legibility** and not for overflow, and the test now asserts only what a
measurement can decide — that the row stays inside the width it is given, which a `fixedSize()` or a
`frame(minWidth:)` would still break, and which is how #45 happened in the first place. Which layout is
readable is verified by looking, per ARCHITECTURE §7.

**What looking found that no test was asked for.** At AX1 — the size ARCHITECTURE §6 actually names as
the bar for field screens — the camera-denied fallback sentence sat *on top of* the three chips. Both
were bottom-anchored overlays on the viewfinder, at `bottom:150` and `bottom:34`, independent of each
other; the sentence grows to two lines as the ramp climbs and it grew straight through the chip row.
That state is not exotic: BUILD-PLAN §9 requires it, and a simulator is always in it. They are one
`bottomControls` stack now, with the gap derived so the chips land on the mock's 150 pt exactly in the
state the mock draws. A stack cannot overlap itself.

**And one thing that is left broken, deliberately.** At AX5 screen 04 collapses: the tray takes almost
the whole phone, the viewfinder is left about 130 pt tall, and the chip row — a bottom overlay on that
viewfinder — is pushed off the bottom of the screen entirely, so #81's feature cannot be reached at all.
It is pre-existing, the same before this change as after, and it is not a layout that can be repaired by
moving a padding: at AX5 an overlay-based camera is not a workable arrangement and what replaces it is a
screen variant SCREENS.md does not draw. ARCHITECTURE §5.8 says stop and ask, so this stops and asks.

**The framing is frozen at the shutter, and that is a behaviour change with a reason.** It used to be
re-read at "Log visit", on the recorded argument that "the chip row stays live after the shutter and
the last tap before Log visit is the answer". That was reasonable for one photograph and is destructive
for three: it would relabel every staged photograph as whichever chip happened to be selected when the
button was pressed, and since the file on disk is named after the framing, the row and the file would
then disagree about which photograph they are. The same reasoning applies to the ghost overlay: it is
recorded from `draft.photo(shotType: .fullTree)` specifically, not from the selected chip, because
`VisitGhostStore.record` refuses anything that is not a full tree — so passing the selection would have
made whether the next visit gets an alignment layer depend on where a contributor's finger stopped.

**One regression this introduced and it was caught by looking.** `hasSnapped` became per framing, and
`VisitCameraView` fired the shutter flash on `hasSnapped` turning true — the same event as a capture
while a visit held one photograph, and *not* the same event once selecting an already-photographed chip
also turns it true. Tapping between two filled chips flashed the screen white as though each tap had
taken a photograph. On a simulator or the library fallback that flash is the only confirmation a
capture has, so a false one is a lie about the one thing this screen has to be honest about. The flash
is keyed on `VisitCameraModel.captureTick` now — a counter incremented *after* the write, so a refusal
flashes nothing either.

### How each of these was made to fail

Reverting `VisitPhotoStaging.url` to `"\(visitID.uuidString).jpg"` is the deliberate break that
matters. Six tests fail with sixteen issues, and they name the loss in pixels rather than in
abstractions: the round-trip lands two photographs instead of three, one `photos` row keeps
`storageKey: nil` because the second upload found its source already moved, and the staged files all
measure 240×180. Replacing `PhotoBinary.write` with a plain `data.write(to:)` — a new capture path that
skips the strip, which is precisely E148's failure mode — fails the two new staging tests with 69
issues naming the GPS dictionary, `MakerApple`, `TIFF.Make`, `TIFF.Model` and `Exif.BodySerialNumber`
read off the written files.

Making `shotType`'s setter bump `captureTick` — which is the old flash behaviour, expressed on the
model — fails `theFlashCountsCapturesOnly` with "selecting a photographed chip flashed the screen 3
times". Taking the ghost from `shotType` rather than `.fullTree` fails
`theGhostComesFromTheFullTreeShot`. Requiring all three framings in `enqueue` fails
`twoOfThreeIsStorable`.

The one that did *not* fail is recorded above, because it is the more useful result: `shotTypeChips`
put back to an `HStack` left the AX5 measurement green, twice — once through the old whole-screen test
and once through the row-only rewrite — and that is what settled the question of whether an `HStack`
overflows at all.

### A correction to the inherited work

The tests as inherited used `VisitPreviewFixtures.outbox()` for two cases that *save*. That fixture is
deliberately unmigrated — "the previews draw the screens, they do not save from them" — so
`logVisit()` failed on a missing `outbox` table and returned nil, and the two tests read that as a
refusal of the framings they were about to assert on. They use a migrated queue now. It is the ordinary
version of this file's own thesis: a test can fail for a reason that has nothing to do with its
subject, and the reason it gives is the one you wrote in the assertion.


### E153 — the almanac's two group-tap tests blamed the almanac for a fix that was never going to be there (#63)

`AlmanacGroupTapTests` failed with two sentences that were not true — `§4's CTA is not on the almanac`
and `R10's row is not on the almanac` — and it failed with them on every machine, including one with a
simulated fix over San Francisco. Two separate things were wrong, and only the first was the one that
had been noticed.

**The guard that could not fire.** Without a coordinate there is no neighbourhood (A4, ERRATA E44) and
`AlmanacScreen` draws E123's `See your neighbourhood` prompt **in place of** all four blocks, so both
counted rows are correctly absent. `reachAlmanac` knew that and carried the right message; it detected
the state with `app.staticTexts["See your neighbourhood"].waitForExistence(timeout: 3)`. A fixed wait
on an *absence* is wrong in both directions at once — too short and it misses, which is what happened,
so the guard passed and the test walked into an assertion it had itself decided might be unanswerable;
too long and every healthy run pays for a state it does not have.

**So the wait is a race, and deliberately not a symmetric one.** `reachAlmanac` now takes the element
its caller is about to tap and polls for it, in the shape `MapSearchUITests.wait(timeout:for:)` already
uses on screen 01. The row ends the wait the instant it appears, so a run that is going to pass pays
nothing. The prompt does not end it early — it is the state screen 12 is drawn in until a coordinate
turns up, and this helper has been wrong once already about how long that takes — and only once the
row has failed to arrive does the prompt decide which report is honest. The report is then a skip
rather than a failure, which `MapSearchUITests.requireAMapWithPins` had already settled for the same
missing fix and in the same words: "a skip says 'not checked here', which is true, where a failure says
'broken', which is not". It carries the same literal command its neighbours do, `xcrun simctl location
<udid> set 37.78485,-122.4215`. The helper throws rather than returning `Bool`, which is what `XCTSkip`
needs and what removes the `guard … else { return }` at both call sites; nothing else called it.

**And then the tests still failed, with a fix, on a screen that was showing neither thing.** This is
the half that had not been noticed, and it is worth stating plainly: on the entrance these tests used,
`CYPRESS_SCREEN=journal`, they could never have passed. `AlmanacView` builds its `@State` model from
the coordinate it is handed and keeps it — E123 recorded that as a known limitation, phrased as "the
content appears on the next visit to the tab" — and the deep link puts screen 12 on the glass inside
the first frames of launch, before the ask has been answered and long before CoreLocation has published
anything. The model reads `almanac(near: nil)`, which is `.empty` by contract, and stays there. A
second later the fix does arrive, `showsLocationPrompt` (which is `coordinate == nil`, recomputed on
every pass) flips to false, and the prompt is withdrawn from a screen that has nothing to replace it
with. What is left is a header with no pill, the footnote, and eleven hundred points of nothing.

**That state is a defect in the app, not in the test, and it is left standing.** It is precisely what
ERRATA E126 built the failure sentence for — "a screen that draws its five blocks away and leaves a
footnote is reporting a quiet neighbourhood" — and it slips past both guards, because the read did not
fail and the coordinate is no longer nil. E123's own note is too kind to it: the prompt is *not* honest
either way, because by then the prompt is gone. The fix belongs with `AlmanacModel` — reload when the
coordinate it was built without turns up — and it is a product change with its own tests, not a line to
be smuggled into a test repair.

**What the tests do instead is use the app's own front door.** They launch on screen 01, which is the
one screen that asks for location on the shipping path (`MapHomeView.task` is the only caller of
`start()`), wait until the map has drawn individual pins, and then press `Journal` and `Neighborhood`.
Screen 12 is built at that press, from a coordinate that exists. This is not the test navigating around
the blank screen — it is the sequence in which the app is actually used, and it is the only one in
which screen 12 is built from a coordinate at all. The pin wait is not a fix check and does not claim
to be one (see below); what it buys is that the tab is not pressed before the map has finished its
first read, which is as close as this suite can get to "CoreLocation has had its chance to answer".

**The obvious better witness was tried first and does not work, which is a finding of its own.**
`MapRecentreCopy.value` says `Centred on you` only by way of `camera.isCentred(on: coordinate)`, so it
cannot be true without a coordinate — an exact statement of the thing being waited for, in the app's
own words, with no basemap involved. Measured on a simulator with a fix set over Van Ness, the control
reads `Not centred` for the whole of a 39-second run, and a screenshot of that same launch shows the
camera sitting on the fix with the reader's blue dot in the middle of the screen. The control is
describing a camera that is not the one on screen. It belongs to screen 01, it is not this task's, and
it is filed rather than fixed here — but it means the recentre control's `accessibilityValue` is
telling a VoiceOver reader the map is not on them while it is, and `MapRecentreUITests` cannot catch it
because it only asserts the value is non-empty.

**The other candidate turns out not to mean what the codebase thinks it means either.**
`MapSearchUITests.requireAMapWithPins` treats "the map drew individual pins" as "there is a fix", on
the reasoning that a fixless map opens on the whole city at a clustered zoom. It does not: screen 01
opens at `MapLayout.defaultSpanMetres`, 120 m across, whether or not there is a fix — only the centre
differs — and measured with location revoked outright for the app, the map opens on Dolores Park and
draws pins there anyway. That skip cannot fire. It is harmless where it sits (those two tests then run
and pass), but it is not a fix detector and it is not used as one here. What the pin wait does in this
file is hold the test on the map until the map has finished its first read, which is the difference
between pressing `Journal` before CoreLocation has answered and pressing it after; the only skip is
the one screen 12 itself justifies, and it is the prompt that decides it.

**Verified in all three directions, on iPhone 16.** With location granted and `xcrun simctl location
… set 37.78485,-122.4215`, both tests **pass** — 18.3 s and 19.1 s — and they tap through to the
screens they were written for, which their own screenshot notes record: `Walk the two → …` and
`187 empty planting sites → …`, in Western Addition. With location revoked from the app, both
**skip** — `screen 12 drew "See your neighbourhood" instead of its neighbourhood, so neither counted
row exists to tap — this needs a simulated GPS fix over San Francisco: xcrun simctl location <udid> set
37.78485,-122.4215`. And with screen 12 deliberately broken — `vacantSitesBlock` and `coverageBlock`
deleted from `AlmanacScreen.body`, leaving §3 and therefore a neighbourhood — both **fail**, at the
caller, naming the row: `XCTAssertTrue failed - R10's row is not on the almanac, which does have a
neighbourhood` and `… §4's CTA is not on the almanac, which does have a neighbourhood`. That is the
one thing a skip must never do, done on purpose to check it does not. The break was reverted and the
app tree is byte-identical to what it was before it.

**One note for the next person who tries to reproduce the skip.** `xcrun simctl location <udid> clear`
does not do it: the app keeps receiving the last fix and both tests went on passing. What produces a
device with no fix is `xcrun simctl privacy <udid> revoke location app.cypress.Cypress`, which is the
knob `MapRecentreUITests` already documents for the same purpose.

The blank almanac was photographed rather than deduced: the app was installed and launched with
`SIMCTL_CHILD_CYPRESS_SCREEN=journal`, and the screenshot shows `Almanac` with no pill, no prompt and
no blocks; one press to `Map` and back to `Journal` filled the same screen with Western Addition.


### E154 — My Grove and the Journal looked alike, and for one pair of them they were the same list

The project owner, using the app: *"What's the diff between Trees and Journal? They look almost
identical. We need either some differentiator or some small explanatory note of what's on each page,
and a theory about why to keep both."*

There were **three** surfaces, not two, and the duplicate was not the one named in the complaint:

| surface | what one row is | a tree you visited twenty times |
|---|---|---|
| My Grove ▸ `Trees` (`GroveTreesPresentation`, from `grove()`) | one tree you have a relationship with | **1 row** |
| Journal tab ▸ `Yours` (`JournalPresentation`, from `journal(cursor:limit:)`) | one thing you did | 20 rows |
| My Grove ▸ `Journal` pill | **the same list as the Journal tab** — same read, same rows, same view | 20 rows |

So the genuine duplicate was the pill against the tab. Trees against Journal is two different
questions that had been given one drawing.

---

**The pill is cut, and E135's argument for it is answered rather than overturned.**

`GroveTreesTests.theJournalPillIsOneListNotACopy` was placed in the suite specifically so that a
round proposing this would have to answer it first. Its argument: an earlier round wanted to cut the
pill because "two copies of a person's own record is two things that must agree forever", and that
objection was answered *structurally* — one derivation (`JournalPresentation`), one model and one
view (`JournalSection`), mounted in both places, so there is no second implementation to drift.

That argument is correct and nothing found here contradicts it. **It establishes that the two
surfaces can never disagree. It does not establish that a reader needs two doors into one room.**
The owner hit exactly the second thing: he spent time working out why two things looked the same,
and for the pill and the tab he was not mistaken — they *were* the same list. Drift-safety is not
comprehensibility.

The cost the earlier round weighed was a control the design draws being left unbuilt (SCREENS.md 08
§2 draws three pills). The cost since observed is a person unable to tell two of his own screens
apart. The second is larger, and it is evidence the earlier round did not have. **This is a
different argument on different grounds, not the old one becoming right.**

Deviation recorded: **screen 08 §2's three pills ship as two**, `Trees` and `Species`. The row is
still 08's own geometry (E46) with one `flex:1` cell fewer.

`theJournalPillIsOneListNotACopy` is replaced by `theJournalHasOneDoorNotTwo` — the same forcing
function pointed at the failure that happened. A second entrance to the journal has to break a test
to exist. `ScreenEntranceTests.theSurfacesThatWereNotRoutes` asserted
`GroveTab.journal.hasDestination` as its proof that `journal()` had a caller; a pill that no longer
exists must not leave a test asserting it leads somewhere, so it asserts what is actually required —
the journal has a caller, and exactly one.

---

**The survivors were then made to look like what they are.** They were identical *today* only
because the app is new and most trees carry one event; they diverge permanently the first time
somebody visits one tree twice. Both drew title = tree name, subtitle = grey text ending in a date.

- **Trees is a set of nouns.** The date is gone from the row entirely; recency moved out of the text
  and into the ordering, which is `last_visited DESC NULLS LAST` and was always the store's. In its
  place the row carries the shape of the relationship: `Favorite · 3 visits · 1 measurement`. That is
  the one fact the journal cannot state without printing twenty rows.
- **The Journal is a stream of verbs.** The date leads: one `micro.label` section header per day —
  §1.3's own treatment for "section headers inside screens" — with that day's acts under it. Row
  titles are verb-first (`Visited Grandmother Cypress`), so the act is the subject rather than a
  clause in grey at 12.5 pt. The note is the only thing left on the second line.
- **One explanatory line under each header**, which is what was asked for, written as a pair:
  *"One line per tree, however many times you have been back."* against *"One line for each thing
  you did, newest first, under the day it happened."* Same length, same shape, opposite content.
  The tone model is `JournalCopy.emptyState`, which does its whole job in one breath.

Grouping is by **consecutive run, never by key**: the store orders by `captured_at DESC`, so a day's
rows are already contiguous and folding runs preserves the read's order exactly, while
`Dictionary(grouping:)` would impose an order of its own and `Show earlier` would begin inserting
rows into the middle of a list somebody is reading. It also merges a page boundary that falls inside
a day into the section already on screen instead of drawing the same date twice.

---

**The tally, against D1 and ARCHITECTURE §5.1.** §5.1 is blunt — "if you find yourself writing
`visitCount` into a user-visible string, stop" — and `3 visits` is literally that string. The
exception is not new: `DeviceContributions` already argued it for screen 15's `Keep your three
visits`, on three clauses. `GroveRecord` carries those three and adds two that a *list* needs:

1. **never public** — one phone, contributions in the common case attributed to nobody at all (D9),
   and no `CypressAPI` method that could return a second person's grove to sit beside it;
2. **never compared** — nothing sorts on it, nothing takes a maximum. The list's order is the
   store's, and `theTallyDoesNotSortTheList` is built so that a sort in either direction changes the
   answer;
3. **never a reward** — no badge, no threshold, no colour that changes. The row is drawn identically
   at one and at forty;
4. **never summed** — there is deliberately no `total` on the type and nothing anywhere produces a
   row about the grove rather than about a tree (`theTallyIsNeverATotal`);
5. **kinds, not one number** — `4 entries` is a single figure a person can rank their own trees by
   and want to raise; `3 visits · 1 measurement` says what *kind* of relationship it is, which is a
   thing to have rather than a thing to maximise. It is the more useful sentence besides: it tells
   you that you have never measured the tree you walk past every day.

`GroveQueries`' header says "nothing here counts contributions", and that stays true of that file —
it feeds the species ring, whose numerator is a count of *species*. The tally is a different question
with a different subject and lives in `ContributionStore.groveRecords`, next to the grove read it
belongs to.

**E38, pages are not totals.** `groveRecords` answers with `COUNT(*)` over the whole predicate and no
limit, so the engine proved the number — the same standing `deviceContributions` has. An
implementation that cannot prove it returns **nil**, and `GroveEntry.record` is optional for exactly
that: a nil draws no tally at all rather than `0 visits`, which would be a claim about a person's
history that an unproven read may not make. Both reads run inside one `queue.read`, so the rows and
their tallies come from one snapshot.

**And the distinction cost something to keep.** The first implementation wrote:

```swift
record: records[row.treeID] ?? .none
```

`records[key]` is `GroveRecord?`, so the contextual type of `.none` is `Optional<GroveRecord>` and
the leading dot resolved to `Optional.none` rather than `GroveRecord.none`. It compiled. Every
favourite nobody had visited came back as *"this read could not answer"* when the read had in fact
answered. **A leading-dot `.none` against an optional of a type that has its own `none` is a silent
type error**, and it was caught only by the test that goes through `LocalAPI` against a real store —
no test over the doubles could see it, because a double hands that field over directly.

And the honest limit of that, since a later round will otherwise over-trust the optional: **the two
states draw the same thing.** An unproven read prints no tally and a proved-empty record prints no
tally, so this bug had no visible consequence and no assertion about a *string* can tell the two
apart. The mutation sweep showed it — replacing `if let record` with `record ?? GroveRecord()` did
not fail a single test, because a record of four zeroes produces no clauses either. What the optional
buys is that the difference is representable and cannot be printed as `0 visits` by a later change;
what guards it is an assertion on the value (`aFavouriteWithNoContributionsIsEmptyNotUnknown`), never
on the drawing.

---

**Looked at, not only tested.** `CypressTests/GroveJournalShots.swift` draws both surfaces from one
contribution history and lays them out two columns wide, so the comparison is one image. The fixture
is the argument: one tree carries six records, one carries two, one is a favourite nobody has
visited — Trees draws three rows over the history the journal draws eight rows of. Five trees with
one event each would have photographed the two screens agreeing, which proves nothing.

Before, both columns are a white card, a green tile, a bold tree name and a grey line with a date in
it, under a My Grove that offers a `Journal` pill. After, they share no element of grammar.

The shot harness had to be talked down from 2,400 pt to 1,200: the contact sheet is
`rows × (cell + caption)` tall, so three rows of 2,400 asks `UIGraphicsImageRenderer` for a 21,930 px
canvas — past the ~8,192 px ceiling E145 records and, at that size, past what the host process
survives. It crashed the test runner before the number was picked. **E145's ceiling applies to the
sheet, not only to the capture**, which is not what that entry says and is where the next person will
meet it.

**Two things AX5 showed that the drawn size did not.** In the before shot the `Trees` row's title
truncates to `Grandmother…`; in the after shot it wraps to two lines. That is an observation off two
images and the cause was not chased — `IconTextRow`'s title still carries no `lineLimit` and no
`fixedSize` in either — so it is recorded rather than claimed as a fix, and the missing `fixedSize`
on that `Text` is a thing worth looking at on its own. Second: two pills have room for their labels
at AX5 where three were tight. Neither was the point of the change.

---

**One thing this round cost somebody else's tests, and it was not the code.** Two UI tests —
`AlmanacGroupTapTests.testWalkTheNineOpensAMapOfThemAll` and
`DeepLinkVoiceOverTests.testTheNudgeControlsActuallyMoveThePin` — failed on this branch and passed the
moment the simulator's fix was moved. They had been run against a streaming `simctl location` route
over the **Outer Sunset**, and E153's own skip message names the fix these tests want:
`37.78485,-122.4215`. A neighbourhood with no young unvisited trees in it has no §4 coverage CTA, so
the test failed on a *correctly* absent row — the state E153 was written to distinguish, one
neighbourhood further out than it had been asked about. The same two failed on pristine `main` under
the same conditions, which is how they were attributed.

So: **a red UI test on this project is a question about the simulator's fix before it is a question
about the diff**, and a *streamed* route is worse than a static fix here, because it is plausible,
persistent across runs, and invisible in the failure message.

**Open.** The `Trees` list still says nothing about *when* — deliberately, since that is the
journal's job — which means a tree seen yesterday and a tree seen two years ago read alike unless you
notice where they sit in the order. Ordering carries it today because the grove is short. If a grove
ever runs to a hundred trees, position stops being legible as recency and the question reopens; the
answer then is a section header ("this season" / "before that"), which is a structure, not a date on
a row, and not a duration since (a duration is one rendering away from a lapsed streak, D1).


### E155 — the almanac went permanently blank if it was opened before the fix arrived (#99)

Screen 12 has one input that is not the database: a coordinate. Everything on it — the pill, the
three season rows, the composition card, the vacant-site count, the coverage ask — hangs off
resolving a neighbourhood from that coordinate, and `LocalAPI.almanac(near:)` answers `.empty` for a
`nil` one, which is right: without a fix there is no area and the almanac has no subject (A4, E44).

`AlmanacView` built its model in a `@State` initialiser. `@State` runs its initialiser exactly once
for the lifetime of the view's identity, so the coordinate the almanac was derived from was whichever
one existed in the first frame, permanently. On a cold launch that is `nil` — the composition root's
`MapLocationProvider` is inert until screen 01 asks it to start, and CoreLocation then takes its own
time. The almanac read `almanac(near: nil)`, got `.empty`, and stopped.

That much was known. E123 recorded it, under "one known limitation, left as-is": granting location
while standing on the almanac would not reload it, "and the prompt is honest either way… the reader
reaches the filled screen by the next navigation".

**The second half of that sentence is false, and this is the case that disproves it.**
`showsLocationPrompt` was `coordinate == nil` computed in the same initialiser — but as a plain `let`
on a struct, which SwiftUI recomputes on every pass the parent makes through its body, unlike the
`@State` beside it. The two therefore came apart the instant the fix landed: the model still held the
empty almanac it had read from `nil`, and the prompt that explained it evaluated to `false` and
disappeared. What the reader is left with is a header with no pill, a footnote, and eleven hundred
points of nothing, until the view is torn down and rebuilt.

So the prompt is not honest either way. It is honest for about a second, and then it removes itself
from precisely the screen that most needs it. This is the state E126 built screen 12's failure
sentence for — "a screen that draws its five blocks away and leaves a footnote is reporting a quiet
neighbourhood" — and it walks past both of that entry's guards, because the read did not fail
(`hasFailed` is correctly `false`) and the coordinate is no longer `nil`.

It is reachable in the shipping app: cold launch, tap `Journal`, tap `Neighborhood` before the fix
lands. Indoors on a real phone that window is seconds. Through the DEBUG `CYPRESS_SCREEN=journal`
deep link it happens every single time — `RootView` opens the link from a `.task`, which runs after
the first frame, so screen 01 mounts, `MapHomeView.task` calls `start()`, and the router then swaps
in the journal tab well before the provider has published anything. That is how it was found (E153),
and it is the reliable reproduction.

**The invariant, restated, because the fix is shaped by it rather than by the symptom.** A screen
with nothing on it must always say why. Not "must eventually say why", and not "must say why at the
moment it becomes empty" — at *every* moment, an empty screen 12 carries either the prompt or the
failure sentence.

**What changed.** Two things, and the second is the one that holds the invariant.

1. `AlmanacModel.coordinate` is a `var` the model can be told about again, and `AlmanacView` reads
   with `.task(id: coordinate)` rather than a bare `.task`. A bare `.task` runs once at mount, which
   is the same once-only the `@State` initialiser has, so it would have moved the bug rather than
   fixed it. Keyed on the coordinate, the read re-runs when — and only when — the fix changes.
   `AlmanacModel.update(coordinate:)` is the entry point and returns without a read when the value
   has not moved, so a provider republishing the same fix does not re-read the whole almanac.

2. **The prompt is decided by the coordinate the picture on screen was derived from, not by the one
   the parent is holding.** `AlmanacModel` keeps `displayedCoordinate` alongside `coordinate`; they
   differ for exactly as long as a re-read is in flight, and `needsLocation` — which `AlmanacView`
   now hands to `AlmanacScreen` in place of E123's view-layer `let` — reads the first. The re-read
   also deliberately does **not** reset the phase to `.loading`: the empty almanac and its prompt
   stay on the glass until the replacement has actually been read. Without that pairing the fix
   would still leave a window, one database read wide, in which the prompt has gone and the
   neighbourhood has not arrived — the same blank, made brief instead of made impossible.

A read that is superseded by a newer fix while it is in flight drops its own answer rather than
writing it. Two fixes in quick succession is ordinary on a phone that is still settling, and the
stale one landing last would put a neighbourhood on screen that `displayedCoordinate` no longer
describes — which would break the invariant in the other direction, by making the prompt's condition
answer for a picture nobody is looking at.

**Where E123 went wrong, precisely.** Not in showing the prompt — that ruling stands and the copy is
unchanged. It went wrong in the sentence "because it is a view decision rather than a derived value,
it carries no presentation test; it was verified by **looking**". The looking was done on a device
whose fix was already settled, where `coordinate == nil` is a constant for the whole life of the
screen and the view-layer computation is indistinguishable from the right one. The condition is a
statement about the *state on screen*, and a statement about the state on screen belongs with the
thing that owns the state. E123 put it one layer above, where it is recomputed on a different
schedule from the thing it describes — and a condition that updates on a different schedule from its
subject is not a condition, it is a race that happens to usually win.

**Verification.** `AlmanacLateFixTests`. The model half asserts the sequence rather than the values,
because every individual value was already correct on the broken app: `almanac(near: nil)` is
`.empty` and should be, `coordinate == nil` was `false` and should have been, nothing failed. What is
only true on the fixed app is that a second coordinate is read at all, and that the prompt outlives
the read that replaces it. The mid-read assertion needs the read held open — a guessed sleep would
make the test's subject a timing assumption instead of the ordering it is about — so `Held` parks
inside `almanac(near:)` on two latches until the test lets it go, and the half-way state is looked at
rather than raced against.

The render half is the end-to-end statement, and it is the one that would have caught this without
knowing where to look: screen 12 rendered through a host whose coordinate is `nil` at mount and
becomes a fix after the first pass, against the same host with the fix there from the start, asserted
**equal**. A fix that arrives late must leave the reader looking at the same screen as a fix that was
always there; the blank, the prompt still standing, and a half-drawn column are all different
pictures. It is driven through `AlmanacView` rather than by handing `AlmanacScreen` a flag, for the
reason E126 gives about its own render test — the wiring between the model and the screen is half of
what was broken. The control render proves the harness byte-stable first, without which an equality
assertion is as void as an inequality one.

**Three deliberate breaks, and the third one is the reason this section is long.**

Removing the re-read at the *model* — taking the new coordinate but never loading from it — reddens
the model tests exactly where they should: `(api.reads → [nil]) == ([nil, Self.fix] → …)`,
`(model.presentation?.neighborhoodName → nil) == "Sunset/Parkside"`, and
`(model.needsLocation → true) == false`.

Restoring `needsLocation` to E123's `coordinate == nil` leaves every plain re-read test green and
reddens exactly one assertion, the mid-read one: `Expectation failed: (model →
Cypress.AlmanacModel).needsLocation → false`. One line of one test, which is what a break this
narrow should cost.

Reverting `.task(id: coordinate)` to a bare `.task` — the original defect, exactly — leaves all four
*model* tests green, because the model is not what is wrong, and reddens only the render comparison:
`Expectation failed: lateMatchesEarly`. That asymmetry is the argument for having both halves.

**And that last break exposed a defect in the test rather than in the app, which is worth more than
the entry it was found under.** With the comparison written the obvious way — `#expect(late ==
early)` on two `Data` values — the test did not fail. It *hung*: sampled at ninety-nine per cent of a
core and three gigabytes resident, the whole stack sitting inside `BidirectionalCollection.difference`
→ `_myers(from:to:using:)`. Swift Testing, on a failing comparison of two collections, builds a Myers
diff to describe the mismatch, and a Myers diff of two hundred-kilobyte PNGs does not finish in any
useful time. `FailedReadTests` has never met this because its picture assertions are *inequalities*:
they pass, and a passing expectation is never asked for a description. So an equality `#expect` on
large `Data` is a test that cannot fail — this project's single most repeated defect, arrived at from
a direction nobody had come from before. Reducing the comparison to a `Bool` before the macro sees it
turns a hang into a five-point-seven-second failure. `FailedReadTests` should probably be given the
same treatment defensively; it is not touched here.

The two latch-based tests carry `.timeLimit(.minutes(3))` for a related reason: they wait on a read
*beginning*, so an app that has stopped re-reading does not fail them either, it never wakes them.
Three minutes and not Swift Testing's minimum of one, because one minute is reachable by load alone —
these were measured on a machine at a load average of three hundred with three agents on it, and a
limit a busy machine can trip is a flake wearing a failure's clothes.

And it was looked at, running, on the entrance it was reported from: `CYPRESS_SCREEN=journal` on
iPhone 16 with `xcrun simctl location … set 37.78485,-122.4215`. **Before**, screen 12 is a bare
`Almanac` header and a footnote, with no pill, no prompt and nothing between them, and it is still
that twenty seconds later. **After**, the same launch draws the pill `Western Addition`, `THIS SEASON`
with the elder (`New Zealand Xmas Tree · in the city record since 1972`), `WHO LIVES HERE · 135
SPECIES` with its four-row composition card, `WHERE A TREE COULD GO · 187 empty planting sites`, and
`WHERE EYES ARE NEEDED · 2 young trees with no visits since planting / Walk the two` — the same
neighbourhood and the same two numbers E153 recorded from the front door. With location revoked
outright from the app, the same launch draws E123's `See your neighbourhood / Turn on location and the
almanac fills with the trees around you` and nothing else, so the prompt still owns the state it was
built for.

**An environment note, filed because it cost an hour and will cost the next person the same.** The
unit suite does not merely fail on a simulator that has never granted the app camera access — it
**hangs**. `VisitCameraSubjectTests.aStoredGhostIsNotDrawnOverACloseUp` calls
`VisitCameraModel.load()`, which reaches `VisitCameraController.start()`, which on `.notDetermined`
awaits `AVCaptureDevice.requestAccess(for: .video)`. That presents a system alert over the test host
and waits for somebody to press it, and nobody is going to. The run stops with a suite `started` and
never finished, one test's worth of output missing and no failure anywhere — which reads exactly like
a stall. `xcrun simctl privacy <udid> grant camera app.cypress.Cypress` and it passes in 3.9 s. The
grant is also what an `xcrun simctl uninstall` throws away, so reinstalling the app between runs
reintroduces it. Worth a line in whatever document tells a new agent to copy the seed database in.

**One consequence worth stating.** The deep-link entrance to screen 12 is viable again — it now
produces a populated almanac on a simulator with a fix. `AlmanacGroupTapTests` (E153) still reaches
the almanac by the app's own front door, and is left that way deliberately: its subject is the two
counted rows and the screens behind them, not this defect, and the front door is the sequence in
which the app is actually used. Rewriting it to use the deep link would trade a test of the product
for a test of the seam. Both of its tests were re-run against this fix and pass — 18.7 s and 18.1 s —
so nothing E153 established has been undone.

**Not addressed here.** Screen 12 still draws nothing while its first read is in flight on a device
that *has* a fix. That is the ordinary loading blank, it is measured in milliseconds against a local
SQLite read, it predates this entry, and it is the same on every screen in the app; giving screen 12
alone a spinner would be a design change, not a repair. It is named so it is a known boundary rather
than an oversight.

The same `@State`-built-from-a-parameter shape exists at four other sites, all of them carrying
`gpsAccuracyM: location.availability.accuracyM` into a once-only model — `CareLogView`,
`CheckInView`, `MeasureView` and `VisitCameraView`. There the snapshot is arguably right (a
contribution should carry the accuracy of the fix it was taken on, not a later better one), but the
cold-launch case is the same: a form opened before the first fix records `nil` accuracy even though a
fix arrives while it is being filled in, and D6 treats a missing accuracy as unusable rather than as
good. Filed, not fixed here.


### E156 — The map drew a different city's trees than the city's own map did, and nothing said which

For its whole life the seed has been built from DataSF's `tkzw-k3nq` export, and the app has
described those 195,309 rows as San Francisco's street trees. The city's own public map at
<https://bsm.sfdpw.org/urbanforestry/> draws a different list — SF Public Works' operational
`BUF_Street_Trees` layer, 133,577 records — and the two disagree in both directions. The owner found
it by hand: a 36-inch Monterey Pine at `1 TWIN PEAKS BLVD`, TreeID 276198, on the city's map and
absent from ours. Not a pipeline bug. `tkzw-k3nq` has never contained it, and has never published any
`TreeID` above 276035, while the operational layer has issued ids to 277733.

Measured against a full extract of both, 2026-07-26: **130,070 records are in both, 65,239 are in
DataSF only, 3,507 are in the city's layer only.** The 65,239 are mostly what the city's map
deliberately does not show — 37,707 `Permitted Site` rows where a permit exists and a tree may not,
7,356 `Undocumented` — but **17,443 are `alive`, carry an ordinary legal status (15,348 `DPW
Maintained`) and sit on ordinary sidewalk sites**, and nothing in either schema says why the city no
longer lists them. That residue is unresolved and is the largest thing the switch takes on faith.

The owner has ruled that the city's own inventory decides which trees exist, and it now does:
`Tools/build_seed.py --source city` is the default and ships all 133,577 of them. **`--source datasf`
still builds the old seed and is still tested**, because reversal had to stay one command rather than
one revert. `Tools/fetch_city_trees.py` caches the extract to `Fixtures/raw/` — 67 sequential pages, a
second apart, resumable — and the build never touches the service.

**No uuid moved.** Both paths derive `trees.uuid` as `uuid5(NS_TREE, <TreeID>)` and both inventories
use the same `TreeID` space, so all 130,070 shared records kept their identity byte for byte, in both
directions. That was the precondition for making the switch reversible at all, and it was verified
rather than assumed.

**Which inventory decides a row is not the same question as which one knows a fact, and answering
them together was the mistake worth recording.** The first build took the city's layer alone. It
publishes seven fewer columns than the export, so the seed came out with **zero planting dates**, no
legal status, no plot sizes and no caretaker — which meant `LandContext.inferred(from:)` could place
no tree, the `Stands on` sentence drew for nobody, and the almanac's elder, plantings and coverage
reads returned nothing for the entire city. Screen 12 lost three rows. Worse, three test suites went
*green* on it: their assertions are exclusions ("no inventory read returns a vacant site") and an
exclusion is trivially true of an empty answer. Only the two UI tests that tap those rows failed, and
they looked like harness flakiness. The shipped build takes the row set from the city's layer and
those seven columns from the export for the 130,070 records both list — 97% coverage, NULL on the
3,507 the export has never heard of — and the controls fire again.

The vacant-site collapse was the one loss that join could not repair, because a vacant site is a
*row* and rows come from the spine: **12,518 → 153**, with 17 of 41 neighbourhoods holding none. The
state #11 designed, #31 redirects to and #32 counts still worked and was still tested; it described
a third of the city and nothing else. **That has been undone, and the reason it could be undone
without touching the tree row set is the part worth keeping.**

**The city's layer is not disagreeing with us about vacant sites. It has no such category.**
`PlantType` is `Tree` on all 133,577 of its records; there is no site-status column, no `qSiteInfo`,
no `qLegalStatus`. Reading that silence as "a tree stands there now" would be inferring a fact about
the world from the shape of a schema. That is a different claim from the one this switch makes about
living trees, where the layer *is* the operational record and a tree it stopped listing is most
likely gone. So the seed now carries the export's vacant planting sites as rows alongside the city's
trees: **145,837 rows — 133,577 trees from the city's layer, 12,260 sites from the export** — and
all 41 neighbourhoods hold at least one site again.

The one place the two inventories genuinely contradict each other is a TreeID the export calls an
empty basin and the layer lists as a planted tree. **128 rows**, measured rather than assumed, and
there the city wins, exactly as it does for the tree row set. A further 130 the layer also holds as
empty (`BOTANICAL = 'Potential Site'`) were already in the seed from the first pass. Nothing is
double-counted and no `external_ref` appears twice, because the test is simply "did the city pass
already emit this TreeID".

**No uuid was ever at risk here either, and this was checked rather than reasoned about.** All 12,518
of the export's vacant-site TreeIDs are rows in the new seed; 128 of them are `alive` rather than
`vacant_site`, which is a change of status and not a change of identity. Across every simulator
install on this machine, 23 contribution rows reference a tree and **none of them references a vacant
site**, so the collapse orphaned nothing and the restoration un-orphans nothing. The only vacant-site
uuid written down anywhere in the repo is `aa72e15a-…` in `TreeProfilePreviews`, a preview fixture
constructed in code rather than read from the seed; its TreeID 271641 is back in the file regardless.

**This is what `--source city` means now, not a third flag value.** A `--source` value answers which
inventory the seed believes about the trees, and the export's sites are not a third answer to that
question — no build that wants a working "where a tree could go" can decline them, and no build that
has them is disagreeing with the city about anything. `--source datasf` still builds all 195,309 rows
and is still tested against its own pinned numbers, so reverting is still one command.

**Provenance is now a per-row fact, and it had to become one.** `trees.inventory_source` says which
inventory listed each row, and `seed_meta` carries a name, a url and a snapshot date for each. The
tree page's sentence — `From the SF Public Works street tree inventory, 26 July 2026.` — is true of
every record that draws it, because only the city's trees reach that screen. The vacant site has its
own screen and it used to say nothing at all about where its record came from, which was survivable
while the file held one inventory and is not now: it draws
`From the DataSF Street Tree List, 20 July 2026.` under its stat grid. The seed contract fails if a
row names an inventory the receipt cannot describe, so the sentence can never be resolved to the
other inventory's name by accident.

The deeper defect was never the row count. It was that a 100 MB file shipped inside the app with
**nothing anywhere saying where its contents came from or how old they were** — not on a screen, not
in the database, not in a log. That is why "is our data stale?" could not be answered when it was
asked; the only way to settle it was to re-download the source and diff. The seed now carries
`trees_source`, `trees_source_url` and `trees_snapshot_on` in its build receipt, written from the
extraction's own record rather than a clock, and the tree page's city-record section ends with `From
the SF Public Works street tree inventory, July 26, 2026.` The seed contract fails if that date is
missing or unparseable. One gate had to move to make room for it: `CityRecordPresentation.isEmpty` is
`facts.isEmpty`, which correctly refuses a header over an empty grid — and on the city-only build that
silently removed the entire section from every tree in the seed. The section now opens for cards
**or** for a provenance line.

**A UI test had been red since the first round and was not read as such.** `AlmanacGroupTapTests`
locates screen 12's coverage CTA with `label BEGINSWITH "Walk the "`, but
`AlmanacPresentation.coverageCTA` renders `Walk to it` when the count is one, because "walk the one"
is not a sentence. The neighbourhood these tests land in from the simulated fix — Western Addition —
held two young trees under the DataSF export and holds one under the city's, because the switch cut
the seed's planting dates from 70,067 to 28,747. So the button was drawn correctly and the locator
could not see it, and the failure read `§4's CTA is not on the almanac`: a true sentence about the
predicate and a false one about the app. That is the same "blame the almanac for something else"
shape E153 had just removed from these tests. The locator now matches `Walk `, and the count is left
to the assertions that were always about it.

Three smaller repairs rode along. `plant_type` held `Tree` 194,988 times and `tree` three times (TreeIDs
253212, 253634, 96598), so every `WHERE plant_type = 'Tree'` in the product silently dropped three
rows; the build now folds case-variant spellings in the five columns the app compares against
literals, and the seed contract fails if any return. Free text is deliberately left alone —
`McAllister St` and `MCALLISTER ST` are both spellings the city uses, and picking one would be editing
its record rather than repairing a filter. And the tree page used to say `The city's street tree
inventory records no pruning dates or schedule`, true of the export and false of the layer we now
ship: it carries `Prune_Year` on every record. That field belongs to the **keymap grid**, not the tree
— 133,577 records share 106 distinct values, 5,147 of them the exact string the owner saw under 276198
— so the seed does not carry it and the sentence now says the city records pruning by block and not by
tree.
And the debug harness's candidate window, widened from 500 to 4,000 in the first round because the
nearest vacant site to the map's opening centre had become the 1,181st record by distance, goes back
to 500: it is the 16th again, and the widening was making a harness green over a surface that had
gone vestigial.

**The 475 records the city writes backwards were already fixed and are recorded here so nobody
inherits them as open.** `city_qspecies` swaps `COMMON` into the botanical half when `BOTANICAL` is
empty and `COMMON` reads as a binomial; measured on the built seed, 410 of 540 such rows are swapped
and land on the real species row rather than minting one beside it. What is left is smaller and
different: 8 stub species shadow a species already in the corpus over 30 tree rows (0.021%), because
the city wrote the genus in lowercase or gave a cultivar with no epithet. Fixing that means a
canonical-spelling pass over the species name, which is #95's mechanism applied to a column #95
deliberately excluded, and it changes the corpus the species fixtures are sourced against. Its own
task, not a rider on a decision about which rows exist.

**One UI test is intermittently red on both corpora, it is not this change's doing, and its cause is
unresolved.** `MapSearchUITests.testTypingASpeciesNameNarrowsTheMap` types `Platanus` and asserts the
map still draws pins; when it fails it says `narrowing to the commonest species in San Francisco
emptied the map`. What is established:

- It **passed** on the shipped 145,837-row city seed at 21:37 and **failed** on that same file at
  22:01 and 22:04. So it is not decided by the corpus.
- It fails against the **pre-switch DataSF seed** built 2026-07-25 — before any of this work, with no
  `inventory_source` column and no `trees_source` receipt at all. So it is not this change's doing.
  (That run is also the only exercise the backwards-compatible read path has had, and it passed: a
  seed carrying neither the column nor the receipt still opened and drove the app.)
- It is **not a sampling race in the test**, which was the first hypothesis and is refuted: adding a
  thirty-second wait for the pin count to settle above zero still read zero, and the test then failed
  on the wait rather than on the sample. That change was reverted rather than kept, because a wait
  that does not fix it would have shipped a wrong explanation in a comment.

What is left is that the map genuinely draws no pin for the commonest species in San Francisco, some
of the time, on a build where the same search worked twenty minutes earlier. That is worth its own
task and it is not one this round can close honestly.

---

### E157 — Deleting your account did not stop the next one adopting your records

Account deletion offers two doors and the default is the kind one: *leave my records, unattributed*.
It nulls `user_id` on the four contribution tables and leaves `device_id` alone, which is the correct
thing to do with `device_id` — it is `NOT NULL` there, it is D9's anonymous installation handle, and
the row carried it before there was an account and would carry it if there had never been one.

D9 also says what a row in that shape *is*. `user_id IS NULL AND device_id = this phone` is the
definition of **this device's unclaimed work**, and `claimDevice` moves such rows onto the account
that signs in. So the leaving door produced rows that were, by every predicate in the app, the
phone's to give away, and the next account signed in on that phone took them. The journal, the grove
and screen 15's count read the same predicate and showed them for the same reason. Records a person
deliberately unlinked from themselves became linked to whoever came next: on a shared or handed-down
phone, a re-identification of somebody who had asked not to be identifiable.

The behaviour is older than the two-door deletion — it is D9's, and E136 recorded it as a known hole
and left it to the owner. What made it a defect rather than a quirk is that E136 also put the promise
on screen in words. `AccountDeletionCopy.leaveRecordsBody` said the records stay "with nothing left
on them saying they were yours", and that was true until somebody signed in. A promise on screen that
the database does not keep is not a backlog item.

The project owner ruled: *"Yes, anonymize with tombstone."* Rows anonymised by a deletion are marked,
and are skipped for ever.

**The shape, and the two obvious alternatives that are wrong.**

*Clearing `device_id` instead* is one `UPDATE` and it fails twice over. The column is `NOT NULL` on
all four tables, so the state does not exist; and if it did, it would erase the distinction the whole
fix rests on. **Anonymised by a deletion** and **never had an account** currently look identical, and
they are not the same thing: the second is D9's own case, an unsigned-in contributor keeping their own
work on their own phone, and it must go on being claimed. A fix that made those two states equally
unclaimable would trade one broken promise for another.

*A column on each of the four tables* — `anonymized_at`, in `deleted_at`'s shape — is the house's
usual move, and it closes the four tables while leaving the hole that matters open. A contribution
lives in the outbox between being written and being applied: `OutboxStore.forgetAccount` strips
`$.userID` out of the queued payload and the row is **inserted for the first time after the deletion
has already run**. A column-based tombstone has nothing to write on, because at deletion time the row
does not exist, and by the time it does the deletion is long over. It would be born unmarked and
adopted by the next account — the original defect with one extra step in front of it, under a
mechanism that looked complete.

So the tombstone is `AppSchema` **v13**, a side table keyed on the one identity a contribution has
*before* it is stored as well as after:

```sql
CREATE TABLE IF NOT EXISTS anonymized_contributions (
    client_uuid   TEXT PRIMARY KEY COLLATE NOCASE,
    anonymized_at TEXT NOT NULL
);
```

`client_uuid` is the idempotency key (BUILD-PLAN §4, DECISIONS §3.8). It is `NOT NULL UNIQUE` on all
four tables and a top-level key on all four payloads, so a deletion can tombstone a record that has
not been stored yet and the mark is waiting when the queue drains. That is the property a column
cannot have, and it is the whole reason for the shape.

`COLLATE NOCASE` sits on the key rather than on every reader because a UUID reaches this table by two
routes — `SQLiteValue`'s uppercase `uuidString` from a stored row, `JSONEncoder`'s from a queued
payload — and a guarantee should not turn on those two agreeing about case for ever.

The table holds a `client_uuid` and a timestamp and nothing else: no `user_id`, no `device_id`, no
tree. It says *this record is nobody's*, which is all that is needed. Storing the account it came from
would rebuild exactly the joining key `AccountDeletionChoice` refuses a sentinel id for — a stable
handle relinking one person's whole history of trees, dates and times.

**Which tables.** The four with `device_id NOT NULL`: `visits`, `observations`, `measurements`,
`care_events`. The anonymising path also names `photos` and `photo_votes`, and neither needs a
tombstone, for a reason worth writing down rather than assuming: both carry **at most one** owner
(v12 and v9), so an account-owned row has `device_id IS NULL`, and anonymising leaves both columns
NULL. `claimDevice`'s `device_id = :device` cannot match it. `tree_names`, `review_flags` and
`tree_status_overrides` are anonymised too and have no device column at all, so no claim path reaches
them. `private_reminders` and `favorites` are deleted with the account under both doors. The
tombstone lands on exactly the tables that can be re-adopted, and on all of them — a tombstone on
three of four would have been worse than none, because it would have made the guarantee look kept.

**Where the mark is read, and why it is five places and not one.** `claimDevice` is the only writer
that re-adopts, and it is called from two places (`LocalAPI.claimDevice` and the per-batch re-claim
`adoptRowsWrittenAfterTheClaim`), so guarding the function guards both. But `user_id IS NULL AND
device_id = :device` means *the work of the phone in your hand* in four more queries —
`deviceContributions`, `journal`, `groveTreeIDs`, `groveRecords` — and a tombstone applied to the
claim alone would have stopped the rows moving while going on displaying them. The next person to
sign in would read a stranger's visits in their own journal, and screen 15 would offer to keep a
count of records the claim then declined to move: the promise visibly broken in the one place a
person can see it. The clause is named once, as `ContributionStore.notAnonymized(_:)`, so that "all
five" is checkable rather than remembered.

That helper takes a table qualifier and it is not decoration. Written `WHERE t.client_uuid =
client_uuid`, SQLite resolves the bare name in the *inner* scope and the condition becomes a
tautology, so `NOT EXISTS` is false for every candidate row and the claim silently adopts nothing at
all. A guarantee that inverts on a name-resolution rule is not one.

**What it costs, stated because the owner weighed it and chose it.** Someone who deletes their
account and signs back in on their own phone does not get their own work back. There is no escape
hatch and one was not built: any mechanism that could return the records to the right person is a
mechanism that returns them to the wrong one, since nothing in the database distinguishes the two.
The copy on screen now says so, in the same breath as the promise rather than as a separate warning:

> Nobody can tell afterwards that they were all one person's, and that includes this phone: if you
> make a new account here, they do not come back to you.

It is written as a consequence of the promise, not as a caveat to it, because it is the same fact
seen from the other side — and a person who reads the first sentence and believes it should not need
a second paragraph to learn what believing it costs.

**Not changed, deliberately.** The records stay on their trees and are still read by every
tree-scoped query, which is the entire point of the door: `treeProfile` returns the visit, the
photograph keeps its place, the vote still counts toward the hero. What the tombstone removes is
ownership, not existence. And `AccountDeletion.Outcome` gained no counter for it — the number of
tombstones is the number of anonymised contributions, already reported, and a second field carrying
the same total is a field that will one day disagree with the first.

---

### E158 — Four contribution forms recorded the GPS accuracy from before the phone had one (#102)

Found while fixing E155, and it is the same mechanism read a second time. `@State` runs its
initialiser exactly once for the lifetime of a view's identity, so anything a view carries into a
model built there is the value that existed in the first frame and no other. E155 was a coordinate.
This is D6's per-contribution GPS accuracy, on the four views that carry one:

    Cypress/Features/CareLog/CareLogView.swift        — 09, the care log
    Cypress/Features/CheckIn/CheckInView.swift        — 05, the check-in
    Cypress/Features/Measure/MeasureView.swift        — 16, the measure sheet
    Cypress/Features/Visit/VisitCameraView.swift      — 04, the visit camera

Each took `gpsAccuracyM: Double?` and each was handed `location.availability.accuracyM` (or
`location.fix.accuracyM`) by its composition root, read once, at the instant the screen was built.

**Why this is not simply E155 again.** There the snapshot was straightforwardly wrong — an almanac
is a picture of where you are now, and freezing the coordinate froze the picture. Here the snapshot
is arguably *right*, and the argument for it has to be answered rather than ignored: a contribution
should carry the accuracy of the fix it was actually taken on, not a better one that arrived
afterwards. Attaching the newest accuracy to an append-only record would be a false claim about a
reading's provenance, and a quieter defect than the one being fixed — D6 exists so that a
measurement can be trusted to belong to the tree it names, and a precision the reading was never
taken at defeats exactly that. So the fix is **not** to make the value live.

**The defect is the cold launch.** The composition root's `MapLocationProvider` is inert until
screen 01 asks it to start, and CoreLocation then takes its own time; `VisitLocationProvider` is the
same. Open any of these four forms before the first fix lands and the model froze `nil`. A usable
fix then arrives while the form is still being filled in — a measure sheet is a kind, a method, a
unit and a number typed on a keypad; a camera session is up to three framings, a note and a chip
row — and the arrival was an event nothing in those screens could observe.

A `nil` accuracy is not a blank field. `FieldCaptured.isEligibleForGrowthCharting` treats it as
unusable rather than assumed good, deliberately and correctly ("unknown accuracy is treated as
unusable rather than assumed good", `CoreEntity`). So on screen 16 the whole of it lands: the person
walked to the tree, put a tape around the trunk at 1.4 m, typed the number, and the reading was
excluded from that tree's growth chart for the lifetime of the record, on a phone that had a
perfectly good fix by the time they pressed Save.

**What changed.** The parameter is a closure — `@escaping @MainActor () -> Double?` — which is the
shape `now` already has beside it in all four initialisers, and for the same reason: it is a
question about the present, and a form is a thing somebody fills in over a minute. Each model asks
it once, at the moment the contribution is written:

- `MeasureModel.save()`, `CareLogModel.save()` and `CheckInModel.save()` read it where they used to
  read the stored `Double?`.
- `VisitCameraModel.logVisit()` sets `draft.gpsAccuracyM` beside `draft.note` and
  `draft.phenologyTags`, which is where the other two properties of the contribution are already
  taken. The draft is built without one; the visit id still is minted at init, because that names
  the file the photograph is written to and has to exist before the shutter.

Submission is the moment the contribution exists, so this preserves the "accuracy of the fix it was
taken on" intent rather than trading it away — and it fixes the `nil`, because by the time a form
has been filled in a fix has almost always arrived.

`MeasureModel.presentation` reads it on every pass, which makes screen 16's chart notice — the
sentence under the CTA — track the fix. That sentence is a prediction about the next tap and has to
be made from the fix that tap would use. It withdraws itself when the first fix lands, which is
**not** E155's withdrawal: what it explained has actually stopped being true, and the screen it sits
on is full either way.

There is a race left, and it is the right one: the notice can say "chartable" and the fix can then
degrade in the second before Save, so the reading is stamped 40 m after being promised a dot. Both
sentences are true at the moment they are made, and any alternative freezes something.

**On whether D6's exclusion is silent, which was the second question.** It is not, and the premise
should be retired rather than acted on.

- Before the save, `MeasurePresentation.chartNotice` prints `Without a location fix the reading is
  saved but stays off the growth chart.` — and a separate sentence naming the metres when the fix
  is real and too poor. `ChartEligibility` has three cases and not two precisely so that the screen
  can say which.
- After the save, the reading is on screen 11's log. D6 excludes a reading from *charting*; it does
  not delete it, and `GrowthHistoryPresentation.logRows` carries every non-deleted measurement,
  dot or no dot. When nothing is chartable the screen prints a sentence where the cards would have
  been.

So E126's invariant — a screen showing nothing must say why — was already honoured at both ends.
What was wrong is one word of it. Screen 11's sentence read `taken with a GPS fix too weak to
attribute them to this tree`, which describes a bad fix to somebody whose phone had not answered
yet, and on the broken app that was not an edge case: the cold-launch population was the *whole*
population of nil-accuracy readings. `GrowthHistoryPresentation.noChartReason` now picks between
that sentence and `saved before the phone had a location fix`, on whether any reading in the record
carries an accuracy at all. This is screen 16's own rule — "no fix" and "a poor fix" are different
facts about the world although D6 treats them the same — applied to the screen that reports the
consequence.

Nothing was added to 04, 05 or 09. Growth charting reads measurements and only measurements
(`TreeMeasurement.isChartable` is its one gate), so a visit, a check-in and a care event lose
nothing by carrying a `nil`; a notice on those three would be a warning about a consequence that
does not exist.

**What the tests are.** `CypressTests/GPSAccuracyAtSubmitTests.swift`. Every warm-path assertion
passes either way — `MeasurementAccuracyTests` walks an accuracy end to end and was green against
this bug for the whole of its life — so each test here moves the fix *between* mount and submit and
asserts which of the two the record ends up carrying. One asserts the opposite direction: two
readings taken in one standing, either side of the fix improving, each keeping its own moment. That
one is the guard against a later round replacing the closure with a live value.

---

### E159 — Screen 04 lost its framing chips off the top of the display at the accessibility sizes

SCREENS 04 draws a `flex:1` viewfinder over a `flex:none` tray, with the framing chips and the
shutter as an `.overlay` on the viewfinder's bottom edge. That is drawn at the default type size and
at no other, and R14 is the ruling that says what the screen does at the rest of the ramp.

What went wrong is the overlay, not the tray. An overlay aligned `.bottom` pins its bottom edge to
the viewfinder's, so as the tray grows with the type ramp and squeezes the viewfinder shorter than
the overlay, the chip row grows **upward, off the top of the screen** — under the status bar and the
Dynamic Island, where it cannot be read and does not answer a tap. E152's feature, one session taking
a full tree, a trunk and a leaf, was not merely cramped at AX5. It was unreachable.

R14's answer: the viewfinder keeps a floor and the controls beneath it scroll. Three things it
deliberately left to be decided against the running layout, and what they were decided as.

**The floor is 524 pt on a 393 pt phone, and it is read off the capture rather than chosen.**
`VisitCameraController` sets `sessionPreset = .photo`, which is 4:3 on every iPhone, and
`VisitCameraPreview` sets the layer to `.resizeAspectFill`. A viewfinder `width` points wide
therefore shows the whole frame at exactly `width × 4/3`; taller than that and the preview crops the
sides, shorter and it crops the top and the bottom — and on a street tree the first thing off the top
is the crown. So the floor is the height at which the viewfinder stops showing the photograph it is
about to take, which is where R14's reasoning stops being comfort and becomes fact.

**The switch is `isAccessibilitySize`, and it is not a number of its own.** Measured on the running
app: the viewfinder is 583 pt at the drawn size, 550 at `xxxLarge`, 503 at AX1. The floor first binds
exactly where that predicate first turns true, so no second spelling of "large text" was invented.

**The shutter pins and the chips travel.** A person on this screen is holding a phone up at a tree,
and aiming and firing are one gesture: a shutter you have to scroll to find is a shot you lose your
aim to reach. It also costs a constant 68 pt at every text size where the controls' cost grows
without bound. The argument the other way, so it is on the record rather than lost: those points are
viewport the controls could have had, and once all three framings are photographed the shutter has
nothing left to do. Refused because the screen cannot know when a contributor is finished, and
because a control that is sometimes pinned and sometimes not is worse than one that always is.

The rule the variant follows, stated so the next person does not have to derive it: **the viewfinder
carries only furniture whose size does not depend on the type ramp** — the close button, the framing
corners, the shutter. Everything that grows with the ramp moves into the scrolling controls. The one
exception is the guidance pill, because with the chips moved down it is the only thing left saying
which framing is being aimed; it is top-anchored, so it grows down into the frame rather than off the
display, and it is hit-transparent.

`SCREENS.md` §3 · 04 now draws the result as screen 04's accessibility variant, per R14's own
instruction that whoever builds it leaves a spec rather than a precedent.

---

---

### E160 — The tests written for that variant could not run, and had never been run

Worth recording separately from the fix, because the fix was sound and the tests were not, and the
combination is the exact shape this project keeps catching itself in.

Two tests were written to host screen 04 and ask which control ended up on which side of the fold, by
**accessibility label**. Every one of those lookups came back empty. A hosted SwiftUI tree in an
off-screen window vends no accessibility elements at all: probed directly, a bare
`Button("Hello button")` inside a `UIHostingController` reports `accessibilityElementCount() == 0`,
and there are no elements anywhere in its hierarchy — SwiftUI builds that tree lazily for a real
assistive client, and a unit-test host is not one. So both tests failed on the first run they ever
got. They had been committed unreviewed after the agent writing them was killed mid-run, in the
window between writing them and running them.

The same helper had a second, independent fault. `firstScrollView(in:)` returned the first
`UIScrollView` in the hierarchy, and `UITextView` **is** a `UIScrollView` — screen 04's note field is
a `TextField(axis: .vertical)`, which UIKit backs with one, and it sits inside the controls. So the
helper answered "yes, the controls scroll" on the drawn layout, where they do not, and reported the
note field's origin as the viewfinder's floor.

Rewritten on geometry, which UIKit will answer for a hosted tree, and which is what R14's split
actually is: the viewfinder ends at its floor, the scroll view begins exactly there, and it holds
more than fits in it. **Which** control is on which side is verified by looking, per ARCHITECTURE §7
and exactly as `theChipRowFitsTheWidthItIsGivenAtAX5` already says of the row above it.

Two measuring traps found on the way, written down because both would have been read as the view
being wrong rather than the ruler:

- `UIHostingController` resolves a safe area even in a bare window and folds it into
  `sizeThatFits`. A phenology chip measured 83.67 pt tall where the layout draws it at 56.67, and the
  add-tree well measured 535 pt where it draws 481 — the same 54 pt of inset both times.
  `safeAreaRegions = []` is the fix and it is load-bearing.
- SwiftUI wraps a `ScrollView` in a `PlatformContainer` and positions *that*, leaving the scroll view
  at its parent's origin. `scroll.frame.minY` is therefore 0 on a scroll view sitting 524 pt down the
  screen; the measurement has to be converted into the root's coordinate space.

---

---

### E161 — The phenology chips on screen 04 were squeezed until their labels broke mid-word

Reported by the project owner: *"The photo check in labels are too narrow. Text gets all compressed
in them as they're currently implemented."* **At the default text size**, which is the part that
matters — this was not an accessibility-size defect.

The phenology row was an `HStack`, and an `HStack` compresses its children rather than overflowing
its proposal. A row wider than the space it is given does not spill off the phone; it squeezes every
chip below the width its own label needs, and the labels wrap. A curated deciduous species offers all
six tags, and six chips want about 537 pt in the 361 pt the tray leaves them. On a 393 pt phone at
`.large` the row read:

> `Leaf/out · Full/leaf · Flow/ering · Fruit/ing · Fall/colo/r · Bar/e`

Every label broken mid-word, one of them across three lines.

**Why it survived so long.** `VisitPhenologyVocabulary` offers this row "for the curated 40 and
nobody else" — a species needs a curated field-guide entry *and* a sourced `leaf_retention` before a
single chip appears. No preview and no fixture in the project had ever stood screen 04 over one of
the 40 with a habit on it, so every rendering of this screen the suite had ever made showed an empty
phenology row. The owner met it immediately, because London Plane is both one of the 40 and the
commonest street tree in San Francisco.

The fix is `CypressChipFlow`, the component the app's other three chip rows already use. The
mechanism was already written down in this codebase, in `VisitShotTypeChips`' own note explaining why
*that* row had stopped being an `HStack` — and that note even named this row as the place still doing
it, "which is what the phenology row below already looks like at AX5". It was wrong about one thing
only, and it is the thing that made this a live defect rather than a known rough edge: it does not
wait for AX5.

The row is now its own type, `VisitPhenologyChips`, for the reason `VisitShotTypeChips` already
established: a row whose geometry is the defect has to be hostable on its own, or the test guarding
it is a test of its parent.

---

---

### E162 — The "Add this tree" photo well was a landscape frame, so the viewfinder cropped the shot

Reported by the project owner: *"Add this tree photo window is still awkwardly horizontal and doesn't
capture full view on vertical orientation."*

"Still" is exact. #79 had already fixed the reported half of this — *"photo for custom tree should be
standard photo style, right now it's horizontal and cuts off vertical frame"* — by drawing the
captured still with `PhotoFit` instead of `scaledToFill`. That stopped the crop. It did not change
the **well**, and the well was the actual defect.

`VisitMetrics.AddTree.wellHeight` was `268`, and its own comment said what it was meant to be: "the
4:3 frame that photograph will be, at the gutter's width on the drawn 393 pt frame". 361 × 3/4 ≈ 271.
That is a 4:3 frame lying on its side. A phone held upright captures **3:4 portrait**, which at 361 pt
wide is 481 pt tall. One inverted ratio — dividing where the photograph multiplies — and the well had
been a landscape letterbox for its whole life.

What it cost, in each of the well's two states:

- **Live.** The well holds `VisitCameraPreview`, whose layer is `.resizeAspectFill`. A 3:4 frame
  filling a 361 × 268 landscape box is scaled until it covers, cropping 44 % off the top and the
  bottom. A volunteer aiming at a street tree could not see the crown they were framing. This is the
  half the owner's "doesn't capture full view" names, and it is the worse half: a viewfinder that
  does not show the shot.
- **Still.** After #79 the photograph was whole, but whole inside a box the wrong shape for it —
  drawn at 201 × 268 with a third of the well standing empty on either side.

The well now takes its shape from `Camera.captureAspectRatio`, inverted for SwiftUI's width ÷ height
convention, so the well and screen 04's viewfinder floor cannot drift apart: they are two views of
the same photograph, and that value is read off the capture path rather than chosen. It is an aspect
ratio and not a height, so the well is right on a phone this was never measured on.

**No cap, deliberately.** A maximum height would be a return to the letterbox by a smaller margin:
any well shorter than its own capture crops the live preview again, which is the defect. The composer
scrolls and the CTA is pinned outside that scroll, so a taller well costs scrolling, never reach.

One consequence worth naming, because the old behaviour had been written up as a feature. The code
argued that the jump from a filling viewfinder to a fitted still was intended — the frame "pulls
back" at the moment of capture and shows what the well was never going to show. With the well the
same shape as the capture there is no jump: fill and fit are the same drawing, and what you aimed at
is what you are shown. The old behaviour was a symptom being read as a design, and what it really
told a volunteer was that the viewfinder had been lying to them.

---

### E163 — Two of screen 10's four glyphs were drawn with path defects, not with the wrong geometry

Reported by the project owner walking the app on 2026-07-27: *"On share screen airdrop symbol is
malformed and link symbol looks weird."* Both marks are hand-drawn `Shape`s — this app has no SF
Symbols and no icon font (SCREENS.md §2 C16) — so there was no wrong symbol name to find. There were
two bugs in two paths, and both of them are the same class of mistake: a `Path` API that appends to a
current point being used as though it started a fresh one.

**AirDrop — two arcs joined by a chord.** `ShareAirDropArcs` drew its two concentric arcs in a `for`
loop of `path.addArc`, with no `path.move(to:)` between them. `addArc` appends to the current
subpath, so the second call first drew a **straight line** from the inner arc's right-hand end
`(16.9, 14.1)` to the outer arc's left-hand start `(3.4, 11.5)` — a chord clean across the mark.
At `1.8pt` that chord ran within a stroke-width of the inner arc for most of its length and the two
merged into a filled-looking blob with a spur out of the lower left. What the owner saw was not a
questionable mark, it was a broken one.

**The dot had already been moved to escape it, which is the part worth recording.** The dot was
offset `0.30 · side` *below* the arcs, under a comment stating that at 24pt a centred dot touches the
inner arc. It does not, and could not: the inner arc's nearest point to its own centre of curvature
is `radius − stroke/2 = 5.1pt` away and the dot's radius is under 2. What the dot would have touched
is the **chord**, which crossed 4.4pt above that centre. So a real defect was diagnosed in the wrong
element, and the repair — a full stop floating below the mark — was carried in the file as a
deliberate decision, with a reason that reads plausibly and is false. The dot is now at the arcs'
centre of curvature, where it belongs, and the chord is gone.

**The mark stays `arcs + dot`.** Apple's own AirDrop glyph is an upward triangle under the arcs, and
the fixed mark still reads closer to a wi-fi symbol than to Apple's. That is what SCREENS.md 10 §4
transcribes — `AirDrop` (arcs + dot) — and swapping the dot for a triangle would be changing a
transcribed description rather than drawing it, which is the design's call. Flagged here rather than
taken.

**Copy link — each cap swept a quarter turn instead of a half.** `ShareChainLink` is two capsule ends
on the box's leading diagonal, each an arm in, a half turn, and an arm back out, plus a bar on the
diagonal joining them. The upper cap was written `startAngle: 225, endAngle: -45`, which is a **90°**
sweep, not the 180° the construction needs: it stopped at the top of its circle instead of at the far
side of it, and the arm that followed was then drawn from that wrong point diagonally back across the
mark. The lower cap had the same defect mirrored (`45 → 135`). The result was two lopsided hooks each
with a stroke cutting through it, which at 24pt reads as a paintbrush — which is what the owner was
looking at. The arms' own endpoints were correct all along; the fix is the two sweeps and the two
points the second arm starts from.

**Neither defect was visible to the test suite and neither ever could be.** 819 tests pass over these
files; `ScreenSweepShots` photographs screen 10 in four appearances and asserts only that an image
came out. Both were found by cropping the 24pt icon well out of that image and looking at it.

---

### E164 — `Add a reading` sat in the Height box and opened the DBH form

Reported by the project owner the same day: *"'add a reading' is misleading because it's in a box for
Height … if adding a reading for height the height sub screen should open, not dbh."* Two defects
under one sentence.

**The routing was a plain bug.** `Route.measure` carried a tree id and nothing else, and
`MeasureDraft.kind` defaults to `.dbh` — SCREENS.md 16 §2's drawn selection. So every entrance to
screen 16 opened on DBH, including the empty `Height` stat card whose whole meaning is that this
tree has no height on it. A contributor entering from the Height box and typing a number without
looking at the segmented control wrote a **trunk diameter in metres**, and nothing downstream would
have caught it: `MeasurePresentation`'s sanity pill compares against previous readings *of the
drafted kind*, of which there were none. The route now carries a `MeasurementKind` and the profile
hands it the kind of the card that was tapped.

**The framing was a design question, and is answered in RULINGS R15.** A general "add any reading"
action was drawn inside a per-measure box and vanished once the tree had both measures, which left a
fully-measured tree with no door to screen 16 at all — E74's original gap, reopened for exactly the
trees that have most to record. R15 splits the two entrances: the empty stat slot stays 03's door for
a *first* reading of its own kind, and screen 11 gains E74's own named candidate — an `Add a reading`
control under the measurement log — as the door for a repeat one. R15 states what it overrules.

**The first fix passed a test suite that could not see half of it, and that is the part worth
keeping.** The tests written for the routing defect all stopped at `TreeProfilePresentation
.StatDestination`. One hop further on — `TreeProfileView.route(for:)`, a private instance method
turning that destination into a `Route` — was reachable only by the renderer. Rewriting that single
line as `case .measure: return .measure(treeID, .dbh)` reinstates the original defect exactly, and
the whole suite stays green while it does. Screen 11's new link had the same shape: its `Route` was
built inside a `Button` closure with a hardcoded kind.

The remedy was already in the codebase and is now applied to both: `MapHomeView.route(for:)` is
`static` and `PinSetDestinationTests` calls it directly, on the reasoning that a second copy of a
mapping is how a basin comes to open a tree's profile (E113). Both of screen 16's entrances are now
`static` mappings a test can call — `TreeProfileView.route(for:treeID:)` and
`GrowthHistoryView.route(forAddReading:)` — and the kind screen 11 opens on has moved out of the view
into `GrowthHistoryPresentation.addReadingKind`.

The general rule this is the third instance of: **a comment naming which layer owns a decision is not
a mechanism that makes the other layer honour it.** The comment on the line above this bug said, in as
many words, "which card means which kind is the presentation's call, not this view's" — and the view
was free to ignore it, because nothing could call the view.

---

### E165 — The map's species search matched a prefix, so "cypress" found one species of six

`SpeciesQueries.search` resolved a query against `seed.species` with a **prefix range scan** —
`name >= :q AND name < :q || U+FFFF COLLATE NOCASE`, over `scientific_name` and `common_name`,
unioned. It was written that way because BUILD-PLAN §6 specifies a trigram index on both names,
which Postgres has and SQLite does not, and the method's own comment recorded the resulting gap in
one line: "Trigram matching finds 'oak' inside 'Coast Live Oak'; a prefix scan does not."

That line understated it. The seed's common names are overwhelmingly `Adjective Noun` — the noun
being the word a person types. So the gap is not an edge case, it is the normal case:

| typed | the prefix scan found | the catalogue holds |
|---|---|---|
| `cypress` | 1 — `Cypress species / Cupressus spp` | 6 |
| `oak` | 1 — `Oak / Quercus spp` | 21 |

The project owner walked the app and reported the `cypress` case: *"I just typed in cypress and got
three hits across the whole city which seems like a bug? Should bring up all Monterey cypress not
just cypress spp."* Both halves of that sentence are worth separating, because only one of them is a
matching defect:

- **the misses** — Monterey, Italian, Leyland, Hinoki and Montezuma Cypress all carry the word in
  second position, so none of them matched. That is the defect.
- **"three hits"** — those were three *pins* of the one species that did match, inside the viewport,
  not three species. Screen 01's status line reports pins; nothing on it said how many *species* the
  query had resolved to, so a one-species narrowing that happened to draw three pins was
  indistinguishable from a three-species answer. The count was never wrong. It was answering a
  different question from the one being asked of it.

**The cap was not involved.** `MapSearch.speciesLimit` is 100 and `Page<Species>.maximumLimit` clamps
to the same, so nothing was truncated at six, or at one.

**Fixed** by matching a substring of either name, with a rank computed in the same pass — a name that
*starts* with the query outranks one where a *word* starts with it, which outranks the letters
appearing inside a word. So `cypress` returns the genus first, `Monterey Cypress` (the one curated
Cypress) second, and `oak` reaches `Coast Live Oak` while `Silkoak species` sinks to the bottom.

The leading wildcard forfeits no index, which is the part worth writing down because the objection to
it is otherwise correct: the range scan was **already** walking both name indexes end to end.
`COLLATE NOCASE` does not match the `BINARY` collation the seed's indexes were built with, so SQLite
could never turn the range into a seek — its plan said `SCAN … USING COVERING INDEX`, not `SEARCH`.
The new plan is the same two covering walks. Timings against the full seed are in
`.measurements/README.md` and `.measurements/species-search-108.txt`: the SQL goes from 0.08–0.25 ms
to 0.13–0.83 ms and the whole read is unchanged wherever the two return the same rows.

**What this newly exposes, and what was done about it (E38).** Matching anywhere makes the 100-species
cap reachable in ordinary use where it was not before: `a` prefix-matched 97 species and *contains* in
555. A truncated species set narrowing the map while the status line calls it "Showing 100 species" is
a page wearing a total's clothes. `MapSearch.Narrowed` now carries whether the catalogue returned a
full page, and `MapSearchCopy` says so in all four of the sentences it can produce.

**Two things moved with it, because the change made them untrue.** `SpeciesPickCopy.noMatch` told a
contributor "Nothing in the catalogue starts with …. Try the first word of either name", which now
sends them to retype a query that already worked. `DataGates`' species-search assertion checked that
every match had a name *beginning* with the query.

**What is still not fixed.** This is substring matching, not the trigram matching §6 specifies: a typo
misses, and so does a name the catalogue spells differently. That still wants an FTS5 index the seed
does not carry, and it still belongs in `Tools/build_seed.py` beside the data rather than being built
on device at first launch.

**One more sentence went wrong on the way, and the simulator is what caught it.** With "cypress"
resolving to six species instead of one, screen 01 drew **"No 6 species in view"**.
`MapSearchCopy.subject` names one or two species and *counts* anything beyond that, and `status` was
substituting that one phrase into four sentences of which only one takes a count. It was latent
before this change — a genus like `Quercus` prefix-matched seventeen species and read "No 17 species
in view" the same way — and became the ordinary case the moment one common word started matching six.
The counted forms now carry their own article and the sentences around them branch.

---

---

### E166 — The search bar had no clear control, and no *visible* way out of the keyboard

Task #110, two owner reports about C20: *"it's possible to get stuck in the search bar — cursor active
and no way to exit out of keyboard"*, and *"I want a little x in far right of bar to clear contents"*.

`SearchBar` was a `TextField` and a `Shape` in an `HStack` with no clear button, no `submitLabel`, no
`FocusState` and no `scrollDismissesKeyboard`, and its only map caller added none of them.

**The first report is not literally true, and the correction is the point of this entry.** There was
no keyboard trap. Measured on the simulator against the component exactly as it shipped — no
`FocusState`, no `submitLabel`, no `onSubmit` — pressing return already resigned focus, because that
is SwiftUI's default for a single-line `TextField`. A UI test written to prove the return key had
been *fixed* passed against the *unfixed* component, which is how this was found; the test was
asserting the platform's behaviour rather than the app's, and has been deleted rather than kept.

The defect is real but it is **discoverability, not capability**. The key that worked said `return`,
which reads as "insert a newline"; nothing else on screen 01 dismisses the keyboard, because an
`MKMapView` does not resign anyone's first responder and a tap-catcher over it would take the pan and
the pinch with it; and the keyboard covers the FAB, the bottom card and the tab bar while it is up.

Fixed by relabelling the key that already worked (`submitLabel(.search)` → `Search`) and adding a
`Done` above the keyboard, plus the ✕ that genuinely did not exist — trailing edge, VoiceOver label
`Clear search`, 44 pt target, drawn as a `Shape` like every other glyph in the app. Recorded as
ruling **R15**, since SCREENS.md §2 specifies neither affordance (DECISIONS constraint 21).

---

### E167 — The search UI tests depended on the machine's last `simctl location`, and the guard that was supposed to notice could not fire

Tasks #104 and #101. Two defects in `CypressUITests/MapSearchUITests`, filed separately and fixed
together because they are one mistake: **a test depending on ambient machine state it never states.**

**Neither is a product defect.** Screen 01 does the right thing in every state described below,
including the one the red test was actually finding. What was wrong was what the tests knew.

---

**#104 — "intermittent and unexplained" was neither.**

`testTypingASpeciesNameNarrowsTheMap` typed `Platanus` — the London Plane, the commonest street tree
in San Francisco — and asserted the map was not empty afterwards. Its guard, `requireAMapWithPins`,
only checked that the map had drawn *some* pins. "Some pins are drawn" and "this viewport holds
London Planes" are claims about different sets, and over most of the city they disagree.

Measured on this branch, twice, minutes apart, with no code change between:

| simulated fix | trees in the opening viewport | London Planes | result |
| --- | --- | --- | --- |
| `37.7505,-122.4950` (Sunset Blvd at 37th) | 264 — 95 Monterey Cypress, 52 Monterey Pine | **0** | red: `narrowing … emptied the map` |
| `37.78485,-122.4215` | 156 | **47** | green |
| location revoked outright (opens on Dolores Park) | pins drawn | **0** | red |

The counts are from the seed, queried directly against a 120 × 261 m box at each fix —
`MapLayout.defaultSpanMetres` on this phone's aspect — rather than inferred from pin counts. The
map's settled viewport is slightly wider than that box, so the pins it draws run a little above these
numbers (56 planes drawn at the second fix against 47 in the box); the zeroes are the load-bearing
part and they are zero either way.

So the failure is deterministic in whatever `xcrun simctl location` the device was last left at —
which no code in the file read, no failure message mentioned, and every agent had set differently.
That is why it read as a flake across three machines.

Two traps that kept it hidden and are worth writing down: `xcrun simctl location <udid> clear` does
**not** unfix a device (the app keeps the last fix; revoking the app's location grant is what
unfixes it), and a *streaming* route started with `simctl location <udid> start` persists across
runs and appears in no failure message.

**Fixed by asking instead of assuming.** The map already colours the commonest few species among the
pins it has drawn and puts their names on those pins' accessibility labels (`MapSpeciesPalette`,
`MapPinKind.accessibilityLabel(for:palette:)`). So the test reads the viewport's own census, types
the name of a species that is provably on this screen, and watches a second one disappear while the
first survives. It hardcodes no species, no coordinate, and no assumption about where the map opens
— which matters twice over, because task #115 is changing that. Picking a coordinate that holds
London Planes today was rejected: it is the same defect with a longer fuse.

---

**#101 — a guard that could not fire.**

`requireAMapWithPins` was written as a GPS-fix detector, on the stated grounds that "screen 01 opens
on the user when it has a fix and on the whole city when it does not, and the whole city is zoom ≤ 15
— A1's clustered side: badges, not individual pins."

Every clause after the first is false. Screen 01 opens at `MapLayout.defaultSpanMetres` — 120 m
across — with a fix and without one; only the centre differs, and the fixless centre is
`MapLayout.defaultCentre`, Mission Dolores Park. 120 m is far inside A1's pin threshold, so the
clustered whole-city view the guard was watching for is a state launch cannot produce.
`AlmanacGroupTapTests` had already measured this and written it down against this file by name.

Confirmed here: with location revoked for the app, **five tests ran and none skipped** — and the
narrowing test still failed. The guard stood in front of two tests, certified a precondition it could
not check, and one of them then failed for the exact reason it had just certified absent.

A guard that cannot fire is the same defect as a test that cannot fail, which this file has retired
once already (the return-key test under E166). It now guards what
`testAWordNoSpeciesMatchesSaysSo` actually needs — pins to watch go away, which a viewport over a
park or the ocean legitimately does not have — and its skip message says that instead of prescribing
a GPS fix.

---

**The product behaviour the red test was actually finding, checked on the device rather than read off
the source.** The obvious suspicion is that a search narrowing to zero visible pins draws an empty map
and says nothing — which would be a real defect, and the one worth finding here. It does not. Typed
into a running build at `37.7505,-122.4950`, `Platanus` empties the map and draws, under the search
bar:

> None of the 11 matching species are in view

`MapSearchCopy.status`' `matched == 0` branch, in its counted form — eleven because matching has been
`LIKE '%query%'` over both names since E165, and E38's rule that a page must not wear a total's
clothes applies to the species set as well as the trees. Naming the *viewport* rather than the query
is deliberate: it tells the reader to move the map rather than doubt the spelling.

So the empty map was never silent, and there is no product defect behind #104. What there was is a
test that could not tell that state from a broken one — it read "no pins" and reported "broken",
which is exactly the mistake the app's own copy exists to stop a *person* making.

### E168 — The map kept its own copy of the camera, and every write to it was thrown away


The owner: *"Opening the app should open on where you're located right now, 100% of the time."*

Reproduced on the simulator with location granted and a fix set over Van Ness: screen 01 opened on
`MapLayout.defaultCentre` — 37.7596, −122.4269, Mission Dolores Park — and stayed there for the life
of the launch. Not for a second before CoreLocation answered. Permanently, with the fix already on
`location.availability`.

`AlmanacGroupTapTests` had recorded half of this in its own header and read it the other way round:
*"the control reads `Not centred` for a whole 39-second run, and a screenshot of that same launch has
the camera on the fix and the reader's blue dot in the middle of the screen. Something between the
settled region and `MapRecentre.Camera` disagrees with the picture; whatever it is, it belongs to
screen 01 and not here."* It did belong to screen 01. The control was telling the truth; both
sentences were about a map that had never moved, and the screenshot came from a launch where the
timing happened to go the other way.

**The camera request was thrown away, not never made.** A probe in the layer itself, on a cold launch:

    MAKE   seq=0 bounds=(0.0, 0.0) to=37.7596      ← makeUIView, zero frame, asks for the fallback
    MADE   region=37.3346                          ← MapKit did not take it; 37.3346 is its own default
    APPLY  seq=1 bounds=(402.0, 874.0) to=37.7599  ← the fly-to-you, applied at full size, in a window
    REJECT seq=1 applied=1  ×∞                     ← and every pass after it, forever

A freshly constructed `MKMapView()` has `bounds == .zero`; SwiftUI lays it out afterwards. `setRegion`
on a map with no area does not take — measured, the region set to 37.7596 read back as 37.3346 — but
`makeUIView` recorded the ticket as applied anyway. So the request minted by the first GPS fix was
already stale by the time there was a map to show it on, and it was dropped. There is no retry:
`MapHomeView.hasCentredOnUser` is a one-shot (#85) and had already fired.

`MapCameraRequest`'s ticket is not at fault and is not weakened here. E140 established that camera
*geometry* cannot be compared because an update pass can arrive carrying state from before the
reader's last gesture. What was wrong is that a number was spent on a camera nobody was shown.

**The fix.** `applyCameraIfChanged` refuses a map it cannot aim, without spending the ticket — the one
early return in that method that does not record the request, because it is the one case where the
camera has not been superseded and has not been seen. `makeUIView` no longer sets a region at all.
`AimableMapView` supplies the single layout hook a `UIViewRepresentable` does not have, and aims at
whatever the app wants *by then*: the remembered opening camera if no fix has landed, the reader's own
location if one has. Both orders arrive at the same place.

**On screen 01, that hook has never once been the thing that aimed the map.** Measured on every cold
launch traced: `updateUIView` reaches `applyCameraIfChanged` before the deferred `onFirstLayout`
callback does, so by the time the hook runs the ticket is spent and it logs `REJECT`. Screen 01
re-runs its body often enough to produce its own pass the instant the size lands, exactly as the note
above guessed it would. The hook earns its place on the two quiet screens and as belt-and-braces here;
it should not be described as what closed this defect on the app's default screen, because it is not.

**A second road to the same defect, closed at the same time.** `MapLocationProvider` is the
composition root's, shared with screens 09, 12, 16 and the visit flow, and `RootView` wires
`onRequestLocation: { location.start() }` in three places. Arrive on screen 01 after any of them and
`availability` is already `.located` — so `.onChange(of:)` never fires, because the value never
changes. The one-shot is now also called from `.task`, and `centreOnUserIfNeeded()` is the single
place that decides.

---

#### The regression this fix introduced, and how it hid

Worth more than the original defect, because it is the class of bug this project keeps finding: **a
value that looks answered and is not.**

`MapHomeView.region` — the app's copy of where the camera is — held MapKit's own default for the
whole launch:

    region 37.1328,-95.7856   span 98.0°×61.3°

That is the geographic centre of the continental United States, sitting behind a map of Folsom Street
with the reader's blue dot in the middle of it. Everything downstream of the settled camera was
reading it: the recentre control's `Centred on you` (#100), a cluster tap's "two zoom levels in"
measured from a 98° span, and the camera this app now remembers between launches — which is why
nothing was ever written down.

**The first fix for this named the wrong mechanism, and the wrong one was ruled out by measurement.**
It said that aiming from inside `layoutSubviews` is re-entrant, that `setRegion` is honoured but
`regionDidChangeAnimated` "is never delivered", and it moved the aim to the main queue. The symptom
survived that change untouched. A probe in the layer itself, cold launch, iPhone 16 Pro, static fix at
37.7599, −122.4148, timestamps in milliseconds:

    .802 .838 .850  apply  REFUSE-no-area seq=0
    .857            settle region=37.132840 span=97.992432
    .870            apply  ACCEPT seq=0 to=37.759600
    .870            settle region=37.759600 span=0.002084
    .871            apply  WROTE parent.region=37.759600 readback=37.132840
    .875            layoutSubviews bounds={{0, 0}, {402, 874}}
    .885            apply  REJECT seq=0 applied=0
    .907            centreOnUserIfNeeded avail=located(37.7599, −122.4148)
    .907            flyTo 37.7599,-122.4148 metres=120
    .909            apply  ACCEPT seq=1 to=37.759900
    .915            settle region=37.759900 span=0.002084
    .916            apply  WROTE parent.region=37.759900 readback=37.132840

**The settle is delivered.** Twice, carrying exactly the right region. It was never suppressed. What
that trace shows instead is that the settle arrives in the *same millisecond* as the `setRegion` that
caused it — MapKit calls `regionDidChangeAnimated` synchronously from inside `setRegion` — and
`applyCameraIfChanged` is called from `updateUIView`. So both writers of `region` were running inside
a SwiftUI view-update pass, and **a `@State` write made during a view update is discarded.** The one
write that landed in the entire launch is the settle at `.857`, the only one that happened outside a
pass — and what it carried was MapKit's default. That is the number that stuck.

`Coordinator.echo(_:)` hands every camera back one runloop turn later, and is used by **both** writers
rather than only the one known to be unsafe today: the settle is synchronous under `setRegion` and
asynchronous after a real flight, and a value whose correctness depends on which of those happened is
a value that will be wrong again.

Verified on the running app, nothing pressed, launch state: `R 37.7599,-122.4148 S 0.00108 centred`.

**How it hid.** The whole unit suite was green. The map looked right in every screenshot. The camera
tests assert `mapView.region`, which is the truth, and the one thing that was wrong was the *copy* of
it the screen holds. It was found by launching the app with a debug readout of `region` drawn on top
of the chrome and reading the numbers — not by a test.

**What each test is now measured to catch.** Two deliberate breaks, built and run against
`CypressUITests/MapCentredStateUITests` on a simulator with a fix:

| Break | Result |
|---|---|
| baseline, fixed | `Executed 2 tests, with 0 failures` in 10.979 s |
| write `parent.region` inline instead of through `echo(_:)` — the real defect | `Executed 2 tests, with 1 failure` in 31.890 s — `XCTAssertEqual failed: ("Not centred") is not equal to ("Centred on you")` |
| aim re-entrantly from `layoutSubviews` (`announce?()` inline) | `Executed 2 tests, with 0 failures` in 11.082 s — **invisible** |

Two things follow, and both are worth more than the green line.

**The re-entrancy break is invisible because there is nothing to see.** On screen 01 the
`onFirstLayout` hook never applies a camera at all: `updateUIView` reaches `applyCameraIfChanged`
first on every launch and spends the ticket, so the hook only ever logs `REJECT` (line `.885` above).
No test guards it because no behaviour depends on it.

**Say this plainly, because the comment above it does not read that way.** `AimableMapView`'s
`DispatchQueue.main.async` carries a long, careful, confident note about re-entrancy, and the next
person to read it will assume it is load-bearing. On screen 01, as currently wired, **it is dead in
practice** — the whole hook, not just the hop. Mutating it either way changes no observable behaviour
and no test.

**It should nonetheless stay, and the reason changed during this round.** When it was written it was
insurance against a screen too quiet to produce another `updateUIView` pass once the size landed —
speculative, and on the one screen anybody measured, unnecessary. It stopped being speculative when
`mapViewDidChangeVisibleRegion` was gated on `appliedSequence != nil` (below): with that gate, a map
that is never aimed never reports a camera at all, so screen 01 would never fetch a tree and screen
16's pin would never track. The hook is now the thing that guarantees the aim eventually happens, and
that is a real job. Its note has been rewritten to claim that job and not the other one.

**Under the real break, the *pressed* test still passes.** A press produces a genuine animated flight
whose settle arrives outside the update pass and therefore lands. That is the entire content of "still
`Not centred` at launch, and a press fixes it": it is one bug, not two, and the unpressed test is the
only one that can see it.

`MapOpeningCameraApplyTests.theSettledRegionIsEchoedBack` pins that the echo exists — delete the write
and it fails — but it cannot see either break, because a map view outside a window and outside a
SwiftUI update pass reproduces neither condition.

---

#### The second regression this fix introduced: a pin 2,300 km from its tree

Worse than anything above, and it is the fix's own doing rather than the original defect's.

Two of the changes made for E168 are individually correct. `makeUIView` no longer sets a region, and
`applyCameraIfChanged` refuses a map with no area without spending the ticket. Together they open a
window that did not exist on main, where the camera was set in `makeUIView` at the earliest possible
moment: **between construction and the first laid-out pass, the map has never been aimed at all**, and
what `MKMapView` reports as its visible region in that window is its own default — 37.1328, −95.7856,
span 98°.

`mapViewDidChangeVisibleRegion` fires during that window and reports it.

On screen 01 that was invisible and nearly free: one wasted fetch over a bounding box the size of
North America, discarded by `MapModel.cameraDidChange` as soon as a real camera arrived. On **screen
16** it is not free at all. `VisitPinAdjustView` follows this callback directly — its whole design is
that the map moves under a fixed reticle and the pin *is* the middle of the map:

    onCameraChange: { box, _ in … pin = VisitPinAdjust.centre(of: box) }

So the pin a contributor is about to attach to a tree they are standing next to was being dragged to
the middle of Kansas before they touched anything. Measured on merged main in clean derived data:

    testPinAdjust                             failed (18.685 s)   hittability: activation point invalid
    testTheNudgeControlsActuallyMoveThePin    failed  (9.009 s)
    testThePinSaysWhenItHasGoneAsFarAsItGoes  failed (12.416 s)
        XCTAssertEqual failed: ("2344980 m east of where you are standing.")

2,344,980 m observed, against a great-circle distance of **2,343,915 m** from the fix to MapKit's
default centre. A 0.05 % match is an identification, not a resemblance. The first of the three fails
differently only because a pin in Kansas has no activation point on a map of San Francisco.

**The gate.** `mapViewDidChangeVisibleRegion` now returns unless `appliedSequence != nil`.
That property is exactly the question "has this layer ever aimed this map", and the callback's
contract is *the app moved the camera, here is where it is now* — a camera nobody asked for has no
business travelling through it. All three tests pass with the gate and fail without it, which is the
red-then-green this entry is entitled to claim.

**Two lessons, and the second is the one worth carrying.** The first is ordinary: a fix that makes a
value arrive *later* has to be checked against everything that reads it *earlier*. The second is that
this branch's own tests could not see it. Screen 01 is where all the attention went, and on screen 01
the same defect is a rounding error in a database query. It surfaced only because screen 16 happens to
wire a user-visible artefact straight to the same callback — and it surfaced as three red tests that
were initially, and wrongly, written off as derived-data contamination.

---

#### Where the map opens now, and what it says about it

**Opening on the reader is only two thirds of "100% of the time", and the third part is the one that
gets skipped.** There is a window before CoreLocation answers, and there are states where it never
will, and in every one of them the map is showing a piece of San Francisco that is not where the
reader is standing. ERRATA **E126** governs: a screen showing something other than what you asked for
must say why. **E158** is the warning — screen 11 spent its life telling people their GPS fix was
"too weak" when their phone had merely not answered yet, and the cold-launch population was the
*entire* population of that message.

`MapCameraMemory` remembers the camera the reader last left the map on. A place they have actually
been beats a stranger's park: the app reopened in the same neighbourhood is very nearly right, and
Dolores Park survives as the answer to the one question nothing else can answer — a first launch, no
history, no fix. `UserDefaults` rather than `app_state`, for `VisitSaveLedger`'s reason (a UI fact,
not a contribution) and one that decides it outright: `CypressStore.appState(_:)` is `async`, and a
camera that arrives one `await` after the first frame is the defect performed slightly faster.

The write is **not on the pan path**. Tasks #51, #75 and #84 were all map performance and #84 was the
basemap re-evaluating some 200 times a second at rest; a settle updates a struct in memory and the
write happens once, when the app leaves the foreground or the screen goes away. There is no debounce
timer to tune. `noteDoesNotWrite` asserts it: fifty settles, nothing in storage.

Four standing states now, and no two of them read the same:

| State | What the map shows | What it says |
|---|---|---|
| `located` | the reader | nothing — there is nothing to explain |
| `notAsked` | remembered camera, or the city | **Cypress has not been given your location.** Nothing has answered the location request yet, so there is nowhere to centre the map. + where it is |
| `waitingForFix` | remembered camera, or the city | **Finding you.** Cypress has permission and is still waiting for a first fix. + where it is + it will move as soon as one arrives |
| `denied` / `servicesOff` | remembered camera, or the city | **Location is off** / **Location Services are off.** The map still works—it just cannot show where you are… + where it is |

Two things about that table. The last row's two titles were already distinct (`MapLocationCopy.title`)
and stay so. And every row carries a clause naming **what the reader is looking at instead** — "The
map is where you last left it" or "The map is over the middle of the city" — which is the half of E126
that was missing. The old sentence explained the absence of the dot; it said nothing about the presence
of a particular stretch of city, and a reader who has never been to Dolores Park was left to assume
the app thought they were there.

The two waits are given `MapOpening.patience` — three seconds — before they say anything, because a
notice that flashes on every healthy launch teaches the reader to stop reading the slot it appears in.
The refusals are said at once: nothing is coming, so there is nothing to be patient about.

##### Which of those four a simulator can actually produce

Driven on the running app rather than reasoned about, iPhone 16 Pro, one screenshot each.

| Asked for | `simctl` | What appeared |
|---|---|---|
| fix present | `privacy grant location` + `location set 37.7599,-122.4148` | map on Folsom & 9th, dot dead centre, **no notice**, control filled and reading `Centred on you` |
| permission revoked, no history | fresh install + `privacy revoke location` | Dolores Park, **Location is off** + "…The map is over the middle of the city." + Settings, control struck through |
| permission revoked, with history | as above, after one granted launch was backgrounded | **Folsom & 9th**, no dot, **Location is off** + "…The map is where you last left it." |
| never asked | fresh install + `privacy reset location` | Dolores Park, system sheet up, control in the plain `askable` drawing |

**`waitingForFix` is not reachable on a simulator, and that is a property of the design rather than a
gap in the testing.** Two things were confirmed by driving it. First, `xcrun simctl location <udid>
clear` does **not** unfix a device: on a fresh install with permission granted and the location
cleared, the map still opened centred on the fix with the dot in the middle — the only way to take a
fix away from the app is to take the *permission* away, which produces `denied`, a different state
with different copy. Second, `simctl location <udid> list` offers only City Run, City Bicycle Ride,
Freeway Drive and Apple; there is no no-fix scenario. And even if there were, `MapOpening.patience`
gates the notice at three seconds and a simulator answers from cache in well under one, so the
`searching` sentence is by construction only ever shown to a phone that is genuinely slow. That is
E158's lesson working as intended, and it means the row is exercised by
`CypressTests/MapOpeningCameraTests` and by nothing on a device.

**The remembered camera was verified end to end, and only works because of the fix above.** After one
granted launch was backgrounded, `UserDefaults` held:

    map.lastCamera = (37.759899, -122.414803, 0.001081, 0.001362)

Before the echo was repaired, `region` held a span of 98°, which `MapCameraMemory.isWorthRemembering`
correctly refuses as wider than `maximumSpanDegrees`. So nothing was ever written, on any launch, and
the third row of that table could never have been reached. Repairing the echo is what made the memory
real.

---

#### #128, tested on this branch: the ticket is inverted, and the real defect is #85's shape

Reported by the owner walking the app: *"Going Map > Journal > Map, you land NOT where you're
actually located when you go back to map, which shouldn't happen."*

Driven on the device rather than reasoned about, on this branch, with a fix at 37.7599, −122.4148.

**As worded it does not reproduce.** Map → Journal → Map with the camera untouched lands on Folsom &
9th with the reader's dot dead centre and the control reading `Centred on you`. You land exactly where
you are located, which is what the ticket asks for.

**What does reproduce is the opposite, and it is worse.** Pan the map away first — south to Folsom &
20th, the dot off screen, the control correctly reading `Not centred` — then Journal, then Map. The
map is back on the reader, dot dead centre, and **the pan is gone**.

That is #85's shape returning through a door #85 did not close: "the map snaps back to your location
and cannot be panned away". The mechanism is not the `@State` discard this entry is about, so
`echo(_:)` does not fix it and was not expected to.

Two things are true and only one of them is the cause. A pan is a *gesture*: it moves `MKMapView`'s
camera and mints no `MapCameraRequest`, so `MapHomeView.position` still holds the last request the app
made and the reader's pan is never represented in any value that survives the tab. That is the
standing hazard. But the thing that actually re-aims the camera is simpler and is exactly what the
guard rail names: **`hasCentredOnUser` is `@State` on a tab root that SwiftUI rebuilds**, so returning
to the tab resets the one-shot, `.task` runs `centreOnUserIfNeeded()` again, it finds a fix, and it
mints a *fresh* fly-to. The map re-centres on every appearance. `#85` closed that for later fixes
arriving within one visit; it did not close it for a second visit.

Both readings agree the view's state was rebuilt, which is what the observation shows; whoever fixes
it should confirm which of the two drives the camera before choosing where to put the flag.

**It is almost certainly not this branch's.** On main, `makeUIView` called
`setRegion(position.region, animated: false)` on the same stale request for the same reason. This was
**not** verified by running main — it is read off the two versions of the file, and should be treated
as inference until somebody runs it.

Recorded and not fixed here. The fix is a real design decision — what a fresh map view owes a request
it has never applied but that has already been superseded by a gesture — and it interacts directly
with E140's ticket rule and with #85. It should not be bolted onto a merge about the opening camera.

---

#### The suite, on merged main, at the end of this round

iPhone 16 Pro, private derived data, location granted with a fix at 37.7599, −122.4148.

    Test run with 899 tests in 85 suites passed after 101.468 seconds
    Executed 42 tests, with 1 test skipped and 2 failures in 411.356 seconds

The unit suite is clean — no issues at all, #123's `VisitCameraSessionTests` red having landed on main
as E171.

**The one skip is structural and cannot be fixed in the test.**
`MapRecentreUITests.testPressingItWithLocationDeniedExplainsRatherThanDoingNothing` needs location
*denied*; `MapCentredStateUITests` and `MapSearchUITests` need it *granted with a fix*. Both are set
outside the test process by `simctl privacy`, so one invocation on one simulator can exercise the
granted paths or the refused one, never both. Whichever way the machine is set, something skips and
the run is still green. The fix belongs to how the suite is invoked — a second pass with location
revoked and `-only-testing` on the refusal tests — not to any file in it. Worth knowing before
trusting a green here, and worth knowing that three UI test files each document a *different*
`simctl location` in their own headers (37.7599,−122.4148; 37.78485,−122.4215; and, implicitly,
`MapLayout.defaultCentre`), so no single device fix satisfies all of them.

**The two failures share one cause and it is not the camera.** Both are XCUITest refusing to resolve
hittability of a map pin:

    Failed to determine hittability of "City tree, Southern Magnolia" Button:
    Activation point invalid and no suggested hit points based on element frame

They are `AccessibilityTreeTests.testNoUnlabelledButtonsOnLaunch` and
`DeepLinkVoiceOverTests.testPinAdjust`, and both reach it through a helper that walks every button on
screen and asks `isHittable`. It is **intermittent**: across three clean runs on this branch the first
of them failed, passed, and failed. Whether it predates this branch was **not established** — it would
take a run on main with the same device fix, which was not done. What can be said is that #115 working
changes what that helper walks: the map now opens on the reader's own street with a screenful of pins
rather than on a park with almost none, so a walk over ~290 annotation views is now the normal case
rather than the rare one. That makes this branch a plausible aggravator of a pre-existing fragility,
and an implausible cause of a new one.

---

#### #100 was not the defect it was reported as

Reported as: the recentre control's accessibility state does not track whether the map is centred, so
VoiceOver announces the wrong thing.

Measured first, before changing anything. `MapCentredStateUITests.testTheControlSaysCentredOnceTheMapIsOnYou`
— launch, press the control, poll the spoken value — **passed on unmodified code**, so the pure
decision `MapRecentre.engagement(availability:camera:)` was never the fault. The reported defect, as
worded, does not exist.

But the conclusion first drawn from that green — "the wiring from `MKMapView`'s settle through
`MapHomeView.region` to `MapRecentre.engagement` was intact" — is **wrong, and it is wrong in the
direction that matters.** The wiring was severed; the press is simply the one path that survives it.
A press produces a real animated flight, its settle arrives outside the SwiftUI update pass, and the
write lands. Every camera the *app* sets on its own — the opening one, the fly-to-you — is applied
from inside `updateUIView`, and those writes were being discarded. So the control's spoken value was
false for the entire life of every launch nobody touched, and pressing it repaired the value as a side
effect of repairing the camera.

That is why `AlmanacGroupTapTests` could record `Not centred` for a 39-second run *and* a screenshot of
that same launch with the dot in the middle of the screen. Both observations were correct and they
were not in tension: the picture came from `MKMapView`, the sentence came from the app's discarded
copy of it. `Not centred` was not "a true statement about a map that had never moved" — the map had
moved, and the sentence was simply false.

So #100 as filed is one symptom of #115's second defect (E168), and fixing that fixes it. The witness
is `MapCentredStateUITests.testTheMapOpensOnTheReaderWithoutBeingAsked`, and the break table above
shows it going red with exactly the reported words while the pressed test stays green.

What was genuinely wrong is narrower and is still an accessibility defect. `Engagement` had three
cases and `away` carried all of "I know where you are and the map is not there", "nobody has answered
the permission ask" and "I am still looking" — and `MapRecentreCopy.value` spoke one word over all
three: `Not centred`. For a sighted reader that is a caption on a picture they can also see. For a
VoiceOver reader it is the *entire* report on where the map is, and in two of the three states it
describes a relationship that does not exist: there is no "centred" to be short of, because the app
does not know where the reader is, and pressing will not move the camera at all — it will raise a
permission sheet, or promise a move later.

So it is E126 arriving at the one control whose whole purpose is that no press is ever silent, and the
fix is five cases where there were three: `centred`, `away`, `askable`, `searching`, `unavailable`,
each with its own spoken value and its own hint about what the press will do. The *drawing* is
unchanged — `askable` and `searching` still look exactly like `away` did, because a control that
changed colour while CoreLocation thought about it would be flicker with no information in it, and
only `unavailable` is struck through. `engagementTracksThePress` holds the shape: every availability
that presses differently now describes itself differently.

### E169 — The seed said "empty planting site" where the source said nothing, and nobody could count it

`Tools/build_seed.py` decided what every record in the corpus *was* with one line:

```python
status = "vacant_site" if kind == "placeholder" else "alive"
```

where `placeholder` meant *the species string did not parse*. There was no field anywhere in the
ingest in which a source could state what a record was, so the builder inferred it from the absence
of something else. That produces two errors at once, and both are in the shipped seed.

**A source that omits a species describes an empty hole in the pavement.** In the DataSF corpus
**1,777** of the 12,518 vacant planting sites are ours, not the export's: their `qSpecies` is blank
(`::`, 1,657 rows) or reads `Tree :: Tree` (131). **1,326 of the blank ones carry
`qLegalStatus = DPW Maintained`** — the city saying it maintains a street tree at that address —
and our map draws a planting site there. The remaining 10,741 are genuine: `Tree(s) ::` on a
`Permitted Site` and the literal `Potential Site` are the source describing a site, and those are
correct.

The shipped `--source city` seed has 153 vacant sites of its own, on rows the city layer lists with
`PlantType = 'Tree'`. Their split between stated and inferred was **not measured** — it needs the
layer's species text, and the cached extract is absent from this machine — so no number for it is
recorded here.

**A source that names a shrub describes a street tree.** `Shrub :: Shrub`, `Private shrub` and
`Privet` are the city telling us, in the only field it has, that the thing growing there is not a
tree. `trees.status` has no value for that, so they ship as `alive` with no species: **85** rows
under `--source city`, **312** under `--source datasf`.

Neither number existed before. Both were inside `vacant_site_rows` and `non_taxon_rows`,
indistinguishable from the rows that are correct.

**Fixed in shape, not in rows.** `Tools/inventory_contract.py` requires every record to state its
`kind` (`tree` / `planting_site` / `not_a_tree`) and its `kind_basis` — where
`inferred_from_absent_species` is spelled that badly on purpose. `build_seed.STATUS_FOR_KIND` is
the one place the contract's vocabulary meets the seed's, and `not_a_tree` maps to `alive` there
with the reason written on it. The build receipt now carries
`planting_sites_stated_by_source`, `planting_sites_inferred_from_absent_species` and
`records_not_a_tree`, so the size of the defect is a number in the file.

**No row moved.** `--source datasf` built by the code on `main` and by the refactored code over the
same 198,435-row export produces the same sha256 (`8958e758…`), the same `sf_species_map.csv` and
the same `schema.sql`; after the receipt keys were added the five tables still hash identically and
`seed_meta` differs by exactly six added keys. Correcting the 1,777 and the 312 changes the corpus
and belongs to #94.

### Three counts in the #94 brief did not describe the shipped seed

- **"318 shrubs are called street trees."** 318 is the DataSF corpus's `plant_type = 'Landscaping'`
  population, of which 166 are already `vacant_site` and 152 are `alive`. The shipped `--source
  city` seed holds 166 `Landscaping` rows and **every one is a vacant site**. The rows that really
  are shrubs-called-trees there are a different population — the 85 above, found by species text
  rather than by `plant_type`.
- **"12,413 vacant planting sites are called street trees."** They are `status = 'vacant_site'`, a
  value of their own, and `TreeProfileDestination` already redirects them off the tree profile
  (`VacantSiteRedirectTests`). The defect is the copy that calls all 145,837 rows street trees, and
  separately the 153 that are not vacant at all.
- **The defect runs both ways.** The brief describes only vacant-sites-called-trees. The larger and
  less visible half is trees-called-vacant-sites, which nobody had counted.

### Two schema blockers for #107, reproduced rather than predicted

Neither is a defect today — one city, one id space — and both are hard failures the first time a
second city is ingested. **Whoever picks up #107 should read this entry before writing an adapter,
because both bite during the ingest, after the rows are built.** Reproduced against the shipped
seed's own `CREATE TABLE trees`, pulled from its `sqlite_master`, with San Francisco's TreeID 276198
already inserted:

**Blocker 1 — `external_ref INTEGER UNIQUE` is a global constraint on a source-local id.**
Los Angeles TreeID 276198 is a different tree with a different uuid, and it cannot be a row:

```
sqlite3.IntegrityError: UNIQUE constraint failed: trees.external_ref
```

The uuid derivation is already safe — `ID_SPACES[<space>].identity_prefix + source_ref`, verified
over all 145,837 shipped rows — but the column is not. The fix is to widen the index to
`(id_space, external_ref)` or to store the qualified string. It is a small change that is invisible
until it is a build failure partway through inserting a second city.

**Blocker 2 — `CHECK (inventory_source IN ('city','datasf'))` is a closed two-value vocabulary.**
A row naming any third inventory cannot be inserted:

```
sqlite3.IntegrityError: CHECK constraint failed: inventory_source IN ('city','datasf')
```

The CHECK must be widened, and `city` is a poor identifier once there is more than one city, so it
is worth renaming in the same pass. **The Swift side needs no change:**
`InventorySource.init(id:seedMeta:)` already resolves any identifier the receipt describes through
the `inventory_<id>_*` keys, so a new inventory is a build-side change only.

Both are caught by the contract's own registry before a row is built —
`require_inventory` refuses an unregistered inventory and `require_id_space` refuses a space with an
empty or unterminated prefix — but the registry cannot widen a CHECK constraint in a shipped schema.
That is the ingest's job and it has not been done.

### E170 — The check-in raised two review kinds and the queue could resolve only one


Task #58. One defect with four surfaces, all of them downstream of the same shape: **the code that
raised a review flag switched over two cases, and the code that resolved one hard-coded a single
case.** Everything else here follows from that asymmetry, including the two things that were missing
rather than wrong.

---

**What was raised.** `ObservationStatus.reviewFlagKind` returned `.appearsDead` *and*
`.appearsRemoved`; `LocalAPI.apply` inserted a `review_flags` row for either; screen 05 drew
`Appears dead` and `Removed?` side by side with identical affordances. Two of the check-in card's
four status segments opened a review.

**What could be resolved.** One. `openRemovalReviews` named `.appearsRemoved` in its own body, and
`confirmRemoval` guarded `flag.kind == .appearsRemoved` before writing `.removed`. The You tab's
queue had one section and one verb.

So every `appears_dead` flag anybody has ever raised on this app went into a table no surface read,
and stayed `open` forever. Nothing was lost and nothing was corrupted — which is exactly why a green
suite never noticed. `ModerationTests` proved the whole loop end to end for `appears_removed` and
said nothing about the other half of the vocabulary the same enum offered.

This is RULINGS R12's consequence. E124-B built the local moderation route and discharged R12 for
`appears_removed`; the dead half was left where R12 found it.

**Two absences on the same fault line.** Neither is a separate mistake — both are what "nobody
followed those two segments past the tap" looks like from a different angle:

- `ObservationStatus.opensReviewFlag` was documented as "the two cases that trigger a confirmation
  dialog and a review flag" and **had no caller in shipping code at all** (only
  `SQLiteStoreTests.swift:135`). The flag half happened; the dialog half was documentation of a
  feature that did not exist, and screen 05 moved the segment on one tap with nothing asked.
- `ReviewFlag.Status.dismissed` has existed since the model was written and **nothing wrote it**. A
  lead who thought a report was wrong could only leave it open. A queue whose only verb is "agree"
  is not a review, and the list could only ever grow in one direction.

---

**Fixed by putting the two sides on one switch.**

`ReviewFlag.Kind.confirmedStatus` is the seam: `appears_removed` → `.removed`, `appears_dead` →
`.deadReported`, and nil for the three kinds that are not status claims. The raise and the resolve
both read it, so a kind that can be raised and not confirmed is now a compile error rather than a
flag that sits open forever. `openReviewFlags` takes `kinds:` and the queue asks for
`statusReviewKinds`, derived from the same switch. `confirmRemoval` became `confirmReview` and takes
the status off the flag; `dismissReview` is the second verb, writing `.dismissed` and **no status
override** — dismissing says the reported change did not happen, and `tree_status_overrides` must not
start carrying rows that mean "somebody looked".

**No migration and no new enum case.** `TreeStatus.deadReported` has existed since `Tree.swift` was
written — its own header records the BUILD-PLAN-over-PRODUCT decision that put it there — and the
`tree_status_overrides` table from AppSchema v7 already carries any `TreeStatus`. The dead path goes
through the seam E124-B built for removal, unchanged.

**A confirmed death is not a removal, and the app now says so on three surfaces.**
`TreeStatus.deadReported.acceptsNewContributions` is `true`, deliberately: a dead street tree is
still standing over a pavement, and reporting it is the single most useful thing a passer-by can do.
So it is *not* routed to screen 19. It keeps its profile, its REPORT and CARE cells and its pin, and
what changed is that all three stop being silent about it:

| surface | before | after |
| --- | --- | --- |
| profile | identical to a live tree with no check-ins | `DEAD` badge and a Callout: reported dead, a reviewer confirmed, still standing so still worth reporting |
| map pin | grey dot spoken as `Removed tree, memorial` | grey dot spoken as `Dead tree, still standing` |
| queue row | `Reported removed` / `Confirm removed` | `Reported dead` / `Confirm dead`, beside `Dismiss` |

The pin's *drawn* half is deliberately unchanged. `MapPin.Kind` is a closed catalogue whose sixth
entry took a ruling (R7), and whether a standing dead tree deserves its own drawn pin is a design
decision this errata has no standing to make. It is the same split E107 made for the vacant site: fix
the words, leave the drawing for whoever owns the catalogue. The badge borrows the removed pair's
grey for the same reason — the two badges never say the same word, and there is no fifth badge colour
to invent.

**Screen 05 says where a report goes.** Both flagging segments now draw
`This goes to a community reviewer to confirm. The city is not notified.`, and `opensReviewFlag` gates
it. The register is `AccountAskCopy.noticeUnavailable`'s — name what is true today, then end on the
plain limit. The temptation to imply otherwise is strongest exactly here, because somebody reporting
a dead tree is reasonably hoping an official will come; DECISIONS §3.3 forbids "sent to the city"
copy and R12 exists because that gap was noticed once already.

**And the moderation queue stopped claiming it from the other end.** `ModerationCopy.confirmMessage`
used to close on *"This is how the city record is corrected."* That is the forbidden claim in the
passive voice, on the one screen where a lead is most likely to believe it — confirming a flag writes
one row on this phone. Both kinds' messages now end on `The city is not notified.`

**`opensReviewFlag` was wired, not deleted.** The ruling allowed either. Wiring it, because the
property is right about the product: those two segments are the only ones on a 60-second card whose
effect leaves the phone and lands in front of another person, and "appears dead" is a claim worth a
second tap. `CheckInModel` holds the proposed status in `pendingStatus` and never touches the draft
until the dialog returns, so cancelling leaves the card exactly as it was — a dialog that backed out
onto the segment it had proposed would be worse than no dialog. The other two segments stay one tap:
`Declining` has no consequence outside this phone, and taxing the common path buys nothing.

**The harness grew a slot, and the awkwardness is the point.** `DebugDeepLink`'s standing rule is that
a case which writes persistent state must not write it onto a tree another case reads. `.memorial`
marches outward on its own because a removed tree drops out of every `standingTree` scan afterwards;
a tree marked dead **stays in**, because `deadReported.acceptsNewContributions` is `true`. So
`.deadProfile` needed its own slot (three quarters out, between `.measure`'s middle and the photo
cases' far end) or `.memorial` would have marked this very record removed on the next run —
photographing a memorial where the previous case had just proved a dead tree keeps its profile.
`.moderationReview` now seeds **both** kinds on two trees: a queue seeded with removals only would
photograph the exact state that hid this defect.

---

**Tests.** `ModerationTests` was parameterised over `ObservationStatus.allCases.filter(\.opensReviewFlag)`
rather than over a hand-written pair, so a third flagging segment added to the card cannot slip past
it. The role gate is now proven on the write for both roles × both kinds × both verbs — eight
refusals, each checked to leave the flag open and the tree unmoved. `ReviewFlagNoticeTests` covers
screen 05's dialog and the copy, asserting the city sentences as properties of the words rather than
as equalities, because the failure mode is somebody rewriting them warmly.

Every one of them was watched failing before it was believed. Restricting `openReviewFlags` back to
`[.appearsRemoved]`, pointing `appears_dead`'s `confirmedStatus` at `.removed`, and dropping
`dismissReview`'s role gate turned the suite red in exactly the places those three things are
watched; the same for `select(status:)`, the badge ordering, the pin label and the moderation copy.

**Two real fixes came out of doing that**, which is the argument for doing it at all:

- `openReviews()[0]` is how this suite reached the flag, and under the very defect being fixed the
  queue comes back empty. The subscript killed the test *process* — `Fatal error: Index out of
  range` — and xcodebuild then reported `Test run with 0 tests in 2 suites passed`. A crash is not a
  failure: it takes the rest of the run with it and reports as the wrong thing entirely, which on
  this project is the exact shape of a suite ratifying a defect. It is `#require` now.
- The pin-label override was written as "if the status is `deadReported`, say so", which quietly
  outranked DECISIONS §3.16. A community-added tree confirmed dead would have lost the community's
  words. It fires on the drawn memorial pin only, so the *lie* is fixed and the precedence is not
  widened — `Community-added tree` is incomplete, not untrue, and that is a different problem.

---

**Driven on the device, not inferred.** Screen 05: tapping `Appears dead` raises `Report this tree as
dead? / A community reviewer checks this before the tree's status changes. Nothing is sent to the
city.`; Cancel leaves the card on `Alive` with no notice line; `Report it` selects the segment and
draws the notice under it. The You tab, seeded with both kinds, drew `Reported dead · Confirm dead`
above `Reported removed · Confirm removed`, each with its own `Dismiss`. Confirming the dead one
resolved it out of the queue, and the tree behind it — Kwanzan Flowering Cherry, 50 Hancock St, a
real seed record, SF #238248 — then drew the `DEAD` badge, the `Confirmed dead:` Callout, a live
`Be the first to photograph this tree`, `Check in · under a minute`, and all four quad cells
including REPORT. Not screen 19.

### E171 — `#expect(cgFloat == 3.0 / 4.0)` compared two boxes, not two numbers, and was false at 0.75


`main` failed its own unit suite on one assertion, and the assertion was arithmetically correct:

    ✘ VisitCameraSessionTests.theAddTreeWellIsAPortraitCaptureFrame()
      CypressTests/VisitCameraSessionTests.swift:808: Expectation failed: (ratio → 0.75) == (3.0 / 4.0 → 0.75)

Both sides print `0.75`, so the obvious reading is a float that misses by less than `description`
shows. That reading is wrong, and the hours it costs are the reason this entry exists. The values are
**bit-identical**. Printed from inside a running test, at full precision and as raw IEEE 754:

    [APP]  wellAspectRatio    = 0.75000000000000000000  d=0x3fe8000000000000
    [APP]  captureAspectRatio = 1.33333333333333325932  d=0x3ff5555555555555
    [TEST] wellAspectRatio    = 0.75000000000000000000  d=0x3fe8000000000000
    [TEST] 3.0 / 4.0          = 0.75000000000000000000  d=0x3fe8000000000000

There is nothing wrong with the arithmetic, and nothing wrong with the product. `4.0 / 3.0` rounds to
`0x3ff5555555555555`, whose reciprocal rounds back onto exactly `0.75` with a factor of eight of ULP
to spare. The defect is in **how `#expect` types its operands**.

**The mechanism.** `#expect(a == b)` does not compile to `a == b`. The macro expands to a generic
call of roughly the shape

    __checkBinaryOperation<T, U>(_ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @autoclosure () -> U, …)

so that a failure can report each operand's value separately. `T` binds from the left-hand side; `U`
is inferred from the right-hand side *and from what `==` will accept*. Here `T` is `CGFloat`, and the
bare literal expression `3.0 / 4.0` takes its default literal type, `Double`. Swift has no
`==` for `(CGFloat, Double)`. It does have the implicit `CGFloat`↔`Double` conversion — and it also
has the implicit conversion of any `Hashable` to `AnyHashable`, together with
`==(AnyHashable, AnyHashable)`. The solver takes the second. Reproducing that exact signature and
printing what it bound:

    [MIMIC bare]  result=false  T=CGFloat  U=AnyHashable  size=40  value=0.75
    [MIMIC var]   result=true   T=CGFloat  U=CGFloat      size=8   value=0.75

`AnyHashable` equality compares the **dynamic type first**. Both boxes hold the same 64 bits; one is
labelled `CGFloat` and the other `Double`, so they are unequal:

    [BOX] AnyHashable(CGFloat(0.75)) == AnyHashable(Double(0.75)) -> false
    [BOX] base types: CGFloat vs Double

That is the whole failure. Not a float, not the optimiser, not constant-folding: a type-erasing
comparison, reported through a message that shows the values and hides the types.

**Which spellings are affected.** Run against the same `ratio`, in one test:

| spelling | result |
| --- | --- |
| `let b = (ratio == 3.0 / 4.0); #expect(b)` | passes |
| `#expect(ratio == rhsCG)` where `let rhsCG: CGFloat = 3.0 / 4.0` | passes |
| `#expect(ratio == 0.75)` | passes |
| `#expect(ratio == CGFloat(3.0) / CGFloat(4.0))` | passes |
| `#expect(Double(ratio) == 3.0 / 4.0)` | passes |
| `#expect(ratio == 3.0 / 4.0)` | **fails** |

Two things fall out of that table. The trap needs the macro — the same comparison written as a plain
`let` is true, because outside a generic parameter the solver has a concrete `CGFloat` on both sides
and never reaches for `AnyHashable`. And it needs a *compound* literal expression: a bare `0.75`
binds `U` to `CGFloat` directly, since a single literal can simply be a `CGFloat` with no conversion
at all. `3.0 / 4.0` is a call to `/`, which pulls in the default literal type first.

**The fix is to name the type, and it is not a tolerance.** `VisitCameraSessionTests` now reads

    let portrait: CGFloat = 3.0 / 4.0
    #expect(ratio == portrait, "the well is \(ratio), not the 3:4 frame a phone held upright takes")

which keeps the comparison exact. Loosening it to `abs(ratio - 0.75) < ε` was the tempting repair and
would have been the wrong one twice over: it discards an alarm that was working, and it would have
been fixing a product that was never broken. Proved by mutation — with the product constant moved by
**one ULP** (`(1 / Camera.captureAspectRatio).nextUp`, a change of 1.1e-16) the assertion goes red.

**The sweep, which is the part worth keeping.** The trap is not specific to this constant; it is
available to every `#expect` in the suite that compares a `CGFloat` against a `Double`, and this
codebase measures geometry constantly. It divides into two cases, and only one of them is dangerous:

- **`==` — loud.** An affected equality is *always* false, so it fails immediately and cannot hide.
  A full clean run of the unit suite is therefore a complete census of them. There is exactly one:
  the assertion above.
- **`!=` — silent.** An affected inequality is *always* true, so it passes for the wrong reason and
  nothing ever notices. These cannot be found by running; they have to be read. All 98 `!=`
  expectations in `CypressTests` were listed and checked. 58 are `!= nil`; the remaining 40 compare
  strings, enums, copy constants, `Route`s and presentation structs. **None compares a `CGFloat`
  against a `Double` or against an untyped literal.** The suite has no silent instance today.

The one other equality in the suite that pairs a literal arithmetic expression with a numeric value
is `MeasurePresentationTests.swift:88`, `#expect(draft.quantity?.siValue == 64 * 0.0254)`. It is
sound, and usefully so: `siValue` is a `Double`, so `U` binds to `Double?` with no conversion needed
and no erasure. Literal arithmetic is not the trigger on its own — the trigger is `CGFloat` meeting
`Double` across the macro's generic parameter.

**The rule.** Inside `#expect` and `#require`, never compare a `CGFloat` against an unannotated
numeric expression. Bind the expected value to a `CGFloat` first, or write both sides `Double`. The
comparison you read is not the comparison the macro compiles.

Related: E162, which is the well's own defect and the reason this test exists; ticket #113.

### E172 — The survey that had to ask each city what its own numbering means

     parallel agent. Written for #107, the survey half. -->

### California's other tree inventories, surveyed — and what the contract yields from each

E169 left #107 with a question it could not answer from San Francisco: *which city next, and does
the contract carry a genuinely foreign inventory without being widened for it?* Eight California
inventories were probed through their own APIs on **2026-07-31**, 195 requests in total, every
response cached under `Fixtures/raw/ca_survey/` and every request logged, so the count is read off a
file. Nothing was bulk-downloaded and nothing was fetched from behind a login or a click-through
licence, because nothing found required one.

**The recommendation is San Jose**, and the reason is not its size.

**Only one of the eight publishes a field that says what a record is.** San Jose's Street Tree layer
carries `VACANTSITE` — `Yes`/`No`, 344,879 rows, null on 680. E169's finding was that until the
contract existed there was no field anywhere in the ingest in which a source could state this, so
`build_seed.py` inferred it from a missing species. Against San Jose that inference is reached by
**61 rows of 344,879 — 0.018% of the corpus**, against **1,777 of the 195,309-row `--source datasf`
corpus (E11) — 0.91%**. The shipped seed is `--source city`, whose split between stated and inferred
E169 records as not measured, so no figure for it is quoted. For Los Angeles, Sacramento, Santa
Monica, Oakland, San Mateo and Long Beach the
inference would be reached by *every record*, because none of them publishes a vacancy or site
concept at all.

**Three sources publish a licence that is a grant; two publish a disclaimer or nothing.** Measured
from each publisher's own metadata:

- **San Jose — CC-BY.** `license_id: cc-by` on the city's CKAN package `street-tree`,
  `metadata_modified` 2026-07-24.
- **Oakland — CC0 1.0**, and the dataset's `rowsUpdatedAt` is **2013-01-22**. Eight fields, no id but
  a row number, no DBH, no date.
- **Long Beach — CC BY 4.0**, and **1,728 rows**: trees planted since September 2018 under one CAL
  FIRE grant. A grant deliverable, not a city inventory.
- **Santa Monica — ODC-BY-1.0**, 40,966 rows.
- **Sacramento** states *"provided as a public service and for general informational purposes only"*
  — a disclaimer, not a licence.
- **Los Angeles** and **San Mateo** state nothing at all: empty `licenseInfo`, empty `copyrightText`.

**Two findings that stop a source rather than rank it.**

*Berkeley could not be verified.* `data.cityofberkeley.info` returns **HTTP 403** to every automated
request made here — metadata, count, sample, and the landing page. Berkeley's `City Trees` is
described as covering trees, planting sites **and stumps**, which is all three of the contract's
kinds, and it may be the best fit in the state. **It is recorded as unverified. It is not recorded
as permissive.**

*Santa Monica's API serves placeholder rows before it serves real ones.* At offset 0 the CKAN
datastore returns records with `_id: 0`, `name_botanical: "ncMUFCMU"` and coordinates
`39.7817, -89.6501` — **Springfield, Illinois**. At offsets 5,000 and 30,000 the same resource
returns plausible Santa Monica data. `total` reads 40,966 throughout. Observed, not explained. An
ingest that read the first page and stopped would ship Illinois.

*San Diego publishes no tree inventory.* Its open-data portal lists 115 datasets and none concerns
trees.

**Two sources publish DBH and neither publishes a measurement.** Sacramento's `DBH` is a string
range spelled two ways in the same column — `13 - 24` and `19 to 24` — and Santa Monica's is
`dbh_min`/`dbh_max`. `InventoryRecord.dbh_in` means inches somebody measured, so the contract yields
**NULL for all 112,814 Sacramento rows and all 40,966 Santa Monica rows**, and there is no honest way
around it. San Jose's `TRUNKDIAM` is a double in inches and is the only one that survives.

**Los Angeles is the largest and would add 635,558 trees of unknown species.** Its open layer
publishes six fields: an id, a type, a tooltip, a URL. `Species: Not Specified` on every sampled row.
The species exist behind per-tree NavigateLA report pages — 635,558 requests against somebody else's
server, which is not a thing to do.

### The contract carried a foreign inventory without being widened, and the proof is 29 real rows

`SanJoseStreetTreeAdapter` and `Tools/test_ca_inventory_adapter.py` are new;
`Tools/inventory_contract.py` gains one `IdSpace` line and one `Inventory` line and nothing else.
`Tools/test_inventory_contract.py` still reports **114 checks passed, 0 failed** with San Jose
registered.

The adapter reads `NAMESCIENTIFIC` straight into `scientific_name`. There is no `::` in it, it does
not import `parse_qspecies`, and it never touches `PLACEHOLDER_SPECIES` — which is exactly what
`SFCityLayerAdapter.species_of`'s docstring promised the third source would be able to do, now
demonstrated rather than asserted.

Three of San Jose's own conventions would otherwise have produced records the contract refuses:

- **72,142 rows carry `TRUNKDIAM = 0`.** `validate()` refuses a non-positive `dbh_in`, so until the
  adapter resolved the sentinel this was a hard failure, not a wrong number. Only 2,701 of those
  rows are `VACANTSITE = 'No'`.
- **72,995 rows carry the literal string `Vacant site` (71,590) or `Vacant Site` (1,405) in the
  scientific-name field.** Two spellings, one fact. A rule keyed on the literal string mints a
  species called `Vacant Site` for 1,405 planting sites — #103's mechanism exactly.
- **4,513 rows say `Unknown`.** Treated as a placeholder it deletes 4,513 trees from the map;
  minted as a species it puts `Unknown` in the field guide. R18 already settled it: a tree of
  unknown species is a tree.

**Where San Jose disagrees with itself, the adapter picks the field whose only meaning is vacancy
and counts the disagreement** rather than resolving it silently: **611** vacant sites that name a
real taxon, **3,666** vacant sites carrying a positive trunk diameter, **82** rows saying
`Vacant site` under `VACANTSITE = 'No'`, and **61** rows where the source said nothing in either
field. All four counts are measured against the live layer.

### Two of the new tests did not notice the adapter being broken

Ten deliberate regressions were applied one at a time and the suite was required to go red for each.
**Eight did. Two did not, and both were fixture gaps rather than assertion gaps.**

- **The vacancy vocabulary could be keyed on the wrong case with the suite green**, because every
  vacancy row in the fixture was *also* flagged `VACANTSITE = 'Yes'` — the flag reached the answer
  first and the vocabulary was never consulted. The 82-row case where the flag says occupied and the
  species field says vacant is the only case the vocabulary decides, and it was missing.
- **The trailing-space rule could be deleted with the suite green**, because querying the layer for
  `NAMESCIENTIFIC = 'Ulmus '` returns rows holding `Ulmus`: trailing spaces are insignificant to SQL
  comparison, so the obvious query built a fixture that made the test pass **without ever containing
  the case**. Re-fetched with `LIKE 'Ulmus_'`, and the test now asserts on the raw fixture value as
  well as the parsed one so the case cannot be lost again silently.

After both fixes all ten go red. 563 checks pass over 29 rows taken verbatim off the layer, one
query per case the adapter has a rule for.

### The two schema blockers, now stated as the constraints they must become

E169 reproduced both. Neither is changed here — `AppSchema` is at v13 and a migration is a
build-and-test job — but the survey settles what they should become, because the id-space answer is
now known for a real second city.

**`trees.external_ref INTEGER UNIQUE`** must become `external_ref TEXT NOT NULL` beside a new
`id_space TEXT NOT NULL`, with the uniqueness moved to `UNIQUE (id_space, external_ref)`. **Text,
not integer**: `source_ref` is defined as the source's own id verbatim as a string, and nothing
guarantees the third city's is numeric. Storing the qualified seed string `us-ca-sj:3` in one column
is the alternative and is worse — it makes "which space is this row in" a parse rather than a column.

**`CHECK (inventory_source IN ('city','datasf'))`** must become `CHECK (inventory_source <> '')`
plus a foreign key into a new `inventories` table that `build_seed.py` writes from `INVENTORIES` for
exactly the inventories that contributed rows. A hardcoded list is the wrong instrument for "the
receipt can describe this inventory": every new city would edit the schema. In the same pass, `city`
should be renamed `sf_city` — E169 already says it is a poor identifier once there is more than one
city, and the rename touches a stored value so it belongs in a migration and not before one.

**No Swift change is needed for either**, which E169 established and this survey did not disturb.
`CypressTests/InventoryContractTests.swift` should pass unchanged for a second city; **that was not
verified here, because building and the simulator were out of scope for this task**, and if it does
not pass it has found something real.

### E173 — The delete shipped on one screen and the gesture people make led away from it


The report, walking the app:

> Not sure if the feature to delete photos is still tbd, but I don't see that option, so hopefully
> it's tbd rather than 'shipped' but not actually.

#78 is COMPLETED and it is genuinely complete. **The control exists, works, and is reachable — and
it is not on the screen the gesture takes you to.** This is the third of the four things that report
could have been, and it is a defect rather than a misreading.

#### What was observed, before any code was read

Booted the simulator, installed a build from this worktree, and drove it. On `photoHero` — screen 03
over a tree with three photographs — the delete is exactly where E147 put it: screen 20, one amber
trash glyph per row, beside the two thumbs. It opens a confirmation naming the consequence, the verb
is on the button, and it works. E147's walkthrough was accurate and its tests were honest.

Then the other tap. **Tapping the photograph opens `PhotoViewerView`, which had no delete on it and
no route onward.** One photograph, full-frame, named in its own caption, with a close button in the
corner and nothing else. Somebody who taps their photograph in order to do something to it arrives
at a screen whose entire vocabulary is *look, then close*, and the only correct conclusion from
inside that screen is that the feature does not exist.

Both doors into the viewer are like this: the hero on 03 (`TreeProfileView.hero`) and a row on
screen 20 (`TreePhotosView.card`). So a person who is already standing on the surface that has the
delete, and taps the picture to see it properly before deciding, loses the control by looking closer.

#### Why the reasoning that excluded it was right about the hero and wrong about the viewer

E147 wrote down its exclusion:

> No delete affordance in the full-screen viewer or on the hero: screen 20 is the only surface that
> shows a tree's photographs as a set with per-photograph controls, and a delete on the hero would
> act on whichever photograph the rule happened to pick.

The second clause is true, and it is the reason not to put a delete on the hero: the hero is
whichever photograph `PhotoHero.choose` ranked first this frame, so a trash beside it is a control
whose subject changes under a vote. **The viewer is the opposite case.** It is handed a `photoID`.
It draws that photograph and no other, whole, with that photograph's own caption under it. There is
no rule and nothing for it to pick. The sentence was carried from the hero to the viewer in the same
breath, and the two were never the same screen.

The other half is timing. `PhotoViewerView` is E142, and it exists because of an earlier field
report — *"clicking on photo from tree page should show full view"*. E142 gave the photograph a tap,
and in doing so made "tap the photograph" the app's answer to *act on this photograph*. E147 landed
after it, and reasoned about the hero as though the tap still went nowhere.

#### The pill is a caption, and that is the rest of the answer

The one door to screen 20 is the hero's metadata pill, which reads `3 photos · since 2026`. It is a
button and it says so to VoiceOver, and `HeroPhotoHeader` grew its target to 44 pt on purpose. But
it is mono 10.5 in a translucent capsule in the corner of a photograph, which is the same treatment
this app gives `Best photo · Oct 2025` two inches away — a label. Nothing about it reads *there are
controls behind this*. So the delete sat behind a caption, one tap away from a screen whose obvious
tap goes somewhere else, and the owner's summary of that arrangement is the correct one.

#### The repair

`Route.photoViewer` gains the tree id. That is not bookkeeping: ownership is a fact about a tree's
photographs (`TreeProfile.deletablePhotoIDs`), so a viewer holding only a photograph's id **cannot
ask whether the person looking at it may delete it** — which is the mechanical reason this screen
could not have had the control when it was written. The route's own comment argues that it carries a
caption rather than an id to avoid a second read that could disagree with what is on screen; that
argument does not apply here, because this is not a word, it is the key the answer is read under.

The viewer then drives **the same `TreePhotosModel`** screen 20 drives, rather than a model of its
own. One implementation of "may this person delete this photograph, and what does removing it cost
the tree" — the community-add sentence included — instead of two that can drift. The control is the
same glyph in the same amber register opening the same confirmation with the same words, because a
person who has seen one of these has seen both.

Three smaller decisions, each with a reason:

1. **Bottom-trailing, diagonally opposite `Close`.** The destructive control is as far as the screen
   allows from the one that means *never mind*, and clear of the caption in the other corner.
2. **The viewer closes on a successful delete.** Its subject no longer exists; staying would draw
   *That photograph could not be opened* over the place it used to be, which reads as a failure
   rather than as the thing that was just asked for. The surface underneath re-reads itself — which
   is E127, and which E147's own harness defect was about.
3. **The failure is drawn over the photograph.** `TreePhotosModel.deleteError` must never be silent;
   here there is no list to put it above, and the photograph still being there is half the message.

#### The test, and how it was made to fail

`CypressUITests/PhotoDeletionReachabilityTests` — and it is a **UI test on purpose**. Every unit test
in `PhotoDeletionTests` passed throughout this defect and would have gone on passing: they assert
that `deletePhoto` removes a row and a file, which was always true. Nothing asserted that a person
holding the phone could get to it. A unit test on a presentation helper would have repeated exactly
the mistake that closed #78 green.

It drives the reported path. `communityPhotos` — the deep link E147 built precisely to have its
photograph deleted, on its own tree — then tap the hero photograph, then assert the delete is in the
tree, is hittable, opens a confirmation, and that taking the confirmation leaves the tree cold. It
does not stop at `isHittable`: this project has shipped a control that reported `true` and that no
finger could press, so the control is *used* and the surface underneath is read.

Made to fail on purpose by deleting the one overlay line that draws the control — which restores the
defect exactly as it stood, since nothing else about the deletion changed. Both cases went red, on
their own sentences:

```
PhotoDeletionReachabilityTests.swift:47: error: testTheHeroPhotographReachesADeleteThatWorks :
  XCTAssertTrue failed - the viewer opened over a photograph this device owns and offered no way
  to delete it — which is the whole of the owner's report on #78
PhotoDeletionReachabilityTests.swift:110: error: testAPhotographOpenedFromTheBrowserReachesTheSameDelete :
  XCTAssertTrue failed - the browser's own row opened a viewer with no delete on it, so looking
  closer at a photograph costs you the controls for it
     Executed 2 tests, with 4 failures (0 unexpected) in 29.254 seconds
```

The line restored, both green:

```
Test Case 'testAPhotographOpenedFromTheBrowserReachesTheSameDelete' passed (12.789 seconds).
Test Case 'testTheHeroPhotographReachesADeleteThatWorks' passed (11.538 seconds).
     Executed 2 tests, with 0 failures (0 unexpected) in 24.327 seconds
```

#### What was not built, and one thing seen in passing

The pill's own discoverability is untouched. It is now a second way to the same control rather than
the only way, which is the part of this that mattered; whether a mono-10.5 capsule over a photograph
should look like a door at all is a design question and not this entry's.

**The silent case is still silent, and it is now silent in two places.** An anonymised photograph —
one whose contributor left through the door that keeps their work — is still *shown*, correctly, and
has no delete on it, correctly. What neither screen 20 nor the viewer does is **say so**. The row
simply has one fewer control than the row above it, and the viewer simply has an empty corner. E126
requires a screen with nothing on it to say why, and the same logic covers an action that is absent
for a reason; "this photograph's contributor has left, and it is nobody's to remove" is a sentence
this app would normally write. It is deliberately not written here because it is a different defect
from the reported one and wants its own entry and its own copy — the state is reachable (sign in,
contribute, delete the account keeping the work), it is rare, and inventing the sentence in passing
is how copy gets written that nobody has read against the screen.

Seen while reading, and not fixed here: `TreePhotosModel.load` filters `profile.photos.items`, which
`LocalAPI` already narrows to what this installation wrote, while the hero pill's count comes from
the tree's whole photo count. On a tree carrying photographs from other people the pill would say
`214 photos` and screen 20 would draw its empty state. Nothing syncs anybody else's photographs down
today, so the two cannot disagree yet and this is latent rather than live — but it is the shape E126
is about, and it becomes real the day the service exists.

### E174 — The add-tree well filled the screen, so the form beneath it read as the end of it


Reported by the project owner, walking the app: *"Screen for Add this Tree has the photo square fill
the entire vertical area so it's not clear to the user that there is content below the photo that
they can fill out."*

**The suite asserted the thing being complained about**, which is the reason this entry is longer
than the fix. E162 (#113) found the well was a landscape frame that cropped a portrait capture and
made it the 3:4 frame a phone held upright actually takes, deriving it from
`Camera.captureAspectRatio` so the well and screen 04's viewfinder floor cannot drift. That was
right, and `VisitCameraSessionTests.theAddTreeWellIsAPortraitCaptureFrame` has guarded it since. But
3:4 at the gutter's width is 481 pt on a 393 pt phone, and E162 wrote the consequence down as a
feature:

> **No cap, deliberately.** A maximum height would be a return to the letterbox by a smaller margin:
> any well shorter than its own capture crops the live preview again, which is the defect.

That paragraph is correct about the mechanism and wrong about the conclusion, and the difference is
one word. A cap on the well's **height** does return the letterbox — the well would be gutter-wide
and too short, `VisitCameraPreview` is `.resizeAspectFill`, and the crown would go off the top of a
street tree again, which is exactly E162's defect. A cap on the well's **width** does not: the well
keeps its ratio to the last bit and is simply drawn smaller and centred. E162 refused the only cap it
considered, and there was a second one.

**Measured on the running app, iPhone 16e (390 × 844 pt), the add screen with a fix:**

| | scroll viewport | well | share |
| --- | --- | --- | --- |
| before, default type | 573 pt | 476 pt tall × 356 wide | **83 %** |
| before, AX5 | 247 pt | would be 476 | **193 %** — drawn clipped by the footer |
| after, default type | 539 pt | 357 tall × 266 wide | 66 % |
| after, AX5 | 179 pt | 116 tall × 91 wide | 65 % |

The tests host a 393 × 852 phone rather than this one, and the failures they record against the
pre-fix layout read 481 pt of a 617 pt viewport at the drawn size (78 %) and 219 *drawn* rows of a
287 pt viewport at AX5 — the second being where the footer cut the well off, because 481 pt has
nowhere to go in 287.

At the drawn size the 83 % left 105 pt under the photograph, into which the screen fitted the
photo-source link, one sentence, and the top half of the words `Move the pin` — a clipped line above
a pinned CTA, which reads as the bottom of a screen rather than as the middle of a form. At AX5 it
was worse than the owner reported: the well did not fit in the viewport at all, so the entire first
screenful was one grey box clipped at the footer, and the photo sources, the pin row, the land
question and the species row were all below a fold that nothing on the screen admitted to. That is
E159's failure in a different costume — a thing sized by something other than the type ramp growing
past the space the type ramp left it.

**The fix, in three parts.**

1. `VisitMetrics.AddTree.wellWidthCeiling(viewport:)` — the well may take at most
   `wellViewportShare` (two thirds) of the composer's scroll viewport, expressed as the **width**
   that bounds that height at the well's own ratio. `VisitAddTreePhotoWell` applies it as
   `.frame(maxWidth:)` ahead of its `.aspectRatio(_:contentMode: .fit)`, so the well shrinks along
   its own diagonal. `wellAspectRatio` is untouched and still derived from the capture; nothing here
   can move it, and `theWellCeilingTakesWidthNotShape` is the assertion that says so — it binds the
   ceiling hard and reads the ratio back off the drawing.
2. The composer's scroll is wrapped in a `GeometryReader`, whose only job is to hand the viewport's
   height to that function. Same shape as screen 04's `accessibilityLayout` and for a related
   reason: a split at a stated line rather than whatever two flexible children negotiate.
3. **The accuracy chip is pinned with the header instead of scrolling with the form.** Without this
   the ceiling means less than it says: "the well takes two thirds of the viewport" is only "a third
   of the viewport shows the form" if the well starts at the top of the viewport, and with the chip
   above it inside the scroll the chip's height came out of the third. At AX5 the chip is 78 pt of a
   247 pt viewport — the whole of the remainder. The chip is a statement about the screen rather
   than a row of the form (it is screen 02's status row, and 02 does not scroll it either), so
   pinning it is what it was always describing.

**One consequence that had to be fixed with it.** The narrower well and the type ramp stop being
compatible above a point: at AX5 the well is 91 pt wide and `"A photo of the tree is required"` sets
four lines of ~33 pt type inside it, which the well clipped top and bottom into *"photo of the tree
is requir"*. E159 already wrote the rule for this — a frame whose size does not follow the ramp
carries only furniture that does not follow the ramp either, and everything that grows moves out —
so at accessibility sizes the sentence is drawn under the well rather than inside it. Nothing is lost
to VoiceOver at any size: the well's `accessibilityLabel` is that string either way. It also lands
where the peek is, which is why AX5 now shows a legible line of copy below the photograph where it
used to show nothing at all.

**What the test now guards, and why it is a different test.**
`theAddTreeWellIsAPortraitCaptureFrame` keeps every ratio assertion it had, including the 481 pt
figure — that number is still exactly true of the well's *shape*, which is what it was always about,
and the test now says so and measures the unbounded well to prove it. What it could never assert is
the defect above: the well was the right shape and the wrong share of a screen, and a component
measured on its own has no screen to be a share of. So `theAddTreeWellLeavesTheFormOnTheScreen`
hosts the real composer at 393 × 852 at `.large` and at `.accessibility5`, draws it with
`layer.render(in:)`, and reads the well's rows out of the pixels by its `surfaceEmptyThumb` fill —
because the well is a `RoundedRectangle` inside a `ScrollView`, SwiftUI vends no `UIView` for it, and
a hosted tree vends no accessibility elements either. Three claims, all three red before the fix:
the well is at most two thirds of the viewport; the well starts at the top of the viewport; and
there is ink drawn below the well and above the CTA, which is the owner's sentence restated as a
fact about pixels.

**Proved by mutation, because a layout assertion that has never been red is a screenshot with a
`#expect` around it.** With `wellWidthCeiling` returning `.infinity`, the chip put back inside the
scroll and the sentence put back inside the well — the layout as it stood on `main` — the new test
records five issues across its two cases:

    ✘ … size → .large: (wellHeight → 481.0) <= (ceiling + 2 → 413.11)
    ✘ … size → .large: (CGFloat(well.lowerBound) - viewport.minY → 36.0) < (3 → 3.0)
    ✘ … size → .accessibility5: (wellHeight → 219.0) <= (ceiling + 2 → 193.33)
    ✘ … size → .accessibility5: (CGFloat(well.lowerBound) - viewport.minY → 67.67) < (3 → 3.0)
    ✘ … size → .accessibility5: (ink → 0) >= 200

and with the ceiling applied as `.frame(maxHeight:)` instead of `.frame(maxWidth:)` — the letterbox
this fix exists not to be — `theWellCeilingTakesWidthNotShape` records the shape going wrong:

    ✘ (abs(measured.width - ceiling) → 161.0) < (1 → 1.0)
    ✘ (abs(measured.width / measured.height - ratio) → 1.055) < 0.01

The last line is the important one: 1.055 is the distance from 0.75, which is the well ceasing to be
the shape of the photograph. That is the assertion standing between E174 and a second E162.

**One thing the first draft of the ink claim got wrong**, kept here because it is the failure mode of
every probe like it: it counted the well's own dashed border as content below the photograph, so it
passed on the exact AX5 layout it was written to fail. Starting the band 6 pt below the well's last
filled row is what makes `ink → 0` above true.

Related: E162, whose "no cap" this narrows and whose ratio it leaves alone; E159, whose rule about
what a ramp-independent frame may carry is applied here a second time; ticket #127.

### E175 — Three trees in four have no planting date, so a year filter is mostly a claim about the city's paperwork

**Ticket #116, screen 01.** The owner's instruction on the year filter was to check the seed before
designing the control: "`plant_date` coverage is not 100% and a filter that silently drops every row
with no date is a lie. Count it first."

#### The count

Against the shipped seed (`Cypress/Resources/cypress-seed.sqlite`, `trees_source = city`,
`trees_snapshot_on = 2026-07-26`):

```
total rows                     145,837
carrying planted_year           37,962   26.03 %
carrying no planted_year       107,875   73.97 %
```

By status, which is the split that matters, because the map mostly draws living trees:

```
status        rows      with year    %
alive       133,424       28,725    21.5
vacant_site  12,413        9,237    74.4
```

Range of the dated rows: **1955–2026**. Distribution: pre-1990 7,742 · 1990s 8,746 · 2000s 10,134 ·
2010s 8,493 · 2020s 2,847.

The schema already says this is one fact at two grains and holds them together —
`CHECK ((planted_on IS NULL) = (planted_year IS NULL))` — so there is no partial state to exploit. A row
either has a planting date or it does not, and four out of five living street trees do not.

#### Why that is a design fact and not a footnote

`planted_year BETWEEN 2010 AND 2019` is an honest predicate. SQLite's three-valued logic drops every
NULL, which is correct — a tree with no recorded date is not a tree known to have been planted in the
2010s. The dishonesty is not in the SQL, it is in **what the reader concludes from the silence.**

A map that empties out under `Year: 2010s` is read as "there are no 2010s trees on this block". What is
actually true is "the city did not record when about three of these four trees were planted." Those are
different claims and the app is only entitled to the second one. At 26 % coverage the first claim is
wrong far more often than it is right.

This is the same shape as E158 — screen 11 spent its whole life telling people their GPS fix was "too
weak" when the phone had merely not answered yet — and the same shape as E38's page-as-total: an
absence rendered as an answer.

#### What was done

The predicate stands. The **surface** carries the rest: whenever a decade is chosen, screen 01 renders

> About 3 in 4 trees have no recorded planting date—none of them can appear under a year.

The `planted_year IS NOT NULL` clause is written into the SQL beside the `BETWEEN` even though it
changes no row, so a reader of the query plan sees the decision rather than inferring it from a missing
clause. `LocalAPI` applies the same rule to the community layer in Swift — a community tree with a nil
`plantedYear` is excluded, matching the seed side exactly — because a dashed pin surviving a year filter
would be the map claiming the community recorded a date the city did not.

The proportion is stated rather than a per-viewport count. That trade is argued in RULINGS **R23** §4:
the honest per-viewport number costs a second full fetch of the box on every pan, and the proportion is
a property of the inventory that is true on every screenful. `CypressTests/MapFilterTests` pins it
against the shipped seed on both the raw share and the rounding, so a re-ingest that moves coverage
fails the build instead of leaving the sentence lying on screen.

#### Proving the new tests can fail

Six deliberate mutations, applied together, one per assertion, run against
`CypressTests/MapFilterTests` — `Test run with 16 tests in 1 suite failed after 0.412 seconds with 10
issues.` Each mutation was reverted afterwards and the tree re-verified clean.

| # | Mutation | Test that went red |
|---|---|---|
| M1 | `contributedTreeIDs` loses its owner clause | Yours holds the trees this device contributed to, and no one else's |
| M2 | an empty `treeIDs` set resolves to "not narrowed" instead of `.matchesNothing` | an empty membership set empties the map rather than showing every tree |
| M3 | `favoriteTreeIDs` drops `deleted_at IS NULL` | Favourites excludes a tree whose favourite was turned back off |
| M4 | the `plantedYears` clause is never emitted | a year-narrowed viewport returns no tree without a planting date |
| M5 | `MapFilterCopy.result` always reports the drawn page | the result line reports matches, not the size of the thinned page |
| M6 | `MapViewport.shouldCluster` stops exempting membership | only a membership narrowing suspends clustering |

Selected red output, verbatim:

```
MapFilterTests.swift:104:9: Expectation failed:
  (yours → [14C2C728-…, C37AE43F-…]) == ([mine] → [C37AE43F-…])
MapFilterTests.swift:105:9: Expectation failed:
  !((yours → […]).contains(theirs → 14C2C728-…) → true)

MapFilterTests.swift:201:9: Expectation failed:
  (favourites → [14C2C728-…, C37AE43F-…]) == ([kept] → [C37AE43F-…])

MapFilterTests.swift:315:9: Expectation failed:
  (undated → [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, …
MapFilterTests.swift:317:9: Expectation failed:
  (outside → [2020, 1997, 2023, 2024, 1994, 1995, 1994, 1994, 1998, …

MapFilterTests.swift:351:9: Expectation failed:
  (thinned.contains("1458") → false) || (thinned.contains("1,458") → false)
MapFilterTests.swift:353:9: Expectation failed: (thinned → "151 trees") != "151 trees"

MapFilterTests.swift:473:9: Expectation failed:
  !((MapViewport(bounds: city, zoom: 12, treeIDs: [UUID()]) → …).shouldCluster → true → true)
```

M4's output is the one worth reading twice: with the year clause gone, the viewport came back holding
a long run of `nil` planting years and a spread of 1992–2024. That is precisely the silent set the
caveat above exists to speak for.

#### A second defect, found by running the app and not by reading it

With `Yours` on and no matches in view, screen 01 drew a `0 trees` pill in the chrome **and** a
`No trees of yours here` card below it. The same fact twice, with the weaker phrasing on top; the card
says why the map is empty and offers the way out (E126), and a bare zero says neither. The result line
now draws nothing when the map is empty.

The unit suite was green across both states. It could not have caught this — the two surfaces are
correct individually and only wrong beside each other, which is a thing you see and not a thing you
assert. `Test run with 917 tests passed` said nothing about it.

---

### E177 — The search bar answered with a map and never said what it had understood (task #109)

---

The project owner, walking screen 01: *"I think it should surface drop downs with species (as you
type)."*

**What the bar did.** Typing narrowed the map in place and drew a status line under the filter chips.
That much was E134's work and it is right: the map is the result, and there is no results *screen*
behind C20 (`MapSearch` argues it at length). What was missing is the step before the result — the
bar never said **what it had understood the query to mean**. A person typing `cypr` got a map that
changed shape and no way to find out what it had changed *to*, and the status line's own vocabulary
admits it: `Showing the 6 matching species` names a count where the reader wanted six names.

The defect is worst exactly where E165 made the search best. Since task #108 the catalogue matches a
word anywhere in either name, so `cypress` resolves to the genus *and* Monterey, Italian, Leyland,
Hinoki and Montezuma Cypress. That is the fix the owner asked for; it also means a query now routinely
means six different things at once, and the map draws all six as identically coloured dots. The
narrowing got broader and the explanation did not.

**Fixed** by dropping a list of species under the bar as you type: common name in the serif list face,
scientific name in the italic serif beneath, and tapping one narrows the map to **that species** and
puts its name in the field rather than leaving the typed fragment there. `SCREENS.md` 01 lists "search
results" among the surfaces it does not specify, so the design is delegated under DECISIONS constraint
21 and is recorded as ruling **R25** — including the parts that are decisions rather than drawings:
what a row does *not* show, what the list does when nothing matches, what it does at AX5, and what a
VoiceOver reader hears.

---

#### The way this ticket was most likely to go wrong, and the type that stops it

**E38: a page is not a total.** E165 made the 100-species cap **routine** rather than exotic — `a`
prefix-matched 97 species before that change and *contains*-matched 555 after it, and
`MapSearch.Narrowed.isTruncated` exists to carry that fact. A dropdown shows a handful of rows, so it
is a page of a page, and six rows of five hundred and fifty-five matches drawn with nothing saying so
is precisely the defect E38 names.

So the remainder is modelled rather than described. `MapSuggestions.Remainder` has three cases and the
third is the whole point:

| case | when | the sentence |
|---|---|---|
| `.none` | every match is on screen and the catalogue's answer was not itself a page | *nothing* |
| `.exactly(n)` | more matched; the catalogue counted them all | `Showing 6 of 21 matching species. Keep typing to narrow it.` |
| `.atLeast(n)` | the catalogue returned a full page, so the total is unknown | `Showing 6 of at least 100 matching species. Keep typing to narrow it.` |

`atLeast` claims the weaker of the two available sentences, for the same reason `isTruncated` does one
level up: "at least 100" is true when exactly 100 matched *and* when 555 did, and the reverse is not.
Nothing in the app can count the rest without reading the whole species table on the typing path.

**One read, two surfaces.** The list and the narrowing are two readings of the same
`searchSpecies(query:limit:)` answer, so the dropdown can never offer a species the map is not
narrowed to. A second query at a second limit would eventually allow exactly that, and nothing else in
the suite would notice, which is why `typingDropsAList` asserts the containment rather than the rows.

---

#### Two defects the suite could not see, both found by typing into the running app

**1 · The E38 sentence was below the fold, which is E38's own defect one level down.** The remainder
line began as the last row of the scrolling list, on the reasoning that a VoiceOver reader who hears
the rows should hear what they are a page of in the same sweep. Typed into the running app, `a` drew
six rows, filled the height cap exactly, and left `Showing 6 of at least 100 matching species` where
nobody would find it. Every test stayed green, including the XCUITest that asserts the sentence
exists — `XCUIElement.exists` is true for an element inside a scroll view whether or not any part of
it is on screen, which is exactly the gap between "the app says it" and "the app says it to somebody".
The sentence is now pinned under the scroll and inside the accessibility container: one sweep for
VoiceOver, and never scrollable away.

**2 · At AX5 the FAB drew on top of that sentence.** Screen 01's chrome is two absolutely positioned
blocks and the bottom one — recentre, FAB, tree card — was applied *after* the top one, so it won every
overlap. At the drawn size the two never overlap and nobody had noticed in the year the screen has
existed. At AX5 with the list open, `What tree is this?` sat squarely across the middle of the
sentence: `Showing 6 of at least 100 match……. Keep ty…… it.` The blocks are now applied in the other
order. Nothing inside either of them moved, and nothing else on screen 01 changed position at any
size.

**A third thing, in the tests rather than the app, and it is #101 and #104's mistake again.** The
first XCUITest draft matched the row label `Monterey Cypress, Hesperocyparis macrocarpa`, copied out of
`SCREENS.md` 02. The seed spells that species `Cupressus macrocarpa`. Three tests went red reporting
`typing “cypress” drew no suggestions` — a sentence about the dropdown being broken that was in fact a
sentence about the mock. The row's real claim is structural (a common name, a comma, a second name),
which is provable without knowing *which* second name, so the tests now match a prefix and assert
something follows it.

#### Proving the tests can fail

Three one-line mutations to production code, run against `MapSuggestionTests` and
`MapSuggestionUITests`, restored afterwards.

| # | mutation | file |
|---|---|---|
| 1 | `remainder = .atLeast(hidden)` → `.exactly(hidden)` | `MapSuggestions.swift` |
| 2 | `rowLabel` returns `name(species)` only | `MapSuggestions.swift` |
| 3 | `applySearch(MapSearch(query: searchText, matches: [species]))` deleted from `chooseSuggestion` | `MapModel.swift` |

**The unit suite — 4 of 14 red, 8 issues:**

```
✘ Test "a full page from the catalogue is reported as a floor, never as a total" recorded an issue
  at MapSuggestionTests.swift:108:9: Expectation failed:
  (listing.remainder → .exactly(94)) == (.atLeast(MapSearch.speciesLimit - MapSuggestions.rowLimit) → .atLeast(94))
✘ … at MapSuggestionTests.swift:113:9: Expectation failed:
  (sentence → "Showing 6 of 100 matching species. Keep typing to narrow it.")
    == "Showing 6 of at least 100 matching species. Keep typing to narrow it."
✘ … at MapSuggestionTests.swift:119:9: Expectation failed:
  (sentence → "Showing 6 of 100 matching species. Keep typing to narrow it.").contains("at least")
✘ Test "one letter against the real catalogue is a page, and the list says it is" recorded an issue
  at MapSuggestionTests.swift:241:9: Expectation failed:
  (listing.remainder → .exactly(94)) == (… → .atLeast(94))
✘ Test "a row names both names, and a species with only one name says only that one" recorded an issue
  at MapSuggestionTests.swift:146:9: Expectation failed:
  (MapSuggestionCopy.rowLabel(both) → "Monterey Cypress") == "Monterey Cypress, Hesperocyparis macrocarpa"
✘ Test "choosing a suggestion narrows the map to that one species and puts its name in the field"
  recorded an issue at MapSuggestionTests.swift:286:9: Expectation failed:
  (after.speciesIDs → [D64A2DCB…, 5D2F9A2D…, F909A9EE…, 9846C997…, 04E62989…, B2FFEE94…])
    == ([chosen.id] → [F909A9EE…])
✘ … at MapSuggestionTests.swift:299:9: the same six ids, after the debounce, so the pin had not merely
  arrived late
✘ Test run with 14 tests in 1 suite failed after 1.305 seconds with 8 issues.
```

The sixth is the ticket's own sentence stated as a failure: with the pinning removed, choosing
`Monterey Cypress` leaves the map on all six species whose names contain the word.

**The UI suite — 5 of 5 red:**

```
MapSuggestionUITests.swift:167: testAPageOfMatchesSaysItIsAPage : XCTAssertTrue failed - a query
  matching a full page of the catalogue drew six rows and said nothing about the other ninety-four
MapSuggestionUITests.swift:139: testChoosingARowPutsThatSpeciesInTheField : … drew no suggestions
MapSuggestionUITests.swift:219: testLeavingTheKeyboardClosesTheList : … drew no suggestions
testTheChipsUnderTheListAreNotCoveredButReachable  failed (27.953 seconds)
testTypingDropsRowsCarryingBothNames               failed (27.102 seconds)
```

Restored, the whole unit suite is green and all five UI tests pass.

---

#### What this did not change

`SearchBar`'s ✕ and `Done` (R16) are untouched, and the ✕ still clears without dismissing the
keyboard — choosing a suggestion does dismiss it, and R25 records the rule that tells the two apart.
The matching itself (E165) is untouched: no query was written for this. The placeholder still says
species and only species (E134). No schema migration; nothing under `Data/` changed at all.

---

*E176 is reserved and deliberately absent. It is held for the San Jose ingest branch, still in flight
on 2026-07-31, which was handed the number at spawn time and cites it in source comments. The gap is
not an error and must not be filled by anything else.*


### E178 — the seed calls a landmark tree by the wrong species, and in one case by a cultivar

Two of San Francisco's 26 landmark trees carry a species in `cypress-seed.sqlite` that contradicts
the City's own landmark roster. Both would be rendered on any "great trees" surface built for #118,
and both are DECISIONS constraint 15 failures — botanical content the app would be asserting that
the city does not assert.

| landmark | SFPW roster and the City's ArcGIS landmark table | our seed |
|---|---|---|
| #17, 115 Parker Ave (designated 2005-09-03) | Howell's Manzanita, *Arctostaphylos hispidula* | `external_ref` **253858** → *Arctostaphylos manzanita 'Dr Hurd'*, common name "Dr. Hurd Manzanita" |
| #3, 1701 Franklin St (designated 1996-02-15) | Flaxleaf Paperbark, *Melaleuca linariifolia* | `external_ref` **7946** → *Melaleuca ericifolia*, common name "Heath Melaleuca" |

The first is not a synonym or a spelling drift. The City's own stated reason for the designation is
*"Rare (thought to be extinct) species of Manzanita studied by experts. Former site of Laurel Hill
Cemetary"* — the rarity **is** the designation. Our seed calls it a widely planted nursery cultivar.

The seed is not wrong about its source: it faithfully carries what DataSF `tkzw-k3nq` publishes for
those TreeIDs. The disagreement is between two of the City's own records, and it is the *landmark
roster* that carries the authority here, because §810 makes the species part of the finding the
Board adopted.

**What this does not settle:** whether a curated landmark entry may override the seed's
`species_current`, or whether it must render the city's two claims side by side. That is a #118
decision. It is recorded now so that nobody discovers it by shipping it.


### E179 — `qLegalStatus = 'Landmark tree'` is not the designation register, in either direction

The seed's `legal_status` column carries `Landmark tree` on 217 rows, and it is tempting — it is a
key join on `TreeID`, it needs no fetch, and it is already there. It is not the roster.

**It under-counts.** Four of the 26 designations carry no landmark flag anywhere in DataSF:

- #8, Two Cliff Date Palms (*Phoenix rupicola*), Dolores median → seed `25023`, flagged `DPW Maintained`
- #9, the Guadalupe Palm grove (*Brahea edulis*), 1608 Dolores → seed `25132`/`25133`, flagged `DPW Maintained`
- #22, Canary Island Pine, 2251 Filbert St → **no record at that address exists in DataSF at all**
- #23, California Buckeye, 2694 McAllister (removed 2022) → seed `255909`, flagged `Significant Tree`

**It over-counts.** Two Quesada Avenue trees are flagged `Landmark tree` and are not the designated
species — `Acacia melanoxylon` and `Prunus domestica 'Mariposa'` — where designation #7 covers "13
Canary Island Date Palms". Two rows at `2040 Sutter St` are flagged and match no roster entry at all.

**And it cannot express the state it is holding.** Public Works Code §810(d) creates a *temporary*
designation that begins on a resolution of intent and expires after 215 days unless extended.
DataSF row `111205` carries the note `Tree has temporary Landmark Status while nonimation is under
consideration. - Chris Buck 4/7/16` under the same `Landmark tree` flag; that tree was later
genuinely designated (#21, 2016-05-20). §810(b)(4) also lets the Board **rescind** a designation.
So the flag conflates designated, temporarily designated, and — potentially — rescinded, and a
boolean or a single free-text value is the wrong shape for it.


### E180 — `trees.legal_status` is documented as "DataSF `qLegalStatus`", but 130,029 `city` rows carry it

Observational, low stakes, recorded because the schema comment is load-bearing for provenance.

`build_seed.py`'s schema comment describes six columns as "Six DataSF columns carried verbatim, for
the tree page's *what the city has on file* panel". `legal_status` is one of them. But
`BUF_Street_Trees/FeatureServer/3` publishes no legal-status field of any kind — its 16 fields are
`OBJECTID`, `TREEID`, `Address`, `SiteOrder`, `PlantType`, `Prune_Status`, `Prune_Year`,
`Prune_TreeCount`, `DBH`, `DBHRange`, `COMMON`, `BOTANICAL`, `bos`, `keymap`, `Latitude`,
`Longitude` — and yet 130,029 of the seed's 133,577 `city` rows carry a non-null `legal_status`
(3,548 are null).

So for a `city` row, `legal_status` is a value from the *other* inventory joined on `TreeID`. That
is almost certainly correct behaviour and is what makes §3 of the landmark investigation possible.
But it means a `city` row's `inventory_source` does not describe where every one of its fields came
from, and the "what the city has on file" panel is quietly showing a reader one inventory's column
under another inventory's name — the precise thing the `inventory_source` comment says the column
exists to prevent. Worth a sentence in the schema comment, or a provenance stamp per field.

