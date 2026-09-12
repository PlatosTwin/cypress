/**
 * Reads over one opened pack, built from that pack's own introspected shape.
 *
 * Every statement here is assembled from a `PackSchema` rather than written against one
 * generation, for the reason `TreeQueries` gives at length: the identity columns, the joins and
 * the city-name projection each differ by generation, and a query written for the newest one
 * throws `no such column` on a pack that is a generation behind — which is not a hypothetical,
 * because the bundled seed and a downloaded pack are routinely two different generations at once
 * (R37.3). Measured here: the checked-in pinned seed is generation 16 and every pack in the live
 * catalog is 17.
 *
 * **Values are bound, never interpolated. Identifiers come from the introspected schema, never
 * from a caller.** `PackSchema`'s columns are a closed set of literals chosen by `introspect`
 * (`uuid`/`id`, `rt_id`/`id`), so the SQL below is assembled from a fixed vocabulary; the only
 * caller-supplied things that reach a statement are parameters.
 */
import type { Pack } from './pack.ts';
import type { PackSchema } from './seedSchema.ts';

export interface TreeBounds {
  readonly minLatitude: number;
  readonly maxLatitude: number;
  readonly minLongitude: number;
  readonly maxLongitude: number;
}

/** One tree, as a pack states it. A subset of the phone's `TreeRecord`, shaped for a read surface. */
export interface TreeRow {
  /** The stable, citable identity (DECISIONS constraint 13). Lowercase, as the files store it. */
  readonly uuid: string;
  readonly latitude: number;
  readonly longitude: number;
  readonly status: string;
  readonly address: string | null;
  readonly speciesScientificName: string | null;
  readonly speciesCommonName: string | null;
  readonly neighborhoodName: string | null;
  /**
   * The tree's own city, resolved through the same three-step fallback the phone uses, or null
   * when the pack is old enough not to say. **Never fabricated** — a pack that does not carry a
   * civic name yields null rather than a guess (DECISIONS constraint 15).
   */
  readonly cityName: string | null;
}

/**
 * The city-name projection, and the joins that make the aliases it reads exist.
 *
 * A literal port of `TreeQueries.treeSQL(matching:)`, including the part that is easy to get wrong:
 * **each source is gated on the flag that says the column exists AND on `hasIdSpace`, never on the
 * name flag alone.** The `isp` alias only enters the query when `hasIdSpace`, and `dc` is joined
 * *through* `isp`, so projecting `isp.short_name` on `hasCivicShortNames` alone throws `no such
 * column: isp.short_name` at prepare time — a naming collision with a table that was never joined,
 * not a null result. The phone has a fixture that reproduces exactly that, and so does this port's
 * test.
 *
 * 1. `dc.display_name` when `hasDimCity && hasIdSpace` (generation 16);
 * 2. `isp.short_name` when (1) did not resolve and `hasCivicShortNames && hasIdSpace` (15);
 * 3. `NULL` otherwise.
 */
function cityNameSource(schema: PackSchema): { joins: string; projection: string } {
  const idSpaceJoin = schema.hasIdSpace ? 'LEFT JOIN id_spaces isp ON isp.id = t.id_space' : '';
  const resolvableDimCityName = schema.hasDimCity && schema.hasIdSpace;
  const dimCityJoin = resolvableDimCityName ? 'LEFT JOIN dim_city dc ON dc.id = isp.city_id' : '';
  const resolvableShortName =
    !resolvableDimCityName && schema.hasCivicShortNames && schema.hasIdSpace;

  let projection = 'NULL';
  if (resolvableDimCityName) projection = 'dc.display_name';
  else if (resolvableShortName) projection = 'isp.short_name';

  return { joins: `${idSpaceJoin}\n  ${dimCityJoin}`, projection };
}

/**
 * The soft-delete predicate, applied whenever the column exists.
 *
 * **A deliberate, narrow divergence from the phone, stated rather than absorbed.** `TreeQueries`
 * applies `deleted_at IS NULL` only when the file actually holds a soft-deleted row, and that is
 * an index decision, not a correctness one: `deleted_at` is not in `idx_trees_lat_lon`, so the
 * clause costs the map its covering index on a path measured in tens of milliseconds per frame.
 * Applying it unconditionally is a strict superset of the phone's behavior — identical results on
 * every pack, including the ones where the phone omits it — and this layer has no 60 fps map to
 * pay for. Measured on the pinned seed: zero rows have a non-null `deleted_at`, so on today's data
 * the two spellings return the same rows and differ only in plan.
 */
