<!-- Written for #129, the ingest half. Append to docs/ERRATA.md as E176. Do not renumber. -->

### E176 — The second city, and the three things that had to stop being San Francisco's

Task #129. `AppSchema` is untouched; **the schema that changed is the seed's**, and it is the
change E169 reproduced and `docs/investigations/ca-tree-inventories.md` §5 specified. See the
section at the end of this entry for why no `AppSchema` migration was written, since the ticket
reserved v14 for one.

**Berkeley first, because the survey left it open.** E172 recorded `City Trees` (`9t35-jmin`) as
*unverified, not permissive*, and guessed the HTTP 403 was a WAF rejecting a scripted user agent.
Opened in a real browser, as the survey asked:

- `data.cityofberkeley.info/` — **loads**. The portal home page renders, and states 44 datasets.
- `data.cityofberkeley.info/browse?q=tree` — **loads**, and returns **0 results**.
- `data.cityofberkeley.info/Environment/City-Trees/9t35-jmin` — **403**, the same
  `Attack ID 20000009` block page a scripted request gets, from a real Chrome with a real UA.
- The Socrata federated catalogue (`api.us.socrata.com`, a different host and not blocked) lists
  **66 datasets** for the domain. Enumerated in full: **none of them is a tree dataset.**

So the WAF is real and is not the finding. **The finding is that Berkeley's `City Trees` dataset is
not published on Berkeley's portal**, by its own catalogue and by Socrata's. The description the
survey found — trees, planting sites *and* stumps — is third-party copy about a dataset that has
since been withdrawn or unpublished. It is not a better fit than San Jose; it is not a fit at all
until the city republishes it. **E172's Berkeley paragraph should be read as closed, not open.**

**San Jose ingested.** 344,879 records read from
`geo.sanjoseca.gov/.../OPN_OpenDataService/MapServer/510`, CC-BY, cached under `Fixtures/raw/`.
Every one of them was built into an `InventoryRecord` and passed `validate()`: **zero contract
violations over the whole corpus**, which is the thing E172 could assert only over 29 fixture rows.

**Requests, read off the logs rather than recalled:**

| source | requests | what for |
|---|---:|---|
| San Jose Street Tree layer | **178** | 1 layer metadata, 1 count, 173 pages at the layer's own `maxRecordCount` of 2000, 3 deep-page verifications. `Fixtures/raw/sj_street_trees.requests.log` |
| SF Public Works layer | **67** | `Tools/fetch_city_trees.py`, the existing 67 pages. The worktree had no cache; the shipped seed is `--source city` and E169 records that extract as absent from this machine |
| DataSF | **2** | `street_tree_list.csv` and the Analysis Neighborhoods GeoJSON, both fetched once by `build_seed.py` |
| `data.cityofberkeley.info` | **5** | 2 scripted (403), 3 browser page loads and their subresources |
| `api.us.socrata.com` | **3** | the federated catalogue, to enumerate Berkeley's 66 datasets |
| ArcGIS layer metadata (San Jose) | **1** | field list, before the fetcher existed |
| **total** | **256** | |

Nothing was bulk-downloaded twice: `fetch_san_jose_trees.py` writes one file per page and skips
every page already on disk, and `build_seed.py` reads the cache and never touches either service.

---

### Change 1 — `external_ref` stopped being a global constraint on a source-local id

E169's reproduction was `sqlite3.IntegrityError: UNIQUE constraint failed: trees.external_ref`.
It is now:

```sql
id_space     TEXT NOT NULL REFERENCES id_spaces(id),
external_ref TEXT NOT NULL,          -- SF TreeID | SJ FACILITYID
UNIQUE (id_space, external_ref),
```

