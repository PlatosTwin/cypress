## The species search now survives a typo, and the index that does it is **not** the FTS5 one the ticket asked for (task #227, closing E165's "what is still not fixed")

`ERRATA E165` fixed prefix-matching by matching a substring, and closed by naming what that still
was not: *"This is substring matching, not the trigram matching §6 specifies: a typo misses, and so
does a name the catalog spells differently. That still wants an FTS5 index the seed does not carry,
and it still belongs in `Tools/build_seed.py`."*

Both halves of that sentence were acted on. The second half — build it into the seed, not on device
— is exactly right and is what this change does. **The first half names the wrong index, and the
measurement that says so is the reason this entry exists.**

### FTS5's trigram tokenizer answers substring queries, which is what we already had

The instrument was calibrated before it was trusted, against the shipped 726-species catalog rather
than against a fixture. An FTS5 table `USING fts5(scientific_name, common_name, tokenize='trigram')`
was built over those exact rows and asked E165's own two questions:

| query | today's `LIKE '%q%'` | FTS5 trigram `MATCH` |
|---|---|---|
| `cypress` (control) | 6 | 6 |
| `liquidambar` (control) | 4 | 4 |
| `liquidamber` (**typo**) | 0 | **0** |
| `sweetgum` (**alternate spelling**) | 1 | **1** |

The two columns are identical in every row. FTS5's trigram tokenizer exists to make `LIKE '%q%'`
*fast*; it does not make it *fuzzy*. `MATCH 'liquidamber'` tokenizes the query into a phrase of
consecutive trigrams and requires all of them, so one wrong letter is still a miss. Shipping it
would have added a virtual table, five shadow tables and a schema generation, and fixed neither of
the two cases it was added for — and every test written against it would have passed, because it
answers the control queries correctly.

What BUILD-PLAN §6 means by "a trigram index" is Postgres' `pg_trgm`, and `pg_trgm`'s value is
**similarity**: the fraction of the query's trigrams a name carries. That is a set-overlap question,
not a token-match one, and SQLite will answer it from an ordinary table.

### What shipped

`seed.species_trigrams(trigram, species_id) WITHOUT ROWID` — the table is its own index — built in
`Tools/build_seed.py` beside the data, as E165 required. ~21k rows over 726 species on the shipped
seed, well under a megabyte of a 108 MB file. Stub (`:: 9662`, `RULINGS R47`) and soft-deleted rows
are excluded, because they are the rows the search itself refuses to offer.

The scheme is `pg_trgm`'s: lowercase, every non-`[a-z0-9]` run to a single space, two leading spaces
and one trailing, cut into 3-character windows. The internal space is load-bearing — it lets a
trigram straddle two words, which is how `monteray cypres`, wrong in both halves, still reaches
`Monterey Cypress`.

`SpeciesQueries.search` gained a **fourth band** below E165's three substring bands. It runs only
for the page slots the substring pass did not fill, only for queries of four characters or more, and
its results are deduplicated against what the substring pass already returned. Where the substring
match answers, the answer is what E165 shipped, ranks and all.

### The bar is 0.6, and it is bracketed on both sides by measurement

Counting what the similarity pass *adds* to what the substring pass already returned:

| query | 0.5 | 0.6 | 0.7 |
|---|---|---|---|
| `cypress` | +3 (`Empress Tree`, `Cupressus arizonica`, `Cupressus species`) | nothing | nothing |
| `oak` | nothing | nothing | nothing |
| `quercus` | +1 (`Queen Palm`) | nothing | nothing |
| `liquidamber` | +4 Liquidambars | **+4 Liquidambars** | +4 Liquidambars |
| `sweetgum` | +8 | **+6, incl. all three Sweet Gums** | nothing |

0.5 admits species into queries that already had a complete answer — and those are the queries whose
exact ranking `SpeciesSearchTests` pins. 0.7 stops finding `American Sweet Gum` for `sweetgum`, one
of the two misses E165 named. 0.6 is the only setting that fixes both and disturbs nothing.

This was cross-validated rather than asserted: the red-proof that lowers the bar to 0.5 fails naming
`Cupressus arizonica`, `Cupressus species` and `Empress Tree` — the same three species the Python
sweep predicted, arrived at independently by the Swift path.

### The fallback, and why it is read from the file

Seed schema **15**. `SeedDatabase.newestKnownSchemaVersion` and `Tools/publish_cities.py`'s
`SEED_SCHEMA_VERSION` both move 14 → 15 (R37.1).

The addition is pure: an s14 file has no `species_trigrams`, and `SeedSchema.hasSpeciesTrigrams`
(introspected with `tableExists`, exactly as `hasIdSpace` is) turns the fourth band off, leaving the
substring search s14 shipped with. This is not a courtesy — **R37.3 makes the mixed case ordinary**:
the bundled seed and a downloaded city are two different generations at the same time, so the app
can be reading an s15 bundle and an s14 San Jose in one session. A version integer could not answer
that question per-attachment; the file can.

Red-proved by forcing the flag true, which fails with
`SQLiteError(1/1): no such table: seed.species_trigrams` — the crash the fallback exists to prevent.

### One existing test changed meaning, and it is not the escape leaking

`SpeciesSearchTests.wildcardsInTheQueryAreEscaped` asserted that `cypre%s` finds nothing. It now
finds the five Cypresses, because the similarity pass does not use `LIKE` — it folds `%` to a space
like any other punctuation, so `cypre%s` is an ordinary near-miss of `cypress`.

