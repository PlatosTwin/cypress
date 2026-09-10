# `TEST_RUNNER_CYPRESS_SHOT_DIR` on the `xcodebuild` command line reaches no process

**Status: instructions corrected in `tools/shot-dir-and-sql-properties`. No code was broken. One doc
comment prescribed a spelling that reaches no process; three more named the variable without saying
how to set it, so a reader could not act on any of the four. One screenshot round paid for it.**

Four suites write a PNG per state to the directory named by `CYPRESS_SHOT_DIR`. **Exactly one of
them said how to put it there, and what it said was false.** This is the account of what each file
actually said, quoted from `b5a929c` — the base of the branch that corrected them — because the
first draft of this erratum widened one file's defect to four, which is the same habit the erratum
exists to record:

| file at `b5a929c` | what it said about *how* | verdict |
| --- | --- | --- |
| `CypressUITests/AreaPickerUITests.swift:13-14` | "Set `CYPRESS_SHOT_DIR` (as `TEST_RUNNER_CYPRESS_SHOT_DIR` on the `xcodebuild` command line) to choose where." | **false** — the one instruction that reaches no process |
| `CypressUITests/AlmanacGroupTapTests.swift:14` | "`CYPRESS_SHOT_DIR` in the runner's environment to choose where; otherwise the paths are printed." | true, and incomplete — names the right channel, does not say how a shell reaches it |
| `CypressUITests/AlmanacGroupTapTests.swift:342-343` | "`TEST_RUNNER_CYPRESS_SHOT_DIR` chooses the directory — the `TEST_RUNNER_` prefix is what forwards an `xcodebuild` variable into the runner's environment." | imprecise, not false — "an `xcodebuild` variable" is the ambiguity the whole defect lives in: it forwards one from `xcodebuild`'s *environment*, never one written as an argument |
| `CypressTests/ScreenSweepShots.swift:30` | "Output goes to `CYPRESS_SHOT_DIR` if set, otherwise a temporary directory. Paths are printed." | silent on how |
| `CypressTests/DynamicTypeScreenshotTests.swift:27` | "Output goes to `CYPRESS_SHOT_DIR` if set, otherwise the temporary directory…" | silent on how |
| `Cypress/App/DebugDeepLink.swift:46` | nothing — it names `CYPRESS_SHOT_DIR` once as an example of this codebase's environment-key naming, while explaining `CYPRESS_SCREEN` | did not state the convention at all |

A `NAME=value` argument to `xcodebuild` is a **build-setting override**. It does not enter any
process's environment, `xcodebuild` does not object to a name it has never heard of, and the tests
pass either way — they fall back to `NSTemporaryDirectory()` and print the path they used. So the
instruction failed by doing nothing, which is the failure mode that leaves no trace: in the
2026-08-31 picker round the shots landed inside the simulator's app container and the round fell
back to reading the printed `CYPRESS-SHOT:` lines out of the captured log.

The mechanism the comments were reaching for is real and was already in use one target over.
`xcodebuild` forwards every variable in **its own environment** whose name begins `TEST_RUNNER_` to
the process that hosts the test bundle, with the prefix stripped. That process is the app under test
for `CypressTests` and the `…-Runner.app` for `CypressUITests`, so one exported variable serves both
targets:

    export TEST_RUNNER_CYPRESS_SHOT_DIR=/some/dir
    Tools/run_tests.sh <udid> <log> …

`XCUIApplication.launchEnvironment` is a different channel and cannot do this job. It sets the
environment of the **app under test** — which is how `CYPRESS_SCREEN` and `CYPRESS_LOCATION` travel
— and the UI tests' `record(_:named:)` runs in the runner, not in the app.

## Measured, three ways, on one device

iPhone 16e `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, 390 pt, worktree
`cypress-wt-shotdir` at `b5a929c`, 2026-09-09. Each run was
`Tools/run_tests.sh … -only-testing:CypressUITests/AreaPickerUITests/testASanJoseReaderIsToldWhatActuallyChoseItsArea`,
one shot per run, and each target directory was listed **before** the run and shown empty.

| spelling | where the PNG went |
| --- | --- |
| `export TEST_RUNNER_CYPRESS_SHOT_DIR=<dir>` before the script | `<dir>/picker-10-san-jose-fallback.png` — 387,880 bytes, `PNG image data, 1170 x 2532`, mtime inside the run window |
| nothing set | `…/CoreSimulator/Devices/3A1F212D…/data/Containers/Data/Application/<uuid>/tmp/picker-10-san-jose-fallback.png` |
| `TEST_RUNNER_CYPRESS_SHOT_DIR=<dir>` as an `xcodebuild` argument | the same container `tmp`; `<dir>` still empty afterwards |

1170 px at 3× is 390 pt, the 16e's own screen, which is the check that the image came from the run
being described rather than from a directory something else had written to.

## What now keeps it true

`CypressTests/ShotDirectoryConventionTests` asserts two facts, both silent when they break: that all
four shot writers read one key out of their environment, and that every name this repository tells
an operator to export is that key behind the forwarding prefix. It deliberately does **not** police
the prose that says *how* to set the variable — the defect here was a false instruction, and a gate
matching the words "command line" would go green on the same instruction reworded, which is the
worst shape a guard takes in this repository. **That gap is real and unguarded** — a reworded false
instruction still passes, verified by planting one — and it is recorded in `docs/ROADMAP.md` rather
than only here, so the next round that touches these files meets it without reading this page first.

The argument itself lives in one place, `Tools/run_tests.sh`'s header, with the table above. The
four writers point at it, and `DebugDeepLink` — which named the key only as a naming example — now
separates the key's spelling from the channel it arrives on, since conflating those is the defect
this page is about. The guard's third
test now proves its own sweep reached each of those files by name rather than merely counting a
plausible number of them — the first cut counted 477 files with a whole target missing and passed.
