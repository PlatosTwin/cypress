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
 * data.
 *
 * **Two of those now have a public read and this file uses it.** PR #163 (milestone W-G) shipped
 * `GET /api/v1/public/trees/{id}`: the latest live height, the latest live trunk DBH — each with
 * its entered unit, its method and its month — and R27.1's beloved state with its count above the
 * floor. `src/lib/publicTreeRead.ts` is the client; this file decides what the page does with the
 * answer, and with the three different ways there can fail to be one.
 *
 * **The rest is still absent and the endpoint agrees.** There is no tree name anywhere in this
 * system, no vitality rating in the response (it was removed before #163 merged, because a
 * published rating has no takedown route), no photo count, no visits panel and no photographs.
 *
 * **Nothing contributed is stubbed, faked or approximated.** Where §W1 specifies a fact neither
 * half can answer, the element is absent. It is not drawn empty, not drawn with a placeholder, and
 * not drawn with the nearest city-record fact wearing the contributed fact's label. The one row
 * where a city-record fact takes a contributed row's *place* is the DBH bucket, and it carries the
 * `city record` badge precisely so it cannot be read as the taped reading it is standing in for
 * (D7, E63) — and it now yields that place to the taped reading itself whenever there is one.
 *
 * The full list of §W1 elements this does not render, and why each one is absent, is in the pull
 * request that added this file.
 *
 * ── The community half may be missing, and that is the ordinary case ─────────────────────────
 *
 * Nothing about this page depends on the service answering. The page's spine is the city record —
 * public data under ODbL that no contributor can withdraw — so a refused connection, a timeout, an
 * unset variable or a body this build cannot read all leave a page that resolves, states what the
 * city knows, and says it could not ask for the rest. That is the ruling's §8c property, and it is
 * why there is no `throw` on the request path.
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
  provenanceNote,
  recordNumber,
  snapshotDay,
  statedValue,
  statusLabel,
} from './cityRecord.ts';
import {
  CITY_RECORD_BADGE,
  measuredValueText,
  methodBadge,
  type Badge,
} from './measuredValue.ts';
import { sourceObligation, type SourceObligation } from './obligations.ts';
import { COMMUNITY_NOT_REQUESTED, type CommunityHalf, type PublicReading } from './publicTreeRead.ts';

/** What one row of the fact column says. `SCREENS.md` C30 · `WebFactRow`. */
export interface FactRow {
  /** Stable across renders, so a test names a row rather than an index. */
  readonly id: string;
  readonly label: string;
  readonly value: string;
  /** The C30 method badge beside the value, when the fact carries one. */
  readonly badge: Badge | null;
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
  /** `seed_meta.inventory_<id>_license` — absent for San Francisco, and that is the honest state. */
  readonly inventoryLicense: string | null;
  /**
   * What this render learned from `GET /api/v1/public/trees/{id}`, or that it did not ask.
   *
   * **Optional, and the default is `notRequested` rather than "nothing".** A caller that renders
   * the city record alone — the OpenGraph card does — gets exactly the page W-C shipped, and the
   * five states are `publicTreeRead.ts`'s. The two that matter here are `empty` and `unavailable`:
   * one is a fact about the tree and the other is a fact about this server, and they render
   * differently for that reason.
   */
  readonly community?: CommunityHalf;
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
  /**
   * What this record's source obliges the page to print, verbatim, or `null`.
   *
   * R36's binding consequence (b) and R78 ruling 3: the obligation follows the data onto whatever
   * surface serves it, and a machine-readable `attribution` array does not discharge it. It is on
   * the model rather than in the template so that "does this page carry it" is a question a test
   * can ask of a value.
   */
  readonly obligation: SourceObligation | null;
  /**
   * Which of the five community states this render is in — `publicTreeRead.ts`'s own tag.
   *
   * On the model rather than left in the route, so "do these three states render differently" is a
   * question a test can ask of a value. The page also writes it into the markup, which is the only
   * channel an operator has for the difference between `empty` and `unavailable` once the page has
   * been served: a `.astro` page's 200 keeps its headers, but the reasons are long and belong in
   * the process log beside the refusals W-C already logs there.
   */
  readonly communityState: CommunityHalf['state'];
  /**
   * One sentence when this page **cannot speak** for the community half, null otherwise.
   *
   * It is not an error banner and it is not on every page: it appears exactly when a silence would
   * otherwise be read as an answer. `empty` means the service answered and this tree has nothing —
   * rendering nothing there is the house style and the reader is not misled. `unavailable` and
   * `unconfigured` mean this page does not know, and a page that drew those the same way as
   * `empty` would assert "nobody has measured this tree" every time it was merely unable to ask.
   */
  readonly communityNote: string | null;
  readonly documentTitle: string;
  readonly description: string;
}

