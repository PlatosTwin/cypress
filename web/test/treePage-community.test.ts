import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  communityNote,
  facts,
  treePageModel,
  W1Copy,
  type TreePageInput,
} from '../src/lib/treePage.ts';
import {
  decodePublicTreeRead,
  type CommunityHalf,
  type PublicTreeRead,
} from '../src/lib/publicTreeRead.ts';
import { repoFile } from './support/sources.ts';

/**
 * What W1 draws when the community half is there, when it is empty, and when it cannot be reached.
 *
 * **The bodies are the handler's own golden files**, decoded through the real decoder — not a
 * literal typed here. `server/testdata/public_tree.json` is what
 * `TestPublicTreeReturnsTheContributedState` compares the handler against byte-for-byte, so a row
 * below is a row the service can actually produce. `publicTreeRead.test.ts` is the tier that
 * proves the decode; this is the tier that says what the page does with it.
 *
 * ── The property this file exists for ────────────────────────────────────────────────────────
 *
 * Three states must not look identical, and two of them are silences:
 *
 * - `empty` — the service answered and this tree has nothing. Renders nothing extra, which is the
 *   house style and misleads nobody.
 * - `unavailable` / `unconfigured` — this page could not ask. Renders the same rows **and one
 *   sentence**, because without it the page would assert "nobody has measured this tree" every
 *   time it merely failed to reach the service.
 *
 * The last test compares the three rendered models directly, so "they differ" is asserted rather
 * than inferred from the assertions above it.
 */

/** `2576 LOMBARD ST` — the same real San Francisco row `treePage.test.ts` is built on. */
const lombard: TreePageInput = {
  idSpace: 'sf',
  uuid: 'eac6cce9-68bf-53c6-aa3c-44d26deb868d',
  status: 'alive',
  address: '2576 LOMBARD ST',
  neighborhoodName: 'Marina',
  cityName: 'San Francisco',
  speciesCommonName: 'Monterey Cypress',
  speciesScientificName: 'Cupressus macrocarpa',
  plantedYear: 1993,
  dbhCityCmMin: 65,
  dbhCityCmMax: 70,
  siteType: 'Sidewalk: Curb side : Cutout',
  externalRef: '13284',
  inventoryName: 'SF Public Works street tree inventory',
  inventoryURL: 'https://services.arcgis.com/…/BUF_Street_Trees/FeatureServer/3',
  inventorySnapshotOn: '2026-08-22',
  inventoryLicense: null,
};

const GOLDEN_UUID = '9f3a1c07-4d55-4a7e-9f10-2b6f0c1d5e42';

/** The handler's golden body, through the real decoder. */
function goldenRead(file: string): PublicTreeRead {
  const outcome = decodePublicTreeRead(JSON.parse(repoFile(file)) as unknown, GOLDEN_UUID);
  assert.equal(outcome.ok, true, `${file} no longer decodes — the contract has moved`);
  if (!outcome.ok) throw new Error('unreachable');
  return outcome.read;
}

const full = goldenRead('server/testdata/public_tree.json');
const answered: CommunityHalf = { state: 'answered', read: full };
const empty: CommunityHalf = { state: 'empty' };
const unavailable: CommunityHalf = { state: 'unavailable', detail: 'connection refused' };
const unconfigured: CommunityHalf = { state: 'unconfigured', detail: 'the variable is not set' };

const row = (input: TreePageInput, id: string) => facts(input).find((fact) => fact.id === id);
const ids = (input: TreePageInput) => facts(input).map((fact) => fact.id);