function softDeletePredicate(schema: PackSchema, columns: ReadonlySet<string>): string {
  void schema;
  return columns.has('deleted_at') ? 'AND t.deleted_at IS NULL' : '';
}

function treeProjection(schema: PackSchema, cityProjection: string): string {
  return [
    `t.${schema.treeIdentityColumn} AS uuid`,
    't.lat AS lat',
    't.lon AS lon',
    't.status AS status',
    't.address AS address',
    's.scientific_name AS species_scientific_name',
    's.common_name AS species_common_name',
    'n.name AS neighborhood_name',
    `${cityProjection} AS city_name`,
  ].join(',\n         ');
}

function decodeTreeRow(row: unknown): TreeRow {
  const record = row as Record<string, unknown>;
  const text = (key: string): string | null => {
    const value = record[key];
    return value === null || value === undefined ? null : String(value);
  };
  return {
    uuid: String(record['uuid']),
    latitude: Number(record['lat']),
    longitude: Number(record['lon']),
    status: String(record['status']),
    address: text('address'),
    speciesScientificName: text('species_scientific_name'),
    speciesCommonName: text('species_common_name'),
    neighborhoodName: text('neighborhood_name'),
    cityName: text('city_name'),
  };
}

function treeColumnSet(pack: Pack): ReadonlySet<string> {
  const rows = pack.db.prepare('SELECT name FROM pragma_table_info(?)').all('trees');
  return new Set(rows.map((row) => String((row as Record<string, unknown>)['name'])));
}

/**
 * One tree by its citable uuid, or null.
 *
 * `lower(?)` in the SQL, not at the binding site, and this is the one detail worth copying
 * verbatim: `trees.uuid` is `NOT NULL UNIQUE`, so its index is **BINARY**, and a `COLLATE NOCASE`
 * comparison cannot seek it whichever operand carries the collation — the plan degrades to a bare
 * `SCAN t`, which on the pinned seed is 198,625 rows walked to fetch one tree. A constant
 * `lower(?)` keeps the seek. Sound because every pack stores its uuids lowercase.
 */
export function treeByUUID(pack: Pack, uuid: string): TreeRow | null {
  const { joins, projection } = cityNameSource(pack.schema);
  const sql = `
    SELECT ${treeProjection(pack.schema, projection)}
      FROM trees t
      LEFT JOIN species s ON s.id = t.species_current
      LEFT JOIN neighborhoods n ON n.id = t.neighborhood_id
      ${joins}
     WHERE t.${pack.schema.treeIdentityColumn} = lower(?)
       ${softDeletePredicate(pack.schema, treeColumnSet(pack))}
     LIMIT 1
  `;
  const row = pack.db.prepare(sql).get(uuid);
  return row === undefined ? null : decodeTreeRow(row);
}

/**
 * Trees inside a bounding box, through the R*Tree pre-filter.
 *
 * The R*Tree is a **conservative** pre-filter — it answers in bounding boxes, so `lat`/`lon` are
 * re-tested on the table afterwards, exactly as `TreeQueries.bboxSource(.rtreePrefilter)` does.
 * The join is `t.<rtreeJoinColumn> = r.id`, which is the identity `SeedSchema.rtreeJoinColumn`
 * exists to name: an `INTEGER PRIMARY KEY` is a rowid alias and stable across `VACUUM`, but the
 * original TEXT-PK shape made the implicit rowid unstable and carried `rt_id` instead.
 *
 * `limit` is mandatory. A read surface that can be asked for 298,839 rows by a query string has a
 * denial-of-service in it, and a default nobody chose is how that ships.
 */
