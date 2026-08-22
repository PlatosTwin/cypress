# New York City: the first non-California test of the inventory contract

Survey note, 2026-08-01. Owner authorized this exploration the same day. Rests on
`Tools/inventory_contract.py` (the contract) and `docs/investigations/ca-tree-inventories.md` /
`inventory-contract.md` (the San Jose precedent), which should be read first: this note answers the
same questions in the same vocabulary, for a city whose numbering, whose species convention and
whose id spaces have no relationship to San Francisco's or San Jose's.

**Nothing here builds, runs a simulator, edits a `.py` adapter, or touches
`Tools/inventory_contract.py`'s registries.** The deliverable is this note and the cached responses
under `Fixtures/raw/nyc/`. No seed rebuild happened and none of NYC's ~899k current tree points were
downloaded — only metadata and small samples, per the brief's hard limit.

> ### Correction, 2026-08-14 — four figures below are wrong
>
> Added by the ingest round (`docs/investigations/nyc-ingest.md`), which measured a full extract of
> both datasets. **The survey's reasoning and its recommendation stand; four numbers do not.** They
> are corrected here and left in place below, struck through where they appear, rather than silently
> rewritten — a survey whose numbers change without a record is a survey nobody can date.
>
> | §  | the survey says | measured 2026-08-14 | what happened |
> |---|---|---|---|
> | §4 (twice) | the seed's **738**-species corpus | **731** | never 738; `count(*)`, `count(DISTINCT scientific_name)` and `seed_meta.species_count` all say 731, and `Tools/validate_species.py` prints it |
> | §3 box | merged undated share ≈ **86.6%** | **85.24%** | an arithmetic slip, not drift: the survey's *own* inputs give 85.24% |
> | §3 box | **160,440** undated in the seed | **160,441** | off by one |
> | §1.1 / §3 | `TPStructure` has five values | **six** | `TPStructure` is NULL on 11 of 1,121,106 rows |
>
> Two further things the survey could not have known, both now measured and both consequential:
> **`Forestry Planting Spaces` publishes 6,864 whole-row duplicates**, and its `GlobalID` — the join
> key — is therefore not unique as published; and **§6's "the schema has no slot for a standing dead
> tree" is wrong**: `trees.status` already permits `dead_reported`, which is documented as a tree
> "still standing over a pavement" (RULINGS R19). The real gap is in `InventoryRecord` and
> `STATUS_FOR_KIND`, which is a contract change and not a migration.

**Verdict up front: the live ForMS `Forestry Tree Points` layer (`hn5i-inap`) is NYC Parks' real,
maintained inventory; the famous 2015 Street Tree Census (`uvpi-gqnh`) is a ten-year-old snapshot
NYC Parks itself now points users away from.** Both are publicly redistributable. Neither is a small
lift: Tree Points alone is larger than the current 198,625-row seed, its planting-date coverage is
worse than San Jose's, its species field is packed exactly the way DataSF's was, and its address
lives in a *second* dataset that has to be joined in. None of that is a reason not to proceed — it is
the reason this is a survey and not a patch.

---

## 0. How the figures here were obtained

Every number below is either read off a response cached under `Fixtures/raw/nyc/`, or marked as an
estimate. All queries were aggregate (`count(*)`, `count(distinct …)`, `GROUP BY`) or samples capped
at `$limit=25` — never a bulk download, and every dataset's total row count came from the source's
own `count(*)`, not an estimate.

**Requests made, by host, read off this session's command history (no request was repeated once a
result was on disk):**

