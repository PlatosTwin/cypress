# Neighborhood polygons for San Jose and New York City

Investigation, 2026-09-10, round W-F. Answers the question the web proposal
(`docs/design-proposals/2026-09-10-web-version.md` §8 B) named as open and the owner ruled on the
same day: **source neighborhood polygons for San Jose and New York City.**

**Nothing here ships.** No seed was rebuilt, `Tools/publish_cities.py` was not run, `dist/upload.sh`
was not run. Everything below was measured against the pinned seed
(`Fixtures/seed/cypress-seed.sqlite`, 108,249,088 bytes, copied by `Tools/setup_worktree.sh`), the
live `manifest-v2.json`, and GeoJSON downloaded from each candidate source during this
investigation. The downloads live in the agent scratchpad, not the repository.

**Headline: a seed schema migration is NOT required.** The `neighborhoods` table's existing columns
hold both sources without a new column, and `AppSchema` never touches the table at all. There is one
constraint that a naive ingest would violate — `name … UNIQUE` against San Jose's two repeated names
— and §3 gives a rule that clears it without touching the DDL. The version numbers are in §3.

**Second headline, and it refutes the brief that commissioned this note: San Jose is the easy one.**
The brief expected council districts or planning areas. San Jose publishes a real, tessellating
neighborhood layer, on the same map service the project already reads its street trees from.

---

## 1. What was already true, verified rather than assumed

`Tools/build_seed.py:2105` names exactly one polygon file:

```python
nb_path = os.path.join(raw_dir, "sf_analysis_neighborhoods.geojson")
```

fetched from `NEIGHBORHOODS_GEOJSON_URL` (`build_seed.py:159-161`), which is DataSF's `j2bu-swwd`.
`load_neighborhoods` (`build_seed.py:1996`) reads it; the caller at `build_seed.py:2148` builds an
`STRtree` from it; the per-tree stamp at `build_seed.py:2453` tests each row against that one set and
writes `NULL` for anything outside it. All three line numbers in the brief were correct.

In the pinned seed:

| | rows | `neighborhood_id IS NULL` |
|---|---:|---:|
| `sf` | 145,837 | 2 |
| `us-ca-sj` | 52,788 | **52,788** |

`sqlite3 … "select id_space, count(*), sum(neighborhood_id is null) from trees group by id_space"`.
Six of the seven published packs carry zero neighborhood rows — the five NYC boroughs by the same
mechanism, since NYC is stamped against San Francisco's polygons too.

**E2 is the reason this note downloads everything itself.** ERRATA **E2** records that the dataset
BUILD-PLAN named for SF neighborhoods, `p5b7-5n3h`, is a *map visualization*: it returns 41 features
with no geometry, and point-in-polygon against it silently matches nothing.

**That failure mode is live on NYC's portal right now, on the neighbouring dataset id.** NYC Open
Data publishes both `9nt8-h7nd` ("2020 Neighborhood Tabulation Areas (NTAs)") and `4hft-v355`
("… - Mapped"). The same export command against each:

```
9nt8-h7nd  http=200  bytes=4,589,227
4hft-v355  http=200  bytes=53            # twice, on two separate probes
```

53 bytes is `{"type":"FeatureCollection","features":[` and nothing after it. `4hft-v355`'s tabular
endpoint returns `[{}]` — a row with no columns. **`4hft-v355` is NYC's `p5b7-5n3h`.** An ingest that
takes the plausible-looking "Mapped" id gets HTTP 200 and no geometry, exactly as E2 describes.

---

## 2. The sources

### 2.1 New York City — DCP 2020 Neighborhood Tabulation Areas

| | |
|---|---|
| publisher | NYC Department of City Planning (DCP), via NYC Open Data |
| dataset id | **`9nt8-h7nd`** — *2020 Neighborhood Tabulation Areas (NTAs)* |
| endpoint | `https://data.cityofnewyork.us/api/geospatial/9nt8-h7nd?method=export&format=GeoJSON` |
| bytes downloaded | **4,589,227** (`content-type: application/vnd.geo+json`) |
| features counted here | **262** |
| server's own count | **262** |
| `rowsUpdatedAt` | **2026-05-28** |
| update frequency | Quarterly (portal `custom_fields`) |
| licence field | **`license: null`, `licenseId: None`** |
| attribution | `Department of City Planning (DCP)`, `https://www.nyc.gov/content/planning/pages/resources/datasets/neighborhood-tabulation` |

