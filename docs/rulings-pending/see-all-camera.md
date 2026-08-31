# Rulings pending — the camera `See them all on the map` opens on (owner ruling, 2026-08-31)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename.

Two entries. The first is the owner's ruling, verbatim in intent. The second is the three decisions
underneath it that the owner did not make, recorded with the alternatives so ratification is a
choice between written-down options rather than a re-derivation.

---

### R??? — `See them all on the map` opens on the city where the reader has the most trees

**Date:** 2026-08-31. **Decided by:** owner, trying build 63. **Implemented by:** this round.

> Clicking "See them all on the map" should center the map on where the trees are; right now it
> just takes you to the map, and if you're nowhere near a city it shows blank. It should be
> centered on the city where you have the most trees — which also covers people with trees in
> multiple cities.

#### What it supersedes

**The camera deferral in ERRATA E287.** That entry names two axes standing between the link's
`Yours` set and what the reader actually sees, and the first is this one:

> **the camera.** The link keeps the remembered viewport, so trees in the set can be off screen.
> Flagged in PR #130 and ratified as a follow-up rather than fixed.

It also strikes the ROADMAP follow-up "Map camera fits the filtered set", which recorded the same
deferral as its own small round. The second axis — the installed inventory — is **not** superseded
and is still open; see decision 3 below for the one corner of it this round touches.

Nothing in **R86** moves. R86 is about the chip row at 390 pt and is silent on the camera; what
this amends is the era of the link R86 belongs to, not that ruling's content.

#### What was actually blank, confirmed on a device

Reproduced before it was fixed, on the iPhone 16 Pro simulator with the reader's location and the
map's opening camera both pinned to downtown San Jose — a city the bundled inventory really covers,
sixty-eight kilometers from where this device's contributions are. Screen 01 arrived with the
`Yours` chip filled, the map drawn, streets named, and **no pin on it**. That is the owner's
sentence: the map was, technically, showing only their trees.

#### Where the behavior hangs

**On the link's own one-shot, not on the chip.** `AppRouter.pendingMapFilter` is spent by
`MapHomeView.applyPendingFilter`, and the camera move is now the second thing that function does.
Two consequences, both deliberate:

- **Pressing `Yours` on screen 01 still moves nothing.** A reader already looking at the map has
  chosen the camera they are looking at; narrowing what is drawn on it is not a request to be taken
  elsewhere, and a chip that teleported the map would be #85's un-pannable map with a new trigger.
- **A plain tab switch moves nothing**, because it disarms the narrowing (`AppRouter.tab`'s `didSet`,
  the R86-era repair) and the camera rides the same arming.

**And it beats the opening fly-to-you for that one arrival.** `MapHomeView.centerOnUserIfNeeded()`
would otherwise land after it and put the camera back on the reader — which is the blank screen
above, exactly. The reader asked to see their trees, so their trees win. When there is nothing to
show, the one-shot is handed back and asked again, so a reader who gets no camera does not also lose
the one they would have had.

**This decides nothing about search.** RULINGS R25 leaves "should choosing a species also move the
camera" open by name, with its own unanswered question (nearest to the camera, or nearest to the
reader?). Nothing here is reachable from the search bar.

---

### R??? — The three decisions under that ruling, ratified 2026-08-31, with the alternatives they were chosen over

**Date:** 2026-08-31. **Proposed by:** this round, under DECISIONS constraint 21. **RATIFIED by
the owner, 2026-08-31, via the orchestrator** — all three, as proposed, after the adversarial
review of PR #135. Each is kept with the alternative it was chosen over, because a ratification
that discards what it ruled out leaves the next round to re-derive it.

#### 1. The camera **fits** the winning city's trees; it does not center on their middle — RATIFIED

"Centered on where the trees are" has two readings when the trees are spread over a neighborhood.
This round fits: the box holds every one of the reader's trees in the winning city, padded by a
quarter of their own extent, and never tighter than `MapLayout.defaultSpanMeters` — ERRATA E12's
120 m, the scale at which San Francisco's street trees stop fusing into a mat.

