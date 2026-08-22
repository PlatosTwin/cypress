# Unnumbered errata — the s17 region generation

Staged per CLAUDE.md, "Numbering and shared files". The orchestrator splices these under real
E numbers at merge and rewrites any code comment that cites this filename.

---

### E??? — The publisher and the app read coverage from different keys, and only an unwritten key kept them agreeing

`SeedCities.coverage` (Swift) reads `seed_meta` for the standardised `coverage_<id_space>` first
and falls back to a hand-mirrored legacy per-city name (`sj_ship_extent`). `Tools/publish_cities.py`
read the legacy name and **only** the legacy name — its `COVERAGE_KEYS` shim — with no path to the
standardised key at all.

The two agreed about San Jose for exactly one reason: nothing had ever written
`coverage_us-ca-sj`. The day anything did, the app's own bundled row and the published manifest
would have stated different coverage for the same city — one saying `downtown`, the other whatever
the new key held — with no error anywhere and nothing comparing them. R37's trailing clause had
already asked for the fix ("when a third city lands, `build_seed.py` should write
`coverage_<id_space>` keys and the publisher's `COVERAGE_KEYS` shim retires"), and the divergence
is what made the ask urgent rather than tidy: the shim was not merely redundant, it was the half of
a disagreement that had not happened yet.

Closed three ways in the s17 round: `Tools/build_seed.py` writes `coverage_<id_space>` for every
contributing space; `publish_cities.coverage_for` reads the two keys **in the same order the app
does**; and `Tools/test_publish_cities.py` pins that order with a fixture where the two keys carry
*different* values, which is what makes the preference observable rather than assumed.

Red-proved: reversing the two keys' order in `coverage_for` fails
`Tools/test_publish_cities.py` with "coverage_for did not prefer the standardised
coverage_<id_space> key over the legacy one".

---

### E??? — `site_lineage`'s split guard asked about id spaces, and every NYC borough is one id space

`Tools/publish_cities.build_city_file` refused to sever a `site_lineage` link that crossed an **id
space** before deleting the other city out. The comment beside it said none exist today "(a site's
replacement stands in the same city)", which was true and is the wrong granularity for what the cut
became.

RULING D1 makes the published unit the borough. All five New York boroughs are in one id space
(`us-ny-nyc`), so a Queens tree whose predecessor stood in Brooklyn would have **passed** the
id-space check and then been severed by the per-region delete — silently, on the first NYC publish,
with the provenance link the check exists to protect gone from both packs.

A cut is a cut at whatever granularity the cut is made. The check is now keyed on `region_id`,
which is strictly stronger: it still catches every cross-space link (those cross regions too) and
additionally catches the cross-borough case that motivated it.

Red-proved: `Tools/test_publish_cities.py` builds a fixture with a Queens tree whose
`site_lineage` points into the Bronx and asserts the publisher exits non-zero with "cross regions".

---

### E??? — `Fixtures/seed/schema.sql` had drifted from the generator that writes it

The tracked schema contract is written by `Tools/build_seed.py` from its own `SCHEMA_SQL`. The
copy on disk did not match: `species_map.is_non_taxon`'s comment on disk still read *"A tree stands
at the site, so it is NOT a placeholder and its status is `alive`"*, a claim `SCHEMA_SQL` had
already corrected to say the opposite — that the column is a claim about the **string** and says
nothing about any row's status, San Jose's `Stump` being the counterexample.

Comment-only, so no DDL diverged and nothing shipped wrong. It is recorded because of what the
drift means rather than what it cost: the contract file is tracked precisely so a reader can trust
it without running the generator, and a file that can silently fall behind its generator does not
support that. It is also, by coincidence, drift in the one comment about status-versus-string
independence that this round's standing-dead work turns on.

Corrected as a side effect of regenerating the file for `dim_region`. A reviewer seeing that hunk
in the diff should know it was not hand-edited.

---

### E??? — `STATUS_FOR_KIND` made a whole column of the seed schema unreachable

`trees.status` has permitted `alive | declining | dead_reported | removed | vacant_site` since
before the ingest contract existed, and RULINGS R19 defines `dead_reported` as a tree still
standing over a pavement. `build_seed.STATUS_FOR_KIND` was a dict keyed on `kind` **alone**, with
three entries mapping to two values — so **no adapter, from any source, could cause a row to ship
as anything but `alive` or `vacant_site`.** Three of the five permitted statuses were
unreachable by construction.

