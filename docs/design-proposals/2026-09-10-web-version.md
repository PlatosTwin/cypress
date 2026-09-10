# The web version — a public read surface, in this repo, over the published base layer

**2026-09-10. A design proposal, written before any `web/` directory exists. No production Swift, no
publisher change, no migration, no schema change in any version space.**

> **The owner's instruction, verbatim.** *"We've been working on an iphone version of cypress but
> it's high time that we also get a web version. please act as the orchestrator for a subagent swarm
> that will plan out and then execute a web-version of cypress (using this repo as a monorepo, unless
> that comes back as a very bad idea). run autonomously to make this happen, asking questions as you
> need but otherwise directing the swarm as needed"*

Every fact below was read out of this repository or measured against the live deployment on
2026-09-10. Where this document states what a constant is, it was read from the declaration. Four
research agents produced the evidence; where a finding contradicts a checked-in document, the
contradiction is stated rather than smoothed over.

**Three things to read before the rest.** §1 — the web version is not greenfield, and the single
screen it must ship is already transcribed at the same fidelity as the nineteen iOS screens. §4 —
the read path is the *existing published base layer*, which means the web introduces no second source
of truth for inventory and does not invoke R36's Shape B fallback. §7 — a `web/` directory is unsafe
in this repository until one regex changes, and that edit must land in the same PR that creates the
directory.

---

## Decisions, 2026-09-10

Four were put to the owner as explicit choices with trade-offs stated, and all four were ruled.

| | Question | Ruling |
|---|---|---|
| **W-1** | What is web v1? | **The public read surface.** W1 tree pages plus the `Explore` / `Species` / `Neighborhoods` / `Data & export` nav the spec draws. No login, no writes. |
| **W-2** | Monorepo? | **Yes — `web/` in this repository**, with the CI carve-out landing in the same PR that creates the directory. |
| **W-3** | Constraint 21 on unspecified web surface | **A scoped exception, in the shape of M5's.** Agents may design the unspecified web pages; every invention lands in `docs/rulings-pending/` for the owner's ratification. Nothing is settled quietly inside a view file. |
| **W-4** | Runtime | **TypeScript + SSR, self-hosted on Fly.** Vercel stays ruled out (R36 / `RULINGS.md:2275`). |

The decisions below this line were **not** put to the owner. They are the orchestrator's, taken under
W-3's grant and under the owner's instruction to run autonomously, and each is written here so it can
be overturned on the merits rather than rediscovered.

| | Decision | §|
|---|---|---|
| **W-5** | The web reads the **published city packs**, mounted read-only on a Fly volume, through the same schema the phone uses. No Postgres inventory, no second pipeline. | §4 |
| **W-6** | **No raster basemap in v1.** Explore draws pins over the neighborhood polygons already shipped in the seed. PMTiles on Tigris is the named path if a basemap is later wanted. | §5 |
| **W-7** | **No photos on the public surface in v1.** W1's specified hero is a gradient, not a photograph; a public photo read path is a privacy decision (D11) and gets its own round. | §6 |
| **W-8** | Astro + TypeScript, `node:sqlite`, no React in v1. | §3 |
| **W-9** | Verification gets a web pair — `Tools/run_web_tests.sh` and `Tools/verify_web_test_log.sh` — because judging a run by its exit code is this project's signature failure mode and nothing about that changes on a different platform. | §8 |

---

## 1. The web version is not greenfield

Three documents already commit to it, and one of them draws it.

- **`docs/distilled/SCREENS.md` §W1 · Public tree page** is transcribed at the same pixel fidelity as
  the nineteen iOS screens: a `ChromeWindow` at 1180×780, URL `cypress.app/sf/tree/9f3a-monterey-cypress`,
  a `1.45fr 1fr` body grid, a radial-gradient hero with the H1 at Serif 42px/600, a fact column of C30
  rows carrying every method badge, and a recent-visits panel. Its caption specifies that "the
  OpenGraph image is rendered from the same three ingredients so the group-chat preview and the page
  agree."
- **`docs/distilled/PROTOTYPE-FLOW.md` PART 2** transcribes the Coordinator dashboard, web-only, at
  `cypress.app/org/workday`. Out of scope for v1 under W-1, but it is drawn.
- **`docs/ARCHITECTURE.md` §8** closes its milestone table with: *"The public web tree page (W1) and
  the coordinator dashboard are out of scope for the iOS app; they are separate deliverables and are
  not built here."* The work was deferred, not undecided.

