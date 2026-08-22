#!/usr/bin/env python3
"""inventory_adapters.py -- one adapter per inventory, all producing InventoryRecords.

An adapter's whole job is to answer, for one upstream, the questions
`Tools/inventory_contract.py` asks: what does this record describe, what is its
id, what species is it, where is it, what did the source actually say and what
did it merely fail to say. Everything upstream-specific lives here -- field
names, units, date formats, the value that means "not recorded", the convention
for packing two names into one column. Nothing upstream-specific lives past it.

The rule that keeps this honest: **an adapter may only report what its source
publishes.** It resolves the source's sentinels (a `DBH` of `0`, a blank CSV
cell, a `PlantDate` of `01/01/1900`) to `None`, because only the adapter knows
they are sentinels. It does not fill them in.

WHAT AN ADAPTER IS. There is deliberately no base class. An adapter is anything
with an `inventory_id`, a `records()` generator yielding `InventoryRecord`s, and a
`stats` dict carrying at least `source_rows` and `dropped_no_coords`. That is the
whole interface, and with two adapters whose constructors have nothing in common
an abstract base was fifteen lines asserting it -- documentation with a `class`
keyword in front of it. This paragraph is the documentation; `build_seed.py` calls
`.records()` and reads `.stats`, and a third adapter needs to satisfy nothing else.

An adapter OWNS:

  * its source's field names, units, date formats and sentinels;
  * dropping records its source publishes with no usable position, counted into
    `stats["dropped_no_coords"]`;
  * deciding each record's `kind` and, honestly, its `kind_basis`.

An adapter does NOT own: the corpus bounding box, uniqueness of `source_ref`
across the build, uuid derivation, the species catalogue, or the neighbourhood
stamp. Those are the seed's rules, they live in `build_seed.py`, and they belong
in one place so that two adapters cannot disagree about what a row means.

WHY THE TWO SAN FRANCISCO ADAPTERS SHARE A SPECIES PARSER. `qSpecies` --
`Scientific name :: Common name` in one column -- is DataSF's convention, and the
city's ArcGIS layer publishes `BOTANICAL` and `COMMON` as two clean fields. The
city adapter still rejoins them into the packed string and re-splits it, which is
a lossy round-trip through another inventory's serialization format and is
exactly the shape this file exists to stop. It is kept for now because changing
it would change the shipped corpus, and it is confined to
`SFCityLayerAdapter.species_of` so the next source does not inherit it: a third
city with two clean name fields sets `scientific_name` and `common_name`
directly and never sees a `::`.
"""

from __future__ import annotations

import csv
import datetime as _datetime
import json
import re
from typing import Iterator, Optional

from inventory_contract import (
    KIND_NOT_A_TREE,
    KIND_PLANTING_SITE,
    KIND_TREE,
    InventoryRecord,
    KindBasis,
)

# ---------------------------------------------------------------------------
# The DataSF qSpecies vocabulary
# ---------------------------------------------------------------------------
# Moved here verbatim from build_seed.py. These are statements about ONE
# upstream's spelling habits and they have no business in a shared ingest core:
# the next city will have its own, and a `PLACEHOLDER_SPECIES` set at module
# scope in the builder is how one city's habits become every city's rules.

# qSpecies strings that are site placeholders rather than species. BUILD-PLAN 7
# names "Tree(s) ::", "::" and empty; the live data also carries a handful of
# equivalent forms, all of which describe a planting site with no tree in it.
PLACEHOLDER_SPECIES = {
    "",
    "::",
    ":: ",
    "tree(s) ::",
    "tree(s)",
    ":: tree(s)",
    "tree ::",
    "nan ::",
    "nan",
    "potential site ::",
    "potential site",
    "vacant site ::",
    "vacant site",
    "vacant lot ::",
    "no species ::",
    "unknown ::",
}

# THE SUBSET OF THE ABOVE IN WHICH THE SOURCE SAYS NOTHING AT ALL.
#
# This split is the point of `kind_basis`, and it is the measurable half of task
# #94. Every string above produces `status = 'vacant_site'` in the seed today,
# but they are not the same claim:
#
#   `Tree(s) ::`                       11,818 rows, 9,738 of them `Permitted
#                                      Site`. The export's own convention for "a
#                                      site permitted for tree(s)". The source is
#                                      describing a planting site. STATED.
#   `Potential Site :: Potential Site`    155 rows, and the city layer's literal
#                                      `BOTANICAL = 'Potential Site'`. STATED.
#
#   `::`                                1,657 rows, of which 1,326 are
#                                      `qLegalStatus = DPW Maintained` -- the city
#                                      says it maintains a street tree here and
#                                      simply did not record which species.
#   `Tree :: Tree` / `:: Tree`            131 rows. The source says, in the only
#                                      field it has, that there IS a tree.
#
# The last two groups are 1,788 rows where our seed asserts an empty hole in the
# pavement and the source asserted no such thing. They keep their current status
# -- correcting them changes the corpus and belongs to #94 -- but they are now
# counted under their own name in the build receipt instead of being invisible
# inside a single number.
SILENT_PLACEHOLDER_SPECIES = {
    "",
    "::",
    ":: ",
    "nan ::",
    "nan",
    "no species ::",
    "unknown ::",
    "tree ::",
    ":: tree",
    "tree :: tree",
}

# qSpecies strings whose scientific-name half names no taxon: a growth habit
# ("Shrub"), an ownership note ("Private shrub"), a vernacular that resolves to
# no single plant ("Privet" is any of three Ligustrum species in this same
# inventory), a genus the surveyor could not read ("Palm (unknown Genus)"), or
# an admission that nobody has identified it yet ("To Be Determine").
#
# These are NOT placeholders: the city recorded something growing at the site.
# They are also not species, so they map to no species row at all. Before this
# list existed each one minted a species of its own and a site labelled `Shrub`
# inherited that species' phenology chips, autumn strip and field guide
# (DECISIONS constraint 15: do not invent botanical content).
#
# Under the contract these are `KIND_NOT_A_TREE`: the source is telling us the
# thing growing there is not a tree, in the only field it has to tell us in.
# See `build_seed.STATUS_FOR_KIND` for what the seed currently does with that.
#
# Keys are lowercased and whitespace-collapsed.
NON_TAXON_SPECIES = {
    "shrub :: shrub",
    "private shrub :: private shrub",
    "privet ::",
    ":: to be determine",
    "palm (unknown genus) :: palm spp",
    "new zealand tea tree :: new zealand tea tree",
    ":: brisbane box",
}

# Misspellings in qSpecies that hold one species as two. Keyed on the lowercased
# whitespace-collapsed qSpecies string; the value is (scientific name, confidence).
#
# Only entries an outside source already resolved belong here. `patanus racemosa`
# is a one-character misspelling of a name present in this same dataset, and
# Fixtures/species/leaf_retention.yaml carries the resolution with its own
# citation (SelecTree tree-detail/1107, match_method
# `fuzzy_name_edit_distance_1_to_"platanus racemosa"`). The confidence is below
# the 1.0 a clean binomial earns because the correction is ours, not the city's.
#
# What must NOT go here: a vernacular-only string merged onto a binomial by
# judgment. "Brisbane Box" names both Lophostemon confertus and Tristania
# conferta, which this inventory carries as two separate species rows, so
# merging on the common name would be a synonymy ruling with no source behind
# it. Those strings go to NON_TAXON_SPECIES instead.
QSPECIES_NAME_CORRECTIONS = {
    "patanus racemosa ::": ("Platanus racemosa", 0.9),
}

# Fixtures/species/*.yaml carries one entry per species the PREVIOUS build
# minted, so correcting the map above strands eight of them: the seven non-taxa
# lose their species row, and `patanus racemosa ::` folds into Platanus
# racemosa. The YAML files are left byte-identical -- they are a sourcing record
# with citations, not a generated index -- so the loader is told which absences
# are deliberate. Any OTHER stranded entry is real drift between the fixtures
# and the parser, and fails the build.
RETIRED_SPECIES_NAMES = {
    "Shrub",
    "Private shrub",
    "Privet",
    ":: To Be Determine",
    "Palm (unknown Genus)",
    "New Zealand Tea Tree",
    ":: Brisbane Box",
}

# The stranded entry whose sourced content is not discarded but re-keyed onto
# the species it was always a misspelling of. Its leaf retention must agree with
# what the target's own entry says, or the build fails.
MERGED_SPECIES_NAMES = {
    "patanus racemosa ::": "Platanus racemosa",
}

INCH_TO_CM = 2.54


def normalise_species_key(sci: str) -> str:
    return " ".join(sci.strip().lower().split())


