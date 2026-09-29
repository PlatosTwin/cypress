# `web/` — the public read surface

**Astro + TypeScript, SSR on the Node adapter, self-hosted on Fly.** Opened 2026-09-10 by the
owner; the authority is `docs/design-proposals/2026-09-10-web-version.md` and the queue underneath
it is `docs/ROADMAP.md` section **W**. Milestone **W-A** built the foundation: it builds, it is
tested, and it renders one placeholder page. **W-B** has since landed in full — the design tokens,
the pack read layer and the re-derived domain rules — described under *Design tokens*, *The rules,
re-derived* and *The read path* below. **W-C** reads all three: the public tree page is served from
a mounted pack, painted with the exported tokens, and its facts pass through the re-derived rules.

**What v1 is** (ruling W-1): a public read surface. No login, no writes. The tree page, plus the
`Explore` / `Species` / `Neighborhoods` / `Data & export` nav the spec draws.

**Why it is here and not in its own repository** (ruling W-2): the CI carve-out that keeps a web
commit from running the iOS suite and minting a TestFlight build has to live beside the directory
it classifies, and did, in the pull request that created both.

**What it is not.** It is not the iOS app in TypeScript. `Core/`'s rules are re-derived (W-B),
`Data/`'s schema is reused verbatim, and `Features/` is not ported at all — v1 is read-only, and
50,224 lines of it are about writing.

## What exists, exactly

As of W-C. Everything below was read from this directory, not remembered.

| | |
|---|---|
| Framework | Astro `7.3.2`, `@astrojs/node` `11.1.5`, `output: 'server'`, `mode: 'standalone'` |
| Language | TypeScript `5.9.3`, `astro/tsconfigs/strictest`, `erasableSyntaxOnly` |
| Runtime | Node `24.13.1`, pinned in `package.json` `engines`, `.nvmrc` and both `Dockerfile` stages |
| Test runner | `node --test`, TAP reporter, no test framework dependency |
| React | none, deliberately (W-8) |
| Fly app | `cypress-web` — **created, and empty**: no machines, no volume, nothing deployed. See *Deploying it* |
| Volume | declared in `fly.toml` (`cypress_packs`, 3 GB, at `/data/packs`) and **not yet created** |
| Pages | `/` (placeholder) and **`/‹id-space›/tree/‹uuid›`** — W1, server-rendered from a mounted pack (W-C) |
| OG cards | `/‹id-space›/tree/‹uuid›/og.png` — 1200×630 raster, what `og:image` points at. `og.svg` is still served and is the drawing it is made of |
| Packs | read from the directory `CYPRESS_PACK_DIR` names. No default path: unset means the page says so, in a 503 |
| Design tokens | `src/styles/tokens.css`, **generated** from the Swift by `scripts/export-tokens.mjs` |
| Card fonts | `fonts/`, **copied** from `Cypress/Resources/Fonts/` by `scripts/export-card-fonts.mjs`. Four faces, 852 KB |
| Pack reads | `src/lib/pack/` — opens a published pack read-only through `node:sqlite`. W1 reads it through `src/lib/packLibrary.ts` |
| Rules | `src/lib/{vitality,quantity,geometry,growthCharting,idSpaces}.ts` — W-B's first third |
| W1's own modules | `src/lib/{packLibrary,treePage,cityRecord,gradients,ogCard,obligations}.ts` and `src/styles/w1.css` |

**Three runtime dependencies and three development ones**, and no test framework at all. The
third arrived in W-C's raster round and is the only one this directory has ever added on purpose:
`@resvg/resvg-js`, so the OpenGraph card can be a PNG. What it is, what it cost and what was
rejected instead are in `src/lib/ogRaster.ts`'s header; the short version is 3.4 MB, one transitive
platform binary, no system libraries, and it renders text from font files handed to it rather than
from whatever the host has installed. The discipline is not "never add one" — it is that adding one
is a decision with an owner, and this one was ruled.

