# Rulings pending: how the C3 round read the owner's pin-move answers for the Outbox and the Journal

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

The owner's answers are in `community-trees-c3-answers.md` (the Move pin and Journal entries) and
`community-trees-answers-2026-11-15.md` (the square on a history row). This entry records the
decisions the building round made where those answers left a detail open. Each is a reading of the
nearest specified thing, not a new design.

### R??? — The Outbox row and the Journal row for a pin move

1. **The Outbox row.** `OutboxCopy.kindLabel(.locationCorrection)` is "Pin moved", so the row is
   "Pin moved · Grandmother Cypress". It has no sub-line; the time follows the title alone, as for
   every other kind with no sub-line. A refused move reads "This couldn't be sent.", which
   `OutboxFailureReason.describe` already gave every terminal non-moderation refusal regardless of
   kind. Nothing changed there; `PinMovedOutboxTests` pins it for `forbidden` and `not_found`.
2. **Which moves are Journal rows.** A row of `tree_locations` that is not the tree's root row (the
   root records the add), that this phone's person wrote (the owner predicate the four other arms
   use), whose tree is not withdrawn (every Journal row opens a profile), and whose key is not
   tombstoned by an account deletion. The row's date is the move's `occurred_at`, the moment the
   person saved it.
3. **No second line in the Journal.** The owner's words are the title, "Moved the pin of X". The
   row's subtitle is empty, so `IconTextRow` draws one line. A distance ("12 m north") was the
   owner's choice for the profile's history rows, not for the Journal, and the Journal has no
   other place that names one.
4. **The square.** The community tree mark (`CommunityTreeTile`) at the Journal row's 34 pt tile
   size and corner. It replaces the tree's photograph too, not only the accent: the row is about
   where the pin is, and the owner chose the mark for this row by name.
5. **The export carries pin moves.** The Journal export is "a copy of everything you have recorded
   on this phone" and is built from the whole journal, so each move is a row of kind `pinMoved`
   with an empty summary. The GeoJSON point is the tree's current position, as for every other
   kind. The add's root row is not exported, because it is not a move.
6. **No migration.** The Journal's fifth arm walks `tree_locations` (it has no index on
   `occurred_at` alone) and hands its rows to the outer sort without sorting them itself. The plan
   gate allows the walk by name, because the table holds only the chains of trees this phone added:
   one root per add and one row per move. That exemption rests on the premise that only this
   phone's own adds and moves write `tree_locations`. It is true today: the cache of other people's
   trees writes only `community_tree_cache` and `community_tree_cache_tiles`.

#### A limit the round found (a fact, not a ruling)

- **After sign-out, pin moves leave the Journal and the export, and visits stay.** Sign-in moves a
  `tree_locations` row to the account (`user_id` set, `device_id` NULL), and visits keep their
  `device_id`. A signed-out phone reads by `device_id`, so it no longer finds the moves. They come
  back at the next sign-in. The review's probe: add a tree signed out, move it, visit it, sign in,
  move and visit again, sign out; the Journal then reads 0 moves and 2 visits.
- The arm has no column that could keep these moves after sign-out without a schema change. The
  owner has not ruled on it. The arm's behavior was not changed.
- **Resolved on 2026-11-16** by `feat/journal-keeps-pin-moves`. The owner chose "Everything, pin
  moves too". Migration v24 adds `tree_locations.set_on_device`, and the fifth arm also matches a
  move this phone set, so the probe above now reads 2 moves and 2 visits. The ruling is
  `journal-keeps-pin-moves.md` in this folder.

---

*Added after the sections above, by the branch `feat/withdraw-owner-answers`.*

### R??? — A pin move on a tree with no name (the owner's answer, 2026-11-16; ROADMAP 159)

