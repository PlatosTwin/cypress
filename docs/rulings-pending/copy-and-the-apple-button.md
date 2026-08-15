# The copy round — the owner's rulings of 2026-08-14 on screens 15, 17 and the You tab

*(Unnumbered; the orchestrator splices this under the real next number at merge. Five rulings from
2026-08-14, each taken as an explicit choice among stated alternatives, **plus two corrections the
owner ruled on 2026-08-15** after the adversarial review of PR #88 — the `moderation_rejected`
sentence, and the rendering of where the stopped-versus-will-retry distinction lives. Both
corrections are marked in place and dated. Ruling 5 of the original round — session restore — is a
separate ticket and is not here. Implemented on `feat/copy-rulings`; the evidence for each, and the
things the round found that the rulings do not cover, are in
`docs/errata-pending/the-copy-round-and-what-it-did-not-reach.md`.)*

Every sentence below had gone false under the app while it was still being drawn. #158's wiring round
gave the outbox a send sink over `cypress-sync`, and #158 step 5 made `Continue with Apple` a real
exchange; between them they falsified a family of promises about where a volunteer's work lives. Each
was left standing on purpose, because copy is the owner's under DECISIONS constraint 21. These are
the answers.

**A terminally refused outbox item says `This couldn't be sent.`** Screen 17's row for an item the
service refused with a code the taxonomy says will not change — `forbidden` and its five siblings —
carries that sentence and no other. It replaces the composed `"<cause> This one will not go through
on its own."`, and it must stay distinguishable from the retryable `No connection.` state, which is a
row that is still trying. The eight per-code sentences remain for a row that is still retrying and
are no longer drawn for one the service has finished with; screen 17's footnote promise that an item
"says why" is narrowed by that, deliberately.

**`moderation_rejected` is the one exception, and it reads `This was reviewed and won't be shared.`**
*(Ruled verbatim by the owner on **2026-08-15**, narrowing the sentence above after PR #88's review
found it applied to six codes rather than one.)* The other five terminal codes — `forbidden`,
`validation_failed`, `conflict`, `not_found`, `unauthorized` — keep `This couldn't be sent.`, which
the reviewer checked sibling by sibling and found true of each. It is not true of this one: a
`moderation_rejected` item **reached the service**, the request was accepted, and a person read the
content and declined it. "This couldn't be sent." tells that volunteer their work never left the
phone, which is a false claim about where their field work is (ARCHITECTURE §5.4, DECISIONS
constraint 3 — the rule this whole round exists to enforce).

**The `stopped` state folds into the failed row, and there is no fourth drawn state.** ERRATA **E83**
invented `stopped` — the same amber C24 card as `retry`, its own mono word, and no control — because
`failed` means two different things and SCREENS.md 17 draws one treatment. The ruling reverses that
half of E83: SCREENS.md 17's "States drawn" line is `waiting`, `retry`, `synced`, and it stays three.
A refused item draws the failed row, control included. The rest of E83 stands: the taxonomy still
fails a non-retryable item immediately rather than burning 48 h of backoff on an answer that will not
change.

> **Where the distinction lives — the owner's correction of 2026-08-15, and the drafting error it
> corrects.** As first written, this ruling said *"The stopped-vs-will-retry distinction lives only
> in the outbox detail."* **There is no outbox detail.** SCREENS.md 17 draws a queue of rows, a wi-fi
> row, a synced section, a summary line and a footnote; there is no detail screen, no navigation off
> a row, and none is being built. The owner has acknowledged the phrase as a drafting error and ruled
> the rendering that replaces it:
>
> **The row's sentence is the distinction.** A terminal row reads its terminal sentence — ruling 1's,
> or the `moderation_rejected` sentence above — and a retryable row reads the retryable one. Same
> card, same furniture, same control; the words carry it.
>
> Two things follow, and both are the ruling rather than a reading of it. The retry control is *not*
> withheld from a refused row, because withholding it would put the distinction back onto the row's
> furniture. And the sentence has to **survive a retry tap** — a control that erases the only carrier
> of the distinction defeats the ruling, which is what PR #88's review found it doing (F1) and what
> the drain behind `OutboxViewState.retry(id:)` fixes.

**The You tab's account block says `Check-ins and notes sync to your grove. Photos stay on this phone
until you choose to share them.`** It replaces `AccountCopy.signedInBody`'s *"This account gathers
what you save here under one name on this device. Nothing is uploaded, and nothing about you is
public."*, whose middle clause was false in two independent ways. **One body for both arms** —
anonymous and signed-in — so the card is drawn in the signed-out arm too, which is the state the old
sentence was most wrong about and the one arm that never drew it. The claim that photographs do not
upload is true today; **the round that lands the photo sink revisits this sentence**, and the owner
said so as part of the ruling.

**Screen 15's deferred routes say `Google and email sign-in are coming later.`** It replaces
*"Accounts are not ready yet"*, which was written when no route on that screen worked and stopped
being true beside a `Continue with Apple` that signs people in. The notice's second sentence —
"Everything you have saved stays on this phone." — is §7's own promise and is untouched: the ruling
quoted the first clause and replaced that.

**Screen 15's Apple button draws the Apple logo as a vector shape.** Into the existing drawn control,
per Apple's Sign in with Apple custom-button guidelines, with the geometry taken from Apple's
published artwork rather than from memory — consistent with RULINGS **R57**, which makes every glyph
in this app a `Shape` drawn in this repository. **No SF Symbol and no
`ASAuthorizationAppleIDButton`.** The button's fill token and its label do not change.

R57 is amended by that last one only in what it now covers: the policy's own statement in
`ShareDestinationGlyph` argues in passing that Apple glyphs "would put three vendors' marks on one
row of a screen that draws its own", which was about screen 10's share row and is unaffected. Screen
15's mark is a vendor's own requirement on that vendor's own control, and it is the first drawn glyph
in the app whose geometry is not this project's to choose. What that costs is written up in the
errata entry: Apple's guidelines ask for the downloaded artwork file itself, and this is a
transcription of it.