`node:sqlite` is why the runtime is pinned this tightly: it is in the standard library, which is
what keeps the Docker image simple now that the read layer opens packs, and it is documented as
experimental, which is what makes a floating Node tag a bad idea. `src/lib/pack/` imports it;
nothing else does.

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

**Nothing is deployed as this is written.** What changed in W-E is that the repository now
*describes* a deployment somebody can run: `fly.toml` declares the volume, the pack directory and a
health check, and `/health` answers the question a deploy needs answered. The Fly app `cypress-web`
**does now exist** — created while this round was open — and it is empty: no machines, no volume,
nothing deployed to it, answering on no hostname. Creating the volume and running `flyctl deploy`
are still a human's, and neither has happened.

**The site is `cypressatlas.org`** — the owner's ruling of **2026-09-13**, superseding the
2026-09-10 ruling that named `cypressgrove.app`. Both are recorded, with their dates, in the web
round's owner-decisions entry under `docs/rulings-pending/`; the orchestrator splices it into
**`docs/RULINGS.md`** under its real number at merge, so look for it there by date. This paragraph
deliberately does not name the pending file, because a citation by pending filename dangles the
moment the splice happens and `PendingCitationGuard` scans Swift only, so nothing here would catch
it.

**There is no cutover in this round, and that is the ruling and not an omission.** The owner's words
were that the site "won't land there live for a bit": the name is what to build toward. So
`fly.toml` declares no `[[certificates]]`, nothing touches DNS, and the site answers on its
`.fly.dev` hostname. Not `cypress.app`: that domain — the one `ShareCopy.publicURLPrefix` has always
pointed at, registered to somebody else and expiring 2026-11-03, parked with no A record — **is not
the owner's**, which is settled rather than open. Moving `ShareCopy.publicURLPrefix` is shipped iOS
copy and therefore a Swift round with its own review, not a web change; until it moves, no link in
the wild resolves.

The Fly app keeps the name `cypress-web` — a machine, not a brand. It is deliberately not renamed to
match the domain, because the domain can move and a Fly app name cannot.

### The volume

`fly.toml` declares a `[mounts]` on the volume **`cypress_packs`** at **`/data/packs`**, and
`[env] CYPRESS_PACK_DIR` is that same path. The two must agree and they are asserted to:
`web/test/toolchain.test.ts` compares them, in the same shape as the port guard beside it. Nothing
at runtime would notice them disagreeing — the volume attaches, the machine is healthy, and every
tree URL answers nothing with the data sitting on disk a directory away.

`CYPRESS_PACK_DIR` is the mount destination itself rather than a path inside it, so that a freshly
created volume — which is empty — is a directory that exists and is empty rather than one that is
absent. `openPackLibrary` refuses an absent directory outright, which is correct and which would
mean **every tree route 500s** until the packs arrive; an empty one is the state the read path
already handles. Measured against the built server rather than reasoned about, because the first
draft of that sentence said "every page": with an absent pack directory, `/` renders and answers
200 and `/health` answers 200 saying `unreadable` — it is `/‹id-space›/tree/‹uuid›` and its
`og.png` that 500.

**Size: 3 GB**, and `fly.toml` carries the arithmetic rather than the conclusion. In short: seven
packs at 713.6 MB re-measured against the live manifest on 2026-09-13, a refresh that writes a new
set beside the old one before pruning, therefore a peak around 1.43 GB, therefore 3 GB so the corpus
can roughly double before a refresh no longer fits. One more gigabyte than the design proposal
named, because a volume extends and never shrinks: too small is an outage found mid-refresh, too
large is cents.

**The volume has to exist before the first deploy.** A `[mounts]` naming a volume that is not
there fails a deploy at the point where the app is already half-created — which is why W-A left the
block out until this round. `fly.toml` carries an `initial_size = '3gb'`, and that is **not**
insurance against forgetting: flyctl refuses to create a volume for a process group with no
machines, which is exactly a first deploy, and tells you to run `fly volume create`. The key is
there to state the size in the file rather than only in whichever shell command created the volume.