def parse_qspecies(raw: str):
    """Parse the DataSF 'Scientific name :: Common name' convention.

    Returns (kind, scientific_name, common_name, confidence) where kind is one
    of 'placeholder', 'non_taxon', 'parsed', 'stub'. Unchanged from the version
    that built the shipped seed; moved here because it is a statement about
    DataSF's column, not about tree inventories.
    """
    s = (raw or "").strip()
    if s.lower() in PLACEHOLDER_SPECIES:
        return "placeholder", None, None, 0.0

    key = " ".join(s.lower().split())
    if key in NON_TAXON_SPECIES:
        # Something is planted here; it is just not a species. See NON_TAXON_SPECIES.
        return "non_taxon", None, None, 0.0

    correction = QSPECIES_NAME_CORRECTIONS.get(key)
    if correction:
        corrected_name, corrected_conf = correction
        _, _, common = s.partition("::")
        return "parsed", corrected_name, " ".join(common.strip().split()) or None, corrected_conf

    if "::" not in s:
        # No convention marker at all -> stub with the raw string as the name.
        return "stub", s, None, 0.2

    sci, _, common = s.partition("::")
    sci = " ".join(sci.strip().split())
    common = " ".join(common.strip().split())

    if not sci:
        # ':: Something' -- a common name with no scientific name.
        if not common or common.lower() in {
            "tree",
            "tree(s)",
            "potential site",
            "vacant site",
            "nan",
        }:
            return "placeholder", None, None, 0.0
        return "stub", s, common, 0.3

    if sci.lower() in {"tree(s)", "tree", "nan", "potential site", "vacant site"}:
        return "placeholder", None, None, 0.0

    tokens = sci.split()
    genus = tokens[0]

    # A scientific name should start with a capitalised genus of letters only.
    if not genus[:1].isupper() or not genus.replace("-", "").isalpha():
        return "stub", s, common or None, 0.2

    if len(tokens) == 1:
        # Genus only, e.g. "Ficus".
        conf = 0.7
    elif tokens[1].lower() in {"sp.", "spp.", "sp", "spp", "x", "hybrid"}:
        # Genus + explicit indeterminate/hybrid marker.
        conf = 0.75
    elif tokens[1][:1].islower() and tokens[1].replace("-", "").isalpha():
        # Proper binomial, optionally with cultivar/variety trailing.
        conf = 1.0 if len(tokens) == 2 else 0.9
    else:
        conf = 0.6

    return "parsed", sci, common or None, conf


def qspecies_to_contract(raw: str):
    """A DataSF-convention species string -> (kind, kind_basis, sci, common, conf, is_stub).

    The one place where "the species text did not parse" is turned into a claim
    about what the record IS, and therefore the one place worth reading twice.
    Everything it can say about the basis, it says.
    """
    kind, sci, common, conf = parse_qspecies(raw)
    key = " ".join((raw or "").strip().lower().split())

    if kind == "placeholder":
        basis = (
            KindBasis.INFERRED_FROM_ABSENT_SPECIES
            if key in SILENT_PLACEHOLDER_SPECIES
            else KindBasis.STATED
        )
        return KIND_PLANTING_SITE, basis, None, None, None, False

    if kind == "non_taxon":
        return KIND_NOT_A_TREE, KindBasis.STATED_AS_NON_TAXON, None, None, None, False

    return (
        KIND_TREE,
        KindBasis.STATED_CATEGORY,
        sci,
        common,
        conf,
        kind == "stub",
    )


# ---------------------------------------------------------------------------
# Source-specific value parsers
# ---------------------------------------------------------------------------


def parse_planted_date(raw: str, horizon_year: int) -> Optional[_datetime.date]:
    """DataSF `PlantDate` -> a date, or None. Ships '03/08/2024 12:00:00 AM'.

    The upper bound is the seed epoch's year, not the wall clock's: the seed is
    declared byte-for-byte reproducible and a clock reading inside it is ERRATA
    E13's defect. Sentinel dates outside 1800..horizon resolve to None, because
    only this adapter knows they are sentinels rather than dates.
    """
    raw = (raw or "").strip()
    if not raw:
        return None
    head = raw.split(" ")[0]
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y", "%Y/%m/%d"):
        try:
            parsed = _datetime.datetime.strptime(head, fmt).date()
        except ValueError:
            continue
        if 1800 <= parsed.year <= horizon_year:
            return parsed
        return None
    return None


def parse_dbh_inches(raw) -> Optional[float]:
    """A DataSF/ArcGIS `DBH` -> inches measured, or None.

    **`0` and blank mean "not recorded" in both of San Francisco's inventories,
    not "a zero-inch trunk".** That is a fact about these two sources and it is
    resolved here, so `InventoryRecord.dbh_in` can mean what it says: a number
    is a measurement somebody took. A city where 0 really is 0 writes its own
    adapter and this rule never reaches it.
    """
    raw = (raw or "").strip() if isinstance(raw, str) else ("" if raw is None else str(raw))
    if not raw:
        return None
    try:
        inches = float(raw)
    except ValueError:
        return None
    if inches <= 0 or inches > 400:  # 400in ~ 10m diameter; anything above is junk
        return None
    return inches


def _clean(value) -> Optional[str]:
    """Free text -> the text, or None. Blank is None; that is the contract."""
    if value is None:
        return None
    text = str(value).strip()
    return text or None


# (seed column, DataSF column) for the six carried verbatim. One list so the
# DDL, the INSERT and the adapters cannot drift apart.
CITY_RECORD_COLUMNS = [
    ("legal_status", "qLegalStatus"),
    ("caretaker", "qCaretaker"),
    ("care_assistant", "qCareAssistant"),
    ("plant_type", "PlantType"),
    ("plot_size", "PlotSize"),
    ("permit_notes", "PermitNotes"),
]

# DataSF columns consumed by an explicit mapping; everything else goes to
# city_raw (which is NULL unless --with-city-raw).
MAPPED_COLUMNS = {
    "TreeID",
    "qSpecies",
    "qAddress",
    "Latitude",
    "Longitude",
    "PlantDate",
    "DBH",
    "qSiteInfo",
    "qLegalStatus",
    "qCaretaker",
    "qCareAssistant",
    "PlantType",
    "PlotSize",
    "PermitNotes",
}


# ---------------------------------------------------------------------------
# The adapters
# ---------------------------------------------------------------------------


class SFDataSFAdapter:
    """The DataSF open-data export `tkzw-k3nq` -- 18 columns, one row per record.

    The richer of San Francisco's two inventories in facts and the looser in
    which records exist: it carries permitted sites where nothing has been
    planted and undocumented trees the maintenance inventory never adopted.
    """

    inventory_id = "sf_datasf"

    def __init__(
        self,
        csv_path: str,
        horizon_year: int,
        with_raw: bool = False,
        planting_sites_only: bool = False,
        limit: int = 0,
    ) -> None:
        self.stats = {"source_rows": 0, "dropped_no_coords": 0}
        self.csv_path = csv_path
        self.horizon_year = horizon_year
        self.with_raw = with_raw
        self.limit = limit
        #: The city build reads this export twice: once for the seven columns
        #: the city layer does not publish, and once for the vacant planting
        #: sites the layer has no category for. The second read wants only the
        #: sites, and says so here rather than by filtering downstream.
        self.planting_sites_only = planting_sites_only
        self.stats["candidate_rows"] = 0

    def records(self) -> Iterator[InventoryRecord]:
        with open(self.csv_path, "r", encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh)
            header = reader.fieldnames or []
            required = {"TreeID", "qSpecies", "qAddress", "Latitude", "Longitude"}
            missing = required - set(header)
            if missing:
                raise ValueError(f"CSV is missing expected columns: {sorted(missing)}")
            raw_columns = [c for c in header if c and c not in MAPPED_COLUMNS]

            for row in reader:
                species_text = (row.get("qSpecies") or "").strip()
                kind, basis, sci, common, conf, is_stub = qspecies_to_contract(species_text)

                if self.planting_sites_only and kind != KIND_PLANTING_SITE:
                    continue
                self.stats["candidate_rows"] += 1
                self.stats["source_rows"] += 1
                if self.limit and self.stats["source_rows"] > self.limit:
                    self.stats["source_rows"] -= 1
                    self.stats["candidate_rows"] -= 1
                    break

                lat = self._float(row.get("Latitude"))
                lon = self._float(row.get("Longitude"))
                if lat is None or lon is None:
                    self.stats["dropped_no_coords"] += 1
                    continue

                raw_json = None
                if self.with_raw:
                    payload = {}
                    for column in raw_columns:
                        value = (row.get(column) or "").strip()
                        if value:
                            payload[column] = value
                    raw_json = json.dumps(payload, separators=(",", ":"))

                yield InventoryRecord(
                    inventory=self.inventory_id,
                    kind=kind,
                    kind_basis=basis,
                    lat=lat,
                    lon=lon,
                    source_ref=_clean(row.get("TreeID")),
                    scientific_name=sci,
                    common_name=common,
                    species_confidence=conf,
                    species_text=species_text or None,
                    species_is_stub=is_stub,
                    address=_clean(row.get("qAddress")),
                    site_type=_clean(row.get("qSiteInfo")),
                    planted_on=parse_planted_date(row.get("PlantDate"), self.horizon_year),
                    dbh_in=parse_dbh_inches(row.get("DBH")),
                    # Blank becomes None -- an empty cell in this CSV means the
                    # city recorded nothing, and storing '' would make "no value"
                    # and "the value is nothing" indistinguishable downstream.
                    city_record={
                        seed_column: _clean(row.get(csv_column))
                        for seed_column, csv_column in CITY_RECORD_COLUMNS
                    },
                    raw_json=raw_json,
                )

    @staticmethod
    def _float(raw) -> Optional[float]:
        text = (raw or "").strip()
        if not text:
            return None
        try:
            value = float(text)
        except ValueError:
            return None
        return None if value != value else value  # NaN