**Vintage.** 2020 NTAs, not 2010. They are aggregations of 2020 census tracts and nest inside
Community District Tabulation Areas. The 2010 vintage still exists on the portal and is a different
tessellation; the 2020 one is current and is what the quarterly update advances.

**Count control.** 262 features parsed out of the downloaded file, against the server's own
`$select=count(*)` on the same id, which also returns 262 — and per borough the server's `GROUP BY
boroname` returns Queens 82 / Brooklyn 69 / Bronx 50 / Manhattan 38 / Staten Island 23, matching the
downloaded file's own tally exactly. Every feature has a geometry; all 262 are `MultiPolygon`; zero
have empty `coordinates`. This is the check E2 exists to force.

**Boroughs are separable, and no work is needed to separate them.** Every feature carries `boroname`
and `borocode`, and `publish_cities.py` already prunes per pack (§3.3), so the split falls out of the
existing pipeline rather than needing per-borough logic in `load_neighborhoods`.

**Do they cover NYC's trees?** Measured: a spread sample of **30,000 `Full` Forestry Tree Points**
from `hn5i-inap` — the same dataset `Tools/fetch_nyc_trees.py:128` reads — pulled at five offsets
across the `objectid` order and tested point-in-polygon against the 262 NTAs.

```
inside >=1 NTA:  30,000  (100.00%)
inside no NTA:        0  ( 0.00%)
inside  >1 NTA:       0
```

**Control:** the identical code path, run on 20,000 SF trees out of the seed against the seed's own
41 SF polygons, returns **20,000/20,000 (100.00%)** — which is what the seed itself claims (2 NULLs
in 145,837). A broken instrument would have failed here rather than in New York. The control was run
in the same process, immediately before the reading, in all three of this note's coverage tests.

**One product question the geometry raises.** 65 of the 262 NTAs are not residential neighborhoods —
`ntatype` is non-zero: 40 parks (`ntatype 9`), 14 cemeteries (`7`), 8 institutional (`6`, e.g.
*Brooklyn Navy Yard*, *United Nations*), 2 airports (`8`, *LaGuardia Airport*, *John F. Kennedy
International Airport*), 1 *Rikers Island* (`5`). **1,875 of the 30,000 sampled trees (6.25%) land in
one.** A reader standing in Prospect Park would have screen 12 name their neighborhood
*Green-Wood Cemetery* or *John F. Kennedy International Airport*. That is what the City's own layer
says and it is not wrong, but it is a naming decision, and DECISIONS constraint 21 makes it the
owner's. §5 stops the ingest round there.

### 2.2 San Jose — the City's own Neighborhoods layer

**The brief's premise was that San Jose is the hard one and might publish only council districts or
planning areas. It is wrong.** San Jose publishes a genuine neighborhood tessellation.

| | |
|---|---|
| publisher | City of San José |
| dataset | **`Neighborhoods`** on `data.sanjoseca.gov` (CKAN slug `neighborhoods`) |
| endpoint | `https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/MapServer/549` |
| query used | `…/549/query?where=1=1&outFields=OBJECTID,NAME,SOURCE,FACILITYID,INTID&outSR=4326&f=geojson` |
| bytes downloaded | **2,261,837** (2,179,985 of it geometry) |
| features counted here | **297** |
| server's own count | **297** (`returnCountOnly=true`) |
| licence | **CC-BY** (`license_id: cc-by`, "Creative Commons Attribution") |
| attribution obligation | City of San José, by name, wherever the data is redistributed |
| CKAN metadata modified | 2026-09-04 |

**It is layer 549 on the same map service the project already reads.** `OPN/OPN_OpenDataService`
layer **510** is `Street Trees` — the inventory in the manifest's `us-ca-sj` attribution entry today.
Same host, same service, same licence, already-established provenance.

The City's own description: *"In 2020, neighborhood boundaries were established throughout the City in
partnership with Council offices. These neighborhoods are collections of one or more census block
groups."* Built from census block groups is why it tessellates.

**Coverage, measured against the trees the pack actually ships** — the 52,788 `us-ca-sj` rows in the
pinned seed. (The live `us-ca-sj` pack carries 52,775, a build apart; the 13-row difference does not
move a 99.91% figure.)

```
SJ pack trees:  52,788
inside >=1:     52,740  (99.91%)
inside none:        48  ( 0.09%)
inside  >1:          0  ( 0.00%)
sum(polygon areas) / area of their union = 1.0000
```

Control: SF 20,000/20,000, same process, same code. The 48 misses are boundary slivers — distance to
the nearest polygon edge has a median of **11.5 m** and a maximum of **187.9 m**, none within 1 m, so
they are not a precision artefact of the download but trees sitting in gaps or just outside the city
line. They would carry `NULL`, exactly as SF's 2 do.

`sum(areas)/union = 1.0000` and **zero** trees in more than one polygon: this layer is a partition,
not a collection of overlapping catchments.

The shipped `us-ca-sj` window (a downtown box, `sj_ship_extent=downtown`) reaches **67 of the 297**
neighborhoods. The other 230 exist in the build seed and are deleted by the publisher's prune.

### 2.3 The San Jose layer that is *not* the answer, and why it matters

`data.sanjoseca.gov` also publishes **`Neighborhood and Business Associations`**
(`PLN/PLN_AdministrativeBoundaries/MapServer/9`, 268 features, CC-BY). It is the obvious hit on a
portal search for "neighborhood" and it is the wrong layer. Measured on the same 52,788 shipped trees:

```
inside >=1:  46,551  (88.2%)
inside none:  6,237  (11.8%)
inside  >1:  10,707  (20.3%)     <- one fifth of the city is in two "neighborhoods" at once
sum(areas)/union = 1.231
```

Only 145 of its 268 features are neighborhood associations at all; the rest are business associations,
home-owner associations, mobile-home associations, `Apartment Complex`, `Senior Council`, `Youth
Council`. First-hit type for the shipped trees: 34,613 Neighborhood Association, 5,281 Business
Association, 3,626 District Council, 2,454 Neighborhood Action Coalition, 572 Informal Business Group,
5 Mobile Home Association.

**It also carries personal data.** Its fields include `PRIMARYCONTACTNAME`, `PRIMARYCONTACTEMAIL`,
`PRIMARYCONTACTPHONE` and the secondary set — named private individuals who volunteer as association
board members. If the ingest round is ever tempted back to this layer, those columns must not enter
the seed. Layer 549 carries `NAME`, `SOURCE`, `LASTUPDATE`, `NOTES` and nothing personal.

### 2.4 Attribution, and a gap the round has to close

`Tools/publish_cities.py:842` `attribution_for` builds the manifest's `attribution` array by iterating
`inventories` — **tree inventories only.** Polygon layers are not inventories, so they contribute
nothing. Read from the live manifest:

```json
"sf": [ {"inventory": "sf_city",  …}, {"inventory": "sf_datasf", …} ]
```

**DataSF's `j2bu-swwd` appears nowhere.** The polygon layer's attribution is not carried today. For
San Francisco that is a latent gap; **for San Jose it is a licence obligation**, because CC-BY
requires attribution as a condition of the grant. The ingest round must extend the attribution path
to polygon sources, not just fill the table.

Related: `build_seed.py:3263-3264` writes `neighborhoods_dataset_id` and `neighborhoods_source_url`
as **singular** `seed_meta` keys. Three sources need three sets, in the `inventory_<tag>_*` shape
`attribution_for` already reads.

**NYC's licence is a `null` and is not therefore permissive.** The project has been here before: for
`hn5i-inap` and `82zj-84is` the seed records
`"NYC Open Data / Data Mine terms; notification + verbatim disclaimer required"` rather than a licence
string (`build_seed.py:3141-3146`), and `docs/investigations/nyc-ingest.md` §2 has the reasoning.
`9nt8-h7nd` publishes `license: null` in exactly the same way and is a City dataset on the same
portal, so **the same terms and the same disclaimer obligation must be presumed to apply**, and the
NTA source recorded the same way. This note does not re-derive the Data Mine terms; it says the
question is already answered in this repository and the answer transfers.

---

## 3. Does this change the schema? **No.**

### 3.1 The three version spaces, read from the code

Read now, from the code, per CLAUDE.md — not from this note next time either:

| space | symbol | file | value today |
|---|---|---|---:|
| writable database migration counter | `AppSchema.currentVersion` | `Cypress/Data/Store/AppSchema.swift:58` | **21** |
| published seed / city-file version | `SeedDatabase.newestKnownSchemaVersion` | `Cypress/Data/Store/SeedDatabase.swift:111` | **17** |
| manifest envelope format, written | `MANIFEST_FORMAT` | `Tools/publish_cities.py:203` | **2** |
| manifest envelope format, read | `CityManifest.knownFormats` | `Cypress/Data/Cities/CityManifest.swift:51` | **{1, 2}** |

`AppSchema.currentVersion` is computed as `migrations.map(\.version).max()`; the array holds
`Migration(version: N …)` for N = 1…21 with no gaps. Calibration: the grep that produced that list was
checked for `version: N` occurrences *outside* a `Migration(` constructor in the same file — there are
none, so the 21 matches are 21 migrations and not 21 coincidences. `SEED_SCHEMA_VERSION` in
`publish_cities.py:193` is also 17 and `Tools/test_publish_cities.py:302` asserts the two agree.

### 3.2 Nothing proposed here touches any of them

**`AppSchema` (21) is not involved at all.** The writable database has no `neighborhoods` table; its
own header comment (`AppSchema.swift:6`) lists `neighborhoods` among the tables that live in the seed
and states that nothing in `AppSchema` duplicates them. No migration, no migration author, no seat.

**`SeedDatabase.newestKnownSchemaVersion` (17) stays 17,** because the DDL does not change. Every pack
is a copy of one build seed narrowed by `publish_cities.py` (§3.3), so every pack carries the
`neighborhoods` table; what six of them carry is zero rows, because
`publish_cities.py:669` deletes every polygon no surviving tree references and outside SF no tree
references one. (Directly confirmed on the downloaded `us-ca-sj` pack by the round that commissioned
this note; confirmed here structurally, from the split code and from the pinned seed's
`sum(neighborhood_id is null) = 52,788` for `us-ca-sj`.) **Filling rows is a content change, not a
schema change:** it advances `content_rev`, not `schema_version`.

**`MANIFEST_FORMAT` (2) is untouched.** No manifest key changes shape. (An added
`attribution` entry per §2.4 is a new element in an existing array, which format 2 already carries.)

### 3.3 Do the new sources' fields fit the existing columns?

`Fixtures/seed/schema.sql:126`:

```sql
CREATE TABLE neighborhoods (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    geom_geojson TEXT NOT NULL,
    min_lat REAL NOT NULL, max_lat REAL NOT NULL,
    min_lon REAL NOT NULL, max_lon REAL NOT NULL,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);
```

`load_neighborhoods` needs `name` and a geometry and derives the rest. Field mapping:

| source | name field | geometry | fits? |
|---|---|---|---|
| DataSF `j2bu-swwd` | `nhood` | MultiPolygon | current behaviour |
| NYC `9nt8-h7nd` | **`ntaname`** | MultiPolygon | yes |
| San Jose layer 549 | **`NAME`** | Polygon / MultiPolygon | yes |

`load_neighborhoods` currently reads `props.get("nhood") or props.get("name")`. Both new sources need
their key added — a one-line change in the loader, not a column. Nothing either source carries is
*required* by the app: `boroname`, `ntatype`, `nta2020`, `SOURCE` are all droppable. **If the round
decides it wants `ntatype` on the row** — to let a reader distinguish a park NTA from a residential
one — *that* is a new column and *that* is a schema bump. §5 keeps it out of scope for exactly that
reason.

### 3.4 The one real constraint problem: `name … UNIQUE`

**San Jose's layer holds 297 features and 295 distinct names.** Two names repeat:

| name | OBJECTID | centroid | `SOURCE` |
|---|---:|---|---|
| Commercial | 138 | 37.37735, −121.86446 | *(null)* |
| Commercial | 279 | 37.36605, −121.88490 | Fill in |
| Guadalupe | 226 | 37.22602, −121.89628 | *(null)* |
| Guadalupe | 266 | 37.30026, −121.87921 | Fill in |

The two *Guadalupe* polygons are **8 km apart**. These are two different places that share a name, not
a split polygon. `INSERT INTO neighborhoods` would fail on the second of each pair. Since the whole
layer is inserted before the publisher prunes, this stops the build regardless of the ship window —
and `Commercial` is inside the shipped downtown window anyway.

**No collisions across cities, today.** SF's 41 ∩ NYC's 262 = ∅; SF ∩ SJ = ∅; NYC ∩ SJ = ∅, exact and
casefolded. (Control: the same set-intersection code run SF-against-SF returns all 41, so the
comparison is real and not defeated by encoding or whitespace.) But **that is a property of today's
data, not of the pipeline** — the same reasoning `nyc-ingest.md` §2 gives for RULING D19 — and one
Socrata refresh renaming an NTA to `Chinatown` would break a build with no code change.

Cross-*pack* the problem is already solved and should not be re-solved. `InventoryUnionSQL.swift:204`
`createNeighborhoods` appends each installed arm's neighborhoods whole, renumbered by
`MAX(id) + ROW_NUMBER() OVER (ORDER BY n.id)`, into a temp table mirrored with
`inlineConstraints: ["id": "PRIMARY KEY"]` — **the UNIQUE on `name` is deliberately not carried into
the union**, because `InventoryUnion.swift:35` states that a neighborhood name is unique only within a
city. So two installed packs may each hold a `Chinatown` and the app is fine. The constraint bites
only *within one file*.

**And the reader-facing disambiguation does not cover this case either.**
`AreaPickerSheet.options` (`Cypress/Features/Journal/AreaPickerSheet.swift:91-110`) qualifies a name
that two *cities* share as `Downtown · San Jose` (`AreaPickerCopy.qualified`, line 212), pinned by
`AreaPickerTests.collidingNamesAreQualified` (line 439). San Jose's two `Commercial`s are in **one**
city, so the qualifier would produce two chips both reading `Commercial · San Jose` — the exact
condition that test asserts against (`#expect(Set(labels).count == labels.count)`). Option 3 below is
therefore not just a DDL change; it also needs a second disambiguator the app does not have.

**Three ways out, and the recommendation.**

1. **Merge same-named polygons in one source into one `MultiPolygon` row.** No DDL change. But it
   makes *Guadalupe* a single discontiguous place spanning 8 km, and screen 12 would count trees from
   both. Semantically wrong; **not recommended**.
2. **Disambiguate the name at ingest** ("Commercial (North San José)"). No DDL change, but it is
   inventing civic content, which DECISIONS constraint 15 forbids, and there is no field in the layer
   to disambiguate *from* — `SOURCE` is null on one of each pair. **Not available.**
3. **Drop the `UNIQUE` and key uniqueness where it actually lives.** Correct, and it is a **seed
   schema change**: `newestKnownSchemaVersion` 17 → 18, one migration author, a stop-and-report.

**Recommended: none of the three in the ingest round.** Option 3 is right and it is a decision, not an
implementation detail — so the ingest round should carry San Jose's layer with a **documented,
ruled dedupe rule in D19's shape** ("among features sharing a `NAME` in one source, keep the one with
the smallest numeric `OBJECTID`, and record the dropped ones in `seed_meta`"), which loses 2 of 297
polygons and 0.09%-scale coverage, and put option 3 to the owner as a separate, later schema round.
A rule is needed either way, because "the names happen not to collide" is not a pipeline property.

**This is the answer to the brief's critical question: no migration is required, and the round does
not need to STOP — provided it takes the dedupe rule rather than the DDL.** If the owner prefers the
DDL, the round stops there and hands the schema bump to a named migration author.

---

## 4. What it costs

**Calibration, and an error it caught.** The per-byte figure comes from the SF rows that already
exist: 41 rows holding **1,710,901** bytes of `geom_geojson` occupy **1,753,088** bytes of `dbstat`
pages plus **4,096** for `sqlite_autoindex_neighborhoods_1` — a ratio of **1.0271** bytes of file per
byte of geometry.

The first version of that query said **3.5983**, because it selected `dbstat` rows with
`name LIKE '%neighborhood%'` — which also matches `idx_trees_neighborhood` (1,908,736 bytes) and
`idx_trees_neighborhood_planted` (2,490,368 bytes). Those are indexes on **`trees`**, not on
`neighborhoods`, and they already hold one entry per tree whether the value is `NULL` or an integer,
so they barely grow when the column is filled. Left in, they would have overstated the corpus cost by
3.5×. The corrected query names the two objects instead of globbing them.

Published corpus today, from the live `manifest-v2.json` (`sum(bytes)`): **713,605,120** bytes — the
brief's 713.6 MB, confirmed.

| pack | polygons | geometry bytes | est. added | pack now | + |
|---|---:|---:|---:|---:|---:|
| `us-ny-nyc-manhattan` | 38 | 361,300 | 371,073 | 66,891,776 | 0.55% |
| `us-ny-nyc-brooklyn` | 69 | 1,104,554 | 1,134,434 | 159,080,448 | 0.71% |
| `us-ny-nyc-queens` | 82 | 1,891,873 | 1,943,051 | 199,163,904 | 0.98% |
| `us-ny-nyc-bronx` | 50 | 617,172 | 633,867 | 92,061,696 | 0.69% |
| `us-ny-nyc-staten-island` | 23 | 527,864 | 542,143 | 84,238,336 | 0.64% |
| `us-ca-sj` | 67 | 401,558 | 412,420 | 29,372,416 | 1.40% |
| `sf` | 41 | *(unchanged)* | 0 | 82,796,544 | 0.00% |
| **corpus** | | | **+5,036,988** | **713,605,120 → 718,642,108** | **+0.71%** |

The NYC rows are an **upper bound**: they assume every NTA in the borough contains at least one tree
and therefore survives `publish_cities.py:669`'s prune. The San Jose row is exact — 67 is the measured
count of polygons the shipped downtown window actually reaches.

**Why NYC is cheap.** DataSF's polygons are far heavier than either new source: SF averages 41,729
geometry bytes per polygon (one, *Bayview Hunters Point*, is 739,062 bytes on its own) against NYC's
17,186 and San Jose's 7,340. 559 new polygons cost less than a third of what 41 SF ones do.

**The bundled app seed is the bigger relative hit and is easy to miss.**
`Cypress/Resources/cypress-seed.sqlite` is built by `build_seed.py`, which inserts **every** polygon
before any prune runs. San Jose's whole 297-polygon layer adds ~2,238,957 bytes to a 108,249,088-byte
bundled file, **+2.07%**, of which the shipped downtown window uses 67 polygons. The ingest round
should prune `neighborhoods` at the end of `build_seed.py` the way `publish_cities.py:669` already
does, or accept the 2 MB.

**A cost the table does not show: the whole corpus republishes.** `load_neighborhoods` assigns ids by
sorting *all* features by name globally, so adding 559 polygons renumbers San Francisco's 41. Every SF
tree's `neighborhood_id` changes value, the `sf` pack's bytes and `sha256` change, and all 82,796,544
bytes of it are a fresh download for every existing SF reader even though nothing about San Francisco
changed. Making the id assignment per-source and stable would avoid that; it is worth doing in the
same round, and it is a `build_seed.py` change, not a schema one.

---

## 5. What breaks

`SpeciesQueries.resolveNeighborhood` (`Cypress/Data/Store/SpeciesQueries.swift:508`) does **not** do
point-in-polygon at read time. It takes the `neighborhood_id` of the **nearest inventoried tree**
within `AlmanacLimits.neighborhoodResolutionRadiusM` (400 m, `Cypress/Data/API/Almanac.swift:431`) and
returns that tree's neighborhood — the E44 decision, so that the count card and the map cannot
disagree. So the moment `trees.neighborhood_id` stops being `NULL` in a pack, **every**
neighborhood-scoped surface in that city switches path, with no code change.

### 5.1 Behaviour that is correct today and changes

| surface | today, outside SF | after |
|---|---|---|
| Screen 12, the almanac's area | `AlmanacArea.radius(1,200 m)`, `name == nil` (R29's second arm) | a named polygon area |
| Screen 12's provenance line | `AreaPickerCopy.resolvedFromFixRadius` | the polygon's sentence |
| Screen 07 `Near you` | counted over 1,200 m | counted over the neighborhood |
| Screen 08 recognition ring | denominator over 1,200 m of the most-visited tree | denominator over its neighborhood |
| Coverage panel / vacant-site row | invisible — `neighborhood_id IS NULL` excludes every SJ and NYC row | populated |
| `AreaPickerSheet` | offers the radius | offers the named area |
| Web `Explore` / `Neighborhoods` (unbuilt) | six blank rectangles | seven cities of polygons |

