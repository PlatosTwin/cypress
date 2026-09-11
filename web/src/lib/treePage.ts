/**
 * W1 · the public tree page, as a value.
 *
 * Everything the page renders is decided here and nothing is decided in the `.astro` file, for the
 * reason every `*Presentation` and `*Copy` in the iOS app is out of its view: **a sentence a state
 * produces is a decision, and a decision is worth a test that does not have to render anything to
 * read it.** This module imports no `node:sqlite`, no Astro and no DOM; it takes the row the pack
 * gave and returns the page.
 *
 * ── What v1 renders, and the ruling behind it ────────────────────────────────────────────────
 *
 * `docs/ROADMAP.md` §W records the finding that reshaped this milestone: **W1's fact column is
 * about half contributed data.** The tree's name, its vitality, its measured height, the taped DBH
 * reading, the photo count and the recent-visits panel all live in the *writable* database and
 * reach the server as contributions, whose public read surface is Class R — the contributor's own
 * data. There is no public read for any of it, so v1 renders the city record and nothing else.
 *
 * **Nothing contributed is stubbed, faked or approximated.** Where §W1 specifies a fact the pack
 * cannot answer, the element is absent. It is not drawn empty, not drawn with a placeholder, and
 * not drawn with the nearest city-record fact wearing the contributed fact's label. The one row
 * where a city-record fact takes a contributed row's *place* is the DBH bucket, and it carries the
 * `city record` badge precisely so it cannot be read as the taped reading it is standing in for
 * (D7, E63).
 *
 * The full list of §W1 elements this does not render, and why each one is absent, is in the pull
 * request that added this file.
 *
 * ── Where the copy comes from ────────────────────────────────────────────────────────────────
 *
 * `src/lib/cityRecord.ts` carries the labels and formats, ported from the iOS app and checked
 * against it at run time. The title and subtitle precedences below are `TreeProfilePresentation`'s
 * and `SiteCopy`'s, with the contributed rung — a given name (D15) — removed rather than replaced,
 * because that rung has no public read either.
 */
import {
  cityDBHRangeText,
  cityRecordBadge,
  provenanceNote,
  recordNumber,
  snapshotDay,
  statedValue,
  statusLabel,
} from './cityRecord.ts';

/** What one row of the fact column says. `SCREENS.md` C30 · `WebFactRow`. */
export interface FactRow {
  /** Stable across renders, so a test names a row rather than an index. */
  readonly id: string;
  readonly label: string;
  readonly value: string;
  /** The C30 method badge beside the value, when the fact carries one. */
  readonly badge: string | null;
  /**
   * C30 draws one row at weight 700 in `--color-canopy`. §W1 gives that treatment to `Status`,
   * and the status is what this page's first row still carries.
   */
  readonly emphasized: boolean;
}

/** The everything-this-page-knows input. Assembled by the route from the pack, never guessed. */
export interface TreePageInput {
  readonly idSpace: string;
  readonly uuid: string;
  readonly status: string;
  readonly address: string | null;
  readonly neighborhoodName: string | null;
  readonly cityName: string | null;
  readonly speciesCommonName: string | null;
  readonly speciesScientificName: string | null;
  readonly plantedYear: number | null;
  readonly dbhCityCmMin: number | null;
  /** EXCLUSIVE — see `cityDBHRangeText`. */
  readonly dbhCityCmMax: number | null;
  readonly siteType: string | null;
  readonly externalRef: string | null;
  /** The inventory that listed this row, as the pack's own `inventories` table states it. */
  readonly inventoryName: string | null;
  readonly inventoryURL: string | null;
  /** `seed_meta.inventory_<id>_snapshot_on` — a bare `YYYY-MM-DD`, or absent. */
  readonly inventorySnapshotOn: string | null;
  /** `seed_meta.inventory_<id>_licence` — absent for San Francisco, and that is the honest state. */
  readonly inventoryLicence: string | null;
}

/** The italic-or-not runs of the serif line under the H1. */
export interface SubtitlePart {
  readonly text: string;
  /** A scientific name is set italic, as §W1's `Latin Serif italic` line is. Nothing else is. */
  readonly italic: boolean;
}

/** The `Data` row, which ruling 4 of the web round's owner decisions shapes on its own. */
export interface TermsLine {
  readonly label: string;
  readonly value: string;
  /** Why the value is what it is, when it is an absence. Null when the receipt recorded terms. */
  readonly note: string | null;
}

export interface TreePageModel {
  readonly idSpace: string;
  readonly uuid: string;
  /** `/sf/tree/<uuid>` — the path `ShareCopy.publicURLPrefix` has always pointed at. */
  readonly path: string;
  /** §W1's hero eyebrow: where this record is. */
  readonly eyebrow: string | null;
  readonly title: string;
  readonly subtitle: readonly SubtitlePart[];
  readonly facts: readonly FactRow[];
  readonly terms: TermsLine;
  /** `From the SF Public Works street tree inventory, August 22, 2026.` — or absent. */
  readonly provenance: string | null;
  readonly documentTitle: string;
  readonly description: string;
}

// ── Copy this file authors, which is as little as it could be ───────────────────────────────

