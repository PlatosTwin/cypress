<!-- UNNUMBERED. Written on branch p1/round9-b for task #106. The orchestrator splices this under
     the real next E number at merge. Do not cite it by filename from code; nothing in code cites
     it today. -->

### E??? — #106's premise: San Francisco Rec & Park publishes no tree inventory, and Golden Gate Park has no source to populate from (task #106)

Ticket #106 says Golden Gate Park is empty *"because SF Public Works' street-tree layer covers
streets, not parks. Those trees are maintained by **Rec & Park**, a different dataset entirely."*
The first sentence is right. **The second is false: there is no such dataset.** The full survey,
with request counts and every source checked, is `docs/investigations/sf-park-trees.md`; this entry
records the finding and its consequences for the record.

#### What the department actually publishes

The San Francisco Recreation and Parks Department publishes **twelve** datasets, and DataSF's own
register of city datasets (`data.sfgov.org/resource/y8fp-fbf5`, which carries `Internal`, `Scoping`,
`In Progress` and `Not Published` rows as well as published ones) lists all twelve: park sections,
functional areas, facilities, a 2007 facility-conditions assessment, park scores, properties,
linear assets, an activity guide, staffing, golf-course production data, and one point asset layer.

The point asset layer is the closest thing to an inventory and it is worth quoting, because it
settles the question: `Assets Maintained by the Recreation and Parks Department` describes *"the
locations of assets like trash cans, picnic tables, benches, etc"*. Its `asset_type` histogram has
**37 values and 9,000-odd rows** — 3,186 benches, 1,646 lamp posts, 25 bollards, 2 toilets, 1
arbor — and **no tree**. Measured twice, through Socrata and directly against the ArcGIS layer; the
two agree exactly, so the open-data mirror is not a filtered subset.

The city's ArcGIS Online organisation (`services.arcgis.com/Zs2aNLFN00jrS4gG`, 2,075 services, the
same org `BUF_Street_Trees` lives in) was searched two ways — a name scan of the whole service
directory and a full-text item search, which catches services with opaque names. 68 tree items;
every one belongs to Public Works, SF Environment, SF Planning, 311 or SFO. The Rec & Park staff
accounts own park-evaluation layers and trail story maps.

**Why, in the city's own words:** the citywide census the `sf_city` inventory descends from —
EveryTreeSF, 2016–17 — excluded trees in public parks by design, and SF Planning said future phases
of the Urban Forest Plan would cover parks and open space. Ten years on, none has published data.

#### How empty the park is, measured against the park's own polygon

A bounding box is not good enough here: the usual Golden Gate Park rectangle contains Fulton,
Lincoln, Stanyan and the whole Richmond and Sunset frontage. So the boundary used is Rec & Park's
own — the `Recreation_and_Parks_Properties` feature labelled `Golden Gate Park`, `complex = All
Sections`, 1,031.65 acres — and the test is point-in-polygon over `Fixtures/seed/cypress-seed.sqlite`.

| | rows |
|---|---:|
| seed rows in the GGP **bounding box** | 5,914 |
| seed rows inside the GGP **polygon** | **65** |
| of those 65, `legal_status = 'DPW Maintained'` | 65 |

**0.06 trees per acre**, and all 65 are street trees on named boulevards that clip the park's
outline. Citywide the same test over all 240 Rec & Park property polygons (5,255 acres) puts
**1,922 of 145,837 SF seed rows** on Rec & Park land — 1.3%, and that 1.3% is edge effects.

This is the same fact `LandContext.inferred(from:idSpace:)` already states from the other direction:
`.cityPark` resolves for 177 of 195,309 rows. That number was reached by reading the city's
*claims*; this one by reading *geometry*. They agree, and the enum's doc comment is correct as
written.

#### What this changes, and what it does not

**Nothing in the seed, the schema or any Swift file.** No migration, no registration in
`Tools/inventory_contract.py`, no seed rebuild. That is the point: the correct response to a source
that does not exist is to add nothing.

Specifically, **do not register an `IdSpace` or an `Inventory` for Rec & Park.** `require_id_space`
and `check_id_space_registry` would accept a well-formed entry, and it would then sit in the
registry naming a publisher with no rows.

**#106's two delegated decisions are left open and no ruling was written for them.** Both were
delegated on the explicit condition that they be decided from the data — whether a park inventory
shares SF's `TreeID` numbering (a second inventory in `sf`, uuids colliding by design, R18/E156) or
carries its own (a new id space with a prefix, R20/R24), and how a park tree's land context is
expressed. With no rows there is nothing to decide from, and a ruling written from a ticket instead
of from a source is the failure mode CLAUDE.md names for comments and that applies identically to
`docs/RULINGS.md`. `docs/investigations/sf-park-trees.md` §5 records what evidence would decide each
one.

One half of the land-context question is worth stating anyway because it removes a wrong assumption
rather than adding a right one: **a park tree does not need a fourth `LandContext` case.**
`.cityPark` already exists, is already frozen by `AppSchema` v11's CHECK, and is documented as
*"land the Recreation and Parks Department holds"*. The open part is only whether a park adapter
should state it per row or leave it nil.

#### Where this leaves the ticket

Golden Gate Park is empty on the map because **San Francisco has never counted its park trees** —
not because of an ingest gap. E126's rule applies to how the app says so: an empty state names what
would fill it. The honest sentence is that the city's inventory covers streets and not parks. The
only route to a populated Golden Gate Park that exists today is the community layer (#69), where a
contributor adding a tree in the park is adding something the city genuinely does not have — which
`LandContext`'s doc comment already calls a feature.

Two sources were refused deliberately rather than left to be rediscovered:

- **SFO's tree inventory** (`SFO_TREE`, 3,128 rows with genus, species, DBH, spread, height,
  condition) is real, publicly published, and a City and County of San Francisco department's. It is
  also twelve miles outside the city, in San Mateo County, outside all 41 analysis neighbourhoods,
  and nowhere near a park. Ingesting it would answer a different question than the one asked.
- **The San Francisco Botanical Garden's Garden Explorer** (`sfbg.gardenexplorer.org`) is the only
  accessible record of individually located plants inside Golden Gate Park, but it is a 501(c)(3)'s
  garden accession list rather than a municipal inventory, it asserts copyright with no stated
  licence, and it offers no export. Under #106's own data-fetching rules that is a stop-and-ask.
