#!/usr/bin/env python3
"""Tests for `whats_new.py`. Pure Python and real `git`, no network, no credentials.

    python3 Tools/test_whats_new.py

NOTHING RUNS THIS AUTOMATICALLY, the same as `test_appstore_connect_feedback.py`,
`test_inventory_contract.py` and `test_ca_inventory_adapter.py`. Wiring all of them into CI is
filed separately; it is said here rather than left implicit because the enforcement this file
covers is a gate, and a gate whose own test never runs is weaker protection than its existence
suggests. Run it by hand when touching `whats_new.py`.

**Every test builds a real repository in a temporary directory and runs the real `git`.** The
alternative -- stubbing `git()` -- would test the parsing and skip the only interesting part,
which is whether `git ls-tree`, `git diff --diff-filter=A` and `git log --name-only` answer the
question they are being asked. Three of the four wrong conclusions CLAUDE.md records came from
exactly that gap: a command that ran fine and answered a different question.

**Both directions, every time.** A test that only shows the check passing on a good diff cannot
tell "the check works" from "the check always passes". Each gate below has a must-pass case and a
must-fail case over the same fixture, and the failing one asserts the exit code AND that the
message names what to do.
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "whats_new.py")
_spec = importlib.util.spec_from_file_location("whats_new", TOOL)
wn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wn)

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    print(("PASS " if condition else "FAIL ") + name + (("  " + detail) if detail else ""))
    if not condition:
        FAILURES.append(name)


# ---------------------------------------------------------------------------------------------
# A repository, built commit by commit, so the history under test is the history intended.
# ---------------------------------------------------------------------------------------------

class Repo:
    """A throwaway git repository with a deterministic identity and committer clock.

    The dates are fixed and increasing: `added_when` sorts by commit time, and a fixture whose
    commits all land in the same second would make the ordering test pass or fail on how fast the
    machine is.
    """

    def __init__(self, directory: str) -> None:
        self.dir = directory
        self.clock = 1_760_000_000
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "T")
        self.write("README.md", "root\n")
        self.commit("root")

    def git(self, *arguments: str) -> str:
        finished = subprocess.run(("git",) + arguments, cwd=self.dir,
                                  capture_output=True, text=True)
        if finished.returncode != 0:
            raise RuntimeError(f"git {' '.join(arguments)}: {finished.stderr}")
        return finished.stdout.strip()

    def write(self, path: str, text: str) -> None:
        full = os.path.join(self.dir, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as handle:
            handle.write(text)

    def remove(self, path: str) -> None:
        os.remove(os.path.join(self.dir, path))

    def commit(self, message: str) -> str:
        self.clock += 60
        stamp = f"{self.clock} +0000"
        self.git("add", "-A")
        environment = dict(os.environ,
                           GIT_AUTHOR_DATE=stamp, GIT_COMMITTER_DATE=stamp)
        finished = subprocess.run(
            ("git", "commit", "--quiet", "-m", message),
            cwd=self.dir, capture_output=True, text=True, env=environment)
        if finished.returncode != 0:
            raise RuntimeError(finished.stderr)
        return self.git("rev-parse", "HEAD")

    def branch(self, name: str) -> None:
        self.git("checkout", "--quiet", "-b", name)

    def switch(self, name: str) -> None:
        self.git("checkout", "--quiet", name)

    def tag(self, name: str) -> None:
        self.git("tag", name)


def run(repo: Repo, *arguments: str) -> subprocess.CompletedProcess:
    """`whats_new.py` as CI runs it: a subprocess, in the repository, exit code and both streams.

    Not an in-process call. The module's `git()` reads the process's working directory, and an
    in-process test would either have to chdir -- which leaks between tests -- or prove nothing
    about the thing CI actually invokes.
    """
    return subprocess.run((sys.executable, TOOL) + arguments,
                          cwd=repo.dir, capture_output=True, text=True)


NOTE = "docs/whats-new/"


# ---------------------------------------------------------------------------------------------
# check: the gate that stops a code change merging without its line
# ---------------------------------------------------------------------------------------------

def test_check_both_directions() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        base = repo.git("rev-parse", "HEAD")

        # MUST FAIL: a code change with no note.
        repo.branch("no-note")
        repo.write("Cypress/Features/Thing.swift", "// a change\n")
        head = repo.commit("a code change, no note")
        bad = run(repo, "check", "--base", base, "--head", head)
        check("check fails on a code change carrying no note", bad.returncode != 0,
              f"exit {bad.returncode}")
        check("...and the message says where to put the note",
              NOTE in bad.stderr and "internal:" in bad.stderr)

        # MUST PASS: the same diff, plus a note.
        repo.write(NOTE + "thing.md", "You can now see a thing.\n")
        head2 = repo.commit("the note")
        good = run(repo, "check", "--base", base, "--head", head2)
        check("check passes once the note is added", good.returncode == 0,
              good.stdout.strip() or good.stderr.strip())
        check("...and it echoes the line it accepted",
              "tester-visible" in good.stdout and "You can now see a thing." in good.stdout)


def test_check_accepts_the_escape_hatch() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        base = repo.git("rev-parse", "HEAD")
        repo.branch("internal-only")
        repo.write("Tools/thing.py", "# a change\n")
        repo.write(NOTE + "internal.md", "internal: a refactor; no tester-visible change.\n")
        head = repo.commit("internal change")
        result = run(repo, "check", "--base", base, "--head", head)
        check("an `internal:` line satisfies the check", result.returncode == 0,
              result.stderr.strip())
        check("...and is labelled as internal in the log", "internal:" in result.stdout)

        # ── The anchoring, which review F4 found asserted in a comment and tested nowhere ──
        # A real tester-voice line is free to use the word mid-sentence, and an unanchored
        # `"internal:" in line` would silently drop it from the changelog with `check` green and
        # `compile` exit 0. Mutating `startswith` to `in` used to leave all 39 checks passing.
        repo.tag("build-80")
        repo.write(NOTE + "mentions.md",
                   "The sync queue now shows an internal: prefix on rows it could not send.\n")
        repo.commit("a tester-visible line that happens to use the word")
        compiled = run(repo, "compile", "--at", "HEAD")
        check("a line that MENTIONS 'internal:' mid-sentence is still shipped",
              "The sync queue now shows an internal: prefix" in compiled.stdout,
              compiled.stdout.strip())

        # CONTROL: the same probe over a line that genuinely STARTS with it must drop it, so the
        # assertion above is about the anchor rather than about shipping everything.
        repo.tag("build-81")
        repo.write(NOTE + "hatch.md", "internal: a refactor; no tester-visible change.\n")
        repo.commit("an actual escape-hatch line")
        control = run(repo, "compile", "--at", "HEAD")
        check("CONTROL: a line that starts with it is still dropped",
              "a refactor; no tester-visible change" not in control.stdout,
              control.stdout.strip())


def test_check_rejects_an_edit_to_a_shipped_note() -> None:
    """The must-fail case that a naive `--name-only` would let through."""
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "old.md", "An older line.\n")
        base = repo.commit("a note that already exists on main")

        repo.branch("edits-the-old-note")
        repo.write("Cypress/Features/Thing.swift", "// a change\n")
        repo.write(NOTE + "old.md", "An older line, reworded.\n")
        head = repo.commit("code, plus an edit to somebody else's note")
        result = run(repo, "check", "--base", base, "--head", head)
        check("editing an existing note does not answer the check", result.returncode != 0,
              f"exit {result.returncode}")

        # CONTROL: the same probe accepting the same diff once a NEW file is added, which is what
        # separates "the check rejects edits" from "the check rejects this fixture".
        repo.write(NOTE + "new.md", "You can now do the thing.\n")
        head2 = repo.commit("and a new note")
        control = run(repo, "check", "--base", base, "--head", head2)
        check("CONTROL: adding a new note answers it", control.returncode == 0,
              control.stderr.strip())


def test_check_rejects_an_empty_note_and_an_overlong_one() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        base = repo.git("rev-parse", "HEAD")
        repo.branch("empty")
        repo.write("Cypress/A.swift", "//\n")
        repo.write(NOTE + "empty.md", "# only a comment\n\n")
        head = repo.commit("a note file with no note in it")
        empty = run(repo, "check", "--base", base, "--head", head)
        check("a comment-only note file is not a note", empty.returncode != 0,
              f"exit {empty.returncode}")

        repo.write(NOTE + "empty.md", "x" * (wn.MAX_LINE + 1) + "\n")
        head2 = repo.commit("a note line far too long")
        long = run(repo, "check", "--base", base, "--head", head2)
        check("a note line over MAX_LINE is refused", long.returncode != 0,
              f"exit {long.returncode}")
        check("...and the message says how long it is",
              str(wn.MAX_LINE + 1) in long.stderr)

        # CONTROL: one character shorter passes, so the refusal is about the length and not about
        # the fixture.
        repo.write(NOTE + "empty.md", "x" * wn.MAX_LINE + "\n")
        head3 = repo.commit("a note line exactly at the limit")
        control = run(repo, "check", "--base", base, "--head", head3)
        check("CONTROL: exactly MAX_LINE passes", control.returncode == 0,
              control.stderr.strip())


def test_check_ignores_the_readme() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        base = repo.git("rev-parse", "HEAD")
        repo.branch("readme-only")
        repo.write("Cypress/A.swift", "//\n")
        repo.write(NOTE + "README.md", "how this directory works\n")
        head = repo.commit("code plus the directory's own README")
        result = run(repo, "check", "--base", base, "--head", head)
        check("the directory README does not count as a note", result.returncode != 0,
              f"exit {result.returncode}")


def test_check_refuses_a_revision_it_cannot_see() -> None:
    """A shallow clone must fail loudly, not pass vacuously.

    This is the failure this project keeps paying for: a gate that cannot answer its question and
    reports success. `check` on an unknown base must be red.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        result = run(repo, "check", "--base", "0" * 40, "--head", "HEAD")
        check("an unreachable base is an error, not a pass", result.returncode != 0,
              f"exit {result.returncode}")
        check("...and says why", "shallow" in result.stderr.lower())


