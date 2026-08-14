# City data distribution — the owner's rulings on the 2026-08-14 design proposal

*(Unnumbered; the orchestrator splices this under the real next number at merge. Source:
`docs/design-proposals/2026-08-14-city-data-distribution.md`, whose Decisions section carries the
same rulings as D1–D16 with the evidence behind each. Ruled by the owner on 2026-08-14, each as an
explicit choice among stated alternatives.)*

**The published unit becomes a region, and a borough is the region for NYC.** Five borough packs
(54–169 MB raw at the proposal's estimates), plus a whole-NYC pack published beside them for the
reader with the disk and the patience. San Francisco and San Jose become cities with exactly one
region each — one shape everywhere, no NYC-only concept, no permanent branch in the publisher or the
Cities screen. Revisit the unit only if the real Queens number from the ingest lands materially above
~200 MB.

**Seed schema 17 is one generation with one author.** The region column and region dimension land in
the same generation as the standing-dead `kind`/`status` change the owner already ruled schema-first.
One migration round, one review; the NYC ingest targets a single settled schema. The manifest moves
`manifest_format` 1 → 2 in the same stage, and both formats publish side by side for one release
cycle — the format-1 manifest listing whole-city packs only — so unupdated installs do not lose the
catalog.

**The staged sequence is approved and Stage 0 starts now**, before the ingest picks a unit: the app
reads its own bundle's cities, content revisions and coverage by the publisher's own rule; the Cities
screen gains *included in the app* and *newer record available* row states (an amendment to R43 §3's
enumeration); the `Download` affordance disappears where it cannot keep its promise; offline rows
take their titles from `dim_city.display_name`; and `bbox`/`centroid` decoding lands in the same
change. The bundle row compares on `content_rev` alone — record-date parity, claimed as nothing more.

**The download path grows up now, not with Stage 1**: brotli on the wire inside `manifest_format` 1
(R37.4's reserved key; 4.56x measured on the published `sf` artifact), a background-identifier
`URLSession` initiated in the foreground, resume via ranged GETs, and a free-space precheck including
the `NSPrivacyAccessedAPICategoryDiskSpace` declaration it requires.

**The location-triggered offer fires from the Cities screen**, plus at most a one-time prompt after
the map is panned somewhere the attached inventory does not cover — not on launch. This supersedes
the owner's original "on open" phrasing by the owner's own ruling. The prompt's copy remains a
constraint-21 stop-and-ask when it is mocked.

**The freshness destination is deliberately open.** The owner declined to commit to either overlay
packs or R36's shape B; the choice is made after Stage 1's real download sizes are in hand, and
Stage 3's design begins by closing it rather than assuming overlays. Until then, regional packs are
the delta mechanism. The auto-refresh ticket R43 §6 deferred stays unwritten until after Stage 1.

**What does not move:** the fused seed keeps publishing with NYC out of it, so worktree and CI costs
are unchanged; the bundle stays R36's bootstrap (SF + San Jose), revisited deliberately at a natural
break rather than by drift; and the NYC notify-the-City and verbatim-disclaimer obligation is settled
before the first NYC publish — trial and beta packs included — not before the ingest.

**`CLAUDE.md`'s version-spaces bullet gains the third space, `manifest_format`**, under the same
discipline as the other two: named, its number struck from the prose, read from the code
(`Cypress/Data/Cities/CityManifest.swift` and `Tools/publish_cities.py`).