`DESIGN.md:170` and `BUILD-PLAN.md:9` both originally specified a monorepo with a web app over one
backend. W-2 returns to that shape.

### The defect that pays for v1

`Cypress/Features/Share/SharePresentation.swift:245` declares
`static let publicURLPrefix = "https://cypress.app/sf/tree/"`, and screen 10 renders it on the share
card. **Every link the iOS Share screen has ever produced points at a page that does not exist.**
`PRODUCT.md`'s growth loop — "the share card is the growth loop: enthusiasts showing off their
trees" — is currently a dead end at the moment of sharing. W1 is the page those links have always
meant.

### One disagreement to log before any code

`mocks/cypress-mocks.html:971` renders W1 with a three-item nav (`Explore` · `Species` ·
`Neighborhoods`) and fact rows `Status` / `Height / DBH` / `Photos across time` / `City record` /
`Data`. `SCREENS.md` §W1 transcribes a **four**-item nav (adding `Data & export`) and six fact rows,
splitting `Height` and `Trunk · DBH` onto separate rows and adding `In the city record since`.

Per the ROADMAP's standing rule — *"Every screen is implemented against `SCREENS.md`, which is the
transcription; the mock is the check, not the source. Where they disagree the disagreement is an
ERRATA entry before it is a code change"* — this is an errata entry, written before W1 is built, not
a judgment call inside a component. The implementing round writes it to `docs/errata-pending/`.

---

## 2. What is portable, measured

Counts are from `find`/`wc -l` against the worktree, not estimated.

| Layer | Files | Lines | Verdict for the web |
|---|---|---|---|
| `Core/` | 25 | 3,997 | **Port the rules.** Vitality rubric (157 L), `Quantity` (143 L), the 25 m public-photo grid, `isEligibleForGrowthCharting`, ID spaces, `LandContext.inferred`. Hard-coded Swift, no external rules file, trivially re-derivable in TypeScript. |
| `Data/` | 69 | 32,916 | **Reuse the schema, not the code.** Most of the bulk is SQLite plumbing and outbox/sync mechanics. The web reuses `Fixtures/seed/schema.sql` and the city-pack manifest contract verbatim. |
| `DesignSystem/Tokens` | 8 | 4,748 | **Export mechanically.** 213 colors, 224 spacing values, 105 font declarations — declarative `static let`s with no logic. A generator emits CSS custom properties; a test asserts the export still matches the Swift source. |
| `DesignSystem/Components` | 34 | 7,228 | **Rewrite.** C1–C30 are SwiftUI view code. |
| `Features/` | 148 | 50,224 | **Rewrite, and mostly not needed** — v1 is read-only. |

There is **no module seam to compile to WASM**: `Cypress.xcodeproj` has a single application target,
so `Core`/`Data`/`DesignSystem`/`Features` are directory conventions upheld by code review, not
compiler-enforced modules. Extracting `Core` into a SwiftPM module is possible — it imports only
Foundation — but nobody has started it and there is no `Package.swift`. **The ported asset is the
rules and the schema, not the Swift.**

The executable spec already exists. `CypressTests` holds **1,951 `@Test` functions across 187 files**;
the domain-rule subset (`VitalityRubricTests`, `SpeciesTrigramTests`, `SpeciesCorrectionTests`,
`UnreadSpeciesNameTests`, `SpeciesSearchTests` and kin) is what the TypeScript rules module must
satisfy, ported case by case rather than re-invented.

### Two documents that are wrong, found on the way

- **`docs/ARCHITECTURE.md` §1's comparison table (line 29) and §2's import-discipline paragraph (lines 48, 53, 72, 99) all say the local store is GRDB.** It is not.
  `Cypress/Data/Store/SQLiteConnection.swift` and its siblings `import SQLite3` directly, there is no
  GRDB dependency in the app target, and the only three files that mention GRDB do so in comments
  disclaiming it (`TreeProfileModel.swift:8`, `MapModel.swift:6`). This is exactly the class of
  confident-comment defect the ROADMAP's own preamble warns about.
- **`.gitignore:30` calls the seed an "88 MB build product."** `Fixtures/seed/pinned-seed.json:63-70`
  measures the artifact it pins at **108,249,088 bytes**.

Both go to `docs/errata-pending/` in the foundation round. Neither blocks the web.

