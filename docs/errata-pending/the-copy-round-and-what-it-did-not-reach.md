# Unnumbered — the copy round: what the owner's five rulings fixed, and the two sentences beside them that are still false

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under the
real next number at merge. Written on `feat/copy-rulings`, the round that implements the owner's
rulings 1, 2, 3, 4 and 6 of **2026-08-14**, and the two corrections the owner ruled on **2026-08-15**
after the adversarial review (the rulings themselves are staged in
`docs/rulings-pending/copy-and-the-apple-button.md`).

Everything below was checked against the code, the tests or the running screen. The two findings in
§4 are new with this round and are **not** ruled. §6 is round 2: what the review proved, including
one defect in behavior that this round's own tests were arranged not to see.

---

## 1. What the rulings discharged, and what each replacement is now claiming

Three earlier pending entries raised these as stop-and-asks and deliberately did not answer them.
Read against this round:

| raised in | the false sentence | ruled |
| --- | --- | --- |
| `158-the-apple-button-works-and-three-sentences-beside-it-do-not.md` §1a | `AccountAskCopy.noticeUnavailable`, *"Accounts are not ready yet"* | ruling 4 |
| the same entry, §1b | `AccountCopy.signedInBody`, *"Nothing is uploaded"* | ruling 2 |
| the same entry, §3 | screen 15's button carries no Apple mark | ruling 6 |
| `158-the-app-goes-live-and-three-sentences-stop-being-true.md` §3 | screen 17's per-code sentences | rulings 1 and 3 |

**The replacements make narrower claims than the sentences they replace, and each one's falsifier is
written at its own site.** That is the pattern worth carrying forward — a sentence with no stated
falsifier is how the last set went stale without anyone noticing:

- `AccountCopy.storageBody`'s first clause is `DataLayer.boot` wiring `APIOutboxSendSink`, and its
  second is `OutboxSendSink` having exactly one method that is not a photo. Both are pinned by
  `OwnerCopyRulingTests.nothingOnTheSendSideCanCarryAPhotograph`, which reads the protocol's own
  surface off the source and goes red on the round that adds the photo sink — which is the round the
  owner said revisits the sentence.
- `AccountAskCopy.noticeUnavailable` names Google and email rather than "accounts", so it becomes
  false when either ships rather than when anything ships.
- `OutboxFailureReason.refusedTerminally` is asserted against the retryable fallback it has to be
  distinguishable from, not only against itself
  (`OutboxPresentationTests.aRefusalDoesNotReadLikeALostConnection`).

**`AccountCopy.signedInBody` was renamed to `storageBody`** in the same change, because it is no
longer a signed-in sentence. That is a rename of a shared identifier and will break any other live
branch that reads it (CLAUDE.md, "Numbering and shared files").

## 2. Ruling 3 reverses half of ERRATA E83, and the half it keeps is the half that matters

E83 records that `failed` is two terminal states and SCREENS.md draws one, and it answered with a
fourth drawn state, `stopped` — the same amber card, its own mono word, no control. The ruling folds
that back in: one drawn terminal row, and the sentence is the whole of the difference.

E83's other argument survives intact and should not be read as overturned with it: a non-retryable
code still fails the item immediately rather than spending 48 h of backoff on an answer BUILD-PLAN §6
says will not change. What changed is only what screen 17 *draws* about the two.

