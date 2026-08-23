#!/bin/bash
# Fetch the fused seed a build needs, resolved from the PIN this repository checks in and
# verified by hash before anything is allowed to use it.
#
# Usage: Tools/fetch_seed.sh [worktree-root]
#
# WHY THIS IS NOT `curl -o`. The seed is a ~103 MB git-ignored build product, so a fresh
# checkout has none, and without it 13 tests fail on `seedURL -> nil` and the app ships
# empty. It could be fetched from a fixed "latest" path -- and that is exactly the trap
# ERRATA E219 records: two seed builds declared the same generated_at and the same tree
# count while differing byte for byte, and nothing could tell them apart. So the seed is
# named by its own build_id, its sha256 is stated, and this script refuses any file that
# does not match. A seed you did not verify is an artifact you did not watch being produced.
#
# WHY THE PIN IS A FILE HERE AND NOT THE LIVE MANIFEST. Verifying against the manifest
# answered "did I download the file the bucket currently advertises", which is a weaker
# question than it looks: the answer changes when someone publishes, with no commit
# anywhere. On 2026-08-22 the s17 publish moved manifest.json and every job on main began
# compiling against a 706 MB three-city seed no `SeedCorpus` entry was pinned for -- main
# went red retroactively, from commits that had been green. A publish must not be able to
# do that. `Fixtures/seed/pinned-seed.json` is the version this tree builds against; a
# publish round bumps it deliberately, in the pull request that carries the constants
# moving with it. That file is also the whole of the bundle-scope ruling: it is what the
# app bundles, so pinning it to the pre-New-York artifact is what keeps the app ~103 MB
# with the boroughs arriving as downloads.
#
# The escape hatch, and what it is NOT for: CYPRESS_SEED_SOURCE=live restores the old
# behaviour and resolves from the published manifest. It exists for a publish round that
# wants the artifact currently on the bucket. It must never be how a red pin is made green,
# and CI must never set it -- a live fetch is not reproducible, and reproducibility is the
# entire point of this file.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PUBLIC="${CYPRESS_CITIES_BASE:-https://cypress-cities.t3.tigrisbucket.io}"
SOURCE="${CYPRESS_SEED_SOURCE:-pin}"
PIN="$ROOT/Fixtures/seed/pinned-seed.json"

say() { printf 'fetch_seed: %s\n' "$1"; }
die() { printf 'fetch_seed: FAIL: %s\n' "$1" >&2; exit 1; }

# ── Where the seed's identity comes from ─────────────────────────────────────────────
# Both branches produce the same four values -- path, sha256, bytes, and a human-readable
# name for where they came from -- so everything below this block is identical either way.
case "$SOURCE" in
pin)
  [ -f "$PIN" ] || die "no pin at $PIN. It is checked in: this is the version the tree builds against."

  # Captured in its own `if`, NOT as `read <<<"$(...)"`: a here-string is built before
  # `read` runs, so `read` succeeds on empty input and the pipeline's failure is thrown
  # away even under `set -e`. That bug shipped in the first draft of this script and sent
  # it on to download the bucket root.
  if ! seed_fields="$(python3 -c '
import json, sys
with open(sys.argv[1]) as handle:
    pin = json.load(handle)
missing = [k for k in ("path", "sha256", "bytes", "id_spaces") if not pin.get(k)]
if missing:
    sys.exit("the pin lacks " + ", ".join(missing))
spaces = pin["id_spaces"]
if not isinstance(spaces, list) or not all(isinstance(s, str) and s for s in spaces):
    sys.exit("the pin id_spaces must be a non-empty list of strings")
print(pin["path"], pin["sha256"], pin["bytes"], ",".join(sorted(spaces)))
' "$PIN")"; then
    die "$PIN is not a usable pin"
  fi
  read -r rel want_sha want_bytes want_spaces <<<"$seed_fields"
  origin="the pin, Fixtures/seed/pinned-seed.json"
  ;;
live)
  # The public domain caches manifest.json on the plain URL: minutes after a republish, a
  # bare GET still returned the previous manifest while `?cb=` returned the new one. A
  # build that resolves its seed from a stale manifest is self-consistent and wrong -- the
  # hash check below would pass against the OLD seed. So bust the cache and send no-cache,
  # and treat the freshness of this one file as load-bearing.
  say "CYPRESS_SEED_SOURCE=live -- resolving from the published manifest, NOT from the pin."
  say "  This is not reproducible: the answer changes when somebody publishes. Do not"
  say "  certify a test run, a warning count or a release from a tree fetched this way."
  manifest="$(curl -fsS --max-time 60 -H 'Cache-Control: no-cache' \
    "$PUBLIC/manifest.json?cb=$(date +%s)")" \
    || die "could not read $PUBLIC/manifest.json"

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
  # The manifest states no id-space list, so there is no scope to check against. Stated
  # rather than defaulted to the pin's: checking a live seed against the pin's scope would
  # answer a question nobody asked and would refuse every legitimate use of this branch.
  want_spaces=""
  origin="the live manifest at $PUBLIC"
  ;;
