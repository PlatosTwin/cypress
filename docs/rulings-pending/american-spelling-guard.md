# American spellings: what the guard checks, and what it cannot

*Pending. Cite this file as `docs/rulings-pending/american-spelling-guard.md` until the orchestrator
splices a number; #140 delegated the guard's shape and scope.*

## The ruling

**One named word list, `BritishSpelling.forms` in `CypressTests/BritishSpellingGuardTests.swift`, is
the project's definition of "British". Two tests read it, from opposite ends:**

1. `BritishSpellingGuardTests.everyAppStringLiteralIsAmerican` — reads the **app target's own source
   off disk** and checks **every string literal in it**.
2. `AlmanacGeographyTests.fallbackSaysWhatItIs` — E182's original check, kept, now reading the same
   list, over three strings **screen 12 composes at runtime**.

Neither subsumes the other, and that is the whole design: the first is broad and static, the second
is narrow and dynamic. A guard with only the first would miss a sentence assembled from two innocent
halves; a guard with only the second would miss every screen nobody thought to add.

## Why a source scan rather than the obvious alternatives

The phrase in the ticket is "every user-visible string in the app". Three ways to reach it were
considered and two were rejected:

- **Reflect over the 44 `*Copy` types.** Swift has no reflection over static members, so each type
  would need a hand-maintained `static var allStrings`. A string added tomorrow is not in it, and
  the guard's completeness becomes a thing somebody has to remember — which is the chore #140 exists
  to end.
- **Scan the built binary.** Attractive, and wrong: Swift stores literals of 15 UTF-8 bytes or fewer
  inline as instruction immediates rather than in `__TEXT,__cstring`. `"Not centred"` is 11 bytes. A
  byte scan of the binary would have passed clean over the exact string this ticket started from.
- **Scan the source.** `#filePath` is this test file's absolute path at compile time, and a
  simulator test process is an ordinary macOS process that can read the host filesystem back. So the
  guard walks `<root>/Cypress/**/*.swift` and reads it.

The scan is a small character scanner, not a regex: `"` inside a `//` comment, an escaped `\"`, and
`"""` blocks all occur in this codebase and all defeat the regex versions of this.

## What the guard checks

Every string literal in the app target — a **superset** of the user-visible strings. It also sweeps
SQL, log lines and gate messages, deliberately: over-covering means no list of "which literals are
copy" has to exist, so nothing depends on a future author classifying their string correctly.

## What the guard does **not** check, stated because a guard that claims more than it checks is
worse than one that states its limits

1. **Strings the app reads out of the database.** `species.id_tips` carries **18 rows of British
   botanical prose in the shipped seed** — "Dark grey to red-brown bark", "the coloured-leaf
   records", "Smooth pale grey trunk". These *are* user-visible and this guard cannot see them. They
   were left alone on purpose: `Fixtures/species/curated.yaml` cites a fetched source per value and
   its own header forbids hand-editing (DECISIONS constraint 15, BUILD-PLAN §15), and the text is
   already baked into a published 108 MB seed that #140 cannot regenerate and re-verify. **This is
   open work, not a closed question** — see "Residue" below.
2. **Strings composed at runtime** by a `Formatter`, or joined from fragments where no fragment is
   British alone. E182's runtime check covers exactly three such strings on one screen.
3. **Identifiers and comments.** Renamed by hand in #140 passes 2 and 3, and deliberately not
   guarded. A symbol-level guard needs a permanent exception list: `Alegreya` (the body font)
   carries `grey`, `flameTree` carries `meTre`, and `optimistic`, `specialist`, `organism`,
   `capitalism`, `realistic`, `generalist` and `initialisms` each carry an `-ise` stem. Every one of
   those was a live false positive during this ticket. The cost of maintaining that list forever is
   higher than the cost of a stray British identifier, which no reader ever sees.
4. **The test targets.** `CypressTests` and `CypressUITests` were rewritten but are not swept: their
   strings are not shipped, and `AlmanacGeographyTests` has to be able to hold British specimens.

## The word list is a list, not a dictionary

It catches the forms it names. Every form this repo carried at #140 is in it, plus the rest of each
family so the next one written is caught too. Two rules govern additions:

- **Word boundaries only where a bare substring strikes correct English**, and each one is covered
  by `theWordListLeavesCorrectEnglishAlone`. A false positive disables a guard faster than a false
  negative does.
- **`-ise` stems are named individually and require a verb ending.** A blanket `-ise` rule strikes
  `advertise`, `surprise`, `exercise`, `comprise`, `premise`, `expertise` and `otherwise`; a stem
  without an ending strikes `optimistic` and `specialist`.

`towards` is **not** on the list: it is standard American English alongside `toward`.

## The guard cannot pass by seeing nothing

`theGuardCanSeeTheSource` fails — never skips — if the source tree is not where `#filePath` says, if
fewer than 150 files are swept, if fewer than 3,000 literals are read, or if fewer than 300 of them
are sentence-shaped. A skip would read as "checked and clean". `theScannerReadsWhatItSaysItReads`
pins the scanner against a specimen with a comment, an escape, an interpolation and a `"""` block;
`everyPatternCompiles` catches a pattern that silently matches nothing.

## Residue — the deliberate exceptions

Two string literals in the app target are allowlisted in `AppSourceLiterals.contractual`, each
because it crosses into data this repo did not write:

| literal | why |
| --- | --- |
| `case_normalised_columns` | a `seed_meta` key `Tools/build_seed.py` writes into the published seed |
| `Dark grey to red-brown bark, …` | an `id_tips` row quoted verbatim from `curated.yaml`, present verbatim in the shipped seed |

Not guarded and not corrected, all reported rather than forced:

- `Fixtures/species/curated.yaml` — **20 British spellings in botanical prose** (18 `grey`, 2
  `colour`), which reach the reader as the **18 `species.id_tips` rows in the shipped seed** that
  carry 20 British spellings between them. **The one piece of genuinely user-visible British text
  #140 did not fix.** Correcting it is an edit to a file whose header forbids hand-editing, plus a
  seed rebuild and a re-verification; it belongs to whoever owns the next seed build.
- `licence` in `curated.yaml` (404) and `leaf_retention.yaml` (1,688) is **not** prose and is not a
  defect: it is the field name inside each `citations` block, naming the licence of a fetched
  source. Counted here only so the next reader does not mistake ~2,000 matches for ~2,000 defects.
- `Tools/*.py` (81 matches). They build and validate the published seed; a spelling change there is
  a change to the toolchain behind a binary this ticket cannot regenerate and re-verify.
- `Fixtures/raw/**` and `Fixtures/ca_survey/**` — fetched source documents.
- `docs/ERRATA.md` and `docs/RULINGS.md`: prose corrected, **123 inline-code spans left as they
  were**. Some are quoted machine output — the `XCTAssertEqual` line comparing `"Not centred"`
  against `"Centred on you"` is a real 2026 failure — and rewriting one would make the record claim
  a string that was never printed. The rest are period-correct symbol names, which a historical
  record is entitled to.
- `CLAUDE.md` (1 match, the word "colour" in the verification section). Standing rules; not an
  agent's file to edit.
