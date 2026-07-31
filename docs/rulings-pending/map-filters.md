### R23 — the map's filter is a conjunction, the species dimension *is* the legend, and the year control states its own blind spot

**Ticket #116.** The owner asked screen 01 for four narrowings, in stated order of importance: **Yours,
Favourites, species, year.** Design was delegated. This is what was decided and why, including the two
things that were deliberately not built.

---

#### 1 · The row is a conjunction, and `All` stops being a chip

SCREENS.md 01 §12 draws `All / In bloom / Needs care`, "single-select with `All` default". The four
new narrowings do not fit that shape, because **they are not alternatives to one another**. "My trees"
and "planted in the 2010s" are a question a reader can sensibly ask at once, and single-select would
answer the second by silently discarding the first — a control that undoes your last instruction when
you give it a new one.

So `MapFilter` is a struct of independent dimensions, all ANDed. Consequences that follow and are not
negotiable:

- **`All` is gone as a chip.** A chip meaning "no filter" has a selected state indistinguishable from
  the resting state of the row it sits in, and it cost a slot `Yours` needed. The un-narrowed map is
  now the row with nothing on, which is what `All` selected anyway.
- **Every chip is a toggle**, including the membership pair. A conjunction with no way to remove one
  term is a conjunction you can only escape wholesale.
- **A `Clear filters` chip appears only when something is on**, and it is also the button on the empty
  notice. Two ways out, both labelled.
- **`Needs care` and `In bloom` keep their places** inside the conjunction. They are the mock's own and
  they still mean what they meant. `In bloom` still matches nothing, because every `seasonal` in the
  shipped seed is `{}` and inventing bloom months is what BUILD-PLAN §15 forbids — that was already
  true and this ruling does not change it.

`membership` is single-select *within itself*: `Yours ∩ Favourites` is a set so small and so
unmotivated that offering it would be a control nobody wants. Tapping the other one swaps.

#### 2 · The species filter is the legend, made tappable — there is no species chip

This is the ruling's real content. The owner attached two constraints to the species dimension: the
filter and the legend "must agree with each other", and they "must not fight for the same screen
space" — the legend having covered the map once already (#96).

A species chip beside the legend would have been a second control naming the same four species in the
same strip of chrome: both constraints broken at once, and the agreement between them would have been
something to *maintain* rather than something true.

**The strongest available guarantee that two controls agree is that they are one control.** The legend
already names the ≤4 coloured species, already sits in the chrome, already costs the space it costs.
Tapping an entry narrows the map to that species; tapping it again clears; the selected entry takes the
filter row's own selected fill so the state is said in the language the chips beside it use. Zero new
screen space, and the two surfaces cannot disagree because there is one of them.

A species outside the four is reached the way it always was — typed into C20 — and `MapModel.speciesIDs`
**intersects** the two rather than letting either win. Typing "plane" and then tapping the London Plane
legend chip leaves London Planes; neither control silently undoes the other.

#### 3 · Yours and Favourites are id sets, not predicates, and they suspend A1

What this device has visited, photographed, checked in on, measured or added lives in `main`; the seed
knows none of it and no `WHERE` clause over `trees` could. So the set is resolved first
(`CypressAPI.mapMembership(_:)`, one read per press of the chip, not per pan) and rides on the viewport
the way `speciesIDs` already does — which also means a changed membership is a *different viewport* and
the existing fetch debounce sees it.

Three rules fall out and all three are load-bearing:

- **`[]` means "narrowed to nothing", never "not narrowed".** A reader with no favourites who taps
  `Favourites` has asked a question, and the whole city is not its answer. `nil` is the un-narrowed
  case. Collapsing the two anywhere between `MapModel` and the SQL shows every tree in San Francisco as
  though it were theirs.
- **No marker grid.** The 44 pt cell exists to bound an answer that grows with the viewport's area. A
  membership set does not grow — it is bounded by what one person tapped. Gridding it would thin a set
  that fits on screen twice over and make the map say "showing 12 of 31" about an answer it could have
  drawn whole.
- **A1's clustering is suspended, and only here.** Badges bound an unbounded answer; there is nothing
  to bound. Clustering would answer "where are my trees?" with a number the reader has to zoom into
  four times. This is a deliberate, argued deviation and it is narrow: a *year* narrowing still
  clusters, because it can still match 37,962 trees.

