# Copy audit: the demo-era narrative holdovers

Phase 1 inventory and verdict proposal, 2026-08-23. Branch `feat/copy-audit`, off `origin/main`
at `f5b4a63`. Answers the ROADMAP item "Copy audit: remove demo-era narrative holdovers"
(owner instruction 2026-08-21).

The owner's exemplar — *"This is that almanac's 'walk the nine' list, one tree at a time"* — was
item **K1**. It is gone.

---

## 0. Status — the owner's rulings, 2026-08-23

**Both decision rounds are closed and both halves have landed on this branch.** Phase 2A landed the
kills, the footnote slot and the mock's strikes; phase 2B landed the rewrites, the four remaining
footnotes and R9's inline move. Nothing in §§3–5 below is pending.

### Round one — the kills

| # | Ruling | Where it landed |
| --- | --- | --- |
| 1 | **KILL all 11**, and K10/K11 die as kills rather than rewrites — R14 and R16 are moot | §4, and the two Moments *subtitles* go with their rows, so 11 numbered items = **13 strings** |
| 2 | Strike every transcribed line from `SCREENS.md` **in the same commit**, each with a marker citing this document | §7; 8 strikes in `SCREENS.md`, 1 in `PROTOTYPE-FLOW.md` |
| 3 | **The footnote *slot* is the demo artifact** — it comes out everywhere, including the survivor this audit proposed keeping (`CareLogCopy.footnote`) and the `JournalCopy.footnote` alias, and the layout slot goes with it rather than being left empty | §4a below |
| 4 | `AccountAskCopy.body` — **keep the promise verbatim**, on the record that the feature is coming | **R26 is withdrawn. KEEP by ruling** — see §5.12 |

**R26 is a waived item. Do not re-flag it in any future copy audit.** The public-timeline
sentence is a deliberate forward promise, not an oversight; it was screened, raised, and settled.

### Round two — the rewrites (2026-08-23, second decision round)

| # | Ruling | Where it landed |
| --- | --- | --- |
| 5 | **Every rewrite in §5's table is approved as proposed**, with one modification: R7 ships as `First photo · six people know this tree` — **`know`, not the proposed `knew`**, the owner's explicit verbatim wording | §5, and the list of which rewrites shipped at the foot of §2 |
| 6 | **Ruling 3 extends to the four footnotes §4a named as untouched.** All four go | §4b below |
| 7 | **Exception to ruling 6: R9's fact moves inline.** `DBH is measured at 1.4 m above the ground.` survives, in screen 16's §2 under the control that selects DBH; the slot dies | §4b, and `MeasureCopy.dbhHelp` |
| 8 | **R10 dies entirely** — the confirmation dialog already says it, and says it at the moment it applies | `MeasureCopy.anomalyShrunkTrunk` is now the only place that question is asked |

**On R7's tense.** The proposal was `six people knew this tree`, past, matching a memorial. The
owner's wording is present. It is implemented exactly as ruled, and it turns out to be the same
clause `ActivityCopy.onRecordSubtitle` and `TreeProfilePresentation.caretakerHeadline` already
print, so A8's headcount now reads identically on all three screens that draw it. The comment in
`MemorialPresentation.caretakerCount` that leaned on the past tense to justify not applying A8's
24-month window has been rewritten around the reason that survives the change: a removed tree
accrues nothing, so a rolling window walks every memorial to zero.

### 4b. What ruling 6 removed, and what ruling 7 kept

The four sites §4a named, all gone:

| Site | What it said | What happened |
| --- | --- | --- |
| `CheckInCopy.footnote` (05 §8) | `Everything here is optional. Skip anything and it still counts.` | Removed. The claim was always carried by the card's behavior — no control on 05 is required and the CTA is live on an untouched card — and that is unchanged. The 36pt it carried moves to the sticky CTA block. `CypressSpacing.bottomStickyCTAGap` had no other caller and goes with it. |
| `ActivityCopy.footnote` (13 §5) | `One scale across all three charts…` plus the ceiling sentence | Removed, with `ceiling(in:peak:)`, `countedNoun`, `ActivityCopy.monthName` and the `Spacer` that bottom-pinned it. `shortMonthName` had been dead since phase 2A killed its caller and goes in the same sweep. |
| `MeasureCopy.footnoteDBH` / `.footnoteAnomaly` (16 §7) | `Taken at 1.4 m, tape in one hand. A shrinking trunk gets a “sure about that?” before it saves.` | Slot removed. First sentence's fact survives inline as `MeasureCopy.dbhHelp` (ruling 7); second dies (ruling 8). |
| `GrowthHistoryCopy.unrenderedFootnote` (11 §6) | `Tap any point to open the observation behind it.` | Never drawn (E64) and now not held in the source either. ERRATA **E64 is amended in place** to say so — it claimed the constant was kept "so it returns unedited the day the destination is designed", and that is no longer true. |

**One fact was lost on purpose and is recorded rather than worked around.** Screen 13's footnote
opened with a true statement about the chart above it — the three rows share one vertical scale —
and ruling 7 made exactly one exception for a fact, for screen 16. So the shared scale is now a
property of the chart that the chart does not state. Widening ruling 7 to cover it would have been
an inference, which is the mistake §4a exists to avoid; if the owner wants it said, that is a
one-line follow-up on screen 13.

**A fifth `footnote` was checked and is not one.** `VisitAddTreeCopy.footnote`
(`Recorded as community-added and unverified, on this phone.`) is named like the others and is a
different shape: it is centered under the CTA in the footer, states what the record will say, and
is not a bottom-pinned slot. It was in neither enumeration and was not touched. Named here so the
next round does not have to decide whether it was missed.

### 4a. What ruling 3 actually removed

Ruling 3 is the one that went past the audit's own proposal, so its scope is written out rather
than left to "everywhere". **Eight footnote render sites** were removed — the six screens §9
item 4 named (08 My Grove, 12 Almanac, 17 Outbox, 18 Next tree, City, vacant Site), plus the
survivor (09 Care log) and the Journal tab's alias — together with K1's cold-start footnote on
14, which was already a kill. With them went the `margin-top:auto` spacers that existed only to
bottom-pin a footnote, and every `…Metrics.footnote*` constant that positioned one.

**What was deliberately kept: the closing space.** Six of those footnotes carried the screen's
bottom margin (36pt, or 14pt above a tab bar) in their own `padding(.bottom:)`. That is the
screen's inset above the home indicator, not part of the footnote, and deleting it with the
sentence would have run the last row into the edge. It moves to the column on each screen and is
commented as such at every site.

**Four footnotes were NOT touched, because ruling 3's enumeration does not reach them and this
round had no standing to widen it.** They are named here so the next round does not have to
rediscover them: `ActivityCopy.footnote` (13 §5, the shared-scale sentence — a fact about the
chart above it), `CheckInCopy.footnote` (05), `MeasureCopy.footnoteDBH`/`footnoteAnomaly` (16 —
already pending as rewrites R9/R10), and `GrowthHistoryCopy.unrenderedFootnote` (11). **If the
owner's intent was every footnote in the app, that is a follow-up ruling, not an inference.**

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
| **KILL** — narrative holdover, delete outright | **11** items / **13** strings — *ruled, landed* |
| **REWRITE** — useful purpose, wrong voice or now untrue | **25** — *23 implemented; R26 withdrawn, R15 died as a kill* |
| **KEEP** | **928** |
| Additionally removed under ruling 3 (footnote slot) | **1** — `CareLogCopy.footnote`, a KEEP the owner overrode |
| Additionally removed under ruling 6 (the same slot, four more sites) | **4** — §4b |

Numbered **K1–K11** and **R1–R27** below: **38 numbers over 37 distinct strings.**

**The KEEP figure is 965 − 37, and it was recounted rather than carried forward** (PR #119 review,
finding N2 — this table said **929** while §6 below said **928**, and both were written in the same
phase-1 commit, so one of them was always wrong). The recount, and the trap in it:

- The eleven **K** numbers cover **13 strings**, not 11. K10 and K11 each take a Moments *subtitle*
  down with the row's title, which is ruling 1's own wording ("11 numbered items = **13 strings**").
