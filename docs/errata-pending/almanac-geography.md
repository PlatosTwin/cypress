# E182 — A city with no polygons had no almanac, and the screen did not say so

Task #138. The ruling behind the geography half is **RULINGS R29**; this entry is what was built,
what was measured, and what was found and not fixed. `AppSchema` is **untouched — v14 was not
taken.** The seed was **not rebuilt**: every change here is app code and travels with the branch.

Three things landed, and they are separable:

1. **E182 proper** — a finished read that resolves no area now says so. It used to draw the *loading
   screen*, pixel for pixel.
2. **R29's fallback** — San Jose's 52,788 rows are visible to screen 12 and to the coverage panel.
3. **The owner's report** — *"Clicking on newest neighbors on neighborhood almanac should show them
   on the map."*

---

## 1 · The screen that could not tell you it had nothing to tell you

`AlmanacScreen` had three arms: the location prompt, the blocks, and E126's failure sentence. A read
that *succeeded* and resolved no area fell through all three. What drew was `ScreenHeader` with no
pill, `Spacer`, and the footnote — **and that is byte-for-byte the screen a reader sees while the
read is still in flight**, because `presentation == nil` during `.loading` produces the same three
elements.

This is E126's defect on a cause E126 did not have. E126 fixed `.failed` looking like empty; the
state nobody had a cause for in April was "the inventory does not reach here", and hours after San
Jose landed every reader in that city was in it. E126's own words about this screen — *"the last
place to conflate them"* — apply.

What it draws now:

> **No inventory reaches here yet.**
> The almanac is built from city tree inventories, and none of the ones on this phone covers where
> you are. It fills in as more cities join the record.

**No retry button, deliberately.** E126's failure arm has one because that read really can succeed
the second time; this read will return the same answer from the same file forever, and a control
that cannot change the outcome is worse than no control. The second sentence is D16(b) applied — an
honest degraded state that says only what is missing reads as a dead end, so it says which way the
door opens.

This half was the one the ticket said had to land whatever was decided about geography, and it is
still reachable after R29: every coordinate outside two cities is in it.

## 2 · What San Jose gets (RULINGS R29)

`AlmanacQueries` took a `neighborhoodID: Int` and wrote `WHERE t.neighborhood_id = :neighborhood` in
six reads. It now takes an `AlmanacScope`, which renders that identical predicate for a polygon and a
bounding box narrowed by a squared-distance test for the fallback. `LocalAPI.almanac` resolves the
polygon first, then the radius, then nothing.

Measured on the shipped seed, standing at 37.3352, −121.8895 (South First Street, the block E176
photographed):

| | downtown San Jose, r = 1,200 m | Outer Richmond (polygon) | Noe Valley (polygon) |
|---|---:|---:|---:|
| records in the area | **6,963** | 6,216 | 6,361 |
| standing trees | 5,963 | — | — |
| distinct species | **167** | — | — |
| vacant planting sites | 1,000 | — | — |
| young trees, no visits | **4** | — | — |

So four of screen 12's five blocks have something behind them. The bloom row does not and cannot on
a fresh install — it needs a contribution and no seeded tree carries one (A9). **The coverage panel,
which D1 makes the app's only directed ask, now reaches San Jose**, with four trees and a walking
sentence that is true by construction (R29 sets the fallback radius to `AlmanacMetrics.walkRadiusM`).

Two things about San Jose's data that the screen states honestly rather than papers over:

- **222 of 52,788 San Jose rows carry a planting date**, against 37,963 of 145,837 in San Francisco.
  Nine of them are inside the downtown circle, so `The elder` reads *"in the city record since
  2021"*. That is the row's specified claim being precisely true — "in the city record since" is not
  "planted in", and E44's note on that phrasing is why it can be printed at all.
- **Five San Jose rows were planted in spring 2026** across the whole city, so `Newest neighbors`
  draws where they fall and not elsewhere.

## 3 · The third counted row (the owner's report)

`Newest neighbors` counted trees, named two species, and had **no destination of any kind** — not
wired to the wrong screen, simply not tappable. That is E129's defect and E144's, surviving on the
one row neither entry happened to touch.

Fixed the way both of those were fixed, with the same type and the same screen: `RecentPlanting`
gains `nearest: [TreePin]` from a second read of the same predicate, the row carries a
`PinSet(subject: .newestNeighbors(sentence:))`, and `AlmanacView` routes it through the existing
`onShowGroup`. No third route onto the map.

`.newestNeighbors` carries its sentence rather than re-deriving it, for `.oneRecord`'s stated
reason: `AlmanacCopy.newestSubtitle` is assembled from a species list the destination does not hold,
and re-deriving it would be a second read that can disagree with the row the reader pressed.

**Why the existing sweep did not catch it.** `PinSetDestinationTests` has a test named *"no counted
row on screen 12 resolves to a single record"* whose body enumerates two of the three counted rows.
A sweep that names itself after a universal and then lists its members is only as good as the list;
this one was written when §2's rows had no destinations at all and was never revisited. It
enumerates three now, and asks `seasonRows` for the row by `kind` rather than by index so a fourth
cannot slip in behind it.

