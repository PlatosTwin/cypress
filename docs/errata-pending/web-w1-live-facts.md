# Unnumbered — the orchestrator splices these under the next E numbers at merge (CLAUDE.md,
# Numbering). Written from branch `web/w1-live-facts`, 2026-09-11, milestone W-C, over
# `web/w1-tree-page` at 295d107. Every claim below was measured on this tree, against the published
# San Francisco pack (`sf.sqlite`, `s17-r2026-08-22.02-ac7b1ccc`, 82,796,544 bytes, sha256
# `15d9521e…5f00` — all three matching `manifest-v2.json`, with `select count(*) from trees`
# returning 145,964 against the manifest's `tree_count` as the control), or against the running
# `cypress-sync`.

### `pathBlocks` ended a `paths:` block at the first entry carrying a trailing comment, and both filters have one

`web/test/pack-versions.test.ts` holds the guard that says every file the web suite reads from
outside `web/` is in **both** of `.github/workflows/web.yml`'s `paths:` filters. It parses the
workflow with `pathBlocks`, whose entry pattern was anchored `'\s*$`:

    const entry = /^\s*-\s*'([^']+)'\s*$/.exec(line);

`web.yml`'s **second entry in each of its two filters** is

    - 'Cypress/DesignSystem/Tokens/**'   # web/test/tokens.test.ts re-renders these to CSS

which matches neither that pattern nor the comment-line rule below it, and therefore fell through
to *"anything else ends the list"*. The parser read **one** path out of each block — `web/**` —
and every other entry was reported as missing.

**The test was red on `web/w1-tree-page`** at the moment this branch was cut, with the message
`web/test reads Cypress/Data/Store/SeedDatabase.swift and .github/workflows/web.yml does not
trigger on it`. That file has been in both filters since W-B.

**The failure mode is the one this repository has a rule about, arriving from the other side.** A
guard that goes green over a defect and a guard that goes red for a reason that is not the defect
are the same error: what it reports is not what it measured. The red one is the less dangerous of
the two and it is still not harmless — the honest reading of that message is "somebody deleted a
path from the workflow", and the repair a reader would reach for is to re-add a line that is
already there.

`web.yml` is correct YAML and GitHub reads the whole list; nothing about CI was broken. The parser
was.

**Fixed** by allowing a trailing comment after the quoted value, and — the part that matters — by
putting that exact line into the calibration specimen, which previously carried a comment on its
own line and a following key with a quoted value and not this. The specimen's answer was known
before the fixed parser saw it.

### The public tree read is in `main` and is not on the running service

`docs/rulings-pending/public-tree-read.md` and `server/internal/api/public.go` are merged. The route
is **not deployed**, and the distinction matters to anything that reads the endpoint's existence off
the repository.

Measured 2026-09-11 against `https://cypress-sync.fly.dev`:

| request | answer |
|---|---|
| `GET /health` | `200` |
| `GET /api/v1/sync` | `405 Method Not Allowed` |
| `GET /api/v1/devices/register` | `405 Method Not Allowed` |
| `GET /api/v1/public/trees/9f3a1c07-…` | `404 page not found` |
| `GET /api/v1/public/trees/not-a-uuid` | `404 page not found` |

The service is up. A route that IS registered but takes another verb answers `405` — that is the
calibration, and it is why the `404` is evidence rather than a guess: Go's `ServeMux` answers a bare
`404 page not found` for a pattern it does not hold, and the service's own handler would have
answered `validation_failed` for the malformed id, before touching the database. Merging #163 did
not redeploy the machine.

Deliberately probed with a **malformed** id as well as a well-formed one: `parsePathUUID` runs
before `PublicTreeCommunityHalf`, so that request could not have reached production Postgres
whatever the answer had been.

**The consequence for W1**, which is why this is an erratum and not a note: the community read being
unavailable is not an edge case this page should degrade gracefully through — it is the state the
page ships in, and it stays that way until W-E or a redeploy. A page built on the assumption that
the endpoint answers would be a page that has never once run in the state it is in.