# ---------------------------------------------------------------------------------------------
# compile: which lines belong to this build
# ---------------------------------------------------------------------------------------------

def test_compile_ships_each_line_exactly_once() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "one.md", "The first thing.\n")
        repo.commit("note one")
        repo.tag("build-10")

        repo.write(NOTE + "two.md", "The second thing.\n")
        repo.commit("note two")

        first = run(repo, "compile", "--since", "build-10", "--at", "HEAD")
        check("a build ships only the notes added since the last build tag",
              first.returncode == 0
              and "The second thing." in first.stdout
              and "The first thing." not in first.stdout,
              first.stdout.strip())

        repo.tag("build-11")
        repo.write(NOTE + "two.md", "The second thing, reworded.\n")
        repo.commit("reword an already-shipped note")
        repo.write(NOTE + "three.md", "The third thing.\n")
        repo.commit("note three")
        second = run(repo, "compile", "--since", "build-11", "--at", "HEAD")
        check("rewording a shipped note does not re-ship it",
              second.returncode == 0
              and "The third thing." in second.stdout
              and "reworded" not in second.stdout,
              second.stdout.strip())


def test_compile_accumulates_across_a_build_that_never_happened() -> None:
    """A prose-only merge mints no build and moves no tag, so its note waits."""
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write("docs/x.md", "prose\n")
        repo.commit("base")
        repo.tag("build-20")

        repo.write(NOTE + "a.md", "Thing A.\n")
        repo.commit("a PR whose merge shipped nothing")     # no tag: no build was minted
        repo.write(NOTE + "b.md", "Thing B.\n")
        repo.commit("the PR that does ship")

        result = run(repo, "compile", "--since", "build-20", "--at", "HEAD")
        check("notes accumulate over merges that minted no build",
              result.returncode == 0
              and "Thing A." in result.stdout and "Thing B." in result.stdout,
              result.stdout.strip())
        check("...newest first", result.stdout.index("Thing B.") < result.stdout.index("Thing A."))


