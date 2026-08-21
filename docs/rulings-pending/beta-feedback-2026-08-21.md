# Ruling (pending number): the beta-feedback round of 2026-08-21

**Date:** 2026-08-21. **Decided by:** owner, on TestFlight tester feedback.

## Provenance of the feedback

App Store Connect pull, run **32497784558**, covering **builds 18–41**. Everything ruled below
comes from a tester's own words on a shipped build; nothing here is an agent's proposal that the
owner agreed to. The two build numbers that appear against specific defects (25, 37) are the
builds the reports were filed against, not the builds the defects were introduced in.

Six items were ruled **in scope** for the polish round and two were **deferred**. Both lists are
recorded, because a deferral is a decision and re-raising a decided item is a documented failure
mode in this project.

---

## In scope

### 1. The map card must never name a tree it has not read (defect, build 37)

> *"first tree tapped after app open shows 'Unidentified · 25 m N' for about a second, then
> corrects to the right species"*

**Ruled:** the bottom card on screen 01 must never show a wrong identity. A loading or placeholder
state is acceptable and so is awaiting resolution; a flash of wrong data is not.

The card is drawn synchronously from the pin so the tap feels answered, and the profile read lands
after it — that is the design and it is not what was ruled against. What was wrong is that
`MapCardSubject.title` had no value for *not knowing yet* and fell through to the literal
`"Unidentified"`, which is a claim about the species. "Still reading" and "read, and there is no
species" are now two values, and only the second says the word.

### 2. The visit sheet paints its own ground under the keyboard (defect, build 25)

> the region behind and around the keyboard on the dark visit-logging sheet renders pure white

**Ruled:** fixed, in tokens, with no raw values (ARCHITECTURE §6). Screen 04 is dark regardless of
the system setting and the ground under the keyboard is part of that screen.

### 3. Outbox stamps say the date once a list spans days

> synced rows read `1:49 pm` on a list whose rows are from different days

**Ruled, verbatim in effect:** *show the date instead of the time once the list spans more than one
day, otherwise the time.* It is a property of the list, not of the row: one answer for one list, so
that every stamp in it is the same kind of fact and the rows can be read against each other.

### 4. The full-screen photo viewer gets pinch zoom

**Ruled in.** Standard pinch to zoom, pan while zoomed, and double tap to return to the whole
frame.

This **overrules the viewer's own recorded decision not to have one.** `PhotoViewerView`'s header
carried a section titled "Why there is no pinch-to-zoom", which closed: *"If somebody asks to look
closer, that is a second report and it can have its own entry."* Somebody asked. The section is
rewritten rather than deleted, and one of the three costs it named is now recorded as having been
wrong: it feared "a gesture that fights the cover's own dismiss drag", and this screen is presented
in a `fullScreenCover`, which has no interactive dismissal. That concern was `.sheet`'s.

### 5. The capture screen gets pinch zoom

**Ruled in.** Pinch to zoom while shooting, through `AVCaptureDevice.videoZoomFactor` — the lens,
not a transform on the preview, so what is captured is what was aimed at.

The ceiling over the hardware's own is **NOT SPECIFIED** and was chosen in the implementation
(`VisitCameraController.preferredMaxZoom`); it exists so that a volunteer cannot attach an upscaled
smear to a record. If the owner wants a different number it is one constant.

### 6a. Screen 18 offers three functions

**Ruled:** the visit-saved screen's control set is **next nearest, back to the map, back to this
tree**. This replaces `Next nearest` / `Done for today` / `See it on the tree's timeline`.

**The functions are ruled and the copy is not.** The strings shipped in this round are the
implementation's draft (`VisitSavedCopy`) and may be replaced without touching anything else.

Two of the three functions already existed under labels that named the mood of leaving rather than
the place being left for. `Done for today` called `goToMap()`, so a person who wanted the map for a
moment had to declare an end to their morning to reach it; `See it on the tree's timeline` pushes
the tree's *page*, of which the timeline is one band. The destinations have not moved.

`Route done · see your grove` is **not** a fourth control and is untouched: it is the primary CTA's
other state, for when the route is finished (PROTOTYPE-FLOW §1.6 rule 5).

### 6b. The map gets MapKit's own compass

**Ruled:** a MapKit-native compass on screen 01, visible only when the camera is off north, tapping
it returns to north.

This **overrules the reasoning recorded at the call site**, which was that SCREENS.md 01 lists map
controls under **NOT SPECIFIED** so none should be added. What that reasoning missed is one line
below it: `isRotateEnabled = true`. A map that turns and does not say which way is north can be
left pointing somewhere the reader did not choose, with nothing on screen to undo it.

`MKMapView`'s own behavior for `showsCompass` is exactly the ruling — `MKCompassButton` fades in on
rotation, fades out at north, and its tap animates the camera back — so no glyph of ours is
involved and R57's no-SF-Symbols policy is not in question.

---

## Deferred (decided, not forgotten)

### Grove statistics: a date-range filter

A tester asked for a way to narrow the Grove's figures to a period. **Deferred**, not refused: it
is a real request and it is not beta-polish. It wants a design pass of its own — which figures a
range applies to, what the default range is, and what the screen says when a range contains
nothing — and none of that is drawn in SCREENS.md.

### Coverage outside San Francisco: Marin, Sausalito, Mill Valley

Testers asked for trees in Marin County, Sausalito and Mill Valley. **Deferred, and reframed:** it
is not a defect and it is not a feature request the app can answer on its own terms. It is an
**inventory question for the distribution plan** — whether those jurisdictions publish a street
tree inventory this project may ingest, under what license, and whether a second and third city
file is what the seed/city download path should be spending its budget on next. It goes to whoever
owns the distribution plan, not to a UI round.

---

## Consequences

- The two overrulings above (4 and 6b) are the reason this entry exists rather than a set of
  commit messages: both reversed a decision that was argued in a code comment, and a reader who
  finds the old reasoning in the history needs to be able to see that it was overruled on purpose
  and by whom.
- The copy for screen 18's two new controls is **open**, and the round that closes it is a copy
  decision, not a design one.
- Nothing here authorizes a schema migration, and none was taken.

---

## Addendum, 2026-08-21 — the copy decision closed

The owner chose the implemented draft in a decision round: **`Back to the map`** and
**`Back to this tree`**, with `Next nearest` unchanged. Screen 18's copy is no longer open; a
later change to these strings is a new decision, not a continuation of this one.
