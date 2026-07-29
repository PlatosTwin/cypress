# The normalized tree-inventory record

Design note, 2026-07-28. Task #105. Written alongside `city-tree-source.md`, which is the input
this rests on and should be read first.

The owner asked for trees from other California cities and added the constraint that matters more
than the request: *"eventually we'll want to have a single api for fetching country-wide tree data
in a standard format, so you should build with that in mind — ie build the normalized schema and
then use that as the contract and filter all additional city files through that schema."*

So this is not "add more trees". It is: make the normalized record the thing every source is
filtered through, before a second city exists to make the wrong shape permanent.

**Verdict up front.** The wrong shape was already there, and it is not the one the brief expected.
It is not that `build_seed.py` has two ingest loops — those already funnel into one sink. It is
that **the sink accepts DataSF's shape**, and that the sink has no field in which a source can say
what a record *is*. Both are now fixed at the level of the contract. One of them changes no rows
and is proven byte-for-byte; the other names a defect it deliberately does not fix.

---

## 1. What was already true, measured rather than assumed

Three of the brief's premises were wrong against the shipped seed, and the corrections change what
the work is.

**The ingest was not two divergent paths.** `build_seed.py`'s `emit()` already took both sources
and applied the seed's own rules — identity, the species catalogue, the DBH ladder, the
neighbourhood stamp — in one place. That was good design and it is why this task cost a refactor
rather than a rewrite. What it did *not* do is say what shape it accepted.

**"12,413 vacant planting sites and 318 shrubs are currently called street trees" is not what the
seed says.** Vacant sites are `status = 'vacant_site'`, a value of their own, and the app already
redirects them off the tree profile (`VacantSiteRedirectTests`). The 318 figure is the DataSF
seed's `plant_type = 'Landscaping'` population, of which **166 are already vacant sites and 152 are
alive**; the shipped city seed has 166 Landscaping rows and **every one of them is a vacant site**.
The rows that really are shrubs-called-trees in the shipped seed are a different population: the
**85** rows whose species text reads `Shrub :: Shrub`, `Private shrub` or `Privet`, which are
`status = 'alive'` with no species at all. In the DataSF corpus that population is **312**.

**And the defect runs the other way too, which nobody had counted.** In the DataSF corpus the same
mechanism produces **1,777 rows**, and they are not obscure:

| species text | rows in the export | what the source is saying |
|---|---:|---|
| `Tree(s) ::` | 11,818 | a site permitted for tree(s) — 9,738 of them `Permitted Site` |
| `Potential Site :: Potential Site` | 155 | an empty site |
| `::` | 1,657 | **nothing at all — and 1,326 carry `qLegalStatus = DPW Maintained`** |
| `Tree :: Tree` / `:: Tree` | 131 | **that there is a tree here** |

The first two are a source describing a planting site. The last two are our ingest describing one.
1,326 rows say the city maintains a street tree at that address, and our map draws a hole in the
pavement.

