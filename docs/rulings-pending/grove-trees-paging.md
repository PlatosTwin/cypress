# Rulings pending — Grove > Trees paging (owner decisions, 2026-09-02)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge and rewrites any comment that cites this filename. **No code comment in this round
cites it by filename**: `GroveModel.TreesPhase`, `GroveModel.TreesDrawing`, `GroveView.treesTab`,
`GroveView.moreBlock`, `GroveTreesPresentation` and `GroveTreesPagingTests` each say "the owner
ruled on 2026-09-02" in prose and describe the behavior, rather than pointing at a number that does
not exist yet.

Two entries, decided together from one report. They are separable, and either without the other
leaves half of the reported problem standing: paging alone still shows a blank column while the
first page is read, and a loading state alone still builds a thousand rows before it can stop.

---

## What was reported

**My Grove's Trees tab is blank for seconds before anything appears**, on a grove of about a
thousand trees. Measured on an iPhone 16 Pro at 1,027 trees: **3.3–3.7 s** of a screen with a
selected pill above it and nothing under it, photographed as a run of empty frames.

The database was not the cause and had already been fixed twice — `treeSQL()` per tree (#250) and
the unscoped `heroPhotoIDs()` sweep (#176). At 1,027 trees the five statements still total about
38 ms. What remained was above the query: `LocalAPI.grove()` returned the whole grove, a thousand
`GroveEntry`s became a thousand `IconTextRow`s in a non-lazy `VStack`, and none of it reached the
glass until all of it was built.

The second fact is that `GroveModel.TreesPhase` had no case for "the read is in flight". `.idle`
covered both "nobody has opened this pill" and "the read is running", and `GroveView` matched none
of its arms in either — so the column drew nothing at all.

---

### R??? — Grove > Trees pages, the way Journal > Yours pages

**Date:** 2026-09-02. **Decided by:** owner. **Implemented by:** this round (PR #149).

The Trees list is paged so the first page paints immediately, and the rest is revealed by the
affordance `Journal > Yours` already has — the same components and the same tokens, inventing no
new UI vocabulary. This is the constraint-21 half of the ruling: the mocks show no paging control
on screen 08, and the decision is to **reuse an existing one rather than draw a new one**.

**Page size 50.** Not specified by the owner and chosen the way `JournalLimits.pageSize` was: by
what the phone draws rather than what the store can answer. A grove row is about 100 pt, so an
iPhone 16 Pro shows seven to eight of them and fifty is six or seven screenfuls — enough that the
first `Show more` is a deliberate act. Twenty-five was tried and rejected for the opposite failure:
on a grove of a thousand it puts the control in front of somebody twenty times.

**One word departs from the journal's copy, and it is the ruling's own logic applied to this
list.** `JournalCopy.olderNote` says "earlier" and explains why: the journal is ordered by time, so
what is behind the cursor is a *direction*. A grove is a set of nouns, not a chronology, and its
tail is the trees nobody has visited — which are not earlier than anything. So the note says
"more". Copying the journal's sentence verbatim would have reused its words while contradicting its
reason, on the one screen the owner has already had to say reads too much like the journal.

Neither the note nor anything else states how many trees there are (D1, ERRATA E38).

---

### R??? — Every phase of the Trees column draws something

**Date:** 2026-09-02. **Decided by:** owner. **Implemented by:** this round (PR #149).

A blank column is a defect **at any duration**. The phases are now exhaustive over things that can
be drawn, and the exhaustiveness is a fact about the type rather than about a comment:
`GroveModel.TreesDrawing` has no case meaning "nothing", so a phase that draws nothing cannot be
reintroduced by leaving a `switch` arm out — which is exactly how the blank existed for two rounds.

The treatment for a read in flight is a bare `ProgressView()`, which is what screens 03, 07, 11, 13,
15 and the launch gate already use. A skeleton or a message would be a drawing and a sentence that
appear in no mock (DECISIONS constraint 21).

**This supersedes a measured, documented decision, and that is the point worth recording.**
`docs/whats-new/fix-grove-tab-performance.md` explicitly considered a loading state and declined it,
on a measurement: at 26 ms on a forty-tree grove, "a spinner visible for two frames reads as a
flicker rather than as progress", and the note says the measurement came first and the decision
second. That reasoning was correct and is not being overturned as reasoning. What broke was its
**premise** — that the read is fast because the grove is small. At 1,027 trees the same column was
blank for 3.3–3.7 s, and a rule of the form "no loading state below N milliseconds" cannot hold on a
list whose length is the reader's own history.

So the ruling is the stronger form: **draw something in every phase, and do not condition that on a
duration**, because the duration is a function of data the app does not control.

---

## What these rulings do not decide

- They do not say the account's half must arrive before the first paint. It does not; the merged
  answer is folded in behind the painted page, which is the 2026-09-01 ruling one round earlier and
  is unchanged here.
- They do not set a page size for any other list. `JournalLimits.pageSize` is the journal's and is
  untouched.
- They say nothing about the Species pill, which was not reported and is not changed.
