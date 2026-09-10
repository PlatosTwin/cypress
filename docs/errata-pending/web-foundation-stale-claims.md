# Unnumbered — the orchestrator splices these under the next E numbers at merge (CLAUDE.md,
# Numbering). Written from branch `web/foundation`, 2026-09-10, milestone W-A. The
# 2026-09-10 web proposal (§2, "Two documents that are wrong, found on the way") assigns both
# entries to the foundation round; each was re-measured here rather than copied from it.

### `ARCHITECTURE.md` says the local store is GRDB. It is not, and never was in this repository.

Five places say it, in the two sections a reader goes to for exactly this fact:

    docs/ARCHITECTURE.md:29  | Local store: expo-sqlite | **SQLite via GRDB** | …
    docs/ARCHITECTURE.md:48    Core/  Pure domain. No SwiftUI, no GRDB, no MapKit imports.
    docs/ARCHITECTURE.md:53      Store/  GRDB schema, migrations, DAOs, the bundled seed importer
    docs/ARCHITECTURE.md:72  **Import discipline.** … `Data` may import Core and GRDB.
    docs/ARCHITECTURE.md:99  **No view … may touch GRDB or the network directly.**

Measured on this tree, 2026-09-10:

    $ grep -rln "import GRDB" Cypress/ CypressTests/
    (nothing)
    $ grep -rln "import SQLite3" Cypress/ | head -5
    Cypress/Data/Cities/SeedCities.swift
    Cypress/Data/Cities/CityLibrary.swift
    Cypress/Data/Store/SQLiteStatement.swift
    Cypress/Data/Store/SQLiteError.swift
    Cypress/Data/Store/SQLiteConnection.swift

The store is hand-written over the C API. There is no GRDB dependency in the app target — the
project has zero external dependencies, which §1's own table states two rows above the one that
names one — and the only files that mention GRDB do so in comments disclaiming it
(`TreeProfileModel.swift:8`, `MapModel.swift:6`).

**Why it matters beyond tidiness, and why it is being filed by the web round.** §2 is the
*import-discipline* section: it is the document a reviewer cites when refusing an import, and
four of the five occurrences are inside the rules themselves. A rule stated over a dependency
that does not exist cannot be checked against the code, and "may import Core and GRDB" is not a
sentence anyone can enforce here. It is also the first thing a port reads: W-B re-derives the
domain rules in TypeScript and reuses `Fixtures/seed/schema.sql`, and an agent that believed
this section would go looking for a query builder's migration format that was never used.

This is the confident-comment class the ROADMAP's own preamble names, at document scale.

**The correction, in one sentence:** the local store is SQLite through `SQLite3` directly, in
`Cypress/Data/Store/`; no query-builder library is used, and the import-discipline rules should
name `SQLite3`.

### `.gitignore` calls the bundled seed an 88 MB build product. It is 108,249,088 bytes.

    .gitignore:30  # Bundled seed: an 88 MB build product of Tools/build_seed.py, byte-for-byte
                   # reproducible.

The artifact that line describes is pinned, with its size, in the file that decides which bytes
this repository builds against:

    $ python3 -c "import json;print(json.load(open('Fixtures/seed/pinned-seed.json'))['bytes'])"
    108249088

108,249,088 bytes is 103.2 MiB, or 108.2 MB decimal. Neither reading is 88. The number is stale
rather than wrong-by-convention: San Jose landed after it was written, and New York after that.

**Corrected in the same pull request** (W-A edits `.gitignore` to add `web/`'s build products),
because the alternative is a second document that has to be read alongside the first.

**The correction states no size at all**, and that is the whole of it. A comment that names a
number is a copy of a fact that already has an owner, and this one had been wrong for two
publishes before anyone looked. The line now says the size is deliberately not written there and
points at `Fixtures/seed/pinned-seed.json`, which is the file that decides which bytes this
repository builds against — so the next reader re-measures instead of trusting a comment, and
there is nothing left in `.gitignore` for the publish after next to falsify.

*(This paragraph previously read "the line now states the measured size and says where the
measurement lives", and the line it described said the opposite in bold. Adversarial review on
#162 caught the contradiction before the splice: the entry and the file disagreed, and the file
disagreed with itself — declaring the size deliberately unwritten and then writing it, dated. The
dated number is gone from `.gitignore` too, so both halves now say one thing.)*
