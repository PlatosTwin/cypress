/**
 * Id spaces: the numbering a record's id is drawn from, and the uuid it mints.
 *
 * **Where the real declaration lives, because the brief guessed and the guess was half right.**
 * There is NO Swift declaration of the id spaces. `Cypress/Core/Models/Tree.swift:176` carries
 * `idSpace: String?` and every consumer treats it as an opaque string; `Cypress/Data/Cities/
 * SeedCities.swift:154` reads the published file's own `id_spaces` TABLE. The registry — the
 * frozen prefixes, the rules a new space must meet, the separator — exists once, in Python, at
 * `Tools/inventory_contract.py:204-417` (`IDENTITY_SEPARATOR`, `IdSpace`, `ID_SPACES`,
 * `INVENTORIES`, `require_id_space`, `require_inventory`, `check_id_space_registry`), and the uuid
 * namespace it is keyed under is `NS_TREE` at `Tools/build_seed.py:1076`. So this module is ported
 * from Python, and its test cases come from `Tools/test_inventory_contract.py` rather than from
 * `CypressTests`.
 *
 * `trees.uuid = uuid5(NS_TREE, ID_SPACES[<space>].identity_prefix + source_ref)` is what made the
 * DataSF → city switch reversible: identity is a pure function of the source's own id, so 130,070
 * records kept their uuid byte for byte across the switch and back (ERRATA E156). `sf`'s prefix is
 * the empty string, frozen, because 145,837 shipped uuids are derived that way and DECISIONS
 * constraint 13 makes a tree's citable identity permanent.
 *
 * The web needs this because a public tree URL is `/‹id-space›/tree/‹uuid›` (ROADMAP W-C): the
 * page has to be able to say which numbering an `external_ref` belongs to, and to recognize that
 * San Francisco's two inventories share one.
 *
 * ── Where TypeScript and Python may legitimately differ ──────────────────────────────────────
 *
 * 1. **`uuid5` is SHA-1 over 16 namespace bytes plus the UTF-8 name.** Node's `node:crypto` is a
 *    builtin, so this adds no dependency. The test checks it against uuids whose values are
 *    already asserted in `Tools/test_inventory_contract.py` — `276198` → `80a237b1-…` and `266901`
 *    → `62b2911f-…` — which are known answers rather than answers this port produced.
 * 2. **Python encodes the name with `str.encode()`, i.e. UTF-8**, and so does `Buffer.from(s)`.
 *    Identical for the ASCII ids every registered space publishes; identical for non-ASCII too,
 *    because both are UTF-8. A lone surrogate in a JS string would encode as U+FFFD where Python
 *    would refuse the string outright — unreachable for these sources, named because it is the one
 *    input where the two encoders part company.
 * 3. **`ID_SPACES` is a mutable module-level dict in Python** and the contract's own tests mutate
 *    it to register a fictional space. The equivalent here is `checkRegistry(spaces, inventories)`
 *    taking its registry as an argument, so a test can pass a doctored one without the shipped
 *    registry ever being mutable — the same coverage without Python's `try/finally` restore.
 */

import { createHash } from 'node:crypto';

/**
 * Separates an id-space prefix from a source's own id in a uuid seed string. A `source_ref`
 * containing it is rejected, so the two halves cannot alias.
 */
export const IDENTITY_SEPARATOR = ':';

/** The frozen namespace `build_seed.py` derives tree uuids in (`Tools/build_seed.py:1076`). */
export const NS_TREE = '6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001';

/**
 * A numbering scheme that record ids are drawn from.
 *
 * Not a city and not an inventory. San Francisco's two inventories are one id space on purpose
 * (E156: the same 133,577-record intersection, median coordinate disagreement 0.04 m, zero uuids
 * moved across the switch).
 */
export interface IdSpace {
  readonly id: string;
  /**
   * Prepended to `sourceRef` to make the uuid5 seed string. **Frozen per space.** Changing one
   * rewrites every public tree URL in that space.
   */
  readonly identityPrefix: string;
  /** Why the prefix is what it is, so nobody "tidies" `sf`'s empty one. */
  readonly note: string;
}

/** One published list of records. What `trees.inventory_source` stores. */
export interface Inventory {
  readonly id: string;
  readonly idSpace: string;
  readonly name: string;
  readonly url: string;
}

export type IdSpaceRegistry = Readonly<Record<string, IdSpace>>;
export type InventoryRegistry = Readonly<Record<string, Inventory>>;

