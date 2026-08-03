# San Francisco's park trees: what Rec & Park actually publishes

Investigation, 2026-08-02/03, written for ticket **#106** ("Add park trees so Golden Gate Park
populates"). No `.swift` file was edited and no seed was rebuilt. The seed was queried read-only
from `Fixtures/seed/cypress-seed.sqlite`; no source was written to. The simulator was used once, to
look at the map (§1.1), and the suite was run once on the finished tree:

```
VERIFY-NOTE: device iPhone 16e 3A1F212D-8F3A-41F1-AF72-EC95E155A4C9 — screen 390 (1170 px @ 3.000000x)
VERIFY-NOTE: device-state active-city=none map.lastCamera=[none]
VERIFY-NOTE: SwiftCompile tasks=397
VERIFY-OK: ✔ Test run with 1080 tests in 102 suites passed after 117.338 seconds.
```

with the UI half of the same log reading `Executed 68 tests, with 8 tests skipped and 0 failures
(0 unexpected)` and `** TEST SUCCEEDED **`.

---

## Verdict up front

**#106's central premise is false, and the ticket cannot be completed as written.**

The ticket says: *"Those trees are maintained by Rec & Park, a different dataset entirely."* The
first half is true. The second half is not. **The San Francisco Recreation and Parks Department
publishes no tree inventory — not on the city's open-data portal, not on the city's ArcGIS Online
organisation, and not anywhere else this survey could reach.** It publishes benches, lamp posts,
trash cans, picnic tables, fences, gates, property boundaries, functional areas and park-evaluation
scores. It does not publish trees.

This is not "we could not find it". DataSF publishes an inventory *of its own datasets*
(`y8fp-fbf5`), which lists every dataset the city holds along with a publishing status — including
`Internal`, `Scoping`, `In Progress` and `Not Published` ones. Rec & Park has **twelve** entries in
it (§2.3). None is a tree inventory, and none is planned.

So there are no rows to ingest, and the two decisions #106 delegated — whether a park inventory is
a new *inventory* in the `sf` id space or a new *id space*, and how a park tree's land context is
expressed — **have no data to be decided from**. Both are left open on purpose; §5 says what would
decide them if a source ever appears.

The measurement that says how empty Golden Gate Park is, done properly against Rec & Park's own
park polygon rather than a bounding box, is §1. The short form: **65 trees stand inside the
1,031.65-acre Golden Gate Park polygon, and all 65 are DPW-maintained street trees on named
boulevards.** Not one park tree.

---

## 0 · Request counts and caching

Every response is cached under `Fixtures/raw/sf_park/bodies/`, keyed by `sha1(url)`, with
`requests.log` recording every request that actually went out. A URL already on disk was never
re-requested. One second minimum between requests to the same host. No bulk download was made from
any source — the largest single response is the 240 Rec & Park property polygons, fetched once,
which is that layer in its entirety.

**Total: 71 scripted requests**, read off `Fixtures/raw/sf_park/requests.log` via
`python3 Tools/fetch_sf_park_trees.py counts`.

| source | requests | what it is |
|---|---:|---|
| `rpd_agol` | 17 | Rec & Park layers on `services.arcgis.com/Zs2aNLFN00jrS4gG` |
| `agol_search` | 10 | ArcGIS Online item search (discovery) |
| `buf_agol` | 8 | SF Public Works urban-forestry layers |
| `ccsf_agol` | 8 | the CCSF service directory (2,075 services) |
| `datasf_catalog` | 8 | Socrata catalogue search over `data.sfgov.org` |
| `sfo` | 6 | SFO's tree inventory (§4) |
| `sf_city_maintained_tree` | 4 | 311's City-Maintained Tree layer |
| `arcgis_hub` | 3 | ArcGIS Hub dataset search (discovery) |
| `datasf_inventory` | 3 | DataSF's inventory of its own datasets |
| `rpd_assets` | 2 | the Rec & Park asset dataset on Socrata |
| `sf_env` | 1 | SF Environment's Quercus agrifolia study |
| `berkeley_geodata` | 1 | UC Berkeley GeoData (403, see below) |
| **TOTAL** | **71** | |

