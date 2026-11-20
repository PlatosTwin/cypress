# Cypress TestFlight feedback triage, 2026-11-12 (v2)

Read-only pass. Nothing in the repo was edited. Main checkout fast-forwarded to `0479f2f4` (#204, which
added the first triage as `docs/investigations/beta-feedback-triage-2026-11-12.md` and ROADMAP 94-97).
This version replaces v1's ranking with the fresh pull folded in.

## New since 2026-09-28

Run **43331239955** (dispatched 2026-11-12T23:43:29Z, success), artifact `generatedAt`
2026-11-12T23:45:21Z: **38 screenshot submissions, 0 crash submissions, 0 customer reviews,
`notes: []`**, 82 builds. All 33 ids from the 2026-09-28 set are present, so **5 are new**. All 5 are
build 82, iPhone17_5, iOS 26.6.1, 390 pt, on mobile data. `testerId` is still empty (chip 53), and the
JSON still holds zero `@` characters.

| # | Date (UTC) | Summary | Outage window? | Status, with evidence | Roadmap |
|---|---|---|---|---|---|
| **F34** | 09-30 22:03 | *"Strange empty white space has appeared below bottom menu after browsing the tabs for City and Neighborhood"*. Screenshot: My Grove > Trees with a white band about 60 pt tall under the tab bar. "City and Neighborhood" are the Journal's two stats segments | No | **Open**, defect, not reproduced. Same visual family as F8 (white area around the keyboard, shipped). Likely a safe-area or keyboard inset left behind by the Journal's area picker; unconfirmed | **Not in roadmap** |
| **F35** | 09-30 22:04 | *"Does sync on WiFi actually work on WiFi only? Just took a bunch of photos and am not on WiFi and they appear synced here"*. Screenshot: screen 17, `Sync photos on wifi only` ON, visits marked synced Sep 30 | No | **Open, confirmed in code: the toggle does nothing outside screen 17's `syncNow`.** Every feature writer (`VisitOutboxWriter:132`, `CheckIn`, `CareLog`, `Measure`, `Reminder`, `Favorite`) and `OutboxViewState.retry/retryAll` call `drain()`, whose `photoUploadsAllowed` defaults to `true`. `syncNow(isOnWifi:)` is the only gated call and, by its own comment, has no caller, because the app has no reachability source (ERRATA **E81**). So photo bytes upload on cellular while the switch says they will not | **Not in roadmap** (E81 names the missing source, not this effect) |
| **F36** | 10-02 02:00 | *"Took this photo yesterday on a tree I added and now it says can't be opened…"*. Screenshot: `PhotoViewerView` showing `That photograph could not be opened`, caption `Full tree · Sep 28, 2026`, on a self-added tree | No | **Open, not reproduced, cause unknown.** Two suspects on main, neither proven: chip **67** (a keyed photo row with no bytes, which #194 can create and which pairs with the phone's own copy) and chip **76(a)** (photo identity after adoption). The caption's Sep 28 date against the tester's "yesterday" (Oct 1) suggests the viewer opened a different copy than the one just taken | Nearest: chips 67, 76 |
| **F37** | 10-31 20:29 | *"Put the pin in the wrong place. Need an edit feature"*. Screenshot: map with a dashed community pin a few meters from the blue dot | No (before Nov 2) | **Open.** Second report of F31(a), relocation. The location-correction verb is in C1; the control is C3 | Community trees C1, C3 (F31) |
| **F38** | 11-12 23:01 | *"I am in DC. Why the fuck does this say Castro market still???"*. Screenshot: My Grove > Species, `47 of 187 species · you can recognize in the Castro/Upper Market` | Ends at the outage's last day; **not a sync symptom** | **Open; behaves as built, reads as a bug.** The ring's area is the reader's most-visited neighborhood (`LocalAPI.groveSpecies`, RULINGS **R29**), never their location, and the caption does not say so. F17 fixed the same complaint on the Journal's stats (picker plus accuracy rule) but not on screen 08. D.C. also ships no neighborhoods (chip 88), so a location rule would find none there | **Not in roadmap**; family of F17; touches chip 88 |

**Sync outage (Nov 2-12):** no new item reports a sign-in, sync or upload symptom. F38 is the only item
in the window, and it is about area naming. Nothing in this pull is attributable to the outage.

**Items that change the top 10:** F35 enters at #2 (P0: a drawn control that does nothing, costing
cellular data). F36 enters at #4 and F38 at #5 (P1). F37 raises C1 from one report to two. The agreement
item (ROADMAP 94) is done and dropped; "re-pull feedback" is done by this run.

