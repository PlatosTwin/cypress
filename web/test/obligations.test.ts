import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  NYC_DISCLAIMER_ATTRIBUTION,
  NYC_DISCLAIMER_HEADING,
  NYC_DISCLAIMER_REQUIRED,
  NYC_ID_SPACE,
  sourceObligation,
} from '../src/lib/obligations.ts';
import { idSpaces } from '../src/lib/idSpaces.ts';
import { repoFile, swiftMultilineStringLet, swiftStringLet } from './support/sources.ts';

/**
 * The disclaimer a page serving New York's data must carry, against the app's own copy of it.
 *
 * This is not a style check. R36's binding consequence (b) puts the source's attribution
 * obligations on whatever serves the data; R78 ruling 2 rules the surface and signs off the
 * constraint-21 question of adding the copy; **R78 ruling 3 says the manifest's machine-readable
 * `attribution` array does not discharge it**. So the obligation is discharged by text on a page,
 * and the text has to be the City's.
 *
 * The comparison runs against `CityDownloadsPresentation.swift` parsed at run time rather than
 * against a transcription, for the reason every port in this directory does — and with one extra
 * reason here. The iOS suite already checks that Swift string against
 * `docs/operations/nyc-data-obligations.md`. Chaining to it means the web's copy is two mechanical
 * hops from the City's own terms with no human retyping at either end; a transcription here would
 * cut the chain at exactly the link that matters.
 */

const swift = repoFile('Cypress/Features/Cities/CityDownloadsPresentation.swift');

describe('the NYC Data Mine disclaimer', () => {
  it('is the app’s own required text, character for character', () => {
    const declared = swiftMultilineStringLet(swift, 'nycDisclaimerRequired');
    assert.equal(NYC_DISCLAIMER_REQUIRED, declared);
  });

  it('is one paragraph — the Swift’s line continuations are joins, not line breaks', () => {
    // The calibration for the parser above, run against this specimen rather than a synthetic one.
    // The Swift writes this sentence across four source lines ending in `\`; a parser that joined
    // on newlines would return a string that is equal to nothing and looks almost right in a diff.
    const declared = swiftMultilineStringLet(swift, 'nycDisclaimerRequired');
    assert.ok(!declared.includes('\n'), 'the required text came back with a line break in it');
    assert.ok(declared.length > 250, `the required text parsed to ${declared.length} characters`);
    // And the indentation strip worked: no run of Swift's source indentation survived into it.
    assert.ok(!declared.includes('   '), 'source indentation survived into the required text');
  });

  it('still says the four things the City’s terms require it to say', () => {
    // Named facts rather than the whole sentence re-quoted: if the Swift and this file BOTH drifted
    // the equality above would still pass, and these are what the obligation is actually about.
    for (const phrase of [
      'The City of New York can not vouch',
      'accuracy or completeness',
      'modified for use from its original source',
      'NYC.gov, the official web site of the City of New York',
    ]) {
      assert.ok(NYC_DISCLAIMER_REQUIRED.includes(phrase), `the disclaimer no longer says “${phrase}”`);
    }
  });

  it('carries the app’s heading and the app’s own attribution line', () => {
    assert.equal(NYC_DISCLAIMER_HEADING, swiftStringLet(swift, 'nycDisclaimerHeading'));
    assert.equal(
      NYC_DISCLAIMER_ATTRIBUTION,
      swiftMultilineStringLet(swift, 'nycDisclaimerAttribution'),
    );
  });

  it('names the two datasets the obligation is owed over', () => {
    assert.ok(NYC_DISCLAIMER_ATTRIBUTION.includes('Forestry Tree Points'));
    assert.ok(NYC_DISCLAIMER_ATTRIBUTION.includes('Forestry Planting Spaces'));
  });
});

describe('which pages carry it', () => {
  it('is New York’s id space, and that space is one the registry knows', () => {
    // The control: a constant naming a space that does not exist would make every assertion below
    // vacuously "no obligation", which is the failure that ships the violation.
    assert.ok(Object.hasOwn(idSpaces, NYC_ID_SPACE), `${NYC_ID_SPACE} is not in the registry`);
    assert.ok(idSpaces[NYC_ID_SPACE]?.note.includes('New York'));
  });

  it('attaches to every New York page', () => {
    const obligation = sourceObligation(NYC_ID_SPACE);
    assert.notEqual(obligation, null);
    assert.equal(obligation?.heading, NYC_DISCLAIMER_HEADING);
    // The City's sentence first, ours second, and ours is never the one a reader sees alone.
    assert.deepEqual(
      [...obligation?.paragraphs ?? []],
      [NYC_DISCLAIMER_REQUIRED, NYC_DISCLAIMER_ATTRIBUTION],
    );
  });

  it('attaches to no other id space the registry holds', () => {
    // Asserted over the registry rather than over two names, so a city added later is answered
    // here by whoever adds it rather than by nobody.
    for (const space of Object.keys(idSpaces)) {
      if (space === NYC_ID_SPACE) continue;
      assert.equal(sourceObligation(space), null, `${space} grew an obligation nothing declared`);
    }
  });

  it('answers null for a space that does not exist, rather than throwing', () => {
    assert.equal(sourceObligation('zz'), null);
    assert.equal(sourceObligation(''), null);
    assert.equal(sourceObligation('constructor'), null);
  });
});