class SFCityLayerAdapter:
    """SF Public Works' own operational layer -- what its public map draws.

    16 fields against the export's 18, and it drops nine of them. The seven the
    app depends on are carried across from the export for the records both
    inventories list; `enrichment` is that index, keyed by TreeID as a string.
    A record only this layer publishes carries None in all seven, which is the
    contract working rather than a gap to fill.

    **This layer has no vacancy category at all.** `PlantType` is `Tree` on all
    133,577 of its records. So every `KIND_PLANTING_SITE` it produces comes from
    a species field, and the two ways that happens are worth telling apart --
    see `species_of`.
    """

    inventory_id = "sf_city"

    def __init__(self, rows: list, enrichment: dict, horizon_year: int, limit: int = 0) -> None:
        self.stats = {"source_rows": 0, "dropped_no_coords": 0}
        self.rows = rows
        self.enrichment = enrichment
        self.horizon_year = horizon_year
        self.limit = limit

    @staticmethod
    def species_of(botanical, common):
        """`BOTANICAL` + `COMMON` -> the contract's species fields.

        THE ROUND TRIP THROUGH DataSF's CONVENTION IS DELIBERATE AND TEMPORARY.
        This layer publishes two clean fields, and they are packed into
        `Scientific :: Common` here only so the shipped corpus does not move --
        the whole species catalogue, its 577 uuids and its stub ceiling are
        derived through `parse_qspecies`. A new city sets `scientific_name` and
        `common_name` on the record directly; nothing outside this method needs
        to know what a `::` is.

        ONE CORRECTION IS APPLIED, AND IT MOVES NO INFORMATION. 540 of the
        layer's rows leave `BOTANICAL` null and put the botanical name in
        `COMMON`: `Lophostemon confertus`, `Pistacia chinensis`. Left alone each
        would mint a stub species beside the real species it names. Swapping the
        halves when `BOTANICAL` is empty and `COMMON` reads as a botanical name
        puts the string the city already wrote on the side of the separator that
        means what it says. `_botanical_shape` is the whole of that test.
        """
        botanical = " ".join((botanical or "").strip().split())
        common = " ".join((common or "").strip().split())
        if not botanical and common:
            swapped = SFCityLayerAdapter._botanical_shape(common)
            if swapped is not None:
                botanical, common = swapped, ""
        return f"{botanical} :: {common}".strip()

    @staticmethod
    def _botanical_shape(common: str):
        """`COMMON` -> the same name with its genus capitalised, or None.

        None means "this does not read as a botanical name", and the caller
        leaves the string on the common-name side, where it becomes a stub.

        TWO SHAPES QUALIFY, AND BOTH ARE UNAMBIGUOUS ON FORM ALONE. This test is
        deliberately blind to the species catalogue: consulting it would make the
        answer depend on ingest order, and asserting a synonymy the city did not
        write is exactly what `QSPECIES_NAME_CORRECTIONS` refuses to do.

          binomial   `Genus epithet [...]` -- a lowercase second token. The genus
                     may be miscased (`lophostemon confertus`,
                     `platanus hispanica 'columbia'`); nothing but the case of
                     the first letter is touched, and the catalogue key is
                     lowercased anyway, so the row lands on the species the city
                     named.
          cultivar   `Genus 'Cultivar'` -- the remainder wrapped in single
                     quotes, which is the ICNCP's own marker for a cultivar
                     epithet and the only thing that distinguishes a capitalised
                     botanical name from a capitalised common one.

        WHAT MUST KEEP FAILING, AND WHY THE CULTIVAR QUOTES ARE LOAD-BEARING. A
        rule that accepted any two capitalised words would swap `To Be Determine`
        -- 65 rows whose whole meaning is that nobody has identified the tree --
        onto the scientific side, where it would mint a species and escape
        `NON_TAXON_SPECIES`, which is keyed on the unswapped string. It would do
        the same to every two-word common name (`Monterey Pine`). So a bare
        `Magnolia`, a `Magnolia Little Gem` and a `Podocarpus Gracilor` are left
        as stubs: each may well be botanical, but nothing in the string says so,
        and a stub is the honest record of a name that could not be read.
        """
        tokens = common.split()
        if len(tokens) < 2:
            return None
        genus = tokens[0]
        if not genus.replace("-", "").isalpha():
            return None
        rest = " ".join(tokens[1:])
        second = tokens[1]
        binomial = second[:1].islower() and second.replace("-", "").isalpha()
        cultivar = len(rest) > 2 and rest.startswith("'") and rest.endswith("'")
        if not (binomial or cultivar):
            return None
        return f"{genus[:1].upper()}{genus[1:]} {rest}"

    def records(self) -> Iterator[InventoryRecord]:
        for record in self.rows:
            self.stats["source_rows"] += 1
            if self.limit and self.stats["source_rows"] > self.limit:
                self.stats["source_rows"] -= 1
                break

            lat = record.get("Latitude")
            lon = record.get("Longitude")
            if lat is None or lon is None or lat != lat or lon != lon:
                self.stats["dropped_no_coords"] += 1
                continue

            ref = str(record["TREEID"])
            # The join is counted on the RECORD, not in this adapter's stats, and
            # the difference is not cosmetic: a record counted here may still be
            # dropped downstream by the corpus bounding box or as a duplicate ref,
            # and `seed_meta.rows_enriched` is a claim about rows that SHIPPED.
            # Counting it at the point of the lookup overstated it by 55 rows.
            extra = self.enrichment.get(ref)

            species_text = self.species_of(record.get("BOTANICAL"), record.get("COMMON"))
            kind, basis, sci, common, conf, is_stub = qspecies_to_contract(species_text)

            # `PlantType` is this layer's own and reads `Tree` on every row; the
            # other five come from the export's row for the same TreeID, or are
            # None for a record only this layer publishes.
            city_record = {}
            for seed_column, csv_column in CITY_RECORD_COLUMNS:
                if seed_column == "plant_type":
                    city_record[seed_column] = _clean(record.get("PlantType"))
                else:
                    city_record[seed_column] = _clean((extra or {}).get(csv_column))

            yield InventoryRecord(
                inventory=self.inventory_id,
                kind=kind,
                kind_basis=basis,
                lat=lat,
                lon=lon,
                source_ref=ref,
                scientific_name=sci,
                common_name=common,
                species_confidence=conf,
                species_text=species_text or None,
                species_is_stub=is_stub,
                # Seven of this layer's columns do not exist, and are carried
                # across from the export for the records both inventories list.
                # `None` here means this layer is the only one that lists the
                # record, so those seven are genuinely absent rather than joined.
                attributes_from="sf_datasf" if extra is not None else None,
                # Stored EXACTLY as the city writes them, mostly uppercase.
                # Title-casing turns `MCALLISTER ST` into a spelling nobody uses.
                address=_clean(record.get("Address")),
                site_type=_clean((extra or {}).get("qSiteInfo")),
                planted_on=parse_planted_date((extra or {}).get("PlantDate"), self.horizon_year),
                dbh_in=parse_dbh_inches(record.get("DBH")),
                city_record=city_record,
                raw_json=None,
            )


# ---------------------------------------------------------------------------
# San Jose
# ---------------------------------------------------------------------------


# The strings San Jose writes into `NAMESCIENTIFIC` that are not species. Every
# one is measured against the live layer, 2026-07-31, 344,879 rows:
#
#     'Vacant site'   71,590   the city's own vacancy string, lower case
#     'Vacant Site'    1,405   the same claim, other spelling. Two strings, one
#                              fact -- so the set is keyed case-folded and the
#                              spelling never reaches a rule.
#     'Stump'          1,933   something is at the site and it is not a tree
#     'Unknown'        4,513   a TREE the surveyor could not identify. This one
#                              is deliberately NOT in this set; see below.
#
# `Unknown` is the case R18 already settled: a tree of unknown species is a tree,
# not an empty hole and not a non-tree. It yields KIND_TREE with no species, and
# `species_text` keeps the city's word so the build can still count them.
SJ_VACANCY_SPECIES = {"vacant site"}
SJ_NON_TREE_SPECIES = {"stump"}

#: San Jose's `TRUNKDIAM` is a double in inches, aliased "Trunk Diameter (DBH) (in)".
#: `0` appears on 72,142 rows and only 2,701 of those are `VACANTSITE = 'No'`, so
#: on the other 69,441 it sits beside a site the city says is empty: it is this
#: source's "no trunk to measure" rather than a zero-inch trunk. Two rows exceed
#: 400 in (2,304 and 445); the same 400 in ceiling the SF adapter uses rejects
#: them. All counts measured against the live layer 2026-07-31.
SJ_DBH_CEILING_IN = 400.0


