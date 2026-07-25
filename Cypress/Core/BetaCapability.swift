import Foundation

/// What this build can actually do, as opposed to what it has code for.
///
/// **Why a flag and not a deleted route (RULINGS R4).** Screen 15 is built and tested. What it could
/// not do, before, was *complete*: authentication is magic-link only (DECISIONS §3, no passwords
/// ever), a magic link needs a server to send it, and the local beta has no backend — so the flag
/// held the ask back rather than dead-end a person on second 8 of a street-corner visit.
///
/// **What changed (ERRATA E124).** The dead-end was never the *account* — it was the *round trip*.
/// A local account needs no server: signing in mints a `userID` and calls the `claimDevice` seam
/// that already exists (`CypressAPI.claimDevice(deviceUUID:userID:)`), which moves this device's
/// anonymous contributions onto that id and persists it in `app_state`. No email is sent and none is
/// stored — the composition root's `onLink` ignores the address and claims the device — so §3.9's
/// "no passwords, ever" and §3.11's "private by default" are kept by construction, not by a promise.
/// The one thing this build still cannot do is *back up* to a cloud, which is why screen 18's storage
/// line stays true when signed in ("saving to this phone only"): a local account is an identity, not
/// a backup. When the magic-link service lands, `onLink` swaps its body for the real exchange and
/// nothing else on the path changes.
///
/// **Not a feature-flag system.** There is no remote config, no per-user rollout and no store: these
/// are compile-time facts about a build, and they become true by deleting the constant when the thing
/// they gate exists. Anything that needs to vary at runtime belongs in `app_state`, not here.
public enum BetaCapability {

    /// Whether an account can be created or signed into.
    ///
    /// `true`: sign-in completes locally through `claimDevice` (ERRATA E124). It was `false` while
    /// the only path to an account ran through a magic-link server this build does not have.
    /// Everything device-scoped — favourites (ERRATA E89), private reminders (E23) — keeps working
    /// exactly as before; a local account simply gives those contributions a `userID` to hang from
    /// instead of the device id, which is the move `claimDevice` was written for.
    public static let accountsAvailable = true
}
