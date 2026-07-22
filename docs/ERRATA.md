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
