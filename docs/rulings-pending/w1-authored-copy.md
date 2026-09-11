# Unnumbered — the orchestrator splices this under the next R number at merge (CLAUDE.md,
# Numbering). Written from branch `web/w1-tree-page`, 2026-09-11, milestone W-C. It asks for two
# things: ratification of two authored strings, and a decision on an ordering conflict the brief and
# an existing ruling disagree about.

### Two sentences on W1 were authored rather than ported, and want a ruling

Everything else the public tree page says already existed in Swift, over the same columns, and is
checked against the Swift parsed at run time — the five status labels (`SegmentedControl`), the
`city record` badge (`MethodBadge.label`), the DBH range format
(`TreeProfilePresentation.cityDBHRangeText`), the record number (`CityRecordCopy.recordNumber`, R28),
the provenance sentence (`CityRecordCopy.provenanceNote`), the non-value markers
(`CityRecordCopy.noValueMarkers`), both fallback titles (`TreeProfilePresentation.fallbackTitle`
= `Tree`, `SiteCopy.fallbackTitle` = `Planting site`) and the vacant-site kind (`SiteCopy.kind`).

**Two strings have no original**, because the situation they describe does not arise in the app —
the phone never renders a license line:

1. `no license recorded` — the `Data` row's value when the publisher's receipt carries no license
   for that inventory. This is San Francisco's state on the pinned seed, so it is what most rendered
   pages will say.
2. `Cypress states each source’s own terms and says nothing where the record carries none.` — the
   note under it.

Both follow from the web round's fourth owner decision ("state each source's own terms"), which
ruled the *policy* and not the words. The second was deliberately written to state what Cypress
does rather than what the city failed to do: the receipt's silence is a fact about the publishing
pipeline, and a sentence implying a public works department withheld a license would assert
something nobody measured. **Ratify, or replace the wording.**

### W-C shipped the pack half; W-G's endpoint landed while it was in flight

**Written after merging `origin/main` into this branch, which is where the situation changed.** An
earlier draft of this section reported a document conflict — the round's first owner decision says
"the public community read is built BEFORE W1, not after it", while the W-C brief and
`docs/ROADMAP.md`'s W-C row say "v1 renders city-record facts only". That framing is now obsolete
and is not worth ratifying: **#163 merged, W-G is done, and the ordering the owner asked for was
honored.** The two documents were describing two halves of one plan, not disagreeing.

So the honest statement of where this leaves W1 is a gap, not a contradiction:

`GET /api/v1/public/trees/{id}` exists and this page does not call it. W-G's own ruling settles what
it answers of §W1's fact column — the **latest live height** (value, entered unit, method, month),
the **latest live trunk DBH** in the same shape, and the **beloved** state with its count above the
floor. W1 therefore has three elements available to it today that this branch renders as absences,
and `ROADMAP.md`'s W-G notes already assume the page will draw them ("Restoring the `Status` row on
W1 depends on (a)").

That work is written into the chip backlog as item **26** rather than held here, because it is a
task and not a decision. **What is a decision, and is the question:** does W-C count as done with
the pack half alone — the roadmap row is struck on that basis — or should the row stay open until
W1 renders what W-G publishes? Either answer is fine; the two documents should say the same one.

Nothing in this branch resists the addition. The contributed elements are *omitted*, not stubbed, so
no copy has to be unsaid; the fact column is a list `facts()` builds from a model, and a row absent
for lack of a source is indistinguishable from a row not yet written.
