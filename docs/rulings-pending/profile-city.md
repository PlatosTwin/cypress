<!-- Written for #137. Append to docs/RULINGS.md as R28. Do not renumber. -->

### R28 — the tree profile asks the row which city it is from, and San Francisco's sentence does not run anywhere else (task #137)

Four decisions, taken together because they are one mistake seen four times: **San Francisco's name
had become the framework's, invisibly, by being the only one there had ever been.** This is R24's
finding one layer up, in copy rather than in an inference, and it is the same sentence that closes
R24: *a rule written over one city's vocabulary does not run against another's.*

---

**What was on screen.** On a San Jose tree, the profile said San Francisco four times — the subtitle's
source label (`SF city inventory`), the record card (`SF #167879`), the section header
(`WHAT SAN FRANCISCO HAS ON FILE`) and a sentence about how San Francisco records pruning — while
the provenance line **at the foot of the same section** read *"From the City of San Jose Street Tree
inventory, July 31, 2026."* and was correct. One screen, two answers, and the wrong one in the
larger type. E176 found it, filed it, and declined to fix it because generalizing a city's name
across five surfaces is a design decision rather than an ingest change. This is that decision.

**The machinery already existed and four call sites were not using it.** `InventorySource` resolves
per row through `LocalAPI.provenance(of:in:)` from `trees.inventory_source`, and its own
documentation already declared `name` to be "the phrase the app puts on screen". The profile's
subtitle was a `switch` over `TreeSource` with two string literals in it.

---

#### 1 · The source label names the row's inventory, in the same string the provenance line uses

`TreeProfilePresentation.provenance` returns `InventorySource.name` — byte for byte what
`CityRecordCopy.provenanceNote` puts at the bottom of the screen. That identity is the ruling, not a
convenience: the top of the profile and the bottom of it now read from one value, so they cannot
disagree again for any city, in any seed. There is no second derivation to drift.

**The fallback is city-neutral, not San Francisco.** A seed built before the `inventory_*` receipt
keys cannot say which inventory a row came from, but `source == .cityImport` still says it is a
municipal one — and that is the distinction SCREENS.md drew this element for, `city inventory`
against `community-added, unverified`. Naming a city the row cannot supply is the defect; naming the
category it can supply is not.

**Why not keep it short and city-neutral for everyone.** That was the other candidate: let the
subtitle say `city inventory` always and let the bottom line name which. It is tidier and it loses
something real. Under D16 the map is a merged national table, and *which city's inventory this row
is from* is a fact a reader wants at the top of the screen rather than 800 points below it. Dropping
it would be a regression dressed as a simplification.

#### 2 · The record number keeps the publisher's id and loses the city

`SF #167879` was doing two jobs and only one of them survives a second city.

**The number survives.** It is San Francisco's `TreeID` or San Jose's `FACILITYID` — different
columns, the same kind of thing, and the only string a reader can carry back to the city that issued
it. The card renders `#167879`.

**The prefix does not.** It named a city, and on 52,788 rows it named the wrong one. Nothing is lost
by dropping it: the card's label already reads `City record`, and *which* city is now stated twice
more on the same screen, both times from the row.

**It is not replaced by the qualified identity.** `us-ca-sj:167879` is R18's *identity* key, the
string the uuid5 is derived from, and it exists so two cities' numberings cannot collide in one
table. It is Cypress's namespacing, not San Jose's record number, and printing it would hand the
reader a slug that means nothing in the city's own asset system.

#### 3 · The header names the kind of source, and the section's own last line names which one

`What the city has on file`. **This is the one of the four that does not derive from the row, and
the reason is the type rather than the principle.** The header is a micro-label — uppercase mono
with letter-spacing — and the only value the row can honestly supply is the inventory's published
name, `City of San Jose Street Tree inventory`, 38 characters. Set in that face at that width it is
four wrapped lines of shouting above a two-card grid.

So the header states the category, which is true of every municipal inventory the merged table will
ever hold, and the provenance line **inside the same section** states which one, in full, with the
day it was read. A constant that is true everywhere is not the same defect as a constant that is
true in one city.

