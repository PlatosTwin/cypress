# Copy audit: the demo-era narrative holdovers

Phase 1 inventory and verdict proposal, 2026-08-23. Branch `feat/copy-audit`, off `origin/main`
at `f5b4a63`. Answers the ROADMAP item "Copy audit: remove demo-era narrative holdovers"
(owner instruction 2026-08-21).

**This document proposes; it does not change anything.** No drawn string is edited on this
branch. The orchestrator runs batched owner decision rounds off the tables below, and phase 2
implements whatever comes back.

The owner's exemplar — *"This is that almanac's 'walk the nine' list, one tree at a time"* — is
item **K1**, at `Cypress/Features/TreeProfile/TreeProfilePresentation.swift:1340`.

---

## 1. Coverage method — how the inventory was built, and what it cannot see

The enumeration is mechanical, not a reading of the screens I remembered. Four passes:

**Pass 1 · every string literal in the app target.** A regex over all 282 `.swift` files under
`Cypress/`, skipping whole-line comments, capturing `file:line:literal:source-line`. **5,287**
literals.

*Calibration, per CLAUDE.md.* The extractor was run against a case whose answer was already
known before any of its output was trusted: the owner's quoted sentence. It reported
`TreeProfilePresentation.swift:1340` plus three unrelated occurrences (two gallery button
labels, one `#Preview` name) — the right line, and the right neighbours. A pass that had found
only the previews, or nothing, would have been discarded.

**Pass 2 · prose filter.** Dropped SQL, URLs, single-token identifiers, all-caps constants, and
anything with no lowercase letter or no space. **1,972** prose-like literals.

**Pass 3 · reachability.** Removed files that do not draw on a phone, each checked by reading
its header rather than by guessing from the name:

| Excluded | Why |
| --- | --- |
| `ComponentGallery.swift`, `TokenGallery.swift` | header says "Not shipped in any screen"; Xcode-preview contact sheets. 401 literals — including two `"Walk the nine"` sample buttons |
| `Data/Tests/DataGates.swift`, `Features/Visit/VisitGates.swift` | acceptance gates returning developer failure strings |
| `*Previews.swift` and any line containing `#Preview` | Xcode canvas titles |
| `DesignSystem/Tokens/Cypress{Color,Font,Gradient,Motion}.swift` | token documentation prose |
| `Data/Store/*` (SQL, migrations, sqlite errors) | never rendered |

**883** candidates survived. A further **79** are developer-only or internal-error strings
(`Debug*.swift` deep-link banners, `MapFrameProbe`/`MapProbeOverlay` HUD, `AuthHTTP`,
`RemoteWire`, `CityDownloader`, `CityManifest`, Apple-sign-in `Incomplete` reasons) — listed in
§6 and excluded from the verdict counts, because none of them reaches a user in a shipping
build. That leaves **804** literal fragments, **774** drawn strings after joining the 30
`+ "…"` continuation lines back into the sentence they belong to.

**Pass 4 · the strings the prose filter would have missed.** Two separate sweeps, because the
"must contain a space" rule in pass 2 hides every one-word button label:

- literals with no space that appear inside a render call (`Text(`, `Button(`, `PrimaryButton(`,
  `accessibilityLabel(`, `ScreenHeader(`, …) — **7** hits: `SYNC`, `Dismiss`, `On`, `Off`,
  `Back` ×2, `Saving…`;
- literals with no space bound to a `static let` in a `…Copy` enum or returned from a `case`
  arm — **181** after removing storage keys, file names and compass points.

All 188 were read. Every one is a tab name, a chip, a nav title, a unit name or an enum label
(`Map`, `Journal`, `You`, `Watered`, `Mulched`, `Thriving`, `Tape`, `Caliper`, `meters`, …).
**All KEEP**, none proposed for change; they are counted in the total below but not itemized.

**Pass 5 · outside the Swift sources.** `Cypress/Resources/Info.plist` carries three
user-facing permission strings (`grep`ed for `UsageDescription` across `.plist`, `.pbxproj` and
`.xcconfig`; the project sets no `INFOPLIST_KEY_NS…`). All three are in §5.13. There is no
`.strings` catalog and no localization — the app is English-only, literals inline.

### What this method cannot see

Stated so the gap is on the record rather than implied:

1. **Runtime-composed sentences.** A string built from a formatter plus a stem
   (`"\(count) \(noun) · since \(year)"`) is enumerated at its stem; the sentence a user
   actually reads was judged by reading the function, not the literal.
2. **Copy that lives in the seed database.** Species descriptions, `recognition` text, vitality
   rubric wording that comes from data rather than source. `Vitality.swift`'s five rubric
   sentences are in-source and were audited; anything the seed carries was not. If the owner
   wants seed prose screened too, that is a second round with a different method (SQL over
   `cypress-seed.sqlite`), and it should be asked for explicitly.
3. **Copy in `docs/`.** `SCREENS.md` specifies much of the copy below verbatim; see §7.

---

## 2. Summary table

| | Count |
| --- | ---: |
| Drawn strings enumerated (prose, joined) | 774 |
| Short labels (one-word buttons, chips, enum labels) | 188 |
| `Info.plist` permission strings | 3 |
| **Total user-facing strings screened** | **965** |
| **KILL** — narrative holdover, delete outright | **11** |
| **REWRITE** — useful purpose, wrong voice or now untrue | **25** |
| **KEEP** | **929** |

Numbered **K1–K11** and **R1–R27** below. That is 38 numbers over **36 distinct strings**: R14
and R16 are the same two strings as K10 and K8, offered as rewrites rather than deletions so the
owner has both options on one line. 11 + 25 = 36.

Of the 36, **20 are load-bearing for tests** (§8), and **20 are specified verbatim in
`SCREENS.md`** (§7) — which is the DECISIONS constraint-21 territory the ROADMAP item
anticipated, and the reason nothing is being reworded silently.

---

## 3. The ten worst offenders

Ranked by how loudly the app narrates itself. Every one is drawn on a phone today.

| # | Screen | File:line | Current text | Proposal |
| --- | --- | --- | --- | --- |
| K1 | 14 · cold-start profile | `Features/TreeProfile/TreeProfilePresentation.swift:1338–1343` | `A young tree nobody has visited. This is the almanac’s “walk the nine” list, one tree at a time.` | **KILL** the whole footnote (`coldStartFootnote` returns `""`) |
| K2 | 18 · next tree | `Features/Visit/VisitSavedView.swift:266–277` | `Ten check-ins in a row is the real volunteer morning. The save answers the only question that matters: which tree is next.` | **KILL** the footnote view |
| K3 | 17 · outbox | `Features/Outbox/OutboxPresentation.swift:481` | `Nothing here disappears silently. An item that cannot sync says so, says why, and waits for you.` | **KILL** `OutboxCopy.footnote` |
| K4 | 12 · almanac | `Features/Almanac/AlmanacPresentation.swift:452` | `No ranks, no counters. The almanac notices trees, not scores.` | **KILL** `AlmanacCopy.footnote` |
| K5 | 08 · My Grove *and* Journal | `Features/Grove/GrovePresentation.swift:309` | `Quiet collecting. There are no streaks and no leaderboards.` | **KILL** `GroveCopy.footnote` — note `JournalCopy.footnote` is an alias of it, so this is two screens |
| K6 | City segment | `Features/City/CityPresentation.swift:304` | `No leaderboard, no city ranking. Just what the record holds.` | **KILL** `CityCopy.footnote` |
| K7 | vacant planting site | `Features/Site/SitePresentation.swift:294` | `A planting site is a gap in the canopy, not a tree with a page missing. It stays on the map because it is the city's own record of where a tree could stand.` | **KILL** `SiteCopy.footnote` |
| K8 | 12 · almanac, young-trees card | `Features/Almanac/AlmanacPresentation.swift:749` | `The first two summers decide whether a street tree makes it.` | **KILL** the opening sentence — unattributed arboricultural claim (DECISIONS 15); keep `All nine are within a 15-minute walk.` |
| K9 | 18 · next tree, route map | `Features/Visit/VisitSavedView.swift:345` | `done trees go quiet` | **KILL** the corner label |
| R1 | vacant planting site | `Features/Site/SitePresentation.swift:246–253` | `No tree at this site.` + ` The city's inventory lists a planting basin here and nothing growing in it. Cypress keeps the record of what is planted—it does not plant.` | **REWRITE** → keep the first two sentences, drop `Cypress keeps the record of what is planted—it does not plant.` |
| R2 | 19 · memorial | `Features/Memorial/MemorialPresentation.swift:435` | ` This profile is now read-only. Every photo, visit, and check-in stays—a record of the tree that was here.` | **REWRITE** → ` This profile is now read-only. Every photo, visit, and check-in stays.` |

