# Rulings (pending numbers): NYC notify-the-City and disclaimer obligations (D12)

**Date:** 2026-08-21. **Decided by:** owner, via decision round. Full grounding, sourcing, and
the drafts these rulings apply to are in `docs/operations/nyc-data-obligations.md`, PR #97
(`docs/nyc-tc-obligations`). D12 of
`docs/design-proposals/2026-08-14-city-data-distribution.md` already settled *that* both
obligations must be discharged before the first NYC publish, trial and beta packs included;
these three rulings settle *how*.

## Ruling 1 — notify-the-City routing: both reachable channels, not one

**Question put to the owner.** The NYC.gov Data Mine terms require notifying "the City," via a
hyperlink on the terms page itself. That link (`nyc.gov/html/contact/contact.shtml`) is dead —
fetched 2026-08-21, it redirects to nyc.gov's generic "outdated or non-existing page." No
dedicated app-notification email or form exists anywhere reachable from NYC Open Data's current
site. Two candidates were found instead: the NYC Open Data general contact form
(`opendata.cityofnewyork.us/engage/`) and the per-dataset "Contact Dataset Owner" route on each
of the two Socrata dataset pages (routes to Parks & Recreation / DPR, the submitting agency).

**Ruling.** Use both. The same note text goes through the general contact form *and* the
per-dataset contact route on each of the two datasets (Forestry Tree Points `hn5i-inap`,
Forestry Planting Spaces `82zj-84is`) — three submissions across two distinct channels, none
treated as sufficient by itself. `opendata@cityofnewyork.us` (unverified) is not used.

**Consequence.** The draft note in `docs/operations/nyc-data-obligations.md` §3 is written to
be sent unmodified through all three; the owner sends it, this repo does not.

## Ruling 2 — disclaimer surface: the in-app city-downloads screen, plus the listing text

**Question put to the owner.** The terms require the verbatim disclaimer "at the site where the
application can be accessed or downloaded." The repo has no existing "product page" concept —
no About/data-sources/attribution screen in the mocks (`docs/distilled/SCREENS.md`), and
CLAUDE.md constraint 21 makes adding one its own stop-and-ask.

**Ruling.** Both surfaces carry the verbatim text: (a) the in-app city-downloads screen
(`Cypress/Features/Cities/CityDownloadsView.swift` and kin — the actual surface offering an NYC
pack, whole-city or per-borough, trial packs included per D12), and (b) the TestFlight/App
Store listing, wherever the app itself is currently distributed. **This ruling is the
constraint-21 sign-off** for adding disclaimer copy to the city-downloads screen — it does not
need to be re-raised as a fresh stop-and-ask when that screen work is built.

**Consequence, binding on sequencing.** The in-app copy change is **not** part of PR #97 (a
docs-only change). It lands with the s17/NYC seed-schema and publish round (design proposal
§6.3) and must be live in that same round: that round cannot publish an NYC pack, trial or
beta, without the city-downloads-screen copy already shipped and the listing text already in
place.

## Ruling 3 — the manifest's `attribution` array does not discharge the obligation alone

**Question put to the owner.** `Tools/publish_cities.py`'s manifest already carries a per-city
`attribution` array (`city-publishing.md`; R36 binding consequence (b)) — machine-readable
`inventory`/`name`/`url`/`snapshot_on`/`license` fields. Does that satisfy the terms' "include
the following disclaimers" requirement by itself?

**Ruling.** No. Human-visible text is required, on both surfaces named in Ruling 2 — for trial
packs exactly as for a general release. The manifest's `attribution` array remains
supplementary, structured provenance; it does not substitute for rendered, human-readable
disclaimer text.

## Consequences that apply across all three

- Agents building the s17/NYC publish round should treat Ruling 2's sequencing as a hard
  precondition on that round's own "first NYC publish" gate, alongside D20's 90%-species-
  coverage gate — not as a separate, later ticket.
- Agents should not re-raise these three questions as open; they are decided. Any future
  question about *whether* the routes/surfaces in Rulings 1–2 are sufficient is a new question,
  not a re-litigation of these three.
