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
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

import {
  ParseFailure,
  markdownAnchorTable,
  markdownGradientRecipe,
  markdownScrim,
  markdownSection,
  pythonIdSpacePrefixes,
  pythonStringConstant,
  pythonUUIDConstant,
  repoFile,
  repositoryRoot,
  sourcesTheWebSuiteReads,
  swiftClosedRangeLet,
  swiftDeclaration,
  swiftClosureStringCases,
  swiftDoubleLet,
  swiftMultilineStringLet,
  swiftEnumCases,
  swiftGradientRecipe,
  swiftStringCases,
  swiftStringLet,
  swiftStringSetLet,
  swiftSwitchTable,
} from './support/sources.ts';

describe('the parsers the parity tests depend on', () => {
  it('reads a multi-line string let, joining its line continuations and stripping its indent', () => {
    // Specimen first, answer written out by hand before the parser saw it. Both of Swift's
    // multi-line rules are in here and both are traps: the closing delimiter sets the indent that
    // comes off every line, and a trailing backslash joins WITHOUT a newline. The second is how a
    // one-sentence legal notice is written across four lines of Swift, and a parser that joined on
    // newlines would return a value that is wrong in a way no diff viewer shows.
    const specimen = [
      '    static let notice = """',
      '        One sentence written \\',
      '        across two source lines.',
      '        A second paragraph line.',
      '        """',
      '    static let other = "plain"',
    ].join('\n');
    assert.equal(
      swiftMultilineStringLet(specimen, 'notice'),
      'One sentence written across two source lines.\nA second paragraph line.',
    );
    // The control: it must not read a single-quoted let, and it must not run past the closing
    // delimiter into the next declaration.
    assert.throws(() => swiftMultilineStringLet(specimen, 'other'), /no `let other/);
    assert.ok(!swiftMultilineStringLet(specimen, 'notice').includes('plain'));
  });

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

  // ── W-C's parsers ─────────────────────────────────────────────────────────────────────────

  it('slices one markdown section and stops at the next heading of its level', () => {
    const specimen = [
      '#### 03 · Tree profile',
      'Gradient: `radial(28% 46%, #4E8F6A 0→36%)`,',
      'base `linear-gradient(180deg,#EAF0E2 0%,#CFE0D2 55%,#9DBFA6 100%)`.',
      '##### A deeper heading, which is INSIDE the section',
      'still 03',
      '#### 04 · Visit',
      'Gradient: `radial(99% 99%, #000000 0→99%)`,',
      'base `linear-gradient(180deg,#111111 0%,#222222 100%)`.',
    ].join('\n');
    const three = markdownSection(specimen, '#### 03 · Tree profile');
    assert.ok(three.includes('28% 46%'));
    assert.ok(three.includes('still 03'), 'a deeper heading must not end the section');
    // The near miss the whole bounding exists for: an unbounded slice answers 04's question with
    // 03's gradient and looks entirely reasonable doing it.
    assert.ok(!three.includes('99% 99%'), 'the slice ran into the next screen');
    assert.throws(() => markdownSection(specimen, '#### 99 · Nothing'), ParseFailure);
  });

  it('reads a hero gradient stack out of a section, and not the thumbs below it', () => {
    const specimen = [
      '1. **Hero**. Gradient:',
      '   `radial(28% 46%, #4E8F6A 0→36%)`, `radial(54% 32%, #35704F 0→42%)`,',
      '   base `linear-gradient(180deg,#EAF0E2 0%,#CFE0D2 55%,#9DBFA6 100%)`.',
      '   Scrim `rgba(16,32,22,0)→.5` from 48%.',
      '2. Activity thumb — `radial(40% 40%, #4E8F6A 0→50%)` over something else.',
    ].join('\n');
    const recipe = markdownGradientRecipe(specimen);
    // Two, not three: the activity thumb sits after the base and belongs to another element.
    assert.equal(recipe.radials.length, 2);
    assert.deepEqual(recipe.radials[0], {
      x: 0.28, y: 0.46, color: { rgb: 0x4e8f6a, alpha: 1 }, extent: 0.36,
    });
    assert.equal(recipe.base.degrees, 180);
    assert.deepEqual(recipe.base.stops.map((stop) => stop.position), [0, 0.55, 1]);
    assert.deepEqual(markdownScrim(specimen), { rgb: 0x102016, from: 0.48, to: 0.5 });
  });

  it('reads an rgba layer and a base with no stated stop positions', () => {
    const specimen = [
      '   - Base: `radial(34% 44%, rgba(78,143,106,.5) 0→40%)`,',
      '     `linear-gradient(170deg,#E4EBD8,#B9CDBC)`.',
    ].join('\n');
    const recipe = markdownGradientRecipe(specimen);
    assert.deepEqual(recipe.radials[0]?.color, { rgb: 0x4e8f6a, alpha: 0.5 });
    // CSS puts an unpositioned two-stop base at 0 and 1. Derived, not defaulted to 0 — a default
    // would put both stops in the same place and still parse.
    assert.deepEqual(recipe.base.stops.map((stop) => stop.position), [0, 1]);
    assert.throws(() => markdownGradientRecipe('nothing here'), ParseFailure);
    assert.throws(() => markdownScrim('nothing here'), ParseFailure);
  });

  it('reads a CypressGradientRecipe out of Swift, in both of its linear forms', () => {
    const specimen = [
      '    static let heroX = CypressGradientRecipe(',
      '        base: linear(180, [(0xEAF0E2, 0), (0xCFE0D2, 0.55), (0x9DBFA6, 1)]),',
      '        radials: [',
      '            CypressRadialStop(0.28, 0.46, hex(0x4E8F6A), 0.36),',
      '            CypressRadialStop(0.54, 0.32, hex(0x35704F, 0.6), 0.42),',
      '        ]',
      '    )',
      '    static let thumbX = CypressGradientRecipe(',
      '        base: CypressGradient.linear(170, 0xE4EBD8, 0xB9CDBC),',
      '        radials: [CypressRadialStop(0.40, 0.40, CypressGradient.hex(0x4E8F6A), 0.50)]',
      '    )',
    ].join('\n');
    const hero = swiftGradientRecipe(specimen, 'heroX');
    assert.equal(hero.radials.length, 2, 'the parser reached into the second recipe, or missed one');
    assert.deepEqual(hero.radials[1]?.color, { rgb: 0x35704f, alpha: 0.6 });
    assert.deepEqual(hero.base.stops.map((stop) => stop.position), [0, 0.55, 1]);

    const thumb = swiftGradientRecipe(specimen, 'thumbX');
    assert.equal(thumb.radials.length, 1);
    assert.deepEqual(thumb.base.stops.map((stop) => stop.color.rgb), [0xe4ebd8, 0xb9cdbc]);
    assert.throws(() => swiftGradientRecipe(specimen, 'absentX'), ParseFailure);
  });

  it('reads a string constant, and is not fooled by one quoted in a comment', () => {
    const specimen = [
      '    /// It used to read `static let header = "What San Francisco has on file"`.',
      '    static let header = "What the city has on file"',
      '    static let plotWidthSuffix = " ft wide"',
    ].join('\n');
    assert.equal(swiftStringLet(specimen, 'header'), 'What the city has on file');
    assert.equal(swiftStringLet(specimen, 'plotWidthSuffix'), ' ft wide');
    assert.throws(() => swiftStringLet(specimen, 'absent'), ParseFailure);
  });

  it('reads a Set<String> across however many lines it is written on', () => {
    const specimen = [
      '    static let markers: Set<String> = [',
      '        "n/a", "n.a.", "na",',
      '        "not applicable",',
      '    ]',
      '    static let other: Set<String> = ["x"]',
    ].join('\n');
    assert.deepEqual(swiftStringSetLet(specimen, 'markers'), ['n/a', 'n.a.', 'na', 'not applicable']);
    assert.deepEqual(swiftStringSetLet(specimen, 'other'), ['x']);
    assert.throws(() => swiftStringSetLet(specimen, 'absent'), ParseFailure);
  });

  it('reads the switch inside a closure, scoped to the one the marker names', () => {
    const specimen = [
      '        SegmentedControl(',
      '            options: [.alive, .declining],',
      '            selection: selection,',
      '            label: { status in',
      '                switch status {',
      '                case .alive: return "Alive"',
      '                case .vacantSite: return "Vacant site"',
      '                }',
      '            }',
      '        )',
      '    }',
      '}',
      'extension Other {',
      '    label: { method in',
      '        switch method {',
      '        case .tape: return "Tape"',
      '        }',
      '    }',
    ].join('\n');
    const labels = swiftClosureStringCases(specimen, 'options: [.alive, .declining],');
    // `vacantSite` is in the switch and not in the options, which is the case the real file has
    // and the one a parser that stopped at the options would drop.
    assert.deepEqual([...labels], [['alive', 'Alive'], ['vacantSite', 'Vacant site']]);
    assert.ok(!labels.has('tape'), 'the scan ran on into a second closure');
    assert.throws(() => swiftClosureStringCases(specimen, 'absent'), ParseFailure);
  });
});

/**
 * The tripwire's instrument, calibrated the same way every other parser on this page is.
 *
 * `swiftDeclaration` is the only parser here that reads a WHOLE declaration rather than a value
 * out of one, and it is the only one whose output is a hash — which means a broken version of it
 * fails in a way nobody can read. Two properties have to hold and both are asserted against
 * specimens whose answers were known before the parser saw them:
 *
 *   * it is INSENSITIVE to the things a fingerprint must not trip on (comments, indentation,
 *     line breaks), or every reflowed doc comment cries wolf until somebody stops reading it;
 *   * it is SENSITIVE to the things it exists to catch — the two exact edits PR #173's reviewer
 *     made to the real Swift are reproduced here in miniature, so this file proves the wire is
 *     live without needing the real Swift to be mutated.
 */
describe('the whole-declaration fingerprint', () => {
  const specimen = [
    'struct Sample {',
    '    /// A doc comment.',
    '    public func snap(_ x: Double) -> Double {',
    '        let step = 111_320.0   // a trailing comment',
    '        return (x / step).rounded() * step',
    '    }',
    '',
    '    public var gate: Bool {',
    '        return accuracy <= 15',
    '    }',
    '}',
  ].join('\n');

  it('bounds the declaration at its own closing brace, not the next one down', () => {
    const snap = swiftDeclaration(specimen, 'public func snap(_ x: Double) -> Double');
    // `gate` is the declaration BELOW. A parser that ran to the struct's closing brace would
    // swallow it, and would then report the same fingerprint for a file that had reordered two
    // functions — or a different one for a change in a function this row does not name.
    assert.ok(!snap.source.includes('gate'), `the body ran past its own brace: ${snap.source}`);
    assert.ok(snap.source.endsWith('}'));
    assert.equal(
      snap.normalized,
      'public func snap(_ x: Double) -> Double { let step = 111_320.0 return (x / step).rounded() '
        + '* step }',
    );
  });

  it('closes over nested braces rather than the first one it meets', () => {
    const closure = [
      'public func split(kind: Kind) -> [Row] {',
      '    let points = filter { $0.kind == kind }',
      '    return points',
      '}',
    ].join('\n');
    const found = swiftDeclaration(closure, 'public func split(kind: Kind) -> [Row]');
    assert.ok(found.source.includes('return points'), `stopped at the closure: ${found.source}`);
  });

  it('is blind to comments and to layout, which is what keeps it from crying wolf', () => {
    const reflowed = [
      'struct Sample {',
      '    /// A doc comment, rewritten entirely, now spanning',
      '    /// two lines and saying something else.',
      '    public func snap(_ x: Double) -> Double {',
      '        /* a block comment where a trailing one used to be */',
      '        let step = 111_320.0',
      '            return (x / step).rounded() * step',
      '    }',
      '}',
    ].join('\n');
    assert.equal(
      swiftDeclaration(reflowed, 'public func snap(_ x: Double) -> Double').fingerprint,
      swiftDeclaration(specimen, 'public func snap(_ x: Double) -> Double').fingerprint,
      'reformatting and rewriting comments moved the fingerprint; it would go red on every '
        + 'cosmetic edit and be re-recorded without being read',
    );
  });

  it('does not read a `//` inside a string literal as a comment', () => {
    const withURL = 'public var host: String {\n    return "https://example.org/x"\n}';
    const found = swiftDeclaration(withURL, 'public var host: String');
    assert.ok(
      found.normalized.includes('https://example.org/x'),
      `the URL was eaten as a comment: ${found.normalized}`,
    );
  });

  /**
   * **The sensitivity proof: the two edits from the #173 review, in miniature.**
   *
   * Each changes one character of the specimen and nothing else. If either of these fingerprints
   * came back equal to the baseline, the tripwire in `swiftDrift.test.ts` would be recording a
   * constant and the suite would be green for the same reason it was green before this file
   * existed.
   */
  it('moves when a constant moves, and when a comparison flips', () => {
    const baselineSnap = swiftDeclaration(specimen, 'public func snap(_ x: Double) -> Double');
    const baselineGate = swiftDeclaration(specimen, 'public var gate: Bool');

    const constantMoved = specimen.replace('111_320.0', '111_000.0');
    assert.notEqual(constantMoved, specimen, 'the mutation did not apply; this measures nothing');
    assert.notEqual(
      swiftDeclaration(constantMoved, 'public func snap(_ x: Double) -> Double').fingerprint,
      baselineSnap.fingerprint,
      '111_320 -> 111_000 left the fingerprint unchanged',
    );

    const comparisonFlipped = specimen.replace('accuracy <= 15', 'accuracy < 15');
    assert.notEqual(comparisonFlipped, specimen, 'the mutation did not apply; this measures nothing');
    assert.notEqual(
      swiftDeclaration(comparisonFlipped, 'public var gate: Bool').fingerprint,
      baselineGate.fingerprint,
      '<= -> < left the fingerprint unchanged, which is the exact hole this file closes',
    );
    // And the OTHER declaration in the same file is untouched by either, so a red names the
    // declaration that actually changed rather than everything in the file.
    assert.equal(
      swiftDeclaration(comparisonFlipped, 'public func snap(_ x: Double) -> Double').fingerprint,
      baselineSnap.fingerprint,
    );
  });

  it('refuses an ambiguous signature rather than picking one of two', () => {
    const twoOverloads = [
      'public static func permitted(month: Int) -> Bool { return true }',
      'public static func permitted(month: Int, habit: Habit) -> Bool { return false }',
    ].join('\n');
    // The shared prefix matches both. Taking the first would fingerprint whichever the file
    // happens to list first, and would move for free the day somebody reorders them.
    assert.throws(() => swiftDeclaration(twoOverloads, 'public static func permitted(month: Int'), ParseFailure);
    // Narrowed, it resolves.
    assert.ok(
      swiftDeclaration(twoOverloads, 'public static func permitted(month: Int) -> Bool')
        .normalized.includes('return true'),
    );
  });

  it('refuses a signature that is absent, and one with no balanced body anywhere after it', () => {
    assert.throws(() => swiftDeclaration(specimen, 'public func absent()'), ParseFailure);
    assert.throws(
      () => swiftDeclaration('public static let bare: Double = 25\n', 'public static let bare'),
      ParseFailure,
    );
  });

  /**
   * The other half of that sentence, asserted rather than left to the reader.
   *
   * This test used to be named "…and one with no body after it", which is not what the specimen
   * above proves: the specimen is the LAST thing in its string, so the scan runs off the end. Give
   * the body-less signature a neighbor and the refusal disappears — the scan closes on the
   * neighbor's brace instead (PR #173 delta review, D4).
   *
   * That is written down here, and asserted, because it is a documented behavior and not a bug:
   * the fingerprint then covers MORE text than the row names, so it is strictly more sensitive.
   * If anyone ever tightens the bound to "a body of its own", this assertion goes red and the
   * decision gets read rather than discovered.
   */
  it('fingerprints a body-less signature through to the next declaration when one follows', () => {
    const withNeighbor = 'public func foo() -> Double\n\npublic var bar: Int { return 1 }\n';
    const found = swiftDeclaration(withNeighbor, 'public func foo() -> Double');
    assert.equal(found.normalized, 'public func foo() -> Double public var bar: Int { return 1 }');
  });

  /**
   * Comment-insensitivity at the LOOKUP stage, which is a different claim from the normalizer's.
   *
   * `swiftDrift.test.ts` tells its reader that reflowing or rewriting a doc comment does not trip
   * the wire. It did trip it, before `codeOnly`: the ambiguity count scanned raw text, so a doc
   * comment naming the function it documents made the lookup report `appears more than once in the
   * source — narrow the signature` — advice that cannot be followed, for an edit that changed no
   * code. Demonstrated by PR #173's delta review on the real `Geometry.swift`.
   */
  it('does not count a signature quoted in a comment or a string as a second declaration', () => {
    const quotedInComment = [
      '/// Calls `public func snap(_ x: Double) -> Double` and rounds the result.',
      'public func snap(_ x: Double) -> Double {',
      '    return x',
      '}',
    ].join('\n');
    const found = swiftDeclaration(quotedInComment, 'public func snap(_ x: Double) -> Double');
    assert.equal(found.normalized, 'public func snap(_ x: Double) -> Double { return x }');

    const quotedInString = [
      'public var usage: String {',
      '    return "public func snap(_ x: Double) -> Double"',
      '}',
      'public func snap(_ x: Double) -> Double {',
      '    return x',
      '}',
    ].join('\n');
    assert.equal(
      swiftDeclaration(quotedInString, 'public func snap(_ x: Double) -> Double').normalized,
      'public func snap(_ x: Double) -> Double { return x }',
    );

    // And the blanking does not cost the parser its real ambiguity refusal: two genuine
    // declarations still collide. Without this the fix could have been "never refuse anything".
    const twoReal = [
      'public func snap(_ x: Double) -> Double { return x }',
      'public func snap(_ x: Double) -> Double { return -x }',
    ].join('\n');
    assert.throws(
      () => swiftDeclaration(twoReal, 'public func snap(_ x: Double) -> Double'),
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
      23,
      `the parity checks name ${sourcesTheWebSuiteReads.length} sources, not 23. If a check was `
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

  /**
   * **The census, and the hole it closes.**
   *
   * PR #173's review deleted `src/lib/growthCharting.ts` AND `test/growthCharting.test.ts` and the
   * suite went green at 92 of 92 — with `Cypress/Core/Models/CoreEntity.swift` still in
   * `sourcesTheWebSuiteReads` and still in both of `web.yml`'s `paths:` filters, triggering a
   * workflow for a file nothing read any more. Every assertion above is satisfied by that state:
   * the rule and its only check left together, so nothing was left behind to notice.
   *
   * A count is what notices. `web/src/lib/` is enumerated and compared against a named list, so a
   * module that disappears is red and a module that appears without anybody adding it here is red
   * too. Named rather than counted, because a count of eight is satisfied by deleting one file and
   * adding another.
   */
  it('every module under src/lib is still here, and is still checked by a test', () => {
    const lib = join(repositoryRoot(), 'web', 'src', 'lib');
    const onDisk = readdirSync(lib)
      .filter((entry) => statSync(join(lib, entry)).isFile() && entry.endsWith('.ts'))
      .sort();
    assert.deepEqual(
      onDisk,
      [
        'cityRecord.ts',
        'geometry.ts',
        'gradients.ts',
        'growthCharting.ts',
        'idSpaces.ts',
        'measuredValue.ts',
        'obligations.ts',
        'ogCard.ts',
        'ogRaster.ts',
        'packLibrary.ts',
        'publicTreeRead.ts',
        'quantity.ts',
        'spelling.ts',
        'tokens.ts',
        'toolchain.ts',
        'treePage.ts',
        'vitality.ts',
      ],
      'web/src/lib no longer holds the modules this suite was built around. A module that left '
        + 'took its test with it and nothing else here would have said so; a module that arrived '
        + 'has no parity check until somebody writes one. Whichever it is, the list belongs in '
        + 'this assertion in the same change.',
    );
    // And each has a test file that imports it. A module kept with its test deleted is the same
    // hole one file further along.
    for (const module of onDisk) {
      const name = module.replace(/\.ts$/, '');
      const testPath = join(repositoryRoot(), 'web', 'test', `${name}.test.ts`);
      const text = readFileSync(testPath, 'utf8');
      assert.ok(
        text.includes(`../src/lib/${module}`),
        `web/test/${name}.test.ts exists but does not import ../src/lib/${module}, so the module `
          + `is unchecked despite having a test file named for it`,
      );
    }
  });
});
