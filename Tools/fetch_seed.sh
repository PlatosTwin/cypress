#!/bin/bash
# Fetch the fused seed a build needs, resolved from the published manifest and verified
# by hash before anything is allowed to use it.
#
# Usage: Tools/fetch_seed.sh [worktree-root]
#
# WHY THIS IS NOT `curl -o`. The seed is a ~103 MB git-ignored build product, so a fresh
# checkout has none, and without it 13 tests fail on `seedURL -> nil` and the app ships
# empty. It could be fetched from a fixed "latest" path -- and that is exactly the trap
# ERRATA E219 records: two seed builds declared the same generated_at and the same tree
# count while differing byte for byte, and nothing could tell them apart. So the manifest
# names the seed by its own build_id, states its sha256, and this script refuses any file
# that does not match. A seed you did not verify is an artifact you did not watch being
# produced.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PUBLIC="${CYPRESS_CITIES_BASE:-https://cypress-cities.t3.tigrisbucket.io}"

say() { printf 'fetch_seed: %s\n' "$1"; }
die() { printf 'fetch_seed: FAIL: %s\n' "$1" >&2; exit 1; }

# The public domain caches manifest.json on the plain URL: minutes after a republish, a
# bare GET still returned the previous manifest while `?cb=` returned the new one. A build
# that resolves its seed from a stale manifest is self-consistent and wrong -- the hash
# check below would pass against the OLD seed. So bust the cache and send no-cache, and
# treat the freshness of this one file as load-bearing.
manifest="$(curl -fsS --max-time 60 -H 'Cache-Control: no-cache' \
  "$PUBLIC/manifest.json?cb=$(date +%s)")" \
  || die "could not read $PUBLIC/manifest.json"

# Captured in its own `if`, NOT as `read <<<"$(...)"`: a here-string is built before
# `read` runs, so `read` succeeds on empty input and the pipeline's failure is thrown
# away even under `set -e`. That bug shipped in the first draft of this script and sent
# it on to download the bucket root.
if ! seed_fields="$(printf '%s' "$manifest" | python3 -c '
import json, sys
m = json.load(sys.stdin)
s = m.get("source_seed", {})
missing = [k for k in ("path", "sha256", "bytes") if not s.get(k)]
if missing:
    sys.exit("manifest source_seed lacks " + ", ".join(missing)
             + " -- republish with a Tools/publish_cities.py that emits them")
print(s["path"], s["sha256"], s["bytes"])
')"; then
  die "manifest did not describe a fetchable seed"
fi
read -r rel want_sha want_bytes <<<"$seed_fields"
[ -n "$rel" ] && [ -n "$want_sha" ] && [ -n "$want_bytes" ] \
  || die "manifest source_seed was incomplete"

say "manifest names $rel ($want_bytes bytes, sha256 ${want_sha:0:16}...)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsS --max-time 900 -o "$tmp/seed.sqlite" "$PUBLIC/$rel" \
  || die "download failed: $PUBLIC/$rel"

got_bytes="$(wc -c <"$tmp/seed.sqlite" | tr -d ' ')"
[ "$got_bytes" = "$want_bytes" ] \
  || die "size mismatch: got $got_bytes, manifest says $want_bytes"

got_sha="$(shasum -a 256 "$tmp/seed.sqlite" | cut -d' ' -f1)"
[ "$got_sha" = "$want_sha" ] \
  || die "sha256 mismatch: got $got_sha, manifest says $want_sha"

# Both destinations, because they are two different consumers and setup_worktree.sh
# already treats them as a pair: the app bundles Cypress/Resources, the suite's fixtures
# read Fixtures/seed.
for dest in "$ROOT/Cypress/Resources/cypress-seed.sqlite" "$ROOT/Fixtures/seed/cypress-seed.sqlite"; do
  mkdir -p "$(dirname "$dest")"
  cp "$tmp/seed.sqlite" "$dest"
  say "placed $dest"
done

say "verified sha256 $got_sha"
