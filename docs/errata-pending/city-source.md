The map drew a different city's trees than the city's map did, and nothing said which

For its whole life the seed has been built from DataSF's `tkzw-k3nq` export, and the app has
described those 195,309 rows as San Francisco's street trees. The city's own public map at
<https://bsm.sfdpw.org/urbanforestry/> draws a different list — SF Public Works' operational
`BUF_Street_Trees` layer, 133,577 records — and the two disagree in both directions. The owner found
this by hand: a 36-inch Monterey Pine at `1 TWIN PEAKS BLVD`, TreeID 276198, on the city's map and
absent from ours. It was not a pipeline bug. `tkzw-k3nq` has never contained it, and has never
published any `TreeID` above 276035, while the operational layer has issued ids to 277733.

Measured against a full extract of both, 2026-07-26: **130,070 records are in both, 65,239 are in
DataSF only, 3,507 are in the city's layer only.** The 65,239 are mostly things the city's map
deliberately does not show — 37,707 `Permitted Site` rows where a permit exists and the tree may not,
7,356 `Undocumented` — but **17,443 of them are `alive`, carry an ordinary legal status (15,348
`DPW Maintained`) and sit on ordinary sidewalk sites**, and nothing in either schema says why the
city no longer lists them. That residue is unresolved and it is the largest thing the switch takes on
faith.

The owner has ruled that the city's own inventory is the source of truth, and it now is:
`Tools/build_seed.py --source city` is the default and ships 133,577 rows. **`--source datasf` still
builds the old seed and is still tested**, because reversal had to stay one command rather than one
revert. `Tools/fetch_city_trees.py` caches the extract to `Fixtures/raw/` — 67 sequential pages, one
second apart, resumable — and the build never touches the service.

**No uuid moved.** Both paths derive `trees.uuid` as `uuid5(NS_TREE, <TreeID>)` and both inventories
use the same `TreeID` space, so all 130,070 shared records kept their identity byte for byte, in both
directions. That was the precondition for making the switch reversible at all, and it was verified
rather than assumed.

Two things got worse and are worth naming rather than discovering later. **Vacant planting sites
collapse from 12,518 to 153**: the city's layer has no vacant-site category — `PlantType` is `Tree`
for every one of its records — so the state #11 designed, #31 redirects to and #32 counts now
describes 153 sites. And **nine DataSF columns have no counterpart**, so there are no planting dates
at all, no `Cared for by`, no `Legal status`, and no `Stands on` sentence. Both are listed in
`seed_meta.columns_absent_from_source` and both reverse with the flag.

The deeper defect was not the row count. It was that a 100 MB file shipped inside the app with
**nothing anywhere saying where its contents came from or how old they were** — not on a screen, not
in the database, not in a log. That is why "is our data stale?" could not be answered when it was
asked; the only way to settle it was to re-download the source and diff. The seed now carries
`trees_source`, `trees_source_url` and `trees_snapshot_on` in its build receipt, written from the
extraction's own record rather than a clock, and the tree page's city-record section ends with
`From the SF Public Works street tree inventory, 26 July 2026.` The seed contract fails if that date
is missing or unparseable.

Two smaller repairs rode along. `plant_type` held `Tree` 194,988 times and `tree` three times
(TreeIDs 253212, 253634, 96598), so every `WHERE plant_type = 'Tree'` in the product silently dropped
three rows; the build now folds case-variant spellings in the five columns the app compares against
literals, and the seed contract fails if any return. Free text — `address`, `plot_size`,
`permit_notes` — is deliberately left alone, because `McAllister St` and `MCALLISTER ST` are both
spellings the city uses and picking one would be editing its record rather than repairing a filter.
And the tree page used to say `The city's street tree inventory records no pruning dates or schedule`,
which was true of the export and is false of the layer we now ship: it carries `Prune_Year` on every
record. That field is a property of the **keymap grid**, not the tree — 133,577 records share 106
distinct values, 5,147 of them the exact string the owner saw under 276198 — so the seed does not
carry it and the sentence now says the city records pruning by block and not by tree.
