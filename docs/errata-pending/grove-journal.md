### My Grove and the Journal looked alike, and for one pair of them they were the same list

The project owner, using the app: *"What's the diff between Trees and Journal? They look almost
identical. We need either some differentiator or some small explanatory note of what's on each page,
and a theory about why to keep both."*

There were **three** surfaces, not two, and the duplicate was not the one named in the complaint:

| surface | what one row is | a tree you visited twenty times |
|---|---|---|
| My Grove ▸ `Trees` (`GroveTreesPresentation`, from `grove()`) | one tree you have a relationship with | **1 row** |
| Journal tab ▸ `Yours` (`JournalPresentation`, from `journal(cursor:limit:)`) | one thing you did | 20 rows |
| My Grove ▸ `Journal` pill | **the same list as the Journal tab** — same read, same rows, same view | 20 rows |

So the genuine duplicate was the pill against the tab. Trees against Journal is two different
questions that had been given one drawing.

---

**The pill is cut, and E135's argument for it is answered rather than overturned.**

`GroveTreesTests.theJournalPillIsOneListNotACopy` was placed in the suite specifically so that a
round proposing this would have to answer it first. Its argument: an earlier round wanted to cut the
pill because "two copies of a person's own record is two things that must agree forever", and that
objection was answered *structurally* — one derivation (`JournalPresentation`), one model and one
view (`JournalSection`), mounted in both places, so there is no second implementation to drift.

That argument is correct and nothing found here contradicts it. **It establishes that the two
surfaces can never disagree. It does not establish that a reader needs two doors into one room.**
The owner hit exactly the second thing: he spent time working out why two things looked the same,
and for the pill and the tab he was not mistaken — they *were* the same list. Drift-safety is not
comprehensibility.

The cost the earlier round weighed was a control the design draws being left unbuilt (SCREENS.md 08
§2 draws three pills). The cost since observed is a person unable to tell two of his own screens
apart. The second is larger, and it is evidence the earlier round did not have. **This is a
different argument on different grounds, not the old one becoming right.**

Deviation recorded: **screen 08 §2's three pills ship as two**, `Trees` and `Species`. The row is
still 08's own geometry (E46) with one `flex:1` cell fewer.

`theJournalPillIsOneListNotACopy` is replaced by `theJournalHasOneDoorNotTwo` — the same forcing
function pointed at the failure that happened. A second entrance to the journal has to break a test
to exist. `ScreenEntranceTests.theSurfacesThatWereNotRoutes` asserted
`GroveTab.journal.hasDestination` as its proof that `journal()` had a caller; a pill that no longer
exists must not leave a test asserting it leads somewhere, so it asserts what is actually required —
the journal has a caller, and exactly one.

---

**The survivors were then made to look like what they are.** They were identical *today* only
because the app is new and most trees carry one event; they diverge permanently the first time
somebody visits one tree twice. Both drew title = tree name, subtitle = grey text ending in a date.

- **Trees is a set of nouns.** The date is gone from the row entirely; recency moved out of the text
  and into the ordering, which is `last_visited DESC NULLS LAST` and was always the store's. In its
  place the row carries the shape of the relationship: `Favorite · 3 visits · 1 measurement`. That is
  the one fact the journal cannot state without printing twenty rows.
- **The Journal is a stream of verbs.** The date leads: one `micro.label` section header per day —
  §1.3's own treatment for "section headers inside screens" — with that day's acts under it. Row
  titles are verb-first (`Visited Grandmother Cypress`), so the act is the subject rather than a
  clause in grey at 12.5 pt. The note is the only thing left on the second line.
- **One explanatory line under each header**, which is what was asked for, written as a pair:
  *"One line per tree, however many times you have been back."* against *"One line for each thing
  you did, newest first, under the day it happened."* Same length, same shape, opposite content.
  The tone model is `JournalCopy.emptyState`, which does its whole job in one breath.

Grouping is by **consecutive run, never by key**: the store orders by `captured_at DESC`, so a day's
rows are already contiguous and folding runs preserves the read's order exactly, while
`Dictionary(grouping:)` would impose an order of its own and `Show earlier` would begin inserting
rows into the middle of a list somebody is reading. It also merges a page boundary that falls inside
a day into the section already on screen instead of drawing the same date twice.

---

