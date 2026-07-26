# Pending errata — the capture flow (#76, #81, #87)

Two entries, unnumbered, for splicing into `docs/ERRATA.md` at merge time.

> **Numbering note for whoever splices these.** The code on this branch already cites **E149** for the
> first entry and **E150** for the second, because the work was written before the no-numbering rule
> reached it. If the assigned numbers differ, these are every citation site:
>
> ```
> git grep -n "E149\|E150" -- Cypress CypressTests
> ```
>
> As of writing that is `AppRouter.swift`, `RootView.swift`, `VisitFlowView.swift`,
> `VisitCameraView.swift`, `VisitCameraModel.swift`, `VisitOutboxWriter.swift`, `VisitMetrics.swift`,
> `VisitAddTreeModel.swift`, `PhotoMetadataTests.swift` and `VisitCameraSessionTests.swift`.

---

## The way out of the camera was however deep you happened to be, and one of the ways out went nowhere

The report is #76: "need a back to map button/functionality after taking photo/checking in". It reads
like a missing button and it is not. Every route out of the capture flow existed; none of them was a
*destination*.

**The routes, and what each of them actually did.** `VisitFlowView` hands its container four exits and
the container is `RootView`'s one `fullScreenCover`. Three of the four were relative:

- the shortlist's back chevron and the camera's ✕ → `onExit` → `router.sheet = nil`;
- screen 18's "Done for today" → **also `onExit`**, the same closure, the same one line;
- screen 18's "See it on the tree's timeline" → `sheet = nil` then `push(.treeProfile(id))`.

`sheet = nil` dismisses the cover onto whatever the tab root plus `router.path` happened to be when the
flow opened. From the map's FAB that is the map, and the whole thing looks correct. From **screen 03's
own photo CTA** — the app's primary call to action on a tree page, and the entrance E127 built — the
stack is `[.treeProfile(id)]`, so finishing a contribution lands on the profile of the tree you have
just photographed, which is the one screen a person who is *done* has no further business on. Every
screen in this app hides the system navigation bar (`toolbar(.hidden, for: .navigationBar)`, twelve
files), so there is no `‹ Back`; the only way to the map from there is a 40 pt translucent circle
drawn on top of the hero photograph, and the bottom tab bar — the thing that names the map — is drawn
only by the four tab roots and so is not on screen at all.

**And the third route made "back" appear to be broken.** From the profile entrance,
`push(.treeProfile(id))` pushed the profile of the tree that was *already on top of the stack*. Two
identical screens, so the first Back looked like nothing happening, and only the second reached the
map. A control that appears not to work is a stronger reason to report "there is no way back" than a
control that is missing.

**A fourth route did nothing at all, and this one is a plain defect.** `AppRouter` keeps **one** `path`
for all four tabs. Screen 18's "Route done · see your grove" was `sheet = nil; router.tab = .grove`,
which swaps the tab root *underneath* whatever is pushed. From the map entrance the stack is empty and
the grove appears. From the profile entrance the stack is `[.treeProfile]`, so the grove arrived behind
the tree profile and the only evidence anything had happened was that Back now went somewhere new.
Nothing in the app rendered wrong; the screen the person asked for was simply not on top.

**The fix is a destination, not a button.** `AppRouter.goToTab(_:)` clears `sheet`, clears `path`, then
sets `tab` — all three, in that order — and `goToMap()` is that for the map. `VisitFlowView` grew
`onDone`, separate from `onExit`, because *abandoning* and *finishing* mean different things and the
container cannot act on the difference unless it can see it: abandoning is relative (nothing was
contributed, so go back where you were) and finishing is absolute. `onDone` defaults to `onExit`, so a
caller with no opinion behaves exactly as before rather than silently doing nothing.

Worth recording: **`popToRoot()` had been sitting in `AppRouter` with no caller anywhere in the app.**
The operation that means "back to the map" existed and nothing had ever asked for it. That is not the
same defect as a missing operation and it is a more interesting one — the router was complete and the
flow simply never made a decision about where finishing goes.

`push(_:unlessAlreadyOnTop:)` is the timeline link's half. The plain `push` is unchanged, because
everything else in the app relies on stacking two of a kind being allowed.

### #87, the directed hypothesis: refuted, and then closed anyway

