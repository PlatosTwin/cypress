/**
 * The id spaces, against `Tools/inventory_contract.py`.
 *
 * **The brief for this milestone said "the ID spaces" and pointed at the Swift. There is no Swift
 * declaration.** `Cypress/Core/Models/Tree.swift:176` carries `idSpace: String?` and treats it as
 * an opaque string; `Cypress/Data/Cities/SeedCities.swift:154` reads the published file's own
 * `id_spaces` table. The registry — the frozen prefixes, the rules a new space must meet, the
 * separator — exists once, in Python. So the cases ported here come from
 * `Tools/test_inventory_contract.py`, not from `CypressTests`.
 *
 * Ported: `test_the_sf_uuid_derivation_is_frozen` (the two known uuids and the empty prefix),
 * `test_the_two_sf_inventories_share_an_identity_on_purpose`, `test_two_cities_cannot_collide`,
 * `test_a_new_id_space_cannot_declare_an_empty_prefix`, `test_a_new_id_space_must_terminate_its_
 * prefix`, `test_two_id_spaces_cannot_share_a_prefix`, `test_an_unregistered_source_is_refused`,
 * and `test_a_source_ref_cannot_alias_another_id_space`.
 *
 * The Python's refusal tests mutate the module-level `ID_SPACES` dict and restore it in a
 * `finally`. `requireIdSpace`/`checkRegistry` here take the registry as an argument instead, so
 * the fictional spaces below are the same coverage without the shipped registry ever being
 * mutable — which is the one structural difference between the two suites.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  ContractError,
  IDENTITY_SEPARATOR,
  NS_TREE,
  checkRegistry,
  identitySeed,
  idSpaces,
  inventories,
  requireIdSpace,
  requireInventory,
  sourceRefProblems,
  treeUUID,
  uuid5,
  type IdSpace,
  type IdSpaceRegistry,
} from '../src/lib/idSpaces.ts';
import { pythonIdSpacePrefixes, pythonStringConstant, pythonUUIDConstant, repoFile } from './support/sources.ts';

const contract = repoFile('Tools/inventory_contract.py');

/** The refusal message, or '' if the space was accepted. `refusal_for` in the Python. */
function refusalFor(spaceID: string, registry: IdSpaceRegistry): string {
  try {
    requireIdSpace(spaceID, registry);
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
  return '';
}

const withSpace = (id: string, identityPrefix: string): IdSpaceRegistry => ({
  ...idSpaces,
  [id]: { id, identityPrefix, note: 'fictional, for this test only' },
});

describe('the registry is the Python’s', () => {
  it('every registered space, and its frozen prefix', () => {
    const inPython = pythonIdSpacePrefixes(contract);
    const onTheWeb = new Map(Object.values(idSpaces).map((space) => [space.id, space.identityPrefix]));
    assert.deepEqual(
      [...onTheWeb].sort(),
      [...inPython].sort(),
      `web/src/lib/idSpaces.ts and Tools/inventory_contract.py disagree about the id spaces or `
        + `their prefixes. A prefix is frozen per space — changing one rewrites every public tree `
        + `URL in it — so a disagreement here is the web resolving /‹space›/tree/‹uuid› to a `
        + `different tree than the one the seed minted.`,
    );
    assert.equal(inPython.size, 3, `the Python registers ${inPython.size} spaces, not 3`);
  });

  it('the separator and the uuid namespace are the ones the seed builder uses', () => {
    assert.equal(IDENTITY_SEPARATOR, pythonStringConstant(contract, 'IDENTITY_SEPARATOR'));
    assert.equal(NS_TREE, pythonUUIDConstant(repoFile('Tools/build_seed.py'), 'NS_TREE'));
  });

  it('every inventory names a registered space, and the shipped registry validates', () => {
    assert.deepEqual(checkRegistry(), []);
    for (const inventory of Object.values(inventories)) {
      assert.doesNotThrow(() => requireInventory(inventory.id));
    }
    assert.equal(Object.keys(inventories).length, 5, 'the Python registers five inventories');
  });
});

/**
 * `test_the_sf_uuid_derivation_is_frozen`, ported with its known answers.
 *
 * These two uuids are asserted in `Tools/test_inventory_contract.py` as literals, so they are
 * answers known before this port existed — which is what makes them a calibration of `uuid5` and
 * not a restatement of whatever it happens to compute.
 */
describe('the uuid derivation is frozen', () => {
  it('SF TreeID 276198 still mints the shipped uuid', () => {
    assert.equal(
      treeUUID('sf', '276198'),
      '80a237b1-ba0a-515b-8c96-3da5a790c69d',
      'SF uuid derivation moved: TreeID 276198 no longer mints the shipped uuid. 145,837 public '
        + 'tree URLs are this function, and DECISIONS constraint 13 makes them permanent.',
    );
    assert.equal(idSpaces['sf']?.identityPrefix, '', "the 'sf' prefix is no longer empty");
    assert.equal(identitySeed(requireIdSpace('sf'), '276198'), '276198');
  });

  /** `test_the_two_sf_inventories_share_an_identity_on_purpose`. E156. */
  it('SF’s two inventories share an identity on purpose', () => {
    assert.equal(inventories['sf_city']?.idSpace, 'sf');
    assert.equal(inventories['sf_datasf']?.idSpace, 'sf');
    assert.equal(treeUUID('sf', '266901'), '62b2911f-c0f1-5876-9922-c92a69e94bcc');
    // Their colliding is what made the DataSF → city switch reversible with zero uuids moved, and
    // what keeps a photograph attached to its tree across a source change. Not a bug to fix.
    assert.equal(
      treeUUID(inventories['sf_city']!.idSpace, '266901'),
      treeUUID(inventories['sf_datasf']!.idSpace, '266901'),
    );
  });

  /** `test_two_cities_cannot_collide`. */
  it('a second city’s TreeID 276198 does not mint San Francisco’s uuid', () => {
    const la: IdSpace = { id: 'us-ca-la', identityPrefix: 'us-ca-la:', note: '' };
    assert.equal(identitySeed(la, '276198'), 'us-ca-la:276198');
    assert.notEqual(
      uuid5(NS_TREE, identitySeed(la, '276198')),
      treeUUID('sf', '276198'),
      'a second city’s TreeID 276198 mints San Francisco’s uuid',
    );
    // And the two registered non-SF spaces do not collide with SF or with each other.
    const minted = ['sf', 'us-ca-sj', 'us-ny-nyc'].map((space) => treeUUID(space, '276198'));
    assert.equal(new Set(minted).size, 3, `three spaces minted ${new Set(minted).size} distinct uuids`);
  });

  it('uuid5 is RFC 4122 version 5, not something that merely looks like a uuid', () => {
    const minted = treeUUID('sf', '276198');
    assert.match(minted, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    // The published RFC 4122 example: uuid5 of the DNS namespace over "python.org".
    assert.equal(
      uuid5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'python.org'),
      '886313e1-3b8a-5372-9b90-0c9aee199e5d',
      'uuid5 disagrees with the RFC’s own worked example, so it is not uuid5',
    );
    assert.throws(() => uuid5('not-a-uuid', 'x'), /not a uuid/);
  });
});

/**
 * `test_a_new_id_space_cannot_declare_an_empty_prefix`.
 *
 * The Python's own docstring explains why the assertion is on the REASON and not just the fact:
 * an empty prefix trips both refusals (`''.endswith(':')` is False), so an assertion that only
 * asks "was it refused" stays green with the empty-prefix guard deleted — and that is exactly how
 * it stayed green when the guard was disabled.
 */
describe('the rules a new space must meet', () => {
  it('a new space cannot declare an empty prefix, and is refused for that reason', () => {
    const registry = withSpace('us-ca-la', '');
    const message = refusalFor('us-ca-la', registry);
    assert.notEqual(message, '', 'an id space with an empty prefix was accepted; it would mint SF’s uuids');
    assert.match(
      message,
      /empty identity_prefix/,
      `an empty prefix was refused, but not by the empty-prefix guard — it fell through to another `
        + `check, so that guard could be deleted unnoticed. Got: ${message}`,
    );
    assert.ok(
      checkRegistry(registry).some((problem) => problem.includes('empty identity_prefix')),
      'the registry check does not object to a second empty-prefix id space',
    );
    // And the premise: a uuid derived under it WOULD be byte-identical to San Francisco's.
    assert.equal(
      uuid5(NS_TREE, identitySeed(registry['us-ca-la']!, '276198')),
      '80a237b1-ba0a-515b-8c96-3da5a790c69d',
      'the premise of this test is wrong: an empty prefix no longer reproduces SF’s uuid',
    );
  });

  /** `test_a_new_id_space_must_terminate_its_prefix`. */
  it('a prefix that does not end in the separator is refused, for that reason', () => {
    const message = refusalFor('us-ca-la', withSpace('us-ca-la', 'us-ca-la'));
    assert.notEqual(message, '', 'an id space whose prefix does not end in the separator was accepted');
    assert.match(message, /does not end in/, `refused for the wrong reason: ${message}`);
    // The premise: without a terminator, `us-ca-la` + `1:2` and `us-ca-la1` + `:2` are one seed
    // string. The separator is what partitions the space of seed strings.
    assert.equal(identitySeed({ id: 'a', identityPrefix: 'us-ca-la', note: '' }, '1:2'), 'us-ca-la1:2');
    assert.equal(identitySeed({ id: 'b', identityPrefix: 'us-ca-la1', note: '' }, ':2'), 'us-ca-la1:2');
  });

  /**
   * `test_two_id_spaces_cannot_share_a_prefix` — the refusal that had no test in Python until the
   * suite noticed every earlier test registered exactly one fictional space.
   */
  it('two spaces cannot share a prefix, and only the pairwise check can see it', () => {
    const registry: IdSpaceRegistry = {
      ...idSpaces,
      'us-ca-la': { id: 'us-ca-la', identityPrefix: 'us-ca:', note: '' },
      'us-ca-sd': { id: 'us-ca-sd', identityPrefix: 'us-ca:', note: '' },
    };
    assert.equal(
      refusalFor('us-ca-la', registry) + refusalFor('us-ca-sd', registry),
      '',
      'the premise is wrong: these two spaces are individually well-formed, and if requireIdSpace '
        + 'now rejects one of them this test is no longer reaching the pairwise check',
    );
    const problems = checkRegistry(registry);
    assert.ok(
      problems.some((problem) => problem.includes('share the identity_prefix')),
      `two id spaces sharing a prefix were accepted; their uuids collide. Got: ${JSON.stringify(problems)}`,
    );
    assert.equal(
      uuid5(NS_TREE, identitySeed(registry['us-ca-la']!, '276198')),
      uuid5(NS_TREE, identitySeed(registry['us-ca-sd']!, '276198')),
      'the premise is wrong: a shared prefix no longer produces a shared uuid',
    );
  });

  it('a space registered under a key that is not its id is a problem', () => {
    const problems = checkRegistry({ 'us-ca-la': { id: 'other', identityPrefix: 'x:', note: '' } });
    assert.ok(problems.some((problem) => problem.includes('not its id')), JSON.stringify(problems));
  });

  it('an unknown space is refused', () => {
    assert.throws(() => requireIdSpace('us-ca-la'), ContractError);
    assert.throws(() => requireIdSpace('us-ca-la'), /unknown id space/);
  });

  /** `test_an_unregistered_source_is_refused`. */
  it('an unregistered inventory is refused', () => {
    assert.throws(() => requireInventory('us-ca-la-streets'), ContractError);
    assert.throws(() => requireInventory('us-ca-la-streets'), /unknown inventory/);
    // An inventory in an unregistered space is refused by the space check behind it.
    assert.throws(
      () =>
        requireInventory(
          'la_streets',
          { la_streets: { id: 'la_streets', idSpace: 'us-ca-la', name: 'n', url: 'u' } },
        ),
      /unknown id space/,
    );
  });
});

/** `test_a_source_ref_cannot_alias_another_id_space`, and the blank-ref half beside it. */
describe('a source_ref that could alias another space', () => {
  it('a ref containing the separator is refused rather than minting a uuid', () => {
    assert.notDeepEqual(sourceRefProblems(`us-ca-la${IDENTITY_SEPARATOR}1`), []);
    assert.throws(() => treeUUID('sf', 'us-ca-la:1'), ContractError);
    assert.throws(() => treeUUID('sf', 'us-ca-la:1'), /contains ':'/);
  });

  it('a blank ref is refused', () => {
    assert.notDeepEqual(sourceRefProblems(''), []);
    assert.notDeepEqual(sourceRefProblems('   '), []);
    assert.throws(() => treeUUID('sf', ''), /blank/);
  });

  it('an ordinary ref is not refused — the checks above are not a constant failure', () => {
    for (const ref of ['276198', '266901', 'MB-20140207', '{0B2C3D4E-1111-2222-3333-444455556666}']) {
      assert.deepEqual(sourceRefProblems(ref), [], `'${ref}' was refused`);
    }
    assert.equal(treeUUID('sf', '276198'), '80a237b1-ba0a-515b-8c96-3da5a790c69d');
  });
});
