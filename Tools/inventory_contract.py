#!/usr/bin/env python3
"""inventory_contract.py -- the normalized tree-inventory record.

THIS FILE IS THE CONTRACT. Every tree inventory the seed is built from is filtered
through `InventoryRecord`; nothing downstream of `build_seed.py`'s `emit()` ever
sees an upstream's own field names, its own spelling of "no value", or its own
convention for packing two facts into one string.

It exists because of the order these things happen in. San Francisco has two
inventories in two shapes (ERRATA E156), and the code that reads them grew one
loop per shape with a shared sink in the middle. That worked, and it hid the
question. The moment a second *city* arrives, whatever the sink happens to accept
becomes the contract by default -- and what it happens to accept today is
DataSF's shape: a `Scientific name :: Common name` packed string, a six-element
positional list of DataSF column names, `DBH` as a string in inches where `0`
means "not recorded", and no way at all for a source to say whether a record is
a tree. Writing that down as a contract before city two exists is cheaper than
discovering it afterwards.

---------------------------------------------------------------------------
WHAT A SOURCE MUST STATE, AND WHAT IT MAY LEAVE OUT
---------------------------------------------------------------------------

Required, because no default for them is honest:

    inventory     which inventory listed this record
    kind          tree | planting_site | not_a_tree -- see below
    kind_basis    how the adapter knows the kind
    lat, lon      WGS84

Optional, and `None` means the source did not say so -- never a substitute:

    source_ref            the source's own id for this record
    scientific_name       ) never packed into one string; see `species_text`
    common_name           )
    species_confidence
    address, site_type, planted_on, dbh_in, and the city-record columns

The rule that decides whether city two is cheap: **an absent optional field is
`None`, and `None` is carried through to a NULL column.** It is never an empty
string, never a zero, and never a plausible-looking stand-in. Three fields in the
current SF ingest already had a sentinel that had to be un-invented by hand --
`DBH = 0` meaning "not recorded", a blank CSV cell meaning "the city recorded
nothing", and a `PlantDate` far outside 1800..epoch meaning "a placeholder date".
Each of those is a *source's* convention, so each is the *adapter's* job to
resolve. By the time a value reaches this record it is a fact or it is `None`.

---------------------------------------------------------------------------
KIND: WHY IT IS REQUIRED, AND WHY IT CARRIES ITS OWN EVIDENCE
---------------------------------------------------------------------------

Task #94 is that 12,413 vacant planting sites are counted as street trees. The
schema-level cause is not the count. It is that until this file existed there was
no field in which a source could say what a record *is*. `build_seed.py` derived
it:

    status = "vacant_site" if kind == "placeholder" else "alive"

where `placeholder` meant "the species string did not parse". So a source that
omits a species describes an empty hole in the pavement, whether it meant to or
not, and a source that names a shrub describes a street tree. Both halves of that
are wrong and both are live in the shipped seed:

  * 153 rows are `status = 'vacant_site'` although the city's own layer says
    `PlantType = 'Tree'` on every one of its 133,577 records. 136 of them do
    carry the city's literal `BOTANICAL = 'Potential Site'` -- that is the city
    stating vacancy, and it is fine. The remainder are rows where the city said
    nothing about the species, and our seed turned that silence into a claim.
  * 85 rows are `status = 'alive'` with no species at all because their species
    text reads `Shrub :: Shrub` or `Private shrub :: Private shrub` -- the city
    saying, in the only field it has, that the thing growing there is not a tree.

So `kind` is required and cannot be defaulted, and `kind_basis` records how the
adapter reached it. `KindBasis.STATED` means the source has a field for this and
this is what it said. `KindBasis.INFERRED_FROM_ABSENT_SPECIES` means the adapter
guessed from a hole, and it is spelled that badly on purpose: it is the one basis
whose count belongs in the build receipt, because that count is the size of #94.

`NOT_A_TREE` is representable here and has no `trees.status` value to map onto.
That is deliberate and it is the whole mechanism: the contract can hold the fact,
the seed's own vocabulary cannot yet, and `build_seed.py` has to say in one named
place what it does about the difference instead of the fact having nowhere to go.

---------------------------------------------------------------------------
IDENTITY: QUALIFIED BY ID SPACE, NOT BY INVENTORY
---------------------------------------------------------------------------

`trees.uuid = uuid5(NS_TREE, <seed string>)` is what made the DataSF -> city
switch reversible: identity is a pure function of the source's own id, so 130,070
records kept their uuid byte for byte across the switch and back, and no
photograph or favourite was orphaned (ERRATA E156).

Generalising that to many cities is not "add the source name to the seed string".
San Francisco's two inventories **must** collide -- they publish the same `TreeID`
space, and their colliding is exactly the property that makes them
interchangeable. Los Angeles must not collide with either. So the qualifier is
the **id space**: the numbering scheme the ids are drawn from. Two inventories of
one id space share one; two cities do not.

    seed string = ID_SPACES[<space>].identity_prefix + source_ref

`sf`'s prefix is the empty string, frozen, because 145,837 shipped uuids are
derived that way and a public tree URL may not change. That is a historical
value, not a template: `require_id_space` rejects any *new* space whose prefix is
empty or does not end in the separator, and `source_ref` may not contain the
separator, so the seed strings of two spaces cannot alias. A new space is one
line in `ID_SPACES` and cannot be added wrongly without failing a test.
"""

