# Which California city is ingested after San Francisco

Survey and design note, 2026-07-31. Task #107, survey half. Rests on
`inventory-contract.md` (#105, ERRATA E169, RULING R18), which should be read first: this note
answers the questions that note left open, in its vocabulary.

Nothing here builds, runs a simulator, or edits a `.swift` file. The deliverables are this note,
`Tools/ca_inventory_survey.py`, the id-space and inventory registration in
`Tools/inventory_contract.py`, `SanJoseStreetTreeAdapter` in `Tools/inventory_adapters.py`, and
`Tools/test_ca_inventory_adapter.py`.

**Verdict up front: San Jose.** It is the only candidate found that states its licence in its own
catalogue (CC-BY), publishes a scientific name in a field of its own, publishes trunk diameter as a
number of inches rather than a range, and — the thing E169 says no source had — publishes a field
whose only job is to say whether a site holds a tree. It is also the only candidate where the
`inferred_from_absent_species` basis is reached by a rounding error of the corpus rather than by
1.2% of it.

---

## How the figures here were obtained

Every number below is either read off a response cached under `Fixtures/raw/ca_survey/`, or is
marked as inference. The probe is `Tools/ca_inventory_survey.py`; it asks each source's own API for
its field list, its row count and five sample rows, caches every response keyed by URL, never
re-requests a URL already on disk, and appends every request that actually went out to
`requests.log`.

**Total requests, read off that log on 2026-07-31 (`python3 Tools/ca_inventory_survey.py --counts`):**

| source | requests | | source | requests |
|---|---:|---|---|---:|
| `san_jose` | 126 | | `oakland` | 3 |
| `socrata_catalog` (discovery) | 29 | | `berkeley` | 3 |
| `santa_monica` | 9 | | `san_mateo` | 3 |
| `arcgis_online_search` (discovery) | 7 | | `arcgis_hub` (discovery) | 3 |
| `los_angeles` | 4 | | `san_diego` | 2 |
| `sacramento` | 4 | | `ca_state` | 1 |
| | | | `long_beach` | 1 |
| | | | **TOTAL** | **195** |

For scale, San Francisco's own street-tree fetch was 67 requests. The 126 against San Jose are the
recommendation's deep dive — per-value counts for each of the 618 distinct species strings' outliers,
the id-uniqueness measurements, and one query per fixture case — and no bulk download was made from
any source. Nothing here downloaded a full inventory.

**Dates.** Every count is as at 2026-07-31 unless stated. Where a source publishes its own
last-updated date, that date is given instead and is the one that matters.

---

## 1. The survey

### 1.1 What was actually found

| City | Inventory | Platform | Rows | Licence, as the publisher states it | Verified |
|---|---|---|---|---:|---|
| **San Jose** | `Street Tree` | ArcGIS MapServer 510, also CSV/GeoJSON | **344,879** | **CC-BY**, `license_id: cc-by`, `license_url: opendefinition.org/licenses/cc-by`, in the city's own CKAN package `street-tree` | observed |
| Los Angeles | `Trees (Bureau of Street Services)` | ArcGIS FeatureServer | **635,558** | **none stated** — `licenseInfo` empty, `copyrightText` empty | observed |
| Sacramento | `City Maintained Trees` | ArcGIS FeatureServer | **112,814** | a disclaimer, not a grant: *"provided as a public service and for general informational purposes only"* | observed |
| Santa Monica | `Trees Inventory` | CKAN datastore | **40,966** | **ODC-BY-1.0**, `license_id: odc-by-1-0` | observed |
| Oakland | `Oakland Street Trees` | Socrata `4jcx-enxf` | **38,613** | **CC0 1.0** (Public Domain Dedication) | observed |
| San Mateo | `Street Trees` | ArcGIS FeatureServer | **24,045** | **none stated** | observed |
| Long Beach | `Tree Inventory` | Opendatasoft | **1,728** | **CC BY 4.0**, with the licence URL | observed |
| Berkeley | `City Trees` (`9t35-jmin`) | Socrata | — | **could not verify** | see §1.3 |
| San Diego | — | — | — | — | **no tree dataset published**, see §1.3 |

Row counts are the server's own `returnCountOnly` / `$select=count(*)` answer, not an estimate.

### 1.2 What each one carries

| City | stable record id | scientific name | common name | DBH | planting date | site / vacancy concept |
|---|---|---|---|---|---|---|
| **San Jose** | `FACILITYID`, 344,879 distinct / 344,879 rows, 0 null | `NAMESCIENTIFIC`, one clean field, 618 distinct values | **no such field** | `TRUNKDIAM`, **a double in inches** | `INSTALLDATE`, populated on **1,342 of 344,879** | **`VACANTSITE` — `Yes`/`No`, a field whose only meaning is vacancy** |
| Los Angeles | `TreeID`, integer | **none in the layer** — `TOOLTIP` reads `Species: Not Specified` on every sampled row | none | none | none | `Type_Description`, `Tree` on the sampled rows |
| Sacramento | `GISOBJID` / `ASSET_ID` | `BOTANICAL` | `SPECIES`, inverted vernacular (`oak, coast live`) | `DBH` **as a string range, spelled inconsistently**: `13 - 24` and `19 to 24` both appear | none | `PLANTTYPE` is a growing-space type (`Planter Strip`), not a vacancy statement |
| Santa Monica | `tree_id` | `name_botanical`, with cultivars | `name_common` | `dbh_min` / `dbh_max` — **a range, not a measurement** | `date_modified` is a record-edit date, not a planting date | none found |
| Oakland | `objectid` only | `species`, plain string, `Unknown` present | none | none | none | `lowwell`, `wellwidth` etc. are well dimensions, not vacancy |
| San Mateo | `UNIQUEID` / `ID` | `SPP` | none | `DBH` as a numeric-looking string | `INV_DATE` is the inventory date, not a planting date | `GROWSPACE` / `SPACESIZE`, not vacancy |
| Long Beach | `tree` | `species` | none | none | **`date_planted`** | `stock_size`, `grow_space` |

### 1.3 The two that stop the survey rather than feeding it

**Berkeley — could not verify, and that is the finding.** `data.cityofberkeley.info` returns
**HTTP 403** to every automated request made here: the Socrata metadata endpoint, the row-count
endpoint, the sample endpoint, and a plain fetch of the dataset landing page. Berkeley's own portal
copy is widely quoted as permitting download, reuse and redistribution without restriction, and the
`City Trees` dataset is described as covering *trees, planting sites and stumps* — which is exactly
the three-way distinction the contract's `kind` field wants. **On the evidence available here that
is a promising source whose licence and contents could not be confirmed, and it is written down as
unverified rather than summarised as permissive.** Whoever revisits it should try the portal in a
browser; the block looks like a WAF rejecting a scripted user agent, not a paywall.

**San Diego publishes no tree inventory.** The city's open-data portal lists 115 datasets and none
of them concerns trees, street trees, urban forest or tree inventory (checked 2026-07-31). Tree data
for San Diego exists on a separate ArcGIS Hub site run under the *Trees For Communities /
ArborAccess* banner, which is not the city's open-data publication and was not surveyed further.

**Santa Monica's API serves placeholder rows before it serves real ones.** At offset 0 the CKAN
datastore returns records with `_id: 0`, `name_botanical: "ncMUFCMU"` and coordinates
`39.7817, -89.6501` — which is Springfield, Illinois. At offsets 5,000 and 30,000 the same resource
returns plausible Santa Monica data (`Phoenix canariensis` at `34.0233, -118.4999`). `total` is
40,966 throughout. **This is observed, not explained**; an ingest that read the first page and
stopped would ship Illinois. It is recorded here because it is precisely the class of defect #122
exists to stop: a number that was true when somebody wrote it down.

### 1.4 Sources deliberately not pursued

Discovery ran the Socrata federated catalogue (5 term queries plus 24 per-domain queries), ArcGIS
Online's item search (4 queries), the ArcGIS Hub dataset search (3 queries) and `data.ca.gov`'s CKAN
(1 query). Most California cities are no longer on Socrata; Los Angeles and Oakland are the
survivors, and the rest have moved to ArcGIS Hub. The searches also surfaced Redlands (54,150 rows)
and Hayward, which were not probed — the recommendation was already settled by then and probing them
would have spent somebody else's bandwidth to change nothing.

**Nothing was downloaded from behind a login or a click-through licence, because nothing found
required one.** Had one, the rule would have been to stop and write it down.

---

## 2. The per-city verdict against the contract

What the contract yields, per E169's rule that an absent field is `None` and `None` becomes a NULL
column — never an empty string, a zero, or a plausible-looking stand-in.

| City | `kind` / `kind_basis` | `scientific_name` | `common_name` | `dbh_in` | `planted_on` | `source_ref` |
|---|---|---|---|---|---|---|
| **San Jose** | **stated** on 344,818 of 344,879. `inferred_from_absent_species` on **61** | from `NAMESCIENTIFIC` | **always NULL** — no such field, and no species is minted from a vernacular | measured inches; **NULL on the 72,142 rows whose `TRUNKDIAM` is 0** and the 2 above 400 in | **NULL on 343,537 of 344,879** | `FACILITYID` |
| Los Angeles | `stated_category` from `Type_Description` | **always NULL** — 635,558 trees of unknown species | always NULL | always NULL | always NULL | `TreeID` |
| Sacramento | no vacancy field; every kind would be **ours** | from `BOTANICAL` | `SPECIES` is an inverted vernacular and needs a rule of its own | **always NULL** — a range is not a measurement, and `13 - 24` / `19 to 24` are the same range spelled two ways | always NULL | `GISOBJID` |
| Santa Monica | no vacancy field | from `name_botanical` | from `name_common` | **always NULL** — `dbh_min`/`dbh_max` is a range | always NULL | `tree_id` |
| Oakland | no vacancy field | from `species` | always NULL | always NULL | always NULL | **`objectid` only** — a row number, see §3 |
| San Mateo | no vacancy field | from `SPP` | always NULL | from `DBH` after parsing | always NULL | `UNIQUEID` |
| Long Beach | no vacancy field | from `species` | always NULL | always NULL | **from `date_planted`** | `tree` |

Read down the `kind_basis` column. For every city except San Jose, *every* record's kind would be
the ingest's inference from a missing species — which is the mechanism E169 names as #94's cause,
applied to a whole new corpus at once. That is the single strongest argument in this note and it is
not about size.

---

## 3. The id-space answer, per city

R18: identity is `uuid5(NS_TREE, ID_SPACES[<space>].identity_prefix + source_ref)`, and the
qualifier is the **id space** — the numbering scheme the ids are drawn from — not the source. Two
inventories of one numbering share a space (San Francisco's `city` and `datasf`, deliberately). Two
cities do not.

The question each city has to answer is therefore: *does this city's record numbering share a space
with anything else?* Argued below from how each city numbers, never from convenience.

**San Jose — its own space, `us-ca-sj`, prefix `us-ca-sj:`.** The numbering is `FACILITYID`, Esri's
Local Government Information Model asset id: the id the city's own asset records are keyed on and
the id its published extracts carry. Measured on 2026-07-31: **344,879 distinct values over 344,879
rows, zero null, and no `:` in any of the 1,000 sampled.** It is a small-integer space that overlaps
San Francisco's `TreeID` range numerically — San Jose `FACILITYID` 3 and San Francisco `TreeID` 3
both exist — which is exactly the collision the prefix exists to prevent, and exactly why the space
cannot be `sf`. It cannot collide with `sf` for a structural reason rather than a lucky one: `sf`'s
prefix is the frozen empty string, so an `sf` seed string is a bare `TreeID` and contains no `:` at
all, while every `us-ca-sj` seed string contains one at position 8. `check_id_space_registry` also
refuses two spaces sharing a prefix, and `source_ref` may not contain the separator.

**Why `FACILITYID` and not the other two ids the layer publishes.** All three are non-null and
distinct over all 344,879 rows, so uniqueness does not decide it.

  * `DAVEYID` reads `MB 20140207121505` — a two-letter crew code and a collection timestamp from the
    Davey Resource Group survey. It is an id **for the visit, not for the site.** A site re-surveyed
    gets a second one and a tree planted after the contract has none the contractor ever issued.
    Keying identity on it would make a tree's permanent public URL a property of when somebody
    happened to walk past it.
  * `OBJECTID` is the feature service's row number. It is the one id in the layer that is documented
    to move when the layer is republished, and DECISIONS constraint 13 makes a tree's citable
    identity permanent.
  * `FACILITYID` and `INTID` hold the same number as a string and an integer respectively —
    identical on all 1,000 rows sampled. They are **one numbering, not two**, so choosing between
    them is a choice of representation, not of space. `FACILITYID` is taken because `source_ref` is
    a string verbatim and the string form is what the CSV and GeoJSON extracts publish.

**Los Angeles — its own space, `us-ca-la`, prefix `us-ca-la:`** (not registered; LA is not the
recommendation). `TreeID` is the Bureau of Street Services' own numbering and its range overlaps San
Francisco's directly — E169 already uses LA `TreeID` 276198 against SF `TreeID` 276198 as the worked
example of the collision, and `test_two_cities_cannot_collide` pins it.

**Sacramento — its own space.** `GISOBJID` values are eight-digit (`10012227`, `10123517`), so they
do not currently overlap San Francisco's range — **and that is not a reason to share a space.** A
space is shared when two inventories publish the same numbering, not when two numberings happen not
to have collided yet. Sacramento would take `us-ca-sac:`.

**Oakland — its own space, and a weaker promise inside it.** The Socrata dataset publishes no id but
`objectid`, which is a row number in a 2013 extract. Under the contract that is not a stable
identity: an adapter should pass `source_ref=None` and let `has_stable_identity` be False, which is
a materially weaker promise and is readable as one. Registering an id space for Oakland keyed on
`objectid` would look like identity and not be it.

**Santa Monica, San Mateo, Long Beach — their own spaces**, on `tree_id`, `UNIQUEID` and `tree`
respectively. None shares a numbering with anything else surveyed.

**Nothing found shares an id space with anything else.** San Francisco's two-inventories-one-space
arrangement is a property of one city publishing one asset register twice, and no second instance of
it turned up in California.

---

## 4. The recommendation: San Jose, first

Ranked on licence clarity, field coverage and id stability — not on size or name recognition.

**Licence.** San Jose is the only large candidate whose licence is a grant rather than a disclaimer
and is stated by the publisher in machine-readable form: `license_id: cc-by`,
`license_title: Creative Commons Attribution`, `license_url:
http://www.opendefinition.org/licenses/cc-by`, on the CKAN package `street-tree`, organisation
*Enterprise GIS*, `metadata_modified` 2026-07-24. Los Angeles and San Mateo state nothing;
Sacramento states a disclaimer, which is not a licence. Oakland's CC0 is cleaner still, but see
below. No login, no click-through, no no-redistribution term.

**Field coverage — and one field in particular.** `VACANTSITE` is a `Yes`/`No` column whose only
meaning is whether a site holds a tree. E169's finding is that until the contract existed *there was
no field anywhere in the ingest in which a source could say what a record was*, so the builder
inferred it from a missing species. San Jose is a source that says. The consequence is measurable
and it is the reason this recommendation is not close:

| | San Francisco, `--source datasf` | San Jose |
|---|---:|---:|
| records in the corpus | 195,309 (E11) | 344,879 |
| kind stated by the source | — | **344,818** |
| kind **inferred from an absent species** | **1,777** (E169's receipt) | **61** |
| share of the corpus that is our guess | 0.91% | **0.018%** |

The San Francisco column is the `--source datasf` build, because that is the build whose receipt
produced the 1,777. The shipped seed is `--source city` (E156), whose split between stated and
inferred E169 explicitly records as **not measured** — the cached extract was absent from that
machine — so no figure for it is quoted here either.

It also carries `TRUNKDIAM` as a double in inches, which is what `InventoryRecord.dbh_in` means.
Sacramento and Santa Monica publish DBH as a *range*, so the contract yields NULL for every row of
both — 112,814 and 40,966 trees with no trunk diameter, and no honest way around it.

**Id stability.** `FACILITYID` is an asset id, unique and non-null over all 344,879 rows, measured
rather than assumed. Oakland's only id is a row number in a thirteen-year-old extract.

**Why not the others, briefly.**

  * **Los Angeles** is the largest at 635,558 records and would add **635,558 trees of unknown
    species** to a corpus of 145,837. It publishes no species, no DBH and no planting date in the
    open layer, and states no licence. The species exist behind per-tree NavigateLA report pages,
    which is 635,558 requests against someone else's server — not a thing to do.
  * **Oakland** has the best licence found (CC0) and the worst everything else: 8 fields, no id but
    a row number, no DBH, no date, and `rowsUpdatedAt` of **2013-01-22**. Worth revisiting only if a
    newer Oakland extract appears; the ArcGIS search did surface an *Oakland Public Tree Inventory*
    under a non-city owner that was not pursued.
  * **Sacramento** is the strongest runner-up on field count and the weakest on what those fields
    contain: DBH is a range spelled two ways, there is no planting date, no vacancy concept, and the
    licence is a disclaimer.
  * **Long Beach** has a clean CC-BY-4.0 licence and a real `date_planted`, and covers **1,728**
    trees planted since September 2018 under one CAL FIRE grant. It is a grant deliverable, not a
    city inventory, and it is the right *second* source precisely because it is small and clean.
  * **Berkeley** may be the best fit in the state on paper — trees, planting sites *and* stumps, all
    three of the contract's kinds — and could not be verified at all. It should be re-checked by
    hand before anything else on this list.

---

## 5. The two schema changes, stated exactly

Both are recorded in E169 with reproduced SQLite errors. Neither is written here as a migration:
`AppSchema` is at v13, and a migration is a build-and-test job for whoever picks up the ingest half.
`Tools/inventory_contract.py` already refuses an unregistered inventory and an ill-formed id space
before a row is built, but a Python registry cannot widen a CHECK constraint in a shipped schema.

**Change 1 — `trees.external_ref` must stop being globally unique.**

Today: `external_ref INTEGER UNIQUE`. E169's reproduction, with San Francisco's `TreeID` 276198
already inserted:

```
sqlite3.IntegrityError: UNIQUE constraint failed: trees.external_ref
```

San Jose `FACILITYID` 3 and San Francisco `TreeID` 3 are two different trees. Both exist. The insert
fails partway through the second city.

*What it must become.* The column must carry the id space alongside the ref, and the uniqueness must
be over the pair:

  * add `id_space TEXT NOT NULL` to `trees`, holding the `ID_SPACES` key (`sf`, `us-ca-sj`);
  * change `external_ref` from `INTEGER UNIQUE` to `TEXT NOT NULL` — **text, not integer**, because
    `source_ref` is defined as the source's own id *verbatim as a string* and nothing guarantees the
    third city's is numeric;
  * replace the column-level `UNIQUE` with `UNIQUE (id_space, external_ref)`.

Storing the qualified seed string (`us-ca-sj:3`) in one column is the alternative and is worse: it
makes "which space is this row in" a parse rather than a column, and the id space is a thing the
receipt and the UI both need to name.

**Change 2 — `inventory_source`'s CHECK must stop enumerating San Francisco's two lists.**

Today: `CHECK (inventory_source IN ('city','datasf'))`. E169's reproduction:

```
sqlite3.IntegrityError: CHECK constraint failed: inventory_source IN ('city','datasf')
```

*What it must become.* The CHECK's job is to stop a row naming an inventory the receipt cannot
describe, and a hardcoded list is the wrong instrument for that — every new city edits the schema.
It should become a **non-emptiness constraint plus a foreign key into a table of inventories the
seed itself declares**:

  * add `CREATE TABLE inventories (id TEXT PRIMARY KEY, id_space TEXT NOT NULL, name TEXT NOT NULL,
    url TEXT NOT NULL)`, written by `build_seed.py` from `INVENTORIES` for exactly the inventories
    that contributed rows;
  * change the CHECK to `CHECK (inventory_source <> '')` and add
    `FOREIGN KEY (inventory_source) REFERENCES inventories(id)`;
  * add `FOREIGN KEY (id_space) REFERENCES id_spaces(id)` on the same pattern, or fold the id space
    into `inventories` — a row's space is a property of its inventory and does not need to be stated
    twice.

**And rename `city`.** E169 already says it: `city` is a poor identifier once there is more than one
city. It should become `sf_city`, alongside `sf_datasf` and the new `sj_street_tree`. That rename is
a corpus-affecting change — `inventory_source` is a stored value and `InventorySource(id:seedMeta:)`
resolves it through `inventory_<id>_*` receipt keys — so it belongs in the same migration and not
before it.

**No Swift change is needed for either.** E169 established that `InventorySource.init(id:seedMeta:)`
already resolves any identifier the receipt describes. This survey found nothing that changes that.
The one Swift-side thing worth checking during the ingest half, and **not checked here because
building was out of scope**: `CypressTests/InventoryContractTests.swift` asserts that every distinct
`inventory_source` in the seed is describable from the receipt and that its declared id space matches
the one its uuids were derived in. That test should pass unchanged for a second city, and if it does
not, it has found something real.

---

## 6. The adapter, and what writing it proved

`SanJoseStreetTreeAdapter` is in `Tools/inventory_adapters.py`;
`Tools/test_ca_inventory_adapter.py` is 563 checks against 29 rows taken verbatim off the layer,
cached in `Fixtures/ca_survey/san_jose_street_tree_sample.json`.

**It proved the thing it was meant to.** The adapter reads `NAMESCIENTIFIC` straight into
`scientific_name`. There is no `::` anywhere in it, it does not import `parse_qspecies`, and it
never touches `PLACEHOLDER_SPECIES`. That is exactly what `SFCityLayerAdapter.species_of`'s
docstring promised a third source would be able to do, and it turned out to be true.

**It also proved that the contract's hard rules bite on real foreign data.** Three of San Jose's
own conventions would have produced records the contract refuses outright, and each had to be
resolved by the adapter because only the adapter knows it is a convention:

  * **72,142 rows have `TRUNKDIAM = 0`.** `validate()` refuses a non-positive `dbh_in`, so these are
    a hard failure rather than a wrong number until the adapter resolves 0 to `None`.
  * **72,995 rows have the literal string `Vacant site` (71,590) or `Vacant Site` (1,405) in the
    scientific-name field.** Two spellings, one fact. A rule keyed on the literal string would mint
    a species called `Vacant Site` for 1,405 planting sites — #103's mechanism exactly — so the
    vocabulary is keyed case-folded.
  * **4,513 rows say `Unknown`.** R18 already settled this one: a tree of unknown species is a tree.
    Treating `Unknown` as a placeholder would delete 4,513 trees from the map; minting a species
    from it would put `Unknown` in the field guide.

**Where the source disagrees with itself, the adapter picks and counts.** These are San Jose's, not
ours, and all four are measured:

| the disagreement | rows | what the adapter does |
|---|---:|---|
| `VACANTSITE = 'Yes'` and the species field names a real taxon | **611** | keeps the flag, drops the species, counts it. An empty hole that names a species is one of the two records the contract exists to forbid. |
| `VACANTSITE = 'No'` and the species field says `Vacant site` | **82** | treats it as stated vacancy — the species field is not naming a plant there — and counts it under the vocabulary rather than the flag. |
| `VACANTSITE = 'Yes'` with a positive `TRUNKDIAM` (1,808 of them also carrying the literal `Vacant site`) | **3,666** | drops `dbh_in` on any planting site and counts it. The contract permits a planting site to carry a trunk diameter; nothing but this rule stops an empty hole claiming a 9 in trunk on the tree profile. |
| `VACANTSITE` null **and** the species field blank | **61** | `planting_site` with `inferred_from_absent_species` — the one branch where the kind is ours, spelled badly on purpose. |

**Two counts that are decisions, not observations, and should be read as such.** `Stump` (1,933
rows) is mapped to `not_a_tree`: a stump is present, so it is not a planting site, and it is not a
tree. And `Unknown` under `VACANTSITE = 'No'` is mapped to `tree` with no species. Both follow R18's
reasoning rather than any statement San Jose makes, and both are argued in the adapter's own
comments so the next reader can disagree with them in one place.

### The tests were broken deliberately, and two of them did not notice

Ten mutations were applied to the adapter and the registry one at a time, each one a plausible
regression, and the suite was required to go red for each. **On the first pass eight went red and
two stayed green.** Both were fixture gaps rather than assertion gaps, which is the more dangerous
kind:

  * **The vacancy vocabulary could be keyed on the wrong case with the suite still green**, because
    every vacancy row in the fixture was *also* flagged `VACANTSITE = 'Yes'` — so the flag reached
    the answer first and the vocabulary was never consulted. Fixed by adding the 82-row case where
    the flag says occupied and the species field says vacant, which is the only case the vocabulary
    decides.
  * **The trailing-space rule could be deleted with the suite still green**, because the fixture did
    not contain a trailing space. Querying the layer for `NAMESCIENTIFIC = 'Ulmus '` returns rows
    holding `Ulmus` — trailing spaces are insignificant to SQL comparison — so the obvious query
    produced a fixture that made the test pass without ever containing the case. Re-fetched with
    `LIKE 'Ulmus_'`, which finds it. The test now asserts on the raw fixture value as well as on the
    parsed one, so the fixture cannot silently lose the case again.

After both fixes all ten mutations go red. The mutation script is not checked in; it is fifteen
lines of `str.replace` and `subprocess.run` and is reproducible from this paragraph.

---

## 7. What this note does not settle

  * **Berkeley.** Unverified, and possibly the best fit in the state. Somebody should open the
    portal in a browser.
  * **Whether San Jose's 344,879 rows should all ship.** 75,886 are vacant sites and 294,649 are
    `OWNEDBY = 'Private'` — the adjacent property owner's responsibility, which is San Jose's model
    for street trees and not a reason to exclude them, but it is a product question about what the
    map draws and it is not this note's to answer.
  * **The migration.** Section 5 says what the constraints must become. It does not write them, and
    the numbers in it have not been run against a database, because building was out of scope.
  * **Whether the seed's species catalogue survives 618 new scientific names.** The stub ceiling and
    `Fixtures/species/*.yaml` are keyed to San Francisco's 577. Nothing here touched them.
