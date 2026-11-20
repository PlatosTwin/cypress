/**
 * The tripwire on the Swift the ports were derived FROM.
 *
 * ── What was wrong, and why this file exists ─────────────────────────────────────────────────
 *
 * `test/support/swift-reference.json` is a RECORDING. The real `Quantity.swift`,
 * `Geometry.swift` and `CoreEntity.swift` were compiled unmodified, once, on a machine with a
 * Swift toolchain, and what they printed was checked in. Every parity assertion in
 * `geometry.test.ts`, `quantity.test.ts` and `growthCharting.test.ts` compares the TypeScript
 * against that recording.
 *
 * A recording does not move when its subject does. PR #173's reviewer proved the consequence with
 * two one-character edits to the real Swift, each of which left the whole suite green while the
 * two implementations genuinely disagreed:
 *
 *   * `Geometry.swift`, `let metersPerDegreeLat = 111_320.0` → `111_000.0`. Swift and the port
 *     then snapped the same coordinate **8.2 m apart in latitude**. `103 of 103 tests passed`.
 *   * `CoreEntity.swift`, `gpsAccuracyM <= GPSAccuracy.growthChartingLimitM` → `<`. That is the
 *     exact D6 boundary `growthCharting.test.ts` says it exists to prevent, and that test pins
 *     the NUMBER 15 three times and never the comparison. `103 of 103 tests passed`.
 *
 * Neither is reachable by the value parsers in `support/sources.ts`: `metersPerDegreeLat` is an
 * un-annotated function-local `let` that `swiftDoubleLet` declines by design, and a comparison
 * operator is not a value at all. And #173 made the situation worse before it made it better, by
 * adding those Swift files to `web.yml`'s `paths:` — so an edit like either one now RUNS this
 * suite and collects a green, which reads as evidence.
 *
 * ── What this file does, scoped honestly ─────────────────────────────────────────────────────
 *
 * It fingerprints Swift declarations — signature through closing brace, comments dropped,
 * whitespace collapsed — and asserts each fingerprint is the one recorded below. WHICH
 * declarations, and why those, is set out under "Which declarations are in the table" below; the
 * short version is the ones a port reproduces the body of and no value parser reads. It is a
 * TRIPWIRE, and the whole of what it proves is:
 *
 *   **this Swift has not been edited since these fingerprints were recorded.**
 *
 * It does NOT prove the TypeScript agrees with the Swift. Nothing in this suite can, because the
 * suite has no Swift toolchain of its own; the recording is what stands in for that, and this file
 * exists to make sure the recording is still a recording OF something rather than a fossil. So the
 * guard as a whole is: **TypeScript against a recorded snapshot, plus a tripwire on the Swift
 * source that snapshot came from.** Both halves are needed and neither is the other.
 *
 * It also cannot tell a behavioral edit from a cosmetic one. Renaming a local, reflowing a body
 * past the collapsing this normalizes away, adding a parameter — all go red. That is deliberate.
 * A red here is not "the Swift is wrong", it is "a human has to look", and looking is the step
 * that was missing.
 *
 * ── Which declarations are in the table, and why the rest are not ────────────────────────────
 *
 * **The rule: a Swift declaration is listed below when something in `web/src/lib/` reproduces its
 * BODY, and no value parser already reads that body.** Both halves matter. The first is what makes
 * the table a statement about the ports rather than a sample of the Swift; the second is what keeps
 * it from becoming a second, more brittle copy of a check that already bites.
 *
 * The rule is stated because the first version of this table failed the first half of it and said
 * otherwise. It listed eleven declarations and called them "the declarations the ports
 * re-implement"; `Quantity.series` and the `Codable` wire contract were missing, and the guard on
 * the table counted rows rather than naming them, so nothing noticed. PR #173's delta review
 * mutated both to a green suite (D2). `quantity.ts` had said all along, in these words, that it
 * reproduces `Quantity.init(from:)`. The count was true and the claim around it was not.
 *
 * So, what is OUT, each with the reason:
 *
 *   * **The enum cases and switch tables `quantity.test.ts` and `vitality.test.ts` parse by
 *     VALUE** — `LengthUnit.metersPerUnit`, `isMetric`, `MeasurementMethod.series`,
 *     `MeasurementKind.plausibleSIRange`, `Vitality`'s raw values, `label`, `anchor`, and the
 *     ORDER of `Vitality.rubric`. Those tests read the live Swift and compare the values
 *     themselves, which is strictly better than a hash: they say WHICH entry moved. Note the
 *     distinction this draws, because it is the one the first table got wrong —
 *     `MeasurementMethod.series` is read by value and is out; `Quantity.series`, the one-line
 *     delegation to it, is read by nothing and is IN.
 *   * **`Quantity.encode(to:)`.** Nothing in `web/src/lib/` writes this wire — `quantity.ts`
 *     exports `quantityFromJSON` and no encoder — and the key names an encoder would write come
 *     from `CodingKeys`, which IS in the table. If the web ever gains a writer, this row is owed.
 *   * **`TreeMeasurement.series` and `TreeMeasurement.isPlausible`.** Both are one-line
 *     compositions, and the port composes neither: `growthCharting.ts`'s `ChartablePoint` takes
 *     `series` as a field the caller supplies rather than deriving it, and `quantity.ts` exports
 *     `isPlausible` and `plausibleSIRange` separately with nothing pairing them. What the port
 *     does reproduce — the two halves — is covered above and below.
 *   * **`Double.rounded()`**, which `geometry.ts`'s `roundedAwayFromZero` reproduces. It is
 *     stdlib, not a declaration in this repository, and its behavior is recorded by measurement in
 *     `swift-reference.json`'s `rounded` rows, which `geometry.test.ts` asserts against.
 *   * **Swift the ports do not touch at all**: `Species.swift`'s data, anything in `Data` or
 *     `Features`.
 *   * **The Python.** `inventory_contract.py`'s prefixes are parsed by value; its inventory NAMES
 *     and URLs are still an unguarded transcription (#173 review, N4) and this file does not
 *     change that.
 *
 * ── Two kinds of row, added by W-C ───────────────────────────────────────────────────────────
 *
 * Everything above describes the ARITHMETIC rows, which are the whole of what this file covered
 * until the public tree page was built. W-C added four more, marked `kind: 'copy'`, and they are
 * different in one way that matters to whoever reads a red: they are `Features` declarations that
 * decide what a screen SAYS — a non-value filter, a range format, a record number, a provenance
 * sentence — and `swift-reference.json` does not cover them, because the recorder compiles `Core`
 * and they are not in it. So the repair for a copy row is to reconcile `src/lib/cityRecord.ts`
 * with the diff, not to re-record anything, and the failure message says so per row rather than
 * telling every reader to run a command that would not help half of them.
 *
 * They are here rather than in a table of their own because the membership rule below is a rule
 * about `web/src/lib/` and says nothing about the recording. A second table would have made this
 * one's own completeness assertion — "every Swift file whose arithmetic the ports reproduce" —
 * quietly false, which is the shape of defect that rule was written after.
 *
 * ── When this goes red ───────────────────────────────────────────────────────────────────────
 *
 * Read the diff on the named Swift declaration and decide which it is:
 *
 *   1. **Behavior changed.** Re-record `swift-reference.json` by running the command in
 *      `support/swift-reference/main.swift`, re-run the suite so the ports are re-checked against
 *      the NEW Swift, fix whatever that turns red, and only then paste the new fingerprint here.
 *   2. **Cosmetic only.** Paste the new fingerprint here and say in the commit message why you
 *      believe it is cosmetic. Re-recording the reference costs six seconds and is cheap insurance
 *      even then.
 *
 * Both paths are deliberate acts by a human who read a diff, which is the entire point.
 *
 * ── Why not just run the Swift in CI? ────────────────────────────────────────────────────────
 *
 * Because it was not tried here, and a guard nobody has watched run is not a guard. The premise
 * that it is impossible is FALSE and worth writing down: `ubuntu-latest` is Ubuntu 24.04, whose
 * runner image ships **Swift 6.3.3** (`actions/runner-images`, `images/ubuntu/Ubuntu2404-Readme.md`,
 * "Language and Runtime"). `Core` is pure Foundation by ARCHITECTURE §2, so the four files
 * `main.swift` compiles plausibly build on Linux.
 *
 * What stops it being this PR's fix is a measurement nobody has taken: the recording is Darwin
 * output, and glibc's `cos`, `atan2` and `sqrt` are not required to agree with Darwin's to the
 * bit, so a Linux re-run diffed byte-for-byte against `swift-reference.json` may well fail for a
 * reason that is not drift. That is answerable — with the same tolerance machinery
 * `geometry.test.ts` already uses — and it is a round of its own, on a runner, watched. Reported to
 * the orchestrator rather than guessed at here. Until that round happens this tripwire is
 * toolchain-free, runs everywhere the suite runs, and catches both mutations above in under a
 * millisecond.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { repoFile, swiftDeclaration } from './support/sources.ts';

interface Region {
  /** How a human refers to it. Appears in the failure message and nowhere else. */
  readonly name: string;
  /** Which file, relative to the repository root. */
  readonly file: string;
  /**
   * An exact substring of the declaration's signature, unique in that file.
   *
   * `swiftDeclaration` REFUSES a signature that matches twice rather than taking the first, so a
   * shared prefix (`public static func isRatingPermitted(`, which has two overloads) has to be
   * narrowed until it names one declaration. The narrowing is sometimes a trailing newline; that
   * makes the lookup itself sensitive to reformatting, which fails as a `ParseFailure` naming the
   * signature rather than as a fingerprint mismatch. Both are red and the message says which.
   */
  readonly signature: string;
  /**
   * An enclosing declaration to look inside first, when the signature is only unique within one
   * type.
   *
   * `Quantity.series` and `MeasurementMethod.series` are both `public var series:
   * MeasurementSeries` and both live in `Quantity.swift`, so the bare signature is refused as
   * ambiguous — correctly. The alternative was to narrow by pasting body text into the signature
   * (`… { method.series }`), which would turn the very mutation this row exists to catch into a
   * "signature not found" rather than a fingerprint mismatch. Scoping instead keeps the signature
   * free of the body, so a body edit reports as what it is.
   *
   * Resolved with `swiftDeclaration` itself, so an edit to the enclosing declaration's own header
   * is refused by the same rules rather than silently widening the search.
   */
  readonly within?: string;
  /**
   * Which guard this row belongs to, because there are now two and they go red for different
   * reasons.
   *
   * `arithmetic` — the original set. `test/support/swift-reference.json` is a recording of what
   * these declarations PRINT, every parity assertion compares a port against that recording, and a
   * red here means the recording may no longer describe its subject. The repair begins with
   * re-recording.
   *
   * `copy` — added by W-C. `src/lib/cityRecord.ts` re-implements four small declarations that
   * decide what the public tree page SAYS: a non-value filter, a range format, a record number and
   * a provenance sentence. Nothing about them is in `swift-reference.json` — they are `Features`
   * code, print nothing, and the recorder does not compile that target — so "re-record the
   * reference" is not the repair and telling a reader to do it would send them somewhere useless.
   * The repair is to read the diff and reconcile `cityRecord.ts` with it, which
   * `test/cityRecord.test.ts` checks by value for everything a value parser can reach.
   *
   * They are in THIS table rather than in a second one because the membership rule below is a
   * rule about `web/src/lib/`, not about the recording, and a table that silently meant "the
   * arithmetic ones" while stating the general rule is exactly the defect PR #173's delta review
   * found in its first version.
   */
  readonly kind: 'arithmetic' | 'copy';
  /**
   * The module under `web/src/lib/` that reproduces this declaration, when it is not the one every
   * `copy` row belonged to when the kind was introduced.
   *
   * The `copy` failure message names a module and tells a reader to reconcile it. Every row in the
   * first `copy` set was `cityRecord.ts`'s, and the message said so as a literal — which stopped
   * being true the moment a second module ported something. Naming it per row is what keeps the
   * advice followable; the fallback is the module the original set belongs to.
   */
  readonly port?: string;
  /** `sha256` of the normalized declaration, recorded at PR #173 and re-recorded deliberately. */
  readonly fingerprint: string;
}