## 4 · Verification

### The test that can only pass on the fixed app

Every value-level assertion about §1 passes on the broken app. `AlmanacPresentation(almanac:
.empty)` was always correct — `neighborhoodName` was already nil, `isEmpty` was already true — and a
test asserting the copy string exists would pass too. What can only pass on the fixed app is a
comparison of the two *pictures*, exactly as E126 established: screen 12 after a read that finished
and resolved no area, against screen 12 while the read is still in flight.

`AlmanacGeographyTests.outOfRangeDrawsSomethingLoadingDoesNot` renders both through a
`UIHostingController` in an off-screen window, with a control render first proving the harness is
byte-stable. The loading side is a `CypressAPI` whose `almanac` suspends on a
`withCheckedContinuation` that is never resumed, rather than sleeping — a timer would be racing the
harness's eight 120 ms passes, and a "loading" screen that had quietly finished loading is the one
thing this comparison must not capture.

**Mutation proof.** With the `outOfRange` arm deleted from `AlmanacScreen` — reverting the branch to
the three it had:

```
✘ Test "an almanac that resolved no area does not look like one that is still loading"
  recorded an issue at AlmanacGeographyTests.swift:299:9: Expectation failed: differs
↳ an almanac that finished and found no inventory draws the loading screen (E182):
  105083 bytes against 105083
✘ Test run with 8 tests in 1 suite failed after 3.364 seconds with 1 issue.
```

### The rest

- **San Francisco did not move**, which is the whole safety argument for the hybrid.
  `namedAreaIsUnchanged` reads Sunset/Parkside through the new scope and compares against the pinned
  corpus figures: R5's species count, R5's denominator, E115's site count. A denominator that
  quietly moves is exactly the failure R5 exists to prevent, and it would move silently.
- `sanJoseResolvesTheFallback` checks its own precondition first — that no San Jose row carries a
  `neighborhood_id` — so that if a San Jose polygon layer ever lands, the suite fails loudly instead
  of going on passing while measuring the polygon path.
- `outsideTheRecordResolvesNothing` puts a fix in downtown Sacramento and asserts the almanac
  resolves *no area*, not a radius over an empty circle.

### On screen, in both cities

Built, installed and launched on iPhone 16 Pro Max, driven by hand at three fixes. The privacy
grant was set with `simctl privacy … grant location` and each fix with `simctl location … set`
followed by a terminate and relaunch, because `AlmanacView` builds its model from the coordinate it
is handed on mount.

**Downtown San Jose (37.3352, −121.8895).** The screen a reader in the second city now gets:

| | |
|---|---|
| pill | `Within a 15-minute walk` |
| under the header | *No neighborhood boundaries are on file for where you are, so this almanac is drawn around you instead. It will name a neighborhood once this city's boundaries join the record.* |
| The elder | `MUSASHINO SAWLEAF ZELKOVA · in the city record since 2021` |
| Newest neighbors | `1 tree planted this spring` |
| Who lives here | `167 species` — Platanus acerifolia 33%, California Fan Palm 6%, Mexican Fan Palm 5%, Everyone else 56% |
| Where a tree could go | `1,000 empty planting sites` |
| Where eyes are needed | `4 young trees with no visits since planting` · *All four are within a 15-minute walk.* · `Walk the four` |

Every figure matches what was measured against the file beforehand, including the walking sentence
rendering rather than being withheld.

**`Newest neighbors`, tapped.** It opens the `PinSet` map: title `Newest neighbors`, subject
`1 tree planted this spring`, the E38 line `It is on this map.`, the pill carried through as
`Within a 15-minute walk`, and the pin drawn on N 12th St. That is the owner's report closed.

**Outer Sunset (37.7533, −122.4934).** Unchanged, which is the point: pill `Sunset/Parkside`, **no
explanatory line at all**, `The elder — Ornamental Cherry · in the city record since 1969`,
`Who lives here · 201 species`, `1,436 empty planting sites`, `9 young trees with no visits since
planting` / `Walk the nine`. A reader in San Francisco cannot tell this pass happened.

**Downtown Sacramento (38.5816, −121.4944).** Header, `No inventory reaches here yet.`, the two-line
body, and the footnote. Before this pass that screen was the header and the footnote with an empty
column between them — which is what a reader sees while the read is still running.

## 5 · Things checked rather than assumed

**Cold-start thresholds (DECISIONS §2.6).** The ticket's warning is that a smaller area crosses a
threshold less often and can silently empty a panel that was populating. Two findings:

- **San Francisco cannot regress, structurally.** The polygon path is preferred wherever a polygon
  exists, so every SF area is the area it always was. There is no coordinate in San Francisco whose
  almanac changes shape.