---

## 3. Runtime and framework (W-4, W-8)

**Astro + TypeScript, self-hosted on Fly, Node adapter, `node:sqlite`.**

Astro over Next because v1 is a read surface: Astro ships zero JavaScript by default, which is the
right posture for a page whose job is to render fast and preview well in a group chat, and its
islands model defers the whole frontend-toolchain question until Explore actually needs interactivity.
Next's strongest features target the platform R36 already ruled out.

`node:sqlite` over `better-sqlite3` because it is in the standard library and needs no native build
step — which keeps the Docker image close to the two-direct-dependency discipline `server/` holds.
This requires Node 22+; the round that scaffolds `web/` pins the exact version and states it.

**No React in v1.** If a later round needs it, that is a decision with a reason, taken then.

---

## 4. The read path (W-5) — the published base layer, mounted

This is the crux, and it turns on a fact the research surfaced: **the API cannot serve W1.**
`GET /api/v1/trees/{id}` returns the community half only — no coordinate, no species name, no display
name — because R36 puts the city layer on the phone and `RemoteAPI` says so. The reads that exist
(`/me/grove`, `/me/journal`, `/me/map-membership`) are Class R, the contributor's own data. There is
no server-side source for "what tree is this UUID."

Three shapes were considered.

| | Shape | Verdict |
|---|---|---|
| **A** | **Web app opens the published city packs read-only from a Fly volume** | **Taken.** |
| B | Browser-side SQLite over HTTP range requests against the public bucket | Rejected. Pushes 100 MB+ of index traffic at readers, and makes every page load depend on range-request behavior of an endpoint the project does not control. Clever and fragile. |
| C | Import the inventory into Postgres and serve it | Rejected. A second source of truth for inventory, a second pipeline to keep in step with `build_seed.py`, and a third place for the schema-version confusion CLAUDE.md already warns about twice. |

**Why A is in R36's grain rather than around it.** R36's base layer is "versioned per-city SQLite
files published by the ingest pipeline to object storage with a manifest," and the app is one consumer
of that. The web is a second consumer of the *same artifact*, reading it with the *same schema*
through the same manifest contract. It is not R36's Shape B — that fallback is "a live query API over
the full corpus" replacing the phone's local read path, and nothing here changes what the phone does.
What the web adds is a consumer that happens to run on a server because a browser has no local store.

**Consequences that are binding:**

1. The web machine holds every published pack, not one city. **Measured against the live
   `manifest-v2.json` on 2026-09-10: seven packs, 713.6 MB, 1,097,382 trees** — `sf` 145,964 /
   82.8 MB, `us-ca-sj` 52,775 / 29.4 MB, and NYC's five boroughs from `us-ny-nyc-manhattan`
   98,929 / 66.9 MB to `us-ny-nyc-queens` 298,839 / 199.2 MB. Every pack is `schema_version` 17 at
   version `s17-r2026-08-22.02-ac7b1ccc`. The tree total is exactly `SeedCorpus.swift:22`'s
   1,097,382, which is the calibration that the manifest and the app agree on what was published.
   **A 2 GB Fly volume** holds the corpus with room for one version's overlap during a refresh;
   the deployment round re-measures rather than trusting this paragraph.
2. **The web reads `manifest-v2.json` and refreshes the same way the app does.** It must respect
   `CityManifest`'s format set, and a pack whose `schema_version` exceeds what the web knows is
   refused, not guessed at — the same posture `SeedDatabase.newestKnownSchemaVersion` takes.
3. **The three version spaces stay three.** `AppSchema.currentVersion` (the writable app DB),
   `SeedDatabase.newestKnownSchemaVersion` (the published seed), and `CityManifest.knownFormat` (the
   envelope) are unrelated axes. The web touches only the second and third, and never writes to any
   of them. Read all three from the code, never from prose — including this document.
4. **NYC's verbatim disclaimer obligation follows the data** (RULINGS ruling 2: the disclaimer must
   appear on every surface offering the pack, and a machine-readable `attribution` array does not
   discharge it). Any web page rendering NYC trees carries it, human-visible.

---

## 5. The map (W-6)

`docs/distilled/DECISIONS.md:153` puts "Mapbox or any per-seat map licensing" permanently out of
scope. The iOS app uses native MapKit; MapKit JS needs an Apple token the project has never evaluated,
and adopting it would tie the open web surface to Apple for no product reason.

