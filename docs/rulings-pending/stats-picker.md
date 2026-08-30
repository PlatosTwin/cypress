# Pending rulings — the Journal's neighborhood/city picker (`feat/stats-picker`)

Unnumbered, per CLAUDE.md; the orchestrator splices under the real next R-number at merge.

## Ratified by the owner, 2026-08-30

Recorded by the orchestrator from the owner's own window, on the PR #132 review. **These are no
longer proposals.** Each item's text below stands as ruled; where the review round changed how one is
implemented, the change is recorded under it and marked.

| item | status |
|---|---|
| **D1** — a non-local pick draws from the live inventories only | **RATIFIED as shipped** |
| **D2** — the mechanism is a sheet of chips | **RATIFIED as shipped**, with the presentation corrected (F2 below) |
| **D3** — the default states its own provenance, always | **RATIFIED as shipped**, and now three sentences rather than two (F1 below) |
| **D4** — a picked area drops the blocks that are about the reader | **RATIFIED as shipped** |
| **D5** — the honest coarse-fix state | **RATIFIED as shipped**, with each segment's bound corrected (F3 below) |
| **D6** — the City segment names its city from `dim_city` | **RATIFIED as shipped** |
| **D7** — a pick does not survive relaunch | **RATIFIED**: it resets, deliberately |

**Still open, and the only things on this page awaiting an answer:** the two wordings the review round
had to write — `AreaPickerCopy.resolvedFromFixRadius` (F1) and `AreaPickerCopy.qualified` (F4). Both
are marked **AWAITING RATIFICATION** where they appear.

---

**Everything below is a proposal for the owner's ratification, not a decision.** SCREENS.md carries
no mock for a picker on any screen, so the round is written under DECISIONS constraint 21's
delegated-authority pattern — the same footing R43 §3's affordance table and the City segment itself
stand on. Each item states what was built, and the alternative that was weighed and can be taken
instead without redesigning the round.

**What is already decided and is not up for ratification here:** the owner's 2026-08-28 backlog item
("In journal view, add ability to select a different neighborhood and get the stats for that
neighborhood (and ditto for City)"), and that this round supersedes R84 **D4** for the Journal.

---

## D1 — A non-local pick draws from the **live** inventories, and only those

**Built:** both lists come from the union R84 decision 1 already serves — the bundled seed plus every
downloaded pack currently attached. That is exactly the set the map draws and the set the Cities
screen calls installed, so what the picker offers is checkable by the reader against a screen they
have already seen.

**Why not the published catalog.** A city whose pack is not on the phone has no rows to aggregate.
Offering it would open a screen that can only say nothing — E182's state, reached deliberately.

**Alternative, if the owner wants it:** offer every city in the live `manifest-v2.json` and turn a
tap on an uninstalled one into a route to the Cities screen with that city's download queued. It is
a real product improvement and it is a different round: it puts a network fetch behind a Journal
segment that has never had one, and it needs its own answer for the offline case.

**Narrower alternative:** offer only the inventory the reader is standing in. This is the
conservative reading and it is what R84 D4 effectively said. It also fails the owner's ask — a
reader who downloaded Manhattan cannot read Manhattan without going there.

## D2 — The mechanism is a sheet of chips, and it introduces no new component

**Built:** C17 `BottomSheet(style: .standard)`, titled by C1 `ScreenHeader`, holding C4 `Chip`s in a
`CypressChipFlow` — `.filterSelected` for the live choice, `.filterIdle` for the rest. That is
screen 01's map-filter row, verbatim, and it already carries the `.isSelected` accessibility trait.
The affordance that opens it is a `SecondaryOutlineButton(.compact)` labelled `Change`, under the
header.

**Presented by the composition root, through `RootView`'s single `.fullScreenCover` keyed on
`AppRouter.sheet`** — the way screens 09, 10 and 15 are. **This is a correction (PR #132 review,
F2).** The first version drew the same card as a `ZStack` layer inside the segment's own content
slot, which sits between the C5 segmented control and the tab bar and therefore covered neither: the
review tapped `City` *through* the scrim, the segment switched, and the sheet vanished with no
dismissal and no `onClose`. VoiceOver's rotor still reached every card underneath. A cover is a
separate hosting context and closes all three at once.

The selection the sheet writes therefore lives on `AppRouter` (`journalArea` / `journalCity`), beside
`journalSegment` and for a related reason: a `Route` is `Hashable` and cannot carry a closure back
into a feature's `@State`. It is destroyed with the router on any inventory change, which is what
keeps D7 true.

**Why not a list with a checkmark:** a second selection idiom for the same job, and the checkmark
would have to be drawn as a shape (R57 forbids SF Symbols) — a new glyph for a control the app
already has.

### Two chips with one label (PR #132 review, F4) — **AWAITING RATIFICATION**

`InventoryUnionSQL` deliberately does not merge neighborhoods across arms — *"two cities may each
have a `Downtown`, and merging those would put San Jose's trees in a San Francisco neighborhood"* —
so under R84's union the picker can be handed two rows with one name and nothing to choose between.

**Proposed, and built:** qualify **only a name that actually collides**, in the app's own middle-dot
idiom — `Downtown · San Jose`. Qualifying unconditionally would print a city beside all 41 of San
Francisco's names when nobody is choosing between cities; qualifying nothing leaves two identical
chips. A record with no city name on file is left unqualified rather than given an empty suffix.

Today's bundle cannot reach it (41 distinct San Francisco names, and San Jose carries no polygons at
all). It becomes live the first time a downloaded pack carries a neighborhood set, which is the
configuration D1 exists to enable and which the five published NYC borough packs are one install
away from.

