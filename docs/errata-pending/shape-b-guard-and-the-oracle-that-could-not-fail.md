# E— · E209's Shape B, fixed and guarded — and the red-proof that caught the guard exempting itself (task #186)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `p1/round8-b`. Latest numbered at time of writing: E209, R49. The design decision is in
the companion pending ruling, `city-record-columns-decline-outside-their-id-space.md`.*

---

## The measurement, re-derived rather than quoted

Every figure in the #186 brief and in E209-B1/B2 was re-measured against the shipped seed
(`Cypress/Resources/cypress-seed.sqlite`, `trees_source = sf_city`, 198,625 rows) before anything was
built. **All four are exactly right.**

| claim | ticket | measured |
|---|---:|---:|
| San Jose rows drawing `City lists this as` | 51,689 of 52,788 (97.9 %) | **51,689 of 52,788 (97.918 %)** |
| of those, reading `N/A` | 25,032 | **25,032** |
| San Francisco rows drawing the card | 166 | **166** |
| San Jose rows where `site_type` is identical to `plant_type` | all 52,788 | **all 52,788, 0 differing** |

### Three things the sweep found that E209 did not

1. **E209's list of San Jose `GROWSPACE` values is incomplete.** It names seven; the seed holds
   **fourteen**. The six it omits — `Other/Maintained` (581), `Back of Sidewalk` (580), `Backup`
   (104), `Unmaintained Area` (73), `Island` (29), `Raised Planter` (20) — plus `Unassigned` account
   for the 1,387 rows between its list and its own 51,689 total, which is why the total was still
   right. The 1,099 rows that draw nothing are NULL, not empty string.

2. **San Francisco has the same defect, in its own data.** `site_type` is the bare separator `:` on
   **4,608 SF rows** — `qSiteInfo`'s two halves with both halves empty — and it drew `Site — :` on
   screen 14 and on screen 19. E209 characterised Shape B as San Jose's problem; it is not. The
   count of rows drawing a `Site` card that states nothing is **30,445** across the two cities.

3. **Screen 19 is not a footnote here.** 5,393 of San Jose's 11,787 vacant planting sites in the
   shipped seed read `Site — N/A`, on a screen whose entire subject is a hole in the ground.

Corrected in passing: `listedAsText`'s doc comment asserted the column is "100% populated", which is
false for the shipped seed (1,099 San Jose NULLs), and quoted only the DataSF export's counts as
though they were the file's.

## What was changed

Both halves of E209's "B1 and B2 must be fixed together", plus the SF case it did not know about:

- `CityRecordPresentation` gained `idSpace`, and **`listedAsText` declines outside `sf`** (R24).
- **`CityRecordPresentation.statedValue`** refuses a string that states no value — no letter or digit
  anywhere, or a source-neutral form-null (`n/a`, `unassigned`, …) — and every card in §9b plus the
  `Site` card on 03/14 and 19 goes through it. `SitePresentation` and `TreeProfilePresentation` now
  share one `siteTypeText` instead of two copies of the same condition, which is how they came to
  disagree.

Photographed running, on San Jose record `#100002` / 945 W JULIAN ST, before and after: the two
`N/A` cards go; `Legal status`, `Cared for by` and the provenance line stay, so the section is not
emptied and E126's "must say why" is not engaged. Reasoning in the companion ruling.

## The guard, which is the point of the ticket

`CityRecordSectionTests.everySurfaceDrawsOnlyColumnsItsIdSpaceCanSpeakFor` sweeps **every row of
every id space** — via the 2,133 distinct tuples over the card-bearing columns, weighted by row
count — through the **real** `TreeProfilePresentation` and `SitePresentation`, and asserts:

1. **no card draws a value that states no value**; and
2. **no two cards on one screen carry the same value under different labels** (E209-B2).

Neither assertion mentions a city, which is the whole difference from
`everyCitySurfaceNamesTheRowsOwnInventory`. That guard sweeps drawn strings for another city's
*name*; `N/A` contains none, so it was structurally incapable of seeing this and would have stayed
green through all five rediscoveries of Shape B.

It goes through the real screens rather than through the helpers they call, deliberately: a `Site`
card that reads the column straight out of the row and skips `siteTypeText` is a live regression
path, and a sweep over the helper alone cannot see it.

### Red-proof — three breaks, and what each one actually said

| break | result |
|---|---|
| remove `listedAsText`'s R24 guard | **red.** `us-ca-sj screen 03/14: the plantType card draws 'N/A' under 'City lists this as' on N rows…`, plus `'Back of Sidewalk' is drawn twice … as 'Site' and as 'City lists this as'`, plus the control: `San Jose draws the plant type card on 51689 rows; R24 says it declines` |
| delete `statedValue`'s two refusals | **red**, on all four: `sf screen 03/14 … ':'`, `sf screen 19 … ':'`, `us-ca-sj … 'N/A'`, `us-ca-sj … 'Unassigned'` |
| make screen 03/14's `Site` card bypass `siteTypeText` | **red on 03/14 only**, not 19 — which is what proves the per-screen routing earns its keep |

## The half of this worth reading: **the first version of the guard could not fail**

Assertion 1 was written as `CityRecordPresentation.statedValue(v) == v` — asking the function under
test whether the function under test had done its job. Break 2 was applied, the suite was run, and it
came back **`VERIFY-OK: Test run with 28 tests in 1 suite passed`** on a build with the refusal
deleted. Deleting the rule deleted the yardstick with it.

That is CLAUDE.md's "exempted the thing they were guarding as its own wrapper", and it is #101's
defect — a guard that reads as coverage and cannot fail — reproduced *inside the very ticket written
to stop it recurring*. It survived a green full-suite run of 1,069 tests and was caught by nothing
except breaking the code on purpose and reading the result.

The fix is a second, independent list of placeholders written out in the test
(`CityRecordSectionTests.statesNoValue`). The duplication is deliberate: the two must be able to
disagree, and a change that teaches the renderer a new placeholder must be a visible diff in the
test too.

**The general rule, which is why this is an errata entry and not a commit message: a guard must not
use the code it guards as its oracle, and the only thing that detects one that does is a red-proof
you actually read.** A red-proof that is run but whose colour is assumed is worth nothing here — this
one was green when it should have been red, and looked exactly like a passing test.

## Left alone, deliberately

E209's other members are untouched and still want tickets: `SharePresentation.ShareCopy.city`
(Shape A — needs a source for a short civic name no table carries) and `MapKitBasemap.defaultCentre`
(Shape B — needs a per-city centre `CityManifest.City` does not carry).

**#134 was read and not taken.** It is the observation that a `city` row's `inventory_source` does
not describe where every one of its fields came from — 130,029 of the 133,577 `city` rows carry a
`legal_status` the city's own layer does not publish, joined in from the DataSF export on `TreeID` —
and it proposes either a per-field provenance stamp or a sentence in the schema comment. The first is
a schema change and **writable v14 belongs to a closed round**, so it is out of bounds here; the
second is about `legal_status` on San Francisco rows and does not fall out of a change to
`plant_type`/`site_type` on San Jose ones. It is genuinely the same gap seen from the data side, and
it is worth its own ticket. Nothing in this change makes it worse: no new column is routed into a
label, and two columns stop reaching one.
