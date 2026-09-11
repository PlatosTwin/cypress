# Unnumbered — the orchestrator splices these under the next E numbers at merge (CLAUDE.md,
# Numbering). Written from branch `claude/cypress-web-version-60fc5e`, 2026-09-10, while surveying
# the repository for the web round. None of the three is caused by the web work; all three were
# found by it.

### Two documents describe a database layer this app does not have

`docs/ARCHITECTURE.md` says the local store is GRDB, in five places: the §1 comparison table
(line 29, "Local store: expo-sqlite → **SQLite via GRDB**"), and §2 at lines 48 ("No SwiftUI, no
GRDB, no MapKit imports"), 53 ("GRDB schema, migrations, DAOs"), 72 ("`Data` may import Core and
GRDB") and 99 ("No view … may touch GRDB or the network directly").

**There is no GRDB in this project.** `Cypress/Data/Store/SQLiteConnection.swift`,
`SQLiteStatement.swift`, `SQLiteValue.swift` and `SQLiteError.swift` each `import SQLite3` and talk
to the C API directly. The app target has zero external dependencies, which is ARCHITECTURE's own
stated constraint one section earlier. The only three files in the app that contain the string
"GRDB" are `Features` view models disclaiming it — `TreeProfileModel.swift:8` and `MapModel.swift:6`
both say, in as many words, "no GRDB, no SQLite".

The import-discipline rule the document states is still the rule and is still followed; it is the
*named dependency* that is wrong. Corrected reading: `Data` owns the SQLite3 access layer and
nothing above `Data` touches it.

**Why it matters beyond tidiness.** The rule at line 99 is enforced by review against a name that
does not appear in the codebase, so a violation cannot be found by searching for the thing the rule
forbids. This is the ROADMAP preamble's own lesson — "confident comments are where bugs live" —
holding in a document rather than a comment.

### `.gitignore` states a seed size 19 MB below the pinned artifact

`.gitignore:30` reads "Bundled seed: an 88 MB build product of Tools/build_seed.py". The pin beside
it, `Fixtures/seed/pinned-seed.json:63-70`, measures the artifact it pins at **108,249,088 bytes**
(~103 MiB), schema_version 16, tree_count 198,625.

Harmless where it sits — the pattern below the comment is correct and ignores the file either way —
and recorded because the number is quoted from `.gitignore` in conversation as if it were measured.
The pin is the measurement; the comment is prose, and prose went stale.

### The W1 mock and the W1 transcription disagree, and the transcription is the source

Found before any web code was written, per the ROADMAP's standing rule: "Every screen is implemented
against `SCREENS.md`, which is the transcription; the mock is the check, not the source. Where they
disagree the disagreement is an ERRATA entry before it is a code change."

`mocks/cypress-mocks.html:971-985` renders the public tree page with:

- a **three**-item nav — `Explore` · `Species` · `Neighborhoods`, then `Sign in`
- **five** fact rows — `Status`, `Height / DBH` (combined), `Photos across time`,
  `City record`, `Data`
- URL `cypress.app/sf/tree/9f3a-monterey-cypress`

`docs/distilled/SCREENS.md` §W1 transcribes:

- a **four**-item nav — `Explore` · `Species` · `Neighborhoods` · **`Data & export`**, then `Sign in`
- **six** fact rows — `Status`, `Height` and `Trunk · DBH` **split onto separate rows** each with its
  own method badge, **`In the city record since`** (mono `1898`), `City record`, `Data`
- the same URL

Two substantive differences, not one. The nav gains a fourth destination, and the fact column splits
the combined height/DBH row so that each measurement carries its own badge — which is the more
consequential of the two, because a shared row cannot show that `18 m` is `est.` while `64 cm` is
`taped`, and the method badge on every number is D-numbered product law, not decoration.

**Resolution: build the transcription.** Six rows, four nav items. The mock is the earlier artifact
and the combined row is what the badge rule forbids; `SCREENS.md` is the source by the standing rule
and is also the one that is right on the merits. Recorded rather than resolved silently so that the
next reader who opens the mock and finds five rows has the answer.

The two rows the mock lacks entirely — `In the city record since`, and the split — both come from the
pack, so neither is blocked on anything.

### CLAUDE.md restates ARCHITECTURE §6 more strictly than §6 says, and the restatement is what gets quoted

`docs/ARCHITECTURE.md` §6 scopes its literal ban to the feature layer, in two sentences that agree
with each other:

> Never write a raw hex or a raw font size inside a feature. Use `CypressColor.*`, `CypressFont.*`,
> `CypressRadius.*`, `CypressShadow.*`. **A literal in `Features/` is a bug.**

`CLAUDE.md` restates it without the scope, and adds a category §6 does not name:

> No raw hex, font sizes, or radii — tokens only (§6).

Radii are not in §6's sentence, and "tokens only" with no qualifier reads as a whole-repository
rule. Because CLAUDE.md loads automatically for every session and every subagent, **the unscoped
version is the one that gets quoted** — it was relayed verbatim into a web-round review brief on
2026-09-10, where it would have made `Base.astro`'s five hand-written sizes a §6 violation. They
are not one: §6 does not reach outside `Features/`, and it does not reach outside Swift at all.
The reviewer caught it by reading §6 instead of the restatement, which is the only way this class
is ever caught.

**The defect is not that either sentence is wrong** — §6 is right about `Features/`, and a
tokens-only discipline for the web is a perfectly good thing to want. It is that a **citation by
number** (`§6`) is attached to a rule its source does not state, so the restatement borrows an
authority it was not given, and no reader who trusts the citation will check. Same family as the
citation guards: a reference that resolves to the wrong thing is worse than one that resolves to
nothing, because nothing reports it.

Two separable fixes, and they are not alternatives: narrow CLAUDE.md's sentence to what §6 says,
**and** — if a tokens-only rule should bind the web — write that rule somewhere that governs the
web, where it can be cited honestly.