*The alternative:* center on the centroid at the fixed 120 m opening span. It is what
`InventoryUnion.openingCenter` does for a downloaded city, and it is one number simpler. It was not
chosen because a reader with trees on four blocks would see one of them and have to find the rest,
which is the defect ERRATA E129 and E144 both are — a screen that names a group and shows one of it.

The arithmetic is not new: it is `PinSetPresentation.frame(around:)`'s, moved to
`MapCameraFrame.around(_:padding:)` unchanged and now called from both screens.

#### 2. A tie between two cities goes to the **most recent contribution** — RATIFIED

Two cities holding the same number of the reader's trees is a genuine tie, and the reader's own
answer to "which of these am I in" is the one they were at last. A third key — the city's own
`id_space`, ascending — sits under it so the ranking is a strict total order and the same tap opens
the same map twice.

*The alternative:* break the tie on inventory size, largest first, which is what
`InventoryUnion.openingCenter` already does for the opening camera and would make the two camera
paths agree. It was not chosen because "the biggest city wins" is a fact about the inventory rather
than about the reader, and this camera is the reader's.

*Recorded because it cost something:* the first version of the determinism guard passed against a
build with the last tie-break deleted. What decides a tie the ranking cannot is `Dictionary`
iteration order, which is a function of the process's hash seed rather than of the row order — one
process flipped four times in twenty-four permutations and the next flipped in none of two hundred.
`ContributedCamera.winner` now sorts by the group's key before it ranks, and the test asserts the
rule instead of its own first answer.

#### 3. A city whose inventory is gone cannot win, and the next city takes it — RATIFIED

E287's second axis: a journal row survives its tree's city pack being removed, and the pin does not.
So a reader can have four contributions in a city they no longer have installed and one in a city
they do. This round lets the second city win.

It needed no code and that is the argument for it: `LocalAPI.contributedPlaces` resolves geometry
through the inventory union, an id the union does not hold is simply absent, and a city that
contributes no place cannot win a vote counted in places. The camera is therefore always pointed at
something the map can actually draw.

*The alternative:* count the vote over journal rows rather than over drawable pins, so the removed
city still wins and the camera opens on an empty box. That is honest about the reader's history and
useless as a camera, and R41 forbids the map saying why it is empty.

*The corner where nothing can be done, stated rather than hidden:* a reader **every** one of whose
contributions is in removed packs gets no fitted camera at all. There is no view that shows those
trees, so the honest move is for this round to aim nothing.

**That corner is where the screen goes on doing what it always did, and it is not stillness — an
earlier draft of this paragraph said it was** (PR #135 review, F3, corrected in three places). What
happens is that `MapHomeView.fitCameraToYours()` ends its suppression and asks
`centerOnUserIfNeeded()` again, so the map may fly to **the reader**. That is the pre-round
behavior, unchanged, and it is right: what was ratified above is stillness for the *fit* — the
policy declines to invent a plausible box — not suppression of an opening fly-to-you that has
nothing to do with this ruling. A reader with no drawable trees is better served by being shown
where they are than by a camera frozen wherever the app happened to open.


---

### On the device

Both states, on the iPhone 16 Pro simulator, with the reader's location and the map's opening camera
pinned to the densest San Jose bin (`37.329024,-121.878931`) while every contribution is in San
Francisco, sixty-eight kilometers away:

- `docs/design-proposals/images/see-all-camera-before-blank-san-jose.png` — the `Yours` chip filled,
  streets drawn, **no pin**. The owner's report.
- `docs/design-proposals/images/see-all-camera-after-fitted-san-francisco.png` — the camera in the
  Mission with both contributed trees on screen, with margin.

The adversarial reviewer of PR #135 reproduced both independently on a second device (iPhone 16 Pro
Max, 440 pt) and reports the same two screens.
