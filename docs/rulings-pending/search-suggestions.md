### R25 — screen 01's search bar drops a list of species, and the list says what it is a page of (task #109)

*To be appended to `docs/RULINGS.md`. Written to a per-task file per ARCHITECTURE §7 — every agent
appends to `RULINGS.md` and every merge conflicts.*

---

**What was already specified, quoted rather than summarised.** `SCREENS.md` §2 draws C20 as a pill
with a leading magnifier, a placeholder and nothing else. Screen 01 lists the bar at `top:68px` as
item 11 of its structure, says of its behaviour only that "search opens species/street/neighborhood
search", and then, three lines later under **States/variants**, says:

> **NOT SPECIFIED:** search results, zoom controls, empty/no-GPS state.

So screen 01 specifies that the bar searches species and specifies **nothing whatever** about what
comes back — no list, no rows, no dropdown, at any text size. DECISIONS constraint 21 says stop rather
than invent one. This is that stop, answered under the standing delegation.

**The finding, which is one sentence from the owner.** *"I think it should surface drop downs with
species (as you type)."* What the bar did instead: typing narrowed the map in place and drew a status
line under the chips (E134, and `MapSearch` argues at length why there is no results *screen*). A
person typing `cypr` got a map that changed shape and no way to find out what it had changed to.

