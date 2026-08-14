# City data distribution — regional packs, freshness, and the download screen that lies

**2026-08-14. A design proposal, written before the NYC ingest commits to a unit. No production
Swift, no publisher change, no migration, no schema change in any version space.**

> **The owner's question, verbatim.** Asked whether NYC should be ingested whole-city or
> borough-by-borough:
>
> *"We need whole city from the start, but we also must be very smart about performance. there's
> already the option to download city dbs (though that screen needs work, because i can download
> from sf and sjc even though those ostensibly ship with the app...), so one option is to add
> downloads by borough, so on open, app detects where you are, and if there's a download covering
> that area, asks if you want to download. but we also need to be thoughtful about how the api will
> be used. we do not want to be shipping stale dbs per build. eventually everything will need to be
> sitting on a server and updatable without shipping a new seed. how does google maps do this?
> probably needs more thought, tbh, before we ingest."*

Every number below was read out of this repository at `e36395e`, measured against the live bucket on
2026-08-14, or produced by an experiment whose method and calibration are in §12. Where this document
states what a constant is, it was read from the declaration.

**Three things the owner should read before the rest.** §3 — the SF/San Jose defect has three causes,
not one, and the deepest is that the app cannot read its own bundle. §6.2 — the recommended first move
costs no schema change in any space and can land before the NYC ingest picks a unit. §8 — this
proposal names **three** independently-advancing version numbers, not the two `CLAUDE.md` warns about.

---

## 0. The five questions inside that paragraph

| The owner's words | The question | Answered in |
|---|---|---|
| *"i can download from sf and sjc even though those ostensibly ship with the app"* | Why does the screen offer what the bundle already holds? | §3 |
| *"add downloads by borough"* | Is a borough a legitimate published unit, and what does it cost? | §5, §6 |
| *"on open, app detects where you are… asks if you want to download"* | What is the data-side cost of a location-triggered offer? | §4.4, §7 |
| *"we do not want to be shipping stale dbs per build… updatable without shipping a new seed"* | What is the update path, and is a delta possible? | §6.4, §12.3 |
| *"how does google maps do this?"* | What do the majors do, and what transfers? | §4 |

One of those five is already solved and the record does not say so clearly: **published city files
plus a rewritable manifest is exactly "sitting on a server and updatable without shipping a new
seed," and it has been live since 2026-08-06.** What is *not* solved is that the bundle is also a
copy of that data, is shipped per build, and is invisible to the app that carries it. §3 is that
problem; §6 is the sequence out of it.

---

## 1. What is already true, stated once

### 1.1 The bundle

`Cypress/Resources/cypress-seed.sqlite` is **108,249,088 bytes**, 26,428 pages of 4,096 bytes,
198,625 trees across two id spaces. Read out of the file: `id_spaces` holds `sf` and `us-ca-sj`;
`dim_city` holds `San Francisco` and `San Jose`; `seed_meta.id_spaces_in_file` is `sf,us-ca-sj` and
`seed_meta.sj_ship_extent` is `downtown`.

Storage, by `dbstat`: **72.7 MiB of table pages, 30.5 MiB of index and R\*Tree pages** — indexes are
just under 30% of the file. The shared authored species tables (`species`, `species_map`,
`species_trigrams`) total **0.49 MiB**, which matters in §5: R37.3 keeps them whole in every city
file, and the duplication that sounds expensive is half a megabyte.

R36's binding consequence (a) already demoted this file: *"the 103 MB bundled seed becomes a
bootstrap, not the distribution."* R43 §1 built on that — the built-in inventory is *"the bootstrap
R36 demoted it to."* **Nothing in the app acts on that demotion yet.** The bundle is still a full,
current copy of both published cities, and §3 is the visible consequence.

### 1.2 The published catalog

`GET https://cypress-cities.t3.tigrisbucket.io/manifest.json`, fetched 2026-08-14:

| id | display name | coverage | trees | schema | version | bytes |
|---|---|---|---:|---:|---|---:|
| `sf` | San Francisco | full | 145,837 | 16 | `s16-r2026-07-31-c9a440b2` | 80,855,040 |
| `us-ca-sj` | San Jose | downtown | 52,788 | 16 | `s16-r2026-07-31-c9a440b2` | 28,229,632 |

Plus `source_seed`: the fused 108,249,088-byte seed at `seed/c9a440b2/cypress-seed.sqlite`, which
`Tools/fetch_seed.sh` resolves and hash-verifies on every CI run.

**The published catalog is, by construction, exactly the set of cities in the bundle.**
`Tools/publish_cities.py` takes `SELECT DISTINCT id_space FROM trees` over the fused seed and
publishes one file per space. There is at present no way for a city to be published that is not also
bundled, and no way for a city to be bundled that is not also published. That identity is the root of
§3 and the thing §6 breaks.

**A finding that contradicts three errata entries.** E209 shape B3, E213 and E214 each record that
`CityManifest.City` *"carries no center or bbox to derive one from,"* and E214 calls the fix *"a
different, wider ticket."* That is true of the Swift type and false of the artifact:
`Tools/publish_cities.py` has emitted `bbox` (min/max lat and lon) and `centroid` for every city
**since the original #156 commit**, and both keys are in the manifest live right now — San Francisco's
bbox is `lat [37.70802, 37.819956]`, `lon [-122.511131, -122.366622]`; San Jose's is
`lat [37.30500, 37.36999]`, `lon [-121.93000, -121.85500]`, which is E176's `SJ_SHIP_WINDOW` arriving
in the manifest untouched. `CityManifest.City` simply does not decode them, and R37.4's tolerance for
additive keys is why it does not have to. **The data-side blocker named in those three entries does
not exist. The client-side gap is two `Decodable` properties.** §7 spends that finding.

### 1.3 The download path, and what it was sized for

`Cypress/Data/Cities/CityDownloader.swift` does the whole job in `URLSession.shared`:
`session.bytes(from:)`, a `for try await byte in bytes` loop appending into a 512 KiB buffer, SHA-256
as it goes, size and digest checked against the manifest entry before the file is handed to
`CityLibrary.install(verifiedFileAt:id:version:)` for an atomic rename. It is careful, and it is
sized for 81 MB. For a file five times larger, four properties are worth naming now rather than
discovering later:

- **No resume.** A dropped connection restarts from byte zero. There is no `Range` request and no
  partial-file state; the temp file is deleted on any error, deliberately (`CityDownloader`'s stated
  contract).
- **No background transfer.** `URLSession.shared` is not a background-identifier configuration, so
  the transfer is bound to the foreground app. `Cypress/Data/RemoteAccess.swift` is the only place in
  the app that constructs a configuration at all, and it constructs `.ephemeral`. §4.5 has what the
  fix costs and the one sharp edge it carries.
- **No free-space check.** Nothing under `Cypress/` calls a disk-space API, and
  `Cypress/Resources/PrivacyInfo.xcprivacy` says so in a comment that is itself a small design
  constraint: adding one means declaring `NSPrivacyAccessedAPICategoryDiskSpace`, and that file's own
  instruction is to re-run the greps rather than declare defensively.
- **Byte-at-a-time iteration.** `for try await byte in bytes` is one `AsyncSequence` element per
  byte. At 81 MB it is tolerable; nobody has measured it at 500 MB and this document does not claim
  it is or is not a problem — only that it has never been asked the question.

R43 §3 also fixes one download at a time, and R43 §6 refuses auto-download and background manifest
refresh outright, pointing them at their own ticket. That refusal is still in force and §7 respects
it.

### 1.4 What the map costs today

`Cypress/Data/Store/TreeQueries.swift` records the figure this proposal leans on: the whole-city
clustered map query is **104 ms over 195,309 rows**, and it is that fast only because the projection
stays inside `idx_trees_lat_lon` — adding one column the index does not carry took it to 355 ms
(a cluster representative) or 427 ms (`deleted_at`). The pin query is bounded by a viewport grid
budget, so it does not scale with corpus size; **the clustered aggregate does.**

### 1.5 The version spaces, read from the code

- `AppSchema.currentVersion` — the writable database's `PRAGMA user_version`, the maximum
  `Migration(version:)` in `Cypress/Data/Store/AppSchema.swift`: **15**, *"applying a mutation
  locally and sending it are two facts."*
