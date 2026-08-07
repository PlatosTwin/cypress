# A phenology observation was written, stored, read back — and never drawn anywhere

*Unnumbered — the orchestrator splices the real E-number at merge.*

## The report

Build 18 TestFlight feedback, pulled 2026-08-07 (see the ASC feedback triage in this same
directory): a tester circled screen 04's whole tray — the note field, the observed-state chips and
`Log visit` — and asked **"Where do leaf out full leaf flowering etc go?"**

Read literally it is a question about destination. The answer was: nowhere.

`visits.phenology_tags` has existed since `AppSchema`'s `visits` table, `ContributionStore`
writes it, `ContributionStore.decodeVisit` reads it back into `Visit.phenologyTags`, and
`TreeProfile.visits` carries it to the profile. `TreeProfilePresentation.activity` then built the
`Visit` row's detail from `visit.note` alone:

    detail: visit.note.map { " · “\($0)”" } ?? "",

So a contributor who tapped `Flowering` and logged the visit without writing a note got a C9 row
reading `Visit`, with a timestamp and nothing else. The record was complete and correct at every
layer below the one the contributor could see. This is the class of defect a green suite ratifies:
nothing was broken, a field was simply never read.

The one place any of it did surface is screen 13's `Spring flush noted` moment, which reads
`leaf_out` and only `leaf_out`, only in the current year, only when the visit series is complete,
and expresses it as a sentence about the tree rather than as the observation the contributor made.
Five of the six states reached no surface at all.

## Why the tree profile's activity feed, and why this is not constraint 21 territory

SCREENS 03 §8 draws two C9 rows:

| | label | detail |
| --- | --- | --- |
| 1 | `Visit` | ` · “Fog dripping off the crown”` |
| 2 | `Care` | ` · watered, mulched` |

The second row is the precedent, and it is exact. `watered, mulched` is not prose someone wrote —
it is the `CareAction` vocabulary rendered as a comma-joined lowercase list, which is what
`TreeProfilePresentation.careActionLabel` exists to produce. A C9 detail slot carrying a
contribution's structured vocabulary is a drawn pattern on this screen.

A visit's observed states are the same class of value, on the same feed, on the same kind of row,
about the same contribution. Rendering them there is the drawn pattern applied to a field the row
already had. No new screen, no new section, no new component, no new token, no new metric —
`ActivityRow` and `TreeProfileView.activityFeed` are untouched.

## The one judgment call, and what actually decided it

The mock never draws a row with **both** a note and a vocabulary list, so their order relative to
each other is not drawn. It is decided in `visitDetail(note:phenologyTags:)`, **note first**:

    Visit · “Fog dripping off the crown” · flowering      Oct 12
    Care  · watered, mulched                              Sep 28
    Visit · leaf out, fruiting                            Aug 30

**The mock is not silent about the note's own position.** SCREENS 03 §8 draws
`**Visit** · “Fog dripping off the crown”` — the note is placed, immediately after the label. So
while the pair's order is undrawn, the note's position is not, and constraint 21's spirit is not to
relocate what the mock draws in order to make room for what it does not. That is the reason, and it
is a reading of the spec rather than of a screenshot.

Two arguments were made for the reverse order and neither survived. Recording both, because the
first is the one this change's whole case rests on elsewhere and its limit matters:

- **Parallelism with `Care · watered, mulched` is weaker than it looks.** That row has no free text
  competing for the slot, so putting the vocabulary first there is not a choice between two
  orderings — it is the row's only content. The parallel this change rests on is about the detail
  slot's *shape*, and it does not extend to what shares the slot with it.
- **Line-breaking does not distinguish the two.** Whichever clause goes last can be widowed, so the
  wrap is symmetric and cannot pick a winner. An earlier draft of this entry claimed screenshots had
  settled it; they had not, and that claim is withdrawn.

There is also a values argument, and it belongs to the owner rather than to this branch: the note is
a volunteer's own sentence, and a civic app should not put machine vocabulary in front of a person's
own words. With no note at all — the tester's case, and the common one — the row reads
`Visit · flowering` either way round, so nothing is lost there.

A designer may overrule this by swapping two lines. It is decided in one place and the tests name it
as a decision rather than as a fact.

### The wrap artifact this order carries, stated plainly

