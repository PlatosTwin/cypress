<!-- Written for #137. Append to docs/ERRATA.md as E181. Do not renumber. -->

### E181 — a San Jose tree's profile said San Francisco four times, thirty points above a line that said San Jose

E176 walked the app with two cities in the seed, found this, wrote it down and declined to fix it,
because generalizing a city's name across five surfaces is a design decision rather than an ingest
change. This is the fix. The decisions are RULINGS **R28**; what follows is what was measured, what
was changed, and what was found and deliberately left alone.

---

#### The defect, and why it was worse than either half being wrong

On a San Jose tree the profile read:

| surface | said | the row says |
|---|---|---|
| subtitle provenance element | `SF city inventory` | `inventory_source = 'sj_street_tree'` |
| `City record` stat card | `SF #167879` | a `FACILITYID` in id space `us-ca-sj` |
| §9b section header | `WHAT SAN FRANCISCO HAS ON FILE` | San Jose has it on file |
| the sentence under the grid | `The city's street tree inventory records pruning by block, not by tree…` | a statement about DataSF's column list |

…while the last line **of that same section** read *"From the City of San Jose Street Tree
inventory, July 31, 2026."* and was right, because it resolves per row through
`InventorySource(id:seedMeta:)`.

One screen, two answers. A reader who notices cannot tell which half to believe, and the wrong half
is in the larger type. Neither half being wrong alone would have been as bad: a screen that is
uniformly wrong is a bug, and a screen that contradicts itself is a screen nobody can use as
evidence for anything.

**All four were literals. None of them needed to be.** `Tree.idSpace` has carried the id space since
R24, `trees.inventory_source` names the contributing inventory per row, and
`LocalAPI.provenance(of:in:)` already resolved it — that is how the correct line got to be correct.
The machinery was in place and four call sites were not using it.

**One doc comment is probably why.** `TreeProfile.inventorySource` was documented as *"A property of
the seed rather than of the tree, so every profile in one build carries the same value"*. That was
true when it was written and stopped being true at #91, when the seed began drawing living trees
from SF Public Works' layer and vacant sites from the DataSF export. A value that is the same for
every row in a build is not worth asking a row for, and a reader who believed that sentence would
not have thought to. It is corrected in place rather than deleted, with a pointer here.

#### What now derives from what

- **Subtitle** — `InventorySource.name`, which is byte for byte the string the provenance line at the
  bottom uses. Not similar to it; the same value. The two halves of the screen cannot disagree again.
  Falls back to a city-neutral `city inventory` when the seed cannot resolve an inventory, never to a
  city.
- **Record card** — `#<external_ref>`. The publisher's own number, which is the citable one; the
  `SF ` prefix is gone. Not `us-ca-sj:167879` — that is R18's identity key and Cypress's namespacing,
  not a number San Jose's asset system would recognize.
- **Header** — `What the city has on file`. The one of the four that does **not** derive, and R28 §3
  argues the reason: it is a letter-spaced uppercase micro-label and the row's honest value is a
  38-character publisher name. The section's own last line names the inventory in full, with a date.
- **Pruning sentence** — `CityRecordPresentation.pruningNote(idSpace:)`, nil outside `sf`, matching
  `LandContext.inferred(from:idSpace:)`'s guard exactly, including the treatment of a nil id space as
  San Francisco's.

#### Screens 14 and 19 carried the same two literals

`SitePresentation` and `MemorialPresentation` each had their own copy of `SF city inventory` and
`SF #<ref>`. The vacant-site screen is not hypothetical — **11,787 of the shipped seed's 24,200
vacant planting sites are San Jose's** — and its provenance line was already correct, so it had the
identical contradiction on the identical line. All three screens now call one derivation.

---

### What was found beside it and NOT fixed

#### The §9b panel shows San Jose's columns under San Francisco's labels — E180's seam, one layer up

This is E180 (`legal_status` reaching `city` rows from the other inventory) seen from the UI. Under
D16 a merged row routinely carries fields from several publishers, and the labels are a per-publisher
fact that `CityRecord` currently has no room for. Measured over the 52,788 San Jose rows in the
shipped seed:

| card label | San Jose column behind it | rows drawing it | what it actually means |
|---|---|---|---|
| `City lists this as` | `GROWSPACE` | 51,689 | where the tree *stands* — `Park Strip` 15,907, `Well/Pit` 3,758, `Median` 1,868 — not what the record is listed as. **`N/A` on 25,032 of them**, printed as a fact. |
| `Legal status` | `OWNEDBY` | 50,630 | who is responsible for the tree, not its standing in law. `Private` on 48,036, which R24 already established is San Jose's *adjacent owner maintains* model, not a property line. |
| `Cared for by` | `MAINTBY` | 52,788 | `General Fund` on 49,343 — a budget line, not a caretaker. |

This entry did not fix it, and the reason is R24's rather than a budget: choosing what San Jose's
`GROWSPACE` should be labeled, and whether these six seed columns should be holding another
publisher's differently-meaning columns at all, is the deeper question `SanJoseStreetTreeAdapter.CITY_RECORD_COLUMNS`
was already flagged for. **It is not made worse here** — nothing in this change routes a new column
into a label — and the four surfaces that *were* fixed no longer claim the wrong city over it.

#### Two things were checked and are latent rather than live

