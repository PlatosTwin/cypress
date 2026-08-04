## E215 — fixed: one photo visibility predicate, asked once (#219)

**Appends to the existing ERRATA E215 entry** ("The hero pill and the photo browser filter the
same series by two different rules"). Not a new number — the orchestrator should fold this under
E215 at merge, not splice a fresh entry.

### What E215's premises checked out as

Verified against the code before building, per E215's own instruction and CLAUDE.md's "facts in
your brief may be wrong":

- Both sites really do read the same `TreeProfile.photos` series from `LocalAPI.treeProfile(id:)`
  — confirmed.
- The two predicates really did disagree in mechanism exactly as E215 describes —
  `TreeProfilePresentation.visiblePhotos` (own-aware: `isOwnPhoto(photo) ? isVisibleToItsContributor
  : isPubliclyVisible`) versus `TreePhotosModel.load()` (own-blind: `isVisibleToItsContributor`
  alone) — confirmed by reading both sites directly.
- They agree today only because `LocalAPI` sets `ownPhotoIDs` to every row it returns (no sync
  exists) — confirmed in `LocalAPI.swift`.
- **One premise the errata did not name, found while building:** a *third* site duplicated the same
  own-aware predicate inline — `MemorialPresentation.init` (screen 19), one line, byte-for-byte the
  same ternary as the hero's. It was not named in E215 and was not itself a live disagreement (its
  own copy was correct), but it was a second place the rule could drift from the hero's the next
  time either was touched. Folded into the same fix rather than left as a second unification still
  owed.

### The repair

One predicate, moved to `TreeProfile` in `Cypress/Data/API/CypressAPI.swift` (Data layer — the
predicate reads only `Photo.isVisibleToItsContributor` / `Photo.isPubliclyVisible` (Core) and
`TreeProfile.isOwnPhoto` (Data), so it needs nothing Data may not import per ARCHITECTURE §2):

- `TreeProfile.isVisibleOnDevice(_:)` — the predicate itself.
- `TreeProfile.visiblePhotos: Series<Photo>` — `photos.filter(isVisibleOnDevice)`, preserving the
  series' completeness (`Series.filter`).

All three sites now read it instead of restating it:

- `TreeProfilePresentation.visiblePhotos` → `profile.visiblePhotos`.
- `TreePhotosModel.load()` → `photos = profile.visiblePhotos.items` (was
  `profile.photos.items.filter(\.isVisibleToItsContributor)` — the own-blind filter E215 names).
- `MemorialPresentation.init` → `profile.visiblePhotos` (was the same inline ternary as the hero's,
  now a read instead of a second copy).

### The test

`CypressTests/PhotoVisibilityParityTests.swift` — one payload (`ownPhotoIDs` naming one of three
photographs, the other two somebody else's, one pending and one approved), read once by both
`TreeProfilePresentation.visiblePhotos` and `TreePhotosModel.load()` through a stub `CypressAPI`.
Asserts the two sets are equal, and separately pins the named defect: a stranger's `.pending`
photograph must not reach the browser even though it is visible on its own contributor's device.

**Red-proof.** Reverted `TreePhotosModel.load()` to the pre-fix filter
(`profile.photos.items.filter(\.isVisibleToItsContributor)`) and re-ran
`PhotoVisibilityParityTests` alone. Two of the four tests failed, both for the guarded reason:

```
✘ Test "a stranger's unmoderated photo does not reach the browser, even though it reaches its own
  contributor's device" recorded an issue at PhotoVisibilityParityTests.swift:156:9: Expectation
  failed: !((model.photos.map(\.id) →
  [E2150000-0000-4000-8000-0000000000A1, E2150000-0000-4000-8000-0000000000A2,
   E2150000-0000-4000-8000-0000000000A3]).contains(Self.strangersPending.id →
  E2150000-0000-4000-8000-0000000000A2) → true)
↳ screen 20 showed a stranger's unmoderated photograph — the exact failure ERRATA E215 names

✘ Test "the hero and the browser agree on exactly the same set of photographs" recorded an issue at
  PhotoVisibilityParityTests.swift:116:9: Expectation failed: (browserIDs →
  [E2150000-0000-4000-8000-0000000000A3, E2150000-0000-4000-8000-0000000000A1,
   E2150000-0000-4000-8000-0000000000A2]) == (heroIDs →
  [E2150000-0000-4000-8000-0000000000A1, E2150000-0000-4000-8000-0000000000A3])
↳ screen 20 ([…A3, …A1, …A2]) and the hero ([…A1, …A3]) disagreed on the tree's own photo set
```

The other two tests in the suite (own pending photo reaches the browser; a stranger's *approved*
photo reaches the browser) stayed green on the broken code, which is the expected shape — this
regression only shows up on the one row moderation had not cleared. Restored the fix afterward;
`Tools/verify_test_log.sh` on the re-run reported `Test run with 42 tests in 5 suites passed`.

### Verification

`Tools/verify_test_log.sh --warnings` against a fresh DerivedData build reported `source=0` across
the five touched files (`CypressAPI.swift`, `MemorialPresentation.swift`, `TreePhotosModel.swift`,
`TreeProfilePresentation.swift`, `PhotoVisibilityParityTests.swift`), `compile-tasks=430`.

Full `CypressTests` run on that same build: `1191 tests in 118 suites`, one failing —
`PendingCitationGuardTests.theGuardCanSeeTheSourceItClaimsToCheck` ("the guard swept all three
targets, not one of them"). **Confirmed pre-existing and unrelated**: reproduced identically
(`swept → 0` for `CypressTests` and `CypressUITests`) on a clean `origin/main` control worktree with
none of this branch's changes present. Not touched here — out of scope for #219/E215, and worth its
own ticket (`AppSourceLiterals.repositoryRoot()` / `PendingCitationGuard.sourceFiles` appear not to
resolve the worktree root correctly for `CypressTests`/`CypressUITests` under some condition this
did not chase down).
