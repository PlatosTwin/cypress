# Rulings pending — the four web nav destinations (round W-D, 2026-09-10)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename. Nothing in `web/`, `Cypress/`,
`CypressTests/` or `CypressUITests/` cites it yet, because nothing here is built.

**What this file is.** `SCREENS.md` §W1 draws four nav items and says of them, verbatim: *"`Sign in`
and the four nav items are drawn but **NOT SPECIFIED** as to destination."* DECISIONS constraint 21
makes each of those a stop-and-ask. The owner granted a scoped exception on 2026-09-10 covering
exactly those four destinations and the supporting pages they require — the shape of the one E98
recorded for M5's six unreachable entrances — on the condition that every invention under it is
written down for ratification rather than settled inside a component file. This is that writing.

**The exception's boundary, restated so it can be spent rather than assumed.** It covers `Explore`,
`Species`, `Neighborhoods`, `Data & export`, and the supporting pages those four require. It does
**not** cover the Coordinator dashboard, the moderation console, or any surface that accepts a
contribution. Two things in this file sit on that boundary and are claimed deliberately, with the
argument given where they appear: the public **planting-site page** (§4.3), because `Explore` draws
site pins and a site is not a tree, and a **page-foot attribution block** (§5.4), because NYC's
terms require human-visible text on every surface offering that data and no drawn surface holds it.

**Method, and what that is worth.** Every claim below was read out of `Fixtures/seed/schema.sql`,
`Tools/build_seed.py`, `Tools/publish_cities.py`, `Tools/inventory_contract.py`, the Swift the iOS
screens are actually built from, or `docs/RULINGS.md`. **No published pack is present in this
worktree**, so nothing here was confirmed by a query against a real pack. Four claims below are
marked **UNVERIFIED AGAINST A PACK** and each names the single query that settles it. They are
derived from the code path, which is stronger than prose and weaker than a row count, and the round
that builds these pages runs those four queries first. Three premises in the brief and in the
proposal did not survive the reading; they are in §7 rather than smoothed over.

---

## 1. What the corpus can actually answer

Every design below is downstream of this section, so it comes first.

**The published pack is `Fixtures/seed/schema.sql` narrowed.** `Tools/publish_cities.py`'s header
states the narrowing table by table, and three consequences of it decide most of this document:

1. **`species` and `species_map` are kept WHOLE in every pack.** The catalogue is shared authored
   content, not city data, and splitting it would fork curation. So every pack carries every
   species, including species with no tree in it.
2. **`species_map.tree_count` therefore describes the FUSED build**, and the publisher says so
   in-band through `seed_meta.species_map_counts_scope`.
3. **Most of `seed_meta` is the fused build receipt, kept verbatim.** The publisher rewrites exactly
   `id_spaces_in_file`, `rows_kept`, every `rows_from_<inventory>`, `trees_snapshot_on`, and adds
   `publish_*` keys. **Everything else in a pack's `seed_meta` is a fact about the fused seed, not
   about the file you opened.** `rows_status_declining`, `vacant_site_rows`, `rows_status_alive` and
   their kin are fused counts sitting inside a Queens pack.

**Ruling: no number rendered on the web is read from `seed_meta` unless the publisher rewrites it.**
Counts come from `COUNT(*)` over the pack's own `trees`, which is what the indexes are for. The
receipt is a calibration to check the count against, never the count. This applies to W-B's read
layer as much as to these four pages, and it is the single most likely way this round ships a
confident wrong number.

**The `neighborhoods` table is San Francisco's and only San Francisco's.** `Tools/build_seed.py`
loads one polygon file, `Fixtures/raw/sf_analysis_neighborhoods.geojson` (DataSF `j2bu-swwd`), and
stamps `trees.neighborhood_id` by point-in-polygon against it. The comment at the stamp says so in
capitals: *"THE POLYGONS ARE SAN FRANCISCO'S ANALYSIS NEIGHBORHOODS AND ONLY THOSE. A San Jose row
falls in none of them and gets NULL."* `publish_cities.py` then deletes every polygon no surviving
tree references — *"San Jose currently references none and ships none."* New York's trees are points
outside every San Francisco polygon, so they carry `NULL` too; NYC's borough boundaries are read
transiently by `BoroughResolver` to assign `dim_region`, and **no NYC geometry is stored in any
table** — `dim_region` has `pack_id`, `display_name`, `level`, `city_id` and no geometry column.
There is no NTA layer, no community-district layer, nothing.

> **UNVERIFIED AGAINST A PACK (1).** `SELECT COUNT(*) FROM neighborhoods;` against each of the seven
> packs. Expected: nonzero for `sf` only. If a borough pack returns rows, everything in §4 is wrong
> and should be rewritten before it is built.

**RULINGS R29 already ruled the question this creates**, and it is binding here. R29 chose "a named
polygon where the merged record holds one, a stated radius where it does not," and its decisive
argument was **not** cost: *"the unit would not be the same unit … Presenting all of those under one
word would reintroduce at the polygon level exactly the seam D16's normalized format removes at the
tree level — and it would do it invisibly, because a pill reading `District 3` and a pill reading
`Sunset/Parkside` look like the same kind of promise and are not."* The web has no reader location,
so R29's radius half is unavailable to it. What R29 leaves the web is: **name the place where the
record holds a named place, and name the region where it does not** — and never let a borough wear
the word *neighborhood*, which the schema's own `dim_region` comment already guards against ("*Cared
for by Queens* [is] a falsehood the app would ship").

**The field guide is 40 species deep and the catalogue is not.** `Fixtures/species/curated.yaml`
carries **40** entries — counted, and its own header says "the top 40 SF street-tree species by
DataSF row count" — and it is the only fixture loaded with `curated=True` in `build_seed.py`.
`leaf_retention.yaml` carries **577** entries and `nyc_species.yaml` **503**, both loaded with
`curated=False`, and both carry at most `family` and `leaf_retention`. So `id_tips`, `seasonal` and
`care_notes` are non-empty for on the order of 40 species out of a catalogue of a thousand, and 66
of `leaf_retention.yaml`'s 577 have no sourced habit at all (its own header says so).

