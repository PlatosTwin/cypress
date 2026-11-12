# Cypress TestFlight feedback triage, 2026-11-12

Read-only pass made by an agent on 2026-11-12, against main at `30eac915` (#203, D.C.). The
queue itself lives in `docs/ROADMAP.md`; this file is the record of how it was ranked that day.

## Summary

- **No new feedback could be pulled today.** Run **43328447485** of `asc-feedback.yml` failed with
  HTTP 403 `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` ("A required agreement is missing or
  has expired", link `/business`). This is an Apple account matter: the Account Holder must accept
  the updated agreement in App Store Connect, under Business. No key is needed or was asked for.
- **The same 403 has blocked every TestFlight upload since 2026-10-02.** The `release` job of run
  36968512685 (#200's merge) failed on this exact error. **Build 82** (2026-09-30, main at #191) is
  the last build testers have. TestFlight builds expire 90 days after upload, so build 82 stops
  working around **2026-12-29** unless the agreement is renewed and a new build ships.
- The triage therefore uses the newest artifact that exists: run **36494988293** (2026-09-28),
  **33 screenshot submissions, 0 crash submissions, 0 customer reviews, `notes: []`**. All 33 come
  from one device (iPhone17_5, 390 x 844 pt). `testerId` is empty on all 33 (chip 53), so the number
  of testers cannot be counted. Treat it as one tester.
- **Of the 33: 23 fixed on main, 1 refused by the owner (F16), 9 still open.** Every fixed item is in
  build 82 or earlier, except #200 (contribution-camera zoom), which is on main and in no build.
- **Nov 2-12 sync outage:** no feedback from that window is visible, because the API has refused
  every call since 2026-10-02. Nothing here can be attributed to the outage, and nothing rules it out.
- **New finds with no roadmap entry:** (1) the expired Apple agreement and its two effects;
  (2) F1's leftover owner decision on the ghost caption's width and copy (ERRATA E254 §2), which the
  2026-08-28 reconciliation counted as shipped; (3) chip-number collisions: the C1 branch and PR #201
  each add their own chips 85-87, and main now uses 85-93 for D.C.
- **Owner priorities checked:** "performance outranks the feature queue" (2026-09-01) closed with the
  perf campaign on 2026-09-04 (ROADMAP "Perf campaign close"; memory note says treat it as closed
  unless the owner repeats it). The standing decisions that still shape the order are the F31
  community-trees decisions of 2026-09-28 (C1, then C2, then C3) and "one migration author per round".

## Ranked to-do list

Factors per item: reports (R), severity (Sev), half-built (HB), dependencies (Dep), size (S/M/L).

### P0: broken for testers, or blocks everything else

| # | Item | Why | R | Sev | HB | Dep | Size |
|---|---|---|---|---|---|---|---|
| 1 | **Accept the expired Apple agreement** (App Store Connect, Business) | Blocks feedback pulls, every TestFlight upload since 2026-10-02, and testers lose build 82 near 2026-12-29 | 0 (ops) | High | n/a | Owner only (Account Holder) | S |
| 2 | **Ship a new TestFlight build once #1 is done**, then re-pull feedback | #200 is stranded on main; any fix below cannot reach testers; Oct-Nov feedback is unread | 0 | High | Pipeline ready | #1 | S |
| 3 | **Re-pull feedback and re-run this triage** for 2026-09-28 to now | Six weeks of feedback, including the Nov 2-12 outage window, are unseen | ? | Unknown | n/a | #1 | S |

### P1: frequent friction, the main open tester requests, or tester-visible defects

| # | Item | Why | R | Sev | HB | Dep | Size |
|---|---|---|---|---|---|---|---|
| 4 | **C1, community trees core** (`feat/community-trees-core`) | The owner's decided answer to F31; also fixes chip 79 on the branch | 1 (F31) | Med | **Yes**: last commit 2026-10-01 is "wip, unverified"; 19 commits behind main | Migration seat; server deploy check before merge | L |
| 5 | **C2, sync down** | Second half of F31 ("go to everyone") | 1 (F31) | Med | No | C1 | M |
| 6 | **F32 part 3: the 10 m add-a-tree refusal** | Tester cannot log trees where no inventory exists; owner decision (constraint 16) | 1 | Med | No | Owner ruling | S after ruling |
| 7 | **F32 part 2: sentence-case species names** + chip 91 (one source of common names) | Owner ruled sentence case 2026-09-28; not done; D.C. pack added more disagreement ("Trident maple" vs "trident maple") | 1 | Low-Med | No | Next seed publish (Fly worker go-ahead) | S-M |
| 8 | **Chip 77: iOS 26 hides `confirmationDialog` cancel buttons** at 7 sites | Testers run iOS 26.6.1; take-back and delete sheets lack a cancel | 0 | Med | Fix pattern exists (#185) | iOS 26 runtime to confirm | S-M |
| 9 | **Chip 89: `dim_region` id collision across packs** | A phone mid-update can hold two packs sharing a region id; the second is refused | 0 | Med (data) | No | Own round + test | M |
| 10 | **Chip 76(a): photos can double again on a signed-out device** after adoption | Same symptom as F30 on a narrower path | 0 (F30 family) | Low-Med | No | None | S |
| 11 | **Chips 62, 13, 59, 16: privacy and security on the sync service** | 62: proximity conflict shows another adder's address and exact second; 13: per-tree counts of user acts vs D1/R27.1; 59: device claim needs no proof; 16: spoofable `Fly-Client-IP`. C2 makes community trees public, which raises the stakes | 0 | Med | No | 13 and 16 need rulings | S each |
| 12 | **C3, community trees UI** | Strikes F31; every surface is unmocked | 1 (F31) | Med | No | Owner answers (C3 question list), C1, C2 | L |
| 13 | **Chip 87: recheck DDOT GLOBALID stability, early December** | If ids churn, every D.C. tree's identity churns | 0 | Med | n/a | Dated | S |

### P2: polish, design rounds, and content

| # | Item | R | Notes | Size |
|---|---|---|---|---|
| 14 | **F32 part 1: vernacular synonyms** ("cook pine" is in the seed as "Coral reef araucaria") | 1 | Sourcing round, cited aliases only (constraint 15) | M |
| 15 | **F4: a time filter** | 1 | **New evidence:** the screenshot is My Grove's Species tab (screen 08). The open question becomes only the vocabulary | S-M after design |
| 16 | **F22: species distribution map on screen 07** | 1 | Design round; C18 reduced map exists | M |
| 17 | **F25: You tab UI/UX pass** | 1 | Design round; no You screen in the spec | M |
| 18 | **F15: enrich the tree profile** (ID help, history, edibility) | 1 | Content work with citations | L |
| 19 | **D.C. species round** (chip 85) and planting-date UTC fix (chip 92) | 0 | D.C. coverage 86.27%, waived | M + S |
| 20 | **City disputes, remaining parts**: badge, "trees with data issues" filter, missing-tree entry, community-flagging redesign | 0 | Badge needs a server read; flagging redesign overlaps C3 | M-L |
| 21 | **Chip 81 and 82: physical-phone checks** (F33 pinch, dispute location wait) | 0 (F33 follow-up) | Only a device answers them | S |
| 22 | **Chip 53: feedback artifact has empty `testerId`** | 0 | Without it, "how many testers" cannot be answered | S |
| 23 | **Chip 90: `upload.sh` should refuse a stale manifest**; chip 93: serve D.C. on the web | 0 | Both small, both D.C. follow-ups | S + S |

### P3: later

| # | Item | R | Notes |
|---|---|---|---|
| 24 | **F1 leftover: the no-ghost caption's width or copy** (E254 §2, three options) | 1 | **Not in roadmap.** Leading was fixed in d7fdbd4a; width 80 and copy `no ghost yet · first photo` are unchanged |
| 25 | **D6: Cities search and filter by state** | 1 | Trigger is the catalog near 20 packs; it holds 8 now. Needs a publisher `state` field |
| 26 | **F9: Marin / Sausalito / Mill Valley coverage** | 1 | Folded into "Seed inventory expansion" (R80 deferral); not scheduled |
| 27 | Owner backlog: photos through the seasons; root README | 0 | Design round; scope is the owner's |
| 28 | Remaining chips (tooling, CI, web, server hygiene) | 0 | Listed below by group |

## Feedback to roadmap

All 33 are iPhone17_5 at 390 x 844 pt. Builds 18 and 25 ran iOS 26.5.2; builds 37-60 iOS 26.6; build 77
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

## Open roadmap items with no feedback behind them

Grouped. Chip numbers are from `docs/ROADMAP.md` on main at `30eac915`.

- **Community trees and sync service:** C1 (also chip 79), C2, C3; chips 9 (reading vs withdrawal
  race), 10 (what a signed-out phone can take back), 11 (withdrawn-to-empty tree), 54, 58, 60, 61,
  64, 65, 66, 67, 68, 69, 71, 76; perf leftover "post-drain favorite reconcile and replica lag".
- **Privacy and security:** chips 13, 16, 59, 62, 63; "iNaturalist licensing" (needs an answer
  before launch).
- **City disputes:** badge, filter, missing-tree entry point, community-flagging redesign.
- **D.C. and data pipeline:** chips 85-93 (89 and 87 most urgent), 3, 17, 18, 33, 34, 35, 36, 37;
  seed inventory expansion (Oakland, Los Angeles and 12 more).
- **App UI and correctness:** chip 77 (iOS 26 cancel buttons), `cypressHitArea` overhang audit,
  chip 42, chip 15 (one current height per tree), chip 19 (beloved floor), "MapKit road-color
  inversion", chips 81 and 82 (phone checks), chip 84.
- **Web (W):** W-B, W-D, W-G remainders; open questions 2-5 (withdrawn records on indexed pages,
  CORS and Sign in with Apple JS, Coordinator dashboard, moderation console); chips 21, 22, 25, 27,
  28, 29, 30, 31, 32, 39, 45, 46, 47, 48, 51, 93.
- **CI, tooling, test harness:** chips 1, 2, 5, 6, 8, 12, 20, 23, 38, 40, 41, 43, 44, 49, 53, 55, 57,
  72, 73, 74, 75, 83; exit-code taxonomy left half-applied; `assertEveryControlIsLabeled` scope;
  UI test classes that inherit the opening camera; PR #201 (open, `ci/build-once-for-ui-shards`);
  branch `tools/fetch-seed-diagnostics` (one commit, no PR, 455 commits behind main).
- **Docs and paperwork:** chip 56 (splice 33 pending files, orchestrator only); copy-audit questions
  7-9; F23 placement, F26 copy, F28 affordance, R85 awaiting owner ratification; root README.

## Method

- Repo: main checkout, `git pull --ff-only` from 12 behind to `30eac915`. Read CLAUDE.md, the
  workflow header, ERRATA E254, ROADMAP (all sections), PR #118's body, and the memory notes.
- Pull: `gh workflow run asc-feedback.yml` at 2026-11-12T23:23:27Z, run 43328447485, failed in about
  4 s with the 403 above. No artifact was uploaded.
- Fallback: downloaded run 36494988293's artifact (created 2026-09-28T22:53:51Z, `generatedAt`
  22:53:35Z, expires on GitHub 2026-12-27) and run 32649153871's (2026-08-23, 28 items). Every
  August id is in the September set, so the September file is the full record.
- Open vs fixed: the 2026-08-28 and 2026-09-28 roadmap reconciliations, checked against
  `git log origin/main` for each named PR (#118, #130, #132, #135, #154, #156, #191, #194, #195,
  #200), the TestFlight `release` job logs (build 82 on 2026-09-30; the 403 on 2026-10-02), `fly
  releases -a cypress-sync` (v13 on 2026-09-29 23:33), and code greps for F1, F2 and F32.
- Screenshots: looked at F4's (My Grove > Species), which settles the roadmap's "which screen".
- **What the API cannot tell us:** how many testers (empty `testerId`, chip 53); whether a report
  is resolved (no such flag); crashes no one submitted; anything since 2026-09-28. Customer reviews
  are empty because version 1.0 is still `PREPARE_FOR_SUBMISSION`.
- **Not verified:** that the Apple agreement is the only blocker (the API names no specific
  agreement); the exact commit behind server release v13 (inferred from timing); the current health
  of `cypress-sync` after the outage (`fly status` showed its one machine `stopped` at 22:26Z, which
  may be auto-stop); whether F5-F8 and F10 still behave on build 82 (taken from the 08-28 audit's
  receipts, not re-read).

## Sources

- Feedback: the `asc-feedback` artifact of run 36494988293 (2026-09-28, 33 items, screenshots
  included). GitHub keeps it until 2026-12-27; re-run the workflow after the agreement is accepted
  for anything newer.
- Failed pull: run 43328447485. Failed upload: run 36968512685, `release` job.

## Corrections after the pass

- `cypress-sync` was down from 2026-11-12 02:47 UTC because `cypress-sync-db` had been stopped by a
  user request on 2026-11-02. The owner approved restarting both on 2026-11-12, and `/health`
  answered `status: ok` at about 22:15 UTC. The `stopped` state the pass saw at 22:26Z is the app's
  ordinary auto-stop (min 0 machines, auto-start on request).
- Item 2's "pipeline ready" assumes the agreement is the only blocker; the TestFlight run for
  #203's merge (30eac915) is the first upload attempt after the pass and will show it.

