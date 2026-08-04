## E229 — a symlinked scratchpad path made `PendingCitationGuardTests` miscount two of three targets

**Found while investigating #219's aftermath**: `PendingCitationGuardTests.theGuardCanSeeTheSourceItClaimsToCheck`
was red in every scratchpad agent worktree and green on the main checkout and in CI. Confirmed
against a control worktree built straight from unmodified `origin/main` (same failure) versus the
main checkout at `/Users/…` (passes) and CI's runner (passes) — so the defect tracks the path, not
the code.

### The mechanism

`AppSourceLiterals.repositoryRoot()` (`CypressTests/BritishSpellingGuardTests.swift`) derives the
worktree root from `#filePath` — whatever spelling the compiler was invoked with. In a scratchpad
worktree that lands under `/tmp/…`, that spelling is `/tmp/…`. `/tmp` is a macOS symlink to
`/private/tmp`, and `FileManager`'s enumerators hand back the unsymlinked `/private/tmp/…` spelling
regardless of what was asked for. So `PendingCitationGuard.sourceFiles` built `directory` from the
`/tmp/…` root and then computed each file's repo-relative path as
`url.path.dropFirst(directory.path.count)` — dropping a character count measured against the
*short* spelling from a path written in the *long* one, eight characters short.

`"/Cypress"` is exactly eight characters — the same length as the un-dropped `"/private"` — so that
target's bucket key survived the miscount by coincidence: `CypressTestsessTests` and
`CypressUITestssUITests` are what `CypressTests` and `CypressUITests` become instead, and neither
matches any key `theGuardCanSeeTheSourceItClaimsToCheck` asserts a floor against, so both were
silently counted as zero. The *citation scan* itself (`everyCitationNamesADocumentAReaderCanFind`)
was never compromised — it reads `file.url`, the absolute (correct) URL, not the mangled `relative`
label, and iterates the full flat list regardless of per-target bucketing. That is why only the one
test was ever red.

### The fix, and the one thing worth flagging for whoever reads this next

Both `AppSourceLiterals.repositoryRoot()` and `PendingCitationGuard.sourceFiles` now call
`.resolvingSymlinksInPath()`. **This does not do what it sounds like it does.** Verified directly
before trusting it:

```swift
URL(fileURLWithPath: "/private/tmp/x").resolvingSymlinksInPath().path  // → "/tmp/x"
URL(fileURLWithPath: "/tmp/x").resolvingSymlinksInPath().path          // → "/tmp/x"
```

`.resolvingSymlinksInPath()` does not resolve `/tmp` outward to `/private/tmp`; per Apple's
documented behavior it does the opposite — it strips a leading `/private` back off whenever the
shorter path still names the same file. So the fix does not make every path say `/private/tmp/…`;
it converges every path (root and enumerated alike) onto the *short* `/tmp/…` spelling. Which
spelling wins was never the point — only that both sides of the prefix arithmetic agree on the same
one, whichever it is.

An initial draft of the fix comments asserted the wrong direction (claimed resolving would produce
`/private/tmp` throughout) before this was checked against a standalone `swift` script. Left here so
the next reader does not have to re-derive it: **`resolvingSymlinksInPath()` shortens, it does not
lengthen** — a case CLAUDE.md's "calibrate the instrument" rule exists for.

### Verification

Red, in a scratchpad worktree at the unfixed commit (`Tools/run_tests.sh`, `-only-testing:
CypressTests/PendingCitationGuardTests`):

```
✘ Test "the guard swept all three targets, not one of them" recorded an issue at
  PendingCitationGuardTests.swift:172:13: Expectation failed: (swept → 0) >= (target.floor → 95)
↳ the guard swept 0 files under CypressTests/; that target held 107 at #189, so this is not it.
✘ Test "the guard swept all three targets, not one of them" recorded an issue at
  PendingCitationGuardTests.swift:172:13: Expectation failed: (swept → 0) >= (target.floor → 12)
↳ the guard swept 0 files under CypressUITests/; that target held 15 at #189, so this is not it.
```

A temporary diagnostic (not shipped) printed the flat, unbucketed sweep before and after the fix, to
confirm the citation scan's hit set was never touched by the bucketing bug:

```
before: E229-DIAG totalFiles=397 totalHits=0
after:  E229-DIAG totalFiles=397 totalHits=0
```

Identical — 397 files (263 + 115 + 19, matching the main checkout's on-disk counts) and zero
citation hits in both runs, confirming the fix changes only the per-target bucketing, not what the
scan finds.

Green, same worktree, after the fix: `Tools/verify_test_log.sh` reported
`VERIFY-OK: ✔ Test run with 20 tests in 7 suites passed` across `PendingCitationGuardTests`,
`BritishSpellingGuardTests`, `DrawnGlyphGuardTests`, `DeployPathsAgreeTests`,
`UITestShardCoverageTests`, `DragGestureGateTests`, `WorkflowShellQuotingTests` — every other caller
of `AppSourceLiterals.repositoryRoot()` in `CypressTests`, run as a group to confirm the shared fix
did not regress any of them. `Tools/verify_test_log.sh --warnings` reported `source=0` on both
touched files.

### Cross-reference

Filed after the investigation that produced ERRATA E215 (#219) surfaced this as an unrelated,
pre-existing failure — see that entry's fix note for the control-worktree comparison that first
isolated it to the path rather than the code.
