# Rulings pending — city inventories become cumulative (owner decision, 2026-08-24)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge and rewrites any comment that cites this filename.

**The decision letters below are local to this entry, and they collide with another live
document's.** `docs/design-proposals/2026-08-14-city-data-distribution.md` letters its own
decisions D1–D20, and the same letter means different things in the two lists: D1 here is
id-space shadowing and D1 there is the borough as New York's published unit; D3 here is the
opening camera and D3 there is the whole-NYC pack; D5 here is the attach cap and D5 there is
Stage 0. Flagged at splice time because it rules out the obvious sweep — a mechanical
letter-to-number rewrite would give half the citations the wrong document. It is also why no
comment in `Cypress/`, `CypressTests/` or `CypressUITests/` cites a decision letter any more:
each states its constraint standing alone instead, and `PendingCitationGuardTests` §4 holds them
there.

---

## The decision

Recorded by the orchestrator, 2026-08-24, in response to App Store Connect feedback on the
downloads/cities screen. It is the owner's, not this round's, and it is not delegated design
authority for anything below it.

1. **The read layer serves the union of the bundled seed plus every downloaded city pack.** A
   reader who has downloaded Manhattan and Chicago sees both, together with everything the bundled
   seed carries.
2. **`Use` becomes add/remove of a pack from the active set**, not an exclusive switch.

### The second half, recorded later the same day

Also the owner's, on seeing the Cities screen on a device:

> SF and SJC should not be showing Use if they ship by default — it is confusing and terrible UX
> to show what that screen shows.

3. **A city the built-in inventory covers never presents a `Use` affordance, and never appears as
   a second, parallel city entry beside the built-in card.** The bundled copy is always part of the
   union.
4. **A downloaded newer copy of a bundled city is an update to that city's data, not a peer
   inventory.** It is presented inside that city's own entry as an update state, and removing the
   downloaded copy returns the entry to the bundled record.
5. **The built-in card and any per-city entry may never contradict each other** — no `In use` above
   a sibling `Use`.

### The state that was ruled out, confirmed against the code

The screen really does draw what the ruling describes, and it does so by a path worth naming
because the fix has to go through it. `CityInstallState.init` tests `installedVersion` **before**
it tests `bundled`, so the moment a downloaded copy of San Francisco exists the `bundled` argument
is never consulted: the row resolves to `.installedCurrent` or `.updateAvailable` and
`CityDownloadRow.decide` draws `Installed · <version>` with `Use` and `Remove` — beside a built-in
card that is simultaneously saying `Includes San Francisco and San Jose` and `In use`. The
`.bundled` and `.bundledOutdated` cases, which exist precisely to stop a bundled city being offered
as a download, are unreachable for any city that has ever been downloaded once.

## What it supersedes

**RULINGS R43 §1 in full.** That section rules that "exactly one inventory is attached, always
under the `seed` schema name", names the choice as "the built-in inventory **or** one downloaded
city file", and records multi-city simultaneous attach as future work. The decision above reverses
each of those three sentences.

R43 §1's stated reason for the restriction is unchanged by the reversal and is the work this round
was asked to scope: attaching several files at once means union reads across N schemas, which is a
rewrite of the read layer. §§2–4 and §6 of R43 are not reversed, but three things inside them rest
on §1 and no longer stand on their own:

- **§3's affordance table.** `Use` / `In use` / `Remove` describe an exclusive switch. What a row
  offers, and what the built-in inventory's card offers, are open (see D2 below).
- **§4's active-choice mechanism.** "The active choice is a marker file (`cities/active-city`)
  holding the city id; absent means built-in" describes one id, and the set is now plural.
- **`CityInstallState.bundled` / `.bundledOutdated`.** Both are documented on the premise that "a
  downloaded copy shadows the bundled one through the existing `active-city` marker, with no new
  mechanism". Under a union there is no shadowing unless one is designed — and decision 4 above is
  that design: the shadow is per bundled city, and it is what makes a downloaded copy an update
  rather than a peer.

