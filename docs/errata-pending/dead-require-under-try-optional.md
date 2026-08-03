# (pending) — `try? #require(x)` is a dead requirement, and the compiler had been saying so (task #83)

*Written from the branch `p1/test-warnings`. Unnumbered by CLAUDE.md's rule; the orchestrator
splices the real number at merge and rewrites the citations that name this file.*

## What was found

Two of the 58 unique warnings in #83's baseline were not concurrency warnings at all, and were not
noise:

    CypressTests/CityRecordTests.swift:330: warning: '#require(_:_:)' is redundant because
      'Tree(source: .cityImport, …, cityRecord: city).landContext' never equals 'nil'
    CypressTests/PinAdjustTests.swift:79: warning: '#require(_:_:)' is redundant because
      'VisitPinAdjust.nudge(pin, towards: .north, from: Self.fix)' never equals 'nil'

Both expressions **are** optional — `Tree.landContext` is `KnownLandContext?` and
`VisitPinAdjust.nudge` is `Coordinate?`. The warning is right anyway, and it is about the `try?`.

`#require` is generic: `require<T>(_ value: T?, …) throws -> T`. Written `try? #require(opt)`, the
type checker is free to bind `T` to the *optional itself* — the argument `KnownLandContext?` is
implicitly promoted to `KnownLandContext??`, whose outer level is never `nil` — and then `try?`
flattens the result back to the same optional the expression started as. Every type checks, the
call site reads exactly as intended, and the requirement can never fail.

These were the only two `try? #require` sites in `CypressTests`, and both of them warned. Every
`try #require` in the suite was clean.

## What the two dead requirements were covering for

- **`PinAdjustTests.theNudgeStopsAtTheBoundary`.** The loop's message `"nudge \(step) of 15 was
  refused inside the circle"` could not be printed by anything. A refused nudge fell through
  `pin = moved ?? pin` silently; only the aggregate distance assertion three lines later could
  notice, and it would have said "0.05" rather than which nudge was refused.
- **`CityRecordTests.statedWinsAndIsLabelled`.** `inferred` stayed optional, so the two assertions
  under it were `nil == .street` and `nil == .inferredFromCityRecord` on a nil answer — a failure,
  but reported as a mismatched enum rather than as "the inference returned nothing".

Neither was a false green: in both cases some later assertion still caught a nil. What was lost is
the diagnostic — the failure named the wrong thing, which on this project is how afternoons go.

## The fix, and how it was proved

Both call sites now use `try` (with the enclosing test made `throws`). Red-proofed on iPhone 16 Plus
`24D1629F-9FA8-4E3D-812E-F6BC85C9E668`: the nudge loop widened to `1...16` and the city record
changed to `CityRecord(legalStatus: "Undocumented", caretaker: nil)`. Both went red **at the
`#require` line itself** — `PinAdjustTests.swift:81` and `CityRecordTests.swift:333` — with
`Expectation failed: … → nil`, which is the reason expected and not merely the colour expected.
Both were restored and the full unit suite re-run green.

## The rule

`try? #require(…)` is never what the writer meant. If the value is genuinely allowed to be absent,
the test should say so with `if let` or an `#expect` and no requirement; if it is required, `try`
is the only form that makes the requirement do anything. The compiler already flags it, so the
standing zero-warning line is what enforces this — which is the second reason #83's debt was worth
paying rather than suppressing.
