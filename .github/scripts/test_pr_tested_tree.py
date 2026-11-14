#!/usr/bin/env python3
"""Tests for pr_tested_tree.py: the main-push skip says yes only for a proved, exact match.

Run: python3 .github/scripts/test_pr_tested_tree.py   (`plan` runs it on every TestFlight run)

The first test is the calibration: a record that does prove the tree must give `reuse=true`, or
every "no" below would pass for the wrong reason (a script that always says no). Every other test
changes ONE fact of that same proved case and asserts the answer becomes "run the suite".
"""

import contextlib
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pr_tested_tree as m  # noqa: E402

SHA = "a" * 40
TREE = "b" * 40
HEAD = "c" * 40
RUN = 4242


def record(**over):
    fields = {
        "tree": TREE, "merge-commit": "d" * 40, "head-sha": HEAD, "run-id": str(RUN),
        "run-attempt": "1", "decision": "suite", "unit": "success", "ui-build": "success", "ui": "success",
    }
    fields.update(over)
    return m.RECORD_HEADER + "\n" + "".join(f"{k}={v}\n" for k, v in fields.items() if v is not None)


class FakeGitHub:
    def __init__(self, pulls=None, runs=None, records=None, fail=None):
        self.pulls = pulls if pulls is not None else [
            {"number": 7, "merged_at": "2026-11-13T00:00:00Z", "merge_commit_sha": SHA, "head": {"sha": HEAD}}
        ]
        self.runs = runs if runs is not None else [
            {"id": RUN, "event": "pull_request", "head_sha": HEAD, "status": "completed", "conclusion": "success"}
        ]
        self.records = records if records is not None else {RUN: record()}
        self.fail = fail

    def pulls_for_commit(self, sha):
        if self.fail == "pulls":
            raise RuntimeError("HTTP 502")
        return self.pulls

    def pr_runs(self, head):
        return self.runs

    def record(self, run_id):
        return self.records.get(run_id)


def decide(api, sha=SHA, tree=TREE):
    with contextlib.redirect_stdout(io.StringIO()):
        return m.decide(api, sha, tree)


class ProvedMatch(unittest.TestCase):
    def test_calibration_a_proved_tree_is_reused(self):
        out = decide(FakeGitHub())
        self.assertEqual(out["reuse"], "true")
        self.assertEqual(out["pr"], "7")
        self.assertEqual(out["pr-run"], str(RUN))

    def test_a_newer_unproved_run_does_not_hide_an_older_proved_one(self):
        runs = [
            {"id": RUN, "event": "pull_request", "head_sha": HEAD, "status": "completed", "conclusion": "success"},
            {"id": RUN + 1, "event": "pull_request", "head_sha": HEAD, "status": "completed", "conclusion": "success"},
        ]
        self.assertEqual(decide(FakeGitHub(runs=runs))["reuse"], "true")


class EveryDoubtRunsTheSuite(unittest.TestCase):
    def assertRuns(self, api, **kw):
        out = decide(api, **kw)
        self.assertEqual(out["reuse"], "false", out)

    def test_a_different_tree_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record(tree="e" * 40)}))

    def test_the_push_tree_differing_runs(self):
        self.assertRuns(FakeGitHub(), tree="f" * 40)

    def test_an_abbreviated_tree_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record(tree=TREE[:12])}), tree=TREE[:12])

    def test_no_record_runs(self):
        self.assertRuns(FakeGitHub(records={}))

    def test_a_record_from_another_run_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record(**{"run-id": str(RUN + 9)})}))

    def test_a_record_for_another_head_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record(**{"head-sha": "9" * 40})}))

    def test_a_record_of_a_skipped_suite_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record(decision="prose")}))

    def test_a_record_missing_a_job_runs(self):
        for job in ("unit", "ui-build", "ui"):
            with self.subTest(job=job):
                self.assertRuns(FakeGitHub(records={RUN: record(**{job: None})}))
                self.assertRuns(FakeGitHub(records={RUN: record(**{job: "failure"})}))

    def test_a_record_without_its_header_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record().split("\n", 1)[1]}))

    def test_a_record_with_a_repeated_key_runs(self):
        self.assertRuns(FakeGitHub(records={RUN: record() + f"tree={TREE}\n"}))

    def test_a_failed_or_unfinished_run_runs(self):
        for change in ({"conclusion": "failure"}, {"conclusion": "cancelled"}, {"status": "in_progress"},
                       {"event": "push"}, {"head_sha": "9" * 40}):
            run = {"id": RUN, "event": "pull_request", "head_sha": HEAD, "status": "completed", "conclusion": "success"}
            run.update(change)
            with self.subTest(change=change):
                self.assertRuns(FakeGitHub(runs=[run]))

    def test_no_merged_pr_runs(self):
        self.assertRuns(FakeGitHub(pulls=[]))
        self.assertRuns(FakeGitHub(pulls=[{"number": 7, "merged_at": None, "merge_commit_sha": SHA, "head": {"sha": HEAD}}]))
        self.assertRuns(FakeGitHub(pulls=[{"number": 7, "merged_at": "x", "merge_commit_sha": "0" * 40, "head": {"sha": HEAD}}]))

    def test_two_merged_prs_run(self):
        pr = {"number": 7, "merged_at": "x", "merge_commit_sha": SHA, "head": {"sha": HEAD}}
        self.assertRuns(FakeGitHub(pulls=[pr, dict(pr, number=8)]))

    def test_a_malformed_push_sha_runs(self):
        self.assertRuns(FakeGitHub(), sha="abc")

    def test_an_api_error_runs_and_main_still_writes_outputs(self):
        # Through main(), so the exception path is the one CI takes.
        real = m.GitHub
        m.GitHub = lambda repo: FakeGitHub(fail="pulls")
        out_path = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"pr-tested-tree-test-{os.getpid()}.txt")
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                rc = m.main(["--repo", "o/r", "--sha", SHA, "--tree", TREE, "--output", out_path])
            with open(out_path, encoding="utf-8") as f:
                written = f.read()
        finally:
            m.GitHub = real
            if os.path.exists(out_path):
                os.remove(out_path)
        self.assertEqual(rc, 0)
        self.assertIn("reuse=false\n", written)
        self.assertNotIn("reuse=true", written)


if __name__ == "__main__":
    unittest.main(verbosity=2)
