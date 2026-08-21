### R__: every TestFlight build ships a changelog, and CI will not let one merge without its line

**Owner ruling, 2026-08-21.** Every build uploaded to TestFlight carries a "What to Test" —
TestFlight's changelog field — compiled from **one tester-voice line per pull request**, in the
voice of somebody using the app: *"You can now pinch-zoom photos."* CI enforces it: a code change
cannot merge without its line.

Until this, builds went up through `xcrun altool` with no notes at all. `altool` cannot set that
field — it uploads a binary and knows nothing about the metadata hanging off it — so nobody had to
decide not to write one, and forty-three builds went to testers saying nothing.

---

#### The mechanism

**A note is a file, not a line in a shared file.** `docs/whats-new/<branch-or-topic>.md`, one
sentence — occasionally two or three. Blank lines and `#` comments are ignored, so a file can
carry an explanation for reviewers that testers never see. This is the pending-directory pattern
`docs/errata-pending/` already uses, for the same reason: a single `CHANGELOG.md` conflicts on
every branch that touches it, and this repository routinely has four open at once.

**"Already shipped" is read off git, and nothing writes a marker.** The release workflow already
tags the commit each build shipped from, `build-N` (#196). So:

> the notes for the build minted at `<at>` = the note files present at `<at>`, minus the note
> files present at `<since>`, where `<since>` is the previous `build-N` tag.

`Tools/whats_new.py compile` is that sentence and little else. The consequences are the
requirements rather than side effects of them:

- **No line ships twice.** A file present at the previous tag is excluded whatever happened to it
  since — editing a shipped note does not re-ship it.
- **Nothing is lost to a merge that minted no build.** A prose-only merge moves no tag (`plan`'s
  ships predicate), so its notes are still unshipped and are picked up by the next real build.
  They accumulate across as many skipped merges as it takes.
- **A build's notes can be re-derived afterwards**, from `build-N` and `build-(N-1)` alone. That
  is what lets the backstop below stamp a build the release job could not reach.
- **No bot commit to main, no state file, no token that can write a ref.** Two people running the
  compile a week apart on the same pair of revisions get the same bytes.

Ordering is newest note first; over App Store Connect's 4000-character limit the oldest lines drop
and the text ends `…and earlier improvements.` rather than simply stopping.

#### The escape hatch, and why it is not a loophole

**A line beginning `internal:` satisfies the check and is left out of the compiled notes.**

    internal: reworks the outbox retry policy; no tester-visible change.

A real code change with nothing for a tester to look at is common and honest — a workflow edit, a
refactor, a new test, this very change. The alternative to an escape hatch is not a better
changelog; it is an invented feature, which DECISIONS constraint 15 forbids and which a tester
would then go looking for.

It is not a way out of the rule. The rule is *"every code pull request states its tester-visible
effect"*; `internal:` states that the effect is none, in the diff, where a reviewer can disagree
with the judgement. A build whose every note is internal still ships a changelog — it says so in
plain words rather than going out blank.

#### Where CI refuses

`plan` in `.github/workflows/testflight.yml` runs `Tools/whats_new.py check` on every pull request
whose diff is not prose-only, and `gate` — the required status check — fails when it reports
missing. Three details are deliberate:

- **The check runs in `plan` but fails in `gate`.** Failing `plan` would skip `unit` and `ui`, and
  `gate` would then report only "plan did not succeed", burying the one sentence the author needs.
  As it is, the suite still runs and the author gets both answers in one round.
- **A note must be an ADDED file.** Editing a note another branch already wrote does not answer
  the check.
- **`gate` refuses an unrecognized value, not just a missing one.** If the check is renamed or
  crashes, `plan`'s output is the empty string — and a gate that only tested for `"missing"` would
  go green precisely when the enforcement stopped working. That is this repository's signature
  failure and it is guarded the same way `tests` is.

Prose-only pull requests need no line. They may carry one; it waits in the directory until the
next build that ships.

#### Publishing it

`Tools/appstore_connect.py set-whats-new` writes the compiled text to the build's
`betaBuildLocalizations` and then **reads it back and compares**, because a 200 that stored
something else is indistinguishable from success at the call site.

The release job compiles the notes immediately after checkout — before the archive, so a malformed
note costs ten seconds instead of forty minutes, and before the new tag exists, so the boundary
cannot collapse onto itself — and publishes them after the step that already waits for the build
to appear. **That step's existing twenty-minute bound is reused; no second wait is introduced.**

The one gap is a build that uploads and then processes slowly: the expiry step fails, the build
reaches testers anyway, and it carries no notes.
`.github/workflows/whats-new-backstop.yml` runs twice a day, finds any live build with an empty
"What to Test", and stamps it from that build's own tag. It writes nothing to the repository, and
a build with no tag is left alone with a warning rather than stamped with a guess.

#### Voice

American spellings (favorite, color, center, neighborhood). Plain sentences. Nothing invented, and
nothing claimed that has not been seen working — a changelog is a claim, and the standing rule
about unverified claims applies to it in full. `docs/whats-new/README.md` is what an author reads.

#### The backfill

`docs/whats-new/0043-community-contributions-sync.md` describes what build 43 shipped, so that the
first build carrying notes does not open on a changelog that skips a release. It is a backfill and
says so in its own comments: **build 43 itself had no notes and this does not pretend otherwise.**
Its lines were checked against `OutboxItem.Kind` and `server/internal/api/sync.go` rather than
against the ticket, which is where the last line — that the server records these contributions
rather than acting on them yet — comes from.