- `SeedDatabase.newestKnownSchemaVersion` — the published seed/city-file generation, R37's `s<n>`, in
  `Cypress/Data/Store/SeedDatabase.swift`: **16**. `Tools/publish_cities.py`'s `SEED_SCHEMA_VERSION`
  agrees at 16, and the live manifest says 16 for both cities.
- `CityManifest.knownFormat` / `MANIFEST_FORMAT` — **1**. §8 argues this is a third version space and
  should be named as one.

---

## 2. The numbers this decision turns on

### 2.1 Bytes per row, measured on the published artifacts

Two published city files at the same schema generation give a two-point fit:

```
sf        145,837 trees   80,855,040 bytes
us-ca-sj   52,788 trees   28,229,632 bytes
marginal  (80,855,040 - 28,229,632) / (145,837 - 52,788) = 566 bytes/row
intercept  28,229,632 - 566 x 52,788 = -1.7 MB
```

The intercept is negative and small, which is the honest way of saying **there is no meaningful
fixed overhead per city file** — consistent with §1.1's measurement that the shared species tables
are 0.49 MiB. E176's *"~535 bytes/row"* and the NYC survey's *"roughly 540 bytes/row"* are the same
number seen from the fused seed. **This document uses 550 bytes/row** and states it as an estimate
everywhere it is used.

### 2.2 New York, by borough — measured, with its provenance stated

`docs/investigations/nyc-street-trees.md` establishes the totals: 899,094 currently-standing tree
points (`TPStructure='Full'`) in `Forestry Tree Points`, and 945,458 `Populated` rows in the second
dataset, `Forestry Planting Spaces`, which is where the borough lives (`boroughcode`). The survey did
not break either down by borough. One aggregate query against Socrata on 2026-08-14 does:

| borough | populated planting spaces | all planting spaces | est. standing trees | est. pack, raw | est. pack, brotli |
|---|---:|---:|---:|---:|---:|
| Queens | 322,941 | 371,611 | ~307,100 | ~169 MB | ~37 MB |
| Brooklyn | 241,767 | 283,820 | ~229,900 | ~126 MB | ~28 MB |
| Bronx | 141,993 | 163,353 | ~135,000 | ~74 MB | ~16 MB |
| Staten Island | 135,166 | 154,047 | ~128,500 | ~71 MB | ~16 MB |
| Manhattan | 103,087 | 118,365 | ~98,000 | ~54 MB | ~12 MB |
| *(no borough code)* | 504 | 513 | ~500 | — | — |
| **total** | **945,458** | **1,091,709** | **~899,100** | **~495 MB** | **~109 MB** |

**Read the provenance before the numbers.** The two count columns are measured — they reproduce the
survey's own 945,458 and 1,091,709 exactly, which is the calibration that says the query asked the
right question. The three estimate columns are *derived*: standing trees are scaled by the
899,094/945,458 = 0.951 ratio the survey established, and bytes by §2.1's 550 bytes/row and §2.3's
measured brotli ratio. **A borough's populated planting spaces and its standing tree points are not
the same set** — the survey says so, and reconciling them is an ingest question. The parallel
`feat/nyc-ingest` measurement will replace the three estimate columns with real ones; the design
below does not turn on which of them is right, only on their order of magnitude and their **spread**,
which is 5.7:1 between Queens and Manhattan.

Two consequences, stated flatly:

- **Whole NYC in the bundle is dead.** 108 MB + ~495 MB is a ~600 MB `.app`. E176 already rejected
  265 MB as *"past Apple's cellular-download ceiling and absurd for a local beta,"* and that was
  before the NYC survey existed. §4.5 sharpens why that ceiling binds here and nowhere else: it is an
  App Store setting about **app** downloads, so it bounds the bundle and does not reach an in-app
  download at all.
- **Whole NYC as one downloadable file is a ~495 MB download that must be re-taken in full every
  time it is refreshed.** The source updates every two weeks (`docs/investigations/nyc-street-trees.md`
  §1.1: *"Every 2 weeks"*, automated updates enabled). That is the freshness problem the owner named,
  in its most expensive form.

**And the refresh is tiny, which is the whole reason §6.4 and §4.3 exist.** Measured on the live
layer's own `updateddate` column on 2026-08-14: **17,388 of 1,121,106 rows moved in 30 days — 1.6%**
(49,517 in 90 days, of which 10,372 are genuinely new). A fortnightly refresh is therefore on the
order of **8–9k rows, roughly 5 MB of row data**. Re-downloading ~495 MB to deliver ~5 MB of change
is the ratio the design has to answer for, and every option below is graded on how close it gets to
it.

### 2.3 What this data compresses to — measured

R37.4 reserved compression as an additive manifest key and estimated *"gzip (~2x)."* **That estimate
is low by three-quarters.** Measured on the published `sf` city file (80,855,040 bytes, sha256
verified against the manifest entry before compressing — §12.1) and on the bundled fused seed:

| | `sf` city file | fused seed | ratio |
|---|---:|---:|---:|
| raw | 80,855,040 | 108,249,088 | 1.00x |
| gzip -6 | 22,928,560 | 30,528,117 | **3.53x / 3.55x** |
| brotli -q 9 | 17,749,806 | 24,192,368 | **4.56x / 4.47x** |
| zstd -19 | — | 22,337,689 | 4.85x |

**Brotli is the recommendation and the reason is the dependency rule.** Apple's `Compression`
framework ships `COMPRESSION_ZLIB`, `COMPRESSION_LZFSE`, `COMPRESSION_LZ4` and `COMPRESSION_BROTLI`
in the OS; zstd would be a vendored third-party library, which the zero-external-dependencies line in
`CLAUDE.md` does not allow for a 6% gain over brotli. Brotli takes San Francisco from 81 MB to
**17.7 MB** on the wire, and NYC-whole from ~495 MB to **~109 MB**.

**Compression buys bandwidth, not disk.** SQLite cannot `ATTACH` a compressed file, so the device
still needs the raw bytes at rest plus transient space during decompression. Every disk figure in this
document is the raw one, deliberately.

### 2.4 What a bigger corpus costs the map

§1.4's clustered aggregate is a covering-index scan, so it is linear in rows in the viewport. Scaling
104 ms over 195,309 rows:

| attached inventory | rows | est. whole-inventory cluster query |
|---|---:|---:|
| today (SF + San Jose bundle) | 198,625 | 104 ms *(measured)* |
| Manhattan pack | ~98,000 | ~52 ms |
| Brooklyn pack | ~229,900 | ~122 ms |
| Queens pack | ~307,100 | ~163 ms |
| NYC whole | ~899,100 | **~480 ms** |

These are extrapolations from one measured point, not measurements, and they should be re-measured
against a real trial seed before anyone treats ~480 ms as a fact. But the *shape* is the design
argument and it does not depend on the constant: **a regional unit keeps the hottest query in the app
inside the envelope two performance campaigns bought it, and a whole-NYC unit does not.** This is a
reason to prefer regional packs that is independent of download size, and it is the one the owner's
*"very smart about performance"* is most likely reaching for.

### 2.5 What it costs the toolchain

- **`Tools/setup_worktree.sh`** copies the seed into two directories per worktree — 216 MB of copying
  per agent today. It copies **the fused bundle**, and under every option in §5 the bundle does not
  grow, because NYC never enters `Fixtures/seed/cypress-seed.sqlite`. **The per-worktree cost is
  unchanged by NYC in every option except A′** (bundling NYC), which no option recommends. This is
  worth stating because `docs/investigations/nyc-street-trees.md` §5 flags worktree copies as a cost
  of a merged seed, and a distribution design that keeps NYC out of the fused seed retires that
  concern rather than paying it.
- **CI** runs `Tools/fetch_seed.sh` on every job of every non-prose run, downloading and hashing the
  fused seed from the bucket. Same conclusion, same reason: unchanged, as long as NYC is published
  rather than fused. If NYC ever *were* fused, this cost would land on every CI job of every run,
  which is a second, quieter argument against A′.
- **The publisher.** `Tools/publish_cities.py` byte-copies the fused seed once per output file and
  then `DELETE`s and `VACUUM`s. Today that is two copies of 108 MB. A five-borough NYC would be five
  copies of whatever the fused NYC input is — an ingest-machine cost, not a user-facing one, but it
  is the step that decides §12.3's answer about deltas.

