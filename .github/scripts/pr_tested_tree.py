#!/usr/bin/env python3
"""Did this push's exact tree already pass the whole suite on its pull request?

Read by `plan` in `.github/workflows/testflight.yml` on a push to main. If the answer is a proved
yes, `unit`, `ui-build` and `ui` are skipped for the push, `release` still runs when the push ships,
and `gate` checks that the skip was for this reason (decision `tested-on-pr`).

Why this is safe, and the only reason it is: the pull request's run tested GitHub's merge commit
(`refs/pull/N/merge`), and a squash merge or a merge commit onto an up-to-date base (the ruleset
requires one, and allows both methods) writes a commit whose tree is the same tree. Same tree means the same bytes in every file: app, tests,
seed pin, and this workflow. So the suite that passed on the pull request ran on exactly what main
now holds. The proof is the tree hash, never the commit, the branch name or the PR number.

Where the tested tree comes from: `gate`, on a pull request, writes a record after it has checked
that plan decided `suite` and that unit, ui-build and ui all succeeded, and uploads it as the
artifact `suite-passed-tree`. Nothing else writes that artifact. This script reads it back.

Every doubt answers "run the suite": no merged pull request whose merge commit is this push, no
green run for its last head, no record, a record from another run or head, a record that does not
say every test job succeeded, a malformed hash, or any API error. A wrong "run" costs one suite
run; a wrong "skip" is a false green, so only an exact match skips.

Usage (in CI): pr_tested_tree.py --repo OWNER/NAME --sha <push sha> --tree <push tree> [--output FILE]
Prints its reasoning and writes `reuse=true|false`, `pr=`, `pr-run=` and `reason=` to --output.
The tests are `.github/scripts/test_pr_tested_tree.py`, which `plan` runs on every run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ARTIFACT = "suite-passed-tree"
RECORD_FILE = "suite-passed-tree.txt"
RECORD_HEADER = "cypress-suite-passed 1"
WORKFLOW_FILE = "testflight.yml"
HEX40 = re.compile(r"\A[0-9a-f]{40}\Z")
# How many green runs of the PR's last head to look at. A head usually has one; a re-run can add
# another. Bounded so a broken API answer cannot make this loop for long.
MAX_RUNS = 10


class GitHub:
    """The three questions this script asks GitHub, through the gh CLI. Tests replace this class."""

    def __init__(self, repo: str):
        self.repo = repo

    def _api(self, path: str):
        out = subprocess.run(["gh", "api", path], check=True, capture_output=True, text=True).stdout
        return json.loads(out)

    def pulls_for_commit(self, sha: str) -> list[dict]:
        return self._api(f"repos/{self.repo}/commits/{sha}/pulls")

    def pr_runs(self, head_sha: str) -> list[dict]:
        data = self._api(
            f"repos/{self.repo}/actions/workflows/{WORKFLOW_FILE}/runs"
            f"?event=pull_request&head_sha={head_sha}&status=completed&per_page={MAX_RUNS}"
        )
        return data.get("workflow_runs", [])

    def record(self, run_id: int) -> str | None:
        data = self._api(f"repos/{self.repo}/actions/runs/{run_id}/artifacts?name={ARTIFACT}")
        live = [a for a in data.get("artifacts", []) if a.get("name") == ARTIFACT and not a.get("expired")]
        if not live:
            return None
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(
                ["gh", "run", "download", str(run_id), "-R", self.repo, "-n", ARTIFACT, "-D", tmp],
                check=True, capture_output=True, text=True,
            )
            path = os.path.join(tmp, RECORD_FILE)
            if not os.path.isfile(path):
                return None
            with open(path, encoding="utf-8") as f:
                return f.read()


def parse_record(text: str) -> dict[str, str] | None:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines or lines[0] != RECORD_HEADER:
        return None
    fields: dict[str, str] = {}
    for line in lines[1:]:
        key, sep, value = line.partition("=")
        if not sep or key in fields:
            # A line with no `=`, or a key given twice, is not a record gate wrote.
            return None
        fields[key] = value
    return fields


def check_record(fields: dict[str, str] | None, run_id: int, head_sha: str, tree: str) -> str | None:
    """None when the record proves `tree` passed in run `run_id`; otherwise why it does not."""
    if fields is None:
        return "the record is malformed"
    if fields.get("decision") != "suite":
        return f"the record says decision={fields.get('decision')!r}, not suite"
    for job in ("unit", "ui-build", "ui"):
        if fields.get(job) != "success":
            return f"the record says {job}={fields.get(job)!r}, not success"
    if fields.get("run-id") != str(run_id):
        return f"the record names run {fields.get('run-id')!r}, not {run_id}"
    if fields.get("head-sha") != head_sha:
        return f"the record names head {fields.get('head-sha')!r}, not {head_sha}"
    recorded = fields.get("tree", "")
    if not HEX40.match(recorded):
        return f"the record's tree {recorded!r} is not a full hash"
    if recorded != tree:
        return f"that run tested tree {recorded}, and this push is tree {tree}"
    return None


def decide(api, sha: str, tree: str) -> dict[str, str]:
    """The whole decision. Returns the outputs; `reuse` is "true" only for a proved match."""

    def no(reason: str, **extra: str) -> dict[str, str]:
        print(f"run the suite: {reason}")
        return {"reuse": "false", "reason": reason, "pr": "", "pr-run": "", **extra}

    if not HEX40.match(sha) or not HEX40.match(tree):
        return no(f"the push sha {sha!r} or tree {tree!r} is not a full hash")

    merged = [p for p in api.pulls_for_commit(sha) if p.get("merged_at") and p.get("merge_commit_sha") == sha]
    if len(merged) != 1:
        return no(f"{len(merged)} merged pull requests have this push as their merge commit; exactly one is needed")
    pr = merged[0]
    number = str(pr.get("number", ""))
    head = (pr.get("head") or {}).get("sha", "")
    if not HEX40.match(head):
        return no(f"pull request #{number} has no readable head sha", pr=number)
    print(f"this push is the merge of pull request #{number}, whose last head was {head}")

    runs = [
        r for r in api.pr_runs(head)
        if r.get("event") == "pull_request" and r.get("head_sha") == head
        and r.get("status") == "completed" and r.get("conclusion") == "success"
    ]
    runs.sort(key=lambda r: int(r.get("id", 0)), reverse=True)
    if not runs:
        return no(f"no successful pull_request run of {WORKFLOW_FILE} exists for head {head}", pr=number)

    for run in runs[:MAX_RUNS]:
        run_id = int(run["id"])
        text = api.record(run_id)
        if text is None:
            print(f"  run {run_id}: no {ARTIFACT} record (gate did not write one, or it expired)")
            continue
        why_not = check_record(parse_record(text), run_id, head, tree)
        if why_not:
            print(f"  run {run_id}: {why_not}")
            continue
        reason = f"pull request #{number}, run {run_id}, passed the suite on tree {tree}, which is this push's tree"
        print(f"skip the suite: {reason}")
        return {"reuse": "true", "reason": reason, "pr": number, "pr-run": str(run_id)}

    return no(f"none of the {len(runs)} successful runs for head {head} proves this tree", pr=number)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Did this push's exact tree already pass on its pull request?")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--tree", required=True)
    ap.add_argument("--output", help="append key=value lines here (GITHUB_OUTPUT)")
    args = ap.parse_args(argv)
    try:
        result = decide(GitHub(args.repo), args.sha, args.tree)
    except Exception as exc:  # any API or download failure: the safe answer is to run the suite
        print(f"run the suite: the check could not finish ({type(exc).__name__}: {exc})")
        result = {"reuse": "false", "reason": "the check could not finish", "pr": "", "pr-run": ""}
    if args.output:
        with open(args.output, "a", encoding="utf-8") as f:
            for key in ("reuse", "pr", "pr-run", "reason"):
                f.write(f"{key}={result[key]}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