// ── Copy this file authors, which is as little as it could be ───────────────────────────────

/**
 * The six strings below are **not** ported from anywhere, because nothing in the app or the mocks
 * says them. They are collected here rather than spread through the functions so that a reader —
 * or the owner ratifying them — can see the whole of this page's invented language at once, which
 * is the practice `SiteCopy` established for the screen SCREENS.md does not draw.
 *
 * They are written to `docs/rulings-pending/` for ratification under the W-3 exception, and the
 * entry states what each one is allowed to claim.
 *
 * **Two of them arrived with the community half and neither has a mock behind it**, which makes
 * both a DECISIONS constraint 21 stop-and-ask. The conservative option is taken and named: one
 * sentence covering every way this page can fail to ask, and one label for a state §W1 does not
 * draw but an owner ruling requires (2026-09-10, `docs/rulings-pending/public-tree-read.md` §1a).
 */
export const W1Copy = {
  /** The `Data` row's value when the publisher's receipt records no license for the inventory. */
  noLicenseRecorded: 'no license recorded',
  /**
   * Why that row is empty, because ruling 4 requires the page to say why rather than look broken.
   *
   * It states what Cypress does, not what the city failed to do: the receipt's silence is a fact
   * about the pipeline, and a sentence blaming a public works department for it would be asserting
   * something this project did not measure.
   */
  noLicenseNote:
    'Cypress states each source’s own terms and says nothing where the record carries none.',
  /** `TreeProfilePresentation.fallbackTitle`, for a record with no species and no address. */
  unnamedRecord: 'Tree',
  /** `SiteCopy.fallbackTitle`, for a planting site with no address. */
  unnamedSite: 'Planting site',
  /**
   * The `Beloved` row's label. R27.1's own word, which is the closest thing to a source there is:
   * nothing in `Cypress/`, in the mocks or in `SCREENS.md` says `beloved` anywhere.
   *
   * The row exists because the owner ruled on 2026-09-10 that the state ships on this page — §W1
   * does not draw it, so without that ruling it would not be here. It is a **state and not a
   * rank**, which is what the label has to carry: no position, no "most loved", no comparison to
   * another tree, because there is no ranking on one tree's page.
   */
  belovedLabel: 'Beloved',
  /**
   * What this page says when it could not ask for the community half.
   *
   * It states what happened and what is still true, in that order, because the second half is the
   * point: nothing above it is affected, and a reader who sees this has not been shown a page with
   * a hole in it. It does **not** say why — an unset variable, a refused connection and a timeout
   * are one fact to a reader and three to an operator, and the operator's three are in the log.
   *
   * The word is `contributions` rather than `measurements` because the beloved state is not a
   * measurement and this sentence covers its absence too.
   */
  communityUnavailable:
    'Community contributions could not be loaded, so this page shows the city record alone.',
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

/** The community half this render is working from, or the not-asked default. */
function communityOf(input: TreePageInput): CommunityHalf {
  return input.community ?? COMMUNITY_NOT_REQUESTED;
}

/** The decoded body when there is one, otherwise null. Every other state answers null. */
function answered(input: TreePageInput) {
  const half = communityOf(input);
  return half.state === 'answered' ? half.read : null;
}

/**
 * One live reading as a C30 row: the value as it was entered, its method badge beside it.
 *
 * `MeasuredValue` is the only way the design system renders a `Quantity` — *"there is no view in
 * the design system that renders a `Quantity`'s number alone"* — and this is that rule on the web.
 * The two are built together here so no caller can assemble half of one.
 *
 * **The month does not reach the row, and that is deliberate rather than an omission.** The
 * endpoint publishes `2026-08` and §W1's fact column draws `18 m` `est.` with no date on it. The
 * date is on the value for the ruling's §4 reason — a diameter with no date is not a reading — but
 * C30 has one value slot and a row reading `18 m · Aug 2026 · est.` is a row nothing draws. It is
 * carried on the model and is the obvious next thing a design round can place.
 */
function readingRow(id: string, label: string, reading: PublicReading): FactRow {
  return {
    id,
    label,
    value: measuredValueText(reading.quantity),
    badge: methodBadge(reading.quantity.method),
    emphasized: false,
  };
}

/**
 * The C30 rows, in §W1's order, with every row neither half can answer simply absent.
 *
 * ── W-C shipped four of §W1's six; the community read fills two more ─────────────────────────
 *
 * `Height` is §W1's second row and it was **absent** when this file was written, because a measured
 * height is contributed and there was no public read for one. There is now, so the row is here when
 * the service answers with a height — value, entered unit and method badge, which is all three of
 * D7's parts and the only shape this project renders a quantity in.
 *
 * `Trunk · DBH` is the one row on this page with two possible sources, and the precedence is
 * **the live reading first**. W-C's own note said the city bucket "takes a contributed row's
 * place" and carries the `city record` badge "precisely so it cannot be read as the taped reading
 * it is standing in for". When the reading it was standing in for arrives, the stand-in stands
 * down: §W1 draws one `Trunk · DBH` row, it draws `64 cm` `taped`, and that is what this renders.
 * With no live reading the bucket is back, badged as the city's, exactly as W-C shipped it.
 *
 * `Beloved` is **not in §W1 at all** and is here on an owner ruling of 2026-09-10 — the state
 * ships on the public tree page, as a state and not a rank. It is appended after the rows §W1 does
 * draw rather than inserted among them, because the specification's order is a transcription and
 * an undrawn row has no place in it to claim.
 *
 * `Status` still carries the lifecycle enum and not a vitality rating. §W1 draws
 * `Thriving · vitality 4`; the rating is **not in the response** — it was removed from the endpoint
 * before it merged because a published rating has no takedown route (the ruling's §8), and nothing
 * here invents one.
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
 *
 * **A vacant site draws no community reading either, and that is the same ruling extended.**
 * `SitePresentation.stats` refuses a measurement on a site because "the second is a claim about a
 * tree", and the claim is no less a claim for having been taped by a person rather than published
 * by a city. A reading against a basin the city records as empty is a disagreement with the city
 * record, which is `data_dispute`'s subject and is withheld from this endpoint by name. The
 * beloved state is not a measurement and stays: a site can be somebody's favorite, and saying so
 * asserts nothing about a tree being there.
 */
export function facts(input: TreePageInput): readonly FactRow[] {
  const rows: FactRow[] = [];
  const isSite = input.status === 'vacant_site';
  const community = answered(input);

  const status = statusLabel(input.status);
  if (status !== null) {
    rows.push({ id: 'status', label: 'Status', value: status, badge: null, emphasized: true });
  }

  const height = isSite ? null : community?.height ?? null;
  if (height !== null) rows.push(readingRow('height', 'Height', height));

  const liveDBH = isSite ? null : community?.trunkDBH ?? null;
  const dbh = isSite ? null : cityDBHRangeText(input.dbhCityCmMin, input.dbhCityCmMax);
  if (liveDBH !== null) {
    rows.push(readingRow('dbh', 'Trunk · DBH', liveDBH));
  } else if (dbh !== null) {
    rows.push({
      id: 'dbh', label: 'Trunk · DBH', value: dbh, badge: CITY_RECORD_BADGE, emphasized: false,
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

  /**
   * `Beloved · 11 favorites` — R27.1's state with the number the owner ruled rides along with it.
   *
   * **It renders only when the service said so, and only with its number.** `beloved` is true
   * exactly at three or more distinct account-backed favorite owners, and `beloved_by` is null
   * below that floor rather than nought — a count under a k-anonymity threshold is the disclosure
   * the threshold exists to prevent. `decodePublicTreeRead` drops the pair when they disagree, so
   * a row here always has both halves and this page never publishes one without the other.
   *
   * The value is `favorites` and not `people`: the count is of accounts, and one person with two
   * Apple IDs is two of them. Saying `people` would be this page overstating what the number is.
   * The plural is agreed with rather than assumed — the floor makes a `1` unreachable today, and a
   * row reading `1 favorites` would be wrong on the day somebody changes the floor.
   */
  const belovedBy = community?.beloved === true ? community.belovedBy : null;
  if (belovedBy !== null) {
    rows.push({
      id: 'beloved',
      label: W1Copy.belovedLabel,
      value: `${String(belovedBy)} ${belovedBy === 1 ? 'favorite' : 'favorites'}`,
      badge: null,
      emphasized: false,
    });
  }

  return rows;
}

/**
 * The sentence for a page that could not ask, or null.
 *
 * Three of the five states answer null and two answer the same sentence, and the asymmetry is the
 * decision: `notRequested` and `empty` are silences that mislead nobody, while `unconfigured` and
 * `unavailable` are silences that would read as "this tree has nothing" if the page said nothing.
 *
 * **`unconfigured` and `unavailable` say the same thing to a reader and different things to an
 * operator.** `packLibrary.ts` refuses a default pack directory so that "not mounted" cannot look
 * like "mounted and empty", and the same discipline applies here to the two states that matter —
 * `empty` versus the rest. It does not extend to telling a reader which kind of misconfiguration
 * they are looking at: that difference is the operator's, it is on `communityState` and in the
 * `detail` the route logs, and putting it on a public page would be an internal error message in a
 * fact column.
 */
export function communityNote(input: TreePageInput): string | null {
  const half = communityOf(input);
  return half.state === 'unconfigured' || half.state === 'unavailable'
    ? W1Copy.communityUnavailable
    : null;
}

/**
 * §W1's `Data` row, under the web round's owner ruling 4: **state what the receipt records, say
 * less where it does not.**
 *
 * The mock's transcribed value is `ODbL · CSV / GeoJSON`, and it cannot be rendered. ODbL is the
 * license *contributors* grant at signup; v1 publishes no contributions, so claiming it over city
 * rows would assert a license over data this project does not hold the rights to license. The
 * ingest receipt carries San Jose's `CC-BY` and New York's Data Mine terms and carries **nothing
 * for San Francisco**, the largest and oldest source — so San Francisco's row is the emptiest one
 * on the page, which is the honest state and is why the note exists.
 *
 * The license string is reproduced **verbatim** from the receipt rather than shortened. New York's
 * reads `NYC Open Data / Data Mine terms; notification + verbatim disclaimer required`, and a
 * reader is owed the whole of it — an obligation summarized away is an obligation not discharged.
 */
export function terms(input: TreePageInput): TermsLine {
  const license = statedValue(input.inventoryLicense);
  if (license !== null) return { label: 'Data', value: license, note: null };
  return { label: 'Data', value: W1Copy.noLicenseRecorded, note: W1Copy.noLicenseNote };
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
    obligation: sourceObligation(input.idSpace),
    communityState: communityOf(input).state,
    communityNote: communityNote(input),
    documentTitle: city === null ? heading : `${heading} · ${city}`,
  };
  return { ...partial, description: description(input, partial) };
}