---

## 3. The download screen that offers what the bundle already holds

### 3.1 What it does

`CityDownloadsModel.rows` builds the screen as `[.builtIn] + manifest.cities.map { … }`, and the
per-city state comes from `CityInstallState(published:installedVersion:)` where `installedVersion` is
`library.installedCities().first { $0.id == city.id }?.version` — **the downloaded library only**.
`CityLibrary` reads `Application Support/Cypress/cities/`; the bundle is not in it and has no entry
there by design.

So for `sf`: nothing on disk under `cities/sf/`, therefore `installedVersion == nil`, therefore
`.notInstalled`, therefore `CityDownloadsPresentation`'s `decide` returns
`(CityDownloadsCopy.size(city.bytes), nil, [.download])` — **`81 MB` and a `Download` button, for
145,837 trees the app is drawing on the map at that very moment.** The owner's report is exact.

### 3.2 Why — three causes, and only the first is a bug

1. **The app cannot read its own bundle's contents.** Nothing anywhere asks the bundled seed which
   cities it holds. `CityLibrary` was written to be the whole record of what is installed — *"Disk is
   the record"* — and that was right for downloads and silently wrong for the bundle, which is
   installed in every sense the reader cares about and in none of the senses the directory layout can
   express.
2. **The publisher's unit is the id space, and the bundle's contents are the same id spaces.**
   `Tools/publish_cities.py` publishes `SELECT DISTINCT id_space FROM trees` from the very file that
   ships in the app. Publishing the bundle's own contents is not a defect — R37.3 makes city files
   narrowed copies of the fused seed on purpose, and `Tools/fetch_seed.sh` and CI depend on the fused
   seed being published too. It is a defect only in combination with (1).
3. **R43 §3 has no state for "you already have this."** The ruling enumerates six row states —
   not-installed, installed-current, update-available, downloading, failed, needs-newer-app — and
   *bundled* is not among them, because when R43 was written the built-in inventory was one
   undifferentiated card rather than a set of cities. The vocabulary genuinely does not contain the
   sentence the screen needs to say.

**And a fourth consequence nobody has hit yet, because it needs a user to press the button.** If the
reader does download `sf`, they now hold 81 MB of a city they already had, the screen shows two rows
for San Francisco (`Built-in inventory` and `San Francisco`), and `Use` switches between two copies of
the same data with no way to tell them apart. That is the same defect one step further along, and it
is the one that would generate a support question.

### 3.3 What the honest screen says, and what it costs

The fix needs one new fact on the device: **which cities the bundle holds, and at what content
revision.** Both are already inside the bundled file, and can be derived by the publisher's own rule
rather than a new one:

- **Which cities** — `SELECT id FROM id_spaces` on the attached bundle. Returns `sf`, `us-ca-sj`.
- **At what revision** — `content_rev_for(space)` in `Tools/publish_cities.py` is
  `max(seed_meta.inventory_<tag>_snapshot_on)` over the tags whose `inventory_<tag>_id_space` is that
  space. Run against the bundled seed by hand it yields `2026-07-31` for both, which is exactly the
  `r2026-07-31` in both published version strings. **The rule is already stated once, in the
  publisher; the app would be applying the same rule to a different file.**
- **Coverage** — `seed_meta.sj_ship_extent` is `downtown`, already the source of the manifest's
  `coverage` field through `COVERAGE_KEYS`. R37's trailing clause anticipated this: when a third city
  lands, `build_seed.py` should write `coverage_<id_space>` keys and the shim retires. NYC is that
  third city.
- **Display name** — since s16 the file carries `dim_city.display_name`, so the bundle can name its
  own cities without the manifest and without inventing anything (constraint 15 satisfied: the string
  is authored data read out of a file, not composed on device).

**Deliberately not part of the comparison: `build_id`.** R60's segment is the first 8 hex of the
source seed's sha256, so a bundled city cannot compute its own version string without hashing 108 MB
at launch. The bundle row should therefore compare on **`content_rev` alone** — a date, which orders
— and say what it actually knows. Concretely, the row states:

- published `content_rev` == bundled `content_rev` → *included in the app, record as of this date*,
  and **no `Download` affordance at all**. This is R43 §3's own principle, stated there for the
  schema-too-new case: *"a button that cannot keep its promise is not drawn."*
- published `content_rev` later → *a newer record is available*, and `Download` is honest, because it
  now buys something. The downloaded copy shadows the bundled one through the existing `active-city`
  marker; no new mechanism.
- published `content_rev` earlier, or the city is bundled and unpublished → included in the app, no
  affordance. (This is reachable: it is what the two weeks after a bundle build look like if a
  publish is skipped.)

**Cost: zero schema change in any of the three version spaces, zero publisher change, zero manifest
change.** It is a read of a file the app already has open, plus row states R43 does not yet enumerate
— which makes it a ruling amendment, not a mock question (§9).

### 3.4 A smaller lie found in the same file

`CityDownloadRow.installedOffline` titles the row with the raw id — `sf`, `us-ca-sj` — and its comment
explains why: *"the manifest carries the display name and it is unreachable; the id is the one name
the disk actually knows, and inventing a prettier one is constraint 15's line."* That reasoning was
correct when it was written and stopped being correct at s16: **`dim_city.display_name` is inside
every published city file**, narrowed to that city's single row by `Tools/publish_cities.py`. The disk
does know the name now. An offline reader is currently shown `us-ca-sj` where the file on their own
phone says `San Jose`. Small, and it belongs to the same fix.

---

## 4. What the majors do

*(§4 is the one section whose evidence is not in this repository; see §12.4 for when it was fetched
and the standing instruction to re-fetch rather than quote. Where a claim could not be verified from
a primary source it is marked, because for this question the undocumented parts are where the
interesting mechanisms live.)*

### 4.1 Google Maps and Apple Maps — the interaction is documented, the transport is not

**Google Maps offline areas** are a user-adjusted rectangle: pick a place, "Download offline map," or
"Select your own map" and drag. Google documents an auto-update behavior — *"When your offline maps
expire in 15 days or less and you're connected to Wi-Fi, Google Maps tries to update the area
automatically"* — and a settings toggle for it. **Google does not document the total validity period,
and does not document whether an update is a delta or a re-download.** The widely-quoted numbers (30
days, one year, 120,000 km² per area) are third-party and unverified. Google's patents describe
per-tile versioning and incremental compilation, but a patent is not evidence about a shipping build.
The on-device format is proprietary and, under the Maps Platform terms, caching or offline use of
tiles is prohibited anyway — so there is nothing here to copy even if it were legible.

**Apple Maps offline maps** (iOS 17+) are the same interaction: drop a pin, download, resize; **the
size is shown before the download and per saved map**; automatic updates are on by default with a
Wi-Fi-only toggle; there is no documented expiry, only an opt-in "Optimize Storage" that removes
unused maps after an unstated period. Apple states the *effect* of an update — *"kept up to date if
things like a business or street name change"* — and never the transport. A business-name change
propagating implies something finer-grained than area re-download, and it is unverifiable.

**What transfers:** the interaction, not the mechanism. Both show the size before the commitment,
which R43 §3 already does (`81 MB` on the not-installed row). Both make updating automatic and
Wi-Fi-conditioned, which R43 §6 deliberately deferred to its own ticket. Neither is evidence for or
against any delta design.

### 4.2 Organic Maps — the manifest shape Cypress is about to need

Open source, so the mechanism is readable rather than inferred.

- **The manifest is a recursive tree.** `countries.json`, ~284 KB, one root node with children; each
  node carries `id` (which doubles as the filename), `s` (exact byte size), `h` (an integrity hash),
  and `g[]` (children). 1,323 nodes, 1,166 downloadable leaves, maximum depth 3. **This is exactly the
  shape §6's Stage 1 needs** — a city with regions under it is a two-level version of the same tree,
  and Organic Maps has been running the three-level version for years.