Q: "A community tree with no species reads "Moved the pin of Tree" in the Journal and "Pin moved ·
Tree" in the Outbox. Which words should those two rows use for such a tree?"
Chosen: **""Moved a tree's pin""**. Journal: `Moved a tree's pin`. Outbox: `Pin moved`.
Not chosen: "Leave as is"; ""an unnamed tree"".

How the branch `feat/withdraw-owner-answers` built it (the author's notes):

- **The apostrophe on screen is the typographic one** (`Moved a tree’s pin`, U+2019), as in the
  app's other on-screen strings, for example `Report a mistake in the city’s record`.
- **Only where the row would otherwise read the fallback title "Tree".** Each row knows that from a
  fact, not from the word: the Journal row from an empty `treeDisplayName`, and the Outbox row from
  no resolved name (`treeName` nil). Both come from `LocalAPI.displayNames`, which follows the
  next entry's rule: the words show only for a tree with no given name and no species.
- **Only the pin move changes.** Every other kind on an unnamed tree still reads the fallback, for
  example "Visit · Tree" and "Visited Tree".
- **A city tree cannot reach either row.** A pin move is made only on a community tree the reader
  added (`LocalAPI.correctLocation`).

### R??? — Rows name a community tree by its species (the owner's answer, 2026-11-16)

The question in the entry above (the owner's answer 6) said "a community tree with no species":

Q: "A community tree with no species reads "Moved the pin of Tree" in the Journal and "Pin moved ·
Tree" in the Outbox. Which words should those two rows use for such a tree?"
Chosen: **""Moved a tree's pin""**. Journal: `Moved a tree's pin`. Outbox: `Pin moved`.
Not chosen: "Leave as is"; ""an unnamed tree"".

The branch first built "no given name", because the code's name rule never used an added tree's
species as its name in a row. The review found the difference, and the owner was asked (answer 10):

Q: "A tree someone added has a species but no given name. Its profile title is the species (for
example "Sycamore, London Plane"), but its Outbox and Journal rows never use the species. They
read "Pin moved" and "Moved a tree’s pin" (your new words), and other rows read "Visit · Tree".
My earlier question said "no species"; the built rule is "no given name". What should those rows
call such a tree?"
A: "Use the species (Recommended)". Option text: "Rows name the tree as its profile does: "Pin
moved · Sycamore, London Plane", "Moved the pin of Sycamore, London Plane", "Visit · Sycamore,
London Plane". Your new words then show only for a tree with no name and no species. This changes
an older rule in the code that an added tree's species is not used as its name in rows."
Not chosen: "Keep as built" ("Rows use only a given name. Every added tree without one reads
"Pin moved" and "Moved a tree’s pin", and its other rows read "· Tree", even when it has a
species.").

**Answer 10 replaces the old code rule** that an added tree's species is not used as its name in
rows (D15's "a self-asserted species is not a name the app puts on a tree", as the Journal and
Outbox applied it).

How the branch `feat/withdraw-owner-answers` built it (the author's notes):

- **One rule, in `LocalAPI.displayNameIfPresent` and `LocalAPI.displayNames`:** the tree's active
  given name; else, for a tree in the city inventory, its species' common name (as before); else,
  for a community tree, the common name of the species its profile title shows. That species is
  the row's `species_current`, with the reader's own naming or correction laid over a cached tree
  while it is in force (`localSpeciesAnswers`, ROADMAP 144), the same overlay `treeProfile` uses.
  A species with no common name reads its scientific name, as the profile does.
- **A withdrawn tree this phone still holds keeps its species name**, so `Tree withdrawn · …` and
  the refused row still name it.
- **The callers:** the Journal (its rows and their VoiceOver labels), the Outbox, and the private
  reminders list on the Account screen. The export does not carry a tree name.
- **Not changed: My Grove's Trees list and its city-file rows** (`LocalAPI.grove()`,
  `RoutedAPI.resolvedCityFileRows`). They keep the old rule, so an added tree with a species and
  no given name still reads with no name there. Answer 10 named the Outbox and the Journal; whether
  My Grove follows is open with the owner.
- **The profile is one read ahead in one case.** After a service read, `RoutedAPI` can show a
  species the service served before this phone's cache holds it. The rows use what the phone
  holds, so for that window the row can name the older species.