Decisions 3–5 additionally supersede the R43 §1-era `Use` / `In use` presentation **for bundled
cities specifically**, which is a narrower thing than decisions 1–2 supersede: R43 §1 is reversed
for downloaded packs by the union, and reversed for bundled cities by the rule that they were never
a separate choice to begin with.

## What the code says the decision has to reckon with

Measured on this branch, 2026-08-24, against the checked-out tree and the live catalog. Nothing
here is a ruling; it is the ground the ruling has to be made on.

### The bundle already contains both of the two packs that overlap it

`Cypress/Resources/cypress-seed.sqlite` holds **198,625** trees in two id spaces — `sf` (145,837)
and `us-ca-sj` (52,788) — and no others. The live `manifest-v2.json` (format 2, generated
2026-08-23) lists **seven** packs: `sf` (145,964), `us-ca-sj` (52,775), and the five New York
boroughs, which share the id space `us-ny-nyc` and total 898,643 trees. Total published, 1,097,382
trees in about 713 MB.

So the overlap is exact and it is not hypothetical: **the only two packs whose ground the bundle
also covers are `sf` and `us-ca-sj`**, and both are offered for download today, because the
published record date (2026-08-22) is later than the bundle's (2026-07-31) and
`CityInstallState.bundledOutdated` therefore draws the button. A literal union with no shadowing
rule draws every San Francisco tree twice.

The five borough packs never overlap the bundle, and no two packs overlap each other. **Pack-versus-
pack de-duplication is not needed; bundle-versus-pack de-duplication is.**

### The mechanism the union would have to use

Only a `TEMP` view may reference an attached database — a view created in an attached in-memory
schema is refused outright (`view trees cannot reference objects in database inv0`). So a union
that leaves the existing SQL untouched has to live in `temp`, which means `SeedDatabase.schemaName`
becomes `temp` and every `\(seed).trees` in `Cypress/Data/Store/TreeQueries.swift` and its
neighbours keeps its text. Two sites in that file read `t.rowid`, which a view does not have; both
have an `id` that is a rowid alias in the current identity model.

Apple's system SQLite reports `SQLITE_LIMIT_ATTACHED` as **10** (3.51.0, macOS; not yet confirmed
on the simulator or a device). Bundle plus seven packs is eight, plus `main`. The cap is close
enough to today's catalog to need a stated answer (D5).

### What it costs, measured

The whole-of-San-Francisco cluster query at 64 pt cells — the query
`SpatialIndexStrategy.default`'s own table was measured on, run the same way (sqlite3 CLI, macOS,
warm). The packs here are **synthetic**: the bundled seed narrowed by id space and vacuumed, not
the published files, which were not downloaded.

| arrangement | time | plan |
|---|---|---|
| the bundle alone, straight at the table | 59–61 ms | `SEARCH t USING COVERING INDEX idx_trees_lat_lon` |
| one arm, through a temp view | 60–61 ms | covering index kept |
| two arms, the second outside the viewport | 69 ms | covering index kept, both arms |
| eight arms, six outside the viewport | 158–165 ms | — |
| bundle + `sf` pack, no de-duplication | 157–170 ms | covering index kept; every cell counts double |
| de-duplicated by `id_space NOT IN ('sf')` on the bundle arm | 164 ms | index used, not covering |
| de-duplicated by `NOT EXISTS (… p.uuid = b.uuid)` | 289 ms | — |
| de-duplicated by rowid range on the bundle arm | 75–85 ms | covering index kept, both arms |

Four things follow, and the last one is the one that matters:

1. **A temp view costs nothing by itself.** One arm through a view is the bare table's time.
2. **Arms outside the viewport are nearly free.** Eight attached inventories cost what two do when
   six of them hold no row the camera can see, because the latitude range prunes them at the index.
   The read scales with rows in view, not with inventories attached — which is the opposite of what
   R43 §1 assumed, and it is why this is worth attempting at all.
