<!-- UNNUMBERED. Splice the number in at merge; do not edit docs/RULINGS.md from a
     parallel agent. Written for #107, the survey half. -->

### San Jose is its own id space, keyed on `FACILITYID`, and a source's asset id is what an id space is made of

**The decision.** San Jose is registered as `ID_SPACES["us-ca-sj"]` with `identity_prefix
"us-ca-sj:"`, and its `source_ref` is **`FACILITYID`** — verbatim, as a string. Its inventory is
`INVENTORIES["sj_street_tree"]`.

R18 settled that identity is qualified by id space and left open what an id space is *for a city
that is not San Francisco*. San Jose forces the question, because its Street Tree layer publishes
**three** ids that are each non-null and each distinct over all 344,879 rows (measured 2026-07-31),
so uniqueness does not choose between them.

**Why `FACILITYID`.** It is Esri's Local Government Information Model asset id: the id San Jose's own
asset records are keyed on and the one its CSV and GeoJSON extracts carry. 344,879 distinct values
over 344,879 rows, zero null, and no `:` in any of the 1,000 sampled.

**Why not `DAVEYID`.** It reads `MB 20140207121505` — a crew code and a collection timestamp from the
Davey Resource Group survey. It is an id **for the visit, not for the site.** A re-surveyed site gets
a second one; a tree planted after the contract has none the contractor ever issued. Keying identity
on it would make a tree's permanent public URL a property of when somebody happened to walk past it.

**Why not `OBJECTID`.** It is the feature service's row number and is the one id in the layer
documented to move on republish. DECISIONS constraint 13 makes a tree's citable identity permanent.

**Why not `INTID`.** `FACILITYID` and `INTID` hold the same number as a string and an integer, and
were identical on all 1,000 rows sampled. They are **one numbering, not two**, so choosing between
them is a choice of representation and not of space. The string form is taken because `source_ref` is
defined as the source's own id verbatim as a string.

**The rule this generalises to.** *An id space is the numbering an inventory's publisher keys its own
asset records on — not the numbering that is most convenient, most unique, or most numeric.* A
source may publish several unique ids and they are not interchangeable: one names the asset, one
names a survey event, one names a row in a response. Only the first is an identity. The test a new
source must pass is not "is it unique" but **"would the publisher still issue this id to this site
next year".**

**Why San Jose cannot collide with San Francisco, structurally rather than luckily.** `sf`'s prefix
is the frozen empty string, so an `sf` seed string is a bare `TreeID` and contains no `:` at all,
while every `us-ca-sj` seed string contains one at position 8 and `source_ref` may not contain the
separator. This matters because the two numberings **do** overlap: San Jose `FACILITYID` 3 and San
Francisco `TreeID` 3 both exist and are different trees in different cities. `require_id_space`
refuses an empty or unterminated prefix and `check_id_space_registry` refuses two spaces sharing
one; both refusals are pinned by tests that assert the reason.

**What this rules out.** No city may be registered into `sf`. No city may be given a space because
its id ranges happen not to have collided with San Francisco's yet — **Sacramento's `GISOBJID` is
eight digits and does not currently overlap, and that is not a reason to share a space.** A space is
shared when two inventories publish the same numbering, which in California is a property of San
Francisco publishing one asset register twice and of nothing else surveyed.

**What it does not decide.** Whether a source with no asset id at all should be ingested. Oakland
publishes only `objectid`, a row number in a 2013 extract; under the contract the honest handling is
`source_ref=None`, which makes `has_stable_identity` False and is a materially weaker promise.
Whether the app should carry rows with that weaker promise is a product question and is not settled
here.

### A source's own conventions are the adapter's to resolve, including when the source contradicts itself

**The decision.** When a source states the same fact twice and disagrees with itself, the adapter
**picks the field whose only meaning is that fact, drops the other, and counts the row.** It does not
average them, does not prefer the richer-looking one, and does not drop the record.

San Jose states vacancy in two places: `VACANTSITE` (`Yes`/`No`, which means nothing else) and
`NAMESCIENTIFIC` (which carries a taxon, a vacancy string, `Stump`, `Unknown`, or nothing). Measured
2026-07-31: **611** rows are `VACANTSITE = 'Yes'` and name a real taxon, **82** are `VACANTSITE =
'No'` and say `Vacant site`, and **3,666** are `VACANTSITE = 'Yes'` with a positive trunk diameter.

`VACANTSITE` wins for the kind, because it is the field with one meaning. The species is dropped on a
planting site — a planting site that names a species is one of the two records the contract exists to
forbid — and so is `dbh_in`, because a measured trunk in an empty hole is two unreconciled records
rather than a fact. Every one of those decisions increments a named counter in `adapter.stats`.

**Why it is a ruling and not just an adapter detail.** The counting is the load-bearing half. E169's
whole finding was that a defect nobody could count stayed unfixed for as long as it existed. An
adapter that resolves a source's self-contradiction silently is indistinguishable, from downstream,
from a source that never contradicted itself — and the next person to read the corpus has no way to
learn that 3,666 trunk measurements were discarded.

**What this rules out.** No adapter may resolve a conflict between two of its source's fields without
a counter naming it. No adapter may fill a field its source left empty. And no adapter may widen the
contract to accommodate its source: San Jose's `TRUNKDIAM = 0` on 72,142 rows is a hard `validate()`
failure until the adapter resolves the sentinel, and that is the contract working rather than an
obstacle to it.

**What it does not decide.** Which of San Jose's two statements is *right*. The adapter records that
they disagree and how often; reconciling them is San Jose's, and choosing what the map draws for the
611 is #94's.