/**
 * The registry, transcribed from `Tools/inventory_contract.py:227`.
 *
 * The `note` on each is shortened to its load-bearing sentence; the Python carries the full
 * measurement record and is the place to read it. What is NOT shortened is `identityPrefix`, and
 * `web/test/idSpaces.test.ts` parses the Python to prove these three prefixes are still what it
 * says — a transcribed constant with no guard is how the vitality rubric forked for two weeks.
 */
export const idSpaces: IdSpaceRegistry = {
  sf: {
    id: 'sf',
    identityPrefix: '',
    note:
      'FROZEN EMPTY. 145,837 shipped uuids are uuid5(NS_TREE, <TreeID as ASCII>) with no prefix, '
      + 'and DECISIONS constraint 13 makes a tree’s citable identity permanent. Both of San '
      + 'Francisco’s inventories are in this space because they publish the same TreeID '
      + 'numbering. New spaces MUST declare a non-empty prefix.',
  },
  'us-ca-sj': {
    id: 'us-ca-sj',
    identityPrefix: 'us-ca-sj:',
    note: 'City of San Jose. The numbering is FACILITYID on the Street Tree layer.',
  },
  'us-ny-nyc': {
    id: 'us-ny-nyc',
    identityPrefix: 'us-ny-nyc:',
    note: 'City of New York, NYC Parks’ ForMS 2.0. The numbering is GlobalID on the '
      + 'Forestry Tree Points layer.',
  },
};

/** `Tools/inventory_contract.py:INVENTORIES`. */
export const inventories: InventoryRegistry = {
  sf_city: {
    id: 'sf_city',
    idSpace: 'sf',
    name: 'SF Public Works street tree inventory',
    url:
      'https://services.arcgis.com/Zs2aNLFN00jrS4gG/arcgis/rest/services/'
      + 'BUF_Street_Trees/FeatureServer/3',
  },
  sf_datasf: {
    id: 'sf_datasf',
    idSpace: 'sf',
    name: 'DataSF Street Tree List',
    url: 'https://data.sfgov.org/api/views/tkzw-k3nq/rows.csv?accessType=DOWNLOAD',
  },
  sj_street_tree: {
    id: 'sj_street_tree',
    idSpace: 'us-ca-sj',
    name: 'City of San Jose Street Tree inventory',
    url:
      'https://geo.sanjoseca.gov/server/rest/services/OPN/OPN_OpenDataService/MapServer/510',
  },
  nyc_tree_points: {
    id: 'nyc_tree_points',
    idSpace: 'us-ny-nyc',
    name: 'NYC Parks Forestry Tree Points',
    url: 'https://data.cityofnewyork.us/resource/hn5i-inap',
  },
  // LISTS NO TREES. Registered because `attributes_from` names it — NYC's address, borough and
  // site type live here and nowhere else.
  nyc_planting_spaces: {
    id: 'nyc_planting_spaces',
    idSpace: 'us-ny-nyc',
    name: 'NYC Parks Forestry Planting Spaces',
    url: 'https://data.cityofnewyork.us/resource/82zj-84is',
  },
};

/** What `require_id_space` and `require_inventory` raise. `ContractError` in the Python. */
export class ContractError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ContractError';
  }
}

/** `IdSpace.identity_seed`. The string `uuid5(NS_TREE, …)` is taken over. */
export function identitySeed(space: IdSpace, sourceRef: string): string {
  return `${space.identityPrefix}${sourceRef}`;
}

/**
 * The registered id space, or a throw. Enforces the rules a new space must meet.
 *
 * `sf` is grandfathered on the empty prefix and is the only space that may be. Every other space
 * must carry a non-empty prefix ending in the separator, so no two spaces' seed strings can alias
 * and no new space can silently inherit San Francisco's uuids.
 */
export function requireIdSpace(spaceID: string, registry: IdSpaceRegistry = idSpaces): IdSpace {
  const space: IdSpace | undefined = registry[spaceID];
  if (space === undefined) {
    throw new ContractError(
      `unknown id space '${spaceID}'; register it in ID_SPACES with a frozen identity_prefix `
        + `before ingesting anything keyed in it`,
    );
  }
  if (space.id !== 'sf') {
    if (space.identityPrefix === '') {
      throw new ContractError(
        `id space '${spaceID}' declares an empty identity_prefix. Only 'sf' may, and only because `
          + `its uuids already shipped. An empty prefix here would mint San Francisco's uuids for `
          + `another city's trees.`,
      );
    }
    if (!space.identityPrefix.endsWith(IDENTITY_SEPARATOR)) {
      throw new ContractError(
        `id space '${spaceID}' has identity_prefix '${space.identityPrefix}', which does not end `
          + `in '${IDENTITY_SEPARATOR}'; two spaces' seed strings could alias`,
      );
    }
  }
  return space;
}

