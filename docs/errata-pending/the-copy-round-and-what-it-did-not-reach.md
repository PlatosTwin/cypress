# Unnumbered — the copy round: what the owner's five rulings fixed, and the two sentences beside them that are still false

Staged unnumbered per CLAUDE.md's "Numbering and shared files"; the orchestrator splices it under the
real next number at merge. Written on `feat/copy-rulings`, the round that implements the owner's
rulings 1, 2, 3, 4 and 6 of **2026-08-14** (the rulings themselves are staged in
`docs/rulings-pending/copy-and-the-apple-button.md`).

Everything below was checked against the code, the tests or the running screen. The two findings in
§4 are new with this round and are **not** ruled.

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
why. The eight per-code sentences still exist and are still drawn for a row that is retrying; for a
terminally refused row the "why" is now only in `lastErrorCode`, which nothing draws. That is the
ruling's trade — the owner had the composed `<cause> This one will not go through on its own.` in
front of them as the alternative — and it is recorded here so a later reader does not read the
footnote as unqualified.

**One consequence that is a real behavior change, not only copy.** A refused row now carries the
retry control, where `stopped` withheld it. Tapping it re-queues an item the service will refuse
again. That is deliberate and is what "the distinction lives only in the outbox detail" requires; the
alternative — a control on one terminal row and not on the other — is the furniture-level distinction
the ruling removed. `OutboxPresentationTests.theTwoTerminalReasonsDifferOnlyInTheirSentence` is what
holds it, and its assertion on `showsRetryButton` is the load-bearing one.

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
  setting Apple's guideline was not written about.

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

## 5. Two things about the ruling text itself that were resolved by reading rather than by asking

Recorded because a later reader will meet the same two ambiguities in the ruling text.

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
