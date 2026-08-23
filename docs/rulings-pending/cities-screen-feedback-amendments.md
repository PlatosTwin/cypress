# Rulings pending — three amendments to R43 the Cities screen's tester feedback forced (2026-08-23)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename.

All three amend **RULINGS R43 §3**, which is the mock for a surface that has none. R43 was written
under delegated design authority against a catalog of **two** cities; the catalog now holds seven,
five of them New York boroughs, and a tester filed eight reports against the screen on the evening
of 2026-08-23 (build 49, App Store Connect run 32649153871). These are the three places the ruling
itself had to move. The other five reports were defects against the ruling rather than in it, and
need no entry here.

**None of these is an owner ruling yet.** They are this round's proposals, implemented so they can
be looked at rather than imagined, and the PR puts the alternatives beside each one. A reviewer
who disagrees is disagreeing with a branch, not with a decision.

---

### R??? — `Use` belongs to every state that holds an attachable copy, including `update available`

**Date:** 2026-08-23. **Proposed by:** this round, from a tester report. **Status:** awaiting the
owner.

#### What went wrong

R43 §3's affordance table reads, in full, for one state:

> update available → `Update` and `Remove`

That is a complete description of what the reader can do, and it omits the thing they most need to
do. A city in this state is **installed, verified, attachable and not attached**. The moment the
catalog moves ahead of the copy on disk, the only button that would attach it disappears.

Reached by an ordinary path, and a tester walked it: download Manhattan, use it, switch back to the
built-in inventory to compare, then find no way back —

> *"This is a bug: I have manhattan downloaded already and used it once but then I clicked use on
> the default inventory and now I can't seem to use manhattan even though it's on my phone"*

The copy was fine. The screen had simply stopped offering it.

R43 §1 already assumes the opposite of the table, in the sentence describing what happens when a
downloaded file fails to validate: the row *"shows the city as installed but not in use"* — a state
whose entire content is that `Use` is available. §3's table and §1's prose disagreed, and the table
is what was built.

#### Ruling

`Use` is drawn for **every** state in which the device holds a copy this build can attach, and is
withheld only where it cannot keep its promise. `update available` is such a state.

#### The cost, which is real and is the thing to rule on

R43 §3 says affordances are *"compact buttons, never more than two visible"*. This state now draws
**three** — `Use`, `Update`, `Remove`. That is the one place this round exceeds the ruling's own
guidance, and it is deliberate:

- dropping `Remove` strands the opposite direction: a city that cannot be deleted until it has
  first been updated, which is worse than the defect being fixed;
- demoting `Update` hides the newer record the state line directly above is announcing;
- so the count is what gives, for exactly one state.

**Measured rather than assumed:** the three buttons were rendered on a 402 pt iPhone 16 Pro and
photographed; none truncates, and the row reads as a row. A narrower device is the open question a
reviewer should press on.

**Alternatives, for the owner:** (a) three buttons, as built; (b) `Use` and `Update` only, with
`Remove` reachable after the update — rejected above; (c) a second button row for this state, which
invents a card layout R43 does not have.

---

### R??? — A bundled city states possession before it states an offer, and the built-in card names what is in it

**Date:** 2026-08-23. **Proposed by:** this round, from two tester reports. **Status:** awaiting
the owner.

#### What went wrong

Two reports, one cause: the screen was accurate about what a reader could *fetch* and silent about
what they already *held*.

> *"Why am I seeing option to download sf and San Jose when those cities SHIP WITH THE APP?? Bad
> design"*

San Francisco and San Jose are inside the app bundle. Their record date (2026-07-31) is older than
the published one (2026-08-22), so the state is `.bundledOutdated` and the `Download` button is
honest — it buys a newer record. But the row's only line was
`Newer record available · included copy is 2026-07-31`, which never says the city is in the app.
Read cold, beside a `Download` button, it reads as an offer to sell the reader something they are
looking at on the map.

> *"On this view we should say WHAT CITIES ship in the pre-built seed. Right now all it says is
> THAT there's an inventory not WHAT ITS OF"*

Same shape, on the built-in card: R43 §3 gives it the title `Built-in inventory` and the subtitle
`Ships with the app and cannot be removed`, and between them they never name a city.

#### Ruling

- A `.bundledOutdated` row states `Included in the app · record as of <date>` as its **state line**
  — D5's own sentence, already in the vocabulary — and moves the offer to the quieter detail line
  as `A newer record is available to download.` No new fact; the order changed, and the date is
  now printed once rather than twice.
- The built-in card carries a third line naming the cities the seed holds:
  `Includes San Francisco and San Jose`.

**Every name is read out of the shipped file** (`dim_city.display_name`, via `SeedCities`), never
written into a Swift constant — DECISIONS constraint 15, and the only version that cannot go stale
the day the bundle changes. A seed that names nothing contributes no line rather than an empty one.

**Alternative:** name the cities in the *subtitle* instead of a third line, which keeps the card at
two lines but edits a string R43 §3 fixes verbatim. Rejected as the more invasive of the two.

---

### R??? — The Cities screen is sectioned: what you have, then what you can get, with a city's packs under its name

**Date:** 2026-08-23. **Proposed by:** this round, from two tester reports. **Status:** awaiting
the owner.

#### What went wrong

R43 §2 rules the screen as a flat list, in one sentence:

> The pushed screen is **Cities**: `ScreenHeader` back-circle screen, one card for the built-in
> inventory, then one card per city the manifest lists, in manifest order. That is the whole screen.

That was written for two cities. At seven cards — five of them boroughs of one city — the same
tester filed the complaint twice in three minutes:

> *"The NYC ones should be visually grouped somehow under NYC"*

> *"…there needs to be visual grouping and section separation. If a city is downloaded and usable it
> should be at top, separated from others."*

#### Ruling

Two top-level headings in the You tab's existing micro-label idiom — no new component, no new
chrome:

- **`On this phone`** — the built-in card, the cities inside it, and anything downloaded.
  Membership is `CityInstallState.isOnDevice`, decided beside `allowsDownload` so the sectioning
  and the buttons cannot disagree about what the phone holds.
- **`Available to download`** — everything else, with the packs of any city that has **more than
  one** of them gathered under a third-level heading carrying that city's own name (`New York
  City`), taken from the manifest's `parent_city_display_name`. A city with a single pack gets no
  heading: a `San Francisco` heading over San Francisco is furniture.

Order inside a section is the order it arrived in — the publisher's order, which R43 §2 makes the
display order, is preserved within each section rather than across the screen.

A download in flight keeps whatever section its state already earned: a first download stays under
`Available to download` until its bytes are verified and installed, and an update to a city already
held does not jump out of the top section while it runs.

**Alternatives, for the owner:** (a) as built; (b) group by city always, so single-pack cities get
headings too — rejected as furniture; (c) sort within `On this phone` by what is in use first,
which adds a third ordering rule to a screen that now has two.

#### What this does *not* do, and the report it leaves open

> *"Eventually we will have 20+ entries here. We need a way to allow search/filtering. Filtering
> should be by state. Search just normal search"*

Not built. The report is explicitly about a future catalog ("eventually", "20+"); the catalog holds
seven. Sectioning addresses the pain that exists now, and a search field over seven rows is chrome
with nothing to do. Recorded as a proposed ticket rather than implemented, so the decision to add
it is made when the catalog makes it necessary — and so that the filter's vocabulary (**by state**,
which is a fact the manifest does not currently carry for any pack) is designed once, deliberately,
rather than inferred from an id prefix.