export function requireInventory(
  inventoryID: string,
  registry: InventoryRegistry = inventories,
  spaces: IdSpaceRegistry = idSpaces,
): Inventory {
  const inventory: Inventory | undefined = registry[inventoryID];
  if (inventory === undefined) {
    throw new ContractError(
      `unknown inventory '${inventoryID}'; register it in INVENTORIES so the app can name it on `
        + `screen. A row whose provenance cannot be described is a row that draws somebody else's `
        + `name and snapshot date.`,
    );
  }
  requireIdSpace(inventory.idSpace, spaces);
  return inventory;
}

/** Problems with the registry itself, as sentences. Empty means healthy. */
export function checkRegistry(
  spaces: IdSpaceRegistry = idSpaces,
  registry: InventoryRegistry = inventories,
): string[] {
  const problems: string[] = [];
  const prefixes = new Map<string, string>();
  for (const [spaceID, space] of Object.entries(spaces)) {
    if (space.id !== spaceID) {
      problems.push(`'${spaceID}' is registered under a key that is not its id`);
    }
    try {
      requireIdSpace(spaceID, spaces);
    } catch (error) {
      problems.push(error instanceof Error ? error.message : String(error));
      continue;
    }
    const seen = prefixes.get(space.identityPrefix);
    if (seen !== undefined) {
      problems.push(
        `id spaces '${seen}' and '${spaceID}' share the identity_prefix `
          + `'${space.identityPrefix}'; their uuids would collide`,
      );
    }
    prefixes.set(space.identityPrefix, spaceID);
  }
  for (const [inventoryID, inventory] of Object.entries(registry)) {
    if (inventory.id !== inventoryID) {
      problems.push(`'${inventoryID}' is registered under a key that is not its id`);
    }
    if (!(inventory.idSpace in spaces)) {
      problems.push(
        `inventory '${inventoryID}' is in unregistered id space '${inventory.idSpace}'`,
      );
    }
  }
  return problems;
}

/**
 * Everything wrong with a `source_ref`, as sentences — the identity half of
 * `InventoryRecord.validate` (`Tools/inventory_contract.py:570-581`). Empty means usable.
 */
export function sourceRefProblems(sourceRef: string): string[] {
  const problems: string[] = [];
  if (sourceRef.trim() === '') {
    problems.push(
      'source_ref is blank; a source that publishes no id must pass None so the weaker identity '
        + 'is visible, not an empty string that looks like one',
    );
  }
  if (sourceRef.includes(IDENTITY_SEPARATOR)) {
    problems.push(
      `source_ref '${sourceRef}' contains '${IDENTITY_SEPARATOR}', which separates the id-space `
        + `prefix from the id; it could alias another space`,
    );
  }
  return problems;
}

// ── uuid5 ───────────────────────────────────────────────────────────────────────────────────

/** RFC 4122 v5: SHA-1 over the namespace's 16 bytes followed by the UTF-8 name. */
export function uuid5(namespace: string, name: string): string {
  const hex = namespace.replace(/-/g, '');
  if (!/^[0-9a-f]{32}$/i.test(hex)) {
    throw new Error(`not a uuid: '${namespace}'`);
  }
  const namespaceBytes = Buffer.from(hex, 'hex');
  const digest = createHash('sha1')
    .update(Buffer.concat([namespaceBytes, Buffer.from(name, 'utf8')]))
    .digest();
  const bytes = Uint8Array.prototype.slice.call(digest, 0, 16);
  // Version 5 in the high nibble of byte 6; RFC 4122 variant in the top two bits of byte 8.
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x50;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const out = Buffer.from(bytes).toString('hex');
  return [
    out.slice(0, 8),
    out.slice(8, 12),
    out.slice(12, 16),
    out.slice(16, 20),
    out.slice(20, 32),
  ].join('-');
}

/**
 * The uuid this source id mints in this id space — the whole point of the registry.
 *
 * Refuses a `source_ref` the contract would refuse, rather than minting a uuid from it: a bad ref
 * produces a valid-LOOKING uuid, which is the failure mode the separator rule exists to prevent.
 */
export function treeUUID(
  spaceID: string,
  sourceRef: string,
  registry: IdSpaceRegistry = idSpaces,
): string {
  const space = requireIdSpace(spaceID, registry);
  const problems = sourceRefProblems(sourceRef);
  if (problems.length > 0) throw new ContractError(problems.join('; '));
  return uuid5(NS_TREE, identitySeed(space, sourceRef));
}