Filling it is a separate step with its own section in this file. Two properties of the read path it
has to live with, stated here because they belong to the reader and not to whatever does the
filling:

- **`openPackLibrary` opens every `*.sqlite` directly in `/data/packs`**, so a partially written
  download must not sit there under that name while it is being written.
- **An entry the walk cannot inspect is that entry's problem, not the volume's.** A refresh that
  writes a new set beside the old one and prunes afterwards will, for the width of the prune, offer
  names that vanish before they can be stat'd. Those land on `/health`'s `problems` and the packs
  beside them go on serving. They used to take the whole library down and report an unmounted
  volume; that was a real defect, found in adversarial review of this round, and `packFiles` in
  `src/lib/packLibrary.ts` carries the note.

### `GET /health`

`web/src/pages/health.ts`. The path is `cypress-sync`'s, which has answered on `/health` since it
shipped; two Fly apps in one project answering the same operator question on two different paths is
a fact somebody would have to remember. `fly.toml`'s check path and the file that answers it are a
third copy-of-one-fact pair, and guarded like the other two: `web/test/toolchain.test.ts` resolves
the path to a file under `src/pages/`, requires exactly one, and imports it to confirm it exports
the verb the check sends.

It answers **200 in every state**, and puts the answer in the body:

| `state` | what happened | the repair |
|---|---|---|
| `unconfigured` | `CYPRESS_PACK_DIR` is unset | the image was deployed without its environment |
| `unreadable` | the **directory** could not be read | not mounted, not there, not a directory, or not readable |
| `empty` | readable, holding no pack this build can open | the volume is mounted and not filled |
| `serving` | packs are open; `idSpaces` says which URLs answer | — |

plus `ready`, `packs`, and `problems` — files in the directory that refused to open, by basename,
with the reason. A pack that refused is a whole city missing and is invisible in a count that went
up, so it is reported in every state, `serving` included. **A fault with one file is never one of
the four states**: `unreadable` is a directory-level answer only.

    curl -s https://<host>/health | jq '{ready, state, idSpaces, packs, problems}'

**The 200 is deliberate and it is not a shrug.** `fly.toml` points an `[[http_service.checks]]` at
this path, and a check gates the release: a 503 while the volume is empty would make the *first*
deploy impossible, because the volume is empty by construction until a sync that needs the machine
to exist. It would present as a rollback naming nothing. Machine health and request availability are
different questions — a reader asking for a tree on an unfilled machine already gets a 503 with
`x-cypress-refusal: noPacks` from the route itself. The full argument is in the route's header;
read it before reaching for 503.

The body is anonymous and unauthenticated, so it prints no absolute path and no environment value.
The unredacted error goes to the machine's log, where `flyctl logs` reaches it and a crawler does
not.

### Running it, in order

1. Create the volume — `cypress_packs`, 3 GB, in `sjc`. The app already exists. The volume must
   exist before the first deploy: a `[mounts]` naming a volume that is not there fails a deploy at
   the point where the app is already half-created, which is why W-A left the block out until this
   round. `initial_size` in `fly.toml` will not do this for you — flyctl refuses to create a volume
   for a process group with no machines.
2. `flyctl deploy`. The machine boots holding no packs. That is expected: `/health` says
   `state: empty`, and tree URLs answer 503.
3. Fill the volume.
4. `curl .../health` and read `ready` and `idSpaces`. The packs are opened once for the life of the
   process, so a volume filled after the machine started needs the machine restarted.

**Still unmeasured after all of this: the 512 MB in `[[vm]]`.** It was W-A's estimate and W-E could
not improve on it, because measuring it needs a running machine with a pack mounted. Whoever deploys
should measure it and write the number into `fly.toml` in place of the paragraph that says this.