Note-first can leave a ` · ` at the head of a wrapped line. It does so on the project's own preview
fixture — `TreeProfileSeedFixtures.visits[0]`, note `Fog dripping off the crown`, tag `flowering`,
rendered by `PhenologyOnProfileShots` at the sweep's fixed 393 pt width:

    Visit · “Fog dripping off the crown”
    · flowering                                           Oct 12

This is recorded because it is a **consequence** of the chosen order, not a reason for it — and
because a review of this change reported the opposite ("the ` · ` never landed at the head of a
wrapped line", across six specimens graded to walk the boundary). Both observations are correct: the
break has an opportunity on each side of the separator, so a one-character difference in where the
note ends decides whether the dot closes the earlier line or opens the next. The reviewer's
specimens fell one way and the fixture's own note falls the other, which is why "never" is too
strong. It is cosmetic, it is not a reason to move the clause the mock places, and anyone who meets
it later should find it written down here rather than think it was missed.

## What was deliberately not done

- **No new stage, no rename, no reorder.** The words are `PhenologyTagLabel`'s own chip copy
  lowercased, so what a contributor tapped is what they read back, and the six of them are pinned
  by value in `PhenologyStageVocabularyTests` (DECISIONS constraint 15). The reading order is
  `VisitPhenologyVocabulary.order` — the same array the *app's* screen-04 chip row is built from,
  `VisitCameraModel` through `VisitCameraView` — so no second ordering exists to drift from the
  first. A row reads the same however the chips were tapped.

- **The parallel with the care row stops at the detail slot's shape.** The `Care` row renders
  `event.actions` in **stored** order; this renders states canonically. Nothing shows today because
  the fixture's `[.watered, .mulched]` happens to match the mock. Two orderings for the same kind of
  value on the same feed is worth closing and is filed separately; deliberately not widened into
  here. (The neighboring `careActionLabel` is a second hand-written switch that does not derive from
  `CareActionLabel.text` — it prints `weeded` where the chip says `Weeded basin` — which is the same
  drift `phenologyTagLabel` avoids by deriving. Also filed, also not this change.)
- **No schema change.** Both version spaces are untouched. The column this reads has existed since
  `visits` was created and the decode already returned it.
- **The deeper product question is still open.** "What is a phenology observation *for* once
  recorded?" — aggregation across a tree's years, a species-level view, anything on screen 12 or 13
  beyond today's spring-flush sentence — is not answered here and was not meant to be. This makes
  the observation visible to the person who made it, on the tree they made it about.

## Two things found while checking, neither caused by this change

- **A premise worth correcting, and the correction's own first draft was wrong.** The triage names
  "the four phenology chips (`Leaf out`, `Full leaf`, `Flowering`, `Fruiting`)". The vocabulary is
  **six**, and the reduction to four is D5's evergreen exclusion — but the source of each number is
  not the mock, which is what an earlier draft of this entry said and had to be corrected in review:

  - **The six are `PRODUCT.md:128`** — `phenology_tag: leaf_out | full_leaf | fall_color | bare |
    flowering | fruiting` (BUILD-PLAN §4) — realized as `PhenologyTag`. A document, not a drawing.
  - **The four are `Species.availablePhenologyTags`** (`Cypress/Core/Models/Species.swift:267-275`),
    whose base set is exactly `{leafOut, fullLeaf, flowering, fruiting}` and which adds `fallColor`
    **and** `bare` unless the species is a *known* evergreen.
  - **SCREENS 04 draws neither.** It draws three chips — `New growth` (on), `Cones`, `Storm damage`
    (`SCREENS.md:804`, and `PROTOTYPE-FLOW.md:27` and `:270` verbatim). `Leaf out`, `Full leaf` and
    `Fruiting` appear nowhere in `SCREENS.md`, and `Flowering`'s only hits there are
    `Red Flowering Gum`. (Calibrated before believing it: the same case-insensitive grep finds
    `Fog dripping off the crown`, which is present, twice.)

  So the app's screen 04 and the mock's screen 04 do not offer the same chips at all. That is a
  separate discrepancy, older than this change and not touched by it. The lesson worth keeping is
  the narrower one: **a count of phenology states must be read from `PhenologyTag` or from
  `PRODUCT.md`, never from a mock** — including when the thing being written is itself a correction
  of somebody else's wrong premise.

- **C9 rows break mid-word at AX5, on the drawn row, before this change — and this change puts more
  rows into it.** The AX5 capture added here (`phen-03-profile-observations-light-ax5`) shows the
  mock's own untouched `Care · watered, mulched` rendering as `watere/d,` `mulch/ed`, and
  `Care · weeded` as `weede/d` — the fixed-width mono timestamp column keeps its width while the
  body's column collapses.

  The defect is not caused by this change and is not changed in kind by it. But it is worsened in
  reach, and understating that would misprice the ticket: **a visit tagged and left unwritten — the
  exact case this change exists for — rendered as a single clean `Visit` line before, and now
  renders `leaf`/`out,`/`fruitin`/`g` down four broken lines.** Rows that were not in the defect are
  now in it.

  It has gone unseen because **screen 03's own sweep entry does not pass `ax5ViewportHeight`**
  (`CypressTests/ScreenSweepShots.swift:245`), so its AX5 capture is 2,556 px against this change's
  8,100 px and stops mid-`Cupressus macrocarpa` — the activity feed has genuinely never been
  photographed at an accessibility size. `DynamicTypeScreenshotTests.swift:137` shoots 03 at AX5 too,
  but into a fixed 852 pt frame, so it does not reach the feed either. Same shape of gap as E199/#228
  on screen 11, which is why `11-growth-history` asks for the tall viewport. Filed as **#262**; not
  fixed here.

## Verification

Final figures are from the **merged** tree (this branch merged with `origin/main` at `f8b61a4`),
whose tree hash is `5219512658b4cda4a2eee584457ef15bda517107` — the same tree the adversarial
reviewer measured independently, on a different device.

- Unit, **fresh** DerivedData: see the run headers on the PR. `VERIFY-WARNINGS: source=0` over
  `TreeProfilePresentation.swift` and `PhenologyOnProfileTests.swift`, certified from a build with
  a nonzero `SwiftCompile` count that compiled both named files (E203).
- UI: `** TEST SUCCEEDED **` with a nonzero executed count and `XCTest skipped=0`.
- Five red-proofs, each read for its message rather than its color:
  - phenology dropped from `visitDetail` → **four** tests red — `taggedVisitWithNoNoteReachesTheFeed`
    on `(row?.detail → "") == " · flowering"`, `everyTagReachesTheFeed` on six issues,
    `noteAndTagsCompose` on `" · “Fog…”" == " · “Fog…” · flowering"`, and `tagsRenderInSeasonalOrder`.
    The drawn-row, bare-visit, empty-note, care-row and feed-mechanics tests and the whole vocabulary
    suite stayed green, which is what says they are not agreeing with everything.
  - seasonal order replaced by tap order → **only** `tagsRenderInSeasonalOrder`, on
    `" · bare, fruiting, leaf out" == " · leaf out, fruiting, bare"`.
  - `Flowering` renamed to `In bloom` in `PhenologyTagLabel` → `PhenologyStageVocabularyTests` on the
    literal (`"in bloom" == "flowering"`, twice), **plus two plumbing tests** in the other suite —
    four issues, not one. Pinning literals rather than looping over the enum is the point: a loop
    agrees with any rename, and `everyTagReachesTheFeed` — which asserts against the same expression
    the implementation evaluates — did stay green through this proof. `PhenologyStageVocabularyTests`
    is the only thing between a copy change and the record.
  - states put back before the note → **only** `noteAndTagsCompose`, on
    `" · flowering · “Fog dripping off the crown”" == " · “Fog dripping off the crown” · flowering"`.
  - the `!note.isEmpty` guard removed → **only** `emptyNoteRendersNothing`, on
    `" · “” · flowering" == " · flowering"` and `" · “”" == ""`. The `MemorialCopy.visitDetail`
    assertion in the same test stayed green, which is correct: it is the function the guard was
    taken from and it was never missing it.

**Correction to an earlier version of this entry.** It reported
`Test run with 1290 tests in 129 suites passed` "on the merge-base tree". That figure is from this
branch's own previous commit, not from the merge base — the change adds tests, so a merge-base count
could not include them. A wrong provenance label on a count is the thing this repository files
errata about, and it was caught in review rather than by its author.
- Screen 03 photographed in four appearances with the feed carrying both compositions.
