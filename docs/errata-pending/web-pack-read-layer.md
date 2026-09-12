# Unnumbered — the orchestrator splices these under the next E numbers at merge (CLAUDE.md,
# Numbering). Written from branch `web/pack-read`, 2026-09-10, milestone W-B (the read layer
# clause). Each was measured on this tree or against the live bucket, not copied from a document.

### `web.yml` triggers on `web/**` only, and its own comment is the premise that made that safe

The workflow's `paths:` allow-list carried this reasoning:

    # Here the only cost of not running is not running a suite that
    # tests one directory: a path outside `web/` cannot affect this app

That was true when it was written — W-A's suite reads `package.json`, `.nvmrc`, `Dockerfile`,
`fly.toml`, and its own sources, all under `web/`. It stopped being true the moment a web test
opened a file outside `web/`, which is the first thing the pack read layer had to do: the three
version spaces live in Swift and Python, and a web constant that copies one of them is only honest
if something compares them.

The failure shape is the one `#170` names in another guard, and it is worth stating in general
form: **a drift guard whose CI trigger does not include the file it guards is green on exactly the
diff that breaks it.** Bump `SeedDatabase.newestKnownSchemaVersion` in Swift and touch no `web/`
path, and the assertion that the web still reads the same generation does not run. It runs later,
on an unrelated web change, and presents as that change's fault.

Fixed in the same round rather than filed: `web.yml`'s two `paths:` lists now name the six files
the web suite reads from outside `web/`, and `web/test/pack-versions.test.ts` asserts that every
such file is on both lists, that each still exists, and — calibrated against a path deliberately
absent — that the membership test can answer no. The rule the comment now states is: **a file a web
test opens is a file that triggers the web suite.**

### `Fixtures/seed/schema.sql` is the generation-17 contract; the file beside it is generation 16

Measured on this tree, 2026-09-10:

    $ sqlite3 Fixtures/seed/cypress-seed.sqlite ".tables" | tr -s ' ' '\n' | grep dim_
    dim_city
    $ grep -c "CREATE TABLE dim_region" Fixtures/seed/schema.sql
    1
    $ sqlite3 Fixtures/seed/cypress-seed.sqlite "PRAGMA user_version;"
    0