**Alternatives:** a per-city section in the sheet (more structure than a chip flow supports), or a
stated decision that the ambiguity is accepted.

**Alternative:** make the header pill itself the tap target, with a drawn caret. Tighter, and it
loses the sentence — see D3, which is the half of this round that answers the tester rather than the
owner.

**Not built, and offered as a possible amendment:** a `SearchBar` above the chips. 41 neighborhoods
is a scroll; a hundred would need search, and the component exists. Left out to keep the round's
surface small.

## D3 — The default states its own provenance, always

**Built:** one muted sentence under the header, in `areaNote`'s type and color, on both segments.

- resolved from the reader's fix **through a polygon**, i.e. the nearest inventoried tree —
  **"Chosen from the tree nearest you in the city record."**
- resolved from the reader's fix **through R29's radius fallback**, where no polygon covers them —
  **"Centered on where you are."** — **AWAITING RATIFICATION**
- picked by the reader, almanac — **"You're reading a place you're not in, so the section asking you
  to go and look is left out."**
- picked by the reader, City — **"You're reading a city you're not in, so the comparison with your
  own streets is left out."**

### The third sentence, and why it exists (PR #132 review, F1 — blocking)

The first version had two sentences and keyed them on `AreaResolution`, which answers *"did the
reader choose this"* — the question the picker asks — and not *"what chose it"*, which is the
question this line answers. The two coincide for a polygon and come apart for the fallback, where no
tree was consulted at all.

**It was not an edge.** All **52,788** San Jose rows carry `neighborhood_id IS NULL`, so every reader
in the bundle's second city sat permanently under *"Chosen from the tree nearest you in the city
record."* printed directly above *"No neighborhood boundaries are on file for where you are, so this
almanac is drawn around you instead."* Two adjacent sentences about one area, and the new one was the
false one — this round's own thesis failing on itself.

The wording states what actually happened and stops: the reader's fix is the circle's center
(`AlmanacScope.radius(center:meters:)` is handed the coordinate), and *why* it is a circle is the
next line's job. **Deliberately not `nil`**, which was the review's other suggestion: D3's rule is
that the default accounts for itself always, and a blank where the account should be is how the
screen got into F17 to begin with.

**The alternative, if the owner prefers it:** drop the line for the fallback and let `areaNote` carry
the whole explanation. It reads slightly lighter and it costs D3 its "always".

**This is the half of the round that answers F17 rather than the backlog item.** The report asks why
the page "seems to default to" a neighborhood, and until now the screen said nothing at all: a name
in the header, as bare fact, with no account of where it came from and no way to disagree. The
sentence names the *mechanism* rather than the outcome, because the mechanism is the part that
explains a surprising name.

**Alternative:** state it only when the area is picked, and leave the default silent as it is today.
Half the round's cost, and it leaves the tester's actual question unanswered.

## D4 — A picked area drops the blocks that are about the reader, and keeps the ones about the place

**Built:**

- **Almanac §4, `Where eyes are needed`, does not draw for a picked area.** It is the app's one
  directed ask (D1) and its second sentence is a claim about the reader's own walking distance
  (`AlmanacMetrics.walkRadiusM`). Both are about the reader; neither survives being pointed at a
  neighborhood across town.