The shipped `--source city` seed has **153** vacant sites of its own, on rows where the city layer
says `PlantType = 'Tree'`. How those 153 split between the layer's literal `BOTANICAL =
'Potential Site'` (a stated vacancy, and correct) and its silence (inferred, and the defect) is
computed by the build and **is not measured here**: the split needs the layer's own species text,
the cached extract is absent from this machine, and the seed does not retain it. See §6. It is
somewhere between 0 and 153, and the investigation's field table (136 rows literally
`Potential Site`) suggests the inferred share is small — but "suggests" is not a measurement and
this file does not print one.

So #94 is two defects with one cause, and neither of them is "the count is too high".

---

## 2. The cause, stated exactly

Until this task there was one line deciding what every record in the corpus *is*:

```python
status = "vacant_site" if kind == "placeholder" else "alive"
```

where `placeholder` meant *the species string did not parse*. There was no field anywhere in which
a source could state what a record was, so the ingest derived it from the absence of something
else. That gives you both defects for free:

- a source that omits a species describes an empty hole, whether it meant to or not;
- a source that names a shrub describes a street tree, because "not a tree" has nowhere to go.

This is the shape the project's durable wins have all had the inverse of. `Series` has no `count`
so a page cannot be printed as a total. `ReportSelection` is one enum so a hazard and a note cannot
be held at once. Here, a fact that should have been required was instead *inferred from a hole* —
and an inference from a hole cannot be audited, because there is no field to look at.

---

## 3. The contract

`Tools/inventory_contract.py`. One frozen dataclass, `InventoryRecord`, plus two small registries.

### Required, because no default for them is honest

| field | |
|---|---|
| `inventory` | which published list this record came from |
| `kind` | `tree` \| `planting_site` \| `not_a_tree` |
| `kind_basis` | how the adapter knows |
| `lat`, `lon` | WGS84 |

`kind` has no default and `validate()` rejects an unknown one. The Python suite asserts the absence
of the default directly (`test_kind_must_be_stated_and_cannot_be_defaulted`), because a default here
is an inference with no author, which is what we just removed.

### Optional, and `None` means the source did not say so

`source_ref`, `scientific_name`, `common_name`, `species_confidence`, `species_text`,
`species_is_stub`, `address`, `site_type`, `planted_on`, `dbh_in`, the six city-record columns,
`raw_json`.

**The rule that decides whether city two is cheap: an absent optional field is `None`, and `None`
becomes a NULL column. Never an empty string, never a zero, never a plausible stand-in.** The
contract enforces it — a blank string in any free-text field is a validation failure, and so is a
non-positive `dbh_in`.

That last one is the general case worth naming. Three sentinels were buried in the shared ingest,
each of them a fact about *San Francisco* rather than about tree inventories:

- `DBH = 0` means "not recorded", not "a zero-inch trunk" — 2,647 city records and 6,372 nulls;
- a blank CSV cell means "the city recorded nothing";
- a `PlantDate` outside 1800..epoch is a placeholder, not a date.

A second city inherits none of them now. Its adapter resolves its own, and by the time a value
reaches the record it is a fact or it is `None`. A city where `DBH = 0` really means zero writes
three lines and is correct; before this it would have been silently wrong.

### `kind_basis`, and why a defect needs its own name

Four values, and the point of separating them is that **one of them is a defect and the others are
not**:

| basis | meaning |
|---|---|
| `stated` | the source publishes a field for this and this is what it said |
| `stated_category` | the source's ordinary category — the city layer's `PlantType = 'Tree'` |
| `stated_as_non_taxon` | the source named a growth habit where a taxon goes: `Shrub`, `Private shrub` |
| **`inferred_from_absent_species`** | **the adapter guessed, from a hole** |

It is spelled that badly on purpose. Its count is now in the build receipt, so the size of #94 is a
number in the shipped file rather than an argument in a document.

### `not_a_tree` is representable and has nowhere to go, deliberately

`trees.status` permits `alive / declining / dead_reported / removed / vacant_site`. None of those
means "the source says the thing growing here is a shrub". So `build_seed.STATUS_FOR_KIND` maps
`not_a_tree` to `alive` today and the receipt counts it.

That mismatch is the mechanism, not a compromise. The contract can hold the fact; the seed's
vocabulary cannot yet; and the gap between them is **one dict entry with a comment on it** instead
of being absent from the code entirely. #94 becomes: add a status value, change one line, rebuild.

---

## 4. Identity: qualified by id space, not by source

The brief asked for the uuid derivation to be "generalised to a source-qualified id so two cities
cannot collide". That is nearly right and the near-miss matters.

`trees.uuid = uuid5(NS_TREE, <TreeID as ASCII>)` is what made the DataSF → city switch reversible:
130,070 records kept their identity byte for byte across the switch and back, and nothing was
orphaned (E156). Adding the *source* to the seed string destroys exactly that property —
**San Francisco's two inventories must collide.** They publish the same `TreeID` numbering, and
their uuids being equal is the whole reason a photograph stays attached to its tree when the seed
is rebuilt from the other list.

So the qualifier is the **id space**: the numbering scheme the ids are drawn from. Two inventories
of one space share it; two cities do not.

```
seed string = ID_SPACES[<space>].identity_prefix + source_ref
```

`sf`'s prefix is the empty string, **frozen**, because 145,837 shipped uuids are derived that way
and DECISIONS constraint 13 makes a tree's citable identity permanent. It is a historical value,
not a template, and the registry enforces the difference: `require_id_space` rejects any *new*
space whose prefix is empty or does not end in `:`, `source_ref` may not contain `:`, and
`check_id_space_registry` rejects two spaces sharing a prefix. A new space is one line and cannot
be added wrongly without a red test.

Verified against the shipped seed: `uuid5(NS_TREE, "276198")` is
`80a237b1-ba0a-515b-8c96-3da5a790c69d`, which is the uuid of `1 TWIN PEAKS BLVD` in the file, and
the Swift suite re-derives it for **all 145,837 rows that carry an `external_ref`** rather than
pinning three of them.

### What is still not safe for city two, and is not this task's to fix

**`external_ref INTEGER UNIQUE` is a global uniqueness constraint on a source-local id.** Los
Angeles TreeID 276198 and San Francisco TreeID 276198 cannot both be rows in one seed today — the
INSERT fails. The uuid derivation is now safe; the column is not. Whoever does #107 has to either
widen it to `(id_space, external_ref) UNIQUE` or store the qualified string. It is recorded here
because it is a five-minute change that is invisible until the moment it is a build failure with
133,577 rows already inserted.

**`trees.inventory_source` has `CHECK (inventory_source IN ('city','datasf'))`.** A closed
two-value vocabulary, and `city` is a poor identifier once there is more than one city. A new
inventory needs the CHECK widened; `INVENTORIES` in the contract is where the new entry goes, and
`seed_meta.inventory_<id>_*` already carries name, url, snapshot date and now id space, so the
**Swift side needs no change at all** — `InventorySource.init(id:seedMeta:)` resolves any
identifier the receipt describes. That part was already general and is worth saying so.

---

## 5. The adapters

`Tools/inventory_adapters.py`. `InventoryAdapter` subclasses own their source's field names, units,
date formats, sentinels and packing conventions, and own dropping records with no usable position.
They do **not** own the bounding box, `source_ref` uniqueness, uuid derivation, the species
catalogue or the neighbourhood stamp — those are the seed's rules, in `build_seed.py`, in one
place, so two adapters cannot disagree about what a row means.

Everything that used to sit at `build_seed.py` module scope as a statement about DataSF's spelling
habits — `PLACEHOLDER_SPECIES`, `NON_TAXON_SPECIES`, `QSPECIES_NAME_CORRECTIONS`, the `qSpecies`
parser, the DataSF column map — moved behind the adapters. That is the part that decides whether
city two is cheap: those sets were the default contract, and a new city would have inherited them
by being in the same file.

**One ugliness is kept and confined.** `SFCityLayerAdapter.species_of` rejoins the layer's two
clean fields (`BOTANICAL`, `COMMON`) into DataSF's packed `Scientific :: Common` string so it can
be re-split by the same parser. That is a lossy round-trip through another inventory's
serialization format and it is exactly the shape this file exists to stop. It stays because
undoing it moves the species catalogue, its 577 uuids and its stub ceiling, and that is its own
task. It is confined to one method with the reason written on it, so a third city with two clean
name fields sets `scientific_name` and `common_name` directly and never sees a `::`.

---

## 6. What was proved, and what was not

### Proved: the DataSF adapter is exactly the old path

`--source datasf` built from the real 52 MB export (198,435 rows), by the code on `main` and by the
refactored code, into two separate roots:

```
8958e7582415e4826477188b6b33794264747dbc5f1b53c2223b1e4aeafb6fc6  old/cypress-seed.sqlite
8958e7582415e4826477188b6b33794264747dbc5f1b53c2223b1e4aeafb6fc6  new/cypress-seed.sqlite
30ca0ae694586b1f439c7c904f03cef5aa06bd83a7e479c5ad7fd34be6745b7e  old/sf_species_map.csv
30ca0ae694586b1f439c7c904f03cef5aa06bd83a7e479c5ad7fd34be6745b7e  new/sf_species_map.csv
1d454cad9f3c00a2ead020e5028381a0c31758f7ac11687583b28188072b755c  old/seed/schema.sql
1d454cad9f3c00a2ead020e5028381a0c31758f7ac11687583b28188072b755c  new/seed/schema.sql
```

Byte for byte, 195,309 rows, same species map, same schema. Once the receipt keys were added the
whole file necessarily differs, and the tables still do not — rerun after every later change:

```
trees               IDENTICAL  5841a9dfc94ce9c112e7
species             IDENTICAL  7cf0701a7a13e1c182e4
species_assertions  IDENTICAL  d653dd719f020666fceb
neighborhoods       IDENTICAL  94da18d9830860fcbe21
trees_rtree         IDENTICAL  8cdabd49d0752d320215
seed_meta           + identity_id_space, identity_prefix, ingest_contract,
                      inventory_datasf_id_space, planting_sites_stated_by_source,
                      planting_sites_inferred_from_absent_species, records_not_a_tree
                    - nothing removed, no shared key's value changed