- **`CityRecordCopy.agencyGlossary` is San Francisco's vocabulary and is not id-space qualified.**
  `DPW` → `SF Public Works`, `FUF` → `Friends of the Urban Forest`, `PUC`, `MTA`, `SFUSD`, `Rec/Park`.
  Measured against the seed: San Jose's `MAINTBY` holds only `General Fund` (49,343),
  `Medians and Backups` (3,318) and `Special Districts` (127), so **not one entry fires on a San Jose
  row today**. It is exactly R24's shape and it is one differently-spelled municipal code away from
  putting `SF Public Works` on a San Jose tree. Left alone deliberately: gating it is a change to what
  145,837 San Francisco rows render, on a screen this entry was not chartered to redesign.
- **`plotSizeText` refuses San Jose's `SPACEWIDTH` outright, and is accidentally right to.** The
  column is bare integers (`3`, `4`, `8+`), which `isPositiveNumber` and the notation triage already
  refuse as "a number with no dimension and no unit". So no San Jose row draws a `Plot size` card and
  none draws a wrong one. Worth recording because it is luck rather than design — the rule was
  written for DataSF's three notations and happens to decline San Jose's fourth.

#### Not taken

- **No schema migration.** `AppSchema` stays at v13. Nothing here needed one: every value the four
  surfaces now read was already in the seed and already on `Tree` and `TreeProfile`.
- **No pruning sentence for San Jose.** R28 §4 has the argument. The short version is that the true
  San Jose sentence is a *different* claim from the San Francisco one, and Cypress has not read that
  city's published field metadata to make it.
- **`mocks/cypress-mocks.html` is untouched.** It is the drawing; SCREENS.md is where a departure
  from a drawing gets recorded.
- **E175's San Jose neighborhood hole is untouched** and unrelated: every San Jose row still carries
  `neighborhood_id IS NULL`, so screen 12 still cannot see the city. Nothing here changes that in
  either direction.

---

### The four new tests were broken deliberately, and each went red on its own

A green suite is worth nothing until it has been shown to bite. Each of the four surfaces was
reverted to its pre-#137 state, one at a time, and the output is pasted verbatim.

**M1 — the subtitle goes back to the literal.** `recordSource` returns `"SF city inventory"` for
every city row again. Two of the four tests go red, and the third assertion in the sweep names the
offending string:

```
✘ Test "no surface on a profile names a city other than the row's own inventory"
  recorded an issue at CityRecordSectionTests.swift:627:13: Expectation failed:
    (presentation.provenance → "SF city inventory") == (source.name → "City of San Jose Street Tree inventory")
✘ ... CityRecordSectionTests.swift:641:17: Expectation failed: (offenders → ["SF city inventory"]).isEmpty → false
✘ Test "a vacant site's subtitle names the inventory that listed it, in whichever city"
  recorded an issue at CityRecordSectionTests.swift:742:17: Expectation failed:
    !((subject.subtitle → "Vacant planting site · SF city inventory").contains(marker → "SF") → true)
✘ Test run with 50 tests in 2 suites failed after 0.574 seconds with 9 issues.
```

Note the *first* of those two San Jose lines: the sweep fails on the SF row as well, because
`SF city inventory` is not `SF Public Works street tree inventory` either. The old literal was not
even right about San Francisco — it named a city where the screen's other half named an inventory,
and SF publishes two.

**M2 — the record number keeps its city.** `recordNumber` returns `"SF #\(ref)"`:

```
✘ Test "the city record card is the publisher's own number and nothing else"
  recorded an issue at CityRecordSectionTests.swift:665:13: Expectation failed:
    (presentation.cityRecordText → "SF #100002") == ("#\(ref)" → "#100002")
✘ Test "no surface on a profile names a city other than the row's own inventory"
  recorded an issue at CityRecordSectionTests.swift:641:17: Expectation failed:
    (offenders → ["SF #100002"]).isEmpty → false
✘ Test run with 27 tests in 1 suite failed after 0.353 seconds with 3 issues.
```

**M3 — the header goes back to naming a city.**

```
✘ Test "no surface on a profile names a city other than the row's own inventory"
  recorded an issue at CityRecordSectionTests.swift:641:17: Expectation failed:
    (offenders → ["What San Francisco has on file"]).isEmpty → false
✘ Test run with 27 tests in 1 suite failed after 0.338 seconds with 1 issue.
```

**M4 — the pruning sentence stops declining.** The `idSpace` guard is deleted, which is exactly the
pre-R28 state and the one that put a claim about DataSF's column list on 52,788 San Jose trees. The
failure prints both notes, so the contradiction this whole entry is about is visible in one line —
San Francisco's sentence and San Jose's provenance, side by side:

```
✘ Test "San Jose gets no pruning sentence, and is not handed a substitute for one"
  recorded an issue at CityRecordSectionTests.swift:697:17: Expectation failed: !(saysPruning → <not evaluated>)
↳ a us-ca-sj row was handed San Francisco's pruning claim: ["The city's street tree inventory
  records pruning by block, not by tree, so it says nothing about when this tree was last pruned.",
  "From the City of San Jose Street Tree inventory, July 31, 2026."]
✘ Test run with 27 tests in 1 suite failed after 0.329 seconds with 1 issue.
```

Restored, and the whole suite green: **`Test run with 937 tests in 87 suites passed after 101.780
seconds`** on the shipped two-city seed. Main was 933 in 87 suites; the four added here are the
difference.

---

### What the running app showed

APP_OUTPUT_PLACEHOLDER
