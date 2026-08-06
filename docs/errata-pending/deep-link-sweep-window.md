### EXXX — `DeepLinkSweepTests`'s outbox flake was a push-transition race in the test, not a reading-order defect (task #242)

*UNNUMBERED — the orchestrator splices the number at merge and rewrites the code citations. Filed
from branch `test/242-sweep-window`. Cites E242 for family history.*

---

#### The two flakes, and why they're the same failure caught at two different moments

`CypressUITests/DeepLinkSweepTests.testEveryPushedScreenSaysWhereItIsFirst` failed twice on CI's
loaded runners, both on the outbox arm, in `ui (3)`:

- Run **31074532263**: "the first control in the element tree is 'Outbox, What is waiting to send,
  and what has gone' rather than Back" and "the first words read are 'You' rather than the
  screen's own name".
- Run **31082691131**: "the first control in the element tree is 'Sign in, Gather what you save
  under one name on this phone' rather than Back" and the same "'You' rather than the screen's own
  name".

E242 already established that this suite had **no substantiated failures** before the night these
occurred, so the family history here starts clean — this is a new mechanism, not a recurrence of
anything E242 closed.

#### The mechanism

`outbox` is deep-linked through the You tab. A `NavigationStack` push keeps the OUTGOING screen
(the You tab, its tab bar, its rows) in the accessibility tree for the length of the slide
transition — the incoming screen's elements enter the hierarchy at the *start* of the animation,
not once it settles. `DeepLinkHarness.arrive()` waits only for `waitForExistence` on the pushed
screen's anchor text, which is satisfied the instant the incoming title enters the tree — while the
outgoing You tab is still present, still hittable, and still ahead of the incoming screen in
`debugDescription`'s depth-first order. The test then read `app.debugDescription` immediately.

Both runs' second assertion ("first words read are 'You'") is the outgoing You tab's own tab-bar
item — proof the tree read was the tab root's, not the pushed Outbox screen's. The two different
"first controls" are the You tab's `IconTextRow` rows (`Cypress/DesignSystem/Components
/IconTextRow.swift`), whose default SwiftUI button-label combining produces exactly the two
strings both runs reported: `YouCopy.outboxRowTitle` + `YouCopy.outboxRowSubtitle` = "Outbox, What
is waiting to send, and what has gone" (`Cypress/Features/You/YouTabView.swift`), and
`AccountCopy.signInTitle` + `AccountCopy.signInSubtitle` = "Sign in, Gather what you save under one
name on this phone" (`Cypress/Features/You/AccountSection.swift`). Two snapshots of the same
outgoing tree, caught at different points in the same transition — not two different defects, and
not a reading-order defect in the app at all.

The window is structural to every push the sweep does, not specific to the You tab — the fix
applies the same wait to all nine arms.

#### The fix, and the one it isn't

Added a wait, after `arrive()` and before reading order, for the tab bar (`app.buttons["My
Grove"]`) to stop being hittable — the same signal `DeepLinkHarness.check()` already asserts,
one-shot, as one of its two witnesses that a deep link actually pushed rather than landing on a tab
root. Turned into a genuine `XCTWaiter` wait here because the race is exactly that a one-shot check
run too early would still read the outgoing screen.

A title-text identity wait (`app.staticTexts[title]`, gated with `settledFrame`) was tried first
and rejected on evidence, not preference: `site`'s `ScreenHeader` title is `SiteCopy.headerTitle =
"Site"`, and the same screen's stat grid carries `SiteCopy.siteLabel = "Site"` as a second,
permanent element with the identical label. That collision isn't a race — both elements are on
screen at steady state — so a label-based wait raised `"Multiple matching elements found"`
deterministically on every run rather than ever settling. The tab-bar-departure signal doesn't
depend on any screen's copy being unique, which is also why it generalizes to all nine arms without
a per-screen exception.

**Not tautological.** The wait establishes only that the outgoing tab root is gone — never that
`Back` is first, and never anything about the `Back` button itself. Red-proofed by temporarily
changing the expected first-button literal from `"Back"` to a value guaranteed wrong, running the
full sweep: all nine arms — including outbox — failed for the order reason, and the failure message
named the real, settled first control (`'Back' rather than RED-PROOF-WRONG-EXPECTATION`), not a
mid-push artifact. Restored, then run twice more consecutively green
(`Executed 2 tests, with 0 failures`, `XCTest skipped=0`, run device iPhone 16 Pro Max
`DE8E11AE-4375-4C3B-A296-9B60A7DF1DB3`).

Full `CypressUITests` suite on the same device and worktree, head `6d44d02`: `Executed 92 tests,
with 0 failures`, `** TEST SUCCEEDED **`, `XCTest skipped=0`. Warnings certified on a fresh
DerivedData build (`Tools/verify_test_log.sh --warnings`): `SwiftCompile tasks=438`, `0 source
warnings`, `DeepLinkSweepTests.swift` confirmed among the compiled files.
