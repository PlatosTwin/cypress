### E?? — The UI suite inherits the simulator's *location*, and a fix on a treeless block reads as a broken map

*Found on branch `p1/round10-b` (task #185), 2026-08-03, on iPhone 16e `3A1F212D-…`. Not caused by
that ticket; the control at the merge base proves it.*

*UNNUMBERED — the orchestrator splices the number at merge.*

---

**The symptom.** Two UI tests fail and nothing else does:

    AlmanacGroupTapTests.testWalkTheNineOpensAMapOfThemAll
    AlmanacGroupTapTests.testTheVacantRowOpensAMapAndNamesThePage
      XCTAssertTrue failed - screen 01 drew no tree pins in thirty seconds,
      which it does with a fix and without one

They look like a defect in whatever you just changed, because they are two tests out of seventy and
they name the map.

**The cause.** The device's location fix was `37.769402, -122.486198` — the western end of Golden
Gate Park. Screen 01 opens at `MapLayout.defaultSpanMetres`, 120 m across, **centred on the user**.
The seed holds **zero** trees within 200 m of that point and 3,230 within a kilometre, so the map
opened over a rectangle of the city that SF's *street* tree inventory does not cover, and drew
nothing. `reachAlmanac` then waited thirty seconds for a pin that was never going to appear.

    SELECT count(*) FROM trees
     WHERE lat BETWEEN 37.7685 AND 37.7703 AND lon BETWEEN -122.4873 AND -122.4851;   -- 0

**Why `run_tests.sh` let it through, and this is the part worth keeping.** E202's device-state guard
refuses a `map.lastCamera` **too wide** for the screen, because a wide camera draws cluster badges
where a test waits for pins. This camera was `zoom 18` — as narrow as they come — and the guard
passed it, correctly by its own rule. The failure is the opposite geometry with the same symptom: a
camera narrow enough and *pointed somewhere empty*. The header records the camera on every run
(`CYPRESS-RUN: device-state`) so the coordinate is in the log, but nothing reads it against the seed.

Location state is deliberately unchecked by `run_tests.sh` — a fixless or location-denied device is
a legitimate configuration and #121's tests skip on it. That decision stands. What it does not
anticipate is a device with a *perfectly good fix in the wrong place*, which is neither of the two
states it reasoned about.

**How the cause was established rather than guessed.**

1. Deleted `map.lastCamera` per the script's own remedy and re-ran: **same two failures**. So the
   remembered camera was a symptom, not the cause — the app re-derives it from the fix on every
   launch, and the log's next header showed the identical coordinate back again.
2. Ran the same two tests at the **merge base** `10c8bd9`, on the same device, with none of the
   branch's changes present: **same two failures**. That is #183's control, and it settles authorship.
3. `xcrun simctl location <udid> set 37.7596,-122.4269` — the map's own default centre, 36 trees
   within 200 m — and re-ran: **`Executed 2 tests, with 0 failures`**. Then the full suite:
   `** TEST SUCCEEDED **`, 70 executed, 0 failures.

Step 3 alone would have been a green re-run proving nothing. Steps 1 and 2 are what make it a cause.

**The other tell, and it is worth knowing.** The skip count moves with the fix. The failing runs
reported `70 tests, with 4 tests skipped`; the passing one reports `2 tests skipped`. Two
location-conditional tests (#121) had been skipping on a device that *had* a fix — which is itself a
sign the fix was not where anything expected it. A UI log whose skip count changed between two runs
of the same tree is reporting a device change, not a code change.

**What to do.** Before blaming a change for an empty map: read the `map.lastCamera` coordinate out of
the `CYPRESS-RUN` header and ask the seed how many trees are near it. If the answer is none, move the
fix rather than the code. `xcrun simctl location <udid> set 37.7596,-122.4269` is the repair; note
that `simctl location clear` does **not** unfix a device (CLAUDE.md), so clearing is not it.

The device was left with the fix at the default centre.

**Worth mechanizing, not done here.** `run_tests.sh` already knows the camera and the worktree, so it
could count seed trees inside the remembered viewport and refuse on zero with the same voice it uses
for a wide camera. That is a change to a shared tool from a branch, and it belongs to whoever owns
the next round of `run_tests.sh` rather than to a copy ticket.
