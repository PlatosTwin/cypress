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

## 2. Open question — the terms' own "notify the City" link is dead

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

**This is presented as an open question, not resolved here**: the terms require notifying
"the City" through a link that no longer works, and NYC Open Data's site does not name a
specific successor channel for exactly this obligation. The draft note in §3 is destination-
agnostic prose the owner can paste into whichever channel they choose to use — the two
reachable candidates are the NYC Open Data "Contact Us" form
(`https://opendata.cityofnewyork.us/engage/`) and Parks & Recreation's per-dataset contact
route on the two Socrata dataset pages. **The owner should pick the destination**; this
document does not.

---

## 3. Draft — notify-the-City note

**For the owner to review, adapt, and send themselves, through whichever channel is chosen
per §2. Not sent by this task.**

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
- Nothing about the destination address is filled in; see §2.
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

### Where it must appear

Per the terms' own wording, the disclaimer goes **"at the site where the application can be
accessed or downloaded."** D12 makes this bind **before the first NYC publish, trial and beta
packs included** — the obligation attaches "the moment NYC data is served from the bucket,
not only when it is drawn" (design proposal §11, item 8), so:

1. **Every download surface that offers an NYC pack** — whole-city or any of the five borough
   packs — must show or link to this text before or alongside the download, for every release
   channel the app currently ships through (TestFlight now; the App Store product page
   whenever the app goes public). This is the literal reading of "the site where the
   application can be accessed or downloaded" and it is unambiguous.
2. It must be present **the first time any NYC pack is published to the bucket**, per D12 —
   including a trial/beta-only pack gated behind `BetaCapability` or an equivalent flag. A
   pack that is reachable only by testers is still "accessed," and D12's ruling text is
   explicit that "trial or beta pack" does not exempt it.
3. The manifest itself already has a carrier for this: `city-publishing.md` documents a
   per-city `attribution` array — "`inventory`, `name`, `url`, optional `snapshot_on`,
   `license`" — captioned "R36 binding consequence (b): the attribution obligation travels
   with the published data." The NYC entry in that array is where the *machine-readable*
   attribution belongs; §5 below is an open question about whether that satisfies obligation
   (B) on its own or whether a *human-readable* surface (an App Store / TestFlight listing,
   or an in-app screen) is also required.

---

## 5. Open questions for the owner

1. **Where does "the site where the application can be accessed or downloaded" resolve to,
   concretely, for Cypress today?** The repo does not currently define a "product page" as an
   app screen or a maintained web page — `docs/distilled/SCREENS.md` has no About/data-
   sources/attribution screen in the mocks, and per CLAUDE.md constraint 21 a screen not in
   the mocks is its own stop-and-ask. The literal reading of the terms points at the
   TestFlight public listing (Cypress currently ships only via TestFlight — `docs/ERRATA.md`
   E254) and, later, the App Store Connect product page description — both external to the
   app, neither requiring new mock work. Whether the owner also wants an in-app surface (e.g.
   a future "data sources" or "about" screen) is a product decision this document does not
   make.
2. **Which channel discharges "notify the City,"** given the terms page's own link is dead
   and no specific email/form for this exact obligation could be found? §2 lists the two best
   candidates found (NYC Open Data's general contact form; the per-dataset Socrata contact
   route to Parks & Recreation). Recommend the owner pick one and, if it bounces or goes
   unanswered, treat the notification as attempted and documented — the terms do not state
   what happens if the City's own contact channel is unreachable.
3. **Does the manifest's machine-readable `attribution` array (per `city-publishing.md`)
   satisfy obligation (B) by itself, or does the boxed text also need to render as visible
   text somewhere a human reads it before downloading?** The terms say "include," which reads
   as human-visible; a JSON field a server returns is not obviously "included at the site."
   Recommend treating §4's rendered block as the actual discharge and the manifest field as
   a secondary, structured record — the design proposal's D12 ruling did not adjudicate this
   distinction, and neither does this document.
4. **Timing against the ingest's own gate.** D20 already blocks the first NYC publish (trial
   and beta included) on species coverage reaching 90% of rows. D12 adds a second,
   independent gate — this document is that gate's input, not its close. The publish should
   wait on **both** D20's coverage threshold and the owner's sign-off that §3 has been sent
   and §4 is live wherever NYC packs are offered.

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
