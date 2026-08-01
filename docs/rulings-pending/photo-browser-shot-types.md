# The photo browser gains segmented access by framing (task #154)

**UNNUMBERED — pending. The orchestrator assigns the R number at merge and rewrites any code
comments that cite this filename.**

**The report.** Owner's device walk, 2026-07-31: "the photo browser shows ONLY full-tree shots;
leaf and trunk photos are unreachable."

**The premise, checked before building on it — and refuted at the code level.** There is no
`.fullTree` filter anywhere on the browsing path. `ContributionStore.photos(treeID:)` selects
every undeleted row of every shot type; `TreePhotosModel.load()` filters only
`isVisibleToItsContributor` (tombstones); screen 20 draws every row it gets and already captions
them `Trunk`, `Leaf close-up`, `Photo`. The capture, staging, outbox and upload path carries the
framing end-to-end (E152), and `VisitCameraSessionTests.threePhotographsRoundTrip` proves three
framings land as three rows. Nothing to check under #47 either: the full-tree preference lives
only in the hero *heuristic* (`Photo.isBestPhotoShot`, `PhotoHero.choose` tier 3), which is not
on the browser's path.

What the owner most plausibly saw: photo binaries upload only when `photoUploadsAllowed`
(the wi-fi gate) — a visit's JSON can land while its trunk/leaf binaries sit `awaitingWifi`, and
in that window the only photographs *in the table* are community-add photos, which `addTree`
inserts directly and labels `.fullTree`. That is a browser showing only full-tree shots, with the
mechanism in the outbox rather than in a filter. Field confirmation is the owner's — check the
outbox screen for `awaitingWifi` rows next walk.

**The decision (pre-authorized in the task): the browser gains a segmented subject filter, in
place, no new screen.**

- Segments: `All · Full tree · Trunk · Leaf close-up` — the whole timeline first, then the three
  framings screen 04 offers, in the chip row's own order, each named by
  `TreePhotosPresentation.subject(_:)` so the segment and the caption cannot spell one framing
  two ways.
- No segment for `.other`. Nothing in the app lets somebody frame a shot as "other" — the value
  exists for care photos and for pre-shot-type outbox rows — so a segment would name a choice
  nobody made. `.other` rows are on the timeline under `All`.
- The filter is a **view** of the timeline, not a different read: the hero, `deletablePhotoIDs`
  and the community-add sentence keep answering for the tree. An empty slice of a photographed
  tree gets its own sentence naming the framing, because "no photos of this tree yet" would be
  false with the timeline one tap away.

**Hero voting is untouched — and one premise in the task is corrected on the record.** The task
says "keep hero voting full-tree-only". The shipped rule (E125, A3's escape clause) is that a
thumbs-up is the manual pin and **overrides** the full-tree heuristic — an up-voted leaf can lead
the page, deliberately, because a person's "this one" outranks a shot type. This change does not
touch `PhotoHero`; narrowing the vote's power to full-tree would be a reversal of E125, which a
browser-affordance ticket has no standing to make. What "full-tree-only" is true of is the
*heuristic tier*: with no votes, the hero is still the most recent full tree.

**The anonymized-photos half of the ask.** No, ownerless photos are not excluded by any browser
filter — screen 20 gates on `deletedAt` alone, and under `LocalAPI` `ownPhotoIDs` is every row on
the device, so `TreeProfilePresentation.visiblePhotos` keeps them too. The latent risk sits one
layer out, for whichever round builds `RemoteAPI`: `visiblePhotos` shows a non-own photo only if
`isPubliclyVisible`, and nothing in the app can ever set `.approved` — so the day `ownPhotoIDs`
becomes a real ownership set, an anonymized (`PhotoOwner.nobody`) photo drops out of the hero,
the pill count and the season strip while remaining in the browser. That is #131's territory and
is not fixed here; it is named so the next round does not find it by report.
