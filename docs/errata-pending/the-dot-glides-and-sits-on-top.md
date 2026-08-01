# The location dot jumped between fixes and hid under the pins (tasks #149, #150)

**Unnumbered — pending. The orchestrator assigns the E number at merge.**

## #149 — the glide

`Coordinator.syncUserDot` wrote the new fix straight into the annotation's KVO'd `coordinate`, so
the view moved in one frame: a walking reader's dot teleported a few metres once a second. The fix
wraps the same write in a `UIView` animation — `MKMapView`'s own mechanism for interpolating an
annotation between coordinates, on the render server, inside #75's architecture. One object, one
view, zero SwiftUI passes: nothing per-update touches observable state, so the E139
~50-sessions-a-second class stays dead (the existing "an update that changes nothing costs
nothing" contract in `updateUIView` is untouched).

Three deliberate non-glides: the first fix (nothing to glide from), Reduce Motion (the position is
the answer, not the delivery — `applyCameraIfChanged`'s own rule), and a jump past
`MapLayout.userDotSnapDegrees` (~1 km): a teleport animated at 1 km/s would claim a journey that
never happened. Duration is `MapLayout.userDotGlideSeconds` (1 s, linear) to match CoreLocation's
~1 Hz cadence.

**Verified on the simulator with a moving `simctl location start` scenario; device verification is
still owed** — E139 stands as the warning that map-performance conclusions from the simulator are
historically wrong, so the glide's cost and feel need the owner's phone before this is called
done-done.

## #150 — the z-order

`MapMarkerView.apply` gave the dot `zPriority = .min` — under every tree pin — so on any dense
block the reader's own position vanished. The ordering is now three named tiers on `MapLayout`,
declared together so call sites cannot disagree:

- `userDotZPriority = .max` — the dot, topmost, above the selected pin's #89 emphasis too. It is
  small, single, and `isEnabled == false` (it steals no taps from the pins beneath it).
- `selectedPinZPriority = 750` — above every unselected neighbour (the reticle must not be
  half-covered, #89), below the dot.
- `pinZPriority = .defaultUnselected` — everything else, and the `prepareForReuse` floor.

Asserted structurally — the layer exposes `zPriority` — in
`MapMarkerRenderingTests.userDotIsTopmost` (dot > selected > unselected, reuse resets); mutation
M-C (dot back to `.min`) went red saying the right thing. Screenshot with the fix placed on a seed
tree's own coordinates is in the branch report.