`Yours` unions the four contribution tables **plus `community_trees`** — a tree you added is the most
emphatically yours there is, and it is in none of the four. That arm carries no owner clause because
the table carries no owner columns, which is correct today (no sync brings anybody else's rows down)
and is flagged in the code as the thing that must change on the same day those columns arrive.

#### 4 · The year control is a decade, and it says out loud what it cannot judge

**Counted before it was designed, which was the instruction.** Against the shipped seed:
**145,837 trees, 37,962 carrying `planted_year` — 26.03 %.** Among the 133,424 living ones it is
28,725, or **21.5 %**. Distribution of the dated rows: pre-1990 7,742 · 1990s 8,746 · 2000s 10,134 ·
2010s 8,493 · 2020s 2,847.

Two decisions follow.

**Decades, not years.** The seed spans 1955–2026. Seventy-two options holding a citywide mean of 527
trees each is a control whose every setting is invisible in a viewport. Five buckets, sized off the
real distribution; the first is open-ended because 7,742 rows spread over 35 years do not split.

**The control states its blind spot every time it is on.** Roughly three trees in four are set aside
*before* the filter judges anything. Silence would make their absence read as an answer — "there are no
2010s trees here" — when the truth is "the city did not record when most of these were planted". Those
are different claims about the same empty patch of map and only the second one is ours to make. So
`MapYearFilterCopy.setAside` renders whenever a decade is chosen:

> About 3 in 4 trees have no recorded planting date—none of them can appear under a year.

**Deliberately not built: a per-viewport count of the undated.** "214 more trees here have no date"
would be the better sentence. Getting it honestly costs a **second full fetch of the same box with the
year predicate removed** — the map's hot path, doubled, on every pan while the chip is on — to produce
a caveat that does not change in kind as the reader moves. The proportion is a fact about the inventory
the map is drawn from, true on every screenful, and `MapFilterTests` pins it against the shipped seed
so a re-ingest that moved coverage fails the build rather than leaving the sentence lying. If somebody
later finds a way to get the count for free, take it; do not buy it with a second fetch.

#### 5 · The number over the map, and the two rules it sits between

The result line (`31 trees`) exists because a filtered map that says nothing about its own result is
asking the reader to count pins.

**D1.** The owner's brief draws the line precisely — a neutral count as a *filter result* is fine, a
count that reads as a personal total is not. The difference is what the number is *of*. `31 trees` is a
fact about the viewport and it changes when the reader pans, which is what makes it not a score.
`You have visited 31 trees` would be stable, about the person, and forbidden. So the noun is always
**trees**, the sentence never takes a second person, and there is no phrasing available in
`MapFilterCopy` that could say otherwise — a test asserts the absence of "your", "you have", "visited",
"contributed" and "total" across every value the line can take.

**E38.** The line reads `content`, never `pins`. The grid thins, so the drawn array can be a spatial
sample; `PinAnswer.matchesInView` is non-nil exactly when that happened, and the two cases render in
different words (`1458 trees—showing 151`). A page is not a total.

**And the line yields when the notice is already speaking.** Found by running the app rather than by
reading it: a `0 trees` pill sat in the chrome while `No trees of yours here` sat in the card below —
the same fact twice, weaker phrasing on top. The count now draws nothing when the map is empty.

#### 6 · The empty state (E126)

A filtered map with no matches says why, and how to leave. Both halves, and the second is the one that
gets skipped. The notice reuses `MapLocationNotice` — same slot, same card, same trailing button, whose
label was hard-coded to `Settings` and is now a parameter.

`Yours` and `Favourites` get **two** different reasons, because "none here" and "none anywhere" are
different facts and only one of them is fixed by panning. Telling somebody who has never hearted a tree
to "zoom out to look further" is advice to go hunting for something that does not exist — the dead end
D16 (b) names.

---

#### Deliberately not decided here

- **Whether the chrome is now too tall.** With a filter on and a legend showing, screen 01 carries a
  search bar, two wrapped chip rows, a result line and up to two legend rows. Each row earns its place
  and the legend rows are not new, but this was looked at on the running app and it is dense. The
  obvious next move — merging the legend chips into the filter row, now that they are both filters — was
  not made, because it would take the legend's job as a *key* (explaining pin colour when nothing is
  filtered) and fold it into a control row, and that is a change to #96's surface rather than to this
  one. Whoever takes it should measure the saved row against that loss.
- **Whether `In bloom` should survive.** It cannot match a tree in the shipped seed, and now that an
  empty result costs a notice card explaining itself, a chip guaranteed to produce one is closer to a
  dead end than it was when it merely drew nothing. Left alone because it is the mock's and because the
  curated species pipeline is what fixes it, not this ticket.
- **Combining two memberships.** `Yours ∩ Favourites` is refused above on the grounds that nobody wants
  it. That is an assertion about readers, not a measurement.
