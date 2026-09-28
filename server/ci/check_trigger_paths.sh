#!/bin/bash
# Every file outside `server/` that a Go test opens must be a path that starts the server workflow.
#
# The Go suite is not self-contained: several tests parse Swift sources in `Cypress/` at run time
# to prove the wire vocabulary still agrees with the client (`swiftEnumRawValues`,
# `swiftStoredPropertyNames`, `assertVocabularyMatches`, `apierr_test.go`'s `clientSourcePath`).
# A rename in one of those Swift files touches no `server/` path, so without a trigger entry the
# guard that exists to catch it would not run on the change that breaks it — and would first go
# red on some later, unrelated server change, looking like that change's fault. This is
# `web.yml`'s rule ("a file a web test opens is a file that triggers the web suite") applied here.
#
# How it finds them: every string literal of the form "../../../<path>" in a Go file under
# `server/` — the shape every one of those readers uses today, since tests run with the package
# directory as their working directory and every package with tests is two levels deep. A reader
# that builds its path some other way is invisible to this check; that is a known limit, not a
# guarantee.
#
# Usage: server/ci/check_trigger_paths.sh <workflow-file>   (run from the repository root)
set -euo pipefail

workflow="${1:?usage: $0 <workflow-file>}"
[ -s "$workflow" ] || { echo "TRIGGER-PATHS-FAIL: workflow '$workflow' is missing or empty"; exit 1; }

read_paths="$(grep -rhoE '"\.\./\.\./\.\./[^"]+"' --include='*.go' server | tr -d '"' | sed 's#^\.\./\.\./\.\./##' | sort -u)"
[ -n "$read_paths" ] || { echo "TRIGGER-PATHS-FAIL: found no cross-tree reads at all, which cannot be right — the search is not reading server/"; exit 1; }

missing=0
while IFS= read -r path; do
  # Twice: once under `push`, once under `pull_request`. A path listed in one trigger only is the
  # half-covered shape this check exists to refuse.
  n="$(grep -cF -- "- '$path'" "$workflow" || true)"
  if [ "$n" -lt 2 ]; then
    echo "  missing: $path (listed $n time(s); needs one under push and one under pull_request)"
    missing=$((missing + 1))
  else
    echo "  covered: $path"
  fi
done <<< "$read_paths"

if [ "$missing" -ne 0 ]; then
  echo "TRIGGER-PATHS-FAIL: $missing file(s) a Go test reads would not start this workflow when changed"
  exit 1
fi
echo "TRIGGER-PATHS-OK: every file outside server/ that a Go test reads triggers this workflow"