**v1 ships Explore with no raster basemap.** It draws tree pins over the neighborhood polygons that
are *already in the seed* — DataSF `j2bu-swwd` geometries, stored as GeoJSON in the `neighborhoods`
table (`Fixtures/seed/schema.sql:129`, ingested at `Tools/build_seed.py:1996`). This is not a
compromise dressed up: the app's own reduced map component, `C18 · MapCanvas`, is a pin field without
street detail, and the spec reuses it on screens 15 and 18.

**If a basemap is later wanted, the named path is MapLibre GL JS over PMTiles hosted on Tigris** —
BSD-licensed renderer, OpenStreetMap data under ODbL (an obligation the project already discharges
for tree data), a single file on object storage read by HTTP range, no tile server and no per-seat
licensing. That is a decision for the round that needs it, with a measurement of the extract size in
front of it.

---

## 6. Photos (W-7)

`cypress-photos` is a **deliberately private bucket**: visibility is enforced application-side
through `isPubliclyVisible()` and operator takedown, not by ACL, and anonymous reads were verified to
return 403. There is no public read path and creating one is a privacy decision under D11, not an
implementation detail.

v1 does not need one. **W1's specified hero is four radial gradients over a linear base, not a
photograph** — `SCREENS.md` §W1 transcribes the exact stops. The photo count ("214 PHOTOS SINCE 2019")
is a number, and numbers come from the pack. A public photo read path gets its own round, its own
ruling, and its own answer to what a withdrawn photo does to a page a search engine has indexed.

---

## 7. CI — the edit that must land with the directory

`testflight.yml`'s `plan` job classifies changed paths by **deny-list**, not allow-list. Two
independent decisions:

- `tests` — `DOC_ONLY='docs/|graphify-out/|[^/]*\.md$'` (`testflight.yml:239`).
- `ships` — `NO_ARCHIVE` extends `DOC_ONLY` with `.github/`, `CypressTests/`, `CypressUITests/`,
  `server/`, and three named `Tools/` scripts (`testflight.yml:279`).