Note `CityQueries.resolveIDSpace` (`Cypress/Data/Store/CityQueries.swift:71`, 1,200 m via
`AlmanacLimits.fallbackRadiusM`, `Almanac.swift:496`) is **unaffected** — it reads `trees.id_space`,
not `neighborhood_id`, and it already answers in every city.

**No new performance regime.** Trees per polygon, from each pack's manifest `tree_count` over its
polygon count: SF **3,560** (busiest single neighborhood in the seed: 11,142), Manhattan 2,603,
Bronx 2,757, Brooklyn 3,443, Queens 3,644, Staten Island 5,453, San Jose **787**. Every one is the
same order as San Francisco's, and Staten Island's average is half SF's busiest, so the
neighborhood-scoped reads land in the range `idx_trees_neighborhood` and
`idx_trees_neighborhood_planted` already serve. This is a check, not a promise: it was not measured
on a device, and the ingest round should run the almanac query-plan suites on the rebuilt seed.

### 5.2 Tests that pin the current behaviour and go red — by name

These were written to fail. `SecondCityGeographyTests.swift:74-76` says so out loud: *"If a San Jose
polygon layer ever lands, every fallback assertion below would silently start measuring the polygon
path; this makes them fail loudly instead."* That is the project's own guards-green-when-the-defect-is-
present rule, applied in advance. They should be **updated, not deleted**, and each needs a new home
for the claim it was making.

