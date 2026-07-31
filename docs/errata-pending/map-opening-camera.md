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

**On screen 01, that hook has never once been the thing that aimed the map.** Measured on every cold
launch traced: `updateUIView` reaches `applyCameraIfChanged` before the deferred `onFirstLayout`
callback does, so by the time the hook runs the ticket is spent and it logs `REJECT`. Screen 01
re-runs its body often enough to produce its own pass the instant the size lands, exactly as the note
above guessed it would. The hook earns its place on the two quiet screens and as belt-and-braces here;
it should not be described as what closed this defect on the app's default screen, because it is not.

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

`MapHomeView.region` — the app's copy of where the camera is — held MapKit's own default for the
whole launch:

    region 37.1328,-95.7856   span 98.0°×61.3°

That is the geographic centre of the continental United States, sitting behind a map of Folsom Street
with the reader's blue dot in the middle of it. Everything downstream of the settled camera was
reading it: the recentre control's `Centred on you` (#100), a cluster tap's "two zoom levels in"
measured from a 98° span, and the camera this app now remembers between launches — which is why
nothing was ever written down.

**The first fix for this named the wrong mechanism, and the wrong one was ruled out by measurement.**
It said that aiming from inside `layoutSubviews` is re-entrant, that `setRegion` is honoured but
`regionDidChangeAnimated` "is never delivered", and it moved the aim to the main queue. The symptom
survived that change untouched. A probe in the layer itself, cold launch, iPhone 16 Pro, static fix at
37.7599, −122.4148, timestamps in milliseconds:

    .802 .838 .850  apply  REFUSE-no-area seq=0
    .857            settle region=37.132840 span=97.992432
    .870            apply  ACCEPT seq=0 to=37.759600
    .870            settle region=37.759600 span=0.002084
    .871            apply  WROTE parent.region=37.759600 readback=37.132840
    .875            layoutSubviews bounds={{0, 0}, {402, 874}}
    .885            apply  REJECT seq=0 applied=0
    .907            centreOnUserIfNeeded avail=located(37.7599, −122.4148)
    .907            flyTo 37.7599,-122.4148 metres=120
    .909            apply  ACCEPT seq=1 to=37.759900
    .915            settle region=37.759900 span=0.002084
    .916            apply  WROTE parent.region=37.759900 readback=37.132840

**The settle is delivered.** Twice, carrying exactly the right region. It was never suppressed. What
that trace shows instead is that the settle arrives in the *same millisecond* as the `setRegion` that
caused it — MapKit calls `regionDidChangeAnimated` synchronously from inside `setRegion` — and
`applyCameraIfChanged` is called from `updateUIView`. So both writers of `region` were running inside
a SwiftUI view-update pass, and **a `@State` write made during a view update is discarded.** The one
write that landed in the entire launch is the settle at `.857`, the only one that happened outside a
pass — and what it carried was MapKit's default. That is the number that stuck.

`Coordinator.echo(_:)` hands every camera back one runloop turn later, and is used by **both** writers
rather than only the one known to be unsafe today: the settle is synchronous under `setRegion` and
asynchronous after a real flight, and a value whose correctness depends on which of those happened is
a value that will be wrong again.

Verified on the running app, nothing pressed, launch state: `R 37.7599,-122.4148 S 0.00108 centred`.

**How it hid.** The whole unit suite was green. The map looked right in every screenshot. The camera
tests assert `mapView.region`, which is the truth, and the one thing that was wrong was the *copy* of
it the screen holds. It was found by launching the app with a debug readout of `region` drawn on top
of the chrome and reading the numbers — not by a test.

**What each test is now measured to catch.** Two deliberate breaks, built and run against
`CypressUITests/MapCentredStateUITests` on a simulator with a fix:

| Break | Result |
|---|---|
| baseline, fixed | `Executed 2 tests, with 0 failures` in 10.979 s |
| write `parent.region` inline instead of through `echo(_:)` — the real defect | `Executed 2 tests, with 1 failure` in 31.890 s — `XCTAssertEqual failed: ("Not centred") is not equal to ("Centred on you")` |
| aim re-entrantly from `layoutSubviews` (`announce?()` inline) | `Executed 2 tests, with 0 failures` in 11.082 s — **invisible** |

Two things follow, and both are worth more than the green line.

**The re-entrancy break is invisible because there is nothing to see.** On screen 01 the
`onFirstLayout` hook never applies a camera at all: `updateUIView` reaches `applyCameraIfChanged`
first on every launch and spends the ticket, so the hook only ever logs `REJECT` (line `.885` above).
No test guards it because no behaviour depends on it.

**Say this plainly, because the comment above it does not read that way.** `AimableMapView`'s
`DispatchQueue.main.async` carries a long, careful, confident note about re-entrancy, and the next
person to read it will assume it is load-bearing. On screen 01, as currently wired, **it is dead in
practice** — the whole hook, not just the hop. Mutating it either way changes no observable behaviour
and no test.

