#!/bin/bash
# Prepare a fresh git worktree for an agent: copy the git-ignored seed database into both
# places the build and tests need it.
#
# Why: `git worktree add` does not carry the ~103 MB git-ignored seed, and without it 13
# tests fail with `seedURL → nil` (AlmanacVacantSiteTests, MapContentBudgetTests,
# SeedContractTests, BundleContractTests) — an agent that hits this spends an hour chasing
# a defect it did not cause. See docs/investigations/repeat-failures-postmortem.md.
#
# Usage: Tools/setup_worktree.sh <worktree-path>
#
# The copy is checked against `Fixtures/seed/pinned-seed.json`, which is the seed version the
# repository builds against. An agent whose seed differs from CI's is testing a different
# artifact than the one that will be judged, and the symptom is a suite that goes red on
# counts nobody changed — which is what happened across main on 2026-08-22. Set
# CYPRESS_SEED_UNPINNED=1 to copy anyway, for the one case that is legitimate: an offline
# machine, or a publish round deliberately holding the full-scope seed.

set -eu
WT="${1:?usage: setup_worktree.sh <worktree-path>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/Cypress/Resources/cypress-seed.sqlite"
PIN="$REPO/Fixtures/seed/pinned-seed.json"

[ -d "$WT" ] || { echo "not a directory: $WT" >&2; exit 1; }
[ -f "$SEED" ] || { echo "seed missing at $SEED — main checkout is itself broken" >&2; exit 1; }

if [ -f "$PIN" ] && [ "${CYPRESS_SEED_UNPINNED:-0}" != "1" ]; then
  WANT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$PIN")"
  GOT="$(shasum -a 256 "$SEED" | cut -d' ' -f1)"
  if [ "$WANT" != "$GOT" ]; then
    cat >&2 <<EOF
setup_worktree: the seed in this checkout is not the pinned one, so it was NOT copied.

  pinned  $WANT   (Fixtures/seed/pinned-seed.json)
  here    $GOT   ($SEED)

Fetch the pinned seed into the new worktree instead — it is one command and it verifies
what it downloads:

    Tools/fetch_seed.sh "$WT"

Copying anyway gives this agent a different artifact from the one CI judges, and the way that
shows up is a suite going red on counts nobody touched. If the difference is deliberate —
an offline machine, or a publish round holding the full-scope seed — re-run with
CYPRESS_SEED_UNPINNED=1.
EOF
    exit 1
  fi
fi

for DEST in "Cypress/Resources" "Fixtures/seed"; do
  mkdir -p "$WT/$DEST"
  cp "$SEED" "$WT/$DEST/cypress-seed.sqlite"
done

echo "seed ($(du -h "$SEED" | cut -f1 | tr -d ' ')) copied to $WT/{Cypress/Resources,Fixtures/seed}/"
echo "reminder: assign this agent its own simulator UDID and a private DerivedData dir (dd-<suffix>)."
