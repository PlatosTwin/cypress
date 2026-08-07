#!/usr/bin/env python3
"""Tests for `appstore_connect.py feedback`. Pure Python, no network, no credentials.

    python3 Tools/test_appstore_connect_feedback.py

They run here rather than in `CypressTests` for the same reason as the ingest contract tests: the
thing under test is Python. `feedback` reads attacker-adjacent data — a submission id, a URL and a
response body all arrive over the network and all three decide what CI writes to disk — so the
properties worth pinning are the ones that are invisible in a green run against Apple's real API,
which returns well-formed values every time.

Every test states what would have to go wrong for it to fail, and the two security tests carry a
CONTROL that shows the same probe detecting the unsafe case. Without the control, "nothing
escaped" and "the probe does not work" are the same output.

The module is imported rather than shelled out to, which the `from __future__ import annotations`
in `appstore_connect.py` is what makes possible on the 3.9 that ships with macOS.
"""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import sys
import tempfile
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "appstore_connect", os.path.join(HERE, "appstore_connect.py"))
asc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(asc)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    print(("PASS " if condition else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not condition:
        FAILURES.append(name)


# ---------------------------------------------------------------------------------------------
# Fixtures: the smallest App Store Connect responses that exercise the paths under test.
# ---------------------------------------------------------------------------------------------

BUILD = {"id": "b-9", "type": "builds",
         "attributes": {"version": "9", "uploadedDate": "2026-07-30T09:00:00Z"}}

# A planted address in both the places Apple can put one: the submission's own attributes, and an
# included betaTesters resource. Neither may reach the output.
PLANTED_EMAIL = "planted-address@example.com"


def make_shot(shot_id: str = "shot-1") -> dict:
    return {
        "id": shot_id, "type": "betaFeedbackScreenshotSubmissions",
        "attributes": {
            "createdDate": "2026-08-01T10:00:00Z", "comment": "a comment",
            "deviceModel": "iPhone17_5", "osVersion": "26.5.2", "email": PLANTED_EMAIL,
            "screenshots": [{"url": "https://cdn.example/a.png", "width": 10, "height": 20,
                             "expirationDate": "2026-08-08T10:00:00Z"}],
        },
        "relationships": {"build": {"data": {"id": "b-9", "type": "builds"}},
                          "tester": {"data": {"id": "t-1", "type": "betaTesters"}}},
    }


TESTER = {"id": "t-1", "type": "betaTesters", "attributes": {"email": PLANTED_EMAIL}}


def router(fail_builds: bool = False, shot: dict | None = None,
           captured: list[str] | None = None):
    """A stand-in for `request_json` that answers from fixtures and can be told to fail."""
    def route(method: str, path: str, bearer: str, body: dict | None = None) -> dict:
        if captured is not None:
            captured.append(path)
        if path.startswith("/builds?"):
            if fail_builds:
                raise urllib.error.HTTPError(path, 403, "FORBIDDEN", {}, None)
            return {"data": [BUILD]}
        if "betaFeedbackScreenshotSubmissions" in path:
            return {"data": [shot] if shot else [], "included": [BUILD, TESTER]}
        if "betaFeedbackCrashSubmissions" in path:
            return {"data": []}
        if "appStoreVersions" in path or "customerReviews" in path:
            return {"data": []}
        raise AssertionError("fixture has no route for " + path)
    return route


def collect(**kwargs) -> dict:
    asc.request_json = router(**kwargs)
    return asc.collect_feedback("fixture-bearer", "APPID", None)


# ---------------------------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------------------------

def test_builds_failure_degrades() -> None:
    """Fails if a `/builds` error can end the whole run again.

    `/builds` is the first read and the most expendable one — `include=build` already sidecars the
    build resources — but it used to go through `call`, which exits the process. A key that could
    not read it produced no artifact at all, losing all four collections at once.
    """
    print("\n-- a /builds failure degrades instead of ending the run --")
    # BaseException, not SystemExit: the pre-fix path did not exit cleanly, it raised out of
    # `tempfile` while reading a body-less error response. A regression here must report FAIL,
    # not take the whole test run down with it.
    try:
        report = collect(fail_builds=True, shot=make_shot())
    except BaseException as error:  # noqa: BLE001 — deliberate, see above
        check("the run completes despite a 403 on /builds", False,
              f"{type(error).__name__}: {error}")
        return
    check("the run completes despite a 403 on /builds", True)
    check("a note records the failure", any("403" in n for n in report["notes"]),
          str(report["notes"])[:140])
    check("the screenshot collection survived", report["counts"]["screenshotSubmissions"] == 1)
    check("buildVersion still resolves, via include=build",
          report["screenshotSubmissions"][0]["buildVersion"] == "9")

    # CONTROL: with /builds healthy there is nothing to report, so the note above is not noise.
    healthy = collect(fail_builds=False, shot=make_shot())
    check("CONTROL: no notes when nothing fails", healthy["notes"] == [], str(healthy["notes"]))


def test_tester_address_is_never_fetched_or_emitted() -> None:
    """Fails if an address reaches the artifact, or if the command asks Apple for one.

    Two independent properties. The output must not contain the address (filtering), and the
    request must not have asked for the tester resource at all (not asking) — the second is what
    makes the first structural rather than a promise about a filter staying correct.
    """
    print("\n-- the tester's address is neither requested nor emitted --")
    calls: list[str] = []
    asc.request_json = router(shot=make_shot(), captured=calls)
    report = asc.collect_feedback("fixture-bearer", "APPID", None)

    includes = [c.split("include=")[1].split("&")[0] for c in calls if "include=" in c]
    check("no request includes the tester resource",
          includes and all("tester" not in value for value in includes), str(includes))
    check("the planted address is absent from the whole report",
          PLANTED_EMAIL not in json.dumps(report))
    check("it is absent even though the fixture put one in `included`",
          any(c for c in calls if "betaFeedbackScreenshotSubmissions" in c))
    check("the opaque tester id survives without the include",
          report["screenshotSubmissions"][0]["testerId"] == "t-1")
    check("`email` is not a key on the record",
          "email" not in report["screenshotSubmissions"][0])

    # CONTROL: the probe finds the address when it is somewhere the flattener keeps.
    poisoned = make_shot()
    poisoned["attributes"]["comment"] = f"reach me at {PLANTED_EMAIL}"
    record = asc.submission_record(poisoned, {"b-9": BUILD})
    check("CONTROL: the search finds a planted address in a field that IS kept",
          PLANTED_EMAIL in json.dumps(record))


def test_submission_id_cannot_choose_the_write_path() -> None:
    """Fails if a server-supplied id can place a file outside the screenshots directory.

    The id is opaque in practice, but "in practice" is not a property of a value that decides
    where CI writes. Note the control: the naive `join(dir, f"{id}-1.png")` really does escape.
    """
    print("\n-- a hostile submission id stays inside the screenshots directory --")
    sandbox = tempfile.mkdtemp(prefix="asc-feedback-test-")
    try:
        shots = os.path.join(sandbox, "screenshots")
        os.makedirs(shots)
        root = os.path.realpath(shots)
        hostile = "../../../../../../tmp/escaped"

        naive = os.path.realpath(os.path.join(shots, f"{hostile}-1.png"))
        check("CONTROL: the naive filename really does escape",
              not naive.startswith(root + os.sep), naive)

        for nasty in [hostile, "....//....//etc/passwd", "..", ".", "", "/etc/passwd",
                      "~/x", "a\x00b", "shot-1"]:
            target = asc.screenshot_path(shots, nasty, 1)
            contained = target is None or os.path.realpath(target).startswith(root + os.sep)
            check(f"id {nasty!r} cannot escape", contained, repr(target))

        # Both layers matter, and containment alone would satisfy the loop above by returning
        # None for everything. This pins the FIRST layer: the sanitizer must turn the traversal
        # into an ordinary filename, so a hostile-looking id still yields a written screenshot
        # rather than a silently dropped one. Without the substitution this is None.
        sanitized = asc.screenshot_path(shots, hostile, 1)
        check("the sanitizer resolves the traversal rather than the path check rejecting it",
              sanitized is not None, repr(sanitized))
        check("and what it produced is a flat filename, not a path",
              sanitized is not None and os.sep not in os.path.basename(sanitized)
              and os.path.dirname(os.path.realpath(sanitized)) == root,
              repr(os.path.basename(sanitized) if sanitized else None))

        legitimate = asc.screenshot_path(shots, "AM_YOYrGo2Mlq-upLpfPx1c", 1)
        check("a real ASC id is left intact",
              os.path.basename(legitimate or "") == "AM_YOYrGo2Mlq-upLpfPx1c-1.png",
              repr(legitimate))
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def test_download_refuses_non_https() -> None:
    """Fails if `urlopen` can be pointed at anything but https.

    `urlopen` honours `file://`, so without the guard a hostile `screenshots[].url` reads a local
    file off the runner and publishes it in the artifact.
    """
    print("\n-- download() refuses every scheme but https --")
    sandbox = tempfile.mkdtemp(prefix="asc-feedback-test-")
    try:
        secret = os.path.join(sandbox, "secret.txt")
        with open(secret, "w") as handle:
            handle.write("CONTENTS-THAT-MUST-NOT-BE-PUBLISHED")
        destination = os.path.join(sandbox, "out.png")

        for url in [f"file://{secret}", "http://cdn.example/a.png", "ftp://x/y", "",
                    "javascript:alert(1)"]:
            problem = asc.download(url, destination)
            check(f"{url[:26]!r} refused", "is not https" in problem, problem)

        check("nothing was written", not os.path.exists(destination))

        # CONTROL: the guard is about the scheme, not about refusing everything. An https URL gets
        # past it and fails later, on the network, with a different message.
        problem = asc.download("https://cdn.invalid.example/a.png", destination)
        check("CONTROL: https is not rejected by the scheme guard",
              "is not https" not in problem, problem)
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)


def main() -> None:
    test_builds_failure_degrades()
    test_tester_address_is_never_fetched_or_emitted()
    test_submission_id_cannot_choose_the_write_path()
    test_download_refuses_non_https()
    print(f"\n{len(FAILURES)} failing check(s)")
    for name in FAILURES:
        print(f"  {name}")
    sys.exit(1 if FAILURES else 0)


if __name__ == "__main__":
    main()
