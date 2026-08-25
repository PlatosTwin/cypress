# PROTOTYPE-FLOW — Cypress clickable prototype + Coordinator dashboard

Distilled from:
- `_unzipped/design_handoff_cypress/Cypress Prototype.dc.html` (467 lines; template lines 29–383, logic class lines 385–464)
- `_unzipped/design_handoff_cypress/Cypress Coordinator.dc.html` (133 lines; template lines 24–128, **no logic class — fully static**)
- Context: `_unzipped/design_handoff_cypress/README.md` sections C and D.

The design-tool runtime is `support.js` (`DCLogic`). `setState` is a **React-style shallow merge** and accepts either an object or an updater function (`support.js:755`). `<sc-if value>` = conditional render, `<sc-for list as>` = list render, `{{ x }}` = binding into an attribute or text node. None of this runtime should be ported.

---

# PART 1 — PROTOTYPE STATE MACHINE

## 1.1 Props

| Prop | Type | Default | Effect |
|---|---|---|---|
| `coachmarks` | boolean | `true` | Read as `this.props.coachmarks ?? true`. Gates all guiding tooltips. Derived: `coach = coachOn && screen !== 'camera'`; `coachCam = coachOn && !snapped`. |

## 1.2 State variables (verbatim from `state = {…}`, line 386)

| Variable | Type | Initial | Notes |
|---|---|---|---|
| `screen` | enum `'map' \| 'identify' \| 'profile' \| 'camera' \| 'saved' \| 'grove'` | `'map'` | Single source of screen truth. |
| `snapped` | boolean | `false` | Photo taken in camera. Gates **Log visit**. |
| `note` | string | `''` | Camera note input. |
| `chips` | `{[label]: boolean}` | `{ 'New growth': false, 'Cones': false, 'Storm damage': false }` | Phenology toggles. |
| `visitCount` | number | `3` | "N visits today" on the saved screen. |
| `justVisited` | boolean | `false` | Shows the "just now" Visit row on the profile feed. |
| `treeIdx` | number 0–2 | `0` | Index into `this.trees`. |
| `lastNote` | string | `''` | Note captured on tree 0, echoed into the profile feed. |
| `saves` | number | `0` | Total logged visits this session. Drives account ask + grove "visited today". |
| `account` | enum `'none' \| 'ask' \| 'linked' \| 'dismissed'` | `'none'` | |
| `careOpen` | boolean | `false` | Care bottom sheet (profile only). |
| `careChips` | `{[label]: boolean}` | `{ 'Watered': false, 'Mulched': false, 'Weeded basin': false, 'Litter cleared': false }` | |
| `justCared` | boolean | `false` | Shows the "just now" Care row on the profile feed. |
| `careSummary` | string | `''` | Lowercased, comma-joined list of checked care chips. |
| `shareOpen` | boolean (**not in the initial object**) | read as `s.shareOpen ?? false` | Share bottom sheet. |
| `copied` | boolean (**not in the initial object**) | read as `s.copied ?? false` | Copy-link success state. |

`this.trees = ['Grandmother Cypress', 'The Tea Tree at 46th', 'Ginkgo on Noriega']` (line 387) — a class field, not state.

## 1.3 Every mutation

| Handler | Trigger | Exact mutation |
|---|---|---|
| `goMap` | map-back chevrons, "Done for today", grove Map tab | `{screen:'map'}` |
| `goIdentify` | "What tree is this?" FAB | `{screen:'identify'}` |
| `goProfile` | any map pin, map tree card, any identify candidate card, any grove tree row | `{screen:'profile'}` |
| `goGrove` | map "My Grove" tab; `nextAction` when `treeIdx >= 2` | `{screen:'grove'}` |
| `goCamera` | profile ~~"Visit · say hello with a photo"~~ "Visit · add a photo" | `{screen:'camera', snapped:false, note:'', chips:{'New growth':false,'Cones':false,'Storm damage':false}}` |
| `backFromCamera` | camera ✕ | `{screen: treeIdx === 0 ? 'profile' : 'saved'}` (evaluated at render) |
| `snap` | shutter | `{snapped:true}` |
| `setNote` | note input `onChange` | `{note: e.target.value}` |
| phenology `chip.toggle` | phenology chip tap | `{chips:{...chips, [label]: !chips[label]}}` |
| `logVisit` | "Log visit" | **Guard: `if (!this.state.snapped) return;`** then `{screen:'saved', visitCount: visitCount+1, saves: saves+1, account: (saves+1 === 3 && account === 'none') ? 'ask' : account, justVisited: treeIdx === 0 ? true : justVisited, lastNote: treeIdx === 0 ? note : lastNote}` |
| `nextAction` | "Next nearest" / "Route done" CTA | if `treeIdx >= 2` → `{screen:'grove'}`; else `{screen:'camera', treeIdx: treeIdx+1, snapped:false, note:'', chips:{'New growth':false,'Cones':false,'Storm damage':false}}` |
| `backToProfile` | "See it on the tree's timeline" | `{screen:'profile'}` |
| `goCare` | profile "Care" | `{careOpen:true}` |
| `closeCare` | care scrim | `{careOpen:false}` |
| care `cc.toggle` | care chip tap | `{careChips:{...careChips, [label]: !careChips[label]}}` |
| `logCare` | care sheet "Done" | **Guard: no-op if no care chip is on.** Then `{careOpen:false, justCared:true, careSummary: Object.keys(c).filter(k=>c[k]).join(', ').toLowerCase()}` |
| `goShare` | profile "Share" | `{shareOpen:true, copied:false}` |
| `closeShare` | share scrim | `{shareOpen:false}` |
| `copyLink` | "Copy link" | `{copied:true}` |
| `linkAccount` | Continue with Apple / Continue with Google / Use email | `{account:'linked'}` |
| `dismissAsk` | "Not now · keep saving to this phone only" | `{account:'dismissed'}` |
| `reset` | breadcrumb "restart" | Re-sets the entire initial state object verbatim. **Does not clear `shareOpen` or `copied`** (they are absent from the reset object) — a latent bug; the sheet only renders on `profile`, so it can reappear after restart. |

