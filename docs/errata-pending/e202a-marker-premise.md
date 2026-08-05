### E202-A's marker-survives-reinstall premise: it does, on this device today — E210 §4 measured a different mechanism (task #220)

*UNNUMBERED — the orchestrator splices the number at merge.*

*Measured 2026-08-04, iPhone 16e `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, iOS 18.6 (simulator runtime
`com.apple.CoreSimulator.SimRuntime.iOS-18-6`), macOS 26.6 (build 25G72), Xcode 26.6 (build 17F113),
worktree at commit `bb3d8f0` (base) then `bd153a4`/`03963e6` (this ticket's own commits, irrelevant to
the mechanism below — the experiment does not touch `CityLibrary` or the marker path). Filed from
task #220, which was asked to resolve the discrepancy between **E202-A** ("the marker survives
reinstall, because `xcodebuild test` replaces the app bundle and leaves the data container alone")
and **E210 §4** ("on this configuration the data container did **not** survive `xcodebuild test`" —
three consecutive runs, three container UUIDs, marker gone every time, measured on this same 16e).*

---

#### The claim under test

E202-A: a leftover `active-city` marker at `Application Support/Cypress/cities/active-city` survives
`xcodebuild test`'s reinstall, "because `xcodebuild test` replaces the app bundle and leaves the data
container alone." `Tools/run_tests.sh` refuses a run on that state (E202-A's own recommended fix).

E210 §4 recorded a contrary result on this same device: it planted `us-ca-sj` at the marker path, ran
one UI test through the escape hatch, and found the container UUID different afterward and the marker
gone — three times, three different UUIDs — and left the discrepancy "not resolved," worth someone's
attention "before E202-A is relied on again."

#### Calibration first

Before trusting any "present / absent" read below, the same `cat`/`[ -f ]` check was run against a
marker just planted by hand, to confirm it finds what is actually there:

    $ echo -n "us-ca-sj" > "$C/Library/Application Support/Cypress/cities/active-city"
    $ cat "$C/Library/Application Support/Cypress/cities/active-city"; echo
    us-ca-sj
    PLANTED: marker file exists, detection command confirms

This was repeated before every plant below. The detection command is trusted for the rest of this
note.

#### Experiment 1 — a mechanism E202-A's marker does not have: `tree_status_overrides`

While proving E217's leak/fix (same ticket, same device, same session — see the PR this file ships
with), `LocalAPI.debugMarkStatus` wrote rows to `tree_status_overrides`, a table with **no self-clearing
logic anywhere in the app** — nothing reads it except `LocalAPI.debugStatusOverrides()`/`treesNear`'s
override layer, and nothing writes an empty row or a tombstone into it. If device data survives
`xcodebuild test` reinstalls on this device, this table is the cleanest instrument for it: no app-side
validation can explain a row disappearing.

Five separate `xcodebuild test` invocations were run against this device over two sessions (2026-08-03
and 2026-08-04), each through `Tools/run_tests.sh`, each assigned its own fresh container by
`xcrun simctl get_app_container … data`:

| when | container UUID (`Data/Application/…`) | `tree_status_overrides` row count |
|---|---|---|
| 2026-08-03, several runs before this session | (not captured live) | 11 (found already present at session start) |
| 2026-08-04 run 1 | `CF20BD30-926E-4570-AC54-095D11760C4A` | 13 (+2) |
| 2026-08-04 run 2 | `47A20D8A-5430-4E37-8616-0CB002178227` | 15 (+2) |
| 2026-08-04 run 3 (`testPinAdjustCTA` only, no write) | `CCC81C5B-0B31-4774-AD7F-CA75F55B98D4` | 15 (unchanged, confirms *read* survived) |
| 2026-08-04 run 4 (`testPinAdjustCTA` only) | `590BDC8B-1B25-4A73-AA15-BB631FD441CC` | 15 (unchanged) |
| 2026-08-04 run 5 (`testPinAdjustCTA` only) | `43F5BAD6-E3C6-4D5C-BAE6-4E80AE0591CD` | 15 (unchanged) |

Every one of these five runs assigned a **different** container UUID (confirmed by `simctl
get_app_container` before and after, and by the fact that the pre-run UUID's directory no longer
exists on disk afterward — checked directly, e.g. `CF20BD30…` was gone after run 2). And every one of
these five runs read back **the same 15-row table**, including the 11 rows that predate this session
entirely. `tree_status_overrides` is under `Library/Application Support/Cypress/`, the same directory
`cities/active-city` lives in.

**This device's `Data/Application/` directory holds 133 old container UUIDs**, almost all stamped with
the identical mtime `Aug 2 21:44` (one mass event — an erase or an initial device setup) — including
every UUID this experiment assigned. `xcodebuild test`'s install step is not minting brand-new,
empty containers each time; it is round-robining through a pool of pre-existing ones and carrying the
data forward. Reinstall genuinely does not throw the data away on this device today.

#### Experiment 2 — reproducing E210 §4's own method, with the mechanism read off first

Three consecutive plant → run → check cycles, matching E210 §4's structure exactly:

| run | container before | marker planted? | container after | marker present after? | `tree_status_overrides` count after |
|---|---|---|---|---|---|
| 1 | `47A20D8A-…` | yes (`us-ca-sj`) | `CCC81C5B-…` | **No such file or directory** | 15 |
| 2 | `CCC81C5B-…` | yes (`us-ca-sj`) | `590BDC8B-…` | **No such file or directory** | 15 |
| 3 | `590BDC8B-…` | yes (`us-ca-sj`) | `43F5BAD6-…` | **No such file or directory** | 15 |

This reproduces E210 §4's own result precisely: three runs, three container UUIDs, marker gone every
time. **And in every one of the same three runs, `tree_status_overrides` — sitting one directory over
from the marker, written well before this experiment and never touched by it — survived intact.**
Whatever removed the marker did not remove the container's data wholesale.

#### The mechanism, read from the code rather than guessed at

`Cypress/Data/Cities/CityLibrary.swift:177-195`, `validatedActiveSeedURL()`:

    /// Resolves the marker to a seed URL this build may attach, validating the file first. A
    /// dangling marker (removed city), an unreadable file, or a generation from the future all
    /// clear the marker and return nil — the caller attaches the bundle and the app launches;
    /// the Cities screen then shows the city as installed-but-not-in-use, which is the truth.
    public func validatedActiveSeedURL() -> URL? {
        guard let id = activeCityID() else { return nil }
        guard let version = installedVersion(of: id) else {
            try? deactivate()
            return nil
        }
        …
    }

`installedVersion(of:)` looks for an actual downloaded city directory
(`Application Support/Cypress/cities/<id>/<version>/<id>.sqlite`) on disk. `AppModel.swift:33` calls
this — through `DataLayer.bootPreferringActiveCity` — on **every app launch**, marker-driven UI test
or not. A marker planted with a bare `echo … > active-city`, with no matching download, has no
`installedVersion`, so `deactivate()` — which deletes the marker file — fires on the very next boot.
This is deliberate, documented app behavior, not data loss: the doc comment says so in as many words
("a dangling marker … clear[s] the marker").

E210 §4's own wording — "**Planted** `us-ca-sj` at the marker path" — describes exactly this: a raw
write with nothing downloaded behind it. That configuration hits `validatedActiveSeedURL`'s self-heal
on the very first launch after planting, independent of whether the surrounding container was reused,
replaced, or genuinely wiped. **The experiment that produced E210 §4 could not have told the two apart**,
because it only ever checked the marker after a launch, never before.

E202-A's own original incident (E202, 2026-08-02, iPhone 16 Plus) is not this configuration: that
marker was set by a real smoke test that **actually downloaded San Jose and tapped "Use"** — a
directory with a real `installedVersion` exists behind it, so `validatedActiveSeedURL` would keep it
rather than heal it. That marker's survival across the next `xcodebuild test` was never itself
retested here, for the practical reason that reproducing a real city download was out of this
ticket's budget — see "What is still open" below.

#### The resolution

**E202-A's stated general mechanism — device data survives an `xcodebuild test` reinstall on this
device — is true, reconfirmed five times today via `tree_status_overrides`, a table with no
self-clearing logic of its own. The marker file itself did not survive in any experiment here,
and that is not evidence against E202-A: an undownloaded marker is deleted by `CityLibrary`'s
self-heal on the next boot — a distinct, intentional app-level mechanism — while E202-A's original
scenario, a downloaded install-backed marker, is exactly what this note does not retest.**
`Tools/run_tests.sh`'s E202-A refusal reads the marker
*before* the current invocation's app has booted even once, so a genuine leftover from a prior
manual download-and-activate (the scenario the refusal exists for) is caught before any self-heal
could run — the guard remains both correct and reachable.

**E210 §4's contrary finding is not wrong about what it observed — the marker was gone, the
container UUID did change every time — but it drew the wrong conclusion from it.** It measured
`CityLibrary`'s own intentional self-heal of a marker with no download behind it, not a property of
`xcodebuild test`'s reinstall. The "three consecutive runs, three container UUIDs" fact is real and
reproduced again here; "the data container did not survive" is the part that does not hold — the
data survived every time in this session, through every one of those UUID changes.

#### What `Tools/run_tests.sh` should become

**Nothing.** The refusal already fires on exactly the state it is meant to catch (a marker present
*before* this invocation's app has run), and this note's evidence supports keeping it rather than
weakening or removing it — a real leftover from a downloaded city would behave like E202's original
33-failure incident, not like this experiment's synthetic plant. No script change is made here.

The one edit worth making is to the comment trail: E210 §4's "Unresolved" section (docs/ERRATA.md,
"on this configuration the data container did **not** survive `xcodebuild test`") should be marked
superseded by this entry once it is numbered, so the next agent does not re-open the same afternoon.
That cross-reference is left for the orchestrator's splice rather than made here, since this file
does not yet have a number to point to.

#### What is still open

This note did not test whether a marker backed by a **real download** (the actual E202 scenario)
survives an `xcodebuild test` reinstall — only that a synthetic, undownloaded one is self-healed by
the app itself regardless of what the container did. Given `tree_status_overrides`' clean five-for-five
survival in the identical container/session, there is no positive reason to expect a real download's
marker to behave differently, but it was not directly measured, and downloading a real city inside
this ticket's environment was judged out of scope. Worth a cheap follow-up: download a city through
the real UI flow (or seed a fake `<id>/<version>/<id>.sqlite` so `installedVersion` succeeds without a
real download), plant its marker, run `xcodebuild test`, and confirm the marker is what `run_tests.sh`
reads back before the next invocation.
