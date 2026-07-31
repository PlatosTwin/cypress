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

#### What was checked on the running app, because a green suite has said nothing about a screen before

MUTATION_AND_SCREENSHOT_SECTION

---

#### What this did not change

`SearchBar`'s ✕ and `Done` (R16) are untouched, and the ✕ still clears without dismissing the
keyboard — choosing a suggestion does dismiss it, and R25 records the rule that tells the two apart.
The matching itself (E165) is untouched: no query was written for this. The placeholder still says
species and only species (E134). No schema migration; nothing under `Data/` changed at all.