## 1.4 Derived values (`renderVals()` return)

| Key | Expression |
|---|---|
| `isMap / isIdentify / isProfile / isCamera / isSaved / isGrove` | `screen === '<name>'` |
| `isDark` | `screen === 'camera'` — passed to `IOSDevice dark=` so the bezel goes dark |
| `snapped` / `notSnapped` | `snapped` / `!snapped` |
| `coach` | `coachmarks && screen !== 'camera'` |
| `coachCam` | `coachmarks && !snapped` |
| `treeName` | `trees[treeIdx]` |
| `askAccount` | `account === 'ask' && screen === 'saved'` |
| `askTitle` | `saves === 1 ? 'Keep this visit' : 'Keep your ' + saves + ' visits'` — in practice always `Keep your 3 visits`, since `ask` is only ever set at `saves === 3` |
| `storageLine` | `linked` → `Backed up to your account · joins the public timeline when signal returns.`<br>`dismissed` → `Saving to this phone only. You can add an account any time.`<br>otherwise → `Saved to this phone. You can add an account later to back it up.` |
| `nextLabel` | `treeIdx >= 2` → `Route done · see your grove`; else `'Next nearest: ' + trees[treeIdx+1] + (treeIdx === 0 ? ' · 40 m' : ' · 60 m')` |
| `cameraHint` | `treeIdx === 0` → `Full tree · match last visit's angle` (curly apostrophe `’`); else `Full tree · its first photo` |
| `photoCount` | `justVisited ? 215 : 214` |
| `visitNoteShown` | `lastNote ? '“' + lastNote + '”' : 'photo, no note'` (curly quotes) |
| `careAny` | `Object.values(careChips).some(Boolean)` |
| `careBtnStyle` | enabled → `background:#1D4634;color:#fff;box-shadow:0 4px 14px rgba(20,50,30,.28)`; disabled → `background:#E9ECDE;color:#8B9482`. Shared base: `border-radius:14px;text-align:center;padding:15px;font-weight:700;font-size:16px;cursor:pointer;transition:all .2s` |
| `logBtnStyle` | `snapped` → `background:#4E8F6A;color:#0E1A12`; else → `background:#26332A;color:#5F6F61`. Base: `border-radius:14px;text-align:center;padding:15px;font-weight:800;font-size:16px;cursor:pointer;transition:all .2s` |
| `crumbMap/Identify/Profile/Camera/Saved` | active → `color:#1D4634;font-weight:600;border-bottom:2px solid #2F6B4F;padding-bottom:2px`; inactive → `{}` |

Chip style bases:
- phenology chip base: `border-radius:999px;padding:7px 15px;font-size:13px;cursor:pointer;white-space:nowrap;` — on: `background:#2F6B4F;color:#fff;font-weight:700;border:1px solid #2F6B4F`; off: `background:#1B241B;border:1px solid #2A362B;color:#AEBBAB`
- care chip: `border-radius:999px;padding:12px 18px;font-size:14.5px;cursor:pointer;white-space:nowrap;transition:all .15s;` — on: `background:#2F6B4F;color:#fff;font-weight:700;border:1px solid #2F6B4F`; off: `background:#fff;border:1px solid #E3E8D9;color:#3C4A3E`

## 1.5 Screen → affordance → target