**It should nonetheless stay, and the reason changed during this round.** When it was written it was
insurance against a screen too quiet to produce another `updateUIView` pass once the size landed —
speculative, and on the one screen anybody measured, unnecessary. It stopped being speculative when
`mapViewDidChangeVisibleRegion` was gated on `appliedSequence != nil` (below): with that gate, a map
that is never aimed never reports a camera at all, so screen 01 would never fetch a tree and screen
16's pin would never track. The hook is now the thing that guarantees the aim eventually happens, and
that is a real job. Its note has been rewritten to claim that job and not the other one.

**Under the real break, the *pressed* test still passes.** A press produces a genuine animated flight
whose settle arrives outside the update pass and therefore lands. That is the entire content of "still
`Not centred` at launch, and a press fixes it": it is one bug, not two, and the unpressed test is the
only one that can see it.

`MapOpeningCameraApplyTests.theSettledRegionIsEchoedBack` pins that the echo exists — delete the write
and it fails — but it cannot see either break, because a map view outside a window and outside a
SwiftUI update pass reproduces neither condition.

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

##### Which of those four a simulator can actually produce

Driven on the running app rather than reasoned about, iPhone 16 Pro, one screenshot each.

| Asked for | `simctl` | What appeared |
|---|---|---|
| fix present | `privacy grant location` + `location set 37.7599,-122.4148` | map on Folsom & 9th, dot dead centre, **no notice**, control filled and reading `Centred on you` |
| permission revoked, no history | fresh install + `privacy revoke location` | Dolores Park, **Location is off** + "…The map is over the middle of the city." + Settings, control struck through |
| permission revoked, with history | as above, after one granted launch was backgrounded | **Folsom & 9th**, no dot, **Location is off** + "…The map is where you last left it." |
| never asked | fresh install + `privacy reset location` | Dolores Park, system sheet up, control in the plain `askable` drawing |

**`waitingForFix` is not reachable on a simulator, and that is a property of the design rather than a
gap in the testing.** Two things were confirmed by driving it. First, `xcrun simctl location <udid>
clear` does **not** unfix a device: on a fresh install with permission granted and the location
cleared, the map still opened centred on the fix with the dot in the middle — the only way to take a
fix away from the app is to take the *permission* away, which produces `denied`, a different state
with different copy. Second, `simctl location <udid> list` offers only City Run, City Bicycle Ride,
Freeway Drive and Apple; there is no no-fix scenario. And even if there were, `MapOpening.patience`
gates the notice at three seconds and a simulator answers from cache in well under one, so the
`searching` sentence is by construction only ever shown to a phone that is genuinely slow. That is
E158's lesson working as intended, and it means the row is exercised by
`CypressTests/MapOpeningCameraTests` and by nothing on a device.

**The remembered camera was verified end to end, and only works because of the fix above.** After one
granted launch was backgrounded, `UserDefaults` held:

    map.lastCamera = (37.759899, -122.414803, 0.001081, 0.001362)

Before the echo was repaired, `region` held a span of 98°, which `MapCameraMemory.isWorthRemembering`
correctly refuses as wider than `maximumSpanDegrees`. So nothing was ever written, on any launch, and
the third row of that table could never have been reached. Repairing the echo is what made the memory
real.

---

#### #100 was not the defect it was reported as

Reported as: the recentre control's accessibility state does not track whether the map is centred, so
VoiceOver announces the wrong thing.

Measured first, before changing anything. `MapCentredStateUITests.testTheControlSaysCentredOnceTheMapIsOnYou`
— launch, press the control, poll the spoken value — **passed on unmodified code**, so the pure
decision `MapRecentre.engagement(availability:camera:)` was never the fault. The reported defect, as
worded, does not exist.

But the conclusion first drawn from that green — "the wiring from `MKMapView`'s settle through
`MapHomeView.region` to `MapRecentre.engagement` was intact" — is **wrong, and it is wrong in the
direction that matters.** The wiring was severed; the press is simply the one path that survives it.
A press produces a real animated flight, its settle arrives outside the SwiftUI update pass, and the
write lands. Every camera the *app* sets on its own — the opening one, the fly-to-you — is applied
from inside `updateUIView`, and those writes were being discarded. So the control's spoken value was
false for the entire life of every launch nobody touched, and pressing it repaired the value as a side
effect of repairing the camera.

That is why `AlmanacGroupTapTests` could record `Not centred` for a 39-second run *and* a screenshot of
that same launch with the dot in the middle of the screen. Both observations were correct and they
were not in tension: the picture came from `MKMapView`, the sentence came from the app's discarded
copy of it. `Not centred` was not "a true statement about a map that had never moved" — the map had
moved, and the sentence was simply false.

So #100 as filed is one symptom of #115's second defect (E168), and fixing that fixes it. The witness
is `MapCentredStateUITests.testTheMapOpensOnTheReaderWithoutBeingAsked`, and the break table above
shows it going red with exactly the reported words while the pressed test stays green.

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
