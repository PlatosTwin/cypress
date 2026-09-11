/**
 * British spellings, and the American form each should take.
 *
 * CLAUDE.md: "American spellings: favorite, color, center, neighborhood." The rule is the
 * repository's; only the enforcement is new here.
 *
 * **Why this lives in the web suite and not in `BritishSpellingGuardTests`.** Extending that
 * Swift guard to walk `web/` was considered and is wrong — it would make `web/` an input to
 * `CypressTests`, and "nothing in `CypressTests` or `CypressUITests` opens a file under `web/`"
 * is the load-bearing premise of the entire `WEB_ONLY` carve-out in `testflight.yml`. The guard
 * would falsify the sentence it was added under, and every web-only commit would go back to
 * running 34 minutes of `macos-26`. A rule enforced in the wrong target costs more than it saves.
 *
 * **What this checks, exactly:** every character of the web's own source files — comments and
 * markdown included, unlike the Swift guard, which is scoped to string literals because it is
 * guarding *what a user can see*. Here there is no shipped copy yet (W-A is a placeholder page),
 * so the thing worth guarding is the prose an author reads, which is where all three of this
 * round's occurrences were. When W-C ships real copy this is already covering it.
 */
export interface BritishForm {
  readonly pattern: RegExp;
  readonly american: string;
}

/**
 * A named list, not a dictionary: it catches the forms it names.
 *
 * Word boundaries appear only where a bare substring would strike correct English, and each one
 * is exercised by `theWordListLeavesCorrectEnglishAlone` in the test beside this file — the same
 * argument `BritishSpelling` makes in Swift, where "Alegreya", "flameTree", "optimistic" and
 * "specialist" each contain a British spelling as a substring.
 */
export const britishForms: readonly BritishForm[] = [
  // -our -> -or
  { pattern: /colour/gi, american: 'color' },
  { pattern: /favour/gi, american: 'favor' },
  { pattern: /neighbour/gi, american: 'neighbor' },
  { pattern: /behaviour/gi, american: 'behavior' },
  { pattern: /honour/gi, american: 'honor' },
  { pattern: /labour/gi, american: 'labor' },
  { pattern: /humour/gi, american: 'humor' },
  { pattern: /flavour/gi, american: 'flavor' },
  { pattern: /harbour/gi, american: 'harbor' },
  { pattern: /rumour/gi, american: 'rumor' },
  { pattern: /savour/gi, american: 'savor' },
  { pattern: /vapour/gi, american: 'vapor' },
  { pattern: /vigour/gi, american: 'vigor' },
  // -re -> -er. `centred`/`centring` before `centre`, so the message names the right word.
  { pattern: /centred/gi, american: 'centered' },
  { pattern: /centring/gi, american: 'centering' },
  { pattern: /centre/gi, american: 'center' },
  { pattern: /theatre/gi, american: 'theater' },
  { pattern: /fibre/gi, american: 'fiber' },
  { pattern: /litre/gi, american: 'liter' },
  { pattern: /sombre/gi, american: 'somber' },
  { pattern: /calibre/gi, american: 'caliber' },
  // `-metre`, bare or behind any SI prefix, generated rather than listed one prefix at a time.
  //
  // It used to be four hand-written entries — `millimetre`, `centimetre`, `kilometre` and a bare
  // `metre` — and `nanometres` fell between them: the bare rule's lookbehind is defeated by the
  // `o` of `nano`, and no entry named that prefix. Three occurrences sat inside `web/`, past this
  // sweep, until a reviewer read them (PR #173). Enumerating the prefixes is the fix; adding
  // `nanometre` alone would have left `picometre` in the same hole.
  //
  // **What the lookbehind still excludes, said plainly.** `(?<![A-Za-z])` is load-bearing — a bare
  // `metre` strikes "flameTree" as "fla-meTre-e". It also means a `metre` glued to the end of a
  // longer word is NOT caught, a camelCase `fooMetre` included. That is a deliberate false
  // negative, not a claim of coverage, and it is asserted as such in the test beside this file.
  ...['', 'nano', 'micro', 'milli', 'centi', 'deci', 'deka', 'deca', 'hecto', 'kilo', 'mega',
    'giga', 'tera', 'pico', 'femto'].map((prefix) => ({
    pattern: new RegExp(String.raw`(?<![A-Za-z])${prefix}metre`, 'gi'),
    american: `${prefix}meter`,
  })),
  // -ce -> -se, and the two -ise families that occur in prose about code.
  { pattern: /licence/gi, american: 'license' },
  { pattern: /defence/gi, american: 'defense' },
  { pattern: /offence/gi, american: 'offense' },
  { pattern: /pretence/gi, american: 'pretense' },
  // `analyse`, not `analys`: "analysis" is correct English in both.
  { pattern: /analyse/gi, american: 'analyze' },
  { pattern: /catalogue/gi, american: 'catalog' },
  { pattern: /dialogue/gi, american: 'dialog' },
  { pattern: /grey(?![A-Za-z])/gi, american: 'gray' },
  { pattern: /cancelled/gi, american: 'canceled' },
  { pattern: /travelling/gi, american: 'traveling' },
  { pattern: /modelling/gi, american: 'modeling' },
];

export interface Offense {
  readonly matched: string;
  readonly american: string;
  readonly line: number;
}

/** Every British spelling in `text`, with the 1-based line it sits on. */
export function offenses(text: string): Offense[] {
  const found: Offense[] = [];
  const lines = text.split('\n');
  lines.forEach((line, index) => {
    for (const form of britishForms) {
      // A fresh regex per line: a `/g` regex carries `lastIndex` between calls, and reusing one
      // across lines silently skips matches. That is the shape of a guard that is green because
      // it looked in the wrong place, which is the defect class this repository names first.
      const re = new RegExp(form.pattern.source, 'gi');
      let match: RegExpExecArray | null;
      while ((match = re.exec(line)) !== null) {
        found.push({ matched: match[0], american: form.american, line: index + 1 });
      }
    }
  });
  return found;
}
