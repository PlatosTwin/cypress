# Washington, D.C. street trees: profile and ingest (2026-11-12)

This note records what DDOT publishes, what the D.C. pack ships, and the decisions behind it. Code:
`Tools/fetch_dc_trees.py`, `DCStreetTreeAdapter` in `Tools/inventory_adapters.py`, the `us-dc-dc`
entries in `Tools/inventory_contract.py` and `Tools/build_seed.py`, and the `--add-pack` mode of
`Tools/publish_cities.py`. Tests: `Tools/test_dc_inventory_adapter.py` and section 9 of
`Tools/test_publish_cities.py`.

## 1. The source

| | |
|---|---|
| Layer | `https://maps2.dcgis.dc.gov/dcgis/rest/services/DCGIS_DATA/Urban_Tree_Canopy/MapServer/23` ("UFA Street Trees") |
| Publisher | District Department of Transportation (DDOT), Urban Forestry Division |
| License | CC BY 4.0. Credit line: "District Department of Transportation" |
| Rows | 223,777 (`returnCountOnly`, 2026-11-12). The fetch held 223,777 distinct GLOBALIDs. |
| Paging | `maxRecordCount` 2000, `resultOffset` with `orderByFields=OBJECTID`, 112 pages |
| Spatial reference | native 26985 (Maryland State Plane, metres); fetched with `outSR=4326` |
| Newest edit | `LAST_EDITED_DATE` 2026-11-07T01:02:36Z |

The fetch is sequential with a 1 s delay, resumable per page, and refuses to write a cache whose
distinct GLOBALID count differs from the server count. The cache lives outside the repo (about
100 MB). A 39-row real sample is in `Fixtures/raw/dc/dc_street_trees_sample.json`.

## 2. Identity

Id space `us-dc-dc`, prefix `us-dc-dc:`, keyed on `GLOBALID` with the braces stripped and the case
kept as published (uppercase). GLOBALID is the only complete unique id: 223,777 distinct, zero null.
`OBJECTID` moves on republish. `FACILITYID` is a planting-site id, null on 67,033 rows and repeated
on others. `GIS_ID` is empty on every row.

**Known risk.** Nobody has shown whether GLOBALID survives a DDOT republish of the live layer.
DDOT's Street Tree Archive layer carries regenerated GLOBALIDs, but that layer is a copy. Re-fetch
in a few weeks and join on GLOBALID (ROADMAP chip backlog).

Pack id `us-dc-dc`, display name "Washington, D.C.", inventory `dc_street_trees`. These freeze at
first publish (R37.2).

## 3. What ships

`TBOX_STAT` alone decides. Many non-`Plant` rows still carry the removed tree's species and DBH,
so a filter on species presence would ship removed trees as living ones.

