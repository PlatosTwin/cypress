### E184 — the favorite a refresh put back, and the note that sent the reader to a heart nobody drew (task #139)

Two reports from the project owner, walking the running app on 2026-07-31:

1. *"Clicking Favorite on a tree page **now** seems to do nothing."*
2. *"Favorites note says there is a heart icon to heart a tree, but that's false."*

They look like two bugs. The first is one bug and one non-bug, and separating them took the
running app rather than the code.

---

#### What the running app actually showed

Reproduced first, read second, on iPhone 16 Pro against a clean install of `main` at `bbf8f0b` with
the two-city seed attached, tapping the control and then opening the container's `cypress.sqlite`
directly.

`SIMCTL_CHILD_CYPRESS_SCREEN=treeProfile`, one tap on `Favorite`, then:

```
$ sqlite3 …/Library/Application Support/Cypress/cypress.sqlite \
    "select id, user_id, device_id, tree_uuid, deleted_at from favorites;"
B8B3562E-…|<null>|5EB227BD-4C96-4C02-8367-343FC0A6F2DF|86E142E2-4C3E-5F42-B32C-4AE84589E370|
$ sqlite3 … "select kind, state, fail_count, last_error_code from outbox;"
favorite_toggle|done|0|
```

The row is there, `deleted_at` is null, the outbox item is `done`, and the cell drew its selected
appearance. A second tap tombstoned it (`deleted_at` set, a second `client_uuid`, a second outbox
row) and the cell went back to idle. The same held from the other live entrance — the Grove row —
under a signed-out device and again with `app_state.current_user_id` set, which is the `.user` arm
of `FavoriteOwner` and E89's ground. **Six taps, six correct rows.**

So the plain sentence "the tap stores nothing" is false, and this entry says so on the record: the
tombstone toggle writes, the replay guard behaves, and `grove()` reads both ownership arms back.
Suspects 1 and 3 in the ticket are cleared by observation, not by reading.

#### The defect that is real: a refresh answers for a tap it never saw

`TreeProfileModel.load()` ended with

```swift
isFavorite = await storedFavorite()
```

and `load()` is not only the first-appearance read. `TreeProfileView` calls `reload()` when the
screen comes back to the front (`onAppear` after the first) and again when a sheet closes over it
(`onChange(of: router?.sheet == nil)` — the Care sheet, the Share sheet, the camera cover).

That assignment was ordered against nothing. The *taps* were ordered against each other by the
`writes` task chain, and the comment on `writes` is explicit about why: "run concurrently, two
writes and two re-reads can interleave and leave the cell showing whichever read happened to land
last." The reads that are not taps were left out of that sentence. A refresh takes its snapshot,
gives up the main actor, and assigns whatever it read whenever it gets the actor back — so a
refresh that started a moment before the finger arrived lands *after* the tap and puts the heart
back off, over a favorite the store is holding.

The user-visible result is exactly the owner's words. The row is in the database and the control
says off. On a control whose state is read rather than remembered (RULINGS R2), that is the only
shape "I tapped Favorite and nothing happened" can take.

The sequence is one a person performs without trying: close the Care or Share sheet, then tap
`Favorite` while `treeProfile()` is still walking a 108 MB seed.

**The fix.** Every favorite read is stamped with the tap count it was taken under and dropped if
that count has moved. The tap that overtook the read does its own re-read at the end of `write()`,
so the store still gets the last word — one read later, from a snapshot that includes the tap. The
control keeps answering the finger immediately, which chaining the reads onto `writes` would have
cost.

#### Why the green suite could not have caught it

Both existing suites are green and both are half a test.

- `FavoriteTests` proves the store — tombstone, replay guard, both ownership arms, the sign-in
  merge. No screen is involved.
- `FavoriteToggleTests` proves the screen against a **stub**. Its `Records` double answers `grove()`
  out of a `Set<UUID>` the test itself writes to, so the model's read-back is checked against a box
  rather than against `LocalAPI.grove()`. Its one real-store test, `eachTapGetsItsOwnKey`, drives
  `ProfileFavoriteWriter` **without a `TreeProfileModel`** and against a tree it makes with
  `addTree` — a `community_trees` row, which is the one arm of `requireTree` that no tree the owner
  can tap goes down.

So the write is covered, the read is covered, and the seam between them is not. Neither suite has
any notion of a second reader of `isFavorite`, which is where the defect lives.

`FavoriteRoundTripTests` is new and covers the seam: the model and the composition root's writer
joined, against a real store with the real seed attached and a real seed tree resolved the way
`DebugDeepLink` resolves one.

#### The regression test, failing against the code as found

Run against unmodified `main` — this is the original defect, not a mutant:

```
✘ Test "a refresh already in flight does not put the heart back after a tap" recorded an issue at
  FavoriteRoundTripTests.swift:177:9: Expectation failed:
  (model → Cypress.TreeProfileModel).isFavorite → false
✘ Suite "Screen 03 · the favorite round trip, real store (#139)" failed after 0.258 seconds with 1 issue.
✘ Test run with 4 tests in 1 suite failed after 0.258 seconds with 1 issue.
```

Line 177 is the assertion *after* the stalled refresh returns. The assertion before it — "the tap
itself did not take" — passed, which is the point: the tap landed, and the refresh undid it. The
other three tests in the suite passed against the broken code too, which is a fair measure of how
narrow the hole was.

The double stalls `grove()` **after** it has taken its snapshot. Stalling it before would return the
fresh answer and prove nothing.

#### The copy: there is no heart, and there never was

`MapFilterCopy.emptyMessage` told a reader with no favorites: *"You have not hearted a tree yet. Tap
the heart on any tree's page and it will appear here."*

There is no heart anywhere in this app:

- `SCREENS.md` §2 C8 — "**NOT SPECIFIED:** icons for these four actions — the spec shows text only."
- `SCREENS.md` §5 gap 3 — "Icons for `Favorite` / `Care` / `Share` / `Report` (C8) — text only."
- `SCREENS.md` 03 §6 draws the row verbatim as `Favorite` · `Care` · `Share` · `Report`.
- `mocks/cypress-mocks.html` contains the string "heart" zero times.
- RULINGS R2 retracts its own first draft on this exact point: "**C8 has no glyph.** … there was
  nothing to fill."

So this was not an affordance that was replaced. It is an affordance that was never drawn, named in
the one place a reader could act on it — an empty state whose entire job is to route them to the
control. The copy now names the control as drawn. **No mock is overruled and `SCREENS.md` needs no
departure note**, which is the opposite of the #137 case: there the screen departed from the mock
and the mock got a note; here the copy had departed from the mock and the copy came back.

`MapFilterTests.emptySetAndEmptyViewportDiffer` asserted `noneAnywhere.lowercased().contains("hearted")`
and so held the defect in place. It meant to assert that the never-favorited state says what to do;
it asserted that it says it in a word describing a control nobody drew. That is worth its own line
in this file: **a copy test that pins a phrase pins whatever the phrase was wrong about.** It now
asks for `QuadActionRow.Action.favorite.label`, and a second test sweeps every sentence the type can
produce for the word "heart".

Mutation proof for the copy tests — the original sentence restored:

```
✘ Test "an empty set and an empty viewport give different reasons" recorded an issue at
  MapFilterTests.swift:444:9: Expectation failed:
  (noneAnywhere → "You have not hearted a tree yet. Tap the heart on any tree's page and it will
  appear here.").contains(QuadActionRow.Action.favorite.label → "Favorite")
✘ Test "no map-filter sentence sends the reader to an affordance the app does not draw" recorded an
  issue at MapFilterTests.swift:472:17: Expectation failed:
  !((sentence.lowercased() → "you have not hearted a tree yet. tap the heart on any tree's page and
  it will appear here.").contains("heart") → true)
✘ Test run with 17 tests in 1 suite failed after 0.446 seconds with 2 issues.
```

#### What this entry does not claim

It does not claim the ordering defect is what the owner hit. It is the only mechanism in this
codebase by which a favorite that **is** in the database displays as off, and it matches the report
word for word — but the report is one sentence and the interleaving is a race, and six deliberate
taps on the running app did not produce it. What is established is: the write path is sound and was
proved so on device; the read-back had a real ordering hole on the exact path the report names; and
the second report was true as written.

**When it broke, as precisely as the history supports it.** Nothing in `RootView`'s `onFavorite`
wiring, `FavoriteOutboxWriter`, `ContributionStore.applyFavoriteToggle`, `groveTreeIDs` or
`favoriteTreeIDs` has changed since R2 landed. The dates that matter are these two:

| | | |
|---|---|---|
| `8bb7c0d` | **2026-07-22** | R2/E112 — the favorite gets an on-state, and `load()` starts assigning `isFavorite` from a read |
| `70011ed` | **2026-07-25** | E127 — `TreeProfileView` gains the `onAppear` re-read *and* the `onChange(of: router?.sheet == nil)` re-read |

Before 2026-07-25 there was one reader of `isFavorite` and one writer, and ordering the writes
against each other was enough. E127 added a second reader on a path nothing chained, three days
later, for an unrelated and correct reason — a profile that did not know about the measurement just
taken on screen 16. Neither change is wrong on its own. The hole is the pair, and no test in this
repository had both halves in scope, which is precisely how it survived a green suite for six days
and reached the owner's thumb.
