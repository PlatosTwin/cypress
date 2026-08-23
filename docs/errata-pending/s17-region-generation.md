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

**Coverage stays keyed on the id space while pack identity moved to the region** — a deliberate
divergence taken in the same round, with the one state a per-city key cannot describe (several
regions in one space shipping less than all of the city) refused by the publisher rather than
guessed. The reasoning is in `coverage_for`'s own docstring and in this round's pending rulings.

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
(`us-ny-nyc`), so a Queens tree whose predecessor stood in Brooklyn **passed** the id-space check
and the per-region delete then severed the link.

**The severity, corrected.** An earlier draft of this entry said the severing was *silent*. It is
not, and the correction is owed to adversarial review (finding F3), which measured it rather than
reasoning about it. A severed link leaves `site_lineage` pointing at a deleted row, and
`build_city_file`'s own `PRAGMA foreign_key_check` catches exactly that and refuses the publish:

    FAIL: us-ny-nyc-queens: foreign_key_check reported 1 violations,
          first: ('trees', 4, 'trees', 0)

exit 1, nothing published. **So no corrupt pack could ever have shipped, and no provenance was
ever at risk.** What the wrong granularity cost is a *diagnosis*: the operator gets a rowid pair to
resolve by hand instead of a sentence naming the cause. Post-fix, the same seed fails before any
delete runs, with `1 site_lineage links cross regions; splitting would sever provenance -- stop and
report`.

Recorded as a real defect at its real severity: a guard checking the wrong granularity, caught
downstream by a coarser net. The repair is worth making — a check that fires before the delete, and
that would still be needed if the FK ever stopped covering this — but it is not the data-loss
finding the first draft described.

Red-proved: `Tools/test_publish_cities.py` builds a fixture with a Queens tree whose `site_lineage`
points into the Bronx and asserts the publisher exits non-zero **with the "cross regions" message**,
which is the part that distinguishes the fix from the pre-existing net.

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

---

### E??? — `deadNotice` told a reader a community reviewer confirmed a city's own record

**Found by adversarial review of the s17 PR (finding F7), recorded there as debt, and REPAIRED as a
fast-follow (build 50) once NYC s17 published and the 10,635 rows became real.** The entry below is
the debt as it was written; the resolution is at the foot of it.

`TreeProfilePresentation.deadNotice` fires on the status alone:

```swift
guard tree.status == .deadReported else { return nil }
return Self.deadNoticeText   // "Reported dead, and a community reviewer confirmed it. …"
```

It asks *what* the status is and never *who said so*. Every `dead_reported` row that has ever
existed came from the community path, so the sentence has been true for every row ever shipped.

**s17 makes it false.** `build_seed.status_for_record` now maps a source-stated
`CONDITION_DEAD` onto `dead_reported`, and NYC Parks publishes `TPCondition = Dead` on 10,635
rows. The moment those ship, a reader opening one of them is told that *a community reviewer
confirmed it* about a record no community member has ever seen. Nobody reported it and no reviewer
agreed; the City wrote it down.

That is precisely the test RULING D17 applies to *Cared for by Queens* — a sentence the app would
be stating as fact on the strength of a column that does not mean what the sentence says — and it
fails it the same way.

**Why this round records it instead of fixing it.**

- **Nothing is wrong on `main` today, and nothing s17 publishes changes that.** No shipped source
  produces `dead_reported`: San Francisco and San Jose publish no condition field, so every row
  stays `condition = None` and the copy stays true. Verified by rebuild — 198,625 uuids joined
  against the shipped seed, **0 status changes**. The defect is armed by s17 and fired by the NYC
  ingest, which is a later round.
- **The repair needs copy, and copy is not this author's to invent.** `deadNoticeText`'s own
  doc-comment says **NOT SPECIFIED — SCREENS.md draws no confirmed-dead profile**. A
  provenance-aware variant needs a second sentence for the city-record case, and DECISIONS
  constraint 21 makes an unmocked state a stop-and-ask. Writing it here would be inventing civic
  copy to close a ticket.

**What the repair looks like, so the next round does not re-derive it.** The row already knows its
own provenance — `trees.inventory_source` and `verification_state` (`city_record` vs the community
values) are both present and both already read by this layer. The notice needs to branch on that
rather than on the status alone, and the city-record branch needs its own approved sentence. The
existing sentence stays correct for the community path and should not be touched.

**Owed before the first NYC publish**, alongside RULING D12's notify-the-City obligation and D20's
species gate — it is in the same family: a claim the app makes on a reader's behalf that the data
does not support.

---

#### RESOLVED — build 50, branch `fix/f7-dead-caption`

The owner ruled the repair a fast-follow once the five borough packs went live carrying the 10,635
`dead_reported` rows. Three things in the debt entry above are worth correcting against the code, and
they are corrected here rather than silently: the repair is not the one the entry predicted.

**1. `verification_state` is the wrong discriminator, and so is `source`.** The entry named
`trees.inventory_source` and `verification_state` (`city_record` vs the community values) as the seam.
Neither answers the question. `dead_reported` reaches a **`city_import`** row by *both* paths — the
inventory can publish the status, and a reviewer on this device can confirm a reported death on a row
that shipped `alive`, which is the arm E170 built and `ModerationTests` has exercised since. Both rows
are `source == .cityImport`, and both are `verification_state == .cityRecord` — every one of the
198,625 rows in the shipped seed carries that pair, measured off the file, and confirming a death
writes `tree_status_overrides` and touches neither column. A repair keyed
on either would have produced the *mirror* falsehood — the city credited with a death the community
found — on a surface that had been correct since E170.