Two of the 71 are failures and both are recorded rather than hidden: one `400` from a Socrata SoQL
query with a wrong column name (my error, retried correctly), and one `403` from
`geodata.lib.berkeley.edu` to a scripted request. The Berkeley 403 did not matter — a web search
identified the record as *City Trees, Berkeley, California, 2013*, which is Berkeley's street trees
and has nothing to do with San Francisco's parks.

**Outside the cache:** 4 exploratory `curl`s to `data.sfgov.org` and `api.us.socrata.com` before the
caching helper existed, 5 `WebSearch` calls, and 3 `WebFetch` attempts (`urbanforestmap.org` — TLS
failure, the domain no longer belongs to the project; `catalog.data.gov` — 404; the Berkeley record
— 403). Counted here so the number in the report is the whole number: **71 cached + 4 uncached = 75
HTTP requests to data sources**, plus 5 web searches.

---

## 1 · How empty Golden Gate Park is, measured against the park's own polygon

The ticket's framing was checked rather than assumed, and a bounding box was not good enough: the
usual GGP rectangle contains Fulton Street, Lincoln Way, Stanyan Street and the whole Richmond and
Sunset frontage, all of which are dense with street trees.

So the boundary used is **Rec & Park's own**: `Recreation_and_Parks_Properties/FeatureServer/0`,
the feature whose `map_label` is `Golden Gate Park` and whose `complex` is `All Sections` — 1,031.65
acres, 3 rings, 1,096 vertices. Point-in-polygon over the seed:

| measurement | value |
|---|---:|
| seed rows in the GGP **bounding box** | 5,914 |
| seed rows inside the GGP **polygon** | **65** |
| of those, `legal_status = 'DPW Maintained'` | 65 (all) |
| of those, `caretaker = 'Rec/Park'` | 53 |
| distinct addresses among them | Sunset Blvd, Chain of Lakes Dr and kin — named boulevards |
| park area | 1,031.65 acres |
| density | **0.06 trees per acre** |

Every one of the 65 is a street tree standing on a boulevard that happens to clip the park's
outline. Not one is a tree in the park.

The same measurement citywide, over all 240 Rec & Park property polygons (5,255 acres):

| measurement | value |
|---|---:|
| SF seed rows standing on Rec & Park land | **1,922** of 145,837 (1.3%) |

That 1.3% is the size of the whole overlap between San Francisco's street-tree inventory and San
Francisco's parks, and it is edge effects.

### 1.1 And on the running map, which is where the ticket said to look

Measured on the phone as well as in the database, because a green suite has ratified real defects
here. iPhone 16e `3A1F212D-…`, 390 pt, seed unchanged at `d3e3d229…`, simulator location set to
Stow Lake (37.7694, −122.4862) and the app opened on screen 01 at the reader's own position.

At street zoom the park draws **no pins at all** — only Apple's basemap canopy artwork, which is
itself the picture of the problem: the basemap knows there are trees there and the inventory does
not. Pinched out two steps so that Fulton Street and the Richmond come into frame, one screen holds
the whole finding: **north of Fulton, a pin on every tree down every block; south of Fulton — JFK
Drive, Middle Drive West, Martin Luther King Jr Drive, the whole visible park — not one.** The
species legend that appears (Sycamore/London Plane, Olive, Cherry Plum, Blackwood Acacia) is drawn
entirely from the street rows above the park.

Kept at `shots/106-golden-gate-park-empty.png` (git-ignored, regenerable).

This confirms the number `LandContext.inferred(from:idSpace:)` already carries in its doc comment
— `.cityPark` resolves for 177 of 195,309 rows — from the opposite direction. That function reached
177 by reading the city's *claims* (`qLegalStatus` / `qCaretaker`); this reaches 1,922 by reading
*geometry*. Both say the same thing: **the Street Tree List is not a park inventory**, which is
exactly what its name says.

---

## 2 · What Rec & Park publishes

### 2.1 On DataSF (Socrata)

`Assets Maintained by the Recreation and Parks Department` (`e3jj-mbb3`) is the closest thing to a
park-asset inventory the department publishes. Its own description: *"The locations of assets like
trash cans, picnic tables, benches, etc, operated and maintained by Rec and Park."* Licence is
stated and clean — **Open Data Commons PDDL**, `licenseId: PDDL`.

Its `asset_type` histogram, measured both through Socrata and directly against the ArcGIS layer
(the two agree exactly, so the Socrata mirror is not filtered):

