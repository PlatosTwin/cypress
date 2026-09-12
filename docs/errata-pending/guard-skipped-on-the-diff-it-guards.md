# Unnumbered — the orchestrator splices this under the next E number at merge (CLAUDE.md,
# Numbering). Found during the web round's orchestration, 2026-09-10.

### A guard that CI skips on exactly the diffs it exists to check

`DocumentCitationGuardTests` reads every `.md` under `docs/` and asserts that each backticked,
slash-bearing, extension-carrying citation names a file a reader can open. It lives in
`CypressTests`, so it runs in the `unit` job and only there.

Since #216 a change touching only prose — `docs/`, `graphify-out/`, a root `*.md` — deliberately
skips `unit`. `testflight.yml`'s classifier reads `DOC_ONLY='docs/|graphify-out/|[^/]*\.md'`.

Those two facts compose into a guard that never runs on its own subject. **The only files
`DocumentCitationGuardTests` reads are `docs/**`, and a diff confined to `docs/**` is precisely the
diff that skips the job it runs in.** It executes only as a passenger on some unrelated change that
happens to touch Swift. `gate` is green either way, and its green is honest about what it checked:
that the diff was prose. It says nothing about the prose.

This is not hypothetical and it is not old. #158 (`5ff63c1`, "open the web round") cited the web
round's two verification scripts — `run_web_tests.sh` and `verify_web_test_log.sh`, then unwritten,
proposed to live under `Tools/` — as backticked **repo-relative paths**, prefix included, in four
documents. (They are named without their directory here for the reason #166 named them that way in
the roadmap: a token carrying no `/` is not a path to this guard, and an errata entry about dangling
citations that dangles two of its own is a poor advertisement. That is not a hypothetical either —
the first draft of this entry did exactly that, and the out-of-band check caught it.) Both scripts were still unmerged on the web foundation branch, so main
took on eight dangling citations in one commit. Three further prose-only PRs — #160, #161 and #164 —
then merged green on top of a main that was already carrying them, because each of the four is
classified prose-only and `unit` reports `skipping` on all of them (checked, not assumed: none of
the four touches a non-prose path). Nothing reported the defect until an unrelated code PR ran
`unit` and went red **for something it had not introduced**. #166 reworded the prose to land the
fix; this entry is the class.

The count is the part worth keeping. **One bad commit, three green PRs after it, and the number of
runs that could have caught it was zero** — not "low", zero, because the job that holds the guard
cannot be reached by any diff of this shape.

The shape is the project's dominant test-suite defect, recorded four times before on 2026-08-07:
**a guard that is green because the defect is present.** The three earlier shapes were input
deletion, computed-and-discarded, and a truncated instrument. This is a fourth: **the guard is not
wrong, it is not reached.** No amount of reading the test finds it, because the test is correct.

#### Two ways to see it, and only one of them is cheap

Reading `DocumentCitationGuardTests` proves nothing — the defect is not in it. The question that
finds it is the standing one: *could this pass while the defect it names is present?* Here the
answer is that it does not pass at all, and an unrun test and a passing test are the same colour
on the PR page.

Until it is fixed, a prose-only PR's citations must be checked out of band, and the check must be
calibrated in both directions before it is believed — against a tree known to be clean and a tree
known to dangle. An uncalibrated mirror of this guard's rules reports **35 false positives on
`origin/main`**, which is green in CI; the signal is the *delta* against main, not the count. That
mirror was written and calibrated on 2026-09-10 and it is not in the repository, which is itself
the argument for fixing the gap properly.

#### The same guard has a second, unrelated blind spot

`DocumentCitationGuard.extensions` is an explicit allowlist, and `sql` and `go` are not in it. So
`` `migrations/005_data_dispute_kinds.sql` `` and `` `internal/api/server.go` `` — both cited in
this round's documents, both written relative to `server/` rather than to the repository root, so
neither resolves from where the guard looks — are invisible to it. The guard's own header records
this limit honestly for `.csv`, `.html`, `.sql`, `.xcconfig` and `.geojson`, and explains why
widening the list is not free. The entry notes it here only so the two gaps are not confused: the
first is a guard that does not run, the second is a guard that runs and cannot see.

#### A third instance, found by the same question

`docs/ROADMAP.md`'s chip backlog contains **two items numbered 8**. The list reads 1-8, 8, 9, 10,
11: twelve items whose last number is 11, so every cross-reference by number past the eighth is
ambiguous. Nothing guards the numbering of the file CLAUDE.md names as the project's only queue.
It was found on 2026-09-10 by running a numbering assertion against main *as a control*, expecting
silence — the same move that CLAUDE.md's calibration rule prescribes, and the reason it is in there.
