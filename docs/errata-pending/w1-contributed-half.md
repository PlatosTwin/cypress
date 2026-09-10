# Unnumbered — the orchestrator splices this under the next E number at merge (CLAUDE.md,
# Numbering). Written from branch `web/public-tree-read`, 2026-09-10, round W-G.

### `SCREENS.md` §W1 draws two elements that no public read may answer

The web proposal's §8a amendment established that W1's fact column is about half contributed data and
that the published packs answer none of it. This entry is the narrower finding underneath that one:
**two of those elements are not merely unanswered today, they are elements a public page may not
carry at all**, so W-C will build a §W1 that is deliberately short of its transcription, and the
disagreement is recorded before the code rather than discovered inside a component.

The standing rule is the ROADMAP's: *"Every screen is implemented against `SCREENS.md`, which is the
transcription; the mock is the check, not the source. Where they disagree the disagreement is an
ERRATA entry before it is a code change."* Here the transcription disagrees with the product rules
rather than with the mock, which is the same obligation from a different direction.

**1 · The recent-visits panel.** §W1 draws it at `margin-top:auto` in the fact column: three rows,
each a 26×26 gradient chip and a trailing mono date — `"Fog dripping off the crown"` `Oct 12`,
`Watered, mulched` `Sep 28`, `"Cones everywhere this year"` `Sep 14`. Two of the three rows are
verbatim contributor prose.

A dated list of visits to a fixed point, on a page indexed under that point's address, is a public
user location history — which PRODUCT's non-goals table answers with one word, *"Never."* The prose
is unscreened and unscreenable: `photos` has a moderation state machine, a CHECK forcing
`approval_reason` before `approved`, and an operator takedown route, and `contributions` has none of
those. And the rows would carry claims that are not adjudicated — `ObservationStatus.appearsDead` and
`.appearsRemoved` *open review flags* rather than asserting anything (DECISIONS §3.7), and
`StructureFlag` may not appear on any surface without its verbatim disclaimer, *"informal
observations, not a risk assessment"*.

**2 · The photo count in the hero caption.** §W1's caption is
`FOLIAGE · JAN THROUGH DEC · 214 PHOTOS SINCE 2019`. R27.1 §5 already answered this exact number —
*"Favorites only. The owner was explicit that photo counts are not wanted here"* — and PRODUCT's
non-goals name *"leaderboards or ranked counts of photos/check-ins/care/favorites"* as a thing not to
build. It is not caught by D1's own wording, because D1 forbids counting *people's* actions and this
counts a tree's photographs; R27.1 is the ruling that draws that distinction and then declines this
number anyway.

**3 · The H1 has no source in either half of the system**, which is a gap rather than a refusal.
`Grandmother Cypress` is a contributed name, and there is no name column in the seed contract and no
naming mutation in `contributions.kind`'s seventeen values (`004_measurement_withdrawal_kind.sql`);
`community_trees` in `001_initial.sql` records having deliberately *removed* a `display_name`. So W-C
has nothing to render in 42px serif except the species name from the pack — and `common_name` is null
on real rows (§8a).

**Resolution: build W1 without the panel and without the count**, and take the H1 to the owner. The
argument for each is in `docs/rulings-pending/public-tree-read.md` §1 and §2, and the owner is asked
to ratify the two refusals and to answer the H1 in that file's questions. Recorded here rather than
only there because the next reader to open §W1 and count six fact rows plus a visits panel against a
page that draws neither deserves to find the answer in the errata, which is where this project puts
disagreements with a transcribed screen.

**Not a new finding, and checked before it was written:** the URL on the same screen —
`cypress.app/sf/tree/9f3a-monterey-cypress` — is already **E60**. `SharePresentation.publicURL` builds
the real link from the tree's lowercased UUID and its doc comment explains why the mock's short slug
cannot name a tree in a 195,309-row inventory. W-C's route is a UUID, and that was settled.
