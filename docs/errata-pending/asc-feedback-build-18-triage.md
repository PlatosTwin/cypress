# Real tester feedback on build 18, and what the App Store Connect API will and will not tell us

*Unnumbered — the orchestrator splices the real E-number at merge.*

## What was pulled, and how

`Tools/appstore_connect.py feedback` and `.github/workflows/asc-feedback.yml` were added so this
question can be asked at all. No machine of the owner's carries an App Store Connect key, by
design; the credentials exist only as the three repository secrets, so the read runs on a GitHub
runner and hands back an artifact. Same shape as `asc-status.yml`: ubuntu, no Xcode, about a
minute.

Four collections are read, all GET, nothing written. Every path and attribute name was taken from
Apple's current documentation data on 2026-08-07, not from memory:

| collection | endpoint |
| --- | --- |
| screenshot feedback | `GET /v1/apps/{id}/betaFeedbackScreenshotSubmissions` |
| crash feedback | `GET /v1/apps/{id}/betaFeedbackCrashSubmissions` |
| crash log text | `GET /v1/betaFeedbackCrashSubmissions/{id}/crashLog` |
| public reviews | `GET /v1/apps/{id}/customerReviews` |
| release state | `GET /v1/apps/{id}/appStoreVersions` |

**Run 31195352441, 2026-08-07, `notes: []`** — nothing was truncated or forbidden:

- **2 screenshot submissions**, both from one tester, both on **build 18**, both on an iPhone17_5
  running iOS 26.5.2 at 390 × 844 pt, 40 seconds apart.
- **0 crash submissions.** No tester has hit a crash TestFlight caught.
- **0 customer reviews**, and this one is not evidence of anything: the app's only App Store
  version is `1.0` in `PREPARE_FOR_SUBMISSION`. It has never been on the store, so
  `customerReviews` cannot be anything but empty until it is. The command records
  `appStoreVersionsReadable` precisely so an empty review list is never read as "nobody reviewed
  it" when it means "there is nothing to review".

Two notes on the tooling itself, both deliberate:

- **Tester email is never read.** Both submission resources carry the tester's `email`. The
  command asks for its fields by name and `email` is not among them, so it cannot reach a CI
  artifact that anyone with repo access can download for months. The opaque tester relationship id
  is kept instead, which is enough to tell testers apart and to tie several reports to one person.
  Verified on the real artifact: zero `@` characters in the JSON. The address is also never
  *fetched*: `include` asks only for `build`, because an included `betaTesters` resource carries
  `email` too, and the tester id the command wants is in `relationships.tester.data.id` without it.
  Not asking is structural where filtering afterwards is a promise.
- **The screenshots are downloaded, not just linked.** Apple serves them from pre-signed URLs that
  expire — the two here expire 2026-08-14 — so a JSON kept for comparison would point at nothing
  within the week. The images travel in the artifact and the JSON records the expiry. The download
  is `https`-only, size-capped, and writes to a filename this program constructs from a sanitized
  id: the id, the URL and the body all come from the network, and none of them may decide what CI
  reads off disk or where it writes.

## The feedback, and what it is

### 1. "Text about ghost photos is cut off and flows poorly" — a real defect, fixed here

The tester circled the ghost caption on screen 04. The caption reads `no ghost yet · first photo`
and renders as four lines of one or two words each, down the left of the viewfinder beside the
shutter.

Nothing is literally clipped — every word is present — but the tester's reading of it as "cut off"
is fair, and one contributing cause is a straightforward transcription defect:

`CypressFont.LineSpacing` states the project's CSS→SwiftUI conversion, because CSS `line-height`
includes the glyph box and SwiftUI's `.lineSpacing()` is only the gap added between lines:

    lineSpacing ≈ size × (lineHeight − 1.2)

Its four numeric tokens obey it exactly — 15/1.55 → 5.25, 13.5/1.50 → 4.05, 12.5/1.45 → 3.125,
11.5/1.30 → 1.15. (`speciesHero` and `treeNameHero` are clamped to 0: their mock line-heights are
*tighter* than the natural box, so the formula would go negative. They sit outside the rule by
their own documented intent, not in violation of it.) SCREENS 04 gives the caption mono 10.5px at
`line-height:1.4`, which converts to **2.1**. `VisitMetrics.Camera.ghostCaptionLineSpacing` was
**4.2** — `10.5 × 0.4`, which is the subtraction performed with the **wrong constant**: the font's
natural line box taken as 1.0 instead of 1.2, and so double the leading the mock asks for.

Worth being precise about, because the obvious gloss is wrong and this sentence is what a future
engineer meets when the test goes red: the `− 1.2` did not go *missing*. Dropping it altogether
would give `10.5 × 1.4 = 14.7`, not 4.2. The value has held 4.2 since the M0 walking-skeleton
commit and was never revisited.

