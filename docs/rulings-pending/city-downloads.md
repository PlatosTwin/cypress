# PENDING — City downloads: the app side of the R36 base layer (task #157, delegated)

*Unnumbered on purpose. The orchestrator splices this under the real next number at merge
(CLAUDE.md, Numbering). Written under the delegated design authority the owner granted this
surface — the download UI has no mock (DECISIONS constraint 21), so this ruling is the mock.
Everything in it is built from the app's existing vocabulary: the You tab's door-and-fact
sections, C10 rows, screen 17's row metrics, the unspecified-copy conventions
(`YouCopy`'s header comment). Nothing here is a store.*

## What this rules

R36 made cities downloadable files; R37 fixed their versioning (`s<schema>-r<content_rev>`,
immutable paths, `manifest.json` rewritten last). This ruling decides the app side: where city
management lives, what a city row says, what the affordances are, what happens on failure, and
which file the map actually draws from.

## 1. One inventory is attached at a time, and that is the load-bearing decision

Every read the app performs is qualified `seed.` against a single attached schema
(`SeedDatabase.schemaName`); two performance campaigns (E130, E139) tuned that path. Attaching
several city files at once would mean union reads across N schemas through the R*Tree — a
rewrite of the whole read layer with an unproven planner, which is not #157 and is not attempted
here.

So: **exactly one inventory is attached, always under the `seed` schema name, exactly the way
the bundle attaches today** (read-only, `immutable=1`, `SeedDatabase.attach`). The choices are
the **built-in inventory** (the fused bundled seed — the bootstrap R36 demoted it to) or **one
downloaded city file**. The reader picks; the default is built-in. Downloading never switches
the map by itself — `Use` does. The one exception: updating the city that is currently in use
re-attaches the new file, because the reader already made that choice and the update is the
same choice with fresher data.

Switching rebuilds the data layer (the composition root re-boots `DataLayer` and the view tree
under it). A downloaded file that fails to attach or validate is deactivated and the app falls
back to the built-in inventory rather than failing to launch — the row then simply shows the
city as installed but not in use.

Multi-city simultaneous attach is recorded as future work riding on a read-layer design, not as
a gap in this one.

## 2. Where it lives

- **You tab**, a new `City data` section between the export rows and Settings: one C10
  `IconTextRow` (title `Cities`, subtitle below) pushing a new `Route.cityDownloads`.
- The pushed screen is **Cities**: `ScreenHeader` back-circle screen, one card for the built-in
  inventory, then one card per city the manifest lists, in manifest order. That is the whole
  screen.

## 3. What a city card says

Card chrome is the You tab's setting-card idiom (surfaceCard fill, borderCool, screen-17 row
metrics). Contents, top to bottom:

- **Display name** from the manifest (`display_name` — a civic fact entered at publish, never
  derived on device).
- **Coverage**, only when not `"full"`: `Covers <coverage> only` (e.g. `Covers downtown only`).
- **State line**, one of:
  - not installed — the download size, e.g. `81 MB` (ByteCountFormatter over manifest `bytes`);
  - installed and current — `Installed · <version>` (the raw R37 version string; this is a
    data-management screen and the string is the fact);
  - update available — `Update available · <version> installed`;
  - downloading — `Downloading…` with a determinate progress bar;
  - failed — `Download failed. Nothing was changed.` (state reverts to whatever was true
    before the attempt);
  - schema too new — `Needs a newer app`, detail line
    `This city's data is a newer format than this app can read.`
