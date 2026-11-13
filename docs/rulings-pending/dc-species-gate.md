# Rulings pending: RULING D20's species-coverage gate is waived for Washington, D.C. (2026-11-12)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it
under a real number at merge. No code comment cites this filename.

---

### R??? — D20 is WAIVED for Washington, D.C., at the measured 86.27%

**Date:** 2026-11-12. **Decided by:** the owner, relayed by the orchestrator in the D.C. round's
brief: the owner granted a D.C. waiver for the first publish if D.C. measured below 90%.
**Status:** ruled.

#### The measured number

D20 asks that 90% of a city's rows resolve to a species already in the corpus. D.C. was measured the
way R100 measured New York: the R0 to R3 cascade of `Tools/build_nyc_species_map.py` (exact name,
hybrid sign, rank within species) against the species catalogue already published, 1,198 species,
over every shipped D.C. tree.

**170,322 of 197,418 rows: 86.27%, 7,355 rows short of 90%.** Exact name alone (R0) is 164,538 rows,
83.34%. Detail: `docs/investigations/dc-street-trees.md` §5.

#### Ruling

The gate is not met, and it is waived for Washington, D.C. The waiver records the shortfall; it does
not remove it. Anyone quoting D.C.'s species coverage quotes 86.27% and the 7,355-row shortfall.

#### Consequences

- The first D.C. publish is not blocked on D20.
- The waiver is D.C.'s, not a change to D20, the same as R100 for New York.
- Much of the gap is notation the cascade does not handle (`Ginkgo biloba (male)`, `Prunus
  species`, curly-quoted cultivars), not missing taxa. Closing it is a curation round with cited
  rules, listed in `docs/ROADMAP.md`'s chip backlog.