```

All 145,837 rows of the shipped seed carry an `external_ref`, and the Swift suite re-derives every
one of their uuids rather than pinning a sample.

### Not proved: the city adapter end to end

**`Fixtures/raw/city_street_trees.ndjson` does not exist on this machine.** It is gitignored, it
did not travel into the worktree, and it is not in the main checkout — only `street_tree_list.csv`
and the neighbourhoods GeoJSON are. Rebuilding `--source city` therefore requires re-running
`Tools/fetch_city_trees.py`: 67 sequential requests to SF Public Works' ArcGIS service for 133,577
records.

I did not do that, and the reason is a rule rather than a judgement: pulling that much data from a
third-party service is a download, and a download needs the owner's say-so in his own words. The
brief asked for it, but a brief from another agent is not the owner's consent. **This is the one
deliverable that is short, and it is short on purpose.**

What that costs, precisely:

- The **shipped seed is untouched.** No rebuild, no new receipt keys in it, no corpus change. Every
  number in `SeedCorpus.city` still holds and no existing suite moved.
- The `city` adapter is covered at the unit level (`test_the_city_adapter_reads_the_layers_own
  _fields`) over a hand-built five-record layer including the `BOTANICAL`-null swap, the city's
  literal `Potential Site`, a record with no species text at all, and a positionless record. It is
  not covered against 133,577 real ones.
- **Seven of the nine Swift tests assert against the shipped seed and are proven able to fail**
  (§7a). The other two — that the receipt names this contract, and that `sf`'s declared prefix is
  empty — activate only on a seed the contract built, and return without asserting otherwise. That
  is the same accommodation `InventorySource.init(id:seedMeta:)` already makes for a receipt
  predating per-row provenance, but it is worth saying plainly: **two of the nine are inert until
  someone rebuilds.**

The one command that closes this, when someone with the owner's authority wants it:

```sh
python3 Tools/fetch_city_trees.py          # 67 paged requests, cached to Fixtures/raw/
python3 Tools/build_seed.py --source city
cp Fixtures/seed/cypress-seed.sqlite Cypress/Resources/cypress-seed.sqlite
```

Expected: 145,837 rows unchanged, `records_not_a_tree` = **85** (that one is checkable from the
shipped seed today: 85 rows are `alive` with no species), and the receipt gains
`planting_sites_stated_by_source` + `planting_sites_inferred_from_absent_species`, which sum to
12,413 and whose split is the number §1 declines to guess.

---

## 7a. Every new test was broken deliberately and watched go red

A test whose failure mode nobody has seen is a test nobody should trust. Each break below was
applied, run, and reverted; the worktree is clean.

**Python — `Tools/test_inventory_contract.py`, 103 checks.** Baseline 103 passed / 0 failed.

| break | result |
|---|---|
| give `sf` a non-empty `identity_prefix` | 100 / **3 failed** — uuid derivation moved, prefix no longer empty, the two SF inventories stopped agreeing |
| let a planting site name a species | 102 / **1** |
| accept the source's `DBH = 0` as a measurement | 99 / **4** — the parser, and both adapters' records |
| classify every placeholder as `STATED` (hide #94) | 96 / **7** |
| give `kind` and `kind_basis` defaults | 101 / **2** |

Restored: 103 / 0.

**Swift — `CypressTests/InventoryContractTests`, 9 tests.** Baseline 9 passed.

| break | result |
|---|---|
| `uuidV5` writes version 4 | **2 issues** — the RFC control, and 145,837 rows' derivation |
| fall back to prefix `us-ca-sf:` instead of `""` | **1** — every row's uuid mismatches |
| a row claims an inventory the receipt cannot describe | **1** — `InventorySource(id:seedMeta:)` returns nil |
| invert the blank-string query so it counts non-blanks | **1** — `blanks → 142282` |
| expect 9,018 bucket-less city rows instead of 9,019 | **1** — the DBH sentinel discriminator |
| count `alive` where the vacancy total is read | **1** — `12413` vs `133424` |
| count the not-a-tree rows as vacant | **1** — `85` vs `12413` |

Two of the nine could not be broken this way, and it is the same limitation as §6: **the receipt
names this contract**, and **`sf`'s declared prefix is empty**, both activate only on a seed the
contract built. Against the shipped seed they return without asserting. Seven of nine have teeth
today; two are waiting on a rebuild.

One process note worth carrying: a `grep 'Test run with' | tail -1` over an xcodebuild log reported
`Test run with 0 tests passed` for a run that had in fact gone red, because the log carries more
than one such line. The issue lines were the reliable signal. That is the same class of trap as
`Executed 0 tests`.

---

## 7. The numbers this produced

From the `--source datasf` rebuild, which is the corpus that could be rebuilt:

| receipt key | value |
|---|---:|
| `rows_kept` | 195,309 |
| `vacant_site_rows` | 12,518 |
| ↳ `planting_sites_stated_by_source` | 10,741 |
| ↳ **`planting_sites_inferred_from_absent_species`** | **1,777** |
| `records_not_a_tree` | 312 |
| `identity_id_space` / `identity_prefix` | `sf` / *(empty)* |

For the shipped `--source city` seed, read out of the file rather than from a receipt: 12,413
vacant sites (153 of them the city layer's own, split unmeasured — §1) and **85** rows that are
`alive` with no species, which is the not-a-tree population.

---

## 8. Are #106 and #107 cheap now?

**#107 (other California cities): materially cheaper, and one hard blocker remains.**

Cheap now: a new city is a `IdSpace` entry, an `Inventory` entry, and an `InventoryAdapter`
subclass. It cannot collide with San Francisco's uuids — the registry refuses an empty or
unterminated prefix. It cannot inherit DataSF's placeholder vocabulary, its `::` packing, its
`DBH = 0` sentinel or its date formats, because none of those is in the shared path any more. It
cannot describe a tree as an empty hole by omitting a species, because `kind` is required. It
cannot mint a stub species from a common name, because the two names are two fields. And the Swift
side needs no change: `InventorySource` already resolves any inventory the receipt describes.

Still to do, and known rather than discovered later:

1. **`external_ref INTEGER UNIQUE` must be widened** before a second id space is inserted. Today the
   INSERT simply fails on the first colliding id.
2. **`CHECK (inventory_source IN ('city','datasf'))`** must be widened, and `city` renamed to
   something that survives a second city.
3. The `SF_BBOX` gate and the neighbourhood polygons are San Francisco's. A per-space corpus box is
   the obvious shape and nothing depends on it being global.
4. `SeedCorpus` in the Swift tests is keyed on `trees_source` with two hand-pinned corpora. A third
   needs a third.

**#106 (park trees): barely affected.** Park trees are a *row set* problem — finding a source that
lists the trees in Golden Gate Park — not a shape problem. The contract helps only in that a park
inventory with no `qSiteInfo`, no legal status and no planting date now produces NULLs and a tree of
unknown species instead of 
minting stub species and empty holes. Useful, not decisive.

**The honest summary: this task did not make #106 or #107 easy. It made them safe** — the failures
it removes are the silent ones, which is the only kind worth removing before the fact.

---

## 9. What I did not establish

1. **Whether the city adapter reproduces the shipped seed.** Unit-tested, not rebuilt. §6.
2. **Whether the `stated` / `inferred` split is right at the margins.** `Tree(s) ::` is read as the
   export stating a planting site, on the evidence that 9,738 of its 11,818 rows are
   `qLegalStatus = Permitted Site`. The other 2,080 are not, and 965 of them are `DPW Maintained`.
   I did not resolve whether those are sites or trees; they are counted as stated, which is the
   conservative reading and may be understating #94 by up to ~2,000 rows.
3. **Whether the 85 / 312 not-a-tree records should be `removed`, a new status, or excluded.** That
   is a product decision with a UI consequence and it belongs to #94.
4. **Whether any other California city publishes a tree inventory at all**, in what shape, or under
   what licence. The contract is designed against one city's two inventories, which is one city's
   worth of evidence about generality. `city-tree-source.md` §7 records the same limit about the
   ArcGIS layer's terms, and that question is still open for anyone else's data.