The hypothesis handed to this work was "no sheet or cover receives the environment the NavigationStack
carries". As a statement about the code it is **false, and has been since E142**: the app has exactly
one `fullScreenCover`, and its content was explicitly given both values the stack carries —
`.environment(router)` and `.environment(photoImages)` — which is precisely what E142 was recorded to
fix. Nor could it have caused #76: nothing in `Features/Visit` reads `AppRouter` from the environment
at all (`git grep "Environment(AppRouter.self)"` lists thirteen files and none of them is in that
folder). The visit flow is driven entirely by closures handed down from the composition root, so the
stranding was a wiring decision and not a missing environment value.

What #87 *did* still describe correctly was a hazard, and it is worth closing rather than arguing
with. E142 fixed the two values that were missing by writing them out a second time at the cover, which
left the list of shared environment values existing in two places with nothing making them agree. A
third shared value added to the `NavigationStack` would have reached every pushed destination and
silently reached no sheet — the same defect, the same silence, one value later. Those two sites are now
one `SharedEnvironment` modifier applied to both, so adding to the list reaches both by construction.

**Verdict: #87 is resolved, but not by the fix #76 needed.** Its literal claim was already false; its
underlying risk is now structurally impossible rather than merely currently absent.

### How each of these was made to fail

`goToMapIsAbsolute` and `goToTabClearsTheStack` are the ones that matter, because both assert the field
that looks optional. Deleting `path.removeAll()` from `goToTab` fails both with "the map is behind 2
pushed screens" / "the grove arrived underneath 1 pushed screens"; deleting `sheet = nil` fails both
with "the visit flow's cover is still up". Reverting `push(_:unlessAlreadyOnTop:)` to an unconditional
append fails `theTimelineLinkDoesNotDuplicateTheProfile` with "a second identical profile was pushed".
And the flows were walked on a running simulator, because no unit test can say whether a person can get
out of a screen — screenshots and the route are in the branch's report.

---

## Three photographs of one tree, and the two the third one used to destroy

The report is #81: "should be possible to take a full and then trunk and then leaf photo from one
camera screen without having to leave and come back". The screen already drew the three chips. What it
did not have was three photographs — the chips were three ways of *labelling* one.

**The data model was narrow in exactly one place.** `OutboxItem.photos` has been `[OutboxPhoto]` since
it was written and `outbox.enqueue(_:photos:)` has always taken a list; `VisitDraft.photo` was a single
`OutboxPhoto?`. The draft was the narrow section of a pipe that was wide at both ends, so pressing the
shutter under a second chip replaced the photograph that was there.

**The filename is where this became silent data loss.** `VisitPhotoStaging.url(for:)` was
`"\(visitID.uuidString).jpg"` under a comment that read "one file per visit id, so a re-save of the
same draft overwrites rather than accumulating" — true, and the bug. Three captures in one session were
three writes to **one path**, and `PhotoBinary.write` removes the destination before moving the new
bytes in. So the third photograph deleted the first two from disk. Nothing in the app reads a staged
file between the shutter and the drain, so there was no moment at which the loss could surface: no
error, no missing thumbnail, nothing. A contributor who photographed a tree three ways kept the leaf.

The name is now `"\(visitID.uuidString)-\(shotType.rawValue).jpg"` — the visit **and the framing**.
`ShotType.rawValue` rather than a counter, an index or a fresh UUID, because the framing is the thing
that actually distinguishes these files: a visit holds at most one photograph per framing, which is
what makes a *retake* of the trunk overwrite the trunk and nothing else. A counter would make every
retake a new file and leave orphans in a directory iCloud backs up.

**Everything that reads that path was checked rather than assumed.** `photos.local_path` takes one row
per photograph, each with its own path (`beginPhotoUpload`). `OutboxStore.removePhoto(atPath:from:)`
keys on the path, so draining one of the three does not take its siblings out of the row — the
invariant its own comment states, "a row cannot stage the same file twice", is *more* true now, not
less. `LocalAPI.uploadPhoto` moves each staged file to `<photoID>.jpg` under a fresh photo id, so three
staged files land as three stored files with three distinct `storage_key`s. Had the three paths still
collided, the second upload would have found its source already moved and failed `notFound` — which is
why `storageKey` is the load-bearing assertion in the round-trip test rather than a nicety.