## Design tokens (W-B)

`src/styles/tokens.css` is **generated and checked in**. `scripts/export-tokens.mjs` reads
`Cypress/DesignSystem/Tokens/*.swift` and writes it; `test/tokens.test.ts` re-runs the same render
and fails byte-for-byte when the two disagree. Do not edit the CSS — the next test run reverts it.

```sh
npm run tokens         # rewrite src/styles/tokens.css
npm run tokens:check   # exit 1 if it is stale (the test says the same thing, louder)
npm run fonts          # rewrite fonts/ from Cypress/Resources/Fonts (W-C's card raster)
npm run fonts:check    # exit 1 if a face is stale, missing, or unaccounted for
```

The generator lives under `web/` rather than in `Tools/` because **both CI workflows classify by
path**: `web.yml` runs on an allow-list and `testflight.yml`'s `WEB_ONLY` exempts the same set, and
a script at `Tools/export_tokens.mjs` is in neither — a change to it alone would skip the web suite
and run 34 minutes of `macos-26` that exercises nothing. Widening `WEB_ONLY` is the alternative and
it is guarded by `CypressTests/DeployPathsAgreeTests`, so it is a change the **iOS** suite has to
prove. Moving one file needs neither.

**Why generated-and-checked-in rather than parsed at build time.** The Dockerfile copies
`astro.config.mjs`, `tsconfig.json` and `src/` and nothing else — the Swift tree is not in the
image and never will be, because putting it there would make the iOS source a build input of a
web container. A build-time parse would also make every page render depend on a parser that has to
be right. So the CSS is a real file: it ships, it is reviewable in a diff, and a designer can read
what the web is actually painting. The cost of that choice is staleness, and the staleness is
exactly what `test/tokens.test.ts` refuses.

**Nothing is skipped silently.** Every `static let` in a token scope becomes a token, a private
constant, or a **named** entry on a skip list the test asserts one line at a time. A declaration
that matches no rule throws rather than being dropped — an exporter that returns "the tokens I
understood" is green on the day it stops understanding one.

**Dark mode is `prefers-color-scheme` and nothing else.** Every paired token in the Swift is
`Color(UIColor { traits in traits.userInterfaceStyle == .dark })`, which resolves off the *system*
setting; the app has no in-app appearance control (the only `preferredColorScheme` calls in the
target are in `#Preview` blocks). A `[data-theme]` attribute hook would be exporting a product
decision the source does not contain, and a test that the export matches its source cannot protect
anything the source does not say. Only tokens whose dark value differs appear in the dark block —
`lightOnly` and `escalated` resolve to one value in both schemes by definition.

**Three things the export does not carry**, each named in the test rather than left to be noticed:

- `CypressGradient.swift` — multi-stop linear and radial recipes with their own geometry. Not one
  custom property. W1's hero is a gradient, so W-C ports them.
- The eight composed `Animation`s. Their curves are `--motion-ease-*` and six of their durations
  are `--motion-duration-*`; `camera` (0.4 s) and `selection` (0.18 s) write their durations inline
  rather than in `CypressMotion.Duration`, so those two numbers have no token on either platform.
- `CypressFont.LineSpacing` is exported verbatim, in **points of extra leading**, which is SwiftUI's
  unit and not CSS `line-height`. `CypressFont.swift` gives the conversion it was derived under
  (`lineSpacing ≈ size × (lineHeight − 1.2)`). Nothing is transformed here, because inverting an
  approximation and calling it a token would be inventing a value the design system does not state.

  **Inverting it yields the wrong answer for two of the six, and the two are named in the
  generated file's own header.** `speciesHero` and `treeNameHero` are declared `0` in the Swift
  *because SwiftUI cannot set leading tighter than the face's natural line height* — the doc
  comment beside each says "tighter than natural; clamp at 0". `0` is that clamp, not the design
  value, so inverting `--font-line-spacing-species-hero: 0px` returns `line-height: 1.2` where the
  source documents **1.1**, and `--font-line-spacing-tree-name-hero` the same against **1.05** —
  *looser* than intended, on the two largest display styles. CSS has no such floor. A consumer
  that wants a `line-height` inverts the other four and uses the documented figure for these two;
  `test/tokens.test.ts` reads both figures out of the Swift and fails if the header stops matching
  them.