class SanJoseStreetTreeAdapter:
    """City of San Jose's `Street Tree` layer -- 344,879 rows, CC-BY.

    THE REASON THIS SOURCE IS WORTH THE CONTRACT'S EXISTENCE. It publishes a
    field whose only job is to say whether a site holds a tree -- `VACANTSITE`,
    `Yes`/`No` -- which is the field E169 says no source had. So almost every
    record here reaches `KindBasis.STATED` or `STATED_CATEGORY`, and
    `INFERRED_FROM_ABSENT_SPECIES` is reached by 61 rows out of 344,879 rather
    than by 1,777 out of the 195,309-row `--source datasf` corpus (E11, E169) --
    0.018% against 0.91%. That number is the point: the basis is not a formality,
    it is a measurement of how much of the corpus is our guess.

    It also disagrees with itself, and the disagreements are the interesting
    part. Measured on 2026-07-31:

      * 611 rows are `VACANTSITE = 'Yes'` and name a real taxon. An empty hole
        that names a species is one of the two records this contract exists to
        forbid, so the adapter cannot pass both through. It keeps the flag --
        that is the field whose *only* meaning is vacancy, against a species
        field that carries four different kinds of claim -- drops the species,
        and counts the row into `vacant_sites_naming_a_taxon`.
      * 4,885 rows are `VACANTSITE = 'No'` and their species field says
        `Vacant site`, `Stump` or `Unknown`. Of those, 82 literally say
        `Vacant site` on a site the flag calls occupied. Same rule, other
        direction: the flag decides the kind for `Vacant site`, and `Stump`
        still yields `not_a_tree` because a stump is a thing that is there.
      * 3,666 rows are `VACANTSITE = 'Yes'` with a positive `TRUNKDIAM`, 1,808 of
        them with the literal `Vacant site` in the species field as well. A
        planting site with a measured trunk is not a fact, it is two records that
        were never reconciled, so `dbh_in` is dropped on any planting site and
        the count goes to `planting_sites_with_a_trunk_diameter`.

    NOT A ROUND TRIP THROUGH ANOTHER CITY'S FORMAT. `NAMESCIENTIFIC` is one
    clean field, so it is read into `scientific_name` directly. Nothing in this
    class builds a `::` string, imports `parse_qspecies`, or touches
    `PLACEHOLDER_SPECIES` -- which is what `SFCityLayerAdapter.species_of`'s
    docstring promised the third source would be able to do.

    WHAT SAN JOSE DOES NOT PUBLISH, which the contract renders as NULL and not
    as a plausible-looking stand-in:

      * a common name -- there is no such field, so `common_name` is always None
        and no species is ever minted from a vernacular (#103's mechanism);
      * a planting date on 343,537 of 344,879 rows. `INSTALLDATE` is populated
        on 1,342. `ORIGINALINVENTORYDATE` is the date somebody walked past the
        tree, not the date it was planted, and it is NOT read into `planted_on`.
    """

    inventory_id = "sj_street_tree"

    #: Layer columns carried into `city_record` under SEED column names. Keyed by
    #: seed column so no San Jose column name survives past this class.
    CITY_RECORD_COLUMNS = [
        ("legal_status", "OWNEDBY"),
        ("caretaker", "MAINTBY"),
        ("plant_type", "GROWSPACE"),
        ("plot_size", "SPACEWIDTH"),
        ("permit_notes", "CONDITION"),
    ]

    def __init__(self, rows: list, limit: int = 0) -> None:
        self.rows = rows
        self.limit = limit
        self.stats = {
            "source_rows": 0,
            "dropped_no_coords": 0,
            # Every branch of the kind decision, so its shape is a number.
            "kind_from_vacancy_flag": 0,
            "kind_from_species_vocabulary": 0,
            "kind_inferred_from_absent_species": 0,
            # The source's disagreements with itself.
            "vacant_sites_naming_a_taxon": 0,
            "planting_sites_with_a_trunk_diameter": 0,
            "trunk_diameter_over_ceiling": 0,
        }

    # ------------------------------------------------------------------ parts

    @staticmethod
    def parse_trunk_diameter(raw) -> Optional[float]:
        """`TRUNKDIAM` -> inches measured, or None. See `SJ_DBH_CEILING_IN`."""
        if raw is None:
            return None
        try:
            inches = float(raw)
        except (TypeError, ValueError):
            return None
        if inches != inches:  # NaN
            return None
        if inches <= 0:
            return None
        if inches > SJ_DBH_CEILING_IN:
            return None
        return inches

    @staticmethod
    def parse_install_date(raw) -> Optional[_datetime.date]:
        """`INSTALLDATE` -> a date, or None. The service ships epoch milliseconds.

        No horizon clamp and no sentinel list, because neither is warranted by
        anything measured in this source: `INSTALLDATE` is non-null on 1,342 rows
        and a sentinel invented for a source that does not use one is the same
        mistake as failing to resolve one that does.
        """
        if raw is None:
            return None
        try:
            millis = float(raw)
        except (TypeError, ValueError):
            return None
        if millis != millis:
            return None
        try:
            return _datetime.datetime.utcfromtimestamp(millis / 1000.0).date()
        except (OverflowError, OSError, ValueError):
            return None

    @staticmethod
    def _species_key(raw) -> str:
        return " ".join((raw or "").strip().lower().split())

    def classify(self, vacant_flag, species_raw):
        """One row's `(kind, kind_basis, scientific_name)`, and why.

        Read this next to `qspecies_to_contract`: that function had to infer a
        kind from a species string because DataSF has no other field. Here the
        kind mostly comes from a field that means only that, and the species
        field is consulted second and for a named reason each time.
        """
        flag = (vacant_flag or "").strip().lower()
        key = self._species_key(species_raw)
        name = " ".join((species_raw or "").strip().split()) or None

        if flag == "yes":
            # The city's dedicated vacancy field says the site is empty. It wins
            # over the species field even when that names a taxon (611 rows),
            # because `VACANTSITE` means exactly one thing and `NAMESCIENTIFIC`
            # means four.
            self.stats["kind_from_vacancy_flag"] += 1
            if name and key not in SJ_VACANCY_SPECIES and key not in SJ_NON_TREE_SPECIES:
                self.stats["vacant_sites_naming_a_taxon"] += 1
            return KIND_PLANTING_SITE, KindBasis.STATED, None

        if flag == "no":
            if key in SJ_VACANCY_SPECIES:
                # 82 rows: the flag says occupied and the species field says
                # `Vacant site`. Two statements, and the one that is only ever
                # about vacancy is the species field here -- it is not naming a
                # plant, it is repeating a vacancy claim. Treated as stated
                # vacancy, and reached through the species vocabulary, so it is
                # counted separately from the flag's own decisions.
                self.stats["kind_from_species_vocabulary"] += 1
                return KIND_PLANTING_SITE, KindBasis.STATED, None
            if key in SJ_NON_TREE_SPECIES:
                self.stats["kind_from_species_vocabulary"] += 1
                return KIND_NOT_A_TREE, KindBasis.STATED_AS_NON_TAXON, None
            # `VACANTSITE = 'No'` is the city's category field placing this
            # record in the ordinary category, which is what STATED_CATEGORY
            # means. `Unknown` and a blank species both land here and both are
            # trees of unknown species -- R18's answer, not a planting site.
            self.stats["kind_from_vacancy_flag"] += 1
            return KIND_TREE, KindBasis.STATED_CATEGORY, self._taxon(name, key)

        # `VACANTSITE` is null on 680 rows -- the category field is silent, so
        # the species field is all there is.
        if key in SJ_VACANCY_SPECIES:
            self.stats["kind_from_species_vocabulary"] += 1
            return KIND_PLANTING_SITE, KindBasis.STATED, None
        if key in SJ_NON_TREE_SPECIES:
            self.stats["kind_from_species_vocabulary"] += 1
            return KIND_NOT_A_TREE, KindBasis.STATED_AS_NON_TAXON, None
        if name:
            # The city wrote something in the species field. Naming what grows
            # at a site is the city stating that something grows there, in the
            # only field left once the flag is silent.
            self.stats["kind_from_species_vocabulary"] += 1
            return KIND_TREE, KindBasis.STATED, self._taxon(name, key)

        # 61 rows: no vacancy flag AND no species. The source said nothing, and
        # this is the one branch where the KIND IS OURS. Spelled with the badly
        # named basis on purpose so the build receipt carries its size.
        self.stats["kind_inferred_from_absent_species"] += 1
        return KIND_PLANTING_SITE, KindBasis.INFERRED_FROM_ABSENT_SPECIES, None

    @staticmethod
    def _taxon(name, key):
        """The scientific name to record, or None when the string names no taxon.

        `Unknown` is a tree of unknown species, so it yields None here and
        `KIND_TREE` above -- the record says a tree is there and does not say
        which. Minting a species called `Unknown` is #103 exactly.
        """
        if not name or key in {"unknown"}:
            return None
        return name

    @staticmethod
    def confidence_for(scientific_name: Optional[str]) -> Optional[float]:
        """How far to trust `NAMESCIENTIFIC`, on the same scale the SF parser uses.

        San Jose publishes 618 distinct values (measured 2026-07-31) and they are
        clean: `Platanus acerifolia`, `Quercus`, `Acer x fremanii 'Autumn Blaze'`.
        The scale is the SF one so a species catalogue built from both sources
        does not have two meanings for the same number.
        """
        if scientific_name is None:
            return None
        tokens = scientific_name.split()
        genus = tokens[0]
        if not genus[:1].isupper() or not genus.replace("-", "").isalpha():
            return 0.2
        if len(tokens) == 1:
            return 0.7
        if tokens[1].lower() in {"sp.", "spp.", "sp", "spp", "x", "hybrid"}:
            return 0.75
        if tokens[1][:1].islower() and tokens[1].replace("-", "").isalpha():
            return 1.0 if len(tokens) == 2 else 0.9
        return 0.6

    # ----------------------------------------------------------------- records

    def records(self) -> Iterator[InventoryRecord]:
        """`rows` are the layer's own features: {'attributes': {...}, 'geometry': {...}}."""
        for feature in self.rows:
            self.stats["source_rows"] += 1
            if self.limit and self.stats["source_rows"] > self.limit:
                self.stats["source_rows"] -= 1
                break

            attributes = feature.get("attributes") or {}
            geometry = feature.get("geometry") or {}
            lat, lon = geometry.get("y"), geometry.get("x")
            if lat is None or lon is None or lat != lat or lon != lon:
                self.stats["dropped_no_coords"] += 1
                continue

            species_raw = attributes.get("NAMESCIENTIFIC")
            kind, basis, scientific_name = self.classify(
                attributes.get("VACANTSITE"), species_raw
            )

            raw_dbh = attributes.get("TRUNKDIAM")
            dbh_in = self.parse_trunk_diameter(raw_dbh)
            if dbh_in is None and raw_dbh not in (None, "") and float(raw_dbh or 0) > SJ_DBH_CEILING_IN:
                self.stats["trunk_diameter_over_ceiling"] += 1
            if dbh_in is not None and kind == KIND_PLANTING_SITE:
                # A measured trunk on an empty hole is two unreconciled records,
                # not a fact. Dropped, and counted rather than quietly lost.
                self.stats["planting_sites_with_a_trunk_diameter"] += 1
                dbh_in = None

            address = " ".join(
                str(part).strip()
                for part in (attributes.get("ADDRESSNUM"), attributes.get("STREETNAME"))
                if str(part or "").strip()
            )

            yield InventoryRecord(
                inventory=self.inventory_id,
                kind=kind,
                kind_basis=basis,
                lat=float(lat),
                lon=float(lon),
                source_ref=_clean(attributes.get("FACILITYID")),
                # One clean field into one clean field. No `::` anywhere.
                scientific_name=scientific_name,
                # San Jose publishes no common name. None, never a guess.
                common_name=None,
                species_confidence=self.confidence_for(scientific_name),
                species_text=_clean(species_raw),
                # Every name this source publishes is a scientific name it wrote
                # itself, so nothing here is a stub minted from a raw string.
                species_is_stub=False,
                address=_clean(address),
                site_type=_clean(attributes.get("GROWSPACE")),
                planted_on=self.parse_install_date(attributes.get("INSTALLDATE")),
                dbh_in=dbh_in,
                city_record={
                    seed_column: _clean(attributes.get(layer_column))
                    for seed_column, layer_column in self.CITY_RECORD_COLUMNS
                },
                raw_json=None,
            )