3. **Duplication, not the union, is what costs.** The 157–170 ms row is the 59 ms row with twice
   the trees under the camera.
4. **How the duplicate rows are excluded decides whether this is affordable.** Rejecting them on
   `id_space` costs a table probe per rejected row and gives all the savings back. Rejecting them
   on `uuid` costs 4.8× the baseline. Rejecting them on a rowid range is answered from
   `idx_trees_lat_lon` itself, which carries `id`, so the covering index survives and the whole
   union lands at 75–85 ms against a 59–61 ms floor.

   The bundle's id ranges are in fact contiguous per id space today (`sf` is 1–145,837,
   `us-ca-sj` is 145,838–198,625, with no row of either space inside the other's range). **That is
   a property of one build of one file, not a contract** — `Tools/build_seed.py` promises nothing
   about it. It is measurable at open and checkable (a range is contiguous when its count equals
   its span), so it can be used where it holds and fallen back on where it does not; it must not
   be assumed.

The R\*Tree strategy also survives the union — the box constraints still reach the virtual table
through the view — but joining two compound views expands to N² arms in the plan. It is not the
default strategy and is not on the path a thumb drags.

### Species are the identity problem the geometry is not

`trees.uuid` and `species.uuid` are `uuid5` of a source id and of a scientific name respectively,
so both are stable across builds and both are usable as cross-file keys. `trees.id` and
`species.id` are integers local to their file. Geometry can be re-keyed with a per-file offset;
`species.id` cannot be, because `trees.species_current` in one file must resolve to the *same*
species row as `species_current` in another, or the species list shows 731 species per attached
inventory and every group-by splits. Which file's catalog is canonical, and whether the
translation happens inside the view or at the query boundary, is D6.

## Proposed: what the Cities screen becomes

Written under R43 §3's delegated-authority pattern, which is how that ruling's own affordance
table was produced: the screen has no mock, so the ruling is the mock. **These are proposals for
ratification, not decisions.** Anything the decisions above do not determine is in the list below
rather than settled here.

**One card per thing the reader can act on, and a bundled city is not one of them.**

- **The built-in card** keeps its title and its `Includes …` line and **draws no affordance at
  all** — not `Use`, not `In use`, not `Remove`. It cannot be switched off, so a control that
  says otherwise is the contradiction decision 5 forbids. `Ships with the app and cannot be
  removed` already says the operative fact and needs no button under it.
- **A bundled city gets one entry, nested under the built-in card**, in the `isCityGroup` idiom
  `CityDownloadSection` already draws for a city's packs. Never a peer card in `On this phone`,
  which is decision 3. (*"Nested under"* turned out to name more than one arrangement, and the
  `isCityGroup` idiom was the wrong one. The owner settled it on 2026-08-25 as containment inside
  the built-in card — see the ratified section below. This bullet is left as it was proposed.)
  Its state line is one of three:
  - `Included in the app · record as of <rev>` — the bundle's own copy is what the map draws;
  - `Included in the app · record as of <rev>` with `A newer record is available.` beneath and one
    `Update` button — the catalog is ahead, and the verb is `Update` rather than `Download`
    because decision 4 makes it one;
  - `Updated · record as of <rev>` with `Revert to the included copy` — a downloaded copy has
    replaced the bundled rows for this city.
- **`Remove` is not the word for undoing that update.** It reads as removing the city, and the
  city cannot be removed; what is removed is the newer copy, and the entry returns to the bundled
  record. That is decision 4's second clause and it needs its own verb.
- **A pack the bundle does not cover** — the five New York boroughs today — keeps its own card and
  loses `Use` and `In use` along with everything else. See D9: if downloaded means in the union,
  the only verbs the screen needs anywhere are `Download`, `Update`, `Remove` and `Cancel`, and
  `Use` leaves the vocabulary entirely.