- **Granularity is ad hoc and driven by size, not by administrative tidiness.** Whole small countries
  (`Luxembourg`, 44.9 MB), whole US states (`US_Vermont`, 59.1 MB), sub-state metros
  (`US_Texas_Dallas`, 208.5 MB), and invented splits where geography demanded them
  (`Algeria_Coast`). Median leaf: 65.6 MB. **A New York borough at 54–169 MB sits inside that
  distribution, and Queens at ~169 MB is smaller than Organic Maps' Dallas leaf.** That is the
  strongest external evidence available for open question 1.
- **Versioning is a date-stamped path**: `maps/<YYMMDD>/<name>.mwm`, with the manifest served per
  version at the same prefix — the same immutable-path discipline as R37.2, arrived at independently.
- **Updates are whole-file re-downloads**, and this is the cautionary data point of the whole survey:
  the bsdiff/courgette machinery is *in the tree*, with a `diffs/<ver>/<diffver>/<name>.mwmdiff` URL
  scheme wired up — **and it ships disabled**, the diff URL defined as an empty string and the
  diff-scheme loader commented out. A serious project built the byte-diff answer to precisely this
  problem and then turned it off.
- **Location → pack is a separate 5.9 MB polygon file**, and the algorithm is bbox-reject followed by
  a real point-in-polygon test. §7's second constraint is not a Cypress quirk; it is what everyone who
  has built this feature discovered.

### 4.3 OsmAnd — the only shipping incremental scheme, and it never patches anything

- **Manifest**: `indexes.xml`, ~2.5 MB, per entry a name, a date, a timestamp, a zipped and an
  unzipped size, and a `<deleted_map>` element as the retire-this-file channel. **No per-file hash —
  freshness is by timestamp alone.** Cypress's manifest is strictly stricter (sha256 per file,
  verified before a byte is kept) and should stay that way.
- **Updates, documented**: full maps monthly; "live updates" generated every 15 minutes server-side
  and downloadable hourly, daily or weekly, costing *"about 2–4% of the full map size per month"* and
  — the sentence that matters — *"applied on top of the downloaded map and do not replace the full map
  file."*
- **Mechanically these are additional whole files, not patches.** An overlay is another `.obf`,
  gzipped, 3–5 MB against a ~122 MB base, landing in a `live/` directory and read as an *extra index*
  alongside the base. A monthly rollup file supersedes that month's dailies. **Deletions travel as a
  tombstone**, `osmand_change=delete`, because an append-only overlay cannot remove a row from a file
  it does not touch.
- **The one thing the survey could not verify** is how OsmAnd's *read* path resolves a base object
  against an overlay's tombstone. That is exactly the part Cypress would have to design rather than
  copy.

**This is the most transferable design in the survey**, and it maps onto Cypress with unusual
directness: an overlay is another SQLite file, the base stays immutable and read-only and
sha256-verified, no `VACUUM` problem exists because the base is never rewritten, and the whole thing
runs on a dumb bucket. Its cost is precisely Option C's cost — the query layer must read across more
than one attached file — which is why §6 puts them in the same neighborhood of the sequence.

**And Cypress now has the churn number to size it.** The NYC layer's own `updateddate` column shows
**17,388 of 1,121,106 rows moved in 30 days — 1.6%** (49,517 in 90 days; 10,372 genuinely new). A
fortnightly refresh is therefore on the order of **8–9k rows, ~5 MB raw at 550 bytes/row**, against a
~495 MB city or a ~126 MB borough. **An overlay scheme is worth roughly 20x over a borough
re-download and 100x over a whole-city one.** Two cautions carried from the survey: Socrata's
`:updated_at` is useless here (every row shares one timestamp because the publish rewrites the table
— use the dataset's own `updateddate`), and **deletions are not visible through either column**, so
a tombstone channel would need a full id-set diff at ingest. That is a real cost and it is the same
cost OsmAnd pays.

### 4.4 PMTiles, and querying a file you have not downloaded

**PMTiles** is the cloud-optimized single-file tile archive: a 127-byte header, a root directory that
must fit in the first 16 KB, and columnar delta-encoded directories, so *"nearly any map tile can be
retrieved in at most two additional requests"* against **plain object storage with `Range` GETs and
no compute** — and Tigris is a named supported backend. It is directly relevant to how Cypress hosts,
and directly *irrelevant* to what Cypress stores: PMTiles has no key space other than z/x/y, and a
tree inventory is row-oriented. Its own docs are blunt about updates: *"It is not possible to update
an archive in-place without re-writing the entire file, similar to CSV, JSON and Parquet."* The
planet build is republished daily as a fresh complete file. Its `makesync`/`sync` subcommands are
rsync-style *pull* — a client refreshing a local copy over range requests, not a patch anyone uploads.

**The genuinely interesting adjacent idea: SQLite itself is range-request-friendly.** A VFS that
serves pages over HTTP `Range` lets an indexed query walk only the B-tree pages it needs; the best
known demonstration reports ~1 KB transferred against a 670 MB database on static hosting. Against
Cypress's shape that would mean **querying a city file without downloading it** — a genuine fifth
architecture sitting between Option B and Option D. It is not recommended here, for three reasons
worth recording rather than re-deriving: it requires a custom SQLite VFS (a real piece of systems
code, against a zero-dependency line); it makes every map pan a network round trip, which is R36's
shape-B objection arriving through a side door; and offline stops working, which is the property this
app's whole base layer exists to protect. **It would, however, be an excellent way to let a reader
*preview* a city they have not downloaded** — which is a Stage 2 idea, not a Stage 1 one.

### 4.5 The iOS constraints, corrected

Three things the record here gets subtly wrong or has not caught up with.

- **The 200 MB threshold is an App Store setting about app downloads, not a `URLSession` limit.** It
  lives in Settings → App Store → Cellular Data → App Downloads. E176 invoked it correctly against a
  265 MB *bundle*. It is the reason Option A′ is dead and **it is not a constraint on Option A's
  495 MB in-app download at all.** Stated carefully, because the evidence is negative: there is no
  size threshold anywhere in `URLSession`'s API — the cellular controls are all boolean — but Apple
  nowhere states that the App Store limit does not reach in-app downloads. Strongly-supported
  inference, not a citable Apple sentence.
- **On-Demand Resources is deprecated as of iOS 27**, superseded by **Apple-hosted Background
  Assets**, and the replacement changes the answer to a question this project had settled. ODR asset
  packs *"cannot be updated independently of a new app version"*; Background Assets packs **can** be
  uploaded to App Store Connect separately from a build, at up to 200 GB and 200 packs per app
  record, and devices download them separately. **That is a real alternative host for city files and
  it should be refused for a stated reason rather than by omission:** an asset-pack upload still goes
  through App Store Connect, so a fortnightly data refresh would be gated on Apple's review queue —
  which is exactly the coupling between *shipping* and *updating* that the owner's paragraph is trying
  to break. Tigris keeps that coupling severed. Worth revisiting only if bucket egress ever becomes a
  cost worth trading a review gate for.
- **Background `URLSession` is the fix for §1.3's second bullet, with one sharp edge**: transfers
  continue while the app is suspended or terminated, **but the system cancels them if the user swipes
  the app away from the multitasking screen**, and a transfer *started* while the app is in the
  background is always discretionary regardless of `isDiscretionary`. So the download must be
  foreground-initiated on a background-identifier configuration. Resume data — §1.3's first bullet —
  has documented preconditions Cypress already half-satisfies: HTTP(S) `GET`, an unchanged resource,
  an `ETag` or `Last-Modified`, **byte-range support on the server**, and a temp file the system has
  not purged. R37.2's immutable versioned paths make "unchanged resource" true by construction, which
  is a nice consequence of a rule adopted for a different reason.

### 4.6 What actually transfers

1. **Nobody bundles the data in the app.** Organic Maps and OsmAnd ship an app with no maps at all.
   Cypress's 108 MB bundle is the outlier, R36 already called it a bootstrap, and §3 is what it costs
   to have a bootstrap the app cannot see.
2. **Everyone's unit is a named region with a stated size, discovered through a versioned manifest.**
   Cypress has all three today. Stage 1 is not a new idea; it is the second level of a tree everyone
   else already has.
3. **Region size, not administrative tidiness, decides the split.** A borough is a legitimate unit
   because it lands in the same size band as everyone else's leaves.
4. **The only shipping incremental scheme adds files rather than patching them**, at a cost per month
   that matches Cypress's measured NYC churn to within a factor of two.
5. **The byte-diff route has a negative result attached to it from a project that built it.** Combined
   with §12.3's `VACUUM` measurement and bsdiff's ~200 MB client-side memory requirement for a file
   this size, that is enough evidence to stop proposing it.
6. **Cypress is already stricter than both open-source comparables on integrity and on refusing an
   incompatible generation.** Nothing in this proposal should relax either.

---

## 5. Four options

Each is stated as: what ships in the bundle, what downloads, how an update reaches a reader, what
happens offline, what it does to each version space, what it costs the server and the toolchain.

### Option A — status quo, and NYC is one more city file

**Bundle:** unchanged (SF + San Jose, 108 MB). **Downloads:** one `us-ny-nyc` file, ~495 MB raw
(~109 MB brotli). **Updates:** republish, new `version` string, `Update available`, full re-download.
**Offline:** unchanged — one inventory attached, everything local. **Server:** Tigris egress only;
~495 MB per updating reader per refresh. **Version spaces:** *nothing moves.* NYC is one more
`id_space`, which R18 already provides for and R24 §1 already made room for
(`UNIQUE (id_space, external_ref)`). **Toolchain:** unchanged.

*For:* zero new mechanism. It is what the code does today, and the NYC ingest could target it with no
distribution work at all.
*Against:* a ~495 MB download over a path with no resume, no background transfer and no free-space
check (§1.3); a ~480 ms whole-inventory cluster query (§2.4); and a fortnightly refresh cadence that
makes ~495 MB the *recurring* cost, not the one-off one. It answers the owner's *"whole city from the
start"* and none of the rest of the paragraph.

### Option A′ — NYC in the bundle

Named only to record that it was considered and refused. ~600 MB `.app`, past every threshold E176
already refused at 265 MB; 5x the per-worktree copy and the per-CI-job fetch; and it is the *"shipping
stale dbs per build"* the owner explicitly does not want. **Refused.**

### Option B — the published unit becomes a region; one is attached at a time

**Bundle:** unchanged. **Downloads:** NYC publishes as five borough packs (§2.2) and, optionally, a
whole-city pack for readers with the disk. SF and San Jose keep publishing as single-region cities —
a city with one region is the same shape, not a special case. **Updates:** per region, so a Brooklyn
reader re-takes ~126 MB (~28 MB brotli), not ~495 MB. **Offline:** unchanged in kind, changed in
degree — R43 §1's *"exactly one inventory is attached"* survives untouched, which is what makes this
option small. **Server:** Tigris egress, and a materially smaller bill than A because readers take
their borough rather than the city.

*What it costs, honestly:*

- **A borough boundary becomes a data cliff.** A reader with Brooklyn attached who walks over the
  Williamsburg Bridge sees an empty map. There is already ratified copy for this exact state — the
  screen-01 out-of-coverage line *"Trees may well stand here, unlisted."*, whose ruling explicitly
  says the trigger fires *"outside a downloaded city's window"* — so the app degrades honestly rather
  than silently. It is still a bad afternoon in a city where crossing a borough line is a normal
  commute. This is Option C's entire reason to exist.
- **The seed needs something to split on.** `Tools/publish_cities.py` splits on `trees.id_space`, and
  a borough is emphatically **not** an id space — R18: *"An id space is the numbering scheme record
  ids are drawn from — not a city and not an inventory."* All of NYC is one numbering (ForMS
  `GlobalID`). So a region column is a **seed schema change: `SeedDatabase.newestKnownSchemaVersion`
  16 → 17.** Named in §8, not designed here.
