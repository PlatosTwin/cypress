# Rulings pending — city inventories become cumulative (owner decision, 2026-08-24)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge and rewrites any comment that cites this filename.

---

## The decision

Recorded by the orchestrator, 2026-08-24, in response to App Store Connect feedback on the
downloads/cities screen. It is the owner's, not this round's, and it is not delegated design
authority for anything below it.

1. **The read layer serves the union of the bundled seed plus every downloaded city pack.** A
   reader who has downloaded Manhattan and Chicago sees both, together with everything the bundled
   seed carries.
2. **`Use` becomes add/remove of a pack from the active set**, not an exclusive switch.

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
  mechanism". Under a union there is no shadowing unless one is designed (D1).

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

## What this entry does not decide

Collected for the orchestrator. Each is a question this round declined to answer for itself: the
first two because they are product decisions, the rest because the code and the mocks do not
determine them.

- **D1 — Shadowing.** Does the bundled seed stay in the union on ground a downloaded pack covers?
  If it is shadowed, at what granularity — id space, published region, or per tree? Note that the
  bundled seed is s16-shaped: it carries `dim_city` and **no `dim_region`**, so it cannot be
  shadowed at region granularity without a seed rebuild. Id-space granularity is sufficient for
  today's catalog and would not be sufficient for a borough pack whose city the bundle carried.
- **D2 — The Cities screen.** Add/remove is a set of states no mock covers, and R43 §3 was written
  as the mock for exactly that reason. What each row offers, what the built-in inventory's card
  offers when it can no longer be the exclusive choice, and whether the built-in inventory can be
  removed from the set at all, are unanswered. DECISIONS constraint 21 makes this a stop-and-ask
  and this round is stopping on it.
- **D3 — What "active" means to the map and to the test harness.** `Tools/run_tests.sh` refuses a
  run on a leftover `active-city` marker and on a camera with no seed tree within 250 m of it
  (E202, E216). Both are single-inventory notions. The opening camera's choice among several live
  inventories is likewise undecided.
- **D4 — Citywide aggregates.** `Cypress/Data/Store/CityQueries.swift` resolves an id space from
  the nearest tree and predicates every count on it, which still holds under a union. Whether the
  Journal's `City` segment and the almanac should now be able to speak about more than the city the
  reader is standing in is a separate question, and this entry does not open it.
- **D5 — The attach cap.** Ten attached databases. Is the active set capped, and what does a row
  say when the reader adds the eleventh?
- **D6 — The canonical species catalog.** See above.
- **D7 — `CityInstallState`.** `.bundled` and `.bundledOutdated` both mean "you already have this,
  through the bundle". Under a union the second one's `Download` button buys a fresher copy of
  ground the reader already sees, which is a different promise from the one the case was written
  for.
- **D8 — Removal while contributing.** Removing a pack from the set has to rebuild the view and
  invalidate every cached prepared statement built against the old one. That is mechanical, but it
  is a lifecycle the current code has no equivalent of: today a switch reboots `DataLayer` whole.