from __future__ import annotations

import datetime as _datetime
from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------------------
# Record kind
# ---------------------------------------------------------------------------

# What the record describes. A source states this or an adapter derives it, but
# it is always present -- there is no "the framework will work it out".
KIND_TREE = "tree"
KIND_PLANTING_SITE = "planting_site"
KIND_NOT_A_TREE = "not_a_tree"
KINDS = (KIND_TREE, KIND_PLANTING_SITE, KIND_NOT_A_TREE)


class KindBasis:
    """How the adapter knows a record's `kind`. Part of the record, not a comment.

    The point of separating these is that one of them is a defect and the others
    are not, and until they were separate values nothing could count the defect.
    """

    #: The source publishes a field that says what this record is, and this is
    #: what it said. DataSF's `qSpecies = 'Tree(s) ::'` on a permitted site; the
    #: city layer's literal `BOTANICAL = 'Potential Site'`.
    STATED = "stated"

    #: The source publishes a category field and this record is in the ordinary
    #: category. The city layer's `PlantType = 'Tree'`.
    STATED_CATEGORY = "stated_category"

    #: **The adapter guessed, from the absence of a species name.** This is #94's
    #: mechanism. A record with this basis is a record where our seed says
    #: something the source did not. Counted into the build receipt so its size
    #: is a number in the file rather than an argument.
    INFERRED_FROM_ABSENT_SPECIES = "inferred_from_absent_species"

    #: The source names a growth habit or an ownership note where a taxon should
    #: be -- `Shrub`, `Private shrub`. The source is telling us it is not a tree;
    #: it just has no field to tell us in.
    STATED_AS_NON_TAXON = "stated_as_non_taxon"

    ALL = (STATED, STATED_CATEGORY, INFERRED_FROM_ABSENT_SPECIES, STATED_AS_NON_TAXON)

    #: The bases that mean "the source said so". Everything else is ours.
    TRUSTWORTHY = (STATED, STATED_CATEGORY, STATED_AS_NON_TAXON)


# ---------------------------------------------------------------------------
# Condition -- how the thing at the site is doing (s17)
# ---------------------------------------------------------------------------

