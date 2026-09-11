/**
 * The instruments, before anything is measured with them.
 *
 * Every parity test in this directory rests on a parser that reads a Swift, Python or markdown
 * file. A parser that silently matches nothing returns an empty table, an equality against an
 * empty table passes, and the suite reports that the port agrees with a source it never opened.
 * That is this project's signature failure in its cheapest form, and CLAUDE.md's answer is the
 * one followed here: **run the instrument against a case whose answer you already know, first.**
 *
 * So each parser below gets a hand-written specimen with the answer stated in the assertion, plus
 * a near-miss it has to DECLINE rather than answer wrongly. Only then does anything point one at
 * the real repository.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  ParseFailure,
  markdownAnchorTable,
  pythonIdSpacePrefixes,
  pythonStringConstant,
  pythonUUIDConstant,
  repoFile,
  repositoryRoot,
  sourcesTheWebSuiteReads,
  swiftClosedRangeLet,
  swiftDoubleLet,
  swiftEnumCases,
  swiftStringCases,
  swiftSwitchTable,
} from './support/sources.ts';

describe('the parsers the parity tests depend on', () => {
  it('reads a Double let, and declines a differently typed one', () => {
    const specimen = [
      'public static let gridM: Double = 25',
      'public static let countM: Int = 25',
      'public static let scaled: Double = 1_250.5',
      'public static let tiny: Double = 1e-3',
    ].join('\n');
    assert.equal(swiftDoubleLet(specimen, 'gridM'), 25);
    assert.equal(swiftDoubleLet(specimen, 'scaled'), 1250.5);
    assert.equal(swiftDoubleLet(specimen, 'tiny'), 0.001);
    // `countM` is an Int in Swift and a different declaration. A parser that answered 25 here
    // would report the same value for two things this repository deliberately keeps apart.
    assert.throws(() => swiftDoubleLet(specimen, 'countM'), ParseFailure);
    assert.throws(() => swiftDoubleLet(specimen, 'absent'), ParseFailure);
  });

  it('reads a ClosedRange let', () => {
    const specimen = 'public static let dbhM: ClosedRange<Double> = 0.001...4.0';
    assert.deepEqual(swiftClosedRangeLet(specimen, 'dbhM'), { lowerBound: 0.001, upperBound: 4 });
    assert.throws(() => swiftClosedRangeLet(specimen, 'heightM'), ParseFailure);
  });

  it('reads an enum’s own cases and no other enum’s', () => {
    const specimen = [
      'public enum Wanted: String, Codable {',
      '    case first = "one"',
      '    case second = "two"',
      '',
      '    public var doubled: String {',
      '        switch self {',
      '        case .first: return "x"',
      '        case .second: return "y"',
      '        }',
      '    }',
      '}',
      '',
      'public enum Unwanted: String {',
      '    case third = "three"',
      '}',
    ].join('\n');
    // `third` must NOT appear: it is the next enum down, and a parser that took "everything after
    // the header" would swallow it and agree with a file it had misread.
    assert.deepEqual(swiftEnumCases(specimen, 'Wanted'), [
      { name: 'first', raw: 'one' },
      { name: 'second', raw: 'two' },
    ]);
    assert.deepEqual(swiftEnumCases(specimen, 'Unwanted'), [{ name: 'third', raw: 'three' }]);
    assert.throws(() => swiftEnumCases(specimen, 'Missing'), ParseFailure);
  });

  it('reads integer raw values too', () => {
    const specimen = ['public enum Level: Int {', '    case low = 1', '    case high = 5', '}'].join('\n');
    assert.deepEqual(swiftEnumCases(specimen, 'Level'), [
      { name: 'low', raw: '1' },
      { name: 'high', raw: '5' },
    ]);
  });

  it('reads a one-line switch table, stops at the property’s end, and spreads a multi-name case', () => {
    const specimen = [
      'public enum Unit {',
      '    public var factor: Double {',
      '        switch self {',
      '        case .small: return 0.01',
      '        case .large: return 10',
      '        }',
      '    }',
      '',
      '    public var isSmall: Bool {',
      '        switch self {',
      '        case .small, .tiny: return true',
      '        case .large: return false',
      '        }',
      '    }',
      '}',
    ].join('\n');
    // `isSmall`'s rows must not leak into `factor`. Without the stop, `factor` would report
    // `small => true`, which reads like a parse and is a different question's answer.
    assert.deepEqual([...swiftSwitchTable(specimen, 'factor')], [['small', '0.01'], ['large', '10']]);
    assert.deepEqual(
      [...swiftSwitchTable(specimen, 'isSmall')],
      [['small', 'true'], ['tiny', 'true'], ['large', 'false']],
    );
    assert.throws(() => swiftSwitchTable(specimen, 'nothing'), ParseFailure);
  });

  it('reads returned string literals across a line break', () => {
    const specimen = [
      'public enum Row {',
      '    public var anchor: String {',
      '        switch self {',
      '        case .one:',
      '            return "first sentence; with a semicolon"',
      '        case .two: return "second"',
      '        }',
      '    }',
      '',
      '    public var other: String {',
      '        switch self {',
      '        case .one: return "not this"',
      '        }',
      '    }',
      '}',
    ].join('\n');
    assert.deepEqual(
      [...swiftStringCases(specimen, 'anchor')],
      [['one', 'first sentence; with a semicolon'], ['two', 'second']],
    );
    assert.throws(() => swiftStringCases(specimen, 'missing'), ParseFailure);
  });

  it('reads ID_SPACES, and only from inside it', () => {
    const specimen = [
      'DECOY = {',
      '    "zz": IdSpace(',
      '        id="zz",',
      '        identity_prefix="zz:",',
      '    ),',
      '}',
      '',
      'ID_SPACES = {',
      '    "aa": IdSpace(',
      '        id="aa",',
      '        identity_prefix="",',
      '        note="a note",',
      '    ),',
      '    "bb-cc": IdSpace(',
      '        id="bb-cc",',
      '        identity_prefix="bb-cc:",',
      '    ),',
      '}',
    ].join('\n');
    assert.deepEqual([...pythonIdSpacePrefixes(specimen)], [['aa', ''], ['bb-cc', 'bb-cc:']]);
    assert.throws(() => pythonIdSpacePrefixes('nothing here'), ParseFailure);
  });

  it('reads module constants', () => {
    assert.equal(pythonStringConstant('SEP = ":"\n', 'SEP'), ':');
    assert.equal(
      pythonUUIDConstant('NS = uuid.UUID("6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001")\n', 'NS'),
      '6f2a1d8e-0f3d-5d3e-9a1a-7c1f0b9a0001',
    );
    assert.throws(() => pythonStringConstant('SEP = 3\n', 'SEP'), ParseFailure);
    assert.throws(() => pythonUUIDConstant('NS = "x"\n', 'NS'), ParseFailure);
  });

  /**
   * The direct port of `VitalityRubricTests.theParserIsCalibrated`, with one case the Swift does
   * not need: Swift's `Int(cells[0])` is nil for anything that is not all digits, and `Number("")`
   * is 0. A blank leading cell has to be declined here, and a literal port would have admitted it
   * as level 0 — which is not a level, and which would then compare successfully against nothing.
   */
  it('reads the Anchor column its header names, inside the named section only', () => {
    const specimen = [
      '## Something else',
      '| Level | Anchor line |',
      '|---|---|',
      '| 1 | not this table |',
      '',
      '### Vitality scale (draft)',
      'Prose in between, and a stray pipe | that starts no row.',
      '| Level | Title | Anchor line | Band |',
      '|---|---|---|---|',
      '| 1 | `1 · Severe decline` | `first` | 51–100% |',
      '| 2 | `2 · Poor` | `second` | 26–50% |',
      '|  | `blank level` | `nobody` | — |',
      '',
      '### The next section',
      '| Level | Anchor line |',
      '|---|---|',
      '| 3 | nor this one |',
    ].join('\n');
    assert.deepEqual(
      [...markdownAnchorTable(specimen, '### Vitality scale')],
      [[1, 'first'], [2, 'second']],
    );
    assert.throws(() => markdownAnchorTable(specimen, '### Absent'), ParseFailure);
    assert.throws(
      () => markdownAnchorTable('### Empty\nno table here at all\n', '### Empty'),
      ParseFailure,
    );
  });
});