The one web-only judgment in the whole export is `GENERIC_FALLBACKS` in `src/lib/tokens.ts`: the
generic CSS fallback after each family, which iOS has no equivalent of. The family *names* are not
invented — `Source Serif 4`, `Alegreya Sans` and `Spline Sans Mono` are derived from the PostScript
prefixes the Swift declares, and they are the `name` table families of the TTFs in
`Cypress/Resources/Fonts/`.

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
on the Swift source that snapshot came from*: `test/swiftDrift.test.ts` fingerprints the Swift
declarations whose bodies the ports reproduce and no value parser reads, and goes red on any edit to
them, cosmetic or not, with a message telling the reader to re-record the reference and re-verify
parity before pasting a new fingerprint. That file states the membership rule, names the set it
covers and lists what is deliberately out; this paragraph does not restate the list, because the
first version of it did and was wrong about the set while being right about the count. Without that second half, two one-character edits to the real Swift — `111_320.0` to
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

## The read path (W-B)

The web opens the **published city packs**, read-only, through the same schema the phone uses —
decision W-5. Not Postgres, not browser-side SQLite over HTTP range requests. It reads
`manifest-v2.json` the same way the app does, and refuses a pack whose `schema_version` is newer
than it knows rather than guessing, which is the posture `SeedDatabase.newestKnownSchemaVersion`
takes.

`src/lib/pack/`, six modules, zero new dependencies:

| | |
|---|---|
| `versions.ts` | The three version spaces, each written once and asserted against the Swift or Python it copies |
| `seedSchema.ts` | `SeedSchema.introspect` ported — asks the file what it carries, never a version integer |
| `pack.ts` | `openPack`, read-only and immutable, with `CityLibrary.validateCityFile`'s refusals |
| `manifest.ts` | `CityManifest` ported — strict on `manifest_format`, tolerant of additive keys |
| `queries.ts` | One tree by uuid, trees in a bounding box through the R\*Tree, counts, pack identity |
| `localSeed.ts` | Which of three states this checkout's ~103 MB seed is in — present, absent, or not the pinned one |

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
R\*Tree, a real two-id-space file). Without the seed its nine tests skip, loudly.

**"Nothing is covered only in the seed tier" is a claim that has to be measured, and it was
false twice.** A fixture can agree with a wrong query — that is the failure mode here, not a
missing test. The R\*Tree join was wired to the wrong column and every fixture bounding-box test
still passed, because every fixture tree shared one `neighborhood_id` and `treesInBounds` re-tests
`lat`/`lon` on `trees` afterwards, re-deriving the right answer from the wrong join; only the
seed-gated test went red, on a machine that has the seed. Reversing `packIdentity`'s
`ORDER BY id LIMIT 1` was the same shape, for the same reason: no fixture carried more than one
`dim_city` row. Both fixtures now discriminate — a tree in the box with no R\*Tree row, an R\*Tree
row with no tree, neighborhood ids that cross over the tree ids, and a fused two-city, two-region,
two-id-space file — and both mutations are red on a runner with no seed. The claim is worth stating
only alongside how it was checked: mutate the thing, move the seed aside, require red.

