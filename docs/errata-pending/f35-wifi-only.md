# Errata pending: "Sync photos on wifi only" did nothing (F35, 2026-11-13)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". It was found in beta
feedback F35 (2026-09-30), logged as ROADMAP item 98, and fixed on `fix/f35-wifi-only`. The defect
**shipped**: every build until this one sent photographs over cellular with the toggle on.

---

### E??? — Every drain sent photographs, because the toggle's only reader had no caller

**What happened.** A tester on cellular, with screen 17's "Sync photos on wifi only" on, saw their
photographs upload. `OutboxQueue.drain(photoUploadsAllowed:)` was the one place that holds a
binary back, and its parameter defaulted to `true`. All six feature writers,
`OutboxViewState.retry` and `retryAll`, and `VisitGates` called `drain()` and took that default.
The one call that resolved the toggle, `OutboxViewState.syncNow(isOnWifi:)`, had no caller, because
nothing in the app could say whether the connection was wi-fi.

**The fix.** The queue decides. `OutboxQueue` takes a `NetworkPathSource`, and `drain()` reads the
stored toggle from `app_state` and asks the source whether the path is unmetered (satisfied, not
expensive, not constrained). `DataLayer.boot` passes the process's one `NWPathMonitor`
(`SystemNetworkPath.shared`). `drain(photoUploadsAllowed:)` lost its default. `syncNow(isOnWifi:)`
is gone. By the owner's decision of 2026-11-13, waiting photographs also go by themselves: the
layer's `OutboxWifiWatcher` drains when the path turns unmetered and a photograph is waiting, and
`RootView` drains when the app comes to the front. Turning the toggle off drains too.

**The 48 h cap, which F35 made reachable.** The drain's expiry phase failed any due row whose
window was older than 48 h. Nothing had ever held a photograph back, so no waiting row could reach
it. Once the toggle works, a photograph held back on a two-day trip without wi-fi would have
expired as "Tried for 48 hours without getting through", on a note saved the whole time. The
expiry phase now skips a row whose reason is `awaitingWifi`. Any real failure overwrites that
reason, and the cap applies again.

**Why no test saw it.** Every test of the deferral called `drain(photoUploadsAllowed: false)`
itself, so each one proved the queue could hold a photograph back and none asked whether anything
in the app ever told it to. `OutboxWifiOnlyTests` now saves through a real feature writer, and it
fails if any app source passes its own answer to `drain(photoUploadsAllowed:)`.

**What this makes stale.**

- **E81** says "There is no reachability monitor, no `NWPathMonitor`". There is one now. Its
  conclusion about screen 17's `offline` pill still holds: the source answers "is this connection
  unmetered", not "is the phone offline", and the pill is still not drawn. Drawing it is a separate
  item.
- **E271 §6a** records that `syncNow(isOnWifi:)` had zero call sites. That was true, and it is now
  removed rather than called.
- **RULINGS** (the 2026-08 photo-browser note, "What the owner most plausibly saw") explains a
  browser showing only full-tree shots by binaries sitting `awaitingWifi`. Until this fix that
  window could not open, because nothing ever deferred a binary. It can open again now.

**DEBUG seam.** `CYPRESS_NETWORK_PATH=metered|unmetered` in the launch environment pins the path,
the way `CYPRESS_LOCATION` pins location, so screen 17's waiting state can be seen on a simulator.
