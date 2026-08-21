# What testers read

One file per pull request. Each file holds one sentence — occasionally two or three — in a
tester's voice, describing what they can now do that they could not do before:

    You can now pinch to zoom a tree's photos.

The release workflow compiles every note added since the last build's tag into TestFlight's
**What to Test** field, newest first. Nothing edits a shared file, so two open branches never
conflict over this directory, and nothing has to be checked off as "shipped" afterwards — the
`build-N` tag the release job already creates is the boundary.

**A code change cannot merge without one.** `plan` in `.github/workflows/testflight.yml` runs
`Tools/whats_new.py check` on every pull request whose diff is not prose-only, and `gate` — the
required status check — refuses if the note is missing.

## The rules

- **Name the file for your branch or your topic**, `feat-photo-zoom.md`, not `notes.md`. The name
  is never shown to anyone; it exists so two branches pick different ones.
- **American spellings**: favorite, color, center, neighborhood.
- **Say only what shipped.** Do not describe a screen that is behind a flag, a mutation the
  server records but does not act on, or anything you have not seen work. A changelog is a claim,
  and this repository's standing rule about unverified claims applies to it.
- **No feature invented to fill the line.** If there is nothing to say, say so — see below.
- Keep a line under 200 characters. The TestFlight field holds 4000 in total and it is shared
  with every other branch open at the same time.
- Blank lines and lines beginning `#` are ignored, so a file can carry a comment for reviewers.

## Nothing for a tester to see

A refactor, a workflow change, a new test, a documentation tool — real code changes with no
tester-visible effect. Write the reason instead, prefixed `internal:`

    internal: reworks the outbox retry policy; no tester-visible change.

That satisfies the check and is left out of the compiled notes. It is deliberately visible in the
diff: claiming "no tester-visible change" is a judgement a reviewer should get to disagree with.

## Taking a line back

**Delete the file.** That is the retraction mechanism and the only one: the release job compiles
the notes *present* at the commit it is building, so a note deleted before its build never reaches
a tester. Do it whenever a feature slips out of a release, or a line turns out to overclaim. The
compile prints `withdrawn (deleted before this build)` to the release log for each one, so the
withdrawal is on the record rather than only in a diff nobody re-reads.

Once a line has actually shipped, deleting its file does nothing — that build is out. Say the
correction in a new note.

## Renaming and rewording

Renaming a note is safe: git reports the move and the line is not published a second time. So is
editing one in place. **Doing both at once is not** — a rename that also rewrites the sentence
falls below git's similarity threshold, reads as a delete plus a new file, and the sentence ships
again. If you need to reword a note that has already shipped, leave its filename alone.

A pull request that *only* renames notes is refused by the check, deliberately: moving somebody
else's sentence is not writing your own.

## Prose-only pull requests

A change to `docs/`, `graphify-out/` or a root `*.md` mints no build, so it needs no note. It may
carry one anyway — a note added by a prose merge simply waits in this directory until the next
build that actually ships.