- **The manifest's unit changes meaning.** An entry stops being "a city" and becomes "a downloadable
  region, which may be a whole city." That is not an additive key, so **`manifest_format` 1 → 2**
  (§8).

### Option C — regions, several attached at once

Option B plus multi-attach: a reader holds Brooklyn *and* Manhattan and the map is continuous across
them. R43 §1 names this as future work.

**What it actually costs, because it is more than it looks and less than it sounds.**

- **SQLite's limit is not the problem.** `SQLITE_MAX_ATTACHED` is 10 by default, and the SQLite on
  this machine reports `MAX_ATTACHED=10` in `PRAGMA compile_options` and refuses the eleventh attach.
  The iOS build's own value was not measured and should be before this is relied on; five boroughs
  fit under either reading.
- **The query layer is the problem.** Every statement in `Cypress/Data/Store/TreeQueries.swift`
  becomes a `UNION ALL` across N schemas. Two specifics: `markerCellsSQL` selects `MIN(t.rowid)`, and
  **`rowid` is per-database**, so that path breaks outright rather than degrading; and the clustered
  aggregate's covering-index property has to survive being pushed into each branch of the union, which
  is exactly the property §1.4 says is worth 3.4x.
- **It is plausibly *faster*, not slower.** The viewport bbox intersects one or two boroughs in almost
  every frame, and the R\*Tree prunes the rest to nothing. Total rows examined is the same or less
  than one big file. This should be measured before it is believed, but the intuition that
  multi-attach is a performance cost is probably backwards.
- **It wants the species catalog out of the packs.** R37.3 keeps `species` whole in every city file
  because it is *"shared authored work, not city data."* Under multi-attach that stops being merely
  duplicative (0.49 MiB x 5) and starts being *ambiguous* — five schemas each holding `species.id = 1`,
  and every join has to pick one. **The clean move is to put the authored species catalog in the app
  bundle**, where authored content belongs, and make region packs pure inventory. That is a bigger
  idea than it looks: it is the first real separation of "authored content shipped per build" from
  "civic data updated per publish," which is the distinction the owner's paragraph is circling.

*Against:* it is a substantial engineering round touching the hottest code in the app, and it does not
need to be in the same round as the NYC ingest.

### Option D — the Fly server answers map queries (R36's shape B)

**Bundle:** could shrink to nothing. **Downloads:** none. **Updates:** instant. **Offline: gone.**
**Server:** Postgres holding 1.1M+ NYC rows plus the existing corpus, PostGIS or an equivalent index,
and a query per pan.

R36 names this and names its trigger in the same sentence: *"Shape B — a live query API over the full
corpus — is the documented fallback, not the plan, reached only if cross-city queries outgrow what a
phone can hold."* That has not happened; the app attaches one inventory at a time and the corpus is
two cities. `docs/ARCHITECTURE.md` §1 records the consequence in the stack table — PostGIS is not
adopted because no server-side spatial query exists under R36's local read path.

**Refused for this round, and the reason to keep it named:** it is the only option that makes
*freshness* free, and it is where D16's *"one database, available over an API"* eventually points.
The recommendation below deliberately does not foreclose it — the live layer keeps growing under R72
and #158, and the day cross-city queries genuinely outgrow a phone, shape B is the answer already
written down.

### The comparison

| | A: one NYC file | B: regions, one attached | C: regions, many attached | D: server-served |
|---|---|---|---|---|
| Bundle | 108 MB | 108 MB | 108 MB (or less, §5 C) | ~0 |
| Largest download | ~495 MB | ~169 MB (Queens) | ~169 MB, several | none |
| Refresh cost / reader | ~495 MB | one region | the regions they hold | none |
| Offline | full | full, with cliffs | full | none |
| Cluster query | ~480 ms | ~52–163 ms | ~52–163 ms | server-side |
| `AppSchema` (15) | — | — | — | — |
| `newestKnownSchemaVersion` (16) | — | **→ 17** | **→ 17** | — |
| `manifest_format` (1) | — | **→ 2** | **→ 2** | — |
| Query layer | untouched | untouched | **rewritten** | replaced |
| Worktree / CI seed cost | unchanged | unchanged | unchanged | could vanish |
| R36 | as ruled | as ruled | as ruled | **revises it** |

---

## 6. Recommendation

**Stage it. B is the destination for this round; C is the round after; the first stage is neither and
should land before the ingest picks a unit.**

The staging is not caution for its own sake. Stage 0 is the only part that answers a defect the owner
can see today, it costs nothing in any version space, and — the actual argument — **it is the part
that must be right before regions exist at all**, because a screen that cannot say "you already have
this" for two cities will not be able to say it for seven regions.

### Stage 0 — the app reads its own bundle (no schema change, no publisher change)

