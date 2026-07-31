# Repeat failures across this project's sessions — a postmortem

*Written 2026-07-31 at the owner's request, after they observed a pattern of "this burned us
again" messages and asked whether the cause is the orchestrator or the guardrail system. Method:
five subagents mined the full conversational text of all three session transcripts (~1.6 MB after
stripping tool output) for every incident, every admitted repeat, and every process correction the
owner made. This file is the synthesis; the per-chunk catalogs list ~90 distinct incidents.*

## The verdict

Both, but not equally, and the split is measurable. Sorting every guardrail this project has
written by **how it is enforced** produces a clean result:

**Rules enforced by a mechanism — a test, a script, a file convention, a structural
arrangement — essentially did not recur.**

| Mechanized guardrail | Recurrences after adoption |
|---|---|
| Reserve an errata number by *skipping* it in the merged file | 0 — held across four spend-limit deaths, two expired transcripts, and a worktree handover |
| Agents write errata **unnumbered** to `docs/errata-pending/` | 0 collisions after adoption (four collisions in one day before it) |
| Commit every worktree before stopping/resuming anything | Saved otherwise-lost work at least three times, including one agent whose entire run was uncommitted |
| Verify every merge on the **merged** tree | Caught two real breaks on 2026-07-31 alone |
| Prove every new test can fail (break-test) | Caught at least five tests that could not fail, including two guards that stayed green with the defect reinstated |
| The structural VoiceOver harness | Caught E110's exact defect class reintroduced in brand-new code |
| The six D9 `AccountAskTests` | Caught the R4 gate placed in the wrong layer before it shipped |
| The one *narrow, checked-at-moment-of-use* memory note (SVG data URIs block artifact sharing) | 0 — never repeated |

**Rules enforced by remembering them at the right moment recurred two to five times each —
several of them violated by their own author, in writing, on the same day they were written.**

| Recall-enforced rule | What happened |
|---|---|
| "Exit codes and green lines lie — check log content and mtime" | Hit at least **five** times; **twice after** it was carried-forward lesson #1 in every compaction summary (`nohup … &` exit 0; killed-build truncated log; `&&`-chain `echo granted` after three failed `simctl` calls; heredoc failure with the chained `git rm` running anyway; Monitor pattern matching an unrelated line) |
| "Agents must not write to `docs/ERRATA.md`" (memory note) | Ignored **four times the same day**: *"My own memory note already said agents must not write to ERRATA.md, and I ignored it"* — and the note itself records *"that failed four times on 2026-07-25 … even after I wrote this line and then ignored it"* |
| Cap at three concurrent xcodebuilds | Violated by the author: *"I have a note warning me about exactly this — and I violated it by treating my own verification runs as free"* — nine hung builds, found by the owner, not the orchestrator |
| "Tell every agent to commit continuously" | Omitted from two briefs right before `TaskStop` destroyed both transcripts; the "minutes, not work" reassurance to the owner was wrong |
| One simulator per agent | Applied to one agent and not its neighbor; the collision produced `SQLITE_IOERR_VNODE` failures that an agent misattributed to its own fixtures and "confirmed" with green reruns |
| "Look at running screens, not just tests" | Skipped for the photo feature; the protocol-extension dispatch bug shipped to the owner's phone with every test green — *"I shipped that to your device having never once looked at a photograph on a running screen"* |
| "Pick the newest DerivedData" (memory note) | **Actively wrong** once worktrees existed — a note that was worse than no note, followed faithfully into a false conclusion |

So the honest answer to "are you an idiot or do the systems suck": the errors are real and mine,
but they are not randomly distributed. They cluster precisely where the system stores rules as
prose and enforces them by in-the-moment recall — which decays under load, late in long contexts,
and across compactions. Where a rule was moved into a mechanism, the recurrence rate went to
approximately zero. That is a systems indictment with a named mechanism, and it is fixable.

## The five repeat classes (≈80 % of all repeats)

**1. Verifying against the wrong artifact — the dominant class, ≥12 variants.**
Stale DerivedData (twice, two forms), a stale log file at the same path, an uncommitted app icon
every worktree silently built without, a console capture that recorded nothing, blank transparent
screenshots that passed every test, all map-performance measurements taken on a simulator with
location *declined*, an agent photographing the pre-rebuild "mutant" build, verification runs
pointed at the wrong tree twice, and the whole exit-code family. The transcript names it:
*"I verified against something other than what I thought I was verifying"* — but every lesson was
recorded at the **instance** level (stale logs, stale DerivedData…), so each new variant counted
as new until it bit. The class rule was never written: **never trust an artifact you did not
watch being produced — check content, mtime, and provenance before reading it as evidence.**
Deepest consequence, in the transcript's own words: recent greens from incremental builds
*"aren't trustworthy — including, potentially, ones I've reported to you before."*

