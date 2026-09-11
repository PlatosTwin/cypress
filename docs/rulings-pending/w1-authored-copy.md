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

---

## Addendum, from branch `web/w1-live-facts` — the gap above is closed, and it cost two more strings

**The owner ruled that W-C stays open and W1 fills the gap.** It does: `src/lib/publicTreeRead.ts`
calls `GET /api/v1/public/trees/{id}` and the fact column now draws §W1's `Height` row, a live
`Trunk · DBH` reading in place of the city's bucket, and a `Beloved` row. The question in the
section above — *does W-C count as done with the pack half alone* — is answered by the owner and
needs no ruling here; what follows are the decisions that filling it required.

### Two more authored strings (constraint 21), both conservative, both wanting ratification

3. **`Beloved`** — the label of a row **§W1 does not draw at all**. It is here because the owner
   ruled on 2026-09-10 that the beloved state ships on the public tree page, *as a state and not a
   rank* (`public-tree-read.md` §1a). Nothing in `Cypress/`, in the mocks or in `SCREENS.md` says
   the word `beloved`; R27.1 does, and it is R27.1's state, so R27.1's word is the label.

   The value is **`3 favorites`**, not `3 people`. The count is of distinct account-backed favorite
   owners, so one person with two Apple IDs is two of them, and `people` would overstate what the
   number is. The plural agrees with the number rather than being hard-coded: the floor makes `1`
   unreachable today, and `1 favorites` would be wrong on the day somebody moves the floor.

   **Where it sits:** last, after every row §W1 draws. The specification's order is a
   transcription and an undrawn row has no place in it to claim.

4. **`Community contributions could not be loaded, so this page shows the city record alone.`** —
   one sentence, shown only when this page could not ask: the API base is unset or unusable, the
   service refused, timed out, answered a non-200, or answered a body this build cannot read.

   It is **not** shown when the service answers and the tree has nothing. That case renders
   nothing, which is the house style and misleads nobody. The sentence exists for the opposite
   case, and the reason is the whole design: without it, "this page could not ask" and "nobody has
   ever measured this tree" would render identically, and the page would assert the second every
   time the first was true. `CYPRESS_PACK_DIR`'s own comment is the same argument — *a default
   would make "not mounted" look exactly like "mounted and empty"*.

   It names no host, no variable and no status code. A reader is owed the fact; the operator's
   diagnosis goes to the process log, which is where W-C already sends this page's refusals.
   `contributions` rather than `measurements`, because the beloved state is not a measurement and
   this sentence covers its absence too.

**Ratify both, or replace the wording.**

### Three decisions taken conservatively, each named so the owner can overrule it

- **A vacant planting site draws no community reading, even when the service has one.**
  `SitePresentation.stats` refuses a measurement on a site because *"the second is a claim about a
  tree"*, and a reading is no less a claim about a tree for having been taped by a person. A
  reading against a basin the city records as empty is a disagreement with the city record — which
  is `data_dispute`'s subject, and which `public.go` withholds from this endpoint by name. The
  beloved state is kept there: a site can be somebody's favorite, and saying so asserts no tree.
  **The alternative** is to draw it, which would make W1 the surface where a community measurement
  silently contradicts the city's own lifecycle column, with nothing on the page saying so.

- **`unavailable` and `unconfigured` say the same thing to a reader.** They are one fact to
  somebody reading the page — this page cannot say — and two facts to an operator, which is what
  `data-community` in the markup and the log line carry. **The alternative** is a second sentence,
  which puts a deployment's internal state in a fact column.

- **The page sends `Cache-Control: public, max-age=60`,** which is the endpoint's own header and
  the ruling's §8b ceiling on the round that renders the page. It is sent on every answer, not
  only on the ones carrying community values: a page with no header is one a cache may keep by
  heuristic for as long as it likes, and the next reader's render is where a withdrawn value
  would reappear.

### One thing this branch did NOT do, and it is the owner's to weigh

**The OpenGraph card does not read the community half.** `og.svg.ts` was being edited in parallel
this round and this branch stayed out of it, so the card renders the pack half alone — its state is
`notRequested`, which is honest but is a disagreement with §W1's own caption: *"the OpenGraph image
is rendered from the same three ingredients so the group-chat preview and the page agree."* It is on
the chip backlog. Nothing about the card is wrong today; it is simply narrower than the page.
