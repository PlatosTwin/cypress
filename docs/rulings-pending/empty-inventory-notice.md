# R— · The map says why it drew nothing, and the trigger is the emptiness rather than a park (task #190)

**Unnumbered.** Written on branch `p1/round10-a` under the delegated design authority #190 grants
for the copy and the surface. Everything below was decided from the running app on iPhone 16 Pro
Max `DE8E11AE-…`, from the shipped seed, and from the code — not from the brief. Where the brief
turned out to be wrong or unbuildable, this says so.

---

## What this rules

Screen 01 gains a fifth standing state. When a read completes for the current viewport, nothing is
narrowing the map, and the answer holds nothing to draw, the bottom slot draws a `MapLocationNotice`
reading:

> **No trees on record here**
> Cypress draws a city street-tree inventory, and this ground is not on it. Trees may well stand
> here, unlisted.

The decision is `MapInventoryNotice.isOwed`; the words are `MapInventoryCopy`; the drawing is the
`.nothing` arm of `MapHomeView.standingNotice`.

---

## 1 · The problem, confirmed on the phone before anything was written

Golden Gate Park at street zoom draws **no pins at all** — only Apple's basemap canopy artwork,
which is the picture of the problem: the basemap knows there are trees there and the inventory does
not. One pan north across Fulton Street and the pins start on the first block and do not stop. The
screenshots are in the branch report.

`ERRATA E126` governs — a screen showing nothing must say why — and this is the one place on screen
01 where E126 was not discharged. It is also the likeliest place a first-time reader opens the app.

The cause is `ERRATA E214`: San Francisco has never counted its park trees. Rec & Park publishes no
tree inventory at any status, and the census the `sf_city` list descends from excluded park trees by
design. There is no ingest gap to close and nothing to retry.

---

## 2 · The trigger, and why it is not a park

**Decided: the trigger is "a settled, un-narrowed read returned nothing to draw."** Four gates, all
of them load-bearing, each with its own test and its own red-proof.

### 2.1 The brief's preferred trigger — "inside an RPD polygon" — is unbuildable, twice over

The brief asked whether the seed carries the Rec & Park polygons or only the 41 analysis
neighborhoods. **Only the 41**, and the answer is worse than that for a geometric trigger:

- `Fixtures/seed/cypress-seed.sqlite` holds one polygon table, `neighborhoods` — 41 rows, dataset
  `j2bu-swwd` per `seed_meta.neighborhoods_dataset_id`. There is no Rec & Park property geometry in
  the file at all. Adding it would be a seed change, which #190 forbids.
- **And the app never reads the polygons it does have.** `SpeciesQueries.resolveNeighborhood`
  answers "which area is this coordinate in" through the **nearest inventoried tree's**
  `neighborhood_id`, deliberately, so that no ray-cast of ours can disagree with the city's own
  assignment (`ERRATA E44`). That mechanism is nil where there is no inventoried tree within 400 m
  — which is precisely the coordinates this notice exists for. **The app's only way to name where
  you are is to ask a tree, and there is no tree.**

So a park-shaped or neighbourhood-shaped trigger is not a design option that was declined on taste.
It is not available.

### 2.2 It would also have been wrong

`Golden Gate Park` *is* one of the 41 analysis neighborhoods (as are `Lincoln Park`, `McLaren Park`
and `Presidio`), so a neighbourhood-keyed notice was superficially buildable and is exactly the lie
the brief warned about: Dolores Park, Lake Merced and the other 236 Rec & Park properties are not
neighborhoods and would get nothing. E214's citywide measurement — 1,922 of 145,837 SF rows on Rec &
Park land, 1.3 %, all edge effects — is a fact about *every* park, not about one.

### 2.3 What the emptiness trigger actually covers, measured on the shipped seed

| screenful | rows in the seed | notice |
|---|---:|---|
| Golden Gate Park interior, one street-zoom screenful around Stow Lake | **0** | draws |
| Presidio core | **0** | draws |
| Lake Merced | **0** | draws |
| Pacific west of the Sunset | **0** | draws |
| Oakland | **0** | draws |
| San Jose outside the shipped downtown window | **0** | draws |
| Dolores Park and one block of ring | 413 | silent |

**The last row is the honest limit of this ruling and is stated rather than hidden.** Dolores Park
is sixteen acres ringed by dense street-tree frontage, so a street-zoom screenful over it is never
empty and the notice never fires there. That is correct behaviour for a trigger that answers "this
screen has nothing on it": the screen does have something on it. It is not a park detector and does
not claim to be one. A reader standing in the middle of Dolores Park sees pins on Dolores Street and
18th Street, which is a truthful picture of a street-tree inventory.

