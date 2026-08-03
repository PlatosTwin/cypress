### R?? — Screen 07's count card names the population it counted, and that population is not a city (task #181)

*Written under the delegated design authority for #181, which covers the copy on this card and
nothing wider. UNNUMBERED — the orchestrator splices the number at merge.*

---

## The reported defect is the smaller half of the real one

#181 reads: the species page hardcodes `In San Francisco` on its citywide count card, so it says San
Francisco to a reader standing in San Jose. That is true. It is also not the worst of it.

**The number under that label was never San Francisco's.** `SpeciesQueries.cityTreeCount` carries no
id-space predicate — it is `COUNT(*)` over every standing tree of the species in the attached
inventory — and the shipped bundle is fused across two id spaces (`sf`, 145,837 trees; `us-ca-sj`,
52,788). Measured on the shipped seed, on species that stand in both:

| species | San Francisco | San Jose | the card printed |
|---|---:|---:|---:|
| Crape Myrtle | 97 | 3,649 | `In San Francisco · 3,746` |
| Chinese Pistache | 431 | 2,026 | `In San Francisco · 2,457` |
| Ornamental Pear | 2,160 | 1,344 | `In San Francisco · 3,504` |
| Southern Magnolia | 5,115 | 983 | `In San Francisco · 6,098` |

A San Francisco reader looking up Crape Myrtle was told their city holds 3,746 of them. It holds 97.
So the card was wrong for **every** reader, not only for the one standing in the second city.

## Why the obvious fix is refused

The naive repair — resolve the tree's city and say `In San Jose` to a San Jose reader — fails twice.

1. **It would put one city's name over a two-city number.** The count is not scoped by id space, so
   any single city name is a mislabel; swapping which city is mislabelled is not a fix. Scoping the
   count instead would be a different change with its own consequences, and it is not what the
   ticket asked for.
2. **There is no tree on this screen to ask.** `SpeciesModel` is constructed from a species id
   alone, entered from a grove tile, the search list or the map legend. R28's mechanism — the row
   states its own inventory through `LocalAPI.provenance(of:in:)` — has no row to run against here.
   This is the first member of the family where R28's answer is structurally unavailable, which is
   worth stating because the family's habit is to be fixed the same way each time.

## The ruling

**The label names the population that was actually counted: `In this inventory`.**

Under R43 exactly one inventory is attached at a time — the built-in fused bundle or one downloaded
city file — and every read on the screen is qualified against it. `inventory` is R43's own word for
that unit (`Built-in inventory`, "one inventory is attached at a time", `In use`), so this borrows
vocabulary the reader has already met in Cities rather than coining any.

The card is now exactly true in both configurations R43 permits:

- **built-in bundle** — the count spans San Francisco and San Jose, and the label claims neither;
- **a downloaded city file** — the count is that city's, and the label is still true of it.

**R28 §3 is the precedent and it is followed rather than extended.** Faced with a label too small to
carry an inventory's published name, R28 made the section header state the *category* — `What the
city has on file` — and let the provenance line inside the section name which one. Its reasoning
transfers unchanged: *"A constant that is true everywhere is not the same defect as a constant that
is true in one city."* `In this inventory` is that constant for this card.

## What this ruling does not do

- **It does not scope the count.** Adding `AND t.id_space = :space` would make the card a per-city
  number and is a different product question — which city, resolved how, on a screen with no row.
  If it is ever wanted, the honest shape is a scoped count *and* a label naming the scope, decided
  together. Noted, not taken.
- **It does not touch `Near you`.** That card was fixed by #141 and is scoped through
  `AlmanacScope`; its label is already city-neutral and its number already honest.
- **It does not rename the inventory anywhere else.** No shared identifier changed.

## The mock pin this overrules

ARCHITECTURE §5 rule 8 makes departing from a drawn mock a decision rather than a commit.

| pinned where | drawn | now | why |
|---|---|---|---|
| SCREENS.md 07 §5 | `In San Francisco` → `1,204` | `In this inventory` → `1,204` | the mock was drawn when the seed held one city, and the number it labels has never been one city's since |

`mocks/cypress-mocks.html` is not edited — it is the drawing, and a drawing is a record of what was
drawn (R28's rule).

## What holds it

`CypressTests/SecondCityGeographyTests.theCountCardNamesThePopulationItCounted` — the family's own
seed-backed suite. It resolves at runtime a species the seed holds in **both** id spaces, asserts
`cityTreeCount` equals the sum of the two (so the count provably spans two cities, which is what
makes any city name a lie), and then asserts the label contains none of `San Francisco`, `San Jose`,
`SF`, `DataSF`. Markers rather than a fixed string, so swapping one hardcoded city for another
cannot satisfy it.

Red-proofed by restoring `In San Francisco`:

> `Expectation failed: !((SpeciesCopy.cityCountLabel → "In San Francisco").contains(marker → "San Francisco") → true)`