## Summary

- Feedback through 2026-11-12 is now read: **38 submissions** from one device. **23 fixed on main,
  1 refused (F16), 14 open** (the 9 from v1 plus the 5 new). Every fixed item is in build 82 or
  earlier, except #200 (contribution-camera zoom), which is on main and in no build.
- **Build 82 (2026-09-30) is still the newest build testers have.** The agreement is accepted, but
  the TestFlight upload for the D.C. merge is still pending. Build 82 expires around 2026-12-29.
- **New finds with no roadmap entry:** F35 (wifi-only toggle ignored, confirmed in code), F34 (white
  band under the tab bar), F38 (Grove ring names a neighborhood the reader is far from). F36 has
  only a nearest guess (chips 67, 76).
- **Owner priorities:** "performance first" (2026-09-01) closed on 2026-09-04. The community-trees
  order C1, then C2, then C3 still stands, and F37 adds a second report behind it.

## Ranked to-do list

Factors per item: reports (R), severity (Sev), half-built (HB), dependencies (Dep), size (S/M/L).

### P0: broken for testers, or blocks everything else

| # | Item | Why | R | Sev | HB | Dep | Size |
|---|---|---|---|---|---|---|---|
| 1 | **Ship a new TestFlight build** (the pending D.C.-merge upload) | #200 is stranded; nothing below reaches testers without it; build 82 expires near 2026-12-29 | 0 (ops) | High | Pipeline ready | Upload in progress | S |
| 2 | **F35: honor the wifi-only toggle** | The switch on screen 17 does nothing; photos upload on cellular. An untrue label of the ARCHITECTURE §5.4 class | 1 | High | Gate exists in `OutboxQueue`; only the caller side is missing | A reachability source (E81), e.g. `NWPathMonitor`; pass it to every `drain()` | S-M |

### P1: frequent friction, the main open tester requests, or tester-visible defects

