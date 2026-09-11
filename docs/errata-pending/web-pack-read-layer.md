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
sides comes from outside the author's hand.** The fix routes every seed-gated registration through
one helper that records the name in the same expression that calls `node:test`'s `it` and keeps the
handle `it` returns, so the list is compared against what was registered; registration happens
whether the test then runs or skips, so the census means the same thing in the tier where the
deletion would hide. The helper's exclusivity is then the only remaining hole, and the census closes
it by matching this file's own bytes for a direct skip-gated registration and requiring none —
calibrated by planting one and watching it name the offending text.

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