- **City card 1, `Your streets, against the city`, does not draw for a picked city.** Its sentence
  is "…% of the trees near you and …% citywide" — two halves that would be measured over ground
  forty miles apart, which is R48's defect wearing a conjunction.
- Everything else is a fact about the place and is unchanged.
- **Distances inside a picked area are measured from the area, not from the reader.** The nearest
  vacant site and the newest plantings order from the neighborhood's own stored bounding-box center,
  so the list is the same for everybody who picks that name.

**Alternative:** keep §4 and card 1, and re-word them to say how far away they are. Honest, and it
turns the app's one directed ask into a suggestion that somebody drive across a city — which is a
product decision, not a copy one.

## D5 — A fix too coarse to place the reader is not used to place the reader

**Built:** `AlmanacLimits.fixCanResolveAnArea(accuracyM:withinM:)`. A fix whose stated accuracy
exceeds the radius its own resolution searches cannot pick out a tree inside that radius, so it is
not used at all; the segment draws **"Your location is too rough to place you."** and the picker.
An unknown accuracy is permitted, which leaves every preview and test unchanged.

**The bound is the caller's, and that is a correction (PR #132 review, F3).** The two segments do not
search the same distance — the almanac resolves through `SpeciesQueries.resolveNeighborhood` at
**400 m**, the City segment through `CityQueries.resolveIDSpace` at `AlmanacLimits.fallbackRadiusM`,
**1,200 m**. Keyed on 400 m for both, a fix good to 600 m blanked a City segment that could still
answer, and did answer on main. Each gate now takes the radius its own read runs over, and this
ruling's text says both numbers rather than one.

**This is the state F17 most likely came from** — see `docs/errata-pending/stats-picker.md` for what
is established and what is not. Approximate location grants exactly this kind of fix, and the app
neither requests full accuracy nor reads `accuracyAuthorization`.

**The copy deliberately does not name the setting.** The app cannot tell an approximate grant from a
poor fix in a parking garage, and naming the wrong cause is how a true screen becomes a misleading
one.

**Alternative (the conservative one):** keep naming the nearest area whatever the accuracy, and rely
on D3's sentence plus the picker to let the reader correct it. This leaves a wrong name on screen by
default, which is the thing the report complained about, but it never blanks a screen that used to
have content on it.

**Second alternative:** ask iOS for temporary full accuracy at this point
(`requestTemporaryFullAccuracyAuthorization`). It is a system prompt with a purpose string, on a
screen that is not asking for anything else, and it is a bigger change than this round's shape.

## D6 — The City segment names its city

**Built:** the header's trailing pill carries `dim_city.display_name`, read through
`id_spaces.city_id`, and carries nothing when the record has no name on file.

**This reverses three comments rather than a ruling** — see the third entry in
`docs/errata-pending/stats-picker.md`. The rule they stated was true until seed schema 16 put the
name on disk. What stays forbidden is composing a name from an id space's key or an inventory's
title, which is what R28 and R48 actually closed.

**Alternative:** keep the bare `City` header and name the city only inside the picker. Safe, and it
means a reader who picked San Jose has no persistent indication of what they are looking at.

## D7 — `Where I am` is always offered, and a stale pick falls back to it

**Built:** the first chip in both sheets is `Where I am`, present even while it is the live choice,
and a picked id the live inventories no longer carry (the reader removed a pack) resolves to the
reader's own area rather than to a named empty screen.

**Ratified 2026-08-30: it resets, and that is the decision.** The selection **does not survive
relaunch**. It lives on the
model for the life of the screen, like `AppRouter.journalSegment` before it was made addressable. A
reader who picks Manhattan, leaves the app and comes back is back on `Where I am`. That is
defensible — a stats screen whose default silently stopped being "here" is its own version of F17 —
but it is a choice, and it has now been made rather than left open.

The review confirmed there is no persistence path to leak through — no `@AppStorage`, no `app_state`
key, no `UserDefaults` write — and the move onto `AppRouter` (F2, above) keeps it that way: the
router is `@State` on `RootView`, which `CypressApp` keys on `ObjectIdentifier(data.store)`, so an
inventory change destroys the selection along with everything else built on the old layer. A pick
cannot outlive the inventory it was made against.
