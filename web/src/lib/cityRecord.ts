/**
 * How the city's own record is said out loud — ported from the iOS app, not authored here.
 *
 * W1's fact column is about half contributed data (`docs/ROADMAP.md` §W, "Corrected 2026-09-10"),
 * and v1 has no public read for that half. What is left is exactly the set of facts the phone
 * already draws on a **cold** tree profile — screen 14, the tree nobody has visited — and every one
 * of those already has a label, a format and a documented reason for both, in
 * `Cypress/Features/TreeProfile/CityRecordPresentation.swift` and
 * `Cypress/Features/TreeProfile/TreeProfilePresentation.swift`.
 *
 * **So none of this copy is new.** Authoring a second vocabulary for the same columns is how the
 * vitality rubric forked for two weeks (ticket #261), and the copy here is load-bearing in a way a
 * label usually is not: `Cared for by` rather than `Caretaker` is a ruling about what 163,955 rows
 * are allowed to imply (E143), and the DBH bucket's badge exists so a published range cannot be
 * read as a reading somebody taped (D7). A web page that re-words either would be re-litigating a
 * decision by retyping it.
 *
 * `web/test/cityRecord.test.ts` parses all three Swift files at run time and fails when this file
 * and they disagree.
 *
 * ── The one thing that is NOT claimed to match iOS ───────────────────────────────────────────
 *
 * The provenance sentence's **date**. The phone formats it with `DateFormatter` under a
 * `yMMMMd` template; this formats with `Intl.DateTimeFormat`. Those are two implementations of
 * CLDR and they agree today for `en-US`, but nothing here proves it and the test does not claim
 * it: what is ported is the SENTENCE — `From the <source>, <day>.` — and the rule that an absent
 * snapshot removes the whole sentence rather than producing a dateless one.
 */

// ── Lifecycle status ────────────────────────────────────────────────────────────────────────

/** `trees.status` — the seed's lifecycle vocabulary, verbatim (`Fixtures/seed/schema.sql`). */
export const treeStatuses = ['alive', 'declining', 'dead_reported', 'removed', 'vacant_site'] as const;
export type TreeStatus = (typeof treeStatuses)[number];

/**
 * The five labels screen 05's `Status` control draws, verbatim
 * (`Cypress/DesignSystem/Components/SegmentedControl.swift`).
 *
 * **This is the row W1 draws as `Thriving · vitality 4`, and it is a different fact.** Vitality is
 * a five-class rubric a person rates in the field and it lives in the writable database; the pack
 * carries the lifecycle enum, which is what the city's inventory says the record IS. The label
 * stays `Status` because that is what the app calls this column too — the value is the one that
 * changes, and no vitality is shown because none is public.
 */
const statusLabels: Readonly<Record<TreeStatus, string>> = {
  alive: 'Alive',
  declining: 'Declining',
  dead_reported: 'Appears dead',
  removed: 'Removed?',
  vacant_site: 'Vacant site',
};

/**
 * The label, or null for a status this build does not know.
 *
 * Null rather than the raw value: the `CHECK` constraint in the seed contract closes this
 * vocabulary, so an unrecognized status means the pack is from a future this build cannot read,
 * and printing `dead_standing` at a reader is worse than printing nothing. The page renders the
 * absence the same way it renders every other fact the record does not carry.
 */
export function statusLabel(status: string): string | null {
  return Object.hasOwn(statusLabels, status) ? statusLabels[status as TreeStatus] : null;
}

// ── Values the city wrote, and the ones it only appears to have written ─────────────────────

/**
 * What a data-entry form writes when nobody answered, case-folded.
 * `CityRecordCopy.noValueMarkers`, verbatim.
 *
 * The Swift's own warning travels with it: **this set must never grow a value that could be
 * somebody's real answer.**
 */
export const noValueMarkers: ReadonlySet<string> = new Set([
  'n/a', 'n.a.', 'na', 'none', 'null', 'nil', 'unassigned', 'unknown', 'tbd',
  'not applicable', 'not available', 'not recorded', 'no data',
]);