describe('the fact column with the community half answered', () => {
  const withHalf: TreePageInput = { ...lombard, community: answered };

  it('the fixture is the one §W1 draws, so these rows are the mock`s own numbers', () => {
    // Calibration on the fixture rather than on the page: §W1's table says `18 m` `est.` and
    // `64 cm` `taped`, and the Go round seeded exactly that. If the fixture ever stops matching,
    // every assertion below is about some other tree and this is where that shows.
    assert.equal(full.height?.quantity.value, 18);
    assert.equal(full.height?.quantity.unitEntered, 'm');
    assert.equal(full.trunkDBH?.quantity.value, 64);
    assert.equal(full.trunkDBH?.quantity.method, 'tape');
  });

  it('draws §W1`s Height row, with the value as entered and its method badge', () => {
    const height = row(withHalf, 'height');
    assert.equal(height?.label, 'Height');
    assert.equal(height?.value, '18 m');
    assert.equal(height?.badge?.text, 'est.');
    assert.equal(height?.badge?.tone, 'estimated');
    assert.equal(height?.emphasized, false);
  });

  it('the taped reading takes the Trunk · DBH row, and the city bucket stands down', () => {
    const dbh = row(withHalf, 'dbh');
    assert.equal(dbh?.value, '64 cm');
    assert.equal(dbh?.badge?.text, 'taped');
    assert.equal(dbh?.badge?.tone, 'measured');
    // The substitution is gone, not doubled: the bucket the pack carries for this row is
    // `65–70 cm`, and there is no second row carrying it.
    assert.equal(row(lombard, 'dbh')?.value, '65–70 cm');
    assert.equal(facts(withHalf).filter((fact) => fact.value === '65–70 cm').length, 0);
  });

  it('falls back to the city bucket when only the height is answered', () => {
    const heightOnly: CommunityHalf = { state: 'answered', read: { ...full, trunkDBH: null } };
    const input: TreePageInput = { ...lombard, community: heightOnly };
    assert.equal(row(input, 'dbh')?.value, '65–70 cm');
    assert.equal(row(input, 'dbh')?.badge?.text, 'city record');
    assert.equal(row(input, 'height')?.value, '18 m');
  });

  it('draws the beloved state with its count, and calls the count favorites', () => {
    const beloved = row(withHalf, 'beloved');
    assert.equal(beloved?.label, 'Beloved');
    assert.equal(beloved?.value, '3 favorites');
    assert.equal(beloved?.badge, null);
    // `people` would overstate it: the floor counts distinct accounts, and one person with two
    // Apple IDs is two of them.
    assert.equal(/people/.test(beloved?.value ?? ''), false);
  });

  it('never draws a beloved row below the floor, where there is no number at all', () => {
    const below: CommunityHalf = {
      state: 'answered',
      read: { ...full, beloved: false, belovedBy: null },
    };
    assert.equal(row({ ...lombard, community: below }, 'beloved'), undefined);
    // And not even when a number arrives with the state false, which the decoder already refuses:
    // a count under a k-anonymity floor is the disclosure the floor exists to prevent.
    const forged: CommunityHalf = {
      state: 'answered',
      read: { ...full, beloved: false, belovedBy: 2 },
    };
    assert.equal(row({ ...lombard, community: forged }, 'beloved'), undefined);
  });

  it('puts the community rows in §W1`s order and appends the row §W1 does not draw', () => {
    assert.deepEqual(ids(withHalf), [
      'status', 'height', 'dbh', 'planted', 'site', 'cityRecord', 'beloved',
    ]);
    // §W1's own order for the rows it draws: Status, Height, Trunk · DBH, then the city's. The
    // beloved row is last because the specification has no place for it to claim.
    assert.deepEqual(ids(lombard), ['status', 'dbh', 'planted', 'site', 'cityRecord']);
  });

  it('still draws no vitality, because the endpoint does not publish one', () => {
    assert.equal(row(withHalf, 'vitality'), undefined);
    assert.equal(row(withHalf, 'status')?.value, 'Alive');
    // The response has no slot for it: the field was removed from the Go before #163 merged,
    // because a published rating has no takedown route (the ruling's §8).
    assert.equal('vitality' in (full as unknown as Record<string, unknown>), false);
  });

  it('a vacant planting site takes no reading, and still takes the beloved state', () => {
    // `SitePresentation.stats` refuses a measurement on a site because "the second is a claim
    // about a tree", and a taped reading is no less a claim for having been taped by a person.
    const site: TreePageInput = { ...lombard, status: 'vacant_site', community: answered };
    assert.equal(row(site, 'height'), undefined);
    assert.equal(row(site, 'dbh'), undefined);
    assert.equal(row(site, 'beloved')?.value, '3 favorites');
  });
});