```
3186 Bench          243 Drinking Fountain   64 Bag Dispenser     24 Flag Pole
1646 Lamp Post      233 Play Structure      54 Gardener Storage  21 Game Table
1361 Trash Can      227 Athletic Access.    47 Cargo Container    21 Bulletin Board
 757 Table          214 Institutional Eq.   46 Picnic Table       17 EV Charger
 318 Signage        143 Bicycle Rack        41 Storage Container  16 Light Pole
 104 Utility Pole    94 Grill               37 Dumpster           14 Statue
  85 Public Art      78 Fire Hydrant        28 Garden Structure     9 Sculpture
  25 Bollard          7 Shade Structure      4 Bike Rack            3 Fire Pit
   2 Toilet           2 Irrigation Valve     2 Drinking Fnt/Cooler  1 Monument
   1 Arbor
```

**Thirty-seven asset types, 9,000-odd assets, and no tree.** A department that inventories its
bollards and its one arbor to the unit does not have an unpublished tree layer sitting beside them
by accident; trees are simply not in this asset system.

### 2.2 On the city's ArcGIS Online organisation

`services.arcgis.com/Zs2aNLFN00jrS4gG` is the City and County of San Francisco's org — the same one
that hosts `BUF_Street_Trees`, which is the `sf_city` inventory the seed is built from. Its public
service directory lists **2,075 services**. Every service whose name contains `tree`, `forest`,
`arbor`, `canopy`, `park`, `rpd`, `plant`, `veg`, `garden`, `hort`, `landscap`, `inventory`, `asset`
or `ggp` was enumerated, and each plausible one opened:

| service | what it actually is |
|---|---|
| `RPD_Assets` | the layer behind §2.1. Benches. |
| `RPD_Linear_Assets` | gates, handrails, fences |
| `RPD_Functional_Areas`, `RPD_Parcels`, `RPD_Properties`, `Recreation_and_Parks_Properties` | polygons |
| `SFRPD_Park_Evaluation_*`, `Park_Evaluation_Master_Layer` | quarterly park scores, polygons |
| `CMMS_Assets_gdb` | Plaza, ParkingLot, WaterMeter, Median, LandscapePlot, LandscapeArea, CommunityCareTaker — points, no trees |
| `GGP_ASBUILT_CAD_7_24_18` | a CAD conversion of Golden Gate Park's **irrigation and utility** as-builts: 22,058 points on layers like `M-IF-PIPE-NEW` and `C-STRM-E`, with fields for sprinkler nozzles, solenoids and flow zones. Not trees. |
| `City_Maintained_Tree_DEV_20230516` | an operational layer for 311 call-takers. 11,255 points and **three fields**: `OBJECTID`, `X`, `Y`. No species, no id of its own, 1 point in the GGP interior. Under R24 it could not be a seed row even if it were park trees, because it publishes no stable identity. |
| `MuniCorridorTrees` (3,960), `Street_Tree_List_View` (144,294), `Confirmed_Landmark_tree_data_table` (25) | Public Works / SF Environment, all street trees; **0 rows inside the GGP interior** for each |

A full-text search of the org's item catalogue (`orgid:Zs2aNLFN00jrS4gG AND tree`) returns **68
items** — this catches items whose *service* is named opaquely, which the directory scan would miss.
Every one belongs to Public Works, SF Environment, SF Planning, 311 or SFO. The four Rec & Park
staff accounts that appear (`sstasio`, `bwan_rec`, `mdurana_rec`, `pebomcc_rec`) own park-evaluation
layers, trail story maps and a day-camp thumbnail.

One near-miss worth recording: `Quercus Agrifolia Study 2021` (SF Environment) is marked **public**
as an item but its feature service answers `{"error":{"code":499,"message":"Token Required"}}`. It
is a single-species study, not an inventory; had it mattered, a token requirement is a login and
therefore a stop-and-ask under this ticket's rules.

### 2.3 DataSF's inventory of its own datasets — the decisive check

`data.sfgov.org/resource/y8fp-fbf5` is the city's register of every dataset it holds, with a
publishing status per row. Filtered to `department_or_division = 'Recreation and Parks'`, in full:

| status | dataset |
|---|---|
| Published | Park Sections |
| Published | SFRPD Activity Guide — Spring through Summer 2016 |
| Published | Functional Areas maintained by Recreation and Parks Department |
| Published | Recreation and Parks Facilities |
| Published | Recreation and Park Department's Facility Conditions Assessment |
| Published | Assets Maintained by the Recreation and Parks Department |
| Published | Employees, positions, and appointments |
| Published | Park Scores 2005-2014 |
| Published | Properties and Facilites *(sic)* |
| Published | Recreation and Parks Properties |
| Published | Linear Assets Maintained by the Recreation and Parks Department |
| Not Published | RPD Production Data: Golf Courses |

Twelve rows. **No tree inventory, at any status.** A separate pass over the same register for every
dataset citywide whose name or description mentions a tree returns 130 rows and adds nothing: Public
Works' Street Tree List, its removal notifications, Planning's Urban Tree Canopy raster analysis, and
a long tail of street-and-sidewalk datasets that mention trees in passing.

### 2.4 Why there is no park inventory, from the city's own account

The citywide street-tree census — **EveryTreeSF**, run 2016–17 by SF Planning, SF Public Works,
Friends of the Urban Forest and ArborPro — is the inventory the `sf_city` list descends from. Its
published scope excludes trees on private property and **trees in public parks**, and SF Planning's
own project page says future phases of the Urban Forest Plan *would* address parks and open space.
Ten years on, no such phase has published data.

The `urbanforestmap.org` project, which in 2010–13 did collect park and private trees, is gone: the
domain now resolves to an unrelated commercial site with a mismatched TLS certificate.

---

## 3 · Everywhere else that was checked

- **ArcGIS Online**, global search for a Rec & Park tree layer: 5 results, all Los Angeles.
- **ArcGIS Hub** dataset search (`san francisco park trees`, `san francisco recreation park tree
  inventory`, `golden gate park trees`): university coursework and story maps.
- **DataSF catalogue** for `urban forest`, `vegetation`, `planting`, `arborist`, `canopy`, `shrub`,
  `forestry`: canopy rasters, the Street Tree List, and a plant-community polygon layer.
- **catalog.data.gov**: the API path returned 404; data.gov mirrors DataSF, which §2.3 covers
  exhaustively.
- **UC Berkeley GeoData**: 403 to scripts; the record in question is Berkeley's own city trees.

### 3.1 The San Francisco Botanical Garden, which is inside Golden Gate Park

`sfbg.gardenexplorer.org` is a real, publicly browsable plant-records database — an IrisBG
*Garden Explorer* instance covering the 55-acre botanical garden inside Golden Gate Park, with
per-specimen maps and photographs. It is the only accessible record of individually located woody
plants anywhere inside the park.

**It is still not this ticket's source, on three counts.** It is operated by the **San Francisco
Botanical Garden Society**, a 501(c)(3), in partnership with Rec & Park — so it is not a municipal
inventory, which is the scope the owner's data-fetching authorisation names. It asserts copyright
(`Content © 2026`, platform © Compositae AS) and states **no licence and no terms of use**, and it
offers **no export or bulk-download path** — under this ticket's rule 1 that is a stop-and-ask, not
a cleared source. And substantively it is a *garden accession list*: a curated living collection of
8,000 kinds of plant, most of them not trees, covering 5% of the park's area. It describes what was
planted in a garden, not what grows in Golden Gate Park.

Recorded here so that it is refused deliberately rather than discovered later and ingested.

---

## 4 · The one other tree inventory San Francisco publishes, and why it is not this ticket's

**SFO has a real one.** `SFO_TREE/FeatureServer/0` — 3,128 points, and a sibling
`SFO_TreePlotter_export` with 2,920 — carries genus, species, common name, DBH, spread, height,
condition, native flag, owner, maintenance and a prune cycle. It is the richest tree layer on the
city's whole ArcGIS org, richer than the street list, and it names its surveyors in `copyrightText`.

It is not #106's. San Francisco International Airport is in San Mateo County, twelve miles outside
the city, outside all 41 analysis neighbourhoods, and its trees are not in Golden Gate Park or in any
park. Ingesting it would populate a corner of the map no reader of this app is standing in, and it is
not what this ticket asked for (and DECISIONS constraint 21 puts a screen full of airport trees
squarely in stop-and-ask territory). It is recorded here because it is the obvious "what about…?" and
because, if the merged national inventory D16 describes ever wants it, this is where it lives and
what it holds. Its identity column would need deciding (`ID_1`, `QA_ID` and `PrimaryID` all exist)
and it is a genuinely separate numbering scheme from SF's `TreeID`.

