# Unnumbered — the orchestrator splices this under the next E number at merge (CLAUDE.md,
# Numbering). Written from branch `web/public-tree-read`, 2026-09-10, round W-G.

### `SCREENS.md` §W1 draws elements that no public read may answer, and misses one it should

The web proposal's §8a amendment established that W1's fact column is about half contributed data and
that the published packs answer none of it. This entry is the narrower finding underneath that one:
**two of those elements are not merely unanswered today, they are elements a public page may not
carry at all**, so W-C will build a §W1 that is deliberately short of its transcription, and the
disagreement is recorded before the code rather than discovered inside a component.

**The heading said "two elements" and the count moved twice after the adversarial review of this
round's PR**, so it is stated here rather than left to be counted: the fact column loses the
recent-visits panel and the photo count (refusals on the merits, §1 and §2), loses the `Status` row
as well (a **deferral** — §4 — because a published rating has no way back off the page), and gains
the *beloved* state, which §W1 does not draw and the owner ruled on 2026-09-10. Short in three
places, long in one.

> **Corrected after the adversarial review of this round's PR. The wrong claim is quoted, not
> deleted.** This entry opened by citing "the standing rule": *"Every screen is implemented against
> `SCREENS.md`, which is the transcription; the mock is the check, not the source. Where they
> disagree the disagreement is an ERRATA entry before it is a code change"* (`ROADMAP.md:65`), and
> then said *"Here the transcription disagrees with the product rules rather than with the mock,
> which is the same obligation from a different direction."*
>
> **The quotation is exact and the inference is not.** That rule's trigger is a conflict between
> **two sources** — SCREENS versus the mock — and here the two agree; both draw the panel and both
> draw the count. It says nothing about an element being *refused* once transcribed. The review
> searched the corpus for a rule that does and found none: `ROADMAP.md:69` covers **inventing** an
> unmocked state (DECISIONS constraint 21) and routes its resolution to the ROADMAP rather than to
> errata, and `ERRATA.md`'s own charter scopes this shelf to *"facts in the handoff documents that
> turned out to be wrong when we went to build against them"*. The observed practice elsewhere is a
> third thing again: a refused element is struck through **in `SCREENS.md` itself**, annotated in
> place with the authority (worked examples at `SCREENS.md:1129` and `:1276`).
>
> **This entry is still the right instrument and it stays.** What is withdrawn is the claim that
> writing it followed a documented rule. It did not; it created one, and the round asks the owner to
> ratify that as a rule — the ruling's **Q8** — rather than leaving three conventions in the corpus
> for one situation. A reader who goes looking for the obligation this paragraph asserted will not
> find it, which is exactly the shape of thing this shelf exists to catch.

Written, therefore, on its own footing: a transcribed screen draws two elements that the product
rules forbid a public page from carrying, the next author will otherwise implement them or spend an
afternoon working out why they are missing, and that is worth a durable record whether or not a rule
compelled one.

**1 · The recent-visits panel.** §W1 draws it at `margin-top:auto` in the fact column: three rows,
each a 26×26 gradient chip and a trailing mono date — `"Fog dripping off the crown"` `Oct 12`,
`Watered, mulched` `Sep 28`, `"Cones everywhere this year"` `Sep 14`. Two of the three rows are
verbatim contributor prose.

A dated list of visits to a fixed point, on a page indexed under that point's address, is a public
user location history — which PRODUCT's non-goals table answers with one word. The row entire,
`PRODUCT.md:49`: `| Public user location history | Never. |` The rationale cell is that word and
nothing else, and the row is unconditional as to attribution: it forbids the history, not the byline.
The prose is unscreened and unscreenable: `photos` has a moderation state machine, a CHECK forcing
`approval_reason` before `approved`, and an operator takedown route, and `contributions` has none of
those. And the rows would carry claims that are not adjudicated — `ObservationStatus.appearsDead` and
`.appearsRemoved` *open review flags* rather than asserting anything (DECISIONS §3.7), and
`StructureFlag` may not appear on any surface without its verbatim disclaimer, *"informal
observations, not a risk assessment"*.

**2 · The photo count in the hero caption.** §W1's caption is
`FOLIAGE · JAN THROUGH DEC · 214 PHOTOS SINCE 2019` (`SCREENS.md:1621`).

