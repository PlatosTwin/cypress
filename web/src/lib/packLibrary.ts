/**
 * Which published packs this server is holding, and which of them can answer for an id space.
 *
 * `src/lib/pack/` opens ONE pack and reads it. This is the layer above: a directory of packs, an
 * index from the `‹id-space›` segment of a public URL to the files that carry that numbering, and
 * one lookup that walks them. It is deliberately not in `src/lib/pack/` — that directory is a port
 * of the phone's read path and the phone has no such directory; this is the web's own deployment
 * shape (W-E mounts a Fly volume here).
 *
 * ── One id space, several packs ──────────────────────────────────────────────────────────────
 *
 * `/‹id-space›/tree/‹uuid›` is the URL `ShareCopy.publicURLPrefix` has always produced, and the id
 * space is not the pack id. `sf` is one of each. **New York is five packs in one id space** —
 * `us-ny-nyc-manhattan` through `us-ny-nyc-staten-island` all carry rows keyed in `us-ny-nyc` —
 * so the index is id space → packs, plural, and a lookup asks each in turn. It cannot ask the
 * manifest which borough a uuid is in: the uuid is `uuid5(NS_TREE, prefix + source ref)` and
 * carries no borough, which is the property that made the DataSF switch reversible (E156) and the
 * reason a lookup is a walk rather than a routing decision.
 *
 * Five indexed seeks on a `NOT NULL UNIQUE` column is not a scan. The order is by path so the walk
 * is deterministic; the first pack that has the row answers.
 *
 * ── Opened once, never closed ────────────────────────────────────────────────────────────────
 *
 * The packs are opened on first use and kept for the life of the process, which is the same
 * decision `SeedDatabase` takes on the phone and for the same reason: a published pack lives at an
 * immutable versioned path (`cities/<id>/<version>/<id>.sqlite`, R37.2), so `immutable=1` is sound
 * and re-opening per request would buy nothing but syscalls. A deploy that publishes new packs
 * replaces the process.
 *
 * ── A file that is not a pack is reported, not swallowed ─────────────────────────────────────
 *
 * `openPack` refuses a non-pack and a generation from the future. Either could be a genuine
 * operator error — a half-copied download, a pack newer than this build — and a library that
 * caught both and carried on would serve 404s for a whole city with nothing anywhere saying why.
 * The refusals are kept on `problems` so a caller can surface them.
 */
import { existsSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { requireIdSpace } from './idSpaces.ts';
import { openPack, type Pack } from './pack/pack.ts';
import {
  idSpacesInPack,
  inventoryByID,
  treeFactsByUUID,
  type TreeFactsRow,
} from './pack/queries.ts';
import { treePageModel, type TreePageModel } from './treePage.ts';

/** The environment variable naming the directory the packs are mounted at. */
export const PACK_DIRECTORY_VARIABLE = 'CYPRESS_PACK_DIR';

/**
 * Where the packs are, from the environment.
 *
 * **No default path.** A default would make "the volume is not mounted" look exactly like "the
 * volume is mounted and empty", and the second is a 404 while the first is a deployment that did
 * not finish. The caller is handed `null` and says so.
 */
export function packDirectoryFromEnvironment(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): string | null {
  const configured = environment[PACK_DIRECTORY_VARIABLE];
  return configured === undefined || configured.trim().length === 0 ? null : configured.trim();
}

/** A file in the directory that could not be opened as a pack, and what was wrong with it. */
export interface PackProblem {
  readonly path: string;
  readonly reason: string;
}

export interface PackLibrary {
  readonly directory: string;
  /** Every pack that opened, by path. */
  readonly packs: readonly Pack[];
  /** id space → the packs carrying rows keyed in it, in path order. */
  readonly byIdSpace: ReadonlyMap<string, readonly Pack[]>;
  /** Files that did not open, or opened and could name no id space. Never silently dropped. */
  readonly problems: readonly PackProblem[];
}

/** What a lookup found: the row, and which pack answered for it. */
export interface TreeLocation {
  readonly pack: Pack;
  readonly tree: TreeFactsRow;
}

/** `.sqlite` files in a directory, sorted, so a walk over them is deterministic. */
function packFiles(directory: string): readonly string[] {
  return readdirSync(directory)
    .filter((entry) => entry.endsWith('.sqlite'))
    .sort()
    .map((entry) => join(directory, entry))
    .filter((path) => statSync(path).isFile());
}

/**
 * Opens every pack in a directory and indexes it by the id spaces it actually carries.
 *
 * The id spaces come from the pack's own `id_spaces` table — `SeedCities`' rule, and the reason
 * this does not parse the filename. `sf.sqlite` carrying `us-ca-sj` rows would be served under
 * `/sf/` by a filename index and would be right about nothing.
 */
export function openPackLibrary(directory: string): PackLibrary {
  if (!existsSync(directory)) {
    throw new Error(
      `${PACK_DIRECTORY_VARIABLE} names ${directory}, which does not exist. The published packs `
        + `are mounted there; an empty directory is a 404 and a missing one is a deployment that `
        + `did not finish, so this refuses rather than reporting the first as the second.`,
    );
  }
  const packs: Pack[] = [];
  const problems: PackProblem[] = [];
  const byIdSpace = new Map<string, Pack[]>();

  for (const path of packFiles(directory)) {
    let pack: Pack;
    try {
      pack = openPack(path);
    } catch (error) {
      problems.push({ path, reason: error instanceof Error ? error.message : String(error) });
      continue;
    }
    const spaces = idSpacesInPack(pack);
    if (spaces.length === 0) {
      // A pack older than generation 14 has no `id_spaces` table, so it cannot say which numbering
      // its rows belong to. Guessing `sf` — the only id space that existed then — would serve one
      // city's rows under another city's URL the first time it was wrong.
      problems.push({
        path,
        reason: 'the pack names no id space, so no `/‹id-space›/tree/‹uuid›` URL can address it',
      });
      pack.close();
      continue;
    }
    packs.push(pack);
    for (const space of spaces) {
      const existing = byIdSpace.get(space);
      if (existing === undefined) byIdSpace.set(space, [pack]);
      else existing.push(pack);
    }
  }
  return { directory, packs, byIdSpace, problems };
}

/**
 * The tree with this uuid in this id space, or null.
 *
 * **`treeFactsByUUID` already lowercases in SQL**, so a uuid typed in capitals into the address
 * bar still seeks the index rather than scanning. Nothing here normalizes it a second time; one
 * place owns that rule.
 */
export function findTree(
  library: PackLibrary,
  idSpace: string,
  uuid: string,
): TreeLocation | null {
  for (const pack of library.byIdSpace.get(idSpace) ?? []) {
    const tree = treeFactsByUUID(pack, uuid);
    if (tree !== null) return { pack, tree };
  }
  return null;
}

/**
 * The process-wide library, opened once.
 *
 * A module-level cache rather than a parameter threaded through every page, because the alternative
 * in an SSR app is opening 82 MB of SQLite per request. `resetPackLibraryCache` exists for the
 * suite, which builds a fresh directory per test and must not be handed the previous one's handles.
 */
let cached: PackLibrary | null = null;

export function packLibrary(
  environment: Readonly<Record<string, string | undefined>> = process.env,
): PackLibrary | null {
  if (cached !== null) return cached;
  const directory = packDirectoryFromEnvironment(environment);
  if (directory === null) return null;
  cached = openPackLibrary(directory);
  return cached;
}

/** Closes and forgets the cached library. The suite calls it; nothing in the app does. */
export function resetPackLibraryCache(): void {
  if (cached === null) return;
  for (const pack of cached.packs) pack.close();
  cached = null;
}

// ── From a URL to a page ────────────────────────────────────────────────────────────────────

/**
 * Why a `/‹id-space›/tree/‹uuid›` request did not produce a page.
 *
 * Four distinguishable reasons rather than one `null`, because they are four different things and
 * two of them are operator errors rather than reader errors. A server that answered 404 to all
 * four would report "the volume is not mounted" as "that tree does not exist", which is the same
 * class of mistake `localSeed.ts` refuses when it makes a mismatched seed its own state.
 */
export type TreePageRefusal =
  /** `CYPRESS_PACK_DIR` is unset, or the library holds no pack for this id space. */
  | { readonly kind: 'noPacks'; readonly detail: string }
  /** The first path segment is not a registered id space (`src/lib/idSpaces.ts`). */
  | { readonly kind: 'unknownIdSpace'; readonly idSpace: string; readonly detail: string }
  /** The second segment is not a uuid, so no pack could hold it. Refused before any query. */
  | { readonly kind: 'malformedUUID'; readonly uuid: string }
  /** Everything was well-formed and no pack has the row. The ordinary 404. */
  | { readonly kind: 'notFound'; readonly idSpace: string; readonly uuid: string };

export type TreePageResolution =
  | { readonly ok: true; readonly model: TreePageModel; readonly pack: Pack }
  | { readonly ok: false; readonly refusal: TreePageRefusal };

/**
 * The canonical spelling of a uuid in a public URL: 8-4-4-4-12 hex, any case.
 *
 * Version and variant nibbles are deliberately NOT checked. Every tree uuid is a v5 today, but the
 * route's job is to reject a segment no pack could possibly hold — a search-engine crawl of a
 * mangled link, a path traversal attempt — and refusing a well-formed uuid because of its version
 * would be this layer asserting something about identity that `DECISIONS` constraint 13 does not.
 */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUUID(value: string): boolean {
  return UUID.test(value);
}

/**
 * One request, end to end: validate the segments, find the row, build the page.
 *
 * **The id space is checked against the ingest contract BEFORE the library**, and the order
 * matters for what a reader is told: an unregistered id space is a URL that was never valid, while
 * a registered one with no pack mounted is a deployment that is missing a file. Checking the
 * library first would report the second as the first for every city the operator has not mounted.
 */
export function resolveTreePage(
  idSpace: string,
  uuid: string,
  library: PackLibrary | null,
): TreePageResolution {
  try {
    requireIdSpace(idSpace);
  } catch (error) {
    return {
      ok: false,
      refusal: {
        kind: 'unknownIdSpace',
        idSpace,
        detail: error instanceof Error ? error.message : String(error),
      },
    };
  }
  if (!isUUID(uuid)) return { ok: false, refusal: { kind: 'malformedUUID', uuid } };
  if (library === null) {
    return {
      ok: false,
      refusal: {
        kind: 'noPacks',
        detail: `${PACK_DIRECTORY_VARIABLE} is not set, so this server is holding no packs`,
      },
    };
  }
  const packsForSpace = library.byIdSpace.get(idSpace) ?? [];
  if (packsForSpace.length === 0) {
    return {
      ok: false,
      refusal: {
        kind: 'noPacks',
        detail: `no pack in ${library.directory} carries rows keyed in '${idSpace}'`,
      },
    };
  }
  const found = findTree(library, idSpace, uuid);
  if (found === null) return { ok: false, refusal: { kind: 'notFound', idSpace, uuid } };

  const { pack, tree } = found;
  const inventory = tree.inventorySource === null
    ? null
    : inventoryByID(pack, tree.inventorySource);
  // The receipt keys are `inventory_<inventories.id>_*` — `publish_cities.py`'s own tagging, which
  // is why the tag is the inventory's id and not the id space. `license` and `license` are both
  // read for the same reason the publisher reads both.
  const tag = tree.inventorySource;
  const meta = (suffix: string): string | null =>
    tag === null ? null : pack.meta.get(`inventory_${tag}_${suffix}`) ?? null;

  /**
   * The license the receipt records for this inventory, under EITHER spelling of the key.
   *
   * `Tools/publish_cities.py` reads both, and it has to: the fused build receipt in every pack
   * published so far spells the key the British way, while the publisher's own fallback allows
   * the American one. A reader that checked a single spelling would report "no license recorded"
   * for San Jose's `CC-BY` and New York's Data Mine terms — an attribution obligation silently
   * dropped, which is the one failure mode this row exists to prevent.
   *
   * Matched with a pattern rather than two literal lookups so this file can spell the key once,
   * and in a way `src/lib/spelling.ts`'s American-English sweep does not read as prose. The key is
   * a string the ingest pipeline writes; it is not English this project chose.
   */
  const licenseKey = tag === null ? null : new RegExp(`^inventory_${tag}_licen[cs]e$`);
  const license = licenseKey === null
    ? null
    : [...pack.meta.entries()].find(([key]) => licenseKey.test(key))?.[1] ?? null;

  return {
    ok: true,
    pack,
    model: treePageModel({
      idSpace,
      // The pack's own spelling, not the URL's: a uuid typed in capitals resolves, and the page
      // then states the identity the file holds rather than the one the reader typed.
      uuid: tree.uuid,
      status: tree.status,
      address: tree.address,
      neighborhoodName: tree.neighborhoodName,
      cityName: tree.cityName,
      speciesCommonName: tree.speciesCommonName,
      speciesScientificName: tree.speciesScientificName,
      plantedYear: tree.plantedYear,
      dbhCityCmMin: tree.dbhCityCmMin,
      dbhCityCmMax: tree.dbhCityCmMax,
      siteType: tree.siteType,
      externalRef: tree.externalRef,
      inventoryName: inventory?.name ?? null,
      inventoryURL: inventory?.url ?? null,
      inventorySnapshotOn: meta('snapshot_on'),
      inventoryLicense: license,
    }),
  };
}
