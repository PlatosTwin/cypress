# The city's tree map is not backed by `tkzw-k3nq`

Investigation, 2026-07-25. Triggered by tree `276198` (`1 TWIN PEAKS BLVD`, Monterey Pine),
which the project owner found on San Francisco's public Street Tree Map and which does not
exist in DataSF `tkzw-k3nq` at all.

**Verdict up front: the key is compatible.** The city's service uses the same `TreeID` space
we do. A source switch or a merge would *not* orphan existing tree uuids. The gap is real but
asymmetric, and it is much smaller in the direction the owner noticed than in the other.

Everything below was measured against the live services on 2026-07-25. Read-only: `query`
requests only, no writes, no bulk extraction, no credentials.

---

## 1. The source

The public map at <https://bsm.sfdpw.org/urbanforestry/> is an Esri JS 4.18 app. Its page
loads ArcGIS Online webmap `b11a000d57e14b3a9dec64bc65e93082` (the source comments it
`//PROD`; a second id `ec39c97c9c38495db29a3a62d72cc1a6` is present but commented `//DEV`).
Both webmaps point their "Street Trees" operational layer at the same feature layer:

```
https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/BUF_Street_Trees/FeatureServer/3
```

- Layer name `StreetTrees`, point geometry, WKID 102100 (Web Mercator).
- Parent item: ArcGIS Online `d066424916f443c4b004c3d87703d7c0`, title **BUF Street Trees**,
  owner `gis@dpw`, org `Zs2aNLFN00jrS4gG`, item `source: "City and County of San Francisco"`,
  sharing `public`. Sibling layers in the same service: `DCPNeighborhoodsTreeCount` (1),
  `DCPNeighborhoodsTreeDensity`, `BOSDistrictsTreeDensity` (2). A separate service,
  `Key_Map_Grid_Tree_Prune_Schedule/FeatureServer/0`, carries the pruning grid.
- `editingInfo.lastEditDate` = 2026-07-20. Live.
- No token is required. My queries sent none. (The app page does embed an Esri API key in
  client-side JavaScript; it is for basemap tiles. I did not use it and have not recorded it here.)

### The exact query that returns 276198

```
https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/BUF_Street_Trees/FeatureServer/3/query?where=TREEID%3D276198&outFields=*&returnGeometry=true&f=json
```

Response attributes, field for field against the owner's screenshot:

| Screenshot label | Service field | Value |
|---|---|---|
| Address | `Address` | `1 TWIN PEAKS BLVD` |
| Tree ID# | `TREEID` | `276198` |
| Species | `COMMON` + `BOTANICAL` | `Monterey Pine` / `Pinus radiata` |
| Trunk Size (in.) | `DBH` | `36` |
| Board of Supervisor District | `bos` | `08` |
| Keymap Grid | `keymap` | `211` |
| Last Pruned | `Prune_Year` | `Completed 20210601` |

Also returned: `OBJECTID` 109109, `SiteOrder` 1, `PlantType` `Tree`, `Prune_Status`
`Completed`, `Prune_TreeCount` 833, `DBHRange` 3, `Latitude` 37.75916, `Longitude` -122.448345.

Every visible field matches. The screenshot labels are the webmap's `popupInfo` aliases; "Species"
and "Last Pruned" are Arcade expressions over `COMMON`/`BOTANICAL` and `Prune_Status`/`Prune_Year`
respectively.

---

## 2. Inventory

**Record count: 133,577.** (`where=1=1&returnCountOnly=true`.)

`TREEID` is **unique and never null**: a `groupByFieldsForStatistics=TREEID` +
`having COUNT(OBJECTID) > 1` query returns 0 groups; `count(TREEID)` with
`returnDistinctValues=true` returns 133,577; `TREEID IS NULL` returns 0. `OBJECTID` runs
1..133,577 contiguously.

### Full field list (16)

| Field | Type | Notes |
|---|---|---|
| `OBJECTID` | OID | 1..133577, contiguous |
| `TREEID` | integer | 1..277733, unique, no nulls — **the DataSF TreeID** |
| `Address` | string(100) | uppercase in most rows, mixed case in newer ones; 23 blank |
| `SiteOrder` | integer | |
| `COMMON` | string(200) | common name |
| `BOTANICAL` | string(200) | scientific name; 557 null; 136 literally `Potential Site` |
| `DBH` | integer | inches; 2,647 zero, 6,372 null |
| `Latitude` | double | WGS84 |
| `Longitude` | double | WGS84 |
| `PlantType` | string(200) | **`Tree` for all 133,577 rows** |
| `bos` | string(10) | supervisor district, `01`..`11`; 757 null |
| `keymap` | string(10) | pruning grid id |
| `Prune_Status` | string(20) | `Completed` / `Active` / `Coming Soon` / null |
| `Prune_TreeCount` | integer | trees in the tree's *keymap grid*, not a tree attribute |
| `Prune_Year` | string(30) | e.g. `Completed 20210601`, `Active 2026`, `Upcoming` |
| `DBHRange` | integer | 1–3 symbology bucket |

Query capabilities: `Query,Extract`; `maxRecordCount` 2000 (`standardMaxRecordCount` 16000);
pagination, statistics, `having`, `distinct`, SQL expressions all supported; formats JSON,
geoJSON, PBF.

### Pruning coverage — and a correction worth reading

Raw coverage looks excellent:

| `Prune_Status` | rows | share |
|---|---|---|
| `Completed` | 119,090 | 89.2% |
| `Active` | 9,387 | 7.0% |
| `Coming Soon` | 4,339 | 3.2% |
| null | 761 | 0.6% |

**But `Prune_Year` is a property of the keymap grid, not of the individual tree.** There are
only **106 distinct `Prune_Year` values across 133,577 trees**. 5,147 trees share
`Completed 20210601` — the same value the owner saw on 276198. `Prune_TreeCount` for 276198
is 833, which is the tree count of keymap grid 211, not anything about that tree. The webmap's
own Arcade expression reads `Prune_Status`/`Prune_Year` straight through, and the city's About
panel says as much: *"Last Pruned is the date associated with the status of a Keymap Grid."*

So the service does **not** publish a per-tree pruning history. It publishes "the block this
tree sits on was last pruned on date X". That is still more than `tkzw-k3nq` has (which has
nothing), but it is not a per-tree maintenance log, and it should not be presented as one.

This also undercuts one inference in the brief: 276198 showing a 2021 prune date does **not**
prove the record is old. Grid 211 was pruned in June 2021; a tree added to the inventory in
2025 and sitting in grid 211 would display exactly the same string.

### What it contains, and what it does not