---

## 4. KILL — the full list

Eleven items. Nine are in §3; the two below complete the list.

| # | Screen | File:line | Current text |
| --- | --- | --- | --- |
| K10 | 13 · tree activity, Moments | `Features/Activity/ActivityPresentation.swift:437` | `Spring flush noted` |
| K11 | 13 · tree activity, Moments | `Features/Activity/ActivityPresentation.swift:439` | `Watered through the dry weeks` |

**Why K10/K11 are KILL rather than REWRITE.** The Moments band draws three rows. Row 3
(`Seven years on record`, `First photo Mar 2019 · six people know this tree`) is a fact about
the record. Rows 1 and 2 are captions written for a mock's screenshot: `Spring flush noted`
with the subtitle `Apr 3 · four visitors caught the bright new tips`, and
`Watered through the dry weeks` with `Jun–Aug · five care visits kept it going`. Nothing in the
app detects a spring flush or a dry spell; the rows are keyed off observation and care counts,
so the titles assert a seasonal narrative the data does not carry. The alternative to killing
them is R14/R15 below — the owner should choose one or the other, not both.

---

## 5. REWRITE — by screen

Twenty-five distinct strings, numbered R1–R27 (R14 and R16 restate K10 and K8 as rewrites; see
§2). `→` is the proposal.

### 5.1 Screen 03 · tree profile

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R3 | `TreeProfilePresentation.swift:736` | `Visit · say hello with a photo` | `Visit · add a photo` |
| R4 | `TreeProfilePresentation.swift:736` (cold arm) | `Be the first to photograph this tree` | `Add the first photo of this tree` |

Both are `SCREENS.md`-verbatim (746, 1231). R3's "say hello" is the clearest surviving instance
of the demo voice on the most-visited screen in the app; R4 reads as a first-mover prize.

### 5.2 Screen 19 · memorial

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R2 | `MemorialPresentation.swift:435` | ` This profile is now read-only. Every photo, visit, and check-in stays—a record of the tree that was here.` | ` This profile is now read-only. Every photo, visit, and check-in stays.` |
| R5 | `MemorialPresentation.swift:522` | `A new tree is coming.` | `This site may be replanted.` |
| R6 | `MemorialPresentation.swift:524` | ` When the city replants this site, the new profile will link back here—the site keeps its lineage.` | ` If the city replants here, the new tree's profile will link back to this one.` |
| R7 | `MemorialPresentation.swift:492–494` | `First photo · the record begins · six people came to know it` | `First photo · six people knew this tree` |
| R8 | `MemorialPresentation.swift:511–513` | `Check-in · vitality 2 · a steward confirmed the decline` | `Check-in · vitality 2` |

R5/R6: `A new tree is coming.` is a prediction the app cannot make — nothing in the data says
the city will replant this site. That is the F7-round rule (copy must be true and
provenance-accurate) applied to a future tense. R8: "a steward" is a role this app has no
concept of; the check-in was made by a contributor.

### 5.3 Screen 13 · tree activity (alternative to K10/K11)

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R14 | `ActivityPresentation.swift:437` | `Spring flush noted` | `Leaf-out noted` |
| R15 | `ActivityPresentation.swift:460` | `Apr 3 · four visitors caught the bright new tips` | `Apr 3 · four visitors` |

### 5.4 Screen 12 · almanac

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R16 | `AlmanacPresentation.swift:749–752` | `The first two summers decide whether a street tree makes it. All nine are within a 15-minute walk.` | `All nine are within a 15-minute walk.` (this is K8 stated as a rewrite of the composed sentence) |

### 5.5 Screen 16 · measure

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R9 | `MeasurePresentation.swift:454` | `Taken at 1.4 m, tape in one hand.` | `DBH is measured at 1.4 m above the ground.` |
| R10 | `MeasurePresentation.swift:456` | `A shrinking trunk gets a “sure about that?” before it saves.` | **delete** — the confirmation itself already says it, and better |

R9 keeps the only fact in the sentence and drops the pose. The 1.4 m is genuinely useful and
must survive.