The actual seam is one line up from all of that. `LocalAPI.treeProfile` reads the record's status and
then overwrites it from `tree_status_overrides`, and after that overwrite the two origins are
indistinguishable: one `TreeStatus` field, and the row it came from gone. So the answer is carried
rather than re-derived — `TreeStatusProvenance` (`.record` / `.communityReview`) on `TreeProfile`, set
beside the overwrite it describes, defaulting to `.record` everywhere because that arm credits nobody
and a payload that does not know must not read as evidence that a reviewer confirmed something.

**2. The city sentence names the inventory, not the city, and reads it off the row.** It goes through
`InventorySource.name` — the value R28 already made the subtitle and the provenance line share — so
`NYC Parks Forestry Tree Points` appears in no source file, and a second publisher shipping a `Dead`
condition needs no code here. A seed whose receipt cannot name an inventory falls back to
`CityRecordCopy.unnamedCityInventory`, the same fallback and the same argument as the subtitle's.

**3. There are three arms, not two.** The third is for a record whose status came neither from a
review here nor from an inventory: it states the death and attributes it to nobody. Unreachable in
shipping code today — `addTree` writes `alive`, and only an override moves a status afterwards — and
written anyway, because an arm that would have to *invent* an attributor is exactly what F7 was.

**The copy, before and after.** All of it is still `NOT SPECIFIED`; SCREENS.md draws no dead profile
in any of the three states, and the wording went to the owner with the PR.

| | lead-in | sentence |
|---|---|---|
| **before**, every dead row | `Confirmed dead:` | Reported dead, and a community reviewer confirmed it. It is still standing, so anything you see here is still worth reporting. |
| **after** · a reviewer here confirmed it | `Confirmed dead:` | *unchanged — it was never wrong about the rows it was written for* |
| **after** · the row's own inventory says so | `Listed dead:` | Recorded dead in the {inventory}. It is still standing, so anything you see here is still worth reporting. |
| **after** · nobody can be credited | `Reported dead:` | Reported dead. It is still standing, so anything you see here is still worth reporting. |

*"Recorded", not "confirmed", in the city arm.* The city wrote it down in a file, on a day. Nobody
went and looked on the reader's behalf, and DECISIONS §3.3 still holds in both directions: the
sentence says a file already records the death and says nothing about anybody acting on it.

**The lead-in travels with the sentence.** `deadNotice` returns a `DeadNotice` value carrying both,
and the view draws both off it. `Confirmed dead:` over a sentence about a city's file is the same
falsehood F7 was, reassembled one layer up, and the pair is now the thing that cannot come apart.

Guarded by `CypressTests/DeadNoticeProvenanceTests` (nine tests, provenance selection rather than
phrasing, since the phrasing may still move) and by `ModerationTests.confirmedDeadIsNotAMemorial`,
which is the end-to-end half: a real `confirmReview` — the only path in shipping code that writes
`tree_status_overrides` — has to arrive at the presentation as `.communityReview`. Three red-proofs,
each watched failing for its own reason and restored by file copy: the pre-fix single sentence, the
plumbing dropped in `LocalAPI`, and the city arm hardcoding `NYC Parks Forestry Tree Points`.

`StatusBadge.Kind.deadReported`'s doc-comment went false on the same day and is corrected with it: it
read *"a tree a lead has confirmed dead"*. The badge word is `Dead` either way, so the badge needed no
arm — only the sentence under it did.

**A second, older defect surfaced by the same sentence: `InventorySource.name` could be empty.**
Adversarial review of the repair (finding F2) found that `init?(seedMeta:)` guarded the *id* for
emptiness and not the *name*, where its per-inventory sibling `init?(id:seedMeta:)` has always guarded
both. A receipt carrying `trees_source_name` present-and-empty therefore produced a value that was not
nil and could not be said, so every `?? unnamedCityInventory` fallback in the app was bypassed by a
value that needed it most.

This predates the repair by a long way — it is the shape of the four-surfaces-say-SF defect (E181),
one level down — but the repair is what made it a broken *sentence* rather than a missing subtitle
element: `Recorded dead in the .` The city-record provenance line had the same hole in the same
receipt, rendering `From the , 26 July 2026.`

**One guard in the initializer closes every surface**, and the sibling the reviewer named
(`CityRecordCopy.recordSource`) is covered by it rather than needing its own fix: both shipping
construction paths run through this initializer — `init?(id:seedMeta:)` falls through to it whenever
the per-inventory name is absent or empty, and `CypressStore` builds inventories through no other
route. The memberwise `init(id:name:url:snapshotDate:)` is deliberately left unguarded and has no
shipping caller; it is not a decoding boundary, and a caller passing `""` there is stating one.

Nil rather than a fallback to `id`, because `InventorySource.id` is documented *"Not shown to
anyone"*, and every caller already has a correct path for an inventory it cannot name — the same
discipline `snapshotDate` keeps for an absent date. An *absent* name key still yields `id` and is
unaffected, so this can only fire on a receipt that wrote the key empty.
