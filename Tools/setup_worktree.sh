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

set -eu
WT="${1:?usage: setup_worktree.sh <worktree-path>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/Cypress/Resources/cypress-seed.sqlite"

[ -d "$WT" ] || { echo "not a directory: $WT" >&2; exit 1; }
[ -f "$SEED" ] || { echo "seed missing at $SEED — main checkout is itself broken" >&2; exit 1; }

for DEST in "Cypress/Resources" "Fixtures/seed"; do
  mkdir -p "$WT/$DEST"
  cp "$SEED" "$WT/$DEST/cypress-seed.sqlite"
done

echo "seed ($(du -h "$SEED" | cut -f1 | tr -d ' ')) copied to $WT/{Cypress/Resources,Fixtures/seed}/"
echo "reminder: assign this agent its own simulator UDID and a private DerivedData dir (dd-<suffix>)."