export function treesInBounds(pack: Pack, bounds: TreeBounds, limit: number): readonly TreeRow[] {
  if (!Number.isInteger(limit) || limit <= 0) {
    throw new RangeError(`limit must be a positive integer, got ${JSON.stringify(limit)}`);
  }
  const { joins, projection } = cityNameSource(pack.schema);
  const sql = `
    SELECT ${treeProjection(pack.schema, projection)}
      FROM trees_rtree r
      JOIN trees t ON t.${pack.schema.rtreeJoinColumn} = r.id
      LEFT JOIN species s ON s.id = t.species_current
      LEFT JOIN neighborhoods n ON n.id = t.neighborhood_id
      ${joins}
     WHERE r.max_lat >= ? AND r.min_lat <= ?
       AND r.max_lon >= ? AND r.min_lon <= ?
       AND t.lat BETWEEN ? AND ?
       AND t.lon BETWEEN ? AND ?
       ${softDeletePredicate(pack.schema, treeColumnSet(pack))}
     ORDER BY t.${pack.schema.treeIdentityColumn}
     LIMIT ?
  `;
  const rows = pack.db
    .prepare(sql)
    .all(
      bounds.minLatitude,
      bounds.maxLatitude,
      bounds.minLongitude,
      bounds.maxLongitude,
      bounds.minLatitude,
      bounds.maxLatitude,
      bounds.minLongitude,
      bounds.maxLongitude,
      limit,
    );
  return rows.map(decodeTreeRow);
}

/** How many live trees a pack holds. Soft-deleted rows are excluded, as everywhere else here. */
export function treeCount(pack: Pack): number {
  const predicate = softDeletePredicate(pack.schema, treeColumnSet(pack));
  const row = pack.db.prepare(`SELECT COUNT(*) AS n FROM trees t WHERE 1 ${predicate}`).get();
  return Number((row as Record<string, unknown>)['n']);
}

/**
 * What a pack says it is: its published unit and the city that unit belongs to.
 *
 * Read from the **file**, never from a manifest entry, on `CityLibrary.validateCityFile`'s
 * reasoning — the manifest is a rewritable object on a remote bucket and the file is what gets
 * opened. Every field is optional because every one of them arrived in a different generation:
 * `dim_region` at 17, `dim_city` at 16, and a pre-16 pack has neither.
 */
export interface PackIdentity {
  /** `dim_region.pack_id` — simultaneously the manifest entry's id and the install key (s17). */
  readonly packId: string | null;
  /** `dim_region.display_name` — names the PACK, which for New York is a borough (s17). */
  readonly regionDisplayName: string | null;
  /** `city`, `borough` or `extent`. **Not coverage** — San Jose is level `city`, coverage `downtown`. */
  readonly regionLevel: string | null;
  /** `dim_city.display_name` (s16). For a borough pack this is the city, not the borough. */
  readonly cityDisplayName: string | null;
  readonly cityState: string | null;
  /** The city's own official street-tree page (s16) — a civic fact entered at publish. */
  readonly urbanForestryURL: string | null;
  /** `seed_meta.publish_pack_id`, when the file was written by the publisher. */
  readonly statedPackId: string | null;
  /** The generation the file states about itself. 0 when it does not say — see `Pack`. */
  readonly statedSchemaVersion: number;
}

/**
 * A published pack carries exactly one region row and one city row, because the publisher narrows
 * both to the pack it is writing — "a pack that carried another region's civic facts would be
 * claiming an authority it does not have". The **source** seed is the case that is not so: the
 * pinned one carries two `dim_city` rows (San Francisco and San Jose) because it is the fused
 * build every pack is cut from, not a pack. So this reads the *first* row by `id` and the caller
 * gets a defined answer either way, rather than a query that is correct only on a real pack.
 */
export function packIdentity(pack: Pack): PackIdentity {
  const first = (sql: string): Record<string, unknown> | null => {
    const row = pack.db.prepare(sql).get();
    return row === undefined ? null : (row as Record<string, unknown>);
  };
  const text = (source: Record<string, unknown> | null, key: string): string | null => {
    if (source === null) return null;
    const value = source[key];
    return value === null || value === undefined ? null : String(value);
  };

  const region = pack.schema.hasRegions
    ? first('SELECT pack_id, display_name, level FROM dim_region ORDER BY id LIMIT 1')
    : null;
  const city = pack.schema.hasDimCity
    ? first('SELECT display_name, state, urban_forestry_url FROM dim_city ORDER BY id LIMIT 1')
    : null;

  return {
    packId: text(region, 'pack_id'),
    regionDisplayName: text(region, 'display_name'),
    regionLevel: text(region, 'level'),
    cityDisplayName: text(city, 'display_name'),
    cityState: text(city, 'state'),
    urbanForestryURL: text(city, 'urban_forestry_url'),
    statedPackId: pack.meta.get('publish_pack_id') ?? null,
    statedSchemaVersion: pack.statedSchemaVersion,
  };
}
