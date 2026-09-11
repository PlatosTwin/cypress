import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  cityDBHRangeText,
  cityRecordBadge,
  noValueMarkers,
  provenanceNote,
  recordNumber,
  snapshotDay,
  statedValue,
  statusLabel,
  treeStatuses,
} from '../src/lib/cityRecord.ts';
import {
  repoFile,
  swiftClosureStringCases,
  swiftDeclaration,
  swiftStringCases,
  swiftStringLet,
  swiftStringSetLet,
} from './support/sources.ts';

/**
 * The copy the public tree page borrows from the app, checked against the app.
 *
 * Every label and format in `src/lib/cityRecord.ts` already existed in Swift, over the same
 * columns, with a documented reason — and several of those reasons are rulings rather than taste:
 * the `SF ` prefix on a record number named the wrong city on 52,788 San Jose rows (R28); the
 * DBH bucket's badge is what keeps a published range from reading as a taped measurement (D7,
 * E63); `statedValue`'s middle gate is why San Francisco's bare `:` in `site_type` does not draw a
 * card claiming the city recorded a placement.
 *
 * A second copy of copy is the same hazard as a second copy of a rule (ticket #261), so this file
 * reads the Swift at run time. The **bodies** of the four declarations that are algorithms rather
 * than constants are additionally fingerprinted in `swiftDrift.test.ts` — value parsing says what
 * the Swift MEANS and the tripwire says it has not moved, and this suite needs both for the same
 * reason `web/README.md` gives for the ports.
 */

const cityRecordSwift = repoFile('Cypress/Features/TreeProfile/CityRecordPresentation.swift');
const profileSwift = repoFile('Cypress/Features/TreeProfile/TreeProfilePresentation.swift');
const segmentedSwift = repoFile('Cypress/DesignSystem/Components/SegmentedControl.swift');
const badgeSwift = repoFile('Cypress/DesignSystem/Components/MethodBadge.swift');
const seedContract = repoFile('Fixtures/seed/schema.sql');

describe('the lifecycle status, and what the app calls each one', () => {
  it('is the vocabulary the seed contract closes, and nothing more', () => {
    // Parsed out of the schema's own CHECK rather than transcribed, because that constraint is
    // what makes the set closed: a pack cannot hold a sixth status, so a sixth label would be
    // copy for a state that cannot exist.
    const check = /CHECK \(status IN \(([^)]*)\)\)/.exec(seedContract);
    assert.notEqual(check, null, 'Fixtures/seed/schema.sql no longer CHECKs trees.status');
    const declared = (check?.[1] ?? '')
      .split(',')
      .map((value) => value.trim().replace(/^'|'$/g, ''));
    assert.deepEqual([...treeStatuses], declared);
  });

  it('carries screen 05’s labels, verbatim', () => {
    const labels = swiftClosureStringCases(
      segmentedSwift,
      'options: [.alive, .declining, .deadReported, .removed],',
    );
    // The control: five cases, not the four the control OFFERS. `vacantSite` is in the switch and
    // not in the options, and it is the one this page needs most — 12,412 of San Francisco's
    // 145,964 rows are vacant sites. A parser that stopped at the options would return four and
    // every label below would still match.
    assert.equal(labels.size, 5, `the Swift switch parsed to ${labels.size} labels, not 5`);
    assert.equal(statusLabel('alive'), labels.get('alive'));
    assert.equal(statusLabel('declining'), labels.get('declining'));
    assert.equal(statusLabel('dead_reported'), labels.get('deadReported'));
    assert.equal(statusLabel('removed'), labels.get('removed'));
    assert.equal(statusLabel('vacant_site'), labels.get('vacantSite'));
  });

  it('answers null for a status it does not know, rather than printing the raw value', () => {
    assert.equal(statusLabel('dead_standing'), null);
    assert.equal(statusLabel(''), null);
    // Not inherited from Object.prototype, which is what `Object.hasOwn` is guarding.
    assert.equal(statusLabel('toString'), null);
    assert.equal(statusLabel('constructor'), null);
  });
});

describe('a value the city wrote, against one it only appears to have written', () => {
  it('holds exactly the markers CityRecordCopy.noValueMarkers holds', () => {
    const declared = swiftStringSetLet(cityRecordSwift, 'noValueMarkers');
    assert.equal(declared.length, 13, `the Swift set parsed to ${declared.length} members, not 13`);
    assert.deepEqual([...noValueMarkers].sort(), [...declared].sort());
  });

  it('keeps a real value, trimmed', () => {
    assert.equal(statedValue('  Sidewalk: Curb side : Cutout  '), 'Sidewalk: Curb side : Cutout');
    assert.equal(statedValue('Park Strip'), 'Park Strip');
  });

  it('refuses the three shapes the Swift refuses', () => {
    // Empty and whitespace.
    assert.equal(statedValue(''), null);
    assert.equal(statedValue('   '), null);
    // **No letter and no digit** — San Francisco writes a bare `:` into `site_type` on real rows,
    // and this gate is the one a re-implementation forgets.
    assert.equal(statedValue(':'), null);
    assert.equal(statedValue(' - '), null);
    // A non-value marker, case-folded.
    assert.equal(statedValue('N/A'), null);
    assert.equal(statedValue('Unassigned'), null);
    assert.equal(statedValue('unknown'), null);
  });

  it('does not refuse a value that merely contains a marker', () => {
    // The Swift matches the WHOLE trimmed string against the set. `Nail` starts with `na`, and a
    // `startsWith` or an `includes` would delete it.
    assert.equal(statedValue('Nail'), 'Nail');
    assert.equal(statedValue('None of the above'), 'None of the above');
  });

  it('counts a digit or a letter in any script, which `isLetter || isNumber` does', () => {
    // Swift's `Character.isLetter` is Unicode-wide, so the port uses `\\p{L}`/`\\p{N}` and not
    // `A-Za-z0-9`. Without this the first non-ASCII civic string to arrive would vanish.
    assert.equal(statedValue('Pōhutukawa'), 'Pōhutukawa');
    assert.equal(statedValue('三'), '三');
  });

  it('is still the algorithm the Swift runs', () => {
    // Read here as well as fingerprinted in swiftDrift.test.ts, because the fingerprint says only
    // that the body has not moved and this says what the body is made of. The three guards are
    // named; a fourth appearing makes this red and the fingerprint red together.
    const swift = swiftDeclaration(cityRecordSwift, 'static func statedValue(_ raw: String) -> String?');
    assert.equal((swift.normalized.match(/guard/g) ?? []).length, 3);
    assert.ok(swift.normalized.includes('trimmingCharacters(in: .whitespaces)'));
    assert.ok(swift.normalized.includes('$0.isLetter || $0.isNumber'));
    assert.ok(swift.normalized.includes('noValueMarkers.contains(trimmed.lowercased())'));
  });
});

