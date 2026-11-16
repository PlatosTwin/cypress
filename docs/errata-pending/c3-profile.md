# Errata pending: the species claim on somebody else's tree, and its tap that failed (round C3, 2026-11-15)

This entry is unnumbered, per CLAUDE.md "Numbering and shared files". It was found by round C3's
planner and fixed on `feat/c3-profile` (package A). It has **not shipped**: the only way to see
somebody else's tree on a phone is the community cache, which round C2 fills, and C2 is not yet in
a released build.

---

### E??? — "Say what species you think this is" showed on somebody else's unnamed tree, and the tap failed

**What happened.** `TreeProfilePresentation.offersSpeciesClaim` was `tree.source == .community &&
species == nil && acceptsContributions`. It had no test of who added the tree or which table holds
it. Round C2 made trees from the community cache openable, so on somebody else's unnamed tree the
profile offered the claim. `LocalAPI.claimSpecies` reads only this phone's own `community_trees`
table and threw `notFound`, so the tap ended in the not-found sentence. This is the shape
`VisitAddTreeModel.canAdd` exists to avoid: a control for an act the boundary refuses.

**The fix.** `offersSpeciesClaim` also needs `profile.isAddedHere` (a new `TreeProfile` field: the
tree is a row of this phone's own table) and `profile.addedByYou`. The second half is the owner's
ruling of 2026-11-15 ("Hide species controls for now"), which also hides "Report the species as
wrong" on any tree the reader did not add: `LocalAPI.speciesCorrectionOffer` answers `.unavailable`
unless the reader is the adder.

**Tests.** `OthersTreeControlsTests.unnamedCachedTree` (red when the old condition is restored) and
`anotherPersonsTreeHere` (red when the adder guard is removed). `SpeciesCorrectionTests
.theOfferMatchesTheBoundary` used to assert that a stranger is offered the report on a tree added
on this phone; it now asserts the owner's rule.
