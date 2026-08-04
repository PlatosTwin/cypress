#!/bin/bash
# Stage graphify-out/ so the committed knowledge graph rides along with the code it describes.
#
# WHY THIS EXISTS. `graphify-out/` is tracked on purpose: anyone cloning this repo gets a
# ready-made graph database of the codebase without installing or running anything. That promise
# only holds if the tracked graph keeps up. graphify's own post-commit hook REBUILDS the graph but
# never commits it, so within one commit of installing it the tracked graph was already stale
# against HEAD. This is the missing half.
#
# WHY NOT IN CI. It was considered and rejected on evidence: graphify is not on PyPI
# (`pip index versions graphify` -> "No matching distribution found"), and is installed here as a
# uv tool named `graphifyy` from a source a GitHub runner has no path to. A CI job that cannot
# install the tool cannot rebuild the graph, and one that silently skipped would leave the graph
# stale while looking green. The compute already happens locally, on every commit, for free.
#
# WHY PRE-COMMIT AND NOT AFTER THE REBUILD. graphify rebuilds in a DETACHED process so `git commit`
# returns immediately — a full rebuild "can take hours" per its own hook. Committing from that
# background process would mean a commit appearing without anyone asking, racing whatever git
# operation is running at the time. Staging instead means the graph is always exactly one commit
# behind: commit N carries the rebuild triggered by commit N-1. For a graph of a codebase that is
# the difference between "current" and "current minus one file", and it costs no compute, no
# background commits, and no races.
#
# WHAT IT REFUSES TO STAGE. A rebuild in flight is writing these files right now, and a truncated
# graph.json committed as gospel is worse than a graph one commit older. Both checks below skip
# rather than fail: the next commit picks the graph up, and no commit is ever blocked by this.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/graphify-out"

[ -d "$OUT" ] || exit 0

# A rebuild in flight. `_rebuild_code` rather than "graphify": the detached child runs
# `python -c "<source>"`, so its whole argv carries the source text, and matching the bare word
# would also match this script's own path.
if pgrep -f _rebuild_code >/dev/null 2>&1; then
  echo "stage_graphify: a rebuild is running — leaving graphify-out for the next commit" >&2
  exit 0
fi

# Truncation check, cheap: a complete graph.json ends in `}`. Reading the last byte costs nothing,
# where parsing 54 MB of JSON on every commit would be felt.
GRAPH="$OUT/graph.json"
if [ -f "$GRAPH" ]; then
  last="$(tail -c 4 "$GRAPH" | tr -d '[:space:]')"
  case "$last" in
    *'}') ;;
    *) echo "stage_graphify: graph.json does not end in '}' — refusing to stage a half-written graph" >&2
       exit 0 ;;
  esac
fi

# `git add graphify-out` and nothing else. NOT `git add -A`: CLAUDE.md forbids it on main because
# another agent's untracked work can share this checkout, and one named directory is explicit in
# exactly the way `-A` is not. .gitignore inside graphify-out/ decides what within it is portable.
git -C "$ROOT" add graphify-out 2>/dev/null || exit 0

if ! git -C "$ROOT" diff --cached --quiet -- graphify-out; then
  echo "stage_graphify: staged $(git -C "$ROOT" diff --cached --name-only -- graphify-out | wc -l | tr -d ' ') graphify-out file(s)"
fi