> **This paragraph is rewritten; the version the review found is quoted first.** It read: *"R27.1 §5
> already answered this exact number — 'Favorites only. The owner was explicit that photo counts are
> not wanted here' — and PRODUCT's non-goals name 'leaderboards or ranked counts of
> photos/check-ins/care/favorites' as a thing not to build. It is not caught by D1's own wording,
> because D1 forbids counting people's actions and this counts a tree's photographs; R27.1 is the
> ruling that draws that distinction and then declines this number anyway."*
>
> **R27.1 §5 governs which signal the beloved-trees *ranking* uses**, and what it forbids is blending
> signals into a composite score. It does not rule on a lone per-tree count, and "already answered
> this exact number" overstated it into the authority the whole refusal leaned on. The quotation from
> §5 is exact, and it is real evidence of the owner's disposition — but it is a disposition inside a
> ranking, not a prohibition.

The refusal stands on the narrower ground the ruling's §1 now argues. **The count is a public count
of user actions**, which ARCHITECTURE §5 rule 1 forbids without qualification as to noun — *"No
streaks, points, ranks, badges, or public counts of user actions"* (`ARCHITECTURE.md:113`), the
constraint form of D1. R27.1 did carve out one exception, a per-tree count of distinct favoriters
above a floor, so **the honest question is whether that carve-out reaches photographs** rather than
whether a blanket rule catches them. Two things say it does not: R27.1 §5's *"Favorites only. The
owner was explicit that photo counts are not wanted here"*, which is the nearest thing to an owner
ruling on photograph counts that exists; and the fact that the carve-out's safety mechanism is a
floor, which cannot be applied to this number because the number **is** the drawn headline fact —
printing it above a floor and hiding it below one publishes "fewer than three people photographed
this tree", the same disclosure with a step.

PRODUCT's non-goals row is quoted exactly here because the earlier version lower-cased and shortened
it: `| **Leaderboards or ranked counts** of photos/check-ins/care/favorites | Pays users to spam the
record, poisons the health time series at the source. "The leaderboard is dead." |` (`PRODUCT.md:40`).
A bare count on one tree's page is not a *ranked* count, so this row is supporting rather than
dispositive, and it is offered as that.

**3 · The H1 has no source in either half of the system**, which is a gap rather than a refusal.
`Grandmother Cypress` is a contributed name, and there is no name column in the seed contract and no
naming mutation in `contributions.kind`'s seventeen values (`004_measurement_withdrawal_kind.sql`);
`community_trees` in `001_initial.sql` records having deliberately *removed* a `display_name`. So W-C
has nothing to render in 42px serif except the species name from the pack — and `common_name` is null
on real rows (§8a).

**4 · And one element is refused that §W1 does *not* draw a problem with: `Status · Thriving ·
vitality 4`.** Added after the review. The rating is a property of the tree and passes every test in
the ruling's §1–§7 — it is refused because **nothing in this system can take a published rating
back**: there is no observation-withdrawal kind, `contributions` has no `moderation_state` and no
operator takedown, and a withdrawal aimed at one answers `applied` and changes nothing. The ruling's
§8 had closed ROADMAP question 2 on a mechanism that covers two of the three values it then
published. Restoring the rating is a migration and a round with a migration author; until then W-C
draws nothing where `Status` is, and this is a **deferral**, not a refusal on the merits like 1 and 2.

**Resolution: build W1 without the panel, without the count and without the `Status` row**, and take
the H1 to the owner. §W1 gains one element it does not draw — the **beloved** state, ruled by the
owner on 2026-09-10 and returned as a boolean above a ≥3 floor — so the fact column is short of its
transcription in three places and long in one. The argument for each is in
`docs/rulings-pending/public-tree-read.md` §1, §1a, §2 and §8, and the owner is asked to ratify the
two refusals and to answer the H1 in that file's questions. Recorded here rather than
only there because the next reader to open §W1 and count six fact rows plus a visits panel against a
page that draws neither deserves to find the answer in the errata, which is where this project puts
disagreements with a transcribed screen.

**Not a new finding, and checked before it was written:** the URL on the same screen —
`cypress.app/sf/tree/9f3a-monterey-cypress` — is already **E60**. `SharePresentation.publicURL` builds
the real link from the tree's lowercased UUID and its doc comment explains why the mock's short slug
cannot name a tree in a 195,309-row inventory. W-C's route is a UUID, and that was settled.
