# A deliberate pan died at the Journal tab, and the one-shot was re-arming itself (task #128)

**Unnumbered — pending. The orchestrator assigns the E number at merge.**

## The mechanism, verified (the ticket's suspicion was right, and it was only half the story)

`RootView` builds each tab root on a `switch`, so Map → Journal → Map destroys `MapHomeView` and
remakes it. Two things died with it:

1. **`hasCentredOnUser` (@State) re-armed** — the ticket's suspected mechanism, confirmed in code.
   The remade screen re-ran the one-shot fly-to-you over whatever camera the reader had, which is
   closed ticket #85's defect arriving through the tab bar. E168's `Coordinator.echo` fix never
   covered this: that was about camera *writes* landing, not about a one-shot re-arming.
2. **The opening `@State` re-read `MapCameraMemory.remembered`** — which is frozen at launch *by
   design* ("where you left the map last time" must not drift as the reader pans). So even with no
   fix and no one-shot, a within-session pan reopened on last launch's camera. The plain
   tab-switch-lands-correctly observation in the ticket holds only because an untouched camera and
   the re-centred one coincide.

## The fix, on the seam the brief named

`MapCameraMemory` (session-scoped, in-memory, survives the identity reset) grew two facts:

- **`sessionSnapshot`** — the camera the reader left screen 01 on this session, written by the
  same `note()` the persistence path uses, behind the same `isWorthRemembering` gate (the seam
  E168 verification proved). `openingSnapshot` = session ?? launch, and the remade screen opens on
  it.
- **`readerMovedCamera`** — set by a pan or pinch that *began on the glass*, observed by two
  additive gesture recognizers on the `MKMapView` (`cancelsTouchesInView = false`, simultaneous
  recognition). Never set by comparing camera values — E140 established no such comparison can
  tell a reader's move from a stale update pass. The one-shot consults it: a camera the reader
  deliberately moved is theirs; a camera they never touched may still centre on them (#115's
  promise kept — the flag is per-process, so a relaunch still opens on the reader).

No re-centre on appearance was added anywhere; the one-shot still fires at most once per process
unless the reader has claimed the camera, in which case never.

## Tests

- Unit: `MapOpeningCameraTests` — session-beats-launch precedence (and `remembered` still frozen),
  `isWorthRemembering` gating the session snapshot, flag lifecycle. Mutation M-D (note() stops
  writing the session snapshot) went red saying the right thing.
- UI: `MapPanTabSwitchUITests`, both directions, witnessing the camera through the recentre
  control's accessibility value (`MapCentredStateUITests`' technique, fixless-skips included):
  a pan survives Journal-and-back (held open 8 s so a re-arming one-shot would hang itself), and
  an untouched camera still centres after the round trip.