### 5.6 Add-a-tree flow

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R11 | `VisitAddTreeView.swift:651` | `No species will be recorded. An unnamed tree is still a tree on the map.` | `No species will be recorded. The tree still goes on the map.` |
| R12 | `VisitAddTreeView.swift:673` | `Where it stands will not be recorded. The tree goes on the map either way.` | `Where it stands will not be recorded.` |
| R13 | `VisitAddTreeView.swift:698` | `A photo is what makes this a record of a tree rather than a pin.` | `A photo is required to add a tree.` |
| R17 | `VisitAddTreeView.swift:699` | `Waiting for a fix. A tree is a place, so it cannot be added without one.` | `Waiting for a location fix. A tree cannot be added without one.` |
| R18 | `VisitAddTreeView.swift:701` | `Cypress cannot see where you are, and a tree is a place. Turn location on in Settings to add one.` | `Cypress cannot see where you are. Turn location on in Settings to add a tree.` |

None of the five is `SCREENS.md`-specified — the whole add-a-tree flow is a screen the mocks do
not draw. The aphorism ("a tree is a place", twice) is agent-written.

### 5.7 Screen 02 · what tree is this?

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R19 | `VisitIdentifyView.swift:349` | ` Both are inside the GPS error circle, so the phone cannot tell them apart. You can.` | ` Both are inside the GPS error circle, so the phone cannot tell them apart.` |

### 5.8 Screen 06 · report an issue, and the You tab's reminders

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R20 | `ReportPresentation.swift:283` | `Saved. Your reminder stays yours alone.` | `Saved. This reminder is private to you.` |
| R21 | `PrivateReminderList.swift:148–149` | `Nothing saved. A reminder you keep after reporting an issue and calling 311 shows up here, and stays yours alone.` | `Nothing saved. A reminder you keep after reporting an issue and calling 311 shows up here. Reminders are private to you.` |
| R22 | `PrivateReminderList.swift:154` | `Your reminders could not be read just now. Nothing has been lost—open the You tab again.` | `Your reminders could not be read just now. Nothing has been lost. Open the You tab again.` |

`stays yours alone` is `SCREENS.md`-verbatim (928) but reads as reassurance rather than fact;
`private to you` is the phrasing the outbox already uses (`OutboxPresentation.swift:396`), so
this also removes a synonym.

### 5.9 Journal

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R23 | `JournalPresentation.swift:306` | `Take your record with you` | `Export your journal` |

Not mock-specified. The row opens two format choices whose own labels already say
`Export as a spreadsheet` / `Export as map data`, so the section header is the only place the
word "export" is avoided.

### 5.10 Screen 09 · care log

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R24 | `CareLogPresentation.swift:105` | `Toggle what you did. Thirty seconds, then back to your walk.` | `Toggle what you did.` |

`SCREENS.md` 1031 verbatim. "Toggle what you did" is an instruction; "Thirty seconds, then back
to your walk" is a promise about the reader's morning. RULINGS **R80** item 6a made the same
distinction for screen 18's two buttons — they were renamed for the place they go rather than
for what the reader has decided about their day — and this is the same sentence one screen over.

### 5.11 Map home

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R25 | `MapInventoryNotice.swift:137–138` | `Cypress draws a city street-tree inventory, and this ground is not on it. Trees may well stand here, unlisted.` | `Cypress draws a city street-tree inventory, and this ground is not on it. Trees may stand here without being listed.` |

### 5.12 Screen 15 · the account ask

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R26 | `AccountAskPresentation.swift:176` | `They live on this phone right now. An account backs them up and lets them join each tree’s public timeline.` | **owner's call** — see §9, ambiguity 3. There is no public timeline in the shipping app. |

### 5.13 `Info.plist`

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R27 | `Cypress/Resources/Info.plist:10` (`NSCameraUsageDescription`) | `A visit is a photo of a tree lined up against the last one. Cypress needs the camera to take it.` | `Cypress uses the camera to photograph the tree you are visiting.` |

The first sentence is both narrative and no longer complete: since the photo-library route
landed, a visit is not only a camera photo, and the ghost overlay is off for three of the four
subjects (`VisitCameraModel.swift:158`). The other two plist strings are KEEP — both state a
purpose and stop.

---

## 6. Screened and KEPT — what the sweep passed, and why

So that "928 KEEP" is not an unexamined remainder, the notable near-misses:

- **`CheckInCopy.footnote`** (`CheckInPresentation.swift:167`) `Everything here is optional.
  Skip anything and it still counts.` — mock-verbatim (897) and load-bearing for the screen's
  actual behavior: every control on 05 really is optional. KEEP.
- **`CareLogCopy.footnote`** (`:124`) `This joins the tree’s care history—separate from health
  observations.` — states a real distinction between two record types. KEEP.
- **`AlmanacCopy.vacantSubtitle`** `The city has mapped them. Nothing is growing there.` — two
  facts, no pose. KEEP.
- **The whole dead-notice caption family** (`TreeProfilePresentation.swift:243/259/266`,
  `Confirmed dead:` / `Listed dead:` / `Reported dead:`), **`AccountCopy.storageBody`**
  (`AccountSection.swift:292`), the **outbox upload rows** (`OutboxViewState.swift:102–115`)
  and the **account-deletion sheet** (`Core/AccountDeletionCopy.swift`, all 12 strings) —
  ratified 2026-08-23, KEEP by definition, not screened for tone.
- **The two ruled terminal sentences** (`OutboxViewState.swift:48/60`) and
  **`AccountAskCopy.noticeUnavailable`** — owner rulings of 2026-08-14/15, pinned by
  `OwnerCopyRulingTests`. KEEP.
- **`VisitSavedCopy.backToMap` / `.backToTree`** — owner-final, RULINGS R80 item 6a,
  2026-08-21. KEEP. (Note that K2 and K9 are on the *same screen* as these two and were not
  part of that round.)
- **`YouCopy.privacyBody`** (`YouTabView.swift:389`) — its middle clause is already known-false
  and is written up as **E271 §4a** rather than rewritten. Out of scope for a tone audit; it is
  a truth defect with an existing errata number and an owner decision already pending.
- **Developer-only, excluded from the counts (79 fragments):** `DebugDeepLink.swift` failure
  banners, `DebugLocationOverride`/`DebugMapCameraOverride` parse errors,
  `MapFrameProbe`/`MapProbeOverlay` HUD, `AuthHTTP`/`RemoteWire`/`CityDownloader`/
  `CityManifest` error descriptions (mapped to user sentences by `OutboxViewState` before
  anything is drawn), `AppleSignIn` `Incomplete` reasons, `MapAnnotationLayer` probe dumps.
  `YouCopy.becomeLeadTitle`/`stepDownTitle` are `#if DEBUG` only (E124-B).

---

## 7. The `SCREENS.md` problem

**20 of the 36 distinct strings are specified verbatim in `docs/distilled/SCREENS.md`** — 18
rows below, two of which cover a pair each. Grepped and confirmed line by line:

| Item | `SCREENS.md` line |
| --- | --- |
| K1 `walk the nine` | 1147 (and the button label at 399) |
| K2 volunteer morning | 1380 |
| K3 outbox footnote | 1336 |
| K4 `No ranks, no counters` | 1149 |
| K5 `Quiet collecting` | 1014 |
| K8 / R16 first two summers | 1146 |
| K9 `done trees go quiet` | 1365 |
| K10 / R14 `Spring flush noted` | 1179 |
| K11 `Watered through the dry weeks` | 1180 |
| R2 memorial banner | 1401 |
| R3 `say hello with a photo` | 746 |
| R4 `Be the first to photograph this tree` | 1231 |
| R7 `the record begins` / `came to know it` | 1410 |
| R8 `a steward confirmed the decline` | 1412 |
| R9 / R10 measure footnote | 1294 |
| R20/R21 `stays yours alone` | 928 |
| R24 `Thirty seconds, then back to your walk` | 1031 |
| R26 `public timeline` | 1254 |

Sixteen are **not** in the mocks and are agent-written: K6, K7, R1, R5, R6, R11, R12, R13, R15,
R17, R18, R19, R22, R23, R25, R27 — which includes the whole of §5.6, a flow the mocks never
drew.

`SCREENS.md` is a distilled transcription of the demo-era mock, which is the source of the voice
being removed. Whatever the owner rules, **phase 2 must also amend `SCREENS.md`**, or the next
agent to build against it will restore the lines this round deletes — which is exactly how K1
survived E129. See §9, ambiguity 1.

---

## 8. Load-bearing for tests

