### The one thing R41's carve-out now holds: an empty `Needs care` map says so, once (task #247)

**Owner instruction, verbatim, 2026-08-06:**

> Leave as is, but we can add a quick and light pop-up toast or the like (as long as it dismisses
> quick and doesn't pollute the map permanently) that says no trees need care.

## What this decides, and what it deliberately leaves alone

R41 is categorical — "no message ever accompanies a filter", its test being *"does text appear
because a filter did something?"* — and it names exactly one permitted form for anything judged
genuinely essential: a **single-dismiss popup**, "shown once, dismissed with one tap, never
recurring for the same cause, never persistent on the glass". R41 then judged that nothing in the
product qualified.

The owner has now judged that one state does, and has chosen a briefer form than the one R41
sanctioned: the popup dismisses itself rather than waiting for a tap. **That is the owner refining
their own ruling**, so no delegated authority is being used here and R41's carve-out is not being
read down by anyone.

**"Leave as is" is the first half of the instruction and it binds.** Task #165's settlement stands
untouched — "if nothing matches, fine", the empty map is the whole answer, and the `Clear filters`
chip is the way out. Nothing about the filter row, the chips, or the empty-map behavior changes.
E205's audit of the filter surfaces stays clean.

## The state, exactly

E244 is what made this state reachable. Until #240 the two condition chips did nothing at all to a
clustered map — the predicate was applied to the pins already fetched, and at zoom ≤ 15 there are
no pins to apply it to. E244 moved both into the `WHERE` clause, so `Needs care` now empties the
map honestly. It closed with the product question open in its own words: "whether `Needs care` is
worth a chip at all while the seed carries zero `declining` rows is a product question this task
did not answer". This is the owner's answer: keep the chip, and say the one thing the empty screen
means.

`MapNeedsCareToast.isOwed` opens on four facts and nothing else:

1. the whole `MapFilter` equals `.needsCare` — the chip on and **nothing else narrowing anything**;
2. the search bar is off;
3. the last read did not throw (`MapInventoryNotice.isOwed`'s argument, and E126's);
4. the map has **zero markers** to draw — `markerCount`, so cluster badges count, which is the
   whole of E244.

**Condition 1 is an honesty gate, not merely a scoping one.** `Needs care` beside a decade draws an
empty map for a reason nobody can attribute: a tree on this block may well need care and simply not
have been planted in the 2010s. "No trees need care" would then claim more than the query asked. The
sentence is true of exactly one query, so it is shown for exactly that query — which also means
`In bloom`, `Yours`, `Favorites`, `Year`, `Site` and the legend species all keep R41's silence,
enforced by `CypressTests/MapNeedsCareToastTests`.

## The copy

> **No trees need care**

The owner's own words with a capital and nothing added. It carries no count (R41 names a count among
the surfaces forbidden beside a filter), no "here" (that would be a claim about the ground rather
than the record — the distinction `MapInventoryCopy` spends its comment on), and no explanatory
second clause about what `declining` means or why the inventory holds none, which would be invented
prose under DECISIONS constraint 15. **Flagged for the owner's approval in the PR; it is close to
their own sentence and they hold the veto.**

## The re-arm rule, which is the half the instruction is really about

**One activation of the chip, one answer.** The gate is armed when `Needs care` is switched on, and
disarmed by the first read that *finishes* after that — with trees, with nothing, **or with an
error** — whether or not it produced a toast. Any other change to the filter, and any change to the
search, takes a toast already up off the screen.

**A press whose read failed has had its answer, and the answer was the error state.** This was
missed on the first pass and found in review of PR #46: the disarm was reached only from `fetch()`'s
success path, so a read that threw left the arm live indefinitely, and the next unrelated successful
read — a plain pan, chip untouched, screens and minutes later — collected it and posted the toast.
The sentence then answered the pan rather than the press, which is precisely the pollution this rule
exists to prevent, reached through a transient network failure instead of directly.
`noteReadFinished` is called from all three terminal paths now; `isOwed`'s `!readFailed` guard is
what stops the failed read from *also* showing something, which is "a failed read is not an empty
answer" (E126) applied to the arm as well as to the gate.

**A cancelled read is deliberately not a finished one.** Every cancellation in `fetch()` means a
newer fetch has already superseded it, so the press's answer is the read that actually lands. An
answer spends the press; being overtaken does not.

The alternative — post whenever the state holds — fires on every pan and every zoom across an empty
filtered map. That is a toast that never stops arriving, which is the permanent pollution the
instruction excludes in its own words. What is left is a toast that is the **answer to the press**:
the reader asked what needs care around here, and the map answers once. Panning afterwards is a new
question about the ground, not a second press of the chip, and the empty map is already its whole
answer (task #165).

## The form

- **Three seconds**, then it removes itself. The owner asked for "quick" and for something that
  "dismisses quick" and named no number; three seconds is the smallest commitment that satisfies
  both halves. `MapModel.defaultNeedsCareToastDuration` is the one place a later ruling changes it.
- **In the flow, immediately under the filter chips** — not an overlay over the map. It therefore
  cannot cover the chips, the legend, or anything in the bottom block at ordinary sizes, and the
  argument is `MapSuggestionList`'s one control up: an overlay leaves what it covers reachable by an
  assistive technology and invisible to everyone else.
- **It takes no touches** (`allowsHitTesting(false)`). There is nothing to press — the dismissal is
  time — so a pan that starts on those few points still pans the map.
- **Announced.** `MapHomeView` posts it as an `AccessibilityNotification.Announcement`, the same
  mechanism the recenter control and `VisitPinAdjustView`'s nudge pad use: it reports without
  stealing focus. The card also stays a real element in the tree for the reader sweeping the chrome
  inside that window.
- **Reduce Motion switches the fade off** rather than shortening it, through `cypressAnimation`.

## What it costs at AX5, stated rather than glossed

Photographed on the running app (iPhone 16e, 390 pt) at `accessibility5`: the toast is one line, it
sits under the chip row, and it draws over part of the `What tree is this?` FAB for its three
seconds. **That collision is pre-existing and this takes no new ground.** At AX5 the bottom block has
already climbed into the chip row — the recenter control sits behind the `Needs care` chip and the
FAB behind the row above it — which is the E183 §2 family, an open defect, and R53 §6 is the owner
ruling that governs that slot. The species legend chip occupies *exactly* the same band permanently
today; the toast borrows it for three seconds. Widening the fix to the bottom block's AX5 layout
would be taking a design decision this task has no standing to take (constraint 21).

## Not taken

- **No general toast mechanism.** `MapToast` has one caller and its own comment says why it must
  keep one: R41 is categorical precisely because each previous filter message "survived under a
  different mechanism". Whether any other state deserves this form is the owner's, not a
  precedent set here.
- **No tap-to-dismiss and no queue.** Neither is in the instruction and both are surface nobody
  asked for.

## What holds it

`CypressTests/MapNeedsCareToastTests` — eleven tests, six on the gate (including one that fails if
any other narrowing can open it), one on the words, four driving the real `MapModel` through the
real fetch path for the arming, the auto-dismissal, the re-arm rule, and a read that throws. Every answer comes from a fake
API, so **nothing here depends on the shipped seed's zero `declining` rows staying zero.** Section 4
of `CypressUITests/MapFilterAccessibilityTests` carries a note recording that R41's structural guard
does not drive the one narrowing that produces this, and what a fourth case added there must expect.
