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

### The conflict: decision 1 says the community read comes first, and W-C built W1 without it

`docs/rulings-pending/web-round-owner-decisions.md` records, as the round's **first** decision:
"The public community read is built BEFORE W1, not after it", chosen over shipping the city-record
spine with the contributed rows absent.

W-C's brief and `docs/ROADMAP.md`'s W-C row both say the opposite — "v1 renders city-record facts
only" — and that is what this branch built. The page is therefore **the option the owner did not
take**, shipped without the community read, and the two documents have been disagreeing since
2026-09-10 without either being marked stale.

This branch followed the brief and the roadmap, conservatively: the contributed half is *omitted*
rather than stubbed, so nothing on the page would have to be unsaid if the community read lands and
the rows arrive. Nothing about the page's structure resists them — the fact column is a list the
model builds, and a row absent for lack of a source looks identical to a row that has not been
written yet.

**What is wanted is one sentence saying which document is now current**, so the next round does not
re-litigate it: either decision 1 stands and W1 is incomplete until the community read exists, or
the roadmap's scoping supersedes it and decision 1 should be struck where it is recorded.
