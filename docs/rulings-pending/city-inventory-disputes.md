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

## Consequences

- The "community rows only" deferral is reversed for *flagging*. The city inventory itself stays
  read-only; a dispute is a row in the app's writable database referencing the city tree, never a
  write to the attached city file.
- Whether or how disputes ever reach a city's own dataset is explicitly deferred — storing and
  showing the dispute is the scope; sync-back is a later, separate decision.
- The round that builds this needs the writable-schema migration seat after the §3.4 round's, and
  changes the tree profile's offer states so city rows stop answering `.unavailable` for the two
  flag verbs.
- `SpeciesClaim.swift`'s header (and the parallel record-defect reasoning) must be rewritten by
  that round to cite this ruling's number once spliced.