- **No vacant sites as a category.** `PlantType` is `Tree` for every row. There is no
  `qSiteInfo`, no `qLegalStatus`, no caretaker, no plot size, no plant date, no permit notes.
  136 rows do carry the literal `BOTANICAL = 'Potential Site'`, so a small number of empty
  sites leak in via the species field, but there is no site-status column.
- **Not a park-tree inventory.** Measured by sampling DataSF rows grouped by `qCaretaker` and
  asking the service whether it holds them: `Rec/Park` 29.7% present (n=300), `Port` 22.7%,
  `PUC` 10.0%, `Housing Authority` 5.5%, `Purchasing Dept` 4.7%, versus `Private` 66.0% and
  `DPW` 52.7%. It is a right-of-way street-tree layer that happens to include some
  agency-caretaker trees, not a parks dataset.
- **No private-tree inventory either** — see the legal-status table in section 4.

### Field-for-field against `tkzw-k3nq`'s eighteen columns

| `tkzw-k3nq` | ArcGIS equivalent |
|---|---|
| `TreeID` | `TREEID` — same key |
| `qSpecies` (`Botanical :: Common`) | `BOTANICAL` + `COMMON`, split into two |
| `qAddress` | `Address` |
| `SiteOrder` | `SiteOrder` |
| `DBH` | `DBH` |
| `PlantType` | `PlantType` (degenerate: always `Tree`) |
| `Latitude` / `Longitude` | `Latitude` / `Longitude` |
| `qLegalStatus` | **absent** |
| `qSiteInfo` | **absent** |
| `qCaretaker` / `qCareAssistant` | **absent** |
| `PlantDate` | **absent** |
| `PlotSize` | **absent** |
| `PermitNotes` | **absent** |
| `XCoord` / `YCoord` | **absent** (geometry is Web Mercator) |
| `Location` | **absent** (geometry instead) |
| — | `bos`, `keymap`, `Prune_Status`, `Prune_Year`, `Prune_TreeCount`, `DBHRange` **new** |

The two sources are not nested. ArcGIS adds five useful fields and drops nine.

### License and terms — partially unestablished

- `tkzw-k3nq` is unambiguous: `licenseId` `PDDL`, *Open Data Commons Public Domain Dedication
  and License*, attribution "San Francisco Public Works", publishing frequency Daily, and its
  `rowsUpdatedAt` is 2026-07-23.
- **The ArcGIS service publishes no license.** The item's `licenseInfo`, `accessInformation`,
  `description` and `snippet` are all `null`; the layer's `copyrightText` is empty. It is
  shared publicly and advertises the `Extract` capability, which is the ArcGIS-level permission
  to download, but that is a server capability flag, not a grant of terms. **I could not find
  any terms-of-use or attribution statement attached to this service.** The only text the city
  attaches anywhere is the map's own disclaimer, quoted in full because it is the closest thing
  to terms that exists: *"The database and information populating this map are continually in
  development. As we refine and improve the quality of the data inputted, more accurate
  information will be reflected on this map. Questions and feedback welcome!
  urbanforestry@sfdpw.org"*
- **No documented rate limit and no published bulk download.** ArcGIS Online hosted services do
  not publish per-client quotas. `maxRecordCount` 2000 with pagination is the only stated
  constraint. There is no Hub download page, no `.csv` endpoint, no `?f=geojson` bulk export
  documented for this item; the item is not listed (`listed: false`) and has no categories.

If we ever wanted to depend on this service, the right move is to email `urbanforestry@sfdpw.org`
and ask. I did not, because that is a message on the owner's behalf and outside this task.

---

## 3. Key compatibility — the critical question

**Verdict: the ArcGIS layer uses the same `TreeID` space as `tkzw-k3nq`. Existing uuids stay
valid. Switching or merging sources does not orphan community data.**

`Tools/build_seed.py` derives `trees.uuid = uuid5(NS_TREE, <DataSF TreeID as ASCII>)` and stores
`external_ref INTEGER UNIQUE -- DataSF TreeID`. So identity is a pure function of the integer key,
and the whole question reduces to: does ArcGIS `TREEID` *n* describe the same physical tree as
DataSF `TreeID` *n*?

### Evidence

**Sample A — uniform over ArcGIS records.** `OBJECTID` is contiguous 1..133,577, so a random
sample of `OBJECTID`s is a uniform sample of records. n = 4,000, seed 4242.
**97.53% of sampled ArcGIS records have a `TREEID` that exists in our DataSF snapshot**
(3,901 / 4,000).

**Sample B — 80 non-overlapping random `TREEID` windows of 500 ids** (40,000 ids of the 277,733
id-space, seed 31337), giving an exact set comparison inside each window and **17,793 ids
present in both sources**. Attribute agreement over those 17,793:

| Check | Agreement |
|---|---|
| Address identical (case-normalized) | 88.01% |
| Address same street + same/near number | **99.36%** |
| Coordinates within 1 m | **98.65%** |
| Coordinates within 3 m | 98.66% |
| Coordinates within 50 m | 99.44% |
| Median coordinate offset | **0.040 m** |
| p95 offset | 0.06 m |
| `SiteOrder` agrees | 99.53% |
| `DBH` agrees exactly | 98.57% |
| Botanical name agrees | 98.44% |

A median offset of **four centimeters** across 17,793 independently keyed records is not
something two unrelated id spaces can produce. The two sources are the same survey.

**The residual disagreements are attribute drift, not identity drift.** In a fresh 30-window
sample (5,698 comparable pairs, seed 5150): 98.51% of botanical names agree, 0.21% are the same
genus with a different epithet or cultivar, and 1.28% differ at genus level. Of those 73
genus-level disagreements, **95.9% still share the same address and sit within 3 meters of each
other**. That is the signature of a site that was re-surveyed or replanted — the record is the
same site, one source has newer species information — not of a key collision.

The address mismatches are almost entirely cosmetic: ArcGIS uppercases, and DataSF writes an `X`
suffix on some numbers (`3995X Alemany Blvd` vs `3995 ALEMANY BLVD`). Normalizing street and
number takes agreement from 88.01% to 99.36%.

**Systematic disagreement found: none.** No constant id offset, no block shift, no duplicate
keys. I looked for id shifts specifically after noticing consecutive-id species swaps around
`223193`/`223204` and `529`/`531`; they do not extend beyond isolated pairs and the addresses do
not support a shift hypothesis. I am recording the observation because it is unexplained, but it
affects a fraction of 1% and does not change the verdict.

**One methodological correction, so nobody inherits a wrong number from me.** My first pass
reported "642 duplicate TREEIDs" in the ArcGIS layer. That was an artifact of my own overlapping
sample windows double-counting records, not a property of the service. The direct test
(`having COUNT(OBJECTID) > 1`) returns zero. `TREEID` is unique.