Because the caption's `max-width:80px` wraps this string to four lines, the error was multiplied
across three gaps: 6.3pt of extra stack, and a column that reads as four separately floating words
rather than one small paragraph. Fixed to 2.1, pinned by `VisitCameraCaptionMetricsTests`.

**This does not close the tester's report.** The remaining and larger half is the width, below.

### 2. The caption's `max-width:80px` against a string the mock never draws — owner decision

SCREENS 04 specifies `max-width:80px` for the ghost caption and draws it with **`ghost overlay
30%`**, 17 characters, which stacks to three lines. The app also uses that box for the no-ghost
state, whose string `no ghost yet · first photo` is 26 characters and stacks to four. That state is
not drawn in the mocks — the copy is the app's own — so the box was never sized against it.

There are three ways out and all three are the owner's call, not a branch's:

1. widen the cap, which changes a mock-specified metric for the state the mock *does* draw;
2. shorten the app's own no-ghost copy so it fits the box the mock sized;
3. leave it, on the grounds that the mock's own string stacks three lines deep on purpose and a
   fourth is within the drawn intent.

Worth noting that the project has already dropped this cap once, in the other direction. SCREENS
04's accessibility variant — headed "(R14; …)", so the drop happens under R14's authority, though
R14 itself rules on the viewfinder floor and the scrolling controls and never mentions the caption
— says at `docs/distilled/SCREENS.md:839–840` that the cap "is the one part of it the type ramp
cannot survive — at AX5 it is a column of single stacked syllables". The tester is reporting a
milder form of the same symptom at the default type size, caused by a longer string rather than by
the ramp. The precedent for dropping the cap therefore exists; whether it extends to the default
size is a design decision.

**Proposed ticket.** *Decide the ghost caption's no-ghost treatment.* Where:
`VisitMetrics.Camera.ghostCaptionMaxWidth` and `VisitCameraModel.ghostCaption`
(`Cypress/Features/Visit/VisitCameraModel.swift:159`). Verification: a screenshot of screen 04 on a
390pt phone with no prior full-tree photo, next to the same screen with a ghost, both read on the
device — this is a typography judgment and a simulator screenshot at the drawn size is the
instrument.

### 3. "Where do leaf out full leaf flowering etc go?" — a genuine product gap, owner decision

The tester circled the whole tray on screen 04 — the note field, the four phenology chips (`Leaf
out`, `Full leaf`, `Flowering`, `Fruiting`) and `Log visit` — and asked where that data goes.

Read literally it is a question about destination, not a bug report: having tagged a visit
"Flowering", the tester could not find where that observation surfaces afterwards. This is not
noise and it is not a defect either; it is a hole in the product's feedback loop, and answering it
means deciding what a phenology observation is *for* once recorded. That is DECISIONS constraint 21
territory — a screen or state not in the mocks is a stop-and-ask — and it is not a thing to invent
from a branch.

**Proposed ticket.** *Say where a phenology tag goes.* The cheapest honest answer is probably
confirmation at the point of logging rather than a new surface, but the range runs from a sentence
on the saved screen to a phenology history on the tree profile, and picking a point on that range
is the owner's. Verification depends entirely on which is chosen.

## One thing found while checking, unrelated to the feedback

`VisitMetrics.Saved.footnoteLineSpacing` is `6.5`. SCREENS (`docs/distilled/SCREENS.md:1352`)
gives that footnote `line-height:1.5`; the 13.5px is not stated there but comes from the view's own
`.cypressBody135(...)` at `VisitSavedView.swift:240`. The conversion therefore gives `4.05`, which
is exactly `CypressFont.LineSpacing.body135` — and `.cypressBody135(...)` *already applies* it. So
line 241 overrides a correct value with a wrong one, and the honest fix is to delete the modifier
rather than edit the constant.

This is **not** the caption's arithmetic repeated: the 1.0-line-box slip would give `13.5 × 0.5 =
6.75`, not 6.5. The two are the same defect class only in the loose sense of deviating from the
documented conversion. Different screen, no tester report attached, and a fix that changes a screen
nobody complained about — tracked as ticket #257 rather than folded in here.

## What the API cannot tell us

Worth writing down before someone asks this to do more than it can.

- **There is exactly one active tester's worth of feedback.** Two submissions, one tester id, one
  device, one build, 40 seconds apart. Nothing here supports a claim about how the app behaves
  across devices or across people, and a future run that returns three more submissions from the
  same id is still one person.
- **Zero crashes is not zero crashiness.** `betaFeedbackCrashSubmissions` holds crashes a tester
  chose to submit through TestFlight. A crash nobody reported is not in it, and neither are the
  aggregate metrics; those live behind a different API and are a separate piece of work.
- **The screenshot expiry is a real deadline.** Re-running the workflow after 2026-08-14 will
  return fresh URLs for these two submissions, but an artifact older than its URLs cannot be
  re-fetched from the JSON alone. The downloaded PNGs in the artifact are the durable copy.
