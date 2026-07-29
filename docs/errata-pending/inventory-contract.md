### The seed said "empty planting site" where the source said nothing, and nobody could count it

`Tools/build_seed.py` decided what every record in the corpus *was* with one line:

```python
status = "vacant_site" if kind == "placeholder" else "alive"
```

where `placeholder` meant *the species string did not parse*. There was no field anywhere in the
ingest in which a source could state what a record was, so the builder inferred it from the absence
of something else. That produces two errors at once, and both are in the shipped seed.

**A source that omits a species describes an empty hole in the pavement.** In the DataSF corpus
**1,777** of the 12,518 vacant planting sites are ours, not the export's: their `qSpecies` is blank
(`::`, 1,657 rows) or reads `Tree :: Tree` (131). **1,326 of the blank ones carry
`qLegalStatus = DPW Maintained`** — the city saying it maintains a street tree at that address —
and our map draws a planting site there. The remaining 10,741 are genuine: `Tree(s) ::` on a
`Permitted Site` and the literal `Potential Site` are the source describing a site, and those are
correct.

The shipped `--source city` seed has 153 vacant sites of its own, on rows the city layer lists with
`PlantType = 'Tree'`. Their split between stated and inferred was **not measured** — it needs the
layer's species text, and the cached extract is absent from this machine — so no number for it is
recorded here.

**A source that names a shrub describes a street tree.** `Shrub :: Shrub`, `Private shrub` and
`Privet` are the city telling us, in the only field it has, that the thing growing there is not a
tree. `trees.status` has no value for that, so they ship as `alive` with no species: **85** rows
under `--source city`, **312** under `--source datasf`.

Neither number existed before. Both were inside `vacant_site_rows` and `non_taxon_rows`,
indistinguishable from the rows that are correct.

**Fixed in shape, not in rows.** `Tools/inventory_contract.py` requires every record to state its
`kind` (`tree` / `planting_site` / `not_a_tree`) and its `kind_basis` — where
`inferred_from_absent_species` is spelled that badly on purpose. `build_seed.STATUS_FOR_KIND` is
the one place the contract's vocabulary meets the seed's, and `not_a_tree` maps to `alive` there
with the reason written on it. The build receipt now carries
`planting_sites_stated_by_source`, `planting_sites_inferred_from_absent_species` and
`records_not_a_tree`, so the size of the defect is a number in the file.

**No row moved.** `--source datasf` built by the code on `main` and by the refactored code over the
same 198,435-row export produces the same sha256 (`8958e758…`), the same `sf_species_map.csv` and
the same `schema.sql`; after the receipt keys were added the five tables still hash identically and
`seed_meta` differs by exactly six added keys. Correcting the 1,777 and the 312 changes the corpus
and belongs to #94.

### Three counts in the #94 brief did not describe the shipped seed

- **"318 shrubs are called street trees."** 318 is the DataSF corpus's `plant_type = 'Landscaping'`
  population, of which 166 are already `vacant_site` and 152 are `alive`. The shipped `--source
  city` seed holds 166 `Landscaping` rows and **every one is a vacant site**. The rows that really
  are shrubs-called-trees there are a different population — the 85 above, found by species text
  rather than by `plant_type`.
- **"12,413 vacant planting sites are called street trees."** They are `status = 'vacant_site'`, a
  value of their own, and `TreeProfileDestination` already redirects them off the tree profile
  (`VacantSiteRedirectTests`). The defect is the copy that calls all 145,837 rows street trees, and
  separately the 153 that are not vacant at all.
- **The defect runs both ways.** The brief describes only vacant-sites-called-trees. The larger and
  less visible half is trees-called-vacant-sites, which nobody had counted.

### `external_ref INTEGER UNIQUE` is a global constraint on a source-local id

Not a defect today — one city, one id space — and a hard failure the first time a second city is
ingested. Los Angeles `TreeID` 276198 and San Francisco `TreeID` 276198 cannot both be rows in one
seed: the INSERT fails on the unique index. The uuid derivation is now safe against this
(`ID_SPACES[<space>].identity_prefix + source_ref`, verified over all 145,837 shipped rows) but the
column is not. Whoever does #107 has to widen it to `(id_space, external_ref)` or store the
qualified string. Recorded here because it is a five-minute change that is invisible until it is a
build failure with 133,577 rows already inserted.

`CHECK (inventory_source IN ('city','datasf'))` has the same shape: a closed two-value vocabulary
in which `city` is a poor identifier once there is more than one city. The Swift side needs no
change — `InventorySource.init(id:seedMeta:)` already resolves any identifier the receipt describes.
