# Cypress — standing rules

Loaded automatically for every session and every subagent working in this repo. Every rule here
was paid for; the receipts are in `docs/investigations/repeat-failures-postmortem.md`. When a rule
conflicts with convenience, the rule wins.

## Documents
- `docs/ARCHITECTURE.md` (§2 import discipline, §5 mock fidelity, §6 tokens, §7 concurrency),
  `docs/ERRATA.md`, `docs/RULINGS.md`, `docs/ROADMAP.md`
- `docs/distilled/SCREENS.md`, `docs/distilled/DECISIONS.md`, `docs/distilled/PRODUCT.md`
  (they live in `docs/distilled/`, not `docs/`)
- `docs/errata-pending/`, `docs/rulings-pending/` — see **Numbering** below
- `docs/CONTRIBUTING.md` — how work lands on main; see **Branching and review** below

## Verification — this project's signature failure mode is false green
- Run tests with `Tools/run_tests.sh <udid> <log> [xcodebuild args…]`; judge any log with
  `Tools/verify_test_log.sh <log>`. Never conclude from an exit code: `nohup … &` returns the
  shell's success, a killed build leaves a truncated log under a wrapper claiming success, and a
  trailing `echo` in an `&&` chain lies.
- The only meaningful unit-test line is **`Test run with N tests passed`** (Swift Testing).
  `Executed 0 tests / All tests passed` is XCTest reporting on a suite it cannot see. UI tests
  (XCTest) need `** TEST SUCCEEDED **` **and** a nonzero executed count.
- **Never trust an artifact you did not watch being produced.** Before reading a log, screenshot,
  or build as evidence, check its mtime, its provenance (which build, worktree, simulator), and
  its content. Stale DerivedData, stale logs at a reused path, an uncommitted asset, an empty
  console capture, blank screenshots, and a location-declined simulator have each produced a
  false conclusion here.
- **A warning count only counts if the build compiled something.** Claim warnings only through
  `Tools/verify_test_log.sh --warnings <log> [files…]`, which refuses to certify a count from a
  build with zero `SwiftCompile` tasks, or one that did not compile the files named (E203). Build
  into a fresh DerivedData directory to measure — a reused one recompiles nothing and reports
  nothing, while a green test line survives it unchanged.
- Never write a conclusion before reading the output that supports it.
- Prove every new test can fail: break the code, watch red, restore. Assert presence, not
  absence; assert facts, not phrasing.
- **A red-proof must go red for the reason you expect — read the failure message, not just the
  colour.** Tests here have gone red on the wrong assertion, exempted the thing they were guarding
  as its own wrapper, and run their specimens before their rule under
  `continueAfterFailure = false`. Each looked like a passing red-proof.
- Look at the running screen; a green suite has ratified real defects here. Map performance and
  camera flows only tell the truth on the physical phone.
- Verify every merge by running the suite on the **merged** tree; a branch's green proves the
  branch, only the merged tree proves main.
- A green re-run proves a failure was intermittent, never why it happened.

## Simulators
- **The plain iPhone 16 is the owner's — keep it free.** Its UDID is deliberately not written
  here. You do not need it: never run against a device you were not assigned, and the four below
  are the whole set an agent may use.
  Agents use: 16 Pro `EA0AD796-3052-4EE5-A7A8-A1DE807A3653`, 16 Pro Max
  `DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`, 16e `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`,
  16 Plus `24D1629F-9FA8-4E3D-812E-F6BC85C9E668`.
- One simulator per agent, explicitly assigned. Cap **three** concurrent `xcodebuild`s
  machine-wide — orchestrator verification runs count against the cap.
- **A dead agent's `xcodebuild` keeps running**, and **the UI suite inherits the device's state**
  (E202, E216). `Tools/run_tests.sh` now refuses on all four: another `xcodebuild` live against the
  same simulator or worktree, a leftover `active-city` marker, a `map.lastCamera` too wide for that
  device's own screen, and a camera with **no seed tree within 250 m of it**. Do **not** hand-roll
  the collision check — `grep [x]codebuild` glob-expands under zsh, matches nothing, and passes
  vacuously; use `grep -F xcodebuild` if you inspect by hand.
  Keep reading E202 and E216 to interpret a red run: two runs on one device fake `Application … is
  not running`, `'X' never appeared` and `Test run with 0 tests` with no crash report; a wide camera
  draws cluster badges where a test waits for pins; and a narrow camera **pointed somewhere the
  inventory does not cover** draws nothing at all, which is the same symptom from the opposite
  geometry. Whether the device has a fix is still not checked — fixless is legitimate and #121's
  tests skip on it. **A UI log whose skip count changed between two runs of the same tree is
  reporting a device change, not a code change.**
- **Every log carries its own provenance** — `run_tests.sh` stamps `CYPRESS-RUN:` lines with the
  device, `screen-width-pt`, worktree, HEAD and both E202 states. Judge a width-sensitive UI result
  only from a log whose width you have read. A log with no `CYPRESS-RUN` header did not come from
  this script and its provenance is unknown.
- **A simulator can degrade silently, and its first symptom looks like a real defect** — a specific,
  plausible assertion failure in a test unrelated to your change, on a device whose E202 state is
  clean. The tell is only visible in aggregate: later runs on that device get worse, and a control
  at a known-green commit fails too. `xcrun simctl erase` fixes it. #183 records a case where two
  such failures were filed as a width defect that did not exist.
- Boot and wait for `Booted` before any `simctl` call; `simctl` against a Shutdown device fails
  quietly inside `&&` chains.