### `map` (874px, bg `#E9E5D4`)
| Affordance | Result |
|---|---|
| Any of the 5 pins (4 green `#2F6B4F`, 1 amber `#B4711F`) | `goProfile` |
| Bottom tree card ("Grandmother Cypress") | `goProfile` |
| "What tree is this?" FAB | `goIdentify` |
| Tab "My Grove" | `goGrove` |
| Search bar, filter chips (All / In bloom / Needs care), cluster badges `12` `7`, GPS dot, tabs Map / Journal / You | **inert** |
| Coachmark (if `coach`) | `Tap any pin, or the card below` |

### `identify` (812px, bg `#F5F6EF`, `padding-top:62px`)
| Affordance | Result |
|---|---|
| Back chevron | `goMap` |
| **Card 1 only** (Monterey Cypress) | `goProfile` |
| Cards 2–4 (Ginkgo / London Plane / Victorian Box) | **inert** (`opacity:.9`) |
| "None of these? Add this tree · not in this prototype" | **inert** (`opacity:.55`) |
| Coachmark (if `coach`) | `it matches—tap the top card` (no spaces around the em dash) |

### `profile` (874px, bg `#F5F6EF`)
| Affordance | Result |
|---|---|
| Back chevron (over photo header) | `goMap` |
| ~~"Visit · say hello with a photo"~~ "Visit · add a photo" | `goCamera` |
| "Care" | `goCare` → care sheet |
| "Share" | `goShare` → share sheet |
| "Favorite", "Report", stat cards, foliage strip | **inert** |
| Care sheet scrim / Share sheet scrim | `closeCare` / `closeShare` |
| Coachmark (if `coach`) | `the ten-second visit starts here` |

**Note:** the profile screen's name, Latin name, recognition note, stats and the two historical feed rows are **hard-coded to Grandmother Cypress** and do not follow `treeIdx`. Only `{{ treeName }}` inside the care/share sheet titles, `{{ photoCount }}`, `{{ careSummary }}` and `{{ visitNoteShown }}` are dynamic. When rebuilding, this should become per-tree data.

### `camera` (874px, dark, bg `#10160F`, viewfinder gradient over `linear-gradient(180deg,#26332A,#131B14)`)
| Affordance | Result |
|---|---|
| ✕ (top-left) | `backFromCamera` → `profile` if `treeIdx === 0`, else `saved` |
| Shutter (68px white circle) | `snap` |
| Note input | `setNote` |
| Phenology chips | `chip.toggle` |
| "Log visit" | `logVisit` — **no-op while `!snapped`**; visually disabled via `logBtnStyle` |
| Shot-type chips (Full tree / Trunk / Leaf close-up), framing corners, offline line | **inert** |
| Coachmark (if `coachCam`) | `tap the shutter` |
| While `!snapped` | ghost overlay + label `ghost overlay 30%`; hint pill `{{ cameraHint }}` |
| While `snapped` | brighter gradient + white flash + pill `Photo added to the timeline` |

### `saved` (812px, bg `#F5F6EF`, `padding-top:62px`)
| Affordance | Result |
|---|---|
| Primary CTA `{{ nextLabel }}` | `nextAction` |
| "See it on the tree's timeline" | `backToProfile` |
| "Done for today · back to the map" | `goMap` |
| Route mini-map, social-proof chip, `storageLine` | **inert** |
| Account sheet (if `askAccount`): Continue with Apple / Continue with Google / Use email | `linkAccount` |
| Account sheet: "Not now · keep saving to this phone only" | `dismissAsk` |
| Account sheet: ODbL checkbox, "Read the short version" | **inert** (checkbox is pre-checked, decorative `✓`) |

### `grove` (812px, bg `#F5F6EF`)
| Affordance | Result |
|---|---|
| Any tree row | `goProfile` |
| Tab "Map" | `goMap` |
| Progress card, neighborhood callout, steward card, tabs My Grove / Journal / You | **inert** |

### Breadcrumb (outside the phone)
`MAP → ID → PROFILE → VISIT → SAVED` + `restart` pill.
Mono `'Spline Sans Mono'` 11.5px `#77836F`. `grove` highlights nothing. `restart` → `reset`.

## 1.6 Gating / conditional rules (complete)

