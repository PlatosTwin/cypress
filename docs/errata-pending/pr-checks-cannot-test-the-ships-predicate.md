### A PR's check list can never test the `ships` predicate, and `release: SKIPPED` there means nothing

The release job carries:

```yaml
    if: github.event_name != 'pull_request' && needs.plan.outputs.ships == 'true'
```

On a pull request the **first clause** decides it. `release` reports `SKIPPED` on every PR, always,
whatever `plan` computed — a PR whose diff is nothing but app source shows exactly the same
`SKIPPED` as one that touches only docs. The second clause is never reached, so the PR's check list
carries no information about the deny-list at all.

This was misread once, on 2026-08-04, in the worst possible place: PR #4 was the PR that *added the
gate for that very predicate*. Its checks showed `release SKIPPED`, that was cited as "a second,
independent confirmation of #212", and the merge then went on to decide `shipping — these can
affect the app:` and start minting build 13 for a diff of one test file and one root `.md`. It was
cancelled mid-run. See #215.

**Only the merge run tests the predicate.** If you want to know what a branch will do to the build
number, do not look at its checks — replay the predicate over the diff:

```bash
git diff --name-only main <branch> \
  | grep -vE '^(\.github/|CypressTests/|CypressUITests/|docs/|graphify-out/|[^/]*\.md$)'
```

Output means it ships. Silence means it does not.

This is the CLAUDE.md "calibrate the instrument" rule catching its own author. The reading was real,
the job genuinely was skipped, and the output was answering a different question than the one being
asked — which is what that rule says is indistinguishable from an answer.

**And the obvious calibration is not available here**, which is worth knowing before someone reaches
for it. The natural control is "check the same field on a PR that certainly *does* ship, and watch
it report `SKIPPED` too" — but every PR this repo has had (#1–#4) is a no-ship diff, so there is no
contrasting case on record. The claim above rests on the `if:` expression short-circuiting, not on
an observed contrast. When the first app-source PR lands, that is the control: if its `release`
reports anything other than `SKIPPED`, this entry is wrong and should be deleted.

Until then the replay command is the instrument, and it does not depend on any of this.
