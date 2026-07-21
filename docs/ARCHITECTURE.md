# Cypress iOS — architecture

This is the contract every contributor (human or agent) reads before writing a line of Swift.
It sits *below* the product documents in authority. Precedence:

```
BUILD-PLAN.md  >  SPEC-PHASE1.md  >  DESIGN.md          (product & data)
docs/distilled/DECISIONS.md                              (binding, D1–D15)
docs/distilled/SCREENS.md                                (visual truth)
docs/ARCHITECTURE.md  (this file)                        (how we build it in Swift)
```

Where this file and BUILD-PLAN.md disagree on *product*, BUILD-PLAN wins. Where they disagree on
*iOS implementation*, this file wins, because BUILD-PLAN was written for a React Native codebase
that we are not building.

---

## 1. The one sanctioned deviation from BUILD-PLAN §3

BUILD-PLAN §3 says its stack table is "decided, not suggestions. Do not substitute without a
written reason." This is the written reason.

| BUILD-PLAN §3 | What we build | Why |
|---|---|---|
| Expo (React Native), TypeScript, expo-router | **Native iOS: Swift, SwiftUI, iOS 17+** | The project owner commissioned a native iOS app. The handoff README itself lists SwiftUI as an appropriate target. The design leans hard on three custom type families, a 30 %-opacity camera ghost overlay, and six named animation curves — all cheaper and better native. |
| MapLibre GL + self-built PMTiles via tippecanoe | **MapKit** with a custom-styled overlay set | The stated reason for MapLibre was "No Mapbox account, no per-seat licensing." MapKit satisfies that constraint identically, at zero infrastructure cost, and removes the tile-generation pipeline from the critical path. If the abstract basemap in the mocks becomes a hard requirement, MapLibre Native remains a drop-in behind `MapCanvas`. |
| Fastify + Postgres/PostGIS backend | **Local-first, behind a protocol** (§4) | No backend exists yet. See §4 — the boundary is drawn so the server can arrive without touching a single view. |
| Local store: expo-sqlite | **SQLite via GRDB** | Same engine, same outbox design, idiomatic Swift. |

Everything else in BUILD-PLAN — the data model in §4, the API contract in §6, the ingest spec in §7,
the privacy spec in §10, the ambiguity resolutions in §11, and the "what a coding agent should not
do" list in §15 — is **unchanged and binding**.

## 2. Project layout

A single app target. Files are picked up by an Xcode 16 **synchronized root group**, so adding a
`.swift` file anywhere under `Cypress/` compiles it automatically.

> **Never hand-edit `Cypress.xcodeproj/project.pbxproj`.** There is no reason to. Adding, moving,
> or deleting files under `Cypress/` requires no project change. If you believe you need a project
> change, stop and ask.

```
Cypress/
  App/            CypressApp, RootView, AppRouter, DI container
  Core/           Pure domain. No SwiftUI, no GRDB, no MapKit imports.
    Models/       Tree, Species, Visit, Observation, CareEvent, Measurement, Photo…
    Units/        Quantity + Method — every number carries its method (D7)
    Rubric/       The anchored 5-class vitality scale (D3)
  Data/
    Store/        GRDB schema, migrations, DAOs, the bundled seed importer
    Outbox/       Local-first mutation queue + retry policy
    API/          CypressAPI protocol (§4) and LocalAPI, the on-device implementation
  DesignSystem/
    Tokens/       Color, Typography, Radius, Shadow, Spacing — from SCREENS.md §1
    Components/   C1–C30 from SCREENS.md §2, built once, used everywhere
  Features/       One folder per screen group; a folder owns its views + view model
  Resources/      Info.plist, Assets.xcassets, Fonts/, seed database, species YAML
Fixtures/         Seed source data + generated seed DB (build inputs, not app source)
Tools/            Python scripts that produce Fixtures/ — reproducible, checked in
docs/             This file, plus docs/distilled/*
```

**Import discipline.** `Core` imports Foundation only. `Data` may import Core and GRDB. `DesignSystem`
may import SwiftUI and Core. `Features` may import everything. Nothing imports `Features`.

## 3. State and concurrency

- Swift 5 language mode on the Swift 6.1 compiler. We are not adopting strict concurrency checking
  yet; it would cost more than it buys on a codebase this young with this many parallel authors.
- View state uses `@Observable` (Observation framework, iOS 17). Not `ObservableObject`.
- One `@Observable` model per feature folder, owned by the feature's root view via `@State`.
- Shared services (`CypressAPI`, `Outbox`, `LocationProvider`) are passed through the SwiftUI
  environment from a single composition root in `App/`. No singletons, no `.shared`.
- All I/O is `async`. Anything touching the database or the outbox is `await`ed. UI types are
  `@MainActor`; `Data` types are actors or are called from a background context explicitly.

## 4. The backend boundary

Every read and write the UI performs goes through one protocol, `CypressAPI`, whose method set
mirrors BUILD-PLAN §6 endpoint for endpoint. There are two implementations:

- `LocalAPI` — what ships today. Reads the bundled SF seed database, writes to local SQLite, and
  drains the outbox into that same local store. The app is fully functional with no network.
- `RemoteAPI` — a stub today. When the Fastify service exists it implements the same protocol
  against `/api/v1`, and `LocalAPI` becomes the offline cache behind it.

