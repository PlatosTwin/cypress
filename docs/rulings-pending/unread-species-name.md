### R?? — A name the ingest could not read is not drawn as a name, and one sentence says whose word it is (task #185, delegated)

*Written under the delegated design authority for #185. `RULINGS R47` named this ticket as what it
deliberately left open, so this is the half of #103 that a filter could not reach.*

*Unnumbered. Written from a branch; the orchestrator splices it under the real next number at merge
and rewrites the citations in `Cypress/Core/Models/Species.swift`,
`Cypress/Data/Store/SpeciesQueries.swift`, `Cypress/Features/Species/SpeciesPresentation.swift`,
`Cypress/Features/Species/SpeciesView.swift`,
`Cypress/Features/TreeProfile/TreeProfilePresentation.swift`,
`Cypress/Features/TreeProfile/TreeProfileView.swift`,
`Cypress/Features/Memorial/MemorialPresentation.swift`, `Cypress/Features/Map/MapModel.swift`,
`Cypress/Features/Visit/VisitShortlist.swift` and `CypressTests/UnreadSpeciesNameTests.swift`.*

---

**What was delegated.** R47 removed the five unreadable species from the suggestion list and the
add-tree picker, on E126's principle that a row a reader cannot interpret is worse than a row that
is not there, and it said in its own closing section what that fix could not do: *"you cannot omit a
tree's own species from its own page."* So seven trees went on drawing `:: Magnolia` where their
species name is drawn. The fix is copy, and the delegation is where the copy goes and what it says.

---

#### The measurement, taken from the shipped seed and not from the ticket

Five species rows carry the marker, standing under seven trees out of 198,625. Every count below was
re-read from `Cypress/Resources/cypress-seed.sqlite` and is asserted in
`UnreadSpeciesNameTests.theCatalogueStillCarriesUnreadNames`, so a rebuild that moves them fails a
test rather than leaving this copy addressed to nobody.

| `scientific_name` | `common_name` | trees | where they stand |
| --- | --- | ---: | --- |
| `:: Magnolia` | `Magnolia` | 3 | 3555 20th St · 365 Bartlett St · 3310 25th St |
| `:: 9662` | `9662` | 1 | 110 GOUGH ST |
| `:: Chitalpatashkentensis` | `Chitalpatashkentensis` | 1 | 200 OCTAVIA ST |
| `:: Magnolia Little Gem` | `Magnolia Little Gem` | 1 | 446 Bartlett St |
| `:: Podocarpus Gracilor` | `Podocarpus Gracilor` | 1 | 36 REY ST |

All seven are `sf`, all `alive`, all `city_import`. `seed_meta.stub_rows` is `7`; every one has
`species_map.confidence = 0.3`.

#### The fact the ticket does not state, and it is the one the answer turns on

**`common_name` on these rows is sound. `scientific_name` is not.**

`Tools/inventory_adapters.py::parse_qspecies` reads DataSF's one-column convention
`Scientific name :: Common name`. When the scientific half is empty it returns
`("stub", s, common, 0.3)` — where `s` is **the whole raw string, separator and all**, and `common`
is the common half, unaltered. So on all five rows:

- `scientific_name` = `:: Magnolia` — the parser's leftovers, stored in a column that says "name".
- `common_name` = `Magnolia` — **what the city actually wrote**, verbatim.

That asymmetry is why this is not "hide the species". There is exactly one field to withhold and one
field to quote, and the sentence is what turns the second into a quotation instead of a claim.

It also survives the ugly case. `:: 9662`'s wording is `9662` — and the tree it stands over is
DataSF `TreeID` 9662, which the profile draws two blocks lower as `CITY RECORD #9662`. The city
pasted a record number into a species cell. A reader can see that for themselves once the screen
says where the word came from; they could not before.

---

#### The ruling

**1 · No surface in the app prints a scientific name the ingest never read.**

`Species.scientificNameIsUnread` in `Core`, off `Species.unreadScientificNameMarker`, which
`SpeciesQueries.stubNameMarker` now reads rather than restating — the SQL filter R47 installed and
the screens this ruling changes must be filtering on one string or they will drift. Applied at every
site that draws the value **as** a scientific name: 07's hero Latin line, 03/14's subtitle, the
memorial subtitle, the map card's meta line, and the visit shortlist's second line.

Not applied to the three fallback chains that would print it as a *display name of last resort*
(`VisitCandidate.displayName`, `SitePresentation.neighbourTitle`, `VisitAddTreeCopy.candidateName`).
Those are unreachable for a stub: `parse_qspecies` classifies `:: <nothing>` as a placeholder rather
than a stub, so a stub always has a common half to reach first. Left alone deliberately — a guard on
an unreachable branch is a guard nothing can red-proof.

**2 · Where the line was, one sentence says whose word the name above it is. Both screens.**

The ticket asks where the copy goes and offers three answers. It goes on **both**, and the reason is
that the two screens have different subjects, not that hedging is safer.

