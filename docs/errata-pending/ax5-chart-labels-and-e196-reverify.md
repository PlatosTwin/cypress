### E196's AX5 punch list, re-verified a third time — eight items still gone, and the ninth's other half found in the chart C23 draws

*Written unnumbered per CLAUDE.md; the orchestrator splices the real number at merge.*

#### The premise this round carried, and what it was worth

The brief carried E196's "Defects found at AX5 (find, don't fix)" — all nine items — as open work.
It is not open, and it has not been for two rounds: **E199** (tasks #171, #172) fixed them and
**E237** (task #228) re-verified every one against renders. The brief's own instruction was to
verify rather than assume, so each item was re-rendered on the current tree and looked at rather
than taken from either document.

That was worth doing, but not for the reason the brief expected. Eight items are gone and stay
gone. The ninth — §3, screen 11's overflow — is gone *as reported*, and re-reading its own renders
with the defect no longer in the way showed the same screen still breaking in a place neither E199
nor E237 looked: not the log rows both entries argued about, but the chart above them.

#### The instrument

`CypressTests/ScreenSweepShots` with `TEST_RUNNER_CYPRESS_SHOT_DIR` exported, iPhone 16 Pro Max
`DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`, worktree `cypress-wt-ax5b` at `d84b7fc`
(`origin/main`) — 235 PNGs, all mtimed inside the run that produced them, provenance read off the
log's own `CYPRESS-RUN:` header before any of them was believed. `VERIFY-OK: Test run with 16 tests
in 2 suites passed`. The sweep renders at 393 pt regardless of the device it runs on, so the
capture is the narrow phone, not this one.

#### Per-item verdicts, this round

| # | Item (E196) | Verdict | What was looked at |
|---|---|---|---|
| 1 | 02 identify, populated — overflow | **Gone** | `02-identify-light-ax5.png`: title, GPS chip, amber pill (3 lines), callout, footer all inside 393 pt |
| 2 | e02 denied notice — truncation | **Gone** | `e02-identify-denied-light-ax5.png`: no ellipsis; the sentence is cut only by the sweep's non-scrolling capture at the `ScrollView`'s own frame edge, as E199/E237 both record |
| 3 | 11 growth history — overflow | **Gone as reported; a different half of the same screen is live** — see below | `11-growth-history-{light,dark}-ax5.png` |
| 4 | 19 memorial — name column | **Gone** | `19-memorial-light-ax5.png`: `Judah Street` on its own full-width line under the badge |
| 5 | 10 share — action captions | **Gone** | `10-share-light-ax5.png`: `Messages` intact, one destination per row, full URL (the AX line-cap release) |
| 6 | 15 account ask — CTA | **Gone** | `15-account-ask-light-ax5.png`: `Continue with Google` on two lines, no ellipsis |
| 7 | 07 species — fact chips | **Gone** | `07-species-light-ax5.png`: `Cupressaceae`, `Evergreen`, one chip per row |
| 8 | 03/14 §9b — city-record grid | **Gone** | `c06-city-record-full-ramp-light-ax5.png`: `QuadActionRow` 2×2 with `Favorite`/`Care`/`Share`/`Report` whole, `StatGrid` one column, `#221277` whole, `DPW Maintained` and `A private party` breaking at their spaces |
| 9 | 09 placeholder / 18 subtitle | **Gone** (09 was already stale at E199's writing) | `09-care-log-light-ax5.png`: `Photo or note` wraps as a caption; `18-next-tree-light-ax5.png`: the mono subtitle wraps inside the gutter |

The serif titles that break mid-word in big type (`Grandmot / her / Cypress` on 03, 09, 10) are
E196's own last paragraph — the system wrapping without hyphenation, recorded so nobody re-reports
them as clipping. They are unchanged and are not a defect here either.

#### What is still broken: `LineChart`'s own labels at AX5 (screen 11)

E196 §3 named four symptoms on screen 11. Three are gone (the name pill, the back circle, the log
rows E199 fixed with `ViewThatFits`). The fourth — "the unit labels at the left (`7 cm`, `4 m` —
the leading digits are gone)" — is a survivor that had changed shape enough to read as fixed. E237
looked at it and recorded "the leading unit-label digits (`47 cm`, `14 m`) are intact", which is
true: both digits render. What neither entry asked was **where** they render.

Two defects, both visible in the light and dark AX5 renders of screen 11, both in
`Cypress/DesignSystem/Components/ChartCard.swift`, and both measured before being believed:

1. **The baseline label is drawn outside the card.** `LineChart.labels(scale:)` places it with
   `.position`, which centers it, at `chartGridlineX0 * scale + 16` — 25.97 pt from the plot's
   leading edge on a 393 pt phone. At AX5 the label measures **111 pt** wide, so it spans
   −29.5 … 81.5 pt: past the plot's leading edge by 29.5 pt, and past the card's own 16 pt of
   padding by **13.5 pt**, where it is drawn over the page behind the card. The dark render is the
   unambiguous one — `47 cm` sits on the page background, left of the card's rounded corner.
2. **The year axis wraps mid-number.** The four labels need **356 pt** unclamped against the
   **329 pt** the plot has, so the row wraps: `2019` renders as `201` over `9` and `2021` as `202`
   over `1`, while `2023` and `2025` collide with no gap between them. A year reading as two
   numbers is exactly the fragmentation E196 §8 named on the city record (`#22127 / 7`), one
   component over.

Neither is reachable by a width probe on the screen. `.position` draws outside its own frame
without changing the size anything reports — the same blindness that made E199 delete its screen-11
width guard as unable to fail — and the axis row is clamped to the width it is given, so it wraps
instead of measuring wide. Only the renders, and a measurement of the labels against the budget
they are placed in, can see either.

#### The fix, and why it is not a new design decision

Both are **typographic furniture** in the sense `cypressTypographicFurniture()` already defines
(`CypressFont.swift`, and the four applications E-record'd at the AX sweep): things drawn as type
and read as structure, placed by a geometry that cannot reflow around them. The rule's own list
names "the twelve single letters under a month axis" — `ChartMonthAxis`, the sibling axis in this
same file, on the bar chart 40 lines below. The line chart's year axis is the same object with
four labels instead of twelve, and it was missed. The two in-plot value labels are the third case
on that list — C19's pin count, "positioned by coordinate on a map that cannot reflow around it" —
with the plot box in place of the map: its height is the mock's drawn 100 pt at every text size, by
the file's own header note.

So: `.cypressTypographicFurniture()` on the axis row, and on a new `ChartPlotLabel` that carries
the styling `latestLabel`/`baselineLabel` used to carry inline. The cap is `.accessibility1`, not
the drawn size — roughly double, which is the point of the cap being where it is.

**Nothing moves at or below AX1.** The sweep's drawn-size renders of both screens that use this
file (`11-growth-history-{light,dark}.png`, `13-activity-{light,dark}.png`) are **byte-identical**
before and after the change, MD5-compared across the two runs.

**That comparison is only sound because it was controlled, and the technique does not generalize —
read this before reusing it.** This PR's review produced an accidental same-tree control: a sweep run
that turned out not to have recompiled (`SwiftCompile tasks=0`, so the binary was unchanged) was
compared against another run of the same tree, and **23 of the 235 renders differed**. The sweep is
not byte-deterministic run to run. Byte-identity across a *widened* set would therefore report
differences that are noise, and a future round that MD5s the whole sweep will generate false
positives.

What makes the claim above safe is not MD5 by itself but the pairing: the four named files were
confirmed *individually* deterministic under the same-tree control, and screen 11's AX5 legs differ
under the change while staying stable under that control — so the delta is attributable to the change
rather than to the sweep. Any future use of this technique needs the control first, on exactly the
files it intends to compare. Note also which artifact supplied that control: a build that compiled
nothing is precisely what E203 makes `verify_test_log.sh --warnings` refuse to certify a warning count
from, and it was still the only thing that made this result trustworthy.

**One judgment call, flagged rather than buried.** Capping a *value* label is a stronger claim than
capping a divider: `47 cm` and `64` are content, not furniture, even though their placement is.
The argument for it is that neither number is only there — `LineChart.accessibilityLabel` speaks
both ends of every series, and screen 11's measurement log lists every reading, with its method and
date, at full scale directly below the chart. The alternative considered and not taken was dropping
the in-plot labels entirely at accessibility sizes, which removes a number from the screen rather
than capping its size. If the owner prefers that, it is a two-line change in the same place.

#### Tests, and their red-proofs

`CypressTests/AX5ReflowTests`, two guards, both measuring **through** `LineChart` and
`ChartPlotLabel` rather than through a copy of their styling — a probe that applied its own cap
would go on passing with the cap deleted from the component, which is the shape of guard this file
already threw away once.

- `theGrowthChartsYearAxisStaysOnOneLineAtAX5` — the chart with four year labels is no taller than
  the chart with one. Red with the cap removed from the axis row:
  `Expectation failed: (four → 195.0) == (one → 150.66666666666666)` / *"four year labels made the
  chart 195.0 pt tall against 150.66666666666666 pt for a single label — the axis row wrapped, and
  a wrapped year is two numbers"*. The other 13 tests passed in that run, so the guard fails for
  its own reason and not the file's.
- `theBaselineChartLabelStaysInsideItsCardAtAX5` — half the label's AX5 width fits between its
  center and the card's leading edge. Red with the cap removed from `ChartPlotLabel`:
  `Expectation failed: (measured.width / 2 → 55.5) <= (budget → 41.96969696969697)` / *"the
  baseline label measured 111.0 pt, so centered at 25.96969696969697 pt it reaches
  13.530303030303031 pt past the card's leading edge"* — the same 13.5 pt the dark render shows.

Both assertions were **calibrated before they were written**: a throwaway probe measured the label
widths at AX5 with and without the cap (111 → 57 pt for the baseline label, 89 → 45.7 pt per year)
and was deleted before the first commit. The budget in the second guard is "inside the card", not
"inside the plot", because the measurement showed the capped label still crosses the plot's leading
edge by 2.5 pt — an assertion written to the stricter number would have been red on the fix, which
is what the calibration was for.

#### What was not done

- **No production change for items 1–2 and 4–9.** They do not reproduce; there was nothing to fix.
- **The `.position`-centered `latestLabel` on the right edge has no guard.** Centered at
  `viewBox.width * scale - 14`, it would have to measure more than 28 pt to cross the plot's
  trailing edge and more than 60 pt to leave the card; capped it measures 25.3 pt, and *uncapped*
  it measured 45.7 pt — inside the card either way. A guard on it could not have failed against the
  unfixed tree, so none was written (E199's own lesson about the screen-11 width test).
