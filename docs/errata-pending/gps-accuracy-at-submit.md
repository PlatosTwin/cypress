### Four contribution forms recorded the GPS accuracy from before the phone had one (#102)

Found while fixing E155, and it is the same mechanism read a second time. `@State` runs its
initialiser exactly once for the lifetime of a view's identity, so anything a view carries into a
model built there is the value that existed in the first frame and no other. E155 was a coordinate.
This is D6's per-contribution GPS accuracy, on the four views that carry one:

    Cypress/Features/CareLog/CareLogView.swift        — 09, the care log
    Cypress/Features/CheckIn/CheckInView.swift        — 05, the check-in
    Cypress/Features/Measure/MeasureView.swift        — 16, the measure sheet
    Cypress/Features/Visit/VisitCameraView.swift      — 04, the visit camera

Each took `gpsAccuracyM: Double?` and each was handed `location.availability.accuracyM` (or
`location.fix.accuracyM`) by its composition root, read once, at the instant the screen was built.

**Why this is not simply E155 again.** There the snapshot was straightforwardly wrong — an almanac
is a picture of where you are now, and freezing the coordinate froze the picture. Here the snapshot
is arguably *right*, and the argument for it has to be answered rather than ignored: a contribution
should carry the accuracy of the fix it was actually taken on, not a better one that arrived
afterwards. Attaching the newest accuracy to an append-only record would be a false claim about a
reading's provenance, and a quieter defect than the one being fixed — D6 exists so that a
measurement can be trusted to belong to the tree it names, and a precision the reading was never
taken at defeats exactly that. So the fix is **not** to make the value live.

**The defect is the cold launch.** The composition root's `MapLocationProvider` is inert until
screen 01 asks it to start, and CoreLocation then takes its own time; `VisitLocationProvider` is the
same. Open any of these four forms before the first fix lands and the model froze `nil`. A usable
fix then arrives while the form is still being filled in — a measure sheet is a kind, a method, a
unit and a number typed on a keypad; a camera session is up to three framings, a note and a chip
row — and the arrival was an event nothing in those screens could observe.

A `nil` accuracy is not a blank field. `FieldCaptured.isEligibleForGrowthCharting` treats it as
unusable rather than assumed good, deliberately and correctly ("unknown accuracy is treated as
unusable rather than assumed good", `CoreEntity`). So on screen 16 the whole of it lands: the person
walked to the tree, put a tape around the trunk at 1.4 m, typed the number, and the reading was
excluded from that tree's growth chart for the lifetime of the record, on a phone that had a
perfectly good fix by the time they pressed Save.

**What changed.** The parameter is a closure — `@escaping @MainActor () -> Double?` — which is the
shape `now` already has beside it in all four initialisers, and for the same reason: it is a
question about the present, and a form is a thing somebody fills in over a minute. Each model asks
it once, at the moment the contribution is written:

- `MeasureModel.save()`, `CareLogModel.save()` and `CheckInModel.save()` read it where they used to
  read the stored `Double?`.
- `VisitCameraModel.logVisit()` sets `draft.gpsAccuracyM` beside `draft.note` and
  `draft.phenologyTags`, which is where the other two properties of the contribution are already
  taken. The draft is built without one; the visit id still is minted at init, because that names
  the file the photograph is written to and has to exist before the shutter.

Submission is the moment the contribution exists, so this preserves the "accuracy of the fix it was
taken on" intent rather than trading it away — and it fixes the `nil`, because by the time a form
has been filled in a fix has almost always arrived.

`MeasureModel.presentation` reads it on every pass, which makes screen 16's chart notice — the
sentence under the CTA — track the fix. That sentence is a prediction about the next tap and has to
be made from the fix that tap would use. It withdraws itself when the first fix lands, which is
**not** E155's withdrawal: what it explained has actually stopped being true, and the screen it sits
on is full either way.

There is a race left, and it is the right one: the notice can say "chartable" and the fix can then
degrade in the second before Save, so the reading is stamped 40 m after being promised a dot. Both
sentences are true at the moment they are made, and any alternative freezes something.

**On whether D6's exclusion is silent, which was the second question.** It is not, and the premise
should be retired rather than acted on.

- Before the save, `MeasurePresentation.chartNotice` prints `Without a location fix the reading is
  saved but stays off the growth chart.` — and a separate sentence naming the metres when the fix
  is real and too poor. `ChartEligibility` has three cases and not two precisely so that the screen
  can say which.
- After the save, the reading is on screen 11's log. D6 excludes a reading from *charting*; it does
  not delete it, and `GrowthHistoryPresentation.logRows` carries every non-deleted measurement,
  dot or no dot. When nothing is chartable the screen prints a sentence where the cards would have
  been.

So E126's invariant — a screen showing nothing must say why — was already honoured at both ends.
What was wrong is one word of it. Screen 11's sentence read `taken with a GPS fix too weak to
attribute them to this tree`, which describes a bad fix to somebody whose phone had not answered
yet, and on the broken app that was not an edge case: the cold-launch population was the *whole*
population of nil-accuracy readings. `GrowthHistoryPresentation.noChartReason` now picks between
that sentence and `saved before the phone had a location fix`, on whether any reading in the record
carries an accuracy at all. This is screen 16's own rule — "no fix" and "a poor fix" are different
facts about the world although D6 treats them the same — applied to the screen that reports the
consequence.

Nothing was added to 04, 05 or 09. Growth charting reads measurements and only measurements
(`TreeMeasurement.isChartable` is its one gate), so a visit, a check-in and a care event lose
nothing by carrying a `nil`; a notice on those three would be a warning about a consequence that
does not exist.

**What the tests are.** `CypressTests/GPSAccuracyAtSubmitTests.swift`. Every warm-path assertion
passes either way — `MeasurementAccuracyTests` walks an accuracy end to end and was green against
this bug for the whole of its life — so each test here moves the fix *between* mount and submit and
asserts which of the two the record ends up carrying. One asserts the opposite direction: two
readings taken in one standing, either side of the fix improving, each keeping its own moment. That
one is the guard against a later round replacing the closure with a live value.
