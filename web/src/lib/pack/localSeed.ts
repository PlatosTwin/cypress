/**
 * The checked-out seed, and whether it is the one the repository pinned.
 *
 * `Fixtures/seed/cypress-seed.sqlite` is git-ignored and ~103 MB: `Tools/setup_worktree.sh` copies
 * it into a worktree, and **CI does not have it**. Two files beside it are tracked and therefore
 * everywhere — `Fixtures/seed/pinned-seed.json`, which states the expected size and sha256, and
 * `Fixtures/seed/schema.sql`, the generation-17 schema contract the web suite builds its fixtures
 * from. What this module answers is which of those two worlds a given run is in, and it answers it
 * as a **state**, never as a boolean.
 *
 * ## Why a state and not `existsSync`
 *
 * CLAUDE.md: "Never trust an artifact you did not watch being produced. Before reading a log,
 * screenshot, or build as evidence, check its mtime, its provenance … and its content." A seed
 * file that is present but is not the pinned one is the worse of the two failure modes and the one
 * a boolean cannot express: every assertion written against known row counts would go red, and the
 * reader would go looking for a defect in the read layer. So `mismatched` is its own state, it
 * carries both hashes, and the suite treats it as a **failure** rather than as a reason to skip.
 * Absent is a skip; wrong is a red. They are different facts and they send you to different
 * places.
 */
import { createHash } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

/** The repository root, from this module's own location: `pack` → `lib` → `src` → `web` → root. */
export const repositoryRoot = fileURLToPath(new URL('../../../../', import.meta.url));

/** `Fixtures/seed/cypress-seed.sqlite` — git-ignored, copied in by `Tools/setup_worktree.sh`. */
export const pinnedSeedPath = `${repositoryRoot}Fixtures/seed/cypress-seed.sqlite`;
/** `Fixtures/seed/pinned-seed.json` — tracked, so this one exists in CI. */
export const pinnedSeedManifestPath = `${repositoryRoot}Fixtures/seed/pinned-seed.json`;
/** `Fixtures/seed/schema.sql` — tracked. The generation-17 schema contract. */
export const seedSchemaContractPath = `${repositoryRoot}Fixtures/seed/schema.sql`;

/** What `pinned-seed.json` states about the seed the repository expects. */
export interface SeedPin {
  readonly bytes: number;
  readonly sha256: string;
  readonly treeCount: number;
  readonly schemaVersion: number;
  readonly buildId: string;
  readonly idSpaces: readonly string[];
}

/** Reads and validates `pinned-seed.json`. Throws rather than defaulting — a pin is not optional. */
export function readSeedPin(path: string = pinnedSeedManifestPath): SeedPin {
  const parsed: unknown = JSON.parse(readFileSync(path, 'utf8'));
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error(`${path} is not a JSON object`);
  }
  const source = parsed as Record<string, unknown>;
  const integer = (key: string): number => {
    const value = source[key];
    if (typeof value !== 'number' || !Number.isInteger(value)) {
      throw new Error(`${path} has no integer "${key}" (got ${JSON.stringify(value)})`);
    }
    return value;
  };
  const string = (key: string): string => {
    const value = source[key];
    if (typeof value !== 'string' || value.length === 0) {
      throw new Error(`${path} has no non-empty string "${key}"`);
    }
    return value;
  };
  const spaces = source['id_spaces'];
  if (!Array.isArray(spaces) || spaces.some((s) => typeof s !== 'string')) {
    throw new Error(`${path} has no "id_spaces" array of strings`);
  }
  return {
    bytes: integer('bytes'),
    sha256: string('sha256'),
    treeCount: integer('tree_count'),
    schemaVersion: integer('schema_version'),
    buildId: string('build_id'),
    idSpaces: spaces as readonly string[],
  };
}

export type SeedState =
  /** The file is there and its bytes hash to what the pin states. Safe to assert against. */
  | { readonly kind: 'present'; readonly path: string; readonly pin: SeedPin }
  /** No file. CI, and a worktree that has not run `Tools/setup_worktree.sh`. A skip, loudly. */
  | { readonly kind: 'absent'; readonly path: string; readonly pin: SeedPin }
  /** A file that is not the pinned one. **Never a skip** — see this module's note. */
  | {
      readonly kind: 'mismatched';
      readonly path: string;
      readonly pin: SeedPin;
      readonly detail: string;
    };

let cached: SeedState | undefined;

/**
 * Which of the three states this checkout is in, computed once per process.
 *
 * Memoized because the hash is over ~103 MB and the suite asks several times; the file cannot
 * change under a test run, and if it did, a run that read two different seeds would be worse than
 * one that read a stale answer.
 *
 * **Size is checked before the hash**, which is not an optimization: a size mismatch names the
 * problem in a way two hex strings do not.
 */
export function seedState(): SeedState {
  if (cached !== undefined) return cached;
  const pin = readSeedPin();
  let size: number;
  try {
    size = statSync(pinnedSeedPath).size;
  } catch {
    cached = { kind: 'absent', path: pinnedSeedPath, pin };
    return cached;
  }
  if (size !== pin.bytes) {
    cached = {
      kind: 'mismatched',
      path: pinnedSeedPath,
      pin,
      detail: `it is ${size} bytes and pinned-seed.json pins ${pin.bytes}`,
    };
    return cached;
  }
  const actual = createHash('sha256').update(readFileSync(pinnedSeedPath)).digest('hex');
  if (actual !== pin.sha256) {
    cached = {
      kind: 'mismatched',
      path: pinnedSeedPath,
      pin,
      detail: `its sha256 is ${actual} and pinned-seed.json pins ${pin.sha256}`,
    };
    return cached;
  }
  cached = { kind: 'present', path: pinnedSeedPath, pin };
  return cached;
}