**What the round gave up, stated rather than left to be found.** Screen 17 §6's footnote is "An item
that cannot sync says so, says why, and waits for you", and `This couldn't be sent.` does not say
why. For a terminally refused row the "why" survives only as `lastErrorCode`, which nothing draws.
That is the ruling's trade — the owner had the composed `<cause> This one will not go through on its
own.` in front of them as the alternative — and it is recorded here so a later reader does not read
the footnote as unqualified.

**Six of the eight per-code sentences are unreachable from an outbox row, which is a larger
consequence than it first reads.** `describe` reaches `sentence(for:)` only on the retrying path,
and `OutboxRetryPolicy.nextState` sends every non-retryable code to `.failed` on its first attempt —
so `unauthorized`, `forbidden`, `not_found`, `validation_failed`, `conflict` and
`moderation_rejected` never draw their own line. Three remain in service: the out-of-taxonomy
fallback ("No connection.") and the two retryable codes. The six are kept rather than deleted, with
the reason written at the function; what is *not* kept is any comment elsewhere claiming screen 17
prints one of them, and §6d is that sweep.

**One consequence that is a real behavior change, not only copy.** A refused row carries the retry
control, where `stopped` withheld it — the alternative, a control on one terminal row and not on the
other, is the furniture-level distinction the ruling removed. **It also turned out to be round 2's
finding, because the control did not do what the ruling assumed it did**: see §6a.
`OutboxPresentationTests.theTwoTerminalReasonsDifferOnlyInTheirSentence` holds the drawing and
`OutboxQueueRetryTests` holds the behavior, and both are needed — the first only ever looks at the
row *before* the tap, which is exactly how the defect in §6a survived it.

## 3. The Apple mark: where the geometry came from, and the guideline this does not satisfy

`AppleMark` transcribes Apple's `small` Sign in with Apple logo file — the one Apple's own renderer
uses by default for a button with text — control point for control point, from the path data in
Apple's Sign in with Apple JS SDK
(`https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js`), which the
HIG links to as the way to "get the code". The file's own padding is transcribed with it, because
that padding is what puts the mark on the title's optical centre and it is **not symmetric**: 13.634
above the glyph and 15.834 below, in a 44-unit box. Trimming to the glyph and centring would have
moved the mark down a point, and nothing would have said so.

**Three things Apple asks for that this round does not give, all recorded rather than papered over:**

- **"Use only the logo artwork downloaded from Apple Design Resources; never create a custom Apple
  logo."** Nothing here is drawn by eye, but it is a transcription rather than the file, and the
  literal reading asks for the file. That is the trade ruling 6 takes: R57's "every glyph in this app
  is a `Shape` drawn in this repo" against a vendor asset in the catalog. **App Review evaluates all
  custom Sign in with Apple buttons**, so it is an owner-visible risk and not a private one.
- **"the title's font size would be 43% of the button's height".** SCREENS.md 15 §3 draws 15 px/700
  with `padding:14px`, which is nearer a third. The mock is not this round's to move and the ruling
  says the label does not change, so the mark is sized from the *title* — Apple's own composed rule,
  "the button's height would be 233% of the title's font size" — rather than from the button. The
  proportion between mark and text is Apple's; the proportion between text and button is the mock's.
  Sizing from the title is also the only version that survives Dynamic Type: at AX5 the button's
  height is set by a label on three lines, and a mark matched to that would be half the sheet.
- **The 8% trailing margin between title and button edge** binds only when the title nearly fills the
  control. Screen 15's does not at the drawn size — the mark and the label are centred as a pair, so
  the margin is ~90 pt on a 350 pt button — and at the accessibility sizes where the label wraps, the
  guaranteed margin is Apple's leading minimum rather than 8%. Named because it is a real gap at a
  setting Apple's guideline was not written about — **and it is narrower than this bullet first
  claimed**: measured at AX5 on a 430 pt device the trailing margin is 82.67 pt against Apple's
  31.20, because the label wraps before it can fill the width. It is an absent guarantee, not an
  observed shortfall on any device tried. See §6e.

**`DrawnGlyphGuardTests` needed no extension for ruling 6 and this was measured, not assumed.** Its
tokens are `systemName:` and `systemImage:`, which cover any SF Symbol anywhere in the app target
including this button. What it cannot see is the other half of the ruling:
`ASAuthorizationAppleIDButton` is not a glyph API and spells neither token. Constructing one in
`Cypress/App/AppleSignIn.swift` left `theAppBorrowsNoGlyphs` **green** — run and read, not inferred.
`AppleMarkTests.theAppConstructsNoSystemAppleButton` is the guard for that half, reusing the same
already-calibrated scanner.

## 4. Two sentences the rulings did not reach, and neither is fixed here

### 4a. `YouCopy.privacyBody` says "everything you save stays on this phone", on the same screen

One section below the account card ruling 2 just fixed, the You tab's privacy callout reads:

> *"…everything you save stays on this phone. Public attribution is opt-in, it is off, and there is
> nothing in the app yet that can turn it on."*

The first clause is the **same falsehood** ruling 2 removed from the card above it, from the same
cause: #158's wiring round put `APIOutboxSendSink` behind the outbox, so check-ins and notes leave
the phone under a device credential with no account anywhere (D9). The rest of the sentence is true
and is what ERRATA E100 is about — `User.publicAttribution` cannot be turned on anywhere in the app.

Ruling 2 quoted and replaced `signedInBody` and said nothing about this one, so it stands, wrong,
with the reason written above it in the source. **This is the ask.** It is a small ask: the ruled
sentence one card up is a candidate answer, and the two would then agree.

### 4b. `VisitSaveLedger.storageLine` — screen 18's line under the success block — is still open

Raised in `158-the-app-goes-live-and-three-sentences-stop-being-true.md` §1 and untouched here. Both
of its arms are false for the same reason:

- ask resolved → *"Saving to this phone only. You can add an account any time."*
- otherwise → *"Saved to this phone. You can add an account later to back it up."*

It is a different sentence from ruling 2's, on a different screen, with its own three arms in
PROTOTYPE-FLOW §1.4 keyed on `account ∈ none | ask | linked | dismissed` — and the state the app is
actually in, **anonymous and sent**, is still not one of the four. Ruling 2 does not generalize onto
it: "one body for both arms" was an answer about the account block's two arms, and §1.4's arms are a
different set answering a different question. Naming it here so that "the storage line" is not read
as settled by this round.

## 5. Four things about the ruling text itself, two resolved by reading and two that had to go back to the owner

Recorded because a later reader will meet the same ambiguities in the ruling text. **The two that had
to be asked are listed first, and both were found by the review rather than by the author** — which
is the lesson of the section: round 1 listed only the two below them, and being confident about which
ambiguities are safe to resolve by reading is itself the thing to be suspicious of.

**How wide ruling 1's class is — asked, and the answer changed the app.** The ruling names
`forbidden` and "not retryable"; round 1 read that as the whole non-retryable class, six codes. The
review checked the six one at a time and found five true and one false: a `moderation_rejected` item
**did** leave the phone. The owner ruled the split on 2026-08-15 and gave that code its own sentence
verbatim. This is a scope question about a copy ruling — which is a copy question — and the reading
that widened it was one an engineer should not have taken alone.

**"The distinction lives only in the outbox detail" — asked, and it was a drafting error.** There is
no outbox detail in this app: SCREENS.md 17 draws rows, a wi-fi row, a synced section, a summary
line and a footnote, and `Cypress/Features/Outbox/` is three files. Round 1 silently rendered the
phrase as "the row's own sentence" **inside the staged ruling file** — the document that becomes
law — and then derived the retry-control decision from its own rendering. The owner has acknowledged
the drafting error and ruled the replacement rendering (2026-08-15); the ruling file now quotes the
original phrase, names it as an error, and gives the correction. The rendering happened to be right;
putting it in the permanent record under the owner's name was not.

The two below were resolved by reading, and stand:

**"Screen 18 (account/storage)" is the You tab, not SCREENS.md's screen 18.** SCREENS.md 18 is *Next
tree*, the save confirmation. The repository's own `DebugDeepLink.Screen` labels the You tab `you //
18`, which is where the number in the ruling comes from, and the ruling quotes *"Nothing is
uploaded"* — which is `AccountCopy.signedInBody`'s and nothing else's. The site is unambiguous even
though the number is not; §4b is the sentence that genuinely is on SCREENS.md 18 and it is left open.

**"One body for both arms" is implemented as the card being drawn in both arms**, not merely as one
string serving whichever arm draws it. The anonymous arm drew no body at all before this round, so
the narrower reading would make the clause say nothing. The heading still differs — a signed-in phone
gets `Signed in on this phone`, an anonymous one gets no heading rather than one nobody wrote — and
`AccountCopy.storageCardTitle(isSignedIn:)` is that decision as a value a test can read. If the owner
meant the narrower reading, the change is one `if`.

## 6. Round 2 — what the adversarial review found, and the two rulings it produced

PR #88's reviewer proved six findings, one of them a defect in behavior that the round's own tests
were arranged not to see. All six are fixed on the branch. Two of them went back to the owner and
came back as rulings dated **2026-08-15**, which are recorded in the staged ruling file rather than
only here.

### 6a. The retry control erased the only carrier of the distinction, and drew `waiting` for an item that could never be sent (F1)

Ruling 3 put the whole stopped-versus-will-retry distinction into the row's sentence. `OutboxStore.retry`
sets `state = 'pending'` and **NULLs `last_error` and `last_error_code`** — right for a row about to
be attempted again, and this round left it attached to a control that attempted nothing.
`OutboxView`'s `onRetry` called `OutboxViewState.retry(id:)` and nothing else; there is no drain
behind it, and `syncNow(isOnWifi:)` had **zero call sites in the app**. The only drains were the six
feature writers, which fire when a volunteer saves some *other* piece of work.

Measured by the reviewer on a `forbidden` item through a real `OutboxQueue`:

```
BEFORE TAP:    state=retry    isTerminal=true   showsRetryButton=true   reason=This couldn't be sent.
AFTER TAP:     state=waiting  isTerminal=false  showsRetryButton=false  reason=nil
               item.state=.pending  errorCode=nil  waitingCount=1  failedCount=0