describe('the sources the web suite reads', () => {
  it('the repository root resolves and every named source exists and is not empty', () => {
    const root = repositoryRoot();
    assert.ok(root.length > 0);
    assert.equal(
      sourcesTheWebSuiteReads.length,
      10,
      `the parity checks name ${sourcesTheWebSuiteReads.length} sources, not 10. If a check was `
        + `added, add its source here and to web.yml; if one was removed, this count moves with it.`,
    );
    for (const relative of sourcesTheWebSuiteReads) {
      const text = repoFile(relative);
      assert.ok(
        text.length > 500,
        `${relative} read back ${text.length} bytes. Every parity check reads one of these; an `
          + `empty or truncated one makes its check pass on nothing.`,
      );
    }
  });

  /**
   * **The gap that makes the parity checks real, closed in the one file that can close it.**
   *
   * The `Web` workflow runs on its `paths:` filter. Until this list was added to it, a change to
   * `Cypress/Core/Rubric/Vitality.swift` ran the iOS suite and not this one, so the drift every
   * check in this directory exists to catch would have merged green and surfaced on some later,
   * unrelated web commit. The filter and this list are a pair, the way `web.yml` and
   * `testflight.yml`'s carve-out are a pair, and this is the assertion that says so.
   */
  it('the Web workflow runs when any source the parity checks read changes', () => {
    const workflow = repoFile('.github/workflows/web.yml');
    const missing = sourcesTheWebSuiteReads.filter((relative) => !workflow.includes(`'${relative}'`));
    assert.deepEqual(
      missing,
      [],
      `.github/workflows/web.yml does not list ${missing.join(', ')} under \`paths:\`. The web `
        + `suite parses those files to prove the TypeScript port still agrees with them, and a `
        + `check that does not run on the change it guards is not a check. Add the path to BOTH `
        + `the push and the pull_request filter.`,
    );
    // Both triggers, not one. `push:` and `pull_request:` carry separate filters and the one that
    // matters for a PR is the second; a list added to only the first reads as done. Counted by
    // occurrence rather than by splitting the file on `paths:`, because that word also appears in
    // the workflow's own prose and a split would hand a comment to this loop as if it were a filter.
    for (const relative of sourcesTheWebSuiteReads) {
      const occurrences = workflow.split(`'${relative}'`).length - 1;
      assert.ok(
        occurrences >= 2,
        `web.yml names ${relative} ${occurrences} time(s); it belongs in both the push and the `
          + `pull_request \`paths:\` filter, and a pull request is judged by the second`,
      );
    }
  });
});
