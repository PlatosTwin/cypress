# Rulings pending: "Only you can see it" replaces "on this phone" (owner's ruling, 2026-11-15)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

---

### R??? — A tree only its adder can see says "Only you can see it", not "on this phone"

**Decided by:** the owner, in a question dialog on 2026-11-15.

**The question, as put:**

> I found that the approved lines say something untrue. A tree added by a signed-out person, or by a
> person who did not agree to share, is not only on the phone: the phone sends it to the Cypress
> service, which keeps it private until they sign in or agree. The approved lines say "on this
> phone" and "This tree is only on this phone." Should the wording change?

**Offered:**
- "Say "Only you can see it" (Recommended)"
- "Keep the approved lines"

**Chosen:** "Say "Only you can see it"".

**The fact behind the question, checked in the code (round C3, package A).**
- The phone queues every add for the service, signed in or not: `LocalAPI.addTree` writes the
  `add_tree` item in the same transaction as the tree (`queueAppliedMutation`).
- The service stores the tree and keeps it private unless its owner is an account that agreed to
  the license. `insertCommunityTree` sets `published_at` only from `publicationStamp`, which answers
  nil for a device owner (`owner.UserID == nil`) and for an account with no accepted license
  (`server/internal/store/community_trees.go`).
- A sign-in publishes the device's trees only if the account agreed: `claimCommunityTrees` sets
  `published_at` only when `accepted` (same file).
- Agreeing later publishes the account's held trees: `RecordLicenseConsent` calls
  `publishAccountTrees` when a known license version is recorded
  (`server/internal/store/identity.go`), and `publishAccountTrees` sets `published_at` on every
  tree of that account that has none.

**The four replacement strings, exactly:**

| Where | State | String |
|---|---|---|
| The tree's profile | Signed out | "Only you can see this tree. Everyone can see it after you sign in." |
| The tree's profile | Signed in, not sharing | "Only you can see this tree. Everyone can see it after you agree to share your tree records." |
| The note under Add this tree | Signed out | "Recorded as community-added and unverified. Only you can see it. Everyone using Cypress can see it after you sign in." |
| The note under Add this tree | Signed in, not sharing | "Recorded as community-added and unverified. Only you can see it. Everyone using Cypress can see it after you agree to share your tree records." |

**What it replaces in `community-trees-c3-answers.md` (2026-11-14):**
- "The note under the Add this tree button", answer 2: "Recorded as community-added and unverified,
  on this phone. Everyone using Cypress can see it after you sign in." and "Recorded as
  community-added and unverified, on this phone. Everyone using Cypress can see it after you agree
  to share your tree records."
- "Other people's community trees", answer 3: "This tree is only on this phone. Everyone can see it
  after you sign in." and "This tree is only on this phone. Everyone can see it after you agree to
  share your tree records."

**What it leaves alone.** The signed-in-and-sharing note ("Recorded as community-added and
unverified. Everyone using Cypress can see it once it is sent."), and the note for a phone that does
not know the sharing answer, which the owner chose to keep as today's line ("Keep today's note",
`community-trees-answers-2026-11-15.md`).

**Built:** the two profile lines, by round C3's package A (`TreeProfileCopy.onlyYouSignedOut`,
`TreeProfileCopy.onlyYouNotSharing`). The two Add this tree notes are another package's.