- The twenty-seven **R** numbers cover **24 strings that are not already in that 13**. Three R
  numbers name a string the kills already account for: R14 is K10's title, **R15 is K10's
  subtitle** (`ActivityPresentation.swift:460`, `Apr 3 · four visitors caught the bright new tips`),
  and R16 is K8's sentence stated as a rewrite of the composed line.
- 13 + 24 = **37 distinct strings** disposed. 965 − 37 = **928**.

**The 929 came from counting kills as items and rewrites as strings in the same subtraction** —
`11 + 25 = 36`, then 965 − 36 — which drops the two subtitles and misses that R15 is one of them.
The two bases are one apart twice over and happened to land one apart in total. The itemized 25
in the REWRITE row above is a count of R numbers minus R14/R16 and is left as phase 1 wrote it;
it is *not* the number that belongs in this subtraction, which is why the derivation is spelled
out here instead of a figure being swapped silently.

Of the 37, **20 are load-bearing for tests** (§8), and **22 are specified verbatim in
`SCREENS.md`** (§7, corrected during implementation) — which is the DECISIONS constraint-21
territory the ROADMAP item anticipated, and the reason nothing was reworded silently.

**The 23 rewrites that shipped** are R1–R13, R17–R25 and R27. R14/R15/R16 were moot before phase
2A (their strings died as kills K10/K11/K8) and R26 is waived. The count of 25 above is the
phase-1 tally of *distinct strings* proposed for rewrite and is left as it was written.

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
| R7 | `MemorialPresentation.swift:492–494` | `First photo · the record begins · six people came to know it` | ~~`First photo · six people knew this tree`~~ → **shipped as `First photo · six people know this tree`** — the owner's explicit wording, present tense (§0, ruling 5) |
| R8 | `MemorialPresentation.swift:511–513` | `Check-in · vitality 2 · a steward confirmed the decline` | `Check-in · vitality 2` |

R5/R6: `A new tree is coming.` is a prediction the app cannot make — nothing in the data says
the city will replant this site. That is the F7-round rule (copy must be true and
provenance-accurate) applied to a future tense. R8: "a steward" is a role this app has no
concept of; the check-in was made by a contributor.

### 5.3 Screen 13 · tree activity — ~~alternative to K10/K11~~ **MOOT**

The owner chose KILL. R14 and R15 are withdrawn; both rows and both subtitles are gone.

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R14 | `ActivityPresentation.swift:437` | `Spring flush noted` | `Leaf-out noted` |
| R15 | `ActivityPresentation.swift:460` | `Apr 3 · four visitors caught the bright new tips` | `Apr 3 · four visitors` |

### 5.4 Screen 12 · almanac — **MOOT (R16 = K8, ruled KILL)**

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R16 | `AlmanacPresentation.swift:749–752` | `The first two summers decide whether a street tree makes it. All nine are within a 15-minute walk.` | `All nine are within a 15-minute walk.` (this is K8 stated as a rewrite of the composed sentence) |

### 5.5 Screen 16 · measure

| # | File:line | Current | → |
| --- | --- | --- | --- |
| R9 | `MeasurePresentation.swift:454` | `Taken at 1.4 m, tape in one hand.` | `DBH is measured at 1.4 m above the ground.` — **and it moved.** See below |
| R10 | `MeasurePresentation.swift:456` | `A shrinking trunk gets a “sure about that?” before it saves.` | **delete** — the confirmation itself already says it, and better |

R9 keeps the only fact in the sentence and drops the pose. The 1.4 m is genuinely useful and
must survive.

**Where it went (ruling 7, phase 2B).** The footnote *slot* on 16 dies with all the others, so the
sentence had nowhere to stand at the foot of the screen. It is now `MeasureCopy.dbhHelp`, drawn in
**§2, directly under the segmented control that selects `Trunk · DBH`** — in the footnote's own
type (`body135` / `text.faintAlt`), on the DBH arm only, exactly as the footnote's first sentence
was. That arm is not a style choice: `TreeMeasurement.height` carries no `measurement_height_m` at
all (BUILD-PLAN §4), so over a height reading the sentence would describe a column that row does
not have.