| file | test / symbol | why it goes red |
|---|---|---|
| `CypressTests/AlmanacGeographyTests.swift` | `sanJoseResolvesTheFallback` | asserts `COUNT(*) WHERE id_space='us-ca-sj' AND neighborhood_id IS NOT NULL == 0` (line 157), then `#expect(polygon == nil)` and `area.area == .radius(fallbackRadiusM)`, `area.name == nil` |
| `CypressTests/SecondCityGeographyTests.swift` | `requireSanJoseCarriesNoPolygons` (line 77), called by `sanJoseGetsANearYouCard` (line 164) and `sanJoseContributorGetsARing` (line 344) | same precondition; plus `#expect(… == .radius(meters: AlmanacLimits.fallbackRadiusM))` at lines 170 and 357 |
| `CypressTests/AreaPickerTests.swift` | `sanJoseIsAlwaysTheFallback` (~line 599) | `#expect(counted.null == counted.total)` over all `us-ca-sj` rows, then asserts the radius area and `AreaPickerCopy.resolvedFromFixRadius` |
| `CypressTests/AlmanacVacantSiteTests.swift` | the vacant-site scope assertions (lines 96–145) | `vacantSitesWithNoNeighborhood` is pinned at **11,787** / **11,793** in two corpus variants and drops toward 0; `neighborhoodsWithNoVacantSite` (pinned 0) moves as new neighborhoods arrive with no vacant sites |
| `CypressTests/SeedCorpus.swift` | `cityWithSanJose` (line 352) and the other variants at lines 389–390, 494–495, 566–567 | the constants above, plus the doc comments at lines 347–350 and 503–505 that state the SF-only fact as a finding |

