# Errata pending — a red-proof that renumbers a migration bricks the simulator (R79 / v22, 2026-09-10)

Unnumbered, per CLAUDE.md "Numbering and shared files". Measured this round while red-proving
`AppSchema` v22, and it cost about an hour of a UI suite pointed at a defect that did not exist.

---

### E??? — A red-proof that changes a migration's **version number** leaves the simulator's database ahead of every later build, and the symptom is every UI test failing with no crash

`SchemaV22Tests.aV21DatabaseRunsOnlyV22` asserts that a v21 database applies exactly `[22]` and that
`AppSchema.currentVersion` is 22. The cheapest way to red-prove it is to renumber the migration:

    Migration(version: 22, name: "a city record's data can be disputed…", migrate: applyV22)
    →
    Migration(version: 23, …)

The test goes red with the message you want — `(applied → [23]) == ([Self.version] → [22])` — and the
revert is one character. What is not obvious is that **the unit-test run that produced that message
also migrated the app's real, persisted database to `user_version = 23`**, because `CypressTests` is
hosted by the app and the app boots against
`…/Library/Application Support/Cypress/cypress.sqlite` in its simulator container. The in-memory
stores every schema test uses are not the only database the run touches.

After the revert, every build knows migrations up to 22 and that file says 23. `SchemaMigrator`
refuses with `MigrationError.databaseIsAhead`, which is correct and is the whole point of that
check — a build must not open a database a newer build wrote. The app therefore never finishes
booting, and:

- **the unit suite stays green**, because it uses in-memory databases built from the ladder;
- **every UI test fails**, and none of them says why. The messages are `the Map tab never appeared in
  the accessibility tree at all within 30s`, `screen 01 drew no tree pins in thirty seconds, which it
  does with a fix and without one`, `the photo browser never opened`, `Failed to get matching
  snapshots: Timed out while evaluating UI query` — the whole suite, at 30 s a piece;
- **there is no crash report**, because nothing crashed;
- **`run_tests.sh`'s preflight passes cleanly** — right device, right worktree, no concurrent
  `xcodebuild`, `installed-cities=none`, a camera within the device's width with seed trees under it.

So the log's own provenance header is clean and the failures read exactly like a real, broad
regression in the branch under test. This is the same family as the memory note "user_version N but
build knows up to M = fossil install, not a bug", arriving from a new direction: nobody installed an
old build here, and the fossil was created by the red-proof itself, minutes earlier, in the same
session.

**The tell, and it takes ten seconds:**

    C=$(xcrun simctl get_app_container <udid> app.cypress.Cypress data)
    sqlite3 "$C/Library/Application Support/Cypress/cypress.sqlite" 'PRAGMA user_version'

If that number is greater than `AppSchema.currentVersion`, the branch is not what is failing.

**The fix** is `xcrun simctl uninstall <udid> app.cypress.Cypress`, which takes the container with
it. Note that this also wipes the camera privacy grant, which the unit suite hangs forever without —
re-grant it after the next install, and not while a test is running (`grant` kills the running app).

**How to avoid it.** Red-prove the version claim by breaking something that is not the version
number where you can — the fixture's expectations, or a different assertion in the same test. When
the number itself is what has to move, treat the simulator as dirty afterwards and uninstall before
running anything that launches the app for real. A red-proof is a deliberate defect, and this one
outlives the file you reverted.