- Grant camera once per install (`xcrun simctl privacy <udid> grant camera app.cypress.Cypress`);
  the unit suite hangs forever without it, and an uninstall wipes the grant. Never re-grant on a
  timer — `grant` kills the running app mid-test.
- To make a device fixless, revoke the location privacy grant; `simctl location clear` does NOT
  unfix a device.
- `SQLITE_IOERR_VNODE` / fd-storm failures on the slowest test mean simulator contention, not
  your change — check `ps aux | grep xcodebuild` before theorizing.

## Known hangs (read like a stalled agent, are not)
- `#expect(dataA == dataB)` on two large `Data` values hangs in Swift Testing's diff — reduce to
  a `Bool` before the macro sees it.
- The unit suite hangs on a simulator that never granted camera access (see above).

## Numbering and shared files
- Never write a number into `docs/ERRATA.md` or `docs/RULINGS.md` from a branch or agent. Write
  the entry **unnumbered** to `docs/errata-pending/<topic>.md` or `docs/rulings-pending/`; the
  orchestrator splices it under the real next number at merge, then rewrites any code comments
  that cited the pending filename.
- A deliberate gap in the E/R sequence is a reservation for a live branch — never fill it.
- **Schema versions are the opposite: never reserved, never skipped.** One migration author per
  round, named explicitly. If your task turns out to need a migration, STOP and report.
- **There are two schema-version spaces and they now genuinely collide at 14.** The *writable*
  database's migration counter is `AppSchema.currentVersion` (`PRAGMA user_version`); the
  *published seed/city file* version is `SeedDatabase.newestKnownSchemaVersion` (R37's
  `s<schema_version>`). They are unrelated. **Read both from the code, never from this file** —
  this bullet claimed the writable one was 13 for a round after v14 landed, which is the confusion
  it exists to prevent. Say which one you mean, every time: four tickets sat "blocked on v14" for
  a week because one advanced and the other was assumed to have.
- Never `git add -A` on main; stage explicit paths — another agent's untracked work may share
  the checkout.
- A rename of a shared identifier breaks every other live branch even when correctly scoped to
  your ticket; announce it, and budget a compile-and-fix pass at merge.

## Branching and review
- **main cannot be force-pushed or deleted, by anyone, including the owner** (ruleset
  `main-guardrails`, no bypass actors — both rules red-proved with a control on 2026-08-03). There
  is no rewriting main: a bad commit is recovered *forward*, with a revert. Note that
  `git push --dry-run` does **not** evaluate rulesets — it reported success for a rewind the server
  then refused, so a dry run is not evidence here either.
- **Today, work still lands on main directly**, under the unchanged merge protocol: merge locally,
  run the suite on the **merged** tree, certify warnings on a **fresh** DerivedData, then push.
- **After the beta lock (#187), every non-doc change ships as a PR** reviewed adversarially by an
  agent that did not write it — protocol and beta-lock checklist in `docs/CONTRIBUTING.md`. The
  owner throws that switch; no agent throws it or assumes it has been thrown.
- **Do not read this file to find out which regime is running** — prose goes stale, which is the
  whole lesson of the schema-version bullet above. Ask GitHub:
  `gh api repos/PlatosTwin/cypress/rulesets --jq '.[] | "\(.name)\t\(.enforcement)"'`.
  `main-pull-request-only → disabled` means direct-to-main; `→ active` means PRs only.

## Working in a worktree (agents)
- Set up with `Tools/setup_worktree.sh <worktree-path>` — it copies the git-ignored ~103 MB seed
  into `Cypress/Resources/` and `Fixtures/seed/`; without it 13 tests fail on `seedURL → nil`
  and you will chase a defect you did not cause.
- **Commit continuously.** Limit deaths take every agent at once and a stall with uncommitted
  work is the only way work is lost here.
- Use a private DerivedData directory named for yourself (`<scratchpad>/dd-<your-suffix>/`).
  The scratchpad is shared by every agent: never `rm -rf` at its root, and never reuse another
  run's log path — `rm -f` your own log before each run.
- **Run `Tools/run_tests.sh` in the foreground and wait for it.** Do not background it, and never
  end your turn "waiting for a monitor" — a monitor is not a process, nothing will wake you, and
  an agent that stops waiting for one has simply stopped. If you must wait on a pid you already
  have, use a bounded foreground watcher (`for i in $(seq 1 40)`, not `until`), print a line each
  iteration, and kill the previous watcher before starting a new build.
- Never edit `Cypress.xcodeproj/project.pbxproj` — the tree is a
  `PBXFileSystemSynchronizedRootGroup`.
- **Facts in your brief may be wrong.** Agents have correctly refuted brief premises many times.
  Verify each premise against the code or seed before building on it; refusing a false premise
  is doing the job right.

## Code
- Swift 5 language mode on Swift 6.1, SwiftUI, iOS 17+, zero external dependencies,
  zero-warning line (app **and** test targets).
- `Core` is pure Foundation; `Data` imports no UI framework; `Features` may import anything
  (ARCHITECTURE §2).
- No raw hex, font sizes, or radii — tokens only (§6). No SF Symbols (policy; the five legacy
  sites are ticketed, #130). American spellings: favorite, color, center, neighborhood.
- `CypressTests` is Swift Testing; `CypressUITests` is XCTest.
- A confident comment is where bugs have survived here. Never assert an invariant in a comment
  you have not verified; a comment is not a test. Cite errata by number, never by pending
  filename.
- Do not invent botanical or civic content (DECISIONS constraint 15). A screen or state not in
  the mocks is a stop-and-ask (constraint 21).
