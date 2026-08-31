# Three surfaces answer "which trees are mine" and no two of them agree

**Status: recorded, not repaired.** Found while placing tester report F23's `See them all on the
map` link, and it is what decided the placement. Nothing below is changed by that round; the round
routes around it and this entry is so that the next one does not have to rediscover it.

The app has three queries that all mean "this person's trees", and a reader would call all three
*yours*:

| surface | query | reads |
|---|---|---|
| screen 08's `Trees` pill | `ContributionStore.groveTreeIDs` | `visits` ∪ `favorites` |
| screen 01's `Yours` chip | `ContributionStore.contributedTreeIDs` | `visits` ∪ `observations` ∪ `measurements` ∪ `care_events` ∪ `community_trees` |
| the Journal tab's `Yours` segment | `ContributionStore.journal` | `visits` ∪ `observations` ∪ `measurements` ∪ `care_events`, one row per event |

The journal's set is a subset of the map's — the same four tables, and the map adds trees this
device added. **The grove's set is neither a subset nor a superset of the map's**, in both
directions and for different reasons:

- a tree somebody only **hearted** is in the grove and is not under `Yours`. That is R23 working as
  designed: "a favorite is a *bookmark* … a contribution is a *record*", and `MapMembership` keeps
  them apart deliberately. The grove unions them.
- a tree somebody only **checked in on, measured or cared for** is under `Yours` and is *not* in the
  grove, because `groveTreeIDs` has no arm for those three tables. The grove row for a tree that got
  there some other way still prints `1 check-in`, `2 measurements`, `1 care log` off
  `groveRecords` — so the tally can describe a contribution kind that cannot, on its own, put a
  tree on that screen.

The second one looks more like an oversight than a decision, and `GroveCopy.treesEmptyState` is the
only thing that states the rule: "Favoriting a tree or saving a visit to one puts it in your grove."
That sentence is accurate. Whether it is what the screen should do is a question for the owner, and
it is not one an F23-sized round should answer on its way past.

## What it cost, and what it bought

It cost F23 its obvious placement. The tester's sentence — *"let's add a link that says See them
all on the map. When clicked it takes you back to the map and shows only yours"* — reads most
naturally under the grove's list of trees, and that is the one screen where the link cannot keep its
promise: `them` there includes favorites and the map it opens would silently drop them. The link
went on the Journal segment instead, where the destination **set** is a superset of what the reader
is looking at and the narrowing itself can drop nothing.

**Two axes stand between that set and what the reader sees, and neither is this entry's subject** —
they are recorded here because the superset sentence is now load-bearing and must not be read as a
promise about pins (PR #130 review, F4):

- **the camera.** The link keeps the remembered viewport, so trees in the set can be off screen.
  Flagged in PR #130 and ratified as a follow-up rather than fixed.
- **the installed inventory.** A journal row survives its tree's city pack being removed —
  `LocalAPI.journal` reads the `main` contribution tables and resolves names separately — while the
  pin does not, because `MapViewport.treeIDs` is applied against the inventory union. So `Remove` a
  pack you have contributed in and the row stays, the link still says *all*, and that tree has no
  pin, with R41 forbidding any message that says why. This is the `Yours` chip's behavior since it
  shipped rather than anything the link introduces, and nobody has ruled on it.

It bought two assertions that did not exist before, in `CypressTests/SeeAllOnMapTests`:

- `theMapCannotHideARowTheJournalDrew` writes one row of each of the four kinds and requires every
  tree the journal names to be under `mapMembership(.yours)`. This is the link's promise **about the
  sets** — see the two axes above for what it deliberately does not claim — and it fails if either
  query loses an arm.
- `theMapsYoursIsNotTheGrovesList` requires a favorited tree to be in `grove()` and **not** under
  `Yours`. It is a pin on the state of the world rather than a wish: if the two are ever reconciled
  it goes red and says so, and the placement is open again.

## What would close it

One of three, and it is the owner's to pick:

1. **Leave it.** Three surfaces, three questions, and the link lives where its promise holds.
2. **Give the grove its own map narrowing** — a third `MapMembership` case whose set is
   `groveTreeIDs`. That is a new chip on screen 01, a new arm on `CypressAPI.mapMembership`, and a
   word for it that R23's vocabulary does not currently have.
3. **Reconcile `groveTreeIDs` with `contributedTreeIDs`** so the grove holds every tree you have
   contributed to as well as every tree you have hearted. This changes screen 08 for existing
   installs — trees appear in a list that did not have them — and it is a change to a screen the
   copy audit has already been over.