| host | purpose | requests |
|---|---|---:|
| `data.cityofnewyork.us` | dataset metadata (`.json` views), aggregate queries, three capped samples | 28 |
| `api.us.socrata.com` | federated catalog search, to recover `Forestry Planting Spaces`' real id after its old id 404'd | 1 |
| `www.nyc.gov` | terms of use (three URLs tried; the canonical one from 2026-07's search index had moved) | 3 |
| **total** | | **32** |

For scale: the San Jose survey this note follows made 195 requests and downloaded no bulk file
either. NYC's total is smaller because the brief named the two candidates rather than requiring
discovery across a dozen cities.

**Cached under `Fixtures/raw/nyc/`:** `forestry_tree_points.meta.json`, `2015_census.meta.json`,
`forestry_planting_spaces.meta.json`, `sample_full_25.json` (Tree Points), `census_sample8.json`,
`planting_spaces_sample5.json`, `census_distinct_species.json`, `datamine_terms.html`. Total sample
rows fetched across all three datasets: **38** — well under the 1,000-row-per-dataset cap.

**Dates.** Every count below is as fetched on 2026-08-01, against live query endpoints, except the
2015 Census's own published totals, which are the publisher's numbers from its 2016 publication.

---

## 1. The authoritative source

### 1.1 What the brief got right and what it got wrong

The brief named two candidates and both exist, but the brief's row count belongs to the wrong one:
**683,788** is the 2015 Census's own total, not a live count, and the live layer is *smaller* per
tree currently standing (899,094 "Full" tree points) but *larger* overall (1,120,697 rows, because it
also carries every retired, stumped and shafted record NYC Parks has ever logged).

| | 2015 Street Tree Census | Forestry Tree Points |
|---|---|---|
| Socrata id | `uvpi-gqnh` | `hn5i-inap` |
| Platform | Socrata, `data.cityofnewyork.us` | Socrata, `data.cityofnewyork.us` |
| Published | 2016-10-05, static | continuously, "Every 2 weeks" with automated updates enabled (metadata `updatedAt` **2026-07-28**, four days before this survey) |
| What it counts | one census event, May 2015–Oct 2016 | every tree point NYC's ForMS 2.0 asset system has ever recorded, live |
| Total rows | 683,788 | **1,120,697** |
| Rows describing a currently-standing tree | 652,173 `status='Alive'` (+13,961 `Dead`, +17,654 `Stump`) | **899,094** `TPStructure='Full'` (of which 10,441 are `TPCondition='Dead'` — still standing, not yet removed) |
| Backing system | a decennial volunteer/staff census (three have been run: 1995, 2005, 2015; no fourth is scheduled) | ForMS 2.0, "the operational database used daily by NYC foresters... for inventory and asset management" |
| Publisher's own framing | its metadata description directs readers to ForMS/Tree Points "for current tree population information" | the thing the census points to |

**`Forestry Tree Points` is the recommendation, on the same reasoning the SF investigation used to
prefer the city's own ArcGIS layer over DataSF's static export: it is what the city's own systems
run on, not a periodic export of it.** The 2015 Census is a real artifact worth keeping in mind (see
§4 — it carries a clean two-field species split that Tree Points does not), but it is ten years stale
and describes trees NYC Parks has since removed, replaced, or reclassified; treating it as current
would repeat the DataSF lesson in a new city.

### 1.2 What Tree Points does not carry on its own

Tree Points has no address field and no borough field of its own — `sample_full_25.json` confirms
this on all 25 sampled rows (`objectid`, `dbh`, `tpstructure`, `tpcondition`, `stumpdiameter`,
`plantingspaceglobalid`, `geometry`, `globalid`, `genusspecies`, `createddate`, `location`; nothing
else). Every tree point carries `PlantingSpaceGlobalID`, which joins to `GlobalID` on a **second**
dataset, `Forestry Planting Spaces` (Socrata id `82zj-84is` — its human-readable page still quotes an
older id, `4jyz-6b7u`, which 404s; the working id was recovered from the Socrata federated catalog,
one extra request, logged above). Planting Spaces carries `buildingnumber` + `streetname` (the
address), `boroughcode`, `pssite` (`Street`/`Park`), `psstatus` (`Populated`/`Empty`/`Retired`/`Empty
- DNP`/`Retired - DNP` — meaning of `DNP` not stated in the metadata; not investigated further, since
resolving it belongs to the ingest half, not this survey) and `jurisdiction` (DPR vs. other).

This is structurally the same shape as San Francisco's two-inventory build — `inventory` says which
list held the row, `attributes_from` says which list supplied the address and site-type facts — and
the contract already has a field for exactly this (`InventoryRecord.attributes_from`). It is not a
schema gap. It is two live Socrata datasets that must both be fetched and joined by
`PlantingSpaceGlobalID`/`GlobalID`, which is more moving parts than San Francisco's build (one static
CSV plus one ArcGIS layer) or San Jose's (one layer, self-contained).

**`Forestry Planting Spaces` row count: 1,091,709**, of which **only 1,084,845 are distinct records — 6,864 are whole-row duplicates** (found 2026-08-14; the join key is not unique as published), with **945,458 `Populated`** — close to but not
identical to Tree Points' 899,094 `Full`, which is expected (a `Populated` planting space transitions
to occupied slightly out of step with its tree point's `TPStructure`, and reconciling the two counts
is an ingest-time question, not a survey one).

