### Ex — A tree reference draws the blurry placeholder even when the tree has photographs (task #176)

*Filed unnumbered by the #176 agent; splice under the real next E-number at merge and rewrite any
code comment that still cites this filename.*

**The report.** *"Any reference to an actual tree should have a photo of that tree in the
thumbnail, if available, not just the blurry placeholder. So eg My Grove > Trees and Journal (The
Elder) should have photos if available."*

#### The inventory, built by searching for the placeholder rather than guessing at it

Every SwiftUI call site drawing `CypressGradientField`, `ThumbnailGradient`, `IconTextRow`'s own
tile, or `HeroPhotoHeader` was read and sorted into "names a specific tree" against "does not".

**Converted this round** — each was a placeholder standing in front of a photograph that could
exist, which is the defect:

- **My Grove → Trees** (`GroveTreesPresentation.Row`, drawn by `GroveView.treesTab` via
  `IconTextRow`) — the owner's first named example.
- **Journal** (`JournalPresentation.Row`, drawn by `JournalListView` via `IconTextRow`) — the
  owner's second named example. "The Elder" reaches the journal as an ordinary visited tree; there
  is nothing tree-specific in the row itself for that name to hang off, which is the point — the
  fix is general over every row, not special-cased to one tree's name.
- **Almanac → This season** (`AlmanacPresentation.SeasonRow`, drawn by `AlmanacView.seasonBlock`
  via `IconTextRow`) — the elder and the first bloom are each **literally** one named tree
  (`ElderTree.treeID`, `BloomFirst.treeID`); `newestNeighbors` names a group and was left with no
  photo id on purpose (see the rule, below). Almost always still the placeholder in practice: the
  almanac is neighbourhood-wide and this device's `main.photos` holds only what this device itself
  photographed, so a season row draws a real photo only for a tree this installation has actually
  been to.
- **The map pin card** (`MapCardSubject.heroPhoto`, drawn by `MapTreeCard`) — one tree at a time,
  reusing the `TreeProfile` the card already fetches for its title and badge (`profile.photos`,
  `profile.photoTallies`) rather than a second read.

**Found, and deliberately left alone:**

- **Species page → Nearby individuals** (screen 07 §6, `SpeciesView.nearbyRow`, drawn with
  `ThumbnailGradient(SpeciesThumbnail.placeholder(for:), size: .nearby)`). `NearbySpeciesTree`
  already carries `photoCount`, so the fact a photo exists is on the payload — but not *which*
  photo, and the query behind `nearby` is scoped by coordinate across every tree of a species
  rather than by "this device's own trees" the way `grove()`/`journal()`/`almanac()` are. Wiring
  it in needs its own batched read next to `SpeciesGuide`'s, not a reuse of
  `ContributionStore.heroPhotoIDs`'s unscoped-by-contributor shape. Open for a follow-up round.
- **Share preview** (screen 10 §3, `ShareView.previewCard`, `ThumbnailGradient(ShareThumbnail
  .placeholder(for:), size: .share)`). Its own comment already states the rule: *"A photograph
  would go in this frame the day one is approved."* `Photo.isPubliclyVisible` requires
  `.approved`, and nothing in the shipped app can set that — the placeholder here is honest about
  a *different* fact (no moderation exists yet) than the one this round fixes (a tree's own
  contributor can already see their own unmoderated photograph on their own screen, `Photo
  .isVisibleToItsContributor`, ERRATA E37). Converting this call site would be answering a
  moderation question this ticket did not ask.
- **Screen 02's shortlist / `VisitIdentifyView` candidates.** These name a species suggestion
  during identification, not yet a tree the app has a record of — there is no `treeID` to have
  chosen a photo for.
- **`ComponentGallery`.** A developer-only catalogue of every drawn component, never a user-facing
  screen.

#### The rule for "which photograph", made a value rather than left to a view

Every converted site reuses `PhotoHero.choose(from:tallies:)` — the same A3-plus-pin-override rule
the profile hero already draws by (ERRATA E125) — rather than inventing a second heuristic. What
this round adds is `ContributionStore.heroPhotoIDs(connection:)`: **one statement**, mirroring
`groveRecords`' own "scoped to the contributor, not to a tree list" shape, that reads every live
photograph this device holds, groups it by tree in Swift, and runs `PhotoHero.choose` once per
tree. `LocalAPI.grove()`, `.journal(cursor:limit:)` and `.almanac(near:)` each call it once per
screen load and hand the chosen id down through `GroveEntry.heroPhotoID` / `JournalEntry
.heroPhotoID` / `ElderTree.heroPhotoID` / `BloomFirst.heroPhotoID` to the presentation row. The map
card needs no equivalent statement at all — it already holds the `TreeProfile` the profile hero
reads from, so `MapCardSubject.heroPhoto` is `PhotoHero.choose` applied in place.

`PhotoHeroTests` (§4, §5) asserts the batched read agrees with the rule itself, is keyed per tree,
and responds to a vote exactly as the hero does. `IconTextRow` gained an optional `photoID:`; a
row that does not pass one draws exactly the accent gradient it always has, so no unrelated row
(a settings row, an export option, an almanac vacant-sites count) changed.

#### The hazard this round is not carrying (#87, E142, E151, E152)

`PhotoImage` needs the shared `PhotoImageStore` from the environment or it silently draws "could
not be opened" over a fine photograph. Every screen touched this round — `GroveView`,
`JournalTabView`/`JournalSection`, `AlmanacView`, the map — is reached through
`RootView`'s `NavigationStack`, which carries `sharedEnvironment` (`RootView.swift`, the
`.modifier(sharedEnvironment)` on the stack itself, not only on the one `fullScreenCover`). Neither
of the two sites #87 already names as missing it — `TreeProfileView.swift:122`'s `SpeciesPickView`
cover and `VisitSavedView.swift:102`'s `AccountAskView` cover — was touched.

#### One incidental fix, needed to add these call sites at all

`PhotoImage.photoID` was `UUID`, so every caller with "maybe no photo" (a hero with none, now a
list row with none) had to invent a sentinel UUID that resolves to nothing — `TreeProfileView
.noPhoto`, `00000000-…`. `PhotoImage.photoID` is `UUID?` now; `nil` draws the placeholder directly
rather than asking the store to look up a UUID nothing wrote. Every existing call site still
compiles unchanged — a non-optional `UUID` promotes to the parameter — and `TreeProfileView`'s own
sentinel was left in place rather than touched, since removing it is a separate, unrelated diff.