1. **Log visit is disabled until `snapped`.** Both visually (`logBtnStyle`) and functionally (`if (!this.state.snapped) return;`).
2. **Care "Done" is disabled until ≥1 care chip is on.** `logCare` early-returns; `careBtnStyle` grays out.
3. **3rd save triggers the account sheet.** Inside `logVisit`: `account = (saves + 1 === 3 && account === 'none') ? 'ask' : account`. It never re-triggers after `linked` or `dismissed`, and never triggers if the user linked/dismissed earlier (impossible in this flow, since `ask` is the only path in).
4. **Account sheet only renders on the saved screen.** `askAccount = account === 'ask' && screen === 'saved'`.
5. **After tree 3 the next-tree CTA goes to the grove.** `treeIdx >= 2` → label `Route done · see your grove`, action `go('grove')`.
6. **Camera back target depends on progress.** `treeIdx === 0` → `profile`; otherwise → `saved` (you came from the previous tree's success screen, not from a profile).
7. **Coachmarks are hidden on the camera screen** (`coach`), and the camera's own coachmark disappears once snapped (`coachCam`).
8. **Photo count only advances for tree 0.** `justVisited` is only ever set when `treeIdx === 0`, so `photoCount` goes 214 → 215 exactly once.
9. **The note is only remembered for tree 0** (`lastNote`), because the feed it feeds is Grandmother Cypress's.
10. **Grove rows flip to "visited today" by index:** row `i` shows the "visited today · in the outbox" meta when `i < saves`.
11. **Advancing to the next tree clears the shot:** `nextAction` resets `snapped`, `note`, and all phenology chips.
12. **`goCamera` also clears the shot** (same three fields), so re-entering from the profile never shows a stale snap.
13. **Copy state resets on each share open:** `goShare` sets `copied:false`.

---

## 1.7 Fixture data — verbatim

### The three trees (`this.trees`)
```
0  Grandmother Cypress
1  The Tea Tree at 46th
2  Ginkgo on Noriega
```

### Grove list (`groveTrees`) — default meta strings, by index
| # | Name | Default meta | "Visited" meta (when `i < saves`) | Thumb gradient |
|---|---|---|---|---|
| 0 | Grandmother Cypress | `Monterey Cypress · visited 3 d ago` | `visited today · in the outbox` | `radial-gradient(circle at 32% 40%,#4E8F6A 0%,rgba(78,143,106,0) 44%),linear-gradient(170deg,#E4EBD8,#B9CDBC)` |
| 1 | The Tea Tree at 46th | `Australian Tea Tree · DBH taped in May` | same | `radial-gradient(circle at 40% 36%,#9AAF6E 0%,rgba(154,175,110,0) 46%),linear-gradient(170deg,#EBEDDA,#C8D0B0)` |
| 2 | Ginkgo on Noriega | `Ginkgo · adopted as a sapling, 2021` | same | `radial-gradient(circle at 40% 36%,#C9B44A 0%,rgba(201,180,74,0) 46%),linear-gradient(170deg,#EAEFDC,#C4D2B2)` |

Meta style: default `color:#66735F`; visited `color:#28623F;font-weight:700`. Thumb 52×52, radius 12, border `1px solid rgba(29,70,52,.14)`.

### Species candidate cards (identify screen), in order
| # | Common | Latin | Tell | Distance | Selected |
|---|---|---|---|---|---|
| 1 | `Monterey Cypress` | `Hesperocyparis macrocarpa` | `Its tell: scale-like leaves, lemony when crushed` | `3 m N` | yes — eyebrow `Closest · is it this one?`, border `2px solid #2F6B4F`, shadow `0 6px 20px rgba(47,107,79,.16)`, thumb 76px |
| 2 | `Ginkgo` | `Ginkgo biloba` | `Its tell: fan-shaped leaves` | `9 m NE` | no, thumb 60px |
| 3 | `London Plane` | `Platanus × hispanica` | `Its tell: camouflage bark, maple-like leaves` | `14 m E` | no |
| 4 | `Victorian Box` | `Pittosporum undulatum` | `Its tell: wavy leaf edges, honey scent at night` | `17 m S` | no |

Header: `What tree is this?` · status chips `GPS ±9 m` (dot `#3577C9`) and `Two trees in range · confirm by eye` (`background:#F8EFDF;border:1px solid #EBD3A8;color:#8A5A17`). Footer: `None of these? Add this tree` + `· not in this prototype`.

Candidate thumb gradients (all `linear-gradient(170deg,…)` base + 3 radials, border `1px solid rgba(29,70,52,.14)`):
- Cypress: `#4E8F6A / #35704F / #24513B` over `#E4EBD8→#B9CDBC`
- Ginkgo: `#C9B44A / #8A9A3F / #5E7D3A` over `#EAEFDC→#C4D2B2`
- London Plane: `#B9A268 / #7C8A4E / #5C6B3A` over `#EFEDDC→#CFD3B4`
- Victorian Box: `#6FB380 / #3E8E5C / #2C6B45` over `#E6EEDE→#BFD4BE`

### Map screen fixtures
- Labels: `OCEAN BEACH` (rotated 90°, `#5F8C84`), `GOLDEN GATE PARK` (`#7A9C64`), `JUDAH ST`, `NORIEGA ST` (`#98A388`), all `'Spline Sans Mono'` 9px, weight 600, letter-spacing `.16–.18em`.
- Search placeholder: `Species, street, or neighborhood…`
- Filter chips: `All` (active, `#1D4634` / white), `In bloom`, `Needs care`.
- Cluster badges: `12` (32px) and `7` (30px), `#1D4634` on white 3px border.
- Pins: 5 × 18px, `#2F6B4F` except index 2 which is `#B4711F` and pulses. GPS dot `#3577C9` with `box-shadow:0 0 0 8px rgba(53,119,201,.18)`.
- FAB: `What tree is this?` — `#1D4634`, `box-shadow:0 8px 24px rgba(20,50,30,.4)`, leaf-diamond glyph `#8EC3A5`.
- Bottom card: `Grandmother Cypress` + `THRIVING` badge (`#E2EFE2` / `#28623F`), subtitle `Monterey Cypress · 6 m NE · visited 3 d ago`.
- Tabs: `Map` (active `#1D4634`), `My Grove`, `Journal`, `You` (avatar letter `N`).

### Profile screen fixtures
- Overlay labels: `{{ photoCount }} photos · since 2019` (bottom-right), `Best photo · Oct 2025` (bottom-left, uppercase).
- Section label: `Foliage through the year`
- **12-cell season strip**, in order (Jan→Dec): `#5D9159, #5D9159, #8FB573, #BCD3A8, #BCD3A8, #8FB573, #8FB573, #8FB573, #5D9159, #5D9159, #5D9159, #5D9159` — each `flex:1;height:26px;border-radius:5px`, gap 3px.
- Title: `Grandmother Cypress` (27px Source Serif 4 600) + `THRIVING`.
- Subtitle: `Monterey Cypress · Hesperocyparis macrocarpa` (italic serif 15px `#66735F`).
- Callout: `**How to recognize it:** flat, layered crown; tiny scale-like leaves; lemony scent when crushed.` (`background:#EFF3E3;border:1px solid #DFE6CD;color:#41522F`)
- Primary CTA: ~~`Visit · say hello with a photo`~~ `Visit · add a photo`
  **REWRITTEN — copy audit 2026-08-23** (owner ruling; see `docs/investigations/copy-audit-2026-08-23.md`), R3. The two
  handler tables above name the old label as a trigger and are struck to match.
- Secondary row: `Favorite` · `Care` · `Share` · `Report`
- Stats: `Height` = `18 m` + badge `est.` (`color:#8A6A2A;background:#F1EAD8`); `DBH` = `64 cm` + badge `taped` (`color:#28623F;background:#E2EFE2`).

### Activity feed (profile), top to bottom
| Cond. | Content | Timestamp | Style |
|---|---|---|---|
| `justCared` | `**Care** · {{ careSummary }}` | `just now` | `border:2px solid #2F6B4F`, `czPop .4s ease`, ts `#2F6B4F` bold |
| `justVisited` | `**Visit** · {{ visitNoteShown }}` | `just now` | same highlighted treatment |
| always | `**Visit** · “Fog dripping off the crown”` | `Oct 12` | resting card |
| always | `**Care** · watered, mulched` | `Sep 28` | resting card |

Visit rows use a 38px photo thumb; care rows use a 38px `#E2EFE2` tile with a `#2F6B4F` leaf-diamond glyph.

### Care sheet
- Title `Care log · {{ treeName }}`
- Sub ~~`Toggle what you did. Thirty seconds, then back to your walk.`~~ `Toggle what you did.`
  **REWRITTEN — copy audit 2026-08-23** (owner ruling; see `docs/investigations/copy-audit-2026-08-23.md`), R24.
- Chips: `Watered`, `Mulched`, `Weeded basin`, `Litter cleared`
- Placeholder box: `Photo or note (optional)` (`1px dashed #C9D1BC`)
- CTA `Done`
- ~~Footnote `This joins the tree’s care history, kept separate from health observations.`~~
  **REMOVED — copy audit 2026-08-23** (owner ruling; see `docs/investigations/copy-audit-2026-08-23.md`).

### Share sheet
- Title `Share {{ treeName }}`
- Sub `Anyone can open it, no app or account needed.`
- Preview image label `Best photo · season strip`
- Preview title `{{ treeName }}`, preview URL line `cypress.app/sf/tree/9f3a · {{ photoCount }} photos · 7 years`
- Editable blurb: `“Been visiting this Monterey cypress on 46th Ave. Seven years of photos on its timeline.”` + `· edit before sending`
- CTA `Copy link` → replaced by `Link copied` (`background:#E2EFE2;border:2px solid #2F6B4F`, `czPop .3s ease`)
- Footnote `The link opens the public tree page. Your name appears only if you opted in.`

### Camera fixtures
- Ghost label `ghost overlay 30%`
- Snapped pill `Photo added to the timeline`
- Shot-type chips: `Full tree` (active), `Trunk`, `Leaf close-up`
- Note placeholder `Add a note (optional)`
- Phenology chips: `New growth`, `Cones`, `Storm damage`
- CTA `Log visit`
- Offline line `No signal · saves to outbox, syncs automatically` (dot `#D99A4E`, text `#94A496`)

### Saved fixtures
- `Visit saved` (22px serif)
- `{{ treeName }} · {{ visitCount }} visits today · in the outbox`
- Social proof chip: `Second visitor this week · Mora was here Tuesday`
- Mini route map: 3 muted done-markers (`#AEBFA1` with a white check; the third pops in with `czPop .5s`), 1 pulsing amber marker (`#B4711F`), caption `done trees go quiet`.
- CTAs: `{{ nextLabel }}` / `See it on the tree’s timeline` / `Done for today · back to the map`
- Footer: `{{ storageLine }}`

### Account-ask sheet
- Title `{{ askTitle }}` (`Keep this visit` / `Keep your N visits`)
- Body `They live on this phone right now. An account backs them up and lets them join each tree’s public timeline.`
- Buttons `Continue with Apple` (`#1C2A21`), `Continue with Google` (outline `#D8DECB`), `Use email` (outline)
- ODbL row: `Share my tree records under the open database license. In plain words: anyone may use the data, and your name is included only if you opt in.` + link `Read the short version` (`#2F6B4F`)
- Dismiss `Not now · keep saving to this phone only`

### Grove fixtures
- Header `My Grove` + location pill `Outer Sunset`
- Progress card: `Three trees know you` / `12 of 40 neighborhood species you can recognize`
- Section label `Your trees` → the 3 rows above
- Neighborhood callout: `**Six people know Grandmother Cypress.** You’re one of them. Trees with regulars get watered in dry spells and checked on after storms.` (`#EFF3E3` / `#DFE6CD` / `#41522F`)
- Steward card: badge `SAT`, `**Sunset Tree Stewards**`, `Workday Saturday 9 am · Inner Sunset routes`

### Page chrome (outside the phone)
- Wordmark `Cypress · the ten-second visit` (20px Source Serif 4 600) next to the base64 PNG logo.
- Intro: `Clickable core loop: find a tree on the map, log a visit with a photo, then move on to the next one. Anything tappable glows on hover.`

## 1.8 Named animations

All keyframes are defined in the `<helmet><style>` block (prototype lines 17–22).

| Name | Keyframes | Where used (duration · easing · delay) |
|---|---|---|
| `czFade` | `from{opacity:0;transform:translateY(10px)} to{opacity:1;transform:none}` | **Screen enter** (map/identify/profile/camera/saved/grove root + account scrim): `.32s cubic-bezier(.22,.9,.3,1)`.<br>Coachmarks: `.5s ease .4s both` (map, identify, profile) and `.5s ease .5s both` (camera).<br>Identify candidate cards, staggered: `.3s ease both`, `.08s`, `.16s`, `.24s`.<br>Sheet scrims (care/share): `.25s ease`.<br>Snapped viewfinder gradient: `.4s ease`. |
| `czSheet` | `from{transform:translateY(90px);opacity:0} to{transform:none;opacity:1}` | `.5s cubic-bezier(.22,1.18,.36,1)` — map bottom tree card, care sheet, share sheet, account sheet. |
| `czPinDrop` | `0%{translateY(-14px) scale(.4);opacity:0} 70%{translateY(2px) scale(1.05);opacity:1} 100%{none;opacity:1}` | Map pins: `.45s cubic-bezier(.22,1.18,.36,1)` with `both`, delays `.05s / .12s / .19s / .26s / .33s`. |
| `czPulse` | `0%,100%{box-shadow:0 0 0 0 rgba(180,113,31,.4)} 50%{box-shadow:0 0 0 10px rgba(180,113,31,0)}` | Amber map pin: `2.4s infinite .8s` (composed after its pin-drop). Amber marker on the saved-screen route map: `2.4s infinite`. |
| `czFlash` | `0%{opacity:.9} 100%{opacity:0}` | White full-bleed shutter flash on snap: `.35s ease forwards`, `pointer-events:none`. |
| `czPop` | `0%{scale(.6);opacity:0} 60%{scale(1.08)} 100%{scale(1);opacity:1}` | Highlighted feed rows (care + visit "just now"): `.4s ease`. Snapped confirmation pill: `.4s ease`. `Link copied`: `.3s ease`. Saved-screen success circle: `.45s ease`. 3rd done-marker on the route map: `.5s ease`. |

Hover/active (via `style-hover` / `style-active`):
- Map pins → `transform:scale(1.3)`
- FAB / primary buttons → `background:#2F6B4F` (some also `transform:translateY(-1px)`)
- Cards → `border-color:#2F6B4F` (+ raised shadow `0 10px 30px rgba(47,107,79,.3)` on the map card, `0 8px 26px rgba(47,107,79,.32)` on the identify card)
- Shutter → hover `box-shadow:0 0 0 9px rgba(255,255,255,.5)`, active `transform:translateX(-50%) scale(.92)`
- Restart pill → `border-color:#2F6B4F;color:#1D4634`

## 1.9 Layout quirks worth normalizing on rebuild

- Screen heights are **inconsistent** in the source: `map` 874, `identify` 812, `profile` 874, `camera` 874, `saved` 812, `grove` 812. The device frame is 402×874. Treat 874 (full) as correct and the 812s as an artifact.
- `identify` and `saved` add `padding-top:62px` for the status bar; `map`, `profile`, `camera`, `grove` do not (they own their own top chrome).
- Zoom-based responsive fallback: `zoom:.8 / .73 / .65` at max-widths 460 / 394 / 345 px. Replace with real responsive layout.

---

# PART 2 — COORDINATOR DASHBOARD

**Web-only.** `Cypress Coordinator.dc.html` has **no logic class and no interactive handlers** — every value is hard-coded markup. It is presented inside `ChromeWindow` (`browser-window.jsx`) at **1280 × 840**, URL `cypress.app/org/workday`.

Page chrome outside the browser window (do not ship): wordmark `Cypress · Coordinator`, intro `A concept sketch of the org side: a volunteer coordinator’s Saturday workday, live, without the spreadsheet.`, and a mobile-only hint `Swipe sideways to pan the window` (shown under 767px, where the window becomes horizontally scrollable).

## 2.1 App shell
Root: `background:#F5F6EF`, `color:#1C2A21`, `'Alegreya Sans'`, column flex.

**Top bar** — `padding:13px 28px`, `background:#FBFBF5`, `border-bottom:1px solid #E3E8D9`:
| Element | Copy | Style |
|---|---|---|
| Logo + wordmark | `Cypress` | 18px Source Serif 4 600, 28px PNG mark |
| Org pill | `Sunset Tree Stewards` | `background:#EFF3E3;border:1px solid #DFE6CD;color:#41522F`, dot `#4E8F6A` |
| Nav (active) | `Workday` | `color:#2F6B4F;font-weight:700;border-bottom:2px solid #2F6B4F` |
| Nav | `Assignments`, `Crew`, `Data` | 14px `#66735F` |
| User (right) | `Marisol · coordinator` | avatar `M` on `#7A4F33`, 26px circle |

**Body grid:** `grid-template-columns:1.55fr 1fr`. Left column `padding:24px 26px`; right column `padding:24px 26px`, `border-left:1px solid #E3E8D9`, `background:#FBFBF5`.

## 2.2 Left column

**Header row**
- `Saturday workday · Inner Sunset` — 24px Source Serif 4 600
- LIVE pill: `LIVE · 10:42 AM` — `background:#E2EFE2;color:#28623F;font-weight:800`, dot `#2F6B4F`
- Right, mono 13px `#66735F`: `31 of 54 trees done`

**Progress bar** — 10px tall, radius 6, track `#E9ECDE`; segments `57%` `#2F6B4F` (done) + `9%` `#8FB573` (claimed).
**Legend** — 12px `#66735F`, 9px square swatches: `done` `#2F6B4F` · `claimed, in progress` `#8FB573` · `waiting` `#E9ECDE`.

**Route cards** — white, `border:1px solid #E3E8D9`, radius 16, `box-shadow:0 1px 3px rgba(25,40,28,.05)`, 38px avatar circle, inner bar 7px on `#E9ECDE`:

| Avatar | Title | Sub | Bar (done / claimed) | Count | Status |
|---|---|---|---|---|---|
| `J` `#2F6B4F` | `Jae · Route A` | `Oak St 400–600 block · 18 trees` | 78% / 6% | `14 / 18` | `last check-in 2 min ago` |
| `P` `#4E8F6A` | `Priya · Route B` | `9th Ave 1200–1400 block · 20 trees` | 55% / 10% | `11 / 20` | `last check-in 6 min ago` |
| `T` `#7A4F33` | `Tom · Route C` | `Judah St 800–1000 block · 16 trees` | 38% / 12% | `6 / 16` | `offline 20 min · outbox will sync` |

Counts are mono 15px 600; status lines 11.5px `#66735F`. Note: the bar percentages do **not** match the fractions (78% vs 14/18 = 78% ✓, 55% vs 11/20 = 55% ✓, 38% vs 6/16 = 37.5% ✓) — they are consistent; the extra `#8FB573` sliver is "claimed".

**Live feed** — section label `Live feed` (11px, 800, uppercase, `letter-spacing:.08em`, `#8B9482`). Rows: white, radius 12, `padding:9px 13px`, 13px text; timestamps mono 11px `#8B9482` pushed right.

| Copy (bold segments marked) | Time | Card style |
|---|---|---|
| **Jae** ` checked in the ginkgo at 432 Oak · vitality 4 · watered` | `10:40` | normal |
| **Priya** ` flagged a girdling tie on the plane at 1288 9th · hardware` | `10:36` | normal |
| **Priya** ` reported the gum at 1310 9th as ` **appears dead** ` · review flag opened` | `10:31` | `border:1.5px solid #D9A05B`; `appears dead` in `#8A5A17`; timestamp `#B4711F` 600 |
| **Jae** ` measured DBH 34 cm · taped · tea tree at 466 Oak` | `10:24` | normal |

## 2.3 Right column

**Card 1 — digest preview** (white, radius 16)
- Label `This week · digest preview`
- 3-up stat grid, values mono 22px 600: `128` `check-ins` · `64` `care logs` · `7` `follow-ups` (the `7` is `#B4711F`)
- Note: `A digest goes out Monday at 8 am: what the crew did, what needs review, and the CSV attached.` (12px `#8B9482`)

**Card 2 — Needs your eyes** (white, `border:1.5px solid #D9A05B`, `box-shadow:0 3px 12px rgba(180,113,31,.08)`)
- Label `Needs your eyes` in `#B4711F`
- Bullet dots 9px `#B4711F`:
  - `**Gum at 1310 9th Ave**—reported dead by a trained steward. Confirm before the city sync marks a conflict.`
  - `**Cherry at 620 Oak**—DBH shrank 3 cm since June. Anomaly flag; probably a measuring-height mix-up.`
  - (Both use the no-space em dash from the copy rules.)

**Card 3 — Export the weekend** (white, radius 16)
- Label `Export the weekend`
- Buttons: `Download CSV` (filled `#1D4634`, radius 11) and `GeoJSON` (`border:2px solid #1D4634`, `color:#1D4634`)
- Mono footnote 10.5px `#8B9482`: `keyed on UUID + external_ref · method-tagged · ODbL · unverified rows stamped “not for inventory ingestion” · last SF DPW sync: Thu 02:10, 0 conflicts`

**Card 4 — rationale note** (`background:#EFF3E3;border:1px solid #DFE6CD`, `margin-top:auto`)
- `**Why this screen exists:** the steward loop only needs ten users to be useful. The test is whether the coordinator ever asks for the spreadsheet again.` (12.5px `#41522F`)

## 2.4 iOS-relevant vs web-only

| Element | Verdict |
|---|---|
| Whole coordinator screen (top bar, two-column grid, browser chrome) | **Web-only.** Desktop 1280×840 layout; no mobile counterpart in the bundle. |
| Route cards, live feed, progress + legend | **Web-only as laid out**, but the underlying domain model (workday → routes → per-route progress, live activity events) is shared with the iOS "Sunset Tree Stewards · Workday Saturday 9 am · Inner Sunset routes" grove card. |
| Live-feed event vocabulary (`checked in … · vitality 4 · watered`, `measured DBH 34 cm · taped`, `flagged a girdling tie`, `appears dead · review flag opened`) | **Shared.** These are the server-side rendering of the same events iOS produces via visit / care / measure / report. Reuse the strings and the method tags. |
| Method/ODbL/sync footnote | **Shared copy**, exposed on iOS in the account-ask sheet and share-sheet footnotes. |
| Export CSV / GeoJSON buttons | **Web-only.** |
| `Needs your eyes` review flags | **Web-only UI**, but the flags originate from iOS report/measure actions. |
| `#D9A05B` amber card border, `#B4711F` accents | Shared token family (matches the amber map pin / `est.` badge on iOS). |

---

## UNDETERMINED

- The `Journal` and `You` tabs, `Favorite`, `Report`, search, and filter chips have **no defined behavior** in the prototype — targets unknown.
- The identify screen's cards 2–4 have no tap handler; whether they should select a different species is not specified.
- `visitCount: 3` starts at 3 with no explanation of what the other 3 visits are; "N visits today" is a per-tree-per-day counter in copy but a global counter in code.
- Nothing in the prototype defines the `Journal`, memorial, measure, outbox, or public-web screens — those live in `Cypress Screens.dc.html` (19 screens), not in the state machine.
- Coordinator has no hover/active/loading states, no route detail view, and no defined behavior for nav items, export buttons, or review flags.
- The "second visitor this week · Mora was here Tuesday" social proof is static; the rule that produces it is unspecified.