describe('the fact column when the service says nothing, or cannot be asked', () => {
  it('an empty answer renders exactly the page the pack alone renders', () => {
    const input: TreePageInput = { ...lombard, community: empty };
    assert.deepEqual(ids(input), ids(lombard));
    assert.equal(row(input, 'dbh')?.badge?.text, 'city record');
    // And says nothing, because "nobody has measured this tree" is the truth here.
    assert.equal(communityNote(input), null);
  });

  it('an unreachable service renders the same rows and one sentence', () => {
    for (const half of [unavailable, unconfigured]) {
      const input: TreePageInput = { ...lombard, community: half };
      assert.deepEqual(ids(input), ids(lombard));
      assert.equal(communityNote(input), W1Copy.communityUnavailable);
    }
  });

  it('a render that never asked says nothing either — the OpenGraph card is one', () => {
    assert.equal(communityNote(lombard), null);
    assert.equal(treePageModel(lombard).communityState, 'notRequested');
  });

  it('the note names no host, no variable and no status code', () => {
    // A reader is owed the fact and not the operator's diagnosis; the reason is in the log line
    // the route writes. An internal error message in a fact column is the failure this avoids.
    const note = W1Copy.communityUnavailable;
    assert.equal(/http|CYPRESS_|\b\d{3}\b/.test(note), false, note);
    assert.ok(note.endsWith('.'));
    // American spellings, and it says what is still true rather than only what failed.
    assert.match(note, /city record/);
  });

  it('the three states do not look identical TO A READER', () => {
    /**
     * **`communityState` is deliberately not in here, and that is the whole point of the test.**
     *
     * The first version of this assertion included it, and it stayed green when
     * `communityNote` was broken to answer null for every state — because the state tag still
     * differed and the JSON still differed. It was measuring the model, and what has to differ is
     * the *page*. So this compares only what a reader can see: the rows and the sentence.
     *
     * The tag's own plumbing is asserted separately, below.
     */
    const seen = (half: CommunityHalf) => {
      const model = treePageModel({ ...lombard, community: half });
      return JSON.stringify({ facts: model.facts, note: model.communityNote });
    };
    const withData = seen(answered);
    const withNothing = seen(empty);
    const cannotAsk = seen(unavailable);
    assert.notEqual(withData, withNothing, 'answered and empty render the same page');
    assert.notEqual(
      withNothing,
      cannotAsk,
      'a tree nobody has measured and a service this page could not reach render the same page, '
        + 'so the page asserts the first every time the second is true',
    );
    assert.notEqual(withData, cannotAsk, 'answered and unavailable render the same page');
    // The one pair that DOES agree for a reader, said out loud rather than left to be discovered:
    // `unavailable` and `unconfigured` are one fact to a reader and two to an operator. The
    // operator's difference is `communityState` and the route's log line, not the fact column.
    assert.equal(seen(unavailable), seen(unconfigured));
    assert.notEqual(
      treePageModel({ ...lombard, community: unavailable }).communityState,
      treePageModel({ ...lombard, community: unconfigured }).communityState,
    );
  });

  it('the state reaches the model for every one of the five', () => {
    const states: CommunityHalf[] = [answered, empty, unavailable, unconfigured];
    for (const half of states) {
      assert.equal(treePageModel({ ...lombard, community: half }).communityState, half.state);
    }
    assert.equal(treePageModel(lombard).communityState, 'notRequested');
  });
});