- The only person-count on screen 12 is `BloomFirst.observerCount`, A8's floor of three. It is
  computed **per tree**, not per area, so area size cannot move it. A8's "caretakers" surface itself
  is not on this screen.
- The floor that *could* be crossed by a smaller area is §4's `coverageRowLimit` of 200 — above it
  the card prints no number and disappears (E38). The fallback area is deliberately sized to sit
  inside the SF polygon distribution (R29), and downtown San Jose returns 4.

**Golden Gate Park and ticket #106.** The park spans several polygons, as the ticket said: trees in
the GGP bounding box key to `Outer Richmond` (1,455), `Inner Sunset` (395), `Inner Richmond` (357),
`Golden Gate Park` (70), `Lone Mountain/USF` (47) and `Sunset/Parkside` (27) — `Golden Gate Park` is
itself one of the 41 Analysis Neighborhoods.

**Park rows will key correctly, and the reason is mechanical rather than lucky.** `build_seed.py`
stamps `neighborhood_id` by **point-in-polygon over every record from every source**, not by copying
a DataSF column, so a park inventory arriving through a different adapter gets the same treatment.
Only 2 of 145,837 SF rows fall outside all 41 polygons. What #106 should know: a park tree belongs
to the polygon it stands in, so *"the park's oldest tree"* is a sentence screen 12 will never be able
to say — the elder of Golden Gate Park is the elder of whichever sixth of it you are standing in.

**Other SF-shaped assumptions in the almanac, found and reported.**

- `AlmanacWindow.springMonths = 3...5` is northern-hemisphere. Correct for every US city and wrong
  the first time this database crosses the equator. Not fixed; nothing in scope crosses it.
- **The elder row in San Jose reads `MUSASHINO SAWLEAF ZELKOVA`**, in capitals, where San Francisco
  reads `Ornamental Cherry`. Chased rather than shrugged at: San Jose publishes no common name
  (E176), so `COALESCE(s.common_name, s.scientific_name)` falls through to the scientific name, and
  this row's `NAMESCIENTIFIC` holds an all-caps *common* name rather than a binomial. It is **one
  species and one tree** in the whole file — measured, not assumed — so it is a source-data curiosity
  rather than a pattern; it is worth recording only because that single row happens to be the elder
  of downtown San Jose and therefore sits on the screen's flagship line. Not fixed here: correcting a
  species row is the species catalogue's business, not screen 12's. (215 species carry no common name
  at all and render their scientific name, which is `SpeciesQueries`' documented E51 fallback and
  predates the second city.)
- `AlmanacCopy.street(from:)` drops a leading house number. Checked against San Jose's addresses
  (`393 E ST JOHN ST`) and it works. The all-caps casing it leaves behind is **not** an SF/SJ
  difference: SF's own rows include `1726 ALEMANY BLVD` beside `600 Montgomery St`, so this is a
  pre-existing property of the record rather than something the second city introduced.
- **`AlmanacCopy.locationPromptTitle` read `See your neighbourhood`** — the one user-visible British
  spelling on this screen, on a screen SCREENS.md has always called `Neighborhood almanac`. Now
  `See your neighborhood`. The codebase-wide sweep is a separate ticket and was deliberately not
  started; the geography test asserts the strings *this* screen renders carry no British forms.

**Two other neighborhood-scoped surfaces have the identical hole, and are not fixed here.**

- `GroveQueries.residentNeighborhood` (screen 08) joins `seed.neighborhoods` through the trees a
  contributor has touched. Every San Jose contribution lands on a row with `neighborhood_id IS NULL`,
  so the join drops it and the resident neighborhood is nil forever in that city.
- `LocalAPI.speciesGuide`'s `nearYou` (screen 07's *"61 of these in Sunset/Parkside"*) resolves
  through the same `resolveNeighborhood`, so it is nil for every San Jose reader and the card simply
  does not draw.

Neither renders anything false — both are honest absences — and both are a different screen's
ticket. R29 is a ruling made on screen 12's behalf and has no standing to redesign them, but the
`AlmanacScope` it introduced is the shape either would use.

## 6 · What was not done

- **San Jose's polygons were not fetched**, though the ticket authorized it. R29 says why: under D16
  they would be an optimization for one city rather than the mechanism. **Zero network requests were
  made in this task**, from any source. Nothing was downloaded, nothing was cached, and
  `Fixtures/raw/` is untouched.
- **The seed was not rebuilt.** `Cypress/Resources/cypress-seed.sqlite` and
  `Fixtures/seed/cypress-seed.sqlite` are the file that was already on this machine — 108,007,424
  bytes, `sf|145837` and `us-ca-sj|52788`. No seed needs to be copied at merge.
- **`AppSchema` v14 was not taken.** Nothing here is persisted; the area is resolved per read.
- Screen 07's and screen 08's holes above.
- E176's four SF-hardcoded copy surfaces on the tree profile (`SF city inventory`, `SF #167879`,
  `WHAT SAN FRANCISCO HAS ON FILE`) are unchanged. They are a different screen and E176 already
  filed them.
