# `server/` — the Cypress sync service

The live layer: **Go + Postgres, one `shared-cpu-1x`/256 MB machine on the `cypress-sync` Fly app**.
Ticket **#158**, ruled by RULINGS **R72**; the argument is
`docs/design-proposals/2026-08-09-task158-live-layer.md`.

This replaces the R36 placeholder that answered `501` to everything. The stack decision that file
described as "still open" is closed: Go, two direct dependencies, PostGIS declined.

**What this service is not.** RULINGS **R36** rules which layer travels which way and R72 does not
reopen it. The city layer — the map's pan loop, species, the almanac — is answered on the phone from
the installed city file and never reaches here. What this service holds is the community layer and
the account's own rows: the things liveness actually buys, and the things a second device cannot
know without it.

## What exists, exactly

Provisioned 2026-08-01 on the owner's existing Fly.io personal org.

| Resource | Value |
|---|---|
| Fly app | `cypress-sync` |
| Machine | `d8de496b372048`, `shared-cpu-1x:256MB`, region `sjc` |
| URL | https://cypress-sync.fly.dev |
| Tigris bucket | `cypress-cities` (public read), S3 API endpoint `https://fly.storage.tigris.dev` (authenticated writes), anonymous reads only via `https://cypress-cities.t3.tigrisbucket.io` |
| Volume | none |
| Custom domain / certificate | none |
| IPs | shared IPv4 + the dedicated IPv6 Fly allocates by default (free) |

Bucket credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`,
`AWS_REGION`, `BUCKET_NAME`) were set as app secrets automatically by `flyctl storage create`.
They are not in this repo and must never be.

**Publishing locally** (`dist/upload.sh`, written by `Tools/publish_cities.py`) does not use
those app secrets or any ambient `AWS_*` environment variable -- #248 found that flow silently
falls back to whatever is in `~/.aws/credentials [default]` the moment the shell that exported
`AWS_*` closes, and Tigris rejects a mismatched key mid-multipart-upload with
`InvalidAccessKeyId`. Set up a durable, named AWS CLI profile once, from this bucket's keys in
the Tigris dashboard:

```sh
aws configure --profile cypress-tigris
```

`dist/upload.sh` passes `--profile "${CYPRESS_TIGRIS_PROFILE:-cypress-tigris}"` on every `aws`
call and preflights that profile before touching any object, so a missing or stale profile
fails fast with this same command rather than silently uploading (or failing to upload) under
the wrong identity.

**Publishing without local credentials — the Fly relay (how the s16 publish actually shipped,
2026-08-06).** The owner's machines carry NO Tigris credential by design, and asking the owner
to paste keys per-publish is the exact failure #248 records twice. An agent with `dist/` built,
`gh` auth, and Fly access publishes end to end like this — the keys never leave the Fly app:

1. Put the four `dist/` files (two city files, the fused seed, `manifest.json`) on a temporary
   release on this repo (`gh release create seed-relay-tmp … --prerelease --latest=false`).
   The bytes are public-by-design — they are about to be served anonymously from the bucket.
2. Launch a throwaway worker on the `cypress-sync` app, which inherits the bucket secrets as
   env: `alpine:3.20`, ~512 MB, entrypoint `sh -c` with command `sleep 3600` (the MCP runner
   appends a stray argv token; `sh -c` swallows it — a bare `sleep 3600` entrypoint exits 1).
3. `exec` has a ~30 s transport ceiling: run every long step detached
   (`nohup sh -c '… && touch /tmp/x.done || touch /tmp/x.fail' &`) and poll the marker files.
   Steps: `apk add --no-cache aws-cli`; `wget` the four release assets; `sha256sum -c` against
   the hashes in `manifest.json` (write the sums file with one `echo` per line — `printf '\n'`
   mangles through the nested quoting); `aws s3 cp` each to its manifest path with
   `--endpoint-url $AWS_ENDPOINT_URL_S3`, cities and seed first, manifest LAST with
   `--content-type application/json`. Never print any `AWS_*` value — names only.
4. Verify from OUTSIDE the machine, with the repo's own instruments: `curl` the public-domain
   manifest with `?cb=$(date +%s)` and `cmp` against `dist/manifest.json`; run
   `Tools/fetch_seed.sh <scratch>` (it hash-verifies the seed end to end); full-hash both city
   files from the public domain.
5. Clean up: destroy the worker, delete the relay release and its tag
   (`gh release delete seed-relay-tmp --yes --cleanup-tag`).

Creating machines on the credential-bearing app requires the owner's explicit go-ahead —
ask, don't assume; and never ask the owner to run publication commands themselves.

The bucket is **public read** (flipped 2026-08-01 for the R36 publish). Two gotchas, both
measured on 2026-08-01: Tigris serves anonymous reads only on the dedicated public domain
`https://cypress-cities.t3.tigrisbucket.io` — anonymous GET against the S3 API endpoints
(`fly.storage.tigris.dev`, `t3.storage.dev`) returns 403 AccessDenied even with the bucket
public. And on those API endpoints anonymous HEAD returned 200 while GET returned 403, so a
HEAD-based smoke check is a false green; verify publishes with a GET (dist/upload.sh does).

