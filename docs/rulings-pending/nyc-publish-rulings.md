# Rulings pending — the NYC publish round (owner decisions, 2026-08-22)

Unnumbered, per CLAUDE.md. The orchestrator splices these under real numbers at merge and rewrites
any comment that cites this filename.

Three owner decisions collected during phase 1, plus one clarification the adversarial review
established. All three were **questions this round raised and deliberately refused to answer for
itself**; they are recorded here so the refusals are on the record beside the answers.

---

### R??? — RULING D20's species-coverage gate is WAIVED for New York, at the honest 85.99%

**Date:** 2026-08-22. **Decided by:** owner.

#### Question put to the owner

D20 blocks the first NYC publish — trial and beta included — on species coverage reaching **90% of
rows**. The NYC ingest round measured the exact-match mapping ceiling at **85.99%** (772,785 of
898,643 rows) and recorded that the remaining **35,993** rows cannot be mapped further without
asserting a synonymy no botanical authority supports. A later curation round reported higher
figures — row-weighted `family` at 99.01% and `leaf_retention` at 92.50%, with every borough pack
clearing 90% on both — and those numbers are **not** the number D20 names. The round asked which
number the gate reads, and refused to pick.

#### Ruling

**The gate reads the honest mapping number, not the curation round's figures. At that number the
gate is not met, and it is WAIVED for New York.**

The waiver **records the shortfall rather than dissolving it**: New York publishes at 85.99%
species coverage, 35,993 rows short of D20's threshold, and that is the number to quote. It is not
90%, it is not 92.50%, and it is not 99.01%.

#### Consequences

- The phase-2 publish is no longer blocked on D20. It remains blocked on everything else D12 and
  R78 require.
- **The waiver is New York's, not a change to D20.** A later city meets D20 as written, or comes
  back for its own waiver with its own measured number.
- Anyone quoting NYC's species coverage quotes 85.99% and the 35,993-row shortfall. Citing the
  family or leaf-retention percentages as if they answered D20 is the confusion this ruling exists
  to end.

---

### R??? — `Poor`/`Critical` map to `alive`, not `declining`: the refusal is RATIFIED

**Date:** 2026-08-22. **Decided by:** owner.

#### Question put to the owner

s17 made `trees.status = 'declining'` reachable for the first time. NYC's `TPCondition` publishes
`Poor` and `Critical` on **22,992** standing (`Full`) rows, and mapping them to the contract's
`declining` is the obvious reading. The round mapped them to `alive` instead and said why: a status
no source has ever produced would be shipped to readers for the first time, on 22,992 trees, on an
adapter author's reading of two words in someone else's rating scale — where `Dead → dead_reported`
is a mapping the City itself makes unambiguous and R19 already draws a badge for. The two are not
the same kind of decision, and the round made only the second.

#### Ruling

**Refusal ratified. The 22,992 rows ship as `alive`.** Revisitable at a later publish.

#### Consequences

- `Tools/inventory_adapters.NYC_CONDITIONS` keeps `poor` and `critical` at `CONDITION_ALIVE`, and
  the test that pins those two entries as *decisions* — separately from the table-driven test that
  would follow the table anywhere — stays.
- The City's own word is not lost by this: `TPCondition` rides into `city_record['permit_notes']`
  verbatim on every row, so a later round that wants `declining` can have it without re-ingesting.
- Revisiting it is a rebuild and a republish, not a migration. It is a **publish-time** decision, so
  the natural moment to revisit is a round that is republishing New York anyway.

---

### R??? — the Staten Island pack id is `us-ny-nyc-staten-island`, spelled out

**Date:** 2026-08-22. **Decided by:** owner.

#### Question put to the owner

A `pack_id` is simultaneously the manifest entry's `id`, the `<id>` in R37.2's immutable object path
`cities/<id>/<version>/<id>.sqlite`, and the install key on a reader's device. It is chosen once and
never again. The round entered `us-ny-nyc-si` for Staten Island, following the only precedent the
repository had — `Tools/test_publish_cities.py`'s fixture, written by the s17 round — and flagged it
rather than freezing it, because `-si` was **the lone abbreviation among five** otherwise spelled-out
siblings (`-manhattan`, `-brooklyn`, `-queens`, `-bronx`).

#### Ruling

**Rename to `us-ny-nyc-staten-island`.** The odd one out is a worse thing to freeze forever than a
longer string.

#### Consequences

- Renamed in `build_seed.REGIONS`, `publish_cities.DISPLAY_NAMES`, and the two test files that
  carried the fixture spelling. Nothing derives a pack id from anything else, and no Swift source or
  published object referenced it.
- **It was free, and it was only free because it was asked before the publish.** See the
  clarification below.

---

### R??? — a pack id freezes at the first PUBLISH, not at the merge (review N8)

**Date:** 2026-08-22. Established by the adversarial review of the phase-1 PR and adopted as the
standing reading.

The phase-1 round treated the merge as the freezing event and asked for the Staten Island decision
before it. The review established the sharper rule: **`pack_id` becomes immutable when the first
object is written to the bucket — phase 2 — not when the code merges.** Nothing on `main` binds a
distribution identity; the bucket does.

#### Consequences

- An identity question of this kind is needed **before phase 2**, and blocking a merge on one is
  stricter than necessary.
- It does not soften the underlying rule. After the first publish the id is frozen permanently:
  changing it orphans every installed copy and breaks paths R37.2 promises never move.
- The practical form: a phase-1 PR may merge with an identity flagged, provided the flag is
  answered before the publish that freezes it. This round asked early and got a rename for the cost
  of four string replacements; the same question asked after phase 2 has no cheap answer at all.
