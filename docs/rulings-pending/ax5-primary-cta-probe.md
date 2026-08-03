### R?? — The AX5 primary-CTA probe: what it asserts, and the two things it cannot see (task #173, delegated)

*Pending. Cite this file as `docs/rulings-pending/ax5-primary-cta-probe.md` until the orchestrator
splices a number; #173 delegated the shape of the probe.*

#### The ruling

**`CypressUITests/PrimaryCTAReachabilityTests` launches each deep-linkable screen that has a primary
CTA at `UICTContentSizeCategoryAccessibilityXXXL`, and asserts of that control:**

1. it **exists** in the accessibility tree;
2. it is **reachable** — hittable where it is, or hittable within eight swipes;
3. it is **enabled**, after the screen's own arming step where it has one;
4. it can be brought **wholly onto the glass** — the frame inside the app's frame;
5. it is **drawn** — the frame has a width and a height;
6. its label carries **no ellipsis except as a final character**.

One `test…` method per screen, so a failure names the screen and one broken screen does not hide the
ten behind it. `testEveryTargetInTheTableIsProbed` guards the table against a target being added with
no method to call it — a row this suite would report on and never visit, which is
`Test run with 0 tests passed` in another costume.

This is the structural closure E196 asked for and could not build in-process: **SwiftUI populates no
UIKit accessibility tree under `UIHostingController`**, so a "the CTA is in the AX5 tree" assertion
was built for #144, watched fail on every screen, and removed. `CypressTests/AccessibilityTests`'
header records the dead end. **The sweep photographs; this asserts.**

#### The scope, stated as a list rather than left as a gap

Eleven screens, each with the CTA literal it is judged on:

| deep link | CTA | armed by |
|---|---|---|
| `treeProfile` | `Be the first to photograph this tree` / `Visit · say hello with a photo` | — |
| `photoHero` | the same pair, warm | — |
| `checkIn` | `Save check-in` | — |
| `measure` | `Save measurement` | tap `3` |
| `careLog` | `Done` | tap `Watered` |
| `report` | `Save a private reminder for yourself` | tap `Hanging limb` |
| `site` | `Show me where this is` | — |
| `memorial` | `Show me where this is` | — |
| `growthHistory` | `Add a reading` | — |
| `share` | `Copy link` | — |
| `pinAdjust` | `Use this spot` | — |

Two CTA labels because `TreeProfilePresentation.ctaTitle` is genuinely two-valued on whether the
tree is cold, and which one a device sees depends on what previous runs wrote onto it.

**The deep-linkable screens deliberately absent, and why** — because a table with a hole in it and no
note beside the hole is how a probe comes to be believed about screens it never visited:

- `outbox`, `activity`, `journalList`, `grove` — no primary CTA exists. These are readers and lists
  whose only controls are navigation chrome, a wifi toggle, and empty states.
- `species` — its content forks on whether there is a fix, between a list of nearby trees with
  runtime names and a `LocationPrompt`. Neither is a CTA.
- `journal` — its CTA (`Walk the …`) is real but conditional on a coverage gap existing in the
  resolved neighborhood, which is a property of the seed and the fix rather than of the screen. It is
  asserted by `AlmanacGroupTapTests`, which since #121 pins its own fix and no longer skips.
- `deadProfile`, `speciesClaim`, `speciesUnclaimed`, `recordDefect`, `anonymizedPhotos`,
  `communityPhotos`, `photos`, `you`, `moderationReview` — either the same `TreeProfileView` CTA the
  two profile rows already judge, or a screen whose loudest control is a per-row action with a
  runtime-composed label. Adding them would grow the run without adding a distinct geometry.

The arming steps are not workarounds. Screen 16's save is disabled until a reading is entered and
screen 09's `Done` until a care chip is on — specified states (PROTOTYPE-FLOW §1.3/§1.4) — and screen
06 draws no CTA at all until a hazard is chosen. A probe that read the disabled control and called it
reachable would assert the opposite of its own name.

#### The honesty note: what "not ellipsized" can and cannot mean here

**`XCUIElement.label` is the accessibility label — the string SwiftUI was handed — and not the glyphs
that were drawn.** A `Text` rendering `Continue with Goo…` on the glass reports its whole string to
XCUITest. Measured on this run: `treeProfile`'s CTA reports
`Be the first to photograph this tree` in full at AX5, in a frame 192 pt tall — the ramp wrapped it
across five lines and the label is unchanged either way, which is exactly the property that makes
truncation invisible to this API.