def test_compile_drops_internal_lines_and_says_so() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.tag("build-30")
        repo.write(NOTE + "i.md", "internal: a refactor.\n")
        repo.write(NOTE + "v.md", "You can now do a thing.\n")
        repo.commit("one of each")
        result = run(repo, "compile", "--since", "build-30", "--at", "HEAD")
        check("an internal line is not shipped to testers",
              "a refactor" not in result.stdout and "You can now do a thing." in result.stdout,
              result.stdout.strip())
        check("...but the job log records that it was dropped",
              "internal (not shipped)" in result.stderr)


def test_compile_says_something_when_every_line_is_internal() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.tag("build-40")
        repo.write(NOTE + "i.md", "internal: pipeline only.\n")
        repo.commit("nothing a tester sees")
        result = run(repo, "compile", "--since", "build-40", "--at", "HEAD")
        check("a build with no tester-visible change still ships a changelog",
              result.returncode == 0 and result.stdout.strip() == wn.NOTHING_VISIBLE,
              result.stdout.strip())


def test_compile_is_deterministic() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.tag("build-50")
        for name in ("z", "a", "m"):
            repo.write(NOTE + name + ".md", f"Line {name}.\n")
            repo.commit(f"note {name}")
        first = run(repo, "compile", "--since", "build-50", "--at", "HEAD").stdout
        second = run(repo, "compile", "--since", "build-50", "--at", "HEAD").stdout
        check("two runs over one history produce identical bytes", first == second)
        # Newest first: m, a, z -- which is neither the alphabetical order nor its reverse, so a
        # sort that quietly fell back to the path would show here.
        check("the order is by when the note was added, not by filename",
              first.strip().splitlines() == [wn.BULLET + "Line m.",
                                             wn.BULLET + "Line a.",
                                             wn.BULLET + "Line z."],
              first.strip())


