# Rulings pending: round C3, package A (the tree profile), the author's decisions (2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". Each entry is the package author's call
under the round's brief, for the orchestrator or the owner to confirm or reverse. The owner's own
answers are in `community-trees-c3-answers.md`, `community-trees-answers-2026-11-15.md`,
`community-trees-added-day.md` and `community-trees-only-you-can-see.md`. No code comment cites this
filename.

---

### R??? — How history rows sit among visits and care

**Decided by:** the package A author.

- Newest day first. On one day, visits and care sort above history rows. A history row carries a
  day and no time, so this is the only order that invents no hour.
- History rows keep the service's order (newest first). The phone's own "Added" row, when there is
  one, is last.
- A move whose start or end is missing reads `Pin moved` (or `You moved the pin`) with no distance.
  A move that rounds to 0 m reads `· 0 m north`; the service refuses neither.
- An event of a kind this build does not know makes no row.
- `See the whole year` shows only when there is a visit or care row (`offersActivityLink`), because
  screen 13 charts visits, check-ins and care, and a history row is none of them.

### R??? — The "Added" row when the phone has no history

**Decided by:** the package A author, applying the owner's answer ("the Added row only") and the
added-day ruling.

- Drawn when the history was not read, is empty, or was capped before its `added` event.
- Its day: for a tree in this phone's own table, the add's instant in the reader's zone (it is the
  adder's own phone). For a tree from the community cache, the cache's `createdAt` read as the UTC
  day, because the service sends the added day as midnight UTC.
- "You added this tree" when `addedByYou`, else "Added".

### R??? — What "the service says the tree is not shared" means

**Decided by:** the package A author, applying the owner's "Keep today's note" for the unknown state.

The only fact the wire carries is `is_published` on `GET /trees/{id}`. The service also answers
`false` for a city tree, an unknown id and a hidden one, so the phone reads it only when the same
response carries a non-null `community_tree`. With the phone's sharing state unknown (a reinstall
restore, or an account from before the answer was stored), the line shows only when the reader
added the tree and the service says `is_published: false`, and it is the not-sharing line: the
reader is signed in and the tree is held back, which happens only to an account that has not
agreed. Offline, or with the gate shut, nothing is said in the unknown state.

### R??? — "A tree the reader did not add" includes one on this phone

**Decided by:** the package A author, applying the owner's "Hide species controls for now".

The owner's rule hides both species controls on a tree somebody else added. Two kinds of tree meet
it: one in the community cache, and one in this phone's own table that another account (or this
device before a different account signed in) added. Both now offer neither control. Before, the
second kind offered "Report the species as wrong" to the reader, and `SpeciesCorrectionTests`
pinned that; the test now pins the new rule. The verbs (`claimSpecies`, `correctSpecies`,
`flagWrongSpecies`) are unchanged.

A tree the reader's account added on another phone reaches this one only through the cache. The
service says it is theirs (`added_by_you`), so its rows say "You…", but the species verbs act only
on this phone's own rows, so it offers no species control, as before C3.