**The tally, against D1 and ARCHITECTURE §5.1.** §5.1 is blunt — "if you find yourself writing
`visitCount` into a user-visible string, stop" — and `3 visits` is literally that string. The
exception is not new: `DeviceContributions` already argued it for screen 15's `Keep your three
visits`, on three clauses. `GroveRecord` carries those three and adds two that a *list* needs:

1. **never public** — one phone, contributions in the common case attributed to nobody at all (D9),
   and no `CypressAPI` method that could return a second person's grove to sit beside it;
2. **never compared** — nothing sorts on it, nothing takes a maximum. The list's order is the
   store's, and `theTallyDoesNotSortTheList` is built so that a sort in either direction changes the
   answer;
3. **never a reward** — no badge, no threshold, no colour that changes. The row is drawn identically
   at one and at forty;
4. **never summed** — there is deliberately no `total` on the type and nothing anywhere produces a
   row about the grove rather than about a tree (`theTallyIsNeverATotal`);
5. **kinds, not one number** — `4 entries` is a single figure a person can rank their own trees by
   and want to raise; `3 visits · 1 measurement` says what *kind* of relationship it is, which is a
   thing to have rather than a thing to maximise. It is the more useful sentence besides: it tells
   you that you have never measured the tree you walk past every day.

`GroveQueries`' header says "nothing here counts contributions", and that stays true of that file —
it feeds the species ring, whose numerator is a count of *species*. The tally is a different question
with a different subject and lives in `ContributionStore.groveRecords`, next to the grove read it
belongs to.

**E38, pages are not totals.** `groveRecords` answers with `COUNT(*)` over the whole predicate and no
limit, so the engine proved the number — the same standing `deviceContributions` has. An
implementation that cannot prove it returns **nil**, and `GroveEntry.record` is optional for exactly
that: a nil draws no tally at all rather than `0 visits`, which would be a claim about a person's
history that an unproven read may not make. Both reads run inside one `queue.read`, so the rows and
their tallies come from one snapshot.

**And the distinction cost something to keep.** The first implementation wrote:

```swift
record: records[row.treeID] ?? .none
```

`records[key]` is `GroveRecord?`, so the contextual type of `.none` is `Optional<GroveRecord>` and
the leading dot resolved to `Optional.none` rather than `GroveRecord.none`. It compiled. Every
favourite nobody had visited came back as *"this read could not answer"* when the read had in fact
answered. **A leading-dot `.none` against an optional of a type that has its own `none` is a silent
type error**, and it was caught only by the test that goes through `LocalAPI` against a real store —
no test over the doubles could see it, because a double hands that field over directly.

And the honest limit of that, since a later round will otherwise over-trust the optional: **the two
states draw the same thing.** An unproven read prints no tally and a proved-empty record prints no
tally, so this bug had no visible consequence and no assertion about a *string* can tell the two
apart. The mutation sweep showed it — replacing `if let record` with `record ?? GroveRecord()` did
not fail a single test, because a record of four zeroes produces no clauses either. What the optional
buys is that the difference is representable and cannot be printed as `0 visits` by a later change;
what guards it is an assertion on the value (`aFavouriteWithNoContributionsIsEmptyNotUnknown`), never
on the drawing.

---

**Looked at, not only tested.** `CypressTests/GroveJournalShots.swift` draws both surfaces from one
contribution history and lays them out two columns wide, so the comparison is one image. The fixture
is the argument: one tree carries six records, one carries two, one is a favourite nobody has
visited — Trees draws three rows over the history the journal draws eight rows of. Five trees with
one event each would have photographed the two screens agreeing, which proves nothing.

Before, both columns are a white card, a green tile, a bold tree name and a grey line with a date in
it, under a My Grove that offers a `Journal` pill. After, they share no element of grammar.

The shot harness had to be talked down from 2,400 pt to 1,200: the contact sheet is
`rows × (cell + caption)` tall, so three rows of 2,400 asks `UIGraphicsImageRenderer` for a 21,930 px
canvas — past the ~8,192 px ceiling E145 records and, at that size, past what the host process
survives. It crashed the test runner before the number was picked. **E145's ceiling applies to the
sheet, not only to the capture**, which is not what that entry says and is where the next person will
meet it.

**Two things AX5 showed that the drawn size did not.** In the before shot the `Trees` row's title
truncates to `Grandmother…`; in the after shot it wraps to two lines. That is an observation off two
images and the cause was not chased — `IconTextRow`'s title still carries no `lineLimit` and no
`fixedSize` in either — so it is recorded rather than claimed as a fix, and the missing `fixedSize`
on that `Text` is a thing worth looking at on its own. Second: two pills have room for their labels
at AX5 where three were tight. Neither was the point of the change.

---

**One thing this round cost somebody else's tests, and it was not the code.** Two UI tests —
`AlmanacGroupTapTests.testWalkTheNineOpensAMapOfThemAll` and
`DeepLinkVoiceOverTests.testTheNudgeControlsActuallyMoveThePin` — failed on this branch and passed the
moment the simulator's fix was moved. They had been run against a streaming `simctl location` route
over the **Outer Sunset**, and E153's own skip message names the fix these tests want:
`37.78485,-122.4215`. A neighbourhood with no young unvisited trees in it has no §4 coverage CTA, so
the test failed on a *correctly* absent row — the state E153 was written to distinguish, one
neighbourhood further out than it had been asked about. The same two failed on pristine `main` under
the same conditions, which is how they were attributed.

So: **a red UI test on this project is a question about the simulator's fix before it is a question
about the diff**, and a *streamed* route is worse than a static fix here, because it is plausible,
persistent across runs, and invisible in the failure message.

**Open.** The `Trees` list still says nothing about *when* — deliberately, since that is the
journal's job — which means a tree seen yesterday and a tree seen two years ago read alike unless you
notice where they sit in the order. Ordering carries it today because the grove is short. If a grove
ever runs to a hundred trees, position stops being legible as recency and the question reopens; the
answer then is a section header ("this season" / "before that"), which is a structure, not a date on
a row, and not a duration since (a duration is one rendering away from a lapsed streak, D1).