def test_compile_respects_the_four_thousand_character_limit() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.tag("build-60")
        # 40 notes of ~150 characters each: comfortably over 4000, and each individually legal.
        for index in range(40):
            repo.write(NOTE + f"n{index:02d}.md",
                       f"Note {index:02d}: " + "y" * 130 + ".\n")
            repo.commit(f"note {index}")
        result = run(repo, "compile", "--since", "build-60", "--at", "HEAD")
        text = result.stdout.rstrip("\n")
        check("the compiled notes fit App Store Connect's field",
              len(text) <= wn.WHATS_NEW_LIMIT, f"{len(text)} characters")
        check("...the newest line survived", "Note 39" in text)
        check("...the oldest line was dropped", "Note 00" not in text)
        check("...and the reader is told lines were dropped",
              text.endswith(wn.OVERFLOW_TAIL))

        # CONTROL: the same probe over a set that FITS must not add the tail. Without this,
        # "the tail is present" and "the tail is always present" look the same.
        with tempfile.TemporaryDirectory() as second_directory:
            small = Repo(second_directory)
            small.tag("build-60")
            small.write(NOTE + "one.md", "A short line.\n")
            small.commit("one note")
            fitting = run(small, "compile", "--since", "build-60", "--at", "HEAD").stdout
            check("CONTROL: a changelog that fits carries no overflow tail",
                  wn.OVERFLOW_TAIL not in fitting, fitting.strip())


