### The map opened on Mission Dolores Park with a perfect GPS fix in hand (#115, #100)

The owner: *"Opening the app should open on where you're located right now, 100% of the time."*

Reproduced on the simulator with location granted and a fix set over Van Ness: screen 01 opened on
`MapLayout.defaultCentre` — 37.7596, −122.4269, Mission Dolores Park — and stayed there for the life
of the launch. Not for a second before CoreLocation answered. Permanently, with the fix already on
`location.availability`.

`AlmanacGroupTapTests` had recorded half of this in its own header and read it the other way round:
*"the control reads `Not centred` for a whole 39-second run, and a screenshot of that same launch has
the camera on the fix and the reader's blue dot in the middle of the screen. Something between the
settled region and `MapRecentre.Camera` disagrees with the picture; whatever it is, it belongs to
screen 01 and not here."* It did belong to screen 01. The control was telling the truth; both
sentences were about a map that had never moved, and the screenshot came from a launch where the
timing happened to go the other way.

**The camera request was thrown away, not never made.** A probe in the layer itself, on a cold launch:

    MAKE   seq=0 bounds=(0.0, 0.0) to=37.7596      ← makeUIView, zero frame, asks for the fallback
    MADE   region=37.3346                          ← MapKit did not take it; 37.3346 is its own default
    APPLY  seq=1 bounds=(402.0, 874.0) to=37.7599  ← the fly-to-you, applied at full size, in a window
    REJECT seq=1 applied=1  ×∞                     ← and every pass after it, forever