§3.3, in full: derive the bundle's cities, their content revisions and their coverage from the
bundled file by the publisher's own rule; give R43 §3 two new row states; drop the `Download`
affordance where it cannot keep its promise; and let `installedOffline` use `dim_city.display_name`
(§3.4). Land the two `Decodable` properties for `bbox` and `centroid` in the same change (§1.2) — they
cost nothing, they close E209 B3 / E213 / E214's stated blocker, and Stage 2 needs them.

**This is independent of the NYC ingest and should not wait for it.**

### Stage 0b — the download path grows up, and compression lands

Every option in §5 makes the largest download bigger than the 81 MB `CityDownloader` was sized for,
so this is not option-dependent work and it can run beside Stage 0. Four items, in order of how badly
they bite:

1. **Brotli on the wire** (§2.3, open question 3). 4.56x on the real published artifact, inside
   `manifest_format` 1 exactly as R37.4 reserved, no third-party dependency. It is the highest
   value-per-unit-of-work item in this document and it improves every option equally.
2. **A background-identifier `URLSession`**, foreground-initiated (§4.5), so a large download survives
   the app being backgrounded.
3. **Resume.** R37.2's immutable versioned paths already satisfy the *"resource has not changed"*
   precondition by construction; what has not been checked is whether the bucket's public domain
   serves `ETag`/`Last-Modified` and honors `Range` — the publisher's own `upload.sh` does single-byte
   range GETs to verify anonymous reads, which is suggestive and not the same test.
4. **A free-space precheck**, with the privacy-manifest consequence §1.3 names. A 169 MB download that
   fills the device and fails at 94% is the worst available failure for this feature.

### Stage 1 — the published unit becomes a region (with the NYC schema round)

`manifest_format` 2: an entry gains a region identity — a parent city id, a level (`city` | `borough`
| `extent`), and the `bbox` it already carries. `Tools/publish_cities.py` splits on a region column
rather than on `id_space` alone. SF and San Jose publish unchanged in meaning, as cities with one
region each; the `coverage` shim R37's trailing clause wanted retired retires here, into
`coverage_<id_space>` or its region-shaped successor.

**The seed schema change this needs is `SeedDatabase.newestKnownSchemaVersion` 16 → 17, and it must be
written by the same author as the standing-dead change (§10).** The owner has already ruled
schema-first for NYC; this is a second reason the schema round has to happen before the ingest
commits, not after.

Publish **both** the five borough packs and a whole-NYC pack. The whole-city pack costs nothing but
bucket storage, it is the honest answer for a reader with the disk and the patience, and it means
Option A is still reachable per-reader rather than being foreclosed by the design.

### Stage 2 — the location-triggered offer (§7)

Needs Stage 0's `bbox` decoding and Stage 1's regions. Its own ticket, because R43 §6 already sent
auto-download and background refresh to one.

### Stage 3 — multi-attach, and the species catalog moves to the bundle (Option C)

After NYC has shipped and the borough cliff has been felt rather than predicted. Sequenced last
deliberately: it is the only stage that rewrites `TreeQueries`, and it is the only one whose benefit
is speculative until real readers are crossing real borough lines.

### 6.4 On freshness, and why no delta is recommended yet

The owner's *"updatable without shipping a new seed"* is already true — that is R37's whole point. The
open question is *granularity*, and there are only three honest answers:

1. **Smaller units.** Stage 1's regions are the delta strategy, and they are the only one that
   requires no new verification story. A Brooklyn reader refreshes ~126 MB raw / ~28 MB compressed.
2. **Compression.** §2.3. R37.4 reserved the key and underestimated the gain by three-quarters; brotli
   is 4.56x on the real published artifact and needs no third-party dependency. **This is the highest
   value-per-unit-of-work item in this entire document** and it fits inside `manifest_format` 1.
3. **A binary delta. Measured, and the answer is no — for a specific, fixable reason.** §12.3 has the
   experiment. The short version: a 0.1% row change produces a **99.25%**-identical file at SQLite
   page granularity, which would make a zsync-style range-fetch update nearly free — and then
   `VACUUM` reduces that to **0.00%**. Not "low." Zero matching 4 KiB blocks, confirmed by a control
   in which a no-op `VACUUM` with zero logical change also produced 0.00%. `Tools/publish_cities.py`
   `VACUUM`s every file it writes, and it is right to: that is what makes the narrowed copy small and
   deterministic. **So the delta path is not blocked by SQLite; it is blocked by one line in the
   publisher, and the trade is file size against update size.** That is a real future ticket with a
   measurable answer, and it is not this round's.

   **Row-level changesets: the blocker everybody cites appears to be stale, and the real one is
   elsewhere.** The standing third-party consensus — GRDB's issue tracker, the Swift forums — is that
   Apple's SQLite is not built with `SQLITE_ENABLE_SESSION` and `SQLITE_ENABLE_PREUPDATE_HOOK`, which
   is why projects that want changesets vendor the amalgamation. **Measured against the current SDK,
   that reads as out of date.** The iPhoneOS 26.5 SDK's `libsqlite3.tbd` exports **34 session and
   changeset symbols** — `sqlite3session_diff`, `sqlite3changeset_apply`, the whole `changegroup`
   family — plus all six `sqlite3_preupdate_*` symbols; and Apple's platform SQLite 3.51.0 on this
   machine answers `sqlite3_compileoption_used("ENABLE_SESSION")` and `("ENABLE_PREUPDATE_HOOK")`
   with 1. **What is missing is the interface, not the implementation:** the SDK ships no
   `sqlite3session.h`, and `sqlite3.h` mentions `sqlite3_preupdate_hook()` exactly once, in a doc
   comment for a different function. Using any of it means hand-declaring prototypes against an
   exported-but-unpublished C API — a review-risk judgment, not an engineering impossibility. **The
   deciding runtime check on an actual device has not been run** (§12.3), and it should be before
   anyone builds on this.

   **None of which matters, because the real blocker is one level up.** `sqlite3changeset_apply`
   needs a **writable** database, and R43 §1 attaches city files read-only with `immutable=1`. Making
   a city file writable in order to patch it ends R37.2's byte-verified immutable artifact — the same
   objection that sinks **`sqldiff` SQL patches**, which need a writable target too. You cannot
   sha256 a patched database against a published hash, because SQLite does not promise byte-identical
   files from equivalent operations. **So the two live delta paths are the block one and the overlay
   one, and neither patches anything:** stop `VACUUM`ing after the first publish of a generation and
   range-fetch the changed pages (§12.3), or publish small append-only overlay files beside an
   untouched base (§4.3). Both keep the artifact whole, hashed, immutable and read-only. The overlay
   route is the one with a shipping precedent and the one this document would bet on — and it needs
   Option C's read path, which is why it is not this round's.

---

## 7. The location-triggered offer

The owner's *"on open, app detects where you are, and if there's a download covering that area, asks
if you want to download."* R36 already ruled the intent — *"The app geolocates, offers the reader's
city on first launch"* — and R43 §6 refused to build it in #157 and pointed it at its own ticket. It
is unbuilt, not undecided.

**The data side is done.** §1.2: every manifest entry has carried `bbox` and `centroid` since #156.
The offer is a point-in-rectangle test against the manifest the Cities screen already fetches. There
is no new network call, no new server, no reverse geocoder.

**Three constraints on how it may behave.**

1. **R29's rule is about copy, not about geometry.** R29 is emphatic: *"It never names the city. The
   app does not know which city a coordinate is in; it knows only that no boundary in the record
   contains it."* That governs what the *almanac* says about a place. A manifest bbox test is a
   different question — *which published file covers this coordinate* — and answering it does not
   require naming the reader's location. The offer should say what the download covers, using the
   manifest's own `display_name` and `coverage`, and say nothing about where the reader is. Getting
   this backwards is how a well-intentioned feature ends up inventing a civic claim (constraint 15).
2. **A bbox is a rectangle and boroughs are not.** Queens' and Brooklyn's bounding boxes overlap
   heavily. So the test must tolerate multiple hits and offer them as a *set*, and it must never
   assert that a hit means coverage — a bbox contains ground the inventory does not. E216 is the
   errata that records what a fix on a treeless block looks like: a broken map. The honest phrasing
   offers a download and does not promise what is in it.