/**
 * The Swift the ports re-implement, declaration by declaration, under the membership rule in the
 * file header. `swiftDrift.test.ts`'s own last test names this set, so a row that goes missing is
 * red rather than merely uncounted.
 *
 * Recorded 2026-09-10 against `origin/main` merged into `web/domain-rules`, on the same machine
 * and in the same sitting as the `swift-reference.json` regeneration — the reference was
 * reproduced byte-identically from unmodified Swift first, so these fingerprints and that
 * recording describe the same source.
 */
const REGIONS: readonly Region[] = [
  {
    name: 'Coordinate.distance(to:)',
    file: 'Cypress/Core/Models/Geometry.swift',
    signature: 'public func distance(to other: Coordinate) -> Double',
    kind: 'arithmetic',
    fingerprint: '5b7d6b964bae6aaf33a317cdf190f90a06677977d5d5cae76339254a6f18cb8f',
  },
  {
    name: 'Coordinate.snappedToPublicPhotoGrid()',
    file: 'Cypress/Core/Models/Geometry.swift',
    signature: 'public func snappedToPublicPhotoGrid() -> Coordinate',
    kind: 'arithmetic',
    fingerprint: '56c4e1f3086aff301e952a2ebb72add230eae51eea938402c7d3a0466a5074bb',
  },
  {
    name: 'FieldCaptured.isEligibleForGrowthCharting',
    file: 'Cypress/Core/Models/CoreEntity.swift',
    signature: 'public var isEligibleForGrowthCharting: Bool',
    kind: 'arithmetic',
    fingerprint: '4068764cdc3b9f7a5a6dc1034d83e21266d9271996355740a57679150464c88a',
  },
  {
    name: 'Quantity.init(value:unit:method:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public init(value: Double, unit: LengthUnit, method: MeasurementMethod)',
    kind: 'arithmetic',
    fingerprint: '72b4d2e5f1fdc76834606f6e382d4c244819c72fd0a0bed6418b3e2d0102ae9d',
  },
  {
    name: 'Quantity.converted(to:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public func converted(to unit: LengthUnit) -> Double',
    kind: 'arithmetic',
    fingerprint: 'b49424910d6dd22cb1864586c24301482eca8c10ad93ec3943d7c2b0ec983a89',
  },
  {
    name: 'Quantity.isPlausible(within:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public func isPlausible(within range: ClosedRange<Double>) -> Bool',
    kind: 'arithmetic',
    fingerprint: 'c35e1cdd1c8a7c1ab6a9934a39c0e218230381edfb295c64f63befe0d8f8d627',
  },
  {
    // `quantity.ts:seriesOfQuantity`. NOT the same declaration as `MeasurementMethod.series`,
    // which `quantity.test.ts` reads by value as a switch table: this is the one-line DELEGATION
    // to it, and the delegation is what `swift-reference.json` records in each quantity row's
    // `"series"`. Changing it to `{ .measured }` put every `estimate` measurement in a different
    // series in Swift than in the port and left the suite at `124 of 124` (#173 delta review, D2a).
    name: 'Quantity.series',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public var series: MeasurementSeries',
    within: 'public struct Quantity: Hashable, Codable, Sendable',
    kind: 'arithmetic',
    fingerprint: '5aa83df437d9b9e8d93dda520b9799bca70cc06cc9ea75c903c124f54a3462f0',
  },
  {
    // The wire contract `quantity.ts:quantityFromJSON` reads, and the one #172's pack read layer
    // meets a stored row through. These three case names ARE the JSON keys; giving one a raw value
    // (`unitEntered = "unit_entered"`) renames a key the port still looks for under the old name,
    // and left the suite at `124 of 124` (#173 delta review, D2b).
    name: 'Quantity.CodingKeys',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'private enum CodingKeys: String, CodingKey',
    kind: 'arithmetic',
    fingerprint: 'bb63b32f685a0f96882cb6aef922991a1d3e990a1e077fd6f00853eef3c0553b',
  },
  {
    // `quantity.ts:quantityFromJSON`, which the file says in these words: "This is
    // `Quantity.init(from:)` in the Swift." The rule that travels with it is that `siValue` is
    // RE-DERIVED rather than read, so a persisted row disagreeing with itself resolves to the
    // entered value. A decoder that started trusting a stored `siValue` would diverge silently.
    name: 'Quantity.init(from:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public init(from decoder: Decoder) throws',
    kind: 'arithmetic',
    fingerprint: '805cce04d4197ddd53a649de307eab1d3cf2c8e79b8bc0ed85355c284bf745a1',
  },
  {
    // `growthCharting.ts:isDeleted`, whose doc comment names it: "`SoftDeletable.isDeleted`
    // inverted". The port's `isChartable` is built out of it, where the Swift's `isChartable`
    // spells `deletedAt == nil` inline — so the two agree only as long as this one line does.
    name: 'SoftDeletable.isDeleted',
    file: 'Cypress/Core/Models/CoreEntity.swift',
    signature: 'public var isDeleted: Bool',
    kind: 'arithmetic',
    fingerprint: 'ce4adf18729163b740bbdb609ba51ce9cb0962628b7faf51b79a9462f63e928a',
  },
  {
    // `vitality.ts:classNumberOf`. Same shape as `Quantity.series`: the RAW VALUES are read by
    // value (`swiftEnumCases`, asserted in `vitality.test.ts`), and this delegation to them is
    // not. `{ rawValue + 1 }` would store a different integer in `observations.vitality` than the
    // web reads back, with every value assertion still green.
    name: 'Vitality.classNumber',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    signature: 'public var classNumber: Int',
    kind: 'arithmetic',
    fingerprint: '9e3af4c1021fa3d9931fa078645fa090e5b3d219eca41c7780ad086e08758198',
  },
  {
    name: 'TreeMeasurement.isChartable',
    file: 'Cypress/Core/Models/TreeMeasurement.swift',
    signature: 'public var isChartable: Bool',
    kind: 'arithmetic',
    fingerprint: 'e84e18caa51130f74172b79f38407646941b9073ae2ce3d2aaabaa8606b7a83f',
  },
  {
    name: 'Collection.splitBySeries(kind:)',
    file: 'Cypress/Core/Models/TreeMeasurement.swift',
    signature: 'public func splitBySeries(kind: MeasurementKind)',
    kind: 'arithmetic',
    fingerprint: '267478f351ffe7d50e1b79223540d7d063162b2b3c00f9ddf5263f9065af26d9',
  },
  {
    name: 'Vitality.isRatingPermitted(leafRetention:month:leafOnMonths:)',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    // The newline narrows this away from the `(for species:…)` overload below.
    signature: 'public static func isRatingPermitted(\n',
    kind: 'arithmetic',
    fingerprint: '2327ada371667a4afdba9a12cae8e97b06381c75ddd57788e656f540f3d6c41a',
  },
  {
    name: 'Vitality.isRatingPermitted(for:month:)',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    signature: 'public static func isRatingPermitted(for species: Species, month: Int) -> Bool',
    kind: 'arithmetic',
    fingerprint: '3b21c518e79b24c9a25ed64ccc2636e556f4ab8a638992028863205026b96d40',
  },
  {
    name: 'Vitality.suppression(for:month:)',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    signature: 'public static func suppression(for species: Species, month: Int) -> Suppression',
    kind: 'arithmetic',
    fingerprint: 'd064eb4643fc222bdf5fa811e19a528f4fc12b4c11b9a675bf17a2769ad4baf0',
  },
  {
    name: 'CityRecordPresentation.statedValue(_:)',
    file: 'Cypress/Features/TreeProfile/CityRecordPresentation.swift',
    signature: 'static func statedValue(_ raw: String) -> String?',
    kind: 'copy',
    fingerprint: '34fb7572d2428b3c4a362e82c8909a55be16397ea23ec9b07b5c04a329adfd6e',
  },
  {
    name: 'CityRecordCopy.recordNumber(_:)',
    file: 'Cypress/Features/TreeProfile/CityRecordPresentation.swift',
    signature: 'static func recordNumber(_ ref: String) -> String',
    kind: 'copy',
    fingerprint: '90de64124d3eb3c91afff2e47222cc3956ca8589d7f9260899b2d3f5ca0db8c5',
  },
  {
    name: 'CityRecordCopy.provenanceNote(source:snapshot:)',
    file: 'Cypress/Features/TreeProfile/CityRecordPresentation.swift',
    signature: 'static func provenanceNote(source: String, snapshot: String) -> String',
    kind: 'copy',
    fingerprint: '23eb2a21da6fe5b46004d7cd09bc75b6262e4833b6f72ef92ad3f20804e3d405',
  },
  {
    name: 'TreeProfilePresentation.cityDBHRangeText',
    file: 'Cypress/Features/TreeProfile/TreeProfilePresentation.swift',
    signature: 'var cityDBHRangeText: String?',
    kind: 'copy',
    fingerprint: '2ef73a5258ba64cf7333cb71957759a8ee42cd02c22172c94d48743ee3c62564',
  },
  // ── The community half. `src/lib/measuredValue.ts` reproduces these two bodies ────────────
  //
  // `MethodBadge.label` and `.accessibilityLabel` are NOT here: `measuredValue.test.ts` reads both
  // out of the Swift with a value parser, and the membership rule excludes a body a value parser
  // already reaches. These two are format rules rather than values — one string interpolation and
  // one ternary over `rounded()` — and no parser here can read either.
  //
  // Recorded 2026-09-11 against `web/w1-tree-page` at 295d107, from unmodified Swift.
  {
    name: 'MeasuredValue.formatted(_:)',
    file: 'Cypress/DesignSystem/Components/MethodBadge.swift',
    signature: 'static func formatted(_ quantity: Quantity) -> String',
    kind: 'copy',
    port: 'web/src/lib/measuredValue.ts',
    fingerprint: '477c396904e544f274c8dac41eeb7558de14e7213467428415021175e459d3ba',
  },
  {
    name: 'MeasuredValue.number(_:)',
    file: 'Cypress/DesignSystem/Components/MethodBadge.swift',
    signature: 'static func number(_ value: Double) -> String',
    kind: 'copy',
    port: 'web/src/lib/measuredValue.ts',
    fingerprint: 'aba885894452d7d3306daf75fb9ac782f2bd52129d9ac56792762ef11b338288',
  },
];

