# Rulings pending: pinch zoom on add-a-tree's viewfinder (F33, 2026-09-28)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it
under a real number at merge. No code comment cites this filename. The comments name the report
(F33) and RULINGS R80 item 5.

---

### R??? — R80 item 5's pinch zoom covers add-a-tree's viewfinder

**Date:** 2026-09-28. **Ruled by:** the owner, confirming the question `docs/ROADMAP.md` F33 put to
them. **Status:** ruled.

**The ruling.** RULINGS R80 item 5 ruled in pinch zoom on screen 04's viewfinder. The owner rules
that it **covers add-a-tree's viewfinder too**. Add-a-tree gets the same gesture on the same
`VisitCameraController`, with the same lens ceiling (`VisitCameraController.preferredMaxZoom`).
Nothing about the zoom is decided anew here.

**The report.** Build 77, 2026-09-28, verbatim: *"Need ability to zoom in on photo in this view"*.
The screenshot shows add-a-tree's live viewfinder (`Take the photo`, with `Add this tree` disabled).
This was the third pinch-zoom report, and it came from the one camera surface R80 had not reached.

**As built.**
- **Location.** The gesture lives in one place, `VisitCameraZoomPinch`. Screen 04 and add-a-tree
  both apply it, so neither screen carries its own copy.
- **When it is on.** The rule is screen 04's: a lens to move (`isZoomable`), and a live frame rather
  than a still. Screen 04 passes `!hasSnapped`. Add-a-tree has one framing and passes
  `isAimingCamera` (no photograph yet). The pinch is off once a photograph is in the well, and back
  on after `Retake`.
- **Where it sits.** On add-a-tree it is on the photo well only, so the shutter, the library button
  and the rest of the form keep their own touches.

**Not seen on a phone.** No simulator has a camera, so the gesture never arms on one. Two things
are still to be checked on the physical phone: that two fingers on the well move the lens, and that
the pinch coexists with the composer's `ScrollView`.
