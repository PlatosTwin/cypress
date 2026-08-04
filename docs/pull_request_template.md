<!--
This template is inert until the beta lock (docs/CONTRIBUTING.md). Before then, work lands on main
directly and this file describes a regime that is not running yet.

It lives in docs/ rather than .github/ — GitHub reads a pull request template from the root,
.github/ or docs/, and docs/ is the only one of the three inside the pipeline's paths-ignore.
Under .github/ every edit to this checklist would ship a TestFlight build, and the alternative —
adding an exception to that deny-list — would weaken a rule whose safety argument is that it has
no exceptions.

The checklist is not a formality. Every line is a failure that has already happened in this repo.
-->

## What this changes

<!-- The ticket, and what a reader of main will now see that they did not see before. -->

Closes #

## Verification

- [ ] Suite run on the **merged** tree, not the branch — `Tools/run_tests.sh`, judged by
      `Tools/verify_test_log.sh`, VERIFY-OK line pasted below with its `CYPRESS-RUN` header.
- [ ] Zero-warning line certified on a **fresh** DerivedData
      (`Tools/verify_test_log.sh --warnings <log> <files…>`).
- [ ] Every new test red-proved, and the failure message names the assertion it was supposed to
      name.
- [ ] Anything the simulator cannot see (map performance, camera, heading) is named here as still
      owed on the physical phone.

```
paste the VERIFY-OK line and the CYPRESS-RUN header here
```

## Author's declaration

- [ ] No number quoted from the seed in a comment or doc without re-measuring it.
- [ ] No comment asserts an invariant I did not verify.
- [ ] Errata and rulings written **unnumbered** to `docs/errata-pending/` or
      `docs/rulings-pending/`; no number written into `docs/ERRATA.md` or `docs/RULINGS.md`.
- [ ] No migration authored, or the orchestrator explicitly named me as this round's migration
      author.
- [ ] Premises in the ticket checked against the code — list any that turned out to be wrong:

## Adversarial review

Assigned to an agent that did **not** write this change, working from the ticket and the diff, in
its own worktree at this PR's head, with its own simulator and DerivedData.

- [ ] Reviewer ran the suite itself and did not read the author's log.
- [ ] Reviewer re-proved each red-proof.
- [ ] Reviewer reports what it tried to break and how it failed, even when it found nothing.
- [ ] Every review thread resolved by the author fixing it or the orchestrator ruling on it in the
      thread. **The author does not resolve its own threads.**