**2. Announcing before verifying.** Three `echo`/prose conclusions written before reading the
command's own output (one nearly pinned a nonexistent defect into ERRATA with `XCTExpectFailure`);
six rulings whose premises did not survive contact with the code; at least six false facts
propagated through agent briefs (wrong doc paths in four briefs, "no SF Symbols" refuted by grep,
a stale main sha, wrong figures); four confident wrong claims to the owner in the data-source
thread, each falsified only when the owner looked at the actual thing. Sibling class in code:
five "confident comment" bugs, where documentation asserting a behavior was the reason nobody
checked it — one created by my own fix **within an hour** of preaching the pattern.

**3. Shared mutable state across concurrent agents — eight surfaces, learned one at a time.**
Shared DerivedData → shared source files (`AppRouter` clobbered twice) → shared simulator →
the ERRATA counter → the RULINGS counter (*"the same collision the errata convention was invented
to prevent, which I failed to extend to rulings"*) → shared scratchpad DerivedData → shared log
filenames → schema versions. Every fix protected exactly the surface that had just burned and
left the next one open. The general rule — *any* mutable resource two agents can both reach needs
either partitioning or a single owner — was derivable from incident one.

**4. Tests that cannot fail.** The project's self-named "signature failure mode," and it kept
re-emerging in fresh code after being named: dormant suites never compiled, a UI target running
zero tests and reporting success, guards green with the defect reinstated, a test that positively
**ratified** a defect for weeks, a copy test *requiring* the word "hearted" and thereby holding
false copy in place, `#expect` on large `Data` that hangs instead of failing. The break-test
discipline catches these — but only at the orchestrator's review step, not at authoring time,
because it lives in briefs rather than in anything the author must run.

**5. AX5 layout defects — four instances, one structural cause.** Screen 04's chips, the
add-tree caption, the FAB over the truncation sentence, the empty-map notice growing off-screen
with its own escape hatch. SCREENS.md draws every screen at default type size only, so every
AX5 behavior is invented at implementation time without a mock. Noted repeatedly; never fixed
structurally.

**Cross-session control case.** The earlier design-era sessions provide a clean A/B: the one
lesson written to durable memory (SVG data URIs) never repeated; the biggest lesson left unwritten
("LLMs cannot draw organic vector art — use raster") repeated verbatim in a later session, where
the shipped app icon was again a hand-drawn vector tree and the owner had to re-teach the lesson.

## Root causes

1. **Rules were stored as prose in three lossy places**: memory files (read at session start,
   then never again), compaction summaries (*"that list was carried in prose across a compaction
   and degraded"* — two of six rulings rested on premises that degraded exactly this way), and
   agent briefs hand-rewritten from degraded memory each round (which is how wrong doc paths rode
   in every brief for a day).
2. **The enforcement point was orchestrator recall** — the single most overloaded component,
   weakest precisely when rules matter most: under contention, after limit deaths, late in
   context. Every "I ignored my own note" incident happened at one of those moments.
3. **Lessons were recorded per-instance, not per-class**, so the same class re-presented as a
   novel failure ≥12 times.
4. **There was no `CLAUDE.md`** — the one file the harness loads automatically into every session
   *and every subagent*. Three agents independently reported its absence. Everything invariant
   was therefore re-derived by hand, per brief, forever.

## Fixes shipped with this postmortem

1. **`CLAUDE.md` at the repo root** — the invariant rules (verification doctrine, simulator
   table and rules, numbering conventions, worktree setup, hang list, brief boilerplate),
   auto-loaded into every future session and subagent. Kills the re-derived-brief class.
2. **`Tools/run_tests.sh` + `Tools/verify_test_log.sh`** — build/test verification as a script:
   fresh log, boot-and-wait, and a verifier that refuses to say OK unless the log is fresh,
   terminally complete, and contains a *real* pass line (`Test run with N tests passed`, or a
   nonzero XCTest executed count). Mechanizes away the entire exit-code family.
3. **`Tools/setup_worktree.sh`** — copies the git-ignored seed into both required locations of a
   new worktree. Mechanizes the false-baseline class.
4. **Memory rewritten at class level** and deduplicated (the worktree-agents note carried the
   same `git add -A` lesson twice, written in two compaction eras, neither aware of the other —
   the guardrail store had the same disease as the process it guards).
5. **Filed:** a ticket for rendering the screen sweep at AX5 (closing repeat class 5 structurally
   rather than with a fourth patch); note that #93's blank-screenshot guard still fails open and
   remains the highest-value single test to close in class 1.
