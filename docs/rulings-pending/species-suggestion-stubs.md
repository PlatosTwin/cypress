# R— — the species suggestion list offers only names a reader can read (task #103)

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge
and rewrites the citations in `Cypress/Data/Store/SpeciesQueries.swift` and
`CypressTests/SeedStubNamingTests.swift`.*

---

**What was delegated.** Task #103 raised half of itself in priority: not "canonicalise the species
name in the builder", which is a corpus repair with an obvious right answer, but "decide what the
suggestion list does with a stub row at all", which is a design question about a screen. R25 (task
#109) put a species list under screen 01's search field and specified six things about it; none of
them is what the list should do with a row whose name is not a name. This is that gap, answered
under the standing delegation.

**The measurement, taken from the shipped corpus rather than from the ticket.** A species the ingest
could not read keeps the raw source string as its scientific name. Before #103 the seed carried
fifteen of them, standing under sixty-five trees out of 198,625. Every one had the same shape — an
empty scientific half in front of DataSF's `::` separator — so every one rendered in the list with a
visible `:: ` prefix:

| what the reader saw | line 1 | line 2 |
| --- | --- | --- |
| the stub | `Arbutus 'Marina'` | `:: Arbutus 'Marina'` |
| the real species, in the same list | `Hybrid Strawberry Tree` | `Arbutus 'Marina'` |

Two rows, one plant, and the reader has no way to tell which to press. The second line is labelled
by position as the scientific name; `:: Arbutus 'Marina'` is not a scientific name, it is our
parser's failure quoted back at someone looking for a tree.

**The builder half went first, and it changed the size of this question.** `Tools/build_seed.py`'s
BOTANICAL/COMMON swap now reads a miscased genus and a quoted cultivar, so fifty-eight of those
sixty-five trees merged into the species they were always naming and seven duplicate rows left the
catalogue. **Five stub species and seven trees remain**, and they are the residue that cannot be
merged on form alone: `:: Magnolia`, `:: 9662`, `:: Chitalpatashkentensis`, `:: Magnolia Little Gem`,
`:: Podocarpus Gracilor`. Two of those five still shadow a real species (`Magnolia` and
`Podocarpus gracilor`). So canonicalisation alone does not close this, exactly as the ticket said.

---

## The ruling

**1 · The list does not offer a species whose name the ingest could not read.** Not a merge, not an
honest rendering — the row is not there.

**Merging is not the list's to do.** Where a merge is safe it has already happened, in the builder,
on evidence: the city wrote a name and the only thing wrong with it was case, or a cultivar in
quotes. The five that remain are unmergeable *because nothing in them says what they are* —
`Podocarpus Gracilor` is probably `Podocarpus gracilor` and `:: 9662` is probably a work-order
number, and "probably" is the word that disqualifies it. Asserting either from the client would be a
synonymy no source states, which is the judgment `QSPECIES_NAME_CORRECTIONS` already refuses to make
in the one place that has the whole corpus in front of it. A screen that has one query's worth of
rows is not better placed to make it.

**Rendering them honestly fails for E126's reason.** E126's principle is that a state a reader
cannot interpret is worse than one that is not drawn: a failed read that drew the cold-start screen
was "invisible by construction rather than ugly". A `:: ` prefix is the same defect facing the other
way — it is not invisible, it is *unreadable*, and it is unreadable in the one field a reader uses
to decide whether this is the tree they meant. There is no copy that fixes it, because the honest
sentence is "the city's record of this tree does not say what it is", and that is a sentence about
the seven trees, not about the species the reader was searching for.

**2 · The rule is applied in `SpeciesQueries.searchSQL()`, so it holds on both surfaces.** The same
read feeds the map's suggestion list and the add-tree species picker
(`SpeciesPickModel`). Filtering in `MapSuggestions.init(matches:)` would fix the dropdown and leave
the picker offering `:: 9662` as something to record a tree as — which is worse, because that one
writes. `MapSuggestionTests.typingDropsAList` asserts the one-read-two-surfaces invariant; this
ruling keeps it.

**3 · The predicate is the name's shape, and the fact it stands for is asserted beside the seed.**
The exact statement of "the ingest could not read this" is `species_map.is_stub`. It is not what the
query asks, and the reason is measured: `species_map` carries no index on `species_id`, so a
correlated `EXISTS` over it is a scan per candidate row, and it fails
`SpeciesSearchTests.searchStaysOnItsCoveringIndexes`. Adding that index would change
`Fixtures/seed/schema.sql`, and the per-city files already published at seed schema 14 would not
have it — the gate would pass against the bundled seed and the scan would happen against a
downloaded city.

So the query filters on `scientific_name NOT LIKE ':: %'`, and
`SeedStubNamingTests.theMarkerAndTheProvenanceFlagAgree` proves that the marker and `is_stub` select
the same rows in the seed as built. That is what makes the cheap predicate a statement rather than a
guess about the shape of the data, and it is what will fail — loudly, next to the seed — if a future
ingest ever mints a stub that does not carry the marker.

**4 · The seven trees keep their pins.** This is a rule about a *name list*, not about the map. The
trees are still on screen 01, still tappable, still openable; what a reader cannot do is arrive at
them by typing a name, and there was never a name to type.

---

## What this does not settle

**The corpus holds the same plant under several spellings, and #103 does not touch it.** `Arbutus
'Marina'`, `Arbutus marina` and `Arbutus ‘Marina’` — straight quotes, no quotes, typographic quotes
— are three species rows for one plant, and there are more like them (`Platanus acerifolia
'Columbia'`, `Platanus x acerifolia 'Columbia'`, `Platanus x hispanica 'Columbia'`, `Platanus
hispanica 'columbia'`). The suggestion list shows them all, and a reader typing `marina` still sees
duplicates. That is the ticket's "one species appears twice" complaint in its general form; the
stub half of it is fixed here, and the rest is a synonymy question with no source behind it.
Recorded in `docs/errata-pending/seed-rebuild-drift.md`, not fixed.

**The species page is out of scope and still renders the raw name.** A tree whose species is
`:: Magnolia` shows that string wherever the species name is drawn. It is seven trees, and the fix
is not a filter — you cannot omit a tree's own species from its own page — so it wants its own
ticket and probably its own sentence of copy.