**Two rulings already stand on this control and neither is disturbed.** R16 (task #110) gave C20 the
✕ and the `Done`; both are untouched, and the ✕ still clears without dismissing the keyboard. E165
(task #108) made the catalogue match a word anywhere in either name with a rank; no matching is
written here at all — the list is a second reading of the page that call already returns.

---

#### The ruling, in six parts

**1 · The list is in the flow between the bar and the filter chips, not an overlay over them.**

The obvious dropdown floats. Floating is wrong twice. An overlay leaves the chips underneath
*reachable* by an assistive technology while invisible to a sighted reader — the covered-but-hittable
failure `DeepLinkVoiceOverTests.testAModalIsolatesTheScreenBehindIt` exists to catch, arriving through
a different door. And it puts the rows somewhere other than immediately after the field in the element
tree, which is exactly where a VoiceOver reader who has just typed goes looking for them. In the flow,
the chips move down and stay real, and the swipe order is field → suggestions → chips → status line,
which is the order the words are in. `MapSuggestionUITests` asserts both halves: the chips move rather
than being covered, and they stay hittable.

**2 · Six rows, and the seventh thing on the list is a sentence about the rest.**

Not `MapSearch.speciesLimit`'s 100, which is the right number for narrowing a *map* — every extra
species there is another pin the reader might be hunting and nothing is read in a list. Not
`SpeciesPickModel.resultLimit`'s 25 either, which is the right number for a screen whose whole job is
the list and which may scroll as long as it likes. This list floats over the map that is answering the
question, so every row it adds hides some of the answer. Six two-line rows is about a third of the
display at the drawn size, which leaves the FAB, the tree card and the lower two thirds of the city
visible underneath. That was looked at on the running app, not reasoned about.

**3 · A page is not a total, and the list may not print a number nobody counted (E38).**

This is the part of the ticket most likely to be got wrong and it is the reason `Remainder` is a type
rather than a comment. E165 made the 100-species cap **routine**: `a` prefix-matched 97 species before
that change and *contains*-matched 555 after it. So the dropdown is a page of a page. Three states,
and the third is the whole point:

| state | when | what it says |
|---|---|---|
| `.none` | every match is on screen and the catalogue's answer was not itself a page | *nothing* — the list is the answer |
| `.exactly(n)` | more matched, and the catalogue counted them all | "Showing 6 of 21 matching species. Keep typing to narrow it." |
| `.atLeast(n)` | the catalogue returned a full page, so the total is unknown *and unknowable from here* | "Showing 6 of at least 100 matching species. Keep typing to narrow it." |

`atLeast` claims the weaker of the two available sentences for the same reason
`MapSearch.Narrowed.isTruncated` does one level up: "at least 100" is true when exactly 100 matched
**and** when 555 did, and the reverse is not. A caller that flattened the two cases into one would
print a total the app has never counted. The sentence names the way out — a list that says "there are
more" without saying how to see them has told the reader they are stuck.

**4 · No matches draws no list, because the sentence for that state already exists thirty points
below.**

E126 requires a surface with nothing on it to say why, and this obeys it by *not* adding a second
voice. `MapSearchCopy.status` has printed `No species matches “sycamore”` since E134, in a line that
is on screen for exactly this state and no other. A no-match row in the list as well would put two
spellings of one sentence on one screen and leave the reader working out whether they were being told
two things. The unit suite pins the two halves together in one test, so an empty list is only ever
acceptable while that line exists.

**5 · A row is two names and nothing else.**

Common name in the serif list face, scientific name in the italic serif beneath — the same pairing
`SpeciesPickView`'s row and `SpeciesTile` already draw, so a species looks like a species everywhere
in this app rather than looking like a search result here. A species with no common name (59 of the
seeded 569 have none, E9) shows its scientific name once, on the first line, and no dangling comma in
the VoiceOver label.

Two things were considered and refused. **A thumbnail:** C22's gradient is derived from the name
rather than photographed, so it would add four colours over a map whose own species palette is already
four colours, for no information. **A count of trees:** a per-species count is a read of a
195,309-row table on the typing path, which `TreeQueries` forbids outright — and a count of what is
*in view* is not the same number as a count of what is in the city, which is E38 again, one row
further down.

**6 · At accessibility sizes the list keeps a share of the display and scrolls; it does not shrink.**

At AX5 a row is a wrapped paragraph rather than two lines, so six of them are more than the whole
display. The list takes at most **half** the height it was given and scrolls inside that — R14's
answer on screen 04 and R22's on the add screen, applied a third time and for the third different
reason. Dropping to fewer rows at large sizes was refused: the reader who most needs the names spelled
out would get the fewest of them, and the remainder sentence would then have to count *two* different
truncations. The cap is a `ScrollView`'s `maxHeight` and deliberately **not** `.clipped()`, which has
clipped drawing without clipping touches on this project before and left a control reporting
`isHittable` while answering nobody.

---

#### What choosing a row does, and why it is the opposite of the ✕

Tapping a suggestion pins the map to **that one species**, writes that species' name into the field,
closes the list, and **dismisses the keyboard**.

The pinning is the ticket's own sentence — "tapping one selects that species rather than leaving the
raw typed string in place" — and it is not cosmetic. Typing `cypress` narrows to the six species whose
names contain the word (E165). Picking `Monterey Cypress` off the list is a statement about one of
those six, and the map must stop showing the other five. The species set is therefore pinned rather
than re-derived from the field's new text, which would resolve `Monterey Cypress` back through the
catalogue and could pick up anything else containing the phrase. A subsequent keystroke releases the
pin, because at that moment the field no longer names the chosen species and a map still claiming it
would be saying something the field contradicts.

The keyboard is the deliberate contrast with R16. The ✕ clears and **keeps** focus, because clearing
is the start of the next query far more often than it is the end of searching. Choosing is the
opposite act: the reader has said which tree they meant, and the thing they asked for is the map that
the keyboard is covering. So the same bar now has one control that keeps focus and one that gives it
up, and the rule that tells them apart is whether the act ends a query or begins one.

`SearchBar` gains an **optional** external focus binding for this, and R16's argument for owning the
`FocusState` internally is untouched: it is `nil` at three of the four call sites and they are
unchanged. Screen 01 is the one caller that has to *read* focus, because a dropdown belongs to the act
of typing and must go when the typing stops.

---

#### What a VoiceOver reader hears

A list that appears under a field is a classic trap — the rows are drawn, are visible, are hittable
with a finger, and are somewhere a swipe never reaches. Four properties, all asserted by a launched
app because SwiftUI builds no in-process accessibility tree (E116):

- the rows are **buttons**, immediately after the field, in the swipe order;
- each row is **one element carrying both names** — `Monterey Cypress, Hesperocyparis macrocarpa` —
  rather than two elements that make a reader swipe twice for one species and hear the latin name as
  an orphan;
- the list is a **container with its own label**, `6 species suggestions`, so a reader navigating by
  element is told a list arrived under the field they are still typing into;
- the E38 sentence is **inside that container**, so the reader who hears the rows hears what they are
  a page of in the same sweep, and so it scrolls with them rather than being the one thing that never
  moves.

---

#### What this overrules

Nothing. Screen 01 named search results as unspecified and this fills that hole; §2's C20 is untouched
— the magnifier, the pill, the fill, the border, the radius, the padding, the placeholder and R16's ✕
all stay exactly where they were. Whoever draws C20 next should draw the list into screen 01 as a
variant, at the drawn size and at AX5, so the next person inherits a spec rather than a precedent.

#### Deliberately not decided here

- **Whether the list should offer anything that is not a species.** The placeholder stopped promising
  street and neighbourhood search under E134 because the bar cannot do either, and both are
  `Tools/build_seed.py`'s work before they are the client's. When they arrive, a mixed list needs
  section headers and this ruling does not design them.
- **Whether choosing should also move the camera.** Picking `Monterey Cypress` in a viewport holding
  none of them currently narrows the map to nothing and says `No Monterey Cypress in view`, which is
  honest and is also a dead end. Offering to fly to the nearest one is a real feature with a real
  question behind it (nearest to the camera, or nearest to the reader?) and it is not this ticket.
- **Whether the debounce should be shorter for the list than for the map.** They share one 300 ms
  debounce today because they share one read, and a list that raced ahead of the map would offer rows
  for a narrowing that had not happened. If the list ever feels slow, the thing to measure is whether
  577 species can answer on a shorter debounce than 195,309 trees can — not whether to add a second
  query.