## Ratified by the owner, 2026-08-24/25

Recorded by the orchestrator from the owner's own window. Each of these was open in the list
below when this entry was written; each is now settled, and the implementation is built on them.
Two items carry a later date than the rest and say so where they sit: D2 was **re-ruled** on
2026-08-25 after the first implementation of it drew nothing, and the copy for a refused file was
ratified the same day.

- **D9 — downloaded IS the active set.** A downloaded city is in the union; there is no separate
  active toggle. The screen's vocabulary is `Download`, `Update`, `Remove` and `Cancel`; `Use`
  and `In use` leave it entirely. The `active-city` marker is retired (`CityLibrary`), and a
  device carrying one from an older build has it deleted on the next launch.
- **D1 — shadowing at whole-city / id-space granularity.** A downloaded copy of a bundled city
  shadows every bundled row of that id space. **Bundle only**: a pack never shadows another pack,
  because the five New York boroughs share the id space `us-ny-nyc` and an id-space rule applied
  between packs would delete Brooklyn the moment Manhattan was installed.
- **D2 — the proposed screen, as proposed.** The built-in card draws no affordance at all;
  bundled cities belong to it rather than beside it, with the three state lines exactly as
  written; non-bundled packs keep their own cards. The copy lands verbatim.

  **Re-ruled 2026-08-25: the bundled cities are drawn *inside* the built-in card.** Recorded by
  the orchestrator from the owner's own window, after the first implementation was shown on a
  device. *"Nested under it"* had been read as a sibling group drawn one step quieter — the
  `isCityGroup` idiom — and that resolved to no drawn difference at all, because the flag reached
  the view through a single padding modifier sitting inside `if !section.title.isEmpty` and that
  group's title is empty by construction. `Built-in inventory`, `San Francisco` and `San Jose`
  came out as three cards of identical width and inset, which is the arrangement decision 3
  forbids.

  The ruling is containment, literally. **One card**: the built-in header, and each bundled
  city's entry within that card's own boundary. **Existing chrome only** — the card's rounded
  rectangle and border, a `borderCool` hairline between entries, tokens throughout; no new
  component, no new drawn geometry, nothing that would be a constraint-21 stop-and-ask. A bundled
  city is never drawn outside that card, and a pack the bundle does not cover is never drawn
  inside it. This holds in every row state, including the one that carries a full-width control
  (`Revert to the included copy`) and the one where the downloaded copy could not be read.

  Whether one rectangle encloses another is not a property of a value, so it is pinned on the
  device (`CityCardContainmentUITests`) rather than only in the presentation model — the earlier
  guard asserted the arrangement as data and stayed green while the screen drew peers.
- **D5 — the installed set is capped, with honest copy.** Headroom is checked at open against the
  platform's actual attach limit (`SQLITE_LIMIT_ATTACHED`, read off the live connection — never
  hard-coded), and at the cap the `Download` button is replaced by `Remove a city to download
  another.` An *update* is never withheld: it reuses the slot that city already holds.
- **D3 — the opening camera.** A location fix inside any live inventory wins; failing that, the
  camera this install was last left on; failing that, the largest downloaded inventory. With
  nothing downloaded it degrades to today's behavior exactly.
- **D4 — per-city aggregates stay per-city.** The Journal's `City` segment and the almanac keep
  resolving an id space from the nearest tree. No cross-inventory aggregate is opened.
- **D10 — `content_rev` in copy.** The rendered sentence strips any publisher counter suffix (a
  bare date), and **every comparison keeps the full opaque string**. The live catalog has
  carried revisions like `2026-08-22.02` on all seven packs since the republish of 2026-08-25, so
  both halves are exercised against the shipping shape rather than a fixture.
