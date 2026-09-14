# Rulings pending — how the web's pack directory is laid out and refreshed (W-E, 2026-09-13)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices these under real
numbers at merge. Nothing in `Cypress/`, `CypressTests/` or `CypressUITests/` cites this filename;
the web sources carry the reasoning in their own headers and cite no pending number.

Four decisions the W-E sync made that are not visible from any one file, written down because each
one is the kind of thing a later change would undo without noticing it was a decision. The fourth
came out of the adversarial review of #178.

---

### R??? — The web's pack directory is flat, and the published version is not recorded in it

**Date:** 2026-09-13. **Decided by:** author, W-E. **Status:** decided, and cheap to revisit.

The bucket stores a pack at `cities/<id>/<version>/<id>.sqlite` (R37.2) and the web writes it to
`<CYPRESS_PACK_DIR>/<id>.sqlite`. The version string is therefore **not** on the server's disk.

This is `packLibrary.openPackLibrary` reality rather than a preference: it reads one directory,
non-recursively, and opens every `*.sqlite` in it. Keeping the version in the filename would be
worse than dropping it, because two versions of one city would both match, both open, and both
answer for the same id space — and the walk is by path order, so which one answered would be
decided by a sort. One file per pack id, replaced in place, is the layout that cannot say two
things at once.

What is lost is the ability to ask the disk "which publish is this?". What replaces it is the
sha256: every run re-hashes what is present and compares it to the catalog, so the question is
answered by running the sync and reading what it skipped. If a future round wants the version
recorded, the shape to add is a sidecar receipt the library already ignores — **not** a versioned
filename, and not a subdirectory, because the library would have to learn to walk one.

### R??? — A failed hash is terminal; a failed connection is retried

**Date:** 2026-09-13. **Decided by:** author, W-E. **Status:** decided.

`sync-packs.mjs` retries transport failures (refused connection, 5xx, a stalled socket) a bounded
number of times, and does **not** retry a body that arrived complete and failed verification.
Queens is 199 MB: re-downloading it to be told the same thing turns one clear message into three
slow ones, and a mismatch between a complete object and the catalog is a publish problem rather
than a network one. A test asserts the request count, so the distinction cannot be relaxed quietly.

### R??? — `src/` ships in the runtime image, because the script imports it

**Date:** 2026-09-13. **Decided by:** author, W-E. **Status:** decided.

`web/Dockerfile`'s runtime stage now copies `scripts/` **and** `src/`. The sync script imports the
catalog decoder, the pack generation this build accepts, and the name of `CYPRESS_PACK_DIR` from
`src/lib/` rather than carrying its own copies — one definition each, so the server and the sync
cannot disagree — and `dist/` is Astro's bundle, which holds none of those in an importable form.
A script in the image whose imports are not is a script that fails at `fly ssh console` time, so
`test/sync-packs.test.ts` asserts both directories arrive and that every relative import the script
makes resolves under one of them.

### R??? — A catalog that would put two entries in one file is refused, not reconciled

**Date:** 2026-09-13. **Decided by:** author, W-E, after review of #178. **Status:** decided.

The destination filename is the pack id (see the first entry above), so two catalog entries sharing
an id — or differing only in case, which is one file on a developer's Mac and two on the volume —
map to one path. The arithmetic bug the reviewer found was cosmetic (`bytes-in-place` counted both
entries for the one file that survived), and fixing the arithmetic would have been the wrong repair:
one entry silently overwriting another is a catalog that is wrong about something upstream, and the
volume would end up holding one city under a name claiming to be two. The run refuses the catalog
whole, before a byte moves, and exits nonzero — the treatment an unknown envelope format already
gets. Nothing the publisher emits today can produce either case.