---

## 4. The gap, in both directions

Two independent estimators, which agree:

| | estimate | 95% CI |
|---|---|---|
| ArcGIS total | **133,577** | exact |
| DataSF `tkzw-k3nq` total | **198,435** | exact (live count, matches our CSV) |
| Intersection | **≈ 130,000** | 129,628–130,914 (from Sample A) |
| **In ArcGIS, not in DataSF** | **≈ 3,300** | 2,663–3,949 |
| **In DataSF, not in ArcGIS** | **≈ 68,800** | 66,400–71,200 |

(Sample A gives intersection 130,271; an independent uniform sample of 6,000 DataSF rows checked
against the service gives 65.33% present → intersection 129,644, CI 127,255–132,034. Consistent.)

### Direction 1 — what the city has that we do not (≈3,300)

This is the small direction, and 276198 lives in the most distinctive part of it.

**1,338 of them have `TREEID > 276035`**, and 276035 is exactly the maximum `TreeID` in the live
`tkzw-k3nq` (confirmed: `$select=max(TreeID)` returns 276035, `count` returns 198,435). Not one
of those 1,338 is in DataSF. The city's operational layer has issued ids up to 277,733; the open
data export has never carried anything above 276,035, despite being flagged "Daily" and having
been refreshed two days ago. That is a ceiling in the export pipeline, not staleness in our copy.

**276198 is unusual within that block.** The block is overwhelmingly new plantings — 1,028 of
1,338 have `DBH` 0, another 112 null, 94 have `DBH` 1; only **45 of 1,338 have `DBH ≥ 12`**.
276198 is a 36-inch Monterey Pine. It is far more likely a *mature tree newly added to the
inventory* (a survey catching up with reality on Twin Peaks) than a new planting. The block
spreads across all eleven supervisor districts (heaviest: D10 356, D11 235, D05 158) and 998
distinct addresses, so it is not one project.

The other ~2,000 are scattered through the existing id range, skew small (`DBH` 0 or 3 dominate),
and are otherwise unremarkable.

### Direction 2 — what we have that the city's map does not (≈68,800)

Much larger, and highly structured. Presence rate in the ArcGIS layer, by DataSF `qLegalStatus`,
each from a random sample of up to 500 rows of that status:

| `qLegalStatus` | population | present in ArcGIS |
|---|---|---|
| `Prune Opt Out` | 196 | 98.98% |
| `Street Tree Maintenance Opt Out` | 58 | 91.38% |
| `Landmark tree` | 244 | 88.93% |
| `DPW Maintained` | 142,587 | **84.80%** |
| `Planning Code 138.1 required` | 1,143 | 63.40% |
| `Significant Tree` | 3,148 | 61.60% |
| `Section 806 (d)` | 809 | 60.60% |
| `Property Tree` | 368 | 33.70% |
| `Private` | 348 | 28.74% |
| `Undocumented` | 8,995 | **17.00%** |
| `Permitted Site` | 40,351 | **1.80%** |
| `Section 143` | 131 | **0.00%** |

Populations in that table are counts in the raw `tkzw-k3nq` CSV (198,435 rows), not in the seed
(195,309 rows) — the seed's counts are lower by `build_seed.py`'s legitimate coordinate and
bounding-box drops, e.g. 142,587 raw `DPW Maintained` against 141,478 seeded.

And by `PlantType`: `Tree` 63.67%, `Landscaping` (326 rows) 0.33%, lowercase `tree` (3 rows) 0%.

So the gap is dominated by two populations the city's map deliberately does not show:

- **`Permitted Site` — ~39,600 absent.** A permit was issued for a planting site. The tree may
  not exist yet. The city's operational layer holds planted trees, so these are simply not in it.
- **`Undocumented` — ~7,500 absent.** Trees observed but not adopted into the maintenance
  inventory.
- Plus **~21,700 `DPW Maintained` rows absent**, which is the genuinely interesting residue. In
  the samples these skew toward `qCaretaker` `DPW` and `Private`, `Sidewalk: Curb side : Cutout`
  and `Median : Cutout` sites, and about 16% of them have `DBH` 0 or blank. I could not determine
  what distinguishes them — see section 7.

**The owner's two examples, resolved.** `107407` (`Undocumented`) and `40713` (`Permitted Site`)
are **absent from the ArcGIS layer itself**, not filtered by the app:

```
.../FeatureServer/3/query?where=TREEID+IN+(107407,40713)&outFields=*&f=json  ->  "features": []
```

I also checked the webmap: neither the PROD nor the DEV webmap sets a `definitionExpression` on
the Street Trees layer, so the app draws the whole layer. The city's map does not show those two
trees because its source does not contain them. Our map is not wrong to show them; the two
systems are inventorying different things.

---

## 5. Where "125,000" comes from, and what it counts

Two direct citations, both from the city:

- The Street Tree Map's own **About** panel, at <https://bsm.sfdpw.org/urbanforestry/>:
  *"The Bureau of Urban Forestry (BUF) gathers and maintains a database of approximately 125,000
  public trees on sidewalks, medians, and other public rights-of-way."*
- The StreetTreeSF program page, <https://sfpublicworks.org/streettreesf>: *"StreetTreeSF is a
  voter-approved initiative managed by San Francisco Public Works to professionally maintain and
  care for the 125,000-plus street trees growing throughout all neighborhoods in the City."*

The figure originates with **Proposition E (November 2016)**, which passed with about 79% and,
effective 1 July 2017, moved responsibility for the city's street trees and the sidewalks around
them from property owners to Public Works. Contemporary descriptions of the measure use
"124,000-plus" and "125,000-plus" interchangeably.

**So 125,000 counts living street trees in the public right-of-way that Public Works maintains
under StreetTreeSF.** It is a rounded program figure from 2016, still quoted in 2026, and it is
not a count of rows in any dataset.

How our numbers relate to it:

| population | count | comparable to 125,000? |
|---|---|---|
| Our seed, all rows | 195,309 | No — includes 12,518 vacant sites, 38,568 `Permitted Site`, 8,878 `Undocumented` |
| Our seed, `alive` | 182,791 | No — still includes permitted and undocumented |
| Our seed, `alive` AND `DPW Maintained` | **139,012** | **Closest analogue in our data** |
| The city's ArcGIS layer | **133,577** | **Closest analogue anywhere** |

The city's own operational inventory is 133,577 today — about 7% above the number the city keeps
quoting. Both of our comparable figures sit above 125,000, which is what you would expect after
nine years of planting against a figure fixed in 2016. **Nothing in our seed is wrong because it
is bigger than 125,000.** 195,309 and 125,000 are answers to different questions; the honest
comparison is 139,012 against 133,577, and those are within 4% of each other.

