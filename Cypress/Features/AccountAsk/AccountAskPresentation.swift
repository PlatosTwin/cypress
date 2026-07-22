//
//  AccountAskPresentation.swift
//  Cypress — Features/AccountAsk
//
//  Screen 15 · The account ask (on the third save). SCREENS.md lines 1181–1208.
//
//  This is the one moment the app asks for anything, and DECISIONS §3 bites harder here than
//  anywhere else in the product. The rules this file exists to keep, each with the line that would
//  break it:
//
//  - **§3.9 — no passwords, ever.** Email auth is magic link only (A10). There is no password field
//    in this feature, no "create a password" step, and no property on any type here that could hold
//    one. `AccountLinkRequest` is the whole of what this screen collects and it has two fields.
//  - **§3.9 — never collect birthdates.** There is no date input here either, and no age question:
//    D11 puts the age gate in *onboarding*, SCREENS.md 15 draws none, and inventing one on this
//    screen is what DECISIONS constraint 21 forbids. Age still matters to the app — D11 forces
//    under-18 accounts to anonymous public attribution — and `User.birthYearBucket` is how, because
//    a bucket is a one-bit answer to "did you say you are over 18", not a date. See
//    `AccountAskCopy.whyThereIsNoAgeQuestion`.
//  - **§3.11 — contribution feeds are private by default.** `User.publicAttribution` defaults to
//    false and nothing on this screen turns it on. The body copy's "join each tree's public
//    timeline" is about the *tree's* timeline, where an un-opted-in contributor reads as
//    "a visitor" (BUILD-PLAN §10).
//  - **§3.12 — deletion anonymizes rather than deletes**, and this screen says nothing about
//    deletion, which is the only truthful thing it can say today: ERRATA E23 leaves an open
//    contradiction between §3.12's "null the user_id and sever the device link" and the private
//    reminder's one-owner CHECK. Copy that promised either behaviour would be promising a
//    behaviour nobody has settled.
//  - **D9 / ERRATA E34 — the ask arrives at the third save and gets exactly one second chance.**
//    That is `VisitSaveLedger`'s, not this feature's; nothing here counts anything.
//
//  No SwiftUI in this file, so all of the above is testable without a renderer
//  (`CypressTests/AccountAskTests.swift`).
//

import Foundation

// MARK: - What the screen collects

/// The three sign-in routes SCREENS.md 15 draws, and the whole vocabulary.
///
/// A fourth is not added here. §3.9 fixes the email route as magic link only, so `.email` means
/// "send me a link", never "ask me for a password" — the case is named for the button, and the
/// mechanism behind it is a decision the constraint has already taken.
enum AccountAskProvider: String, CaseIterable, Identifiable, Sendable {
    case apple
    case google
    case email

    var id: String { rawValue }

    /// SCREENS.md 15 §3–5, verbatim.
    var title: String {
        switch self {
        case .apple: return "Continue with Apple"
        case .google: return "Continue with Google"
        case .email: return "Use email"
        }
    }

    /// The filled button on 15 is Apple's; the other two are outlined.
    var isPrimary: Bool { self == .apple }
}

/// Everything screen 15 hands to whoever performs the sign-in. Two fields, and that is the point.
///
/// **This type is the password-and-birthdate assertion made structural.** A field cannot be added
/// to it without a reviewer seeing it, and `AccountAskTests` pins its shape by reflection so that
/// adding one fails a test rather than a code review. §3.9 is the reason.
struct AccountLinkRequest: Hashable, Sendable {
    /// Which button was tapped.
    let provider: AccountAskProvider
    /// Whether the open-database-licence consent row was checked when it was (§6).
    let acceptsLicense: Bool
}

// MARK: - Presentation

/// Everything screen 15 renders.
struct AccountAskPresentation: Equatable {

    /// One of the three buttons.
    struct ProviderButton: Equatable, Identifiable {
        let provider: AccountAskProvider
        var id: String { provider.id }
        var title: String { provider.title }
        var isPrimary: Bool { provider.isPrimary }
    }

