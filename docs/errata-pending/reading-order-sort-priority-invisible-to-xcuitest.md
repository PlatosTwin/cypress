### `accessibilitySortPriority` is invisible to every ordering API `CypressUITests` can reach, and the reason is that all of them report composition order — amends ERRATA E230

#### Why this was reopened

E230 measured one instrument (`debugDescription`, via `DeepLinkHarness.treeOrder`) against one
mutation (screen 01's search field dropped from priority 6 to 2) and found no movement. It closed
with an explicit piece of unfinished business, in its own closing paragraph (`docs/ERRATA.md`, E230,
"Suggested follow-up, not done here") — **not** in `docs/ROADMAP.md`'s "Also outstanding", which
cites E230 by number and does not restate the question. An earlier draft of this entry said it did;
PR #54's review checked and it does not:

> filing whether any lower-level XCUITest API exposes `accessibilityElements`-array order directly
> rather than through `debugDescription`'s dump — not investigated here for lack of time, and worth
> fifteen minutes before assuming it does not exist.

That is the question this entry answers. It is answered in the direction E230 suspected, but the
finding is stronger and more useful than "we tried another API too", because it identifies **what**
these APIs report rather than only what they fail to report — which is what makes the negative
result structural instead of a list of things that happened not to work.

#### The instrument, and the case built to calibrate it

Four arrangements of screen 01's search field and filter chips, selected at launch by a temporary
`CYPRESS_AXORDER` environment variable so **one build** produced all four readings (a rebuild
between conditions is exactly the confound E230 had to argue its way out of with a from-scratch
430-file build):

| mode | composition | geometry | sort priority |
|---|---|---|---|
| `control` | field, then chips | field above chips | field 6, chips 4 |
| `priority` | field, then chips | field above chips | **field 2**, chips 4 |
| `flat` | field, then chips | **chips above field** | **field 4, chips 4** |
| `composition` | **chips, then field** | chips above field | field 6, chips 4 |

`flat` inverts the geometry with `.offset`, which moves the rendered frame without touching layout
order — and the frames in the dump confirm it took effect rather than being assumed: the field is
drawn at y=175 with the chips at y=50, a 125 pt inversion of `control`'s field at y=55 and chips at
y=110.

**`composition` is the calibration case, and it is the reason anything below is believable.** E230
already established that reordering the `VStack`'s children moves `debugDescription`, so its answer
was known before the run. Any probe that could not tell `composition` apart from `control` would be
a broken probe reporting a null result, not a framework limitation — which is the failure mode this
project keeps paying for.

Five probes were read in every mode: `treeOrder(app.debugDescription)`;
`XCUIElementQuery.allElementsBoundByIndex`; `XCUIElementQuery.allElementsBoundByAccessibilityElement`;
a depth-first walk of `try app.snapshot()`'s own `children` arrays; and `.children(matching: .any)`
walked one query per level from the application element (217 nodes visited against a 400-node
budget, so the walk completed rather than truncating).

#### What was measured

iPhone 16e simulator `3A1F212D-8F3A-41F1-AF72-EC95E155A4C9`, 390 pt, one build, four launches.
**All five probes agreed with each other in all four modes**, so one line per mode says everything:

| mode | order reported by all five probes |
|---|---|
| `control` | field → chips |
| `priority` | field → chips — *unchanged* |
| `flat` | field → chips — *unchanged, with the chips drawn 125 pt above the field* |
| `composition` | **chips → field** |

`treeOrder`'s indices make the point in the smallest space: field=164, chips=165 in `control`,
`priority` **and** `flat` — the same two integers, not merely the same relation — against chips=164,
field=169 in `composition`.

#### What this establishes

1. **Sort priority is invisible**, confirming E230 across four more APIs than it tested.
2. **Geometry is invisible too**, which E230 could not have concluded: its second experiment moved
   `MapFilterChips` above `SearchBar` in the `VStack`, and that changes composition order *and*
   geometry together. `flat` separates them, and geometry loses.
3. Therefore **every way of reading the automation snapshot reports raw view-composition order** —
   one `XCUIElementSnapshot`, five traversals and binding strategies over it, none of them a
   computed reading order. The five are **not five independent instruments**, and nothing here
   should be read as five agreeing witnesses: they share one blind spot by construction. That is
   what makes the conclusion general in the direction it IS general — a tree that cannot show an
   element moving 125 pt up the glass will not show a number that only matters to a sort the
   accessibility server performs, whichever way you walk it.
4. `composition` supplies a second, independent proof of (1) that does not depend on (3): the
   shipped priorities were left intact there (field 6 > chips 4) and only the composition changed,
   and every probe reported chips-before-field — the order the priorities say is wrong. A
   priority-aware probe could not have printed that.

**So the answer to E230's fifteen-minute question is: no such SNAPSHOT-READING API exists in this
target, and the reason is not that the right traversal has not been found.** Looking for a sixth
traversal is owed nothing.

**What this does not close, and what the next person should try first.** Snapshot traversal is one
class of API. A **focus engine** is another, and it does not read this tree: order there would come
from the focus system walking the hierarchy, not from the automation snapshot. It is **unprobed by
anyone so far**. PR #54's reviewer attempted it — `typeKey(.tab)` followed by a `hasFocus` sweep —
and got `none`: no element reported focus at all on a simulator without Full Keyboard Access
enabled. That is neither a counterexample nor a working probe, so the honest status is
**inconclusive, and recorded here so it is not re-derived from scratch**. Anyone resuming this
should start by enabling Full Keyboard Access on the device and re-running that probe, and only
then decide whether a focus walk sees anything the snapshot does not. The same goes, a fortiori,
for a real assistive technology, which is E192's physical-phone debt.

#### What was done about it

The gap E230 named — a shipped fix (task #143, E192) with no test behind it — is closed as far as it
can be closed without VoiceOver on a physical phone, and no further:

- **`CypressTests/MapSwipeOrderDeclarationTests`** (new) reads `MapHomeView.swift` off disk through
  `AppSourceLiterals` — the helper `DrawnGlyphGuardTests` (R57) and `BritishSpellingGuardTests`
  (R56) already use for source-level gates — and asserts that the top chrome block's declared
  priorities **descend in the same order the block composes its children**. That agreement is the
  entire reason a composition-order assertion says anything about reading order: if the two ever
  disagree, `ReadingOrderAccessibilityTests
  .testMapFieldPrecedesSuggestionsPrecedesFilterChipsInComposition` keeps passing while asserting
  the opposite of what the app declares, and nothing anywhere says so. It also carries the
  "can this sweep see its subject" test this project's source gates all carry, and that test earned
  its place during the red-proof: with the block's opener perturbed, the descending check **passed
  on an empty list** while the provenance check failed with `declarations.count → 0`.
- The sweep excludes, by indentation, the `VStack`'s own `.accessibilitySortPriority(2)` — that
  number ranks the top block against the bottom chrome, a different comparison among different
  siblings, and including it would fail the suite on a correct tree.

**What is still not proved, and this must not be read as if it were.** That VoiceOver honors the
numbers. That the order a listener actually walks on screen 01 is the declared one. E192's "The
debt" paragraph asked for a physical-phone pass with VoiceOver on, and that debt is unchanged by
this entry. A green `MapSwipeOrderDeclarationTests` means the declaration is internally consistent.
Nothing more.

#### Scaffolding, and why none of it shipped

The `CYPRESS_AXORDER` switch in `MapHomeView` and the probe class in `CypressUITests` were
experiment apparatus and were reverted before this branch's first commit — they are on no branch and
in no history. The measurements above are the artifact; the apparatus is described here in enough
detail to rebuild it in an hour if anyone ever needs to re-run it against a future SDK, which is the
only reason it would be worth rebuilding.

**Say plainly what that costs a reader.** These numbers **cannot be re-derived from the tree — only
re-measured.** Nothing in the repository lets anyone check the `.offset` that produced `flat`, the
400-node budget, or the frames quoted above; the table is the artifact and CLAUDE.md's rule about
not trusting an artifact you did not watch being produced applies to it as much as to anything else.
PR #54's reviewer did rebuild the apparatus independently and reproduced every row (including the
124.3 pt geometric inversion, the identical `priority`/`flat`/`control` indices, and
`visited=218 truncated=false` on the level walk) — so the result has been measured twice, by two
people, from two builds. The next reader after that has this paragraph and a rebuild, not a re-run.
