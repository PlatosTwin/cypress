/**
 * The published city catalog, decoded — a port of `Cypress/Data/Cities/CityManifest.swift`.
 *
 * The contract is R37's: versioned per-city SQLite packs at immutable paths
 * `cities/<id>/<version>/<id>.sqlite`, described by one catalog object that is the only thing ever
 * rewritten in place. `Tools/publish_cities.py` writes it; this is a second reader of it.
 *
 * **Strict about the one thing that can break a reader — `manifest_format` — and tolerant of
 * everything additive**, because R37.4 explicitly reserves the right to add keys without bumping
 * the format. Concretely: an unknown format is refused outright, an unknown *key* is ignored, and
 * an unknown `region.level` is carried through as the string it is rather than rejected. That last
 * one is `CityManifest.Region.level`'s own decision, and its reasoning transfers exactly: an
 * exhaustive enum would turn an additive value into a decode failure that takes the whole catalog
 * offline.
 *
 * ## Two deliberate differences from the Swift, both stated rather than absorbed
 *
 * **1. The format is checked before the cities are decoded.** `CityManifest.decode` decodes the
 * whole `Envelope` — cities included — and *then* checks `knownFormats`, so a future format whose
 * city shape changed would surface as `malformed` rather than `unknownFormat`, despite that
 * method's own comment saying it refuses "unknown formats before looking at anything else". This
 * port does what that comment says. The difference is only visible for a format this build does
 * not read, where refusing is the outcome either way and the *message* is the thing that differs —
 * and "manifest_format 3, this build reads 1, 2" sends a reader somewhere useful, where a JSON
 * type error does not.
 *
 * **2. `base_url_hint` is not surfaced, and that is R37.4's rule rather than a simplification.**
 * A pack path is resolved against the reader's *configured* base URL, never against a field the
 * catalog supplies about itself — a remote object that can redirect its own reader is a different
 * security property from one that cannot. It is not parsed here at all, so nothing can read it by
 * accident. `generated_at` and `source_seed` are left out for the plainer reason that nothing
 * needs them yet.
 */
import { KNOWN_MANIFEST_FORMATS } from './versions.ts';

/** The catalog says a format this build does not read. Refused outright — never guessed at. */
export class UnknownManifestFormatError extends Error {
  /** The format the catalog claimed. */
  readonly format: number;

  constructor(format: number) {
    const known = [...KNOWN_MANIFEST_FORMATS].sort((a, b) => a - b).join(', ');
    super(`manifest_format ${format}, but this build reads format(s) ${known}`);
    this.name = 'UnknownManifestFormatError';
    this.format = format;
  }
}

/** The catalog is not shaped like a catalog. */
export class MalformedManifestError extends Error {
  constructor(detail: string) {
    super(`manifest did not decode: ${detail}`);
    this.name = 'MalformedManifestError';
  }
}

export interface BoundingBox {
  readonly minLatitude: number;
  readonly maxLatitude: number;
  readonly minLongitude: number;
  readonly maxLongitude: number;
}

export interface Coordinate {
  readonly latitude: number;
  readonly longitude: number;
}

/**
 * What kind of unit one pack is, and which city it belongs to. `manifest_format` 2 only.
 *
 * Absent from a format-1 catalog, where **nil is the answer rather than a gap**: every format-1
 * catalog ever published listed whole cities, so "no region stated" and "this is a whole city" are
 * the same fact, and that set is closed now that format 1 is retired.
 */
export interface Region {
  /**
   * `city`, `borough`, or `extent` — **a string, deliberately not a union type**. This is the
   * publisher's vocabulary and it may gain a member without a format bump.
   */
  readonly level: string;
  /** The id space of the city this pack belongs to (`sf`, `us-ny-nyc`). */
  readonly parentCity: string;
  /** The parent city's reader-facing name — a civic fact entered at publish, never derived. */
  readonly parentCityDisplayName: string;
}

/** One published pack, as the catalog describes it. */
export interface ManifestCity {
  /** The pack id — the path component and the install key. Under format 2 a borough may have its own. */
  readonly id: string;
  /** A civic fact entered by hand at publish, never derived (DECISIONS constraint 15). */
  readonly displayName: string;
  /** `"full"`, or the shipped extent's name (San Jose ships `"downtown"`). */
  readonly coverage: string;
  readonly treeCount: number;
  /** The pack generation — compared against `NEWEST_KNOWN_PACK_SCHEMA_VERSION`. */
  readonly schemaVersion: number;
  /**
   * `s<schema_version>-r<content_rev>-<build_id>`.
   *
   * **Read as an opaque string — update detection is equality, and nothing here parses it.** That
   * is the property to preserve: the day something splits this on `-`, a publisher change becomes
   * a client bug.
   */
  readonly version: string;
  /** The record date, carried as its own key so nothing has to parse `version` to get it. */
  readonly contentRev: string | null;
  readonly bbox: BoundingBox | null;
  readonly centroid: Coordinate | null;
  readonly region: Region | null;
  /** Relative to the reader's *configured* base URL, never to `base_url_hint`. */
  readonly path: string;
  readonly bytes: number;
  /** Lowercase hex sha256 of the file at `path`; verified before a byte of it is kept. */
  readonly sha256: string;
}