`docs/investigations/nyc-street-trees.md` §6 originally recorded this as a missing *seed* value and
was wrong about it; `feat/nyc-ingest` found the real location and left a correction block saying so
(*"the CONTRACT lacks the slot, but the SEED SCHEMA does not"*). That correction is what let RULING
D17 rest the s17 generation's identity on the region column instead of on this, since closing it
needs no migration.

The cost was measurable and being paid: NYC Parks publishes `TPCondition`, 10,635 of its rows are
a `Full` structure in `Dead` condition, and the ingest had nowhere to put that but a free-text
`permit_notes` string.

Closed by `InventoryRecord.condition` / `condition_text` plus `build_seed.status_for_record`, which
reads both. `condition=None` — "the source made no claim" — maps exactly where the old dict mapped,
so San Francisco and San Jose, whose sources publish no condition field, move **not one row**.
That is asserted rather than assumed: `Tools/test_build_seed_status.py` pins the None case against
a literal copy of the pre-s17 dict, and the rebuild receipt in the PR body shows the counts
unchanged.

---

### E??? — Per-inventory completeness was recorded under two ad-hoc names and did not extend

`seed_meta.rows_from_<inventory>` has always said what **shipped**. What each source says it
**publishes** was recorded twice, differently: `trees_source_feature_count`, which is global and so
could only ever describe one of the file's inventories, and `sj_source_feature_count`, prefixed by
hand for the second. So "did we ship all of it" was answerable for one inventory at a time, never
uniformly, and `sf_datasf` had no such number at all.

With New York adding two more inventories in a third id space, the ad-hoc shape does not extend —
each new inventory would need its own invented key name, and the verifier would need to know all of
them.

Standardised as `inventory_<id>_source_feature_count`, the same `inventory_<id>_*` shape as the
name/url/date triple beside it and keyed by the same identifier `trees.inventory_source` stores.
`Tools/verify_seed.py` gains check 1d, which **reports** the shortfall rather than failing it — a
file shipping a downtown window out of 344,879 records is a decision, and the defect is a *silent*
gap, not a stated one. Both legacy keys are kept: `Cypress/Data/Tests/DataGates.swift` reads
`trees_source_feature_count` today.

An absent key means the source publishes no count, which is deliberately distinguished from a count
of zero — reporting the first as the second would show a reassuring 100%-complete inventory with
nothing behind it.

---

### E??? — `build_seed.py` wrote inventory identity as literals beside a comment asserting they agree

`seed_meta.trees_source`, `trees_source_name` and `trees_source_url` were written as literal
strings (`"sf_city"`, the name spelled out a second time, a module-level URL constant) while
`INVENTORIES["sf_city"]` in `Tools/inventory_contract.py` already held all three. The comment
directly above them stated that this id, `trees.inventory_source`'s stored value and the
`inventory_<id>_*` key prefix "agreeing is what lets `InventorySource(id:seedMeta:)` resolve a row's
provenance without knowing any city's name in advance" — an invariant nothing enforced, on a value
the app's provenance resolution depends on. Renaming an inventory in the registry would have left
this key holding the old string, silently, in every published file. The same pattern held for
`attributes_source`, `sites_source`, and the `inventory_sf_*_name` / `_url` pairs.

All now read from the registry, so the comment's claim is true by construction. Verified against
the shipped values before and after: the six affected keys are byte-identical in a rebuild, which
is what makes this a de-duplication rather than a change.

---

### E??? — "F9 containment" does not exist

The s17 brief named "Stage 0's F9 containment" as a known defect to fix in this round. **There is
no finding labelled F9 anywhere in the repository** — not in the working tree and not in any of the
1,318 commits across all branches. The complete set of F-labels ever used in `docs/ERRATA.md` and
`docs/RULINGS.md` is F1–F5; they are per-PR review-finding labels, not a global register, and the
numbering has never reached 9.

The nearest real thing is Stage 0's **review finding 9**, which is a *ruling* rather than a defect
(`docs/ERRATA.md` E275 §5 records it among "judgment calls rather than defects"): the offline
Cities screen shows the same cities as the online one. It is implemented
(`CityDownloadsModel.swift`, cited in a comment there) and pinned by
`BundledCityTests.aCityCanNeverOccupyTwoRows`.

Recorded so the next round does not re-derive the same negative. Nothing was changed for it.
