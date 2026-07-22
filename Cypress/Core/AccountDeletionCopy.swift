import Foundation

/// What a person is told before their account is deleted (RULINGS **R3**).
///
/// **Why this is a constant and not a screen.** No deletion surface exists: SCREENS.md draws none,
/// BUILD-PLAN §9 lists none, and DECISIONS constraint 21 says that when a screen or state is not in
/// the mocks, stop and ask rather than invent it. So nothing here is presented anywhere yet. R3 is
/// nevertheless explicit that the copy is load-bearing — "deleting more than someone expected is the
/// failure mode this ruling creates, and copy is the whole defence against it" — and copy that does
/// not exist cannot be reviewed by the person who will draw the screen. It exists here to be wired.
///
/// **The sentence R3 requires.** Deletion keeps contributions and deletes the two record kinds only
/// their owner could ever read (`AccountDeletion`). A person must be told about the second thing
/// *in the same sentence* as the first, before it happens: told only that their observations stay,
/// they would reasonably expect everything else to stay too, and the reminders and favourites would
/// go without warning. `whatHappens` is that sentence and must not be split into two.
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

    /// **The sentence R3 requires, whole.** Both halves in one breath: what the forest keeps, and
    /// what goes with the person.
    public static let whatHappens = """
        Your visits, check-ins, measurements and care notes stay on the trees they were made \
        about, with nothing left on them saying they were yours—your private reminders and your \
        favorites are deleted with the account, because nobody but you could ever read them.
        """

    /// The queue, which is a real state and not a technicality: field work sits in the outbox for as
    /// long as the phone is offline, and a person deleting an account on a bus should know that what
    /// is still waiting is covered by the sentence above rather than exempt from it.
    public static let queuedWork = """
        Anything still waiting to sync is included, so nothing arrives later under your name.
        """

    /// Said plainly, and separately, because it is the one fact that cannot be undone by signing in
    /// again.
    public static let irreversible = "This cannot be undone."

    /// The destructive action. A verb naming what the next tap does, unlike C8's `Favorite`, which
    /// names a thing (R2).
    public static let confirmAction = "Delete account"

    /// The way out. First, and the default, on any surface that draws these two.
    public static let cancelAction = "Keep my account"
}