Prose that becomes wrong and must move in the same PR:

- `Cypress/Data/Store/AlmanacScope.swift:8` — "…are invisible to screen 12 and to the coverage panel"
- `Cypress/Data/API/LocalAPI.swift:2553` — "in San Jose, whose 52,788 rows hold `neighborhood_id IS NULL`"
- `Cypress/Features/Almanac/AlmanacPresentation.swift:165` and
  `Cypress/Features/Journal/AreaPickerSheet.swift:235` — "it was every reader in the bundle's second city, permanently"
- `Tools/build_seed.py:2453-2460` — the stamp's comment, which names the SF-only rule as the design
- `Cypress/Data/Store/InventoryUnionSQL.swift:23` — "41 neighborhoods"

`MapFilter.swift` was checked and does not read `neighborhood_id`; the brief's mention of it does not
land. `AlmanacLimits.fixCanResolveAnArea` (`Almanac.swift:471`) is `accuracyM <= radiusM` and is
unaffected — but its *effect* changes, because the almanac's caller passes the 400 m radius, so
readers in NYC and San Jose newly become subject to the approximate-location refusal (F17) that only
SF readers meet today. **That is a real behaviour change for six of seven cities and it is not
currently covered by any test.**

R29 itself needs re-reading before the ingest round writes anything: its second arm — the radius
fallback — stops being reachable in six cities, and the ruling's own reasoning was written when it
was the only answer outside SF.