#### 4 · The pruning sentence is San Francisco's claim about San Francisco's columns, and it declines outside `sf`

`CityRecordPresentation.pruningNote(idSpace:)` returns nil for any id space but `sf`. Nil `idSpace`
keeps the sentence, matching `LandContext.inferred(from:idSpace:)` exactly — a seed built before the
column existed holds one city and the sentence is true of it.

**This is the part of the ticket most likely to be got wrong, and the wrong answer is a translation.**
The sentence is not a label. It is a specific, sourced claim: DataSF `tkzw-k3nq` has eighteen columns
and no pruning event, and SF Public Works' own layer carries `Prune_Status` and `Prune_Year` **at
keymap-grid grain**, which is what "records pruning by block, not by tree" reports (E143, #91).

San Jose's Street Tree layer publishes no pruning field at all. That is a **different** claim —
"this inventory records nothing about pruning" rather than "it records it at the wrong grain" — and
writing it would be Cypress stating what is and is not in another city's field list on the strength
of one adapter's column selection rather than the city's published metadata. R24's test is not "does
it return something sensible for the new source" but **"was this rule written from this publisher's
documentation"**, and for San Jose it was not.

**So a San Jose reader gets one fewer sentence, and that is the outcome rather than a gap to fill.**
The section is not empty for them — the cards draw and the provenance line draws — so the half of
E126 that governs is not "a surface with nothing on it must say why" but the temptation E126 and E9
both refuse: a plausible-looking stand-in for a fact the app does not have. Absence renders as
absence, and a default is the bug.

**What this does not decide.** Whether San Jose's inventory should get a pruning sentence of its own
once somebody reads the city's published field list, and where a per-inventory "what this source does
not record" fact would live if a third city needs a third sentence. The honest shape at that point is
a column on `inventories`, not a third branch here.

---

#### The mock pins this overruled, and why the departure was in scope

ARCHITECTURE §5 rule 8 makes departing from a drawn mock a decision rather than a commit. The owner
gave the go-ahead for the departure and did not pre-decide the wording; the wording is above and the
pins are updated in place, each with the reason beside it.

| pinned where | drawn | now | why |
|---|---|---|---|
| SCREENS.md 14 §3 | `Lophostemon confertus · SF city inventory` | `… · City of San Jose Street Tree inventory` on a San Jose row | the mock was drawn when the seed held one city |
| SCREENS.md 03 §5, 14 §5, 19 §6 | `SF #114-88`, `SF #201-33`, `SF #088-21` | `#114-88`, `#201-33`, `#088-21` | the prefix named a city; the number is the publisher's |
| SCREENS.md §1 type sample | `DBH 64 cm · taped · SF #114-88` | annotated, sample left as drawn | it is a *typography* sample, not a screen |
| `SiteTests.identityLeadsWithTheAddress` | `Vacant planting site · SF city inventory` | `Vacant planting site · city inventory` | the fixture carries no inventory to name |
| `MemorialPresentationTests` | `SF #088-21` | `#088-21` | as above |
| `TreePlacementTests` | `line.contains("SF city inventory")` | the city-neutral fallback, **and no `SF` anywhere in the line** | the assertion now bites in the direction of the defect |

The **section header** and the **pruning sentence** were pinned only by this repo's own tests and doc
comments, not by SCREENS.md, because §9b is NOT SPECIFIED and always has been (E145).

**`mocks/cypress-mocks.html` is not edited.** It is the drawing, and a drawing is a record of what
was drawn. SCREENS.md is where the departure is recorded, because SCREENS.md is what the contract
calls visual truth.

---

#### The same two literals on screens 14 and 19, fixed with the same one derivation

`SitePresentation` and `MemorialPresentation` each carried their own copy of `SF city inventory` and
`SF #<ref>`. The vacant-site screen is not a hypothetical: **11,787 of the shipped seed's vacant
planting sites are San Jose's**, and that screen's own provenance line was already correct, so it had
the identical top-and-bottom contradiction. Both now call `CityRecordCopy.recordSource` and
`CityRecordCopy.recordNumber`. One string, three screens — a memorial cannot start naming a city the
other two have stopped naming.
