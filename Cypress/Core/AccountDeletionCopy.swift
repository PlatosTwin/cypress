import Foundation

/// What a person is told before their account is deleted (RULINGS **R3**, extended by the project
/// owner's two-door ruling — see `AccountDeletionChoice`).
///
/// **Why this is a constant and not a screen.** No deletion surface was drawn: SCREENS.md draws none,
/// BUILD-PLAN §9 lists none, and DECISIONS constraint 21 says that when a screen or state is not in
/// the mocks, stop and ask rather than invent it. R3 is nevertheless explicit that the copy is
/// load-bearing — "deleting more than someone expected is the failure mode this ruling creates, and
/// copy is the whole defence against it" — and copy that does not exist cannot be reviewed by the
/// person who will draw the screen. It exists here to be reviewed as prose and arranged by
/// `AccountDeletionSheet`, which adds no strings of its own.
///
/// ── R3's one sentence, and why it is now three strings ────────────────────────────────────────
/// R3 required that the two halves of a deletion — what the forest keeps, and what goes with the
/// person — be told *in the same sentence*, and `whatHappens` was that sentence, with a note saying
/// it must not be split. That rule existed because there was one behaviour: told only that their
/// observations stay, a person would reasonably expect everything else to stay too, and the reminders
/// and favourites would go without warning.
///
/// There are now two behaviours, and welding the shared half onto each of them would print the same
/// clause twice and bury the thing the reader most needs to see, which is the *difference* between
/// the doors. So the shared half is hoisted out into `personalRecords`, which opens with "Either
/// way" and sits above both doors, unconditionally, on screen before anything is chosen. R3's actual
/// defence is stronger under that arrangement than under the welded sentence: the clause can no
/// longer be missed by picking the reassuring door, because it is not inside a door at all.
///
/// ── Which door the words are written to flatter ───────────────────────────────────────────────
/// Neither, and that is deliberate. `leaveRecordsBody` is written so that a person taking the default
/// is reading a description of something good — their work stays useful, and nothing on it says it
/// was theirs — rather than a description of the app declining to do what they asked. Most people
/// should take it and feel fine about it. `eraseEverythingBody` is written flat: it states what goes,
/// including the one consequence a person would not think of (a tree's best photo changing), and it
/// does not scold. A warning that sounds like a scolding is a warning people stop reading.
///
/// House style, per ARCHITECTURE §5.7: prose is sentence case, and there are no spaces around em
/// dashes. The app's own control is labelled `Favorite` (C8, screen 03), so the copy says favorites
/// rather than the British spelling this project's prose uses elsewhere — a person should read back
/// the word they tapped.
///
/// Nothing here counts anything. "Your visits" names a kind of record, not a number, because D1
/// forbids public counts of user actions and a farewell screen is the last place to start one.
public enum AccountDeletionCopy {

    /// The screen or sheet's title.
    public static let title = "Delete your account"

    /// The question the two doors answer, said before they are drawn so that the cards below read as
    /// answers rather than as two competing warnings.
    public static let choiceQuestion = "What should happen to what you have added?"

    // MARK: - The two doors

    /// The default door's label. A sentence about the trees rather than about the app, because that
    /// is what the person is actually deciding.
    public static let leaveRecordsTitle = "Leave my records on the trees"

    /// The default door, whole.
    ///
    /// The last clause is the one that makes this a real privacy answer rather than a soft refusal:
    /// the rows are not merely unsigned, they are unlinkable to each other. See
    /// `AccountDeletionChoice` for why that is true — the owner column is nulled and no stand-in id
    /// is written in its place.
    public static let leaveRecordsBody = """
        Your visits, check-ins, measurements, care notes, photographs and photo votes stay on the \
        trees they were made about, with nothing left on them saying they were yours. Nobody can \
        tell afterwards that they were all one person's.
        """

    /// The destructive door's label. First person, and a verb, because this is the sentence a person
    /// is choosing to say about their own work.
    public static let eraseEverythingTitle = "Erase everything I have added"

    /// The destructive door, whole.
    ///
    /// The photo-vote clause is the one that would otherwise be a surprise, and it is R3's rule
    /// applied to a consequence rather than to a record kind: a vote decides which photograph of a
    /// tree everybody sees, so withdrawing yours can change what a stranger looks at tomorrow. A
    /// person is entitled to make that trade and is not entitled to be told about it afterwards.
    public static let eraseEverythingBody = """
        Every visit, check-in, measurement, care note, photo vote and tree name you added is \
        deleted, and your photographs are removed from this phone. A tree whose best photograph was \
        one of yours will start showing a different one.
        """

    // MARK: - True under both doors

    /// R3's other half, hoisted out of the sentence it used to live in. Above both doors, always.
    ///
    /// "Either way" is doing the work the grammar used to do: it marks the clause as unconditional,
    /// so a reader who has already picked a door cannot read it as belonging to the other one.
    public static let personalRecords = """
        Either way, your private reminders and your favorites are deleted with the account, because \
        nobody but you could ever read them.
        """

    /// The queue, which is a real state and not a technicality: field work sits in the outbox for as
    /// long as the phone is offline, and a person deleting an account on a bus should know that what
    /// is still waiting is covered by whichever door they chose rather than exempt from it.
    public static let queuedWork = """
        Anything still waiting to sync is included, so nothing arrives later under your name.
        """

    /// Said plainly, and separately, because it is the one fact that cannot be undone by signing in
    /// again.
    public static let irreversible = "This cannot be undone."

    // MARK: - Actions

    /// The destructive action, labelled with **the door it will take** (R2: a verb naming what the
    /// next tap does).
    ///
    /// This is the whole of the defence against reaching the destructive door by momentum. The two
    /// labels differ in their last three words, so the final tap cannot be made without the word
    /// "erase" being on the button under the thumb. A single "Delete account" label on both would
    /// have made the two doors a setting somebody could forget they had changed.
    public static func confirmAction(for choice: AccountDeletionChoice) -> String {
        switch choice {
        case .leaveRecords: return "Delete account, leave my records"
        case .eraseEverything: return "Delete account and erase everything"
        }
    }

    /// The way out. First, and the default, on any surface that draws these two.
    public static let cancelAction = "Keep my account"

    // MARK: - The destructive door's second gate

    /// `eraseEverything` is confirmed twice and `leaveRecords` once, which is the asymmetry the whole
    /// design turns on: the safe door stays two taps and does not feel like a penance, and the door
    /// that destroys work asks once more, in words that name the work.
    ///
    /// It repeats rather than adding: everything below is a restatement of `eraseEverythingBody` in
    /// shorter form. A second gate that introduces a *new* fact is a first gate that lied.
    public static let eraseConfirmTitle = "Erase everything you have added?"

    public static let eraseConfirmMessage = """
        Your photographs will be deleted from this phone, and the check-ins, measurements and care \
        notes you made will be taken off the trees.
        """

    public static let eraseConfirmAction = "Erase everything"

    /// The way out of the second gate. Not `cancelAction`: backing out here returns to the choice,
    /// where the account still exists and the other door is still on screen, so "Keep my account"
    /// would promise the wrong thing.
    public static let eraseConfirmCancel = "Go back"
}