**Twice more, that check found the repair itself.** The fused fixture doubled every *dimension*
table and left every tree in the first id space, so `LEFT JOIN dim_city dc ON dc.id = isp.city_id`
loosened to `ON dc.id = 1` stayed green in both tiers while mislabeling 52,788 San Jose trees in
the seed; and the `lat`/`lon` re-test that removes the R\*Tree's false positives could be deleted
in silence, because the seed test's per-row loop sits behind its own `LIMIT 200` and none of that
box's seven escapees sort into the first 200. The fixtures now carry a fact row in the second id
space and four trees whose float32-expanded R\*Tree box overlaps the test's box while their
coordinates do not. **A dimension table with two rows proves nothing until a fact row resolves
through the second one**, and **a guard downstream of a `LIMIT` proves nothing about the rows the
limit does not reach.**

**The census is derived, not declared.** `SEED_DEPENDENT_TESTS` and `ALWAYS_RUN_TESTS` are compared
against the names this file actually handed to `node:test`, so a deleted, renamed, reordered or
newly added test is red in both tiers. It used to be a literal compared against a literal in the
same file, which is green on a deletion — which is how a review found it. Registration goes through
one wrapper that `node:test` can only be reached through, rather than through a pattern matched
against this file's source: a pattern recognizes one spelling, and a review found nine spellings
that got past the one that was there and three innocent lines it reddened on, a doc comment among
them. **The census sees its own file only** — a seed-gated test in another file under `test/` is
outside it, which is why it also asserts that no sibling test file refers to `seedState`. **A seed that is present and is not the pinned one is a
failure, not a skip** — `pinned-seed.json`'s size and sha256 are checked before a byte is believed,
and they are checked again at the end of the seed tier, because a read-only regression once rewrote
the pinned seed in place at an unchanged size.

**The bundled seed is generation 16; every published pack is 17.** That is deliberate and it is why
nothing here branches on a version integer. See the errata this round filed.

**Three version spaces, and this file states none of their numbers.** The writable database's
migration counter, the published seed's schema version and the manifest envelope format are
unrelated axes that advance independently; `CLAUDE.md` records that a sentence written to prevent
confusing them went stale twice while doing it. Read all three from the code.

**NYC's disclaimer obligation follows the data.** Any page rendering NYC trees carries it,
human-visible, because a machine-readable `attribution` array does not discharge it.

---

## W1 · the public tree page (W-C)

`src/pages/[idSpace]/tree/[uuid].astro`, server-rendered, at the path
`ShareCopy.publicURLPrefix` has pointed every share card the app has ever produced at. It reads a
published pack through W-B's layer and renders `SCREENS.md` §W1.

**Point it at packs with `CYPRESS_PACK_DIR`.** Every `*.sqlite` in that directory is opened
read-only and indexed by the id spaces the **file itself** declares, not by its filename — New York
is five packs in one id space and San Jose ships fused with San Francisco, so a filename convention
would be a second copy of a fact the file already carries. There is no default path: with the
variable unset the page returns **503** and writes a line to the log, because "no packs are mounted"
is a deployment fault and a 404 would tell an operator it was a missing tree.

**About half of §W1 is not in the pack, and that half is absent rather than faked.** Height, the
taped DBH reading, the foliage strip, its photo caption and the recent-visits panel are contributed
data behind a Class R surface; `Sign in` and `Open in the app` have no destination. The whole
element-by-element account, and the four labels that say less than the mock does, are in this
round's errata entry. **Nothing is stubbed, nothing renders a zero, and nothing invents a fact** —
a placeholder in a fact column is a claim, and an empty state where the mock drew data is a screen
nobody designed.

**The gradient is ported, and guarded in two halves.** `src/lib/gradients.ts` emits CSS from a
recipe. One half of the guard compares W1's recipe against §W1's own transcription, parsed out of
`SCREENS.md` at run time; the other renders `CypressGradient.heroProfile` — parsed out of the Swift
at run time — through the same emitter and requires it to equal what §3's screen 03 transcribes.
That second half is what proves the **emitter**, because W1's hero is not in `CypressGradient.swift`
at all: §W1 draws its own recipe, close to screen 03's and not equal to it. **CSS paints its first
background layer on top and a SwiftUI `ZStack` paints its last on top**, so the layer order is
inverted in the port and there is a test whose only job is to fail if somebody "fixes" it.

