# The seed carries bloom calendars, and four documents say it cannot (found under task #136)

**Unnumbered — pending. The orchestrator assigns the E number at merge.**

## The premise, and where it is written

R23 ("`In bloom` still matches nothing, because every `seasonal` in the shipped seed is `{}`"),
R23.1 (repeats it under "deliberately not decided"), R31 ("Every `seasonal` value in the seed is
`{}` … which for both chips is right now"), E183 §5 (records the same for `Needs care` and leans on
R23's sentence for `In bloom`), and `SeasonalWindowTests`' header ("every `seasonal` in the shipped
seed is empty") all state that no species carries seasonal data.

## The measurement

Against the seed this build ships (`cypress-seed.sqlite`, md5 `815ed501445e6f188cc7898e6b2901cb`,
identical in the main checkout's `Cypress/Resources/` and `Fixtures/seed/`):

- **511 of 569 species carry a non-empty `seasonal` JSON**; 11 carry non-empty `bloom_months`.
- Trees standing under a species whose calendar names the month, `deleted_at IS NULL`:
  Jan 5,513 · Feb 27,531 · Mar 28,235 · Apr 16,701 · May 14,608 · Jun 14,608 · **Jul 17,080** ·
  Aug 2,472 · Sep 2,472 · **Oct–Dec 0**.

So `In bloom` is not "impossible until the curated pipeline lands". It is **seasonal**: live nine
months of the year against this seed, dead the other three. `Needs care` is exactly as recorded —
the only statuses are `alive` (174,425) and `vacant_site` (24,200).

## What #136 built against the corrected premise

- `MapConditionAvailability` (new `CypressAPI` read) answers "could this chip match anything at
  all", per month, from the store — R31's "the data's arrival is the switch", which now switches
  `In bloom` with the seasons as well as with the pipeline.
- The availability carries `hasAnyBloomCalendar`, because `inBloom == false` is two different
  facts, and the disabled chip's sentence must not claim the calendars are unwritten when they are
  merely out of season. Three sentences ship: R31's debt sentence (no calendars), an out-of-season
  sentence (calendars, no bloom this month), and the invitation for `Needs care`.
- `CypressTests/MapConditionAvailabilityTests` pins the seed facts (July blooms, November does
  not, `needsCare` never) the way `MapYearFilterCopy.undatedShareOfSeed` pins coverage, so a
  re-ingest that moves the calendars fails loudly.

## What should be corrected at merge

R23 / R23.1 / R31's "every seasonal is `{}`" sentences are stale as statements about the present
seed (they may have been true of an earlier build; nothing in git tracks the binary, so when the
calendars arrived is not recoverable from history). `SeasonalWindowTests`' header sentence
likewise. None of these were edited from this branch — rulings are amended only by the
orchestrator, and the one amendment granted to this branch was R25 §1 (#143).
