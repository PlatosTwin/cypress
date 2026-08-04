### The Journal tab's `City` segment — three cards, a derived city, and no name for it (delegated)

*Written under the standing delegation for copy and behavior the mocks do not cover — SCREENS.md
draws no mock for this segment at all, so ARCHITECTURE §5 rule 8 sends it to the nearest specified
thing, which is screen 12, the almanac. UNNUMBERED — the orchestrator splices the number at merge
and rewrites the code comments that cite this filename (`Cypress/Data/Store/CityQueries.swift`,
`Cypress/Data/API/City.swift`, `Cypress/Features/City/*.swift`,
`Cypress/Features/Journal/JournalPresentation.swift`, `Cypress/Features/Journal/JournalTabView.swift`,
`Cypress/App/DebugDeepLink.swift`).*

*Raised by the owner: "on Journal, we should have a City tab with similar but not identical stats
and views to what's on the neighborhood view. Should be insightful, interesting, educative, not pure
data porn and not overwhelming." Two changes narrowed the brief after the first pass: card 4 ("what
the record doesn't know") is cut outright, and card 3 became the five oldest trees on file rather
than one elder. Both are reflected below as the shipped design, not as a revision history.*

---

#### What was decided

The Journal tab gains a third segment, `City` (`JournalSegment.city`), alongside `Yours` and
`Neighborhood`. It draws three cards over the whole city the reader is standing in, plus the
almanac's own kind of closing footnote:

1. **`Your streets, against the city`** — the two or three species markedly more common near the
   reader than across the whole city, as a sentence: *"Monterey cypress is 18% of the trees near you
   and 4% citywide."* This is the reason the segment exists — the one comparison neither the almanac
   (which never looks past its own neighborhood) nor the species page's citywide count (RULINGS R48,
   which deliberately does not scope by city) can make on its own.
2. **`Who lives here · N species`** — the whole city's composition, in the almanac's own shape:
   `AlmanacPresentation.composition(_:locale:)`, reused rather than re-derived, so the remainder-row
   discipline ("Everyone else" computed from unrounded shares) cannot drift between the two cards a
   reader is meant to set side by side.
3. **`The oldest on file`** — the five oldest standing trees in the city whose planting the city
   recorded, each carrying the almanac's own hedge, *"in the city record since"*, never "planted in".

Card 4 — a card about how much of the record carries no planting date, and how many mapped sites are
empty — was designed, argued for, and cut on the owner's explicit instruction before it was built.
Nothing about it ships: no query, no copy, no test, no slot left for it. It is not mourned here beyond
this one sentence, because the standing instruction for a cut feature is silence, not a eulogy.

---

#### Why the screen describes a derived city, and never names one

**The bundled inventory is fused across two cities under one attached database, and nothing in it
carries a display name for a city — only for a city's *inventory*.** `id_spaces.id` is a bare key
(`sf`, `us-ca-sj`); `inventories.name` is the *inventory's* published name (`"City of San Jose Street
Tree inventory"`), the same string `CityRecordPresentation`'s provenance line already prints per tree.
Composing "San Francisco" or "San Jose" from either of those would be the same guess three prior
rulings already closed the door on, each time a screen stated a specific city's name over data that
either was not that city's, or was more than one city's:

- **R28** found a San Jose tree profile saying "San Francisco" four times, because a subtitle, a
  record-number prefix and a section header had all been written for the one city that used to be the
  only one there was.
- **R48** found a species page's citywide count spanning both cities under San Francisco's name alone
  — for Crape Myrtle, 97 San Francisco trees and 3,649 San Jose ones, told to every reader as `In San
  Francisco · 3,746`.
- **R51** found a tree-profile card reading San Francisco's `PlantType` vocabulary against San Jose's
  differently-meaning `GROWSPACE` column, because a rule written from one publisher's documentation
  does not carry to a second publisher's.

**A screen literally titled `City`, presenting three aggregate cards over a fused two-city bundle,
is the shape those three defects were each an instance of — the fourth would be the worst one, because
every number on it is citywide by construction rather than a single tree's mistake.** So the ruling
here is not "derive the city carefully and then name it correctly." It is: *derive which city the
reader's queries are scoped to, and never turn that fact into a name at all.*

