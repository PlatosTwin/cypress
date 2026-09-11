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
 * It fingerprints the exact Swift declarations the ports re-implement — signature through closing
 * brace, comments dropped, whitespace collapsed — and asserts each fingerprint is the one recorded
 * below. It is a TRIPWIRE, and the whole of what it proves is:
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
 * ── What it does NOT cover ───────────────────────────────────────────────────────────────────
 *
 *   * Swift outside the eleven declarations listed below. `Species.swift`'s data, the `Codable`
 *     conformances, anything in `Data` or `Features`: unfingerprinted, and the ports do not claim
 *     to reproduce them.
 *   * The enum cases and switch tables that `quantity.test.ts` and `vitality.test.ts` already
 *     parse by VALUE — `metersPerUnit`, `isMetric`, `MeasurementMethod.series`, `Vitality.label`,
 *     `Vitality.anchor`. A fingerprint there would be a second, more brittle copy of a check that
 *     already bites on the thing that matters.
 *   * The Python. `inventory_contract.py`'s prefixes are parsed by value; its inventory NAMES and
 *     URLs are still an unguarded transcription (#173 review, N4) and this file does not change
 *     that.
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
 * the orchestrator for `docs/ROADMAP.md` rather than guessed at here; this PR does not edit the
 * roadmap, because two other live branches are editing the same row. Until that round happens this
 * tripwire is toolchain-free, runs everywhere the suite runs, and catches both mutations above in
 * under a millisecond.
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
  /** `sha256` of the normalized declaration, recorded at PR #173 and re-recorded deliberately. */
  readonly fingerprint: string;
}

/**
 * The Swift the ports re-implement, declaration by declaration.
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
    fingerprint: '5b7d6b964bae6aaf33a317cdf190f90a06677977d5d5cae76339254a6f18cb8f',
  },
  {
    name: 'Coordinate.snappedToPublicPhotoGrid()',
    file: 'Cypress/Core/Models/Geometry.swift',
    signature: 'public func snappedToPublicPhotoGrid() -> Coordinate',
    fingerprint: '56c4e1f3086aff301e952a2ebb72add230eae51eea938402c7d3a0466a5074bb',
  },
  {
    name: 'FieldCaptured.isEligibleForGrowthCharting',
    file: 'Cypress/Core/Models/CoreEntity.swift',
    signature: 'public var isEligibleForGrowthCharting: Bool',
    fingerprint: '4068764cdc3b9f7a5a6dc1034d83e21266d9271996355740a57679150464c88a',
  },
  {
    name: 'Quantity.init(value:unit:method:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public init(value: Double, unit: LengthUnit, method: MeasurementMethod)',
    fingerprint: '72b4d2e5f1fdc76834606f6e382d4c244819c72fd0a0bed6418b3e2d0102ae9d',
  },
  {
    name: 'Quantity.converted(to:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public func converted(to unit: LengthUnit) -> Double',
    fingerprint: 'b49424910d6dd22cb1864586c24301482eca8c10ad93ec3943d7c2b0ec983a89',
  },
  {
    name: 'Quantity.isPlausible(within:)',
    file: 'Cypress/Core/Units/Quantity.swift',
    signature: 'public func isPlausible(within range: ClosedRange<Double>) -> Bool',
    fingerprint: 'c35e1cdd1c8a7c1ab6a9934a39c0e218230381edfb295c64f63befe0d8f8d627',
  },
  {
    name: 'TreeMeasurement.isChartable',
    file: 'Cypress/Core/Models/TreeMeasurement.swift',
    signature: 'public var isChartable: Bool',
    fingerprint: 'e84e18caa51130f74172b79f38407646941b9073ae2ce3d2aaabaa8606b7a83f',
  },
  {
    name: 'Collection.splitBySeries(kind:)',
    file: 'Cypress/Core/Models/TreeMeasurement.swift',
    signature: 'public func splitBySeries(kind: MeasurementKind)',
    fingerprint: '267478f351ffe7d50e1b79223540d7d063162b2b3c00f9ddf5263f9065af26d9',
  },
  {
    name: 'Vitality.isRatingPermitted(leafRetention:month:leafOnMonths:)',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    // The newline narrows this away from the `(for species:…)` overload below.
    signature: 'public static func isRatingPermitted(\n',
    fingerprint: '2327ada371667a4afdba9a12cae8e97b06381c75ddd57788e656f540f3d6c41a',
  },
  {
    name: 'Vitality.isRatingPermitted(for:month:)',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    signature: 'public static func isRatingPermitted(for species: Species, month: Int) -> Bool',
    fingerprint: '3b21c518e79b24c9a25ed64ccc2636e556f4ab8a638992028863205026b96d40',
  },
  {
    name: 'Vitality.suppression(for:month:)',
    file: 'Cypress/Core/Rubric/Vitality.swift',
    signature: 'public static func suppression(for species: Species, month: Int) -> Suppression',
    fingerprint: 'd064eb4643fc222bdf5fa811e19a528f4fc12b4c11b9a675bf17a2769ad4baf0',
  },
];

describe('the Swift the ports were derived from has not moved under them', () => {
  for (const region of REGIONS) {
    it(`${region.name} is the declaration the reference was recorded from`, () => {
      const found = swiftDeclaration(repoFile(region.file), region.signature);
      assert.equal(
        found.fingerprint,
        region.fingerprint,
        `${region.file} — ${region.name} has been edited since its fingerprint was recorded.\n\n`
          + `  recorded  ${region.fingerprint}\n`
          + `  now       ${found.fingerprint}\n\n`
          + `  the declaration as it reads today, normalized:\n`
          + `  ${found.normalized}\n\n`
          + `THIS IS NOT A FAILURE OF THE TYPESCRIPT. It means test/support/swift-reference.json — `
          + `a RECORDING of what this Swift printed — may no longer describe this Swift, and every `
          + `parity assertion in this directory compares the port against that recording. Read the `
          + `diff. If the behavior changed: regenerate the reference (the command is in `
          + `test/support/swift-reference/main.swift), re-run the whole suite so the ports are `
          + `re-checked against the new Swift, fix what that turns red, and only then paste the `
          + `fingerprint above into test/swiftDrift.test.ts. If the edit is cosmetic: paste it and `
          + `say why in the commit message.`,
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
      11,
      `the tripwire lists ${REGIONS.length} declarations, not 11. A row that disappears takes its `
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
      ],
      'the tripwire no longer reaches one of the five Swift files the ports re-implement',
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
});
