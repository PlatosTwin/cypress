# Unnumbered — the orchestrator splices this under the next E number at merge (CLAUDE.md,
# Numbering). Written from branch `fix/web-collision-guard-scope`, 2026-09-10.

### The web collision guard refused the whole machine, and the retries fed each other

`Tools/run_web_tests.sh` shipped with #162 refusing on **any** process whose argv contained
`run_web_tests.sh`, wherever on the machine it lived, and saying this in the refusal:

    REFUSING: another run_web_tests.sh is live and would share /tmp/cy-webguard/web/node_modules:
      32625  /bin/bash /tmp/cy-webguard-other/Tools/run_web_tests.sh /tmp/other.log 120
      Wait for it, or run the phases you need in a separate checkout.

Reproduced against the pre-change file, and the two paths in that refusal are two different
worktrees with two different `node_modules`. The named process could not share the directory the
message says it would share, and the advice — "run in a separate checkout" — is the thing the
refused run was already doing. Two reviewers hit it on 2026-09-10, in `/private/tmp/cy-fix-171`
and `/tmp/rev173`.

**The retry is the part worth keeping.** A refused agent re-runs, and a re-run is itself a process
whose argv contains `run_web_tests.sh`, so it refuses the others while they refuse it. A guard
this shape does not fail open or closed, it deadlocks — and it gets worse the more agents obey it.

**Scoped to `$REPO` now**, the way `run_tests.sh:collision_check` keys on `$UDID` and on
`$REPO/Cypress.xcodeproj` rather than on the word `xcodebuild` alone, trailing slash included for
the same prefix reason that guard records. A candidate is placed by its command line or by its
working directory (`lsof -d cwd`); one that can be placed in this checkout is refused, one placed
elsewhere is allowed, and one that cannot be placed at all is **printed and not refused on** —
three answers, because "I could not tell" is not "no conflict" and a reader is owed the
difference.

**`/tmp` is a symlink to `/private/tmp`, and that nearly shipped a guard that could not fire.**
Bash's `cd`+`pwd` are logical, so a worktree at `/tmp/x` computes `$REPO` = `/tmp/x`, while the
kernel reports its own processes' cwd as `/private/tmp/x/web`. A cwd test against `$REPO` alone
matches neither form for half the worktrees on this machine and never refuses — the vacuous-check
family from CLAUDE.md, arriving through path normalisation instead of through a glob. It was
caught before it was written, by running `lsof` against a process whose directory was already
known and reading the two strings side by side. Both forms are asked for now.

**Both directions are proved, and one of the proofs was wrong first.** The same-checkout refusal
and the cross-checkout allowance were each run against real `run_web_tests.sh` processes. The
first attempt at the refusal proof reported the guard allowing a second run in the same checkout —
the guard was right and the proof was broken: the web suite takes **nine seconds** end to end, so
the `sleep 12` meant to let run one get going had outlived it, and there was no collision to
refuse. The log timestamps say so (`finished 20:06:04`, the second run `started 20:06:07`). A
concurrency proof whose two processes do not overlap proves nothing in either direction, and on
this project it would have been filed as the guard failing.
