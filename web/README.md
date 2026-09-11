# `web/` — the public read surface

**Astro + TypeScript, SSR on the Node adapter, self-hosted on Fly.** Opened 2026-09-10 by the
owner; the authority is `docs/design-proposals/2026-09-10-web-version.md` and the queue underneath
it is `docs/ROADMAP.md` section **W**. Milestone **W-A** built the foundation: it builds, it is
tested, and it renders one placeholder page. Part of **W-B** has since landed: the domain rules
are re-derived in `src/lib/` — see *The rules, re-derived* below.

**What v1 is** (ruling W-1): a public read surface. No login, no writes. The tree page, plus the
`Explore` / `Species` / `Neighborhoods` / `Data & export` nav the spec draws.

**Why it is here and not in its own repository** (ruling W-2): the CI carve-out that keeps a web
commit from running the iOS suite and minting a TestFlight build has to live beside the directory
it classifies, and did, in the pull request that created both.

**What it is not.** It is not the iOS app in TypeScript. `Core/`'s rules are re-derived (W-B),
`Data/`'s schema is reused verbatim, and `Features/` is not ported at all — v1 is read-only, and
50,224 lines of it are about writing.

## What exists, exactly

As of W-A. Everything below was read from this directory, not remembered.

| | |
|---|---|
| Framework | Astro `7.3.2`, `@astrojs/node` `11.1.5`, `output: 'server'`, `mode: 'standalone'` |
| Language | TypeScript `5.9.3`, `astro/tsconfigs/strictest`, `erasableSyntaxOnly` |
| Runtime | Node `24.13.1`, pinned in `package.json` `engines`, `.nvmrc` and both `Dockerfile` stages |
| Test runner | `node --test`, TAP reporter, no test framework dependency |
| React | none, deliberately (W-8) |
| Fly app | `cypress-web` — **declared in `fly.toml`, not created.** W-E deploys |
| Volume | none yet; W-E creates the one the city packs are read from |
| Pages | one placeholder at `/`. W1 is W-C |
| Rules | `src/lib/{vitality,quantity,geometry,growthCharting,idSpaces}.ts` — W-B's first third |

**Two runtime dependencies and three development ones**, and no test framework at all, which is
the same discipline `server/` holds with two. `node:sqlite` is why the runtime is pinned this
tightly: it is in the standard library, which is what will make the Docker image simple when W-B
opens a pack, and it is documented as experimental, which is what makes a floating Node tag a bad
idea. Nothing here imports it yet.

## Running it

```sh
npm install          # once
npm run dev          # http://localhost:4321
npx astro dev stop   # and it needs stopping — see below
npm run build        # dist/server/entry.mjs
npm start            # serve the build
```

**`astro dev` in 7.x detaches.** It backgrounds itself, prints its pid, and survives the shell
that started it; `Ctrl-C` returns your prompt without stopping the server. `npx astro dev status`
says whether one is running and `npx astro dev stop` ends it. An agent that starts one and walks
away leaves a process holding port 4321 for the next person.

## Testing it

**Not `npm test` on its own, when the answer matters.** Use the harness:

```sh
Tools/run_web_tests.sh /tmp/web.log            # install, typecheck, test, build
Tools/verify_web_test_log.sh /tmp/web.log      # the verdict
```

The runner writes a `CYPRESS-WEB-RUN:` provenance header — commit, Node version, worktree,
package-lock hash, phases — runs every phase whether or not an earlier one went red, and writes a
terminus line when it is done. The verifier reads that log and **never an exit code**. It has
three verdicts:

| Exit | Token | Means |
|---|---|---|
| 0 | `VERIFY-WEB-OK` | a real pass line, from a complete run, with tests that ran |
| 1 | `VERIFY-WEB-FAIL` | a red: something in the log reports failure |
| 2 | `VERIFY-WEB-VACUOUS` | the log cannot support a claim either way — no terminus, or zero tests |