I could not find any published, dated reconciliation of the 125,000 figure — no city document
breaks it down by status or restates it for a recent year. The number appears to be quoted
forward unchanged.

---

## 6. Recommendation

### Option A — stay on `tkzw-k3nq`

**Cost: nothing. Known limitation: ~3,300 trees the city shows that we do not, and no pruning
information of any kind.**

`tkzw-k3nq` is PDDL public domain, updated daily, documented, and its eighteen columns carry
nine fields the ArcGIS layer does not have — legal status, site info, caretaker, plant date,
plot size, permit notes — several of which the app already depends on. Its weaknesses are the
1,338-id export ceiling and the absent pruning data.

**This is the right default.** The defect the owner found is real but it is 2.5% of the city's
layer and 1.6% of the union of the two sources.

### Option B — switch to `BUF_Street_Trees`

**Do not.** Uuids survive (the key is the same), but we would lose `qLegalStatus`, `qSiteInfo`,
`qCaretaker`, `PlantDate`, `PlotSize` and `PermitNotes` outright, and drop ~68,800 records —
including every `Permitted Site` and most `Undocumented` trees. The seed would shrink from
195,309 to ~133,577 and every feature keyed off site type or legal status would need rebuilding.
We would also be depending on a service with no published license, no documented download, and
no stated availability guarantee, in exchange for grid-level pruning dates.

### Option C — merge: keep `tkzw-k3nq` as the spine, enrich from ArcGIS

**The only option worth building, and only when someone has time for it.**

- Join on `TreeID` → `TREEID`. Section 3 says this is safe. Every existing uuid is preserved
  because every existing `TreeID` is preserved.
- Add ~3,300 new trees, of which ~1,338 are above the DataSF ceiling. New rows get new uuids from
  the existing `uuid5(NS_TREE, TreeID)` rule with no special-casing — that is the whole benefit of
  the key being compatible.
- Add `bos`, `keymap`, `Prune_Status`, `Prune_Year` as new nullable columns. **Label the pruning
  data honestly in the UI** — it is "this block was last pruned on X", not "this tree was pruned
  on X". Getting that label wrong would be worse than not shipping the field.
- Leave existing attributes alone where the two disagree, or prefer ArcGIS only for `DBH` and
  species where its record is demonstrably newer. The 1.28% genus-level disagreement is a real
  editorial decision and should not be resolved by a silent last-writer-wins.
- Cost: one new fetch stage in `Tools/build_seed.py` (133,577 records at 2,000 per page ≈ 67
  paged requests), a schema addition, a reproducibility story for a second upstream that has no
  snapshot date, and the license question answered by email first.

**Impact on the ~195,309 existing uuids under any option: none.** That is the finding that
matters. Because ArcGIS `TREEID` *is* DataSF `TreeID`, no photograph, favorite, measurement,
care log or site lineage is at risk from any of these three choices.

---

## 7. What I could not establish

Stated plainly, because a guess here is worth less than a gap.

1. **Why ~21,700 `DPW Maintained` trees are missing from the city's operational layer.** They
   are 84.8% present, so 15.2% are absent, and that residue is large. My samples show them
   skewing to `qCaretaker` `DPW` and `Private` and to curb-side cutouts, but I found no field
   that separates them. They could be removed trees `tkzw-k3nq` still lists, or records the
   ArcGIS pipeline drops for reasons not exposed in either schema. **Unresolved.**
2. **Why the DataSF export stops at `TreeID` 276035** while the operational layer issues ids to
   277733, despite the dataset being flagged Daily and refreshed 2026-07-23. This looks like a
   pipeline ceiling, but I have no evidence for the mechanism and did not find any DataSF errata
   describing it. **Unresolved.**
3. **The license and terms of the ArcGIS service.** There are none published — `licenseInfo`,
   `accessInformation` and `copyrightText` are all empty. Whether bulk extraction is *permitted*
   as opposed to *technically enabled* is genuinely unknown. I did not contact the city.
4. **Whether the service is rate limited.** Nothing is documented. My ~200 requests over roughly
   half an hour were never throttled, which proves very little.
5. **Whether the ArcGIS layer or `tkzw-k3nq` is more accurate** where the two disagree on species
   (1.28% at genus level) or coordinates (1.26% beyond 10 m). I established that they refer to
   the same tree. I did not establish which one is right, and neither source carries a per-record
   survey date that would let me decide.
6. **The consecutive-id species swaps** noted in section 3 (`529`/`531`, `223193`/`223204`).
   Observed, unexplained, small.
7. **How often the ArcGIS layer updates.** `lastEditDate` was 2026-07-20 when I looked. One
   reading is not a cadence.

---

## Reproducing this

Throwaway scripts used for this investigation are under `Tools/investigate/`. They are not part
of the build and can be deleted. They read the DataSF CSV from the main checkout and issue
read-only `query` requests to the public feature service.

| script | what it does |
|---|---|
| `arc.py` | POST helper for the feature service `query` endpoint |
| `load_local.py` | indexes `Fixtures/raw/street_tree_list.csv` by `TreeID` |
| `inventory.py` | field value distributions on the ArcGIS layer |
| `uniq.py` | `TREEID` uniqueness and the id ceiling |
| `keycheck.py` | first (overlapping-window) comparison — superseded by `windows.py` |
| `windows.py` | 80 non-overlapping windows, attribute agreement |
| `arcsample.py` | uniform sample over ArcGIS `OBJECTID` — the reverse-gap estimator |
| `localsample.py` | uniform sample over DataSF rows — the forward-gap estimator |
| `bystatus.py` | presence rate by `qLegalStatus`, site family, `PlantType` |
| `final.py` | character of the above-ceiling block, caretaker presence, species triage |
| `drift.py` | address/coordinate agreement among species disagreements |

---

## Addendum, 2026-07-25: the license question, answered

The report above left the license "partially unestablished" and made it the blocker on #91. It is
now established, and the answer is no.

**The PDDL grant stops at the hostname.** DataSF's terms of use define their own scope: *Data*
means "any of the data that is available through data.sfgov.org." Everything the seed is built from
lives there — `tkzw-k3nq` carries `licenseId` `PDDL`, attribution "San Francisco Public Works", and
the terms permit copying, redistribution, modification and commercial use with no attribution
clause of their own. That is a clean grant, and it covers what we already ship.

`services.arcgis.com/Zs2aNLFN00jrS4gG` is not `data.sfgov.org`. Re-checked directly at both levels:

| field | FeatureServer root | layer 3 (`StreetTrees`) |
|---|---|---|
| `copyrightText` | empty string | empty string |
| `description` | empty string | empty string |
| `serviceDescription` | empty string | absent |
| `licenseInfo` | absent | absent |
| `accessInformation` | absent | absent |
| terms / attribution text | absent | absent |