- **03/14 · the tree profile.** `The city files this tree as “Magnolia” and its record gives no
  scientific name.` This is the screen a reader hits: a map pin, a card, a profile. It sits in the
  identity block directly under the subtitle, which is `speciesClaim`'s placement argument unchanged
  — the subtitle is where a species is *stated*, so the account of why its Latin half is missing
  belongs against it. In the app's own voice, not as a `city record` card: it is a sentence *about*
  the record, and the badge would attribute Cypress's reading of the column to San Francisco
  (`landContextNote`'s argument, one block up).
- **07 · the species page.** `“Magnolia” is the city's own wording. The record it comes from gives
  no scientific name.` Reachable from a grove tile once somebody has met one of the seven trees.
  It draws immediately under the hero, in the reading order the missing Latin line held.

**Two strings and not one shared constant.** 03 has a tree in front of it and can say *this tree*.
07 has a wording standing over one record or three, and can say neither *this tree* nor *these
trees* without counting — so its sentence is written about the wording, which is number-neutral and
is what the reader is looking at anyway.

**`files … as` and not `calls` or `names`.** One of the five wordings is a work-order number. A verb
of naming would make the sentence assert that `9662` is this tree's name; a verb of filing describes
what a municipal inventory did with a cell, which is all that is known, and it holds for `9662` and
for `Magnolia` alike. It borrows the grammar of `CityRecordCopy.plantTypeLabel` — `City lists this
as` — because the app already has one voice for reading a city column out without adopting it. The
typographic quotes are load-bearing rather than decorative: they are what marks the word as somebody
else's.

**3 · Dropping the line in silence was considered and refused.** Every other species draws three
hero lines and these would draw two, with nothing saying which fact went missing. That is E126's own
defect wearing better manners — an unreadable state replaced by an uninterpretable one — and it
leaves `9662` standing as the least readable string on the screen with no account of where it came
from. E126 requires an emptied surface to say why.

**4 · Nothing here guesses at the taxon.** `:: Podocarpus Gracilor` is probably *Podocarpus
gracilor* and `:: Chitalpatashkentensis` is probably *Chitalpa tashkentensis* — the seed carries
`Chitalpa tashkentensis 'Pink Dawn'` two rows away — and neither screen says so. That is the
synonymy R47 refused, from a client holding one query's worth of rows, and DECISIONS constraint 15
forbids it outright.

**5 · Two preview surfaces withhold the name and get no sentence, and that is the same ruling and
not an exception to it.** `MapTreeCard.meta` and the visit shortlist's second line are `·`-joined
previews that already drop any clause they have no fact for — no species, no fix, no visit. A
dropped clause there reads as every other absence on the same line, and the profile each opens is
one tap away carrying the whole account. E126 governs a *surface that has been emptied*; a preview
line that is one clause shorter has not been emptied.

**6 · The seven trees keep everything else.** Pins, profiles, photographs, check-ins, the count card
on 07 (`In this inventory · 3`) and the nearby list. This ruling withholds one string and adds one
sentence. R47 kept the pins and this keeps the rest.

---

#### What was looked at, running

Both screens on iPhone 16e `3A1F212D-…`, deep-linked through a temporary `DebugDeepLink` case that
was **removed before commit** (E126's own method).

- 03 over `8b95154d-…` (3555 20th St): `Magnolia` / *SF Public Works street tree inventory* / *The
  city files this tree as “Magnolia” and its record gives no scientific name.* / `Show me where this
  is`. The subtitle used to read `:: Magnolia · SF Public Works street tree inventory`.
- 03 over `98bc455f-…` (110 GOUGH ST): `9662`, the same sentence quoting `9662`, with `CITY RECORD
  #9662` in the grid below it.
- 07 over `31f44959-…`: `FIELD GUIDE` / `Magnolia`, no Latin line, the sentence under the hero, and
  `IN THIS INVENTORY · 3`.

---

#### What this does not settle

**The `Field guide` eyebrow still sits over a page that is not a field-guide entry.** Left as it is:
it is equally true of the 529 uncurated species that carry a name, a family and nothing else, and
changing it would be a decision about screen 07's identity rather than about these five rows.

**A stub with no `::` in it would slip the predicate.** `parse_qspecies` also mints a stub from a
source string carrying no separator at all, and that name has no prefix to test. None ship, and
`SeedStubNamingTests.theMarkerAndTheProvenanceFlagAgree` is what says so — it proves the marker and
`species_map.is_stub` select the same rows in the seed as built, and it is the test that will go red
if a future ingest ever mints one. The predicate is deliberately not widened to guess: a rule for
"does this string look like a name" is exactly what the ingest already tried and got wrong.

**The corpus still carries one plant under several spellings.** `Arbutus 'Marina'`, `Arbutus marina`
and `Arbutus ‘Marina’` are three rows for one tree, `ERRATA E208` records it, and the survey and the
ruling on it are `docs/rulings-pending/species-name-spellings.md` (task #184). Nothing here touches
it: those rows are readable names, and this is about a row that is not a name at all.