3. **It is a new screen state and there is no mock.** SCREENS.md has no Cities screen, no download
   state and no location prompt anywhere. Constraint 21 makes this a stop-and-ask. §9.

**A recommendation on the trigger, because "on open" is the expensive reading.** Do not put this on
launch. Launch-time location plus a launch-time manifest fetch is a background-task design, which is
exactly what R43 §6 refused, and it spends the location permission for a feature the reader has not
asked for. Put it on the Cities screen — which is already fetching the manifest and already has the
reader's attention on downloads — and, at most, on a one-time prompt after the map has been panned
somewhere the attached inventory does not cover, where the out-of-coverage copy already fires.

---

## 8. Schema and version spaces, named separately

`CLAUDE.md` warns about two spaces. **There are three**, and the third is the one this proposal moves
most.

### 8.1 `AppSchema.currentVersion` — the writable database (`PRAGMA user_version`)

**It is 15**, the maximum `Migration(version:)` in `Cypress/Data/Store/AppSchema.swift`.

**Nothing in this proposal touches it, in any stage.** Everything here concerns published, read-only
inventory files and the manifest that describes them. The `active-city` marker stays a file, not a
row — R43 §4's *"No schema migration"* holds, and the reason it holds is the same reason it held then:
disk is the record.

### 8.2 `SeedDatabase.newestKnownSchemaVersion` — the published seed/city file (R37's `s<n>`)

**It is 16**, in `Cypress/Data/Store/SeedDatabase.swift`, matched by `SEED_SCHEMA_VERSION = 16` in
`Tools/publish_cities.py` and by both entries in the live manifest.

- **Stage 0 needs no change.** Everything it reads — `id_spaces`, `dim_city`, `seed_meta` — is s16.
- **Stage 1 needs 16 → 17: a region a tree belongs to, and a dimension describing regions.** Not
  written here, and this is the report `CLAUDE.md` requires. What it must carry, named only:
  - a per-tree region reference, so `Tools/publish_cities.py` has something to narrow on the way it
    narrows on `id_space` today;
  - a region dimension with a display name, a level, and a parent city — the same shape `dim_city`
    took at s16, and for the same reason (a pack that carried another region's civic facts would be
    claiming an authority it does not have);
  - the retirement of `COVERAGE_KEYS`' `sj_ship_extent` shim into whatever region-shaped successor
    the author chooses, which R37's trailing clause already asked for by the third city.
  - **This migration and the standing-dead `kind`/`status` change (`docs/investigations/nyc-street-trees.md`
    §6) are in the same space and must have one author.** They are also both NYC-driven and both
    schema-first by the owner's ruling, so the natural answer is that they are **one generation, 17**,
    authored once. That is a scope decision, not this document's.
- **Stage 3 would move it again** if the species catalog leaves the packs for the bundle (§5 C) — that
  is a removal from the published file's schema, which is exactly what a generation bump is for.

### 8.3 `CityManifest.knownFormat` / `MANIFEST_FORMAT` — the envelope

**It is 1**, in `Cypress/Data/Cities/CityManifest.swift` and `Tools/publish_cities.py`.

**This is a third version space and the record does not treat it as one.** It advances independently
of the other two, it has its own compatibility rule (`CityManifest.decode` refuses an unknown format
outright before reading anything else), and it has its own additive-change rule (R37.4). Every
argument `CLAUDE.md`'s two-spaces bullet makes about confusing 14 with 16 applies to it with equal
force. **Recommend that the bullet gains a third entry.**

- **Stage 0: unchanged.** Decoding `bbox` and `centroid` is additive consumption of keys that already
  exist — precisely the case R37.4 reserved.
- **Stage 1: 1 → 2.** The unit's meaning changes, and a format-1 reader shown a format-2 manifest
  would install a borough believing it was a city. R37.2's *"the on-device update check is string
  equality on `version`"* and R60's *"opaque string compared by equality"* both survive: nothing here
  parses a version string, and that property must be preserved.
- **A migration hazard worth naming now.** A format bump means an old app build stops seeing the
  catalog at all, because `CityManifest.decode` refuses rather than degrades — correctly, but it means
  the day format 2 publishes, every unupdated install shows `Couldn't check what's available.
  Downloaded cities still work.` Either publish both formats for a window (two manifest paths, the
  format-1 one listing only whole-city packs), or accept the outage and time it against TestFlight
  adoption. **Recommend publishing both for one release cycle**; it costs a few kilobytes.

---

## 9. Screens and rulings this touches — the stop-and-ask

`docs/distilled/SCREENS.md` has no Cities screen, no download state, no location prompt and no
coverage affordance anywhere; R43 says so itself and declares that *"this ruling is the mock."*
Constraint 21 therefore makes each of the following a stop-and-ask rather than something a ticket may
invent. **This document names them and draws none of them.**

| Change | Nature | Whose call |
|---|---|---|
| Two new row states on the Cities screen (*included in the app* / *newer record available*), and the removal of `Download` from a bundled city | Amends R43 §3's enumerated states | Ruling amendment; owner or delegated |
| `installedOffline` titles from `dim_city.display_name` (§3.4) | Fixes a row R43 §3 already rules on | Errata + fix, no new ruling |
| A row that says which regions of a city you hold | New vocabulary R43 §3 does not have | New ruling, needs Stage 1 |
| The location-triggered offer's prompt (§7) | A new state with no mock; R43 §6 refused its family for #157 | **Owner** — constraint 21 |
| Any copy naming the reader's location | Would cut against R29 | **Owner** — recommend against |

---

## 10. Sequencing against the three live rounds

- **The NYC ingest (`feat/nyc-ingest`, running now).** It is measuring per-borough row counts and
  trial-seed sizes. **This design does not block it and does not want to.** What it asks of that round
  is one thing: **carry the borough through the adapter into the record**, whatever column the schema
  round eventually chooses, because the borough is only available in the second dataset
  (`Forestry Planting Spaces.boroughcode`) which the ingest is already joining for the address.
  Throwing it away at ingest and re-deriving it later means re-fetching 1.09M rows.
- **The standing-dead schema round (schema-first, per the owner).** Same version space as Stage 1
  (§8.2). One author, and the strong recommendation is one generation.
