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

import { openPack, type Pack } from './pack/pack.ts';
import { idSpacesInPack, treeFactsByUUID, type TreeFactsRow } from './pack/queries.ts';

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