- **The copy for a file the read layer refused — ratified as shipped, 2026-08-25.** Recorded by
  the orchestrator from the owner's own window. Containment (above) is what makes a refused pack
  visible at all, and the screen state it produces is not in the mocks (DECISIONS constraint 21),
  so the two sentences the implementation had to write were put to the owner and are ruled
  verbatim, as written:

  - state line — `Couldn't be read`, drawn in the attention color the screen already gives a
    failed row (`isFailure`, `CypressColor.signalAmber`);
  - detail line — `The downloaded file couldn't be opened, so its trees are not on the map.`

  **No new affordance goes with them.** The sentence states the fact and the button already on
  the row states the remedy: `Revert to the included copy` for a bundled city whose downloaded
  copy failed, `Remove` for a pack the bundle does not carry. Either one clears the file and the
  state with it. That division is why the copy names neither verb — a sentence naming one of them
  would be wrong on the other row.

## Proposed by this round, for the orchestrator to adjudicate

D6, D7 and D8 were delegated to the implementation. What follows is what was built and why.

### D6 — the canonical species catalog

**Chosen: one canonical catalog, materialized at open into `temp.species`, keyed by
`species.uuid`, with a per-arm translation table mapping that arm's local `species_current` onto
it.** Every existing `JOIN species s ON s.id = t.species_current` and `GROUP BY s.id` keeps
working unchanged.

The premise was checked before it was built on. `Tools/build_seed.py` assigns `species.id` as
`len(species_by_key) + 1` in **first-encounter order while it streams its sources**, so two builds
over different city sets number the same species differently — the bundle is built from San
Francisco and San Jose, the packs are cut from a fused seed that also holds New York. The ids
cannot be assumed to agree, and `species.uuid` (a `uuid5` of the scientific name) can.

Two alternatives were rejected on measurement:

- **Leave species per-arm and re-key every join to `uuid`.** Correct, and it produces the ideal
  narrowed plan (`SEARCH s USING COVERING INDEX sqlite_autoindex_species_1` then
  `SEARCH t USING INDEX idx_trees_species_current`) — but it is fifteen join sites across five
  query files, and it moves a species list's grouping key in every one of them.
- **Offset species ids per arm, as tree ids are offset.** The join `s.id = t.species_current`
  then compares two arithmetic expressions and stops being sargable.

Measured against an arm whose species numbering was deliberately **permuted**: the narrowed
viewport still resolves through `idx_trees_species_current` on every arm, because the `LEFT JOIN`
converts to an inner one under the caller's `WHERE` and the planner drives from the translation
table. `CumulativeInventoryTests` carries that fixture, and its red-proof — assuming the two files
agree — names the pack's Ginkgo `Platanus acerifolia`.

### D7 — `CityInstallState`'s shape

**Chosen: one new case, `.bundledUpdated(installedContentRev:updateAvailable:)`, and the bundle
tested before the installed copy.**

The ordering defect is fixed by asking `bundled` first. Reordering alone would have been the wrong
fix and would have hidden the downloaded copy instead: a bundled city *with* a downloaded copy is
a real state, it is the one decision 4 is about, and the enum had no case for it. The
`updateAvailable` flag is a payload rather than a fourth case because what the reader sees is one
city with one record and at most one offer.

`isBundledCity` is stated on the type beside `isOnDevice` and `allowsDownload`, so the screen's
sectioning, its buttons and its copy cannot reach different conclusions about the same city.

### D8 — the removal lifecycle

**Chosen: a whole-layer reboot, and it is stated rather than hidden.** Adding or removing an arm
rebuilds the views over a different set of schemas and renumbers the canonical species catalog.
Dropping and recreating in place would have to get both right on a connection other code may be
mid-read on; booting again gets them right by construction and is the path every launch already
takes. `CityDownloadsModel` therefore calls `onInventoryChange()` on **every** completed install
and every removal, where it used to call it only when the active choice moved.

Two justifications for clearing the statement cache were written and then **withdrawn after
measurement** — SQLite re-prepares a cached statement when the schema changes under it, and it does
not refuse a `DETACH` for a statement that is merely prepared. The clear is kept as a defensive
measure and `InventoryUnion.tearDownEverything` records that it is one.