---

## 6. The sequence for the ingest round

1. **Take the two decisions in §5 and §3.4 to the owner first.** Three questions, none of them an
   implementation detail:
   - the 65 non-residential NTAs (parks, cemeteries, airports, Rikers Island) — carry them, or filter
     to `ntatype = '0'` and let 6.25% of NYC trees carry `NULL`? DECISIONS constraint 21.
   - San Jose's two repeated names — the D19-shaped dedupe rule (recommended, no schema change), or
     drop the `UNIQUE` (schema bump, separate round, named migration author)?
   - R29's second arm becoming unreachable in six of seven cities.
2. **Fetch and cache**, in the shape `Tools/fetch_nyc_trees.py` established: a fetcher that records
   each source's own server-side count and its `rowsUpdatedAt`/`LASTUPDATE` into the cache manifest,
   refuses a cache directory `git check-ignore` does not cover, and **asserts every downloaded feature
   has a non-empty geometry** — E2's check, promoted from a thing an investigator did to a thing the
   tool does.
3. **Generalise `load_neighborhoods`** (`build_seed.py:1996`) to take a list of `(source_tag, path,
   name_field)`, add the ruled dedupe, and **make the integer id assignment per-source and stable** so
   San Francisco's 41 do not renumber (§4). Prune unreferenced polygons at the end of the build.