- **Affordances** (compact buttons, never more than two visible):
  - not installed → `Download`;
  - installed, current, not in use → `Use` and `Remove`;
  - installed and in use → the state label `In use` (not a button) and `Remove`;
  - update available → `Update` and `Remove`;
  - downloading → `Cancel`;
  - schema too new, not installed → no button at all — an affordance that cannot keep its
    promise does not get drawn (R39's rule, borrowed);
  - schema too new but an older compatible version is installed → the installed copy keeps its
    `Use`/`Remove`; only the update is refused.

The **built-in inventory card** carries the title `Built-in inventory`, the subtitle
`Ships with the app and cannot be removed`, and `Use`/`In use` only.

The manifest is fetched when the screen appears and is never persisted; a fetch failure renders
the built-in card, every installed city from disk facts alone, and one line:
`Couldn't check what's available. Downloaded cities still work.` While the first fetch is in
flight the screen says `Checking what's available…`. One download runs at a time.

## 4. The contract with the bucket (data layer)

- **Base URL is app configuration** — `https://cypress-cities.t3.tigrisbucket.io`, a constant in
  the app, per R37.4; `base_url_hint` in the manifest is never read. All probes are GETs —
  Tigris has answered HEAD 200 beside GET 403 (server/README.md), so a HEAD reachability check
  is a false green by construction.
- **Manifest**: `GET <base>/manifest.json`, decoded strictly; `manifest_format != 1` is refused,
  unknown keys are ignored (R37 lets additive keys ride).
- **Schema gate, refused not deferred**: an entry whose `schema_version` exceeds the newest
  generation this build reads (`SeedDatabase.newestKnownSchemaVersion`, 14 today) is never
  downloaded. This is the fossil-install lesson pointed forward: "user_version N but build
  knows up to M" — a file from the future must be refused, not attached.
- **Download**: to a temp path in the library's own staging directory, never the final layout.
  **sha256 (CryptoKit) and byte count are verified against the manifest entry before anything
  else happens**; a mismatch deletes the temp file and changes nothing. Only a verified file is
  moved — an atomic same-volume rename — into the on-device mirror of the bucket's immutable
  layout: `Application Support/Cypress/cities/<id>/<version>/<id>.sqlite`. Disk is the record
  of what is installed; there is no parallel bookkeeping to disagree with it.
- **Update** = download-new-then-prune: the new version lands at its own immutable path,
  verified, before the old version's directory is deleted — the same "rewritten last" discipline
  the manifest itself uses (R37.2). A failed update leaves the installed version untouched.
- **The active choice** is a marker file (`cities/active-city`) holding the city id; absent
  means built-in. At boot the marker is resolved and the file **re-validated before attach**
  (seed-shape introspection plus the `publish_schema_version` gate read from the file's own
  `seed_meta` — the manifest said 14, but the file testifies for itself); a dangling or invalid
  marker is cleared and the built-in inventory attaches.
- **No schema migration.** The writable database is untouched by all of this; installed-city
  state lives on disk and in one marker file.
- **Attribution travels inside the file** (R37.3 keeps `inventories` and `seed_meta` in every
  city file), so the existing city-record surfaces (`CityRecordPresentation`) state the right
  source for whichever inventory is attached, with no new attribution UI.

## 5. Seed-coverage constants become measured facts (R36 consequence c)

`MapYearFilterCopy.undatedShareOfSeed` (0.8078) is a fact about the fused bundle, and it is
wrong for any single-city file (SF alone is 0.7397; San Jose alone is 0.9958 — E175/E176
already proved this constant moves). So the share of undated rows is **measured from the
attached inventory at open** (one aggregate beside `seedHasSoftDeletedTrees`'s existing
measurement) and the caveat sentence is derived from the measured share:
`About <X in Y> trees have no recorded planting date—none of them can appear under a year.`,
where `<X in Y>` is the nearest of a fixed fraction table. The fused bundle must produce
today's sentence verbatim ("4 in 5") — that equivalence is pinned by test, which keeps this a
generalization and not a copy change.

## 6. What this ruling refuses

No store furniture: no prices, ratings, screenshots, hero art, or recommendations. No
auto-download and no background manifest refresh in #157 — R36's "background-refreshes when the
manifest says a newer version exists" needs a background-task design and lands with its own
ticket. No invented city names or coverage words: every civic string on the screen comes from
the manifest or the file, both of which got them from `publish_cities.py`'s hand-entered table.