/**
 * The city's value, or null when the column is populated with a non-value —
 * `CityRecordPresentation.statedValue`.
 *
 * Three gates, and the middle one is the one a re-implementation drops: a string with no letter
 * and no digit is not a value. San Francisco writes a bare `:` into `site_type` on real rows, and
 * without that gate the page draws a card claiming the city recorded a placement of `:`.
 */
export function statedValue(raw: string | null | undefined): string | null {
  if (raw === null || raw === undefined) return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  if (![...trimmed].some((character) => /[\p{L}\p{N}]/u.test(character))) return null;
  if (noValueMarkers.has(trimmed.toLowerCase())) return null;
  return trimmed;
}

// ── The city's published DBH bucket ─────────────────────────────────────────────────────────

/**
 * `65–70 cm`. An en dash and no spaces — `TreeProfilePresentation.cityDBHRangeText`, verbatim.
 *
 * **The upper bound is EXCLUSIVE**, mirroring the Postgres `[)` the seed was built from and
 * `Tree.dbhCityCmRange`'s `IntRange`. A bucket one unit wide therefore prints as a single number:
 * `5–6 cm` would be claiming a range the city did not publish.
 *
 * It is deliberately NOT a `Quantity` (`src/lib/quantity.ts`). D7 makes method mandatory on every
 * numeric observation, and a published bucket has no method: nobody taped it, nobody estimated it,
 * it is a band the city's own form offered. Constructing a `Quantity` for it would mean choosing a
 * `MeasurementMethod` that the record does not state, and every downstream chart and badge would
 * then believe it. The phone keeps the same separation — `.cityRecord(String)` is its own case
 * beside `.quantity(Quantity)` — and E63 records that it stays inert for this reason.
 */
export function cityDBHRangeText(
  lowerBound: number | null,
  upperBoundExclusive: number | null,
): string | null {
  if (lowerBound === null || upperBoundExclusive === null) return null;
  if (!Number.isFinite(lowerBound) || !Number.isFinite(upperBoundExclusive)) return null;
  if (upperBoundExclusive - lowerBound <= 1) return `${lowerBound} cm`;
  return `${lowerBound}–${upperBoundExclusive} cm`;
}

/** The badge beside it. `MethodBadge.Kind.cityRecord`'s own text, verbatim. */
export const cityRecordBadge = 'city record';

// ── Identity and provenance ─────────────────────────────────────────────────────────────────

/**
 * `#13284` — the publishing inventory's own id, which is the citable city record
 * (BUILD-PLAN §7, RULINGS R18). `CityRecordCopy.recordNumber`.
 *
 * No `SF ` prefix: R28 removed it because it named the wrong city on 52,788 San Jose rows, and it
 * must not come back on a surface that serves seven packs.
 */
export function recordNumber(externalRef: string): string {
  return `#${externalRef}`;
}

/**
 * `From the SF Public Works street tree inventory, July 20, 2026.` —
 * `CityRecordCopy.provenanceNote`.
 *
 * The last line of the section and the one that makes every line above it checkable. The date is
 * the SOURCE's, never today's; an absent snapshot removes the sentence rather than producing a
 * dateless one, which is why this returns null instead of a partial string.
 */
export function provenanceNote(source: string, snapshotDay: string | null): string | null {
  if (snapshotDay === null || snapshotDay.length === 0) return null;
  return `From the ${source}, ${snapshotDay}.`;
}

/**
 * `2026-08-22` → `August 22, 2026`.
 *
 * The receipt writes a bare `YYYY-MM-DD` and nothing else — `InventorySource`'s own decoder is
 * "deliberately strict and deliberately not `ISO8601DateFormatter`" for that reason, and this is
 * strict for the same one. **Parsed as UTC and formatted in UTC**: `new Date('2026-08-22')` is
 * already midnight UTC, and formatting it in the server's local zone would render the day before
 * anywhere west of Greenwich. A string that is not a bare date returns null, and the sentence that
 * would have carried it is then absent.
 */
export function snapshotDay(raw: string | null | undefined): string | null {
  if (raw === null || raw === undefined) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw.trim());
  if (match === null) return null;
  const timestamp = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return null;
  // Round-tripped, so `2026-02-31` is refused rather than silently rendered as 3 March.
  if (date.toISOString().slice(0, 10) !== raw.trim()) return null;
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC',
  }).format(date);
}
