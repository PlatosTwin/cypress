# Amendment to E250 — the probe's next two occurrences, recorded verbatim

E250 instrumented `MapPanTabSwitchUITests.testADeliberatePanSurvivesLeavingForJournalAndBack` so
that the next occurrence would carry its trace in the `XCTFail` text "instead of needing another
investigation from zero". Two more occurrences have since happened, and this amendment records
them — because the console log truncates the very line the probe exists to preserve. In both
runs below, `xcodebuild`'s captured output ends the message at `lastEnded …` (literal ellipsis);
the full text survives only in the run's `ui-log-4` artifact, which GitHub deletes on its
retention schedule. Both artifacts were pulled and read on 2026-09-01; the lines below are
byte-exact from those artifacts.

**Fifth sighting** — run 33352801695 attempt 1, shard `ui (4)`, PR #132 (`feat/stats-picker`,
head `43fc737`, merge ref `b7f4657`), 2026-08-31 03:23 UTC; attempt 2 green on identical code.
The diff at that head touched neither the test nor the map. Artifact `ui-log-4` id 9744426503:

```
CypressUITests/MapPanTabSwitchUITests.swift:163: … failed - panning the map did not move the
camera off the reader (the control reads "Centered on you"), so there is no deliberate camera to
preserve — probe: panBegan=3 panEnded=3 panCancelled=0 panFailed=0 lastEndedTranslation=-110,120
settles=3 lastSettleCenter=37.7599,-122.41480000000001 lastSettleSpan=0.001633684502579058
```

**Sixth sighting** — run 33469599808 attempt 1, shard `ui (4)`, the post-build-68 main run
(`3f02a5d`), 2026-09-01 ~04:39 UTC; attempt 2 green on identical code. Artifact `ui-log-4`
id 9786404346:

```
CypressUITests/MapPanTabSwitchUITests.swift:163: … failed - panning the map did not move the
camera off the reader (the control reads "Centered on you"), so there is no deliberate camera to
preserve — probe: panBegan=3 panEnded=3 panCancelled=0 panFailed=0 lastEndedTranslation=-111,120
settles=3 lastSettleCenter=37.7599,-122.41480000000001 lastSettleSpan=0.001633684502579058
```

## What the numbers say, and what they do not

Read against E250's own reference points, without adjudicating the mechanism (that is the
hardening round's job, roadmap chip item 5):

- The two readings are near-identical to each other — the only difference across both full lines
  is one point of x-translation (−110 vs −111) — and close to the first instrumented occurrence
  (run 31783549334, 2026-08-14: `panBegan=3 panEnded=3 … lastEndedTranslation=-111,120 settles=3
  lastSettleCenter=37.7599,-122.4148 lastSettleSpan=0.00208`). Three occurrences, one shape.
- `panBegan=3 panEnded=3` with `panFailed=0`: all three synthesized drags were read as pans by
  the reader's own recognizer, with a healthy ~165 pt translation measured by UIKit at `.ended`.
  This is not E250's "never landed" arm as originally imagined — the touch stream arrives.
- `settles=3`, against the red-proof's no-pan baseline of `settles=2` (the launch fly-to):
  exactly one settle beyond baseline, for three delivered pans, with the settle center back on
  the reader. It is also not the residual-ambiguity third shape E250 pre-registered
  (`panBegan > 0` with settles *unchanged*) — one settle did happen.
- The final spans differ between the no-pan baseline (`0.00211`) and these occurrences
  (`0.00163`), so the camera did not simply sit still; something changed the region once and
  left it centered on the reader. Note the first instrumented occurrence's span (`0.00208`) sat
  essentially at the baseline while these two sit together at `0.00163` — the one axis on which
  the three occurrences are not identical.

The constancy is the finding: whatever produces this failure produces the same trace to the
point, twice, eighteen hours apart, on different heads whose diffs touched neither the test nor
the map. The hardening round should start from these three lines rather than from the sentence
in the failure text.
