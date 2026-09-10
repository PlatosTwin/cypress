# Unnumbered — the orchestrator splices this under the next E number at merge (CLAUDE.md,
# Numbering). Written from branch `tools/harness-hardening`, 2026-09-09.

### Three ways the harness lied about the harness, and the seam that now catches them

Everything below is about `Tools/`, not about the app. It is here because CLAUDE.md's own
sentence — "this project's tooling is gated; the commands you type to make claims about that
tooling are not" — turns out to apply to the gates themselves, and each of these was found by
running the guard against a case whose answer was already known rather than by reading it.

**1. The collision guard refused on its own caller, and E283 named the fix.** Reproduced exactly,
against the pre-change file, with the wrapper shape the errata describes — a shell command that
launches the run and also contains the word `xcodebuild`:

    VERIFY-FAIL: an xcodebuild is already live against this simulator or worktree:
      pid 91815 — same simulator (00000000-DEAD-BEEF-0000-000000000000)
      pid 91821 — same simulator (00000000-DEAD-BEEF-0000-000000000000)

Two hits, and NEITHER was a build: 91815 is the `bash -c` that invoked the script and 91821 is the
shell above it. The exclusion set was `{$$}` where it needed to be the whole ancestor chain. E283
offered a second candidate fix — require the command to *start* with an `xcodebuild` path — and
that one is now refused explicitly and pinned by a check: `nohup xcodebuild test …&` has argv[0]
`nohup`, and CLAUDE.md carries `nohup … &` as a shape this project has actually used, so narrowing
to argv[0] would have removed a true positive to remove a false one.

**2. `simctl bootstatus -b` has no timeout, and a wedged one is invisible.** Measured against the
pre-change file with a `bootstatus` that never returns: 25 seconds in, the script was still alive
and had printed **zero bytes**. There is nothing to distinguish that from a cold boot except
waiting longer, and the observed failure — four stuck `bootstatus` processes deadlocking a
preflight, another device recovered only by `simctl erase` — is what the waiting turns into. The
old script's answer to a device that already holds a wedged `bootstatus` was to start a second
one; counted, it went from one to two.

**3. An event-synthesis timeout and an assertion failure were the same verdict.** Both logs
produced `VERIFY-FAIL: ** TEST FAILED ** present`, exit 1, from the pre-change judge. One of them
says the app failed a check; the other says the host never delivered a tap to the simulator, which
is a fact about the machine and about nothing else. Three of the second kind were read as reds on
2026-09-02 and re-run into green, which is the reading CLAUDE.md warns about from the other side: a
green re-run proves a failure was intermittent, never why.

### The seam, and the one thing it did wrong first

Shell scripts have no test target here. `Tools/test_harness_guards.sh` is the nearest thing: it
sources `run_tests.sh` under `CYPRESS_RUN_TESTS_LIB_ONLY=1`, then defines shell functions named
`ps` and `pid_is_live`, which bash resolves ahead of the real commands. Every guard is then driven
against a process table whose answer is known, and every check is paired with a control.

**And the substituted `ps` promptly blinded a function that needed the real one.** `bounded_run`'s
timeout reported 124 while leaving its child process running, because the kill walks the process
tree by asking `ps` for children and the fixture answered "nobody". A bound that returns while the
process it bounded keeps running manufactures exactly the leftover the guard beside it refuses on.
The fix is ordering — the bound is exercised after the fixture is removed — and it is commented in
place, because the failure is the same shape as everything above it: an instrument answering a
different question than the one being asked, and looking identical to an answer.

### What adversarial review found, and it is the same class as the four above

Review (#153) went looking for the seam's own vacuous guards and found four, three of them in the
files this round added. They are recorded here rather than in the PR alone because every one is
the shape this project keeps paying for: an instrument answering a different question than the
one being asked, and looking identical to an answer.

**1. The environment-refusal verdict could be produced by a log recording a CRASH.** The
classifier read `test_failure_lines()` — which matches three per-test line shapes and deliberately
strips Swift Testing's aggregates, because it was written for the excerpt printer — and it ran
*before* the two checks that read the log's own counters. So a log saying `Restarting after
unexpected exit, crash, or test timeout …` and `Executed 7 tests, with 2 failures (1 unexpected)`,
with one synthesis timeout among them, was answered:

    VERIFY-ENV-REFUSED: this run was refused by the environment, not by the code.
      … Nothing was asserted about the app …
      This is NOT a pass (exit 2). It is also not a red — do not file it as one.

The pre-change judge called that log a red. Exit 2 still fails CI, so no green hid anything — but
the token, the prose and the "re-run this shard alone" advice are aimed at a person, and the
person was being told the wrong thing about a crashed test. Fixed by reading the counters FIRST: a
crash marker, a Swift Testing aggregate, or an XCTest failure count larger than the number of
classified timeouts each force the red path, and a log that holds timeouts and is judged a red now
says which of those it was. All three of review's logs are fixtures in the seam, with the seven
shapes that were tried and did not break it.

**2. One question, two matchers, and the disagreement was printed as evidence.** The collision
guard matched `xcodebuild` anywhere in a command line (so `nohup xcodebuild …&` is caught); the
concurrency count matched argv[0] (so it was not). Measured on one process table: refused by one,
counted **0** by the other. That zero is stamped in the log header and reprinted by the judge as
the corroboration for the refusal above, so a round in which any build was launched under `nohup`
offered the reader an undercount to check the verdict against. Both now call one matcher, pinned
line by line on both callers.

**3. The seam leaked a process on every run, forty lines from the fix for that exact defect.**
`( … ) & SERVER_PID=$!` captures the SUBSHELL, not the `python3 -m http.server` under it, so the
teardown killed the wrapper and left the server holding a loopback port, reparented to launchd.
Twelve had accumulated on the reviewer's machine, the oldest two and a half hours old — and this
file's own `bounded_run` comment says that signaling only the pid bash knows about is how a
timeout manufactures the leftover the guard beside it refuses on. Fixed, and pinned: the teardown
now asserts the pid is gone.

**4. An assertion in the seam that could not fail.** `expect_contains "${out}(no output)" "(no
output)"` concatenates the needle onto the haystack. It read as "and it printed nothing" and
tested nothing — in the file whose thesis is that a guard proved only on the case it was written
for may be passing vacuously.
