# Unnumbered — the orchestrator splices this under the next R number at merge (CLAUDE.md,
# Numbering). Written from the web round's orchestration session, 2026-09-10. It records seven owner
# decisions taken across two question rounds that day, plus one taken by the orchestrator under the
# autonomy grant. `docs/rulings-pending/web-version-round.md` carries the four that opened the round;
# these are the ones that followed, each taken with the evidence in front of it.

### The web round's second and third decision rounds (owner-ratified, 2026-09-10)

**1. The public community read is built BEFORE W1, not after it.**

The finding that forced the question: `SCREENS.md` §W1's fact column is about half city record and half
contributed data. The packs answer address, city, species, `planted_year`, `external_ref`,
`inventory_source`, status and the city's DBH bucket. They do not answer the tree's **name** (there is
no name column in the seed contract), its **vitality** (declared in `AppSchema`, the *writable*
database), any **measured height or taped DBH**, the **photo count**, or the **recent-visits panel**.
All of that is the community layer, behind an API whose read surface is Class R — the contributor's
own data.

Three options were put: ship the city-record spine now with the contributed rows genuinely absent;
build a public community read first and then the full W1; or defer W1 and build the other three pages.
**The owner took the second.** The consequence is accepted deliberately: v1 grows a new public server
surface and a privacy ruling, and is therefore larger than "a public read surface" as first scoped.

*Note for the round that builds it:* because the web app is **server-side rendered on Fly**, it calls
`cypress-sync` server-to-server. **CORS is not required for v1** and should not be built speculatively.

**2. The public site is `cypressgrove.app`.**

`cypress.app` — the domain `ShareCopy.publicURLPrefix` has always pointed at — **is registered to a
third party** and expires 2026-11-03. Measured by RDAP on 2026-09-10, calibrated against a
known-registered and a known-unregistered control: registered 2024-11-03, registrar Spaceship, status
`client transfer prohibited`, parked nameservers, no A record, registrant redacted.

**This is worse than a dead link and should be read as a finding, not a footnote.** Every share card
the iOS app has ever produced points at a hostname somebody else controls. It is dead today; it is not
guaranteed to stay dead.

`cypressgrove.app` was chosen from four available candidates. **The orchestrator flagged, and the
owner accepted, that the name collides with `My Grove`** — screen 08, an existing product surface —
so a reader may reasonably expect `cypressgrove.app` to be about their grove rather than about the
city's trees. Recorded here because the next person to notice the collision should find the decision
rather than the idea.

*Consequence:* `ShareCopy.publicURLPrefix` must move, which is **shipped iOS copy** and therefore a
Swift round with its own review, not a web change. Until it moves, the site answers on its `.fly.dev`
hostname and no link in the wild resolves.

**3. Neighborhood polygons are sourced for San Jose and New York.**

`Tools/build_seed.py:2105` loads exactly one polygon file — DataSF's SF-only `j2bu-swwd`. Verified
against a hash-checked `us-ca-sj` pack: `neighborhoods` holds **0 rows**. Six of seven packs have
none, which hits the `Neighborhoods` nav destination hardest and also limits the iOS almanac.

Three options were put: scope the page to San Francisco and say so; source polygons for the other
cities first; or drop the nav item. **The owner took the second**, which makes it a seed-pipeline
round rather than a web one. Investigation first — sources verified to actually serve geometry
(ERRATA **E2** records the SF dataset that served *empty* polygons, and that mistake is not to be
repeated), schema impact established before any ingest, and **no republish without the owner's
explicit go-ahead**.

**4. The site states each source's own terms, and says nothing where none is recorded.**

W1's transcribed `Data` row reads `ODbL · CSV / GeoJSON`. **ODbL is the licence contributors grant at
signup**, and v1 publishes no contributions — so claiming it over city rows would assert a licence
over data this project does not hold the rights to license. Meanwhile the ingest receipt carries
San Jose's `CC-BY` and New York's Data Mine terms and **carries nothing for San Francisco**, the
largest and oldest source.