describe('the city’s published DBH bucket', () => {
  it('is an en dash with no spaces, as the Swift writes it', () => {
    assert.equal(cityDBHRangeText(65, 70), '65–70 cm');
    // The character, asserted by code point: an en dash and a hyphen are one pixel apart in a
    // diff and ARCHITECTURE §5.7 picks one.
    assert.equal(cityDBHRangeText(65, 70)?.charCodeAt(2), 0x2013);
    assert.ok(!(cityDBHRangeText(65, 70) ?? '').includes(' – '));
  });

  it('collapses a bucket one unit wide, because the upper bound is EXCLUSIVE', () => {
    assert.equal(cityDBHRangeText(5, 6), '5 cm');
    assert.equal(cityDBHRangeText(5, 5), '5 cm');
    // And does not collapse a two-wide one, which is where an off-by-one would hide.
    assert.equal(cityDBHRangeText(5, 7), '5–7 cm');
  });

  it('is absent when either bound is', () => {
    assert.equal(cityDBHRangeText(null, 70), null);
    assert.equal(cityDBHRangeText(65, null), null);
    assert.equal(cityDBHRangeText(null, null), null);
  });

  it('reads the same rule out of the Swift', () => {
    const swift = swiftDeclaration(profileSwift, 'var cityDBHRangeText: String?');
    assert.ok(
      swift.normalized.includes('range.upperBound - range.lowerBound <= 1'),
      'TreeProfilePresentation.cityDBHRangeText no longer collapses on `<= 1`; the port does',
    );
    assert.ok(swift.normalized.includes('–'), 'the Swift no longer writes an en dash');
    assert.ok(swift.normalized.includes(' cm'));
  });

  it('is badged `city record`, which is MethodBadge’s own word for it', () => {
    const labels = swiftStringCases(badgeSwift, 'label');
    assert.equal(cityRecordBadge, labels.get('cityRecord'));
    // The control: the badge vocabulary has more than one member, so a parser returning a
    // one-entry map would be agreeing with itself.
    assert.ok(labels.size >= 3, `MethodBadge.label parsed to ${labels.size} cases`);
  });
});

describe('identity and provenance', () => {
  it('writes a record number with no city prefix — R28', () => {
    assert.equal(recordNumber('13284'), '#13284');
    const swift = swiftDeclaration(cityRecordSwift, 'static func recordNumber(_ ref: String) -> String');
    assert.ok(swift.normalized.includes('"#\\(ref)"'));
    assert.ok(
      !swift.normalized.includes('SF '),
      'the SF prefix is back in CityRecordCopy.recordNumber; it named the wrong city on 52,788 rows',
    );
  });

  it('writes the provenance sentence the app writes', () => {
    assert.equal(
      provenanceNote('SF Public Works street tree inventory', 'August 22, 2026'),
      'From the SF Public Works street tree inventory, August 22, 2026.',
    );
    const swift = swiftDeclaration(
      cityRecordSwift,
      'static func provenanceNote(source: String, snapshot: String) -> String',
    );
    assert.ok(swift.normalized.includes('"From the \\(source), \\(snapshot)."'));
  });

  it('has no sentence at all when the snapshot is absent', () => {
    // The Swift's rule, quoted: "If it is absent the whole sentence is absent: a provenance line
    // carrying a date the app inferred would be worse than no line."
    assert.equal(provenanceNote('SF Public Works street tree inventory', null), null);
    assert.equal(provenanceNote('SF Public Works street tree inventory', ''), null);
  });

  it('renders a bare receipt date in UTC, and refuses anything else', () => {
    assert.equal(snapshotDay('2026-08-22'), 'August 22, 2026');
    assert.equal(snapshotDay('2026-07-20'), 'July 20, 2026');
    // The first of a month, which is the day a local-time parse would move backwards.
    assert.equal(snapshotDay('2026-01-01'), 'January 1, 2026');
    assert.equal(snapshotDay('2026-02-31'), null, 'a day that does not exist must not roll forward');
    assert.equal(snapshotDay('2026-08-22T00:00:00Z'), null);
    assert.equal(snapshotDay('22 August 2026'), null);
    assert.equal(snapshotDay(null), null);
  });
});

describe('the section header the app puts over these facts', () => {
  it('names a KIND of source and never a city — R28', () => {
    const header = swiftStringLet(cityRecordSwift, 'header');
    assert.equal(header, 'What the city has on file');
    assert.ok(
      !/San Francisco|San Jose|New York/.test(header),
      'the city-record header names a city again; R28 overruled that on 52,788 rows',
    );
  });
});
