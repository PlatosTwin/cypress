# Rulings pending: community trees added before syncing existed reach everyone (owner's ruling, 2026-11-14)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

---

### R??? — Old community trees are sent, with everything recorded on them (reverses R77 for community trees)

**The owner's ruling of 2026-11-14.** It reverses a rule the owner had made twice: R77 ("No backfill",
2026-08-15), and the sentence in the community-trees decisions of 2026-09-28 that "trees added before
the sync path existed stay local for ever (R77 is kept, and there is no backfill)".

**The owner's words**, on reading that sentence in a status report: *"reverse. trees that are community
added should make it onto everyone's phone regardless of when they were added."*

**What was asked and what the owner chose** (decision round, AskUserQuestion, 2026-11-14):

1. **How far the reversal goes.** Offered: the tree and its photograph; the tree only; everything on
   those trees. **Chosen: everything on them.** For a community tree that the service never received,
   the phone sends the tree, its photographs, and every visit, measurement and care event recorded on
   it before syncing existed.
2. **How an old tree is sent.** Offered: automatically; ask once first. **Chosen: automatically.**
   After the app update the phone queues each old tree once, with no question, as a new tree goes
   live without a prompt.
3. **A signed-out phone.** Offered: the same rule as new trees; publish anyway. **Chosen: the same
   rule.** The decision of 2026-09-28 stands for old trees too: a tree on a signed-out phone waits,
   and goes live when that person signs in.
4. **The "added" date other people see.** Offered: the day it was added; the day it went live.
   **Chosen: the day it was added**, the original day on the adder's phone.

#### What this changes in R77

- R77's ruling ("pre-sync-path local rows and pre-existing photo binaries stay on-device
  permanently") **no longer holds for rows on a community tree.** Its first consequence, that
  pre-existing local rows must never be retroactively enqueued, is no longer permanent policy for
  those rows.
- R77's third consequence told agents not to raise backfill again. The owner raised it. This entry is
  the record that the reversal is the owner's.

#### What this does not change (the orchestrator's reading; the owner was not asked)

- **Rows on a city tree.** The questions were about community trees. A visit, measurement or
  photograph on a tree from a city's inventory that was recorded before syncing existed is still
  under R77 and stays on the phone. Ask the owner before widening it.
- **The other decisions of 2026-09-28** (the adder alone moves the pin, withdrawal while nobody else
  has built on the tree, history shown without saying who, a photograph's date and never its time).
- **R77's own mechanics.** A photograph taken before syncing existed has never had a send path; the
  round that builds this must check what the photo route accepts today and must not assume it.

#### What the round that builds it has to settle (facts to verify, not rulings)

- A tree added before the first build that queued adds has no `add_tree` row, and
  `CommunityTreeStore.firstQueuedAddsAt` is the cutoff ROADMAP 107 uses for it. That rule hides Move
  pin for such a tree; once the tree is sent, the offer should follow the add row as it does for a new
  tree.
- The service's proximity rule can answer an old tree's add with a conflict. What the phone then does
  with the rows recorded on that tree needs a decision when it is found.
- "The day it was added" needs the service to keep the phone's date for the tree and for each row.
  Check what `POST /sync` records for an `add_tree` today before promising it.