AFTER A DRAIN: state=retry                                              reason=This couldn't be sent.
```

So the tap was not a no-op. It drew the row as `waiting` — SCREENS.md 17's word for "still trying" —
counted it in the header's `N waiting` pill, removed the sentence entirely, and left it there until
an unrelated save happened along. Screen 17 §6 promises that an item which cannot sync "says so, says
why, and waits for you"; after one tap it said neither.

**The fix is to make the control do what its label says**: `retry(id:)` and `retryAll()` now drain,
so a row is `waiting` only while it really is being attempted, and the service's answer returns a
refused item to `failed` with its sentence on the first attempt (E83's fail-immediately). The other
candidate — preserving `last_error_code` across the retry — was considered and is not sufficient
alone: nothing draws the code since ruling 3 stopped `OutboxPresentation.state(for:)` reading it, so
every drawn moment would have been exactly as wrong.

**Why the suite did not see it, which is the part worth carrying forward.**
`theTwoTerminalReasonsDifferOnlyInTheirSentence` is a real guard and it red-proves correctly — but it
reads the row *before* the tap. The round wrote a test for the drawing the ruling specified and none
for the behavior of the control the same ruling insisted on keeping. That is this project's dominant
family (a guard green with the defect present) arrived at from a direction the family's own note does
not name: not a check that ran on nothing, but a check that ran one frame too early.

**One thing the fix does not reach, named rather than implied.** With the remote gate `.disabled`
there is no send sink at all, so a drain settles nothing and a retried row does sit `pending` with no
sentence. That is a property of the gate — every item in that configuration waits forever — and not
of this control; it is the same state the queue is in before anyone taps anything.

### 6b. A sentence ruled for one code was applied to six, and for `moderation_rejected` it was false (F2)

Round 1 read ruling 1's "`forbidden`, not retryable" as the whole non-retryable class. The reviewer
checked the six one at a time against what each row used to say, and found the widening true of five
and false of one: a `moderation_rejected` item **reached `cypress-sync`**, the request was accepted,
and a person read the content and declined it. "This couldn't be sent." tells that volunteer their
work never left the phone.

**Ruled by the owner on 2026-08-15**: `moderation_rejected` reads `This was reviewed and won't be
shared.`, verbatim; the other five keep `This couldn't be sent.` The split is in
`OutboxFailureReason` with the argument written at both constants.