## The surface

All under `/api/v1`, except `/health`. Errors are always
`{"error": {"code", "message", "retryable"}}` — the shape `APIError.Envelope`
(`Cypress/Core/APIError.swift`) already decodes, with the same eight codes and the same
`retryable` table. `CypressTests` is not what keeps those two in step;
`server/internal/apierr/apierr_test.go` reads the Swift declaration directly, because a drifted code
decodes to `server_error` rather than throwing and would look like an outage.

| Route | What it does |
|---|---|
| `GET /health` | Liveness, and the git sha of the running build. |
| `POST /auth/oidc` | Verifies an Apple identity token, **exchanges the authorization code**, mints a session. Optionally registers and claims the device in the same round trip. |
| `POST /auth/refresh` | Rotates the refresh token, mints a new access token. |
| `POST /devices/register` | Exchanges `app_state.deviceUUID` for a device token authorizing `POST /sync` for items carrying a deviceID and no userID. |
| `POST /devices/claim` | The idempotent sweep that re-homes a device's unattributed rows onto an account. |
| `DELETE /me` | Applies the client-sent `AccountDeletionChoice`, writes tombstones, calls Apple's revocation endpoint. |
| `POST /sync` | The batch. Per-item results: `applied`, `duplicate`, `failed`. |
| `POST /trees` | Adds a community tree; runs the 10 m proximity dedupe. |
| `POST /photos/begin` | Reserves the photo id, returns a presigned Tigris `PUT`. |
| `POST /photos/{id}/received` | Closes the 72 h binary grace window. |
| `DELETE /photos/{id}` | The contributor taking their own photograph back. |
| `GET /me/grove` | Class R. |
| `GET /me/grove/species` | Class R. The ring's *denominator* is a city-inventory fact and stays local. |
| `GET /me/grove/{treeID}/favorite` | Class R, narrowed to one tree (#167). |
| `GET /me/journal` | Class R, cursor-paged. |
| `GET /me/map-membership?kind=yours\|favorites` | Class R. |
| `GET /trees/{id}` | The **community half** of `treeProfile`. R-required: this is the acceptance criterion's last mile. |
| `GET /photos/{id}` | The photograph a device never wrote. |
| `POST /operator/photos/{id}/reject` | Operator takedown. Not optional — see below. |

### `device_uuid` is a credential

`POST /devices/register` mints a device token from `app_state.deviceUUID` alone. Spec §5.8 is
explicit that this **is not an attestation** — a reinstall mints a new one and nothing here can tell
the difference — and D9 requires that be cheap, because the anonymous queue is the normal case.

What follows from that, and is worth saying out loud rather than leaving implicit: anyone who knows
an installation's `device_uuid` can obtain a credential over that installation's anonymous
contributions. Re-registering **retires the previous token**, so a takeover is visible — the real
device's next call is a 401 and it re-registers — rather than two holders sharing one queue
silently. The flood defense is the rate limiter, and `rate_limited` is retryable so an honest client
that trips it keeps its queue.

The rate limiter buckets on `Fly-Client-IP`, which is set by Fly's proxy. **That header is only
trustworthy behind the proxy**: anything reaching the app directly can choose its own value and put
itself in an empty bucket. This is correct for the deployed topology and is a reason not to expose
the machine on a second, unproxied route.

### The key convention is not uniform, and the non-uniformity is load-bearing

A payload that **reconstructs a client-owned Swift type** speaks that type's synthesized property
names — camelCase: `distanceM`, `speciesCurrentID`, `checkIns`, `latitude`. Everything else — the
error envelope, sync results, request bodies — is snake_case.

Do not "fix" this. Swift's `.convertFromSnakeCase` maps `species_current_id` to `speciesCurrentId`,
which never matches `Tree`'s synthesized `speciesCurrentID`, and because that property is optional
the mismatch **decodes as nil without throwing**. A uniformly snake_case body would lose fields
silently. `internal/api/wire.go` carries the full argument and cites the Swift file for every key.

So `GET /me/grove` really does look like this, and it is correct:

```json
{"tree_uuid": "…", "hero_photo_id": "…", "record": {"visits": 3, "checkIns": 1}}
```

**Timestamps are RFC3339 at second precision, in UTC.** `JSONDecoder`'s `.iso8601` uses
`.withInternetDateTime`, which rejects fractional seconds — Go's default `RFC3339Nano` would have
failed to decode on the client, on every response carrying a date.

`server/testdata/` holds a golden file per mirrored response shape, and its README states what the
client-side conformance round (#158 step 4) owes them: Swift decode tests reading those exact files.

### Three rules the code will not let you break quietly

- **A 401 means the session, never the item.** `APIError.unauthorized.retryable` is `false` and
  `OutboxRetryPolicy.nextState` reads exactly that, so an `unauthorized` on an *item* fails that
  item terminally and prints "Sign in to send this" to somebody who is signed in (ERRATA **E261**
  §3). The session is checked once, before any item is looked at. An item that genuinely is not this
  identity's to send is `forbidden`.
- **A photograph cannot be approved without recording why.** R72 ruling 5 requires the
  approval-reason column *before* the screening pipeline, because `.approved` alone cannot tell
  "screened and passed" from "auto-approved at launch" and that is unrecoverable after the fact. It
  is a `CHECK`, not a convention. `blur_applied = false` is the re-screen backlog cursor and is
  truthfully false on every row in existence.
- **The takedown ships with the auto-approve.** "Auto-approve without a takedown is the version of
  this rule that must not ship" (R72 ruling 5). It costs the client nothing: `moderationState` can
  move backwards and `isPubliclyVisible` is evaluated at render time, so a rejected photograph stops
  being drawn on every other device at its next read.

## Schema

`server/internal/store/schema.sql`, applied on boot (every statement is `IF NOT EXISTS`).

**It is in neither of the app's two schema-version spaces.** `AppSchema.currentVersion` is the
writable SQLite database's migration counter and `SeedDatabase.newestKnownSchemaVersion` is the
published city file's; this is the server's own, it advances independently, and nothing here is a
migration in either. #158 needs exactly one app-side migration and it is not authored on this
branch.

Tables: `users`, `devices`, `sessions`, `device_tokens`, `contributions`,
`anonymized_contributions`, `favorites`, `community_trees`, `photos`.

`contributions` is keyed on `client_uuid` — the PRIMARY KEY, not a unique index beside a surrogate,
because dedupe is the table's whole job on the write path. `anonymized_contributions` mirrors
`AppSchema` v13 column for column: a key and a timestamp, and nothing that could re-create the
joining key `AccountDeletionChoice` refuses a sentinel id for.

## Configuration

Every value below comes from the environment and **none of them has a default**: a missing one
refuses the boot, which is the only safe answer — a service that started without
`SESSION_SIGNING_KEY` would mint forgeable sessions and look perfectly healthy doing it.

Two variables that are *not* in this table do have defaults, and are listed here so the sentence
above stays exactly true: `PORT` falls back to `8080`, and `GIT_SHA` to `"unknown"`. Neither is a
credential and neither changes behaviour — the first is what Fly sets anyway, the second only labels
`/health`.

| Variable | Secret | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Set by `fly postgres attach`. |
| `SESSION_SIGNING_KEY` | yes | ≥ 32 bytes. Signs access tokens. |
| `APPLE_TEAM_ID` | yes | `iss` of the Apple client secret. |
| `APPLE_KEY_ID` | yes | `kid` of the Apple client secret. |
| `APPLE_PRIVATE_KEY` | yes | The `.p8` file's full PEM text, newlines and all. Read as-is; a value whose newlines were flattened to `\n` is also accepted. |
| `APPLE_BUNDLE_ID` | no | `app.cypress.Cypress`. In `fly.toml` `[env]`, not in secrets — it is in every copy of the app. |
| `OPERATOR_TOKEN` | yes | Authorizes the takedown route. Required: a takedown with no credential configured is a takedown that cannot be performed. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION`, `BUCKET_NAME` | yes | Already app secrets, set by `flyctl storage create` (see above). |

## Tests

```sh
go test ./...
```

The Apple half runs anywhere: token verification uses a locally-minted RSA key and an `httptest`
JWKS endpoint, never Apple, because a test that called Apple would be measuring Apple's uptime and
would pass by being skipped on a machine with no network.

**The SQL half needs a real Postgres and skips loudly without one:**

```sh
CYPRESS_TEST_DATABASE_URL='postgres://…/postgres' go test ./...
```

There is deliberately no in-memory double behind the store. Claim idempotency, the #174 guard, the
tombstone and the dedupe are all properties of `WHERE` clauses, `ON CONFLICT` arms, partial unique
indexes and `CHECK` constraints; a Go map re-implementing them would prove only that the map agrees
with itself, which is the shape of guard this project has repeatedly caught going green while the
defect it named was present. Each test binary creates its own database, so packages running in
parallel do not deadlock each other.

## Cost

- Machine: `shared-cpu-1x`/256MB is ~$2.02/month if it ran always-on. It is configured
  `auto_stop_machines = 'stop'`, `min_machines_running = 0`, so it stops when idle and is
  billed per second only while started — at scaffolding traffic that is a few cents/month.
- Tigris: first 5 GB storage free, $0.02/GB-month after; egress $0.
- No volume, no certificate, no dedicated IPv4 → no other line items.

**Expected: well under $1/month while idle; ~$2/month ceiling if something ever pins the
machine on.**

## The Apple revocation queue

`DELETE /me` calls Apple's revocation endpoint (R72 ruling 2). If Apple refuses, the token is parked
in `pending_apple_revocations` **before** the user row is deleted — otherwise the outage would
destroy the only credential that could ever satisfy the obligation.

It drains itself: `RunAppleRevocationDrain` retries on boot and every 15 minutes, deletes the row on
success, and counts attempts on failure. Retention is bounded at **30 days** (`AppleRevocationTTL`),
after which the row is deleted and an `ERROR` line records that a revocation was abandoned. That
bound is not tidiness: a parked refresh token, plus the client secret this service mints, exchanges
at Apple for that person's `sub` and email, so an unbounded queue would be an indefinite identity
pointer held after a screen that promised erasure.

**If you see `ABANDONED an Apple token revocation` in the logs**, an account was deleted here and
may still be granted at Apple. That is a real compliance gap and the line is the only record of it.

## Deploy

**Not from this branch.** Deployment is gated on the orchestrator, and the machine needs secrets and
a Postgres that do not exist yet. What it will need:

1. **Postgres.** `fly postgres create` (or an unmanaged single-node instance —
   `docs/investigations/api-hosting.md` §7 flags the choice as open and nothing in this design
   depends on it), then `fly postgres attach --app cypress-sync`, which sets `DATABASE_URL`.
2. **Secrets**, in one `fly secrets set`: `SESSION_SIGNING_KEY` (32+ random bytes),
   `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `OPERATOR_TOKEN`. The `AWS_*` and
   `BUCKET_NAME` values are already set on the app.
3. **An Apple `.p8` key** with Sign in with Apple enabled, and the Service ID / key configured in
   the Apple Developer account. Nothing in this repository can create one.
4. **The deploy itself**, unchanged from the placeholder's:

```sh
flyctl deploy --ha=false --build-arg GIT_SHA=$(git rev-parse HEAD)
```

`--ha=false` still matters: without it Fly creates a second machine, which is outside this app's
one-machine budget — and the rate limiter is in memory, so a second machine would also halve the
limit it thinks it is enforcing.

**One thing that is a code change, not a deploy step.** The rate limiter is per-process. If this app
ever runs more than one machine, it moves to Postgres or Redis first.