---

## 2. Terms

NYC's canonical terms-of-use URL as indexed in mid-2026 search results, `nyc.gov/html/data/terms.html`,
now 404s — the page moved sometime before this survey. The working mirror,
`nyc.gov/html/datamine/html/data/terms.html` (fetched and cached as `datamine_terms.html`), states the
operative terms for anyone building an application from NYC Open Data:

> "By accessing datasets and feeds available through the NYC.gov Data Mine (or the 'Site'), the user
> agrees to all of the terms of use outlined below... Submitting City entities are the authoritative
> source of data available on the Data Mine... Data may be updated, corrected, overwritten and or
> refreshed at any time... **Users providing software applications using data supplied on the NYC.gov
> Data Mine must do the following: Notify the City [and] Include the following disclaimers at the
> site where the application can be accessed or downloaded:** 'The City of New York can not vouch for
> the accuracy or completeness of data provided by this web site or application... This site provides
> applications using data that has been modified for use from its original source, NYC.gov, the
> official web site of the City of New York.'"

**Redistribution is permitted — there is no no-redistribution clause, no click-through, and no
login.** But it is not unconditional the way San Jose's stated CC-BY or Oakland's CC0 are: an app
built on this data is required to *notify the City* and to *carry a specific disclaimer string*
verbatim, wherever the app is downloaded or accessed. Neither Socrata dataset metadata (`license`,
`licenseId`) states a machine-readable license — both are `null` — so the operative grant is this
page, the city's general Open Data Law (Local Law 11 of 2012, which mandates publication but was not
itself fetched — the datamine terms page is the actionable text and is quoted above), not a Socrata
license field the way San Jose's CKAN package states `cc-by`. **This is a stop-and-report item for
the owner, not a blocker found here: "notify the City" and "carry this disclaimer" are compliance
obligations Cypress does not currently have for its California sources, and whether/how to satisfy
them is a product decision, not an ingest one.**

---

## 3. Column mapping against the contract

Mapped from `forestry_tree_points.meta.json`, `Fixtures/raw/nyc/sample_full_25.json`, and
`forestry_planting_spaces.meta.json`. Values are what the *live* API returns, which in a few places
differs from the dashboard-facing column descriptions (e.g. the metadata calls `GenusSpecies` "genus
and specific epithet plus common name" — a description, not a schema — and the sampled data confirms
it is one packed field, not three).

