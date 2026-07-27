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
`Tools/build_seed.py --source city` is the default and ships all 133,577 of them. **`--source datasf`
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

The vacant-site collapse was the one loss that join could not repair, because a vacant site is a
*row* and rows come from the spine: **12,518 → 153**, with 17 of 41 neighbourhoods holding none. The
state #11 designed, #31 redirects to and #32 counts still worked and was still tested; it described
a third of the city and nothing else. **That has been undone, and the reason it could be undone
without touching the tree row set is the part worth keeping.**

**The city's layer is not disagreeing with us about vacant sites. It has no such category.**
`PlantType` is `Tree` on all 133,577 of its records; there is no site-status column, no `qSiteInfo`,
no `qLegalStatus`. Reading that silence as "a tree stands there now" would be inferring a fact about
the world from the shape of a schema. That is a different claim from the one this switch makes about
living trees, where the layer *is* the operational record and a tree it stopped listing is most
likely gone. So the seed now carries the export's vacant planting sites as rows alongside the city's
trees: **145,837 rows — 133,577 trees from the city's layer, 12,260 sites from the export** — and
all 41 neighbourhoods hold at least one site again.

The one place the two inventories genuinely contradict each other is a TreeID the export calls an
empty basin and the layer lists as a planted tree. **128 rows**, measured rather than assumed, and
there the city wins, exactly as it does for the tree row set. A further 130 the layer also holds as
empty (`BOTANICAL = 'Potential Site'`) were already in the seed from the first pass. Nothing is
double-counted and no `external_ref` appears twice, because the test is simply "did the city pass
already emit this TreeID".

**No uuid was ever at risk here either, and this was checked rather than reasoned about.** All 12,518
of the export's vacant-site TreeIDs are rows in the new seed; 128 of them are `alive` rather than
`vacant_site`, which is a change of status and not a change of identity. Across every simulator
install on this machine, 23 contribution rows reference a tree and **none of them references a vacant
site**, so the collapse orphaned nothing and the restoration un-orphans nothing. The only vacant-site
uuid written down anywhere in the repo is `aa72e15a-…` in `TreeProfilePreviews`, a preview fixture
constructed in code rather than read from the seed; its TreeID 271641 is back in the file regardless.

**This is what `--source city` means now, not a third flag value.** A `--source` value answers which
inventory the seed believes about the trees, and the export's sites are not a third answer to that
question — no build that wants a working "where a tree could go" can decline them, and no build that
has them is disagreeing with the city about anything. `--source datasf` still builds all 195,309 rows
and is still tested against its own pinned numbers, so reverting is still one command.

**Provenance is now a per-row fact, and it had to become one.** `trees.inventory_source` says which
inventory listed each row, and `seed_meta` carries a name, a url and a snapshot date for each. The
tree page's sentence — `From the SF Public Works street tree inventory, 26 July 2026.` — is true of
every record that draws it, because only the city's trees reach that screen. The vacant site has its
own screen and it used to say nothing at all about where its record came from, which was survivable
while the file held one inventory and is not now: it draws
`From the DataSF Street Tree List, 20 July 2026.` under its stat grid. The seed contract fails if a
row names an inventory the receipt cannot describe, so the sentence can never be resolved to the
other inventory's name by accident.

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

**A UI test had been red since the first round and was not read as such.** `AlmanacGroupTapTests`
locates screen 12's coverage CTA with `label BEGINSWITH "Walk the "`, but
`AlmanacPresentation.coverageCTA` renders `Walk to it` when the count is one, because "walk the one"
is not a sentence. The neighbourhood these tests land in from the simulated fix — Western Addition —
held two young trees under the DataSF export and holds one under the city's, because the switch cut
the seed's planting dates from 70,067 to 28,747. So the button was drawn correctly and the locator
could not see it, and the failure read `§4's CTA is not on the almanac`: a true sentence about the
predicate and a false one about the app. That is the same "blame the almanac for something else"
shape E153 had just removed from these tests. The locator now matches `Walk `, and the count is left
to the assertions that were always about it.

Three smaller repairs rode along. `plant_type` held `Tree` 194,988 times and `tree` three times (TreeIDs
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
And the debug harness's candidate window, widened from 500 to 4,000 in the first round because the
nearest vacant site to the map's opening centre had become the 1,181st record by distance, goes back
to 500: it is the 16th again, and the widening was making a harness green over a surface that had
gone vestigial.

**The 475 records the city writes backwards were already fixed and are recorded here so nobody
inherits them as open.** `city_qspecies` swaps `COMMON` into the botanical half when `BOTANICAL` is
empty and `COMMON` reads as a binomial; measured on the built seed, 410 of 540 such rows are swapped
and land on the real species row rather than minting one beside it. What is left is smaller and
different: 8 stub species shadow a species already in the corpus over 30 tree rows (0.021%), because
the city wrote the genus in lowercase or gave a cultivar with no epithet. Fixing that means a
canonical-spelling pass over the species name, which is #95's mechanism applied to a column #95
deliberately excluded, and it changes the corpus the species fixtures are sourced against. Its own
task, not a rider on a decision about which rows exist.

**One UI test is intermittently red on both corpora, it is not this change's doing, and its cause is
unresolved.** `MapSearchUITests.testTypingASpeciesNameNarrowsTheMap` types `Platanus` and asserts the
map still draws pins; when it fails it says `narrowing to the commonest species in San Francisco
emptied the map`. What is established:

- It **passed** on the shipped 145,837-row city seed at 21:37 and **failed** on that same file at
  22:01 and 22:04. So it is not decided by the corpus.
- It fails against the **pre-switch DataSF seed** built 2026-07-25 — before any of this work, with no
  `inventory_source` column and no `trees_source` receipt at all. So it is not this change's doing.
  (That run is also the only exercise the backwards-compatible read path has had, and it passed: a
  seed carrying neither the column nor the receipt still opened and drove the app.)
- It is **not a sampling race in the test**, which was the first hypothesis and is refuted: adding a
  thirty-second wait for the pin count to settle above zero still read zero, and the test then failed
  on the wait rather than on the sample. That change was reverted rather than kept, because a wait
  that does not fix it would have shipped a wrong explanation in a comment.

What is left is that the map genuinely draws no pin for the commonest species in San Francisco, some
of the time, on a build where the same search worked twenty minutes earlier. That is worth its own
task and it is not one this round can close honestly.