## What this entry does not decide

Collected for the orchestrator. Each is a question this round declined to answer for itself.

- **D1 — Shadowing granularity.** Decision 4 settles *that* a downloaded copy of a bundled city
  shadows the bundled rows. At what granularity is still open: id space, published region, or per
  tree. The bundled seed is s16-shaped — it carries `dim_city` and **no `dim_region`** — so it
  cannot be shadowed at region granularity without a seed rebuild. Id-space granularity is
  sufficient for today's catalog, because the only two packs that overlap the bundle are whole-city
  packs whose pack id *is* their id space; it would not be sufficient for a borough pack whose city
  the bundle carried.
- **D2 — The screen copy above.** **Ruled, and then re-ruled.** The three state lines, the
  `Update` verb for a bundled city and `Revert to the included copy` were ratified verbatim on
  2026-08-24/25; the arrangement they sit in was re-ruled on 2026-08-25 as containment inside the
  built-in card, after the first implementation of *"nested under it"* drew nothing. One thing was
  open that this list never named, because it did not exist until the round wrote it: what a
  downloaded file says when the read layer refuses it. That copy is ratified too. All of it is in
  the ratified section above; nothing about this screen is left proposed.
- **D9 — Is the active set the installed set?** Decision 1 says the union is "the bundled seed plus
  every downloaded city pack", which reads as *downloaded ⇒ in the union*. Decision 2 says `Use`
  becomes "add/remove of a pack from the active set", which reads as a set a pack can be out of
  while still on disk. Both cannot be true. **This round recommends the first**: downloading a pack
  is what puts it in the union, `Remove` is what takes it out, and there is no third state to
  explain — which is also the reading that makes the confusing screen the owner ruled out
  unconstructible. If the second is meant instead, `CityLibrary`'s marker becomes a set of ids and
  every row acquires a fourth state.
- **D10 — `content_rev` in copy.** The comparison already treats it as an opaque ordered string
  (`CityInstallState` compares `publishedRev > bundledRev` on `String`, and splits no version).
  The *copy* does not: `record as of <rev>` renders it as a date. With same-day republishes becoming
  visible to update detection, a rev that is no longer a bare date will read oddly in that sentence,
  and the sentence is what needs a decision, not the comparison.
- **D3 — What "active" means to the map and to the test harness.** `Tools/run_tests.sh` refuses a
  run on a leftover `active-city` marker and on a camera with no seed tree within 250 m of it
  (E202, E216). Both are single-inventory notions. The opening camera's choice among several live
  inventories is likewise undecided.
- **D4 — Citywide aggregates.** `Cypress/Data/Store/CityQueries.swift` resolves an id space from
  the nearest tree and predicates every count on it, which still holds under a union. Whether the
  Journal's `City` segment and the almanac should now be able to speak about more than the city the
  reader is standing in is a separate question, and this entry does not open it.
- **D5 — The attach cap.** Ten attached databases. Bundle plus seven packs is eight, plus `main`.
  Is the installed set capped, and what does a row say at the cap?
- **D6 — The canonical species catalog.** See above.
- **D7 — `CityInstallState`'s shape.** Decision 4 settles what the states *mean*; it does not settle
  the type. The ordering defect named earlier — `installedVersion` tested before `bundled`, so a
  bundled city that has ever been downloaded can never reach `.bundled` again — has to be fixed
  whichever way the rest goes, and the fix is more than reordering two branches: a bundled city with
  a downloaded copy is a state the enum has no case for, and it is the state decision 4 is about.
- **D8 — Removal while contributing.** Removing a pack from the set has to rebuild the view and
  invalidate every cached prepared statement built against the old one. That is mechanical, but it
  is a lifecycle the current code has no equivalent of: today a switch reboots `DataLayer` whole.
