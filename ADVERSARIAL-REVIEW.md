# Adversarial review, round 2

Five reviewers, each briefed to attack rather than encourage, each with a different axe. They read DESIGN.md, SPEC-PHASE1.md, and screenshots of all thirteen mocked screens. This file condenses what they found and records what we decided to do about it. The decisions here drive the v3 mocks and BUILD-PLAN.md.

The panel:

1. A bearish seed investor who has passed on forty community-plus-map apps. Attacked viability, retention, incumbents, and the missing revenue line.
2. A jaded principal product designer. Attacked the gaps between screens, field usability, and mock-versus-spec honesty.
3. A senior city arborist on a municipal data governance board. Attacked measurement validity, liability, privacy, and integration reality.
4. A gamification skeptic who has watched leaderboards poison three citizen science communities. Attacked incentives and community health.
5. A staff engineer told "an LLM will build this from these documents." Attacked buildability, ambiguity, and everything the spec never defines.

## The finding all five converged on

Screen 12, the leaderboard, contradicts the project's own design doc. DESIGN.md Phase 1 says "no streaks or leaderboards." Screen 8's caption brags "there are no leaderboards to game." Screen 12 is a ranked list of four raw volume counts, none of which have verification machinery behind them, one screen away. Every reviewer flagged it independently:

The investor: the mocks sell the year-five network state, untested against day 30.
The designer: it is not in the Phase 1 scope list at all, and "adopted by you" names a Phase 2 feature.
The arborist: ranking "most cared for" rewards over-watering and mulch volcanoes.
The gamification skeptic: ranking trees instead of people is a fig leaf, every metric is farmable in under thirty seconds, and farmed check-ins are indistinguishable in the database from honest ones, forever.
The engineer: no table, no ranking definition, no reset semantics exist anywhere.

Verdict: the leaderboard dies. See decision 1.

## Each reviewer's sharpest findings

### The investor

Phase 1 ships the vitamins and defers the painkiller. The only user with a burning recurring problem is the org steward walking a Saturday route, and that flow sits in Phase 2. The enthusiast layer needs thousands of users to feel alive; the steward loop works with ten.

Nobody opens the app in month 3. The single recurring trigger in the whole design, phenology notifications ("your cherry blooms around this week"), is parked in Phase 2.

The Report screen is a strictly worse 311. On the official city app, reporting does something. Ours ends in "the city has not been notified."

No revenue line. The doc writes a data escrow exit clause before a pricing page. Photo storage costs scale with the most engaged users; revenue scales with nothing.

The signup wall lands on second 8 of the ten second visit. The single conversion moment carries the maximum friction event: an auth sheet plus a license consent checkbox, on a street corner.

Cold start is a map of gray rectangles. The seed solves the empty map; nothing solves the empty content. Every hero image and season strip is blank on day one.

GPS ID is a coin flip among four neighbors. Urban canyon GPS degrades to 20 to 50 m; street trees are 6 to 10 m apart.

### The designer

The mocks depict year three of a community that does not exist. The screen 100 percent of first users will actually see, a bare city record with no photos, is not in the set.

The entire front door is missing: no permission asks, no sign-in sheet, no consent copy, no decline paths.

The vitality scale is five flat paint chips. Near-adjacent greens are indistinguishable in sun glare and for the roughly 8 percent of male volunteers with color vision deficiency. The anchored rubric's reference photos, the entire point, are absent at rating time.

Growth history charts numbers no screen can enter. There is no keypad, no unit field, no method picker anywhere in the thirteen screens.

The volunteer's real day does not compose. Ten check-ins in a row cost five to six taps of navigation each, with no "next nearest" affordance and no visited-today pin state.

The spec demands 44 pt targets and a sun-readable palette; the mocks deliver sub-30 pt season thumbnails and beige-on-cream chips.

Screen 13's small multiples mislead: no scales, so a 41-photo series and a 9-care series occupy identical heights. Favorites per month is a nonsense series for a one-time toggle.

Hazards share one truncated chip row with "needs water." The safety path is gated behind the least scannable control.

