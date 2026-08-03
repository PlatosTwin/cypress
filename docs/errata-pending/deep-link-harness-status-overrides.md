### E?? — The deep-link harness resolved trees from the seed's status while every screen it opened read the device's (task #173)

*UNNUMBERED — the orchestrator splices the number at merge.*

*Found on branch `p1/round12-b`, 2026-08-03, iPhone 16e `3A1F212D-…`, by
`CypressUITests/PrimaryCTAReachabilityTests` on its first run. Not caused by that ticket; the
condition is older than the branch and present on any device that has ever opened screen 19.*

---

**The symptom.** Two of the eleven screens the new AX5 probe visits had no primary CTA at all:

    treeProfile:    no button labeled "Be the first to photograph this tree" or
                    "Visit · say hello with a photo" is in the accessibility tree
    growthHistory:  no button labeled "Add a reading" is in the accessibility tree

Both after eight swipes to the bottom of the screen. `photoHero` — the *same* `TreeProfileView`, over
a different tree — found its CTA in one swipe, which is what makes it a data fact rather than a
layout one. The diagnostic list the probe prints on failure settled it: screen 03 held `Back`,
`Show me where this is`, `Favorite` and `Share`, and nothing else. That is exactly what
`TreeProfileView` draws when `presentation.acceptsContributions` is false, and screen 11's
`offersAddReading` reads the same property.

**The cause.** `LocalAPI` has two readers of a tree's status and they disagree.

- `treesNear(_:radiusM:limit:)` returns the inventory row, with the **seed's** status.
- `treeProfile(id:)` layers this device's `tree_status_overrides` on top — that is E124-B's whole
  mechanism, and it is what makes the `memorial` deep link work at all.

`DebugDeepLink.standingTree` filtered `treesNear` on `acceptsNewContributions`. So after
`CYPRESS_SCREEN=memorial` ran once — writing a `removed` override onto the nearest standing tree —
`standingTree` re-read the seed, still found that record `alive` there, and handed it straight back.
Every subsequent `treeProfile`, `growthHistory`, `checkIn`, `report`, `activity`, `share` and
`careLog` deep link opened a tree the app itself holds as **removed**: no primary CTA, no check-in
button, no `Add a reading`.

**The confident comment, caught in the act.** `DebugDeepLink.photographedTree`'s doc comment states
that `.memorial` "marks the nearest standing tree removed, so `standingTree` steps one outward each
time it runs", and builds the harness's whole no-collision argument on that march — `.memorial` from
the near end, the photo cases from the far end, `.measure` in the middle, "with 456 standing records
between them". **The march never happened.** `.memorial` marked the same record on every run and
`standingTree` returned that record every time. The comment described a mechanism that was never
wired, and it is the reason nobody looked. This is the CLAUDE.md rule about confident comments, in
the same file that already carries two errata about persistent-state collisions (E125, E133).

**Why the suite never noticed.** `DeepLinkVoiceOverTests.testTreeProfile` anchors on
`TreeProfilePresentation.fallbackTitle` — the title a tree with nothing on it shows — and then
asserts that every *hittable* control carries a label and that a `Back` exists. A removed tree
satisfies all three. Nothing in the repository asked a deep-linked screen whether the control it
exists to have pressed was on it, which is the gap #173 was written to close; it closed it on the
first run.

**The repair.** `DebugDeepLink.candidates(_:)` reads `treesNear` and lays
`LocalAPI.debugStatusOverrides()` — a new `#if DEBUG` seam — over the result, and all five
resolvers (`standingTree`, `photographedTree`, `measuredTree`, `anonymizedPhotoTree`,
`deadCandidateTree`) go through it. One extra read of a table that usually holds a handful of rows.
The march the comment describes is now real, and the comment says both things.

**Deliberately not a change to `treesNear`.** The map runs that query on every camera change and
layers overrides itself through `overrideCache`, precisely so the join is paid once rather than per
viewport. Folding it into `treesNear` would spend #130's pin budget to serve a `#if DEBUG` harness.

**What to check before believing a deep-linked screen is missing a control.** Ask whether the tree
it resolved carries a local override:

    C=$(xcrun simctl get_app_container <udid> app.cypress.Cypress data)
    sqlite3 "$C/Library/Application Support/Cypress/<store>.sqlite" \
      'SELECT tree_uuid, status FROM tree_status_overrides;'

Rows here are `memorial` and `deadProfile`'s leavings. They survive reinstall, like every other
device-container fact E202 is about.

**Still open, and not fixed here.** The overrides accumulate forever: nothing in the harness or the
suite clears `tree_status_overrides`, so `standingTree` now genuinely walks outward one record per
`memorial` run and will keep walking. That is the behaviour the design intended, and at a few hundred
runs it is still hundreds of records short of `.measure`'s middle slot — but it is a slow leak with
no cleanup, and a device driven for long enough will eventually collide the way E133 describes. A
`debugClearStatusOverrides` seam called from a suite-level `setUp` is the obvious shape; it belongs
to whoever owns the next round of the harness rather than to a probe ticket.