`DataLayerWiringTests.theSendPathCannotProduceARemoteSurface` is the test that would have caught it —
it used to assert `reason.contains("A moderator declined this.")` and round 1 relaxed it to
`reason == refusedTerminally` as "a correct consequence of the widening". It is the round's clearest
instance of a test being loosened to fit a change instead of the change being questioned. It now
asserts `moderationDeclined` for the `moderation_rejected` fixture it has always used, which is a
tighter assertion than either.

`conflict` is the softer case the reviewer also raised: the proximity dedupe returns it because the
thing is *already recorded*, so "couldn't be sent" points at the wrong cause even though nothing
landed. The owner ruled the split at `moderation_rejected` only, and `conflict` keeps the shared
sentence. Named here because it is the next one anybody will ask about.

### 6c. The new glyph guard named the UIKit spelling only (F4)

`AppleMarkTests.theAppConstructsNoSystemAppleButton` was written after measuring that
`DrawnGlyphGuardTests` cannot see `ASAuthorizationAppleIDButton`. It could not see
`SignInWithAppleButton` either — `AuthenticationServices`' SwiftUI view, which is the API a SwiftUI
codebase actually reaches for. The reviewer compiled
`SignInWithAppleButton(.continue, onRequest:onCompletion:)` into `AccountProviderButton`, the exact
control ruling 6 governs, and **both guards passed**.