| contract field | Tree Points source | what was found |
|---|---|---|
| `source_ref` | `GlobalID` or `OBJECTID` | Both are unique and non-null on all 25 sampled rows. `GlobalID` is a UUID (ForMS's own asset id, stable across re-publish); `OBJECTID` is the feature service's row number, exactly the id San Jose's survey ruled out for San Jose's `OBJECTID`. **`GlobalID` is the id to key on**, for the same reason `FACILITYID` beat `OBJECTID` in San Jose. |
| `scientific_name` / `common_name` | `GenusSpecies` | **Packed, DataSF's shape exactly**: `"Quercus palustris - pin oak"`, `"Morus - mulberry"` (genus only, no species epithet — a real, sampled case), `"Unknown - Unknown"`. Separator is `" - "`, not `"::"`, so `parse_qspecies` cannot be reused verbatim, but the packing problem the contract's docstring warns about ("the sink accepts DataSF's shape") is exactly what a Tree Points adapter would face on day one. |
| `species_text` | `GenusSpecies` verbatim | as above |
| `address` | **not in Tree Points** — `PlantingSpaceGlobalID` → `Forestry Planting Spaces.buildingnumber` + `.streetname` | requires the join described in §1.2 |
| `lat`, `lon` | `Location` (GeoJSON Point) or parse `Geometry` (WKT) | present on every sampled row |
| `site_type` | `Forestry Planting Spaces.pssite` (`Street`/`Park`) | via the join; not on Tree Points itself |
| `planted_on` | `PlantedDate` | **populated on 123,798 of 899,094 `Full` rows — 13.77%.** See boxed note below; this is the single most consequential number in this document. |
| `dbh_in` | `DBH` | numeric, inches, range 0–2,427 in the metadata's stated range (2,427 in is almost certainly a data-entry error worth an adapter-level sanity bound, not investigated further here) |
| status/condition | `TPCondition` (`Excellent`/`Good`/`Fair`/`Poor`/`Dead`/`Critical`/`Unknown`) and `TPStructure` (`Full`/`Retired`/`Stump`/`Shaft`/`Stump - Uprooted`, **and NULL on 11 rows** — corrected 2026-08-14) | **two separate vocabularies where the contract's `kind` wants one.** `TPStructure='Full'` with `TPCondition='Dead'` is a standing dead tree (10,441 of them) — `kind=tree`, alive-or-not is a `status`/`condition` question the contract does not yet carry (see §6). `TPStructure` other than `Full` is this source's own vacancy-and-beyond concept — richer than San Jose's binary `VACANTSITE`, because it also distinguishes a stump from a bare planting space (that distinction lives in `Forestry Planting Spaces.psstatus`, not here) and a retired record from either. |
| land context / caretaker | `Forestry Planting Spaces.jurisdiction` (DPR vs. other), `.pssite`, `.overheadutilities` | via the join; nothing on Tree Points itself carries an owner-type field the way San Jose's `OWNEDBY` does |
| `city_record` passthrough candidates | `RiskRating`/`RiskRatingDate` (455,298/455,295 null — a risk-assessment field with no equivalent anywhere in the current seed), `StumpDiameter` (427,701 non-null, only meaningful off `Full`/`Stump` rows) | not required, worth carrying as passthrough |

> **Planting date coverage, stated exactly, because two constants in
> `Cypress/Features/Map/MapFilter.swift` are weighted averages over the whole seed and every new city
> moves them (`MapFilter.swift:429`, `:438`, `:445`):** `PlantedDate` is populated on **123,798 of
> 899,094** currently-standing (`TPStructure='Full'`) NYC tree points — **13.77%**. That sits between
> San Jose's 0.42% and San Francisco's 26.03%. Folded into a merged seed at face value —
> `(~~160,440~~ 160,441 undated in the current 198,625-row seed) + (899,094 - 123,798 undated in NYC)` over
> `(198,625 + 899,094)` total — the seed-wide undated share would move from **80.78%** to
> ~~**≈86.6%**~~ **85.24%** (corrected 2026-08-14; the survey's own inputs give 85.24%), i.e. `MapFilter.undatedShareOfSeed` and its "About 4 in 5 trees" copy would both need
> re-measuring and re-asserting, exactly as `undatedShareOfSeed`'s own comment predicts happens on
> every city added. **The 2015 Census carries no planting-date field at all — 0% by construction, not
> by non-response** — so if the census were ever used instead of or alongside Tree Points, its
> contribution to that average would be a hard zero, not a smaller positive number.

**The 2015 Census, for comparison, since it is the source with the contract's cleanest species
shape:** `spc_latin` / `spc_common` are already two separate fields (`"Acer rubrum"` / `"red maple"`,
sampled directly, no packing, no adapter work) — genuinely closer to San Jose's shape than to
DataSF's, and closer than Tree Points is. It also carries a `steward` field (`None`/`1or2`/`3or4`/
`4orMore`, care-frequency banding — nothing else surveyed for this app has an analog) and a proper
`status`/`health` split (`Alive`/`Dead`/`Stump` × `Good`/`Fair`/`Poor`) that maps far more cleanly onto
a `kind`/condition distinction than Tree Points' `TPStructure`/`TPCondition` pair does. **This is the
tension the recommendation in §1 does not fully resolve**: the *current* source has worse species
hygiene and worse date coverage than the *stale* one. See §7.

---

## 4. Species burden

**Tree Points' packed `GenusSpecies` has 620 distinct values among `Full` rows** (`count(distinct
GenusSpecies)` where `TPStructure='Full'`) — comparable in scale to San Jose's 618 distinct
`NAMESCIENTIFIC` strings, but packed rather than clean, so the true distinct-taxon count is lower
once `" - "` is split and cultivar/variety suffixes are folded (not measured here; that is exactly the
kind of case-folding and mutation-tested work `SanJoseStreetTreeAdapter` did for San Jose's vacancy
vocabulary).

**The 2015 Census's clean `spc_latin` field has 132 distinct scientific names** among `Alive` rows
(5 rows `Alive` with a null `spc_latin`) — smaller, because it is a coarser identification standard
(no cultivar detail) from a decade-old volunteer census.

**Overlap against the seed's existing ~~738~~ **731**-species corpus (corrected 2026-08-14), measured by exact string match against
`species.scientific_name` in `Fixtures/seed/cypress-seed.sqlite`:** of the census's 132 distinct
`spc_latin` values, **77 match a seed species exactly and 55 do not** (`Acer griseum`, `Amelanchier`,
`Carpinus japonica`, `Chamaecyparis thyoides`, `Cornus mas`, `Crataegus`, and so on — the full list is
in this survey's working output, not reproduced here). That is a **42% new-species rate** against a
~~738~~ 731-species corpus using the cleaner of the two sources' species fields — before Tree Points' larger
and messier 620-value set is even folded in. San Jose's adapter needed a 383-line `sj_species_map.csv`
for 618 distinct strings against the same corpus; a Tree Points mapping file should be expected to be
of the same order or larger, plus the packed-string-splitting work San Jose's adapter never needed.

---

## 5. Scale

**899,094 currently-standing trees (`Forestry Tree Points`, `TPStructure='Full'`) is larger than the
current seed's 198,625 rows combined — by a factor of 4.5.** Using the full 1,120,697-row Tree Points
extract (which a faithful ingest arguably should, since `Retired`/`Stump`/`Shaft` records are real
history the contract's `kind` vocabulary can already hold as `not_a_tree` or a `status`, the way San
Jose's `Stump` rows are handled) the multiple is closer to 5.6.

The current seed file is **103,571,456 bytes** (the shipped `--source datasf` build) to
**108,007,424 bytes** (the current `cypress-seed.sqlite`, San Francisco + San Jose, 198,625 rows) —
roughly **540 bytes/row** including the species table, indexes and the neighborhood stamp. At that
rate, 899,094 NYC rows alone would add on the order of **480 MB**, before accounting for the second
dataset's join (`Forestry Planting Spaces`, 1,091,709 rows of its own, only a subset of whose columns
the contract needs) or any growth in the species table from §4's ~55–620 new taxa. **A merged seed
including NYC would very plausibly be an order of magnitude larger than today's 103–108 MB file.**

Consequences worth a decision, not a recommendation:

  * **App bundle size.** iOS App Store guidance and cellular-download thresholds (the commonly-cited
    200 MB over-cellular limit) are the practical ceiling a seed this size would approach or cross;
    that was not true of either California city.
  * **Worktree copies.** `Tools/setup_worktree.sh` copies the ~103 MB seed into every agent worktree
    today (CLAUDE.md, "Working in a worktree"). A ~5–10× larger seed multiplies that cost per agent,
    per worktree, on every parallel session — worth measuring against however many worktrees typically
    run concurrently before committing to it.
  * **Map pin budget.** Nothing surveyed here touches `Cypress/Features/Map`'s clustering or query
    behavior, but a borough with tree density comparable to San Francisco's densest neighborhoods,
    at 4.5× the row count city-wide, is a different load profile than anything the app has been
    exercised against. Worth a product/perf conversation before an ingest is scheduled, not a
    finding this survey can make on its own.

---

## 6. Id space proposal, and what the contract cannot yet express

**Proposed id space: `us-ny-nyc`, prefix `us-ny-nyc:`.** Keyed on Tree Points' `GlobalID` (a UUID,
ForMS's own stable asset id, non-null and — per the sampled data — well-formed on every row), not
`OBJECTID` (the feature service's row number, the same category of id San Jose's survey ruled out for
San Jose's own `OBJECTID`, and confirmed here to have the same problem: NYC's `OBJECTID` range in the
sample, 578803–1059991-ish, overlaps San Francisco's `TreeID` range and San Jose's `FACILITYID` range
numerically, which is exactly the collision `require_id_space` exists to prevent). `GlobalID` cannot
collide with `TreeID` or `FACILITYID` by construction (UUID vs. small integer), which is a stronger
guarantee than either California city's chosen id enjoys, but the prefix is still required by
`require_id_space` regardless, and rightly — the rule is about how spaces are declared, not about
whether a particular pair happens to be safe.

If the 2015 Census were ever ingested as a second inventory in the same city, it would need its own
id-space judgment: `tree_id` is the census's own numbering and has no stated relationship to
`GlobalID` or `OBJECTID` in either ForMS dataset (not tested here — cross-referencing a sample of
census `tree_id`s against Tree Points would be the first thing to check, the way E156 measured
San Francisco's two inventories' 0.04 m coordinate agreement before declaring them one space). Absent
that check, the safe default is that they are **two spaces**, the same conclusion San Jose's survey
reached for every pair of California sources that shared no stated numbering.

**What the contract cannot express, stated as stop-and-report items — none implemented here:**

  * **A tree's `kind` and its physical state are two different facts here, and the contract's `kind`
    vocabulary (`tree` / `planting_site` / `not_a_tree`) does not have a slot for "standing dead
    tree" versus "removed."** *(Corrected 2026-08-14: the CONTRACT lacks the slot, but the SEED
    SCHEMA does not — `trees.status` already permits `dead_reported`, defined as a tree "still
    standing over a pavement" and settled by RULINGS R19. What is missing is a condition field on
    `InventoryRecord` and a `STATUS_FOR_KIND` that reads it — a contract change, not a migration.)* San Jose's `Stump` rows collapsed cleanly to `not_a_tree`. NYC's
    `TPStructure='Full'` + `TPCondition='Dead'` (10,441 rows) is a tree that is still `kind=tree` by
    every reasonable reading — it has a trunk, a species, a location — but is not alive, which is a
    `trees.status`-shaped fact the current schema conflates with vacancy the same way #94 originally
    did for San Francisco. This is the same schema question San Jose's survey already raised in
    `inventory-contract.md` §5 (Change 1/2, `id_space` and the `inventories` table) plus a new one:
    whether `trees.status` needs a value between "alive" and "vacant_site" for "dead, not yet
    removed." **Not a migration to write here** — CLAUDE.md is explicit that schema changes are a
    STOP, and this is exactly that.
  * **Address and site-type are not on the record-supplying inventory at all — they live in a second,
    independently-updated Socrata dataset that must be joined by a foreign id.** The contract's
    `attributes_from` field already anticipates "which inventory supplied the attribute columns," and
    San Francisco already exercises it (city layer's rows, DataSF's columns), so this is not a new
    contract shape — but it would be the first source where the *adapter itself* has to perform a
    two-dataset join rather than the seed's build script choosing between two already-adapted record
    streams. Worth flagging because it changes what "an adapter" means operationally, even though it
    changes nothing in `inventory_contract.py`.
  * **`psstatus` values `Empty - DNP` and `Retired - DNP`** (3,277 rows combined) carry an unexplained
    suffix this survey could not resolve from the published metadata. Whatever `DNP` means, it is a
    `kind_basis`-relevant fact San Jose's survey did not have an analog for, and it should be resolved
    by whoever picks up the ingest half rather than guessed at here.

---

## 7. Open questions for the owner/orchestrator

  1. **Tree Points vs. the 2015 Census — is currency worth the species/date-quality cost?** §1
     recommends Tree Points on the same "what the city's own systems run on" reasoning the SF
     investigation used, but §3's tension is real: the Census has a clean two-field species split and
     zero packing to undo, at the cost of being ten years stale and silent on planting date entirely.
     A hybrid — Tree Points for currency, the Census consulted only for its species vocabulary — is
     conceivable but was not evaluated here and would need its own coordinate-agreement check in
     E156's style before being proposed as one id space.
  2. **The "notify the City" / disclaimer requirement (§2) — does Cypress take it on, and how?**
     Neither California source imposed anything like it. This is a product and legal-posture question,
     not an engineering one, and it should be answered before an NYC adapter ships regardless of which
     source is chosen.
  3. **Is a ~5–10× larger seed (§5) acceptable before NYC is scoped at all**, and if not, is a
     sub-borough or borough-by-borough ingest (e.g. Manhattan alone) a real option the contract
     already supports? Nothing in `inventory_contract.py` requires a whole-city ingest — an adapter
     could filter by `Forestry Planting Spaces.boroughcode` — but doing that changes what "the NYC
     inventory" means later if the rest is added afterward, and that sequencing is a product decision.
  4. **Does the `kind`/`status` schema gap in §6 (standing-dead trees) get resolved before or after
     an NYC migration is scoped?** It is possible to ingest NYC without touching it — map every `Dead`
     `Full` row to ordinary `alive` and lose the fact, the way the current schema already cannot
     distinguish "vacant because the city says so" from "vacant because the adapter guessed" without
     `kind_basis` in the receipt — but that would be shipping a known, named information loss rather
     than an accidental one, and it is the owner's call whether that is acceptable for a first NYC cut.
  5. **`Forestry Planting Spaces`' `DNP` suffix and the `RiskRating`/`RiskRatingDate` fields** — worth
     a direct question to NYC Parks' open-data contact (the terms page's own "notify the City"
     obligation gives a natural reason to make that contact) before anyone builds around them.