**A new top-level `web/` matches neither.** A web-only commit would run the full `unit` + `ui` suite
on `macos-26` runners — about 34 minutes of wall clock across two expensive runners, for a change
touching zero Swift — *and* mint a real TestFlight build byte-identical to the last one, expiring the
previous build and notifying every tester. That is the failure class (#212, #215, #31) the file
already guards `server/` against, in a commented block at `testflight.yml:262-274` explaining exactly
why `server/` must run tests but never ship.

`server/` is the pattern to follow, and following it is the foundation round's first job. Note also
that the `pull_request` trigger deliberately carries **no** `paths-ignore` (`testflight.yml:85-96`) so
that `gate`, a required check, can never deadlock — so a genuine web-aware skip belongs in `plan`
itself, not in the trigger.

`server/` has **no CI at all** (`ROADMAP.md:689`). The web will not repeat that: a `web.yml` running
on `ubuntu-latest` is part of the foundation round.

---

## 8. Verification (W-9)

This project's signature failure mode is false green, and nothing about that changes on a different
platform. The web gets the same shape of instrument the iOS side has:

- `Tools/run_web_tests.sh` — runs the suite to a log with a `CYPRESS-WEB-RUN:` provenance header
  (commit, node version, pack versions read from the manifest, working tree).
- `Tools/verify_web_test_log.sh` — judges the log. **Never the exit code.** It asserts a positive
  pass line with a nonzero test count, and refuses to certify a log with zero tests executed — the
  web analogue of `Executed 0 tests / All tests passed`.
- The zero-warning line carries over as `tsc --noEmit` clean plus a lint gate, certified on a fresh
  install rather than a warm one, for the same reason a reused DerivedData directory cannot certify a
  warning count.
- Every new test is red-proved, and **the red-proof must go red for the reason expected** — the
  failure message is read, not just the colour.

---

## 8a. AMENDMENT, 2026-09-10 — two of this document's own decisions were wrong

Written the same day, before any web code existed, by opening a real published pack and querying it.
Recorded here rather than silently edited above, because the method that caught them is the point.

**The pack was verified before it was trusted.** `us-ca-sj` downloaded from the public bucket:
29,372,416 bytes against the manifest's 29,372,416, sha256
`2d979b9a0ff90bea058eb409a29ae36019c949ddae82aead9259e9f906383671` against the manifest's, identical.
`select count(*) from trees` returns 52,775 against the manifest's 52,775 — the control that says the
file being queried is the file the manifest describes.

### A. W1's fact column is about half contributed data, and v1 has no public read for it

§4 said the web reads the published base layer and left it there, and §6 deferred only *photos*. That
was too narrow. Reading `SCREENS.md` §W1 against `trees`' actual 30 columns:

| W1 element | Answerable from a pack? |
|---|---|
| Eyebrow — `Great Highway at Judah · San Francisco` | **Yes** — `address`, `dim_city.display_name` |
| Latin line — `Monterey Cypress · Hesperocyparis macrocarpa` | **Yes** — `species_current` → `species`, though `common_name` is **null on real rows** (measured: two of two sampled alive SJ trees) |
| `In the city record since` — `1898` | **Yes** — `planted_year` |
| `City record` — `SF DPW #114-88 · synced weekly` | **Yes** — `external_ref`, `inventory_source` |
| `Data` — `ODbL · CSV / GeoJSON` | **Yes** — static |
| H1 — `Grandmother Cypress` | **No.** There is no name column in the seed contract. A named tree is contributed. |
| `Status` — `Thriving · vitality 4` | **No.** `vitality` is declared in `AppSchema` (the *writable* database), not in the seed. The pack's `status` is the lifecycle enum (`alive`, `vacant_site`, …), a different thing. |
| `Height` — `18 m` `est.` | **No.** A contributed measurement. |
| `Trunk · DBH` — `64 cm` `taped` | **No** for the taped reading. The pack carries `dbh_city_cm_min`/`_max`, the city's published *bucket* (measured: `0`–`5` cm on a 2025 planting) — which is the "city-bucket tree" the ROADMAP already names, not a reading with a method badge. |
| Foliage strip, `214 PHOTOS SINCE 2019` | **No.** Contributed. |
| `Recent visits` panel | **No.** Contributed. |

So W1 is roughly half city record and half community layer, and the community layer is in Postgres
behind an API whose read surface is **Class R — the contributor's own data**. There is no public read
of it, and creating one is a privacy ruling, not an implementation detail.

**This does not make W1 unbuildable.** Everything the pack answers is the spine of the page, and
"render nothing where knowledge is absent" is the house style, not a degradation. It does mean the
scope of W-C is a decision the owner has to take, and it is put to them rather than assumed here.

### B. Neighborhood polygons are San Francisco only, so §5's Explore falls over outside SF

**W-6 said Explore draws pins over "the neighborhood polygons already shipped in the seed."** In the
`us-ca-sj` pack, `neighborhoods` holds **0 rows**. The reason is in the builder:
`Tools/build_seed.py:2105` loads exactly one file, `sf_analysis_neighborhoods.geojson` — DataSF's
`j2bu-swwd`, an SF dataset. San Jose and the five NYC boroughs have no polygons at all.

**Consequence:** an Explore page that draws its geography from `neighborhoods` shows San Francisco and
six blank rectangles. The Neighborhoods nav destination has the same problem in a sharper form — for
six of seven packs there are no neighborhoods to list.

W-6 stands for San Francisco and is **withdrawn as a general answer**. The round that builds Explore
either sources polygons for the other cities, scopes the geography to SF, or takes the basemap
question the proposal deferred. Not decided here; named as open.

---

## 9. Open questions this proposal does not answer

1. **Is `cypress.app` registered?** It appears throughout the docs as a share-link prefix and in
   `ShareCopy.publicURLPrefix`, but no config file in the repository confirms ownership. The
   deployment round must establish this before the share link can resolve; until then the site lives
   at its `.fly.dev` hostname and `publicURLPrefix` stays as it is.
2. **What does a withdrawn or moderated record do to a public page** that a search engine has
   indexed? Relevant the moment anything user-contributed reaches W1. Not v1, because v1 renders
   city-record facts only.
3. **Does the Coordinator dashboard's domain get built?** Workdays, routes, claim/progress and the
   live activity feed exist in neither the server nor the app. That is a product round, not a port.
4. **Server CORS and Sign in with Apple JS** are prerequisites for any web surface that writes.
   v1 needs neither. The round that adds contribution needs both, and the second is a real
   integration change: `authOIDC` requires a nonce and fails closed, and the web flow's nonce is not
   the native flow's nonce.