**The derivation itself is a fact read off a row, not a guess about a coordinate.**
`CityQueries.resolveIDSpace(near:radiusM:)` finds the nearest inventoried tree within
`AlmanacLimits.fallbackRadiusM` (the same 1,200 m the almanac's own fallback area uses, RULINGS R29)
and reads its `id_space`. That is the same shape `SpeciesQueries.resolveNeighborhood(near:)` already
uses to answer "which neighborhood" without a boundary-file lookup, applied one level up. A reader
whose nearest tree is more than that radius away resolves no city at all, and the segment renders the
almanac's own kind of out-of-range state — a title and a body sentence, no button, never a guessed
city name standing in for "we don't know."

**What this rules out, deliberately, is `CityManifest.displayName`.** It exists — "a civic fact
entered by hand at publish," keyed by the same `id_space` — and it is the one place in this app that
*does* carry a proper city name. It was not used here, for one reason that outweighs the convenience:
it is fetched from a network manifest (`GET manifest.json`), and every other read behind this segment
is a synchronous local database query that works with the phone in airplane mode, on a first launch,
with Cities never opened. Wiring a cosmetic label to a network fetch on an otherwise fully local-first
screen would make the segment's *header* the one part of it that can fail differently from its
*content*, and it would do that for a two-word label. The segment's own name, `City` — a category, like
the almanac's own `Neighborhood`, never a place — carries the whole weight instead.

**Nothing downstream of `resolveIDSpace` is allowed to forget the predicate, either.** Every read that
follows — `CityQueries.speciesMix(idSpace:)`, `CityQueries.oldestOnFile(idSpace:)` — takes the resolved
`id_space` and predicates every row on it. `CityQueriesTests.speciesMixDoesNotSpanBothCities` and
`.cityAPIScopesCompositionToOneCity` assert this the same way R48's own test does: not "the count is
non-nil" but "the count equals a direct SQL read scoped to one city, and is strictly less than the
fused total" — a marker-based proof rather than a value that could pass by coincidence.

---

#### Why card 1 is the one built well, and what makes it render nothing

The owner's brief is explicit that this card is the reason the segment exists, so its floors are named
rather than folded into an `if`. All three are **NOT SPECIFIED** — no source states a number — and are
recorded where they are used, `Cypress/Data/API/City.swift`'s `CityLimits`:

- `minimumLocalTreesForContrast` (20) — the local scope has to hold a real sample before any
  comparison is drawn from it. Deliberately looser than the almanac's own cold-start floor for
  composition (which asks only that the read came back non-empty), because a *comparison*, unlike a
  listing, can be actively misleading at a tiny sample in a way a listing of what little there is
  cannot: two trees near the reader is a true fact stated as two trees, but stated as "100% of the
  trees near you" it is a claim about a street from a sample of two.
- `minimumLocalSpeciesCount` (3) — a candidate species needs at least this many of its own trees
  nearby, so one planting cannot read as a pattern. Chosen under A8's own floor of three for a
  headcount of *people*, and deliberately not the same floor for the same reason it differs: this
  counts trees, which carries none of the privacy weight a floor on distinct visitors carries, so there
  was no reason to set it lower than the number this codebase already treats as "small enough to name."
- `minimumDivergencePoints` (5) and `maximumDivergentSpecies` (3) — the gap has to clear rounding noise
  between two independently-rounded percentages, and the card names at most three, which is
  `AlmanacMetrics.compositionNamedRows`'s own cap for "the most common," reused here for "the most
  different."

Below any of these, card 1 renders nothing — not a zero, not a smaller version of the sentence — the
same discipline `AlmanacPresentation` names A9 for. `CityPresentationTests` proves each floor on both
sides: a sample below the floor with an enormous divergence still renders nothing
(`contrastNeedsARealLocalSample`), a real sample with a genuine zero-point gap renders nothing
(`contrastNeedsARealGap`), and a species with too few local trees is excluded even when its percentage
gap alone would qualify (`contrastNeedsARealPerSpeciesSample`) — three tests, because a single
"renders nothing below threshold" assertion would not say *which* threshold it was proving.

---

#### Why card 3 is five trees and not one, and what that costs

The coordinator's own instruction, given after the first pass: *"Card 3 becomes the FIVE oldest on
file, not one elder... with five of them on screen instead of one, that distinction gets easier for a
reader to misread, so the card's own copy has to carry it rather than relying on a per-row phrase."*

**The hedge is unchanged and is carried twice.** Every row's subtitle is `"in the city record since
{year}"` — `AlmanacCopy.elderSubtitle`'s own phrase, applied per row exactly as the almanac's single
elder carries it (`CityCopy.recordSince`, tested by `rowsCarryTheHedge`). But the almanac could rely on
that one phrase because it is one row; five rows read, at a skim, as "five old trees" rather than "five
old *dates*," so the card also states the distinction once for itself, in `CityCopy.recordNote`:
*"These are the oldest planting dates on file, not the oldest trees — most of the record carries no
planting date at all."* DataSF fills a planting date on a minority of rows (measured at 70,067 of
195,309 for San Francisco alone, RULINGS' own figure for the almanac's elder — re-measured rather than
re-quoted here, since San Jose's own fraction is unmeasured and this card is honest about the shape of
the gap rather than a number this ruling would then have to keep in step with the seed).

**Three exclusions, named because each one is a specific way this list could have misled:**

- **Vacant sites.** `CityQueries.oldestOnFile` requires `status IN ('alive','declining')` — the same
  `standing` predicate `AlmanacQueries` names for the identical reason. Measured against the shipped
  seed rather than assumed: San Francisco's own raw-oldest-dated row (`1955-09-19`) is a vacant
  planting site, one day ahead of the oldest *standing* tree (`1955-10-20`) — the two share a
  `planted_year` of 1955, which is why the exclusion has to be checked at `planted_on` grain to be
  proven at all. `CityQueriesTests.oldestOnFileExcludesVacantSites` reads the true raw-oldest row by
  identity, not by year, for exactly that reason, and records that the precondition held for at least
  one city rather than assuming it does.
