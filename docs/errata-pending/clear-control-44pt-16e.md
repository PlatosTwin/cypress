# The 44 pt clear control that measures 43.99999999999999 pt on an iPhone 16e

**Unnumbered — pending splice. Found in passing by the #151 branch (p0/phenology); the file it
implicates is a Map file, which belongs to another live branch, so this records rather than
fixes.**

`MapSearchUITests.testTheClearControlAppearsOnlyWithTextAndCanBeTapped` asserts the map search
field's clear control is at least 44.0 pt tall (ARCHITECTURE §6's touch target). On the
iPhone 16e simulator (3A1F212D-8F3A-41F1-AF72-EC95E155A4C9, iOS 26) the measured frame height is
**43.99999999999999 pt** and the `XCTAssertGreaterThanOrEqual(clear.frame.height, 44, …)` at
`CypressUITests/MapSearchUITests.swift:392` fails.

Evidence of pre-existence, all on that simulator, 2026-07-31:

- fails on `p0/phenology` (whose diff touches no Map file) — twice, deterministically,
  identical value to the last digit;
- fails identically at the branch's base, main `7e9ab93`, with no local modifications
  (`dd-phenology/base-clear.log`).

The value is a floating-point epsilon under the constant — the control is drawn at 44 pt and
the failure is the ruler, on this device's scale geometry, not the layout. Two honest repairs,
whichever the Map branch prefers: measure with a tolerance that names what it forgives
(`accuracy: 0.001`, "a point-scale rounding is not a shrunken target"), or round the measured
frame to the screen's pixel grid before comparing. Lowering the constant is not one of them.

Until it lands, a full-suite run on the 16e reports exactly this one failure; the unit suite
(966 tests, 91 suites) and every other UI test pass.
