# How work lands on main

Two regimes. The first is in force now. The second is written, wired, and switched off, and the
owner throws the switch — not an agent, not a schedule, not whoever reads this next.

**Never read this file to find out which regime is running.** Prose goes stale here; the
`docs/ERRATA.md` shelf is half made of documents that described a state the code had left. One
command answers it, and it asks GitHub rather than a paragraph:

```bash
gh api repos/PlatosTwin/cypress/rulesets --jq '.[] | "\(.name)\t\(.enforcement)"'
```

`main-pull-request-only → disabled` is regime 1. `→ active` is regime 2.

---

## Always, in both regimes: main cannot be rewound or deleted

Ruleset `main-guardrails`, enforcement **active**, **no bypass actors** — the owner's own admin
account is subject to it too. Two rules: `non_fast_forward` and `deletion`.

Verified 2026-08-03 on a throwaway branch carrying the same two rules: a force-push and a delete
were both answered `push declined due to repository rule violations`, and both succeeded against
the same branch seconds later with the ruleset removed. The control is the half that matters — a
rule that has never been seen to reject anything is a rule nobody has tested.

**`git push --dry-run` does not evaluate rulesets.** It reported `(forced update)` for a rewind
the server then refused outright. A dry run is not a run; it is the same false green this project
already has a whole section of `CLAUDE.md` about.

The practical consequence: **there is no rewriting main.** A bad commit on main is recovered
forward, with a revert. Nothing on main can be made to have never happened, including by the owner,
without deleting the ruleset first — which is a deliberate act, which is the point.

Tags are untouched by this. The release job's `build-N` tag still pushes.

---

## Regime 1 — now, through the beta lock

Work lands on main directly, exactly as it does today. The merge protocol is unchanged and is not
relaxed by anything in this file:

- merge the branch to main **locally**;
- run the suite **on the merged tree** — a branch's green proves the branch;
- certify the zero-warning line on a **fresh** DerivedData;
- then push.

This regime is deliberate. The beta is not locked, the feature set is still moving, and a review
gate between an agent and main would cost a round-trip per ticket at exactly the moment the work is
cheapest to redo. It is a trade, and it is being made knowingly.

## Regime 2 — after the beta lock

**Trigger:** the owner declares the beta feature set frozen. #187 is where that lands; **#206 is the
switch itself** and carries this checklist. No agent throws it, and no agent may assume it has been
thrown.

From that moment, every change that is not a documentation edit ships as a pull request, reviewed
adversarially by an agent that did not write it, and merged by the orchestrator.

### What GitHub can and cannot enforce here

Worth stating plainly, because a policy that quietly does nothing is worse than no policy.

**It cannot enforce an approval.** The owner is the only human account, and GitHub forbids
approving your own pull request. `required_approving_review_count` is therefore **0** and must stay
0 — set it to 1 and the only person who can merge is locked out of their own repository. A second
account would fix this and none is planned for the beta.

**What it does enforce** is a surface and a gate:

- there is a diff, at a URL, that a reviewer can attach findings to, and no change reaches main
  without one;
- `required_review_thread_resolution` means every thread the reviewer opens must be resolved before
  the merge unlocks. A finding cannot be ignored into oblivion; somebody has to answer it;
- `dismiss_stale_reviews_on_push` means a review does not survive the code it reviewed;
- the required status check means the suite ran.

The adversarial part is not enforced by GitHub and never will be. It is enforced by the checklist
in `docs/pull_request_template.md` and by the orchestrator refusing to merge without it.

### The review protocol

**The reviewer is a different agent.** Spawned fresh by the orchestrator, given its own worktree
checked out at the PR head, its own simulator, and its own DerivedData. It does not read the
author's transcript and is not told what the author concluded — it is given the ticket and the
diff. An author reviewing its own work re-runs its own reasoning and finds its own blind spots
exactly as often as it found them the first time, which is never.

**Its brief is to find the reason this must not merge.** "Looks good to me" is not an outcome. A
review that finds nothing must say what it tried to break and how it failed — the attempts are the
evidence that the review happened.

Six passes, each of which exists because it has already caught something here:

1. **Re-run the suite yourself, on the merged tree.** Do not read the author's log, do not trust
   its green line, do not accept a log with no `CYPRESS-RUN` header. Every provenance erratum in
   this repo was written after somebody believed an artifact they did not watch being produced.
2. **Re-prove every red-proof the author claims.** Break the code yourself and read the failure
   *message*, not the colour. Red-proofs here have gone red on the wrong assertion, exempted the
   thing they were guarding, and run their specimens before their rule.
3. **Check every comment that asserts an invariant.** Start with the most confident one in the
   diff. Four defects have survived in this codebase specifically because a comment said they
   could not exist.
4. **Check every number quoted from the seed, against the seed.** Counts here go stale silently
   (#122, #198), and a stale count in a comment reads exactly like a fresh one.
5. **Check the premises of the ticket.** Briefs have been wrong repeatedly, and agents refusing a
   false premise is this project working correctly, not an agent going off-task.
6. **The mechanical line:** layering (ARCHITECTURE §2), tokens only, no SF Symbols, American
   spellings, and the zero-warning line — the last of which counts only through
   `Tools/verify_test_log.sh --warnings` on a fresh DerivedData, because a reused one recompiles
   nothing and reports nothing.

**Findings go in as one PR review thread each** — file and line, what fails, and what input makes
it fail. A finding that cannot name a failing case is an opinion, and opinions go in the PR
comment, not a thread.

**The author does not resolve its own threads.** The orchestrator adjudicates: fixed, or ruled on
with a reason written into the thread. Both are legitimate; silently resolving is not.

**`strict_required_status_checks_policy` is not the merged-tree rule.** GitHub's "branch is up to
date with main" makes the *diff* current; it does not run the suite on the merge result. Regime 1's
merged-tree run is still owed, still by hand, and still the only thing that proves main.

---

## The beta-lock checklist

In order. Steps 1–2 must land before 3, or the required context never reports and the branch is
unmergeable by anybody.

**1. Teach the pipeline about pull requests.** In `.github/workflows/testflight.yml`:

```yaml
on:
  push:
    branches: [main]
    paths-ignore: [ 'docs/**', '*.md', 'graphify-out/**' ]   # unchanged
  pull_request:
    branches: [main]
    paths-ignore: [ 'docs/**', '*.md', 'graphify-out/**' ]   # the same three
  workflow_dispatch:
```

Guard the deploy so a pull request cannot ship:

```yaml
  release:
    needs: [unit, ui]
    if: github.event_name != 'pull_request'
```

And split the concurrency group, or every PR run queues in front of a deploy that is already
waiting:

```yaml
concurrency:
  group: testflight-${{ github.event_name == 'pull_request' && github.head_ref || 'main' }}
  cancel-in-progress: false
```

Add one job whose name never changes, for the ruleset to require:

```yaml
  # The UI matrix's contexts are "ui (1)"…"ui (N)", and N is DERIVED from
  # Tools/ui-test-shards.txt. Requiring them by name would break the day a shard line is added —
  # and break it as an unmergeable branch, not as a red test. This job's name is stable.
  gate:
    needs: [unit, ui]
    if: always()          # without this a failed dependency SKIPS the gate, and a skipped
                          # required check is not a failed one — the classic hole
    runs-on: ubuntu-latest
    steps:
      - name: Refuse unless every test job succeeded
        run: |
          set -euo pipefail
          echo "unit: ${{ needs.unit.result }} / ui: ${{ needs.ui.result }}"
          [ "${{ needs.unit.result }}" = "success" ] || exit 1
          [ "${{ needs.ui.result }}" = "success" ] || exit 1
```

**2. Push it to main and let it run once**, so the `gate` context exists for GitHub to offer.

**3. Add the status check and turn the ruleset on** — one call, ruleset `20356185`:

```bash
gh api --method PUT repos/PlatosTwin/cypress/rulesets/20356185 --input - <<'JSON'
{
  "name": "main-pull-request-only",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["merge", "squash"]
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [ { "context": "gate" } ]
      } }
  ]
}
JSON
```

**4. Prove it, with a control.** Not a dry run — see above.

```bash
git commit --allow-empty -m "probe" && git push origin main   # must be REJECTED
git reset --hard origin/main
```

If that push succeeds, the switch is not thrown, whatever the enforcement field says.