- **The photos server round (#158 / R72).** Disjoint. Photos are community-layer, R36 puts the
  community layer on the live side precisely because it cannot wait for a publish, and nothing in this
  document enters a city file. The one shared resource is the Fly machine's attention, not its code.
- **Ordering.** Stage 0 can start now. Stage 1 must follow the schema round's decision, not precede
  it. Stage 2 follows Stage 1. Stage 3 follows NYC actually shipping.

---

## 11. Open questions, each with a recommended answer

1. **Is a borough the right unit, or is it too big?** Queens at ~169 MB is larger than the entire
   current bundle. *Recommend: borough, and publish the whole-city pack beside it.* Sub-borough units
   (community districts, ZIP) multiply the manifest and the cliff count for a benefit that only Queens
   and Brooklyn would feel. Revisit if `feat/nyc-ingest`'s real Queens number lands materially above
   ~200 MB.
2. **Does San Francisco become a region too?** *Recommend: yes, as a city with exactly one region.*
   One shape, not two. The alternative — regions as a special NYC-only concept — puts an `if` in the
   publisher and in the screen forever.
3. **Compression: do it now or with Stage 1?** *Recommend: now, inside `manifest_format` 1, as R37.4
   reserved.* 4.56x measured on the real artifact, no dependency, no format bump, and it improves
   Option A as much as Option B — which means it is the one thing worth doing before the unit question
   is settled.
4. **When format 2 publishes, do old builds go dark for a cycle?** *Recommend: no — publish format 1
   and format 2 side by side for one release cycle*, with the format-1 manifest listing whole-city
   packs only. Kilobytes, and it avoids a self-inflicted outage on the Cities screen.
5. **Does the fused seed keep being published once NYC exists?** It is a CI and worktree input
   (`Tools/fetch_seed.sh`), not a user-facing one. *Recommend: yes, and NYC stays out of it.* That is
   what keeps §2.5 true — the per-worktree and per-CI-job cost does not move.
6. **Whole-NYC pack: publish it, or refuse it?** *Recommend: publish it.* It costs bucket storage,
   nothing else, and refusing it would make the app's coverage strictly worse than Option A for a
   reader who wants everything.
7. **`build_id` in the bundle comparison (§3.3).** The bundle cannot compute its own without hashing
   108 MB. *Recommend: compare on `content_rev` alone for the bundle row and say only what that
   proves* — the row claims record-date parity, not byte parity, and should not imply otherwise.
8. **The NYC "notify the City" and verbatim-disclaimer obligation** (`docs/investigations/nyc-street-trees.md`
   §2, and R36's binding consequence (b)) is a distribution question the moment NYC data is served
   from the bucket, not only when it is drawn. *Recommend: settle it before the first NYC publish, not
   before the first NYC ingest.* It is the owner's call and it is unrelated to which unit wins.
9. **Does the background-refresh ticket R43 §6 deferred get written now?** *Recommend: not yet.* Under
   Stage 1 the update the reader most wants is a small one, and a manual `Update` on a 28 MB
   compressed pack is a materially different product from a manual `Update` on a 495 MB one. Re-ask
   after Stage 1 ships.

---

## 12. Method, and the experiments

### 12.1 Provenance of the measured artifacts

The live manifest was fetched from `https://cypress-cities.t3.tigrisbucket.io/manifest.json` on
2026-08-14. The `sf` city file was downloaded from the path that manifest names; **its size
(80,855,040) and sha256 (`eb6c083f…a556`) were checked against the manifest entry before it was
measured**, so §2.3's compression figures describe the artifact readers actually download and not a
local rebuild of it. The bundled seed measured in §1.1 and §2.3 is the one at
`Cypress/Resources/cypress-seed.sqlite` in the main checkout, whose sha256 `build_id` prefix
(`c9a440b2`) matches the manifest's `source_seed.build_id` — i.e. the bundle and the published seed
are the same build.

### 12.2 The borough counts

One aggregate query against Socrata dataset `82zj-84is` (`Forestry Planting Spaces`), grouped by
`boroughcode` and `psstatus`, on 2026-08-14. No bulk rows were downloaded. **Calibration:** the query's
totals reproduce `docs/investigations/nyc-street-trees.md`'s independently-obtained 1,091,709 and
945,458 exactly — which is what distinguishes this from a coincidence. The tree-point and byte columns
in §2.2 are derived and labelled as such.

### 12.3 The delta experiment, and the control that makes it mean something

**Question:** would a zsync-style update — fetch only the blocks of the new file the client does not
already hold — be cheap for a republished city file?

**Instrument:** a script that hashes every page-aligned 4,096-byte and 2,048-byte block of the old
file into a set, then counts how many of the new file's blocks are in it. Blocks match at any page
position, because SQLite moves whole pages.

**Calibration, run first, both directions:** the seed against itself reports **100.00%**; the seed
against 108 MB of `/dev/urandom` reports **0.00%**. The instrument reads what it claims to read.

**Result**, applying an `UPDATE` to a fraction of `trees` and then measuring against the unmodified
seed:

| logical change | `VACUUM` | 4 KiB blocks already held | would fetch |
|---|---|---:|---:|
| 198 rows (0.1%) | no | 99.25% | 0.8 MB of 108.2 MB |
| 198 rows (0.1%) | **yes** | **0.00%** | 108.6 MB of 108.6 MB |
| 1,986 rows (1%) | no | 92.48% | 8.1 MB of 108.2 MB |
| 1,986 rows (1%) | **yes** | **0.00%** | 108.6 MB of 108.6 MB |

**A 0.00% is the kind of number that is usually a broken instrument, so it got its own control:** the
seed copied and `VACUUM`ed with **zero** logical change also reports 0.00% and grows by 84 pages. So
`VACUUM` rewrites every page of this database regardless of what changed, and the churn result is real
rather than an artifact of the churn. That is the finding §6.4 rests on: **the delta path is blocked
by the publisher's `VACUUM`, not by SQLite**, and unblocking it trades published file size against
published update size — a measurable trade, and a future ticket.

**And one instrument that read the wrong thing first, recorded because it nearly reached §6.4.**
`PRAGMA compile_options` on *this Mac's* `sqlite3` reports `ENABLE_SESSION`, which says nothing at all
about iOS. Asking the right question means asking the iOS SDK: `sqlite3session_create` and
`sqlite3changeset_apply` appear in **neither** `sqlite3.h` nor any other header under the iPhoneOS
SDK's `usr/include`, and there is no `sqlite3session.h` — but `usr/lib/libsqlite3.tbd` exports 34
symbols of that family. Present in the library, absent from the published interface. The first
measurement would have supported the sentence "changesets are available on iOS"; the second says
something narrower and truer, and §6.4 says the narrower thing.

### 12.4 What is not from this repository

§4 was fetched on **2026-08-14** from Google's and Apple's own support documentation, the Organic Maps
and OsmAnd source trees and user documentation, the PMTiles v3 specification and its maintainers'
own discussion threads, and Apple's developer documentation and App Store Connect reference. Product
behavior and library maintenance both have a half-life; **re-fetch before relying on any of it in a
later round** rather than quoting these figures, the same rule this project applies to seed counts
and for the same reason. Claims that could not be reached from a primary source are marked inline as
unverified — Google's expiry period and update granularity, Apple's update transport, and OsmAnd's
read-time resolution of a tombstone are the four that matter most, and all four are undocumented.

The NYC churn figures in §2.2 and §4.3 come from aggregate queries against the live Socrata dataset
on 2026-08-14, using the dataset's own `updateddate` column. **Calibration note carried from that
work:** SODA's `:updated_at` system column is useless for this question — all 1.12M rows share one
timestamp because the publish rewrites the table — and a query that used it would have returned a
confident, wrong, and entirely plausible-looking answer.

### 12.4b The three iOS facts that had gone stale

- **On-Demand Resources is deprecated as of iOS 27**, and the record's understanding that ODR packs
  cannot be updated without an app build is correct for ODR and *wrong for its replacement*: Apple-
  hosted Background Assets packs upload to App Store Connect separately from a build. §4.5 refuses
  that route on a stated ground rather than an obsolete one.
- **The 200 MB cellular threshold is an App Store setting**, not a `URLSession` behavior. It bounds
  the bundle, which is E176's use of it, and does not bound an in-app download.
- **The "SQLite session extension is not available on iOS" consensus reads as stale** against the
  current SDK (§6.4). The measurement that would settle it — `sqlite3_compileoption_used` on a
  device — was not run, and this document does not claim the consensus is wrong, only that the
  evidence for it no longer matches what the SDK exports.

### 12.5 What was not run

No test was run and no simulator was used: this change is prose, and CI takes the prose path — a green
`gate` here is evidence about the diff, not about the code. `CypressTests/DocumentCitationGuardTests`
does apply to this file; every backticked repo-relative path in it was checked against the worktree
with a reimplementation of that guard's own extractors, calibrated first against a document known to
be clean and against a planted dangling citation.

### 12.6 Premises checked, and four refuted

- **Refuted: `CityManifest.City` "carries no center or bbox to derive one from," and fixing that is "a
  wider ticket"** (E209 B3, E213, E214). The manifest has carried both since #156 and carries them
  live today; only the Swift decoder is missing them (§1.2). The errata claims are true about the type
  and wrong about the cost.
- **Refuted: R37.4's "gzip (~2x)."** Measured 3.53x on the published `sf` file, and brotli — which is
  in the OS — is 4.56x (§2.3).
- **Refuted: `CLAUDE.md`'s "`docs/ARCHITECTURE.md` §7 concurrency."** §7 is Testing; concurrency is §3;
  import discipline is inside §2, which the brief and `docs/CONTRIBUTING.md` both have right.
- **Refuted: there are two version spaces.** Three (§8). `manifest_format` has its own compatibility
  rule and its own advancement, and it is the one this proposal moves.
- **Stands: the owner's report about the download screen.** Reproduced from the code in §3.1, with a
  fourth consequence the report did not reach.
- **Stands: `docs/investigations/nyc-street-trees.md`'s scale numbers.** 899,094 and 1,091,709 both
  reproduced independently (§12.2), and its ~540 bytes/row is within 3% of the 566 bytes/row the two
  published city files imply.
- **Stands, and is load-bearing: R43 §1's one-inventory-at-a-time.** Options A and B leave it exactly
  as ruled; only C revises it, which is why C is last.
