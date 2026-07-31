### E177 — The search bar answered with a map and never said what it had understood (task #109)

*To be appended to `docs/ERRATA.md`. Written to a per-task file per ARCHITECTURE §7 — two agents
appending to `ERRATA.md` take the same number, and this round has three of them.*

---

The project owner, walking screen 01: *"I think it should surface drop downs with species (as you
type)."*

**What the bar did.** Typing narrowed the map in place and drew a status line under the filter chips.
That much was E134's work and it is right: the map is the result, and there is no results *screen*
behind C20 (`MapSearch` argues it at length). What was missing is the step before the result — the
bar never said **what it had understood the query to mean**. A person typing `cypr` got a map that
changed shape and no way to find out what it had changed *to*, and the status line's own vocabulary
admits it: `Showing the 6 matching species` names a count where the reader wanted six names.

The defect is worst exactly where E165 made the search best. Since task #108 the catalogue matches a
word anywhere in either name, so `cypress` resolves to the genus *and* Monterey, Italian, Leyland,
Hinoki and Montezuma Cypress. That is the fix the owner asked for; it also means a query now routinely
means six different things at once, and the map draws all six as identically coloured dots. The
narrowing got broader and the explanation did not.

**Fixed** by dropping a list of species under the bar as you type: common name in the serif list face,
scientific name in the italic serif beneath, and tapping one narrows the map to **that species** and
puts its name in the field rather than leaving the typed fragment there. `SCREENS.md` 01 lists "search
results" among the surfaces it does not specify, so the design is delegated under DECISIONS constraint
21 and is recorded as ruling **R25** — including the parts that are decisions rather than drawings:
what a row does *not* show, what the list does when nothing matches, what it does at AX5, and what a
VoiceOver reader hears.

---

#### The way this ticket was most likely to go wrong, and the type that stops it

**E38: a page is not a total.** E165 made the 100-species cap **routine** rather than exotic — `a`
prefix-matched 97 species before that change and *contains*-matched 555 after it, and
`MapSearch.Narrowed.isTruncated` exists to carry that fact. A dropdown shows a handful of rows, so it
is a page of a page, and six rows of five hundred and fifty-five matches drawn with nothing saying so
is precisely the defect E38 names.

So the remainder is modelled rather than described. `MapSuggestions.Remainder` has three cases and the
third is the whole point:

| case | when | the sentence |
|---|---|---|
| `.none` | every match is on screen and the catalogue's answer was not itself a page | *nothing* |
| `.exactly(n)` | more matched; the catalogue counted them all | `Showing 6 of 21 matching species. Keep typing to narrow it.` |
| `.atLeast(n)` | the catalogue returned a full page, so the total is unknown | `Showing 6 of at least 100 matching species. Keep typing to narrow it.` |

`atLeast` claims the weaker of the two available sentences, for the same reason `isTruncated` does one
level up: "at least 100" is true when exactly 100 matched *and* when 555 did, and the reverse is not.
Nothing in the app can count the rest without reading the whole species table on the typing path.

**One read, two surfaces.** The list and the narrowing are two readings of the same
`searchSpecies(query:limit:)` answer, so the dropdown can never offer a species the map is not
narrowed to. A second query at a second limit would eventually allow exactly that, and nothing else in
the suite would notice, which is why `typingDropsAList` asserts the containment rather than the rows.

---

#### Two defects the suite could not see, both found by typing into the running app

**1 · The E38 sentence was below the fold, which is E38's own defect one level down.** The remainder
line began as the last row of the scrolling list, on the reasoning that a VoiceOver reader who hears
the rows should hear what they are a page of in the same sweep. Typed into the running app, `a` drew
six rows, filled the height cap exactly, and left `Showing 6 of at least 100 matching species` where
nobody would find it. Every test stayed green, including the XCUITest that asserts the sentence
exists — `XCUIElement.exists` is true for an element inside a scroll view whether or not any part of
it is on screen, which is exactly the gap between "the app says it" and "the app says it to somebody".
The sentence is now pinned under the scroll and inside the accessibility container: one sweep for
VoiceOver, and never scrollable away.

**2 · At AX5 the FAB drew on top of that sentence.** Screen 01's chrome is two absolutely positioned
blocks and the bottom one — recentre, FAB, tree card — was applied *after* the top one, so it won every
overlap. At the drawn size the two never overlap and nobody had noticed in the year the screen has
existed. At AX5 with the list open, `What tree is this?` sat squarely across the middle of the
sentence: `Showing 6 of at least 100 match……. Keep ty…… it.` The blocks are now applied in the other
order. Nothing inside either of them moved, and nothing else on screen 01 changed position at any
size.

