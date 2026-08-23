# Rulings pending — the seed pin and the bundle's scope (owner decisions, 2026-08-22)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename.

Three entries. Two are owner rulings the s17/NYC publish forced, and this round implements both.
The third is a clarification the same decision round settled about RULING D8's dual-format window;
it is **recorded and not implemented**, deliberately.

---

### R??? — The seed version this repository builds against is checked in, and a publish bumps it deliberately

**Date:** 2026-08-22. **Decided by:** owner. **Implemented by:** this round.

#### What went wrong

`Tools/fetch_seed.sh` resolved the seed from the **live** bucket manifest. Every job in
`.github/workflows/testflight.yml` ran it through `.github/actions/prepare`, so the bytes CI
compiled and tested against were whatever `manifest.json` advertised at that minute.

On 2026-08-22 the s17 publish moved `manifest.json` from a 198,625-tree two-city seed to a
1,097,382-tree three-city one. Nothing in the repository changed. Every commit on main — including
commits that had already been green — began failing, because `SeedCorpus` had no entry pinned for
the new corpus. PR #112 was the fix-forward.

The failure mode is worth naming precisely, because it is not "CI broke": **a build product outside
version control silently became an input to every commit's verdict, retroactively.** A green check
on a merged commit stopped being a fact about that commit.

#### Ruling

**Pin, and bump the pin deliberately.** The repository records the seed version it builds against.
A publish round bumps that record in a pull request, and that pull request also carries whatever
constants move with the new artifact.

#### How it is built

- **`Fixtures/seed/pinned-seed.json`** is the record: `path`, `sha256`, `bytes`, plus the scope and
  provenance a reader needs (`schema_version`, `tree_count`, `id_spaces`) and the file's own
  instructions for bumping it. It is checked in and hand-written.
- **`Tools/fetch_seed.sh`** resolves from that file. It downloads the named object, refuses on a
  size or `sha256` mismatch, and the refusal names the three possible causes and the different
  answer each one has — because only one of them is "run it again".
- **The escape hatch is `CYPRESS_SEED_SOURCE=live`**, which restores the old manifest resolution for
  a publish round that wants whatever is currently on the bucket. It announces that its result is
  not reproducible and must not be used to certify a run. CI states `CYPRESS_SEED_SOURCE: pin`
  explicitly in `.github/actions/prepare`, so determinism is a property of that file rather than of
  a default somebody could later change.
- **`Tools/setup_worktree.sh`** refuses to hand an agent a seed that is not the pinned one
  (`CYPRESS_SEED_UNPINNED=1` overrides, for an offline machine or a publish round). An agent
  testing a different artifact from the one CI judges is exactly the state that produced this
  round, and its symptom is a suite going red on counts nobody touched.

#### Consequences

- **A publish can no longer break a commit that already passed.** It also cannot fix one: a seed
  defect found after a publish reaches main through a pull request, like everything else.
- **The pin is a signature.** Bumping it says "I have measured the new artifact and re-pinned the
  constants that move with it", and the `SeedCorpus` entry in the same diff is the evidence.
- **`SeedCorpus.cityWithSanJoseAndNewYork` is now exercised by a publish round rather than by CI.**
  It is the measured record of the published fused seed and stays; the corpus CI runs is
  `cityWithSanJose`, which is also what `Tools/setup_worktree.sh` gives every agent. Local and CI
  read the same bytes again, which they had stopped doing.
- **Pinning is not a substitute for publishing.** The bucket is still the distribution channel; the
  pin only decides which already-published, write-once object this tree builds against.

---

### R??? — The app bundles pre-New-York scope; every other city arrives as a downloaded pack

**Date:** 2026-08-22. **Decided by:** owner. **Implemented by:** this round.

#### What went wrong

`Tools/fetch_seed.sh` wrote **one** download into **both** `Cypress/Resources/` (what the app
bundles) and `Fixtures/seed/` (what the fixtures read). So the app bundled the published *fused*
seed — the publisher's input, which by construction holds every city the pipeline has ingested.

That was survivable while every ingested city was one worth carrying. After the s17 publish it was
not: the next build would have shipped a **706 MB** app carrying all five New York boroughs, up
from 103 MB — and the Cities screen would have offered those same boroughs as downloads it then
refuses, because `CityInstallState` never offers a bundled city. Testers would have waited for
600 MB of data the download flow existed to spare them.

