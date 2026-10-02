# Rulings pending: pinch zoom on check-in and care log's camera, and every camera opening at 1× (2026-09-29)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it
under real numbers at merge; it holds two rulings, and they may take one number or two. No code
comment cites this filename.

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

---

### R??? — every camera opens at 1×

**Date:** 2026-09-29. **Ruled by:** the owner. **Source:** the owner's answer to the orchestrator's
question *"Camera zoom now exists on three screens (04, add-a-tree, 05/09). When you close a camera
zoomed in and open another, should it start at 1× or keep the zoom?"*, verbatim: *"Always start at
1× (Recommended)"*. **Status:** ruled. Raised by PR #200's review (finding 3), which found the
carry-over undecided: `VisitCameraController` called it "decided by accident".

**As built.** The following is the authoring agent's account, not the owner's words.
`VisitCameraController.configureAndRun`, the one path that reaches a camera device, sets the lens
to 1× as each session starts (`VisitCameraZoom.openAtOneX`). 1× means 1 held inside the device's
current zoom range, and the controller's `zoomFactor` takes whatever the lens reads afterward. This
covers all three screens, because all three start their camera through that controller. The reset
is on start rather than in `stop()`, because a session that is never stopped would skip a reset in
`stop()`. While 05 and 09's camera stays open, the zoom still carries from shot to shot.

**Not seen on a phone.** No simulator has a camera device, so `configureAndRun` returns before it
reaches the reset. `ZoomTests` covers `openAtOneX` against a stand-in lens. That every camera opens
at 1× on the phone is part of chip backlog 81.
