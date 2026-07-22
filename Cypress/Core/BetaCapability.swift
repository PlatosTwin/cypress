import Foundation

/// What this build can actually do, as opposed to what it has code for.
///
/// **Why a flag and not a deleted route (RULINGS R4).** Screen 15 is built, tested, and cannot sign
/// anyone in: authentication is magic-link only (DECISIONS §3, no passwords ever), a magic link needs
/// a server to send it, and the local beta has no backend. A screen that asks for an email address
/// and then does nothing with it is worse than no screen — it takes something from a person and gives
/// nothing back, which is the one thing the privacy posture in §3 exists to prevent.
///
/// A route commented out is indistinguishable from a route somebody forgot to write. This says, in
/// one place, that 15 exists, works, and is waiting on a server rather than on an engineer.
///
/// **Not a feature-flag system.** There is no remote config, no per-user rollout and no store: these
/// are compile-time facts about a build with no backend behind it, and they become true by deleting
/// the constant when the thing they gate exists. Anything that needs to vary at runtime belongs in
/// `app_state`, not here.
public enum BetaCapability {

    /// Whether an account can be created or signed into.
    ///
    /// `false` until magic-link auth has a server to run against. Everything that would have waited
    /// on an account stays device-scoped in the meantime, which is already how favourites (ERRATA
    /// E89) and private reminders (E23) work — so nothing is lost by not asking, and the app's own
    /// copy already promises that an account can be added later.
    public static let accountsAvailable = false
}
