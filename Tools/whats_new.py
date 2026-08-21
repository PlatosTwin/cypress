#!/usr/bin/env python3
"""
whats_new.py -- the TestFlight "What to Test" text, derived from git rather than maintained.

    check --base <rev> --head <rev>     does this diff carry its release note?
    compile --since <rev> --at <rev>    the notes for the build being minted from <at>
    compile --for-build <N>             the notes build N shipped, read from its tag
    latest-build-tag                    the newest `build-N` tag, or nothing
    previous-build-tag <N>              the newest `build-N` tag below N, or nothing

WHY THIS EXISTS. Every TestFlight build ships a changelog (owner ruling, 2026-08-21,
`docs/rulings-pending/testflight-changelog.md`), compiled from one tester-voice line per pull
request. `xcrun altool` cannot set that field at all, so the release workflow sets it through the
App Store Connect API -- and the question this file answers is the harder half: **which lines
belong to THIS build and not to the last one.**

── The shipped/unshipped boundary, and why there is no bot commit ─────────────────────────────

A note is a file under `docs/whats-new/`. A pull request adds one; nothing ever edits a shared
file, so two branches open at once cannot conflict. That is the same pending-directory pattern as
`docs/errata-pending/`, for the same reason.

"Already shipped" is then read off the repository's own history, not off a marker somebody has to
remember to move:

    the notes for a build minted at <at>
      = the note files present at <at>
      - the note files present at <since>

where `<since>` is the commit the LAST build was minted from. The release workflow already tags
that commit `build-N` (`.github/workflows/testflight.yml`, "Tag the commit that shipped"), so the
boundary already exists in the repo and this file just reads it. Nothing writes to main, nothing
needs a token, and two people running `compile` a week apart on the same pair of revisions get the
same bytes.

The consequences worth stating, because they are the requirements rather than side effects:

  * **No line ships twice.** A file present at `<since>` is excluded whatever happened to it
    since -- editing a shipped note does not re-ship it.
  * **Nothing is lost to a prose-only merge.** A merge that mints no build (see `plan`'s `scope`
    step) also moves no tag, so its notes are still unshipped and are picked up by the next real
    build. Notes accumulate across as many skipped merges as it takes.
  * **A build can be re-derived after the fact.** `--for-build N` answers "what did build N say"
    from `build-N` and `build-(N-1)` alone, which is what lets the backstop workflow stamp a build
    the release job could not reach.

── The escape hatch ───────────────────────────────────────────────────────────────────────────

A code change with nothing for a tester to look at -- a workflow edit, a refactor, this file --
still has to answer the check, and the honest answer is not an invented feature. A line beginning
`internal:` satisfies `check` and is dropped from `compile`'s output. The rule stays "every code
PR states its tester-visible effect"; `internal:` is a way of stating that the effect is none, and
it is on the record in the diff where a reviewer sees it.

Pure standard library, and pure `git` -- this runs on the ubuntu runner in `plan` where nothing is
pip-installed. Deliberately knows nothing about App Store Connect: `appstore_connect.py` publishes
the text, this decides what the text is, and the two are testable apart.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

# Where a note lives. Trailing slash included: it is used as a pathspec and as a prefix test, and
# without it `dist/whats-new-old/` would read as inside the directory.
NOTES_DIR = "docs/whats-new/"

# Not notes. `README.md` documents the directory the way `docs/errata-pending/README.md` does, and
# a directory whose own instructions ship to testers is a comedy this project can do without.
NOT_A_NOTE = {"README.md"}

# App Store Connect rejects a `whatsNew` longer than this. Enforced here rather than discovered as
# a 409 after a forty-minute archive.
WHATS_NEW_LIMIT = 4000

# What goes on the end when the lines do not fit. Counted against the limit before anything is
# dropped, so the result is short enough WITH it.
OVERFLOW_TAIL = "…and earlier improvements."

# One tester-voice line, not a paragraph. A note that runs longer than this is either prose that
# belongs in `docs/` or a whole release's worth of text in one file, and either way it would eat
# the budget every other branch is sharing.
MAX_LINE = 200

# What a build with nothing to show says. The ruling is that EVERY build ships a changelog, so
# "nothing tester-visible changed" has to be sayable; an empty `whatsNew` would instead read as a
# pipeline that forgot.
NOTHING_VISIBLE = (
    "No tester-visible changes in this build — it carries internal work only. "
    "Please keep testing what you were testing."
)

BULLET = "• "


def fail(message: str, code: int = 1) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(code)


def git(*arguments: str, allow_failure: bool = False) -> str:
    """One git call, output stripped. Failures exit unless the caller says otherwise.

    `check=False` plus an explicit returncode test, rather than catching CalledProcessError: a
    non-zero git here means a revision that does not exist, which for `rev-parse` is a question
    and for `ls-tree` is a bug, and the two callers want different answers.
    """
    finished = subprocess.run(
        ("git",) + arguments, capture_output=True, text=True)
    if finished.returncode != 0:
        if allow_failure:
            return ""
        fail(f"git {' '.join(arguments)} -> exit {finished.returncode}\n"
             f"{finished.stderr.strip()}", 4)
    return finished.stdout.strip()


def exists(rev: str) -> bool:
    return bool(rev) and bool(git("rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}",
                                  allow_failure=True))


def build_tags() -> list[int]:
    """Every `build-N` tag's N, ascending.

    Read with `git tag --list`, and filtered with a full-string match rather than a prefix one:
    `build-16-hotfix` is not build 16, and a prefix test would silently make it so. Same family as
    the `grep -oE '^### E[0-9]+'` mistake CLAUDE.md records -- a pattern that stops at the digits
    reports a different tag as this one.
    """
    numbers = []
    for line in git("tag", "--list", "build-*").splitlines():
        matched = re.fullmatch(r"build-(\d+)", line.strip())
        if matched:
            numbers.append(int(matched.group(1)))
    return sorted(numbers)


def latest_build_tag() -> str:
    tags = build_tags()
    return f"build-{tags[-1]}" if tags else ""


def previous_build_tag(before: int) -> str:
    below = [n for n in build_tags() if n < before]
    return f"build-{below[-1]}" if below else ""


def notes_in_tree(rev: str) -> set[str]:
    """The note files present at `rev`. An empty/absent rev means "the beginning of time"."""
    if not rev:
        return set()
    listing = git("ls-tree", "-r", "--name-only", rev, "--", NOTES_DIR, allow_failure=True)
    return {p for p in listing.splitlines() if is_note_path(p)}


def is_note_path(path: str) -> bool:
    if not path.startswith(NOTES_DIR) or not path.endswith(".md"):
        return False
    return os.path.basename(path) not in NOT_A_NOTE


def added_between(base: str, head: str) -> list[str]:
    """Note files ADDED by `base..head`, in git's order.

    `--diff-filter=A` and not "changed": a branch must not answer the check by editing a note
    another branch already shipped.
    """
    listing = git("diff", "--name-only", "--diff-filter=A", base, head, "--", NOTES_DIR)
    return [p for p in listing.splitlines() if is_note_path(p)]


def added_when(since: str, at: str) -> dict[str, int]:
    """path -> commit time of the commit that added it, in ONE `git log`.

    The ordering the compiled notes are printed in has to be stable across machines and across
    re-runs, and "the order `git ls-tree` happened to return" is not that -- it is alphabetical by
    path, which would make `0043-...md` permanently outrank a note added a month later.

    One log walk, not one `git log -1` per file: with a few dozen notes the per-file shape is the
    quadratic scan #76's review had to take back out, and it costs nothing to avoid here.
    """
    range_argument = f"{since}..{at}" if since else at
    raw = git("log", "--diff-filter=A", "--format=commit %ct", "--name-only",
              range_argument, "--", NOTES_DIR, allow_failure=True)
    when: dict[str, int] = {}
    stamp = 0
    for line in raw.splitlines():
        if line.startswith("commit "):
            try:
                stamp = int(line.split()[1])
            except (IndexError, ValueError):
                stamp = 0
        elif line.strip() and is_note_path(line.strip()):
            # `git log` walks newest first, so the FIRST time a path appears is the newest commit
            # that added it. A path re-added after a deletion therefore dates from the re-add,
            # which is the answer a reader would expect.
            when.setdefault(line.strip(), stamp)
    return when


def read_lines(path: str, rev: str = "") -> list[str]:
    """The note lines in one file: no blanks, no `#` comments.

    Read from a revision rather than the working tree when one is given, because the backstop
    workflow compiles a build from its tag while the checkout sits on main.
    """
    if rev:
        text = git("show", f"{rev}:{path}", allow_failure=True)
    else:
        try:
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
        except OSError as error:
            fail(f"cannot read {path}: {error}", 4)
            return []
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        lines.append(line)
    return lines


def is_internal(line: str) -> bool:
    """The escape hatch, matched at the start and case-insensitively.

    Anchored: a line that merely mentions the word is a real note, and `in` would swallow it.
    """
    return line.lower().startswith("internal:")


# ── compile ────────────────────────────────────────────────────────────────────────────────────

def compile_notes(since: str, at: str) -> tuple[str, list[str], list[str]]:
    """Returns (text, visible lines, internal lines) for the build minted at `at`."""
    unshipped = sorted(notes_in_tree(at) - notes_in_tree(since))
    when = added_when(since, at)
    # Newest note first, so the thing a tester just got is the first thing they read. Ties broken
    # by path so two notes added in one merge -- which is every note added by the same PR -- come
    # out in the same order every time.
    unshipped.sort(key=lambda p: (-when.get(p, 0), p))

    visible: list[str] = []
    internal: list[str] = []
    seen: set[str] = set()
    for path in unshipped:
        for line in read_lines(path, rev=at):
            if is_internal(line):
                internal.append(f"{path}: {line}")
                continue
            # Two branches can independently describe the same shipped behavior. Saying it twice
            # in one changelog is worse than saying it once.
            if line in seen:
                continue
            seen.add(line)
            visible.append(line)

    return render(visible), visible, internal


def render(visible: list[str]) -> str:
    """The lines as App Store Connect will hold them, inside the 4000-character limit.

    Over the limit, the OLDEST lines go -- they are at the bottom, having been sorted newest-first
    -- and the tail says so rather than leaving a changelog that simply stops. The tail's own
    length is counted before anything is dropped, so the result is under the limit *with* it.
    """
    if not visible:
        return NOTHING_VISIBLE

    body = "\n".join(BULLET + line for line in visible)
    if len(body) <= WHATS_NEW_LIMIT:
        return body

    kept = list(visible)
    while kept:
        candidate = "\n".join(BULLET + line for line in kept) + "\n" + OVERFLOW_TAIL
        if len(candidate) <= WHATS_NEW_LIMIT:
            return candidate
        kept.pop()
    # Every line is individually too long for the budget. Say something true rather than nothing.
    return OVERFLOW_TAIL


def cmd_compile(arguments: list[str]) -> None:
    since = ""
    at = "HEAD"
    out = ""
    for_build = 0
    while arguments:
        flag = arguments.pop(0)
        if flag == "--since" and arguments:
            since = arguments.pop(0)
        elif flag == "--at" and arguments:
            at = arguments.pop(0)
        elif flag == "--out" and arguments:
            out = arguments.pop(0)
        elif flag == "--for-build" and arguments:
            try:
                for_build = int(arguments.pop(0))
            except ValueError:
                fail("--for-build takes an integer build number", 2)
        else:
            fail(f"usage: whats_new.py compile [--since <rev>] [--at <rev>] "
                 f"[--for-build <N>] [--out <path>]  (got {flag!r})", 2)

    if for_build:
        at = f"build-{for_build}"
        if not exists(at):
            fail(f"no tag {at} — cannot say what build {for_build} shipped without the commit "
                 "it shipped from", 5)
        since = previous_build_tag(for_build)

    if since and not exists(since):
        # Loudly, not by treating it as "the beginning of time": that would silently re-ship every
        # note the app has ever carried.
        fail(f"--since {since!r} is not a commit this checkout has. A shallow clone is the usual "
             "cause; the release job checks out with fetch-depth: 0 for exactly this.", 5)
    if not exists(at):
        fail(f"--at {at!r} is not a commit this checkout has", 5)

    text, visible, internal = compile_notes(since, at)

    print(f"compiling notes for {at} since {since or '(no previous build tag)'}", file=sys.stderr)
    for line in internal:
        print(f"  internal (not shipped): {line}", file=sys.stderr)
    print(f"  {len(visible)} tester-visible line(s), {len(text)} characters", file=sys.stderr)

    if out:
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(text)
        print(f"wrote {out}", file=sys.stderr)
    print(text)


# ── check ──────────────────────────────────────────────────────────────────────────────────────

HOW_TO_FIX = """
Add one file under {directory} — for example

    {directory}{example}

