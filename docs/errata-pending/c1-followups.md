# Errata pending: community trees C1 follow-ups (ROADMAP 107, 115, 116)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

---

### E??? — Which outbox rows wait for their tree's add, and why the others do not

**ROADMAP 115's premise was partly wrong.** It said a species claim, a report or a photo vote on a
tree the service has not received is answered `not_found`. On the service (`server/internal/api/sync.go`,
`server/internal/store/community_trees.go`), only `location_correction` is refused that way. A species
claim or correction is recorded and **never applied to the tree** (`materializeSpecies` returns nil
for a tree it does not hold), which is a silent loss rather than a red row. Reports, dismissals, photo
votes, hazard redirects and disputes are recorded against the tree's id, and nothing looks the tree up.

`OutboxItem.Kind.waitsForItsTreeAdd` now holds:

| Kind | Held | Why |
|---|---|---|
| `location_correction` | yes | `not_found`, terminal (#209) |
| `species_claim`, `species_correction` | yes | applied to the tree only when the service holds it |
| `add_tree` | no | it is the tree |
| `visit`, `observation`, `measurement`, `care_event`, `favorite_toggle`, `private_reminder` | no | the drain is their local apply; holding one would keep a visit off its tree on this phone while the add waits for a network. The service never looks the tree up |
| `wrong_species_report`, `never_existed_report`, `species_review_dismissal`, `record_review_dismissal`, `photo_vote`, `hazard_redirect`, `data_dispute`, `data_dispute_withdrawal` | no | recorded against the tree's id, never refused, change nothing on the tree |
| `photo_withdrawal`, `measurement_withdrawal` | no | keyed on the photograph or reading; the service handles either arrival order |

Photographs ride on their own row (an add's or a visit's), so a photograph of a not-yet-sent tree
goes when its row goes, and the service's photo begin does not look the tree up.

### E??? — The time a row waits behind its tree's add is left out of its 48 h window

ROADMAP 116. A held row is never in a pass, so nothing banked its wait. Each drain pass now runs
`OutboxStore.creditHeldBehindAdd` first: every pending row the hold predicate matches has its window
moved forward by `now - updated_at`, and `updated_at` is restamped. `OutboxStore.window` credits a row
held behind an add the same way it credits a wi-fi hold, so the other writes that bump `updated_at`
(`creditHold`) bank it too. No column and no reason sentence: screen 17 draws a pending row's reason,
and the hold has no ruled sentence.

Known limit: if an add fails terminally and is later retried, a dependent row that was not drained
in between is credited for the failed stretch as well. That only delays expiry.

### E??? — Move pin is offered only for a tree the service may hold

ROADMAP 107. `CommunityTreeStore.mayHaveReachedService`: the tree's `add_tree` row is still in the
outbox, or the tree was added on or after `firstQueuedAddsAt`, 2026-08-21 18:54:57 UTC. That is the
date of `build-43`, the first build tag containing #s34 (`6ae2f4f9`), a lightweight tag on PR #103's
merge commit `ac4d8cbd`. The tag's date is used, not the commit's, because only builds 42 and older
existed before the merge, and none of them queued adds.

Still wrong, stated: a tree added after that date on a build that had not been updated yet, and a
pruned add row whose adder v23 guessed. C2's `added_by_you` replaces this test.