4. **Per-source `seed_meta` keys** in the `inventory_<tag>_*` shape, and extend
   `publish_cities.py:842` `attribution_for` to carry polygon sources — CC-BY makes San Jose's a
   licence obligation, and DataSF's has been missing all along (§2.4).
5. **Rebuild the seed and verify before touching the publisher.** The numbers to check, each against
   a control: 41 + 262 + 295 = 598 rows in `neighborhoods` (or 597, per the dedupe rule); SF's
   `neighborhood_id IS NULL` still **2**; San Jose's **48**; NYC's near **0**. **A rebuild that leaves
   SF's 2 unchanged is the control that the SF path did not move.** Beware
   `build_seed --limit` — it leaves a 147-species stub.
6. **Update the five test files in §5.2 in the same PR**, and red-proof each one: break the new
   polygon path, watch the test go red *for the reason expected*, restore. A test that goes red on
   the wrong assertion has proved nothing.
7. **Then STOP.** Republishing is 7 packs and ~718 MB through the Fly relay
   (`server/README.md`, "Publishing without local credentials") and needs the owner's explicit
   go-ahead, which this round does not have and must not assume. Everything above is local and
   reversible; the publish is neither.

---

## 7. What this note found the brief to be wrong about

- **"San Jose is the harder one — it may publish council districts or planning areas rather than
  neighborhoods."** It publishes a true tessellating neighborhood layer, on the same map service the
  project already reads street trees from (§2.2). San Jose is the *easier* of the two.
- **"A clear negative finding is a good outcome here."** There is no negative finding for San Jose.
  The negative finding is about the *obvious* San Jose layer — `Neighborhood and Business
  Associations`, 20.3% double-covered, 11.8% uncovered, carrying volunteers' phone numbers — which is
  what a portal search returns first (§2.3).
- **"This is the critical question … if your task turns out to need a migration, STOP and report."**
  It does not need one. The blocker is a `UNIQUE` constraint on two San Jose rows, which a ruling
  clears without touching the DDL (§3.4).
- The brief's line numbers (`build_seed.py:2105`, `1996`, `2148`; 400 m; 1,200 m) all checked out.
