# Cypress — Screen Spec (SwiftUI-oriented)

Reverse-engineered from `_unzipped/design_handoff_cypress/Cypress Screens.dc.html` (the design-tool
export) and cross-checked against `_unzipped/design_handoff_cypress/README.md` and
`_unzipped/design_handoff_cypress/ios-frame.jsx`.

**Ground rules for this document**

- Every hex, px value, and copy string below is transcribed from the HTML. Nothing is invented.
- Where the source does not specify something (a tap target, a transition, an empty state), it is
  marked **NOT SPECIFIED**.
- Copy strings are verbatim, including the typographic characters the file actually uses:
  `·` (U+00B7 middle dot), `’` (U+2019 right single quote), `“ ”` (U+201C/201D), `—` (em dash, no
  surrounding spaces), `–` (en dash in ranges), `×` (U+00D7), `Ō`/`ō` macrons, `✓`, `⌫`.
- The HTML is a *static* spec: every "selected" chip, "pressed" button, and "checked" toggle is
  drawn in one fixed state. Where a variant is implied but not drawn, it is called out.
- All imagery is a CSS gradient placeholder. Gradients are transcribed exactly so you can either
  reproduce them as SwiftUI `Gradient`s for the placeholder build or swap in real photography.

---

## 1. Design tokens

### 1.1 Palette — as declared on the spec's own swatch board

The spec page opens with a swatch panel labeled `Palette · from the tree itself`. These are the six
named brand colors, verbatim from the file (name + hex + swatch text color):

| Name | Hex | Swatch text color | Role |
|---|---|---|---|
| Cypress Deep | `#1D4634` | `#DFE8D6` | primary buttons, active nav, cluster badges, dark header |
| Canopy | `#2F6B4F` | `#E8F0E4` | links, selection borders, pins, selected chips |
| New Growth | `#4E8F6A` | `#10281C` | secondary accents, avatars, dark-mode CTA fill on 04 |
| Bark | `#7A4F33` | `#F2E6DA` | third-series charts, avatar accent |
| Fog | `#F5F6EF` | `#3C4A3E` | mobile screen background (has `border:1px solid #E0DDCB` on the swatch) |
| Signal Amber | `#B4711F` | `#FDF3E3` | reserved solely for "this tree needs something" |

Caption under the swatches (verbatim):
> One amber, reserved for "this tree needs something." Everything else is green, bark, and fog.

### 1.2 Full color token table (confirmed against the CSS in the file)

**Surfaces**

| Token | Hex | Where used |
|---|---|---|
| `page.parchment` | `#EBE8DC` | `body` background of the spec page itself |
| `surface.screen` | `#F5F6EF` | mobile screen background (02, 03, 05–09, 11–14, 16–19, W1) |
| `surface.card` | `#FFFFFF` | cards, stat cards, list rows, segmented controls |
| `surface.sheet` | `#FDFDF8` | bottom sheets (09, 10, 15) |
| `surface.warmPanel` | `#F7F5EC` | spec-page panels (palette / type panels) |
| `surface.web` | `#FBFBF5` | W1 web header + fact column |
| `surface.mapPaper` | `#E9E5D4` | map canvas ground (01, 15) |
| `surface.mapGrid` | `#F7F4E6` | map street grid stripes (01, 15) |
| `surface.mapStreetBand` | `#FAF7EC` | named street bands on 01 |
| `surface.routeMap` | `#E4E9D3` | mini route map on 18 (border `#DBE0CB`, grid `#F4F1E2`) |
| `surface.emptyThumb` | `#FAFBF4` | cold-start empty photo well (14) |
| `surface.skeleton` | `#E3E8D9` | skeleton blocks behind sheets (09, 10) |

**Borders and hairlines**

| Token | Hex | Where used |
|---|---|---|
| `border.cool` | `#E3E8D9` | default card / chip / row border on every mobile screen |
| `border.warm` | `#DDD9C9` | spec-page panel border |
| `border.hairline` | `#D8D4C4` | spec-page header rule and footer rule |
| `border.dashed` | `#C9D1BC` | optional-field dashed wells (05, 06, 09) |
| `border.dashedStrong` | `#C4CEB4` | empty photo well (14), `2px dashed` |
| `border.sheetGrabber` | `#DDE2D2` | 40×5 sheet grabber pill |
| `border.web.row` | `#E9ECDE` | W1 fact-row separators |
| `border.calloutGreen` | `#DFE6CD` | green callout border |
| `border.calloutGradient` | `#D9E3C8` | "In July" / "New species!" gradient callout border |
| `border.amberSoft` | `#EBD3A8` | amber pill borders |
| `border.amberMid` | `#D9A05B` | attention card border (`1.5px`) |
| `border.amberStrong` | `#E0B070` | 311 hazard panel border (`1.5px`) |
| `border.memorial` | `#C4C8B8` | memorial banner border (`1.5px`) |
| `border.account` | `#D8DECB` | account sheet secondary buttons (`1.5px`) |
| `border.shareCard` | `#E0DDC9` | share preview card |
| `border.pinRing` | `rgba(29,70,52,.14)` | gradient thumbnail hairline |
| `border.glass` | `rgba(29,70,52,.1)` / `rgba(29,70,52,.12)` / `rgba(29,70,52,.08)` | search bar / filter chips / bottom bar top edge |

**Text**

| Token | Hex | Notes |
|---|---|---|
| `text.ink` | `#1C2A21` | primary text, headings |
| `text.body` | `#3C4A3E` | secondary body, unselected chip labels |
| `text.muted` | `#66735F` | captions, Latin names, sublabels |
| `text.faint` | `#8B9482` | micro-labels, timestamps, mono meta |
| `text.faintAlt` | `#77836F` | footnote lines under screens |
| `text.onDark` | `#FFFFFF` | on Cypress Deep / Canopy fills |
| `text.onPhoto` | `#EAF2E6` (03), `#F0F5EC` (07), `#EFF1EA` (19), `#EFF5EA` (W1) | text over hero gradients |
| `text.mapLabel` | `#98A388` street, `#7A9C64` park, `#5F8C84` ocean | 01 map labels |

**Semantic / status**

| Token | Fill | Border | Text | Where |
|---|---|---|---|---|
| Thriving badge (light) | `#E2EFE2` | — | `#28623F` | 01, 03 `THRIVING` |
| Thriving badge (dark) | `#1F3A2C` | — | `#8EC3A5` | D1, D2 |
| `taped` method badge | `#E2EFE2` | — | `#28623F` | 03, 11, W1 |
| `est.` / `estimated` badge | `#F1EAD8` | — | `#8A6A2A` | 03, 11, W1 |
| `city record` badge | `#EAF0E2` | — | `#41522F` | 14 |
| `PLANTED 2024` badge | `#EAF0E2` | — | `#41522F` | 14 |
| `REMOVED` badge | `#E4E6DC` | — | `#5C6555` | 19 |
| Green callout | `#EFF3E3` | `#DFE6CD` | `#41522F` | 03, 14, 16, 19 |
| Gradient callout | `linear-gradient(120deg,#EAF2E6,#F6F2DF)` | `#D9E3C8` | `#1C2A21` | 07, 08 |
| Amber pill / banner | `#F8EFDF` | `#EBD3A8` | `#8A5A17` | 02, 06, 17 |
| Amber selected chip | `#F8EFDF` | `#D9A05B` (1.5px) | `#8A5A17` | 06 |
| Amber attention card | `#FFFFFF` | `#D9A05B` (1.5px) | — | 12, 17 |
| 311 hazard panel | `#F8EFDF` | `#E0B070` (1.5px) | body `#6B5122` | 06 |
| 311 CTA button | `#A35F12` | — | `#FFFFFF` | 06 |
| Memorial banner | `#EDEEE6` | `#C4C8B8` (1.5px) | `#4A5344` | 19 |
| GPS dot | `#3577C9` + `0 0 0 8px rgba(53,119,201,.18)` halo | `3px solid #fff` | — | 01, 02 |

**Foliage strip greens** (fixed 3-step ramp, used identically everywhere)

| Level | Light | Dark |
|---|---|---|
| Densest | `#5D9159` | `#3E6B44` |
| Mid | `#8FB573` | `#587D50` |
| Sparsest | `#BCD3A8` | `#6E8A5F` |

**Vitality reference-swatch gradients** (05 light / D3 dark), all `linear-gradient(140deg, …)`:

| Level | Light | Dark |
|---|---|---|
| 1 · Severe decline | `#C0A37C → #8A6A4A` | `#8A7355 → #5E4832` |
| 2 · Poor | `#C9B06A → #A3813F` | `#8F7C48 → #6E572B` |
| 3 · Fair | `#B3BD7A → #8A9A55` | `#7E8752 → #5C6838` |
| 4 · Good | `#7FAE72 → #5D9159` | `#5B8250 → #3E6B44` |
| 5 · Thriving | `#57925E → #2C6B45` | `#3F7048 → #245239` |

**Dark-mode tokens** (D1–D3, 04)

| Token | Hex | Notes |
|---|---|---|
| `dark.bg.map` | `#141E16` | D1 map ground |
| `dark.bg.screen` | `#0E1712` | D2, D3 |
| `dark.bg.camera` | `#10160F` | 04 shell; camera tray `#151D15` |
| `dark.surface.card` | `#18251D` | D1 tree card, D2/D3 cards |
| `dark.surface.cardAlt` | `#1B241B` | 04 note field & unselected chips |
| `dark.surface.callout` | `#1A241A` | D2 recognize-it note |
| `dark.surface.thumb` | `#1F2E22` | D2 activity thumb base |
| `dark.border` | `#27352B` | D2/D3 card border |
| `dark.border.alt` | `#2B3A2C` | D1 borders |
| `dark.border.camera` | `#2A362B` | 04 |
| `dark.text.primary` | `#E4EBE2` | |
| `dark.text.strong` | `#D6E0CE` | bolded row text |
| `dark.text.secondary` | `#AEBBAB` | unselected chip labels |
| `dark.text.muted` | `#94A496` | sublabels |
| `dark.text.faint` | `#5F6F61` | micro-labels, inactive tabs |
| `dark.accent.mint` | `#8EC3A5` | primary CTA fill, selection, active tab |
| `dark.accent.pin` | `#6FAE8C` | map pins |
| `dark.accent.amber` | `#D99A4E` | amber pin, `est.` badge text |
| `dark.accent.amberBg` | `#2E271A` | `est.` badge fill |
| `dark.accent.gps` | `#6FA8E8` + `0 0 0 8px rgba(111,168,232,.16)` | |
| `dark.map.grid` | `#1C2A1F` | |
| `dark.map.ocean` | `linear-gradient(90deg,#14282B,#183034)` | |
| `dark.map.beach` | `#2B3226` | |
| `dark.map.park` | `#1B3123`, inset ring `#274531` | |
| `dark.map.street` | `#232F24`, ring `#2B3A2C` | |
| `dark.map.label` | `#5C6B57` street, `#557A50` park, `#4E7A74` ocean | |
| `dark.pin.ring` | `#0E1712` (3px) | pins ring against ground, not white |

### 1.3 Type ramp

Three families, loaded from Google Fonts with these axes:

```
Source Serif 4 : ital,opsz,wght @ 0,8..60,400..700 ; 1,8..60,400..600
Alegreya Sans  : ital,wght @ 0,400;0,500;0,700;0,800 ; 1,400
Spline Sans Mono: wght @ 400;600
```

`body` default: `'Alegreya Sans', system-ui, sans-serif`, color `#1C2A21`, `-webkit-font-smoothing:antialiased`.
Serif fallback stack in the file is always `'Source Serif 4', Georgia, serif`.

The spec page states the three roles verbatim:

- `Display · Source Serif 4—the field guide voice` → sample `Ginkgo biloba, planted 1987` (26px/600)
- `Body · Alegreya Sans—the walking voice` → sample `Watered, mulched. Thirty seconds, next tree.` (16px)
- `Data · Spline Sans Mono—the record voice` → sample `DBH 64 cm · taped · SF #114-88` (13px)
  (the sample now reads `#114-88` on screen — see the note under screen 03's stat grid)

Closing note (verbatim):
> Serif for tree names and story. Sans for everything you do. Mono for anything that enters the record—numbers always carry their method.

| Style name | Family | Size | Weight | Extra | Seen on |
|---|---|---|---|---|---|
| `web.h1` | Serif | 42px | 600 | line-height 1.05 | W1 tree name |
| `spec.h2` | Serif | 30px | 600 | line-height 1.15 | spec section headings |
| `screen.title.grove` | Serif | 26px | 600 | — | 08 "My Grove" |
| `tree.name.hero` | Serif | 27px | 600 | line-height 1.05 | 03, D2, 19 |
| `species.hero` | Serif | 25px | 600 | line-height 1.1 | 07 |
| `tree.name.coldstart` | Serif | 25px | 600 | — | 14 |
| `screen.title` | Serif | 22px | 600 | — | 02, 05, 06, 11, 12, 13, 14, 16, 17, D3 |
| `success.title` | Serif | 22px | 600 | — | 18 |
| `sheet.title` | Serif | 20px | 600 | — | 09, 10 |
| `hazard.title` | Serif | 20px | 600 | — | 06 |
| `account.title` | Serif | 21px | 600 | — | 15 |
| `caption.title` | Serif | 16.5px | 600 | — | every figcaption `<b>` |
| `card.title.serif` | Serif | 19px | 600 | — | 02 top candidate, 08 progress |
| `list.name.serif` | Serif | 17.5px | 600 | — | 01 card, 02 rows, D1 card |
| `share.name` | Serif | 17px | 600 | — | 10 preview |
| `web.wordmark` | Serif | 19px | 600 | — | W1 header |
| `latin.name` | Serif *italic* | 18 / 15 / 14.5 / 14 / 13.5 / 13px | 400 | color `#66735F` | W1 / 03,19 / 14 / 07 / 02-top / 02-rows |
| `body.16` | Sans | 16px | 700 | — | primary button labels |
| `body.15.5` | Sans | 15.5px | 700 | — | 01 FAB |
| `body.15` | Sans | 15px | 400/700 | line-height 1.55 | spec intro paragraphs; sheet buttons; W1 fact rows |
| `body.14.5` | Sans | 14.5px | 400/600/700 | — | search placeholder, chart card titles, care chips |
| `body.14` | Sans | 14px | 700 | — | list row titles |
| `body.13.5` | Sans | 13.5px | 400 | line-height 1.45–1.55 | callouts, activity rows, figcaptions |
| `body.13` | Sans | 13px | 400/700 | — | chips, sublabels |
| `body.12.5` | Sans | 12.5px | 400 | — | chip labels, secondary text |
| `body.12` | Sans | 12px | 400/600/700 | — | footnotes, action-row labels |
| `micro.label` | Sans | 11px | 800 | `letter-spacing:.08em`, `uppercase`, `#8B9482` | section headers inside screens |
| `micro.label.10` | Sans | 10px | 700 | `letter-spacing:.08em`, `uppercase`, `#8B9482` | stat-card labels |
| `badge` | Sans | 11px | 700 | `letter-spacing:.02em` | `THRIVING`, `REMOVED`, `PLANTED 2024` |
| `mono.13` | Mono | 13px | 400 | — | type-sample data line |
| `mono.12` | Mono | 12px | 400 | — | distances, percentages |
| `mono.11` | Mono | 11px | 400/600/700 | — | timestamps, states |
| `mono.10.5` | Mono | 10.5px | 400 | — | photo-count pill, public URL |
| `mono.10` | Mono | 10px | 400 | — | chart axis labels |
| `mono.9.5` | Mono | 9.5px | 600 | `letter-spacing:.14em`, uppercase | "Foliage through the year" |
| `mono.9` | Mono | 9px | 600 | `letter-spacing:.16–.18em` | map street labels |
| `mono.readout` | Mono | 56px | 600 | `letter-spacing:-.02em` | 16 measurement readout |
| `mono.keypad` | Mono | 19px | 600 | — | 16 numeric keypad |
| `mono.stat` | Mono | 14.5px | 600 | — | stat card values |
| `mono.statBig` | Mono | 17px | 600 | — | 07 counts |
| `spec.eyebrow` | Mono | 11px | 400 | `letter-spacing:.14em`, uppercase, `#2F6B4F` | section eyebrows |
| `spec.backToTop` | Mono | 10px | 400 | `letter-spacing:.12em`, uppercase, `#8B9482` | "↑ Back to top" |

### 1.4 Radii

| Token | Value | Applies to |
|---|---|---|
| `radius.pill` | `999px` | chips, filter chips, search bar, FAB, status pills |
| `radius.sheet` | `26px 26px 0 0` | bottom sheets (09, 10, 15) |
| `radius.device` | `48px` | iOS frame screen corner (from `ios-frame.jsx`) |
| `radius.card.lg` | `18px` | 01 tree card, 02 candidate cards, 10 share preview, 14 photo well, 18 route map |
| `radius.card.md` | `16px` | 07 recognize card, 11/13 chart cards, 09/10 skeleton hero |
| `radius.card.sm` | `14px` | primary buttons, activity rows, list rows, callouts, stat panels |
| `radius.control` | `12px` | segmented controls, stat cards, secondary action buttons, dashed wells |
| `radius.thumb.lg` | `16px` | 02 top candidate thumb (76px), 10 share thumb (72px) |
| `radius.thumb.md` | `14px` | 01 card thumb (58px), 02 row thumb (60px), 08 species tiles |
| `radius.thumb.sm` | `11px` (07, 44px) / `10px` (activity 38px, almanac 34px) / `8px` (W1 26px, 12 grabber) | |
| `radius.badge` | `6px` | `THRIVING`, `REMOVED`, `PLANTED 2024` |
| `radius.methodBadge` | `4px` | `taped` / `est.` inline badges |
| `radius.foliageCell` | `5px` | season-strip cells |
| `radius.web.button` | `12px` / `10px` | W1 buttons / W1 "Sign in" |
| `radius.leafGlyph` | `50% 0` + `rotate(45deg)` | the leaf-diamond mark |

### 1.5 Shadows

| Token | Value | Applies to |
|---|---|---|
| `shadow.rest` | `0 1px 3px rgba(25,40,28,.05)` | resting card / list row |
| `shadow.restSoft` | `0 1px 4px rgba(25,40,28,.08)` | circular back button |
| `shadow.selected` | `0 6px 20px rgba(47,107,79,.16)` | selected candidate card (02) |
| `shadow.selectedSm` | `0 4px 12px rgba(47,107,79,.16)` | selected vitality row (05) |
| `shadow.primary` | `0 4px 14px rgba(20,50,30,.28)` | primary CTA button |
| `shadow.fab` | `0 8px 24px rgba(20,50,30,.4)` | 01 floating "What tree is this?" |
| `shadow.chipActive` | `0 2px 8px rgba(20,50,30,.25)` | selected filter chip (01) |
| `shadow.searchBar` | `0 4px 16px rgba(20,40,26,.1)` | 01 search bar |
| `shadow.bottomCard` | `0 10px 30px rgba(20,40,26,.16)` | 01 bottom tree card |
| `shadow.sheet` | `0 -12px 40px rgba(10,20,14,.32)` | bottom sheets |
| `shadow.shareCard` | `0 3px 12px rgba(25,40,28,.09)` | 10 preview card |
| `shadow.amberCard` | `0 3px 12px rgba(180,113,31,.1)` | 12, 17 attention cards |
| `shadow.hazard` | `0 4px 14px rgba(163,95,18,.3)` | 06 "Call 311 now" |
| `shadow.pin` | `0 2px 6px rgba(20,40,26,.35)` | map pins |
| `shadow.pinMuted` | `0 2px 6px rgba(20,40,26,.2)` / `.25` | removed pin / dashed community pin |
| `shadow.cluster` | `0 2px 8px rgba(20,40,26,.35)` | cluster count badges |
| `shadow.heroButton` | `0 2px 8px rgba(16,32,22,.25)` | back button over a hero photo |
| `shadow.toggleKnob` | `0 1px 3px rgba(0,0,0,.2)` | 17 switch knob |
| `shadow.dark.*` | `0 2px 6px rgba(0,0,0,.5)`, `0 2px 8px rgba(0,0,0,.5)`, `0 4px 16px rgba(0,0,0,.4)`, `0 10px 30px rgba(0,0,0,.45)`, `0 8px 24px rgba(0,0,0,.5)` | dark-mode equivalents |

Dark-mode cards (D2, D3) carry **no** shadow — they are separated by `#27352B` borders only.

### 1.6 Spacing

Mobile screens use one horizontal rhythm with two variants:

- **16px** gutter — content that lives inside cards (`padding:… 16px`, `margin:… 16px`).
- **18px** gutter — content headed by an uppercase micro-label (`padding:… 18px`). Screens 05, 06,
  11, 12, 13, 16, 17 mix both: the label blocks get 18px, the card grids get 16px.
- **14px** — 01 bottom tree card (`left:14px;right:14px`).
- **20px** — 15 account sheet.

Vertical rhythm inside a screen: header `padding:10px 18px 4px` (or `6px` on 02), then repeated
`padding:14px 18px 0` label sections; card stacks use `gap:8px` (rows), `gap:7px` (chips / dense
rows), `gap:6px` (vitality rows), `gap:10px` (02 candidate list), `gap:9px` (08 grid, 09 chips).

Bottom padding before the home indicator: `30px` (bottom bar), `36px` (footnote line), `40px`
(02 CTA), `44px` (sheets), `8px` + `36px` (sticky CTA over a footnote).

Spec-page rhythm (not app UI): page padding `56px 56px 120px`, max width `1560px`; sections
`margin-top:88px`; screen grid `display:flex;flex-wrap:wrap;gap:56px;align-items:flex-start`; each
figure `width:402px` with `gap:16px` between device and caption.

### 1.7 Device frame

From `ios-frame.jsx` and the screen markup:

- Screen canvas: **402 × 874** logical points, corner radius **48px**.
- Status-bar inset: **62px** (`paddingTop: 62`). Screens declare either `height:874px` with their
  own absolute layout, or `height:812px; padding-top:62px` (812 + 62 = 874).
- Home-indicator inset: bottom paddings of 30–44px absorb it; the frame itself adds
  `paddingBottom: 10`.
- `dark={true}` prop switches the bezel for screens 04, D1, D2, D3.
- W1 uses `ChromeWindow` at **1180 × 780** with URL `cypress.app/sf/tree/9f3a-monterey-cypress`.

**Do not ship the frames** — they are presentation scaffolding. In SwiftUI use real safe areas.

---

## 2. Reusable component catalog

Build these once. Each is used on 2+ screens.

### C1 · `ScreenHeader`
Back circle + serif title + optional trailing pill.
- Container: `HStack(spacing: 12)`, padding `10px 18px 4px` (02 uses `10px 18px 6px`).
- Back circle: 44×44, `borderRadius 50%`, fill `#FFFFFF`, border `1px #E3E8D9`,
  shadow `0 1px 4px rgba(25,40,28,.08)`. Glyph: SVG chevron-left `M8 2L2 8l6 6`, stroke `#3C4A3E`,
  width 2.2, round caps/joins, 10×16 in a 10×16 viewBox.
- Title: Source Serif 4, 22px, 600, `#1C2A21`.
- Trailing pill (optional): fill `#FFFFFF`, border `1px #E3E8D9`, radius 999px, padding `5px 12px`,
  12px, `#66735F`. Dark: fill `#18251D`, border `#27352B`, text `#94A496`.
- Dark variant: back circle fill `#18251D`, border `1px #27352B`, chevron stroke `#AEBBAB`, no shadow.

### C2 · `HeroPhotoHeader`
- Height: **224px** (03, D2), **190px** (07), **200px** (19). `flex:none`, `position:relative`.
- Background: layered `radial-gradient(…)` stack over a `linear-gradient(180deg, …)`; see the
  per-screen gradients below.
- Scrim: `position:absolute; inset:0; linear-gradient(180deg, rgba(16,32,22,0) 48%, rgba(16,32,22,.5) 100%)`
  (03) / `… 42% … .56` (07) / `rgba(30,34,28,…) 46% / .5` (19) / `rgba(8,14,10,…) 48% / .62` (D2).
- Back button: 44×44 circle at `left:16px; top:66px`, fill `rgba(255,255,255,.92)`,
  shadow `0 2px 8px rgba(16,32,22,.25)`. Dark: fill `rgba(24,37,29,.92)`, border `1px #2B3A2C`.
- Bottom-right meta pill: mono 10.5px, `#EAF2E6` on `rgba(16,32,22,.45)`, radius 999px,
  padding `4px 11px`, at `right:14px; bottom:12px`.
- Bottom-left eyebrow: 11px/700, `letter-spacing:.06em`, uppercase, `#EAF2E6`, at `left:16px; bottom:12px`.

### C3 · `FoliageStrip` (12-cell season strip)
- `HStack(spacing: 3)`, each cell `flex:1`, height **26px**, radius **5px**.
- Colors from the 3-step ramp (§1.2). Canonical Grandmother Cypress sequence, J→D:
  `5D9159, 5D9159, 8FB573, BCD3A8, BCD3A8, 8FB573, 8FB573, 8FB573, 5D9159, 5D9159, 5D9159, 5D9159`.
- Optional month row underneath: `gap:3px`, `margin-top:3px`, each `flex:1`, centered,
  8.5px/600, `#8B9482`, letters `J F M A M J J A S O N D`.
- Optional mono eyebrow above: `Foliage through the year` — Spline Sans Mono 9.5px/600,
  `letter-spacing:.14em`, uppercase, `#8B9482` (dark `#5F6F61`), `margin-bottom:6px`.
- **Share-card variant (10):** 12 squares, 11×11, radius 3px, `gap:2.5px`.
- **Web variant (W1):** height 30px, radius 5px, `gap:4px`, each cell
  `border:1px solid rgba(255,255,255,.25)`, container `max-width:420px`.
- **Dark variant (D2):** ramp `#3E6B44 / #587D50 / #6E8A5F`, no month row.

### C4 · `Chip` (pill)
| Variant | Fill | Border | Text | Weight | Padding | Font |
|---|---|---|---|---|---|---|
| Filter, selected (01) | `#1D4634` | — | `#fff` | 700 | `7px 15px` | 13px |
| Filter, idle (01) | `rgba(255,255,255,.92)` | `1px rgba(29,70,52,.12)` | `#3C4A3E` | 400 | `7px 15px` | 13px |
| Meta chip (02, 07) | `#fff` | `1px #E3E8D9` | `#3C4A3E` | 400 | `6px 13px` | 12.5px |
| Structure flag, idle (05) | `#fff` | `1px #E3E8D9` | `#3C4A3E` | 400 | `11px 16px` | 13px |
| Structure flag, on (05) | `#2F6B4F` | — | `#fff` | 700 | `11px 16px` | 13px |
| Hazard, on (06) | `#F8EFDF` | `1.5px #D9A05B` | `#8A5A17` | 700 | `11px 16px` | 13px |
| Hazard, off (06) | `#fff` | `1px #EBD3A8` | `#8A5A17` | 400 | `11px 16px` | 13px |
| Care toggle, on (09) | `#2F6B4F` | — | `#fff` | 700 | `12px 18px` | 14.5px (label + ` ✓`) |
| Care toggle, off (09) | `#fff` | `1px #E3E8D9` | `#3C4A3E` | 400 | `12px 18px` | 14.5px |
| Phenology, on (04) | `#2F6B4F` | — | `#fff` | 700 | `7px 15px` | 13px |
| Phenology, off (04) | `#1B241B` | `1px #2A362B` | `#AEBBAB` | 400 | `7px 15px` | 13px |
| Shot type, on (04) | `rgba(233,240,226,.94)` | — | `#22301F` | 700 | `6px 14px` | 12.5px |
| Shot type, off (04) | `rgba(6,10,7,.55)` | — | `#CFDAC6` | 400 | `6px 14px` | 12.5px |
| Dark flag, on (D3) | `#8EC3A5` | — | `#0E1712` | 800 | `11px 16px` | 13px |
| Dark flag, off (D3) | `#18251D` | `1px #27352B` | `#AEBBAB` | 400 | `11px 16px` | 13px |
| Sanity-check pill (16) | `#EFF3E3` | `1px #DFE6CD` | `#41522F` | 400 | `6px 14px` | 12.5px |
| Method legend (11) | `#fff` | `1px #E3E8D9` | `#3C4A3E` | 400 | `6px 13px` | 12px, `gap:7px` w/ dot |

All pills: `border-radius: 999px`.

### C5 · `SegmentedControl`
- Container: `HStack(spacing:0)`, `border:1px solid #E3E8D9`, `border-radius:12px`,
  `overflow:hidden`, background `#FFFFFF`.
- Segment: `flex:1`, centered, `padding:10px 2px` (05) or `11px 2px` (16), font 13px (05) / 14px (16).
- Divider: `border-left:1px solid #E3E8D9` on every segment except the first.
- Selected: background `#2F6B4F`, color `#fff`, `font-weight:700`.
- Idle: color `#3C4A3E`.
- Dark (D3): container border/divider `#27352B`, bg `#18251D`, selected `#8EC3A5` on text `#0E1712`
  at weight 800, idle text `#AEBBAB`.
- Used by: 05 Status, 05 Foliage, 16 What-are-you-measuring, 16 Method, D3 Status.

### C6 · `PrimaryButton`
- Fill `#1D4634`, text `#FFFFFF`, weight 700, size 16px, `border-radius:14px`, `padding:15px`,
  full width, centered, shadow `0 4px 14px rgba(20,50,30,.28)`.
- Smaller variants: 12 "Walk the nine" `padding:13px`, 14.5px, radius 12px, **no shadow**;
  18 "Next nearest…" `padding:16px`; W1 `padding:13px`, 14.5px, radius 12px, no shadow.
- Dark variant (D2, D3): fill `#8EC3A5`, text `#0E1712`, weight 800, no shadow.
- 04 variant: fill `#4E8F6A`, text `#0E1A12`, weight 800, no shadow.

### C7 · `SecondaryOutlineButton`
- `border:2px solid #1D4634`, text `#1D4634`, weight 700, `border-radius:14px`, centered.
- Sizes seen: 02 `padding:14px`, 15px · 06 `padding:13px`, 14.5px · 18 `padding:14px`, 15px ·
  W1 `padding:11px`, 14.5px, radius 12px.

### C8 · `QuadActionRow` (Favorite / Care / Share / Report)
- `HStack(spacing: 8)`, `padding:10px 16px`.
- Each: `flex:1`, centered, `border:1px solid #E3E8D9`, fill `#fff`, `border-radius:12px`,
  `padding:9px 2px`, 12px/600, `#3C4A3E`.
- Dark (D2): border `#27352B`, fill `#18251D`, text `#AEBBAB`.
- **NOT SPECIFIED:** icons for these four actions — the spec shows text only.

### C9 · `ActivityRow`
- Card: fill `#fff`, `border:1px solid #E3E8D9`, `border-radius:14px`, `padding:11px 13px`,
  `HStack(spacing:11)`, `align-items:center`, shadow `0 1px 3px rgba(25,40,28,.05)`.
- Leading thumb: 38×38, `border-radius:10px`, either a photo gradient or a tinted tile
  (`#E2EFE2` with the 12×12 `#2F6B4F` leaf glyph for Care; `#EDEEE6` with mono 10px `SYNC` in
  `#5C6555` for the city-sync row on 19).
- Body: 13.5px, `<b>` label + ` · ` + detail.
- Trailing timestamp: Spline Sans Mono 11px, `#8B9482`, `white-space:nowrap`, pushed with
  `margin-left:auto`.
- Dark (D2): fill `#18251D`, border `#27352B`, body `#D6E0CE`, timestamp `#5F6F61`, no shadow.

### C10 · `IconTextRow` (almanac / moments)
- Card: fill `#fff`, `border:1px solid #E3E8D9`, `border-radius:14px`, `padding:12px 14px`,
  `HStack(spacing:12)`, `align-items:flex-start`, **no shadow**.
- Leading tile: 34×34, `border-radius:10px`, `radial-gradient(circle at 45% 42%, <accent> 0%, transparent 55%)`
  over a pale base.
- Title: 14px/700. Subtitle: 12.5px, `#66735F`, `margin-top:1px`, block.
- Used by: 12 "This season" ×3, 13 "Moments" ×3.

### C11 · `StatCard`
- Fill `#fff`, `border:1px solid #E3E8D9`, `border-radius:12px`, `padding:9px 12px`.
- Label: 10px, uppercase, `letter-spacing:.08em`, `#8B9482`, weight 700.
- Value: Spline Sans Mono 14.5px/600, `margin-top:1px`, `#1C2A21`.
- Optional inline method badge (C12) after the value.
- Grid: `display:grid; grid-template-columns:1fr 1fr; gap:8px; padding:10px 16px 30px`.
- Large variant (07): `padding:10px 13px`, value mono 17px/600, in a 2-up `HStack(spacing:8)`.
- Dark (D2): fill `#18251D`, border `#27352B`, label `#5F6F61`, value `#E4EBE2`.

### C12 · `MethodBadge` (inline)
- 10.5px/600, `border-radius:4px`, `padding:1px 5px`.
- `taped` → `#28623F` on `#E2EFE2`. `est.` → `#8A6A2A` on `#F1EAD8`.
- `city record` → `#41522F` on `#EAF0E2`.
- Growth-log variant (11): 11px/600, `padding:1.5px 7px`; labels `taped` / `estimated`.
- Web variant (W1): 11px, `padding:1.5px 6px`.
- Dark (D2): `taped` → `#8EC3A5` on `#1F3A2C`; `est.` → `#D9A05B` on `#2E271A`.

### C13 · `StatusBadge`
- 11px/700, `letter-spacing:.02em`, `border-radius:6px`.
- `THRIVING` — `#28623F` on `#E2EFE2`; `padding:2px 8px` (01, D1 card) or `3px 9px` (03, D2).
- `PLANTED 2024` — `#41522F` on `#EAF0E2`, `padding:3px 9px`.
- `REMOVED` — `#5C6555` on `#E4E6DC`, `padding:3px 9px` (no letter-spacing declared).
- Dark `THRIVING` — `#8EC3A5` on `#1F3A2C`.

### C14 · `Callout`
- **Green (recognize-it / lineage):** fill `#EFF3E3`, `border:1px solid #DFE6CD`,
  `border-radius:12px` (14px on 19), `padding:11px 14px` (13px 15px on 19), 13.5px,
  color `#41522F`, `line-height:1.45` (1.5 on 19). Leads with a `<b>` lead-in.
- **Gradient (seasonal / celebration):** `linear-gradient(120deg,#EAF2E6,#F6F2DF)`,
  `border:1px solid #D9E3C8`, `border-radius:14px`, `padding:12px 15px`, 13.5px, `line-height:1.5`.
- **Memorial:** fill `#EDEEE6`, `border:1.5px solid #C4C8B8`, `border-radius:14px`,
  `padding:13px 15px`, 13.5px, `#4A5344`, `line-height:1.5`.
- **Dashed disclosure (06):** `border:1px dashed #C9D1BC`, `border-radius:12px`,
  `padding:13px 15px`, 12.5px, `#66735F`, `line-height:1.5`.
- **Dark (D2):** fill `#1A241A`, border `1px #27352B`, body `#B9C7B2`, lead-in `#D6E0CE`.

### C15 · `OptionalWell` (dashed placeholder)
- `border:1px dashed #C9D1BC`, `border-radius:12px`, `padding:12px 14px` (05) / `13px 15px` (09),
  13.5px, `#8B9482`.
- Copy seen: `Add photos · notes (optional)` (05), `Photo or note (optional)` (09).

### C16 · `BottomTabBar`
- `HStack`, background `rgba(250,250,244,.95)`, `backdrop-filter:blur(10px)`,
  `border-top:1px solid rgba(29,70,52,.08)`, `padding:12px 10px 30px`, pinned to bottom.
- Four equal tabs. Active `#1D4634`, label 11px/**800**; inactive `#8B9482`, label 11px/600.
- Icons (all hand-drawn, no icon font):
  - **Map** — 22×22 rounded square, `border:2px solid <tint>`, `border-radius:6px`, with a centered
    6×6 dot of the same tint. `margin:0 auto 3px`.
  - **My Grove** — 16×16 leaf diamond: `border-radius:50% 0`, `transform:rotate(45deg)`, filled with
    the tint. `margin:3px auto 6px`.
  - **Journal** — 18×20 book: `border:2px solid <tint>`, `border-radius:3px 6px 6px 3px`, with a
    2px-wide spine bar at `left:3px`, full height. `margin:1px auto 4px`.
  - **You** — 20×20 circle, fill `#2F6B4F`, letter `N`, 10.5px/800, `#fff` (dark: `#DFE8D6`).
    `margin:1px auto 4px`.
- Labels verbatim: `Map`, `My Grove`, `Journal`, `You`.
- 08 variant drops the backdrop blur and uses `border-top:1px solid rgba(29,70,52,.08)` only.
- Dark (D1): background `rgba(16,24,18,.95)`, top border `#26332A`, active `#8EC3A5`,
  inactive `#5F6F61`.

### C17 · `BottomSheet`
- Scrim: `position:absolute; inset:0; background:rgba(14,24,17,.44)` (09, 10) or
  `rgba(14,24,17,.3)` (15).
- Sheet: pinned bottom, fill `#FDFDF8`, `border-radius:26px 26px 0 0`,
  shadow `0 -12px 40px rgba(10,20,14,.32)`, `padding:10px 18px 44px` (09, 10) or
  `22px 20px 44px` (15).
- Grabber: 40×5, `border-radius:3px`, `#DDE2D2`, `margin:4px auto 14px`. **Absent on 15.**
- Title: Source Serif 4 20px/600 (09, 10) or 21px/600 with a 40×40 logo beside it (15).
- Background behind the sheet on 09/10 is a **skeleton** of the profile, not the live profile:
  `padding:62px 16px 0`, `gap:10px`; a 150px `border-radius:16px` gradient hero, then bars
  24px×64% and 14px×44% (radius 8/7px, `#E3E8D9`), then 52px `radius:12px` `#E3E8D9` blocks
  (three on 09, two on 10).

### C18 · `MapCanvas` (01, D1, and the reduced version on 15/18)
- Ground `#E9E5D4` (dark `#141E16`).
- Street grid: `repeating-linear-gradient(90deg, transparent 0 58px, #F7F4E6 58px 64px)` +
  `repeating-linear-gradient(0deg, transparent 0 66px, #F7F4E6 66px 72px)`. (15 adds `opacity:.7`.)
- Ocean band: `left:0; width:13%`, `linear-gradient(90deg,#A9CDC7,#BCD8D0)`; beach strip
  `left:13%; width:7px; background:#EADFB4`.
- Park: `left:22%; top:9%; width:74%; height:11%`, `#CDE0BC`, `border-radius:14px`,
  `box-shadow:inset 0 0 0 1.5px #BCD3A6`.
- Named streets: full-width 9px bands `#FAF7EC` with `box-shadow:0 0 0 1px #E4DEC8` at `top:46%`
  and `top:72%`.
- Rotated labels: `OCEAN BEACH` (`rotate(90deg)`, `#5F8C84`, `letter-spacing:.18em`),
  `GOLDEN GATE PARK` (`#7A9C64`), `JUDAH ST`, `NORIEGA ST`, `48TH AVE` (`#98A388`,
  `letter-spacing:.16em`). All Spline Sans Mono 9px/600.

### C19 · `MapPin`
| Kind | Size | Fill | Border | Shadow |
|---|---|---|---|---|
| City tree | 18×18 circle | `#2F6B4F` | `3px solid #fff` | `0 2px 6px rgba(20,40,26,.35)` |
| Needs care | 18×18 circle | `#B4711F` | `3px solid #fff` | same |
| Community layer | 18×18 circle | `#EDF1E3` | `2.5px dashed #2F6B4F` | `0 2px 6px rgba(20,40,26,.25)` |
| Removed (memorial) | 16×16 circle, `opacity:.85` | `#C4C8B8` | `3px solid #fff` | `0 2px 6px rgba(20,40,26,.2)`; centered 8×2 bar `#7A8272`, radius 1px |
| Cluster | `min-width:32/30px`, height 32/30 | `#1D4634` | `3px solid #fff` | `0 2px 8px rgba(20,40,26,.35)`; label 13/12px, weight 800, `#fff` |
| GPS dot | 18×18 | `#3577C9` | `3px solid #fff` | `0 0 0 8px rgba(53,119,201,.18)` |
| Route done (18) | 20×20 | `#AEBFA1` | — | white 10×8 check `M1 5l3.5 3.5L11 1`, stroke 2.2 |
| Route active (18) | 24×24 | `#B4711F` | `3px solid #fff` | `0 0 0 7px rgba(180,113,31,.22)` |

Dark: pins `#6FAE8C`, amber `#D99A4E`, cluster `#8EC3A5` on `#0E1712` text, ring `3px solid #0E1712`,
GPS `#6FA8E8` + `0 0 0 8px rgba(111,168,232,.16)`, community pin fill `#1B241B` with
`2.5px dashed #6FAE8C` and no shadow.

### C20 · `SearchBar`
- `position:absolute; top:68px; left:16px; right:16px`, `HStack(spacing:10)`,
  fill `rgba(255,255,255,.94)`, `border:1px solid rgba(29,70,52,.1)`, radius 999px,
  `padding:12px 18px`, shadow `0 4px 16px rgba(20,40,26,.1)`.
- Icon: 16×16 SVG — `circle cx=7 cy=7 r=5` + `line 11,11→15,15`, stroke `#77836F`, width 1.8, round cap.
- Placeholder: `Species, street, or neighborhood…` — 14.5px, `#77836F`.
- Dark: fill `rgba(24,37,29,.94)`, border `#2B3A2C`, stroke/text `#94A496`, shadow `0 4px 16px rgba(0,0,0,.4)`.

### C21 · `LeafGlyph`
The app's only bespoke mark: a square with `border-radius: 50% 0` rotated 45°.
Sizes seen: 16px (tab bar), 14px (FAB), 12px (care thumb), 10px (recognize-it bullets).

### C22 · `ThumbnailGradient`
Every tree image is a stack of `radial-gradient(circle at X% Y%, C 0%, rgba(C,0) N%)` layers over a
`linear-gradient(170deg, light, dark)` base, with `border:1px solid rgba(29,70,52,.14)`.
Canonical sets:
- **Cypress** — `32% 40% #4E8F6A/44%`, `66% 32% #35704F/48%`, `52% 60% #24513B/54%`,
  base `linear-gradient(170deg,#E4EBD8,#B9CDBC)`.
- **Ginkgo** — `34% 36% #C9B44A/42%`, `64% 30% #8A9A3F/46%`, `50% 58% #5E7D3A/52%`,
  base `linear-gradient(170deg,#EAEFDC,#C4D2B2)`.
- **London Plane** — `36% 38% #B9A268/44%`, `62% 32% #7C8A4E/48%`, `50% 60% #5C6B3A/52%`,
  base `linear-gradient(170deg,#EFEDDC,#CFD3B4)`.
- **Victorian Box** — `36% 36% #6FB380/44%`, `62% 34% #3E8E5C/48%`, `50% 60% #2C6B45/52%`,
  base `linear-gradient(170deg,#E6EEDE,#BFD4BE)`.

### C23 · `ChartCard` (11, 13)
- Fill `#fff`, `border:1px solid #E3E8D9`, `border-radius:16px`, `padding:14px 16px 10px`
  (13 uses `14px 16px 8px`), shadow `0 1px 3px rgba(25,40,28,.05)`, `margin:10px 16px 0`.
- Header row: `justify-content:space-between; align-items:baseline; margin-bottom:8px` —
  title 14.5px/700 + mono 11px `#8B9482` range.
- Line chart: `viewBox="0 0 330 100"`, gridlines `y=28/50/72` from `x=10` to `x=300`,
  stroke `#EAEDDF` width 1. Series `polyline` stroke `#2F6B4F` width 2.5, fill none.
  Points r=5: **filled `#2F6B4F` = taped**, **hollow (`fill:#fff`, stroke `#2F6B4F` 2.5) = estimated**.
  Latest-value label: `text x=328 y=<py+3> text-anchor=end`, 13px/700, `#1C2A21`, mono.
  Baseline label: `text x=10 y=96`, 10px, `#8B9482`, mono.
- X-axis labels below: `justify-content:space-between`, mono 10px, `#8B9482`, `padding:2px 4px 4px`.
- Bar chart (13): `viewBox="0 0 330 36"`, 12 bars `width=18`, `x = 10 + 26*i`, `rx` 2 (h=4),
  2.5 (h≥8) or 3 (h=34); baseline `y+height = 36`. Empty months drawn in `#EAEDDF`.

### C24 · `AttentionCard` (amber)
- Fill `#fff`, `border:1.5px solid #D9A05B`, `border-radius:16px` (12: `padding:14px 16px`) or
  `14px` (17: `padding:13px 14px`), shadow `0 3px 12px rgba(180,113,31,.1)`.
- Its section micro-label uses `color:#B4711F` instead of `#8B9482`.

### C25 · `Toggle` (17)
- Track 44×26, `border-radius:13px`, fill `#2F6B4F` (on).
- Knob 20×20, `border-radius:10px`, `#fff`, `right:3px; top:3px`,
  shadow `0 1px 3px rgba(0,0,0,.2)`.
- **NOT SPECIFIED:** the off state.

### C26 · `AvatarStack` (03)
- 24×24 circles, `border-radius:50%`, `border:2px solid #fff`, overlap `margin-left:-8px`,
  initial letter 10px/800 `#fff`.
- Fills in order: `#2F6B4F` (N), `#7A4F33` (M), `#4E8F6A` (J), `#66735F` (+3).

### C27 · `ProgressRing` (08)
- 74×74, `conic-gradient(#2F6B4F 0 30%, #E0E6D8 30% 100%)`, `border-radius:50%`.
- Inner disc 54×54, fill `#F5F6EF`, label Spline Sans Mono 14px/600, `#1D4634`, text `30%`.

### C28 · `ConfidenceBar` (02)
- Track: height 4px, `border-radius:2px`, `#E3E8D9`, `max-width:150px`, `margin-top:7px`.
- Fill: `#2F6B4F`, `width:88%` on the top candidate. Only the top card has one.

### C29 · `SpeciesTile` (08)
- `aspect-ratio:1`, `border-radius:14px`, label bottom-left, 11px/700, `#fff`,
  `line-height:1.2`, `padding:9px`, `text-shadow:0 1px 3px rgba(10,22,15,.5)`.
- Background per species: `radial-gradient(circle at 40% 34%, A 0%, transparent 46%)`,
  `radial-gradient(circle at 62% 52%, B 0%, transparent 52%)`, `linear-gradient(180deg, C, D)`.
- Locked tile: fill `#E9ECDE`, centered `?` at 20px/600, `#A8B29C`.

### C30 · `WebFactRow` (W1)
- `HStack`, `justify-content:space-between`, 15px, `border-bottom:1px solid #E9ECDE`,
  `padding:12px 0`. Label `#66735F`; value Spline Sans Mono 600 (or 700 `#2F6B4F` for status).

---

## 3. Screens

The spec is grouped into five sections. Section chrome for each is identical: a mono eyebrow
(11px, `.14em`, uppercase, `#2F6B4F`), an "↑ Back to top" link anchored to `#page-top`
(mono 10px, `.12em`, uppercase, `#8B9482`, hover `#1D4634`), a serif H2 (30px/600, `line-height:1.15`,
`margin:8px 0 6px`) and an intro paragraph (15px, `#66735F`, `max-width:66ch`, `line-height:1.55`,
`margin:0 0 36px`).

### Section A — `#sec-loop` · `Mobile · the core loop`
H2: **Six screens that carry the whole loop**
Intro: *Explore, identify, visit, care for, check in on, report. Every contribution field is optional and everything queues offline.*

---

#### 01 · Map home
**Purpose:** the default screen — look around a map that is already full of the city's trees.

**Caption (verbatim):**
> Seeded with the city’s ~125,000 street trees, so the map is full on day one. Green pins are city trees, dashed pins the community layer, amber marks an open care note, and gray dash-marked pins are removed trees—memorials, tappable to [screen 19](#screen-19). The main thing you do here is look around.

**Frame:** `height:874px`, `position:relative`, `overflow:hidden`, background `#E9E5D4`. Full-bleed
(no 62px status padding — content is absolutely positioned below the notch).

**Structure, back to front:**

1. **Map ground + grid** — C18.
2. **Ocean** `left:0; top:0; bottom:0; width:13%`, `linear-gradient(90deg,#A9CDC7,#BCD8D0)`.
3. **Beach strip** `left:13%; width:7px`, `#EADFB4`.
4. **`OCEAN BEACH`** label — `left:1.5%; top:42%`, mono 9px/600, `.18em`, `#5F8C84`,
   `rotate(90deg)`, origin `left top`.
5. **Golden Gate Park** block — `left:22%; top:9%; width:74%; height:11%`, `#CDE0BC`, radius 14px,
   `inset 0 0 0 1.5px #BCD3A6`. Label **`GOLDEN GATE PARK`** at `left:40%; top:13%`,
   mono 9px/600, `.16em`, `#7A9C64`.
6. **Street bands** at `top:46%` and `top:72%`, `left:13%; right:0; height:9px`, `#FAF7EC`,
   `box-shadow:0 0 0 1px #E4DEC8`.
7. **Street labels** — `JUDAH ST` (`left:20%; top:43.6%`), `NORIEGA ST` (`left:52%; top:69.6%`),
   `48TH AVE` (`right:6%; top:33%`, `rotate(90deg)`, origin center). Mono 9px/600, `.16em`, `#98A388`.
8. **Pins** (C19) at: `26%,31%` green · `39%,42%` green · `61%,36%` **amber** · `73%,53%` green ·
   `31%,66%` green · `51%,60%` **dashed community** · `34%,47.5%` **removed/gray with bar**.
9. **Cluster badges** — `77%,22%` reading `12` (32px) and `17%,55%` reading `7` (30px).
10. **GPS dot** at `46%,56.5%`.
11. **Search bar** (C20) — placeholder `Species, street, or neighborhood…`.
12. **Filter chips** at `top:126px; left:16px`, `gap:8px`: **`All`** (selected, `#1D4634`),
    `In bloom`, `Needs care`.
13. **FAB** at `right:16px; bottom:216px` — `HStack(spacing:9)`, fill `#1D4634`, `#fff`, radius 999px,
    `padding:15px 20px`, 15.5px/700, shadow `0 8px 24px rgba(20,50,30,.4)`. Leading 14px leaf glyph
    in `#8EC3A5`. Label: **`What tree is this?`**
14. **Bottom tree card** at `left:14px; right:14px; bottom:104px` — fill `#fff`,
    `border:1px solid rgba(29,70,52,.1)`, radius 18px, `padding:13px 15px`, `gap:13px`,
    shadow `0 10px 30px rgba(20,40,26,.16)`.
    - Thumb 58×58, radius 14px, Ginkgo gradient (C22).
    - Name `Ginkgo` (Serif 17.5px/600) + `THRIVING` badge (C13, `padding:2px 8px`).
    - Meta: `Maidenhair tree · 6 m NE · visited 3 d ago` — 13px, `#66735F`, `margin-top:2px`.
    - Trailing chevron-right SVG 8×14, `M1 1l6 6-6 6`, stroke `#B4BCA9` width 2, round cap.
15. **Bottom tab bar** (C16) — **Map** active.

**Affordances:** tap a pin → tree profile (or memorial for gray pins); tap the card → profile;
tap the FAB → 02; filter chips switch the pin set; search opens species/street/neighborhood search.

**States/variants:** the four pin kinds and the cluster badge are the drawn variants. Filter chip
selection is single-select with `All` default. **NOT SPECIFIED:** search results, zoom controls,
empty/no-GPS state.

---

#### 02 · What tree is this?
**Purpose:** GPS-ranked shortlist of candidate species, confirmed by eye.

**Caption (verbatim):**
> GPS narrows the seeded catalog to a shortlist. When two candidates fall inside the error circle, each card shows what to look for so you can confirm by eye.

**Frame:** `height:812px; padding-top:62px`, `background:#F5F6EF`, vertical flex.

1. **Header** (C1) with title **`What tree is this?`**, `padding:10px 18px 6px`.
2. **Status chips row** — `padding:8px 18px 14px`, `gap:8px`:
   - `GPS ±9 m` — fill `#fff`, border `1px #E3E8D9`, radius 999px, `padding:6px 13px`, 12.5px,
     `#3C4A3E`, with a leading 8×8 `#3577C9` dot (`gap:6px`).
   - `Two trees in range · confirm by eye` — fill `#F8EFDF`, border `1px #EBD3A8`, radius 999px,
     `padding:6px 13px`, 12.5px, `#8A5A17`.
3. **Candidate list** — `padding:0 16px`, `VStack(spacing:10)`.
   - **Top card (selected):** fill `#fff`, **`border:2px solid #2F6B4F`**, radius 18px,
     `padding:14px`, `gap:14px`, shadow `0 6px 20px rgba(47,107,79,.16)`.
     - Thumb **76×76**, radius 16px, Cypress gradient.
     - Eyebrow `Closest · is it this one?` — 10.5px/800, `.08em`, uppercase, `#2F6B4F`.
     - Name `Monterey Cypress` — Serif 19px/600, `margin-top:1px`.
     - Latin `Hesperocyparis macrocarpa` — Serif italic 13.5px, `#66735F`.
     - Confidence bar (C28) at 88%.
     - Tell: `Its tell: scale-like leaves, lemony when crushed` — 12px, `#66735F`, `margin-top:6px`.
     - Distance `3 m N` — mono 12px, `#66735F`, nowrap.
   - **Rows 2–4 (idle):** fill `#fff`, `border:1px solid #E3E8D9`, radius 18px, `padding:14px`,
     `gap:14px`, `align-items:center`, shadow `0 1px 3px rgba(25,40,28,.05)`. Thumb **60×60**,
     radius 14px. Name Serif 17.5px/600, Latin Serif italic 13px `#66735F`, tell 12px `#66735F`
     `margin-top:3px`, distance mono 12px. No confidence bar, no eyebrow.

   | # | Name | Latin | Tell | Distance |
   |---|---|---|---|---|
   | 2 | `Ginkgo` | `Ginkgo biloba` | `Its tell: fan-shaped leaves` | `9 m NE` |
   | 3 | `London Plane` | `Platanus × hispanica` | `Its tell: camouflage bark, maple-like leaves` | `14 m E` |
   | 4 | `Victorian Box` | `Pittosporum undulatum` | `Its tell: wavy leaf edges, honey scent at night` | `17 m S` |

4. **Footer CTA** — `margin-top:auto`, `padding:14px 16px 40px`, C7 outline button
   `padding:14px`, 15px: **`None of these? Add this tree`**

**Affordances:** tap a card to pick a species → 03/visit; the outline button starts a new tree record.

**States:** selected (2px `#2F6B4F` border + shadow + eyebrow + confidence bar) vs. idle.

---

#### 03 · Tree profile
**Purpose:** the tree's home page — photo, season, identity, one primary action, history, measurements.

**Caption (verbatim):**
> The hero photo, the 12-month season strip, and how-to-recognize-it lead; height and DBH sit at the bottom with their *method* badges. Visiting is the single primary action; everything else sits in a quieter row below. The regulars row shows who else knows this tree.

**Frame:** `height:874px`, `background:#F5F6EF`, vertical flex, `overflow:hidden`.

1. **Hero** (C2), height **224px**. Gradient:
   `radial(28% 46%, #4E8F6A 0→36%)`, `radial(54% 32%, #35704F 0→42%)`,
   `radial(74% 50%, #24513B 0→40%)`, `radial(44% 58%, #2F6B4F 0→38%)`,
   base `linear-gradient(180deg,#EAF0E2 0%,#CFE0D2 55%,#9DBFA6 100%)`.
   Scrim `rgba(16,32,22,0)→.5` from 48%.
   - Back circle at `left:16px; top:66px`.
   - Bottom-right pill: `214 photos · since 2019`.
   - Bottom-left eyebrow: `Best photo · Oct 2025`.
2. **Foliage strip** (C3) — `padding:12px 16px 0`, mono eyebrow `Foliage through the year`,
   12 cells + month row.
3. **Identity block** — `padding:12px 16px 0`:
   - `Grandmother Cypress` — Serif 27px/600, `line-height:1.05`.
   - `THRIVING` badge (C13, `padding:3px 9px`), `gap:10px`, `flex-wrap:wrap`.
   - `Monterey Cypress · Hesperocyparis macrocarpa` — Serif italic 15px, `#66735F`, `margin-top:2px`.
4. **Recognize-it callout** (C14 green) — `margin:12px 16px 0`:
   **`How to recognize it:`** ` flat, layered crown; tiny scale-like leaves; lemony scent when crushed.`
5. **Primary CTA** (C6) — `padding:12px 16px 0`: **`Visit · say hello with a photo`**
6. **Quad action row** (C8): `Favorite` · `Care` · `Share` · `Report`
7. **Regulars row** — `margin:10px 16px 0`, fill `#fff`, border `1px #E3E8D9`, radius 12px,
   `padding:9px 13px`, `gap:10px`, shadow `0 1px 3px rgba(25,40,28,.05)`.
   - AvatarStack (C26): `N`, `M`, `J`, `+3`.
   - Text: **`Six people know this tree`** (13px, `#3C4A3E`, bold).
   - Trailing mono 11px `#8B9482`: `2 this month`.
8. **Activity feed** — `padding:0 16px`, `VStack(spacing:8)`, `margin-top:8px`, two C9 rows:
   - **`Visit`** ` · “Fog dripping off the crown”` — thumb `radial(40% 40%, #4E8F6A 0→50%)` over
     `linear-gradient(170deg,#DCE5D2,#A9C4AE)` — `Oct 12`
   - **`Care`** ` · watered, mulched` — thumb `#E2EFE2` + 12px leaf glyph `#2F6B4F` — `Sep 28`
9. **Stat grid** (C11) — `grid-template-columns:1fr 1fr; gap:8px; padding:10px 16px 30px; margin-top:auto`:

   | Label | Value | Badge |
   |---|---|---|
   | `Height` | `18 m` | `est.` |
   | `DBH` | `64 cm` | `taped` |
   | `Planted` | `1898` | — |
   | `City record` | `SF #114-88` | — |

> **Departed from, deliberately — #137 / RULINGS R28.** These strings were drawn when San
> Francisco was the only city in the seed. It now holds San Jose as well and D16 makes it one
> of many, so `SF city inventory` and the `SF ` in `SF #114-88` stated a city on rows that are
> not San Francisco's, while the provenance line on the same screen named the right one. The
> record number keeps the publisher's own id and drops the prefix (`#114-88`); the provenance
> element names the row's own inventory, from `inventories.name`
> (`City of San Jose Street Tree inventory`), and falls back to the city-neutral
> `city inventory` when the seed cannot say which. Everything else on these lines stands.

**Affordances:** hero → photo timeline (**NOT SPECIFIED**); `Visit` → 04; `Care` → 09 sheet;
`Share` → 10 sheet; `Report` → 06; DBH/Height cards → 11 (caption on 11: "Lives under Details on
the tree profile"); activity row → the observation behind it.

---

#### 04 · Visit (dark camera)
**Purpose:** take the ten-second photo, lined up against a ghost of the last one.

**Caption (verbatim):**
> The camera opens straight to a ghost overlay of the last photo so the timeline stays comparable. Note and phenology tag are optional; offline, submit still succeeds. Phenology chips come from the species record, so an evergreen never gets asked about fall color.

**Frame:** `dark` device. `height:874px`, `background:#10160F`, text `#E4EBE2`, vertical flex.

1. **Viewfinder** (`flex:1`, `position:relative`):
   - Base: `radial(34% 44%, rgba(78,143,106,.5) 0→40%)`, `radial(62% 34%, rgba(53,112,79,.55) 0→46%)`,
     `radial(50% 62%, rgba(36,81,59,.6) 0→50%)`, `linear-gradient(180deg,#26332A 0%,#131B14 100%)`.
   - **Ghost overlay layer** (`inset:0`): `radial(36% 40%, rgba(214,229,208,.16) 0→34%)`,
     `radial(58% 32%, rgba(214,229,208,.13) 0→38%)`, `radial(48% 58%, rgba(214,229,208,.12) 0→42%)`.
   - **Guidance pill** at `top:70px`, centered: fill `rgba(6,10,7,.62)`, text `#DFE8D8`, radius 999px,
     `padding:8px 16px`, 13px, `backdrop-filter:blur(6px)`:
     **`Full tree · match last visit’s angle`**
   - **Framing corners** — four 32×32 L-brackets, `3px solid rgba(255,255,255,.55)`, radii
     `8px 0 0 0` / `0 8px 0 0` / `0 0 0 8px` / `0 0 8px 0`, at `top:118px` (left/right 26px) and
     `bottom:120px` (left/right 26px).
   - **Shot-type chips** at `bottom:150px`, centered, `gap:8px`: **`Full tree`** (selected),
     `Trunk`, `Leaf close-up` (C4 shot-type variants).
   - **Shutter** at `bottom:34px`, centered: 68×68 circle, `#fff`,
     `box-shadow:0 0 0 6px rgba(255,255,255,.35)`.
   - **Ghost caption** at `bottom:44px; left:34px`: mono 10.5px, `rgba(228,235,226,.75)`,
     `max-width:80px`, `line-height:1.4`: `ghost overlay 30%`
2. **Tray** (`flex:none`, `padding:16px 16px 40px`, `VStack(spacing:11)`, background `#151D15`):
   - **Note field:** `border:1px solid #2A362B`, fill `#1B241B`, radius 12px, `padding:12px 14px`,
     14.5px, `#E4EBE2`. Content: `New tips glowing`
   - **Phenology chips** (`gap:8px`): **`New growth`** (on), `Cones`, `Storm damage`.
   - **CTA:** fill `#4E8F6A`, text `#0E1A12`, weight 800, 16px, radius 14px, `padding:15px`:
     **`Log visit`**
   - **Offline line:** 12.5px, `#94A496`, `gap:8px`, leading 8×8 dot `#D99A4E`:
     `No signal · saved to outbox, syncs automatically`

**States:** the prototype gates `Log visit` on having snapped a photo (per README); the spec draws
only the enabled state. **NOT SPECIFIED:** disabled CTA styling, the post-shutter review UI.

**Accessibility variant** (R14; everything above is the layout at the default type size). At
`isAccessibilitySize` and above — AX1 up — the `flex:1` viewfinder becomes a **fixed floor** and the
tray becomes a **scroll view** filling whatever is left of the display. The two are computed from one
height, so they always sum to it.

- **The floor** is `viewfinder width × 4/3` — 524pt on a 393pt phone. Not a chosen number: the
  capture is 4:3 (`sessionPreset = .photo`) behind a `.resizeAspectFill` layer, so this is the exact
  height below which the preview stops showing the whole frame it is about to take. The viewfinder is
  583pt at the drawn size and 550pt at `xxxLarge`, both above the floor, so it first binds precisely
  where the accessibility sizes begin.
- **On the viewfinder, still:** the ✕, the four framing corners, the shutter, and the guidance pill.
  Only furniture whose size does not depend on the type ramp, plus the pill — which stays because
  with the chips moved down it is the only thing naming the framing being aimed, and which can stay
  because it is top-anchored and hit-transparent. Its inset moves: at these sizes it drops **below**
  the ✕'s row rather than sharing it, because at AX5 it is the full width of the phone and would
  otherwise hide the only way off the screen.
- **Into the scroll, in this order:** the shot-type chips (first, immediately under the frame they
  aim), the camera-denied sentence, the ghost caption, then the tray exactly as drawn above — note
  field, phenology chips, `Log visit`, offline line.
- **The shutter does not travel.** It stays pinned to the viewfinder's bottom edge at `bottom:34px`
  at every text size: aiming and firing are one gesture, and it costs a constant 68pt where the
  controls' cost grows without bound. §5's gap 11 already reads this way for the rest of the app —
  "scrollable content with a pinned CTA".
- The two elements that lose a property in the move: the camera-denied sentence drops its capsule and
  material (that treatment exists to make it legible *over a photograph*; on the tray it takes the
  tray's own primary ink), and the ghost caption drops its `max-width:80px` while keeping its mono
  face and color. That cap is the one part of it the type ramp cannot survive — at AX5 it is a
  column of single stacked syllables running the height of the viewfinder.
- Chip rows here are **flow** rows, not `HStack`s, at every size: a chip row given less width than it
  asks for is compressed until its labels break mid-word rather than wrapping onto a second line.

---

#### 05 · Light check-in
**Purpose:** the 90-second structured health observation, all fields optional.

**Caption (verbatim):**
> One scrollable card that fits the 90-second budget. Every vitality class shows its reference photo, label, and anchor line at once, so a “4” means the same thing no matter who is rating.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Check-in`, trailing pill `under a minute`.
2. **`Status`** micro-label + C5 segmented: **`Alive`** (selected) · `Declining` ·
   `Appears dead` · `Removed?`
3. **`Vitality · tap the closest match`** micro-label + 5 rows, `VStack(spacing:6)`, each:
   fill `#fff`, `border:1px solid #E3E8D9`, radius 12px, `padding:8px 12px 8px 8px`,
   `HStack(spacing:11)`, `align-items:center`.
   - Reference swatch: 44×30, radius 7px, the `linear-gradient(140deg, …)` from §1.2.
   - Title 13px/700, anchor line 11.5px `#66735F` `line-height:1.3`.
   - **Selected row (4):** `border:2px solid #2F6B4F`, shadow `0 4px 12px rgba(47,107,79,.16)`,
     trailing 20×20 circle `#2F6B4F` with `✓` 11px/800 `#fff`, pushed via `margin-left:auto`.

   | Level | Title | Anchor line |
   |---|---|---|
   | 1 | `1 · Severe decline` | `Over half the crown is dead wood or bare in season; major limbs dead` |
   | 2 | `2 · Poor` | `26 to 50% of the crown is dead wood or bare; large dead sections` |
   | 3 | `3 · Fair` | `11 to 25% of the crown is dead wood; noticeably thin but clearly in leaf` |
   | 4 | `4 · Good` | `1 to 10% of the crown is dead wood; canopy otherwise full` |
   | 5 | `5 · Thriving` | `No dead wood visible; canopy full for the season` |

   **The five anchor lines above are the one copy string in this document that is NOT transcribed
   from the HTML export.** They are the owner's decision on ticket #261, landed here, in
   `PRODUCT.md` §3 and in `Vitality.anchor` together. The export and `SPEC-PHASE1.md` §6 had stated
   the rubric copy differently since the handoff, and `PRODUCT.md` won on the dieback bands because
   RULINGS R13 reserves a class's *meaning* to `PRODUCT.md` and a band is a class's operational
   definition. The export's original five lines are quoted in the ruling. The titles, the level
   numbers, the order and every layout value in this section are still the export's, unchanged.

4. **`Foliage`** micro-label + C5 segmented: `Full` · **`Thinning`** (selected) · `Sparse` · `Bare`
5. **`Structure · flag anything you see`** micro-label + wrapping chips (`gap:7px`):
   `Lean` · **`Broken limb`** (on) · `Trunk wound` · `Root heave` · `Stake / tie issue`
   (multi-select).
6. **Optional well** (C15): `Add photos · notes (optional)`
7. **Sticky CTA** — `margin-top:auto; padding:12px 18px 8px`, C6: **`Save check-in`**
8. **Footnote** — 12px, `#77836F`, centered, `padding:0 18px 36px`:
   `Everything here is optional. Skip anything and it still counts.`

---

#### 06 · Report an issue
**Purpose:** split hazards (→ 311) from neighborly notes (→ stays in Cypress).

**Caption (verbatim):**
> Hazard reports and neighborly notes are separate pickers. Safety issues go straight to the 311 redirect, and the app keeps no public record of a hazard unless the city was actually told.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Report an issue`.
2. **Hazard section** — micro-label in **amber** (`color:#B4711F`):
   `Safety hazard · for the city’s crew`. Chips (`gap:7px`):
   **`Hanging limb`** (on — `#F8EFDF` / `1.5px #D9A05B` / `#8A5A17` / 700) ·
   `Split trunk` · `Blocking path` (off — `#fff` / `1px #EBD3A8` / `#8A5A17`).
3. **Neighborly section** — micro-label `Neighborly note · stays in Cypress` (`#8B9482`).
   Chips: `Needs water` · `Pest suspected` · `Vandalism` (all `#fff` / `1px #E3E8D9` / `#3C4A3E`).
4. **311 panel** — `margin:18px 16px 0`, `padding:26px 20px`, fill `#F8EFDF`,
   `border:1.5px solid #E0B070`, radius 20px, centered.
   - 54×54 circle `#B4711F`, `margin:0 auto 12px`, containing a 22×22 phone SVG filled `#FDF3E3`
     (path `M5 2c1.5 0 3 2.5 3 4 0 1.2-1.4 1.8-1.4 2.8 0 1.6 4 6 5.6 6 1 0 1.6-1.4 2.8-1.4 1.5 0 4 1.5 4 3s-1.8 3.6-4 3.6C9 20 2 13 2 6c0-2.2 1.8-4 3-4z`).
   - Title: Serif 20px/600, `margin-bottom:5px`: **`This may be a public-safety hazard`**
   - Body: 13.5px, `#6B5122`, `line-height:1.5`, `margin-bottom:16px`:
     `A hanging or broken limb over a path needs the city’s crew, not an app queue. Cypress does not dispatch emergency work.`
   - CTA: fill `#A35F12`, `#fff`, 800, 16px, radius 14px, `padding:15px`,
     shadow `0 4px 14px rgba(163,95,18,.3)`: **`Call 311 now`**
5. **Secondary** (C7, `padding:13px`, 14.5px, radius 14px), `padding:10px 16px 0`:
   **`Save a private reminder for yourself`**
6. **Dashed disclosure** (C14 dashed) — `margin:14px 16px 0`:
   `Hazards never become public notes: a “hanging limb” pin the city never saw would be a liability record, not a warning. Your reminder stays yours alone, and ` **`the city has not been notified`** ` until you call. “Routed to the city” appears only with a real 311 ticket (Phase 2).`

**States:** the 311 panel appears because a hazard chip is selected. **NOT SPECIFIED:** what the
screen looks like with only a neighborly chip selected, or with nothing selected.

---

### Section B — `#sec-flows` · `Mobile · one level deeper`
H2: **The flows behind the first screen**
Intro: *Where taps lead: the species field guide, the running list of species you know, the thirty-second care log, the share sheet, and the growth history behind every number.*

> **Layout note:** in the DOM this section's figures appear in source order 07, 08, 09, 11, 12, 13, 10,
> but 11/12/13 carry CSS `order:2/3/4` so the rendered order is **07, 08, 09, 10, 11, 12, 13**.

---

#### 07 · Species page
**Purpose:** the field-guide entry for a species.

**Caption (verbatim):**
> Every species is a field guide entry: how to recognize it, what to look for this month, and how common it is nearby. All of it builds from the seeded catalog and community photos.

**Frame:** `height:874px`, `#F5F6EF`.

1. **Hero** (C2), height **190px**. Gradient: `radial(30% 48%, #4E8F6A 0→38%)`,
   `radial(58% 34%, #35704F 0→44%)`, `radial(76% 52%, #24513B 0→42%)`,
   base `linear-gradient(180deg,#EAF0E2 0%,#CBDCCE 60%,#96BAA1 100%)`; scrim from 42% to `.56`.
   Text block at `left:18px; bottom:14px`, color `#F0F5EC`:
   - Eyebrow `Field guide` — 10.5px/700, `.1em`, uppercase, `opacity:.85`.
   - Name `Monterey Cypress` — Serif 25px/600, `line-height:1.1`.
   - Latin `Hesperocyparis macrocarpa` — Serif italic 14px, `opacity:.9`.
2. **Taxonomy chips** — `padding:14px 18px 0`, `gap:8px`: `Cupressaceae` · `Evergreen conifer` · `Coastal`.
3. **"How to recognize it" card** — `margin:12px 16px 0`, fill `#fff`, `border:1px #E3E8D9`,
   radius 16px, `padding:14px 16px`, `VStack(spacing:10)`, shadow `0 1px 3px rgba(25,40,28,.05)`.
   - Micro-label `How to recognize it`.
   - Three bullets, 13.5px, `gap:10px`, each with a 10×10 leaf glyph:
     - `#2F6B4F` — `Flat, layered crown shaped by the wind`
     - `#4E8F6A` — `Tiny scale-like leaves, lemony when crushed`
     - `#7A4F33` — `Fibrous gray-brown bark, often a leaning trunk`
4. **Seasonal callout** (C14 gradient) — `margin:10px 16px 0`:
   **`In July:`** ` look for closed gray cones the size of a golf ball ripening in the upper crown.`
5. **Count cards** — `HStack(spacing:8)`, `padding:10px 16px 0`, each `flex:1`, C11 large variant:
   - `In San Francisco` → `1,204`
   - `Near you` → `61`
6. **Nearby individuals** — `padding:10px 16px 36px`, `VStack(spacing:8)`, `margin-top:auto`.
   Micro-label `Nearby individuals`, then rows (fill `#fff`, `1px #E3E8D9`, radius 14px,
   `padding:11px 13px`, `gap:12px`, shadow `0 1px 3px rgba(25,40,28,.05)`), thumb 44×44 radius 11px:
   - `Great Highway at Judah` / `214 photos · thriving` / `220 m`
   - `Sunset Blvd median` / `12 photos · good` / `400 m`
   Row title 14px/700, sub 12px `#66735F`, distance mono 12px `#66735F`.

---

#### 08 · Species you know (My Grove · Species tab)
**Purpose:** the quiet collection — how many neighborhood species you can recognize.

**Caption (verbatim):**
> The ring tracks how many neighborhood species you can recognize, and a new find gets a small celebration. There are no leaderboards. Tapping a tile opens the species page.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Title** `My Grove` — Serif 26px/600, `padding:10px 18px 4px`.
2. **Tab row** — `padding:8px 18px 14px`, `gap:8px`, three `flex:1` pills,
   `padding:9px 2px`, radius **11px**, 13.5px:
   - `Trees`, `Journal` — fill `#fff`, `1px #E3E8D9`, `#66735F`, 600.
   - **`Species`** — fill `#1D4634`, border `1px #1D4634`, `#fff`, 700.
3. **Progress block** — `padding:2px 18px 0`, `HStack(spacing:16)`:
   ProgressRing (C27, `30%`) + `12 of 40 species` (Serif 19px/600) and
   `you can recognize in the Outer Sunset` (13px, `#66735F`).
4. **Celebration callout** (C14 gradient) — `margin:14px 16px 0`:
   **`New species!`** ` First Victorian Box, spotted yesterday on Noriega.`
5. **Species grid** (C29) — `grid-template-columns:repeat(3,1fr); gap:9px; padding:14px 16px 0`:

   | # | Label | Radials | Base gradient |
   |---|---|---|---|
   | 1 | `Monterey Cypress` | `#4E8F6A`, `#24513B` | `#5B8A6C → #1D4634` |
   | 2 | `Ginkgo` | `#C9B44A`, `#5E7D3A` | `#98A44F → #4E6030` |
   | 3 | `London Plane` | `#B9A268`, `#5C6B3A` | `#8D9459 → #4C5530` |
   | 4 | `Victorian Box` | `#6FB380`, `#2C6B45` | `#5A9A6F → #245239` |
   | 5 | `Red Flowering Gum` | `#C0523E`, `#356B4A` | `#67885F → #2C4A34` |
   | 6 | `Pōhutukawa` | `#B33A4A`, `#2C5340` | `#5E7E62 → #233F2F` |
   | 7 | *(locked)* `?` | — | `#E9ECDE`, glyph `#A8B29C` |
   | 8 | `Brisbane Box` | `#D9CDA8`, `#4A7D55` | `#7E9B72 → #3A5B3E` |
   | 9 | *(locked)* `?` | — | `#E9ECDE`, glyph `#A8B29C` |

6. **Footnote** — 12px, `#77836F`, centered, `padding:14px 18px`, `margin-top:auto`:
   `Quiet collecting. There are no streaks and no leaderboards.`
7. **Bottom tab bar** (C16) — **My Grove** active; no `backdrop-filter` on this instance.

---

#### 09 · Care log
**Purpose:** a 30-second sheet for logging what you did to the tree.

**Caption (verbatim):**
> A quick sheet over the profile. Toggle what you did and add a photo if you feel like it. Care performed and conditions observed stay separate records, which matters for coordinators later.

**Frame:** `height:874px; position:relative`, `#F5F6EF`. Skeleton behind (C17), scrim
`rgba(14,24,17,.44)`, sheet pinned bottom.

**Sheet contents:**
1. Grabber (40×5, `#DDE2D2`, `margin:4px auto 14px`).
2. Title `Care log · Monterey Cypress` — Serif 20px/600, `margin-bottom:4px`.
3. Sub `Toggle what you did. Thirty seconds, then back to your walk.` — 12.5px, `#8B9482`,
   `margin-bottom:14px`.
4. Toggle chips (C4 care variant), `flex-wrap`, `gap:9px`, `margin-bottom:14px`:
   **`Watered ✓`** (on) · **`Mulched ✓`** (on) · `Weeded basin` · `Litter cleared`
   *(the ✓ is part of the on-state label string)*
5. Optional well (C15): `Photo or note (optional)`, `margin-bottom:14px`.
6. CTA (C6): **`Done`**
7. Footnote — 12px, `#77836F`, centered, `margin-top:10px`:
   `This joins the tree’s care history—separate from health observations.`

---

#### 10 · Share
**Purpose:** render a share card and hand off the public URL.

**Caption (verbatim):**
> The share sheet renders a card from the tree’s best photo, name, and season strip. The link opens the public web page with no login. It is how a tree reaches a friend who has never opened the app.

**Frame:** identical shell to 09 (skeleton has two 52px blocks instead of three).

**Sheet contents:**
1. Grabber.
2. Title `Share this tree` — Serif 20px/600, `margin-bottom:12px`.
3. **Preview card** — `border:1px solid #E0DDC9`, radius 18px, `padding:14px`, fill `#FAF8EF`,
   `HStack(spacing:14)`, `margin-bottom:16px`, shadow `0 3px 12px rgba(25,40,28,.09)`.
   - Thumb 72×72, radius 16px, Cypress gradient (2 radials + `linear-gradient(170deg,#E4EBD8,#B9CDBC)`).
   - Name `Grandmother Cypress` — Serif 17px/600.
   - Location `Great Highway at Judah · San Francisco` — 12px, `#66735F`.
   - Mini foliage strip (C3 share variant, 12 × 11px squares, radius 3px, `gap:2.5px`, `margin-top:7px`).
   - URL `cypress.app/sf/tree/9f3a` — mono 10.5px, `#8B9482`, `margin-top:6px`.
4. **Destination row** — `HStack(spacing:18)`, `padding:0 2px 4px`. Each target: 58px wide, centered,
   label 10.5px `#66735F`; icon well 52×52 circle, fill `#EAF0E2`, `border:1px solid #DDE2D2`,
   `margin:0 auto 5px`, 24×24 SVG stroke/fill `#3C4A3E` width 1.8.
   - `Messages` (speech bubble), `Instagram` (rounded square + circle + dot),
     `AirDrop` (arcs + dot), `Copy link` (chain link).

**States:** README documents a "Link copied" confirmation in the prototype. **NOT SPECIFIED** in
this spec file — no copied state is drawn. Also **NOT SPECIFIED:** the editable blurb field the
README mentions.

---

#### 11 · Growth history
**Purpose:** the measurement record behind the numbers, method preserved.

**Caption (verbatim):**
> Every recorded value keeps its method: filled dots were taped, hollow ones estimated, and the chart never blends the two. Lives under Details on the tree profile.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Growth`, trailing pill `Grandmother Cypress`.
2. **DBH chart card** (C23): title **`Trunk diameter · DBH`**, range `since 2019`.
   Points `10,80 · 51,69 · 92,58 · 133,50 · 174,39 · 215,31 · 256,24 · 297,16`.
   Hollow (estimated) at x=10, 92; filled (taped) at 51, 133, 174, 215, 256, 297.
   Value label `64` at `x=328 y=19`; baseline `47 cm` at `x=10 y=96`.
   Axis: `2019` `2021` `2023` `2025`.
3. **Height chart card** (C23): title **`Height`**, range `since 2020`.
   Points `10,74 · 58,62 · 106,56 · 154,50 · 202,38 · 250,31 · 297,25`.
   Only x=106 is filled; all others hollow.
   Value label `18` at `x=328 y=28`; baseline `14 m` at `x=10 y=96`.
   Axis: `2020` `2022` `2024` `2026`.
4. **Legend** — `padding:12px 18px 4px`, `gap:8px`, two C4 legend pills:
   - filled 10×10 `#2F6B4F` dot + `taped`
   - hollow 5×5 with `2.5px solid #2F6B4F` border, fill `#fff` + `estimated`
5. **Measurement log** — `padding:6px 16px 0`, `VStack(spacing:7)`. Each row: fill `#fff`,
   `1px #E3E8D9`, radius 12px, `padding:10px 13px`, `gap:10px`, 13.5px:
   value (mono bold) · method badge (C12, 11px, `padding:1.5px 7px`) · role (`#8B9482`) ·
   date (mono 11px `#8B9482`, `margin-left:auto`).

   | Value | Method | Role | Date |
   |---|---|---|---|
   | `64 cm` | `taped` | `steward` | `Oct 2025` |
   | `62 cm` | `taped` | `steward` | `Jun 2024` |
   | `60 cm` | `estimated` | `member` | `Aug 2023` |

6. **Footnote** — 12px, `#77836F`, centered, `padding:14px 18px 36px`, `margin-top:auto`:
   `Tap any point to open the observation behind it.`

---

#### 12 · Neighborhood almanac
**Purpose:** what's happening in the neighborhood's trees, without ranking anybody.

**Caption (verbatim):**
> There is no leaderboard, since ranked counts reward spamming the record. Instead the almanac marks the season’s firsts, elders, and newcomers, and points people toward young trees nobody has visited yet.

*(Figure label is `12 Almanac`; the caption headline is `12 · Neighborhood almanac`.)*

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Almanac`, trailing pill `Outer Sunset`.
2. **`This season`** micro-label + three C10 rows (`VStack(spacing:7)`):

   | Tile accent | Title | Subtitle |
   |---|---|---|
   | `#D77A8A` over `#F6E8E4` | `First bloom of the year` | `Red flowering gum on 44th Ave · Jan 22, three neighbors saw it` |
   | `#4E8F6A` over `#E7EFE2` | `The elder` | `Grandmother Cypress · in the city record since 1898` |
   | `#8FB573` over `#EDF2E0` | `Newest neighbors` | `23 trees planted this spring, mostly ginkgo and tea tree` |

3. **`Who lives here · 64 species`** micro-label + composition card
   (fill `#fff`, `1px #E3E8D9`, radius 16px, `padding:14px 16px`, `VStack(spacing:9)`).
   Each row: 11×11 swatch (radius 3.5px) · name 13.5px/700 · a `flex:1` 9px track
   (radius 5px) filled via `linear-gradient(90deg, <color> 0 N%, #EDEFE3 N%)` · mono 12px `#66735F` value.

   | Swatch | Name | Share |
   |---|---|---|
   | `#1D4634` | `Monterey cypress` | `18%` |
   | `#4E8F6A` | `NZ tea tree` | `11%` |
   | `#7A4F33` | `Ginkgo` | `9%` |
   | `#C2CAB4` | `Everyone else` (name colored `#66735F`) | `62%` |

4. **`Where eyes are needed`** micro-label (amber `#B4711F`) + AttentionCard (C24, radius 16px,
   `padding:14px 16px`):
   - Title 14.5px/700: **`9 young trees with no visits since planting`**
   - Body 12.5px `#66735F`, `margin:4px 0 12px`, `line-height:1.45`:
     `The first two summers decide whether a street tree makes it. All nine are within a 15-minute walk.`
   - CTA (C6 small): **`Walk the nine`**
5. **Footnote** — `padding:16px 18px 36px`, `margin-top:auto`:
   `No ranks, no counters. The almanac notices trees, not scores.`

---

#### 13 · Tree activity
**Purpose:** one tree's year as three small multiples plus a list of moments.

**Caption (verbatim):**
> One tree’s year in three small multiples: same month axis and scale, so June’s photo spike reads against the steadier care and check-in rhythm. Below that, the year appears as a list of moments instead of totals.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Activity`, trailing pill `Grandmother Cypress`.
2. **"This year at a glance"** ChartCard (C23, `padding:14px 16px 8px`), header
   **`This year at a glance`** + mono `2026`. Three series, each with a legend line
   (10×10 swatch radius 3px · name 12.5px/700 · mono 12px total, `margin-left:auto`) and a
   `viewBox="0 0 330 36"` bar row:

   | Series | Swatch/fill | Total | Bar heights J→D |
   |---|---|---|---|
   | `Photos` | `#2F6B4F` | `41` | 8, 4, 10, 13, 17, **34**, 17, 10, 8, 8, 4, 4 |
   | `Check-ins` | `#4E8F6A` | `18` | 4, 4, 8, 8, 10, 8, 8, 4, 4, 4, 4, 4 |
   | `Care` | `#7A4F33` | `9` | 4*, 4*, 4, 8, 4, 4, 4*, 8, 4, 4, 4*, 4* — starred bars drawn in `#EAEDDF` (no care that month) |

   Shared month axis: `viewBox="0 0 330 14"`, mono 9px `#8B9482`, centered at
   `x = 19 + 26*i`, letters `J F M A M J J A S O N D`.
3. **`Moments`** micro-label + three C10 rows:

   | Tile accent | Title | Subtitle |
   |---|---|---|
   | `#8FB573` over `#EDF2E0` | `Spring flush noted` | `Apr 3 · four visitors caught the bright new tips` |
   | `#7FA8C4` over `#E8EEF2` | `Watered through the dry weeks` | `Jun–Aug · five care visits kept it going` |
   | `#C9B44A` over `#F4F0DE` | `Seven years on record` | `First photo Mar 2019 · six people know this tree` |

4. **`Same week, other years`** micro-label + 3-up photo strip (`gap:8px`), each `flex:1`,
   height **88px**, radius 12px, with a bottom-left mono 10px chip
   (`background:rgba(255,255,255,.85)`, radius 6px, `padding:2px 7px`, `#3C4A3E`):
   - `2024` — `radial(40% 44%, #8FB573 0→55%)` over `linear-gradient(175deg,#E8EDDB,#C5D2B8)`
   - `2025` — `radial(55% 40%, #7FA284 0→55%)` over `linear-gradient(175deg,#E3E8DC,#BFC9BA)`
   - **`this week`** — `border:2px solid #2F6B4F`, `radial(45% 42%, #4E8F6A 0→52%)` over
     `linear-gradient(175deg,#DFE8D6,#AFC4AC)`; chip is `#fff` on `#2F6B4F`.
5. **Footnote** — `padding:16px 24px 36px`, `line-height:1.5`:
   `One scale across all three charts, so a tall bar means the same amount everywhere. June’s 12 photos set the ceiling.`

---

### Section C — `#sec-field` · `Mobile · in the field`
H2: **Built for day one and muddy hands**
Intro: *The unglamorous screens that make the app trustworthy: a brand-new tree before anyone has photographed it, the account question asked at the right moment, how a number enters the record, where unsent work waits out a dead zone, and how a volunteer’s morning rolls from tree to tree.*

---

#### 14 · Cold-start profile (a brand-new tree)
**Purpose:** what a profile looks like on launch day, before any community photo exists.

**Caption (verbatim):**
> What almost every profile looks like on launch day: a city record, a field guide entry, and a prompt to take the tree’s first photo.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Tree`.
2. **Empty photo well** — `margin:10px 16px 0`, height **170px**, radius 18px,
   `border:2px dashed #C4CEB4`, fill `#FAFBF4`, centered `VStack(spacing:8)`, color `#8B9482`.
   - 46×46 circle `#EAF0E2` containing a 22×18 camera SVG (`rect 1,4 20×13 rx3` +
     `circle 11,10.5 r3.6` + `rect 7,1 8×4 rx1.5` filled), stroke `#8B9482` width 1.8.
   - Text 13px: `No photos of this tree yet`
3. **Identity block** — `padding:14px 18px 0`:
   - `Brisbane Box` — Serif 25px/600.
   - `PLANTED 2024` badge (C13).
   - `Lophostemon confertus · SF city inventory` — Serif italic 14.5px, `#66735F`.
     (drawn; departed from by R28 — see the note under 03's stat grid)
4. **Recognize-it callout** (C14 green) — `margin:12px 16px 0`:
   **`How to recognize it:`** ` glossy oval leaves in whorls; smooth bark peeling to cream and rust.`
5. **Stat grid** (C11, `padding:12px 16px 0`):

   | Label | Value | Badge |
   |---|---|---|
   | `DBH` | `8 cm` | `city record` |
   | `Site` | `Sidewalk cut` | — |
   | `City record` | `SF #201-33` | — | (drawn; `#201-33` on screen, R28)
   | `Watch for` | `First-summer thirst` — **13px/700 sans, not mono**, `margin-top:2px` | — |

6. **CTA** (C6) — `padding:14px 16px 0`: **`Be the first to photograph this tree`**
7. **Footnote** — `padding:14px 24px 36px`, `margin-top:auto`, `line-height:1.5`:
   `A young tree nobody has visited. This is the almanac’s “walk the nine” list, one tree at a time.`

**Differences from 03 to encode as a variant:** no hero, no foliage strip, no regulars row,
no activity feed, no quad-action row, badge is `PLANTED <year>` instead of `THRIVING`.

---

#### 15 · The account ask (on the third save)
**Purpose:** the one-time, deferred sign-in prompt after there is something worth keeping.

**Caption (verbatim):**
> First saves are anonymous and local, because nobody signs a data license on a street corner. The ask comes once there is something worth keeping. Consent is a single plain sentence with the long version a tap away, and declining still works.

**Frame:** `height:874px`, `#E9E5D4`, map behind at `opacity:.7` grid, three 16×16 `#4E8F6A` pins
(`3px solid #fff`, shadow `0 2px 6px rgba(20,40,26,.3)`) at `24%,26%`, `60%,15%`, `76%,38%`;
scrim `rgba(14,24,17,.3)`.

**Sheet** (C17, `padding:22px 20px 44px`, **no grabber**):
1. Header row (`HStack(spacing:12)`, `margin-bottom:6px`): 40×40 Cypress logo PNG +
   `Keep your three visits` (Serif 21px/600).
2. Body — 13.5px, `#66735F`, `line-height:1.5`, `margin:0 0 16px`:
   `They live on this phone right now. An account backs them up and lets them join each tree’s public timeline.`
3. **`Continue with Apple`** — fill `#1C2A21`, `#fff`, radius 14px, `padding:14px`, 15px/700,
   `margin-bottom:8px`.
4. **`Continue with Google`** — `border:1.5px solid #D8DECB`, `#1C2A21`, fill `#fff`, radius 14px,
   `padding:13px`, 15px/700, `margin-bottom:8px`.
5. **`Use email`** — same as Google, `margin-bottom:16px`.
6. **Consent row** — `HStack(spacing:10)`, `align-items:flex-start`, 12px, `#66735F`,
   `line-height:1.5`. Checkbox: 20×20, radius 6px, `border:2px solid #2F6B4F`, glyph `✓`
   12px/800 `#2F6B4F`, `margin-top:1px`. Copy:
   `Share my tree records under the open database license. In plain words: anyone may use the data, and your name rides along only if you opt in. ` **`Read the short version`** *(bold, `#2F6B4F`)*
7. **Decline** — centered, 13px, `#66735F`, weight **700**, `margin-top:16px`:
   `Not now · keep saving to this phone only`

**States:** checkbox drawn checked. **NOT SPECIFIED:** unchecked styling, dismissal gesture.

---

#### 16 · Measure
**Purpose:** the single gate every number in the record passes through.

**Caption (verbatim):**
> Every number in the record enters through this sheet. Method is a required chip, the previous value sits under the readout as a sanity check, and estimates stay labeled as estimates in the growth chart.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Measure`, trailing pill `Grandmother Cypress`.
2. **`What are you measuring?`** micro-label + 2-segment C5 (14px, `padding:11px 2px`):
   **`Trunk · DBH`** (selected) · `Height`
3. **Readout** — centered, `padding:18px 0 2px`:
   - `64` — Spline Sans Mono **56px**/600, `letter-spacing:-.02em`.
   - ` cm` — 20px/700, `#66735F` (leading space is in the source).
   - `switch to inches` — 12px, `#8B9482`, `margin-top:2px`.
   - Sanity pill (C4, `margin-top:10px`, `display:inline-block`):
     `Last recorded 62 cm, Jun 2024 · +2 cm in a year sounds right`
4. **`Method · required`** micro-label + 3-segment C5: **`Tape`** (selected) · `Caliper` · `Estimate`
5. **Keypad** — `grid-template-columns:repeat(3,1fr); gap:8px; padding:16px 18px 0`.
   Keys: `1 2 3 4 5 6 7 8 9 . 0 ⌫`. Each: centered, `padding:14px 0`, fill `#fff`,
   `border:1px solid #E3E8D9`, radius 12px, Spline Sans Mono 19px/600.
6. **CTA** (C6) — `margin-top:auto; padding:14px 18px 8px`: **`Save measurement`**
7. **Footnote** — `padding:0 24px 36px`, `line-height:1.5`:
   `Taken at 1.4 m, tape in one hand. A shrinking trunk gets a “sure about that?” before it saves.`

**States:** the "sure about that?" confirmation is described in copy only — **NOT SPECIFIED** visually.

---

#### 17 · Outbox
**Purpose:** unsent field work gets a real screen, not a toast.

**Caption (verbatim):**
> Field work is too expensive to lose, so unsent items get a real screen rather than a toast. Every unsent item is visible with its state, a failure asks for a retry instead of vanishing, and the wifi toggle respects a volunteer’s data plan.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Header** (C1): title `Outbox`, trailing pill in **amber**: fill `#F8EFDF`,
   `border:1px solid #EBD3A8`, `#8A5A17`, weight 700 — `3 waiting · offline`
2. **Queue** — `padding:12px 16px 0`, `VStack(spacing:8)`. Rows: fill `#fff`,
   `border:1px solid #E3E8D9`, radius 14px, `padding:13px 14px`, `gap:12px`, `align-items:center`.
   Leading tile 38×38, radius 10px. Title 14px/700, sub 12px `#66735F` `margin-top:1px`,
   trailing state mono 11px/600 `#8B9482`.

   | Icon tile | Title | Sub | State |
   |---|---|---|---|
   | `#EAF0E2` + 18×15 camera SVG stroke `#2F6B4F` w2 | `Visit · Grandmother Cypress` | `2 photos · 11:42 am` | `waiting` |
   | `#EAF0E2` + 14×14 ring `3px solid #2F6B4F` with `border-left-color:transparent`, `rotate(-45deg)` | `Check-in · Judah Street Gum` | `vitality 3, thinning · 11:18 am` | `waiting` |
   | `#F8EFDF` + mono 12px/700 `#8A5A17` text `31` | `Measurement · The Tea Tree at 46th` | `DBH 31 cm, tape · upload failed twice` | `retry` — mono 11px/**700**, `#B4711F` |

   The third row is an AttentionCard (C24): `border:1.5px solid #D9A05B`,
   shadow `0 3px 12px rgba(180,113,31,.1)`.
3. **Wifi setting row** — `margin:10px 16px 0`, fill `#fff`, `1px #E3E8D9`, radius 14px,
   `padding:13px 15px`, `gap:12px`:
   - `Sync photos on wifi only` — 13.5px/700.
   - `Notes and numbers sync on any connection` — 11.5px, `#8B9482`, `margin-top:1px`.
   - Toggle (C25) on the right, **on**.
4. **`Synced earlier today`** micro-label + a `VStack(spacing:7)` at `opacity:.65`.
   Rows: fill `#fff`, `1px #E3E8D9`, radius 12px, `padding:10px 13px`, 13px, bold title +
   trailing mono 11px/600 `#28623F`:
   - `Visit · Ginkgo on Noriega` → `✓ 9:56 am`
   - `Care · watered · Brisbane Box` → `✓ 9:41 am`
5. **Summary line** — `margin-top:9px`, mono 11px `#8B9482`:
   `this week · 14 synced · 0 lost`, trailing `full history` in `#2F6B4F` weight 700.
6. **Footnote** — `padding:16px 24px 36px`, `line-height:1.5`:
   `Nothing here disappears silently. An item that cannot sync says so, says why, and waits for you.`

**States drawn:** `waiting`, `retry`, `synced` (dimmed, green check). **NOT SPECIFIED:**
in-progress/uploading state, swipe-to-delete.

---

#### 18 · Next tree
**Purpose:** the save confirmation that answers "which tree is next".

**Caption (verbatim):**
> Saving a check-in immediately offers the next nearest tree, checked trees dim on the map, and a ten-tree morning moves along on its own. The day’s list can be your own favorites or a route from a stewards group.

**Frame:** `height:812px; padding-top:62px`, `#F5F6EF`.

1. **Success block** — centered, `padding:22px 0 6px`:
   - 66×66 circle `#E2EFE2`, `margin:0 auto`, containing a 28×22 check SVG
     `M2 12l8 8L26 2`, stroke `#2C6B45` width **4**, round caps/joins.
   - `Check-in saved` — Serif 22px/600, `margin-top:10px`.
   - `Judah Street Gum · ` + mono `4 of 10` + ` on today’s list` — 13px, `#66735F`, `margin-top:2px`.
2. **Mini route map** — `margin:14px 16px`, height **190px**, radius 18px, fill `#E4E9D3`,
   `border:1px solid #DBE0CB`, `overflow:hidden`.
   - Grid: `repeating-linear-gradient(90deg, transparent 0 52px, #F4F1E2 52px 57px)` +
     `repeating-linear-gradient(0deg, transparent 0 58px, #F4F1E2 58px 63px)`.
   - Water band on the right: `width:8%`, `#B5CFD2`, `opacity:.75`.
   - Four **done** pins (20×20 `#AEBFA1` + white check) at
     `left:22,top:34` · `left:78,top:96` · `left:146,top:52` · `left:206,top:112`.
   - One **active** amber pin (24×24 `#B4711F`, `3px solid #fff`,
     `0 0 0 7px rgba(180,113,31,.22)`) at `right:84px; top:66px`.
   - Corner label at `right:16px; bottom:10px`, mono 10px, `#77836F`: `done trees go quiet`
3. **Primary CTA** (C6, `padding:16px`) — `padding:0 16px`:
   **`Next nearest: The Tea Tree · 40 m`**
4. **Secondary** (C7, `padding:14px`, 15px) — `padding:10px 16px 0`: **`Done for today`**
5. **Footnote** — `padding:16px 24px 36px`, `line-height:1.5`:
   `Ten check-ins in a row is the real volunteer morning. The save answers the only question that matters: which tree is next.`

---

#### 19 · Memorial
**Purpose:** a removed tree's profile, read-only, history intact.
Anchor: `id="screen-19"` (linked from the 01 caption).

**Caption (verbatim):**
> When the weekly city sync marks a tree removed, the profile becomes a read-only memorial: muted palette, history intact. When the site is replanted, the new profile links back through `site_lineage`, so the site’s history carries over.
> *(the token `site_lineage` is set in Spline Sans Mono 11.5px inside the caption)*

**Frame:** `height:874px`, `#F5F6EF`.

1. **Hero** (C2), height **200px**, **desaturated**: `radial(30% 46%, #9AA58E 0→38%)`,
   `radial(58% 34%, #8A9483 0→44%)`,
   base `linear-gradient(180deg,#EDEEE6 0%,#D6D9CC 60%,#B4BAA9 100%)`;
   scrim `rgba(30,34,28,0)→.5` from 46%.
   - Bottom-right pill (`rgba(30,34,28,.45)`, text `#EFF1EA`): `86 photos · 2019–2026`
   - Bottom-left eyebrow (`#EFF1EA`): `Last photo · Apr 2026`
2. **Memorial banner** (C14 memorial) — `margin:14px 16px 0`:
   **`Removed by the city, May 2026.`** ` This profile is now read-only. Every photo, visit, and check-in stays—a record of the tree that was here.`
3. **Identity block** — `padding:14px 16px 0`:
   - `Judah Street Gum` — Serif 27px/600, `line-height:1.05`.
   - `REMOVED` badge (C13).
   - `Red Flowering Gum · Corymbia ficifolia · 2003–2026` — Serif italic 15px, `#66735F`.
4. **Timeline** — `padding:12px 16px 0`, `VStack(spacing:8)`, four C9 rows:

   | Thumb | Copy | Date |
   |---|---|---|
   | `radial(42% 44%, #9FB582 0→52%)` over `linear-gradient(170deg,#E8E9DE,#C9CDBB)` | **`First photo`** ` · the record begins · six people came to know it` | `Mar 2019` |
   | `radial(40% 40%, #C0523E 0→50%)` over `linear-gradient(170deg,#E3E5D9,#C2C7B4)` | **`Visit`** ` · “The reddest bloom on the block, every January”` | `Jan 2026` |
   | `linear-gradient(140deg,#C9B06A,#A3813F)` (vitality-2 swatch) | **`Check-in`** ` · vitality 2 · a steward confirmed the decline` | `Mar 2026` |
   | `#EDEEE6` with mono 10px/600 `#5C6555` text `SYNC` | **`City record`** ` · marked removed · storm damage` | `May 2026` |

5. **Lineage callout** (C14 green, radius 14px, `padding:13px 15px`) — `margin:12px 16px 0`:
   **`A new tree is coming.`** ` When the city replants this site, the new profile will link back here—the site keeps its lineage.`
6. **Stat grid** (C11):

   | Label | Value |
   |---|---|
   | `On record` | `23 years` |
   | `City record` | `SF #088-21` | (drawn; `#088-21` on screen, R28)

**Read-only enforcement:** no Visit CTA, no quad action row, no foliage strip. That absence *is*
the read-only state.

---

### Section D — `#sec-dark` · `Mobile · after dark`
H2: **Dark mode, same forest**
Intro: *The greens desaturate rather than glow, amber stays reserved for need, and every method badge survives the theme switch. Three representative screens; the rest follow the same token mapping.*

---

#### D1 · Map home, dark
**Caption (verbatim):**
> The map goes to forest-floor greens instead of inverted gray. Pins brighten to mint for contrast against the dark ground; the primary FAB flips to light-on-dark so it stays the brightest thing on screen.

Same geometry as 01. Deltas:

| Element | Light | Dark |
|---|---|---|
| Ground | `#E9E5D4` | `#141E16` |
| Grid stripes | `#F7F4E6` | `#1C2A1F` |
| Ocean | `linear-gradient(90deg,#A9CDC7,#BCD8D0)` | `linear-gradient(90deg,#14282B,#183034)` |
| Beach | `#EADFB4` | `#2B3226` |
| Park | `#CDE0BC` / inset `#BCD3A6` | `#1B3123` / inset `#274531` |
| Street bands | `#FAF7EC` / ring `#E4DEC8` | `#232F24` / ring `#2B3A2C` |
| Labels | `#5F8C84` / `#7A9C64` / `#98A388` | `#4E7A74` / `#557A50` / `#5C6B57` |
| Pins | `#2F6B4F`, ring `#fff` | `#6FAE8C`, ring `#0E1712` |
| Amber pin | `#B4711F` | `#D99A4E` |
| Community pin | `#EDF1E3` + dashed `#2F6B4F` | `#1B241B` + dashed `#6FAE8C`, no shadow |
| Clusters | `#1D4634` on `#fff` text | `#8EC3A5` on `#0E1712` text |
| GPS | `#3577C9` + blue halo | `#6FA8E8` + `rgba(111,168,232,.16)` halo |
| Search bar | white glass | `rgba(24,37,29,.94)`, border `#2B3A2C`, icon/text `#94A496` |
| Filter chip on | `#1D4634` / `#fff` / 700 | `#8EC3A5` / `#0E1712` / **800** |
| Filter chip off | `rgba(255,255,255,.92)` | `rgba(24,37,29,.92)`, border `#2B3A2C`, text `#AEBBAB` |
| FAB | `#1D4634` on `#fff`, glyph `#8EC3A5` | `#8EC3A5` on `#0E1712`, **weight 800**, glyph `#1D4634` |
| Tree card | `#fff` / `rgba(29,70,52,.1)` | `#18251D` / `#2B3A2C` |
| Card thumb | Ginkgo light gradient | `radial(34% 36%, #9B8A38 0→42%)`, `radial(64% 30%, #5E7030 0→46%)`, `linear-gradient(170deg,#2A331F,#1A2313)`, border `#2B3A2C` |
| Card chevron | `#B4BCA9` | `#4A5A4C` |
| Tab bar | `rgba(250,250,244,.95)` | `rgba(16,24,18,.95)`, top border `#26332A` |
| Tab active / inactive | `#1D4634` / `#8B9482` | `#8EC3A5` / `#5F6F61` |
| You avatar | `#2F6B4F` on `#fff` | `#2F6B4F` on `#DFE8D6` |

Note: **`48TH AVE` and the removed/gray pin are omitted** in the dark version.

---

#### D2 · Tree profile, dark
**Caption (verbatim):**
> Cards sit at #18251D on a #0E1712 ground—green-tinted blacks, never neutral gray. The season strip mutes but keeps its relative rhythm, and both method badges keep their meaning in the dark.

Same structure as 03 with these deltas:
- Screen background `#0E1712`, text `#E4EBE2`.
- Hero (224px) gradient uses alpha radials over `linear-gradient(180deg,#22301F 0%,#182417 55%,#111A11 100%)`:
  `radial(28% 46%, rgba(78,143,106,.55) 0→36%)`, `radial(54% 32%, rgba(53,112,79,.6) 0→42%)`,
  `radial(74% 50%, rgba(36,81,59,.65) 0→40%)`; scrim `rgba(8,14,10,0)→.62` from 48%.
- Back circle: `rgba(24,37,29,.92)` + `1px #2B3A2C`, chevron `#AEBBAB`.
- Photo pill: `rgba(8,14,10,.55)`, text `#CFE0D2`. **The `Best photo · Oct 2025` eyebrow is dropped.**
- Foliage eyebrow `#5F6F61`; strip ramp `#3E6B44 / #587D50 / #6E8A5F`; **month row dropped**.
- `THRIVING` badge `#8EC3A5` on `#1F3A2C`.
- Latin name `#94A496`.
- Recognize-it callout: fill `#1A241A`, border `1px #27352B`, body `#B9C7B2`, lead-in `#D6E0CE`.
- CTA: `#8EC3A5` on `#0E1712`, weight 800, no shadow.
- Quad action row: `#18251D` / `1px #27352B` / `#AEBBAB`.
- **Regulars row is dropped entirely.**
- Activity rows: `#18251D` / `#27352B`, body `#D6E0CE`, timestamps `#5F6F61`. Visit thumb
  `radial(40% 40%, rgba(78,143,106,.6) 0→50%)` over `#1F2E22`; Care thumb `#1F3A2C` with
  a `#8EC3A5` leaf glyph.
- Stat cards `#18251D` / `#27352B`, labels `#5F6F61`, values `#E4EBE2`;
  `est.` → `#D9A05B` on `#2E271A`, `taped` → `#8EC3A5` on `#1F3A2C`.

---

#### D3 · Check-in, dark
**Caption (verbatim):**
> The screen a volunteer uses at 7 am in December. Vitality reference swatches desaturate so they stay readable against a dark surround; selection moves to mint so it reads without hue.

Same structure as 05 with these deltas:
- Background `#0E1712`; cards `#18251D`, borders `#27352B`; micro-labels `#5F6F61`.
- Header back circle `#18251D`/`#27352B`, chevron `#AEBBAB`; trailing pill `#18251D`/`#27352B`/`#94A496`.
- Segmented selected: `#8EC3A5` fill, `#0E1712` text, weight **800**.
- Vitality swatch gradients: the dark column in §1.2. Titles `#D6E0CE` (selected row `#E4EBE2`),
  anchor lines `#94A496`.
- Selected vitality row: `border:2px solid #8EC3A5`, **no shadow**; check circle `#8EC3A5`
  with `#0E1712` glyph.
- Structure chips: on = `#8EC3A5`/`#0E1712`/800; off = `#18251D`/`1px #27352B`/`#AEBBAB`.
- CTA `#8EC3A5` on `#0E1712`, weight 800, no shadow.
- Footnote `#5F6F61`.
- **Dropped vs. 05:** the `Foliage` segmented control, the optional photos/notes well, and the
  fifth structure chip `Stake / tie issue`.

---

### Section E — `#sec-web` · `Web · public & shareable`
H2: **Every tree gets a page worth sending to a friend**
Intro: *No login needed to view a tree. The share card—best photo, name, season strip—is how a tree gets sent to a friend.*

A responsive helper `Swipe sideways to pan the window` (mono 10px, `.12em`, uppercase, `#8B9482`)
appears above the frame below 700px.

---

#### W1 · Public tree page
**Purpose:** the no-login page a share link opens.

**Caption (verbatim):**
> The link a share card points to. Hero and season strip lead; the fact column keeps every method badge; the OpenGraph image is rendered from the same three ingredients so the group-chat preview and the page agree.

**Frame:** `ChromeWindow` 1180×780, URL `cypress.app/sf/tree/9f3a-monterey-cypress`.
Page: `background:#F5F6EF`, column flex.

1. **Top bar** — `HStack(spacing:26)`, `padding:14px 32px`, `border-bottom:1px solid #E3E8D9`,
   background `#FBFBF5`.
   - 30×30 logo PNG + `Cypress` (Serif 19px/600), `gap:10px`.
   - Nav: **`Explore`** (14px/700, `#2F6B4F`) · `Species` · `Neighborhoods` · `Data & export`
     (14px, `#66735F`).
   - Right: `Sign in` — fill `#1D4634`, `#fff`, radius 10px, `padding:8px 18px`, 13.5px/700,
     `margin-left:auto`.
2. **Body grid** — `display:grid; grid-template-columns:1.45fr 1fr; flex:1; min-height:0`.

   **Left · hero** (`position:relative`, `align-items:flex-end`):
   - Gradient `radial(26% 50%, #4E8F6A 0→34%)`, `radial(52% 34%, #35704F 0→40%)`,
     `radial(72% 54%, #24513B 0→38%)`, `radial(42% 62%, #2F6B4F 0→36%)`,
     base `linear-gradient(180deg,#EAF0E2 0%,#C9DCCC 55%,#8FB59B 100%)`.
   - Scrim `rgba(16,32,22,0)→.6` from 46%.
   - Content `padding:32px`, color `#EFF5EA`:
     - Eyebrow 12px/700, `.1em`, uppercase, `opacity:.85`:
       `Great Highway at Judah · San Francisco`
     - H1 Serif **42px**/600, `line-height:1.05`, `margin-top:4px`: `Grandmother Cypress`
     - Latin Serif italic 18px, `opacity:.9`: `Monterey Cypress · Hesperocyparis macrocarpa`
     - Foliage strip (C3 web variant), `margin-top:18px`, `max-width:420px`.
     - Caption mono 11px, `opacity:.85`, `margin-top:8px`:
       `FOLIAGE · JAN THROUGH DEC · 214 PHOTOS SINCE 2019`

   **Right · fact column** (`padding:32px 34px`, background `#FBFBF5`,
   `border-left:1px solid #E3E8D9`), C30 rows:

   | Label | Value |
   |---|---|
   | `Status` | `Thriving · vitality 4` — weight 700, `#2F6B4F` |
   | `Height` | mono `18 m` + `est.` badge |
   | `Trunk · DBH` | mono `64 cm` + `taped` badge |
   | `In the city record since` | mono `1898` |
   | `City record` | mono `SF DPW #114-88 · synced weekly` |
   | `Data` | mono `ODbL · CSV / GeoJSON` |

   - **Button pair** — `HStack(spacing:10)`, `margin-top:22px`, both `flex:1`, radius 12px:
     **`Open in the app`** (C6, `padding:13px`, 14.5px) and
     **`Share this tree`** (C7, `padding:11px`, 14.5px).
   - **Recent visits panel** — `margin-top:auto`, fill `#F5F6EF`, `border:1px solid #E3E8D9`,
     radius 14px, `padding:16px 18px`. Micro-label `Recent visits`, then
     `VStack(spacing:9)` of 13.5px rows, each with a 26×26 radius-8px gradient chip
     (`gap:10px`) and a trailing mono 11px `#8B9482` date:
     - `#4E8F6A` over `#DDE7DA` — `“Fog dripping off the crown”` — `Oct 12`
     - `#8FB573` over `#E5EBD9` — `Watered, mulched` — `Sep 28`
     - `#C9B44A` over `#F0EDDB` — `“Cones everywhere this year”` — `Sep 14`

**Affordances:** `Open in the app` deep-links; `Share this tree` re-shares; `Sign in` and the four
nav items are drawn but **NOT SPECIFIED** as to destination. No account is needed to read the page.

---

## 4. Page-level chrome of the spec document itself

Not app UI, but transcribed for completeness since it defines the brand surface.

- **Header** (`id="page-top"`): logo PNG + `Cypress` (Serif 30px/600, `line-height:1.1`) +
  `Screens · summer 2026` (mono 11px, `.12em`, uppercase, `#77836F`, `margin-top:3px`).
  `padding-bottom:32px`, `border-bottom:1px solid #D8D4C4`, `gap:18px`.
- **Palette panel** and **Type panel** — §1.1 / §1.3, both `background:#F7F5EC`,
  `border:1px solid #DDD9C9`, `border-radius:18px`, `padding:28px 30px`.
- **"On this page" nav** — mono eyebrow `On this page` + five links, each a mono index
  (12px, `#8B9482`, `min-width:52px`) + a 15px `#3C4A3E` label, `gap:14px`, hover `#1D4634`:

  | Index | Label | Target |
  |---|---|---|
  | `01–06` | `Six screens that carry the whole loop` | `#sec-loop` |
  | `07–13` | `The flows behind the first screen` | `#sec-flows` |
  | `14–19` | `Built for day one and muddy hands` | `#sec-field` |
  | `D1–D3` | `Dark mode, same forest` | `#sec-dark` |
  | `W1` | `Every tree gets a page worth sending to a friend` | `#sec-web` |

- **Figcaption pattern** — 13.5px, `#66735F`, `line-height:1.55`; the `<b>` headline is a block,
  Serif 16.5px/600, `#1C2A21`, `margin-bottom:3px`, and starts with a mono 11px `#2F6B4F`
  `letter-spacing:.08em` index followed by ` · `.
- **Footer** — `margin-top:80px`, `padding-top:24px`, `border-top:1px solid #D8D4C4`,
  `gap:28px`, mono 10.5px, `.1em`, uppercase, `#8B9482`:
  `Cypress · a concept sketch` · `Seeded with SF's ~125,000 street trees` · `Summer 2026`
- **Responsive rules in the file:** below 700px the page padding drops to `36px 16px 90px`;
  device figures scale via `zoom` at `.8` (≤460px), `.73` (≤394px), `.65` (≤345px); W1 becomes
  horizontally scrollable.

---

## 5. Gaps — things a SwiftUI build must decide

Marked **NOT SPECIFIED** in the source file:

1. **Navigation transitions and animation curves.** The README lists prototype animations
   (`czFade` .32s, `czSheet`, `czPinDrop`, `czPulse` 2.4s, `czFlash`, `czPop`, easing
   `cubic-bezier(.22,.9,.3,1)`), but *this* spec file contains none of them.
2. **Pressed / disabled / focus states** for every button and chip. The README notes hover raises
   cards and shifts borders to `#2F6B4F`, and primary buttons darken `#1D4634`→`#2F6B4F`; the
   spec file only declares `style-hover="color:#1D4634"` on spec-page links.
3. **Icons for `Favorite` / `Care` / `Share` / `Report`** (C8) — text only.
4. **Toggle off state** (C25), **checkbox unchecked state** (15).
5. **Empty states** for: outbox with nothing queued, grove with no trees, map with no GPS.
6. **Photo timeline / gallery** reached by tapping a hero photo.
7. **Search results screen** behind C20.
8. **"Link copied" confirmation** and the editable blurb on 10 (present in the prototype per the
   README, absent here).
9. **Post-shutter review UI** and the disabled `Log visit` state on 04.
10. **The "sure about that?" anomaly confirmation** on 16 — described in copy only.
11. **Scroll behavior:** every screen is drawn at a fixed 812/874px with `overflow:hidden`. Several
    (05, 07, 12, 13, 16, 17) clearly exceed one viewport in a real build; the caption on 05 calls it
    "One scrollable card". Treat everything below the header as scrollable content with a pinned CTA
    where `margin-top:auto` is used.
12. **Accessibility:** no Dynamic Type ramp, no contrast pairs, no VoiceOver labels are given. The
    mono micro-labels at 9–10px with wide tracking will need a Dynamic Type strategy.
13. **Real photography** — every image here is a CSS gradient placeholder (§C22).
