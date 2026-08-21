#!/usr/bin/env python3
"""Tests for `appstore_connect.py set-whats-new` and `builds-missing-notes`.

    python3 Tools/test_appstore_connect_whats_new.py

Pure Python, no network, no credentials: `request_json` is replaced by a small fake App Store
Connect that records what it was sent and hands back what it stored. Sibling of
`test_appstore_connect_feedback.py`, and it carries the same warning — **nothing runs this
automatically.** Run it by hand when touching either command.

WHAT IS WORTH PINNING HERE. The publish step runs once per release, at the end of a forty-minute
job, against a live account. It cannot be tried out. So the properties tested are the ones whose
failure would be invisible in a green run against the real API:

  * the two shapes of write -- POST when the build has no localization, PATCH when it has one --
    since a build starts with none and a re-run finds one, and only one of those two paths is ever
    exercised on any given release;
  * the read-back, which is the whole reason this is not "the PATCH returned 200";
  * refusing an empty or oversized body BEFORE the write, rather than discovering it as a 409.

Each gate has a control showing the same probe accepting the good case, because "nothing was
rejected" and "the probe rejects nothing" are the same output.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
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
# A fake App Store Connect: three endpoints, and a memory of what it was told.
# ---------------------------------------------------------------------------------------------

class FakeASC:
    def __init__(self, builds: list[dict], localizations: dict[str, list[dict]],
                 store_instead: str | None = None) -> None:
        self.builds = builds
        self.localizations = localizations
        # When set, every write stores THIS rather than what was sent -- the "the API said 200 and
        # kept something else" case the read-back exists for.
        self.store_instead = store_instead
        self.calls: list[tuple[str, str, dict | None]] = []

    def __call__(self, method: str, path: str, bearer: str, body: dict | None = None) -> dict:
        self.calls.append((method, path, body))
        if path.startswith("/apps?"):
            return {"data": [{"id": "app-1"}]}
        if path.startswith("/builds?"):
            return {"data": self.builds}
        if path.startswith("/builds/") and "betaBuildLocalizations" in path:
            build_id = path.split("/")[2]
            return {"data": self.localizations.get(build_id, [])}
        if method == "POST" and path == "/betaBuildLocalizations":
            attributes = dict(body["data"]["attributes"])
            if self.store_instead is not None:
                attributes["whatsNew"] = self.store_instead
            build_id = body["data"]["relationships"]["build"]["data"]["id"]
            self.localizations.setdefault(build_id, []).append(
                {"id": "loc-new", "attributes": attributes})
            return {"data": {"id": "loc-new"}}
        if method == "PATCH" and path.startswith("/betaBuildLocalizations/"):
            loc_id = path.rsplit("/", 1)[1]
            text = body["data"]["attributes"]["whatsNew"]
            if self.store_instead is not None:
                text = self.store_instead
            for items in self.localizations.values():
                for item in items:
                    if item["id"] == loc_id:
                        item["attributes"]["whatsNew"] = text
            return {"data": {"id": loc_id}}
        raise AssertionError(f"the fake was asked something it does not model: {method} {path}")


def with_fake(fake: FakeASC, function, *arguments):
    """Run `function` against `fake`, capturing stdout/stderr and the exit code.

    `token()` is stubbed too: it would otherwise demand three environment variables and import
    PyJWT, neither of which has anything to do with what is under test.
    """
    real_request, real_token = asc.request_json, asc.token
    real_out, real_err = sys.stdout, sys.stderr
    asc.request_json = fake
    asc.token = lambda: "fake-bearer"
    sys.stdout, sys.stderr = io.StringIO(), io.StringIO()
    code = 0
    try:
        function(*arguments)
    except SystemExit as exit_:
        code = exit_.code if isinstance(exit_.code, int) else 1
    finally:
        out, err = sys.stdout.getvalue(), sys.stderr.getvalue()
        asc.request_json, asc.token = real_request, real_token
        sys.stdout, sys.stderr = real_out, real_err
    return code, out, err


def note_file(text: str) -> str:
    handle = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    return handle.name


BUILD_44 = {"id": "b-44", "type": "builds",
            "attributes": {"version": "44", "expired": False, "processingState": "VALID"}}
BUILD_43 = {"id": "b-43", "type": "builds",
            "attributes": {"version": "43", "expired": True, "processingState": "VALID"}}

NOTES = "• You can now pinch to zoom a tree's photos."


def test_creates_a_localization_when_the_build_has_none() -> None:
    fake = FakeASC([BUILD_44], {})
    code, out, err = with_fake(fake, asc.cmd_set_whats_new, ["44", "--file", note_file(NOTES)])
    check("a build with no localization gets one created", code == 0, err.strip())
    posts = [c for c in fake.calls if c[0] == "POST"]
    check("...by POST, exactly once", len(posts) == 1, str([c[:2] for c in fake.calls]))
    check("...carrying the compiled text and the en-US locale",
          posts and posts[0][2]["data"]["attributes"] ==
          {"locale": "en-US", "whatsNew": NOTES},
          json.dumps(posts[0][2]["data"]["attributes"]) if posts else "")
    check("...and the text is echoed to the job log", NOTES in out, out.strip())


def test_updates_the_localization_that_is_already_there() -> None:
    fake = FakeASC([BUILD_44],
                   {"b-44": [{"id": "loc-1",
                              "attributes": {"locale": "en-US", "whatsNew": "stale"}}]})
    code, out, err = with_fake(fake, asc.cmd_set_whats_new, ["44", "--file", note_file(NOTES)])
    check("an existing localization is updated, not duplicated", code == 0, err.strip())
    check("...by PATCH", any(c[0] == "PATCH" for c in fake.calls),
          str([c[:2] for c in fake.calls]))
    check("...and no second localization is created",
          not any(c[0] == "POST" for c in fake.calls))
    check("...leaving one localization holding the new text",
          len(fake.localizations["b-44"]) == 1
          and fake.localizations["b-44"][0]["attributes"]["whatsNew"] == NOTES)


def test_the_read_back_catches_a_write_that_lied() -> None:
    """A 200 that stored something else. Without the read-back this run is green and wrong."""
    fake = FakeASC([BUILD_44], {}, store_instead="something else entirely")
    code, out, err = with_fake(fake, asc.cmd_set_whats_new, ["44", "--file", note_file(NOTES)])
    check("a write that stored different text is caught", code != 0, f"exit {code}")
    check("...and the error shows both texts",
          "sent" in err and "stored" in err and "something else entirely" in err, err.strip())

    # CONTROL: the identical probe over a fake that stores honestly must pass. Otherwise this test
    # would also pass against a read-back that always fails.
    honest = FakeASC([BUILD_44], {})
    code2, _, err2 = with_fake(honest, asc.cmd_set_whats_new, ["44", "--file", note_file(NOTES)])
    check("CONTROL: an honest write passes the same read-back", code2 == 0, err2.strip())


def test_refuses_an_empty_or_oversized_body_before_writing() -> None:
    empty = FakeASC([BUILD_44], {})
    code, _, err = with_fake(empty, asc.cmd_set_whats_new, ["44", "--file", note_file("\n\n")])
    check("an empty notes file is refused", code != 0, f"exit {code}")
    check("...before any request is made", empty.calls == [], str(empty.calls))
    check("...naming the ruling rather than just erroring",
          "every build ships a changelog" in err.lower(), err.strip())

    big = FakeASC([BUILD_44], {})
    code2, _, err2 = with_fake(
        big, asc.cmd_set_whats_new,
        ["44", "--file", note_file("x" * (asc.WHATS_NEW_LIMIT + 1))])
    check("a body over the App Store Connect limit is refused", code2 != 0, f"exit {code2}")
    check("...also before any request", big.calls == [], str(big.calls))

    # CONTROL: exactly at the limit goes through, so the refusal is about the size.
    edge = FakeASC([BUILD_44], {})
    code3, _, err3 = with_fake(edge, asc.cmd_set_whats_new,
                               ["44", "--file", note_file("x" * asc.WHATS_NEW_LIMIT)])
    check("CONTROL: exactly at the limit is accepted", code3 == 0, err3.strip())


def test_refuses_a_build_that_is_not_there() -> None:
    fake = FakeASC([BUILD_43], {})
    code, _, err = with_fake(fake, asc.cmd_set_whats_new, ["44", "--file", note_file(NOTES)])
    check("a build App Store Connect does not hold is an error", code != 0, f"exit {code}")
    check("...naming the build", "44" in err, err.strip())


def test_builds_missing_notes_skips_a_build_that_is_still_processing() -> None:
    """Review F8. A `PROCESSING` build has no localizations, so it reads as missing its notes.

    The backstop would then try to write to it, App Store Connect may refuse a write against a
    build in that state, and a scheduled job goes red on a transient that fixes itself an hour
    later. This job's whole value is that a red from it means something.
    """
    processing = {"id": "b-45", "attributes": {"version": "45", "expired": False,
                                               "processingState": "PROCESSING"}}
    invalid = {"id": "b-46", "attributes": {"version": "46", "expired": False,
                                            "processingState": "INVALID"}}
    fake = FakeASC([invalid, processing, BUILD_44], {})
    code, out, err = with_fake(fake, asc.cmd_builds_missing_notes)
    listed = out.split()
    check("a build that is still PROCESSING is not listed", "45" not in listed, str(listed))
    check("an INVALID build is not listed either", "46" not in listed, str(listed))
    check("...and the skips are named rather than silent",
          "'PROCESSING'" in err and "'INVALID'" in err, err.strip())
    check("...while the VALID build with no notes still is",
          code == 0 and listed == ["44"], f"{listed!r} {err.strip()}")

    # CONTROL: flip the same two builds to VALID and they appear, so the filter is about the
    # state and not about the fixture.
    control_builds = [dict(b, attributes=dict(b["attributes"], processingState="VALID"))
                      for b in (invalid, processing, BUILD_44)]
    control = FakeASC(control_builds, {})
    _, out2, _ = with_fake(control, asc.cmd_builds_missing_notes)
    check("CONTROL: the same three builds all list once they are VALID",
          sorted(out2.split()) == ["44", "45", "46"], str(out2.split()))


def test_builds_missing_notes_lists_only_live_empty_builds() -> None:
    fake = FakeASC(
        [BUILD_44, BUILD_43,
         {"id": "b-42", "attributes": {"version": "42", "expired": False,
                                       "processingState": "VALID"}}],
        {"b-42": [{"id": "loc-42",
                   "attributes": {"locale": "en-US", "whatsNew": "already written"}}]})
    code, out, err = with_fake(fake, asc.cmd_builds_missing_notes)
    listed = out.split()
    check("the live build with no notes is listed", code == 0 and listed == ["44"],
          f"{listed!r} {err.strip()}")
    check("...the expired build is not", "43" not in listed)
    check("...and neither is the one that already has notes", "42" not in listed)


def main() -> int:
    for name, function in sorted(globals().items()):
        if name.startswith("test_") and callable(function):
            print(f"\n-- {name}")
            function()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED: " + ", ".join(FAILURES))
        return 1
    print("all set-whats-new tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