def test_compile_for_build_reads_the_pair_of_tags() -> None:
    """What the backstop workflow does: re-derive a build's notes from its own tag."""
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "old.md", "Old thing.\n")
        repo.commit("before build 70")
        repo.tag("build-70")
        repo.write(NOTE + "new.md", "New thing.\n")
        repo.commit("shipped in build 71")
        repo.tag("build-71")
        repo.write(NOTE + "later.md", "Later thing.\n")
        repo.commit("after build 71, not shipped yet")

        result = run(repo, "compile", "--for-build", "71")
        check("--for-build reads the build's own tag, not HEAD",
              result.returncode == 0
              and "New thing." in result.stdout
              and "Old thing." not in result.stdout
              and "Later thing." not in result.stdout,
              result.stdout.strip())

        missing = run(repo, "compile", "--for-build", "99")
        check("--for-build on an untagged build is an error, not an empty changelog",
              missing.returncode != 0, f"exit {missing.returncode}")


def test_compile_refuses_a_build_that_predates_the_mechanism() -> None:
    """Builds 1-43. The failure this guards is a LIE, not an error.

    With no notes directory the unshipped set is empty, and an empty set renders as "No
    tester-visible changes in this build" — which for build 43, which shipped the whole
    community-contribution sync, is false. The backstop would have stamped it.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write("Cypress/A.swift", "//\n")
        repo.commit("a build from before any of this existed")
        repo.tag("build-43")
        result = run(repo, "compile", "--for-build", "43")
        check("a commit with no notes directory is refused", result.returncode == 8,
              f"exit {result.returncode}")
        check("...rather than described as having no tester-visible changes",
              wn.NOTHING_VISIBLE not in result.stdout, result.stdout.strip())
        check("...and the exit code is the one the backstop skips on, not a generic error",
              result.returncode == 8 and "predates" in result.stderr)

        # CONTROL: once the directory exists, an empty unshipped set IS the honest answer, and the
        # same probe must let it through. Without this the guard could be refusing everything.
        repo.write(NOTE + "one.md", "A line.\n")
        repo.commit("the mechanism lands")
        repo.tag("build-44")
        repo.write("Cypress/B.swift", "//\n")
        repo.commit("a later build with nothing new to say")
        repo.tag("build-45")
        control = run(repo, "compile", "--for-build", "45")
        check("CONTROL: a build with the directory present and nothing new says so",
              control.returncode == 0 and control.stdout.strip() == wn.NOTHING_VISIBLE,
              f"exit {control.returncode} {control.stdout.strip()}")


def test_compile_refuses_a_since_it_cannot_see() -> None:
    """The silent-catastrophe case: an unreachable `--since` must not mean "ship everything"."""
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "a.md", "A line.\n")
        repo.commit("a note")
        result = run(repo, "compile", "--since", "build-999", "--at", "HEAD")
        check("an unreachable --since is refused", result.returncode != 0,
              f"exit {result.returncode}")
        check("...rather than silently re-shipping the whole history",
              "A line." not in result.stdout)


def test_tag_helpers_do_not_match_lookalikes() -> None:
    """The lookalike must OUTRANK every real tag, or this test cannot fail (review F3).

    The first version of this fixture put `build-10-hotfix` beside a real `build-10`. Both
    `re.fullmatch` and `re.match` then give the same answer — 10 either way — so weakening the
    matcher could not move either assertion, and mutating `fullmatch` to `match` left the whole
    suite green. That is the "guards green when the defect is present" class CLAUDE.md names as
    this project's dominant test-suite defect, sitting inside the test written to prevent it.

    `build-99-hotfix` fixes it in one fixture line: under `match` it parses as 99 and becomes the
    newest tag, under `fullmatch` it is not a build tag at all. The two matchers now disagree,
    which is the whole point of a lookalike fixture.

    **Which assertion below actually kills the mutant, measured rather than assumed:** only the
    `latest-build-tag` one. `resolve_since` rebuilds a tag NAME from the parsed number, so a
    lookalike read as 99 becomes `build-99`, which does not exist, and `exists()` drops it — the
    boundary is accidentally immune. That immunity is worth neither relying on nor deleting the
    other two assertions for: they pin real behavior, and if the reconstruction ever became a
    passthrough of the raw tag text they would become the guard. Said out loud because "these
    three assertions cover it" would be three-quarters wrong.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write("a.txt", "1\n")
        repo.commit("nine")
        repo.tag("build-9")
        repo.write("a.txt", "2\n")
        repo.commit("ten")
        repo.tag("build-10")
        # Numbered ABOVE every real tag, so a prefix match would pick it as the newest.
        repo.tag("build-99-hotfix")
        repo.tag("build-x")
        repo.write("a.txt", "3\n")
        head = repo.commit("after build 10")

        latest = run(repo, "latest-build-tag").stdout.strip()
        check("the newest build tag ignores a lookalike numbered above it (kills the mutant)",
              latest == "build-10", latest)
        boundary = run(repo, "boundary-for", head).stdout.strip()
        check("the boundary for a commit is the newest real tag behind it",
              boundary == "build-10", boundary)
        previous = run(repo, "previous-build-tag", "10").stdout.strip()
        check("the previous build tag walks back one real tag",
              previous == "build-9", previous)