### 2.4 The other three gates

- **Settled.** `MapModel.content` opens at `.pins([])`, the same value an answered-and-empty
  viewport produces. Without the gate the notice would post for the opening publish of every launch,
  over any street in the city. `MapOpening.patience` exists for the same hazard.
- **Not failed.** `ERRATA E126`'s own defect was a screen drawing its empty state for a read that
  never finished. "Nothing is on record here" is a claim about the record; a read that threw has
  learned nothing about the record.
- **Markers, not trees.** The gate reads `MapContent.markerCount`. One cluster badge standing for
  29,390 trees is not an empty screen.

---

## 3 · R41 reaches this surface, and the finding is that it should

#190 asked whether `RULINGS R41`'s ban reaches the chosen surface, and said that if it does, that is
a finding rather than an obstacle. **It does, and the finding is recorded here rather than routed
around.**

R41's test is *"does text appear because a filter did something?"* A bare "no rows in view" trigger
answers **yes**: a species chip, a decade, a membership set or a typed word that matches nothing
empties the map exactly as standing in Golden Gate Park does, and a sentence posted then would be
the fourth filter-adjacent message to be ruled out — after #142's growing notice, the R31
correction's empty-filter box, and `MapFilterStatus` (`ERRATA E205`). It is also the precise state
task #165 settled the other way, on the owner's direct instruction: *"if nothing matches, fine."*

**So the narrowing gate is R41 applied, not R41 read down.** Nothing here shelters filter-triggered
text under a new mechanism. What draws is a fact about the *inventory*, on a map nobody has
narrowed, and it disappears the moment anybody narrows it — including the case where the filter is
what emptied the map. E126's carve-out is not being stretched either: this is not a location notice
and does not claim to be one; it is a new state that meets R41's test by never being caused by a
filter.

`CypressUITests/MapFilterAccessibilityTests.testNoTextAccompaniesAFilter` already holds this from
the other side, and holds it causally rather than temporally: text is a violation only when it is
present with a filter on and absent with it off. This notice is absent with a filter on, by
construction.

**A consequence worth naming for whoever revisits R41.** If R41 were ever relaxed, the honest
version of this notice for a filtered empty map is a *different sentence* — "nothing here matches
what you asked for" is not "this ground is not on the inventory" — and it must not be this one
wearing a wider trigger.

---

## 4 · The surface: the existing bottom-slot notice, not a new component

**Decided: `MapLocationNotice`, in screen 01's bottom slot, as a fifth occupant.** #190 asked that
what already exists be checked before anything is added. It does exist, it is the right shape, and
building a second card would put two kinds of standing notice on one screen.

- SCREENS.md 01 lists `empty/no-GPS state` among its **NOT SPECIFIED** states. That is the same door
  `MapOpening.Standing` and `MapLocationNotice` were built through under ARCHITECTURE §8 rule 8, so
  DECISIONS constraint 21 does not make this a stop-and-ask; the state is named by the spec as one
  the spec does not draw.
- The component already takes a title, a message and an *optional* action, so a notice with nothing
  to press needs no change to it. Not one line of `MapLocationNotice` was touched.

### 4.1 Precedence: the location states win

Where both could speak, the location notice draws and this one does not. This follows E126's own
precedent on screen 12 — a missing fix wins over a failed read, because "the prompt is the one that
has an action behind it". Three of the four location states are about the reader's own device and
two carry a Settings button; this one is a standing fact about the record with nothing to press.
They are barely rivals in practice: a reader with a fix gets `.nothing` from `MapOpening.standing`,
which is the arm this draws in.

### 4.2 No button, deliberately

E126 asks an emptied surface to say why **and** offer a way out, and its examples are a retry for a
failed read and `Clear filters` for a narrowed one. Neither exists here: nothing failed and there is
nothing to clear. The one thing a reader *can* do — put a tree on the map themselves, which per E214
is the only route to a populated Golden Gate Park that exists today — is the `What tree is this?`
FAB, the largest control on the screen, sitting directly above this card whether it draws or not.
Repeating it in prose would be a second, weaker copy of a control already in the reader's eye, and
`ERRATA E183 §2` is a standing warning about what a button on this card costs at accessibility
sizes.

---

## 5 · The copy, and what each clause is answerable for

> **No trees on record here**
> Cypress draws a city street-tree inventory, and this ground is not on it. Trees may well stand
> here, unlisted.