/**
 * The four strings below are **not** ported from anywhere, because nothing in the app or the mocks
 * says them. They are collected here rather than spread through the functions so that a reader —
 * or the owner ratifying them — can see the whole of this page's invented language at once, which
 * is the practice `SiteCopy` established for the screen SCREENS.md does not draw.
 *
 * They are written to `docs/rulings-pending/` for ratification under the W-3 exception, and the
 * entry states what each one is allowed to claim.
 */
export const W1Copy = {
  /** The `Data` row's value when the publisher's receipt records no licence for the inventory. */
  noLicenceRecorded: 'no licence recorded',
  /**
   * Why that row is empty, because ruling 4 requires the page to say why rather than look broken.
   *
   * It states what Cypress does, not what the city failed to do: the receipt's silence is a fact
   * about the pipeline, and a sentence blaming a public works department for it would be asserting
   * something this project did not measure.
   */
  noLicenceNote:
    'Cypress states each source’s own terms and says nothing where the record carries none.',
  /** `TreeProfilePresentation.fallbackTitle`, for a record with no species and no address. */
  unnamedRecord: 'Tree',
  /** `SiteCopy.fallbackTitle`, for a planting site with no address. */
  unnamedSite: 'Planting site',
} as const;

/** `SiteCopy.kind`, verbatim — what a vacant record IS, when the H1 could not say it. */
const VACANT_SITE_KIND = 'Vacant planting site';

// ── The model ───────────────────────────────────────────────────────────────────────────────

/**
 * The H1.
 *
 * `TreeProfilePresentation.title`'s precedence with its first rung removed: a given name wins
 * there (D15) and there is no public read for one, so the species common name is the top rung
 * here. A vacant site takes `SiteCopy.title` instead — the address and nothing else — because "a
 * site has no species to be named after", and a planting basin labelled with a species would be
 * asserting a tree.
 */
export function title(input: TreePageInput): string {
  const address = statedValue(input.address);
  if (input.status === 'vacant_site') return address ?? W1Copy.unnamedSite;
  const common = statedValue(input.speciesCommonName);
  if (common !== null) return common;
  if (address !== null) return address;
  return W1Copy.unnamedRecord;
}

/**
 * The serif line under the H1.
 *
 * `SiteCopy.subtitle`'s rule, applied to both kinds of record: **name the record with every fact
 * the H1 has not already used, then state where it came from.** Provenance is not optional
 * (BUILD-PLAN §5, no UI-only provenance), so the inventory is the last part whenever the pack
 * names one — which is also what keeps this line and the provenance sentence at the foot of the
 * column derived from one value, the property R28 exists to preserve.
 */
export function subtitle(input: TreePageInput): readonly SubtitlePart[] {
  const heading = title(input);
  const parts: SubtitlePart[] = [];
  if (input.status === 'vacant_site') {
    if (heading !== W1Copy.unnamedSite) parts.push({ text: VACANT_SITE_KIND, italic: false });
  } else {
    const common = statedValue(input.speciesCommonName);
    if (common !== null && common !== heading) parts.push({ text: common, italic: false });
  }
  const scientific = statedValue(input.speciesScientificName);
  if (scientific !== null && scientific !== heading) parts.push({ text: scientific, italic: true });
  const inventory = statedValue(input.inventoryName);
  if (inventory !== null) parts.push({ text: inventory, italic: false });
  return parts;
}

/**
 * §W1's hero eyebrow — `Great Highway at Judah · San Francisco`.
 *
 * The address leads, exactly as the mock draws it, **unless the address is already the H1**, in
 * which case the neighborhood takes its place so the two elements do not say the same thing twice.
 * A pack older than generation 16 cannot name a city at all (`TreeRow.cityName`), and then the
 * eyebrow is whatever is left rather than a city this page invented.
 */
export function eyebrow(input: TreePageInput): string | null {
  const address = statedValue(input.address);
  const city = statedValue(input.cityName);
  const where = address !== null && address !== title(input)
    ? address
    : statedValue(input.neighborhoodName);
  const parts = [where, city].filter((part): part is string => part !== null);
  return parts.length === 0 ? null : parts.join(' · ');
}

/**
 * The C30 rows, in §W1's order, with every row the pack cannot answer simply absent.
 *
 * §W1's six rows map onto four here. `Height` is gone — a measured height is contributed and there
 * is no public read for one — and `Trunk · DBH` keeps its label while its value becomes the city's
 * published bucket with the `city record` badge, which is the one substitution on the page and the
 * badge is why it is legible as one.
 *
 * `Site` is added, and it is not an invention: it is screen 14's own card, which
 * `TreeProfilePresentation` draws "only where the city record is all there is to show" — the exact
 * condition this page is in.
 *
 * ── A vacant planting site draws fewer of them, and that is a ruling ─────────────────────────
 *
 * `SitePresentation.stats` is explicit: a site gets `Site`, `City record` and `Neighborhood`, with
 * **no `Planted` card and no measurement**, because "the second is a claim about a tree". The seed
 * carries both on real vacant rows — `124 COLUMBUS AVE` in the shipped San Francisco pack is a
 * `vacant_site` with `planted_year` 2016 and a 5–10 cm city bucket — so this is not hypothetical
 * tidying: rendering them would put a trunk diameter and a planting year on a page whose subject is
 * a basin with nothing in it. E107 is the whole argument, and `Neighborhood` is the card that takes
 * their place there.
 */
