### `#expect(cgFloat == 3.0 / 4.0)` compares two boxes, not two numbers, and is false at 0.75

`main` failed its own unit suite on one assertion, and the assertion was arithmetically correct:

    ✘ VisitCameraSessionTests.theAddTreeWellIsAPortraitCaptureFrame()
      CypressTests/VisitCameraSessionTests.swift:808: Expectation failed: (ratio → 0.75) == (3.0 / 4.0 → 0.75)

Both sides print `0.75`, so the obvious reading is a float that misses by less than `description`
shows. That reading is wrong, and the hours it costs are the reason this entry exists. The values are
**bit-identical**. Printed from inside a running test, at full precision and as raw IEEE 754:

    [APP]  wellAspectRatio    = 0.75000000000000000000  d=0x3fe8000000000000
    [APP]  captureAspectRatio = 1.33333333333333325932  d=0x3ff5555555555555
    [TEST] wellAspectRatio    = 0.75000000000000000000  d=0x3fe8000000000000
    [TEST] 3.0 / 4.0          = 0.75000000000000000000  d=0x3fe8000000000000

There is nothing wrong with the arithmetic, and nothing wrong with the product. `4.0 / 3.0` rounds to
`0x3ff5555555555555`, whose reciprocal rounds back onto exactly `0.75` with a factor of eight of ULP
to spare. The defect is in **how `#expect` types its operands**.

**The mechanism.** `#expect(a == b)` does not compile to `a == b`. The macro expands to a generic
call of roughly the shape

    __checkBinaryOperation<T, U>(_ lhs: T, _ op: (T, () -> U) -> Bool, _ rhs: @autoclosure () -> U, …)

so that a failure can report each operand's value separately. `T` binds from the left-hand side; `U`
is inferred from the right-hand side *and from what `==` will accept*. Here `T` is `CGFloat`, and the
bare literal expression `3.0 / 4.0` takes its default literal type, `Double`. Swift has no
`==` for `(CGFloat, Double)`. It does have the implicit `CGFloat`↔`Double` conversion — and it also
has the implicit conversion of any `Hashable` to `AnyHashable`, together with
`==(AnyHashable, AnyHashable)`. The solver takes the second. Reproducing that exact signature and
printing what it bound:

    [MIMIC bare]  result=false  T=CGFloat  U=AnyHashable  size=40  value=0.75
    [MIMIC var]   result=true   T=CGFloat  U=CGFloat      size=8   value=0.75

`AnyHashable` equality compares the **dynamic type first**. Both boxes hold the same 64 bits; one is
labelled `CGFloat` and the other `Double`, so they are unequal:

    [BOX] AnyHashable(CGFloat(0.75)) == AnyHashable(Double(0.75)) -> false
    [BOX] base types: CGFloat vs Double

That is the whole failure. Not a float, not the optimiser, not constant-folding: a type-erasing
comparison, reported through a message that shows the values and hides the types.

**Which spellings are affected.** Run against the same `ratio`, in one test:

| spelling | result |
| --- | --- |
| `let b = (ratio == 3.0 / 4.0); #expect(b)` | passes |
| `#expect(ratio == rhsCG)` where `let rhsCG: CGFloat = 3.0 / 4.0` | passes |
| `#expect(ratio == 0.75)` | passes |
| `#expect(ratio == CGFloat(3.0) / CGFloat(4.0))` | passes |
| `#expect(Double(ratio) == 3.0 / 4.0)` | passes |
| `#expect(ratio == 3.0 / 4.0)` | **fails** |

Two things fall out of that table. The trap needs the macro — the same comparison written as a plain
`let` is true, because outside a generic parameter the solver has a concrete `CGFloat` on both sides
and never reaches for `AnyHashable`. And it needs a *compound* literal expression: a bare `0.75`
binds `U` to `CGFloat` directly, since a single literal can simply be a `CGFloat` with no conversion
at all. `3.0 / 4.0` is a call to `/`, which pulls in the default literal type first.

**The fix is to name the type, and it is not a tolerance.** `VisitCameraSessionTests` now reads

    let portrait: CGFloat = 3.0 / 4.0
    #expect(ratio == portrait, "the well is \(ratio), not the 3:4 frame a phone held upright takes")

which keeps the comparison exact. Loosening it to `abs(ratio - 0.75) < ε` was the tempting repair and
would have been the wrong one twice over: it discards an alarm that was working, and it would have
been fixing a product that was never broken. Proved by mutation — with the product constant moved by
**one ULP** (`(1 / Camera.captureAspectRatio).nextUp`, a change of 1.1e-16) the assertion goes red.

**The sweep, which is the part worth keeping.** The trap is not specific to this constant; it is
available to every `#expect` in the suite that compares a `CGFloat` against a `Double`, and this
codebase measures geometry constantly. It divides into two cases, and only one of them is dangerous:

- **`==` — loud.** An affected equality is *always* false, so it fails immediately and cannot hide.
  A full clean run of the unit suite is therefore a complete census of them. There is exactly one:
  the assertion above.
- **`!=` — silent.** An affected inequality is *always* true, so it passes for the wrong reason and
  nothing ever notices. These cannot be found by running; they have to be read. All 98 `!=`
  expectations in `CypressTests` were listed and checked. 58 are `!= nil`; the remaining 40 compare
  strings, enums, copy constants, `Route`s and presentation structs. **None compares a `CGFloat`
  against a `Double` or against an untyped literal.** The suite has no silent instance today.

The one other equality in the suite that pairs a literal arithmetic expression with a numeric value
is `MeasurePresentationTests.swift:88`, `#expect(draft.quantity?.siValue == 64 * 0.0254)`. It is
sound, and usefully so: `siValue` is a `Double`, so `U` binds to `Double?` with no conversion needed
and no erasure. Literal arithmetic is not the trigger on its own — the trigger is `CGFloat` meeting
`Double` across the macro's generic parameter.

**The rule.** Inside `#expect` and `#require`, never compare a `CGFloat` against an unannotated
numeric expression. Bind the expected value to a `CGFloat` first, or write both sides `Double`. The
comparison you read is not the comparison the macro compiles.

Related: E162, which is the well's own defect and the reason this test exists; ticket #113.
