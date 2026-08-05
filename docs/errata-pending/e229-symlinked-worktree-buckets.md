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
`.resolvingSymlinksInPath()`. **This does not do what it sounds like it does, and the collapse it
performs is conditional on the path existing — not a string rewrite.** Verified directly before
trusting it, with a path that exists and one that does not:

```swift
URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path    // → "/tmp"            (exists — collapses)
URL(fileURLWithPath: "/private/tmp/x").resolvingSymlinksInPath().path  // → "/private/tmp/x"  (does not exist — untouched)
URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path            // → "/tmp"            (already short)
```

`.resolvingSymlinksInPath()` does not resolve `/tmp` outward to `/private/tmp`; per Apple's
documented behavior it does the opposite — it strips a leading `/private` back off, but only when
the shorter path still names something real on disk (the collapse is a `stat`, not a string
rewrite, which is why the fabricated `/private/tmp/x` above survives unchanged). That precondition
is what makes the fix safe: `repositoryRoot()` and every enumerated file URL name real files the
process just read, never a hypothetical path, so the collapse always fires for them. So the fix
does not make every path say `/private/tmp/…`; it converges every path (root and enumerated alike)
onto the *short* `/tmp/…` spelling. Which spelling wins was never the point — only that both sides
of the prefix arithmetic agree on the same one, whichever it is.

**Two rounds of getting this wrong, both left here so the next reader does not repeat either.**
First, an initial draft of the fix comments asserted the wrong *direction* — claimed resolving would
produce `/private/tmp` throughout — before this was checked against a standalone `swift` script:
`resolvingSymlinksInPath()` shortens, it does not lengthen. Second, the corrected draft's own worked
example (`"/private/tmp/x" → "/tmp/x"`) was itself run through PR review and found false as literally
written: `x` names nothing, the collapse is existence-gated, and the actual output of that exact line
is `"/private/tmp/x"`, unchanged. The general claim was right; the specific example asserting it
wasn't one anybody had run. Fixed by re-verifying the exact committed example against a fresh
`swift` process rather than trusting that a plausible-looking path would behave like the ones
already checked — CLAUDE.md's "calibrate the instrument" rule, twice in one comment.

### The fix was incomplete on first landing — a second real defect the reviewer found

The comment above named the vulnerable *pattern*
(`replacingOccurrences(of: root.path + "/", …)`) but the PR that introduced it only fixed
`PendingCitationGuard.sourceFiles` — `AppSourceLiterals.sourceFiles(root:)` still returned raw,
unresolved `FileManager` enumerator URLs, and three call sites computed a relative path with
exactly the named pattern against them:

- `BritishSpellingGuardTests.everyAppStringLiteralIsAmerican` (reads `AppSourceLiterals.sourceFiles`)
- `DrawnGlyphGuardTests.theAppBorrowsNoGlyphs` (same)
- `WorkflowShellQuotingTests.noAccidentalCommandSubstitution`, over its own separately-unresolved
  `workflowFiles(root:)`

**`replacingOccurrences` does not fail safe here.** It matches a substring anywhere, not only at
the start, so an unresolved `root.path + "/"` (`/tmp/…/`) is still found *inside* a resolved
`file.path` (`/private/tmp/…/`) — one component in from the front, right where the `/private` that
made them differ ends — and that inner match is removed. What survives is the leading `/private`
the match started after, glued directly to whatever text followed the match. Reproduced against
this worktree's own, real `Cypress/App/CypressApp.swift`:

```
BEFORE fix: /privateCypress/App/CypressApp.swift
AFTER fix:  Cypress/App/CypressApp.swift
```

Not a relative path, and not the untouched absolute path either — a third, worse shape, because
it reads as *almost* a relative path. Nothing was red for this on first landing: the three scans
downstream of these paths currently find zero real violations, so there was no offender's `file:line`
for the corruption to show up in. It would have appeared the day any of them found one, in exactly
the scratchpad-worktree environment this ticket is about — the PR's original claim that fixing
`repositoryRoot()` "covers `BritishSpellingGuardTests`' own sweep too — same root function" was true
of the *root* and false of the *enumeration*, which is a separate function per call site.

**Fixed by resolving symlinks on the enumerated URLs too**, mirroring
`PendingCitationGuard.sourceFiles`: `AppSourceLiterals.sourceFiles(root:)` and
`WorkflowShellQuotingTests.workflowFiles(root:)` both now call `.resolvingSymlinksInPath()` on
every URL the enumerator returns, not only on the root. Swept both test targets afterward for any
other instance of the class (`grep` for `replacingOccurrences(of:.*\.path` and
`dropFirst(.*\.path.*count`, and for any other `FileManager.default.enumerator` call): two more
directory reads exist (`UITestShardCoverageTests.declaredUITestClasses`,
`DragGestureGateTests.uiTestSources`), both via `contentsOfDirectory(at:)` rather than a deep
enumerator, and neither computes a relative path by prefix arithmetic — one reads class names out
of file *contents*, the other uses `url.lastPathComponent` alone. Not vulnerable to this class; left
unchanged.

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
did not regress any of them. Re-run identically, same worktree, after the review round's fix to
`AppSourceLiterals.sourceFiles` and `WorkflowShellQuotingTests.workflowFiles`: the same seven suites,
same `Test run with 20 tests in 7 suites passed`. `Tools/verify_test_log.sh --warnings` reported
`source=0` on every touched file across both rounds
(`CypressTests/PendingCitationGuardTests.swift`, `CypressTests/BritishSpellingGuardTests.swift`,
`CypressTests/WorkflowShellQuotingTests.swift`).

### Cross-reference

Filed after the investigation that produced ERRATA E215 (#219) surfaced this as an unrelated,
pre-existing failure — see that entry's fix note for the control-worktree comparison that first
isolated it to the path rather than the code.
