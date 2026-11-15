# Rulings pending: a community tree's "added" day is the day its phone added it (owner's ruling, 2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename. The first entry is the owner's ruling. The second records the service
design that applies it (`feat/community-tree-added-day-server`, server migration 008); it is the
author's reading within delegated authority, logged for review.

---

### R??? — One "added" day for every community tree: the day it was added on the phone

**The owner's decisions.**

1. **2026-11-14**, in the decision round for trees added before syncing existed
   (`community-trees-old-trees.md`, choice 4): other people see "the day it was added", the original
   day on the adder's phone, not the day it went live.
2. **2026-11-15**, AskUserQuestion. The question:

   > Other people see an 'Added' day on a community tree. You chose the original day for trees that
   > predate syncing. Your earlier rule (2026-09-28) says a tree added on a signed-out phone shows the
   > day it went public, which is the sign-in day. That leaves two rules. Which day should a tree show
   > when it was added recently on a signed-out phone and went public later?

   Offered:
   - **"The day it was added (Recommended)"**: "One rule for every community tree: the day the
     person added it on their phone. This changes the date part of the 2026-09-28 rule. Positions
     from while the tree was private still stay private."
   - **"The day it went public"**.

   **Chosen: the day it was added.**

**The rule.** For every community tree, old or new, and for every viewer, the adder included, the
"added" day is the day the person added the tree on their phone. It is served at day precision on
the tile (`GET /community-trees`, `createdAt`), the profile (`GET /trees/{id}`,
`community_tree.createdAt`) and the history (`GET /trees/{id}/history`, the `added` row's
`occurred_at`). No "predates sync" flag is needed or sent.

**What this changes in decision 13 and its rulings.**

- **The date half of decision 13 and the V1 ruling** ("A stranger is told a tree was added the day it
  went live", `community-trees-reads.md`) are replaced. Strangers were told `published_at`; the adder
  was told the service's receipt time (`created_at`). Both are now told the phone's day.
- **The history's "added" row** is dated by that day. Before, it was dated by
  `GREATEST(occurred_at, published_at)` of the `published` event, which is the publication day.

**What it leaves alone.**

- **Positions stay private.** The "added" row still stands at the position the tree held when it went
  public, not the position it was first added at. Positions held and pin moves made while the tree was
  private are never served (decision 13, the position half; the L1 ruling).
- **Every other private act stays undated.** A move or a naming the adder made while the tree was
  private, which reaches the service after publication, is still served at no earlier than the day
  the tree went live (L1). The owner made the add day public, not the days of the private acts.
- **A private tree is still served to nobody but its adder.** Publication, the license rules
  (decisions 7 and 10), withdrawal, takedown, the deletion doors, and who may see what are unchanged.
- **`updatedAt`** is unchanged: the UTC day of the last change, publication included.

### R??? — How the service knows the phone's day (server migration 008)

**Decided by:** the author of `feat/community-tree-added-day-server`, applying the ruling above.

**The column.** `community_trees.added_on DATE NOT NULL`, written once at insert and never changed.
There is no default, so a writer that forgets it fails.

**The wire key.** The `add_tree` payload (`TreeAddition`) may carry **`addedOn`**: the phone's
**local** calendar date of the add, exactly `YYYY-MM-DD`. It is decision 14a's `captured_on` idea,
spelled the way this payload spells its keys (after the Swift property, camelCase; the README's key
convention). Optional; `null` is the same as absent.

- A value that is not a date in exactly `YYYY-MM-DD` (`"2026-10-1"`, `"2026-02-30"`, `""`, a number)
  is a malformed item: `validation_failed`, like every other malformed field of `add_tree`.
- A real date is never refused. The tree is good even when the phone's calendar is not, so an
  implausible day is replaced, as below.

**Which day is stored** (`store.addedDay`):

1. **The instant** is the item's `occurred_at`. If it is after the moment the service received the
   item, the phone's clock ran fast, and the receipt stands in for it: an add cannot happen after the
   service received it.
2. **Without `addedOn`**, the day is the instant's **UTC** date. The service holds no time zone, so a
   tree added at 23:30 Pacific time (06:30 or 07:30 UTC the next day) shows **the next day**. This is
   what every installed build gets, and what the backfill gives every existing tree. It is the same
   limit the history has had for every event since round 1.
3. **With `addedOn`**, the stated day is used when it is within one day of the instant's UTC date. A
   local date never differs from the UTC date of the same instant by more than one day (UTC−12 to
   UTC+14), so a day further off is not this add's day, and the instant's UTC date is used instead.
4. **A day before 2026-07-21** (the project's first commit; no build of the app existed earlier) is a
   phone clock that was wrong. There is no true day to recover, so the receipt's UTC date is used: it
   is the latest the add can have happened, and the day the service showed before this change.

So the stored day is never later than one day past the receipt's UTC date, which is the receipt day
in the phone's own zone. A CHECK (`community_trees_added_on_not_after_receipt`) holds that bound in
the database too. Refusing an implausible day was rejected: an `add_tree` that fails is terminal on
the phone, and it would lose a good tree over its date.

**The history.** The `published` event, served as `added`, is dated by `added_on`. Every other public
event is served at `GREATEST(occurred_at, published_at, added_on)`: the L1 floor, plus a floor at the
add day so that no row is dated before the "added" row below it. That second floor matters only east
of UTC, where `added_on` can be one day after the publication's UTC date. The list is still ordered
by `GREATEST(occurred_at, published_at)`, then `recorded_at`, then the id, so "added" stays the oldest
row.

**Existing rows.** Migration 008 backfills `added_on` from data the service already holds: the
`added` event's `occurred_at` (the phone's instant), else the root location's, else `created_at`;
held to the receipt, with the 2026-07-21 floor. No existing row carries a phone-stated day.

**Old installed phones.** They send no `addedOn`. The service before 008 decoded the payload with
`json.Unmarshal`, which ignores unknown keys, so a new phone talking to the old service is not refused
either. In either deploy order nothing breaks. An old phone's tree shows the UTC date of its add's
instant, which is the phone's own day except for adds late in the evening west of UTC (or early in
the morning east of it).

**Wire shape.** Unchanged: the same keys, and the same calendar-day form (midnight UTC). One thing a
client may meet that it did not before: a community tree's `createdAt` can be one day after its
`updatedAt`'s day, for a tree added east of UTC on a day that was still the previous day in UTC.

**The index.** 008 also drops `idx_community_trees_position` (001), which only the retired 10 m dedupe
read (ROADMAP 141 (a)). The tile's position arm is served by 007's partial
`idx_community_trees_public_position`, and `TestTheTileIndexesServeTheirQueries` still checks that.
