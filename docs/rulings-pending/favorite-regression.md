### R30 — the copy names the control the app draws, and the heart stays unbuilt (task #139)

**The finding.** The map's Favorites empty state said *"You have not hearted a tree yet. Tap the
heart on any tree's page and it will appear here."* The owner reported it as false, and it is. See
ERRATA E184.

**The question this ticket forced.** Two closures were available and the choice was real: either the
heart affordance ought to exist and is missing, in which case the copy is a bug report against the
screen; or the copy describes something that was never drawn, in which case the copy is the bug.

**The ruling: the copy is the bug, and no heart is built.**

The record is one-sided once you go and look at it:

- `SCREENS.md` §2 C8 — "**NOT SPECIFIED:** icons for these four actions — the spec shows text only."
- `SCREENS.md` §5 gap 3 — "Icons for `Favorite` / `Care` / `Share` / `Report` (C8) — text only."
- `SCREENS.md` 03 §6 draws the row as `Favorite` · `Care` · `Share` · `Report`.
- `mocks/cypress-mocks.html` contains the string "heart" **zero** times.
- RULINGS R2 already litigated this and corrected itself in the building: its first draft said "the
  heart glyph fills, glyph and label take `accent`", and the correction reads "**C8 has no glyph.**
  … Adding a heart to one of four text cells would have been a drawn decision on the very component
  this ruling treats as already-drawn — constraint 21, arriving from the direction I was not
  watching."

So the heart is not a replaced affordance whose copy outlived it. It is a word that entered the
prose from R2's retracted first draft and reached a user-facing sentence. Building one now would
mean inventing a glyph for one of four text cells — DECISIONS constraint 21, refused once already
for these exact reasons — and it would be a **sixth** violation of the drawn-glyph policy the
project is already carrying five of (#130). The day design lands the four icons, R2 says it is one
line in `QuadActionRow.appearance`, and this ruling does not move that day earlier.

**No mock is overruled and `SCREENS.md` is not amended.** This is worth stating beside #137, which
established the convention for departing from a mock deliberately — update `SCREENS.md` in place
with the reason next to it, and record the departure in the ruling. That convention does not apply
here, and applying it would have been the mistake: #137's screen departed from its mock and the mock
needed the note. Here the *copy* had departed from the mock, and the fix is the copy coming back.
Writing a departure note for a change that removes a departure would leave the record claiming a
divergence that no longer exists.

**What the sentence says now.** *"You have not favorited a tree yet. Tap Favorite on any tree's page
and it will appear here."* It quotes the cell's own label, which R2 fixed as `Favorite` in both
states — a noun naming the thing rather than a verb naming the next tap — so the word the notice
sends the reader to look for is the word they will find. A test asserts the two strings agree, and a
second sweeps every sentence the type can produce for the word "heart", because the failure mode
here was not one bad sentence but a word that no test would notice being wrong.

#### A note on copy tests

`MapFilterTests` required the empty state to contain the word "hearted". The intent was sound — a
reader with no favorites must be told what to do rather than told to pan around — but the assertion
was written against the phrasing instead of against the fact, and so the test defended the defect.
The general form, for whoever writes the next one: **assert that the copy names the control, by
reading the control's own label; never assert that it contains a particular word.** A phrase pinned
in a test is a phrase nobody can fix.

#### Spelling

The owner named "favorites", not "favourites". This change spells it American in the two files it
owns (`TreeProfileModel.swift` and the new `FavoriteRoundTripTests.swift`) and in the new
user-facing sentence, and touches nothing else: the codebase-wide sweep is task #140 and must run
alone. `MapMembership.favourites` is deliberately left as it is — a concurrent branch is renaming
it, and two branches renaming one case is how a merge eats a fix.