`capabilities` is `Query,Extract`. **`Extract` is a server capability flag, not a grant of terms** —
it says the software is willing, not that the city is. So there is no published permission for bulk
extraction of this layer, and the license that makes our current pipeline safe does not reach it.

**Ruling: do not ingest the ArcGIS layer.** Not because it is forbidden — nobody has said either
way — but because "no license published" is not the same as permission, and a beta that ships
132,000 records taken from an unlicensed endpoint has made a claim on the city's behalf that the
city never made. That is the same error as the `Owner of Tree` field (E143) and the permit notes
(E145): reading an absence as a license to assert. If the owner wants this data, the route is an
email to SF Public Works, and the answer goes in this file.

## What the honesty problem actually is, and that it needs no permission

The integrity complaint that started this — the city says ~125,000 street trees, our map shows
records the city's map does not — survives the source question, and the part of it we can fix is
entirely inside data we already hold under PDDL.

Confirmed against the live API on 2026-07-25:

- **TreeID 276198 is genuinely absent from `tkzw-k3nq`.** Not dropped by our pipeline — the live
  dataset returns no record for it, while the city's own map shows it with a 2021 pruning date. The
  gap is the source's, exactly as the report concluded.
- **TreeIDs 266901 and 223762 are both present**, both `DPW Maintained`, both on Twin Peaks Blvd,
  and both with `qSiteInfo` ending `: Yard`. They are real records; the neighbors the owner saw are
  not phantoms.

What our 195,309 rows are:

| | count |
|---|---|
| `status = alive` | 182,791 |
| `status = vacant_site` — a planting site with no tree in it | **12,518** |
| `plant_type = Landscaping` — not a tree | 318 |
| `legal_status = Undocumented` | 8,878 |
| alive **and** `plant_type` tree | 182,639 |
| alive **and** `DPW Maintained` — the comparable to the city's maintained count | **139,012** |

So the "125,000" figure is not evidence of a defect: it is Proposition E's rounded 2016 count of
*maintained* street trees, and our comparable is 139,012 against the city's live 133,577 — inside
4%. What *is* a defect is calling all 195,309 "San Francisco's street trees" on a screen, when
12,518 of them are empty holes in the pavement and 318 are shrubs.

**Follow-up worth its own item:** `plant_type` is not normalized — 194,988 `Tree`, 318
`Landscaping`, and **3 rows spelled `tree`** (TreeIDs 253212, 253634, 96598). Any filter written as
`plant_type = 'Tree'` silently drops those three. That one is ours, not the city's.

## A correction to an earlier claim in this file

The report says our CSV matches the live dataset "row for row". The count still matches today —
198,435 both sides — but `tkzw-k3nq` was last updated **2026-07-23**, two days before this addendum,
and it publishes daily. An unchanged row count across an update proves only that additions and
removals balanced; it is not evidence that the contents agree. "Not stale" was measured once and has
a shelf life of about a day, and row-count equality was never the test it was used as.

---

# Addendum, 2026-07-26: the switch, built

The license ruling above has been **overridden by the project owner**, who has seen it and said:
*"Just use the official city data. It's fine."* He has accepted the risk of ingesting a service that
publishes no license, for a local beta on his own phone. That settles it; the ruling in the previous
addendum stands as a record of the reasoning and is no longer a blocker, and the question is not to
be re-opened. Nothing about it goes in the app's UI.

Issue #91 is therefore built. What follows is what was measured and done, replacing the report's
estimates with exact counts.

## What ships

`Tools/build_seed.py` takes `--source`:

| | rows | species | vacant sites | planting dates | seed |
|---|---|---|---|---|---|
| `--source city` **(default)** | **133,577** | 577 | **153** | 28,747 | 71.4 MB |
| `--source datasf` | 195,309 | 569 | 12,518 | 70,067 | 103.6 MB |

**The row set is the city's; seven of the attribute columns are the export's.** #91 asks which trees
exist, and only SF Public Works' operational layer knows that — it is what its public map draws. It
is a much poorer record of *facts*, publishing sixteen fields against the export's eighteen and
dropping nine. So the spine is the city's layer (a record it does not list is not in the seed,
whatever the export says) and `qLegalStatus`, `qSiteInfo`, `qCaretaker`, `qCareAssistant`,
`PlantDate`, `PlotSize` and `PermitNotes` are joined on `TreeID` for the 130,070 records both list.
Nothing is added by that join. The 3,507 records only the city has carry NULL in those seven.

This was not the first design. A build that took the city's layer alone was measured first, and it
is why the join exists:

| | city layer alone | city rows + export attributes |
|---|---|---|
| `legal_status` | 0 | 130,029 |
| `plot_size` | 0 | 111,326 |
| planting dates | **0** | 28,747 |
| trees `LandContext` can place | **0** | 130,071 |

With no planting dates the almanac's elder, plantings and coverage reads return nothing **for the
whole city**, screen 12 loses three rows, and `LandContext.inferred(from:)` can place no tree so the
`Stands on` sentence never draws. Three test suites went green while asserting the exclusion of an
empty set, and two UI tests failed outright because the rows they tap no longer render.

**Extraction, 2026-07-26.** 67 sequential POSTs to the feature service, `resultRecordCount=2000` at
the layer's own `maxRecordCount`, a second between pages, ordered by `OBJECTID`, each page written to
its own file so a re-run skips what is already cached. 133,577 features, 0 duplicate `TREEID`s, no
retries needed. `editingInfo.lastEditDate` was 2026-07-20. `Tools/fetch_city_trees.py` is the only
thing in the repo that talks to the service; `build_seed.py` reads the cache and never makes a
request, so a rebuild costs the city nothing and works offline. The cache lands in `Fixtures/raw/`,
which `.gitignore` already excludes for the same reason it excludes the DataSF CSV.

## The gap, exactly — no longer an estimate

The report's samples gave ≈3,300 and ≈68,800. The full extract gives:

| | count |
|---|---|
| TreeIDs in **both** inventories | **130,070** |
| In DataSF, **not** in the city's layer | **65,239** |
| In the city's layer, **not** in DataSF | **3,507** |

### What the 65,239 dropped rows are

Non-overlapping and exhaustive:

| bucket | count | what it is |
|---|---|---|
| `Permitted Site`, `alive` | 29,050 | a permit was issued for a planting site; the tree may not exist |
| `Permitted Site`, vacant site | 8,657 | same, with no species recorded either |
| **other legal status, `alive`** | **17,443** | **the crux — see below** |
| `Undocumented`, `alive` | 6,486 | observed, never adopted into the maintenance inventory |
| other legal status, vacant site | 2,733 | empty basins the city does not list |
| `Undocumented`, vacant site | 870 | |