Consequences that are not optional:

- **No view, and no feature view model, may touch GRDB or the network directly.** If a screen needs
  data, the protocol grows a method.
- Errors surface as the BUILD-PLAN §6 taxonomy — `unauthorized, forbidden, not_found,
  validation_failed, conflict, moderation_rejected, rate_limited, server_error` — each carrying
  `retryable: Bool`. Model this as a Swift `enum APIError`, not as strings.
- Every mutation is idempotent on a client-generated `clientUUID`, written to the outbox *first*,
  and only then attempted against the API. This is true even though the API is currently local:
  the outbox is the feature, not a network workaround.

## 5. Rules that come from the product, not from taste

These are lifted from DECISIONS.md §3 and BUILD-PLAN §15 because they are easy to violate by
accident while writing UI code. The full list is binding; these are the ones that bite in Swift:

1. No streaks, points, ranks, badges, or public counts of user actions. If you find yourself writing
   `visitCount` into a user-visible string, stop.
2. A quantity without a `method` does not compile. `Quantity` has no initializer that omits it (D7).
3. Estimated and measured series are never one series in a chart (D7).
4. Never render "sent to the city" copy. The honest state is "the city has not been notified."
5. Evergreen species never get fall-color chips or autumn strip colors — the chip set derives from
   `species.leafRetention` (D5). That attribute is **optional**: 59 of the 569 seeded species have
   no sourced habit, and a species with `leafRetention == nil` gets *no* phenology surface at all —
   not a neutral chip, not a grey one, nothing (ERRATA E9). Never write `?? .deciduous` or any other
   default; a default is the bug.
6. Aggregate surfaces below their cold-start threshold do not render at all. "Caretakers" needs ≥3.
7. Copy: **no spaces around em dashes** (`trees—memorials`). Micro-labels are uppercase mono with
   letter-spacing; prose is sentence case. Dates read "Summer 2026".
8. When a screen or state is not in `SCREENS.md` or BUILD-PLAN §9, **stop and ask**. Do not invent it.

## 6. Design system

`SCREENS.md` §1 is the token source and §2 is the component catalogue (C1–C30). Rules:

- Never write a raw hex or a raw font size inside a feature. Use `CypressColor.*`, `CypressFont.*`,
  `CypressRadius.*`, `CypressShadow.*`. A literal in `Features/` is a bug.
- Both light and dark are first-class. SCREENS.md documents dark as a delta (D1–D3); tokens carry
  both values and resolve off the environment color scheme. Screen 04 (camera) is dark always,
  regardless of system setting.
- Tap targets ≥44 pt. The design's own critique flagged sub-30 pt thumbnails; where the mock and
  accessibility disagree, the target grows and the *visual* stays put via `contentShape`.
- Dynamic Type: the ramp is fixed-size in the mocks. Use `.custom(_:size:relativeTo:)` so text still
  scales, and verify the field screens at AX1.

## 7. Testing

- `Core` and `Data` are unit tested with Swift Testing (`import Testing`), not XCTest.
- Two tests are acceptance gates, ported from BUILD-PLAN §13:
  - **Outbox chaos**: 20 queued mutations across scripted failures; assert zero loss, zero
    duplicates on `clientUUID`, correct per-item terminal states.
  - **Seed contract**: the bundled seed database's schema and row invariants are pinned; a diff
    fails the test.
- Schema invariants from §13 that apply on device: no numeric observation without method metadata;
  no evergreen species carrying `fallColorMonths`.
- Snapshot-testing the screens against the mocks is explicitly *not* set up yet. Visual verification
  is by running the app in the simulator and comparing to `SCREENS.md`.

### Building while others are building

Most of this codebase is written by parallel agents, and Xcode's build system takes a lock on its
build database. Two `xcodebuild` invocations sharing the default DerivedData will block each other,
and a blocked build looks exactly like a failed build to whoever is waiting on it — which is how a
correct change gets "fixed" until it breaks.

So **always build into your own DerivedData**:

```
xcodebuild -project Cypress.xcodeproj -scheme Cypress \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/cypress-build-<your-task-name> \
  -configuration Debug build
```

The first build there is cold and slow. That is the price of not corrupting someone else's.

## 8. Milestones

Mapped from BUILD-PLAN §12, minus everything that was about the server.

| | Scope | Done when |
|---|---|---|
| **M0** | Walking skeleton | App launches on the seeded SF inventory; map renders clustered real pins; one tree profile loads from the seed; a visit round-trips through the outbox and appears on that tree's timeline after relaunch. |
| **M1** | The core loop, screens 01–06 | Map, what-tree-is-this, profile, camera visit with ghost overlay, light check-in with the five anchor rows, 311 redirect. Permission-denied states render as designed. |
| **M2** | One level deeper, screens 07–13 | Species pages, grove, care log, share, growth history, almanac, activity. |
| **M3** | In the field, screens 14–19 | Cold profile, account ask, measure sheet, outbox, next-tree, memorial. |
| **M4** | Dark mode + polish | D1–D3, animations, accessibility pass. |

The public web tree page (W1) and the coordinator dashboard are out of scope for the iOS app; they
are separate deliverables and are not built here.
