# Rulings pending: pinch zoom on check-in and care log's camera (2026-09-29)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it
under a real number at merge. No code comment cites this filename.

---

### R??? — 05 and 09's camera gets the same pinch as screen 04 and add-a-tree

**Date:** 2026-09-29. **Ruled by:** the owner. **Source:** the owner's answer to the orchestrator's
question *"The check-in (05) and care-log (09) camera has no pinch zoom. Screen 04 and add-a-tree
now do (F33). Give 05/09 the same pinch?"*, verbatim: *"Yes, same pinch (Recommended)"*.
**Status:** ruled. Resolves `docs/ROADMAP.md` chip backlog 80.

**As built.** The following is the authoring agent's account, not the owner's words.
`ContributionCameraView` applies the shared `VisitCameraZoomPinch` to its viewfinder, on its own
`VisitCameraController`, before the ✕ and shutter overlays, as screen 04 does. It passes
`isAiming: true`. Screen 04's rule turns the pinch off when the viewfinder shows the still it just
took. This viewfinder never shows a still: each frame goes to the form and the preview stays live
for the next one. The other half of the rule, a lens to move (`isZoomable`), applies unchanged.

**Not seen on a phone.** No simulator has a camera, so the gesture never arms on one. Checking that
two fingers move the lens on 05 and 09's camera is part of the F33 phone check (chip backlog 81).