**The crux bucket, 17,443 rows**, is the one that can be wrong rather than merely different. They are
`alive`, carry an ordinary legal status and sit on ordinary sites: 15,348 `DPW Maintained`, 940
`Significant Tree`, 341 `Planning Code 138.1 required`, 18 `Landmark tree`; by site family 14,593
`Sidewalk`, 1,600 `Median`, 762 `Front Yard`. The report could not determine what separates them from
the 84.8% of `DPW Maintained` rows the city does list, and neither could this round. They are either
trees removed since the export last agreed with the operational layer, or records the city's pipeline
drops for a reason neither schema exposes. **Unresolved, and the largest thing this switch takes on
faith.**

**Vacant planting sites are the visible casualty: 12,518 → 153.** The city's layer has no vacant-site
category — `PlantType` is `Tree` on all 133,577 records — and the only empty sites that survive are
the 136 whose `BOTANICAL` reads literally `Potential Site` plus a handful with no species at all.
Features #11 (the vacant-site state), #31 (the redirect off the tree profile) and #32 (the almanac's
empty-site count) still work and are still tested, but they now describe 153 sites, and **17 of the
41 neighborhoods have none**, so screen 12's empty-site row is absent across a third of the city.
This is the one loss the join cannot repair: a vacant site is a *row*, and rows come from the spine.
If that surface matters more than agreeing with the city's map, `--source datasf` is one command
away.

### Is 133,577 a loss of 62,000 trees, or a more truthful number?

**A more truthful number, and the arithmetic says so rather than the vibe.** Of the 65,239 rows that
leave, **47,796 (73%) are not living street trees by their own labels**:

| | count | why it is not a maintained street tree |
|---|---|---|
| vacant planting sites | 12,260 | a hole in the pavement; there is no tree |
| `Permitted Site`, `alive` | 29,050 | a permit was issued; the tree may not exist yet |
| `Undocumented`, `alive` | 6,486 | observed, never adopted into the maintenance inventory |
| **not-a-maintained-tree subtotal** | **47,796** | |
| the crux bucket | 17,443 | genuinely ambiguous — see above |

So the honest statement is not "we lost 62,000 trees". It is "we stopped counting 47,796 records that
were never living maintained street trees, and we took a position on 17,443 more that nobody can
currently adjudicate". The residual uncertainty is 13% of the new total, not 33% of the old one.

Two independent estimates of *maintained street trees* agree with each other and with the city:

| | count |
|---|---|
| The city's own quoted figure (Prop E, 2016, still quoted in 2026) | ~125,000 |
| The city's live operational layer, 2026-07-26 | **133,577** |
| Our old DataSF seed, `alive` **and** `DPW Maintained` | **139,012** |
| Our old DataSF seed, all rows | 195,309 |

133,577 sits 7% above a figure fixed in 2016, which is what nine years of planting looks like, and
within 4% of the comparable we could already compute from the export. **195,309 was never an estimate
of that quantity** — it was every row of an open-data table, planting permits and empty basins
included. The number got smaller and more accurate at the same time.

### What the 3,507 additions are

Pure gain, and the reason the owner opened this. All 3,507 are inside the seed's SF bounding box and
none has a null or zero coordinate. 1,338 carry `TREEID > 276035`, exactly the maximum id the DataSF
export has ever published — a ceiling in the export pipeline, not staleness in our copy. **TreeID
276198, `1 TWIN PEAKS BLVD`, the 36-inch Monterey Pine the owner found on the city's map, is among
them and is now in the seed.**

## Identity survived, which is what makes the revert safe

Measured directly, old seed against new:

```
TreeIDs in both       130,070
uuids that MOVED            0
```

Both paths derive `trees.uuid` as `uuid5(NS_TREE, <TreeID as ASCII>)` and both inventories use the
same `TreeID` space, so every shared record kept its identity byte for byte — in both directions.
`266901` is `62b2911f-c0f1-5876-9922-c92a69e94bcc` and `223762` is
`69a3c876-d64a-51da-8575-54e1f47bc146` in both files. Species uuids likewise: 503 species are in both
seeds and none moved. No grove entry, journal note, favorite, photograph or check-in on a tree both
inventories list is touched by the switch, or by switching back.

## Contributions orphaned

Counted across every simulator install on this machine — 36 contribution rows, all left by test runs:

| | rows |
|---|---|
| contribution rows found anywhere | 36 |
| orphaned by the switch | 10 |
| orphaned by switching back | 2 |

Nothing has reached the owner's phone, so on the device that matters the answer is **zero**: fresh
install, nothing to orphan. Per the owner's ruling — *"fine that some observations might disappear;
it's just testing mode now anyhow"* — no preservation scheme, tombstone table or migration was built.

## What the seed now says about itself

The deeper defect was never the row count. It was that a 100 MB file shipped inside the app with
nothing anywhere saying where its contents came from or how old they were, which is why "is our data
stale?" could only be settled by re-downloading the source and diffing. `seed_meta` now carries
`trees_source`, `trees_source_url`, `trees_source_map_url`, `trees_snapshot_on`,
`trees_source_last_edit_on`, `attributes_source`, `attributes_snapshot_on`, `rows_enriched` and
`rows_city_only`. The date is written from the extraction's own record, never a clock at build time,
so rebuilding this seed in 2030 still reports 2026-07-26.

`CypressStore` reads it once at open (the same pattern as `seedHasSoftDeletedTrees`), it travels on
`TreeProfile.inventorySource`, and the tree page's city-record section ends with:

> From the SF Public Works street tree inventory, July 26, 2026.

The seed contract fails if that date is absent or unparseable.

**One gate had to move for it.** `CityRecordPresentation.isEmpty` is `facts.isEmpty`, so a record
producing no card suppressed the whole section — correctly, to avoid a header over an empty grid. On
a first city-only build that removed the section from every tree in the seed, taking the pruning
answer and the provenance line with it. `TreeProfilePresentation.showsCityRecordSection` now opens
the section for cards **or** for a provenance line; the pruning note alone still does not, because it
is a statement about the dataset rather than about this tree.

### What #68's section actually looks like now — looked at, not reasoned about

Two shapes, both checked on a running build against the shipped seed:

- **A record both inventories list** (130,070 of 133,577, 97.4%): unchanged from before the switch.
  `Legal status · DPW Maintained`, `Cared for by · A private party`, `Plot size · 3 ft wide`, the
  `Stands on` sentence above it, then the pruning note and the provenance line. Verified on
  SF #239636 and SF #229291.