---

## 5 · The two delegated decisions, and why neither is taken here

#106 delegated design authority for two calls. Both are **left open**, and the reason is the same in
each case: the ticket's own instruction was to decide *from the data*, and there is no data.

### 5.1 New inventory in `sf`, or a new id space?

R18 makes this the load-bearing distinction and R24 shows both shapes in use. The question is
answered by **how the publisher numbers its records** — `sf_city` and `sf_datasf` share the `sf`
space because they publish the same `TreeID`; `us-ca-sj` is its own space because San Jose's
`FACILITYID` 3 and San Francisco's `TreeID` 3 are different trees.

Rec & Park publishes no records, so it has no numbering, so the question has no answer. **Nothing
should be registered in `Tools/inventory_contract.py` for it.** Registering an `IdSpace` or an
`Inventory` for a source that does not exist would put a name in the registry that
`check_id_space_registry` would happily accept and that no row would ever justify.

What would decide it, if a source ever appears: whether the park rows' own asset id is drawn from
Public Works' `TreeID` sequence. If Rec & Park's records key on `TreeID` — the same numbering, the
same trees potentially double-listed — it is a second inventory in `sf`, exactly like `sf_datasf`,
and the uuids **must** collide (R18's E156 argument). If Rec & Park keys on a TMA property/asset id
of its own (which is what `RPD_Assets.asset_id` and `tma_asset_id` are, and what its bench inventory
uses), it is a new id space and needs a non-empty prefix ending in `:`.

### 5.2 How a park tree's land context is expressed

The ticket's warning here was right and is worth keeping even though the decision is not takeable:
`LandContext.inferred(from:idSpace:)` reads DataSF's `qLegalStatus` and `qCaretaker` **by literal
string**, and R24's rule is that a derivation over one publisher's vocabulary must decline outside
the id space it was written for. A park inventory would publish neither column, so the function
would fall through to `nil` — which is the correct behaviour, not a gap to patch.

The ticket asked whether a park tree needs "a fourth answer rather than a wrong one of the three".
**It does not: the fourth answer already exists.** `LandContext` has four cases, and `.cityPark` —
*"Land the Recreation and Parks Department holds"* — is exactly the value a Rec & Park row would
carry. It is stored vocabulary, frozen by `AppSchema` v11's CHECK, and it is currently reached by
177 rows. So the shape of the eventual decision is narrow: whether a park adapter should *state*
`.cityPark` for every row from a park inventory (defensible — the source is the park department's
own list, and every row on it stands on park land by construction), or leave it nil and let a later
pass derive it. That is one line in an adapter and it is not decidable without seeing the adapter's
source.

**No pending ruling was written.** CLAUDE.md's rule is that a comment asserting an unverified
invariant is where bugs survive here, and the same applies to a ruling: writing R-something about
how a park inventory's identity and land context work, from a ticket rather than from rows, would
put a decision in `docs/RULINGS.md` that nothing measured. The finding is recorded as errata
instead.

---

## 6 · What #106 should become

Three options, in the order this investigation would rank them:

1. **Close #106 as blocked on a source that does not exist**, and keep the finding. Golden Gate
   Park stays empty on the map because San Francisco has never counted its park trees. That is a
   true statement about the city, and E126's rule — an empty state must say what would fill it —
   applies: the honest sentence is *"the city's inventory covers streets, not parks"*, not *"no
   trees here"*.
2. **Re-point #106 at #69.** A contributor adding a tree in Golden Gate Park is adding something the
   city genuinely does not have, which `LandContext`'s doc comment already calls out as a feature
   rather than a gap. The community layer is the only route to a populated Golden Gate Park that
   exists today.
3. **Ask Rec & Park.** The department plainly holds tree records internally — it has arborists, a
   pruning programme and a CMMS. They are not published. A records request is an owner decision, not
   an agent's, and it is not a data-fetching question.

What #106 should **not** become is an ingest of the nearest available thing. SFO's trees, the 311
call-taker layer's 11,255 anonymous points, and the botanical garden's accession list are each a
real dataset and none of them is the trees in Golden Gate Park.