- **"on record", not "here".** The subject is the record, not the ground. `No trees here` is the one
  thing this notice must never say.
- **"a city street-tree inventory"** is the inventory's own published name rather than a
  characterisation invented for this screen. All three inventories `Tools/inventory_contract.py`
  registers are named one: `SF Public Works street tree inventory`, `DataSF Street Tree List`,
  `City of San Jose Street Tree inventory`. **This is the sentence's one dependency on the world,
  and it is stated so the next reader can check it:** the day an inventory is registered that is not
  a street-tree list, this clause becomes false and the sentence needs rewriting. It deliberately
  does not name *which* inventory — that is true of whichever file R43 has attached, and threading
  the attached name out to screen 01 is precisely the plumbing E205 has just finished deleting.
- **"this ground is not on it"** states a boundary of the record's extent. No verb the reader could
  have got wrong, no state that resolves.
- **"Trees may well stand here, unlisted."** The half #190 is actually about. `may well` is
  load-bearing and is not a hedge to be tidied away later: the trigger fires over the Pacific and
  outside a downloaded city's window as well as in the park, and `Trees stand here` would be a
  stronger sentence and a false one in those places.

**What it does not say, and why.** No date, no "yet", no "soon", no "we are working on it". Rec &
Park publishes no tree inventory at any status and no parks phase of the Urban Forest Plan has ever
published data (E214), so a promise would be `ERRATA E212`'s invented destination claim wearing a
different noun. A test refuses eight such words by name. It also refuses seven words that would make
a documented boundary of a municipal dataset read as a fault — `error`, `failed`, `could not`,
`unable`, `try again`, `loading`, `problem` — because this is closer to a map legend than to a
failure.

**No civic content is invented** (DECISIONS constraint 15). Every fact in the sentence is either the
inventory's own name or a tautology about the record: if the city had counted these trees there
would be rows, and there are none.

---

## 6 · AX5, and the errata family this ticket sits inside

`ERRATA E183 §2` measured `MapLocationNotice` at AX5 taller than a 390 pt display, laid out from its
bottom edge, growing up past `y = 0` with E126's way out above the top of the screen. That defect is
a layout ruling nobody has taken and it is **not fixed here** — it is the same open question R23
left ("whether the chrome is now too tall") and R14, R22 and R25 §6 have each answered separately
for their own surface. #190 is not the ticket to answer it in.

**But this ticket must not deepen it, and the first draft of the copy did.** Measured through
`AX5ReflowTests.ax5Size` at accessibility5 on the 393 pt phone the sweep photographs:

| card | height at AX5 |
|---|---:|
| first draft (`…; the inventory has never listed them.`) | **502.3 pt** |
| tallest location notice already shipping in this slot | **456.7 pt** |
| shipped copy (`Trees may well stand here, unlisted.`) | under the budget |

So the copy was shortened until it fit under the tallest card already in the slot, and
`MapEmptyInventoryTests.theNoticeFitsTheSlotAtAX5` holds that budget rather than a number invented
here — a copy edit that spends the line back fails instead of shipping. Photographed at AX5 on the
running phone as well: on a 440 pt device the whole card is on the glass, title on two lines,
message on six, above the tab bar.

---

## 7 · What was checked and left alone

- **No migration, no seed change, no `inventory_contract.py` registration.** E214's rule stands: the
  correct response to a source that does not exist is to add nothing.
- **`MapLocationNotice`, `MapFilterCopy`, `MapSearchStatus`, `MapSpeciesLegend`, the drawer** — all
  untouched. E205's audit of every filter surface is still accurate.
- **`LandContext`** — untouched, and E214 is right that `.cityPark` already exists and needs no
  fourth case.

---

## 8 · One correction to the brief's numbers, for the record

#190 quotes E214's measurement — **65** seed rows inside Rec & Park's own Golden Gate Park polygon,
all of them DPW-maintained street trees. That is not reproducible from anything the app ships,
because the RPD polygon is not in the seed. Measured against the polygon the seed *does* carry — the
`Golden Gate Park` **analysis neighborhood** — the count is **90** rows, of which **79** carry
`legal_status = 'DPW Maintained'` and **53** name `Rec/Park` as caretaker. (The remaining 11 are
`Permitted Site`, `Property Tree` and `Significant Tree`, all `Private`.)

The two numbers are not in conflict: they are two different polygons, and E214 says which one it
used. It is recorded here only so that the next reader who queries the seed and gets 90 does not
conclude that E214 is wrong. **Neither number is reachable by the app at runtime**, which is §2.1's
whole point.