- **Stub species (RULINGS R47, R54).** A tree whose species the ingest could not read carries a sound
  `common_name` (`"9662"`, `"Magnolia"`) and an unsound `scientific_name` (`":: 9662"`,
  `":: Magnolia"`); this query's own `COALESCE(s.common_name, s.scientific_name)` already keeps the
  `":: "` marker off the screen, which is precisely why a name-shaped test of this exclusion would pass
  whether or not it did anything (`CityQueriesTests.oldestOnFileExcludesStubSpecies`'s own header notes
  this and checks by tree identity instead). **The decision made here, which R47/R54 left to whoever
  needed it next: a dated stub-species tree is skipped and the next oldest non-stub tree takes its
  place, rather than being named by its position without a species.** Naming a row `"5th oldest"` with
  no identity would be inventing a rank this app does not otherwise draw (DECISIONS constraint 1);
  silently keeping the tree's place but printing nothing where its subject would go is the empty-title
  problem `IconTextRow`'s own subtitle-vs-title distinction exists to avoid (a title, unlike a
  subtitle, cannot be absent without reserving a blank line). Skipping and backfilling costs nothing a
  reader can notice — the list is still five real, nameable trees — and it is the stricter of the two
  options on a surface five times more exposed than the almanac's own single elder row.
- **The tie at the boundary.** `CityQueries.oldestOnFile` is handed one row more than the card draws
  (`CityLimits.oldestRowLimit + 1`), so `CityPresentation` can tell whether the sixth-oldest row shares
  the fifth's planting year. When it does, the list of five was drawn from a larger tied group by an
  arbitrary tiebreak, and presenting it as *the* five oldest overstates what the query proved.
  `CityCopy.recordNote(tiedAtBoundary:)` appends *"At least one more tree on file shares the last one's
  year."* rather than letting the untied phrasing stand. `CityPresentationTests.tiedBoundarySoftensTheNote`
  and `.untiedSixthRowDrawsPlainly` prove both directions, and
  `.fewerThanFiveShowsWhatExists` proves the third case — fewer than five dated trees at all, which
  draws exactly what exists with no tie logic to apply, since there is no sixth row to compare.

---

#### What this does not decide

- **Whether San Jose's own undated fraction should ever be measured and stated.** Card 4 would have
  needed it and is cut; nothing here computes or claims it.
- **A fourth card, discussed separately with the owner.** Not built, not slotted for, not named here
  beyond this sentence recording that this ruling does not cover it.
- **Whether `CityManifest.displayName` should ever reach an on-device, offline-safe cache** — which
  would reopen the question this ruling answers by *not* using the network manifest here. If that ever
  lands, the honest shape is a cached display name with its own staleness story, decided together with
  whoever needs it, not inherited from this segment's refusal to use the network copy.

---

#### What holds it

`CypressTests/CityQueriesTests.swift` — the real-seed half: `speciesMixDoesNotSpanBothCities` and
`cityAPIScopesCompositionToOneCity` (the fused-bundle guarantee), `oldestOnFileExcludesVacantSites`
(checked at `planted_on` grain, by identity, against a measured precondition),
`oldestOnFileExcludesStubSpecies` (checked by tree identity rather than by name, for the reason its own
header states), and `sanFranciscoResolvesSF` / `sanJoseResolvesItsOwnSpace` /
`outsideBothCitiesResolvesNothing` (the derivation's own distance bound).

`CypressTests/CityPresentationTests.swift` — the synthetic-fixture half: every `CityLimits` floor
proven on both sides, the tie/no-tie/fewer-than-five three-way split for card 3, the subject fallback
chain (`rowTitleFallsBackInOrder`), and `noCopyNamesACity`, which reads every string `CityCopy` owns
plus one representative dynamic sentence from each card and asserts none of them contain `"San
Francisco"`, `"San Jose"`, `"DataSF"` or either raw `id_space` key — markers rather than a fixed
string, the same discipline `SecondCityGeographyTests.theCountCardNamesThePopulationItCounted` uses for
R48, so that swapping one hardcoded city for another could not satisfy it.

Every test above was red-proofed by hand before this change was committed: the `id_space` predicate
removed from `speciesMix` (both fused-bundle tests failed with `sfTotal == sjTotal == 173538`, the
whole attached inventory, read through both `CityQueries` directly and `LocalAPI.city(near:)`); the
`standing` predicate removed from `oldestOnFile` (the vacant-site test failed with the card's own top
row equal to the vacant site's own uuid); the stub-species clause removed (the exclusion test failed
with the stub tree's uuid present in the result set); the local-sample floor removed from
`CityPresentation.contrast` (a ten-tree sample rendered `"Species 1 is 100% of the trees near you and
1% citywide."`); and the tie-boundary comparison replaced with a constant `false` (the softened note
never appeared). Each was restored immediately after its failure was read and confirmed to say what it
was expected to say.