# ---------------------------------------------------------------------------
# New York City
# ---------------------------------------------------------------------------

# NYC Parks' ForMS 2.0 publishes the inventory as TWO Socrata datasets, and the
# adapter joins them. `Forestry Tree Points` (hn5i-inap) has 20 columns and not
# one of them is an address, a borough or a site type; all of those live on
# `Forestry Planting Spaces` (82zj-84is) and arrive through
# `PlantingSpaceGlobalID` -> `GlobalID`. See docs/investigations/nyc-street-trees.md.
#
# `attributes_from` is what the contract already has for exactly this, and San
# Francisco already exercises it. What is new is that the JOIN happens here
# rather than in the builder: `build_seed.py` chooses between two already-adapted
# streams for San Francisco, whereas NYC is one stream whose attribute half is
# looked up per record.

#: The separator inside `GenusSpecies`. TWO CHARACTERS QUALIFY AND THE SECOND IS
#: THE ONE THAT MATTERS. 619 of the 620 distinct values on `TPStructure='Full'`
#: use an ASCII hyphen-minus surrounded by spaces; exactly one --
#: `Asimina triloba – Pawpaw`, 28 rows -- uses an EN DASH (U+2013), and it is the
#: only non-ASCII character anywhere in the vocabulary. Measured against the full
#: 1,121,106-row extract, 2026-08-14.
#:
#: A `str.split(" - ")` would hand that row back whole, mint a scientific name
#: reading `Asimina triloba – Pawpaw`, and stub a species that shadows the real
#: `Asimina triloba`. That is #103's mechanism exactly, and it is why this is a
#: regex over both dash characters rather than a string split.
#:
#: The spaces around the dash are load-bearing in the other direction:
#: `Crataegus crus-galli var. inermis` and `Acer x freemanii 'Autumn Blaze'`
#: carry internal hyphens, and no distinct value contains more than one SPACED
#: dash, so a single split on the first spaced dash is unambiguous.
NYC_SPECIES_SEPARATOR = re.compile(r"\s[-–]\s")

#: `GenusSpecies` strings whose scientific half names no taxon. `Unknown` is a
#: TREE the surveyor could not identify -- R18's answer and San Jose's `Unknown`
#: precedent: a tree of unknown species is a tree, not an empty hole. It yields
#: KIND_TREE with no species, and `species_text` keeps NYC's own word.
#: 5,238 rows on `Full`, measured 2026-08-14.
NYC_NON_TAXON_SCIENTIFIC = {"unknown"}

#: Trunk diameters above this are rejected as data entry rather than measurement.
#:
#: THE BOUND IS 400 IN BECAUSE THE OTHER TWO ADAPTERS USE 400 IN, AND THAT IS THE
#: ARGUMENT. `SJ_DBH_CEILING_IN` and `parse_dbh_inches` both cut at 400, so a
#: reader of the seed can say what a present `dbh_in` means without first asking
#: which city the row came from. A per-city ceiling would make the column's
#: meaning a property of its source, which is the shape this whole file exists to
#: prevent.
#:
#: What the NYC data actually looks like, measured on the 898,643 `Full` rows,
#: 2026-08-14, so the next round can tighten this from numbers rather than taste:
#:
#:      0 in (the "not recorded" sentinel)   650 rows -> None, see below
#:      1-60 in                          897,647 rows
#:      60-100 in                            208 rows
#:      100-400 in                            26 rows
#:      over 400 in                            5 rows  -> rejected here
#:                                            (2,427 / 1,310 / 999 / 830 / 410)
#:
#: So this ceiling rejects 5 rows and passes 26 that are almost certainly also
#: wrong -- a 200-inch street tree is a 17-foot trunk. Tightening it is a real
#: improvement and it is NOT made here, because the defensible number is an
#: arboricultural fact this adapter has no source for, and DECISIONS constraint 15
#: forbids inventing one. It belongs in ONE place for all three cities.
NYC_DBH_CEILING_IN = 400.0

#: `DBH` of 0 on a `Full` tree point is "not recorded", not a zero-inch trunk --
#: 650 rows, the same convention San Francisco and San Jose use and the same
#: resolution. A tree point whose structure is `Full` has a trunk by definition.
NYC_DBH_ZERO_MEANS_UNRECORDED = True

# WHICH `TPStructure` DESCRIBES A TREE. **PROVISIONAL -- see the block comment on
# `NYCTreePointAdapter.classify`.** NYC splits what the contract's `kind` wants in
# one field across two vocabularies, and this mapping is the half that is settled:
# it is about the STRUCTURE at the site, not about whether it is alive.
NYC_STRUCTURE_IS_TREE = {"full"}
NYC_STRUCTURE_IS_NOT_A_TREE = {"stump", "stump - uprooted", "shaft", "retired"}


#: How far outside every borough polygon a tree may sit and still be snapped to
#: the nearest borough rather than stopping the build. RULING D18 requires that
#: borough packs sum exactly to the whole city, so a row cannot be left
#: unassigned -- but "nearest" must be bounded or it is not a measurement.
#:
#: Measured on the 898,643 `Full` rows, 2026-08-14: 543 sit outside every
#: polygon, and their distance to the nearest borough is min 0.03 m, median
#: 25.4 m, MAX 310.0 m. They are trees on the shoreline side of a clipped
#: boundary, or on the Queens/Nassau and Bronx/Westchester city lines. 500 m
#: bounds the observed maximum with headroom and is small enough that exceeding
#: it means something changed -- at which point the build STOPS rather than
#: assigning a borough nobody measured.
NYC_MAX_SNAP_METRES = 500.0


