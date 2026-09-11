/**
 * Opening a published city pack, read-only, through the same contract the phone applies.
 *
 * The phone's path is `CityLibrary.validateCityFile` → `SeedDatabase.attach`, and the validation
 * half is what this ports, in the same order and for the same reasons:
 *
 * 1. open **read-only and immutable** (`mode=ro&immutable=1`);
 * 2. `introspect` — the seed shape must be recognizable, or this is not a Cypress pack;
 * 3. the file's own `seed_meta.publish_schema_version` must not exceed what this build reads.
 *
 * > The manifest already claimed a generation, but the manifest is a rewritable object on a
 * > remote bucket; the file is what actually gets attached, so the file is what gets believed.
 *
 * That sentence is `CityLibrary`'s and it is the reason step 3 reads the file rather than the
 * manifest entry. `manifest.ts` decodes the catalog; nothing in this module consults it.
 *
 * ## What this layer deliberately does NOT do
 *
 * **It does not build `InventoryUnion`.** The phone attaches several packs at once into a `temp`
 * view with re-keyed species and composite ids, because one device holds several cities. One pack
 * at a time is what the web needs and the union's identity arithmetic (`armStride`, `inv`,
 * `local_id`) is entirely the union's business — a pack's own `trees.id` is a plain rowid alias
 * and `site_lineage` points inside the same file. Porting the union's id scheme to read one file
 * would import a hazard to solve a problem the web does not have. The day the web reads two packs
 * in one query, this paragraph is where that decision gets made.
 *
 * **It never writes.** Not a pragma, not a temp table, not an index. The open is `readOnly` *and*
 * `mode=ro`, so a write is refused by SQLite rather than by a promise in a comment — which is
 * `SeedDatabase`'s own argument for `immutable=1`, quoted: "makes that a property of the
 * connection rather than a promise in a comment".
 */
import { DatabaseSync } from 'node:sqlite';
import { pathToFileURL } from 'node:url';

import { introspect, tableExists, type PackSchema } from './seedSchema.ts';
import { NEWEST_KNOWN_PACK_SCHEMA_VERSION } from './versions.ts';

/** A pack whose generation this build does not read, refused before anything is queried. */
export class PackTooNewError extends Error {
  constructor(
    readonly fileVersion: number,
    readonly buildKnows: number,
  ) {
    // The phone's wording, pointed the same way: a generation from the future is refused before
    // ATTACH, never after.
    super(`pack is schema generation ${fileVersion} but this build knows up to ${buildKnows}`);
    this.name = 'PackTooNewError';
  }
}

/**
 * The `file:` URI a pack is opened through, with the read-only and immutable flags —
 * `SeedDatabase.readOnlyURI(for:)`.
 *
 * `pathToFileURL` percent-encodes, which is what SQLite's URI parser expects; a path containing a
 * space would otherwise truncate the filename. Verified on Node 24.13.1 that these parameters are
 * genuinely parsed rather than swallowed as part of the filename: `?mode=bogus` is refused with
 * `no such access mode: bogus`, and the same text appended to a bare path (no `file:` scheme) is
 * refused with `unable to open database file`. Without that calibration, a URI that SQLite ignored
 * would look identical to one it honored.
 */
export function readOnlyURI(path: string, options: { immutable?: boolean } = {}): string {
  const immutable = options.immutable ?? true;
  return `${pathToFileURL(path).href}?mode=ro${immutable ? '&immutable=1' : ''}`;
}

export interface OpenPackOptions {
  /**
   * `immutable=1` — no locking, no `-wal`/`-shm` sidecars, no attempt to create either.
   *
   * True by default, matching the phone, and sound for the same reason: a published pack lives at
   * an immutable versioned path (`cities/<id>/<version>/<id>.sqlite`, R37.2), so a pack file
   * genuinely cannot change under a reader. **Pass false for a pack that can be rewritten in
   * place** — a staging directory, a fixture a test is editing — where the flag would let SQLite
   * serve reads from a file that moved underneath it.
   */
  readonly immutable?: boolean;
}

/**
 * One opened pack: its shape, its metadata, and the connection the query module reads through.
 *
 * `close()` is the caller's to call. Deliberately not a `FinalizationRegistry` or an `using`
 * declaration — a handle whose lifetime is implicit is a handle nobody can reason about in a
 * server, and `using` needs emit, which `erasableSyntaxOnly` forbids in this checkout.
 */
export interface Pack {
  readonly db: DatabaseSync;
  readonly path: string;
  readonly schema: PackSchema;
  /**
   * The generation the file states about itself, from `seed_meta.publish_schema_version`.
   *
   * **0 means the file does not say**, which is an answer and not an error: `publish_cities.py`
   * has always written the key, so a pack without it is either a pre-publisher bundled seed or
   * something that is not a published pack at all. The phone's wording for 0 is "an ancient file,
   * attachable, just never preferable". Do not read this to infer a shape — that is
   * `schema`'s job; read it only to know what the file claims.
   */
  readonly statedSchemaVersion: number;
  /** Every `seed_meta` row, as written. Empty when the pack has no `seed_meta` table. */
  readonly meta: ReadonlyMap<string, string>;
  close(): void;
}

/**
 * Opens a pack read-only and makes it testify for itself.
 *
 * Throws `PackContractError` for a file that is not a Cypress pack, `PackTooNewError` for a
 * generation this build does not read, and whatever `node:sqlite` throws for a file that is not a
 * database at all. The connection is closed before any of those leave this function — a refused
 * open must not leak a handle, and a caller that catches the error has no `Pack` to close.
 */
export function openPack(path: string, options: OpenPackOptions = {}): Pack {
  const db = new DatabaseSync(readOnlyURI(path, options), { readOnly: true });
  try {
    const schema = introspect(db);
    const meta = readMeta(db);
    // Absent reads as generation 0. `??` and not `||`: a literal "0" in the file is the same
    // answer as an absent key, and both are legitimate, but conflating them through falsiness is
    // how a `0` that meant something becomes a `0` that meant nothing.
    const stated = Number(meta.get('publish_schema_version') ?? '0');
    const statedSchemaVersion = Number.isInteger(stated) ? stated : 0;
    if (statedSchemaVersion > NEWEST_KNOWN_PACK_SCHEMA_VERSION) {
      throw new PackTooNewError(statedSchemaVersion, NEWEST_KNOWN_PACK_SCHEMA_VERSION);
    }
    return {
      db,
      path,
      schema,
      statedSchemaVersion,
      meta,
      close: () => db.close(),
    };
  } catch (error) {
    db.close();
    throw error;
  }
}

/**
 * Every `seed_meta` row.
 *
 * Guarded on the table's existence rather than on a try/catch: `seed_meta` is optional in an old
 * bundled seed and never absent from a published pack, so its absence is a shape to report, not an
 * exception to swallow. A bare catch here would also swallow a genuinely corrupt file.
 */
function readMeta(db: DatabaseSync): ReadonlyMap<string, string> {
  if (!tableExists(db, 'seed_meta')) return new Map();
  const rows = db.prepare('SELECT key, value FROM seed_meta').all();
  const meta = new Map<string, string>();
  for (const row of rows) {
    const record = row as Record<string, unknown>;
    meta.set(String(record['key']), String(record['value']));
  }
  return meta;
}