`schema.sql` declares `dim_region` and `trees.region_id`; the pinned seed has neither, and
`Tools/publish_cities.py` refuses a seed without `dim_region` outright ("it is a pre-s17 seed and
this publisher writes s17"). So the two files in `Fixtures/seed/` describe different generations,
and the only thing in the directory that says which the `.sqlite` actually is, is
`pinned-seed.json`'s `"schema_version": 16`.

This is not a defect — `SeedDatabase` states the arrangement deliberately ("the app deliberately
bundles an s16 seed while attaching s17 packs beside it") — and it is a trap for a reader who takes
`schema.sql` as a description of the file next to it rather than as the contract the next build
writes. Two consequences a new reader should be handed rather than discover:

* **A pack does not carry its generation in `PRAGMA user_version`.** That counter is the *writable*
  database's, the third version space. A published pack states its generation in
  `seed_meta.publish_schema_version`; the *source* seed states it nowhere at all, because
  `publish_cities.py` writes that key into each pack it cuts and not into the seed it cuts them
  from. A reader that wants the generation of the checked-out seed must introspect its shape or
  read `pinned-seed.json`.
* **Every pack in the live catalog is generation 17** (`manifest-v2.json`, fetched 2026-09-10, all
  seven entries), so the bundled file and every downloadable file are a generation apart at all
  times. A read layer that branched on one generation would be wrong about whichever file it was
  not written for; this is why `SeedSchema` asks the file what it carries.

### `CityManifest.decode` checks `manifest_format` after decoding the cities, not before

`Cypress/Data/Cities/CityManifest.swift`, the method's own doc comment:

    /// Decodes a catalog's bytes — either published object — refusing unknown formats before
    /// looking at anything else.

and the body immediately under it:

    envelope = try JSONDecoder().decode(Envelope.self, from: data)   // cities included
    guard knownFormats.contains(envelope.manifestFormat) else { … }

`Envelope` holds `cities: [City]`, so every entry is decoded — strictly, with `Int` and `String`
requirements — before the format is consulted. A future format whose entry shape changed would
therefore surface as `DecodeError.malformed("…typeMismatch…")` rather than as
`DecodeError.unknownFormat(3)`.

The outcome is a refusal either way, so nothing is mis-installed and this is a message defect
rather than a safety one — but the message is the whole value: "manifest_format 3, but this build
reads format(s) 1, 2" sends a reader to the publisher, and a JSON type error sends them to the
decoder. It is also the one sentence in that file that a reader would reasonably rely on when
adding a format.

Not changed here — `Cypress/` is out of this round's scope and the fix is a one-line reordering in
a file another branch may be holding. The TypeScript port in `web/src/lib/pack/manifest.ts`
deliberately does what the comment says instead of what the code does, states that divergence in
its own header, and pins it with a test that hands a format-99 catalog entries that are not even
objects.

### The live catalog carries an `attribution` key neither reader decodes, which is R37.4 working

Every entry in `manifest-v2.json` (fetched 2026-09-10) has an `attribution` key. `CityManifest.City`
does not decode it and neither does the web port; both are right to ignore it, because R37.4
reserves the right to add keys without a format bump and a strict decoder would have taken the
Cities screen offline on the publish that introduced it.

Recorded because the tolerance is easy to mistake for an oversight, and because it is now a tested
property rather than an accident of nobody having looked: `web/test/pack-live-manifest.test.ts`
asserts both that the captured catalog still carries the key and that the decoded value does not.

### A census that compares a literal against a literal is green on the deletion it exists to catch

`web/test/pack-real-seed.test.ts` gates eight tests on a ~103 MB seed CI does not have. The skip is
the right call and the hazard it creates is the one CLAUDE.md names: a deleted test and a skipped
test look identical in a summary. The guard written for that was

    assert.equal(SEED_DEPENDENT_TESTS.length, 8, …);

— a hand-maintained array compared against a hand-written number, both in the file the guard is
about, neither consulting anything the test runner had registered. Deleting a seed-dependent test
and leaving the array alone was **green in both tiers**: `106 of 106, 0 skipped` with the seed,
`99 of 106, 7 skipped` without. The only trace was the skip count moving by one, which is a note a
human may read and not an assertion. Three places — the PR body, `web/README.md`, and the file's own
header — named this mechanism as the protection against exactly that deletion.

The general form, which is not about this file: **a self-check is only a check if one of its two
sides comes from outside the author's hand.** The fix routes every registration through one wrapper
that records the name in the same expression that calls `node:test`'s `it` and keeps the handle `it`
returns, so the lists are compared against what was registered; registration happens whether the
test then runs or skips, so the census means the same thing in the tier where the deletion would
hide.

**The first attempt at the remaining hole is the part worth keeping.** A helper only helps if
nothing bypasses it, and the bypass — a test registered with `it` directly — was closed by matching
the file's own bytes for that shape, calibrated by planting one and watching it name the offending
text. That calibration proved the pattern recognized the shape that was planted, and nothing more.
A review then tried twelve variants: **nine got past it** — the same call broken across lines, which
is the shape the file already used for its longest name; double quotes; `it.skip`; `{ skip: skip }`;
a second one-line wrapper; gating inside the body — and **three tripped it falsely**, including a
doc comment that merely described the rule. A guard that reddens on its own documentation is a guard
someone deletes. And `web/` carries no linter and no formatter, so nothing keeps a future author on
the one spelling a pattern can see.

**A source-text pattern cannot make an exclusivity claim, and the prose beside it said it had.**
The replacement does not read bytes at all: `node:test`'s `it` is imported under another name and
called in exactly one place, so a registration reaches the runner only through code that records it,
however it is spelled. The census then compares BOTH lists — the gated tests and the ungated ones —
against what was registered, which is what catches a test that gates itself inside its own body
rather than at registration. All nine evasions are now red; all three false trips are gone. What it
still cannot see is stated rather than implied: a call to the aliased import, or a second import of
`node:test`. That is a visible edit to the top of the file, with the same standing as editing the
list to cover a deletion.

### A fixture that re-derives the right answer cannot falsify the query that produced it

Two defects in the same round shipped green on every runner without the seed, and in both the
fixture tier *had* a test for the behavior:

* `treesInBounds` joins `trees_rtree` to `trees` on `t.<rtreeJoinColumn> = r.id` and then re-tests
  `lat`/`lon` on `trees`. Wiring that join to `t.neighborhood_id` passed all seven fixture
  bounding-box tests, because every fixture tree carried `neighborhood_id` 1 and the re-test
  re-derived the right rows from the resulting cross product. Exactly one test went red — the
  seed-gated one, on a machine holding the seed.
* `packIdentity` reads `ORDER BY id LIMIT 1` because the *source* seed carries two `dim_city` rows
  while a pack carries one. Reversing it to `ORDER BY id DESC` reddened one seed-gated test and
  nothing at all without the seed: no fixture carried a second row, so the ordering was
  unobservable. Found by re-auditing the claim after the first was reported, not by being told.

The lesson is narrower than "fixtures are weak" and worth stating in that narrow form: **when a
query filters twice, the second filter can hide the first, and a fixture in which the join column
is indistinguishable from its neighbors will agree with any join at all.** A fixture earns a
coverage claim only when the wrong answer and the right answer are different *sets*. The fixtures
now carry a live tree inside the box with no R\*Tree row, an R\*Tree row with no tree, neighborhood
ids that cross over the tree ids, and an opt-in fused two-city file — and each mutation above is
red with the seed moved aside.

A third mutation found while checking the second was green in **both** tiers: loosening
`cityNameSource`'s `LEFT JOIN id_spaces isp ON isp.id = t.id_space` to `ON 1 = 1` changed no
assertion anywhere, because the single-id-space fixtures had nothing to duplicate against and the
seed's own bounding-box test is limit-bound at 200 rows either way. The fused fixture closes it.

**Two of those repairs were themselves the same defect, which is the reason this entry is long.**

*A limit clips the loop that was written to catch the thing.* `treesInBounds` re-tests `lat`/`lon`
on `trees` after the R\*Tree pre-filter, because the R\*Tree answers in 32-bit-float boxes rounded
outward and therefore over-returns. The seed-gated test loops over every returned row asserting it
is inside the box — the assertion written for exactly that — and **deleting the re-test was green in
both tiers**. Measured with the `sqlite3` CLI, for that test's own box: 8,990 live R\*Tree
candidates, **7** whose real coordinates are outside it, and **0 of those 7** in the first 200 by
uuid — while the line above the loop asserts `LIMIT 200`. The loop was vacuous by construction, not
by luck, and it was guarded by a limit the same test asserts. The fixture tier could not see it
either: every fixture R\*Tree box was a float32-expanded point at the tree's own coordinates, so
pre-filter and re-test agreed by construction. The general form: **a guard downstream of a `LIMIT`
proves nothing about rows the limit does not reach, and a fixture whose two filters cannot disagree
cannot falsify either of them.** The fixtures now carry four trees whose stored box overlaps the
test's box while their coordinates do not — one per re-tested bound, built on the real float32
rounding rather than on a hand-widened box — and the seed tier now compares the whole box against a
count it computes in SQL instead of looping over a clipped page.

*Two of everything at the dimensions and nothing at the facts.* The fused fixture built to make
`packIdentity`'s first-row rule falsifiable gave the file two cities, two regions and two id spaces
— and left **every fixture tree in the first id space**. So a join over those dimensions could be
wrong in a *single-valued* way and no row could tell: `LEFT JOIN dim_city dc ON dc.id = isp.city_id`
loosened to `ON dc.id = 1` was green in both tiers while labeling all **52,788** San Jose trees in
the pinned seed "San Francisco" — an invented civic fact (DECISIONS constraint 15) on the one read
surface `cityName` exists for. The duplicating mutation (`ON 1 = 1`) was caught and the constant one
was not, because the answer the constant returns was the only answer any fixture row had. **A
dimension table with two rows in it proves nothing until a fact row resolves through the second
one.** The fused fixture now carries a tree in the second id space.

The re-audit that followed — mutate each join and predicate, move the seed aside, require red —
turned up three more of the same shape, all now closed: `cityNameSource` gates `dc.display_name` on
`hasDimCity && hasIdSpace` and no fixture had those flags disagree; `softDeletePredicate` applies
`deleted_at IS NULL` only where the column exists and no fixture lacked the column; and
`treesInBounds`'s `ORDER BY t.<identity column>` — which is what makes a `LIMIT`ed read repeatable —
was unfalsifiable because every fixture uuid happened to sort in rowid order. One mutation is
knowingly left green: loosening the R\*Tree pre-filter itself changes no result, only the plan,
and asserting a plan needs a seam the read layer does not have.

### A destructive probe against the pinned seed rewrote the pinned seed, at an unchanged size

`pack-real-seed.test.ts` asserted read-only by issuing `UPDATE` / `DELETE` / `CREATE TABLE` /
`PRAGMA user_version = 99` against `Fixtures/seed/cypress-seed.sqlite` itself. That is safe exactly
while the property under test holds. Red-proving it — removing `readOnly: true` from `openPack` —
made the probes succeed: the pinned seed stayed **108,249,088 bytes** and its sha256 moved from
`c9a440b2…` to `0c2b699a…`. The file is git-ignored and ~103 MB, so nothing in a `git status` would
have shown it, and the next agent to run any suite against that worktree would have been chasing a
seed mismatch it did not cause.

Two things follow. **A destructive probe belongs on a file the suite is allowed to destroy** — the
probe now runs against a `copyFileSync` copy whose hash is checked against the pin before it is
trusted, which costs a fraction of a second and is the same artifact in every sense the test cares
about. And **the pin's size half would not have caught this**: an in-place `PRAGMA` write moves no
bytes. The seed tier now re-hashes the pinned file at the end of the run and names
`Tools/setup_worktree.sh` in the failure, the same assertion `pack-open.test.ts` already made about
a fixture after a session of reads.