containing ONE plain sentence in a tester's voice, for instance

    You can now pinch to zoom a tree's photos.

If this change has nothing a tester can see — a refactor, a workflow edit, a test — say exactly
that instead, and the check is satisfied:

    internal: reworks the outbox retry policy; no tester-visible change.

One file per pull request, named for the branch or the topic. Nothing edits a shared file, so
open branches cannot conflict over it, and the release job compiles every note added since the
last build's tag. Editing a note that already shipped does NOT answer this check: the file has
to be new on this branch.
""".strip()


def cmd_check(arguments: list[str]) -> None:
    base = ""
    head = "HEAD"
    example = "my-branch.md"
    while arguments:
        flag = arguments.pop(0)
        if flag == "--base" and arguments:
            base = arguments.pop(0)
        elif flag == "--head" and arguments:
            head = arguments.pop(0)
        elif flag == "--example" and arguments:
            example = arguments.pop(0)
        else:
            fail(f"usage: whats_new.py check --base <rev> [--head <rev>] "
                 f"[--example <filename>]  (got {flag!r})", 2)
    if not base:
        fail("usage: whats_new.py check --base <rev> [--head <rev>]", 2)
    for rev in (base, head):
        if not exists(rev):
            fail(f"{rev!r} is not a commit this checkout has — a shallow clone cannot answer "
                 "this question, and answering it wrongly would let a change merge without its "
                 "release note", 5)

    added = added_between(base, head)
    if not added:
        print(f"ERROR: this change adds no release note under {NOTES_DIR}", file=sys.stderr)
        print("", file=sys.stderr)
        print(HOW_TO_FIX.format(directory=NOTES_DIR, example=example), file=sys.stderr)
        sys.exit(1)

    problems: list[str] = []
    total = 0
    for path in added:
        lines = read_lines(path, rev=head)
        if not lines:
            problems.append(f"{path} has no note line — it is empty, or every line is a "
                            "`#` comment")
            continue
        for line in lines:
            total += 1
            if len(line) > MAX_LINE:
                problems.append(
                    f"{path}: a note line is {len(line)} characters, over the {MAX_LINE} this "
                    "allows. One sentence a tester would read, not a paragraph — the 4000-"
                    "character TestFlight budget is shared with every other open branch.")
            kind = "internal" if is_internal(line) else "tester-visible"
            print(f"  {path}: {kind}: {line}")

    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        print("", file=sys.stderr)
        print(HOW_TO_FIX.format(directory=NOTES_DIR, example=example), file=sys.stderr)
        sys.exit(1)

    print(f"OK: {len(added)} release note file(s), {total} line(s)")


def main() -> None:
    if len(sys.argv) < 2:
        fail("usage: whats_new.py {check|compile|latest-build-tag|previous-build-tag}", 2)
    command = sys.argv[1]
    if command == "compile":
        cmd_compile(sys.argv[2:])
    elif command == "check":
        cmd_check(sys.argv[2:])
    elif command == "latest-build-tag":
        print(latest_build_tag())
    elif command == "previous-build-tag":
        if len(sys.argv) != 3:
            fail("usage: whats_new.py previous-build-tag <N>", 2)
        try:
            print(previous_build_tag(int(sys.argv[2])))
        except ValueError:
            fail(f"build number must be an integer, got {sys.argv[2]!r}", 2)
    else:
        fail(f"unknown command {command!r}", 2)


if __name__ == "__main__":
    main()