**Screen 16 has no other help or caption text**, which was checked against the mock and the view
before this was placed: §2 and §4 are uppercase micro-labels, §3 is the readout and the sanity
pill, and the two lines above the CTA are notices about *this* reading. So "inline" meant beside
the control the fact is about, which is where it is. It is a placement decision made under the
ruling and is flagged here rather than buried in a diff.

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
| R26 | `AccountAskPresentation.swift:176` | `They live on this phone right now. An account backs them up and lets them join each tree’s public timeline.` | ~~raised~~ → **KEEP BY RULING (2026-08-23)** |

**WAIVED — do not re-raise.** The audit flagged this as a promise about a feature that does not
exist. The owner ruled that the promise stays verbatim, deliberately, on the record that the
feature is coming. It is pinned by `AccountAskSheetTests.swift:278` and
`AccountSurfaceTests.swift:407`, and both stay. A future copy audit that re-flags this sentence
is re-litigating a settled decision.

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

**Corrected 2026-08-23 during phase 2B: it is 22, not 20.** R5 and R6 are listed below as
agent-written and they are not — screen 19 §5's lineage callout is in the mock verbatim, lead-in
and body, and the strike had to be made there. The line was found by grepping the file for each
string before striking it rather than by trusting this table, which is the only reason it was
caught. Treat the "not in the mocks" list below as a claim to re-check, not a finding.

**22 of the 36 distinct strings are specified verbatim in `docs/distilled/SCREENS.md`** — 19
rows below, two of which cover a pair each. Grepped and confirmed line by line. **The line numbers
are phase-1's and have moved**: both phases struck and annotated this file, so grep for the string.
Every row below now carries a `~~strike~~` and a marker naming this document.

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
| **R5/R6 lineage callout** — *missed by this table, found in phase 2B* | 19 §5 |

Fourteen are **not** in the mocks and are agent-written: K6, K7, R1, R11, R12, R13, R15, R17, R18,
R19, R22, R23, R25, R27 — which includes the whole of §5.6, a flow the mocks never drew. (R5 and
R6 were on this list and should not have been; see the correction above.)

**Four more strikes were added in phase 2B for footnotes rather than for numbered items**: 05 §8,
11 §6, 13 §5 and 16 §7, under ruling 6. Screen 06's dashed disclosure carries a *note* rather than
a strike — it is unchanged, and the note records that it is now the last place in the app that says
`stays yours alone`, since R20/R21 moved the two screens that restated it onto screen 17's
phrasing. That was not in the ruling's scope and was not widened.

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

### What phase 2B actually found, sweeping again

Both methods were run again before anything was edited, and the table above was a lower bound in
two places it did not predict:

- **`MapEmptyInventoryTests` pins R25's clause** (`.contains("may well stand here")`), and R25 is
  not in the table at all. It was found by the symbol-name sweep, not the substring one — the same
  asymmetry `SiteTests.swift:488` demonstrated. The suite caught it anyway, in the first run.
- **Two tests broke on their own *calibration* rather than on their rule.** `SiteTests.emDashRule`
  ended `#expect(SiteCopy.statementBody.contains("—"))` and `MemorialPresentationTests.emDashRule`
  asserted `line.contains("—")` for each line it swept. Both were controls proving the corpus held
  a real em dash — and R1, R2 and R6 deleted every em dash on both screens. Neither is listed as
  load-bearing above, because neither asserts a rewritten string; they assert a *property* the
  rewrites removed. Both now calibrate against a specimen instead, so the control survives the
  corpus.

**The kills cost one UI anchor, and the replacement cost a CI round.** `DeepLinkVoiceOverTests
.testGroveTab` had anchored on screen 08's footnote (`Quiet collecting`), which K5 deleted. Phase 2A
re-anchored it on §3's progress caption and wrote down, in the same comment, that the caption
renders only when the grove has a recognized species — "a device whose grove is empty would fail
here on a healthy build" — and shipped it. It passed on the author's simulator, which had recognized
one in an earlier test, and failed on CI's clean runner at the first opportunity. E216's family
exactly, and a demonstration that naming a hazard in a comment is not guarding it. The anchor now
carries both of the screen's legitimate states, and the fix was proved by erasing the device to
reach CI's condition and watching the pre-fix anchor fail there. **The real cost of removing a
footnote is that a test anchored on it needs a state-independent replacement, and the empty-state
sentence is half of one.**