#### Ruling

**The app bundles an SF + San Jose-scope seed (~103 MB). New York comes via the existing city-pack
download flow.**

#### How it is built

The pin from the entry above names **`seed/c9a440b2/cypress-seed.sqlite`** — the last fused seed
built before New York: San Francisco plus central San Jose, 198,625 trees, 108,249,088 bytes, still
at its write-once path (R37.2). No new artifact was produced and nothing was written to the bucket.

Three guards, at three different layers, because each catches something the others cannot:

1. **`Tools/fetch_seed.sh` checks the file's `seed_meta.id_spaces_in_file` against the pin's
   declared `id_spaces`.** With a matching `sha256` this can never disagree about the *download*;
   what it catches is a **pin** whose declared scope does not describe the file it names — a publish
   round bumping `path` and `sha256` to the newest fused seed by reflex and putting every published
   city inside the app. Red-proved against the live `ac7b1ccc` object.
2. **`BundleContractTests.bundledSeedHoldsOnlyTheRuledScope`** asserts the *built app's* bundle
   holds exactly `sf` and `us-ca-sj`, whichever way the file arrived.
3. **`BundleContractTests.bundledSeedStaysWithinTheAppSizeRuling`** asserts it stays under 200 MB —
   a ceiling, not a pin, since a legitimate refresh of the same two cities moves the count by
   megabytes and nothing legitimate multiplies it sevenfold.

Neither test is written in terms of `SeedCorpus`. The corpus **adapts** to whichever seed is
attached: against a 706 MB three-city bundle it selects the three-city entry and the whole suite
passes. A guard that goes green in the presence of the defect it names is this project's dominant
test failure, and that is the specific shape it would have taken here.

#### Why the pre-New-York artifact rather than an s17 rebuild of the same two cities

Considered, and rejected on three grounds, in order:

1. **It exists, and pinning it writes nothing.** An s17 SF+SJ file does not exist; producing one
   means a build, a relay publish, and a new `SeedCorpus` entry of some forty measured literals.
2. **Nothing in the app reads what s17 added.** `dim_region` and `trees.region_id` are the unit
   `Tools/publish_cities.py` *narrows a pack on*. `SeedSchema.hasRegions` is introspected and read
   by no query in `Cypress/`. An s16 bundle beside s17 packs is exactly the configuration R37.3
   describes, and `RegionGenerationTests` is written against it — its own header says the canonical
   seed "is **s16** as this is written and carries no `dim_region` at all".
3. **An s17 rebuild would also carry the 2026-08-22 re-read of both California layers**, which is
   fresher city data inside the app — a change to what testers receive, and not what was ruled.
   Anyone who wants it can have it: both cities publish packs at `content_rev` 2026-08-22, so the
   Cities screen renders them as `bundledOutdated` and offers the refresh.

#### Consequences

- **The bundle and the published fused seed are now different files by design.** The pin may grow a
  second entry the day CI needs a seed the app does not ship; today one file serves both, because
  nearly every test that reads a seed reads it out of the app bundle, and two files would mean the
  suite certifying one artifact while the build shipped another.
- **The published fused seed stays full-scope.** It is the publisher's input, not a shipping
  artifact.
- **A city's arrival no longer changes the app's size.** That is the property worth keeping: the
  bundle is a decision, and the next city is a pack.

---

### R??? — The corrective republish of 2026-08-22 does not start the format-1 retirement clock

**Date:** 2026-08-22. **Decided by:** owner. **Implemented by:** nothing — recorded only.

RULING D8 dual-publishes `manifest.json` (format 1) beside `manifest-v2.json` (format 2) so an
install that predates format 2 keeps a working Cities screen, and retires format 1 at a later
publish.

The republish of 2026-08-22 — which replaced seed `4f6ebaaa` with `ac7b1ccc` to repair the #95
case-normalisation defect — **kept both manifest formats and does not count as the
retirement-triggering publish.** It was a correction to an artifact published hours earlier, not a
distribution event anyone could have adopted in between.

**Format-1 retirement fires at the next real publish.** This entry exists so that the next publish
round does not have to reconstruct whether the corrective one already counted; it did not.