**TEXT, not INTEGER**, because `source_ref` is defined as the source's own id verbatim as a string
and nothing guarantees the third city's is numeric. The old code coerced it — `int(source_ref) if
source_ref.isdigit()` — which made the column's type a property of the first two sources that
happened to arrive.

**NOT NULL, which is a decision.** SQLite treats NULLs as distinct in a unique index, so a nullable
`external_ref` lets every identity-less row escape the constraint the column exists for. The
contract does permit `source_ref=None` — Oakland publishes nothing but a row number — and such a
source now cannot be a row in this file at all: `emit()` stops the build with a sentence rather than
writing a row nobody can identify. RULINGS R24.

**The collision is real and is in the shipped file.** `twoCitiesShareIdsAndNotIdentities` finds
`external_ref` values that occur in both id spaces and asserts their uuids differ, with a control
that fails if no ref is shared at all — otherwise the assertion would be vacuous, which is the
inert-test failure this project has had once already.

### Change 2 — the inventory vocabulary moved out of the schema and into the file

E169's second reproduction was `CHECK constraint failed: inventory_source IN ('city','datasf')`.
The CHECK's job is "no row may name an inventory the receipt cannot describe", and a hardcoded list
is the wrong instrument for that: every new city edits a shipped schema. It is now

```sql
CREATE TABLE id_spaces  (id TEXT PRIMARY KEY, identity_prefix TEXT NOT NULL, note TEXT NOT NULL);
CREATE TABLE inventories(id TEXT PRIMARY KEY, id_space TEXT NOT NULL REFERENCES id_spaces(id),
                         name TEXT NOT NULL, url TEXT NOT NULL);
