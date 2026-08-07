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

## The one judgment call, settled by looking

The mock never draws a row with both a note and a vocabulary list, so their order is not specified.
It is decided in `visitDetail(note:phenologyTags:)`, states first:

    Visit · flowering · “Fog dripping off the crown”      Oct 12
    Care  · watered, mulched                              Sep 28
    Visit · leaf out, fruiting                            Aug 30

Two reasons, and the second is the one that changed the answer:

1. It puts the structured vocabulary immediately after the bold label on **both** kinds of row, so
   the `Visit` row and the `Care` row read as the same thing said about two contributions. That
   parallel is the whole argument for this slot being the right one.
2. Photographed the other way round — note first — a note long enough to wrap left a ` · `
   orphaned at the head of the second line, because the free text is the only clause whose length
   is unbounded. Both compositions were rendered; the screenshots decided it, not the argument.

A designer may overrule this by swapping two lines. It is decided in one place and the tests name
it as a decision.

## What was deliberately not done

- **No new stage, no rename, no reorder.** The words are `PhenologyTagLabel`'s own chip copy
  lowercased, so what a contributor tapped is what they read back, and the six of them are pinned
  by value in `PhenologyStageVocabularyTests` (DECISIONS constraint 15). The reading order is
  `VisitPhenologyVocabulary.order`, the seasonal order screen 04 already lays the chips out in, so
  no second ordering exists to drift from the first. A row reads the same however the chips were
  tapped.
- **No schema change.** Both version spaces are untouched. The column this reads has existed since
  `visits` was created and the decode already returned it.
- **The deeper product question is still open.** "What is a phenology observation *for* once
  recorded?" — aggregation across a tree's years, a species-level view, anything on screen 12 or 13
  beyond today's spring-flush sentence — is not answered here and was not meant to be. This makes
  the observation visible to the person who made it, on the tree they made it about.

## Two things found while checking, neither caused by this change

- **A premise worth correcting.** The triage names "the four phenology chips (`Leaf out`,
  `Full leaf`, `Flowering`, `Fruiting`)". Four is what SCREENS 04 *draws*; the vocabulary is
  **six** — `fall_color` and `bare` as well. Whether a given tree is offered four or six is D5's
  evergreen exclusion at work, not a property of the vocabulary. Anything counting phenology states
  from the mock rather than from `PhenologyTag` will be short by two.

- **C9 rows break mid-word at AX5, on the drawn row, before this change.** The AX5 capture added
  here (`phen-03-profile-observations-light-ax5`) shows the mock's own untouched
  `Care · watered, mulched` row rendering as `watere/d,` `mulch/ed` — the fixed-width mono
  timestamp column keeps its width while the body's column collapses. The `Visit` row does the same
  with or without an observation, so this change neither causes it nor worsens it in kind.

  It has gone unseen because **screen 03's own sweep entry does not pass `ax5ViewportHeight`**, so
  its AX5 captures stop around the tree's name and the activity feed has never been photographed at
  an accessibility size. Same shape of gap as E199/#228 on screen 11, which is why
  `11-growth-history` asks for the tall viewport. Worth a ticket of its own: give `03-tree-profile`
  the tall AX5 viewport, then decide what C9 does when its body column cannot hold a word — R14
  dropping a `max-width` at accessibility sizes is the nearest existing precedent for the shape of
  that answer.

## Verification

- `Test run with 1290 tests in 129 suites passed` on the merge-base tree, then re-run on the final
  tree; `VERIFY-WARNINGS: source=0` on a fresh DerivedData naming both changed files.
- Three red-proofs, each read for its message rather than its color:
  - phenology dropped from `visitDetail` → the four observation tests red on the pre-fix empty
    detail (`(row?.detail → "") == " · flowering"`); the drawn-row, bare-visit, care-row and
    vocabulary tests stayed green, which is what says they are not just agreeing with everything.
  - seasonal order replaced by tap order → only `tagsRenderInSeasonalOrder` red, on
    `" · bare, fruiting, leaf out" == " · leaf out, fruiting, bare"`.
  - `Flowering` renamed to `In bloom` in `PhenologyTagLabel` → `PhenologyStageVocabularyTests` red
    on the literal (`"in bloom" == "flowering"`), which is the point of pinning literals rather
    than looping over the enum: a loop would have agreed with the rename.
- Screen 03 photographed in four appearances with the feed carrying both compositions.
