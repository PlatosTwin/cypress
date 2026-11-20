# Unnumbered — the orchestrator splices this under the next R number at merge (CLAUDE.md,
# Numbering). Written from branch `claude/cypress-web-version-60fc5e`, 2026-09-10.

### The web version: scope, home, design authority, and runtime (owner-ratified)

*Owner, 2026-09-10, opening the round: "it's high time that we also get a web version … using this
repo as a monorepo, unless that comes back as a very bad idea." Four questions were put back with the
evidence and the trade-offs stated; all four were ruled the same day.*

The evidence behind each is `docs/design-proposals/2026-09-10-web-version.md`.

**1. Web v1 is the public read surface.** `SCREENS.md` §W1's public tree page plus the
`Explore` / `Species` / `Neighborhoods` / `Data & export` nav that page draws. **No login and no
writes.** The three alternatives put to the owner — the Coordinator dashboard, contributor parity in
a browser, and the moderation console — are each recorded as open items on the roadmap rather than
declined, and each was passed over for a stated reason: the Coordinator's domain (workdays, routes,
claim/progress, live feed) exists in neither the server nor the app; contributor parity needs CORS
middleware that does not exist and a Sign-in-with-Apple-JS integration that `authOIDC`'s
fail-closed nonce check does not accommodate; the moderation console has no mock anywhere in the
handoff.

**Why the read surface went first, on the record:** it is the only web scope that is already
specified — W1 is transcribed at the same fidelity as the nineteen iOS screens — it needs no auth at
all, and it closes a live defect. `SharePresentation.swift:245` ships
`https://cypress.app/sf/tree/` as the share-card prefix and no such page has ever existed.

**2. It lives in this repository, at `web/`.** `server/` is the precedent — its own module, README,
Dockerfile and Fly deploy, coexisting without incident. The decisive argument was not precedent but
duplication: the web shares the design tokens, the seed pipeline, the city-pack manifest contract and
the golden wire fixtures with the app, and a second repository forks all four. This project has twice
been bitten by two copies of one number drifting apart, and the schema-version bullet in `CLAUDE.md`
exists because of it.

**The cost is one CI edit and it is not optional.** `testflight.yml`'s `plan` job classifies paths by
deny-list. A top-level `web/` matches neither `DOC_ONLY` (line 239) nor `NO_ARCHIVE` (line 279), so
without a carve-out every web-only commit runs the full `unit` + `ui` suite on `macos-26` runners and
mints a TestFlight build byte-identical to the last one — expiring the previous build and notifying
every tester. That is the failure class #212, #215 and #31 record, and the one the file already
guards `server/` against in a commented block explaining why. **The carve-out lands in the same PR
that creates the directory**, or it does not land at all.

**3. The unspecified web pages are built under a scoped constraint-21 exception**, in the shape of the
one M5 was granted for the six unreachable screen entrances. `SCREENS.md` §W1 draws four nav items and
says of them, verbatim, that their destinations are **NOT SPECIFIED**; DECISIONS constraint 21 makes
each of those a stop-and-ask, and four stop-and-asks would halt the round at its first page.

**The exception's boundary, stated so it can be spent rather than assumed:** it covers the four nav
destinations W1 itself draws and the supporting pages they require, and nothing else. Every invention
under it is written to `docs/rulings-pending/` in the round that makes it, for the owner's
ratification — the same discipline E98 recorded — and nothing is settled quietly inside a component
file. It does not cover the Coordinator dashboard, the moderation console, or any surface that
accepts a contribution.

**4. The runtime is TypeScript with server-side rendering, self-hosted on Fly.** Vercel remains ruled
out under R36 — its Hobby tier's non-commercial term against D14's paid org tier — and that ruling was
not reopened. Fly.io + Tigris is the platform, as it already is for `cypress-sync`; Cloudflare
Workers + R2 + D1 remains the named fallback.

### What this ruling does not decide

The orchestrator took five further decisions under the owner's instruction to run autonomously, each
recorded in the proposal's Decisions table as **W-5** through **W-9** and each overturnable on the
merits: the read path is the published city packs mounted read-only rather than a Postgres import or
browser-side SQLite; no raster basemap in v1; no photos on the public surface in v1; Astro with
`node:sqlite` and no React; and a proposed `run_web_tests.sh` / `verify_web_test_log.sh` pair under
`Tools/`, neither yet written, because judging a run by its exit code is this project's signature
failure mode and the platform does not change that.