Plus a sixteen-item list of screens that must exist: permission and denied states, cold profile, empty states, outbox and its failure modes, search results, the You tab, and more. The full list is preserved in BUILD-PLAN.md section 9.

### The arborist

The nightly open export publishes unverified citizen observations as a citable dataset before any QA tier exists. Provenance labels in the UI do not help a downstream script pulling the file. This is exactly the pipe that has dumped garbage into real city inventories.

Wrong-tree attribution poisons timelines forever. GPS-ranked ID with no confirmation step, append-only records, adjacent trees 6 to 8 m apart: misattribution is silent and permanent.

Estimated and taped values drawn on one connecting line manufacture a trend that is not there. Eyeball height carries roughly 30 percent error; eyeball DBH is noise.

Botanical howler: the flagship Monterey Cypress, an evergreen conifer, has "Fall color starting!" in its timeline and "Fall color" phenology chips. The species-awareness in spec section 6 never reached the UI.

A hazard community note is a discoverable liability record ("hanging limb, the city has not been notified") that then auto-deletes on a 90 day timer. No city wants that live in an app it does not control.

Public attributed visit timelines plus "adopted by you" on a public surface reconstruct where a named person lives and stands. No age gate exists, and volunteer programs include minors.

### The gamification skeptic

Goodhart's law, walked through metric by metric: burst photos pollute the timeline the future AI pipeline depends on; a countable check-in costs three seconds with every field skipped; "watered" is a free unverifiable claim; favorites are sockpuppet-scalable.

Farmed check-ins poison the health time series at the source, and you can never again trust the pre-metric baseline meaning of the record.

Extrinsic crowding-out drives away exactly the users Phase 1 lives on. Favoriting stops being a private bookmark and becomes a vote.

Every ranked metric routes attention toward Grandmother Cypress and away from the dying sapling in a low-canopy neighborhood. The trees most needing eyes, young street trees in their first two summers, photograph badly and have no residents in the app.

The proposed replacement loop, which we adopted: recognition through knowing trees over time rather than counts; streaks that belong to the tree and its group of caretakers rather than the person; status through validation by others; coverage gaps as the only directed incentive, because coverage is the one metric where chasing it produces exactly the data you want.

### The engineer

The mocks and the spec describe two different products. Screens 11 to 13 render adoption, structured measurements, and leaderboards that section 1 of the spec puts out of Phase 1.

There is no API specification at all. No endpoints, no auth model, no sync protocol, no photo upload flow. The mobile and web halves would invent it differently.

The species content pipeline does not exist. ID tips, bloom windows, vitality reference photos: shapeless jsonb with no schema, no source, no authoring surface, for roughly 570 SF species strings.

Tree nicknames exist only in the mocks. No field, no naming flow, no moderation path for the inevitable abuse case.

Ingest is named but not specified: no column mapping, no rules for null coordinates or non-tree rows, no diff algorithm.

Milestones are grocery lists with no acceptance criteria and the word "test" appears nowhere.

A list of roughly fifteen load-bearing ambiguities ("clustering above zoom 16" reads backwards; "best photo" has four defensible readings; "recently visited" by whom?) and fifteen entities the screens imply that the spec never defines. Both lists are resolved item by item in BUILD-PLAN.md.

## Decisions

What we are changing, numbered so the mocks and BUILD-PLAN.md can cite them.

