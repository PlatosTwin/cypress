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

    inventory_id = "datasf"

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

    inventory_id = "city"

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

        ONE CORRECTION IS APPLIED, AND IT MOVES NO INFORMATION. 475 of the
        layer's rows leave `BOTANICAL` null and put the botanical name in
        `COMMON`: `Lophostemon confertus`, `Pistacia chinensis`. Left alone each
        would mint a stub species beside the real species it names. Swapping the
        halves when `BOTANICAL` is empty and `COMMON` reads as a binomial puts
        the string the city already wrote on the side of the separator that
        means what it says.
        """
        botanical = " ".join((botanical or "").strip().split())
        common = " ".join((common or "").strip().split())
        if not botanical and common:
            tokens = common.split()
            if (
                len(tokens) >= 2
                and tokens[0][:1].isupper()
                and tokens[0].replace("-", "").isalpha()
                and tokens[1][:1].islower()
                and tokens[1].replace("-", "").isalpha()
            ):
                botanical, common = common, ""
        return f"{botanical} :: {common}".strip()

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
                attributes_from="datasf" if extra is not None else None,
                # Stored EXACTLY as the city writes them, mostly uppercase.
                # Title-casing turns `MCALLISTER ST` into a spelling nobody uses.
                address=_clean(record.get("Address")),
                site_type=_clean((extra or {}).get("qSiteInfo")),
                planted_on=parse_planted_date((extra or {}).get("PlantDate"), self.horizon_year),
                dbh_in=parse_dbh_inches(record.get("DBH")),
                city_record=city_record,
                raw_json=None,
            )