| `TBOX_STAT` | rows | ships as |
|---|---:|---|
| Plant | 198,167 | tree |
| Retired | 12,264 | not shipped |
| Proposed | 4,933 | not shipped |
| Conflict | 4,346 | not shipped |
| Open | 3,468 | vacant site (San Jose's `VACANTSITE = 'Yes'` precedent) |
| Delete | 279 | not shipped |
| Utility Conflic | 162 | not shipped (value truncated upstream) |
| Under Construct | 154 | not shipped (value truncated upstream) |
| null | 4 | not shipped |

**1,407 rows lie outside the District**, in one cluster at "Oak hill Dr" near Laurel, Maryland
(about 39.10, -76.79). They are District-owned land (OWNERSHIP DGS 1,083, UFA 321, null 3). The
build's `DC_BBOX` (lat 38.78 to 39.01, lon -77.13 to -76.90) drops them; 1,320 of them are
`Plant` or `Open`. The fetch counts them but does not stop on them; it stops only if more than half
of a page is outside the District.

The build, as measured:

| | rows |
|---|---:|
| read | 223,777 |
| not shipped, by status | 22,142 |
| no point | 2 |
| outside `DC_BBOX` (Laurel) | 1,320 |
| **shipped** | **200,313** |
| of which trees (`alive`) | 194,086 |
| of which standing dead (`dead_reported`) | 3,332 |
| of which vacant sites | 2,895 |

## 4. Values

- **Condition.** `Dead` on a `Plant` row is `dead_reported` (R19, NYC's mapping). Excellent, Good,
  Fair and Poor are `alive` (R101's precedent). Blank is no claim. DDOT's word goes to
  `permit_notes`, where NYC and San Jose put theirs. A new value stops the build.
- **DBH** is a double with no stated unit. **Inches is inferred**: median 6.6 and p99 42.1 over the
  positive values. Range -25 to 1,471; 2,390 zeros; 17,398 null. Values at or below 0 and above the
  shared 400 in ceiling become null. On shipped trees: 256 zero or negative, 3 over the ceiling.
- **Planting date** (`DATE_PLANT`, epoch ms). Dates before 1900 or after the seed's horizon year are
  dropped: 130 on shipped trees. 225 rows on the layer read 1899-12-30, the spreadsheet day zero.
  4 rows at 1900-01-01 and 6 at 1900-01-02 pass the rule and may also be placeholders.
- **Address** is `VICINITY` with whitespace collapsed ("3218 18TH ST NW", "2900 BLK M PL SE"). San
  Jose and New York put a number-and-street string in the same field.
- **Not read:** WARD, GENUS_NAME, FAM_NAME (botanical content comes only from cited fixtures),
  FACILITYID, and DISEASE, PESTS, SIGN, WARRANTY, RETIREDDT and CONDITIODT, which hold editor
  usernames or unreliable dates on this layer.
- **No neighborhoods** ship, as for San Jose.

## 5. Species

330 distinct `SCI_NM` values. The adapter normalizes whitespace only (U+00A0 becomes a space; runs
collapse). Everything else stays as DDOT wrote it, the same rule San Jose and New York follow:
cultivars (`Pyrus calleryana 'Bradford'`), hybrids with ` x `, `Prunus species`, `Morus spp`, the sex
suffix (`Ginkgo biloba (male)`), curly quotes (`Ulmus x ‘Morton’ Accolade`) and misspellings
(`Liquidambar Stryaciflua 'Sterile'`). `Other (See Notes)` (2,190 shipped trees) and a blank name
(753) ship as trees with no species (R18). The adapter scores `Genus species` at 0.75 on the shared
confidence scale, like `spp`; the name is unchanged.

`Fixtures/species/nyc_species.yaml` is now offered to the build whenever D.C. is in it. It attaches
cited family and leaf-retention values only to a species whose name exactly matches one New York
curated. The twelve most common D.C. species all carry family and leaf retention, through it
or through `leaf_retention.yaml` (checked on the built pack). No content was written by hand.

### RULING D20 coverage: **86.27%**

Measured the way the NYC ingest measured New York (nyc-ingest §4): the R0 to R3 cascade of
`Tools/build_nyc_species_map.py` against the species catalogue already published (1,198 species,
read from the live `us-ca-sj` pack, which carries the fused catalogue whole). R4 is NYC's own
spelling fix and does not apply. The denominator is every shipped D.C. tree, 197,418.

| rule | values | rows | share |
|---|---:|---:|---:|
| R0 exact | 193 | 164,538 | 83.34% |
| R1 hybrid sign | 1 | 32 | 0.02% |
| R2/R3 rank within species | 50 | 5,673 | 2.87% |
| R1 + R2/R3 | 1 | 79 | 0.04% |
| no species (R18) | 1 | 2,906 | 1.47% |
| unmapped | 80 | 24,190 | 12.25% |

**170,322 of 197,418 rows (86.27%), 7,355 rows short of 90%.** The largest unmapped values are
notation the cascade does not handle (`Ginkgo biloba (male)` 2,952, `Prunus species` 2,208,
`Ulmus species` 1,720, curly-quoted cultivars) and taxa the corpus lacks (`Cladrastis lutea` 1,902,
`Liquidambar rotundiloba` 1,350). The owner waived D20 for D.C. on 2026-11-12;
`docs/rulings-pending/dc-species-gate.md` records it.

## 6. Publishing one pack: `--add-pack`

An ordinary publish writes a manifest from the packs in the seed it reads. A seed built from San
Francisco and D.C. would publish a catalogue without San Jose and New York. `publish_cities.py
--add-pack us-dc-dc --previous-manifest live` builds only the D.C. pack, copies the seven live
entries and `source_seed` unchanged, appends D.C., and writes an `upload.sh` that names only the
D.C. pack and `manifest-v2.json`.

**It also renumbers the pack's region id, and the publish would not work without that.** The app's
`InventoryUnionSQL.mirrorFirstWins` copies `dim_region` from every installed pack into one table
whose `id` is PRIMARY KEY, filtering only on `pack_id`. An SF + D.C. build gives D.C. region id 2,
and the live San Jose pack carries region id 2 (checked on the downloaded pack). A phone holding
both would refuse one of them. `--add-pack` sets the new pack's region id to one past the published
packs (8). A later full rebuild that includes D.C. would move New York's borough ids, because
`us-dc-dc` sorts before `us-ny-nyc`; that is a ROADMAP follow-up.
