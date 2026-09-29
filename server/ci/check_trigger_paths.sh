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
# How it checks coverage: each candidate path must appear as a `paths:` list entry under
# `on.push`, read from that section alone — not a whole-file occurrence count.
#
# **`on.push` is the only list, and there must be no `on.pull_request`.** Pull requests do not start
# this workflow themselves: `testflight.yml`'s `plan` reads this same `on.push.paths` list and calls
# the workflow (`workflow_call`) as its `server` job, which `gate` — the required check — refuses
# to pass without. That is how the suite is required without a path-filtered required check that
# never reports (E225). So a path covered under `push` is covered on pull requests too, and a
# `pull_request` trigger coming back is refused here: it would be the suite twice per pull request,
# the second copy racing the called one for the same concurrency group.
#
# Until 2026-09-28 this checked `push` AND `pull_request`, counted separately per section. Comment lines are ignored (a line is a comment once `#` is stripped, whether the whole
# line is commented out or the `#` starts a trailing comment). This is a plain indentation-based
# block extraction (no PyYAML dependency — the runner may not have it installed), done via a
# small embedded python3 script rather than shell, because "count matches inside the `push:`
# block but not the `pull_request:` block" needs real structure, not a substring count anywhere in
# the file. Earlier, this script counted `grep -cF -- "- 'path'" "$workflow" >= 2` file-wide, which
# a duplicate-under-one-trigger or a commented-out duplicate would both satisfy without the path
# being covered under both triggers — a guard green while the defect it exists to catch is present.
#
# Usage: server/ci/check_trigger_paths.sh <workflow-file>   (run from the repository root)
# The workflow-file argument can point at any copy of the file, not just the real workflow — this
# is how the calibration specimens below are tested without editing `.github/workflows/server.yml`
# itself.
set -euo pipefail

workflow="${1:?usage: $0 <workflow-file>}"
[ -s "$workflow" ] || { echo "TRIGGER-PATHS-FAIL: workflow '$workflow' is missing or empty"; exit 1; }

read_paths="$(grep -rhoE '"\.\./\.\./\.\./[^"]+"' --include='*.go' server | tr -d '"' | sed 's#^\.\./\.\./\.\./##' | sort -u)"
[ -n "$read_paths" ] || { echo "TRIGGER-PATHS-FAIL: found no cross-tree reads at all, which cannot be right — the search is not reading server/"; exit 1; }

# Extract the `paths:` list under on.push and on.pull_request separately. Prints two blocks,
# "PUSH" and "PULL_REQUEST", each followed by its section's path entries (one per line, quotes
# stripped, comments already removed). Pure line/indentation parsing: no external YAML library.
extracted="$(python3 - "$workflow" <<'PY'
import re
import sys

workflow_path = sys.argv[1]
with open(workflow_path, encoding="utf-8") as f:
    raw_lines = f.readlines()


def strip_comment(line):
    """Remove a trailing '#' comment that is not inside a quoted string."""
    in_squote = False
    in_dquote = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_dquote:
            in_squote = not in_squote
        elif ch == '"' and not in_squote:
            in_dquote = not in_dquote
        elif ch == "#" and not in_squote and not in_dquote:
            return line[:i]
    return line


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


# (indent, stripped-content-without-trailing-whitespace, original-line-number) for every
# non-blank, non-comment-only line.
lines = []
for lineno, raw in enumerate(raw_lines, start=1):
    content = strip_comment(raw.rstrip("\n")).rstrip()
    if content.strip() == "":
        continue
    lines.append((indent_of(content), content.strip(), lineno))


def find_child(start_i, parent_indent, name_pattern):
    """Search forward from start_i (exclusive) for a line at indent > parent_indent whose
    content matches name_pattern, stopping as soon as a line at indent <= parent_indent is seen
    (that means we left the parent's block). Returns the index into `lines`, or None."""
    for i in range(start_i, len(lines)):
        indent, content, _ = lines[i]
        if indent <= parent_indent:
            return None
        if re.match(name_pattern, content):
            return i
    return None


def collect_list_items(start_i, parent_indent):
    """Collect '- <quoted string>' items directly under the key at start_i, which sits at
    parent_indent. Items must be indented deeper than parent_indent; stop at the first line back
    at or above parent_indent."""
    items = []
    for i in range(start_i + 1, len(lines)):
        indent, content, _ = lines[i]
        if indent <= parent_indent:
            break
        m = re.match(r"^-\s*(['\"])(.*?)\1\s*$", content)
        if m:
            items.append(m.group(2))
        # A non-list-item line deeper than parent_indent (e.g. a comment already stripped to
        # nothing, or another key) is simply not a path entry; keep scanning until dedent.
    return items


def paths_for_section(section_name):
    on_idx = find_child(0, -1, r"^on:\s*$")
    if on_idx is None:
        return []
    on_indent = lines[on_idx][0]
    section_idx = find_child(on_idx + 1, on_indent, rf"^{section_name}:\s*$")
    if section_idx is None:
        return []
    section_indent = lines[section_idx][0]
    paths_idx = find_child(section_idx + 1, section_indent, r"^paths:\s*$")
    if paths_idx is None:
        return []
    paths_indent = lines[paths_idx][0]
    return collect_list_items(paths_idx, paths_indent)


def has_section(section_name):
    on_idx = find_child(0, -1, r"^on:\s*$")
    if on_idx is None:
        return False
    return find_child(on_idx + 1, lines[on_idx][0], rf"^{section_name}:") is not None


print("HAS_PULL_REQUEST" if has_section("pull_request") else "NO_PULL_REQUEST")
print("PUSH")
for p in paths_for_section("push"):
    print(p)
PY
)"

if [ "$(printf '%s\n' "$extracted" | head -1)" = "HAS_PULL_REQUEST" ]; then
  echo "TRIGGER-PATHS-FAIL: '$workflow' has an on.pull_request trigger. Pull requests run this suite through testflight.yml's server job (workflow_call), which gate requires; a second trigger would run it twice and race the called run for the concurrency group. Remove it."
  exit 1
fi
push_paths="$(printf '%s\n' "$extracted" | sed -n '/^PUSH$/,$p' | sed '1d')"
[ -n "$push_paths" ] || { echo "TRIGGER-PATHS-FAIL: found no on.push.paths in '$workflow' — the reader is not reading the trigger"; exit 1; }

missing=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if grep -qxF -- "$path" <<< "$push_paths"; then
    echo "  covered: $path"
  else
    echo "  missing: $path (needs an entry under on.push.paths, which is also the list pull requests run on)"
    missing=$((missing + 1))
  fi
done <<< "$read_paths"

if [ "$missing" -ne 0 ]; then
  echo "TRIGGER-PATHS-FAIL: $missing file(s) a Go test reads would not start this workflow when changed"
  exit 1
fi
echo "TRIGGER-PATHS-OK: every file outside server/ that a Go test reads triggers this workflow"
