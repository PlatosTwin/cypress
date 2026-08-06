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