1. The leaderboard dies. Screen 12 becomes the Neighborhood almanac: non-ranked, no counts attached to countable actions. First bloom sightings, the oldest tree, species mix, and the coverage panel: young trees not visited since planting, blocks unseen for months. Coverage gaps become the only directed ask in the app.
2. Screen 13 keeps its small multiples but gets honest: the favorites series is cut, the three remaining charts share one scale so amplitude comparison works, and the trivia tiles become a moments list (first spring flush noted, watered through the dry weeks, six people know this tree).
3. The vitality selector becomes five full-width anchored rows, each with a reference photo, the label, and the anchor sentence always visible. Color becomes secondary coding.
4. Hazard reporting is redirect-only. The public community note option disappears for hazard categories. What remains after the 311 handoff is a private reminder on your own record, never public, never auto-staled. Non-safety note categories move to a wrapped grid, visually separated.
5. Phenology surfaces become species-aware. Evergreens never show fall color chips or autumn strip colors. The chip set is driven by a leaf retention attribute on species.
6. Tree ID gets a confirmation step. When candidates sit within GPS error of each other, the app shows the two nearest with a distinguishing trait each and requires a tap to confirm. Per-contribution GPS accuracy is stored; low-accuracy contributions are excluded from growth charting.
7. Minimal measurement capture moves into Phase 1: a measure sheet with a big keypad, mandatory unit and method chips, and the previous value shown for sanity checking. This gives screens 3 and 11 a legal data source. On charts, estimated and taped points render as separate series and are never connected.
8. Five missing screens get mocked: the cold tree profile ("be the first to photograph this tree"), the sign-in sheet with license consent and a decline path, the measure sheet, the outbox with per-item state and retry, and the post-check-in screen with "next nearest tree" and a visited-today map state. The remaining missing states are enumerated as build requirements in BUILD-PLAN.md.
9. Accounts come later in the funnel. First saves are anonymous and local-first under a device ID, synced after account creation. The ask comes at the third save, when the user has something to lose.
10. Phenology notifications move into Phase 1. They are the only mechanism that gives a tree a reason to summon a person back, and the species seasonal data they need is already in the schema.
11. Privacy hardening: contribution feeds are private by default with opt-in public attribution, adopter identity is never public, an age gate lands in onboarding, and minors default to anonymous attribution.
12. The open export gets a verification_state stamp. City inventory rows export clean; citizen observation rows carry a machine-readable unverified marker, and the structured observation export holds until a verification tier ships.
13. The phases invert around the wedge. The org steward loop (assignments, a route view, the batch check-in, the coordinator export) moves from Phase 2 into a Phase 1.5 that starts as soon as the walking skeleton stands, with one partner org. The enthusiast layer launches into a map that already has fresh steward data on it.
14. A revenue position exists: the coordinator dashboard and org tooling are the paid tier, priced for nonprofit budgets, roughly 50 to 200 dollars per org per month. The consumer layer is free forever. If no org will pay even that, we want to learn it at design stage.
15. BUILD-PLAN.md becomes the buildability contract: field-level data model including nicknames and their moderation, an API contract, the ingest spec with column mapping, the sync and outbox design with an error taxonomy, the species content pipeline, the privacy spec, milestones with acceptance criteria, a test plan, and one-sentence resolutions for every ambiguity the engineer listed.

## What we rejected, and why

The investor wanted the Report screen cut from Phase 1 entirely. It stays. All five reviewers independently praised the honest 311 redirect as the most trustworthy decision in the design; the fix is removing the hazard note branch (decision 4), which was the actual liability.

The investor wanted screens 11 and 13 deleted as depicting an impossible future. They stay, with their data problem fixed at the source instead: decision 7 gives them a real Phase 1 data source, and the cold profile mock (decision 8) shows the honest day-one state alongside them.

The designer wanted all sixteen missing screens mocked. We mocked the five that change the product's shape and specified the rest as build requirements. A mock set is an argument, not an inventory.

The gamification skeptic floated iNaturalist-style validation status in Phase 1. It needs the competency and verification machinery that is genuinely Phase 2. The almanac and coverage quests carry the loop until then.

## What every reviewer said to keep

Three things survived five hostile reads untouched, which is worth recording:

The provenance spine. Method and unit metadata on every number, versioned species assertions, stable citable tree UUIDs, lifecycle states. The arborist called it "genuinely rare"; the engineer said an LLM given this will not flatten species into a naive foreign key.

Honest routing. "The city has not been notified" as an explicit, mocked state, with hazards hard-redirected to 311.

The photo timeline with the ghost overlay and season strip. The one artifact the official city app will never have: a longitudinal, framing-consistent visual record of individual trees. If the product pivots, it pivots around this.
