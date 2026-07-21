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
inventing it") no dark values were invented. Each gap is marked `// TODO: no dark value specified`
in `CypressColor.swift`. Dark mode is milestone M4; this needs a design answer before then.

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