    /// The one line this screen may draw that SCREENS.md does not: what happened after a tap.
    ///
    /// **NOT SPECIFIED.** 15 draws three buttons and nothing after them. A control that acts and
    /// says nothing is the same dishonesty as one that claims something it did not do, which is the
    /// call ERRATA E23 already made for screen 06's reminder — so this is the smallest answer that
    /// is not silence, and both sentences end on the screen's own words ("keep saving to this phone
    /// only", §7). Recorded in ERRATA.
    enum Notice: Equatable {
        /// No sign-in service is wired, which is every build today: `CypressAPI` has no `/auth/*`
        /// because there is no auth server, and adding a stub that minted a local account would
        /// claim a backup that does not exist.
        case unavailable
        /// The service was there and the attempt did not go through.
        case failed

        var text: String {
            switch self {
            case .unavailable: return AccountAskCopy.noticeUnavailable
            case .failed: return AccountAskCopy.noticeFailed
            }
        }
    }

    /// `Keep your three visits`, or the numberless form. See `AccountAskCopy.headline`.
    let headline: String
    let body: String
    let providers: [ProviderButton]
    /// §6's sentence, up to the bold run.
    let consentText: String
    /// §6's bold run. A link only when somebody can resolve it — see `AccountAskCopy.consentLink`.
    let consentLinkTitle: String
    let isConsentAccepted: Bool
    let declineTitle: String
    let notice: Notice?
    /// Whether a sign-in attempt is in flight; the buttons stop accepting taps while it is.
    let isLinking: Bool

    init(
        contributions: DeviceContributions,
        isConsentAccepted: Bool,
        notice: Notice? = nil,
        isLinking: Bool = false,
        locale: Locale = .current
    ) {
        self.headline = AccountAskCopy.headline(visits: contributions.visits, locale: locale)
        self.body = AccountAskCopy.body
        self.providers = AccountAskProvider.allCases.map(ProviderButton.init(provider:))
        self.consentText = AccountAskCopy.consentText
        self.consentLinkTitle = AccountAskCopy.consentLink
        self.isConsentAccepted = isConsentAccepted
        self.declineTitle = AccountAskCopy.decline
        self.notice = notice
        self.isLinking = isLinking
    }
}

// MARK: - Copy

/// Screen 15's strings, verbatim from SCREENS.md including its typographic characters.
enum AccountAskCopy {

    /// §2, verbatim — curly apostrophe and all.
    static let body = "They live on this phone right now. An account backs them up and lets them join each tree’s public timeline."

    /// §6, up to the bold run. The trailing space is in the source.
    static let consentText = "Share my tree records under the open database license. In plain words: anyone may use the data, and your name rides along only if you opt in. "

    /// §6's bold run.
    static let consentLink = "Read the short version"

    /// §7, verbatim. The `·` is the mock's, with no spaces around it beyond the ones drawn.
    static let decline = "Not now · keep saving to this phone only"

    // MARK: The headline

    /// `Keep your three visits`.
    ///
    /// The drawn sentence carries a number about the reader, and the number has to be true of the
    /// device it is shown on. It is **not** `VisitSaveLedger`'s counter: that is a `UserDefaults`
    /// funnel value which ARCHITECTURE §5.1 forbids rendering and which is wrong by one on the
    /// second offer anyway (ERRATA E34 lets the ask return on the fourth save). It is a `COUNT(*)`
    /// over the visits this device is holding unattributed — see `DeviceContributions` for why that
    /// count is not the thing D1 forbids.
    ///
    /// Spelled out, as the mock spells it and as SCREENS.md 12 and 13 spell theirs, through the
    /// formatter rather than a table of my own words.
    ///
    /// Two clauses can be untrue and each is simply left out, the same way `AlmanacCopy` leaves out
    /// a headcount it cannot prove:
    /// - **the number**, when the read could not produce one (a client with no store behind it, or
    ///   a device whose visits have already been claimed) — `Keep your visits`;
    /// - **the plural**, at one visit — `Keep your visit`, because "keep your one visit" is not a
    ///   sentence anybody writes.
    static func headline(visits: Int, locale: Locale = .current) -> String {
        switch visits {
        case ..<1: return "Keep your visits"
        case 1: return "Keep your visit"
        default: return "Keep your \(spelledOut(visits, locale: locale)) visits"
        }
    }

