# Rulings pending — how a tab loads (owner decisions, 2026-09-01)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename. **No code comment in this round
cites it by filename**: `RoutedAPI`, `GroveModel`, `GroveView` and `RootView` each say "the owner's
ruling of 2026-09-01" in prose, and describe the behavior rather than pointing at a number that does
not exist yet.

Two entries. They were decided together, from one report, and they are separable: either without the
other leaves half of the reported problem standing.

---

## What was reported

The owner, on the app as it shipped: **My Grove is very slow to load, and the Species sub-tab is the
worst of it.**

The local SQL underneath it was not the cause and had already been fixed — PR #131 batched
`LocalAPI.grove()`'s per-tree reads from a linear 13–22 seconds down to about 26 ms, and
`GroveQueryPlanTests` holds it there. What remained was two facts about the layers above that query,
neither of which any query-plan test could see:

1. **The composition wires `RoutedAPI`, and both of screen 08's reads awaited the service before
   returning anything.** `groveSpecies()` read the phone in about 6 ms and then awaited
   `GET /me/grove/species` against `cypress-sync.fly.dev`; `grove()` did the same with
   `GET /me/grove`. On a first request the session may also mint a device credential over the network
   before either. Nothing in the app configured `timeoutIntervalForRequest`, so an unreachable host
   cost `URLSession`'s 60-second default — a minute of blank tab — and a release build cannot opt out
   of the remote half.
2. **`RootView.tabRoot` is a `switch` on the selected tab**, so `GroveView` and the `@State`
   `GroveModel` inside it were destroyed on every switch away and rebuilt on every switch back.
   Every visit to My Grove was therefore a cold load, network await included, and `GroveModel.load()`
   had no idempotence guard to make a repeat call cheap even in principle.

---

### R??? — A tab paints from the phone and merges the service's half behind it

**Date:** 2026-09-01. **Decided by:** owner, in an `AskUserQuestion` round. **Implemented by:** this
round, for screen 08's two reads.

**The ruling, as decided:** paint the local read immediately; fetch the server delta in the
background and merge it into the presented data when it arrives. A species discovered on another
device may appear a beat later. Applies to `groveSpecies()` **and** `grove()`.

#### What was built

`RoutedAPI.grove()` and `RoutedAPI.groveSpecies()` are now the **paint**: they return the phone's
answer and touch no wire. The join each of them used to perform — unchanged, semantics for semantics
— moved to `refreshedGrove()` and `refreshedGroveSpecies()`, which `DataLayer.boot` hands to the
composition root as two closures. `GroveModel` runs the matching closure in a background task once
its local answer is on the glass and re-publishes when the merge lands.

Three consequences are worth stating out loud, because each is a place a later reader could conclude
something had been lost.

- **`RemoteReadLog` now describes the refresh, not the paint.** `.grove` and `.groveSpecies` are
  written by the refresh, so between the paint and the merge `outcome(of:)` answers **nil** — which
  that method already defines as "the service was not consulted", and which is exactly true of a
  paint that did not ask. It is the same fact the log always carried; it now arrives second. `.live`
  should be read as *refreshed after paint*. Nothing in `Features` reads the log yet (§4.3 rules
  that the sentence a screen draws about a degraded read is a copy question that is not in the
  mocks), so no surface changes meaning today — this is written down for the round that draws it.
- **A refresh that fails leaves the painted answer standing.** The closures swallow the throw to nil
  and the model treats nil as "nothing to merge". Replacing a whole grove with a failure state
  because a second read did not land would be drawing an empty claim over data this phone holds
  (R72 ruling 1).
- **The refresh is nil when the remote gate is shut**, so a `.disabled` build — which is every
  DEBUG build without `CYPRESS_REMOTE=live`, and therefore the whole UI suite — starts no background
  task at all and behaves exactly as it did.

Alongside it, and required by it rather than merely adjacent: **the service's JSON routes got a
session of the app's own with `timeoutIntervalForRequest = 15 s`.** `URLSession.shared` cannot be
configured — its `configuration` is a copy — so as long as the wire was the shared session there was
no value to set. Fifteen seconds is well clear of a Fly autostart and well inside the minute a reader
spends deciding an app is broken. The photo binary's session and the city-pack background session are
deliberately **not** this one: both are large transfers and neither would survive a timeout written
for a JSON route. The outbox does share it, and that is intended — a timeout is a `URLError`, outside
the taxonomy, so the item stays alive on the backoff (ERRATA E261 §3).

#### What was weighed and rejected

- **Keep the blocking read and only add the timeout.** It shortens the worst case and does not
  change the shape: the first frame still waits for a network round trip, and in a park it waits for
  the full failure path every time.
- **Widen `CypressAPI` with a local-first pair.** It would oblige fourteen preview doubles and every
  test double to answer a second read of a question they answer once — the tax `CypressAPI`'s own
  header records paying before. The refresh is a property of *this router*, not of the protocol, so
  it is handed over by the composition root as a closure, which is the shape
  `makeOutboxViewState`'s `treeNameResolver` and `RoutedAPI.signedInUserID` already have.
- **Merge into the model from an `AsyncStream` the router publishes.** More machinery for one
  delivery, and it puts a lifetime question (who cancels the stream) into a layer that has no view
  of when a screen goes away.

---

### R??? — A tab's model outlives the tab switch

**Date:** 2026-09-01. **Decided by:** owner, same round. **Implemented by:** this round, for
screen 08.

**The ruling, as decided:** keep state alive across tab switches — hoist the Grove model above the
tab `switch` (or otherwise give it a lifetime beyond the tab's view identity) so revisiting My Grove
paints the last data instantly and refreshes in the background.

#### What was built

`GroveModel` is owned by `RootView` as `@State`, the way `OutboxViewState`, `ModerationModel`,
`AccountModel` and `PhotoImageStore` already are (ARCHITECTURE §3: one instance, from the composition
root). `GroveView` gained an initializer that adopts a model rather than building one; the
api-building initializer stays for previews, screenshot fixtures and unit tests, which have no
composition root to be handed one by.

`GroveModel.load()` gained the idempotence guard `loadTreesIfNeeded()` has always had, with a third
arm the ruling requires:

- `.loading` — read the phone, paint, refresh behind it;
- `.loaded` — **paint nothing and refresh behind it**, which is what "instantly, and refreshes"
  means when the model already holds the answer;
- `.failed` — leave it. The retry button is the way back from a failure (ERRATA E126), and a `.task`
  firing again is not somebody asking for one.

#### Scope, stated so the next round does not have to guess

**This ruling is about tab models in general and only screen 08 was changed.** The Journal tab was
concurrently authored in the same round and is deliberately untouched here; the map's model was
already outside the switch. Applying the same hoist to the remaining tabs is a follow-up, and the
argument for it is this entry rather than a new one.

#### What was weighed and rejected

- **Render every tab and hide the inactive ones.** Keeps state, and mounts four screens' worth of
  reads at launch — including the map's camera work — to fix one tab's.
- **Cache the answer in the API layer instead of the model.** Puts a lifetime and an invalidation
  rule into `Data`, where nothing knows when a screen appeared, to avoid holding an object the
  composition root already holds four of.

---

## Standing

Both are performance and lifetime decisions about behavior SCREENS.md does not draw, taken by the
owner directly. Nothing here changes what screen 08 renders: the same grid, the same rows, the same
copy. What changes is when they arrive and how often they are re-read.
