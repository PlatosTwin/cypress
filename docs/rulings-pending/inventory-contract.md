### Tree identity is qualified by id space, not by source; and `sf`'s prefix is frozen empty

**The decision.** `trees.uuid` stays `uuid5(NS_TREE, <seed string>)`, and the seed string becomes

```
ID_SPACES[<space>].identity_prefix + <the source's own id, verbatim>
```

An **id space** is the numbering scheme record ids are drawn from — not a city and not an
inventory. San Francisco's two inventories are one space. **`sf`'s `identity_prefix` is the empty
string and is frozen.**

**Why not qualify by source, which is what the task asked for.** Adding the inventory to the seed
string would give `city` and `datasf` different uuids for the same tree, and their uuids being
*equal* is a load-bearing property: it is what made the DataSF → city switch reversible with zero
uuids moved over 130,070 shared records (E156), and it is what keeps a photograph attached to its
tree when the seed is rebuilt from the other list. Two inventories of one numbering scheme must
collide. Two cities must not. The id space is the thing that distinguishes those cases, and the
source is not.

**Why the empty prefix is not a hack that needs tidying.** 145,837 shipped uuids are derived with
no prefix, and DECISIONS constraint 13 makes a tree's citable identity permanent. Any non-empty
`sf` prefix rewrites every public tree URL. So the empty string is a *value* — the historical one —
and the registry enforces that it is not a template: `require_id_space` rejects any space other
than `sf` whose prefix is empty or does not end in `:`, `source_ref` may not contain `:`, and
`check_id_space_registry` rejects two spaces sharing a prefix. A second city cannot be registered
into San Francisco's uuid space without a red test.

**What this settles for #107.** A new city is one `IdSpace` line, one `Inventory` line, and one
`InventoryAdapter` subclass. It cannot mint an SF uuid. It does not need a new namespace constant,
a migration, or any change to `InventorySource` on the Swift side.

**What it does not settle.** `trees.external_ref INTEGER UNIQUE` is still a global constraint on a
source-local id and must be widened before a second space is inserted; see the errata entry. That
is a schema decision for whoever does #107, not one taken here.

### A source states what a record is; the ingest may not infer it from a missing species

**The decision.** `InventoryRecord.kind` is required, has no default, and is one of `tree`,
`planting_site`, `not_a_tree`. Every record also carries `kind_basis`, which distinguishes "the
source published a field for this" from `inferred_from_absent_species` — the adapter guessing from
a hole. The build receipt counts them separately.

**Why it is a ruling and not just a refactor.** It costs something real. `not_a_tree` has no
`trees.status` to map onto, so `build_seed.STATUS_FOR_KIND` maps it to `alive` and the seed carries
a fact its own vocabulary cannot express. That mismatch is deliberate: the alternative is that the
fact has nowhere to be recorded at all, which is the state that produced #94 and kept it
unmeasured for as long as it existed. One dict entry with a comment beats an absence.

**What this rules out permanently.** No future source may describe a planting site by omitting a
species, and none may describe a tree that way either. `validate()` refuses a planting site that
names a species, refuses a blank string in any optional field, and refuses a non-positive `dbh_in`
— so a source's "not recorded" sentinel has to be resolved by the adapter that knows it is a
sentinel, and cannot arrive as a measurement.

**What it does not decide.** Whether the 1,777 inferred vacancies should become trees of unknown
species, and whether the 312 not-a-tree records should get a status of their own, be `removed`, or
be excluded from the corpus. Those change what the map draws and are #94's to settle. This ruling
only makes them countable and makes the schema that permitted them look wrong.
