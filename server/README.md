# `server/` — R36 live-layer scaffolding (PLACEHOLDER for #158)

Everything in this directory is a placeholder. It provisions and proves the infrastructure
R36 calls for; it does **not** implement the sync API. That is ticket **#158**, which is
spec-first, and the stack decision for it (Go, Node/Fastify, something else) is still open —
this Go file was chosen because it is boring and disposable, not because it is the answer.

R36: `docs/RULINGS.md`. The survey that chose Fly + Tigris: `docs/investigations/api-hosting.md`.

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

The bucket is **public read** (flipped 2026-08-01 for the R36 publish). Two gotchas, both
measured on 2026-08-01: Tigris serves anonymous reads only on the dedicated public domain
`https://cypress-cities.t3.tigrisbucket.io` — anonymous GET against the S3 API endpoints
(`fly.storage.tigris.dev`, `t3.storage.dev`) returns 403 AccessDenied even with the bucket
public. And on those API endpoints anonymous HEAD returned 200 while GET returned 403, so a
HEAD-based smoke check is a false green; verify publishes with a GET (dist/upload.sh does).

## Behavior

- `GET /health` → `200`, JSON: `status`, `service`, `git_sha`, `placeholder: true`, `ticket`.
- everything else, any method → `501`, JSON saying the sync API is not built yet.

## Cost

- Machine: `shared-cpu-1x`/256MB is ~$2.02/month if it ran always-on. It is configured
  `auto_stop_machines = 'stop'`, `min_machines_running = 0`, so it stops when idle and is
  billed per second only while started — at scaffolding traffic that is a few cents/month.
- Tigris: first 5 GB storage free, $0.02/GB-month after; egress $0.
- No volume, no certificate, no dedicated IPv4 → no other line items.

**Expected: well under $1/month while idle; ~$2/month ceiling if something ever pins the
machine on.**

## Deploy

One command, from this directory:

```sh
flyctl deploy --ha=false --build-arg GIT_SHA=$(git rev-parse HEAD)
```

`--ha=false` matters: without it Fly creates a second machine, which is outside this app's
one-machine budget.
