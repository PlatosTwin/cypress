#!/usr/bin/env python3
"""
whats_new.py -- the TestFlight "What to Test" text, derived from git rather than maintained.

    check --base <rev> --head <rev>     does this diff carry its release note?
    compile --at <rev>                  the notes for the build being minted from <at>
    compile --for-build <N>             the notes build N shipped, read from its tag
    boundary-for <rev>                  the build tag <rev>'s notes are measured against
    latest-build-tag                    the newest `build-N` tag, or nothing (NOT a boundary)
    previous-build-tag <N>              the build tag build-N's notes are measured against

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
      - the note files git reports as RENAMES of files present at <since>

where `<since>` is the commit the LAST build was minted from -- resolved by `resolve_since` as the
newest `build-N` tag STRICTLY BEHIND `<at>`, never one sitting on `<at>` itself. The release
workflow already tags that commit `build-N` (`.github/workflows/testflight.yml`, "Tag the commit
that shipped"), so the boundary already exists in the repo and this file just reads it. Nothing
writes to main, nothing needs a token, and two people running `compile` a week apart on the same
pair of revisions get the same bytes.

The consequences worth stating, because they are the requirements rather than side effects. Each
is now pinned by a test with a control -- an earlier version of this list asserted the first one
while the code did something narrower, which is the shape CLAUDE.md means by "a confident comment
is where bugs have survived here":

  * **No line ships twice.** A note keeps its identity across an edit (its path is unchanged) and
    across a rename (git reports the move), so neither re-announces a sentence testers have read.
    The one gap, stated rather than hidden: a rename that also REWRITES the sentence falls below
    git's similarity threshold, reports as delete-plus-add, and ships again -- defensibly, since a
    rewritten sentence is a new statement. `docs/whats-new/README.md` says so to authors.
  * **Nothing is lost to a prose-only merge.** A merge that mints no build (see `plan`'s `scope`
    step) also moves no tag, so its notes are still unshipped and are picked up by the next real
    build. Notes accumulate across as many skipped merges as it takes.
  * **A line can be withdrawn, by deleting its note before the build.** That is the retraction
    mechanism and the only one; `compile` reports every withdrawal to stderr so it is visible in
    the release log rather than only in a diff.
  * **A build can be re-derived after the fact.** `--for-build N` answers "what did build N say"
    from `build-N` and its own boundary alone, which is what lets the backstop workflow stamp a
    build the release job could not reach -- and what makes a re-run of a failed release job
    recompile the same set instead of a false empty one.

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
    """The highest-numbered `build-N` tag in the repository, ancestry ignored.

    **Not a boundary, and never to be used as one** — `resolve_since` is. This answers "what is the
    newest build number this repository knows about", which is a different and much weaker
    question: the tag it returns can be sitting on the commit being built, which is review F1.
    """
    tags = build_tags()
    return f"build-{tags[-1]}" if tags else ""


def same_commit(one: str, other: str) -> bool:
    return bool(one) and bool(other) and git(
        "rev-parse", f"{one}^{{commit}}", allow_failure=True) == git(
        "rev-parse", f"{other}^{{commit}}", allow_failure=True)


def is_strict_ancestor(candidate: str, descendant: str) -> bool:
    """Is `candidate` an ancestor of `descendant`, and a DIFFERENT commit?

    `git merge-base --is-ancestor` calls a commit its own ancestor, which is the one answer this
    must not accept — see `resolve_since`.
    """
    if not exists(candidate) or not exists(descendant):
        return False
    if same_commit(candidate, descendant):
        return False
    finished = subprocess.run(
        ("git", "merge-base", "--is-ancestor", candidate, descendant),
        capture_output=True, text=True)
    return finished.returncode == 0


def resolve_since(at: str, below: int | None = None) -> str:
    """The boundary for a build at `at`: the newest `build-N` tag STRICTLY BEHIND it.

    ── Why "strictly behind" and not simply "the newest tag" (review F1) ───────────────────────
    A release job that uploads and then dies in the twenty-minute processing wait leaves a
    `build-N` tag **on the commit being built** — the tag is created right after the upload so the
    backstop has something to read. The remediation for such a run is *Re-run failed jobs*, and on
    the second attempt a naive "newest tag" hands back `build-N`, which points at `at` itself.
    `compile` would diff a commit against itself, find nothing, and publish "No tester-visible
    changes in this build" over a build that has plenty.

    That is not merely a bad changelog, it is an unrecoverable one: the real notes would then be
    present at BOTH tags, so no later compile and no `--for-build` could reach them again, and the
    backstop only stamps builds whose field is empty. A single false changelog would consume the
    lines permanently.

    Walking back past any tag that sits on `at` settles the whole family at once — a re-run, two
    builds minted from one commit, a tag somebody made by hand on HEAD. The same rule serves
    `--for-build`, where `below` additionally refuses to look forward at a higher-numbered tag.

    **Ancestry, not just a smaller number.** A `build-N` tag on some other branch is not this
    build's predecessor, and diffing against it would ship an arbitrary set of notes.
    """
    for number in reversed(build_tags()):
        if below is not None and number >= below:
            continue
        tag = f"build-{number}"
        if is_strict_ancestor(tag, at):
            return tag
    return ""


def previous_build_tag(before: int) -> str:
    return resolve_since(f"build-{before}", below=before)


def notes_in_tree(rev: str) -> set[str]:
    """The note files present at `rev`. An empty/absent rev means "the beginning of time"."""
    if not rev:
        return set()
    listing = git("ls-tree", "-r", "--name-only", rev, "--", NOTES_DIR, allow_failure=True)
    return {p for p in listing.splitlines() if is_note_path(p)}


def notes_directory_exists(rev: str) -> bool:
    """Did `docs/whats-new/` exist at `rev` at all?

    **The difference between "this build changed nothing a tester can see" and "this build predates
    the mechanism that would have said so" is invisible in the compiled output** — both produce an
    empty set of unshipped notes, and `render` then says "No tester-visible changes in this build".
    For build 43 that sentence is simply false: it shipped the community-contribution sync and had
    no notes because there was nowhere to write one.

    So the question is asked separately, and the callers that could publish a falsehood refuse.
    Cheap: one `ls-tree` of the directory, which is empty exactly when the directory is absent.
    """
    if not rev:
        return False
    return bool(git("ls-tree", "-r", "--name-only", rev, "--", NOTES_DIR, allow_failure=True))


def is_note_path(path: str) -> bool:
    if not path.startswith(NOTES_DIR) or not path.endswith(".md"):
        return False
    return os.path.basename(path) not in NOT_A_NOTE


def added_between(base: str, head: str) -> list[str]:
    """Note files ADDED by `base..head`, in git's order.

    `--diff-filter=A` and not "changed": a branch must not answer the check by editing a note
    another branch already shipped.

    **A rename reports as `R`, not `A`, and that is load-bearing rather than incidental** (review
    F2). It means a pull request that only moves an existing note answers this check with nothing,
    and is refused — which is the right answer, because moving somebody else's sentence is not
    writing your own. `test_check_refuses_a_rename_only_change` pins it so a future `--find-renames`
    flag cannot quietly turn a tidy-up into a passing code change.
    """
    listing = git("diff", "--name-only", "--diff-filter=A", base, head, "--", NOTES_DIR)
    return [p for p in listing.splitlines() if is_note_path(p)]


def renamed_between(since: str, at: str) -> dict[str, str]:
    """new path -> old path, for note files git considers renamed across `since..at`.

    ── Why the boundary cannot be a set of paths alone (review F2) ─────────────────────────────
    `compile` subtracts the note files present at `since` from those present at `at`. A rename
    puts a path in the second set that is not in the first, so a note shipped by build 50 and
    tidied into a new filename by build 53 **ships its line a second time** — and the whole claim
    of this file is that a line ships exactly once. The line de-duplication does not catch it:
    there is only one copy of the sentence in the build being compiled.

    A rename-only pull request is already refused by `check` (see `added_between`), so the shape
    that reaches here is the realistic one: a rename riding alongside a legitimate new note, which
    is exactly what a housekeeping pull request looks like in a directory that gains a file per
    merge forever.

    Rename detection is git's, `-M`, on by default for `git diff` and named explicitly here so it
    cannot be turned off by a config somewhere. A rename that also **rewrites** the sentence falls
    below git's similarity threshold and reports as delete-plus-add, so it ships again — correct,
    arguably, since a rewritten sentence is a new statement, and stated in
    `docs/whats-new/README.md` rather than left to be discovered.
    """
    raw = git("diff", "-M", "--name-status", "--diff-filter=R", since, at, "--", NOTES_DIR,
              allow_failure=True) if since else ""
    moved: dict[str, str] = {}
    for line in raw.splitlines():
        fields = line.split("\t")
        # `R097<TAB>old<TAB>new`. Anything else is not a rename record and is skipped rather than
        # guessed at.
        if len(fields) == 3 and fields[0].startswith("R"):
            moved[fields[2]] = fields[1]
    return moved


def deleted_in_range(since: str, at: str) -> set[str]:
    """Note paths that a commit in `since..at` actually DELETED.

    A separate pass from `added_when`, and it has to be, because `--diff-filter=A` and
    `--diff-filter=D` disagree about a rename in a way that matters here: git reports the move as
    `R`, so the old path appears in NEITHER filter. Probed rather than assumed — a rename inside
    the window prints nothing under `D` while a real deletion prints its path.

    That is what separates "this sentence was withdrawn" from "this file was renamed", and the
    first version of `retracted` conflated them.
    """
    if not since:
        return set()
    raw = git("log", "--diff-filter=D", "--format=", "--name-only",
              f"{since}..{at}", "--", NOTES_DIR, allow_failure=True)
    return {p.strip() for p in raw.splitlines() if p.strip() and is_note_path(p.strip())}


def retracted(when: dict[str, int], present_at: set[str], deleted: set[str]) -> list[str]:
    """Notes written since the boundary and then deleted before the build — retractions (F6).

    **Deleting an unshipped note is how a line is taken back**, and it is the only way: nothing
    else in this mechanism can withdraw a sentence once it is committed. The compile's set
    difference already implements it — a file that is not present at `at` contributes nothing —
    so this function does not change the outcome. It exists to make the outcome *visible*.

    Silence is the objection review F6 raised, and it is a fair one: a housekeeping pull request
    that prunes the directory would drop a real tester-facing line, exit 0, and leave the only
    evidence in a diff nobody re-reads. So `compile` prints these to stderr beside the `internal:`
    lines it drops, and the release log says which sentences were withdrawn.

    Two conditions, and both are needed:

      * **added inside the window and not present at the end** — a note that existed at `since`
        and was tidied away later was already shipped, so removing it retracts nothing;
      * **and actually deleted by some commit**. Without this second test a note RENAMED inside
        the window reports as withdrawn, because git files the move as `R` and the old path shows
        up under `--diff-filter=A` from its original commit while never appearing at `at`. The
        line ships perfectly well under its new filename; only the report would be wrong. A false
        "withdrawn" in a release log is exactly the kind of line a later reader believes.

    Note that `git diff <since> <at> --diff-filter=D` would answer neither: a note added and
    deleted entirely inside the range never existed at `since` and does not exist at `at`, so it
    is in no such diff at all. It has to be `git log` over the range.
    """
    return sorted((set(when) - present_at) & deleted)


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

    **Anchored, and tested rather than merely asserted here.** A tester-voice line is free to use
    the word — "The sync queue now shows an internal: prefix on rows it could not send" is a real
    note — and a containment test would swallow it, dropping a shipped feature from the changelog
    with `check` still green and `compile` still exit 0. Review F4 mutated `startswith` to `in` and
    the whole suite stayed green; `test_check_accepts_the_escape_hatch` now kills that mutant.
    """
    return line.lower().startswith("internal:")