The third one is not defensive programming. `node --test` handed a glob that matches no file
exits **0** and prints a complete, entirely green TAP summary reporting zero tests:

```
$ node --test --test-reporter=tap "test/**/*.nosuchthing.ts" ; echo $?
TAP version 13
1..0
# tests 0
# pass 0
# fail 0
0
```

That is `Executed 0 tests / All tests passed` in another language, and it is the false green
`CLAUDE.md` names first. A renamed directory produces it. So does a typo.

For a fast local loop, name the phases you want — `Tools/run_web_tests.sh /tmp/web.log typecheck
test` — and the log records that the install was skipped, which the verifier repeats in its
verdict. A warm `node_modules` certifies the code and says nothing about whether the lockfile
installs.

## CI

`.github/workflows/web.yml`, on `ubuntu-latest`, triggered by `web/**`, the two harness scripts,
and itself. It runs the same `Tools/run_web_tests.sh` an agent runs, keeps the log as an
artifact for thirty days, and builds the Docker image without pushing it.

**It is one half of a pair.** `.github/workflows/testflight.yml` classifies a `web/` change as
`tests=false ships=false` — no iOS suite, no TestFlight build — and the notice it prints says so
on the grounds that the web is tested *here*. Delete or rename this workflow and that notice
becomes a false statement on a green check.

`web/` reaches `testflight.yml`'s predicates through a variable of its own, `WEB_ONLY`, rather
than through `DOC_ONLY`. It is not prose; it is tested somewhere else. The reasoning is written
out at the assignment.

## Deploying it

**Not yet.** `fly.toml` describes the deployment and no `cypress-web` app exists. W-E creates the
app and the volume the published city packs are mounted from.

**The site is `cypressgrove.app`**, ruled by the owner on 2026-09-10, decision 2 of the web
round's owner decisions. That ruling is unnumbered while this branch is open and lives under
`docs/rulings-pending/`; the orchestrator splices it into **`docs/RULINGS.md`** under its real
number at merge, so look for it there by date — this paragraph deliberately does not name the
pending file, because a citation by pending filename dangles the moment the splice happens and
`PendingCitationGuard` scans Swift only, so nothing here would have caught it.
Not `cypress.app`: that domain is **registered to a
third party**, expiring 2026-11-03, parked with no A record — which means every share card the iOS
app has ever produced points at a hostname somebody else controls. It is dead today and is not
guaranteed to stay dead. Moving `ShareCopy.publicURLPrefix` is shipped iOS copy and therefore a
Swift round with its own review, not a web change; until it moves, no link in the wild resolves
and the site answers on its `.fly.dev` hostname.

The Fly app keeps the name `cypress-web` — a machine, not a brand. It is deliberately not renamed
to match the domain, because the domain can move and a Fly app name cannot.

`fly.toml` deliberately declares **no `[mounts]`**. A mount naming a volume that does not exist
fails a deploy halfway through creating the app.

## The rules, re-derived (W-B, first of three)

`src/lib/` holds five rules that already exist elsewhere in this repository, re-derived in
TypeScript and checked against the originals' own test cases:

| Module | The declaration it is derived from |
|---|---|
| `vitality.ts` | `Cypress/Core/Rubric/Vitality.swift` (+ `LeafRetention` in `Core/Models/Species.swift`) |
| `quantity.ts` | `Cypress/Core/Units/Quantity.swift`, `MeasurementKind.plausibleSIRange` in `Core/Models/TreeMeasurement.swift` |
| `geometry.ts` | `Cypress/Core/Models/Geometry.swift` |
| `growthCharting.ts` | `FieldCaptured.isEligibleForGrowthCharting` and `GPSAccuracy` in `Cypress/Core/Models/CoreEntity.swift`; `isChartable` / `splitBySeries` in `Core/Models/TreeMeasurement.swift` |
| `idSpaces.ts` | `Tools/inventory_contract.py` — **not Swift.** `Tree.idSpace` is an opaque `String?` and `SeedCities` reads the pack's own `id_spaces` table; the registry exists once, in Python |