class BoroughResolver:
    """Point-in-polygon against the City's official borough boundaries (D18).

    Deliberately a small class with no knowledge of tree points, so it can be
    tested against coordinates whose borough is independently known.

    THE PRECEDENCE, WHICH IS RULING D18's AND NOT THIS CLASS'S TO CHANGE: a tree
    that joins a planting space keeps the borough that planting space STATES.
    Geometry is run on those rows too, but only as calibration -- it reports
    disagreement and never overrides. Geometry ASSIGNS only where the source
    states nothing, which is the 22,995 orphans and the 485 joined rows whose
    planting space carries no `boroughcode`.
    """

    #: Degrees of latitude per metre, near enough at NYC's latitude for a
    #: distance bound. Not a projection -- it is used to decide whether 310 m is
    #: under a 500 m cap, and nothing finer depends on it.
    _METRES_PER_DEGREE = 111_320.0

    def __init__(self, geojson: dict) -> None:
        from shapely.geometry import shape          # imported here so the
        from shapely.prepared import prep           # adapters module stays
        from shapely.strtree import STRtree         # importable without shapely
        self._names = []
        self._polygons = []
        for feature in geojson.get("features", []):
            name = (feature.get("properties") or {}).get("boroname")
            if not name:
                raise ValueError("a borough boundary feature carries no boroname")
            self._names.append(name)
            self._polygons.append(shape(feature["geometry"]))
        if len(self._names) != 5:
            raise ValueError(f"expected 5 boroughs, got {len(self._names)}: {self._names}")
        self._tree = STRtree(self._polygons)
        self._prepared = [prep(p) for p in self._polygons]
        self._point = __import__("shapely.geometry", fromlist=["Point"]).Point

    @property
    def names(self):
        return list(self._names)

    def contains(self, lat, lon):
        """The borough whose polygon CONTAINS this point, or None."""
        point = self._point(lon, lat)
        for index in self._tree.query(point):
            if self._prepared[index].contains(point):
                return self._names[index]
        return None

    def nearest(self, lat, lon):
        """(borough, metres) for the closest polygon. Never None.

        Only consulted for a point no polygon contains, and only accepted by the
        caller within `NYC_MAX_SNAP_METRES`.
        """
        point = self._point(lon, lat)
        best, best_distance = None, None
        for index, polygon in enumerate(self._polygons):
            distance = polygon.distance(point)
            if best_distance is None or distance < best_distance:
                best, best_distance = index, distance
        return self._names[best], best_distance * self._METRES_PER_DEGREE