def test_check_refuses_a_rename_only_change() -> None:
    """A defence that was load-bearing by accident until review F2 named it.

    `--diff-filter=A` runs rename detection, so moving an existing note reports `R` and not `A`:
    a pull request that only tidies filenames answers the check with nothing and is refused. That
    is the right answer — moving somebody else's sentence is not writing your own — and it is
    pinned here so a future `--no-renames` cannot quietly turn a tidy-up into a passing code
    change.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "alpha.md", "You can now filter the map by species.\n")
        base = repo.commit("a note on main")

        repo.branch("tidy-up")
        repo.write("Cypress/A.swift", "//\n")
        repo.git("mv", NOTE + "alpha.md", NOTE + "pr-c.md")
        head = repo.commit("code, plus a rename of an existing note")
        result = run(repo, "check", "--base", base, "--head", head)
        check("a rename does not answer the check", result.returncode != 0,
              f"exit {result.returncode}")

        # CONTROL: a genuinely new file in the same commit does answer it, so the refusal is about
        # the rename rather than about this fixture.
        repo.write(NOTE + "pr-c-note.md", "You can now sort your favorites.\n")
        head2 = repo.commit("and a real note")
        control = run(repo, "check", "--base", base, "--head", head2)
        check("CONTROL: a new note in the same change does", control.returncode == 0,
              control.stderr.strip())


def test_compile_does_not_re_ship_a_renamed_note() -> None:
    """Review F2. The boundary is a set of paths, so a rename walks a shipped line back in."""
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "alpha.md", "Trees you add now sync to the server.\n")
        repo.commit("the note build 50 shipped")
        repo.tag("build-50")

        # The realistic shape: a tidy-up rename riding alongside a legitimate new note. A
        # rename-ONLY change is already refused by `check` (test above).
        repo.git("mv", NOTE + "alpha.md", NOTE + "pr-c.md")
        repo.write(NOTE + "pr-c-new.md", "You can now filter the map by species.\n")
        repo.commit("a housekeeping PR that renames and adds")

        result = run(repo, "compile", "--at", "HEAD")
        check("a renamed note does not ship its line a second time",
              "Trees you add now sync to the server." not in result.stdout,
              result.stdout.strip())
        check("...while the new note in the same commit does ship",
              "You can now filter the map by species." in result.stdout, result.stdout.strip())
        check("...and the rename is reported, not silently swallowed",
              "renamed (not re-shipped)" in result.stderr, result.stderr.strip())

        # CONTROL: the same sentence in a genuinely NEW file must ship. Without this, "renames are
        # excluded" and "that sentence is excluded" look identical.
        with tempfile.TemporaryDirectory() as second:
            fresh = Repo(second)
            fresh.write(NOTE + "keep.md", "An unrelated shipped line.\n")
            fresh.commit("build 50's note")
            fresh.tag("build-50")
            fresh.write(NOTE + "pr-c.md", "Trees you add now sync to the server.\n")
            fresh.commit("a genuinely new note carrying that text")
            control = run(fresh, "compile", "--at", "HEAD")
            check("CONTROL: the same sentence in a genuinely new file does ship",
                  "Trees you add now sync to the server." in control.stdout,
                  control.stdout.strip())


def test_compile_says_a_repeated_line_once() -> None:
    """Review F5: `if line in seen` had no test — `if False` left the suite green.

    Distinct from the tag-boundary exclusion, which never puts the same sentence in two files.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write("a.txt", "1\n")
        repo.commit("base")
        repo.tag("build-60")
        repo.write(NOTE + "branch-one.md", "You can now sort your favorites.\n")
        repo.commit("one branch says it")
        repo.write(NOTE + "branch-two.md", "You can now sort your favorites.\n")
        repo.commit("another branch says the same thing")

        result = run(repo, "compile", "--at", "HEAD")
        occurrences = result.stdout.count("You can now sort your favorites.")
        check("two files carrying the same sentence produce one line",
              occurrences == 1, f"appeared {occurrences} time(s): {result.stdout.strip()!r}")

        # CONTROL: two DIFFERENT sentences must both survive, so the de-duplication is not simply
        # dropping the second file.
        repo.write(NOTE + "branch-three.md", "You can now rename a favorite list.\n")
        repo.commit("a different sentence")
        control = run(repo, "compile", "--at", "HEAD")
        check("CONTROL: two different sentences both ship",
              control.stdout.count("You can now sort your favorites.") == 1
              and "You can now rename a favorite list." in control.stdout,
              control.stdout.strip())


