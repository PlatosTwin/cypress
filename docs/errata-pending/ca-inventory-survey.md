<!-- UNNUMBERED. Splice the number in at merge; do not edit docs/ERRATA.md from a
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
