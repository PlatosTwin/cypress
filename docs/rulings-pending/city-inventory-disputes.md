# Ruling (pending number): city-inventory data is disputable, disputes stored app-side

**Date:** 2026-08-21. **Decided by:** owner, via decision round.

## Question put to the owner

The tree profile's flag controls ("Report the species as wrong", "Report that there is no tree
here") render only for community records. A city-inventory row is deliberately `.unavailable`:
`SpeciesClaim.swift`'s header records that the city's data sits in an ATTACHed read-only database,
and letting a contributor dispute it "would need an override table and a policy about what the
export then says, which is a larger decision than this." The owner was asked whether to add
city-row flagging to the roadmap, scope it as a near-term round, or leave city data undisputable.

## Ruling

In the owner's words: "City data needs to be disputable via the UI. For now, we can just store it
in a separate DB, and later on we'll figure out how and whether to sync back to the city's DB."

## Refinement, same day — the owner's spec

A second round the same day replaced the "same two flags, extended to city rows" framing.
City-tree and community-tree disputes are **not** the same surface:

**City trees.** The nature-of-issue list, offered as checkboxes (more than one may apply):

1. Pin in wrong location.
2. Wrong species.
3. Wrong other metadata — the owner's examples: a planted year that is clearly wrong, or the
   city recording a tree where the plot is actually empty.

Alongside the checkboxes: an option to enter **suggested values** for whatever is disputed, and a
free-text **notes / additional information** field.

Separately, a fourth defect class the profile screen cannot host because there is no record to
open: **a tree that IS on city property and IS NOT in the city database** — reported as a
missing-tree data defect, another instance of the same dispute machinery.

**Badges and filtering.** A tree carrying flags shows a **small badge displaying those flags**,
and the existing filters box gains a **"trees with data issues"** filter.

**Community trees.** Disputing **location and species only** — the existing species report stays,
a location dispute is added, and the city-tree metadata/suggested-values machinery does not apply.

This spec is the owner's own UI direction and is the constraint-21 authority for these controls;
visual detail beyond what is written here still goes back to the owner at build time.

## Consequences

- The "community rows only" deferral is reversed for *flagging*. The city inventory itself stays
  read-only; a dispute is a row in the app's writable database referencing the city tree, never a
  write to the attached city file.
- Whether or how disputes ever reach a city's own dataset is explicitly deferred — storing and
  showing the dispute is the scope; sync-back is a later, separate decision.
- The round that builds this needs the writable-schema migration seat after the §3.4 round's, and
  changes the tree profile's offer states so city rows stop answering `.unavailable`. The dispute
  row must carry: which issue kinds are checked, per-field suggested values, and free-text notes —
  richer than the existing boolean-shaped species/never-existed flags.
- The missing-tree defect (on city property, absent from the city DB) needs an entry point that is
  not a tree profile — likely the map. Where exactly it lives is a build-time question for the
  owner.
- Map/list rendering gains a flag badge on flagged trees and a "trees with data issues" entry in
  the filters box.
- Community trees converge on exactly two dispute modes: location and species.
- `SpeciesClaim.swift`'s header (and the parallel record-defect reasoning) must be rewritten by
  that round to cite this ruling's number once spliced.