export function facts(input: TreePageInput): readonly FactRow[] {
  const rows: FactRow[] = [];
  const isSite = input.status === 'vacant_site';

  const status = statusLabel(input.status);
  if (status !== null) {
    rows.push({ id: 'status', label: 'Status', value: status, badge: null, emphasized: true });
  }

  const dbh = isSite ? null : cityDBHRangeText(input.dbhCityCmMin, input.dbhCityCmMax);
  if (dbh !== null) {
    rows.push({
      id: 'dbh', label: 'Trunk · DBH', value: dbh, badge: cityRecordBadge, emphasized: false,
    });
  }

  if (!isSite && input.plantedYear !== null && Number.isInteger(input.plantedYear)) {
    // `Planted`, not §W1's `In the city record since`. The column is `planted_year` — DataSF's
    // `PlantDate` — so it states when the tree went in, not when the city began keeping a record
    // of it, and the mock's label makes a claim the data does not. `Planted` is the label the app
    // already draws over this same column. The deviation is an errata entry, not a silent change.
    rows.push({
      id: 'planted',
      label: 'Planted',
      value: String(input.plantedYear),
      badge: null,
      emphasized: false,
    });
  }

  const site = statedValue(input.siteType);
  if (site !== null) {
    rows.push({ id: 'site', label: 'Site', value: site, badge: null, emphasized: false });
  }

  const ref = statedValue(input.externalRef);
  if (ref !== null) {
    rows.push({
      id: 'cityRecord',
      label: 'City record',
      value: recordNumber(ref),
      badge: null,
      emphasized: false,
    });
  }

  // `SiteCopy.neighborhoodLabel`. Only on a site, exactly where `SitePresentation` draws it: on a
  // tree, 03 and 14 have no such card and adding one here would be a fourth surface's invention.
  const neighborhood = isSite ? statedValue(input.neighborhoodName) : null;
  if (neighborhood !== null) {
    rows.push({
      id: 'neighborhood',
      label: 'Neighborhood',
      value: neighborhood,
      badge: null,
      emphasized: false,
    });
  }

  return rows;
}

/**
 * §W1's `Data` row, under the web round's owner ruling 4: **state what the receipt records, say
 * less where it does not.**
 *
 * The mock's transcribed value is `ODbL · CSV / GeoJSON`, and it cannot be rendered. ODbL is the
 * licence *contributors* grant at signup; v1 publishes no contributions, so claiming it over city
 * rows would assert a licence over data this project does not hold the rights to license. The
 * ingest receipt carries San Jose's `CC-BY` and New York's Data Mine terms and carries **nothing
 * for San Francisco**, the largest and oldest source — so San Francisco's row is the emptiest one
 * on the page, which is the honest state and is why the note exists.
 *
 * The licence string is reproduced **verbatim** from the receipt rather than shortened. New York's
 * reads `NYC Open Data / Data Mine terms; notification + verbatim disclaimer required`, and a
 * reader is owed the whole of it — an obligation summarized away is an obligation not discharged.
 */
export function terms(input: TreePageInput): TermsLine {
  const licence = statedValue(input.inventoryLicence);
  if (licence !== null) return { label: 'Data', value: licence, note: null };
  return { label: 'Data', value: W1Copy.noLicenceRecorded, note: W1Copy.noLicenceNote };
}

/** One factual sentence for `og:description` and `<meta name="description">`. */
function description(input: TreePageInput, model: Omit<TreePageModel, 'description'>): string {
  const sentences: string[] = [];
  const scientific = statedValue(input.speciesScientificName);
  const where = model.eyebrow;
  const lead = [model.title, scientific === null || scientific === model.title ? null : scientific]
    .filter((part): part is string => part !== null)
    .join(' · ');
  sentences.push(where === null ? `${lead}.` : `${lead} — ${where}.`);
  const identity = model.facts.find((row) => row.id === 'cityRecord');
  if (identity !== undefined && input.inventoryName !== null) {
    sentences.push(`${identity.value} in the ${input.inventoryName}.`);
  }
  return sentences.join(' ');
}

/** The whole page. */
export function treePageModel(input: TreePageInput): TreePageModel {
  const heading = title(input);
  const city = statedValue(input.cityName);
  const partial: Omit<TreePageModel, 'description'> = {
    idSpace: input.idSpace,
    uuid: input.uuid,
    path: `/${input.idSpace}/tree/${input.uuid}`,
    eyebrow: eyebrow(input),
    title: heading,
    subtitle: subtitle(input),
    facts: facts(input),
    terms: terms(input),
    provenance: input.inventoryName === null
      ? null
      : provenanceNote(input.inventoryName, snapshotDay(input.inventorySnapshotOn)),
    documentTitle: city === null ? heading : `${heading} · ${city}`,
  };
  return { ...partial, description: description(input, partial) };
}
