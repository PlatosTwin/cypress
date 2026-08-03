### R?? — `This season` is a heading over three clocks, and the note says so (task #177)

*Written under the delegated design authority for #177, which covers this tooltip's wording and
where it lives. UNNUMBERED — the orchestrator splices the number at merge.*

---

## First: R41 does not reach this, and that was checked before anything was written

R41 forbids any message accompanying a **filter**, categorically, with three sanctioned channels
(R23.1: chip fill, a count on the chip, the spoken value) and no fourth. The brief was right to make
this a gate, so it is answered first.

**`This season` is not a filter.** It is a static micro-label — `AlmanacCopy.seasonLabel`, drawn by
`AlmanacView.seasonBlock` — over a block of up to three C10 rows on screen 12. There is no chip, no
selection, no toggle, no state, and nothing the reader can set. R41's own test is *"does text appear
because a filter did something?"*; nothing on this block responds to a filter, because the almanac
has none. E205 confirms the scope by showing what R41 actually reached: `MapFilterStatus`, a capsule
on the map glass under the chip row, which rendered *only* when `filter.isActive` or
`filter.decade != nil`.

The almanac already carries two permanent explanatory sentences that nobody has read R41 against —
`areaNote` (R29) and `outOfRangeBody` (E182) — because they explain a *surface*, not a narrowing.
This note is the third of that kind.

If a future reader disagrees: the test to apply is not "is there explanatory text on screen" but
"did a filter cause it". Nothing here did.

## What the heading is actually over

Read from the code that computes the rows, not from the heading and not from the ticket:

| row | what bounds it | is it "this season"? |
|---|---|---|
| **First bloom of the year** | `visits.captured_at >= AlmanacWindow.yearStart` — January 1 of the current calendar year | **No — year-to-date.** In December it is still March's sighting. Its own drawn title already says `of the year`. |
| **The elder** | `ORDER BY t.planted_on LIMIT 1` — **no window at all** | **No — nothing.** The same tree in January as in July, every year, until an older record arrives. |
| **Newest neighbors** | `t.planted_on BETWEEN` `AlmanacWindow.currentSpring` — March 1 to May 31 of the current year | **No — a fixed window.** It does not draw before March, and from June to December it keeps saying `planted this spring` about trees planted in the spring that ended. |

**So none of the three is scoped to the current season, and one of them is not scoped to time at
all.** The heading is the only thing on the block claiming a season.

That is the unflattering finding the brief anticipated, and the note says it rather than papering
over it.

## The ruling

**A one-line note under the micro-label, assembled from the rows that actually drew, naming each
row's own window and stating plainly that they differ.**

With all three rows present it reads:

> Each row keeps its own window: the first bloom is this year's earliest, the elder is the oldest on
> file in any season, and the newest neighbors were planted March to May.

### Why a line under the heading rather than a tap-to-reveal tooltip

The ticket said "tooltip"; where it lives was delegated. Three reasons for the line:

1. **The app has no tooltip idiom.** There is no popover, no info button, no disclosure control
   anywhere in `Cypress/DesignSystem/Components/`. Building one for this would be inventing UI for a
   screen whose states are already over-specified, and R43's discipline — build from the app's
   existing vocabulary — points the other way.
2. **The screen already does this exact job in this exact form.** `areaNote` is a muted sentence
   directly under the header saying which promise a pill is making, because "the pill alone is too
   quiet" (R29). This note is that argument applied one heading down, and it is drawn in `areaNote`'s
   type and colour (`CypressFont.body125`, `CypressColor.textMuted`) for that reason.
3. **The fact reframes rows the reader is looking at now.** A reader who believes `The elder` is a
   seasonal pick has already misread the block; hiding the correction behind a tap serves the reader
   who already suspected something was off, which is not the reader who needs it.

### Why it is assembled rather than written whole

`AlmanacCopy`'s own header rule: *"Every sentence with a number in it is assembled rather than
templated wholesale, so that the parts which are not true can be left out."* The note obeys it. A
clause about the bloom is never written when no bloom drew, and with one row the note states that
row's window and makes no claim about windows differing. It is `nil` exactly when `seasonRows` is
empty — the block does not draw then, and a note explaining three absent rows is the
heading-over-nothing defect with a sentence attached.

### The months come from the constant

`March to May` is read from `AlmanacWindow.springMonths` through the reader's calendar and locale,
not written out, so moving the window moves the sentence. The read and its description cannot drift.

## What this ruling does not do

- **It does not rename the heading.** `This season` is drawn verbatim in SCREENS.md 12 §2. Renaming
  a drawn micro-label is a mock departure, and #177's delegation covers the explanatory text, not
  the heading. **This is flagged deliberately: the honest conclusion of the analysis above is that
  the heading is a poor name for its contents, and a note is a smaller repair than a rename.** If
  the owner wants the heading itself reconsidered, the material is here and the change is one string.
- **It does not change any window.** Not the elder's absence of one, not the bloom's year-to-date
  bound, and not the March–May span that keeps drawing until December. Each is arguably worth its
  own ticket; none is copy, and #177 is a copy ticket.
- **It does not mention that the bloom row is computed from this device's contributions alone.**
  True, and material, but the `Almanac` type has a standing decision about it — the almanac "is
  honest but small until there is a server, and it says so by rendering nothing rather than by
  apologising." Adding an apology here would reverse that decision on one block. Considered and
  excluded, recorded so it is not re-opened by accident.

## What holds it

Four tests in `CypressTests/AlmanacPresentationTests`, plus the note joining `renderedStrings` so
the suite's existing sweeps (no zeroes, nothing counting contributions) now cover it:

- `theSeasonNoteDrawsOnlyWithItsRows` — nil with no area and with no rows; present when a row drew.
- `theElderAloneIsNotDescribedAsSeasonal` — with only the elder, the note names neither spring month
  and does not mention the bloom. Asserted as *absence of the other rows' windows*, so a blanket
  "this season" claim cannot satisfy it.
- `theNoteAccountsForEveryDrawnRow` — all three subjects named, and the note states the windows differ.
- `thePlantingClauseTracksTheWindowConstant` — the clause names the months `AlmanacWindow.springMonths`
  actually bounds the read by.

Each was red-proofed, and one of the red-proofs found a real defect: read off a `Calendar` built by
identifier, `standaloneMonthSymbols` produced `M03 to M05`, because it reads the *calendar's* locale
and such a calendar carries none. The note now takes the reader's locale as its own parameter, as
every other sentence in `AlmanacCopy` already did.