The guard now scans both spellings, and its prose control is **per token** rather than shared: one
counter would have let a newly added token be "controlled" by an older token's mention while matching
nothing itself. `AppleMark`'s header names both spellings deliberately and says that it is the
anchor.

### 6d. Five sites still described a sentence screen 17 no longer prints (F5)

`AppSession.swift`, `AuthHTTP.swift`, `RemoteAPI.swift`, `server/README.md` and two test files all
said that an `unauthorized` on an item "prints 'Sign in to send this' to somebody who is signed in".
That was E261 §3's design rationale and it was true when written; after ruling 1 a failed
`unauthorized` row reads "This couldn't be sent." Each site now states the current sentence and says
what it used to say, because the counterfactual framing ("if a 401 reached an outbox item, then…") is
exactly what makes a stale claim read as current. E261's own numbered entry in `docs/ERRATA.md` is
left alone: it is the record of what was true then.

The defect those comments exist to design out is unchanged, and it is arguably worse dressed the new
way — the row now says nothing at all about the session to somebody whose token only needed
refreshing.

### 6e. What the reviewer verified rather than doubted, recorded because it is evidence

The transcription in §3 was re-derived independently: `appleid.auth.js` fetched, `M.small` parsed,
and **all 59 control points** compared against `AppleMark` after translating x by −6. Every point
matches to seven significant figures, with the comparator calibrated first — 59 mismatches at a wrong
translation, 2 with a single coordinate moved by 0.5. The crop offset, the padding figures and the
0.5/0.7 placement fractions were each traced back to the renderer's own arithmetic rather than to
Apple's prose.

Two measurements from that pass correct claims made here in round 1:

- **The "at cap height" description is a standard-size observation.** At AX5 the label wraps to
  `Continue` / `with Apple` and the mark centres against the two-line block. Nothing specifies this
  and the reviewer did not call it a defect; it is stated because the narrower claim read as general.
  At the drawn size, measured on an iPhone 16 Plus: mark **9.33 × 11.33 pt** against a predicted
  9.39 × 11.54, gap to title **7.00 pt** against Apple's 6.67 minimum, the mark's top 1.33 pt above
  cap height.
- **The 8% trailing-margin deviation §3 names is narrower than §3 claimed.** Measured at AX5 on a
  430 pt device the trailing margin is **82.67 pt** against Apple's 31.20, because the label wraps
  before it can fill the width. The deviation is real as an absence of a guarantee, not as an
  observed shortfall on any device tried.