# ── compile ────────────────────────────────────────────────────────────────────────────────────

class Compiled:
    """What one compile found. A record rather than a widening tuple — `compile_notes` now has
    four things to say and a five-slot return is where a caller starts unpacking in the wrong
    order."""

    def __init__(self, text: str, visible: list[str], internal: list[str],
                 withdrawn: list[str], moved: dict[str, str]) -> None:
        self.text = text
        self.visible = visible
        self.internal = internal
        self.withdrawn = withdrawn
        self.moved = moved


def compile_notes(since: str, at: str) -> Compiled:
    """The changelog for the build minted at `at`, given that `since` is the last build's commit.

    ── What "unshipped" means, exactly ────────────────────────────────────────────────────────
    Three subtractions, and each is a separate claim about the mechanism:

      * present at `at`, minus present at `since` — the boundary itself. A note that kept its
        path is excluded whatever was done to its contents, so rewording a shipped line does not
        re-announce it.
      * minus anything git reports as a RENAME of a note that was present at `since` (review F2).
        Without this a tidy-up that moves an old filename re-ships a sentence testers already
        read, and "no line ships twice" — asserted in this module's own docstring, in the ruling
        and in the pull request — would be false.
      * files that were added since `since` and then deleted are simply absent from the first
        set, which is the retraction path. It changes nothing here and is REPORTED, because a
        withdrawn sentence disappearing silently is review F6.
    """
    present_at = notes_in_tree(at)
    moved = renamed_between(since, at)
    already = notes_in_tree(since)
    # A renamed note is the same note. Subtracting its NEW path is what keeps its line from being
    # published a second time under a different filename.
    renamed_from_shipped = {new for new, old in moved.items() if old in already}
    unshipped = sorted(present_at - already - renamed_from_shipped)
    when = added_when(since, at)
    withdrawn = retracted(when, present_at, deleted_in_range(since, at))
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
            # Two branches can independently describe the same shipped behavior — one file each,
            # so nothing above catches it. Saying it twice in one changelog is worse than saying
            # it once. Pinned by `test_compile_says_a_repeated_line_once`; without a test this is
            # a comment, and review F5 showed the mutant surviving.
            if line in seen:
                continue
            seen.add(line)
            visible.append(line)

    return Compiled(render(visible), visible, internal, withdrawn, moved)


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

    explicit_since = bool(since)

    if for_build:
        at = f"build-{for_build}"
        if not exists(at):
            fail(f"no tag {at} — cannot say what build {for_build} shipped without the commit "
                 "it shipped from", 5)
        since = previous_build_tag(for_build)
        explicit_since = False

    if since and not exists(since):
        # Loudly, not by treating it as "the beginning of time": that would silently re-ship every
        # note the app has ever carried.
        fail(f"--since {since!r} is not a commit this checkout has. A shallow clone is the usual "
             "cause; the release job checks out with fetch-depth: 0 for exactly this.", 5)
    if not exists(at):
        fail(f"--at {at!r} is not a commit this checkout has", 5)

    # ── The boundary, when the caller did not name one (review F1) ─────────────────────────────
    # The release job says only `--at $GITHUB_SHA` and lets this decide, because the decision has a
    # trap in it that a shell one-liner walked straight into: the newest `build-N` tag can be
    # sitting on the very commit being built, after a re-run of a job that uploaded and then died
    # in the processing wait. `resolve_since` walks back past it. See that function.
    if not since:
        since = resolve_since(at)

    # An explicitly named boundary is still checked, and refused rather than quietly walked back:
    # a caller that asked for a diff of a commit against itself has a broken assumption somewhere,
    # and silently substituting a different revision would hide it.
    if explicit_since and same_commit(since, at):
        fail(f"--since {since!r} and --at {at!r} are the same commit, so there is nothing to "
             "compile and the result would be a false \"no tester-visible changes\". Omit "
             "--since and let the tool resolve the newest build tag strictly behind --at.", 9)
    if not notes_directory_exists(at):
        # Exit 8, and the number is load-bearing: the backstop treats it as "leave this build
        # alone", where every other failure is a red run. See `notes_directory_exists`.
        fail(f"{NOTES_DIR} does not exist at {at}, so this commit predates the release-note "
             "mechanism and nothing here can say what it shipped. Refusing rather than "
             "publishing \"no tester-visible changes\", which for such a build is false.", 8)

    result = compile_notes(since, at)

    print(f"compiling notes for {at} since {since or '(no previous build tag)'}", file=sys.stderr)
    for line in result.internal:
        print(f"  internal (not shipped): {line}", file=sys.stderr)
    for path, old in sorted(result.moved.items()):
        print(f"  renamed (not re-shipped): {old} -> {path}", file=sys.stderr)
    for path in result.withdrawn:
        print(f"  withdrawn (deleted before this build): {path}", file=sys.stderr)
    print(f"  {len(result.visible)} tester-visible line(s), {len(result.text)} characters",
          file=sys.stderr)

    if out:
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(result.text)
        print(f"wrote {out}", file=sys.stderr)
    print(result.text)


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
            # "not shipped" rather than "internal", so the line's own `internal:` prefix is not
            # printed twice in the same sentence.
            kind = "not shipped" if is_internal(line) else "tester-visible"
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
        fail("usage: whats_new.py "
             "{check|compile|boundary-for|latest-build-tag|previous-build-tag}", 2)
    command = sys.argv[1]
    if command == "compile":
        cmd_compile(sys.argv[2:])
    elif command == "check":
        cmd_check(sys.argv[2:])
    elif command == "latest-build-tag":
        print(latest_build_tag())
    elif command == "boundary-for":
        if len(sys.argv) != 3:
            fail("usage: whats_new.py boundary-for <rev>", 2)
        if not exists(sys.argv[2]):
            fail(f"{sys.argv[2]!r} is not a commit this checkout has", 5)
        print(resolve_since(sys.argv[2]))
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