Twenty of the 36 distinct strings are asserted somewhere in `CypressTests`/`CypressUITests` and
need a test edit in phase 2. Measured two ways, because one way was not enough: an exact-substring
sweep of both test targets over every candidate ≥18 chars (101 distinct hits), and a
symbol-name grep for each proposed item. The second found `SiteTests.swift:488`'s
`#expect(SiteCopy.statementBody.contains("it does not plant"))`, which the substring sweep
missed because the test asserts a fragment rather than the sentence. **The substring sweep alone
is a lower bound; do not use it on its own in phase 2.**

| Item | Test references |
| --- | --- |
| K1 | **none** — `coldStartFootnote`'s text is asserted nowhere; `isCold` is (7 sites), the string is not |
| K2, K9 | **none** |
| K3 | `OutboxPresentationTests.swift` (2) |
| K4 | `AlmanacPresentationTests.swift` (4) |
| K5 | `GrovePresentationTests.swift` (2) + `JournalCopy.footnote` alias (1) |
| K6 | `CityPresentationTests.swift` (1) |
| K7 | `SiteTests.swift` (1) |
| K8/R16 | `AlmanacPresentationTests.swift` |
| K10, K11, R14, R15 | **none** |
| R1 | `SiteTests.swift` (3, incl. the fragment assertion above) |
| R2, R5, R6, R7, R8 | `MemorialPresentationTests.swift` |
| R3, R4 | `TreeProfilePresentationTests`, `VacantSiteRedirectTests`, `PrimaryCTAReachabilityTests` (UI), `ReadingOrderAccessibilityTests` (UI) — **four suites, two of them UI** |
| R9 | `MeasurePresentationTests.swift` (1) |
| R10 | `MeasurePresentationTests.swift` (2) |
| R12 | `LandContextScreenTests.swift:62` (whole-sentence equality) |
| R23 | `JournalPresentationTests.swift:144` |
| R24 | `CareLogTests.swift:79` |
| R26 | `AccountAskSheetTests.swift:278` (equality) **and** `AccountSurfaceTests.swift:407` (`.contains("public timeline")`) |

R3/R4 are the expensive ones: the two UI suites drive the primary CTA by its label, so phase 2
needs a simulator run, not just a unit pass.

---

## 9. Ambiguities needing a ruling before phase 2

1. **Does this round amend `SCREENS.md`?** Eighteen items are transcribed there verbatim.
   Leaving `SCREENS.md` alone leaves the app and its own screen map disagreeing, and the map is
   what the next builder reads. Proposal: phase 2 edits `SCREENS.md` in the same commit, marking
   each struck line `— removed by the 2026-08-23 copy audit`, so the transcription stays honest
   about what it used to say. Needs the owner's yes, because `SCREENS.md` is a distillation of a
   source document rather than a document we own.

2. **K10/K11 or R14/R15 — kill the Moments rows, or keep them and de-narrate?** They cannot both
   apply. My recommendation is **KILL**: the titles claim a seasonal event the app never detects.

3. **`AccountAskCopy.body` (R26) is a truth question wearing a tone question's clothes.** It
   promises records "join each tree's public timeline". There is no public timeline in the
   shipping app. This is the same shape as ruling 2 of 2026-08-14 (`storageBody`), and I did not
   propose wording, because a rewrite has to decide what the app *does* promise — which is a
   product answer, not a copy answer. Flagging rather than guessing.

4. **Footnotes as a class.** Six screens end in a footnote (08/12/17/18 + City + Site) and five
   of the six are on the KILL list. If the owner's view is that the footnote *slot* is the demo
   artifact, the sixth (`CareLogCopy.footnote`, kept above) and `JournalCopy`'s alias should go
   with them and the layout slot should be removed rather than left empty. If instead the slot
   stays, three of the five need replacement text and I have not proposed any. Which?

5. **Seed-database prose.** Species recognition text and the like live in the seed, not in
   source, and were **not** screened (§1). If they are in scope this is a second round.

---

## 10. Where the machinery is

Extraction scripts and the intermediate TSVs are in the session scratchpad
(`copyaudit/{extract,filter,filter2,filter3,filter4,tests,count}.py`,
`all_literals.tsv` → `prose.tsv` → `candidates.tsv`). They are throwaway; nothing in this
document depends on re-running them, and every file:line above was read in the source.
