import Foundation

/// The two doors at the deletion step, and which one is the default.
///
/// The project owner's ruling, in their words: *"account deletion should have an option—one kills all
/// photos, up votes, etc, the other leaves them in place and tags them to an anonymous/deleted
/// account, with that being the default."*
///
/// RULINGS **R3** decided this question for everybody at once and decided it the kind way: the forest
/// keeps the record, the person stops being named on it. That was the right *default* and the wrong
/// *rule*, because the two things a person can mean by "delete my account" are genuinely different
/// wishes and neither is unreasonable. One person is saying "I am done with this app, don't keep my
/// name on things". Another is saying "I want what I put here gone". An app that hears only the first
/// is telling the second person no, silently, at the moment they are least able to argue.
///
/// So this is a choice, and it is not a choice the implementation gets to make by accident, which is
/// why it is a type in `Core` rather than a boolean parameter with a default value somewhere in
/// `Data`. Every layer that can delete an account has to name a door.
///
/// ── What "anonymous" means in the database, and why it is NULL rather than a sentinel ──────────
/// `leaveRecords` nulls the owner column. It does **not** re-home the row onto a stand-in
/// "deleted account" id, and the alternative was close enough to argue properly.
///
/// A sentinel has one real advantage: it preserves the fact that a set of contributions came from
/// *one* person. This app has a moderation surface, and a moderator looking at forty bad
/// observations wants to know whether they are forty people or one. Under NULL they cannot tell.
/// That cost is real and is accepted here.
///
/// It is accepted because a sentinel is a pseudonym, and a pseudonym is not anonymity. These rows
/// carry a tree, a date and a time. A stable id joining a person's whole history of them reconstructs
/// where somebody walked, how often, and when — in one city, at street-tree resolution. Anybody who
/// can read the database can do it, and the person who asked to be forgotten cannot know it is
/// possible. Deletion is a privacy promise, and a promise that leaves behind a key which relinks
/// everything it claimed to unlink is the version of this feature that would be worst to ship,
/// because nothing on screen would ever reveal it.
///
/// The moderation argument is also weaker than it first looks. Moderation acts on accounts that can
/// still act; a deleted account cannot contribute again, so there is no future pattern to catch, and
/// the past pattern is precisely the thing being dissolved. A person who wants their contributions
/// gone rather than merely unnamed already has `eraseEverything`, which removes the rows a moderator
/// would have been reviewing.
///
/// ── Which records this choice governs, and which it does not ──────────────────────────────────
/// It governs **contributions**: visits, observations, measurements, care events, photographs and
/// their bytes, photo votes, tree names and review flags. Each of those has value to the forest
/// independent of who made it, which is §3.12's own definition and the entire argument for a door
/// that keeps them.
///
/// It does **not** govern private reminders or favourites. Those are deleted under both doors, and
/// that is a ruling rather than an oversight. R3 made the argument and it survives the second door
/// intact: nobody but their owner can read them, and after anonymization nobody at all can — an
/// ownerless favourite is a row no query returns and no person can remove. Offering to "keep" one
/// would be offering to keep a thing that nothing can display, which is not a choice, it is a
/// decorative control. The engine says the same thing in its own words: both tables carry
/// `CHECK ((user_id IS NULL) <> (device_id IS NULL))`, so an ownerless row is unstorable.
///
/// The copy therefore states their deletion **unconditionally**, above both doors, rather than
/// inside either. See `AccountDeletionCopy.personalRecords`.
public enum AccountDeletionChoice: String, Sendable, CaseIterable, Codable {

    /// Contributions stay on the trees they were made about, with the account's name taken off them.
    ///
    /// **The default**, and the order of this enum's cases is the order the surface draws them.
    case leaveRecords

    /// Contributions are deleted outright — rows and, for photographs, the bytes on disk.
    ///
    /// The one thing this cannot promise is that nobody has already seen them; there is no server and
    /// nothing has been uploaded (`BetaCapability`, ERRATA E124), so on this app as it stands it is a
    /// complete erasure and the copy is allowed to say so plainly.
    case eraseEverything

    /// What a surface starts on when nobody has chosen yet.
    ///
    /// Stated once, here, so that no view or model can drift into defaulting to the destructive door
    /// by initialising a variable carelessly. `AccountDeletionCopy` is written to match.
    public static let `default` = AccountDeletionChoice.leaveRecords
}