So check 6 catches **only truncation that happened before rendering**: a presentation layer that
shortened its own copy, or a label built from an already-elided string. **It does not catch visual
mid-word clipping inside a button whose frame is on screen**, which is precisely what E196 items 5
(screen 10's `Mes sa…`), 6 (screen 15's `Continue with Goo…`) and 7 (screen 07's `Cupressac eae`)
are. No XCUITest API on this platform exposes the rendered text. **Those defects remain the sweep's
job and a person's eye**, and this probe does not close them.

The trailing-position exemption is not a loophole. `Share…` is a real CTA on screen 10 and its
ellipsis is copy, not damage; an ellipsis anywhere else in a label is a string that was cut. That is
the only distinction the API leaves room for.

What check 4 *does* catch, and a picture makes easy to miss, is a CTA pushed off the edge of the
glass — E196 items 1 and 3, content wider than the phone, centered and clipped rather than wrapped.
No amount of vertical scrolling repairs that, so it spends the budget and fails.

#### Two design corrections, both made after watching the probe report defects that did not exist

Recorded because each one *looked* like a finding, and filing either would have been worse than not
looking.

1. **Existence is polled inside the scroll loop, not before it.** The first version waited for the
   CTA to exist and only then scrolled it into view, on the reasonable premise that an off-screen
   element is still in the accessibility tree. At AX5 that premise is false here: screens 03 and 11
   hold their CTA in a scroll the ramp makes several screens long, and the control is not in the tree
   until the scroll is dragged near it. Both reported `no button labeled … is in the accessibility
   tree` — a true sentence about the query and a false one about the app.
2. **"On the glass" means *can be brought* on, not *is* on.** Screen 16's CTA is inside a
   `ScrollView`; `isHittable` asks only whether the centre point receives the tap, so the loop
   stopped with the button's bottom 56 pt below the glass and check 4 failed on a state one more
   swipe would have fixed. Where a CTA in a scroll happens to sit is not a fact about the layout.

And one assertion deliberately **not** made: a 44 pt minimum tap target. Several controls here reach
44 through `cypressHitArea(_:)`, which puts a `Color.clear` of at least 44 × 44 in the *background*
with its own `contentShape`. A SwiftUI background does not enlarge the view it sits behind, so the
element's accessibility frame stays the size of the drawn label while the region that receives the
tap is larger — screen 11's `Add a reading` is a 13 pt bold link with exactly that arrangement.
Asserting 44 pt on the reported frame would measure the wrong rectangle. Tap targets are #183's
question, answered at the value level with a tolerance, where the real geometry is in scope.

#### What the probe found on its first run

A defect in the deep-link harness itself, not in any screen: `DebugDeepLink` resolved records from
`LocalAPI.treesNear`, which returns the **seed's** status, while every screen it opens reads
`LocalAPI.treeProfile`, which lays the device's **local status overrides** on top. See the pending
errata `docs/errata-pending/deep-link-harness-status-overrides.md`. `CYPRESS_SCREEN=treeProfile` had
been opening a *removed* tree — no primary CTA, no check-in — on any device that had ever opened
screen 19, and `DeepLinkVoiceOverTests` passed throughout because it checks that the controls which
*are* there carry labels.

That is the case for this probe in one paragraph: the property it asserts is the one the AX5 pictures
were being read for, and nothing else in the repository asks a deep-linked screen whether the control
it exists to have pressed is on it.

#### The proof

- Green on the final tree: `Executed 12 tests, with 0 failures`, iPhone 16e `3A1F212D-…`, 390 pt.
- Red-proofed twice on the device, both messages read rather than the colour:
  - **a renamed CTA** (`CheckInCopy.saveCTA` → `REDPROOF save check-in`) →
    `checkIn: no button labeled "Save check-in" is in the accessibility tree at AX5, after 8 swipes
    down the screen. What is there instead: "REDPROOF save check-in", "Back", "Alive", …` — the
    diagnostic list naming the renamed control is what turns this failure from a riddle into a report.
  - **a CTA pushed off the glass** (`.offset(x: 60)` on screen 16's `ctaBlock`) →
    `measure: the primary CTA "Save measurement" could not be brought entirely onto the glass at AX5
    in 8 swipes — its frame is (78.0, 377.7, 354.0, 138.0) and the screen is (0.0, 0.0, 390.0,
    844.0)`.
