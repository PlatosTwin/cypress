/**
 * What shape a pack turned out to be, asked of the file rather than of a version integer.
 *
 * A port of `Cypress/Data/Store/SeedDatabase.swift`'s `SeedSchema`, and the port is deliberately
 * literal: the same flags, introspected from the same `PRAGMA`s, gated the same way. The phone's
 * argument for doing it this way is the one that matters here too and it is stronger on the web,
 * because the web opens one pack at a time from a bucket it does not control:
 *
 * > the read layer asks the file what it carries rather than trusting a version integer stamped
 * > somewhere else
 *
 * The version integer exists — `seed_meta.publish_schema_version` — and `pack.ts` reads it, for
 * exactly one purpose: refusing a generation from the future. It is never used to *infer* a shape,
 * because 16 → 17 is the only pure addition of the three recent generations and 15 → 16 dropped a
 * column (`id_spaces.short_name`). A reader that assumed "17 implies 15's shape" would be wrong
 * about the pack it is most likely to be handed.
 *
 * ## Two shapes of gate, and why both exist
 *
 * `hasSpeciesTrigrams`, `hasDimCity` are **table**-gated — the generation added a new table.
 * `hasCityRaw`, `hasInventorySource`, `hasCivicShortNames` are **column**-gated — the generation
 * added a column to a table that was already there. `hasIdSpace` and `hasRegions` are
 * **conjunctions**, all-or-nothing, because a column and the table it points at are one generation
 * and are meaningless apart: a `region_id` with no `dim_region` to join is an integer naming
 * nothing.
 *
 * `columnNames` of a table that does not exist answers empty rather than throwing, which is what
 * keeps `hasCivicShortNames` correct on a pre-v14 pack with no `id_spaces` table at all.
 */
import type { DatabaseSync } from 'node:sqlite';

/** The shape of one pack, as its own `sqlite_master` and `PRAGMA table_info` report it. */
export interface PackSchema {
  /** The column on `trees` holding the stable, citable UUID — `uuid`, or `id` in the original TEXT-PK shape. */
  readonly treeIdentityColumn: 'uuid' | 'id';
  /** Same, for `species`. */
  readonly speciesIdentityColumn: 'uuid' | 'id';
  /** The column on `trees` that `trees_rtree.id` equals — `id`, or `rt_id` in the original shape. */
  readonly rtreeJoinColumn: 'id' | 'rt_id';
  /** `trees.city_raw` — present but NULL in the shipped seed; nothing reads it. */
  readonly hasCityRaw: boolean;
  /** `trees.inventory_source` — which of a city's inventories listed each row. */
  readonly hasInventorySource: boolean;
  /** `trees.id_space` with `id_spaces` and `inventories` — generation 14, what made a second city representable. */
  readonly hasIdSpace: boolean;
  /** `species_trigrams` — generation 15, the typo-tolerant species index. */
  readonly hasSpeciesTrigrams: boolean;
  /** `id_spaces.short_name` — generation 15, and **dropped again at 16**. Not a floor. */
  readonly hasCivicShortNames: boolean;
  /** `dim_city` — generation 16, the city dimension table `id_spaces.city_id` joins through. */
  readonly hasDimCity: boolean;
  /** `dim_region` **and** `trees.region_id` — generation 17, the unit a pack is published in. */
  readonly hasRegions: boolean;
  /** Whether the identity model is the current INTEGER-PK one. */
  readonly usesIntegerPrimaryKeys: boolean;
}

/** Raised when a file is not a Cypress pack, before any query is built against it. */
export class PackContractError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PackContractError';
  }
}

/** The tables every generation of a Cypress pack has, and whose absence means it is not one. */
export const REQUIRED_TABLES: readonly string[] = ['trees', 'species', 'neighborhoods', 'trees_rtree'];

/**
 * The columns whose absence means the file is not a Cypress pack whatever else it holds.
 *
 * `SeedSchema.introspect`'s wording: "`lat` and `lon` are the load-bearing columns for every
 * spatial query and are the same in both shapes; their absence means this is not a Cypress seed
 * at all." `status` is checked with them for the same reason.
 */
export const REQUIRED_TREE_COLUMNS: readonly string[] = ['lat', 'lon', 'status'];

/** Whether a table or view of that name exists — `sqlite_master`, both types, as the phone asks it. */
export function tableExists(db: DatabaseSync, name: string): boolean {
  const row = db
    .prepare("SELECT 1 AS present FROM sqlite_master WHERE type IN ('table','view') AND name = ?")
    .get(name);
  return row !== undefined;
}

/**
 * The column names of a table, in declaration order. **Empty for a table that does not exist**,
 * which is load-bearing rather than incidental — see this module's note on `hasCivicShortNames`.
 */
export function columnNames(db: DatabaseSync, table: string): readonly string[] {
  const rows = db.prepare('SELECT name FROM pragma_table_info(?)').all(table);
  return rows.map((row) => String((row as Record<string, unknown>)['name']));
}

/** Asks the file what it carries. Throws `PackContractError` if it is not a Cypress pack. */
export function introspect(db: DatabaseSync): PackSchema {
  for (const table of REQUIRED_TABLES) {
    if (!tableExists(db, table)) {
      throw new PackContractError(
        `the pack has no table '${table}'; it is not a Cypress pack database`,
      );
    }
  }

  const treeColumns = new Set(columnNames(db, 'trees'));
  const speciesColumns = new Set(columnNames(db, 'species'));

  const missing = REQUIRED_TREE_COLUMNS.filter((column) => !treeColumns.has(column));
  if (missing.length > 0) {
    throw new PackContractError(
      `trees is missing ${missing.join(', ')}, so it matches neither known identity model; `
        + `it has [${[...treeColumns].join(', ')}]`,
    );
  }

  const treeIdentityColumn = treeColumns.has('uuid') ? 'uuid' : 'id';
  return {
    treeIdentityColumn,
    speciesIdentityColumn: speciesColumns.has('uuid') ? 'uuid' : 'id',
    rtreeJoinColumn: treeColumns.has('rt_id') ? 'rt_id' : 'id',
    hasCityRaw: treeColumns.has('city_raw'),
    hasInventorySource: treeColumns.has('inventory_source'),
    // All three together or none.
    hasIdSpace:
      treeColumns.has('id_space') && tableExists(db, 'id_spaces') && tableExists(db, 'inventories'),
    hasSpeciesTrigrams: tableExists(db, 'species_trigrams'),
    // Column-gated, and correct on a pack with no `id_spaces` table at all.
    hasCivicShortNames: columnNames(db, 'id_spaces').includes('short_name'),
    hasDimCity: tableExists(db, 'dim_city'),
    // Both together or none.
    hasRegions: treeColumns.has('region_id') && tableExists(db, 'dim_region'),
    usesIntegerPrimaryKeys: treeIdentityColumn === 'uuid',
  };
}
