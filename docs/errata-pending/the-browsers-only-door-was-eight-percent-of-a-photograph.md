# Screen 20's only door was 8% of the photograph everybody presses

**Found:** 2026-08-03, from a field report on a physical iPhone, reproduced on a simulator.
**Class:** a shipped, tested, correct feature that the gesture people make leads away from —
E173 again, on the half E173 named and did not build.

## The report

> when i click on the tree photo from a tree page, i can get to the view where I see all photos and
> can thumbs up/down them, change between all/full/trunk/leaf only very ocassionally, and sometimes
> not at all, instead seeing only the hero photo and no other photos and no option at all to thumbs
> up/down

## The state that decides it, in one sentence

**Nothing in the data decides it — the finger does:** screen 20 has exactly one entrance, the hero's
metadata pill, whose hit rectangle is 44 × ~178 pt in the bottom-trailing corner of a 430 × 224 pt
photograph, so roughly **8%** of the hero opens the browser and the other 92% opens
`PhotoViewerView` — one photograph, no set, no vote, no filter, and until now nowhere to go.

"Only very occasionally" is that 8% being hit by accident.

## How it was reproduced

`CYPRESS_SCREEN=photoHero` on iPhone 16 Plus (430 pt wide), which puts three photographs — full
tree, trunk, leaf — on one seed tree and opens screen 03 over it. Then two taps in device points,
each followed by a screenshot:

| tap | lands on |
|---|---|
| (215, 112) — the middle of the photograph | the viewer: one photograph, `Close`, a trash, **no thumbs, no segments** |
| (335, 201) — inside the pill | screen 20: three rows, `Hero` badge, thumbs, `All / Full tree / Trunk / Leaf close-up` |

Both surfaces are exactly what their code says they are. The screenshot of the first one is the
report, verbatim, in a picture.

## Why no test saw it

Every predicate involved is correct, and the ones a unit test can reach are the ones that were never
wrong:

- `TreeProfilePresentation.visiblePhotos` (own-aware) and `TreePhotosModel.load`
  (`isVisibleToItsContributor`, unconditional) return **the same rows on a shipping device**, because
  `LocalAPI.treeProfile` fills `ownPhotoIDs` with every row it read. Task **#191**'s divergence is
  real and is *not* this: it makes the browser show **more** than the pill counts, after a sync that
  does not exist yet, and could never leave the browser with less.
- `Series` is complete here — the profile reads photos with `limit: nil` — so
  `heroMetaPill` is drawn on every tree that has a photograph. The pill is never missing. It is small.
- Task **#154**'s subject filter has not regressed: all four segments draw and filter.
- Task **#48**'s gate is not involved: the thumbs are per row on screen 20 and are unconditional.

The defect is entirely in which of two adjacent surfaces a finger arrives at, which is only visible
to a test that presses things — E173 made this same argument about `PhotoDeletionTests` and it held
again here.

## The repair

The viewer gets the way onward that E173's own account of the defect named — *"no delete, **and no
way onward to the screen that has one**"* — and did not build. One control,
`All photos of this tree`, in the screen's control vocabulary rather than its caption vocabulary,
closing the cover and pushing `Route.photos` with `unlessAlreadyOnTop` so the same control pressed
from a viewer opened *out of* screen 20 means "back to the set" instead of stacking a second copy of
it. The design decision is written up as a pending ruling; this entry records the defect.

## The lesson, which is E173's restated

A control being reachable is not the same fact as a control being reached. Both times, the surface
somebody arrives at by making the obvious gesture had no route to the feature, and both times every
test of the feature passed. When a screen exists only behind one small control, the thing to check
is not whether that control works — it did — but what is at the other end of the gesture people
actually make.
