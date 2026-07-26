The map drew a different city's trees than the city's own map did, and nothing said which

For its whole life the seed has been built from DataSF's `tkzw-k3nq` export, and the app has
described those 195,309 rows as San Francisco's street trees. The city's own public map at
<https://bsm.sfdpw.org/urbanforestry/> draws a different list — SF Public Works' operational
`BUF_Street_Trees` layer, 133,577 records — and the two disagree in both directions. The owner found
it by hand: a 36-inch Monterey Pine at `1 TWIN PEAKS BLVD`, TreeID 276198, on the city's map and
absent from ours. Not a pipeline bug. `tkzw-k3nq` has never contained it, and has never published any
`TreeID` above 276035, while the operational layer has issued ids to 277733.

Measured against a full extract of both, 2026-07-26: **130,070 records are in both, 65,239 are in
DataSF only, 3,507 are in the city's layer only.** The 65,239 are mostly what the city's map
deliberately does not show — 37,707 `Permitted Site` rows where a permit exists and a tree may not,
7,356 `Undocumented` — but **17,443 are `alive`, carry an ordinary legal status (15,348 `DPW
Maintained`) and sit on ordinary sidewalk sites**, and nothing in either schema says why the city no
longer lists them. That residue is unresolved and is the largest thing the switch takes on faith.

The owner has ruled that the city's own inventory decides which trees exist, and it now does:
`Tools/build_seed.py --source city` is the default and ships 133,577 records. **`--source datasf`
still builds the old seed and is still tested**, because reversal had to stay one command rather than
one revert. `Tools/fetch_city_trees.py` caches the extract to `Fixtures/raw/` — 67 sequential pages, a
second apart, resumable — and the build never touches the service.

**No uuid moved.** Both paths derive `trees.uuid` as `uuid5(NS_TREE, <TreeID>)` and both inventories
use the same `TreeID` space, so all 130,070 shared records kept their identity byte for byte, in both
directions. That was the precondition for making the switch reversible at all, and it was verified
rather than assumed.

**Which inventory decides a row is not the same question as which one knows a fact, and answering
them together was the mistake worth recording.** The first build took the city's layer alone. It
publishes seven fewer columns than the export, so the seed came out with **zero planting dates**, no
legal status, no plot sizes and no caretaker — which meant `LandContext.inferred(from:)` could place
no tree, the `Stands on` sentence drew for nobody, and the almanac's elder, plantings and coverage
reads returned nothing for the entire city. Screen 12 lost three rows. Worse, three test suites went
*green* on it: their assertions are exclusions ("no inventory read returns a vacant site") and an
exclusion is trivially true of an empty answer. Only the two UI tests that tap those rows failed, and
they looked like harness flakiness. The shipped build takes the row set from the city's layer and
those seven columns from the export for the 130,070 records both list — 97% coverage, NULL on the
3,507 the export has never heard of — and the controls fire again.

The vacant-site collapse is the one loss that join cannot repair, because a vacant site is a *row*
and rows come from the spine: **12,518 → 153**, with 17 of 41 neighbourhoods now holding none. The
city's layer has no vacant-site category at all — `PlantType` is `Tree` on every one of its records.
The state #11 designed, #31 redirects to and #32 counts still works and is still tested; it now
describes a third fewer neighbourhoods than it has rows for.

The deeper defect was never the row count. It was that a 100 MB file shipped inside the app with
**nothing anywhere saying where its contents came from or how old they were** — not on a screen, not
in the database, not in a log. That is why "is our data stale?" could not be answered when it was
asked; the only way to settle it was to re-download the source and diff. The seed now carries
`trees_source`, `trees_source_url` and `trees_snapshot_on` in its build receipt, written from the
extraction's own record rather than a clock, and the tree page's city-record section ends with `From
the SF Public Works street tree inventory, July 26, 2026.` The seed contract fails if that date is
missing or unparseable. One gate had to move to make room for it: `CityRecordPresentation.isEmpty` is
`facts.isEmpty`, which correctly refuses a header over an empty grid — and on the city-only build that
silently removed the entire section from every tree in the seed. The section now opens for cards
**or** for a provenance line.

Two smaller repairs rode along. `plant_type` held `Tree` 194,988 times and `tree` three times (TreeIDs
253212, 253634, 96598), so every `WHERE plant_type = 'Tree'` in the product silently dropped three
rows; the build now folds case-variant spellings in the five columns the app compares against
literals, and the seed contract fails if any return. Free text is deliberately left alone —
`McAllister St` and `MCALLISTER ST` are both spellings the city uses, and picking one would be editing
its record rather than repairing a filter. And the tree page used to say `The city's street tree
inventory records no pruning dates or schedule`, true of the export and false of the layer we now
ship: it carries `Prune_Year` on every record. That field belongs to the **keymap grid**, not the tree
— 133,577 records share 106 distinct values, 5,147 of them the exact string the owner saw under 276198
— so the seed does not carry it and the sentence now says the city records pruning by block and not by
tree.
