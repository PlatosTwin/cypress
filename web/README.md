# `web/` — the public read surface

**Astro + TypeScript, SSR on the Node adapter, self-hosted on Fly.** Opened 2026-09-10 by the
owner; the authority is `docs/design-proposals/2026-09-10-web-version.md` and the queue underneath
it is `docs/ROADMAP.md` section **W**. Milestone **W-A** built the foundation — it builds, it is
tested, and it renders one placeholder page. The **read layer** clause of **W-B** landed next and
is described under "The read path" below; the other two W-B clauses (design tokens, the ported
domain rules) are still open.

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
| Pack reads | `src/lib/pack/` — opens a published pack read-only through `node:sqlite`. No pages read it yet |

**Two runtime dependencies and three development ones**, and no test framework at all, which is
the same discipline `server/` holds with two. `node:sqlite` is why the runtime is pinned this
tightly: it is in the standard library, which is what keeps the Docker image simple now that the
read layer opens packs, and it is documented as experimental, which is what makes a floating Node
tag a bad idea. `src/lib/pack/` imports it; nothing else does.

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
itself, and **six files outside `web/` that the suite actually reads** — three Swift sources,
`Tools/publish_cities.py`, and the two tracked files in `Fixtures/seed/`. It runs the same
`Tools/run_web_tests.sh` an agent runs, keeps the log as an artifact for thirty days, and builds
the Docker image without pushing it.

Those six are not decoration. The list used to be three entries under a comment reading "a path
outside `web/` cannot affect this app", which was true until a web test opened a Swift file — and
a drift guard whose trigger excludes the file it guards is green on exactly the diff that breaks
it. `test/pack-versions.test.ts` asserts that every out-of-`web/` file this suite reads is on both
`paths:` lists and still exists. **The rule: a file a web test opens is a file that triggers the
web suite.**

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

## The read path (W-B)

The web opens the **published city packs**, read-only, through the same schema the phone uses —
decision W-5. Not Postgres, not browser-side SQLite over HTTP range requests. It reads
`manifest-v2.json` the same way the app does, and refuses a pack whose `schema_version` is newer
than it knows rather than guessing, which is the posture `SeedDatabase.newestKnownSchemaVersion`
takes.

`src/lib/pack/`, five modules, zero new dependencies:

| | |
|---|---|
| `versions.ts` | The three version spaces, each written once and asserted against the Swift or Python it copies |
| `seedSchema.ts` | `SeedSchema.introspect` ported — asks the file what it carries, never a version integer |
| `pack.ts` | `openPack`, read-only and immutable, with `CityLibrary.validateCityFile`'s refusals |
| `manifest.ts` | `CityManifest` ported — strict on `manifest_format`, tolerant of additive keys |
| `queries.ts` | One tree by uuid, trees in a bounding box through the R\*Tree, counts, pack identity |

**It never writes.** The open is `readOnly` *and* `mode=ro`, so a write is refused by SQLite
rather than by a promise in a comment, and the suite asserts that on the real 103 MB seed as well
as on fixtures.

**It does not build `InventoryUnion`.** The phone attaches several packs at once with re-keyed
species and composite ids because one device holds several cities; one pack at a time is what the
web needs, and porting the union's identity arithmetic would import a hazard to solve a problem
the web does not have.

**What the suite proves without the 103 MB seed, which CI does not have.** Every claim about
behavior is made against packs built at test time by *executing* `Fixtures/seed/schema.sql` — the
repository's own generation-17 contract, which is tracked — at four generations, plus the live
catalog captured verbatim as `test/support/manifest-v2.captured.json`. `test/pack-real-seed.test.ts`
is an additional tier, not the only one: it covers scale and reality (198,625 real rows, a real
R\*Tree, a real two-id-space file) and nothing that is covered *only* there. Without the seed those
eight tests skip, loudly, and a census test that always runs asserts how many of them exist. **A
seed that is present and is not the pinned one is a failure, not a skip** — `pinned-seed.json`'s
size and sha256 are checked before a byte is believed.

**The bundled seed is generation 16; every published pack is 17.** That is deliberate and it is why
nothing here branches on a version integer. See the errata this round filed.

**Three version spaces, and this file states none of their numbers.** The writable database's
migration counter, the published seed's schema version and the manifest envelope format are
unrelated axes that advance independently; `CLAUDE.md` records that a sentence written to prevent
confusing them went stale twice while doing it. Read all three from the code.

**NYC's disclaimer obligation follows the data.** Any page rendering NYC trees carries it,
human-visible, because a machine-readable `attribution` array does not discharge it.
