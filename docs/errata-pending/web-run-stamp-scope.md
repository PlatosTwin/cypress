# Unnumbered — the orchestrator splices this under the next E number at merge (CLAUDE.md,
# Numbering). Written from branch `fix/web-collision-guard-scope`, 2026-09-10. Sibling to
# `docs/errata-pending/web-collision-guard-scope.md`; same script, unrelated defect.

### The web run stamp said `(clean)` about a tree it had not looked at

`Tools/run_web_tests.sh` stamped every log with

    CYPRESS-WEB-RUN: web-dir /private/tmp/cy-webstamp/web (clean)

computed as `git status --porcelain -- web/`. On 2026-09-10 one agent's six attack runs and
another's two mutation runs all stamped `(clean)` with `Cypress/Core/Models/Geometry.swift`
modified under their hands. Reproduced against the pre-change script as a control, with that same
file modified — and the control is sharper than the reports were, because the run that printed
`(clean)` also had `Tools/run_web_tests.sh` itself uncommitted, which is a path the workflow
already declares as an input to this suite.

That scope was merely INCOMPLETE while the suite read nothing outside `web/`. It is FALSE now
that the suite reads Swift: #171 renders `Cypress/DesignSystem/Tokens/**` and #173 fingerprints
five sources under `Cypress/Core/`. **A missing stamp is an unknown; a stamp that says clean about
a tree that was not is a fact a reader relies on** — CLAUDE.md's rule is that every log carries its
own provenance, and a wrong one is worse than none.

**The scope is now derived from `.github/workflows/web.yml`'s own `paths:` lists**, so the file
that decides when this suite runs in CI is the file that decides what the stamp is about, and a
round that teaches the suite to read a new directory widens both in one edit. Globs are handled,
not just literals: the derivation is proved against `Cypress/DesignSystem/Tokens/**`.

**Why deriving one set from another is safe here and was not in
`CypressTests/DocumentCitationGuardTests.swift`.** That guard tried to derive "files that need not
exist on disk" from `.gitignore`, which answers a different question, and the derivation silently
EXCLUDED 46 committed files from being checked. `paths:` answers a different question from this
one too — "which diffs must run this suite", not "which files does this suite open";
`.github/workflows/web.yml` is in the list and no test opens it. So the derivation is used **only
to partition** a whole-repo `git status`, never to drop anything out of it. Every uncommitted file
in the checkout is named in the log either way, under one of two labels:

    CYPRESS-WEB-RUN: suite-inputs DIRTY (3 uncommitted) — scope is the 6 path patterns …
    CYPRESS-WEB-RUN: suite-inputs-dirty  M Cypress/Core/Models/Geometry.swift
    CYPRESS-WEB-RUN: elsewhere DIRTY (1 uncommitted outside those patterns) — … NOT a claim about its inputs
    CYPRESS-WEB-RUN: elsewhere-dirty  M Cypress/Core/Models/Hazard.swift

A stale `paths:` list therefore mislabels a file and cannot hide one, which is exactly what the
`.gitignore` derivation did.

**Two refusals, because their absence is a stamp that cannot say DIRTY** — this project's dominant
defect class. Zero patterns parsed is refused; a `paths-ignore:` block or a `!`-negated entry is
refused, because a negation read as an ordinary pattern widens the scope where the author narrowed
it. Neither exists in the workflow today.

**The `web-dir` key kept its name and changed its meaning, deliberately.**
`Tools/verify_web_test_log.sh` matches `(DIRTY)` in that stamp and is the only thing that puts
dirtiness into the one-line verdict; a run that touched only Swift would otherwise have had a
correct new stamp and a verdict that said nothing. The key is therefore the flag for the whole
input set, and the stamp's own text says so on the line the verifier prints back.

**Both directions measured, and the discriminating one too.** A clean tree stamps
`suite-inputs clean (0 uncommitted)`; a modified `web/test/spelling.test.ts` and a modified
`Cypress/DesignSystem/Tokens/CypressColor.swift` each stamp DIRTY and are named; a modified
`Cypress/Features/Activity/ActivityModel.swift` leaves `suite-inputs clean` and appears under
`elsewhere`. Git's pathspec globbing was calibrated against known answers before any of it was
believed — one file directly in a `**` directory, one nested deeper, one sibling outside it, and a
pattern matching nothing — and so was the YAML parser, against the workflow itself and against a
synthetic file carrying a glob, a trailing comment and a step list.