**The OpenGraph card is a PNG, rasterized from that SVG.** `og.svg.ts` builds the card out of the
same `TreePageModel` the page renders — which is what §W1's caption asks for, "rendered from the
same three ingredients so the group-chat preview and the page agree" — and Facebook, X, Slack,
iMessage and LinkedIn all want a raster. The owner ruled the dependency in; `og.png.ts` rasterizes
the string `treeCardSVG` returns, so the two encodings are one drawing and there is nothing to
diverge. `<meta property="og:image">` points at the PNG and now also declares `og:image:type`,
`og:image:width` and `og:image:height` — **the last two of which this page never declared at all**,
which is a separate defect the same round found.

**The faces are files in this directory, and that is not an accident.** `@resvg/resvg-js` 2.6.2
takes fonts as paths on disk, and the image is built from a context of `web/`
(`docker build … web`), so nothing outside this directory can reach the container. `fonts/` is a
checked-in copy of the four faces the card sets, written by `npm run fonts` and hashed against
`Cypress/Resources/Fonts/` by `test/ogRaster.test.ts` — the same generated-and-checked-in bargain
`tokens.css` is. The five sources are on both of `web.yml`'s `paths:` filters for the same reason
every other out-of-`web/` source is.

**A missing face is a 500, not a blank card.** The render sets `loadSystemFonts: false`, which is
what makes the card look the same on a laptop, on `ubuntu-latest` and in the container — and is
also the setting under which resvg draws *nothing at all* for a family it cannot resolve: no error,
no fallback, a gradient with no words on it. So the directory is checked before a render is
attempted and `MissingCardFonts` names what is absent. Verified by running the built image against
an empty font directory: `500`, `x-cypress-refusal: rasterizer`, and the reason in the log.

**The suite reads the bytes, not the renderer.** `test/support/png.ts` decodes the PNG — signature,
IHDR, inflate, unfilter — and the measure that tells type from no type is a count of luma steps
rather than a count of ink-colored pixels, because three of the card's four runs are drawn below
full opacity. Measured on the real card: 0 steps in a 1080×300 window of pure gradient, and 1,700
to 4,800 in each of the four text bands.

**W1 is light-only on purpose.** Three of §W1's surfaces map to `lightOnly` tokens while the generic
page tokens beside them are `dynamic`, so a dark rendering would be half of one palette over the
other — a state no mock draws. `src/styles/w1.css` carries the same note at the top of the file.

## Filling the volume (W-E)

The server reads packs out of `CYPRESS_PACK_DIR` and **nothing puts them there**. That step is
`scripts/sync-packs.mjs`, run *on the machine*, against the same public catalog the phone installs
cities from:

```
fly ssh console -a cypress-web
cd /app && node scripts/sync-packs.mjs --dir /data/packs
```

Locally it is `npm run packs` with `CYPRESS_PACK_DIR` set, or `-- --dir <path>`. Seven packs,
713,605,120 bytes as this is written, so the first fill is not quick.

**It is not run at boot and must not be.** 713 MB over a cold network is not something a health
check can wait for, and a server that fetches its own data at startup fails to start on the day the
bucket has a bad minute. The image carries the script — `Dockerfile`'s runtime stage copies
`scripts/` and, because the script imports the catalog decoder and the pack generation from
`src/lib/`, `src/` with it — so filling the volume is a thing an operator does to a running machine.

**What it refuses, and why each refusal is worth having:**

- **No destination.** No `--dir`, no `CYPRESS_PACK_DIR`, no default — `packLibrary.ts`'s rule, one
  step earlier. A default would write the packs somewhere that is not the volume and leave the
  volume looking mounted and empty.
