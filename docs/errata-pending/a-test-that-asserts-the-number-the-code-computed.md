### A test that asserts the number the code computed, not the number the animation was given

*UNNUMBERED — the orchestrator splices the number at merge. Task #207.*

**The defect.** The direction cone on the reader's dot (#155) shipped in build 9 and swung a **full
revolution** on every heading update. It pointed correctly whenever the reader stood still, which is
why it survived review: standing still produces no new heading, so no animation runs, and the cone
is simply correct.

**The mechanism.** `MapMarkerView.setHeading` keeps `headingRotationDegrees` as an *unwrapped*
accumulator — 350° followed by 10° becomes 370°, so a reader crossing north keeps turning the same
way instead of spinning backwards through south. That part was right, and its comment said so at
length. The animation's start point was then read back off the render server:

    cone.presentation()?.value(forKeyPath: "transform.rotation.z")

`transform.rotation.z` is not a stored scalar. It is recovered from the layer's `CATransform3D`, and
it always answers **normalized into `(-π, π]`** however far the value written to it had accumulated.
So at 370° the accumulator said 370 and the render server said 10, and `CABasicAnimation` was handed
`from: 10°, to: 370°`: a full turn, to arrive two degrees along. The two numbers were in different
spaces and nothing in the file said which space either was in.

**Why the suite was green.** `MapHeadingTests` asserted:

    #expect(view.headingRotationDegrees == 370)

That is the accumulator — **the number the code computed**. The number that decides what the reader
sees is the *difference between the animation's two endpoints*, and nothing asserted it. The test was
named `theConeTakesTheShortWay`, and its own comment claimed the accumulated angle was a sufficient
assertion because "the rotation is on the render server and no screenshot can catch which way it went
round". The premise was true. The conclusion did not follow, and the name made the gap invisible for a
round.

**Why no test in that shape could have caught it.** A detached `CALayer` has no presentation layer.
In a unit test `presentation()` answers `nil`, the code falls to its `previous`-based fallback, and
**the defective branch never executes**. A view-level test of this passes against the broken code no
matter how it is written. The defect was only reachable on a real render server — which, for a cone
that requires a magnetometer, means only on a physical phone.

**The repair, and the general rule.** The endpoint arithmetic moved out of the view into
`MapHeading.swingStartDegrees(drawnAt:target:)`, where it is a pure function of two angles and a test
can pass it the exact pair the render server produces. The view now calls it and nothing else.

> When an animation is the deliverable, assert the **animation's endpoints**, never the model value
> that fed them. And when a value is read back out of a framework rather than stored, write down the
> space it comes back in — `transform.rotation.z` round-trips through a matrix and loses every whole
> turn on the way.

**What this cost.** One shipped TestFlight build with a visibly broken feature, found by the owner on
the phone in the first minute of use. The three CLAUDE.md rules that would have caught it were all in
place and all pointed the right way: *look at the running screen*, *a confident comment is where bugs
have survived*, and *map and camera flows only tell the truth on the physical phone*. What was missing
was the one that is now above: a test can be green, precise, and about the wrong number.