**Where a phrasing assertion could become a fact assertion, it did.** Three cases:

| Test | Was | Is |
| --- | --- | --- |
| `LandContextScreenTests.theQuestionIsOptional` | whole-sentence equality on R12 | the empty form is non-empty and contains no pressure word — the contract the test's own name is about |
| `MemorialPresentationTests` (steward clause) | the clause renders iff `verificationState == .orgVerified` | the row reads the same on both arms and names nobody — the stronger claim, and it catches a re-introduction |
| `ActivityPresentationTests` (ceiling sentence) | the footnote's exact text on two fixtures | with a care month at the ceiling, the care count reaches no drawn string on the screen — BUILD-PLAN §4's actual rule, held over whatever the screen draws |

`SiteTests.theStatementIsHonest` was retargeted rather than deleted: it asserted the clause R1
removed, and now asserts the two facts that survive. The rule it was guarding (ARCHITECTURE §5.4)
was never carried by that sentence — `noSentencePromisesAnOutcome` sweeps every string the screen
can draw, and it is untouched.

---

## 9. Ambiguities — asked, and answered

All five were put to the owner on 2026-08-23. Four are closed; one was never in scope.

1. **Does this round amend `SCREENS.md`?** — **Yes, in the same commit.** Done: 8 strikes in
   `SCREENS.md` and 1 in `PROTOTYPE-FLOW.md`, each line struck through rather than deleted and
   each carrying `**REMOVED — copy audit 2026-08-23**` with a pointer back here. Struck rather
   than deleted so the transcription stays honest about what the mock said.
2. **K10/K11 or R14/R15?** — **KILL.** Both rows are gone, builders included.
3. **`AccountAskCopy.body` (R26)** — **KEEP the promise verbatim** (see §0, ruling 4). Waived;
   never re-raise.
4. **Footnotes as a class** — **the slot is the artifact; remove it everywhere.** Scope and its
   deliberate edges are written out in §4a, including the four footnotes this round did not touch
   and why.
5. **Seed-database prose** — **out of scope** until the owner rules on it. Unchanged.

### Answered in the second round

6. **Four footnotes remain** (§4a). Ruling 3's enumeration named eight sites and phase 2A removed
   exactly those eight; `ActivityCopy.footnote`, `CheckInCopy.footnote`, Measure's two, and
   `GrowthHistoryCopy.unrenderedFootnote` were still drawn. Whether ruling 3 meant *all* footnotes
   was a question, not an inference. — **Answered: yes, all four go** (ruling 6), with one
   exception for a fact (ruling 7). Implemented in phase 2B; see §4b.

### Open after the second round

7. **Screen 13 no longer says its three charts share a scale.** The fact was true and is now
   unstated (§4b). Not a defect and not an oversight — the consequence of a ruling that made
   exactly one exception, for screen 16 — but the next person to read the chart will not be told.
   A one-line decision for the owner if it is wanted back, and deliberately not taken here.
8. **`stays yours alone` survives once, in screen 06's dashed disclosure.** R20/R21 moved the
   confirmation and the You tab's empty state onto screen 17's `private to you`; the disclosure
   itself was not in the table and was not touched, so the synonym the two rewrites were partly
   meant to retire is still in the app in one place. Recorded rather than widened.
9. **Seed prose is still unscreened** (ambiguity 5, unchanged). Out of scope until ruled on.

## 10. Where the machinery is

Extraction scripts and the intermediate TSVs are in the session scratchpad
(`copyaudit/{extract,filter,filter2,filter3,filter4,tests,count}.py`,
`all_literals.tsv` → `prose.tsv` → `candidates.tsv`). They are throwaway; nothing in this
document depends on re-running them, and every file:line above was read in the source.