**The owner ruled: state what the receipt records, say less where it does not.** San Francisco's row
is therefore the emptiest one on the page, which is the honest state and will look like a defect to
anyone who does not know why — so the page says why. The disagreement with W1's transcribed row is an
**errata entry, not a silent change**.

*Left open by this ruling and named as open:* **DataSF's Street Tree List has no licence recorded
anywhere in the pipeline** — not in `Tools/inventory_contract.py`, not in `build_seed.py`, not in
`seed_meta`. Establishing it is a research task that blocks nothing today and blocks the export the
day someone wants San Francisco's row to say something.

**5. Vacant planting sites get pins and pages on the public web.**

24,200 sites, 12.2% of the map. Measured on the San Jose pack: `alive` 40,982, `vacant_site` 11,793 —
**22.3% of that city**. The owner ruled they render as pins *and* as pages, per **E107**, on the
ROADMAP's own argument for keeping them: 24,200 sites are the single best answer to "where could a
tree go," which is close to the point of the app.

Accepted cost, stated: roughly one public page in eight is a page saying a tree is not there, and
search engines will index all of them. The two alternatives were refused for named reasons — an inert
pin is the control-that-does-nothing failure E100 is written against and re-creates the dead end E113
fixed, and filtering them out would make the web and the app visibly disagree about what exists in
the same city.

**6. `Data & export` hands over bounded selections only.**

A named area, a species within a region, or the current viewport; bulk traffic is pointed at each
city's own published dataset URL, which the seed already records in `inventories`. A whole-pack
download was refused as scope `DECISIONS` deliberately sequenced into Phase 3 — and because it would
publish an internal schema as a contract. Provenance-only was refused because a nav item named
`Data & export` that exports nothing has the wrong name.

**Required in the same round:** a column-contract test, so the export schema cannot drift silently.

**7. Taken by the orchestrator, not the owner: `Sign in` does not ship in v1.**

W1 draws a `Sign in` button and `SCREENS.md` says its destination is **NOT SPECIFIED**. v1 has no web
account and the server cannot mint one for a browser. The three options were: omit it; ship it opening
a page that says accounts live in the iOS app; or ship it disabled.

**Omitted.** A control that visibly does nothing is the failure **E100** is written against, and a
page invented solely to justify a button is invention under a constraint-21 exception that does not
cover it — the exception covers the four nav destinations and their supporting pages, and `Sign in` is
neither. The slot is empty and the rest of the bar is the transcription.

**This is a visible deviation from a transcribed element and is therefore an errata entry**, and it is
the orchestrator's call rather than the owner's only because it is reversible the moment the web can
sign anyone in. Overturnable on the merits.

### Verifications run against a real pack while taking these

Four claims in the design round were marked UNVERIFIED because no pack existed in that worktree. Three
were settled here against `us-ca-sj`, downloaded from the public bucket and hash-verified against
`manifest-v2.json` (29,372,416 bytes; sha256 `2d979b9a…`), with `select count(*) from trees` returning
**52,775** against the manifest's 52,775 as the control that the file queried is the file described.

| Claim | Result |
|---|---|
| `neighborhoods` is empty outside SF | **0 rows** — confirmed |
| Curated species are a small minority | **40 curated, 1,158 uncurated**; `leaf_retention` null on **353** |
| Per-status split decides whether `Needs care` populates | `alive` 40,982 · `vacant_site` 11,793 · **no `declining` rows at all** |

**The third has a consequence the design round predicted and could not check: the `Needs care` filter
chip, ported from screen 01 as `trees.status = 'declining'`, matches nothing in San Jose.** Whether
that is true of the NYC packs is unmeasured. A chip that is always empty in a region is either a fact
about the city record worth stating on the page, or a chip that should not be drawn there; that is a
design question for the round that builds Explore, and it is not answered here.