    /// `three`, `nine`. The same formatter `AlmanacCopy` uses, for the same reason: a reader in
    /// another language gets their own word, and nobody's number falls off the end of a list I
    /// stopped writing at ten.
    static func spelledOut(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: The two unspecified lines

    /// **NOT SPECIFIED** — see `AccountAskPresentation.Notice`.
    ///
    /// "Not ready yet" rather than "failed": nothing failed, the app has no auth server at all and
    /// `CypressAPI` says so in as many words. The second sentence is §7's own promise, which is the
    /// one thing about this screen that is true on every build.
    static let noticeUnavailable = "Accounts are not ready yet. Everything you have saved stays on this phone."

    /// **NOT SPECIFIED** — the other half. Deliberately does not say why: the taxonomy behind it is
    /// `APIError`, whose codes are not sentences, and guessing at a cause is how "sent to the city"
    /// happens (DECISIONS §3.3).
    static let noticeFailed = "That did not go through. Everything you have saved stays on this phone."

    /// Why this screen has no age question, kept as prose where somebody looking for one will find
    /// it rather than only in a commit message.
    ///
    /// DECISIONS §3.9 forbids birthdates and fixes the age gate as "a single over/under-18 choice";
    /// D11 places that choice in **onboarding**, not here; and SCREENS.md 15 draws no such row. So
    /// the screen collects no age, and the account it would create carries
    /// `BirthYearBucket.unknown`.
    ///
    /// That is safe rather than merely permitted, because of the direction D11's rule runs in:
    /// `User.isPublicAttributionEffective` is `publicAttribution && bucket != .under18`, and
    /// `publicAttribution` defaults to **false**. An unknown age therefore cannot leak a name — it
    /// would take a second, deliberate opt-in for the bucket to matter at all, and by then the
    /// onboarding gate has been answered. The bucket also never becomes a birthdate by accumulation:
    /// it is one of three strings, it is never differenced against a clock, and no arithmetic
    /// anywhere in the app turns it into an age.
    static let whyThereIsNoAgeQuestion = """
        The age gate is a single over-or-under-18 choice in onboarding (D11, DECISIONS §3.9). \
        Screen 15 asks nothing about age, and an account created here carries the `unknown` bucket, \
        which cannot make attribution public on its own.
        """
}

// MARK: - Screen metrics

/// The geometry SCREENS.md 15 gives this sheet that `CypressSpacing` does not already name.
///
/// Same arrangement as `AlmanacMetrics`: the numbers live here once so the view body carries no
/// loose values, while every colour, font and radius stays a `DesignSystem` token
/// (ARCHITECTURE §6).
enum AccountAskMetrics {
    /// §1: `HStack(spacing:12)`, `margin-bottom:6px`, 40×40 mark.
    static let headerSpacing: CGFloat = 12
    static let headerBottom: CGFloat = 6
    static let markSide: CGFloat = 40

    /// §2: `margin:0 0 16px`.
    static let bodyBottom: CGFloat = 16

    /// §3–5: `padding:14px` (Apple) / `13px` (outlined), `margin-bottom:8px`, and `16px` under the
    /// last one.
    static let primaryPadding: CGFloat = 14
    static let secondaryPadding: CGFloat = 13
    static let providerGap: CGFloat = 8
    static let providersBottom: CGFloat = 16

    /// §6: `HStack(spacing:10)`, checkbox 20×20 with a `margin-top:1px`, border `2px`.
    static let consentSpacing: CGFloat = 10
    static let checkboxSide: CGFloat = 20
    static let checkboxTop: CGFloat = 1
    static let checkboxBorder: CGFloat = 2

    /// §7: `margin-top:16px`.
    static let declineTop: CGFloat = 16

    /// The unspecified notice line sits where a fourth button would, in the providers' own rhythm.
    static let noticeTop: CGFloat = 8

    /// The three decorative pins on the reduced canvas behind the sheet, as fractions of it
    /// (`24%,26%`, `60%,15%`, `76%,38%`).
    static let pinPositions: [(x: Double, y: Double)] = [(0.24, 0.26), (0.60, 0.15), (0.76, 0.38)]
}