# WHAT THIS IS FOR, AND WHY IT IS NOT A `kind`. `kind` says what the record
# DESCRIBES -- a tree, an empty planting site, a shrub. `condition` says how the
# thing described is DOING. They are independent: a standing dead tree is a
# `KIND_TREE` (something woody stands there, it occupies the site, it is drawn
# on the map) whose condition is `dead`. Modelling it as a fourth `kind` was
# considered and rejected in the s17 round, because every `kind` consumer would
# then have to remember that one of the four is really a tree; the seed's
# `trees.status` already has the value (`dead_reported`, RULINGS R19) and needed
# only something to derive it from.
#
# **The seed schema was never the thing in the way.** `trees.status` has
# permitted `alive | declining | dead_reported | removed | vacant_site` since
# before the contract existed. What was missing is this field and a status
# lookup that reads it: `build_seed.STATUS_FOR_KIND` was keyed on `kind` ALONE,
# so no adapter could cause a row to ship as anything but `alive` or
# `vacant_site` no matter what its source said. `feat/nyc-ingest` found this and
# deliberately left it here rather than take a schema decision in a data round;
# `Tools/build_seed.status_for_record` is the successor lookup.
#
# THIS IS THE SOURCE'S CLAIM, NORMALISED -- never an inference. A source that
# publishes no condition leaves it `None`, and `None` is NOT "alive": it is "no
# claim", and it maps to `alive` only because that is what the seed has always
# shipped for a listed tree. San Francisco and San Jose publish no condition
# field at all, so both stay `None` and NOT ONE of their rows moves -- verified
# by rebuilding the full seed and joining it against the shipped one on `uuid`:
# 198,625 rows matched, 0 changed status.
CONDITION_ALIVE = "alive"
CONDITION_DECLINING = "declining"
CONDITION_DEAD = "dead"
CONDITION_REMOVED = "removed"
CONDITIONS = (CONDITION_ALIVE, CONDITION_DECLINING, CONDITION_DEAD, CONDITION_REMOVED)


# ---------------------------------------------------------------------------
# Id spaces and inventories
# ---------------------------------------------------------------------------

#: Separates an id-space prefix from a source's own id in a uuid seed string. A
#: `source_ref` containing it is rejected, so the two halves cannot alias.
IDENTITY_SEPARATOR = ":"


@dataclass(frozen=True)
class IdSpace:
    """A numbering scheme that record ids are drawn from.

    Not a city and not an inventory. San Francisco's two inventories are one id
    space on purpose (E156: the same 133,577-record intersection, median
    coordinate disagreement 0.04 m, zero uuids moved across the switch).
    """

    id: str
    #: Prepended to `source_ref` to make the uuid5 seed string. **Frozen per
    #: space.** Changing one rewrites every public tree URL in that space.
    identity_prefix: str
    #: Why the prefix is what it is, so nobody "tidies" `sf`'s empty one.
    note: str = ""

    def identity_seed(self, source_ref: str) -> str:
        return f"{self.identity_prefix}{source_ref}"


ID_SPACES = {
    "sf": IdSpace(
        id="sf",
        identity_prefix="",
        note=(
            "FROZEN EMPTY. 145,837 shipped uuids are uuid5(NS_TREE, <TreeID as ASCII>) "
            "with no prefix, and DECISIONS constraint 13 makes a tree's citable "
            "identity permanent. Both of San Francisco's inventories are in this space "
            "because they publish the same TreeID numbering -- that is what made the "
            "DataSF -> city switch reversible, and it is a property to preserve, not a "
            "collision to fix. New spaces MUST declare a non-empty prefix."
        ),
    ),
    "us-ca-sj": IdSpace(
        id="us-ca-sj",
        identity_prefix="us-ca-sj:",
        note=(
            "City of San Jose. The numbering is FACILITYID on the Street Tree layer -- Esri's "
            "Local Government Information Model asset id, which is the id the city's own asset "
            "records are keyed on. Measured against the live layer on 2026-07-31: 344,879 rows, "
            "344,879 distinct FACILITYID, zero null, and no ':' in any of the 1,000 sampled. "
            "It is its own space and shares no numbering with San Francisco: SF's TreeID is a "
            "different city's asset id that happens to also be small integers, which is exactly "
            "the collision the prefix exists to prevent. NOT keyed on DAVEYID (the contractor's "
            "survey-event id, 'MB 20140207121505' -- an id for the visit, not for the site) and "
            "NOT on OBJECTID (the feature service's row number, which moves on republish)."
        ),
    ),
}