**A second copy of a rule is how the vitality rubric forked for two weeks** (ticket #261:
`Vitality.anchor`, `PRODUCT.md` §3 and `SCREENS.md` 05 §3 disagreed from the day both documents
were distilled, and nothing read the two tables). So none of these is checked against a
transcription. `web/test/support/sources.ts` parses the Swift, the Python and the two distilled
markdown tables **at run time**, every parser is calibrated in `test/sources.test.ts` against a
specimen whose answer was known first, and the paths it reads are listed in `web.yml`'s `paths:`
so the checks fire on the change they guard — asserted, in `test/sources.test.ts`, in both filters.

**Where the numbers came from, and what keeps them current.**
`test/support/swift-reference.json` is what the real `Quantity.swift`, `Geometry.swift` and
`CoreEntity.swift` printed when compiled unmodified; `test/support/swift-reference/main.swift` is
the program that printed it and carries the command to regenerate it.

It is a **recording**, and a recording does not move when its subject does. So the guard is in two
halves and the honest description of it is *TypeScript against a recorded snapshot, plus a tripwire
on the Swift source that snapshot came from*: `test/swiftDrift.test.ts` fingerprints the eleven
Swift declarations the ports re-implement and goes red on any edit to them, cosmetic or not, with a
message telling the reader to re-record the reference and re-verify parity before pasting a new
fingerprint. Without that second half, two one-character edits to the real Swift — `111_320.0` to
`111_000.0`, and `<=` to `<` on the D6 gate — left the suite green at `103 of 103` while the two
implementations snapped the same coordinate 8.2 m apart and charted different sets of
measurements. Both were found by PR #173's adversarial review, and both now go red.

The suite has no Swift toolchain, so it still cannot prove the recording is current by running
anything; the tripwire is what turns a stale recording into a red run rather than a green one. 76 of the 78 recorded coordinate comparisons match Swift to the bit. The two
that do not are one unit in the last place of `cos()` at 40.7128° N — 1.2 nanometers — and the
suite asserts that exactly two need its tolerance, so the tolerance cannot widen unnoticed.

**Two things the port had to name rather than smooth over.** Swift's `Double.rounded()` breaks
ties away from zero and JavaScript's `Math.round` breaks them toward positive infinity, which
differs on every negative longitude this app has; `geometry.ts` implements the Swift rule
explicitly in `roundedAwayFromZero`, which does use `Math.round` — under `Math.abs`, with the sign
restored by `Math.sign`, so there is no signed tie for it to break. No **bare** `Math.round` on a
signed value, which is the claim that is true. And `snappedToPublicPhotoGrid` is **not
idempotent** — applying it twice moves a point by up to 12.20 m, and the SQLite read path applies
it twice — which is written up in `docs/errata-pending/`, pinned by a test against the recorded
Swift behavior, and left unrepaired because repairing it moves already-published coordinates.

## The read path, when it arrives (W-B)

The web opens the **published city packs**, read-only, through the same schema the phone uses —
decision W-5. Not Postgres, not browser-side SQLite over HTTP range requests. It reads
`manifest-v2.json` the same way the app does, and refuses a pack whose `schema_version` is newer
than it knows rather than guessing, which is the posture `SeedDatabase.newestKnownSchemaVersion`
takes.

**Three version spaces, and this file states none of their numbers.** The writable database's
migration counter, the published seed's schema version and the manifest envelope format are
unrelated axes that advance independently; `CLAUDE.md` records that a sentence written to prevent
confusing them went stale twice while doing it. Read all three from the code.

**NYC's disclaimer obligation follows the data.** Any page rendering NYC trees carries it,
human-visible, because a machine-readable `attribution` array does not discharge it.
