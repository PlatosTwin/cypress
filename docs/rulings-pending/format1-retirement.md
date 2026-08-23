# Rulings pending — format-1 manifest retirement (owner decision, 2026-08-23)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices this under a real
number at merge and rewrites any comment that cites this filename.

One entry. It **supersedes** a scheduling decision recorded twice in this directory, and the only
mechanism that may do that is the one operating here: the owner's own later decision.

---

### R??? — Format 1 retires now, and the object already in the bucket is frozen rather than deleted

**Date:** 2026-08-23. **Decided by:** owner. **Implemented by:** this round.

#### What this supersedes, and why that is legitimate

Two pending entries scheduled this retirement, and both are now overridden:

- **`s17-region-generation.md`** set a three-tick clock — build 48, then the NYC publish (writing
  both objects), then *the publish after NYC*, which would write format 2 only. It argued
  explicitly against retiring at the NYC publish, on the grounds that doing so "would strand an
  unupdated install on the exact publish that first has something new to offer it."
- **`seed-pin-and-bundle-scope.md`** clarified that the corrective republish of 2026-08-22 did not
  start that clock, and that retirement fires "at the next real publish."

Neither reasoning was wrong when written, and neither is the reason this changed. **A ruling is
changed by the owner deciding differently, not by an agent finding a better argument** — that is
the one mechanism, and it is what happened on 2026-08-23. The prior entries are superseded, not
corrected; they should be read as the record of a decision that stood until this one replaced it.

#### The decision

Format 1 is retired **now**, ahead of the publish that the earlier clock named. `Tools/publish_cities.py`
no longer writes `manifest.json`. The NYC publish of 2026-08-23 — which wrote both objects, as D8
required of it — is therefore the last format-1 object that will ever be produced.

#### Retirement means the end of WRITING, never deletion

This is the load-bearing half, and the half most likely to be lost when this entry is
summarized. The published `manifest.json` **stays in the bucket exactly as the 2026-08-23 publish
left it**, and nothing may overwrite or remove it.

Its content is stale but **true**: it names the two city-level packs at their immutable
`cities/<id>/<version>/` paths, and those objects are write-once under R37.2 and remain served.
Verified anonymously from the public domain in this round, with a known-404 control to calibrate
the check — both packs and the fused seed answer `206` at the byte sizes the manifest states.

So a build that never updated past 47 keeps a working Cities screen indefinitely. What it stops
receiving is anything published after 2026-08-23. Deleting the object would convert a stale screen
into a dead one — "Couldn't check what's available" — which is precisely the self-inflicted outage
D8 was written to prevent, arriving by a different route.

**The old name is therefore reserved, not free.** The single remaining way to break this property
is for someone to upload a *newer* file over the frozen one: a `dist/` left over from a
dual-publish round still carries that round's `manifest.json`, and the publisher's `--out` only
clears `cities/`. `assert_no_legacy_manifest` refuses to finish a run whose output directory holds
one, and names the fix. It refuses rather than deleting the file, deliberately — a guard that
removes its own subject can never fail again.

#### The reader keeps format 1; only the writer retires

`CityManifest.knownFormats` stays `{1, 2}`, and `CityDownloader`'s fallback to `manifest.json`
stays. This is a deliberate divergence from `s17-region-generation.md`'s enumeration of the work,
which listed removing the fallback alongside deleting `write_manifest_v1`, and it follows from the
distinction that entry itself drew about `knownFormats`: what retires is *writing* a format-1
manifest, never *reading* one.

The fallback's original job — protecting a new build against a bucket with no format-2 object — is
discharged on the live bucket, where `manifest-v2.json` has been present since 2026-08-23. What it
still covers is every base URL that is *not* the live bucket: an archived mirror, a fixture
directory, a future bucket populated in some other order. It costs one request on a path that has
already failed. Removing it would buy nothing and would risk a dead Cities screen in exactly the
cases nobody watches.

**This divergence is flagged rather than assumed.** If the owner wants the fallback gone too, that
is a separate app-side change requiring a new build to have any effect — every shipped build from
48 to 55 has the fallback compiled in regardless of what the source says today.

#### A defect this round found, which retirement would otherwise have introduced

`Tools/fetch_seed.sh`'s `CYPRESS_SEED_SOURCE=live` branch resolved the seed from `manifest.json`.
Retiring format 1 without touching it would have left the escape hatch pointing at a frozen object:
"give me the artifact currently on the bucket" would have silently meant "give me the artifact from
before the retirement," permanently, **and the script's sha256 check would have confirmed the stale
answer**. It reads `manifest-v2.json` now. The `source_seed` envelope was never inside the
format-specific part of either document, so only the name changed.

Worth recording because it is the shape of failure this repository keeps paying for: not an error,
but a verified wrong answer.

#### A prior claim this round refutes

`s17-region-generation.md` states, of the NYC round, that the publisher "already writes both, and
`verify_seed` checks both on every run." **`Tools/verify_seed.py` contains no reference to either
manifest** — it is the seed database's acceptance checker and has nothing to do with the catalog.
What actually verified both was `publish_cities.py`'s own readback loop over the files it had just
written, plus `Tools/test_publish_cities.py`. Nothing was under-checked; the sentence named the
wrong instrument.