- **A destination that does not exist.** It never creates one. A mount point that is not mounted is
  an ordinary empty directory, and `mkdir -p` is delighted to fill it on the root disk.
- **An envelope format this build does not read**, before it looks at a single city — `manifest.ts`
  owns that, and the sync just does not catch it.
- **A pack published past `NEWEST_KNOWN_PACK_SCHEMA_VERSION`.** Downloading it would produce a file
  the server then declines to open. The rest of the catalog still syncs; the run exits nonzero.
- **Bytes that are not the bytes the catalog names.** Every pack streams to
  `.<id>.sqlite.part-<pid>-<random>` in the destination directory, is hashed as it streams, and is
  compared against both `bytes` and `sha256` before `rename()` puts it in place. Nothing is ever
  written to the final path directly, and the temporary name deliberately does not end in
  `.sqlite`, because the running server opens every `*.sqlite` it finds. A failed verification
  leaves nothing behind and is **not** retried — the object either matches the catalog or it does
  not. A failed *connection* is retried, a few times, with a stall timeout that measures "this
  transfer has stopped moving" rather than "this transfer is taking a while".
- **A catalog `path` or `id` that is not a plain relative name.** The catalog is a remote object;
  it does not get to choose where its reader writes.
- **A catalog whose entries would land on one file** — two entries with one id, or two ids that
  differ only in case. One would overwrite the other and the summary would count both, so the whole
  catalog is refused before a byte moves, the same way an unknown format is.
- **A destination it cannot write to.** EACCES, EROFS and ENOTDIR are found by opening the
  temporary file *before* the request is made, so an unwritable volume costs no transfer; they are
  reported as an ordinary refusal with a summary line after it, and they are not retried, because
  asking again writes the same error again. `ENOSPC` mid-transfer is treated the same way rather
  than retried into a disk that is already full.

**A refresh is the same command.** A pack already present at the right size and hash is skipped and
said to be skipped, so the second run is fast and legible:

```
sync-packs: skipped sf (s17-r2026-08-22.02-ac7b1ccc, 82796544 bytes, sha256 matches)
sync-packs: downloaded us-ny-nyc-queens (s17-r2026-08-22.02-ac7b1ccc, 199163904 bytes, sha256 verified)
SYNC-PACKS: OK downloaded=1 skipped=6 pruned=0 refused=0 bytes-downloaded=199163904 …
```

That last line is the one to read — a human and a grep can both use it, and the exit code is 1 if
anything was refused. **The layout is flat and the version is not in the filename** (`<id>.sqlite`,
one per pack id), because the library opens every `*.sqlite` in the directory and two versions of
one city would both answer for the same id space. So "which publish is on the volume?" is answered
by running the sync and reading what it skipped, not by looking at the names.

**A city that leaves the catalog is left alone unless you say `--prune`.** A refresh that silently
deletes a city is worse than one that leaves a stale file, so an unlisted pack is reported and kept;
`--prune` removes it, and each removal is printed.

**What it deletes and what it merely reports are two different sets, and the output says which.**
`--prune` only ever deletes a plain file this script could itself have written: an unlisted
`<id>.sqlite`, or a leftover temporary whose process has exited and whose last write is outside the
stall window. A temporary belonging to a live pid, or written moments ago, is kept and named — two
syncs against one directory no longer end with one deleting the other's transfer, though there is
still no reason to run them that way. Everything else it will not touch. But `packLibrary`'s reader
opens **every** name ending in `.sqlite`, does not skip dot-files, and follows symlinks, so
`.hidden.sqlite` and a symlink pointing outside the volume are files the server would serve and
`--prune` will not remove. Those are reported too, marked `--prune does NOT remove it`, so a
directory somebody has poked at stops looking clean.

The server holds its packs open for the life of the process (`packLibrary.ts`), so after a refresh
that actually replaced something, restart the machine before expecting the new bytes to be served.
