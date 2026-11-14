# Errata pending: screen 17's pill now draws `· offline` (ROADMAP 110, 2026-11-14)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". It was written on
`on/110-offline-pill`. It amends **E81**, which it does not replace.

---

### E??? — E81's dropped `· offline` clause is drawn, from the network path and nothing else

**What E81 said.** SCREENS.md 17 §1 draws the amber pill as `3 waiting · offline`. E81 dropped the
clause because nothing in the app knew whether it was offline, and a failure sentence such as
`No connection.` records the last attempt, not the present.

**What changed.** F35 (#208) added `NetworkPathSource`, one `NWPathMonitor` for the process. It
answered only "is the path unmetered", for the wi-fi toggle. That answer cannot say offline: a phone
on cellular is metered and connected. The source now also reports `connectedNow()` and
`connectedChanges()`, read from the same monitor. Connected is false only when
`NWPath.status == .unsatisfied`.

**What "offline" means.** The pill reads `N waiting · offline` only when rows are waiting **and** the
source has read the path **and** found its status `.unsatisfied`. Otherwise it reads `N waiting`:

- Before the first reading arrives, there is no claim. `connectedNow()` is nil and the pill has no
  clause.
- `.requiresConnection` is not offline. Apple defines it as a path that is not active now but that
  a new connection may bring up (VPN On Demand with an idle tunnel, some cellular cases), so the
  next drain may succeed.
- A phone on cellular with "Sync photos on wifi only" on is connected. It is not offline.
- A row's failure sentence is never the source.
- At zero waiting there is still no pill (ARCHITECTURE §5.6).

`OutboxViewState.followConnection()` keeps the reading current. `OutboxView` runs it in its own
`.task`, so the clause changes while screen 17 is open and the listener stops when the screen goes.
The pill has no accessibility label of its own, so VoiceOver reads the same text.

**Debug seam.** `CYPRESS_NETWORK_PATH=offline` now pins a path with no connection, beside
`metered` and `unmetered`. No UI test uses it yet: the UI suite has no way to put a waiting row in
the outbox, because with the network gate off a row is applied locally and finishes at once.

Tests: `OutboxOfflinePillTests`.