*)
  die "CYPRESS_SEED_SOURCE is '$SOURCE'; it is 'pin' (the default) or 'live'"
  ;;
esac

[ -n "$rel" ] && [ -n "$want_sha" ] && [ -n "$want_bytes" ] \
  || die "$origin did not fully describe a seed"

say "resolved from $origin"
say "$rel ($want_bytes bytes, sha256 ${want_sha:0:16}...)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsS --max-time 900 -o "$tmp/seed.sqlite" "$PUBLIC/$rel" \
  || die "download failed: $PUBLIC/$rel"

got_bytes="$(wc -c <"$tmp/seed.sqlite" | tr -d ' ')"
[ "$got_bytes" = "$want_bytes" ] \
  || die "size mismatch for $rel: got $got_bytes, $origin says $want_bytes"

got_sha="$(shasum -a 256 "$tmp/seed.sqlite" | cut -d' ' -f1)"
if [ "$got_sha" != "$want_sha" ]; then
  # The refusal has to say what to DO, because the three causes have three different
  # answers and only one of them is "run it again".
  cat >&2 <<EOF
fetch_seed: FAIL: sha256 mismatch for $rel
  expected  $want_sha
  got       $got_sha
  source    $origin

This is one of three things, and they are not fixed the same way:

  1. A truncated or corrupted download. Re-run this script; nothing is wrong with the tree.

  2. The object at that path changed. It must not -- published paths are write-once
     (RULING R37.2), which is what makes pinning one meaningful at all. Do not work around
     it: report it, because something is overwriting immutable objects in the bucket.

  3. The pin was edited without re-measuring the file it names. A publish round bumps
     Fixtures/seed/pinned-seed.json DELIBERATELY, and the numbers come off the artifact:

         shasum -a 256 <the-published-seed>
         wc -c <the-published-seed>

     and the same pull request carries the CypressTests/SeedCorpus.swift entry measured
     against it. See the pin's own "HOW TO BUMP IT".

Never make this green by widening the check or by setting CYPRESS_SEED_SOURCE=live. CI is
pinned so that a publish cannot break a commit that already passed; a live fetch is exactly
the retroactive breakage the pin exists to stop.
EOF
  exit 1
fi

# ── Is the file the SCOPE the pin claims? ────────────────────────────────────────────
# With a matching sha256 this cannot disagree about the download -- the hash already
# settles which bytes arrived. What it catches is a pin whose declared scope does not
# describe the file it names: a publish round bumping `sha256` and `path` to the newest
# fused seed by reflex, and quietly putting every published city inside the app. That is
# the bundle-scope ruling, checked at the only place that can see both the pin and the
# file. Skipped, with a line saying so, where there is no sqlite3 to ask -- the hash has
# already run, and a SILENT skip is the thing worth avoiding rather than the skip itself.
if [ -n "$want_spaces" ]; then
  if ! command -v sqlite3 >/dev/null 2>&1; then
    say "no sqlite3 on PATH, so the pinned scope [$want_spaces] was NOT checked against the file"
  else
    raw_spaces="$(sqlite3 "$tmp/seed.sqlite" \
      "SELECT value FROM seed_meta WHERE key = 'id_spaces_in_file';" 2>/dev/null || true)"
    got_spaces="$(printf '%s' "$raw_spaces" | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sort | paste -sd, -)"
    [ "$got_spaces" = "$want_spaces" ] || die \
"scope mismatch for $rel: the pin says id_spaces [$want_spaces], the file holds [$got_spaces].
  The pin names a seed of a different scope than it claims. If this is a publish round bumping
  the pin: the app BUNDLES this file, and the bundle is ruled to hold San Francisco and San
  Jose -- New York and every later city arrive as downloaded packs. Pin a seed of the ruled
  scope, or take that ruling back deliberately, in the open, with the app size stated."
    say "scope confirmed: id_spaces_in_file is [$got_spaces]"
  fi
fi

# Both destinations, because they are two different consumers and setup_worktree.sh
# already treats them as a pair: the app bundles Cypress/Resources, the suite's fixtures
# read Fixtures/seed.
#
# ONE file for both, still, and that is now a choice rather than an accident. The bundle
# ruling allows them to differ -- what CI tests and what the app ships need not be the same
# seed any more -- but almost every test that reads a seed reads it out of the APP BUNDLE
# (`SeedDatabase.urlInBundle`), so two files would mean the suite certifying one artifact
# while the build shipped another. They diverge the day something needs them to, and the
# pin grows a second entry that day.
for dest in "$ROOT/Cypress/Resources/cypress-seed.sqlite" "$ROOT/Fixtures/seed/cypress-seed.sqlite"; do
  mkdir -p "$(dirname "$dest")"
  cp "$tmp/seed.sqlite" "$dest"
  say "placed $dest"
done

say "verified sha256 $got_sha"