def test_a_deleted_note_is_a_retraction_and_is_reported() -> None:
    """Review F6. Deleting an unshipped note is how a line is taken back — pinned as deliberate.

    The behavior already existed (the set difference does it); what was missing was a test saying
    it is intended, and any sign of it in the release log.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write("a.txt", "1\n")
        repo.commit("base")
        repo.tag("build-70")
        repo.write(NOTE + "cellular.md", "Photos now upload over cellular.\n")
        repo.commit("a note")
        repo.write(NOTE + "other.md", "You can now see a tree's planting date.\n")
        repo.commit("another note")

        # CONTROL FIRST: before the deletion the line is in the changelog. The same repository one
        # commit later is the only thing that changes.
        control = run(repo, "compile", "--at", "HEAD")
        check("CONTROL: the line compiles before it is withdrawn",
              "Photos now upload over cellular." in control.stdout, control.stdout.strip())

        repo.remove(NOTE + "cellular.md")
        repo.commit("withdraw the cellular note — the feature slipped")
        after = run(repo, "compile", "--at", "HEAD")
        check("a note deleted before its build does not ship",
              "Photos now upload over cellular." not in after.stdout, after.stdout.strip())
        check("...the other note is unaffected",
              "You can now see a tree's planting date." in after.stdout, after.stdout.strip())
        check("...and the withdrawal is named in the log, not silent",
              "withdrawn (deleted before this build)" in after.stderr
              and "cellular.md" in after.stderr, after.stderr.strip())


# ---------------------------------------------------------------------------------------------
# The re-run of a failed release job (review F1) — the scenario that made this round
# ---------------------------------------------------------------------------------------------

def test_a_re_run_recompiles_the_same_notes() -> None:
    """Attempt 1 tags and dies in the processing wait; attempt 2 must say the same thing.

    The tag for the build being minted is created right after the upload, before the twenty-minute
    processing wait — so a job that times out there leaves `build-N` sitting on the commit the
    re-run then builds. "The newest build tag" would be that tag, the boundary would be a commit
    against itself, and the re-run would publish "No tester-visible changes in this build" over a
    build that has plenty. The lines would then be present at both tags and unreachable forever,
    and the backstop skips builds whose field is non-empty by design.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "old.md", "An older shipped line.\n")
        repo.commit("before build 43")
        repo.tag("build-43")
        repo.write(NOTE + "new.md", "You can now pinch to zoom a tree's photos.\n")
        head = repo.commit("the commit build 44 is minted from")

        # CONTROL: attempt 1, before its tag exists.
        first = run(repo, "compile", "--at", head)
        check("CONTROL: the first attempt compiles the real notes",
              "You can now pinch to zoom a tree's photos." in first.stdout, first.stdout.strip())

        # Attempt 1 uploaded and tagged, then died in the processing wait.
        repo.tag("build-44")
        second = run(repo, "compile", "--at", head)
        check("a re-run compiles the SAME notes, not an empty changelog",
              second.stdout == first.stdout,
              f"first={first.stdout.strip()!r} second={second.stdout.strip()!r}")
        check("...specifically, it does not claim there is nothing to see",
              wn.NOTHING_VISIBLE not in second.stdout, second.stdout.strip())
        check("...because the boundary walked past the tag on its own commit",
              "since build-43" in second.stderr, second.stderr.strip())

        # And the backstop must be able to re-derive it from either tag on that commit.
        repo.tag("build-45")
        for build in ("44", "45"):
            derived = run(repo, "compile", "--for-build", build)
            check(f"--for-build {build} recovers the same line",
                  "You can now pinch to zoom a tree's photos." in derived.stdout,
                  derived.stdout.strip())


