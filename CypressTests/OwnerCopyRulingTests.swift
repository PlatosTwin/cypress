//
//  OwnerCopyRulingTests.swift
//  CypressTests
//
//  The three sentences the owner ruled on 2026-08-14 that are not the outbox's — rulings 2 and 4,
//  with ruling 1's proved beside the behavior it belongs to in `OutboxPresentationTests`.
//
//  ── Why a suite that asserts phrasing, when this project's rule is to assert facts ──────────────
//  Because here the phrasing *is* the fact. Every string below replaced one that had gone false
//  under it — "Nothing is uploaded" on a phone that uploads, "Accounts are not ready yet" beside a
//  working sign-in — and each was left standing for a round on purpose, because copy is the owner's
//  under DECISIONS constraint 21. What these tests guard is not that the words are good; it is that
//  the words on the phone are the words that were ruled, and that the clause a ruling deliberately
//  did *not* touch is still there.
//
//  Where a claim can be checked against behavior instead, it is: `storageBody`'s photo clause is
//  asserted against the outbox's actual sinks, not against itself.
//

import Foundation
import Testing
@testable import Cypress

@Suite("The copy the owner ruled on 2026-08-14")
struct OwnerCopyRulingTests {

    // MARK: - Ruling 2 · the storage sentence, one body for both arms