class NYCTreePointAdapter:
    """NYC Parks' `Forestry Tree Points`, joined to `Forestry Planting Spaces`.

    1,121,106 tree points as of 2026-08-14, of which 898,643 are `TPStructure =
    'Full'`. Redistribution is permitted; an application built on this data must
    notify the City and carry the Data Mine disclaimer verbatim
    (docs/investigations/nyc-street-trees.md §2). **Neither obligation is
    discharged by this file.**

    THE JOIN IS THE FIRST THING TO UNDERSTAND ABOUT THIS SOURCE, AND IT DOES NOT
    COVER EVERYTHING. Every one of the 1,121,106 tree points carries a
    `PlantingSpaceGlobalID` -- zero nulls -- but 22,995 of the 898,643 `Full`
    points (2.56%) name a planting space that is not in the Planting Spaces
    extract at all. Those rows are not corrupt and they are not dropped: they get
    a tree with a position, a species and a DBH, and `None` for address, borough
    and site type, which is the contract working rather than a gap to paper over.

    THE ORPHANS ARE A PUBLICATION-CADENCE ARTIFACT, NOT A DATA DEFECT, and the
    measurement says so: 99.9% of the 22,995 were `CreatedDate` 2025 or later,
    against 2.8% of the 875,648 that do join. Tree Points is refreshed every two
    weeks (`rowsUpdatedAt` 2026-07-28); Planting Spaces was last refreshed
    2025-03-05. So the unmatched rows are trees ForMS recorded after the Planting
    Spaces extract was last published, and the gap GROWS between refreshes of the
    second dataset. **A borough-partitioned build cannot place those 22,995 rows
    in a borough**, because borough is a Planting Spaces column -- which is a
    fact the distribution design round needs and is reported rather than patched.

    ONE PLANTING SPACE, ONE TREE, ALMOST. 898,633 planting spaces hold exactly one
    `Full` tree point and 5 hold two, so the join does not meaningfully fan out.
    The Planting Spaces extract itself ships 6,864 WHOLE-ROW duplicates (1,091,709
    rows, 1,084,845 distinct `GlobalID`); `fetch_nyc_trees.py` drops them and
    verifies that every dropped pair agreed in every column before doing so.

    WHAT NYC DOES NOT PUBLISH, rendered NULL rather than as a plausible stand-in:

      * a caretaker or care-assistant of any kind -- there is no such field on
        either dataset, so both are always None;
      * a planting date on 774,918 of 898,643 `Full` rows. `PlantedDate` is
        populated on 123,725 (13.77%). `CreatedDate` is the date the RECORD was
        made, not the date the tree was planted, and is NOT read into
        `planted_on` -- the same distinction San Jose's `ORIGINALINVENTORYDATE`
        forced.
    """

    inventory_id = "nyc_tree_points"

    #: Planting Spaces and Tree Points columns carried into `city_record` under
    #: SEED column names, so no NYC column name survives past this class.
    #:
    #: `plant_type` <- TPStructure and `permit_notes` <- TPCondition are the two
    #: that matter, and they are here so that NO INFORMATION IS LOST while the
    #: kind/status mapping below is still provisional. San Jose already set the
    #: precedent for the second (`permit_notes` <- `CONDITION`).
    #:
    #: `caretaker` and `care_assistant` are absent from this list because NYC
    #: publishes neither, and an absent key is NULL by the contract.
    #:
    #: `RiskRating`/`RiskRatingDate` have NO seed column to land in -- `city_record`
    #: is keyed by seed column name and the seed has no risk column -- so they go
    #: to `raw_json` under `--with-city-raw` and nowhere else. That is a real
    #: passthrough limit and it is stated here rather than discovered later.
    CITY_RECORD_COLUMNS = [
        ("plant_type", "tpstructure"),      # Full | Retired | Stump | Shaft | Stump - Uprooted
        ("permit_notes", "tpcondition"),    # Excellent | Good | Fair | Poor | Critical | Dead | Unknown
    ]

    #: Planting Spaces columns carried into `city_record`, same rules.
    PS_CITY_RECORD_COLUMNS = [
        ("legal_status", "jurisdiction"),   # DPR | Green Thumb | Private | ... | NULL on 84%
    ]

    def __init__(self, tree_point_rows, planting_spaces: dict, horizon_year: int,
                 limit: int = 0, structures=None, borough=None,
                 with_raw: bool = False, borough_resolver=None) -> None:
        """`planting_spaces` is {GlobalID -> planting space row}, already deduplicated.

        `structures` limits which `TPStructure` values are read at all, lowercased;
        `None` means every row. `borough` limits to one `Forestry Planting Spaces`
        `boroughcode`, which is how a per-borough build is expressed -- it is a
        FETCH-TIME/BUILD-TIME parameter and nothing about it is baked into the
        adapter's decisions.
        """
        self.rows = tree_point_rows
        self.planting_spaces = planting_spaces
        #: The seed epoch's year plus one, NOT the wall clock's. The seed is
        #: declared byte-for-byte reproducible and a clock reading inside it is
        #: ERRATA E13's defect.
        self.horizon_year = horizon_year
        self.limit = limit
        self.structures = {s.lower() for s in structures} if structures else None
        self.borough = borough
        #: Whether the OPTIONAL passthroughs join `boroughcode` in `raw_json`.
        #: The borough itself is never optional -- see `raw_json` below.
        self.with_raw = with_raw
        #: `BoroughResolver`, or None. RULING D18 requires every row to carry a
        #: borough, so a build with no resolver can only serve rows whose
        #: planting space states one -- `records()` stops on any row it cannot
        #: place rather than emitting one with no borough.
        self.borough_resolver = borough_resolver
        self.stats = {
            "source_rows": 0,
            "dropped_no_coords": 0,
            # The join, whose shape is the whole story of this source.
            "joined_to_planting_space": 0,
            "no_planting_space_match": 0,
            "dropped_wrong_structure": 0,
            "dropped_wrong_borough": 0,
            # Every branch of the kind decision, so its shape is a number.
            "kind_from_structure_tree": 0,
            "kind_from_structure_not_a_tree": 0,
            "kind_inferred_from_absent_species": 0,
            # The provisional half, counted so the schema round has its size.
            "standing_dead_mapped_to_alive": 0,
            # The source's own noise.
            "dbh_zero_sentinel": 0,
            "dbh_over_ceiling": 0,
            "species_unknown_taxon": 0,
            "borough_carried": 0,
            "no_borough_to_carry": 0,
            "planted_date_beyond_horizon": 0,
            # RULING D18's four outcomes, which must sum to source_rows.
            "borough_stated_by_planting_space": 0,
            "borough_from_point_in_polygon": 0,
            "borough_from_nearest_polygon": 0,
            "borough_unassigned": 0,
            # Calibration: geometry run on rows that already state a borough.
            "borough_geometry_agrees": 0,
            "borough_geometry_disagrees": 0,
            "borough_geometry_no_polygon": 0,
        }

    # ------------------------------------------------------------------ parts

    @staticmethod
    def split_genus_species(raw):
        """`GenusSpecies` -> (scientific_name, common_name), either may be None.

        NYC packs both names into one column the way DataSF does, with a spaced
        dash instead of `::`. Unlike `SFCityLayerAdapter.species_of` this does NOT
        round-trip through DataSF's `::` convention -- it is a clean split into the
        contract's two fields, which is what that method's docstring promised the
        third source would be able to do.

        Shapes present in the 620-value vocabulary, all measured 2026-08-14:

            'Quercus palustris - pin oak'                 clean binomial,      258 values
            "Zelkova serrata 'Green Vase' - ..."          quoted cultivar,     321 values
            'Platanus x acerifolia - London planetree'    hybrid,               12 values
            'Gleditsia triacanthos var. inermis - ...'    variety,               8 values
            'Morus - mulberry'                            genus only,           17 values
            'Asimina triloba – Pawpaw'                    EN DASH,               1 value
        """
        text = " ".join((raw or "").strip().split())
        if not text:
            return None, None
        parts = NYC_SPECIES_SEPARATOR.split(text, 1)
        scientific = parts[0].strip() or None
        common = (parts[1].strip() if len(parts) > 1 else "") or None
        return scientific, common

    @staticmethod
    def confidence_for(scientific_name):
        """How far to trust the scientific half, on the SF and San Jose scale.

        The scale is shared on purpose: a species catalogue built from three
        sources must not have three meanings for the same number.
        """
        if scientific_name is None:
            return None
        tokens = scientific_name.split()
        genus = tokens[0]
        if not genus[:1].isupper() or not genus.replace("-", "").isalpha():
            return 0.2
        if len(tokens) == 1:
            return 0.7
        if tokens[1].lower() in {"sp.", "spp.", "sp", "spp", "x", "hybrid", "x."}:
            return 0.75
        if tokens[1][:1].islower() and tokens[1].replace("-", "").isalpha():
            return 1.0 if len(tokens) == 2 else 0.9
        return 0.6

    def parse_dbh(self, raw):
        """`DBH` -> inches measured, or None. See `NYC_DBH_CEILING_IN`."""
        if raw is None:
            return None
        text = str(raw).strip()
        if not text:
            return None
        try:
            inches = float(text)
        except ValueError:
            return None
        if inches != inches:  # NaN
            return None
        if inches == 0:
            self.stats["dbh_zero_sentinel"] += 1
            return None
        if inches < 0:
            return None
        if inches > NYC_DBH_CEILING_IN:
            self.stats["dbh_over_ceiling"] += 1
            return None
        return inches

    def parse_planted_date(self, raw):
        """`PlantedDate` -> a date, or None. Ships `2015-08-25 10:46:44`.

        NO SENTINEL LIST, because this source does not use one -- inventing a
        sentinel for a source that does not have one is the same mistake as
        failing to resolve one that does.

        A HORIZON CLAMP, because this source DOES need one, and the number is
        measured rather than assumed. Across all 1,121,106 tree points
        (2026-08-14) `PlantedDate` is non-null on 136,730, of which exactly
        THREE are in the future and none is before 1800:

            2030-11-02  Full   CreatedDate 2020-11-04   -> 2020 typed as 2030
            2108-11-23  Full   CreatedDate 2018-11-27   -> 2018 typed as 2108
            2108-11-23  Stump  CreatedDate 2018-11-27   -> the same, twice

        Each is a transposition whose intended year is legible from its own
        `CreatedDate`, and CORRECTING them is exactly what this adapter must not
        do -- that would be inventing a fact. They resolve to None, which is the
        honest record of a date the city published wrong, and they are counted.

        The upper bound is the SEED EPOCH's year, not the wall clock's: the seed
        is byte-for-byte reproducible and a clock reading inside it is E13.
        """
        text = (raw or "").strip()
        if not text:
            return None
        head = text.split(" ")[0].split("T")[0]
        try:
            parsed = _datetime.datetime.strptime(head, "%Y-%m-%d").date()
        except ValueError:
            return None
        if 1800 <= parsed.year <= self.horizon_year:
            return parsed
        self.stats["planted_date_beyond_horizon"] += 1
        return None

    # ----------------------------------------------------------------- kinds

    def classify(self, structure, scientific_name):
        """One row's `(kind, kind_basis, scientific_name)`, and why.

        ================== THE PROVISIONAL PART, READ THIS ======================
        NYC states a record's structure (`TPStructure`) and its physical condition
        (`TPCondition`) in TWO fields, and the contract's `kind` is one field. This
        method uses ONLY `TPStructure`, and that is the whole of the compromise:

            TPStructure='Full' + TPCondition='Dead'   10,635 rows, 2026-08-14

        is a STANDING DEAD TREE. It has a trunk, a species and a location, so it is
        `KIND_TREE` by every reasonable reading -- and `build_seed.STATUS_FOR_KIND`
        turns every `KIND_TREE` into `status='alive'`, which says something about
        those 10,635 trees that NYC Parks did not say.

        **THE SEED SCHEMA IS NOT THE THING IN THE WAY, AND THE SURVEY WAS WRONG
        ABOUT THIS.** `trees.status` already permits `dead_reported`, whose own
        documentation (Cypress/DesignSystem/Components/StatusBadge.swift, RULINGS
        R19) defines it as a tree that "is still standing over a pavement" and is
        "not a second way of saying `removed`" -- precisely this case, already
        drawn, already badged, already reachable in the app.

        What is actually missing is one field on `InventoryRecord` and one lookup:
        `build_seed.STATUS_FOR_KIND` is keyed on `kind` ALONE, so no adapter can
        cause a row to ship as anything but `alive`, `vacant_site` or `alive`.
        That is a change to this contract in Python, NOT a database migration, and
        it is not made here because it moves San Francisco's and San Jose's rows
        too and this round is forbidden to touch either.

        Until it is made, NOTHING IS LOST: `TPStructure` and `TPCondition` are
        carried verbatim into `city_record` (`plant_type` and `permit_notes`), so
        every one of the 10,635 is recoverable from the seed by a later pass, and
        `stats['standing_dead_mapped_to_alive']` reports the size of the claim in
        the build receipt rather than leaving it to be rediscovered.
        ========================================================================
        """
        key = (structure or "").strip().lower()

        if key in NYC_STRUCTURE_IS_TREE:
            self.stats["kind_from_structure_tree"] += 1
            return KIND_TREE, KindBasis.STATED_CATEGORY, scientific_name

        if key in NYC_STRUCTURE_IS_NOT_A_TREE:
            # A stump, an uprooted stump, a snapped shaft, or a record NYC Parks
            # has retired. Something was there and it is not a tree now. San
            # Jose's `Stump` rows reached the same place by the same reasoning.
            self.stats["kind_from_structure_not_a_tree"] += 1
            return KIND_NOT_A_TREE, KindBasis.STATED_AS_NON_TAXON, None

        # `TPStructure` is null on 11 rows of 1,121,106. The category field is
        # silent, so the species field is all there is.
        if scientific_name:
            return KIND_TREE, KindBasis.STATED, scientific_name

        # No structure AND no species. The source said nothing, and this is the
        # one branch where the KIND IS OURS. Spelled with the badly named basis on
        # purpose so the build receipt carries its size.
        self.stats["kind_inferred_from_absent_species"] += 1
        return KIND_PLANTING_SITE, KindBasis.INFERRED_FROM_ABSENT_SPECIES, None

    # ---------------------------------------------------------------- borough

    def _peek_borough(self, lat, lon, space):
        """The borough this row WOULD get, without touching any counter.

        The filter runs before a row is admitted, and `_borough_for` runs after;
        counting in both would double every D18 statistic on a borough build.
        """
        stated = _clean((space or {}).get("boroughcode"))
        if stated:
            return stated, "planting_space"
        if self.borough_resolver is None:
            return None, "none"
        contained = self.borough_resolver.contains(lat, lon)
        if contained is not None:
            return contained, "point_in_polygon"
        nearest, metres = self.borough_resolver.nearest(lat, lon)
        if metres <= NYC_MAX_SNAP_METRES:
            return nearest, "nearest_polygon"
        return None, "none"

    def _borough_for(self, lat, lon, space):
        """(borough, how) for one tree. RULING D18. Never returns (None, ...)
        when a resolver is present.

        PRECEDENCE, WHICH IS THE RULING'S:

          1. what the planting space STATES -- the City's own attribution, and
             it wins even where geometry disagrees (7 rows do; see below);
          2. the polygon that CONTAINS the point, for a row that states nothing;
          3. the NEAREST polygon within `NYC_MAX_SNAP_METRES`, for a point no
             polygon contains.

        Geometry runs on stated rows too, and only to be counted. Measured over
        898,643 `Full` rows on 2026-08-14: 875,095 agree, **7 disagree**, and 61
        sit outside every polygon while still stating a borough. The seven are a
        real data fact and are left exactly as the City states them --
        overriding a source's own attribution from a shoreline-clipped polygon
        would be this adapter deciding a civic question.
        """
        stated = _clean((space or {}).get("boroughcode"))
        if self.borough_resolver is None:
            # No resolver: only a stated borough is available. A row without one
            # is counted as unassigned and `records()` refuses to finish.
            if stated:
                self.stats["borough_stated_by_planting_space"] += 1
                return stated, "planting_space"
            self.stats["borough_unassigned"] += 1
            return None, "none"

        contained = self.borough_resolver.contains(lat, lon)

        if stated:
            if contained is None:
                self.stats["borough_geometry_no_polygon"] += 1
            elif contained == stated:
                self.stats["borough_geometry_agrees"] += 1
            else:
                self.stats["borough_geometry_disagrees"] += 1
            self.stats["borough_stated_by_planting_space"] += 1
            return stated, "planting_space"

        if contained is not None:
            self.stats["borough_from_point_in_polygon"] += 1
            return contained, "point_in_polygon"

        nearest, metres = self.borough_resolver.nearest(lat, lon)
        if metres <= NYC_MAX_SNAP_METRES:
            self.stats["borough_from_nearest_polygon"] += 1
            return nearest, "nearest_polygon"

        # Beyond the cap. Not assigned, not guessed -- `records()` stops.
        self.stats["borough_unassigned"] += 1
        return None, "none"

    # ----------------------------------------------------------------- records

    def records(self) -> Iterator[InventoryRecord]:
        """`rows` are dicts of the columns `fetch_nyc_trees.py` caches."""
        for row in self.rows:
            structure_key = (row.get("tpstructure") or "").strip().lower()
            if self.structures is not None and structure_key not in self.structures:
                self.stats["dropped_wrong_structure"] += 1
                continue

            space = self.planting_spaces.get(
                (row.get("plantingspaceglobalid") or "").strip()
            )
            if self.borough is not None:
                # RULING D18: the filter reads the RESOLVED borough, not the
                # planting space's column. That is what makes the borough packs
                # sum to the whole city -- before D18 the 22,995 rows that join
                # no planting space were dropped by every borough build, and the
                # five packs were 22,995 rows short of the city.
                lat_probe, lon_probe = row.get("lat"), row.get("lon")
                if lat_probe is None or lon_probe is None:
                    self.stats["dropped_wrong_borough"] += 1
                    continue
                resolved, _how = self._peek_borough(float(lat_probe), float(lon_probe), space)
                if resolved != self.borough:
                    self.stats["dropped_wrong_borough"] += 1
                    continue

            self.stats["source_rows"] += 1
            if self.limit and self.stats["source_rows"] > self.limit:
                self.stats["source_rows"] -= 1
                break

            lat, lon = row.get("lat"), row.get("lon")
            if lat is None or lon is None or lat != lat or lon != lon:
                self.stats["dropped_no_coords"] += 1
                continue

            if space is None:
                self.stats["no_planting_space_match"] += 1
            else:
                self.stats["joined_to_planting_space"] += 1

            scientific, common = self.split_genus_species(row.get("genusspecies"))
            if scientific and scientific.strip().lower() in NYC_NON_TAXON_SCIENTIFIC:
                # `Unknown - Unknown`: a TREE nobody identified. R18 and San
                # Jose's `Unknown` both say a tree of unknown species is a tree.
                # Minting a species called `Unknown` is #103 exactly.
                self.stats["species_unknown_taxon"] += 1
                scientific, common = None, None

            kind, basis, scientific = self.classify(row.get("tpstructure"), scientific)

            if (structure_key == "full"
                    and (row.get("tpcondition") or "").strip().lower() == "dead"):
                self.stats["standing_dead_mapped_to_alive"] += 1

            dbh_in = self.parse_dbh(row.get("dbh"))
            if dbh_in is not None and kind != KIND_TREE:
                # A measured trunk on something that is not a tree is two
                # unreconciled records, not a fact. San Jose's rule, same reason.
                dbh_in = None

            if kind != KIND_TREE:
                common = None

            city_record = {
                seed_column: _clean(row.get(source_column))
                for seed_column, source_column in self.CITY_RECORD_COLUMNS
            }
            city_record.update({
                seed_column: _clean((space or {}).get(source_column))
                for seed_column, source_column in self.PS_CITY_RECORD_COLUMNS
            })
            if space is not None:
                width = _clean(space.get("width"))
                length = _clean(space.get("length"))
                if width and length:
                    city_record["plot_size"] = f"{width} x {length}"

            address = None
            if space is not None:
                address = " ".join(
                    part for part in (
                        _clean(space.get("buildingnumber")) or "",
                        _clean(space.get("streetname")) or "",
                    ) if part
                ).strip() or None

            # ---- BOROUGH: carried onto the RECORD, not merely filtered on.
            #
            # The city-data distribution design (docs/design-proposals/
            # 2026-08-14-city-data-distribution.md) makes the published unit a
            # borough-level region, and `boroughcode` exists ONLY on Forestry
            # Planting Spaces. If it does not ride along on the record here,
            # recovering it later means re-fetching 1.09 million rows.
            #
            # IT GOES IN `raw_json` AND NOT IN `city_record`, and that is a
            # deliberate refusal rather than an oversight. `city_record` is keyed
            # by SEED COLUMN NAME and the seed has no region column; the only two
            # unused columns are `caretaker` and `care_assistant`, and
            # `CityRecordPresentation` renders `caretaker` on the tree profile
            # under the label "Cared for by". A Queens tree reading "Cared for by
            # Queens" is a visible falsehood shipped to a user, which is a worse
            # outcome than the one this avoids. `raw_json` is the contract's OWN
            # designated home for "columns nothing maps", it reaches
            # `trees.city_raw` unconditionally, and it costs ~30 bytes a row.
            #
            # A real `trees.region` / borough column is the honest destination and
            # it is a SCHEMA question, so it is named here and not taken.
            raw = {}
            borough, borough_source = self._borough_for(float(lat), float(lon), space)
            if borough:
                raw["boroughcode"] = borough
                raw["boroughsource"] = borough_source
                self.stats["borough_carried"] += 1
            else:
                self.stats["no_borough_to_carry"] += 1
            if self.with_raw:
                # The survey's suggested passthroughs, which likewise have no
                # seed column: a risk assessment with no equivalent anywhere in
                # the corpus, and the planting space's own status.
                for key, value in (
                    ("psstatus", _clean((space or {}).get("psstatus"))),
                    ("riskrating", _clean(row.get("riskrating"))),
                    ("riskratingdate", _clean(row.get("riskratingdate"))),
                ):
                    if value:
                        raw[key] = value

            yield InventoryRecord(
                inventory=self.inventory_id,
                kind=kind,
                kind_basis=basis,
                lat=float(lat),
                lon=float(lon),
                # `GlobalID`, a ForMS asset UUID -- never `OBJECTID`, which is the
                # feature service's row number and moves on republish. Measured
                # unique across all 1,121,106 rows, 2026-08-14.
                source_ref=_clean(row.get("globalid")),
                # One packed field into the contract's two. No `::` anywhere.
                scientific_name=scientific,
                common_name=common,
                species_confidence=self.confidence_for(scientific),
                species_text=_clean(row.get("genusspecies")),
                # Every name here is one NYC wrote in its own species column; the
                # builder resolves it against the corpus and decides stubbing.
                species_is_stub=False,
                # The address, borough and site type came from the OTHER dataset.
                # `None` here means this tree point matched no planting space, so
                # those facts are genuinely absent rather than joined.
                attributes_from="nyc_planting_spaces" if space is not None else None,
                address=address,
                site_type=_clean((space or {}).get("pssite")),
                planted_on=self.parse_planted_date(row.get("planteddate")),
                dbh_in=dbh_in,
                city_record=city_record,
                raw_json=json.dumps(raw, separators=(",", ":"), sort_keys=True) if raw else None,
            )

        # RULING D18: borough packs must sum EXACTLY to the whole city, so a run
        # that could not place a row does not get to finish quietly. This is
        # raised after the last yield, so a caller that consumed the generator
        # sees it; a caller that stopped early was not making a pack.
        if self.stats["borough_unassigned"]:
            raise ValueError(
                f"{self.stats['borough_unassigned']:,} NYC tree points could not be "
                f"placed in any borough -- no planting space states one, no polygon "
                f"contains them, and the nearest is beyond "
                f"{NYC_MAX_SNAP_METRES:.0f} m. RULING D18 requires borough packs to "
                f"sum exactly to the whole city, so this is a stop rather than a "
                f"row with no borough. Re-check the boundary file and the extract."
            )