export interface Manifest {
  readonly format: number;
  /** Packs in catalog order — the publisher's order is the display order (R43 §2). */
  readonly cities: readonly ManifestCity[];
}

function asObject(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new MalformedManifestError(`${what} is not an object`);
  }
  return value as Record<string, unknown>;
}

function requireString(source: Record<string, unknown>, key: string, what: string): string {
  const value = source[key];
  if (typeof value !== 'string') {
    throw new MalformedManifestError(`${what} has no string "${key}" (got ${typeof value})`);
  }
  return value;
}

/**
 * A required whole number.
 *
 * `Number.isInteger` rather than `typeof === 'number'`: `tree_count` and `bytes` are counts, and a
 * `NaN`, an `Infinity` or a `1.5` passing for one of them is exactly the kind of value that
 * survives into arithmetic and surfaces somewhere unrelated.
 */
function requireInteger(source: Record<string, unknown>, key: string, what: string): number {
  const value = source[key];
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new MalformedManifestError(
      `${what} has no integer "${key}" (got ${JSON.stringify(value)})`,
    );
  }
  return value;
}

function optionalString(source: Record<string, unknown>, key: string): string | null {
  const value = source[key];
  return typeof value === 'string' ? value : null;
}

function requireFinite(source: Record<string, unknown>, key: string, what: string): number {
  const value = source[key];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new MalformedManifestError(
      `${what} has no finite number "${key}" (got ${JSON.stringify(value)})`,
    );
  }
  return value;
}

function decodeBoundingBox(value: unknown, what: string): BoundingBox | null {
  if (value === undefined || value === null) return null;
  const source = asObject(value, what);
  return {
    minLatitude: requireFinite(source, 'min_lat', what),
    maxLatitude: requireFinite(source, 'max_lat', what),
    minLongitude: requireFinite(source, 'min_lon', what),
    maxLongitude: requireFinite(source, 'max_lon', what),
  };
}

function decodeCentroid(value: unknown, what: string): Coordinate | null {
  if (value === undefined || value === null) return null;
  const source = asObject(value, what);
  return { latitude: requireFinite(source, 'lat', what), longitude: requireFinite(source, 'lon', what) };
}

function decodeRegion(value: unknown, what: string): Region | null {
  if (value === undefined || value === null) return null;
  const source = asObject(value, what);
  return {
    level: requireString(source, 'level', what),
    parentCity: requireString(source, 'parent_city', what),
    parentCityDisplayName: requireString(source, 'parent_city_display_name', what),
  };
}

function decodeCity(value: unknown, index: number): ManifestCity {
  const what = `cities[${index}]`;
  const source = asObject(value, what);
  const id = requireString(source, 'id', what);
  const named = `cities[${index}] (${id})`;
  return {
    id,
    displayName: requireString(source, 'display_name', named),
    coverage: requireString(source, 'coverage', named),
    treeCount: requireInteger(source, 'tree_count', named),
    schemaVersion: requireInteger(source, 'schema_version', named),
    version: requireString(source, 'version', named),
    contentRev: optionalString(source, 'content_rev'),
    bbox: decodeBoundingBox(source['bbox'], `${named}.bbox`),
    centroid: decodeCentroid(source['centroid'], `${named}.centroid`),
    region: decodeRegion(source['region'], `${named}.region`),
    path: requireString(source, 'path', named),
    bytes: requireInteger(source, 'bytes', named),
    sha256: requireString(source, 'sha256', named),
  };
}

/**
 * Decodes a catalog's bytes — either published object — refusing unknown formats before looking at
 * anything else.
 *
 * Takes text rather than a URL: nothing here fetches. A module that reaches the network to be
 * tested is a module whose test needs a network.
 */
export function decodeManifest(text: string): Manifest {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    throw new MalformedManifestError(error instanceof Error ? error.message : String(error));
  }
  const envelope = asObject(parsed, 'the manifest');

  // The format, first, before a single city is looked at.
  const format = envelope['manifest_format'];
  if (typeof format !== 'number' || !Number.isInteger(format)) {
    throw new MalformedManifestError(
      `the manifest has no integer "manifest_format" (got ${JSON.stringify(format)}), so there is `
        + 'no way to know what the rest of it means',
    );
  }
  if (!KNOWN_MANIFEST_FORMATS.has(format)) throw new UnknownManifestFormatError(format);

  const cities = envelope['cities'];
  if (!Array.isArray(cities)) {
    throw new MalformedManifestError(`the manifest has no "cities" array (got ${typeof cities})`);
  }
  return { format, cities: cities.map(decodeCity) };
}