    /// The second clause changed in the photo-send round, which owner ruling 2 of 2026-08-14
    /// anticipated: the sink that makes "photos stay on this phone" false is the one that round
    /// landed. **The new clause is a proposal pending ratification** — it is pinned here so that it
    /// cannot drift unnoticed while it waits, not because it is settled.
    @Test("the account block draws the ruled storage sentence")
    func theAccountBlockDrawsTheRuledSentence() {
        #expect(
            AccountCopy.storageBody
                == "Check-ins and notes sync to your grove. Photos you add from now on upload too; "
                + "older ones stay on this phone."
        )
    }

    /// "One body for both arms (anonymous and signed-in)." The heading differs; the body does not,
    /// and there is no arm in which the card is absent — which `AccountSection` guarantees by
    /// drawing it outside the `isSignedIn` branch rather than once inside each.
    @Test("only the heading differs between the two arms")
    func onlyTheHeadingDiffersBetweenTheArms() {
        #expect(AccountCopy.storageCardTitle(isSignedIn: true) == AccountCopy.signedInTitle)
        #expect(AccountCopy.storageCardTitle(isSignedIn: false) == nil)
    }

    /// The sentence's second clause is a claim about this build, and the owner said in the same
    /// ruling that it stops being true when the photo sink lands. So it is pinned to the thing that
    /// would land it rather than to itself.
    ///
    /// **The claim is about the *send* side and only the send side.** A drain does two things
    /// (`OutboxQueue`, ERRATA E261 §2): **apply**, which ingests the staged binary into this app's
    /// own container through `LocalAPI.uploadPhoto`, and **send**, which is the only half that
    /// reaches a service. The first draft of this test asserted that a drained item still carried
    /// its `OutboxPhoto` paths and went red on a green build — the paths clear because the *local*
    /// commit consumed them, which is the sentence being kept rather than broken. A test that
    /// cannot tell those two halves apart is worse than none, because it reads as evidence about
    /// the wrong one.
    ///
    /// So the pin is on `OutboxSendSink`'s own surface, read off the source: one method, `sync`,
    /// and `SyncItemBody` has no field a binary could ride in. `RemoteWire`'s own header already
    /// says what a photo method there would be called — "were the send side ever given a photo
    /// method — `uploadPhoto(at:ticket:)`" — and this is what makes adding it red.
    @Test("nothing on the send side can carry a photograph, which is what the sentence promises")
    func nothingOnTheSendSideCanCarryAPhotograph() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Cypress/Data/Outbox/OutboxQueue.swift"),
            encoding: .utf8
        )
        let code = BorrowedGlyphAPI.codeOnly(in: source).components(separatedBy: "\n")

        guard let start = code.firstIndex(where: { $0.contains("protocol OutboxSendSink") }) else {
            Issue.record(
                """
                `protocol OutboxSendSink` is not in Cypress/Data/Outbox/OutboxQueue.swift any more, \
                so this guard scanned nothing. It moved or it was renamed; follow it, do not delete \
                this test.
                """
            )
            return
        }
        guard let end = code[start...].dropFirst().firstIndex(where: { $0.hasPrefix("}") }) else {
            Issue.record("the protocol body has no closing brace at column 0 — the scan cannot bound it")
            return
        }

        let methods = code[start..<end]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("func ") }
        // The control: a scan that found no methods would pass the assertion below by seeing
        // nothing, which is this project's signature false green.
        #expect(!methods.isEmpty, "the scan bounded the protocol and found no methods in it at all")

        // ── What this guard pins now, and why it changed shape ─────────────────────────────────
        //
        // It used to assert `methods.count == 1`, i.e. that the send side had no photo method at
        // all. That was the right pin while the sentence was the only thing holding, and its own
        // message named the exit: "the owner said in ruling 2 of 2026-08-14 that the round which
        // lands the photo sink revisits the sentence. This is that round."
        //
        // The sink has landed, so a count is no longer the invariant — the **pairing** is. The
        // promise `AccountCopy.storageBody` makes is only false if a photograph can actually leave,
        // so the two facts have to agree in one direction or the other, and this asserts exactly
        // that: if the send side can carry a binary, the copy must not still say it cannot. Written
        // as a biconditional rather than as a new fixed expectation, so that reverting the sink
        // reverts the requirement instead of leaving a stale assertion behind.
        let carriesPhoto = methods.contains { $0.lowercased().contains("photo") }
        // **The claim, not the retired literal** (#116 review N6). Matching the exact old sentence
        // pinned the wording this round happens to have removed, so a differently-worded promise
        // that photographs stay put would pass the guard vacuously — and since the section is
        // explicitly awaiting a copy decision, a reword is the likeliest thing to happen to it.
        //
        // So the question is asked twice, from both sides, and the copy has to answer consistently:
        // does it say photographs stay on the device, and does it say they travel? A sentence that
        // does neither is also a failure — it would leave the app silent about photographs while
        // the sink uploads them.
        //
        // **The literal, not the file**, still: `AccountSection.swift` quotes the retired sentence
        // in the doc comment explaining why it was retired, so a `contains` over the source would
        // find the old promise in the prose recording its own removal.
        // **Clause by clause, because the true sentence contains both halves.** R77 makes the
        // promise a split one — new photographs upload, older ones do not — so any guard that
        // simply looked for "stay on this phone" anywhere in the body would fire on the correct
        // copy. What is actually under test is narrower and is the thing a person reads: **does the
        // clause that talks about photographs say they can leave?**
        //
        // A stays-put-only wording fails this however it is phrased, because such a sentence has no
        // verb of travel in its photograph clause — which is what makes this pin the claim rather
        // than the particular words this round happened to choose.
        //
        // Limits, stated rather than implied: it is a keyword rule over English, so a wording that
        // avoided all five verbs would slip past it. It is a tripwire for a reworded promise, not a
        // proof, and the exact sentence is separately pinned by the test above.
        let clauses = AccountCopy.storageBody
            .lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ".;"))
            .filter { $0.contains("photo") }
        let travelVerbs = ["upload", "sync", "share", "back up", "backed up"]
        // **A negated travel verb is not a travel claim** (#116 review N11). "Photos are never
        // uploaded from this phone" contains "upload", and the first version of this scan read that
        // as travel — passing the guard while the sentence promised exactly what the sink makes
        // false. It is the wording a careful copywriter is *most* likely to produce, because it is
        // the natural way to say the thing this round removed.
        let negators = ["never", "not ", "n't", "no longer", "without"]
        let photographsTravel = !clauses.isEmpty && clauses.contains { clause in
            travelVerbs.contains { clause.contains($0) } && !negators.contains { clause.contains($0) }
        }

        let claimsPhotosStayOnDevice = !photographsTravel
        #expect(
            carriesPhoto != claimsPhotosStayOnDevice,
            """
            `OutboxSendSink` declares \(methods) and `AccountCopy.storageBody` \
            \(claimsPhotosStayOnDevice ? "still says" : "no longer says") photos stay on this \
            phone. Those two cannot both be true: a send sink that carries a binary means a \
            photograph leaves, and the sentence promises it does not. Owner ruling 2 of \
            2026-08-14 says the round landing the photo sink revisits the sentence — change the \
            copy or remove the method, do not leave the app saying something it does not do.
            """
        )

        // The other half of the same promise: `POST /sync`'s item body has nowhere to put one.
        let wire = try String(
            contentsOf: root.appendingPathComponent("Cypress/Data/API/RemoteWire.swift"),
            encoding: .utf8
        )
        let wireCode = BorrowedGlyphAPI.codeOnly(in: wire).components(separatedBy: "\n")
        guard let bodyStart = wireCode.firstIndex(where: { $0.contains("struct SyncItemBody") }),
              let bodyEnd = wireCode[bodyStart...].dropFirst().firstIndex(where: { $0.hasPrefix("}") })
        else {
            Issue.record("`struct SyncItemBody` is not where this guard looks for it in RemoteWire.swift")
            return
        }
        let fields = wireCode[bodyStart..<bodyEnd]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("let ") }
        #expect(!fields.isEmpty, "the scan bounded SyncItemBody and found no fields in it at all")
        #expect(
            !fields.contains(where: { $0.lowercased().contains("photo") }),
            "`POST /sync`'s item body carries \(fields.filter { $0.lowercased().contains("photo") })"
        )
    }

    // MARK: - The 2026-08-15 correction · one terminal sentence turned out to be two

    /// **A sweep over the whole taxonomy, because the thing it replaces was a scope error.**
    ///
    /// Round 1 read ruling 1's "`forbidden`, not retryable" as the whole non-retryable class and
    /// gave six codes one sentence. Five of the six are fine; `moderation_rejected` is not, because
    /// that item **reached the service** and a person declined it — "This couldn't be sent." is a
    /// false claim about where somebody's field work is. The owner ruled the split on 2026-08-15.
    ///
    /// **The expectation is a `switch` with no `default`, and that is the whole of the fix for the
    /// second version of the same error (PR #88 review, F2b).**
    ///
    /// The first version of this sweep wrote the expectation as
    /// `code == .moderationRejected ? moderationDeclined : refusedTerminally`, over a
    /// `CaseIterable` loop, and claimed in this comment that "a taxonomy code added later arrives
    /// here with no opinion attached, and this says so". It did not say so. A ternary is a
    /// **default**: the reviewer added a hypothetical `case quotaExceeded`, marked it non-retryable
    /// and gave it a retrying sentence — the two decisions the compiler already forces — and the
    /// suite passed green with the new code silently inheriting "This couldn't be sent." That is
    /// round 1's error arriving by the same route, past the test written to prevent it, wearing a
    /// comment that promised otherwise. A comment is not a test (CLAUDE.md).
    ///
    /// `ruledSentence(for:)` below is exhaustive over `APIError` with no `default`, so a new case
    /// **fails the build at this line** rather than borrowing an answer. That is a step past the
    /// dictionary-and-`#require` form the review suggested, and deliberately: a dictionary literal
    /// is not exhaustive either, so a missing key would have been a red test at run time rather
    /// than the build failure the suggestion described. Three sites now stop a new code —
    /// `APIError.retryable`, `OutboxFailureReason.sentence(for:)`, and this one — and this is the
    /// only one of the three that asks the question that matters for the copy.
    ///
    /// **Both directions measured, with the reviewer's own hypothetical.** With `quota_exceeded`
    /// added to `APIError` and both compiler-forced sites answered, this form gives exactly one
    /// error — `OwnerCopyRulingTests.swift:166:13: error: switch must be exhaustive` — and the
    /// ternary it replaced gives `Test run with 7 tests in 1 suite passed after 0.030 seconds`,
    /// green, with the new code inheriting "This couldn't be sent." unasked. The second half is the
    /// control: on its own, a build failure is only evidence that *something* changed.
    @Test("every terminal code gets the sentence the owner ruled for it, and no other")
    func everyTerminalCodeGetsItsRuledSentence() throws {
        /// What screen 17 must draw for a terminal row carrying `code`, or nil where the code is
        /// retryable and this ruling does not reach it.
        ///
        /// **If you are here because this stopped compiling, the new code needs an owner's answer
        /// to one question before it can join either group: did the item reach the service?**
        /// "This couldn't be sent." says it did not, and is false of anything that did — which is
        /// exactly how `moderation_rejected` came to be wrong. Do not add a `default`.
        func ruledSentence(for code: APIError) -> String? {
            switch code {
            case .unauthorized, .forbidden, .notFound, .validationFailed, .conflict:
                // Never left the phone: refused before or at the boundary.
                return OutboxFailureReason.refusedTerminally
            case .moderationRejected:
                // Arrived, was read by a person, and will not be published (owner, 2026-08-15).
                return OutboxFailureReason.moderationDeclined
            case .rateLimited, .serverError:
                // Retryable, so no terminal sentence of its own; the control half below covers it.
                return nil
            }
        }

        let moderated = OutboxFailureReason.describe(
            error: APIError.moderationRejected, failCount: 1, state: .failed
        )
        #expect(moderated == "This was reviewed and won't be shared.")

        var swept = 0
        for code in APIError.allCases where !code.retryable {
            let expected = try #require(
                ruledSentence(for: code),
                "`\(code.rawValue)` is non-retryable and has no terminal sentence ruled for it"
            )
            let sentence = OutboxFailureReason.describe(error: code, failCount: 1, state: .failed)
            swept += 1
            #expect(
                sentence == expected,
                """
                a terminal `\(code.rawValue)` row reads "\(sentence)" against the ruled \
                "\(expected)".
                """
            )
        }
        // The sweep has to have swept: `allCases` filtered to nothing would pass every assertion
        // above by making none of them.
        #expect(swept == 6, "the sweep covered \(swept) non-retryable codes, not the 6 that exist")

        // The retryable half is untouched by either ruling and still composes the per-code cause.
        // It is the control for the sweep above, which would otherwise pass on a build where
        // `describe` answered one string to everything.
        for code in APIError.allCases where code.retryable {
            let sentence = OutboxFailureReason.describe(error: code, failCount: 1, state: .pending)
            #expect(sentence != OutboxFailureReason.refusedTerminally)
            #expect(sentence != OutboxFailureReason.moderationDeclined)
            #expect(sentence == OutboxFailureReason.sentence(for: code))
        }
    }

    /// The two terminal sentences disagree about the one fact they are split on. Asserted on the
    /// words rather than only on the constants, because the words are what the owner ruled.
    @Test("the two terminal sentences say opposite things about whether the item left the phone")
    func theTwoTerminalSentencesDisagreeAboutWhereTheWorkIs() {
        #expect(OutboxFailureReason.refusedTerminally == "This couldn't be sent.")
        #expect(OutboxFailureReason.moderationDeclined == "This was reviewed and won't be shared.")
        #expect(OutboxFailureReason.moderationDeclined != OutboxFailureReason.refusedTerminally)
        // The moderated sentence must not claim the send failed — that is the whole finding.
        #expect(!OutboxFailureReason.moderationDeclined.lowercased().contains("sent"))
    }

    // MARK: - Ruling 4 · screen 15's deferred routes

    /// The ruling quoted and replaced the first sentence only. The second is §7's own promise and
    /// stands.
    @Test("screen 15's notice names the two deferred routes and keeps its second sentence")
    func theUnavailableNoticeNamesTheDeferredRoutes() {
        #expect(
            AccountAskCopy.noticeUnavailable
                == "Google and email sign-in are coming later. Everything you have saved stays on "
                + "this phone."
        )
        #expect(AccountAskPresentation.Notice.unavailable.text == AccountAskCopy.noticeUnavailable)
    }

    /// The notice the two deferred routes draw is not the one a real failure draws. They were
    /// separate sentences before this round and the ruling did not merge them; a build that
    /// collapsed the two would tell somebody who tapped `Use email` that something went wrong.
    @Test("a deferred route and a failed one still say different things")
    func aDeferredRouteAndAFailedOneStillDiffer() {
        #expect(AccountAskCopy.noticeUnavailable != AccountAskCopy.noticeFailed)
        #expect(AccountAskCopy.noticeFailed.hasPrefix("That did not go through."))
    }
}
