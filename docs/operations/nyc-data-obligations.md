# NYC data obligations — notify-the-City draft and the product-page disclaimer

**2026-08-21. Drafts only — nothing here has been sent to anyone.** D12 of
`docs/design-proposals/2026-08-14-city-data-distribution.md` ("NYC notify-the-City +
disclaimer") requires both obligations **settled before the first NYC publish — including
any trial or beta pack**; first bytes out of the bucket bind the obligation. The owner has
already accepted both obligations (`docs/investigations/nyc-ingest.md` §13: *"The owner has
accepted both obligations"*), but nothing in the repo discharges them yet
(`Tools/fetch_nyc_trees.py`'s docstring, verbatim: *"That obligation is not discharged by
this script and is not discharged by anything in the repo yet"*). This document is that
discharge's first step: a note the owner can send in their own words, and the exact text the
product page must carry. **This document sends nothing and creates no account, filing, or
public content.**

**Updated 2026-08-21, same day, after an owner decision round.** The three open questions this
document originally raised (§5, old items 1–3) were put to the owner and ruled on directly, not
inferred here. §0 records the rulings; §2, §3 and §4 below are updated to match. The rulings are
also staged, unnumbered, at `docs/rulings-pending/nyc-obligations-2026-08-21.md`.

**Notify obligation DISCHARGED 2026-08-21, same day.** The owner reports the notification to the
City has been sent. Of the two obligations D12 gates the first NYC publish on, one remains live:
the verbatim disclaimer (§4) must be on the city-downloads screen and the store listing before —
or with — the first NYC pack, trial included. That copy lands with the s17/NYC publish round.

---

## 0. Owner rulings, 2026-08-21

Decided by the owner via a decision round, same day this document was first drafted. Full text
in `docs/rulings-pending/nyc-obligations-2026-08-21.md`; summarized here so this document reads
as settled rather than as its own first draft.

| # | Question | Ruling |
|---|---|---|
| — | Which channel discharges "notify the City" (§2, old open question 2)? | **Both.** The same note goes through the NYC Open Data general contact form *and* the per-dataset Socrata contact route to Parks & Recreation. Neither is treated as sufficient alone. |
| — | Where must the verbatim disclaimer (obligation B) actually render (§5, old open question 1)? | **Both.** The in-app city-downloads screen — the actual surface offering NYC packs, trial packs included per D12 — carries the verbatim text, *and* the TestFlight/App Store listing carries it too. The owner's ruling here **is** the constraint-21 sign-off for adding this copy to the city-downloads screen; it does not need a separate stop-and-ask when the in-app change is built. |
| — | Does the manifest's machine-readable `attribution` array discharge obligation (B) on its own (§5, old open question 3)? | **No.** Human-visible text is required; the manifest field is supplementary, structured provenance, not a substitute — for trial packs as much as for a general release. |

**What is and is not in this PR.** This document (drafts, sourcing, and the record of these
rulings) is the whole of this docs-only PR. **The city-downloads-screen copy change itself is
not built here** — it lands with the s17/NYC seed-schema and publish round (design proposal
§6.3), because that is the round that gives the screen NYC packs to show a disclaimer next to
in the first place. Sequencing: the screen change must land no later than the same round that
first publishes an NYC pack to the bucket, trial/beta included (D12) — see §4 and §5 item 4.

---

## 1. The obligation, grounded in the terms — quoted verbatim, fetched twice

**Source:** `https://www.nyc.gov/html/datamine/html/data/terms.html` ("NYC DataPortal Terms
of Use"). This is the working mirror the 2026-08-01 ingest survey found after the canonical
`nyc.gov/html/data/terms.html` had moved (`docs/investigations/nyc-street-trees.md` §2); it is
cached at `Fixtures/raw/nyc/datamine_terms.html`.

**Retrieved twice, text identical both times:**
- 2026-08-01, by the NYC ingest survey (cached copy above).
- 2026-08-21, re-fetched live for this document (rendered page text, via browser fetch — the
  page carries Akamai/Dynatrace bot-detection scripts that reject a plain HTTP client fetch,
  so the cached HTML and the rendered text were cross-checked instead of diffed byte-for-byte;
  both give the same operative sentences below).

> "By accessing datasets and feeds available through the NYC.gov Data Mine (or the 'Site'),
> the user agrees to all of the terms of use outlined below as well as the Privacy Policy for
> NYC.gov. ... Submitting City entities are the authoritative source of data available on the
> Data Mine. ... Data may be updated, corrected, overwritten and or refreshed at any time.
>
> Users providing software applications using data supplied on the NYC.gov Data Mine must do
> the following:
>
> A. Notify the City
>
> B. Include the following disclaimers at the site where the application can be accessed or
> downloaded:
>
> 'The City of New York can not vouch for the accuracy or completeness of data provided by
> this web site or application or for the usefulness or integrity of the web site or
> application. This site provides applications using data that has been modified for use from
> its original source, NYC.gov, the official web site of the City of New York.'
>
> C. Comply with any additional terms defined by the City entity or entities providing data
> used by the application, including, without limitation, requirements to include additional
> citations or disclaimers at the site of the application."

**No machine-readable license overrides this.** Both datasets' Socrata metadata publish a
null license, re-confirmed live on 2026-08-21 against the API endpoints:

| dataset | Socrata id | `license` | `licenseId` | `attribution` (Socrata field) | `rowsUpdatedAt` |
|---|---|---|---|---|---|
| Forestry Tree Points | `hn5i-inap` | not set | not set | "Department of Parks and Recreation" | 2026-08-12 |
| Forestry Planting Spaces | `82zj-84is` | not set | not set | "Department of Parks and Recreation (DPR)" | 2025-03-05 |

(Fetched from `https://data.cityofnewyork.us/api/views/hn5i-inap.json` and
`.../82zj-84is.json`, 2026-08-21. Planting Spaces' `rowsUpdatedAt` matches
`docs/design-proposals/2026-08-14-city-data-distribution.md` D19's *"17 months staler than
Tree Points (rowsUpdatedAt 2025-03-05 vs 2026-07-28)"* exactly; Tree Points' own timestamp has
since moved to 2026-08-12 under the dataset's stated fortnightly cadence, which is expected
and not a discrepancy.) With `license`/`licenseId` null on both, the operative grant remains
the Data Mine terms page quoted above — there is no CC-BY or CC0 grant to fall back to, the
way San Jose's CKAN package states `cc-by` (`docs/investigations/nyc-street-trees.md` §2).

**Two obligations follow, and only two:** (A) notify the City, and (B) carry the boxed
disclaimer verbatim, "at the site where the application can be accessed or downloaded." (C) is
a standing compliance duty ("comply with any additional terms"), not a separate action item —
no additional agency-specific terms were found linked from either dataset page.

---

## 2. The terms' own "notify the City" link is dead — and the owner's ruling on routing

The terms page's obligation (A) is a hyperlink: `<a href="../../html/contact/contact.shtml">Notify
the City</a>`. Resolved against the terms page's own path, that is
`https://www.nyc.gov/html/contact/contact.shtml`. **Fetched 2026-08-21: it redirects to
`nyc.gov`'s generic error page** — "We're Sorry. You have reached an outdated or non-existing
page." — with no forwarding link to a current contact page. This is the same failure mode the
2026-08-01 survey found for the canonical terms URL itself (`nyc.gov/html/data/terms.html`,
also since moved) — NYC's Data Mine terms infrastructure has stale internal links.

No dedicated "notify us about your application" email or form was found anywhere reachable
from NYC Open Data's current site. What exists instead, checked 2026-08-21:

- `https://opendata.cityofnewyork.us/engage/` — the NYC Open Data team's general "Contact Us"
  page (references a "Send us a note" feedback channel; the exact form/address was not
  resolvable from the page's static content, which is a JS-rendered React app).
- `https://opendata.cityofnewyork.us/faq/` — no application-notification process or address
  stated.
- Each dataset's Socrata page also carries a per-dataset "Contact Dataset Owner" feature,
  which would route to Parks & Recreation / DPR (the Socrata `attribution` field above), the
  agency that actually submits both datasets — narrower than "the City" as the terms phrase
  it, but the most specific reachable channel found.
- A plausible address, `opendata@cityofnewyork.us`, appears nowhere in NYC's own published
  material found by this search; it is **not** used in the draft below because it was not
  verified. **Do not send to it.**

**Resolved by the owner, 2026-08-21 (§0):** since no single channel is confirmed as the terms'
intended successor to its own dead link, use both of the reachable candidates rather than
picking one — send the same note through:

1. the NYC Open Data general contact form, `https://opendata.cityofnewyork.us/engage/`; and
2. the per-dataset "Contact Dataset Owner" route on each of the two Socrata dataset pages
   (Forestry Tree Points `hn5i-inap` and Forestry Planting Spaces `82zj-84is`), which routes to
   Parks & Recreation / DPR, the submitting agency for both.

Because the Socrata contact feature is per-dataset, route 2 is two submissions, not one — once
against each dataset page. **Total: three submissions of the same note text, across two
distinct channels.** §3's draft is written to be sent through all three without modification.
`opendata@cityofnewyork.us` remains unverified and is still not used.

---

## 3. Draft — notify-the-City note

**For the owner to review, adapt, and send themselves — through all three of §2's routes (the
NYC Open Data contact form, and the Contact Dataset Owner form on each of the two dataset
pages), per the 2026-08-21 ruling. Not sent by this task.** The same text works unmodified
across all three; where a destination form has its own required fields (e.g. a subject line or
a category picker) the owner fills those in per form, but the body below does not need to
change per channel.

> Subject: New York City street-tree data used in the Cypress app
>
> Hello,
>
> I'm writing to notify the City of New York, as required by the NYC.gov Data Mine Terms of
> Use, that our application, Cypress, uses two NYC Open Data datasets published by the
> Department of Parks and Recreation:
>
> - Forestry Tree Points (`hn5i-inap`)
> - Forestry Planting Spaces (`82zj-84is`)
>
> Cypress is a mobile app (iOS) for exploring and caring for street trees. It shows a
> map of trees near the user, tree profiles with species and condition information, and lets
> users log visits and care observations for individual trees.
>
> How the data is used: the two datasets are joined by `PlantingSpaceGlobalID` /
> `GlobalID` to attach an address and borough to each tree point, filtered to currently-
> standing trees, and republished by us as read-only downloadable packs — one per NYC
> borough, plus a whole-city pack — inside the app. We do not modify the underlying facts;
> species names are mapped to a controlled vocabulary for display, and each record keeps
> its original source identifier and the date it was last confirmed against your published
> data.
>
> Per the Terms of Use, the required disclaimer appears everywhere our NYC data packs are
> offered, including any trial/beta release — see the exact text and its placement in the
> attached/linked product-page disclaimer.
>
> Please let us know if there is a preferred point of contact for future questions about
> this use, or if there are additional terms specific to these datasets that we should be
> aware of.
>
> Thank you,
> [owner name]
> Cypress

**Notes for the owner:**
- The "[owner name]" and any organization name are left blank deliberately — filling them in
  is not this task's call.
- Destinations are decided (§2, §0): both the general contact form and both datasets' Contact
  Dataset Owner forms. Submitting into three separate web forms is a hands-on action only the
  owner can take — this task does not have, and should not be given, credentials or a browser
  session authenticated as the owner for any of them.
- The datasets, join, and transformation described match what the seed build actually does —
  cross-checked against `Tools/fetch_nyc_trees.py`'s docstring and
  `docs/investigations/nyc-ingest.md` (the NYC ingest round's own record) before drafting this
  paragraph, not invented for the note.

---

## 4. Draft — product-page disclaimer block

**The verbatim text below is the required disclaimer under obligation (B) — quoted exactly
from §1, not paraphrased.** Two lines are added beneath it: they are not required by the
terms' quoted boxed text, but are recommended so the disclaimer is self-locating (which
datasets, which agency) without altering the required wording itself.

> **Data disclaimer**
>
> "The City of New York can not vouch for the accuracy or completeness of data provided by
> this web site or application or for the usefulness or integrity of the web site or
> application. This site provides applications using data that has been modified for use from
> its original source, NYC.gov, the official web site of the City of New York."
>
> New York City tree data is drawn from the NYC Department of Parks and Recreation's
> Forestry Tree Points and Forestry Planting Spaces datasets (NYC Open Data), used under the
> NYC.gov Data Mine Terms of Use.

### Where it must appear — resolved by the owner, 2026-08-21 (§0)

Per the terms' own wording, the disclaimer goes **"at the site where the application can be
accessed or downloaded."** D12 makes this bind **before the first NYC publish, trial and beta
packs included** — the obligation attaches "the moment NYC data is served from the bucket,
not only when it is drawn" (design proposal §11, item 8). The owner ruled on two concrete
surfaces rather than leaving the phrase to be interpreted later:

1. **The in-app city-downloads screen** — `Cypress/Features/Cities` (`CityDownloadsModel`,
   `CityDownloadsPresentation` in the design proposal's own §3 vocabulary) is the actual
   surface that offers an NYC pack for download, whole-city or per-borough, trial packs
   included. The verbatim block from above renders there. **This ruling is itself the
   constraint-21 sign-off** for adding disclaimer copy to that screen — CLAUDE.md's "a screen
   or state not in the mocks is a stop-and-ask" is satisfied by this decision round; whoever
   builds the screen change does not need to re-raise it as a fresh stop-and-ask.
2. **The TestFlight/App Store listing text** — wherever the app itself is currently
   distributed (TestFlight today per `docs/ERRATA.md` E254; the App Store product page once
   the app is public) also carries the block, satisfying the terms' literal "accessed or
   downloaded" reading at the level of the *app*, not only the *data pack*.
3. **Human-visible text is required on both surfaces above; the manifest's `attribution` array
   does not discharge the obligation by itself, for trial packs either** (§0's third ruling).
   `city-publishing.md`'s per-city `attribution` array — "`inventory`, `name`, `url`, optional
   `snapshot_on`, `license`," captioned "R36 binding consequence (b)" — stays in place as
   supplementary, machine-readable provenance. It is not a substitute for 1 and 2.

**Sequencing, stated once and not repeated:** none of the in-app screen work is part of this
docs-only PR. It lands with the s17/NYC seed-schema and publish round (design proposal §6.3),
and it must be live in that same round — the round cannot publish an NYC pack, trial or beta,
without the city-downloads-screen copy from item 1 already shipped, and without item 2's
listing text already in place wherever that round's build is distributed.

---

## 5. Open questions — three resolved 2026-08-21, one still open

Questions 1–3 below were open when this document was first drafted; the owner ruled on all
three the same day (§0). Kept here, marked resolved, so the reasoning that led to each ruling
stays attached to its answer rather than disappearing once the question closes.

1. **RESOLVED — where does "the site where the application can be accessed or downloaded"
   resolve to, concretely, for Cypress?** *Was open because the repo does not define a
   "product page" as an app screen or a maintained web page — `docs/distilled/SCREENS.md` has
   no About/data-sources/attribution screen in the mocks, and CLAUDE.md constraint 21 makes a
   screen not in the mocks its own stop-and-ask.* **Ruled: both** the in-app city-downloads
   screen and the TestFlight/App Store listing (§4). The ruling is also the constraint-21
   sign-off for the screen addition.
2. **RESOLVED — which channel discharges "notify the City"?** *Was open because the terms
   page's own link is dead and no specific email/form for this exact obligation could be
   found.* **Ruled: both reachable candidates, not a single pick** — the general NYC Open Data
   contact form and each dataset's Contact Dataset Owner route (§2, §3).
3. **RESOLVED — does the manifest's `attribution` array satisfy obligation (B) alone?** **Ruled:
   no.** Human-visible text is required on both surfaces in item 1; the array stays
   supplementary provenance, for trial packs as much as for a general release.
4. **Still open — timing against the ingest's own gate.** D20 already blocks the first NYC
   publish (trial and beta included) on species coverage reaching 90% of rows. D12 adds a
   second, independent gate, and §0/§4 now add a third concrete precondition — the
   city-downloads-screen copy and the listing text must both be live. This document is those
   gates' input, not their close. The publish should wait on **all three**: D20's coverage
   threshold, the notify-the-City note actually sent through all three routes in §2/§3, and
   the disclaimer text actually live on both surfaces in §4 — not merely drafted here.

---

## 6. Sources and retrieval log

| what | URL | retrieved | note |
|---|---|---|---|
| Data Mine Terms of Use (verbatim disclaimer + notify obligation) | `https://www.nyc.gov/html/datamine/html/data/terms.html` | 2026-08-01 (cached, `Fixtures/raw/nyc/datamine_terms.html`) and re-fetched live 2026-08-21 | text identical both times |
| "Notify the City" link target | `https://www.nyc.gov/html/contact/contact.shtml` | 2026-08-21 | redirects to nyc.gov's generic "outdated or non-existing page" |
| NYC Open Data general contact | `https://opendata.cityofnewyork.us/engage/` | 2026-08-21 | "Contact Us" / feedback channel; no dedicated app-notification address found |
| NYC Open Data FAQ | `https://opendata.cityofnewyork.us/faq/` | 2026-08-21 | no application-notification process stated |
| Forestry Tree Points metadata | `https://data.cityofnewyork.us/api/views/hn5i-inap.json` | 2026-08-21 | `license`/`licenseId` null; `attribution` "Department of Parks and Recreation"; `rowsUpdatedAt` 2026-08-12 |
| Forestry Planting Spaces metadata | `https://data.cityofnewyork.us/api/views/82zj-84is.json` | 2026-08-21 | `license`/`licenseId` null; `attribution` "Department of Parks and Recreation (DPR)"; `rowsUpdatedAt` 2025-03-05 |

## 7. Repo evidence this document is grounded on

- `docs/design-proposals/2026-08-14-city-data-distribution.md` — D12 (ruling text), §11 item 8
  (recommendation and its reasoning), R36 binding consequence (b) as cited there.
- `docs/RULINGS.md` R36 ("any data served or published must carry its source's attribution
  obligations (NYC's verbatim disclaimer is the first)") and R37 (manifest contract).
- `docs/investigations/nyc-street-trees.md` §2 — the original terms finding, same quote, same
  URL, from the 2026-08-01 survey.
- `docs/investigations/nyc-ingest.md` §13 — "the owner has accepted both obligations,"
  "neither is discharged by this repo yet."
- `Tools/fetch_nyc_trees.py` docstring (branch `feat/nyc-ingest`) — same statement, in code.
- `Tools/build_seed.py` (branch `feat/nyc-ingest`) — `inventory_nyc_tree_points_licence` seed_meta
  key: `"NYC Open Data / Data Mine terms; notification + verbatim disclaimer required"`.
- `docs/investigations/city-publishing.md` — the manifest's `attribution` array field.
- `docs/ERRATA.md` E254 — confirms the app's only current distribution channel is TestFlight
  (informs open question 1).
- `docs/rulings-pending/nyc-obligations-2026-08-21.md` — the three 2026-08-21 rulings recorded
  in §0 above, staged unnumbered for the orchestrator to splice.