The invariant that test protects — a `%` must not act as "match any characters" — is intact and
still asserted, but `cypre%s` can no longer distinguish the two outcomes. The probe moved to `c%s`,
three characters, which is below `minimumSimilarityQueryLength` and therefore a statement about the
`LIKE` path alone; an honored `%` there would match most of the catalog. The new behavior is
asserted positively in its own test: every species `cypre%s` returns carries the word `cypress`.

### This entry does not close E165. Merging it does not either.

**The code shipped here is inert until the canonical seed is rebuilt.** That is the honest statement
and it should not be softened, because everything about the change looks finished without it.

The seed is git-ignored. It is not built by CI and not carried by `git worktree add`: every tree gets
the *canonical* file — `Tools/setup_worktree.sh` copies it from the main checkout, CI fetches that
same published artifact through `Tools/fetch_seed.sh` — and that file is s14 with no
`species_trigrams`. So on every machine except the one that wrote this, including CI and **including
the shipped app reading its own bundle**, `SeedSchema.hasSpeciesTrigrams` is false and the search
takes the fallback branch. A reader typing `liquidamber` still finds nothing.

The two halves cannot land in one instant, in either order: an s15 canonical seed would fail the
seed-contract tests on every tree that does not yet carry this schema bump, so the seed cannot be
regenerated before this merges — and the four tests that assert E165's user-visible claims against
the real catalog cannot pass before the seed is regenerated. The code goes first, deliberately, and
the window between is real.

**The four tests are `.enabled(if: seedCarriesTrigrams)` rather than deleted or made lenient.** They
print as skipped, with a reason naming exactly what un-gates them, and they switch themselves on the
moment a seed built by this `build_seed.py` is in place. Nothing has to be remembered and nothing has
to be re-enabled by hand.

### The acceptance check, and the owner's checklist

**E165's user-visible half closes when, and only when, all three of these are true:**

1. **The canonical seed is rebuilt** with this branch's `Tools/build_seed.py` — a real full build,
   not the scaled `--limit` build this branch verified with.
2. **It is published** per the manifest / `build_id` protocol (R60, `ERRATA E219`), and
   `Tools/setup_worktree.sh` and `Tools/fetch_seed.sh` are serving the new file.
3. **The four conditional tests activate and pass on a tree the author did not touch.** That
   activation *is* the proof the fix went live — it is the only signal in the system that
   distinguishes "shipped" from "shipped and inert", and it costs nothing to read: the same suite
   that printed four skips prints four passes.

Until (3) is observed, treat this ticket as landed-but-unproven.

**What this branch verified, and the four gaps it left the publisher.** The branch built the index
into a copy of the shipped seed and ran `build_seed.py` end to end only at `--source datasf
--limit 40000`. That proves the wiring; it does not prove the shipped artifact. On the real rebuild:

- **`seed_meta.species_trigram_rows` was never checked against `COUNT(*)`.** The build writes the
  count it thinks it emitted; nothing has compared it to the rows actually in the table. Assert
  `SELECT value FROM seed_meta WHERE key='species_trigram_rows'` equals
  `SELECT COUNT(*) FROM species_trigrams` on the built file.
- **Byte-identity across rebuilds was claimed but never double-built.** The trigram pairs are sorted
  before insert specifically so two builds of the same data produce the same file (R37.1), and that
  has not been tested. Build twice with the same `SOURCE_DATE_EPOCH` and compare sha256.
- **Check 18c never ran against real stub rows.** The scaled build produced **0** stub rows, so "no
  stub or deleted species is reachable through the index" passed vacuously. The canonical seed
  carries **5** — measured, `SELECT COUNT(*) FROM species WHERE scientific_name LIKE ':: %'`, against
  731 species of which 726 are searchable and 0 are soft-deleted. (The review round put this at 7;
  it is 5, and the soft-delete half of 18c has no case in this seed at all, so that half stays
  vacuous until one appears.) Re-run `Tools/verify_seed.py` on the real artifact and confirm 18c is
  meeting a non-empty case.
- **`publish_cities.py` has never been executed at `SEED_SCHEMA_VERSION = 15`.** The claim that a
  narrowed city file inherits the catalog's index is an argument from the publisher's DELETE list
  (`trees`, `trees_rtree`, `species_assertions`, `neighborhoods`, `inventories`, `id_spaces` — it
  never touches `species`), read but not run. Publish, then query `species_trigrams` in the produced
  city file and run checks 18a–18f against it.

### What republishing does and does not require

**The manifest carries a version per city file, not one global version**, so the bump invalidates
nothing already in the bucket. The app at `newestKnownSchemaVersion = 15` still accepts s14 files
(`CityInstallState` refuses only `published > newestKnown`) and they keep searching by substring at
their existing immutable paths (R37.2). Republishing is therefore not urgent and not a migration —
but it is the only thing that makes the feature exist for a reader. The version string becomes
`s15-r<content_rev>-<build_id>`; because `schema_version` moved this is a new immutable path, so
R60's `build_id` segment is not what is doing the work here.

### What is still not fixed

Similarity is not synonymy. `sweetgum` reaches `American Sweet Gum`, but nothing here would make
`liquid amber tree` reach it, and nothing makes a common name in another language reach anything —
that wants an authored alias list beside the species content, not an index. The `sweetgum` case also
admits `Sweetshade` and `Sweet viburnum` at the same overlap; they rank below every substring match
and are genuinely trigram-similar, so they are noise the bar tolerates rather than a defect.

The similarity pass is deliberately not gated by `MapQueryPlanTests`. Its plan is
`SEARCH species_trigrams USING PRIMARY KEY (trigram=?)` — one covering seek per trigram over a
`WITHOUT ROWID` table — and that is recorded in `SpeciesQueries.similarSQL`'s doc comment but not
asserted, unlike the substring statement beside it. A gate there would be cheap and is worth a
ticket.