**A third thing, in the tests rather than the app, and it is #101 and #104's mistake again.** The
first XCUITest draft matched the row label `Monterey Cypress, Hesperocyparis macrocarpa`, copied out of
`SCREENS.md` 02. The seed spells that species `Cupressus macrocarpa`. Three tests went red reporting
`typing “cypress” drew no suggestions` — a sentence about the dropdown being broken that was in fact a
sentence about the mock. The row's real claim is structural (a common name, a comma, a second name),
which is provable without knowing *which* second name, so the tests now match a prefix and assert
something follows it.

#### Proving the tests can fail

Three one-line mutations to production code, run against `MapSuggestionTests` and
`MapSuggestionUITests`, restored afterwards.

| # | mutation | file |
|---|---|---|
| 1 | `remainder = .atLeast(hidden)` → `.exactly(hidden)` | `MapSuggestions.swift` |
| 2 | `rowLabel` returns `name(species)` only | `MapSuggestions.swift` |
| 3 | `applySearch(MapSearch(query: searchText, matches: [species]))` deleted from `chooseSuggestion` | `MapModel.swift` |

**The unit suite — 4 of 14 red, 8 issues:**

```
✘ Test "a full page from the catalogue is reported as a floor, never as a total" recorded an issue
  at MapSuggestionTests.swift:108:9: Expectation failed:
  (listing.remainder → .exactly(94)) == (.atLeast(MapSearch.speciesLimit - MapSuggestions.rowLimit) → .atLeast(94))
✘ … at MapSuggestionTests.swift:113:9: Expectation failed:
  (sentence → "Showing 6 of 100 matching species. Keep typing to narrow it.")
    == "Showing 6 of at least 100 matching species. Keep typing to narrow it."
✘ … at MapSuggestionTests.swift:119:9: Expectation failed:
  (sentence → "Showing 6 of 100 matching species. Keep typing to narrow it.").contains("at least")
✘ Test "one letter against the real catalogue is a page, and the list says it is" recorded an issue
  at MapSuggestionTests.swift:241:9: Expectation failed:
  (listing.remainder → .exactly(94)) == (… → .atLeast(94))
✘ Test "a row names both names, and a species with only one name says only that one" recorded an issue
  at MapSuggestionTests.swift:146:9: Expectation failed:
  (MapSuggestionCopy.rowLabel(both) → "Monterey Cypress") == "Monterey Cypress, Hesperocyparis macrocarpa"
✘ Test "choosing a suggestion narrows the map to that one species and puts its name in the field"
  recorded an issue at MapSuggestionTests.swift:286:9: Expectation failed:
  (after.speciesIDs → [D64A2DCB…, 5D2F9A2D…, F909A9EE…, 9846C997…, 04E62989…, B2FFEE94…])
    == ([chosen.id] → [F909A9EE…])
✘ … at MapSuggestionTests.swift:299:9: the same six ids, after the debounce, so the pin had not merely
  arrived late
✘ Test run with 14 tests in 1 suite failed after 1.305 seconds with 8 issues.
```

The sixth is the ticket's own sentence stated as a failure: with the pinning removed, choosing
`Monterey Cypress` leaves the map on all six species whose names contain the word.

**The UI suite — 5 of 5 red:**

```
MapSuggestionUITests.swift:167: testAPageOfMatchesSaysItIsAPage : XCTAssertTrue failed - a query
  matching a full page of the catalogue drew six rows and said nothing about the other ninety-four
MapSuggestionUITests.swift:139: testChoosingARowPutsThatSpeciesInTheField : … drew no suggestions
MapSuggestionUITests.swift:219: testLeavingTheKeyboardClosesTheList : … drew no suggestions
testTheChipsUnderTheListAreNotCoveredButReachable  failed (27.953 seconds)
testTypingDropsRowsCarryingBothNames               failed (27.102 seconds)
```

Restored, the whole unit suite is green and all five UI tests pass.

---

#### What this did not change

`SearchBar`'s ✕ and `Done` (R16) are untouched, and the ✕ still clears without dismissing the
keyboard — choosing a suggestion does dismiss it, and R25 records the rule that tells the two apart.
The matching itself (E165) is untouched: no query was written for this. The placeholder still says
species and only species (E134). No schema migration; nothing under `Data/` changed at all.