> **UNVERIFIED AGAINST A PACK (2).** `SELECT curated, COUNT(*) FROM species GROUP BY curated;` and
> `SELECT COUNT(*) FROM species WHERE leaf_retention IS NULL;`. The denominator is what the Species
> index has to be honest about; 40 is the numerator and is solid.

**Every seeded row is a city record.** `build_seed.py` writes `verification_state = 'city_record'`
for every row it emits, and `trees.source` is `city_import`. There are no community rows and no
contributions in a pack, because contributions live in the app's *writable* database
(`AppSchema` — `visits`, `photos`, `observations`, `measurements`, `care_events`, `favorites`,
`community_notes`), which the web never sees. **Every screen-12 and screen-01 element that reads a
contribution is therefore unbuildable on the public web**, and §4 names each one rather than
quietly dropping it.

**San Jose ships a window, not a city.** `seed_meta.coverage_us-ca-sj` is `downtown`, and
`dim_region` records `level: city` deliberately — *"LEVEL IS NOT COVERAGE: San Jose is level `city`
with coverage `downtown`, because it is a whole city of which part shipped."* iOS already has the
copy for this: `CityDownloadsCopy.coverageNote` renders `Covers downtown only`. The web borrows it
verbatim rather than composing a new sentence.

---

## 2. URL grammar, and one reservation that has to be recorded

W1's transcribed URL is `cypress.app/sf/tree/9f3a-monterey-cypress`: **the first path segment is an
id space.** The four destinations take reserved top-level segments beside it.

| Path | Page |
|---|---|
| `/` | `Explore`'s region index (v1 has no separate home; see §5.2) |
| `/explore` | the same page; `/` serves it |
| `/explore/<pack_id>` | one published region — `sf`, `us-ca-sj`, `us-ny-nyc-queens`, … |
| `/species` | the catalogue index |
| `/species/<uuid-prefix>-<slug>` | one species |
| `/neighborhoods` | region index, with San Francisco's named areas beneath it |
| `/neighborhoods/sf/<slug>` | one named area |
| `/data` | `Data & export` |
| `/<id_space>/tree/<uuid-prefix>-<slug>` | W1 — **W-C's, not re-taken here** |
| `/<id_space>/site/<uuid-prefix>-<slug>` | the planting site (§4.3) |

Species and site URLs use **the same short-uuid-prefix + slug grammar W1 uses**, resolved by the
same helper, so the site has one URL grammar rather than three. The prefix length is W-C's decision
and is not re-taken here. `species.uuid` is a frozen uuidv5 of the scientific name and
`trees.uuid` is a frozen uuidv5 of `identity_prefix || external_ref` (DECISIONS constraint 13), so
both survive a rebuild, which is the property the grammar depends on.

**The reservation.** `explore`, `species`, `neighborhoods`, `data` and `site` can never become
values of `id_spaces.id`, or a city's pages would shadow a nav destination. `ID_SPACES` is
hand-entered in `Tools/inventory_contract.py` and its ids are frozen per space, so this costs
nothing today (`sf`, `us-ca-sj`, `us-ny-nyc`) and costs a published-path rewrite the day somebody
enters a colliding one. **The reserved list belongs beside `ID_SPACES`, in the file that mints the
ids** — not in the web app, which is downstream of the mistake.

---

## 3. The four destinations

### 3.1 `Explore` — the map, without a map

**What it is.** The city's trees as a field of pins you can look around, one page per published
region, with no basemap under them.

**Nearest specified thing, and it is very near.** Screen **01 · Map home**, whose own caption says
*"The main thing you do here is look around,"* and component **C18 · MapCanvas**, the reduced map
the spec already reuses on screens 15 and 18. W-6 is the ruling that there is no raster basemap;
`DECISIONS.md:153` puts per-seat map licensing permanently out of scope. This page is C18 at desktop
size, and almost nothing about it is new.

**What it shows, and what answers each element.**

| Element | Table · column |
|---|---|
| Region index: the seven published packs | `dim_region.pack_id`, `.display_name`, `.level`; `dim_city.display_name`, `.state`, `.county` through `dim_region.city_id` |
| A region's tree count | `SELECT COUNT(*) FROM trees` in that pack — never `seed_meta` (§1) |
| Coverage note, where partial | `seed_meta.coverage_<id_space>`, rendered as `Covers downtown only` (`CityDownloadsCopy.coverageNote`) |
| Pin positions | `trees.lat`, `trees.lon`, filtered through `trees_rtree` with the exact re-check the schema mandates (`t.lat BETWEEN …`), because the R\*Tree rounds outward and is a conservative filter |
| Pin kind | `trees.status` — `alive` · `declining` · `dead_reported` · `removed` · `vacant_site` |
| Neighborhood outlines, San Francisco only | `neighborhoods.geom_geojson`, `min_lat`/`max_lat`/`min_lon`/`max_lon` |
| Filter chip `In bloom` | `species.seasonal → $.bloom_months` contains the current month, joined through `trees.species_current` |
| Filter chip `Needs care` | `trees.status = 'declining'` — see below |
| Cluster badge counts | a lat/lon grid aggregate over `idx_trees_lat_lon` |
| Search | `species_trigrams` for species; `neighborhoods.name`; `dim_region.display_name` |