- **A record only the city lists** (3,507): the header renders, **no cards at all**, then the two
  sentences. Verified on SF #69746, `750 VISITACION AVE`:

  > WHAT SAN FRANCISCO HAS ON FILE
  > The city's street tree inventory records pruning by block, not by tree, so it says nothing about
  > when this tree was last pruned.
  > From the SF Public Works street tree inventory, July 26, 2026.

  No `Stands on` sentence either — `LandContext.inferred(from:)` reads `qLegalStatus` and
  `qCaretaker`, and those records have neither.

So #68's feature does **not** disappear and does **not** draw an empty grid. It renders in full for
97.4% of records and as a header over two true sentences for the rest, which is a fair account of what
the city has on file for a tree it has only recently begun listing.

## Pruning: cached, deliberately not shipped

The city's layer carries `Prune_Status`, `Prune_Year`, `Prune_TreeCount` and `keymap`, and the cached
extract holds all four. **None is in the seed.** `Prune_Year` is a property of the keymap grid: 133,577
records share **106 distinct values**, 9,387 of them `Active 2026` and 5,147 `Completed 20210601` —
the string the owner saw under 276198. A column named `prune_year` in `trees` gets rendered under a
tree's name sooner or later, and that is E143's mistake with a different column.
`CityRecordTests.thereIsNoPruningData` is now the place that decision is written down, and it fails if
anybody ingests them.

The sentence on the tree page changed, because the old one became false. It read `The city's street
tree inventory records no pruning dates or schedule.` — true of the export, not of the layer we now
ship. It now reads:

> The city's street tree inventory records pruning by block, not by tree, so it says nothing about
> when this tree was last pruned.

A better answer to #68 than the old one, and still not a per-tree pruning claim.

## Reverting to the DataSF export

Literal commands. Assumes `Fixtures/raw/street_tree_list.csv` is present — it is gitignored, and
`--fetch` re-downloads it (~53 MB).

```sh
# 1. Rebuild the seed from the DataSF export instead of the city's layer.
python3 Tools/build_seed.py --source datasf

# 2. Ship it. BOTH paths, or the app and the tests disagree about what is in the seed.
cp Fixtures/seed/cypress-seed.sqlite Cypress/Resources/cypress-seed.sqlite

# 3. Rerun the suite. Its corpus numbers are keyed on `seed_meta.trees_source`
#    (CypressTests/SeedCorpus.swift), so they follow the rebuild without being edited.
xcodebuild -project Cypress.xcodeproj -scheme Cypress \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -derivedDataPath /tmp/cypress-revert -configuration Debug test
```

No commit needs reverting and no code changes. `--source` is an input; both paths are supported and
both are tested by the same suites against their own pinned numbers; `Fixtures/seed/schema.sql` is
byte-identical between them, so **there is no schema change and no `AppSchema` migration** — the two
inventories differ in which columns are populated, not in which columns exist.

**What changes when you revert.** 145,837 rows become 195,309; 12,413 vacant sites become 12,518;
577 species become 569; the seed grows from 78 MB to 104 MB; 37,962 planting dates become 70,067;
every row's provenance names the DataSF export rather than only the sites' rows doing so; and TreeID
276198 with 3,506 others the city's own map shows disappear from ours again. Every uuid present in
both files is unchanged in either direction.

**Two side effects.** `Fixtures/sf_species_map.csv` is regenerated by every build and will show a
large diff — correct, it is the mapping for whichever seed you just built. And
`Fixtures/seed/cypress-seed.sqlite` is gitignored, so **a merge does not carry the seed**: whoever
takes this branch must rebuild or copy it.

## Corrections to the report above

1. **The gap estimates were close but not exact.** ≈3,300 / ≈68,800 measured against a full extract
   are 3,507 / 65,239. The intersection estimate of ≈130,000 was very good: 130,070.
2. **Section 6's "Option B — do not"** is superseded by the owner's ruling, and what shipped is
   nearer Option C inverted: the city's layer as the spine, the export as enrichment, rather than the
   other way round. Its costs are all itemized above; the owner has read them and chosen it anyway.
3. **475 city records put the botanical name in `COMMON` and leave `BOTANICAL` null**
   (`Laurus nobilis 'Saratoga'`, `Lophostemon confertus`, `Pistacia chinensis`). Not noted in the
   report. `build_seed.py` swaps the halves when `BOTANICAL` is empty and `COMMON` reads as a
   binomial; without that each would mint a stub species beside the real species it names. Stub share
   with the swap: 0.0487%, against a 2% ceiling.
4. **The city layer holds species DataSF does not.** 577 against 569, with 74 added and 66 dropped.
   The species fixtures are sourced against the DataSF corpus, so 66 sourced entries name a species
   the city-built seed does not carry. That is an absence in the corpus, not drift between fixtures
   and parser, and the build reports the count rather than failing on it.
5. **Section 4's `PlantType` line is superseded by #95.** The three rows spelled lowercase `tree` are
   gone: `build_seed.py` now folds case-variant spellings in the five columns the app compares
   against literals, and the seed contract fails if any return. `address`, `plot_size` and
   `permit_notes` are deliberately left alone — they are free text shown as the city wrote it, and
   one of `McAllister St` / `MCALLISTER ST` is a real spelling.

---

# Addendum, 2026-07-26 (second round): the vacant sites, kept

The switch above cost one feature outright, and the owner has ruled it back. What follows is what
was measured and built, in the same terms as the addendum before it.

## The ruling, and why it is a different claim from the one about trees

The 17,443 "crux" rows stay dropped. The owner accepted the reasoning as written: the city's layer is
the operational record, and a tree Public Works stopped listing is most likely gone.