| # | Item | Why | R | Sev | HB | Dep | Size |
|---|---|---|---|---|---|---|---|
| 3 | **C1, community trees core** | Owner's decided answer to F31; F37 is a second report; also fixes chip 79 | **2** (F31, F37) | Med | **Yes**: last commit 2026-10-01 "wip, unverified", 19+ behind main | Migration seat; server deploy check | L |
| 4 | **F36: a contributor's own photo "could not be opened"** | The tester cannot see a photo they just took; unreproduced | 1 | Med-High | No | Reproduce first; check chips 67 and 76 | S-M |
| 5 | **F38: Grove ring names the most-visited neighborhood, not where you are** | Reads as broken on D.C.'s launch day; F17 is the same complaint on another screen | 2 (F17 family) | Med | F17's picker exists to reuse | Owner choice under R29 / constraint 21: say "your most-visited neighborhood", add F17's picker, or follow location; D.C. has no neighborhoods (chip 88) | S-M |
| 6 | **C2, sync down** | Second half of F31 | 1 | Med | No | C1 | M |
| 7 | **F32 part 3: the 10 m add-a-tree refusal** | Blocks logging where no inventory exists | 1 | Med | No | Owner ruling (constraint 16) | S after ruling |
| 8 | **F32 part 2: sentence-case species names** + chip 91 | Owner ruled 2026-09-28; D.C. added more disagreement | 1 | Low-Med | No | Next seed publish | S-M |
| 9 | **Chip 77: iOS 26 hides `confirmationDialog` cancel buttons** (7 sites) | Testers run iOS 26.6.1 | 0 | Med | Fix pattern exists (#185) | iOS 26 runtime | S-M |
| 10 | **Chip 89: `dim_region` id collision across packs** | Second pack refused on a phone mid-update | 0 | Med | No | Own round | M |
| 11 | **Chip 76(a): photos double again on a signed-out device** | F30 family; possibly behind F36 | 0 | Low-Med | No | None | S |
| 12 | **Chips 62, 13, 59, 16: sync-service privacy and security** | C2 makes community trees public | 0 | Med | No | 13 and 16 need rulings | S each |
| 13 | **C3, community trees UI** | Strikes F31 and F37 | 2 | Med | No | Owner answers, C1, C2 | L |
| 14 | **Chip 87: recheck DDOT GLOBALID, early December** | D.C. ids may churn | 0 | Med | n/a | Dated | S |

### P2: polish, design rounds, and content

| # | Item | R | Notes | Size |
|---|---|---|---|---|
| 15 | **F34: white band under the tab bar** after the Journal's City/Neighborhood tabs | 1 | Reproduce on device; inset leak suspected | S |
| 16 | **F32 part 1: vernacular synonyms** ("cook pine") | 1 | Cited sourcing round | M |
| 17 | **F4: a time filter** on My Grove > Species (ROADMAP 96) | 1 | Waits on the period vocabulary | S-M after design |
| 18 | **F22: species distribution map on screen 07** | 1 | Design round | M |
| 19 | **F25: You tab UI/UX pass** | 1 | Design round | M |
| 20 | **F15: enrich the tree profile** | 1 | Cited content | L |
| 21 | **D.C. species round** (chip 85), UTC planting day (chip 92), D.C. neighborhoods (chip 88, now also behind F38) | 0 | | M + S + M |
| 22 | **City disputes, remaining parts** | 0 | Badge needs a server read | M-L |
| 23 | **Chips 81 and 82: physical-phone checks** | 0 | | S |
| 24 | **Chip 53: empty `testerId`** | 0 | Still empty on all 38 | S |
| 25 | **Chip 90** (`upload.sh` stale manifest), **chip 93** (D.C. on the web) | 0 | | S + S |

### P3: later

| # | Item | R | Notes |
|---|---|---|---|
| 26 | **F1 leftover** (ROADMAP 95) | 1 | Owner call on width or copy |
| 27 | **D6: Cities search and state filter** | 1 | Catalog holds 8 packs |
| 28 | **F9: Marin / Sausalito / Mill Valley** | 1 | Seed expansion, not scheduled |
| 29 | Owner backlog: photos through the seasons; root README | 0 | |
| 30 | Chip renumbering (ROADMAP 97) at the next merge of C1 or PR #201 | 0 | Bookkeeping |
| 31 | Remaining chips (tooling, CI, web, server hygiene) | 0 | Grouped below |

## Feedback to roadmap

All 38 are iPhone17_5 at 390 x 844 pt. Builds 18 and 25 ran iOS 26.5.2; builds 37-60 iOS 26.6; builds 77 and 82
iOS 26.6.1. F-numbers are the chronological position, as PR #118 and the roadmap number them; D-numbers
are PR #118's Cities-screen labels.

| # | Date | Build | Summary | Status, with evidence | Roadmap |
|---|---|---|---|---|---|
| F1 | 08-06 | 18 | Ghost-photo caption "cut off", flows poorly | **Partly fixed**: leading 4.2 to 2.1 (d7fdbd4a, E254). Width/copy decision still open in code (`ghostCaptionMaxWidth = 80`) | Counted shipped on 08-28; **E254 §2 decision not in roadmap** |
| F2 | 08-06 | 18 | Where do phenology tags go? | Fixed: #58 shows observed states on the profile's activity feed | 08-28 shipped |
| F3 | 08-08 | 25 | Zoom while taking a photo | Fixed (R80 item 5, screen 04 pinch) | 08-28 shipped |
| F4 | 08-08 | 25 | Time filter: today / week / month / 30 days / year | **Open.** Filed on My Grove > Species | Also outstanding: F4; "share one root cause" |
| F5 | 08-08 | 25 | Compass on the map | Fixed | 08-28 shipped |
| F6 | 08-08 | 25 | Show a date, not a time, past one day | Fixed | 08-28 shipped |
| F7 | 08-08 | 25 | Next-tree buttons: next nearest, map, tree | Fixed | 08-28 shipped |
| F8 | 08-08 | 25 | White area around the keyboard | Fixed | 08-28 shipped |
| F9 | 08-09 | 25 | Street-tree data for Marin / Sausalito / Mill Valley | **Open, deferred** | Seed inventory expansion; R80 deferral |
| F10 | 08-15 | 37 | First tree shows "Unidentified" for a second | Fixed | 08-28 shipped |
| F11 | 08-21 | 41 | Pinch zoom in the photo viewer | Fixed (R80 item 4) | 08-28 shipped |
| F12 / D1 | 08-22 | 49 | Offered download of bundled SF / San Jose | Fixed, #118 | PR #118 |
| F13 / D2 | 08-22 | 49 | Download very slow | Fixed, #118 (0.28 s to 0.006 s on fixture) | PR #118 |
| F14 / D3 | 08-22 | 49 | Download dies when the app closes or the screen sleeps | Fixed, eba00fc (background `URLSession`) | 09-28 section |
| F15 | 08-23 | 49 | Enrich the tree profile | **Open** | Also outstanding: F15 |
| F16 | 08-23 | 49 | Trees-seen counters | **Refused** by owner 2026-08-31 (D1) | F16, struck |
| F17 | 08-23 | 49 | Neighborhood stats for the wrong place | Fixed, #132 | F17, struck |
| F18 / D4 | 08-23 | 49 | Say which cities ship in the bundle | Fixed, #118 | PR #118 |
| F19 / D5 | 08-23 | 49 | Group the NYC boroughs | Fixed, #118 | PR #118 |
| F20 / D6 | 08-23 | 49 | Search and state filter on Cities | **Open**, waits for catalog growth | D6 (09-28 section) |
| F21 / D7 | 08-23 | 49 | Four Cities-screen complaints (UPDATE vs DOWNLOAD, false update, grouping, cumulative Use) | Fixed, #118; cumulative Use ruled R84 | PR #118, R84 |
| F22 | 08-23 | 49 | Species distribution map on the field guide | **Open** | Also outstanding: F22 |
| F23 | 08-23 | 49 | "See them all on the map" link | Fixed, #130 and #135 (placement awaits ratification) | F23, struck |
| F24 / D8 | 08-23 | 49 | Cannot re-use Manhattan after switching | Fixed, #118 | PR #118 |
| F25 | 08-23 | 49 | You/Account page pass | **Open** | Also outstanding: F25 |
| F26 | 08-23 | 49 | Unit switch clears the height value | Fixed (keep digits, annotate) | F26, struck |
| F27 | 08-23 | 49 | Cannot edit or delete a measurement | Fixed, #154 and #156 (withdrawal) | F27, struck; chip 56 splice |
| F28 | 08-23 | 49 | Adding a reading is two small taps deep | Fixed ("Add a reading" link) | F28, struck |
| F29 | 08-27 | 60 | Terrible spacing in the header | Fixed, #191, in build 82 | F29, struck |
| F30 | 09-25 | 77 | "2 photos" pill, one photo inside | Fixed, #194, in build 82; server release v13 at 23:33 UTC follows #194's 23:32 merge, so the server half appears deployed (inferred from timestamps) | F30, struck; chip 76 |
| F31 | 09-26 | 77 | Move a self-added tree; share added trees with everyone | **Open**, decided, C1 half-built | Community trees C1, C2, C3 |
| F32 | 09-26 | 77 | Cook pine missing; lowercase names; 10 m refusal | **Open**, three parts | F32 (1, 2, 3); chip 91 |
| F33 | 09-28 | 77 | Zoom on add-a-tree's viewfinder | Fixed, #195, in build 82. Sibling #200 (05 and 09 camera) is on main and in **no build** | F33, struck; chips 80, 81 |
| F34 | 09-30 | 82 | White band under the tab bar after the Journal's area tabs | **Open**, defect, unreproduced | **Not in roadmap** |
| F35 | 09-30 | 82 | Wifi-only photo sync does not hold | **Open**, confirmed in code (all writers call `drain()` with the default `true`; E81) | **Not in roadmap** |
| F36 | 10-02 | 82 | Own photo on a self-added tree "could not be opened" | **Open**, unreproduced | Nearest chips 67, 76 |
| F37 | 10-31 | 82 | Pin placed wrong, need to edit it | **Open** (second F31(a) report) | C1, C3 |
| F38 | 11-12 | 82 | In D.C., Grove ring still says Castro/Upper Market | **Open**, as built (R29), reads as a bug | **Not in roadmap**; F17 family; chip 88 |

## Open roadmap items with no feedback behind them

Unchanged from v1, except: ROADMAP 94 is done; 95 (F1) and 96 (F4) now carry feedback; 97 (chip
renumbering) joins "Docs and paperwork". Chips 67, 76 and 88 now have possible feedback behind them
(F36, F38) and are ranked above.

- **Community trees and sync service:** chips 9, 10, 11, 54, 58, 60, 61, 64, 65, 66, 68, 69, 71;
  perf leftover "post-drain favorite reconcile and replica lag".
- **Privacy and security:** chips 13, 16, 59, 62, 63; iNaturalist licensing (answer before launch).
- **City disputes:** badge, filter, missing-tree entry point, community-flagging redesign.
- **D.C. and data pipeline:** chips 85-93, 3, 17, 18, 33, 34, 35, 36, 37; seed inventory expansion.
- **App UI and correctness:** chip 77, `cypressHitArea` overhang audit, chips 15, 19, 42, 81, 82, 84;
  MapKit road-color inversion.
- **Web (W):** W-B, W-D, W-G remainders; open questions 2-5; chips 21, 22, 25, 27-32, 39, 45-48,
  51, 93.
- **CI, tooling, test harness:** chips 1, 2, 5, 6, 8, 12, 20, 23, 38, 40, 41, 43, 44, 49, 53, 55, 57,
  72-75, 83; the half-applied exit-code taxonomy; `assertEveryControlIsLabeled` scope; UI classes
  that inherit the opening camera; PR #201; branch `tools/fetch-seed-diagnostics` (no PR).
- **Docs and paperwork:** chips 56 and 97; copy-audit questions 7-9; F23, F26, F28 and R85 awaiting
  ratification; root README.

## Method

- Repo: main checkout fast-forwarded to `0479f2f4`. Read ROADMAP 94-97 and the sections v1 read.
- Pull: run 43331239955 (success). Compared ids against run 36494988293's 33: 0 missing, 5 new.
- Looked at all 5 new screenshots.
- Code checks: `OutboxQueue.drain(photoUploadsAllowed:)` and every caller (grep of `.drain(` under
  `Cypress/`); `OutboxViewState.syncNow` and its comment; ERRATA E81; `LocalAPI.groveSpecies` and
  `GrovePresentation` for the ring's area; `PhotoViewerView.unavailable`; chips 67, 76, 88.
- v1's status calls for F1-F33 are kept (evidence in v1 and in
  `docs/investigations/beta-feedback-triage-2026-11-12.md`).
- **What the API cannot tell us:** tester count (empty `testerId`); resolution state; unsubmitted
  crashes; reviews (version 1.0 is still `PREPARE_FOR_SUBMISSION`).
- **Not verified:** F34 and F36 are unreproduced, and their causes are suspects only. F35's effect
  is read from code, not measured on a phone on cellular. Whether F38's tester had the D.C. pack
  installed is unknown; the ring's rule does not depend on it.

## Sources

- Feedback: the `asc-feedback` artifact of run 43331239955 (generated 2026-11-12T23:45:21Z, 38
  items with screenshots). The first pass used run 36494988293 (2026-09-28, 33 items), all of which
  are in this set. GitHub keeps artifacts for 90 days; re-run the workflow for anything newer.
- F35 was confirmed against main by the orchestrator: `OutboxViewState.syncNow(isOnWifi:)` is the
  only call that passes the switch to `OutboxQueue.drain`, nothing calls `syncNow`, and nothing in
  `Cypress/` uses `NWPathMonitor`.

