# Standing up the D16 API: hosting and architecture survey

Investigation note, 2026-08-01. Investigation only — no code changed, no account created, nothing
deployed, nothing bought. Every price below is dated; prices move, dates do not.

D16 names the destination: one merged, normalized national tree inventory, available over an API,
with community contributions layered on top (`docs/distilled/DECISIONS.md` D16). Today there is no
backend at all (`docs/ARCHITECTURE.md` §4: "There is none and none is planned for the beta"). The
NYC survey (`docs/investigations/nyc-street-trees.md`) is the forcing function this note answers:
NYC alone is 899k current tree points against a 198,625-row two-city seed, and folding it in moves
the bundled SQLite from 108 MB toward something close to a gigabyte. A third and fourth city keep
going. At some size the bundle stops being a viable distribution mechanism regardless of what API
shape gets built, and that threshold arrives well before "national."

**Bottom line, stated first because the rest of this document argues for it:** ingest publishes
versioned per-city SQLite files to Cloudflare R2 (or Fly's Tigris — see §4 for the tie-break); the
app downloads the cities it wants instead of bundling one seed; contribution writes go through a
small Fly.io machine talking to a shared Postgres (or LiteFS-backed SQLite — see §4) that
`RemoteAPI` calls exactly where `CypressAPI` already expects a server. No live query API answers map
viewports server-side; the client queries its own downloaded SQLite exactly as `LocalAPI` does
today. Expected cost at zero traffic: **$0–3/month**. At 1,000 monthly-syncing users: **still under
$10/month** on every path examined. The one-sentence reason: this app is offline-first by design,
the read path already works by shipping SQLite to the device, and paying for a live query server to
answer questions the device can answer itself would be solving a problem D16 does not have.

---

## 1. The fork: static distribution vs. live query API vs. hybrid

### A. Static file distribution (recommended)

Ingest publishes versioned, per-city SQLite files (or diffs against the previous version) to object
storage behind a CDN. The app's seed loader — today a bundled asset load — becomes a download-and-
cache step: fetch the manifest, fetch the cities the reader has visited or asked for, open them with
GRDB exactly as `LocalAPI` opens the bundle today. **No server sits in the read path at all.**
Contributions still need somewhere to land, so a small write API (POST-only, no query surface)
receives outbox drains and appends them to the write-side store.

Why this fits Cypress specifically, not just "static hosting is cheap" in general:

- The client already does 100% of its query work against a local SQLite file — `LocalAPI` is
  GRDB over `Cypress/Resources/cypress-seed.sqlite`, and every `CypressAPI` read (`mapContent`,
  `treesNear`, `treeProfile`, `almanac`, ...) is a local query today. A live query API would be
  rebuilding, server-side, exactly the query surface the device already runs — for an app whose
  entire design point (ARCHITECTURE, PRODUCT.md) is working with no network.
  Making the *server* answer `mapContent(in: MapViewport)` for a viewport the device could resolve
  itself from a file it already has is the wrong direction to move the read path.
- The data updates on a publish cadence (a new inventory pull, a moderation batch), not per-request.
  Municipal inventories refresh weekly-to-never (NYC's own metadata says "every 2 weeks"); nothing
  about tree data needs live queries.
- Offline-first is not a nice-to-have here, it is the product: a volunteer standing under a tree
  with one bar of signal is the primary use case SCREENS.md and PRODUCT.md are built around. A file
  the device already has beats a query that might time out.

Cost shape: pay for storage (cheap, grows with total data) and egress (the thing to watch — but see
§2, R2 and Tigris both zero-rate egress) and near-zero compute, because there is no compute in the
read path.

### B. Live query API

A small server (Fly machine + SQLite-on-a-volume via LiteFS/Litestream; or managed Postgres; or
Cloudflare Workers + D1/R2) answers `GET /trees?near=...`, `GET /trees/{id}`, viewport queries, etc.
directly, the way BUILD-PLAN §6's endpoint list was written for.

This is the "conventional" shape and it is not wrong in general — it is what most apps with a
backend do. It is the wrong fit for *this* app because it reintroduces a live dependency into a read
path that presently has none, for queries that do not need liveness. It also does not shrink the
gigabyte problem: a live query server still has to hold (or federate to) all the merged inventory
data somewhere, so B does not avoid the storage growth A faces — it just adds a request-serving tier
on top of it that A does not need.

B becomes the right shape later if the product needs something a static file cannot give it —
full-text or fuzzy species search across the whole national corpus server-side, a live "trees near
me" query against a corpus too large to ever ship to a phone, or moderation/consistency guarantees
that need a single source of truth answering in real time. None of that is true today, at
two-to-four cities.

### C. Hybrid: static reads + a minimal write endpoint

This is not really a third option distinct from A — it is A, stated completely. A always needed a
write endpoint (contributions must land somewhere; D16's community-review loop is a database, and a
database needs writes). The interesting design question C raises is *how minimal*: the answer here
is "as minimal as `CypressAPI.sync(_:)` already assumes" — a POST that takes outbox items and
returns per-item results, plus the photo-upload pair. No query methods on the write server at all.

**Recommendation: A, with C's write endpoint as its only server-side component.** B is not ruled
out forever — see §6 migration path — but nothing in the current app or the D16 destination asks
for it yet, and standing one up now would be management burden the owner explicitly ruled out
("NOT overkill to manage").

---

## 2. Vendor comparison, dated pricing

All figures fetched 2026-08-01 from vendor documentation or vendor-adjacent pricing trackers cross-
checked against a primary source where one was reachable; each row cites which.

### Object storage + CDN (shape A's read path)

| Vendor | Storage | Egress | Free tier | Source, fetched 2026-08-01 |
|---|---|---|---|---|
| **Cloudflare R2** | $0.015/GB-month (Standard); $0.01/GB-month (Infrequent Access) | **$0** — R2's headline feature is zero egress on every class | 10 GB-month storage, 1M Class A ops/month, 10M Class B ops/month, free egress | [developers.cloudflare.com R2 pricing](https://developers.cloudflare.com/r2/pricing/) (page fetched via search-verified secondary sources; primary Cloudflare docs page confirms the same figures) |
| **Fly.io / Tigris** | $0.02/GB-month; first 5 GB free | **$0** — Tigris does not charge for regional, region-to-region, or internet egress | 5 GB storage free | [fly.io/docs/tigris](https://fly.io/docs/tigris/), [tigrisdata.com/pricing](https://www.tigrisdata.com/pricing/) |
| **AWS S3 + CloudFront** | S3 Standard ≈ $0.023/GB-month (us-east-1, unchanged for years) | CloudFront egress ≈ $0.085/GB for the first 10 TB/month (us pricing) | S3: 5 GB free (12-month new-account tier); CloudFront: 1 TB/month free (AWS's account-wide free tier, ongoing as of this writing) | figures are AWS's long-standing published rates; not independently re-fetched this session — treat as approximate and re-verify before committing budget |
| **Vercel Blob** | $0.023/GB-month (Pro, beyond 5 GB included) | $0.05/GB Blob Data Transfer beyond 100 GB included, **separate meter from the 1 TB deployment bandwidth allowance** | Hobby: 1 GB storage, 10 GB transfer/month, free within limits, non-commercial only | [vercel.com/docs/vercel-blob/usage-and-pricing](https://vercel.com/docs/vercel-blob/usage-and-pricing), fetched directly, updated 2026-06-16 |

**Egress is the deciding line in this table.** A city-sized SQLite file (NYC alone would push a
single city file into the hundreds-of-MB range) downloaded repeatedly by users is an egress-bound
workload, not a storage-bound one. R2 and Tigris both zero-rate it; S3+CloudFront and Vercel Blob do
not. At meaningful download volume (§3) that difference is the whole bill.

### Compute (shape A's write endpoint, or shape B's query server)

| Vendor | Pricing unit | Free tier | Cold start / ops character | Source, fetched 2026-08-01 |
|---|---|---|---|---|
| **Fly.io Machines** | shared-cpu-1x/256MB: $0.0028/hr ≈ $2.02/mo always-on; 512MB ≈ $3.32/mo; 1GB ≈ $5.92/mo. Billed per second while *started*. | No new free tier — legacy accounts (pre Oct 2024) keep up to 3 shared-cpu-1x/256MB machines free; new accounts pay from machine #1 | Machines can `auto_stop`/`auto_start`, i.e. scale to zero between requests with a cold-start (~hundreds of ms to a few seconds depending on image); an always-on machine has no cold start | [fly.io/docs/about/pricing](https://fly.io/docs/about/pricing/), fetched directly |
| **Fly Volumes** (needed for LiteFS/SQLite-on-a-volume) | $0.15/GB-month, billed whether attached or not; snapshots $0.08/GB-month, first 10 GB free, **snapshot billing starts January 2026** | none | — | same |
| **Cloudflare Workers** | Free: 100k req/day, 10ms CPU/invocation. Paid: $5/mo flat, includes 10M req/mo + 30M CPU-ms/mo, then $0.30/M req and $0.02/M CPU-ms | 100k requests/day free, forever (not a trial) | No cold start in the traditional sense — V8 isolates, not containers; effectively instant | [developers.cloudflare.com/workers/platform/pricing](https://developers.cloudflare.com/workers/platform/pricing/), fetched directly |
| **Cloudflare D1** (if paired with Workers for the write endpoint) | Paid plan includes 25B rows read/mo, 50M rows written/mo, 5 GB storage; overage ≈$0.001/M rows read, $1.00/M rows written, $0.75/GB-month storage beyond free | 5 GB storage, 5M rows read/day, 100k rows written/day on the free Workers plan | Scale-to-zero, no idle charge | [developers.cloudflare.com/d1/platform/pricing](https://developers.cloudflare.com/d1/platform/pricing/) |
| **Vercel Functions** | Pro: $20/seat/month base + $20 usage credit included; Active CPU $0.128/hr beyond included; separate Fast Data Transfer/Edge Request meters | Hobby: 1M invocations, 4 CPU-hrs, 100GB bandwidth/month, **non-commercial only** — Vercel enforces this, and a project taking real contributions from real users is not a hobby project by Vercel's own definition | Functions cold-start on Node runtime (typically sub-second to a couple seconds); Edge runtime is faster | multiple pricing trackers cross-checked 2026-08-01; base seat price and non-commercial Hobby restriction both independently corroborated across sources |
| **Managed Postgres** (if B or a Postgres-backed write store is chosen) | Fly Managed Postgres: usage-based, not separately priced in the fetched docs — "details available at the Managed Postgres documentation." Neon (Vercel Marketplace) and Supabase both have free tiers in the low hundreds of MB–GB range as of 2026, not independently re-verified this session. | varies | — | not independently fetched in depth this session — flagged as an open question if Postgres is chosen over SQLite-on-a-volume |

### The Hobby-tier trap, stated plainly

Vercel's free Hobby tier is explicitly **non-commercial** — "the free plan cannot be used for any
project that generates revenue, and Vercel enforces this" (cross-checked across pricing trackers,
2026-08-01). D14 already commits Cypress to a paid coordinator tier at $50–200/org/month
(`docs/distilled/DECISIONS.md` D14). The day that tier has one paying customer, Cypress is a
commercial project and Hobby is off the table — meaning any Vercel-hosted piece of this needs to be
budgeted at Pro ($20/seat/month floor) from day one if it is meant to survive contact with D14,
not evaluated against Hobby's free numbers. Fly and Cloudflare's free/cheap tiers carry no such
restriction.

---

## 3. Concrete cost at two traffic points

**Assumptions, stated because they drive the numbers:** "zero traffic" = the app is installed on a
handful of dev/test devices, ingest runs occasionally, no real users yet. "Hobby-scale bump" = 1,000
users, each syncing (downloading their city's current seed file, or a delta, plus draining a small
outbox) roughly once a month — the read pattern D16 anticipates once the app has any real audience
but nowhere near the "national" endgame. City file size assumed at NYC's scale once ingested: order
of 300–500 MB uncompressed per large city (extrapolating from the current 108 MB two-city, 198k-row
bundle and NYC's 899k rows), likely less after compression a static-file pipeline can apply that a
bundled asset cannot (gzip/zstd over the wire, decompressed on device).

### Shape A (recommended): R2 or Tigris for reads, Fly machine (or CF Worker) for writes

| | Zero traffic | 1,000 users/month |
|---|---:|---:|
| **R2 storage** (say 2 GB of published city files, several cities × versions retained) | $0 (within 10 GB free) | $0 (still within 10 GB free at this data size) |
| **R2 egress**, 1,000 downloads × ~400 MB avg (first sync; deltas after) | $0 (free egress, any volume) | $0 |
| **R2 Class B (read) ops**, ~1,000 × handful of GETs each | $0 (within 10M free) | $0 |
| **Write endpoint** — Fly shared-cpu-1x/256MB, always-on | ~$2/month | ~$2/month (1,000 small POSTs/month is nothing for one machine) |
| **Total, R2 variant** | **≈ $2/month** | **≈ $2/month** |
| **Tigris storage** (2 GB, first 5 GB free) | $0 | $0 |
| **Tigris egress** | $0 | $0 |
| **Total, Tigris variant** (same Fly machine either way, and Tigris bills through the Fly account — one bill, one dashboard) | **≈ $2/month** | **≈ $2/month** |

The 1 GB-of-cities future: still comfortably inside R2's or Tigris's free storage tier alone
(10 GB / 5 GB respectively) even before the first paid GB, and egress stays $0 regardless of volume
on either. This is the single biggest reason shape A tolerates the coming data growth better than
any live-query alternative: **the cost of shape A barely moves as the corpus grows, because nothing
in it charges for the thing that scales (egress), and the thing that does scale (storage) is priced
low enough that a plausible multi-city future (5–10 GB) is still single-digit dollars a month.**

### Shape B, for comparison: live query API

| | Zero traffic | 1,000 users/month |
|---|---:|---:|
| Fly machine running LiteFS/Litestream over the merged SQLite, 1 GB RAM (needed to hold a growing multi-city index in memory/page cache) | ~$6/month | ~$6–15/month depending on whether it can auto-stop between queries (likely cannot, if it is meant to answer live map queries with low latency) |
| Fly Volume, 2 GB now growing toward 10+ GB | ~$0.30/month now, ~$1.50/month at 10 GB | same, growing with data |
| **Total** | **≈ $6–7/month** | **≈ $8–17/month, and this line grows with corpus size, unlike shape A** |

Shape B is not expensive at this scale either — Fly is cheap — but it is doing strictly more work
(always-on compute, holding the growing dataset live) for reads the client can already do itself,
and its cost trajectory is coupled to data growth in a way shape A's is not.

### Management burden, in hours/month

- **Shape A**: publishing a versioned file to object storage on a schedule (already close to what
  `Tools/build_seed.py` does today, minus "put the result in the app bundle" and plus "upload it
  and write a manifest entry"). Estimated **1–2 hours/month** once the publish script exists — most
  of that is watching an ingest run, not managing infrastructure. No server to patch, restart, or
  page on for the read path.
- **Shape A's write endpoint**: a small stateless Fly machine or Worker. Estimated **1–2
  hours/month** — dependency bumps, the occasional restart, watching one small queue. This is
  materially less than "run a database with a query surface" because it has no query surface.
- **Shape B**: everything in A's write endpoint, plus running a database that has to stay up, stay
  fast, and stay correct under concurrent writes and reads, with a growing dataset. Estimated
  **4–8 hours/month** conservatively, more once something breaks. This is the "NOT overkill" line
  the owner drew, and shape B is on the wrong side of it for a one-person project today.

---

## 4. Recommended concrete stack, named end-to-end

**Primary: Fly.io for everything, Tigris for storage.**

- **Ingest** (`Tools/build_seed.py`, extended): runs where it runs today (a developer machine, or
  later a scheduled Fly machine / GitHub Action), and instead of producing one bundle-ready
  `cypress-seed.sqlite`, produces **one SQLite file per city** (already close to true — the tool
  already discriminates `--source city` etc.) plus a small **manifest JSON** (city id, row counts,
  file hash, schema/contract version, publish date). Publishes both to a Tigris bucket via the S3-
  compatible API Tigris exposes.
- **Write endpoint**: one small Fly machine (shared-cpu-1x/256MB is enough at this scale) running
  whatever minimal HTTP service implements `POST /sync`, `POST /photos/begin`, and the photo PUT —
  the exact three write-shaped members of `CypressAPI` (`Cypress/Data/API/CypressAPI.swift:96-105`).
  It writes to a Postgres instance (Fly Managed Postgres, or an unmanaged single-node Postgres —
  ARCHITECTURE §4 already names "the Fastify service" as the anticipated backend shape in
  BUILD-PLAN §6, so a small Node/Fastify service here continues rather than invents a direction).
  This machine has no query endpoints and answers no map viewport — it only ever appends.
- **What the app fetches**: at first launch (or when a reader pans into a city not yet downloaded),
  the app fetches the manifest, then the relevant city SQLite file(s) from Tigris over plain HTTPS,
  caches them in the app's document directory, and opens them with GRDB — the same code path
  `LocalAPI` already runs against the bundled seed, pointed at a downloaded path instead of a bundle
  path.
- **Where a contribution write lands**: outbox drain → the Fly write endpoint → Postgres. A future
  ingest pass folds accepted, moderated community contributions back into the next published city
  file, which is D16's "community contributions layered on top" made concrete.
- **NYC attribution**: the manifest and the per-row `inventory_source`/`attributes_from` fields the
  contract already tracks (`docs/investigations/inventory-contract.md` §3) carry provenance through
  to the API response; the verbatim NYC disclaimer (`docs/investigations/nyc-street-trees.md` §2)
  becomes static copy shipped with the app and, if the "notify the City" obligation is read broadly,
  a one-time email — not something the API needs to compute per-request.

**Fallback: Cloudflare (Workers + R2, D1 for the write store).** If Fly ever stops being the fit —
the owner's familiarity is real leverage today, but if the write endpoint's needs outgrow "small
stateless service," Cloudflare's paid Workers plan ($5/month flat) plus R2 (same zero-egress
argument as Tigris) plus D1 (free 5 GB, scale-to-zero, no idle cost) is the credible alternative
named in the brief. It is not the primary recommendation only because it is a second platform to
learn against a first platform (Fly) the owner already runs other projects on — familiarity is
listed as a real advantage in the brief and this note takes that literally.

**Vercel is not recommended for either half.** Its blob egress is metered (unlike R2/Tigris) and
its free tier is contractually non-commercial in a product that already has a priced tier on the
roadmap (D14). Vercel is an excellent choice for the things it is built for — this project has none
of them in its backend (no web frontend is in scope here; if one arrives, revisit).

---

## 5. What changes in the app, without designing it

Named, not designed — BUILD-PLAN and the owner's own review are where these get designed:

- **The `CypressAPI` seam absorbs this cleanly.** `RemoteAPI` (currently a stub proving nothing
  assumes a local database — `Cypress/Data/API/CypressAPI.swift:6-7`) becomes real for the three
  write-shaped methods (`sync`, `beginPhotoUpload`, `uploadPhoto`) against the Fly write endpoint.
  Every read method (`mapContent`, `treesNear`, `treeProfile`, `almanac`, `species`, ...) keeps
  being answered by `LocalAPI` against whichever city files are on-device — `LocalAPI` does not go
  away, it becomes the thing that reads *downloaded* SQLite instead of *bundled* SQLite. This is
  exactly the "LocalAPI becomes the offline cache behind it" sentence ARCHITECTURE §4 already
  states, just realized for storage instead of for a query server.
- **Seed download vs. bundle** is a real, unbuilt piece of work: a manifest fetch, a download-and-
  verify step (file hash from the manifest), a decision about which cities to fetch by default (the
  device's current region, probably) versus on demand, and a storage-budget UI question (does the
  app let a reader remove a city's data to reclaim space — increasingly relevant once cities are
  hundreds of MB each). None of that is designed here; it is named so BUILD-PLAN can pick it up.
- **The outbox/drain design does not change.** It already targets `CypressAPI` and already treats
  every write as queue-first, retry, idempotent-on-`clientUUID` (ARCHITECTURE §4). It gets a real
  network to drain into instead of nothing.
- **Ingest pipeline** grows a "publish" step it does not have today; `Tools/build_seed.py` currently
  writes one bundle file to disk and stops.

---

## 6. Migration path if the project grows

1. **Now → early real usage**: shape A as specified. One write machine, object storage for reads,
   single-digit dollars a month.
2. **If the corpus outgrows "download a city, or a few"** — e.g., a reader wants a metro-area or
   national view that no phone should hold entirely on-device — this is where shape B earns its
   keep: add a live query surface (Fly machine with LiteFS-replicated SQLite, or Postgres, or
   Cloudflare D1) *for cross-city aggregate queries only*, while per-city downloads keep serving
   the primary map-viewport reads they already handle well. This is an addition, not a rewrite,
   because `CypressAPI` already isolates every query behind a protocol method.
3. **If write volume or moderation complexity outgrows one small machine** — many orgs on the D14
   paid tier doing batch check-ins, a moderation queue that needs its own service — split the write
   endpoint from a moderation/admin service (ARCHITECTURE §4 already scopes admin surfaces as "a web
   deliverable, out of scope for the iOS app"), likely on the same platform, likely still Fly given
   the multi-machine, multi-region primitives it already has.
4. **If the numbers in §3 stop being small** — real growth is a good problem — re-run this
   comparison rather than assume today's vendor stays cheapest; R2/Tigris's zero-egress advantage
   compounds with scale, so the gap this note found is likely to widen, not narrow, but it should be
   re-measured against then-current pricing, not this document's numbers.

---

## 7. Open questions for the owner

- **NYC's "notify the City" obligation** (`docs/investigations/nyc-street-trees.md` §2): does an
  API serving NYC-derived rows trigger this per-deployment, or once? This note assumes once, as a
  compliance task alongside shipping the disclaimer copy — not verified with NYC Parks and not this
  note's job to resolve.
- **Postgres vs. SQLite-on-a-volume for the write store.** Both are cheap at this scale; Postgres is
  the more conventional choice for a service that will eventually need moderation queries, org
  dashboards (D14), and multi-table joins the outbox's write shape doesn't need today. This note
  does not pick one — it is a Phase-1.5/BUILD-PLAN question, not a hosting question.
- **How often ingest re-publishes**, and whether the app ships deltas or always re-downloads a full
  city file — directly affects the egress-that-happens-to-be-free-anyway number in §3, but it
  affects on-device bandwidth and battery, which this note has not modeled.
- **Whether "notify the City" and similar per-source obligations belong in the manifest** as
  structured data (so the app can render the right disclaimer per city automatically) or as static
  per-city copy shipped with each app release — a product decision, not a hosting one, but it
  determines whether the manifest schema needs a field for it now or can add one later.
- **AWS S3+CloudFront and Vercel Blob's exact current numbers were not independently re-fetched
  against primary AWS pricing pages this session** (§2 flags this); if either is ever seriously
  considered, re-verify before budgeting — the R2/Tigris zero-egress numbers were fetched from
  primary or near-primary sources and are higher-confidence than the AWS figures in this note.