@dataclass(frozen=True)
class Inventory:
    """One published list of records. What `trees.inventory_source` stores.

    Two inventories may describe the same trees in the same id space and still
    disagree about which of them exist; that is the entire subject of E156.
    """

    id: str
    id_space: str
    name: str
    url: str


# RENAMED IN THE v14 SEED PASS: `city` -> `sf_city`, `datasf` -> `sf_datasf`.
# E169 said it first and E172 restated it: `city` is a poor identifier once there
# is more than one city in the file, and `trees.inventory_source` is a STORED
# value, so the rename is a schema change and belongs with the two constraint
# changes rather than before or after them. `--source city|datasf` is unchanged --
# that flag answers "which of San Francisco's two inventories", and prefixing it
# would make the flag say the city twice.
INVENTORIES = {
    "sf_city": Inventory(
        id="sf_city",
        id_space="sf",
        name="SF Public Works street tree inventory",
        url=(
            "https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/"
            "BUF_Street_Trees/FeatureServer/3"
        ),
    ),
    "sf_datasf": Inventory(
        id="sf_datasf",
        id_space="sf",
        name="DataSF Street Tree List",
        url="https://data.sfgov.org/api/views/tkzw-k3nq/rows.csv?accessType=DOWNLOAD",
    ),
    "sj_street_tree": Inventory(
        id="sj_street_tree",
        id_space="us-ca-sj",
        name="City of San Jose Street Tree inventory",
        url=(
            "https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/"
            "MapServer/510"
        ),
    ),
}


class ContractError(ValueError):
    """A record, id space or inventory that the contract does not permit."""


def require_id_space(space_id: str) -> IdSpace:
    """The registered id space, or raise. Enforces the rules a new space must meet.

    `sf` is grandfathered on the empty prefix and is the only space that may be.
    Every other space must carry a non-empty prefix ending in the separator, so
    no two spaces' seed strings can alias and no new space can silently inherit
    San Francisco's uuids.
    """
    space = ID_SPACES.get(space_id)
    if space is None:
        raise ContractError(
            f"unknown id space {space_id!r}; register it in ID_SPACES with a frozen "
            f"identity_prefix before ingesting anything keyed in it"
        )
    if space.id != "sf":
        if not space.identity_prefix:
            raise ContractError(
                f"id space {space_id!r} declares an empty identity_prefix. Only 'sf' may, "
                f"and only because its uuids already shipped. An empty prefix here would "
                f"mint San Francisco's uuids for another city's trees."
            )
        if not space.identity_prefix.endswith(IDENTITY_SEPARATOR):
            raise ContractError(
                f"id space {space_id!r} has identity_prefix {space.identity_prefix!r}, which "
                f"does not end in {IDENTITY_SEPARATOR!r}; two spaces' seed strings could alias"
            )
    return space


def require_inventory(inventory_id: str) -> Inventory:
    inventory = INVENTORIES.get(inventory_id)
    if inventory is None:
        raise ContractError(
            f"unknown inventory {inventory_id!r}; register it in INVENTORIES so the app can "
            f"name it on screen. A row whose provenance cannot be described is a row that "
            f"draws somebody else's name and snapshot date."
        )
    require_id_space(inventory.id_space)
    return inventory


def check_id_space_registry() -> list[str]:
    """Problems with `ID_SPACES` itself, as a list of strings. Empty means healthy.

    Checked by the tests rather than at import, so a bad registration is a red
    test with a sentence in it instead of an import that explodes in a build.
    """
    problems: list[str] = []
    prefixes: dict[str, str] = {}
    for space_id, space in ID_SPACES.items():
        if space.id != space_id:
            problems.append(f"{space_id!r} is registered under a key that is not its id")
        try:
            require_id_space(space_id)
        except ContractError as error:
            problems.append(str(error))
            continue
        if space.identity_prefix in prefixes:
            problems.append(
                f"id spaces {prefixes[space.identity_prefix]!r} and {space_id!r} share the "
                f"identity_prefix {space.identity_prefix!r}; their uuids would collide"
            )
        prefixes[space.identity_prefix] = space_id
    for inventory_id, inventory in INVENTORIES.items():
        if inventory.id != inventory_id:
            problems.append(f"{inventory_id!r} is registered under a key that is not its id")
        if inventory.id_space not in ID_SPACES:
            problems.append(
                f"inventory {inventory_id!r} is in unregistered id space {inventory.id_space!r}"
            )
    return problems


