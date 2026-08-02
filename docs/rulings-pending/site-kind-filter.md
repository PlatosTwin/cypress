# (pending) — Tree or empty planting site is a filter, and it lives in the drawer (task #179)

*Written under the delegated design authority for #179. No mock covers this control — ROADMAP §1
records that no mock covers the vacant-site state at all (DECISIONS constraint 21) — so this is the
mock. Everything in it is built from vocabulary the app already uses. Unnumbered by CLAUDE.md's
rule.*

## What this rules

The map can be narrowed to **sites with a tree** or to **empty planting sites**, from a control in
the `More filters` drawer. It is the third narrowing behind that control, after `Favorites` (R23.1)
and `Year` (#145).

## 1 · Why it is in the drawer and was never a candidate for the row

R38 fixed the visible row at one horizontally scrolling line — `Yours · In bloom · Needs care ·
More filters`, plus `Clear filters` — on the owner's directive: "one row for filters, that's it."
A fifth resting chip would reopen a question the owner has now closed twice (#145, #166).

R23.1 called the drawer an **extension point** rather than a drawer with one thing in it, and said
what arriving there should cost: "one case and two switch arms, and no view changes at all." This
ruling is the first test of that claim by a narrowing that was not in the row first, and the claim
held — `MapExtraFilter.siteKind`, its two arms, and one arm in `MapFilterChips.drawer`.

## 2 · A menu of three, not two toggle chips

The control is a `Menu` with `Tree or site` (clear), `Has a tree`, `Empty planting site` — the same
shape `Year` uses, for the same reasons R23.1 gives: a decade is a *value*, not a toggle, and the
system's platter is already a ≥44 pt target list, already Dynamic Type correct, already dismissible
by the gesture readers expect, and draws no SF Symbol (adding nothing to #130's five debts).

**Two toggle chips were considered and refused.** The arms are exclusive by construction — every row
is one or the other — so a pair of toggles would offer a both-on state and a both-off state that
both mean "the un-narrowed map", which is a control whose selected state is indistinguishable from
its resting state. That is the exact argument R23 used to stop `All` being a chip, and the argument
R23 §1 used to make `membership` single-select within itself.

## 3 · The words, none of which are invented

DECISIONS constraint 15 forbids inventing civic or botanical content. Nothing here is invented:

- **`Site`** is the control's name. It is E107's own screen title for this record.
- **`Empty planting site`** — `SegmentedControl` already says `Vacant site`, E107's screen says
  `No tree at this site.`, and `MapPin` speaks `Planting site, no tree`. "Empty planting site" is
  the register of those three in a chip.
- **`Has a tree`** — the plain complement, phrased as an answer to "what is here" so the chip reads
  as a sentence: `Site: Has a tree`, `Site: Empty planting site`. That is `Year: 2010s`'s grammar,
  so the drawer's two value-carrying controls speak alike.

**There is deliberately no sentence anywhere in this control.** R41 forbids one, and a filter that
had to explain itself in prose beside the map would be task #180 arriving through a new door.

## 4 · Where the boundary between the two arms is drawn

`MapSiteKind.of(TreeStatus)`, an exhaustive switch beside the status — the shape
`TreeStatus.acceptsNewContributions` uses, so that adding a status is a compile error rather than a
silent assignment to one arm (E95).

- `vacant_site` → **empty site**
- `alive`, `declining`, `dead_reported`, **`removed`** → **has a tree**

`removed` is the one arm worth arguing, and it goes with the trees. A removed tree is a *memorial*
record (`TreeStatus.isMemorial`, DECISIONS §3.17) — a tree the app knows about and can still show
you — and **R7 reserves the vacant-site presentation for a basin that never had one**. Folding
memorials into "empty planting site" would put them behind a label promising no tree was ever here
and would collide with R7 on the pin. So the binary is literally the one the seed draws.

The shipped seed carries only `alive` and `vacant_site`, so the other three arms are decisions about
data that does not exist yet, taken once and in the open rather than left to whoever adds the data.

## 5 · What it composes with, including the contradiction it makes reachable

It is a term in the conjunction like every other dimension (R23 §1). Nothing is special-cased.

That makes one contradiction reachable: **`Empty planting site` + a decade returns nothing**, because
task #178 excludes vacant sites from a year narrowing. This is correct and is left alone. The
alternative — having one dimension clear the other — is the single-select behaviour R23 §1 was
written against, and it would silently discard an instruction the reader gave.

The map empties and says nothing, which is what the task #165 correction to R31 requires ("if
nothing matches, fine") and what R41 requires. The way out is the `Clear filters` chip, which is on
screen whenever any dimension is set, including one set behind the shut drawer (R23.1 §3).

## 6 · Why this had to ship with #178 rather than after it

#178 removes 9,237 vacant planting sites from the year filter's answers. Those rows are, per
ROADMAP §1, "the single best answer to 'where could a tree go'" and E115 established that hiding
them is a status claim the app is not entitled to make. Shipping #178 alone would take away the one
way they were (accidentally, and dishonestly) findable and put nothing back. This control is what
makes #178 a correction rather than a disappearance.

## What holds it

`CypressTests/MapFilterTests` — the two arms return only their own rows (parameterized over both,
read back from the seed by `trees.status` in an independent query), the empty-site arm actually
draws vacant sites, and the year/site contradiction returns nothing rather than letting one term
win. Red-proofed by inverting `MapSiteKind.statuses`, which reddens all three.

`extraFiltersAreDrivenByTheirOwnCases` already existed and required a new arm to compile — R23.1's
extension point catching its first new narrowing, exactly as designed.