describe('the Swift the ports were derived from has not moved under them', () => {
  for (const region of REGIONS) {
    const what = region.kind === 'arithmetic'
      ? 'is the declaration the reference was recorded from'
      : 'still says what cityRecord.ts says it says';
    it(`${region.name} ${what}`, () => {
      const whole = repoFile(region.file);
      const scope = region.within === undefined
        ? whole
        : swiftDeclaration(whole, region.within).source;
      const found = swiftDeclaration(scope, region.signature);
      assert.equal(
        found.fingerprint,
        region.fingerprint,
        `${region.file} — ${region.name} has been edited since its fingerprint was recorded.\n\n`
          + `  recorded  ${region.fingerprint}\n`
          + `  now       ${found.fingerprint}\n\n`
          + `  the declaration as it reads today, normalized:\n`
          + `  ${found.normalized}\n\n`
          + `THIS IS NOT A FAILURE OF THE TYPESCRIPT. `
          + (region.kind === 'arithmetic'
            ? `It means test/support/swift-reference.json — a RECORDING of what this Swift `
              + `printed — may no longer describe this Swift, and every parity assertion in this `
              + `directory compares the port against that recording. Read the diff. If the `
              + `behavior changed: regenerate the reference (the command is in `
              + `test/support/swift-reference/main.swift), re-run the whole suite so the ports are `
              + `re-checked against the new Swift, fix what that turns red, and only then paste `
              + `the fingerprint above into test/swiftDrift.test.ts. If the edit is cosmetic: `
              + `paste it and say why in the commit message.`
            : `This declaration decides what the public tree page SAYS, and `
              + `${region.port ?? 'web/src/lib/cityRecord.ts'} re-implements it. It is NOT in `
              + `swift-reference.json — that recording covers Core only — so re-recording is not `
              + `the repair here. Read the diff, reconcile that module with it, run its test `
              + `(which checks by value everything a value parser can reach), and then paste the `
              + `fingerprint above. If the edit is cosmetic: paste it and say why in the commit `
              + `message.`),
      );
    });
  }

  /**
   * The table's own provenance, so it cannot shrink quietly.
   *
   * A loop over an empty array passes, and a loop over a table somebody deleted two rows from
   * passes just as cleanly. Counted, and named by file, for the same reason the spelling sweep
   * asserts it can see the files it claims to check.
   */
  it('the table still covers every Swift file whose arithmetic the ports reproduce', () => {
    assert.equal(
      REGIONS.length,
      22,
      `the tripwire lists ${REGIONS.length} declarations, not 22. A row that disappears takes its `
        + `guard with it and nothing else notices.`,
    );
    assert.deepEqual(
      [...new Set(REGIONS.map((r) => r.file))].sort(),
      [
        'Cypress/Core/Models/CoreEntity.swift',
        'Cypress/Core/Models/Geometry.swift',
        'Cypress/Core/Models/TreeMeasurement.swift',
        'Cypress/Core/Rubric/Vitality.swift',
        'Cypress/Core/Units/Quantity.swift',
        'Cypress/DesignSystem/Components/MethodBadge.swift',
        'Cypress/Features/TreeProfile/CityRecordPresentation.swift',
        'Cypress/Features/TreeProfile/TreeProfilePresentation.swift',
      ],
      'the tripwire no longer reaches one of the eight Swift files the ports re-implement',
    );
    // Every fingerprint distinct: a copy-paste that repeated one row's hash into another's would
    // pin two declarations to the same text and pass only by coincidence.
    assert.equal(
      new Set(REGIONS.map((r) => r.fingerprint)).size,
      REGIONS.length,
      'two rows of the tripwire carry the same fingerprint, which means one of them was pasted '
        + 'over the other',
    );
  });

  /**
   * The set itself, named.
   *
   * A count is what let the previous version of this table be wrong while looking right: `11` was
   * a true count of a set that was missing `Quantity.series` and the `Codable` wire contract, and
   * the header, `web/README.md` and `main.swift` all called that set "the declarations the ports
   * re-implement" (#173 delta review, D2). A count cannot notice an omission; a list can.
   *
   * So the rule for this table is written down and the membership is asserted against it. **A
   * Swift declaration belongs here when something in `web/src/lib/` reproduces its body, and no
   * value parser already reads that body.** Adding a port function without adding its row turns
   * this red, which is the moment to decide rather than the moment to discover.
   */
  it('names the declarations it covers, so an omission is red rather than silent', () => {
    assert.deepEqual(
      REGIONS.map((r) => r.name).sort(),
      [
        'CityRecordCopy.provenanceNote(source:snapshot:)',
        'CityRecordCopy.recordNumber(_:)',
        'CityRecordPresentation.statedValue(_:)',
        'Collection.splitBySeries(kind:)',
        'Coordinate.distance(to:)',
        'Coordinate.snappedToPublicPhotoGrid()',
        'FieldCaptured.isEligibleForGrowthCharting',
        'MeasuredValue.formatted(_:)',
        'MeasuredValue.number(_:)',
        'Quantity.CodingKeys',
        'Quantity.converted(to:)',
        'Quantity.init(from:)',
        'Quantity.init(value:unit:method:)',
        'Quantity.isPlausible(within:)',
        'Quantity.series',
        'SoftDeletable.isDeleted',
        'TreeMeasurement.isChartable',
        'TreeProfilePresentation.cityDBHRangeText',
        'Vitality.classNumber',
        'Vitality.isRatingPermitted(for:month:)',
        'Vitality.isRatingPermitted(leafRetention:month:leafOnMonths:)',
        'Vitality.suppression(for:month:)',
      ],
      'the set of fingerprinted declarations changed. If a port gained a re-implementation, this '
        + 'is where it gets acknowledged; if one left, say so here too. Do not widen this list to '
        + 'match whatever the table happens to hold — the header above states which declarations '
        + 'belong and why the rest are out, and that paragraph is the thing to reconcile against.',
    );
  });
});