**`Needs care` is buildable and I nearly ruled that it was not.** `Tree.needsCare` is a pure
function of `TreeStatus`: `declining` is true, and `alive`, `deadReported`, `removed`, `vacantSite`
are false — with `deadReported` excluded on an argument its own comment gives ("a claim awaiting a
lead's confirmation … not a condition a passer-by can act on"). `status` is a pack column. So **all
three of screen 01's chips port unchanged**, and `MapFilter.Condition.narrowing(month:)` is the
function to port, not to re-derive.

**Clustering is not a decision this file gets to take.** ROADMAP §"Resolutions", item 2 already took
it: *"cluster until pins genuinely separate, and treat A1's threshold as an erratum,"* on the
measurement that at zoom 16 the median screen holds 1,899 trees and 98.6% of pins overlap. The web
inherits that ruling and adds one engineering consequence: the Queens pack alone is 298,839 rows
(the proposal's measurement of the live manifest on 2026-09-10, not re-measured here), so
**the aggregate is computed in SQL and the browser never receives a row it will not draw.**

**The vacant-site pin, which is the one drawn thing this page changes.** E107 records that "C19 has
no pin for a site, and the map therefore still draws one as `removed`, a gray dot with a bar struck
through it, which says *was and is no longer* about a basin that never held a tree" — and that a new
pin was not invented on iOS because it is a drawn decision. Under this exception it can be taken, so
it is: **a planting site draws as a hollow, dashed-outline pin.** That is not a new vocabulary, it
is the design's existing one for absence — the C14 dashed callout, screen 14's empty well, C15 and
06's disclosure are all drawn that way, and E107 chose the dashed callout on exactly that ground.
This proposal is the web's; whether iOS adopts it is the owner's and is out of this round's scope.

**What it deliberately does not contain.**

- **No basemap, no street grid, no labels** beyond San Francisco's polygon outlines. Screen 01's
  ocean, beach strip, `GOLDEN GATE PARK` block and `JUDAH ST` bands are drawn geography of one
  neighborhood of one city, transcribed from a mock; the seed carries none of it and inventing it
  for seven regions is inventing civic content (constraint 15).
- **No "near you", no geolocation prompt.** The web has no reader fix, and asking a first-time
  visitor's browser for their location to render a public page is a privacy ask v1 does not make.
  R29's radius scope is unavailable for the same reason, which is why §4 exists in the shape it does.
- **No photos** (W-7), so no bottom tree card thumbnail; the card renders name, species and status.
- **No `What tree is this?` FAB.** It opens screen 02, which is a camera and a contribution.
- **No address search.** `trees` has indexes on `(lat, lon, id)`, `species_current`,
  `neighborhood_id`, `status`, `region_id` and `(neighborhood_id, planted_on)`, and **none on
  `address`**. A `LIKE` scan over 1,097,382 rows per keystroke is not a feature, and adding an index
  is a schema change — single-seat, one migration author per round (CLAUDE.md), and this round is
  not it. Screen 01's placeholder reads `Species, street, or neighborhood…`; the web's says what it
  searches and no more.

---

### 3.2 `Species` — the field guide, and the honesty about its depth

**What it is.** One page per species the corpus holds, saying how to recognize it and where it
grows, and rendering nothing where the catalogue has nothing.

**Nearest specified thing.** Screen **07 · Species page**, block for block. Screen **08** is *not*
borrowed and §"does not contain" says why.

**What it shows, and what answers each element.**

| Element (screen 07's order) | Table · column |
|---|---|
| Eyebrow `Field guide`, H1, Latin line | `species.common_name`, `species.scientific_name` |
| Family chip | `species.family` — omitted when `NULL` |
| Habit chip | `species.leaf_retention` — omitted when `NULL`, always |
| `How to recognize it` bullets | `species.id_tips`, a JSON array of `{icon, text}` |
| The month callout | `species.care_notes`, `[{month_range, text}]`, the note whose inclusive range covers the current month |
| Phenology | `species.seasonal` — `bloom_months`, `fall_color_months`, `fruit_months`, `new_growth_months` |
| Counts, per region | `SELECT COUNT(*) FROM trees WHERE species_current = ?` in each open pack |
| Where to see one | the region's earliest-recorded individual of that species — `MIN(planted_on)` — with `trees.address` and, in San Francisco, `neighborhoods.name` |
| "See them on the map" | `/explore/<pack_id>` narrowed to this species |

**Screen 07's three taxonomy chips are two.** The mock draws `Cupressaceae` · `Evergreen conifer` ·
`Coastal`. `Cupressaceae` is `family`. `Evergreen conifer` is `leaf_retention` plus a word the
column does not carry — the chip renders the habit the enum actually holds (`evergreen`,
`deciduous`, `semi_deciduous`) and not a composed phrase. **`Coastal` has no column anywhere in the
schema** and does not ship. This is constraint 15 at the smallest possible scale and it is exactly
where these things get lost.

**The month callout is `care_notes`, not the mock's sentence.** Screen 07 draws
*"**In July:** look for closed gray cones the size of a golf ball ripening in the upper crown."*
That sentence is not in the seed. `seasonal` holds **arrays of month numbers** and no prose;
`care_notes` holds `{month_range, text}` where the text is sourced and citation-backed in
`curated.yaml` ("Prefers wind protection. Susceptible to anthracnose and powdery mildew."). So the
callout renders a `care_notes` entry verbatim when one covers the current month and renders nothing
when none does, and the month arrays drive a phenology strip rather than a sentence. Writing the
mock's sentence for 40 species would be authoring botanical prose, which is the one thing
constraint 15 names.

**D5 is enforced four times already and the web adds no fifth.** An evergreen carries no
`fall_color_months` — a database `CHECK`, `Species.init`, `Tools/validate_species.py` and
`build_seed.py` each hold it — so the phenology strip can render the column as it finds it.
`leaf_retention IS NULL` gets **no phenology surface at all**: not a neutral chip, not a gray one,
nothing (ARCHITECTURE §5 rule 5, ERRATA E9). Never `?? 'deciduous'`; the default is the bug.

**The index lists species the corpus holds.** `species` is kept whole in every pack (§1), so the
table contains species with zero trees in every published region. The index is
`… WHERE EXISTS (SELECT 1 FROM trees WHERE species_current = species.id)`, ordered by count; a
direct URL to a zero-count species still resolves and renders its name, family and habit with no
counts and no map link. Search is `species_trigrams`, whose scoring is pg_trgm's and whose query
side must agree with `SpeciesQueries.swift` character for character — `SpeciesTrigramTests` is the
executable spec for the TypeScript port, not a thing to re-derive.

**What it deliberately does not contain.**

- **No `Near you` card.** Screen 07's second count card needs a reader fix. It is absent, not zero.
- **No screen 08 anywhere.** "Species you know" is a per-person collection with a progress ring
  (`12 of 40 species`) and locked tiles. It is a count of one person's actions, it is private, and
  D1 forbids the public form of it. The web has no person.
- **No photos, no "214 photos" line, no nearby-individual thumbnails** (W-7).
- **No prose for the uncurated tail.** Roughly a thousand species carry family and habit and nothing
  else; their pages are short, and short is the correct rendering of "the catalogue does not know."
  DECISIONS §Phase-1 exclusions names "fabricated species content for the long tail" as permanently
  out.
- **No iNaturalist embed or link-out.** The ROADMAP's own status line: *"iNaturalist licensing — a
  position, not a permission."*

---

### 3.3 `Neighborhoods` — the almanac's public half, and the half that is missing

**What it is.** An index of the places the record can name — the seven published regions, and
beneath San Francisco the Analysis Neighborhoods it carries polygons for — with a page per named
area saying what grows there and what is oldest.

**Nearest specified thing.** Screen **12 · Neighborhood almanac**, whose purpose line is *"what's
happening in the neighborhood's trees, without ranking anybody,"* and whose caption opens *"There is
no leaderboard, since ranked counts reward spamming the record."* Two of its four blocks port; two
cannot, and saying which is most of the work here.

**The shape the record forces.** Only San Francisco has named areas (§1). The index therefore has
two tiers that are deliberately **not** interchangeable, which is R29's ruling applied rather than
re-taken:

- **Regions** — `dim_region`, the unit a pack is published in. San Francisco (city), San Jose (city,
  downtown coverage), and NYC's five boroughs. A borough is named as a borough.
- **Named areas** — `neighborhoods.name`, San Francisco's ~41 Analysis Neighborhoods, nested under
  San Francisco alone.

A region with no named areas says so plainly and links to `/explore/<pack_id>`. It does not get
invented polygons, a grid, or a borough relabeled as a neighborhood.

**What a named-area page shows.**

| Screen 12 block | Verdict | Table · column |
|---|---|---|
| `The elder` | **ships** | `MIN(trees.planted_on)` within `neighborhood_id`, over `idx_trees_neighborhood_planted` (the index exists for exactly this read); rendered as `<name> · in the city record since <year>` |
| `Newest neighbors` | **ships, with the clock corrected** | a `planted_on` range scan on the same index; species names from `species.common_name` |
| `Who lives here · N species` | **ships** | `COUNT(*) … GROUP BY species_current` within the area; top three plus `Everyone else`, which is the composition card as drawn |
| Planting sites | **ships, added** | `COUNT(*) WHERE status = 'vacant_site'` within the area |
| `First bloom of the year` | **cannot ship** | `AlmanacQueries.firstBloomSQL` reads `visits.phenology_tags` — the app's writable DB, absent from every pack |
| `Where eyes are needed` | **cannot ship** | `youngTreesWithoutVisitsSQL` reads `visits`; and a directed ask on a page with no contributor is an ask to nobody |

**"This spring" is a claim about the reader's calendar and the pack has a different one.** Screen 12
draws `23 trees planted this spring`. A pack's planting dates stop at its snapshot
(`seed_meta.trees_snapshot_on`, which the publisher rewrites per file to the city's own content
revision). So the web names **the most recent complete season the record contains**, by name and
year, rather than saying "this spring" against a clock the data does not share. This is
`CityRecordCopy.provenanceNote`'s own rule one level up: *"The date is the source's, never
today's."*

**Planting sites are added to the almanac on the record's own argument.** ROADMAP §"Resolutions"
item 1: *"24,200 sites are the single best answer to 'where could a tree go,' which is close to the
point of the app. Hiding them is a larger loss than an unmocked screen."* E107 then found that
`AlmanacQueries.standing` excludes them from screen 12 deliberately, and E115 corrected the
mechanism and left the product question open. The count is a fact about ground the city listed; it
counts no person and ranks nothing.

**What it deliberately does not contain.**

- **No leaderboard, no ranking, no counts of people.** Screen 12's removed footnote said so and the
  copy audit of 2026-08-23 deleted the footnote *because the screen already obeys the rule* — the
  rule did not go with the sentence. Nothing here counts visits, contributors, or "three neighbors
  saw it".
- **No coverage or attention panel.** It reads `visits`.
- **No per-city polygon invention**, which is R29 verbatim.
- **No radius scope.** R29's second half needs a reader, and there is none.

---

### 3.4 `Data & export` — where every number on this site came from

**What it is.** One page naming, per published region, the inventory the rows came from, the day it
was extracted, the terms it arrives under, and the exact version of the file this site is serving —
with a bounded download of the same rows.

**Nearest specified thing.** Two, and they are unusually close. `PROTOTYPE-FLOW.md` PART 2's
Coordinator card **`Export the weekend`** draws the buttons — `Download CSV` (filled `#1D4634`,
radius 11) and `GeoJSON` (outline) — under a mono footnote reading *"keyed on UUID + external_ref ·
method-tagged · ODbL · unverified rows stamped "not for inventory ingestion" · last SF DPW sync:
Thu 02:10, 0 conflicts"*, and §2.4 marks those buttons **"Web-only."** And on iOS,
`CityDownloadsView` already renders the per-city provenance and the NYC disclaimer block. The page
is the second wearing the first's controls.

**What it shows, and what answers each element.**

| Element | Table · column |
|---|---|
| Region name and kind | `dim_region.display_name`, `.level` |
| City, state, county | `dim_city.display_name`, `.state`, `.county` |
| The city's own urban-forestry page | `dim_city.urban_forestry_url` |
| Inventory name and source URL | `inventories.name`, `inventories.url` (one row per inventory in that pack) |
| Extraction date | `seed_meta.inventory_<id>_snapshot_on`; the reader-facing sentence is `CityRecordCopy.provenanceNote` — `From the <source>, <date>.` |
| Terms, where the receipt carries them | `seed_meta.inventory_<id>_licence` — **present for San Jose (`CC-BY`) and New York (the Data Mine terms string); absent for San Francisco** |
| Coverage | `seed_meta.coverage_<id_space>` → `Covers downtown only` |
| The file being served | `seed_meta.publish_content_rev`, plus the manifest's `version` (`s<schema>-r<content_rev>-<build_id>`) and `schema_version` |
| Row count and its composition | `COUNT(*) FROM trees`, and `GROUP BY status` for the five-value vocabulary |
| Every exported row's verification | `trees.verification_state` — `city_record` on every seeded row |

**The NYC disclaimer, which is an obligation and not a design element.** R78 ruling 2 puts the
verbatim text on the surface that offers the data; **R78 ruling 3 says the manifest's
machine-readable `attribution` array does not discharge it**, for trial packs either. The required
text, quoted from `Cypress/Features/Cities/CityDownloadsPresentation.swift:265` which quotes
`docs/operations/nyc-data-obligations.md` §4:

> The City of New York can not vouch for the accuracy or completeness of data provided by this web
> site or application or for the usefulness or integrity of the web site or application. This site
> provides applications using data that has been modified for use from its original source,
> NYC.gov, the official web site of the City of New York.

Three things the Swift constant's header forbids a future edit from doing, and they bind the web
identically: `can not` is two words and is the City's spelling, so CLAUDE.md's American-spellings
rule does not reach it; `this web site or application` stays two nouns and `web site` stays two
words; the enclosing quotation marks are not part of it. **Note that the required text names a *web
site* twice.** The obligation was written for exactly this surface, and reading it as an app-only
duty is not available.

**Ruling on where it renders.** On `/data`, and **in the page-foot attribution block of every page
that renders a New York row** — which under the region model is every borough's Explore page, every
species page whose counts include a borough, and every borough tree page W-C builds. R78's wording
is "every surface offering the pack"; a species page saying `Queens · 4,182` is offering it.

**Ruling on the guard.** `NYCDisclaimerTests` compares the Swift constant against
`docs/operations/nyc-data-obligations.md` at test time, so drift in either direction is a red test
rather than a compliance failure nobody notices. **The web ships the same test against the same
document.** A second hand-typed copy of a legally required string, checked by nothing, is the
defect this project has a whole CLAUDE.md bullet about.

**Export scope: bounded selections, and the bulk link goes to the source.** A download is offered
for a named area, a species within a region, or the current Explore viewport. It is **not** offered
for the whole corpus, for three reasons that are not performance: DECISIONS puts "public API and
researcher portal with competency-filtered datasets" in **Phase 3**, so the owner has already
sequenced this elsewhere; every source is publicly downloadable at `inventories.url` and pointing
there is both more useful and more honest than re-serving a derivative; and an unbounded endpoint on
a public host is an operational commitment W-E has not been asked to make.

**The export's columns are pinned by a contract test.** DECISIONS constraint 13: *"The export
carries `verification_state`; its headers and values are pinned by a contract test that fails CI on
diff."* The columns are the pack's own, named as the pack names them, so a row round-trips: `uuid`,
`id_space`, `external_ref`, `source`, `inventory_source`, `lat`, `lon`, `address`, `site_type`,
`status`, `species_current` resolved to `scientific_name`, `planted_on`, `dbh_city_cm_min`/`_max`,
`verification_state`, and the six city-record columns. **`external_ref` is TEXT and is never coerced
to a number** — the schema says so in capitals, and San Jose's `FACILITYID` is a string.

**What it deliberately does not contain.**

- **No ODbL claim over city rows.** §5's ODbL is the license *contributors* grant at signup
  (`PRODUCT.md:383`; screen 15's consent row, *"Share my tree records under the open database
  license"*). v1 has no contributions, so there is nothing on the public web that ODbL governs. Each
  source's own terms are stated where the receipt carries them and **nothing is stated where it does
  not** — which today means San Francisco's line names the inventory and the snapshot and stops.
  W1's transcribed `Data` row reads `ODbL · CSV / GeoJSON`, and §7 records that disagreement rather
  than resolving it inside a page.
- **No API.** No keys, no rate limits, no versioned endpoint, no JSON contract for third parties.
- **No photos, no contributor names, no counts of anybody's actions** (D1; and there are none to
  count).
- **No "last sync" freshness claim.** The Coordinator footnote's `last SF DPW sync: Thu 02:10, 0
  conflicts` describes a pipeline the public site does not run. The honest fact is the snapshot
  date, and it is already on the page.

---

## 4. Absence, and the three states it takes

**The rule, stated once.** A block renders when the record answers it and is **absent** when the
record does not. Not greyed, not zeroed, not apologized for. This is not a web convention invented
here — it is ARCHITECTURE §5 rule 6 ("aggregate surfaces below their cold-start threshold do not
render at all"), rule 5 and E9 (`leaf_retention IS NULL` gets no phenology surface *at all*), and
E107's whole argument. One consequence worth stating because it looks like a bug: **an uncurated
species page is short**, and shortness is the correct rendering of "the catalogue does not know."

**4.1 A species with no curated content.** Name, Latin, family and habit where those exist, counts
per region, the map link. No recognition card, no month callout, no phenology strip, no placeholder
copy. The page never says "no data available".

**4.2 A neighborhood with no trees cannot exist, and that is a finding rather than a design.**
`publish_cities.py` deletes every polygon no surviving tree references, so a pack's `neighborhoods`
table is by construction a list of areas that have trees. **No empty-neighborhood state is built**,
because building one is building a state the data cannot reach. What *can* happen, and does, is a
region with **no named areas at all** — six of the seven packs — and that state is designed in §3.3.
The other reachable case is a named area whose *filtered* result is empty (`In bloom` in January),
which is a result and not an absence: the map draws no pins and the filter row says which filter is
narrowing.

**4.3 A vacant planting site is its own page, and it is E107's page.** 24,200 pins — 12.2% of the
map — are basins with nothing in them (ROADMAP §Resolutions 1; E206 re-measured E11's original
12,518/6.4%, which was San Francisco alone). E107 built the iOS answer and this is it, ported
element for element, because every one of its four blocks is a pack read:

- Header `Site` — "14's `Tree` with the noun corrected."
- H1 is `trees.address`, falling back to `Planting site`; a site has no species and no name.
- Subtitle `Vacant planting site · <inventory name>`, the inventory from
  `CityRecordCopy.recordSource` reading `InventorySource.name`, never a hardcoded city — E107
  records that this exact line once said `SF city inventory` over 11,787 San Jose rows.
- A **dashed** callout: `No tree at this site.` ` The city's inventory lists a planting basin here
  and nothing growing in it.` Both verbatim from `SiteCopy`.
- The city's record — `site_type`, the citable `#<external_ref>`, and `neighborhoods.name` where
  the row carries one.
- **No status badge.** E107's reasoning: the only badge that could fire is `PLANTED <year>`, which
  would assert a planting on an empty basin.
- The nearest standing tree and its distance, which ports intact because it needs no reader
  location — `trees_rtree` bbox then squared distance with a `cos(lat)` correction, ordered
  ascending, exactly as `TreeQueries.nearest` does.

It offers no action, because every contribution this app can express asserts a tree, and on the
public web there is no action to offer at all.

**This page sits on the exception's boundary and is claimed deliberately.** W-C owns W1, the public
*tree* page. A site is not a tree — that is E107's entire finding, and rendering one as a tree page
with holes is the defect E11 recorded. `Explore` draws site pins, so a destination for them is a
supporting page the destination requires. **The orchestrator should confirm W-C is not also building
it**, because two rounds building one page is how two copies of one number start.

> **UNVERIFIED AGAINST A PACK (3).** `SELECT status, COUNT(*) FROM trees GROUP BY status;` per pack.
> The per-status split decides how many of these pages exist per region and whether `declining`
> populates `Needs care` at all in a given region. Do not read it from `seed_meta` (§1).

**4.4 A URL that resolves to nothing.** 404, and the page names the corpus version it searched
(`seed_meta.publish_content_rev`). Proposal open question 2 — what a withdrawn or moderated record
does to an indexed page — is genuinely open and v1 does not reach it: v1 renders city-record facts
only, and a city row leaves the corpus when the city stops publishing it, which is a refresh and not
a withdrawal.

---

## 5. The shell

### 5.1 The bar is the transcription, on all five pages

`padding:14px 32px`, background `surface.web`, `border-bottom:1px solid #E3E8D9`, 30×30 logo,
`Cypress` in Serif 19px/600, nav at 14px in `#66735F` with the active item `#2F6B4F`/700, `Sign in`
filled `#1D4634` at radius 10px. **Nothing about it changes across the four destinations** except
which item is active, because a chrome that reflows between pages is a chrome the reader has to
re-read.

**Which item is active where.** W1 draws `Explore` active on a *tree* page, which is transcribed and
is also right: a tree is a thing on the map. So `Explore` is active for `/explore/*`, `/*/tree/*`,
`/*/site/*` and `/`. `Species`, `Neighborhoods` and `Data & export` are active on their own subtrees.

### 5.2 `/` is Explore, because v1 has no other honest home

There is no marketing page in the mocks, and inventing one is outside this exception — it is not a
nav destination and not a page a nav destination requires. The wordmark links to `/`, which serves
the region index. If the owner wants a front page, that is a page with copy, and copy is a decision.

### 5.3 Colors come from the exported tokens, never from hex in a stylesheet

The iOS rule is "no raw hex, font sizes, or radii — tokens only" (ARCHITECTURE §6). Its web analogue
is that W-B's token export is the only source of a color: `CypressColor.surfaceWeb` already exists at
`Cypress/DesignSystem/Tokens/CypressColor.swift:207` and is `#FBFBF5`, W1's header and fact-column
ground, and it is declared `lightOnly`. Every hex quoted in this document is quoted from the
transcription for identification; **none of it is typed into a stylesheet.**

**A consequence: v1 is light only, and declares it.** W1's own surface token has no dark value.
Dark mode for the web would mean deriving a second palette for a surface the token file marks
light-only — E8's 59 derived tokens, again, on a surface nobody has drawn. The page declares
`color-scheme: light` so a dark-preference browser is told rather than left to invert. D1–D3 are
iOS's dark screens and there is no web analogue in the handoff.

### 5.4 A page-foot attribution block, which the obligation requires

No drawn surface holds the NYC disclaimer, and R78 requires it human-visible on every surface
offering that data. So every page carries a foot block: the inventories behind what is on that page,
their snapshot dates, a link to `/data`, and — where a New York row is on the page — the verbatim
block under the heading `Data disclaimer` (`CityDownloadsCopy.nycDisclaimerHeading`, ours, not the
City's) followed by the self-locating attribution line, which §4 of the obligations note marks as
**not** required and therefore ordinary house style.

### 5.5 `Sign in` — v1 has no account, and the button cannot pretend otherwise

**The facts.** `BetaCapability.accountsAvailable` is **`true`** today
(`Cypress/Core/BetaCapability.swift:47`). Read carefully, that constant does not say what a web
button would need it to say. Its own header: *"there is no remote config, no per-user rollout and no
store: these are **compile-time facts about a build**."* The build it is a fact about is the iOS
app, whose `Continue with Apple` posts to `POST /auth/oidc` on `cypress-sync`. The web has neither
half of that: the server has no CORS middleware, and `authOIDC` requires a nonce and **fails
closed**, and the web flow's nonce is not the native flow's — the proposal's §9.4 and the ROADMAP's
open item 3 both say so, and both call it an integration change rather than a client rewrite.

**R4's doctrine is the precedent and it points one way.** Screen 15 was built, tested and routed,
and the flag held its *ask* back rather than "dead-end a person on second 8 of a street-corner
visit." E100 is the same doctrine one step further: where a control cannot complete, the surface
**states the position** instead, because "a switch that forgets what it was told [is] worse than no
control." A web `Sign in` in v1 completes nothing.

**Recommendation: it does not ship in v1.** The bar's right-hand slot is empty; `margin-left:auto`
means the nav simply ends the bar, and nothing else about the transcription moves. **This is a
deviation from a transcribed element, so it is the owner's to ratify** and it is question 1 in §8.
The round that builds W1 records the deviation in `docs/errata-pending/` either way, because the
same button is drawn on that page.

### 5.6 Responsive — one measure, and no horizontal scroll

- **One reading measure per page, set on the page container**: ~700–740px at 16–17px body text.
  **No per-element `max-width: NNch` on paragraphs, deks or list items inside a wider container** —
  mixed measures leave prose wrapping early beside full-width tables and the right edges never
  align. Where a table or a map must be wider than the prose it breaks out deliberately; never the
  reverse.
- **The h1 is sized with `clamp()` so it does not wrap at desktop width.** W1's H1 is Serif
  42px/600, so the top of the clamp is 42px and the desktop rendering is the transcription:
  `clamp(28px, 4vw, 42px)`.
- **Two-column bodies stack below ~900px** — W1's `1.45fr 1fr` and the almanac's paired blocks — fact
  column beneath hero, in source order.
- **Below 700px the page padding drops to `36px 16px 90px`**, borrowed from the spec document's own
  §4 responsive rule, which is the only responsive value in the handoff.
- **Wide content scrolls inside its own `overflow-x: auto` container**; the page body never scrolls
  horizontally, at any width, on any page. **The spec's `W1 becomes horizontally scrollable` is not
  a rule about the product** — see §7.

---

## 6. What this file does not decide

The species-page URL's uuid-prefix length; W1's own layout and copy (W-C's); the pin geometry and
motion tokens (W-B's export decides what is available); the OpenGraph image for the four new pages
(W1's is specified and these are not — it is a supporting question, and if the answer is "the same
three ingredients" it should be written down as such rather than assumed); whether `cypress.app`
resolves (W-E, open); and anything the exception does not cover.

---

## 7. Premises that did not survive checking

**7.1 "`Explore` draws pins over the neighborhood polygons already in the seed."** True for one
region in seven. The proposal's §5 and the ROADMAP's "Decided in the proposal" bullet both state
this without qualification, and the polygons are San Francisco's Analysis Neighborhoods and only
those (§1). Six of the seven packs ship an empty `neighborhoods` table, so for San Jose and all five
boroughs `Explore` draws pins over **nothing** — which is still the right v1 and is not what the
sentence promises. This is a correction to a decision's stated basis, not to the decision.

**7.2 "`SCREENS.md` §4 notes … that W1 'becomes horizontally scrollable'."** §4 is titled *"Page-level
chrome of **the spec document itself**"* and opens *"Not app UI."* Its responsive bullet governs how
the *handoff HTML* displays its own device figures in a narrow browser — `zoom` at `.8`/`.73`/`.65`
for the phone frames, and sideways scrolling for the 1180px-wide chrome window, which is why the
section above it specifies a helper reading `Swipe sideways to pan the window`. It is not a
specification for the product, and a real page requiring horizontal scroll on a phone is a defect.
**`SCREENS.md` §5 item 11 already draws the same distinction** for the fixed-height screens ("Treat
everything below the header as scrollable content"), so this reading is the document's own.

**7.3 "`ARCHITECTURE.md` §5 rule 8's practice" of borrowing from the nearest specified thing.** §5
rule 8 is the stop-and-ask itself: *"When a screen or state is not in `SCREENS.md` or BUILD-PLAN §9,
**stop and ask**. Do not invent it."* The borrowing practice this document follows is **E98's** —
the M5 exception, whose three constraints (a read-only record gains no write; a surface below its
threshold renders nothing; nothing counts a user action) are the ones actually checked here. The
citation matters because rule 8 is the thing the exception suspends, not the thing that licenses the
borrowing.

**7.4 A smaller one, recorded because it will bite someone.** The brief's enumeration of the schema
lists eight of the eleven tables and omits **`dim_region`**, which is the table the whole regional
model rests on: it is the unit a pack is published in, it is why NYC is five packs rather than one,
and its `pack_id` is distribution identity — simultaneously the manifest entry's `id`, the `<id>` in
R37.2's immutable object path, and the install key on device. The other two omitted are `species_map`
and `seed_meta`.

---

## 7a. ANSWERS, 2026-09-10 — all five questions in §8 are now ruled

Taken the same day this document was written, four by the owner and one by the orchestrator. §8 is
left standing verbatim below rather than rewritten, because the trade-off each question stated is
what the answer was chosen against. The record of the owner's rounds is
`docs/rulings-pending/web-round-owner-decisions.md`.

| §8 | Question | Ruling |
|---|---|---|
| 1 | `Sign in` on the public web | **(a) — it does not ship in v1.** *Orchestrator's call, not the owner's,* and reversible the moment the web can sign anyone in. A control that visibly does nothing is what **E100** is written against, and a page invented to justify a button is invention the constraint-21 exception does not cover — that exception covers the four nav destinations and their supporting pages, and `Sign in` is neither. The slot is empty; the rest of the bar is the transcription. **This is a visible deviation from a transcribed element and is therefore an errata entry.** |
| 2 | What licence the site claims over city rows | **(a) — state each source's own terms, say nothing where the receipt has none.** Owner, 2026-09-10. ODbL is the licence *contributors* grant and v1 publishes no contributions, so claiming it over city rows would assert rights this project does not hold. W1's transcribed `Data · ODbL` row becomes an errata entry rather than a silent change. **San Francisco's row will say least**, which is the honest state, so the page says why. |
| 3 | How much data the export hands over | **(a) — bounded selections only.** Owner, 2026-09-10. A named area, a species within a region, or the current viewport; bulk traffic points at `inventories.url`. A whole-pack download was refused as scope `DECISIONS` sequenced into Phase 3, and because it would publish an internal schema as a contract. **The column-contract test is required in the same round**, not deferred. |
| 4 | Whether 24,200 planting sites get public pages | **(a) — pins and pages, per E107.** Owner, 2026-09-10. Accepted cost, stated: roughly one public page in eight says a tree is not there, and search engines will index all of them. Both alternatives were refused for named reasons — an inert pin is the control-that-does-nothing failure **E100** names and re-creates the dead end **E113** fixed, and filtering them out would make the web and the app visibly disagree about what exists in one city. |
| 5 | Whether `Neighborhoods` keeps its drawn label | **Dissolved, not answered.** The owner ruled instead that **polygons are sourced for San Jose and New York** (`docs/investigations/neighborhood-polygons.md`), so the premise — that six of seven regions have none — is being removed rather than designed around. §4 must be re-read against that: it is written for a world where only San Francisco has named areas, and that world is ending. |

### What §5's dissolution changes, and what it does not

The investigation that followed found both sources and verified them serving real geometry: **NYC DCP
2020 NTAs `9nt8-h7nd`, 262 features**, separable by borough; **San Jose's own layer 549, 297 features,
CC-BY**, a true partition (99.91% coverage of shipped trees, zero overlaps). Corpus cost
**+5,036,988 bytes, +0.71%**.

Two things this document should not assume settled:

1. **San Jose ships 295 of 297 polygons unless a migration is taken.** `neighborhoods.name` is
   `NOT NULL UNIQUE` and San Jose has two `Commercial`s and two `Guadalupe`s — the Guadalupes 8 km
   apart. The no-migration path leaves 155 of 52,775 San Jose trees (0.29%) with a null neighborhood.
   Unresolved at the time of writing.
2. **R29's two-tier model still holds and is not repealed by this.** Boroughs, council-district-derived
   areas and Analysis Neighborhoods are still not one word, and §4's refusal to present them as one is
   still right. What changes is that the lower tier stops being empty outside San Francisco.

### Three claims in §4 are now settled against a real pack

Three of this document's four `UNVERIFIED AGAINST A PACK` markers were closed by querying `us-ca-sj`,
downloaded from the public bucket and verified before it was trusted — 29,372,416 bytes and sha256
`2d979b9a…` both matching `manifest-v2.json`, and `select count(*) from trees` returning **52,775**
against the manifest's 52,775 as the control that the file queried is the file described.

| Marker | Query | Result |
|---|---|---|
| (1) | `SELECT COUNT(*) FROM neighborhoods` | **0** — confirmed, as §4 assumed |
| (2) | `SELECT curated, COUNT(*) FROM species GROUP BY curated` | **40 curated, 1,158 uncurated**; `leaf_retention` null on **353** |
| (3) | `SELECT status, COUNT(*) FROM trees GROUP BY status` | `alive` **40,982** · `vacant_site` **11,793** · **no `declining` rows at all** |

**(3) has a consequence this document predicted and could not check.** `Needs care` is specified here
as `trees.status = 'declining'`. San Jose has **zero** declining rows, so the chip matches nothing
there — and 22.3% of that city is vacant sites. Whether the NYC packs differ is **unmeasured**. A chip
that is always empty in a region is either a fact about the city record worth stating on the page, or
a chip that should not be drawn there. **That is a design question for the round that builds Explore
and it is deliberately not answered here.**

---

## 8. Questions for the owner

**1. `Sign in` on the public web.** It is drawn on W1 and its destination is unspecified; v1 has no
web account, and the server cannot mint one for a browser (no CORS; `authOIDC` fails closed on a
nonce the web flow does not have). Three options: **(a) it does not ship in v1** — the slot is
empty, the rest of the bar is the transcription, and the deviation is recorded in errata;
(b) it ships and opens a page saying accounts live in the iOS app — a page invented to justify a
button; (c) it ships disabled — a control that visibly does nothing, which is the failure E100 is
written against. **Recommend (a).** Trade-off: it is a visible deviation from a transcribed element,
and the button returns the round the web can sign someone in.

**2. What license the public site claims over city rows.** W1's transcribed `Data` row reads
`ODbL · CSV / GeoJSON`. ODbL in this project is the license *contributors* grant at signup
(`PRODUCT.md:383`, screen 15's consent row), and v1 publishes no contributions — so on the export
page ODbL would be a claim over data the project does not license. Meanwhile the receipt carries
terms for San Jose (`CC-BY`) and New York (the Data Mine terms) and **carries none for San
Francisco**: neither `Tools/inventory_contract.py` nor `seed_meta` records what DataSF's Street Tree
List is published under. Options: **(a)** state each source's own terms where the receipt has them
and say nothing where it does not, keeping W1's row as transcribed and recording the disagreement as
errata; (b) establish DataSF's terms and add an `inventory_sf_datasf_licence` key before the export
ships; (c) claim ODbL site-wide. **Recommend (a) now and (b) before the export button goes live.**
Trade-off: (a) leaves the most-used city's row saying less than the other two.

**3. How much data the export hands over.** Options: **(a)** bounded selections only — a named area,
a species within a region, the current viewport — with bulk traffic pointed at `inventories.url`;
(b) a whole-pack download; (c) no export in v1, provenance only. **Recommend (a).** DECISIONS puts
the "public API and researcher portal" in Phase 3, so (b) is scope the owner has already sequenced
later, and (c) makes a nav item named `Data & export` export nothing. Trade-off: (a) is the option
that needs a column contract test written in the same round.

**4. Whether 24,200 planting sites get public pages.** Screen 01's own caption and ROADMAP
§Resolutions 1 argue for showing them — "the single best answer to 'where could a tree go'" — and
E107 built the iOS page. On the public web each becomes an indexable page about a patch of empty
ground. Options: **(a)** they render as pins and as pages, per E107; (b) pins but no page, so a site
pin is inert on the map; (c) filtered out of the public surface entirely. **Recommend (a).**
Trade-off: 12.2% of the site's pages will be pages that say a tree is not there — which is true, and
is the thing E11 spent two entries arriving at.

**5. Whether `Neighborhoods` keeps its drawn label when six of seven regions have none.** Only San
Francisco ships polygons, and R29 forbids presenting boroughs and council districts under one word.
Options: **(a)** keep the transcribed label; the page is a region index with San Francisco's named
areas nested beneath it, and a region with no named areas says so; (b) rename the nav item to
`Places` and make regions the primary unit; (c) hide the item until a second city has polygons.
**Recommend (a)** — it keeps the transcription and puts the honest answer on the page rather than in
the label. Trade-off: a reader who clicks `Neighborhoods` from a Queens tree page finds no
neighborhoods, and the page has to say why in a sentence somebody has to write.