**E148 is not routed around, and the new path carries the same coverage.** `VisitPhotoStaging.write`
took a visit id and now takes a visit id and a framing; it is still the one funnel, it still calls
`PhotoBinary.write(_:strippingMetadataTo:)`, and three shots in one session are three calls to it.
`PhotoMetadataTests` grew two tests that assert on **files, after paths**, never on which function was
called: `stagingKeepsThreeFramingsApartAndStripsEachOne` writes all three framings of one visit and
then, with all three on disk at once, checks that there are three distinct paths, that each file still
measures the photograph it was written from, and that each one has lost its GPS and kept its
orientation. The "all three at once" ordering is the whole design of it — every pre-existing assertion
in that file looks at the one file it was just handed, so all of them would have passed against a
collision. `stagingRetakeReplacesOnlyItsOwnFraming` is the other half: the retake lands on the same
path (no orphan) and the full-tree photograph beside it is untouched.

**Two of three is a complete contribution.** Nothing in BUILD-PLAN or PROTOTYPE-FLOW asks for a set;
the only stated gate on this screen is §1.6.1's "Log visit is disabled until snapped". So the gate
stayed at *any* photograph rather than becoming *all three*, and a contributor who does not find a leaf
worth photographing saves two. Refusing would have thrown away the two they did take, and there is no
draft state in this app, so there was never a third option to nag from: what was taken is what is
queued. A retake discards **only its own framing** — re-shooting the trunk has never meant "and throw
the full tree away" — and its replacement writes to the trunk's own path, which is the invariant the
filename buys.

