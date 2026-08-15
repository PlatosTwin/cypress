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

    @Test("the account block draws the ruled storage sentence")
    func theAccountBlockDrawsTheRuledSentence() {
        #expect(
            AccountCopy.storageBody
                == "Check-ins and notes sync to your grove. Photos stay on this phone until you "
                + "choose to share them."
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
        #expect(
            methods.count == 1 && methods[0].hasPrefix("func sync("),
            """
            `OutboxSendSink` now declares \(methods) — the send side has grown a method beyond \
            `sync`. If that method carries a photograph, `AccountCopy.storageBody`'s second clause \
            ("Photos stay on this phone until you choose to share them") is no longer true, and the \
            owner said in ruling 2 of 2026-08-14 that the round which lands the photo sink revisits \
            the sentence. This is that round.
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