A freshly constructed `MKMapView()` has `bounds == .zero`; SwiftUI lays it out afterwards. `setRegion`
on a map with no area does not take — measured, the region set to 37.7596 read back as 37.3346 — but
`makeUIView` recorded the ticket as applied anyway. So the request minted by the first GPS fix was
already stale by the time there was a map to show it on, and it was dropped. There is no retry:
`MapHomeView.hasCentredOnUser` is a one-shot (#85) and had already fired.

`MapCameraRequest`'s ticket is not at fault and is not weakened here. E140 established that camera
*geometry* cannot be compared because an update pass can arrive carrying state from before the
reader's last gesture. What was wrong is that a number was spent on a camera nobody was shown.

**The fix.** `applyCameraIfChanged` refuses a map it cannot aim, without spending the ticket — the one
early return in that method that does not record the request, because it is the one case where the
camera has not been superseded and has not been seen. `makeUIView` no longer sets a region at all.
`AimableMapView` supplies the single layout hook a `UIViewRepresentable` does not have, and aims at
whatever the app wants *by then*: the remembered opening camera if no fix has landed, the reader's own
location if one has. Both orders arrive at the same place.

**A second road to the same defect, closed at the same time.** `MapLocationProvider` is the
composition root's, shared with screens 09, 12, 16 and the visit flow, and `RootView` wires
`onRequestLocation: { location.start() }` in three places. Arrive on screen 01 after any of them and
`availability` is already `.located` — so `.onChange(of:)` never fires, because the value never
changes. The one-shot is now also called from `.task`, and `centreOnUserIfNeeded()` is the single
place that decides.

---

#### The regression this fix introduced, and how it hid

Worth more than the original defect, because it is the class of bug this project keeps finding: **a
value that looks answered and is not.**

Aiming the map from inside `layoutSubviews` is a re-entrant call into a view that is mid-layout.
`setRegion` is honoured — so the map on the glass is on the right street and every screenshot looks
perfect — and `regionDidChangeAnimated` is never delivered. Nothing else writes
`MapHomeView.region`, so it kept MapKit's own default for the whole launch:

    region 37.1328,-95.7856   span 98.0°×61.3°

That is the geographic centre of the continental United States, sitting behind a map of Van Ness and
Market. Everything downstream of the settled camera was reading it: the recentre control's
`Centred on you` (#100), a cluster tap's "two zoom levels in" measured from a 98° span, and the camera
this app now remembers between launches — which is why nothing was ever written down.

**How it hid.** The whole unit suite was green. The map looked right in every screenshot. The camera
tests assert `mapView.region`, which is the truth, and the one thing that was wrong was the *copy* of
it the screen holds. It was found by launching the app with a debug readout of `region` drawn on top
of the chrome and reading the numbers — not by a test, and no test in the suite would have found it.

`AimableMapView` hands its callback to the main queue instead. One frame, and the callback is an
ordinary event again.

**The witness is a UI test, and this was measured rather than assumed.**
`MapOpeningCameraApplyTests.theSettledRegionIsEchoedBack` pins that the echo exists — delete the write
and it fails — but a hook mutated back to firing inside `layoutSubviews` leaves it **green**, because
a map view that is not in a window does not reproduce MapKit's suppression. The test that fails is
`MapCentredStateUITests.testTheMapOpensOnTheReaderWithoutBeingAsked`, with the control reading
`Not centred` on a phone that knows exactly where it is. Both tests are kept and each says which half
it holds.

---

#### Where the map opens now, and what it says about it

**Opening on the reader is only two thirds of "100% of the time", and the third part is the one that
gets skipped.** There is a window before CoreLocation answers, and there are states where it never
will, and in every one of them the map is showing a piece of San Francisco that is not where the
reader is standing. ERRATA **E126** governs: a screen showing something other than what you asked for
must say why. **E158** is the warning — screen 11 spent its life telling people their GPS fix was
"too weak" when their phone had merely not answered yet, and the cold-launch population was the
*entire* population of that message.

`MapCameraMemory` remembers the camera the reader last left the map on. A place they have actually
been beats a stranger's park: the app reopened in the same neighbourhood is very nearly right, and
Dolores Park survives as the answer to the one question nothing else can answer — a first launch, no
history, no fix. `UserDefaults` rather than `app_state`, for `VisitSaveLedger`'s reason (a UI fact,
not a contribution) and one that decides it outright: `CypressStore.appState(_:)` is `async`, and a
camera that arrives one `await` after the first frame is the defect performed slightly faster.

The write is **not on the pan path**. Tasks #51, #75 and #84 were all map performance and #84 was the
basemap re-evaluating some 200 times a second at rest; a settle updates a struct in memory and the
write happens once, when the app leaves the foreground or the screen goes away. There is no debounce
timer to tune. `noteDoesNotWrite` asserts it: fifty settles, nothing in storage.

Four standing states now, and no two of them read the same:

| State | What the map shows | What it says |
|---|---|---|
| `located` | the reader | nothing — there is nothing to explain |
| `notAsked` | remembered camera, or the city | **Cypress has not been given your location.** Nothing has answered the location request yet, so there is nowhere to centre the map. + where it is |
| `waitingForFix` | remembered camera, or the city | **Finding you.** Cypress has permission and is still waiting for a first fix. + where it is + it will move as soon as one arrives |
| `denied` / `servicesOff` | remembered camera, or the city | **Location is off** / **Location Services are off.** The map still works—it just cannot show where you are… + where it is |

Two things about that table. The last row's two titles were already distinct (`MapLocationCopy.title`)
and stay so. And every row carries a clause naming **what the reader is looking at instead** — "The
map is where you last left it" or "The map is over the middle of the city" — which is the half of E126
that was missing. The old sentence explained the absence of the dot; it said nothing about the presence
of a particular stretch of city, and a reader who has never been to Dolores Park was left to assume
the app thought they were there.

The two waits are given `MapOpening.patience` — three seconds — before they say anything, because a
notice that flashes on every healthy launch teaches the reader to stop reading the slot it appears in.
The refusals are said at once: nothing is coming, so there is nothing to be patient about.

---

#### #100 was not the defect it was reported as

Reported as: the recentre control's accessibility state does not track whether the map is centred, so
VoiceOver announces the wrong thing.

Measured first, before changing anything. `MapCentredStateUITests.testTheControlSaysCentredOnceTheMapIsOnYou`
— launch, press the control, poll the spoken value — **passed on unmodified code**. The wiring from
`MKMapView`'s settle through `MapHomeView.region` to `MapRecentre.engagement` was intact, and the
`Not centred` the owner and `AlmanacGroupTapTests` both saw was a true statement about a map that had
never moved. That is #115, and fixing #115 fixes the symptom.

What was genuinely wrong is narrower and is still an accessibility defect. `Engagement` had three
cases and `away` carried all of "I know where you are and the map is not there", "nobody has answered
the permission ask" and "I am still looking" — and `MapRecentreCopy.value` spoke one word over all
three: `Not centred`. For a sighted reader that is a caption on a picture they can also see. For a
VoiceOver reader it is the *entire* report on where the map is, and in two of the three states it
describes a relationship that does not exist: there is no "centred" to be short of, because the app
does not know where the reader is, and pressing will not move the camera at all — it will raise a
permission sheet, or promise a move later.

So it is E126 arriving at the one control whose whole purpose is that no press is ever silent, and the
fix is five cases where there were three: `centred`, `away`, `askable`, `searching`, `unavailable`,
each with its own spoken value and its own hint about what the press will do. The *drawing* is
unchanged — `askable` and `searching` still look exactly like `away` did, because a control that
changed colour while CoreLocation thought about it would be flicker with no information in it, and
only `unavailable` is struck through. `engagementTracksThePress` holds the shape: every availability
that presses differently now describes itself differently.
