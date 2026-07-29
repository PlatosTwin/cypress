### The map's species search matched a prefix, so "cypress" found one species of six

`SpeciesQueries.search` resolved a query against `seed.species` with a **prefix range scan** —
`name >= :q AND name < :q || U+FFFF COLLATE NOCASE`, over `scientific_name` and `common_name`,
unioned. It was written that way because BUILD-PLAN §6 specifies a trigram index on both names,
which Postgres has and SQLite does not, and the method's own comment recorded the resulting gap in
one line: "Trigram matching finds 'oak' inside 'Coast Live Oak'; a prefix scan does not."

That line understated it. The seed's common names are overwhelmingly `Adjective Noun` — the noun
being the word a person types. So the gap is not an edge case, it is the normal case:

| typed | the prefix scan found | the catalogue holds |
|---|---|---|
| `cypress` | 1 — `Cypress species / Cupressus spp` | 6 |
| `oak` | 1 — `Oak / Quercus spp` | 21 |

The project owner walked the app and reported the `cypress` case: *"I just typed in cypress and got
three hits across the whole city which seems like a bug? Should bring up all Monterey cypress not
just cypress spp."* Both halves of that sentence are worth separating, because only one of them is a
matching defect:

- **the misses** — Monterey, Italian, Leyland, Hinoki and Montezuma Cypress all carry the word in
  second position, so none of them matched. That is the defect.
- **"three hits"** — those were three *pins* of the one species that did match, inside the viewport,
  not three species. Screen 01's status line reports pins; nothing on it said how many *species* the
  query had resolved to, so a one-species narrowing that happened to draw three pins was
  indistinguishable from a three-species answer. The count was never wrong. It was answering a
  different question from the one being asked of it.

**The cap was not involved.** `MapSearch.speciesLimit` is 100 and `Page<Species>.maximumLimit` clamps
to the same, so nothing was truncated at six, or at one.

**Fixed** by matching a substring of either name, with a rank computed in the same pass — a name that
*starts* with the query outranks one where a *word* starts with it, which outranks the letters
appearing inside a word. So `cypress` returns the genus first, `Monterey Cypress` (the one curated
Cypress) second, and `oak` reaches `Coast Live Oak` while `Silkoak species` sinks to the bottom.

The leading wildcard forfeits no index, which is the part worth writing down because the objection to
it is otherwise correct: the range scan was **already** walking both name indexes end to end.
`COLLATE NOCASE` does not match the `BINARY` collation the seed's indexes were built with, so SQLite
could never turn the range into a seek — its plan said `SCAN … USING COVERING INDEX`, not `SEARCH`.
The new plan is the same two covering walks. Timings against the full seed are in
`.measurements/README.md` and `.measurements/species-search-108.txt`: the SQL goes from 0.08–0.25 ms
to 0.13–0.83 ms and the whole read is unchanged wherever the two return the same rows.

**What this newly exposes, and what was done about it (E38).** Matching anywhere makes the 100-species
cap reachable in ordinary use where it was not before: `a` prefix-matched 97 species and *contains* in
555. A truncated species set narrowing the map while the status line calls it "Showing 100 species" is
a page wearing a total's clothes. `MapSearch.Narrowed` now carries whether the catalogue returned a
full page, and `MapSearchCopy` says so in all four of the sentences it can produce.

**Two things moved with it, because the change made them untrue.** `SpeciesPickCopy.noMatch` told a
contributor "Nothing in the catalogue starts with …. Try the first word of either name", which now
sends them to retype a query that already worked. `DataGates`' species-search assertion checked that
every match had a name *beginning* with the query.

**What is still not fixed.** This is substring matching, not the trigram matching §6 specifies: a typo
misses, and so does a name the catalogue spells differently. That still wants an FTS5 index the seed
does not carry, and it still belongs in `Tools/build_seed.py` beside the data rather than being built
on device at first launch.