# ---------------------------------------------------------------------------
# The record
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class InventoryRecord:
    """One record from one inventory, in the seed's terms rather than the source's.

    Frozen: an adapter builds it and hands it over. Nothing downstream edits it,
    so "which layer decided this value" has one answer per field.
    """

    # ---- required -------------------------------------------------------
    inventory: str
    kind: str
    kind_basis: str
    lat: float
    lon: float

    # ---- condition (s17) ------------------------------------------------
    #: How the thing at this site is doing, in the contract's vocabulary
    #: (`CONDITIONS`). **`None` means the source made no claim**, which is not
    #: the same as `CONDITION_ALIVE` and must never be spelled as it -- see the
    #: block comment above `CONDITION_ALIVE`. `Tools/build_seed.status_for_record`
    #: turns `(kind, condition)` into the seed's `trees.status`.
    condition: Optional[str] = None
    #: The source's own condition text, verbatim, for the build's own reporting
    #: and for the same reason `species_text` exists: the normalisation above is
    #: the adapter's judgement, and a reader auditing it needs the input to it.
    #: Never parsed downstream.
    condition_text: Optional[str] = None

    # ---- region (s17) ---------------------------------------------------
    #: **The region this record sits in, named in the SOURCE's own vocabulary**
    #: -- NYC Parks writes `"Queens"`, so an adapter passes `"Queens"`, not a
    #: pack id and not a slug. `Tools/build_seed.REGIONS` is the hand-entered
    #: table that maps `(id_space, this string)` onto a `dim_region` row, and
    #: that table is where the published pack's frozen identity lives.
    #:
    #: The seam is deliberate and it is the reason this is not a pack id. Civic
    #: naming is entered, never derived (DECISIONS constraint 15), and an adapter
    #: reads a source -- it is the wrong layer to be inventing an identity that
    #: R37.2 then freezes into an immutable object path forever. An adapter that
    #: passed `"us-ny-nyc-queens"` would be minting distribution identity out of
    #: a data file.
    #:
    #: `None` means "the id space's sole region", which is what San Francisco and
    #: San Jose are and what every one-region city under manifest format 2 is
    #: (RULING D2: one shape everywhere, no NYC-only concept). An id space with
    #: more than one region whose record leaves this `None` fails the build
    #: loudly rather than landing in an arbitrary pack.
    region: Optional[str] = None

    # ---- identity -------------------------------------------------------
    #: The source's own id, verbatim, as a string. `None` when the source
    #: publishes no id for this record -- then identity falls back to the
    #: record's own immutable facts and `has_stable_identity` is False, which is
    #: a materially weaker promise and is readable as one.
    source_ref: Optional[str] = None

    # ---- species --------------------------------------------------------
    #: Two fields, never one packed string. A source that publishes only a common
    #: name sets `common_name` and leaves `scientific_name` None, and gets a tree
    #: of unknown species -- NOT a stub species minted from a vernacular. That is
    #: task #103's mechanism: eight stub species today shadow a real species
    #: already in the corpus because a common name arrived where a taxon was
    #: expected and the pipeline had nowhere else to put it.
    scientific_name: Optional[str] = None
    common_name: Optional[str] = None
    #: 0..1, how far the adapter trusts `scientific_name`. `None` when there is
    #: no scientific name to trust.
    species_confidence: Optional[float] = None
    #: The source's own species text, verbatim, for the build's own reporting.
    #: Never parsed downstream -- the adapter has already done that.
    species_text: Optional[str] = None
    #: True when the adapter could not resolve the species text to a taxon and
    #: minted a species row from the raw string. Counted against the stub ceiling.
    species_is_stub: bool = False

    # ---- placement and dimensions ---------------------------------------
    address: Optional[str] = None
    site_type: Optional[str] = None
    #: A date, already parsed by the adapter in the source's own format, with
    #: the source's own sentinel dates resolved to None.
    planted_on: Optional[_datetime.date] = None
    #: Trunk diameter at breast height, in inches, **measured**. A source whose
    #: "not recorded" sentinel is `0` resolves it to None in its adapter; by the
    #: time it is here, a number means somebody measured it.
    dbh_in: Optional[float] = None

    # ---- the source's own record ----------------------------------------
    #: **Which inventory supplied the attribute columns**, when that is not the
    #: one that listed the record. `None` means the listing inventory supplied its
    #: own, which is the ordinary case.
    #:
    #: This completes the provenance pair rather than being an extra: `inventory`
    #: says which list contained this record, and `attributes_from` says which
    #: list the facts on it came from. San Francisco needs both because the city
    #: build takes its row set from the ArcGIS layer and seven of its columns from
    #: the DataSF export -- the layer does not publish them. A reader who has only
    #: `inventory` cannot tell a record whose facts came from elsewhere from one
    #: whose facts are simply absent, and those are different records.
    attributes_from: Optional[str] = None
    #: Keyed by SEED column name, not by any source's column name. Absent key and
    #: `None` value mean the same thing and both become NULL.
    city_record: dict = field(default_factory=dict)
    #: Passthrough JSON for columns nothing maps, or None.
    raw_json: Optional[str] = None

    # ------------------------------------------------------------------ api

    @property
    def has_stable_identity(self) -> bool:
        return self.source_ref is not None

    def identity_seed(self, id_space: IdSpace) -> str:
        """The string `uuid5(NS_TREE, ...)` is taken over. Raises without a ref."""
        if self.source_ref is None:
            raise ContractError(
                "no source_ref: this record has no stable identity and its uuid must be "
                "keyed on its immutable facts by the caller, which is a weaker promise"
            )
        return id_space.identity_seed(self.source_ref)

    def validate(self) -> list[str]:
        """Everything wrong with this record, as sentences. Empty means valid."""
        problems: list[str] = []

        try:
            inventory = require_inventory(self.inventory)
        except ContractError as error:
            problems.append(str(error))
            inventory = None

        if self.attributes_from is not None:
            try:
                require_inventory(self.attributes_from)
            except ContractError as error:
                problems.append(f"attributes_from: {error}")
            if self.attributes_from == self.inventory:
                problems.append(
                    f"attributes_from is {self.attributes_from!r}, the same inventory that listed "
                    f"the record; that is the ordinary case and is spelled None"
                )

        if self.kind not in KINDS:
            problems.append(f"kind {self.kind!r} is not one of {KINDS}")
        if self.kind_basis not in KindBasis.ALL:
            problems.append(f"kind_basis {self.kind_basis!r} is not one of {KindBasis.ALL}")

        # Identity.
        if self.source_ref is not None:
            if not self.source_ref.strip():
                problems.append(
                    "source_ref is blank; a source that publishes no id must pass None so "
                    "the weaker identity is visible, not an empty string that looks like one"
                )
            if IDENTITY_SEPARATOR in self.source_ref:
                problems.append(
                    f"source_ref {self.source_ref!r} contains {IDENTITY_SEPARATOR!r}, which "
                    f"separates the id-space prefix from the id; it could alias another space"
                )

        # Coordinates.
        for name, value in (("lat", self.lat), ("lon", self.lon)):
            if value is None or value != value:  # None or NaN
                problems.append(f"{name} is not a number; a record with no position is not a record")
        if self.lat is not None and self.lat == self.lat and not -90 <= self.lat <= 90:
            problems.append(f"lat {self.lat} is out of range")
        if self.lon is not None and self.lon == self.lon and not -180 <= self.lon <= 180:
            problems.append(f"lon {self.lon} is out of range")

        # ---- the rules that make #94 and #103 unrepresentable ------------
        if self.kind == KIND_PLANTING_SITE and (self.scientific_name or self.common_name):
            problems.append(
                f"kind is {KIND_PLANTING_SITE} but the record names a species "
                f"({self.scientific_name or self.common_name!r}); an empty planting site with a "
                f"species is one of the two records this contract exists to forbid"
            )
        if self.scientific_name is not None and not self.scientific_name.strip():
            problems.append("scientific_name is blank; absent must be None, not an empty string")
        if self.common_name is not None and not self.common_name.strip():
            problems.append("common_name is blank; absent must be None, not an empty string")
        if self.species_confidence is not None and not 0.0 <= self.species_confidence <= 1.0:
            problems.append(f"species_confidence {self.species_confidence} is outside 0..1")
        if self.scientific_name is None and self.species_confidence:
            problems.append(
                "species_confidence is set with no scientific_name to be confident about"
            )
        if self.species_is_stub and self.scientific_name is None:
            problems.append("species_is_stub with no scientific_name to have stubbed")

        # A measured dimension is a measurement. A source's sentinel is the
        # adapter's problem, not every downstream reader's.
        if self.dbh_in is not None and not self.dbh_in > 0:
            problems.append(
                f"dbh_in is {self.dbh_in}; a source's 'not recorded' sentinel must be resolved "
                f"to None by its adapter, because only the adapter knows it is a sentinel"
            )

        # Absent means absent, in every free-text field. An empty string that
        # reaches a column makes "no value" and "the value is nothing"
        # indistinguishable to every reader downstream.
        for name in ("address", "site_type", "species_text"):
            value = getattr(self, name)
            if value is not None and not value.strip():
                problems.append(f"{name} is blank; absent must be None, not an empty string")
        for key, value in self.city_record.items():
            if value is not None and isinstance(value, str) and not value.strip():
                problems.append(f"city_record[{key!r}] is blank; absent must be None")

        # ---- condition (s17) ---------------------------------------------
        if self.condition is not None and self.condition not in CONDITIONS:
            problems.append(f"condition {self.condition!r} is not one of {CONDITIONS}")
        # An empty planting site has nothing standing in it to be in a
        # condition. This is the `kind`/`condition` independence stated as a
        # rule: the pair that cannot mean anything is the one that is forbidden,
        # and forbidding it here is what keeps `status_for_record` total.
        if self.kind == KIND_PLANTING_SITE and self.condition is not None:
            problems.append(
                f"kind is {KIND_PLANTING_SITE} but the record states a condition "
                f"({self.condition!r}); an empty site has nothing in it to be in a condition, "
                f"and a source that means 'a dead tree stands here' means {KIND_TREE!r} "
                f"with condition {CONDITION_DEAD!r}"
            )
        if self.condition_text is not None and not self.condition_text.strip():
            problems.append("condition_text is blank; absent must be None, not an empty string")
        # The reverse of `species_confidence` with no name to be confident about:
        # a normalised value with no source text behind it is an inference
        # wearing a claim's clothes, and #94 is the whole reason this contract
        # counts those instead of allowing them silently.
        if self.condition is not None and self.condition_text is None:
            problems.append(
                f"condition {self.condition!r} with no condition_text it was normalised from; "
                f"a condition is the source's claim, so the source's own words must travel "
                f"with it"
            )

        # ---- region (s17) ------------------------------------------------
        if self.region is not None and not self.region.strip():
            problems.append(
                "region is blank; a record in the id space's sole region passes None, "
                "not an empty string that looks like a named one"
            )

        if inventory is not None and self.kind_basis == KindBasis.INFERRED_FROM_ABSENT_SPECIES:
            if self.kind != KIND_PLANTING_SITE:
                problems.append(
                    f"kind_basis {KindBasis.INFERRED_FROM_ABSENT_SPECIES!r} on a "
                    f"{self.kind!r}; that basis only ever produced a planting site"
                )

        return problems


def validate_or_raise(record: InventoryRecord) -> InventoryRecord:
    problems = record.validate()
    if problems:
        raise ContractError(
            f"record {record.inventory}/{record.source_ref}: " + "; ".join(problems)
        )
    return record