Vacant sites are not that argument. **The city's layer has no vacant-site category at all** —
`PlantType` is `Tree` on all 133,577 of its records, and there is no `qSiteInfo`, no `qLegalStatus`,
no site-status column of any kind. It is not contradicting the export about an empty basin; it has
nothing to say about one. Dropping 12,518 sites to 153 was therefore not deference to a better
source, it was a feature (#11, #31, #32) becoming vestigial as a side effect of a decision about
trees. So the sites are carried across, and the tree row set is untouched: the map still agrees with
the city's map about every tree on it.

## What ships now

| | rows | trees | vacant sites | species | planting dates | seed |
|---|---|---|---|---|---|---|
| `--source city` **(default)** | **145,837** | 133,424 | **12,413** | 577 | 37,962 | 77.9 MB |
| `--source datasf` | 195,309 | 182,791 | 12,518 | 569 | 70,067 | 103.6 MB |

`--source city` now means the city's layer for the trees and the export for the sites. **It is not a
third flag value**, and the reasoning is in `build_seed.py`'s own header: a `--source` value answers
which inventory the seed believes about the trees, and the export's sites are not a third answer to
that question. No build that wants a working "where a tree could go" declines them, and no build that
has them disagrees with the city about anything, so a `city-no-sites` value would be a third path to
test forever, selected only by somebody reproducing a number in this file.

## The exclusion, measured

Of the export's 12,518 vacant sites, **258 carry a TreeID the city's layer also lists**:

| | count | what it is |
|---|---|---|
| carried through | **12,260** | the city's layer has never heard of this TreeID |
| excluded — the city lists a living tree there | **128** | the one real contradiction; the city wins |
| already in the seed — the city lists it empty too | **130** | `BOTANICAL = 'Potential Site'`; both agree |

The 128 are the whole of the disagreement between the two inventories about vacant sites, and they
are resolved the same way the tree row set is: the city's layer decides. The test in the build is
"did the first pass already emit this TreeID", which makes a duplicate `external_ref` unrepresentable
rather than merely unlikely. Nothing in the second pass can add a *tree*: `parse_qspecies` has already
called the row a placeholder, and every placeholder gets `status = 'vacant_site'` and no species.

## Neighborhood coverage: 17 of 41 empty, now 0 of 41

The number that made this worth doing. Under `--source city` before this round, 17 of the city's 41
analysis neighborhoods held no vacant planting site at all, so screen 12's empty-site row was absent
across a third of the city and #11's state was unreachable there. **All 41 hold at least one now**,
which is what the DataSF export gave. Sunset/Parkside, the neighborhood the almanac suites read,
goes from 7 sites to 1,436 (1,474 under the export).

## Dropped vacant-site uuids: none, and it was checked rather than reasoned about

- **Every one of the export's 12,518 vacant-site TreeIDs is a row in the new seed.** 12,260 as
  `vacant_site`, 258 as rows the city's layer also lists — of which 128 are `alive`. A record whose
  status changed has not lost its identity: `uuid5(NS_TREE, TreeID)` is unchanged, so nothing
  dangles, and the 128 are reachable as trees.
- **Nothing references a vacant site by uuid.** Across all seven simulator installs on this machine,
  23 contribution rows reference a tree (9 photos, 5 measurements, 5 review flags, 3 status
  overrides, 1 visit) and **none of them points at a vacant site**. The collapse orphaned no site and
  the restoration un-orphans none.
- The only vacant-site uuid written down anywhere in the repo is `aa72e15a-f8b2-5711-9735-95338a27104f`
  in `TreeProfilePreviews`, which is a preview fixture constructed in code rather than read from the
  seed. Its TreeID is 271641, a `Permitted Site` the city does not list, so it is back in the file.
- `trees.site_lineage` is NULL for every row the build writes, in both sources, so the one
  self-reference the schema has could not dangle either.

## Provenance had to become a per-row fact

The seed is now built from two inventories, so `seed_meta.trees_source` is a property of the *file*
and is the wrong answer for 12,260 of its rows. `trees.inventory_source` (`city` | `datasf`) carries
the row's own answer, `seed_meta` carries an `inventory_<id>_name` / `_url` / `_snapshot_on` triple
for each, and `LocalAPI.provenance(of:in:)` resolves one to the other. A seed built before the column
existed reports nil and falls back to the file-wide answer, which is correct for it because every row
in it came from one place.

**One correction to how this was briefed.** The sentence that was said to be false on a vacant site —
`From the SF Public Works street tree inventory, July 26, 2026.` — is not drawn on one today. It
belongs to the tree page's city-record section, and a vacant site never reaches the tree page:
`TreeProfileDestination` redirects it to `Route.site`, which `VacantSiteRedirectTests` pins as an
invariant ("a vacant site never becomes a tree profile"). The site screen said nothing at all about
where its record came from. That was survivable while the file held one inventory and is not now, so
the site screen draws its own line under its stat grid —
`From the DataSF Street Tree List, 20 July 2026.` — resolved from the row rather than the file. The
defect was an absent sentence, not a false one, and the fix is the same fix.

The seed contract now fails if a row names an inventory the receipt cannot describe, or if the named
inventory carries no readable snapshot date. That is what keeps the line from ever resolving to the
other inventory's name.

## The 475 `COMMON`/`BOTANICAL` records were already handled

The brief carried these forward as an open defect that "would mint a stub species beside the real
species it names". They do not. `city_qspecies` swaps the halves when `BOTANICAL` is empty and
`COMMON` reads as a binomial, and correction 3 above records it as shipped. Verified on the built
seed: of 540 city records with a blank `BOTANICAL` and a non-blank `COMMON`, **410 are swapped and
land on the real species row** — `Pistacia chinensis` on species 39 with 431 trees, `Lophostemon
confertus` on species 13 with 6,695, `Magnolia grandiflora 'Little Gem'` on species 18 with 850.

What is real is a smaller residue the correction did not claim to cover. 65 of the remaining 130 rows
mint 15 stub species, and **8 of those 15 shadow a species already in the corpus, covering 30 tree
rows** (0.021% of the seed): `:: lophostemon confertus` (11 rows), `:: platanus hispanica 'columbia'`
(8), `:: Ceanothus 'Ray Hartman'` (4), `:: Arbutus 'Marina'` (2), `:: Ulmus 'Frontier'` (2), and one
row each of `:: Podocarpus Gracilor`, `:: agonis flexuosa`, `:: eriobotrya deflexa`. Two causes, both
outside the binomial test: a lowercase genus, and a genus-plus-cultivar with no epithet. The other 7
stubs shadow nothing — `:: Zelkova 'Village Green'` (25 rows), `:: 9662`, `:: Magnolia` — and are
correctly stubs.

**Not fixed here, deliberately.** The fix is a canonical-spelling pass over the species name, which is
#95's mechanism applied to a column #95 deliberately excluded, and it changes the species corpus the
fixtures are sourced against. That is its own task with its own rebuild, not a rider on a decision
about which rows exist.

## Corrections to the addendum above

1. **"12,518 → 153, with 17 of 41 neighborhoods holding none"** described one round of the switch and
   no longer describes what ships. 12,413 sites, 0 of 41 empty.
2. **"This is the one loss the join cannot repair: a vacant site is a *row*, and rows come from the
   spine."** True of a build with one spine, and it framed the sites as unrecoverable without
   reverting. A seed can have rows from two inventories where the two are answering different
   questions, and this one does.
3. **The seed is 77.9 MB, not 71.4 MB**, and `--source city` reads the DataSF CSV twice: once for the
   seven enrichment columns and once for the sites.
4. **`Tools/build_seed.py --limit N` now bounds both passes**, so a smoke build exercises the second
   one instead of skipping it.