...
inventory_source TEXT NOT NULL REFERENCES inventories(id),
CHECK (inventory_source <> ''),
```

written from `INVENTORIES` / `ID_SPACES` for **exactly the inventories that contributed rows**, so
`SELECT * FROM inventories` describes the file rather than the builder. `theFileDeclaresItsOwnVocabulary`
asserts both directions: no row names a space or inventory the file does not declare, and no declared
inventory contributed zero rows.

`id_spaces.identity_prefix` is the load-bearing column and is why an `id_spaces` table exists rather
than the space being folded into `inventories`. `seed_meta.identity_prefix` was one key for the whole
file, which was right while the file was one space and is **wrong for one of two cities the moment
there are two**. The contract test now joins each row to its own space's prefix and re-derives all
198,625 uuids. The old file-wide key is kept, because a seed built before this pass has nothing else
and it is correct for those files, and `id_spaces_in_file` says outright when it has stopped being
the whole answer.

### And the rename

`city` → `sf_city`, `datasf` → `sf_datasf`, beside the new `sj_street_tree`. E169 said `city` is a
poor identifier once there is more than one city; it is a stored value, so the rename is a schema
change and went in the same pass. **`--source city|datasf` is unchanged** — that flag answers "which
of San Francisco's two inventories", and prefixing it would say the city twice.

---

### What ships, and why it is not what was ingested

**344,879 read. 52,788 shipped.** These are two decisions and the receipt carries both
(`sj_rows_read`, `sj_rows_shipped`, `sj_rows_outside_ship_window`) so that a reader can never mistake
a corpus that was never fetched for one that was deliberately not shipped.

San Francisco's 145,837 rows cost 78 MB. San Jose entire, at the same ~535 bytes/row, is another
185 MB — a 265 MB seed inside the .app, past Apple's cellular-download ceiling and absurd for a local
beta. So a subset ships, and **which kind of subset is the whole decision**:

- **Not a random sample.** A 1-in-4 sample is fine in aggregate and a lie at the grain the app
  operates at: somebody standing on a street sees three of the four trees in front of them missing
  and has no way to tell a sampled-out tree from one the city never listed. The map's implicit
  promise is *every tree on this block*.
- **Not trees-only.** 75,886 of San Jose's records are vacant sites and `VACANTSITE` is the entire
  reason this source was chosen. Dropping them throws away the finding.
- **A contiguous window, complete inside it.** Downtown, SoFA, Japantown, Naglee Park, the Alameda,
  north Willow Glen, Roosevelt Park — `lat [37.305, 37.370]`, `lon [-121.930, -121.855]`, stated in
  `SJ_SHIP_WINDOW` in the build rather than measured off the database afterwards. Inside it the
  inventory is whole; outside it there is nothing at all, which is a visible, explainable absence
  rather than an invisible dilution. A beta tester walks blocks, not counties.

**The shipped seed: 198,625 rows, 108 MB** (from 145,837 and 78 MB), 738 species (from 577), 24,200
vacant sites (from 12,413).

### San Jose's own numbers, measured over all 344,879 records

| | this build | E172's survey |
|---|---:|---:|
| kind stated by the vacancy flag | 343,811 | — |
| kind from the species vocabulary | 1,007 | — |
| **kind inferred from an absent species** | **61** (0.018%) | 61 |
| vacant sites naming a real taxon | 617 | 611 |
| planting sites carrying a trunk diameter | 3,736 | 3,666 |
| trunk diameter over the 400 in ceiling | 2 | 2 |

**Two of these do not match the survey and the difference is not rounding.** 617 against 611 and
3,736 against 3,666. Both were measured on 2026-07-31, but by different instruments: the survey asked
the layer for server-side counts, this build ran the adapter over a cached page-by-page extract of
the whole corpus. The likelier explanation is that the layer was edited between the two reads —
`sj_planting_sites_with_a_trunk_diameter` moved by 70 rows, which is a plausible day of edits on a
344,879-row asset register. **It is recorded as a disagreement rather than reconciled**, because
reconciling it would need a third measurement nobody has taken. The 61 that matters — the size of our
own guess — is identical.

---

### The two SF-specific surfaces that did not hold, checked rather than assumed

**1. `LandContext.inferred(from:)` answered confidently and wrongly for every San Jose row.**

It matches DataSF `qLegalStatus` and `qCaretaker` strings. San Jose's `legal_status` is its
`OWNEDBY`. Measured over the 52,788 rows now in the seed:

| `OWNEDBY` | rows | what the rule returned | why it is wrong |
|---|---:|---|---|
| `Private` | 48,036 | `.privateProperty` | San Jose's model is that the **adjacent owner maintains** a tree standing in the public right-of-way. `OWNEDBY` names responsibility, not land. This is `qCaretaker`'s own documented trap, one column to the left — the trap the function's doc comment exists to warn about. |
| `San Jose` | 2,593 | `.otherPublic` | falls through to `caretaker`, which reads `General Fund` — a budget line, not an agency |
| *(blank)* | 2,158 | `.otherPublic` | same fall-through, same budget line |

**All 52,788 rows of a layer called *Street Trees* resolved, and not one to `.street`.** That is worse
than nil: nil draws nothing, and this draws a false sentence on the panel that presents it as the
city's own record.

Fixed by `LandContext.inferred(from:idSpace:)` returning nil for any space that is not `sf`, with
`Tree.idSpace` carrying the row's space. Not by writing a San Jose branch: that would be a design
decision made in passing, and `GROWSPACE` (`Park Strip`, `Well/Pit`, `Median`, `Tree Lawn`) is a
better signal than `OWNEDBY` anyway. RULINGS R24.

**2. The almanac's neighbourhood framing assumes one city, and it still does.**

`seed.neighborhoods` is San Francisco's 41 Analysis Neighborhoods and nothing else. Every San Jose
row therefore carries `neighborhood_id IS NULL` — 52,788 of the seed's 52,790 nulls — and is
**invisible to every neighbourhood-scoped surface in the app**, screen 12 included. Nothing renders
wrongly; a whole city's rows simply never appear in the almanac, the coverage panel, or the
neighbourhood species mix.

**This is reported and NOT fixed.** A San Jose neighbourhood layer is a source nobody has surveyed, a
`neighborhoods` table that mixes two cities' polygons needs a city column and a rule for what "your
neighbourhood" means when you are in neither, and both are product decisions this entry has no
standing to make. It is a known hole in the shipped build, not a surprise waiting for somebody.

**Two more surfaces were checked and hold.** The species legend and map species colouring key off
`species.id` and a palette generated per species, and 577 → 738 species changes only how many colours
are minted; `MapContentBudgetTests`' floor is a `>` bound and central San Jose is not denser than
central San Francisco. `SeedCorpus.densestScreenfulFloor` is unchanged for that reason.

---

### Why there is no `AppSchema` v14, although v14 was reserved for this ticket

**`trees` is not in `AppSchema`.** The app's writable database (`main.*`, `PRAGMA user_version`,
`AppSchema.migrations`) holds only what the device produces — contributions, the outbox, favourites,
review flags. The city inventory lives in the **bundled read-only seed**, which carries no
`user_version`, has no migration list, and is replaced wholesale by a rebuild. Both schema changes
E169 reproduced are in `Tools/build_seed.py`'s `CREATE TABLE trees`, and `SeedSchema.introspect`
already exists precisely so the read layer asks the file which shape it has rather than assuming.

So the correct expression of "the schema is at v13, yours is v14" for this work was a **seed** schema
change plus a `SeedSchema` capability flag (`hasIdSpace`), and no `main.*` migration was needed or
written. **`AppSchema.currentVersion` is still 13 and v14 is still free.** Nothing in this branch
takes it, so the next agent who genuinely needs a device migration can have it — which matters more
than usual here, because a version cannot be reserved by skipping: a device that migrates to v15 will
never run a v14 added afterwards.