def test_an_explicit_since_equal_to_at_is_refused() -> None:
    """A caller that names the boundary gets an error, not a silent walk-back.

    `resolve_since` exists so the release job never has to ask; a caller who asks anyway, and asks
    for a commit against itself, has a broken assumption and substituting a different revision
    would hide it.
    """
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write(NOTE + "a.md", "A line.\n")
        head = repo.commit("a note")
        repo.tag("build-44")
        result = run(repo, "compile", "--since", "build-44", "--at", head)
        check("an explicit --since equal to --at is refused", result.returncode == 9,
              f"exit {result.returncode}")
        check("...rather than compiling an empty changelog",
              wn.NOTHING_VISIBLE not in result.stdout, result.stdout.strip())

        # CONTROL: omitting --since on the identical repository succeeds and finds the line.
        control = run(repo, "compile", "--at", head)
        check("CONTROL: omitting --since compiles the line", "A line." in control.stdout,
              control.stdout.strip())


def test_a_boundary_on_another_branch_is_not_used() -> None:
    """`resolve_since` requires ancestry, not merely a smaller number."""
    with tempfile.TemporaryDirectory() as directory:
        repo = Repo(directory)
        repo.write("a.txt", "1\n")
        root = repo.commit("root")
        repo.tag("build-10")
        repo.branch("sideline")
        repo.write(NOTE + "side.md", "A line only the sideline has.\n")
        repo.commit("a note on a branch that never merged")
        repo.tag("build-20")
        repo.switch("main")
        repo.write(NOTE + "main.md", "A line on main.\n")
        head = repo.commit("a note on main")

        boundary = run(repo, "boundary-for", head).stdout.strip()
        check("a build tag on an unmerged branch is not this build's boundary",
              boundary == "build-10", boundary)
        result = run(repo, "compile", "--at", head)
        check("...so the changelog is measured from the ancestor",
              "A line on main." in result.stdout
              and "A line only the sideline has." not in result.stdout, result.stdout.strip())
        check("CONTROL: build-10 really is an ancestor, so the fixture is not vacuous",
              repo.git("rev-parse", "build-10^{commit}") == root)


def main() -> int:
    if shutil.which("git") is None:
        print("git is not on PATH; these tests need it", file=sys.stderr)
        return 3
    for name, function in sorted(globals().items()):
        if name.startswith("test_") and callable(function):
            print(f"\n-- {name}")
            function()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED: " + ", ".join(FAILURES))
        return 1
    print("all whats_new.py tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