**Three surfaces on screen 04 are NOT SPECIFIED and are marked as such.** SCREENS 04 draws the chips
with no captured state, the CTA reading `Log visit` and nothing else, and no line about what a session
could still hold; when it was drawn a visit held one photograph. Invented, under the project owner's
own request for this feature: a tick on a photographed chip (`CypressCheckmark`, the same shape screen
18's success circle and screen 05's selected row already draw, sized off 05's check circle), a CTA that
counts what it is about to save (`Log visit · 3 photos` — a count of the thing on screen, not of the
person, which is the line D1 draws), and one muted line naming the framings still open. The chips also
carry the fact in their accessibility labels — "Trunk, photographed" — because a mark is not read out
and the chip's own label no longer carries its whole meaning.

**#45's overflow, under the pressure a third control adds — and the two things that were wrong about
how it was checked.** The chip row moved from an `HStack` to a `CypressChipFlow`, on the stated grounds
that three chips wearing ticks at AX5 are wider than the phone and the third would go off the right
edge, the way #45's tray once did. Both halves of that turned out to be wrong, and only measuring found
it.

*The test could not fail.* `theTrayStaysOnTheScreenWithThreeCaptures` hosted the whole of screen 04 at
AX5 and asserted the result measured no wider than 393 pt. The chip row is an `.overlay` on the
viewfinder and **an overlay never enlarges what it is over**, so the row's width was never in the
number being asserted on. Putting the row back to an `HStack` left the test green. This is the same
class of thing E148 recorded — a test that agrees with the code rather than with the world — and it was
found the same way, by breaking the code on purpose and watching nothing happen.

*And then the defect was not the defect.* Once the row was extracted into `VisitShotTypeChips` and
hosted on its own, an `HStack` measured **326 pt in the 361 pt this row is given**. It fits. SwiftUI
compresses children rather than overflowing a proposal. What it costs is the chips themselves: each
squeezed from its natural 158 pt to about 103, its label wrapping into a column of stacked syllables —
which is exactly what the phenology row below it already looks like at AX5, and what a screenshot shows
in a second and no assertion in this project can see. Height does not separate them either: the
compressed `HStack` measures 203 pt tall against the wrapping flow's 175, for the same reason.

So the flow stays, for **legibility** and not for overflow, and the test now asserts only what a
measurement can decide — that the row stays inside the width it is given, which a `fixedSize()` or a
`frame(minWidth:)` would still break, and which is how #45 happened in the first place. Which layout is
readable is verified by looking, per ARCHITECTURE §7.

**What looking found that no test was asked for.** At AX1 — the size ARCHITECTURE §6 actually names as
the bar for field screens — the camera-denied fallback sentence sat *on top of* the three chips. Both
were bottom-anchored overlays on the viewfinder, at `bottom:150` and `bottom:34`, independent of each
other; the sentence grows to two lines as the ramp climbs and it grew straight through the chip row.
That state is not exotic: BUILD-PLAN §9 requires it, and a simulator is always in it. They are one
`bottomControls` stack now, with the gap derived so the chips land on the mock's 150 pt exactly in the
state the mock draws. A stack cannot overlap itself.

**And one thing that is left broken, deliberately.** At AX5 screen 04 collapses: the tray takes almost
the whole phone, the viewfinder is left about 130 pt tall, and the chip row — a bottom overlay on that
viewfinder — is pushed off the bottom of the screen entirely, so #81's feature cannot be reached at all.
It is pre-existing, the same before this change as after, and it is not a layout that can be repaired by
moving a padding: at AX5 an overlay-based camera is not a workable arrangement and what replaces it is a
screen variant SCREENS.md does not draw. ARCHITECTURE §5.8 says stop and ask, so this stops and asks.

**The framing is frozen at the shutter, and that is a behaviour change with a reason.** It used to be
re-read at "Log visit", on the recorded argument that "the chip row stays live after the shutter and
the last tap before Log visit is the answer". That was reasonable for one photograph and is destructive
for three: it would relabel every staged photograph as whichever chip happened to be selected when the
button was pressed, and since the file on disk is named after the framing, the row and the file would
then disagree about which photograph they are. The same reasoning applies to the ghost overlay: it is
recorded from `draft.photo(shotType: .fullTree)` specifically, not from the selected chip, because
`VisitGhostStore.record` refuses anything that is not a full tree — so passing the selection would have
made whether the next visit gets an alignment layer depend on where a contributor's finger stopped.

**One regression this introduced and it was caught by looking.** `hasSnapped` became per framing, and
`VisitCameraView` fired the shutter flash on `hasSnapped` turning true — the same event as a capture
while a visit held one photograph, and *not* the same event once selecting an already-photographed chip
also turns it true. Tapping between two filled chips flashed the screen white as though each tap had
taken a photograph. On a simulator or the library fallback that flash is the only confirmation a
capture has, so a false one is a lie about the one thing this screen has to be honest about. The flash
is keyed on `VisitCameraModel.captureTick` now — a counter incremented *after* the write, so a refusal
flashes nothing either.

### How each of these was made to fail

Reverting `VisitPhotoStaging.url` to `"\(visitID.uuidString).jpg"` is the deliberate break that
matters. Six tests fail with sixteen issues, and they name the loss in pixels rather than in
abstractions: the round-trip lands two photographs instead of three, one `photos` row keeps
`storageKey: nil` because the second upload found its source already moved, and the staged files all
measure 240×180. Replacing `PhotoBinary.write` with a plain `data.write(to:)` — a new capture path that
skips the strip, which is precisely E148's failure mode — fails the two new staging tests with 69
issues naming the GPS dictionary, `MakerApple`, `TIFF.Make`, `TIFF.Model` and `Exif.BodySerialNumber`
read off the written files.

Making `shotType`'s setter bump `captureTick` — which is the old flash behaviour, expressed on the
model — fails `theFlashCountsCapturesOnly` with "selecting a photographed chip flashed the screen 3
times". Taking the ghost from `shotType` rather than `.fullTree` fails
`theGhostComesFromTheFullTreeShot`. Requiring all three framings in `enqueue` fails
`twoOfThreeIsStorable`.

The one that did *not* fail is recorded above, because it is the more useful result: `shotTypeChips`
put back to an `HStack` left the AX5 measurement green, twice — once through the old whole-screen test
and once through the row-only rewrite — and that is what settled the question of whether an `HStack`
overflows at all.

### A correction to the inherited work

The tests as inherited used `VisitPreviewFixtures.outbox()` for two cases that *save*. That fixture is
deliberately unmigrated — "the previews draw the screens, they do not save from them" — so
`logVisit()` failed on a missing `outbox` table and returned nil, and the two tests read that as a
refusal of the framings they were about to assert on. They use a migrated queue now. It is the ordinary
version of this file's own thesis: a test can fail for a reason that has nothing to do with its
subject, and the reason it gives is the one you wrote in the assertion.
