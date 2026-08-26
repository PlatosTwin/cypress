# Rulings pending — a republish must advance `content_rev` (2026-08-24)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge and rewrites any comment that cites this filename.

This is **an owner decision**, not a proposal. It was made on 2026-08-24 after the owner confirmed
the defect on their own phone, and it is recorded here by the orchestrator's author agent because a
branch may not write a number into `docs/RULINGS.md`.

---

### R??? — a republish advances `content_rev`; a same-day republish appends a counter

**Date:** 2026-08-24. **Decided by:** the owner. **Amends:** R37.2 as amended by R60 — the
publisher's `content_rev` contract, and nothing on the app side.

#### What went wrong

The corrective republish of 2026-08-22 went out the same day as the publish it corrected: source
seed `4f6ebaaa`, then `ac7b1ccc`. `Tools/publish_cities.py`'s `content_rev_for` derives the record
revision from the seed's **upstream inventory snapshot dates**, which is exactly what R37 asks for
and which is why they had not moved. Both publishes therefore carried `content_rev` `2026-08-22`,
and R60's `build_id` was the only part of the version string that differed.

That is fatal to update detection, because the app deliberately does **not** compare version strings
when they differ. `CityInstallState.installedIsCurrent` falls back to `content_rev` +
`schema_version` equality, and it does so for a good reason recorded in its own comment: R60's
`build_id` is a hash of the 108 MB fused seed, so re-running the publisher over a rebuilt seed
changes `version` for every city while changing no city's data, and comparing version strings would
offer every device on the catalogue an update to bytes it already holds. That fallback is correct.
What it cannot survive is two *genuinely different* publishes that agree on both fields.

With both revisions `2026-08-22` and both generations `17`, a phone holding
`s17-r2026-08-22-4f6ebaaa` is judged **current** against a live `s17-r2026-08-22-ac7b1ccc`. No
Update button is drawn, and there is no other route to the corrected data. Confirmed on the owner's
phone: Manhattan, `Installed · s17-r2026-08-22-4f6ebaaa`, no affordance, against a live
`s17-r2026-08-22-ac7b1ccc`.

#### The ruling

1. **A publish that changes a pack's data must advance that pack's `content_rev`.** It is the
   publisher's obligation, not the app's. The app's comparison is correct as written and does not
   change.

2. **Where the derived date cannot advance, a counter is appended.** The derived date is a fact
   about the upstream snapshot and cannot be moved to describe a publish; the counter is the part
   that describes the publish. `2026-08-22` → `2026-08-22.02` → `2026-08-22.03`. A bare date is the
   first publish of that record date; there is no `.01`.

3. **The identical corrected data is republished under a bumped revision**, so that devices from the
   superseded publish are offered the correction. Nothing derived from the seed can ask for this —
   the bytes are the ones already live — so it is an explicit operator action (`--republish`).

#### Two refinements this branch made, and why

**The counter is zero-padded to two digits (`.02`), where the decision's worked example wrote
`.2`.** The example's form breaks at the tenth same-day publish, and it breaks silently, in the one
comparison the app makes on this value that is not equality: `CityInstallState`'s `.bundledOutdated`
branch asks `publishedRev > bundledRev` **as a string**, on the stated grounds that "both revisions
are the ISO dates `content_rev_for` produces, where lexicographic order is date order". Un-padded,
`"2026-08-22.10" < "2026-08-22.2"`, and that sentence stops being true. Measured, not argued: with
the formatter un-padded the publisher's own suite reports the inversion by name —
`('2026-08-22.9', '2026-08-22.10')`. Zero-padded, string order and publish order are the same thing:

    "2026-08-22" < "2026-08-22.02" < … < "2026-08-22.99" < "2026-08-23"

The first inequality holds because a prefix sorts before its extension; the last because the `.` is
never reached — the day digits decide first. The hundredth same-day publish is **refused**, not
widened to three digits: `.100` would sort below `.99` and re-open the defect from the other end,
and a hundred publishes of one upstream snapshot is a runaway rather than a number to make room for.

**The counter goes only where the app compares, never where it parses.** `seed_meta.trees_snapshot_on`
keeps the bare derived date. The publisher previously wrote the revision into that key, and a
suffixed value there would break the app in two places — `InventorySource.snapshotDate` parses it
with a strict `yyyy-MM-dd` formatter and would go nil, and the seed contract in `DataGates` expects
exactly that value to be non-nil and names the key in its failure message, so **every published pack
would fail the contract gate**. The counter therefore lives in `publish_content_rev` and the
manifest's `content_rev` — the two fields `installedIsCurrent` actually reads — and nowhere else.
This separation is the whole of why the ruling's "publisher-side fix, no app change" holds. It is
also the honest reading: the upstream snapshot did not move, which is the entire reason a counter
was needed.

#### What this interacts with

- **R37.2** (`version` is the immutable path segment, write-once; only the catalogue is rewritten in
  place). A bumped revision produces a new version and therefore a new path, which is what R37.2
  provides for. The publisher now also *checks* this rather than trusting it: if the previous
  catalogue names the version this run is about to write with a different `sha256`, the run stops.
- **R60** (`build_id` appended to `version`). Unchanged. R60 made the *bytes* distinguishable in the
  path; this ruling makes the *revision* distinguishable in the field the app compares. R60 was
  necessary and was never sufficient, which is what 2026-08-22 demonstrated.
- **R43** (the Cities screen's affordances). Unchanged — no state is added or removed. A device from
  a superseded publish simply moves from `installed` to `update available`, which is what it should
  have said all along.
