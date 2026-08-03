import Foundation
import Testing
@testable import Cypress

/// Screen 15 · the account ask, as a screen rather than as `VisitSaveLedger`'s timing rule
/// (`AccountAskTests` owns that half).
///
/// The three things this suite exists to make un-regressable, all from DECISIONS §3:
///
/// 1. **There is no password field and no birthdate field anywhere in this screen** (§3.9). Asserted
///    structurally, by reflection over the one type the screen collects into and over the account
///    record it would create, plus a sweep of every string the screen can render. A code review
///    catches a `TextField(...)`; a test catches the property somebody added to a struct six months
///    from now.
/// 2. **The number in `Keep your three visits` is provable or absent.** Never a zero, never a page's
///    size, and never `VisitSaveLedger`'s counter.
/// 3. **A tap that cannot sign anybody in says so.** `CypressAPI` has no `/auth/*` because there is
///    no auth server; a screen that swallowed the tap would be the same dishonesty as one that
///    claimed the account (ARCHITECTURE §5.4's principle).
@MainActor
@Suite("Account ask · screen 15")
struct AccountAskSheetTests {

    // MARK: - Doubles

    /// An API that holds a fixed inventory and answers nothing else.
    private struct Holdings: CypressAPI {
        var contributions: DeviceContributions

        func deviceContributions() async throws -> DeviceContributions { contributions }

        func mapContent(in viewport: MapViewport) async throws -> MapContent { .pins([]) }
        func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { [] }
        func treeProfile(id: UUID) async throws -> TreeProfile { throw APIError.notFound }
        func addTree(_ draft: TreeDraft) async throws -> Tree { throw APIError.forbidden }
        func species(id: UUID) async throws -> Species { throw APIError.notFound }
        func searchSpecies(query: String, limit: Int) async throws -> [Species] { [] }
        func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { [] }
        func beginPhotoUpload(_ r: PhotoUploadRequest) async throws -> PhotoUploadTicket {
            throw APIError.forbidden
        }
        func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws {}
        func grove() async throws -> [GroveEntry] { [] }
        func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { Page(items: []) }
        func claimDevice(deviceUUID: UUID, userID: UUID) async throws {}
        func logHazardRedirect(_ event: HazardRedirectEvent) async throws {}
        func exportLatest(_ format: ExportFormat) async throws -> Data { Data() }
    }

    /// Every word this screen can put on a phone, in one place, so the forbidden-vocabulary sweep
    /// cannot miss a string by not knowing about it.
    private static func allCopy(locale: Locale = Locale(identifier: "en_US")) -> [String] {
        var strings = [
            AccountAskCopy.body,
            AccountAskCopy.consentText,
            AccountAskCopy.consentLink,
            AccountAskCopy.decline,
            AccountAskCopy.noticeUnavailable,
            AccountAskCopy.noticeFailed,
        ]
        strings += AccountAskProvider.allCases.map(\.title)
        strings += (0...5).map { AccountAskCopy.headline(visits: $0, locale: locale) }
        return strings
    }

    // MARK: - 1. No password, no birthdate

    /// DECISIONS §3.9: "Never collect birthdates, passwords, or exact photo GPS. Email auth is
    /// magic link only."
    ///
    /// `AccountLinkRequest` is everything the screen hands onward, so its field list is the whole of
    /// what screen 15 can collect. Two fields, both named, and the test fails on a third rather than
    /// merely on a forbidden one — a field nobody thought about is the way this rule gets broken.
    @Test("the account ask collects exactly a provider and a consent answer")
    func linkRequestCollectsNothingElse() {
        let request = AccountLinkRequest(provider: .email, acceptsLicense: true)
        let fields = Mirror(reflecting: request).children.compactMap(\.label).sorted()
        #expect(fields == ["acceptsLicense", "provider"])
    }

    /// The same assertion made negatively, over both the request and the account record it would
    /// create, because `User` is where a password would land if one were ever collected.
    @Test("no type on the sign-in path carries a password or a birthdate")
    func noPasswordOrBirthdateFields() {
        let forbidden = ["password", "passcode", "secret", "birthdate", "birthday", "dateofbirth", "dob"]

        let request = AccountLinkRequest(provider: .apple, acceptsLicense: false)
        let user = User(email: "someone@example.com", displayName: "Someone")

        for subject in [Mirror(reflecting: request), Mirror(reflecting: user)] {
            for label in subject.children.compactMap(\.label) {
                let normalized = label.lowercased()
                for word in forbidden {
                    #expect(
                        !normalized.contains(word),
                        "\(label) looks like a \(word) field, which DECISIONS §3.9 forbids"
                    )
                }
            }
        }
    }

    /// And the copy: a screen with no password field that talks about passwords would still be
    /// promising the wrong mechanism. `Use email` is magic link only (A10).
    @Test("nothing screen 15 can say mentions a password, an age or a birthday")
    func copyNeverMentionsForbiddenThings() {
        let forbidden = ["password", "birthday", "birthdate", "date of birth", "how old", "your age"]
        for line in Self.allCopy() {
            let normalized = line.lowercased()
            for word in forbidden {
                #expect(!normalized.contains(word), "screen 15 says “\(word)”: \(line)")
            }
        }
    }

    /// How age can matter without a birthdate ever being stored, pinned as behavior rather than as
    /// a comment.
    ///
    /// The bucket is a one-bit answer to a single over-or-under-18 question (DECISIONS §3.9, D11),
    /// asked in onboarding and not on this screen. It is three strings, it is never differenced
    /// against a clock, and the rule that reads it only ever *removes* attribution — so an account
    /// created by screen 15, which asks nothing, is safe by default rather than by luck.
    @Test("age is a bucket, and an unknown bucket cannot make attribution public")
    func ageWithoutABirthdate() {
        // Three values and no date anywhere in the type.
        #expect(BirthYearBucket.allCases.count == 3)
        #expect(Set(BirthYearBucket.allCases.map(\.rawValue)) == ["over_18", "under_18", "unknown"])

        // The account screen 15 would create: no age answer, and attribution off.
        let fresh = User(email: "someone@example.com", displayName: "Someone")
        #expect(fresh.birthYearBucket == .unknown)
        #expect(fresh.publicAttribution == false)
        #expect(fresh.isPublicAttributionEffective == false)

        // D11's rule runs one way: it can only take attribution away.
        var optedIn = fresh
        optedIn.publicAttribution = true
        #expect(optedIn.isPublicAttributionEffective == true)

        var minor = optedIn
        minor.birthYearBucket = .under18
        #expect(minor.isPublicAttributionEffective == false)

        var unknown = optedIn
        unknown.birthYearBucket = .unknown
        #expect(unknown.isPublicAttributionEffective == true, "unknown is not under-18; the gate is onboarding's")
    }

    // MARK: - 2. The headline's number

    @Test("the headline states the count it can prove, and drops it when it cannot")
    func headlineIsHonest() {
        let en = Locale(identifier: "en_US")
        #expect(AccountAskCopy.headline(visits: 3, locale: en) == "Keep your three visits")
        #expect(AccountAskCopy.headline(visits: 4, locale: en) == "Keep your four visits")
        #expect(AccountAskCopy.headline(visits: 1, locale: en) == "Keep your visit")
        // Never `Keep your 0 visits`: a surface with nothing to count says the numberless sentence
        // (ARCHITECTURE §5.6).
        #expect(AccountAskCopy.headline(visits: 0, locale: en) == "Keep your visits")
        for line in (0...5).map({ AccountAskCopy.headline(visits: $0, locale: en) }) {
            #expect(!line.contains("0"), "a digit reached the headline: \(line)")
        }
    }

    @Test("the sheet reads its number from the store, not from the save counter")
    func headlineComesFromTheRead() async {
        let model = AccountAskModel(api: Holdings(contributions: DeviceContributions(visits: 3)))
        #expect(model.presentation.headline == "Keep your visits", "before the read there is nothing to claim")

        await model.load()
        #expect(model.presentation.headline.contains("three"))
    }

    // MARK: - 3. A tap that cannot sign anybody in

    @Test("with no sign-in service, a tap says so and does not claim an account")
    func noServiceSaysSo() async {
        let model = AccountAskModel(api: Holdings(contributions: DeviceContributions(visits: 3)))
        let linked = await model.link(.apple)

        #expect(linked == false)
        #expect(model.presentation.notice == .unavailable)
        #expect(model.presentation.notice?.text.contains("stays on this phone") == true)
    }

    @Test("a sign-in that throws leaves a notice rather than a half-finished account")
    func failureSaysSo() async {
        let model = AccountAskModel(
            api: Holdings(contributions: DeviceContributions(visits: 3)),
            onLink: { _ in throw APIError.serverError }
        )
        let linked = await model.link(.google)

        #expect(linked == false)
        #expect(model.presentation.notice == .failed)
    }

    @Test("a sign-in that succeeds reports it once, and carries the consent answer")
    func successCarriesConsent() async {
        let recorded = RecordedRequests()
        let model = AccountAskModel(
            api: Holdings(contributions: DeviceContributions(visits: 3)),
            onLink: { request in await recorded.append(request) }
        )

        #expect(model.isConsentAccepted, "SCREENS.md 15 draws the box checked")
        model.toggleConsent()
        let linked = await model.link(.email)

        #expect(linked)
        #expect(model.presentation.notice == nil)
        let requests = await recorded.all
        #expect(requests.count == 1)
        #expect(requests.first?.provider == .email)
        // Unchecking does not block the sign-in — 15 states no such rule — but it does travel, so
        // the account can record honestly that nothing was agreed to.
        #expect(requests.first?.acceptsLicense == false)
    }

    /// The three drawn routes and no fourth. A "create a password" step would show up here first.
    @Test("there are exactly three routes, and email is one of them")
    func threeRoutes() {
        #expect(AccountAskProvider.allCases.map(\.title) == [
            "Continue with Apple", "Continue with Google", "Use email",
        ])
        #expect(AccountAskProvider.allCases.filter(\.isPrimary) == [.apple])
    }

    /// Screen 15's copy, against SCREENS.md 15 §2, §6 and §7 character for character. These are the
    /// sentences the caption calls "a single plain sentence with the long version a tap away", and
    /// paraphrasing any of them is how consent copy quietly changes meaning.
    @Test("the drawn copy is verbatim")
    func copyIsVerbatim() {
        #expect(AccountAskCopy.body == "They live on this phone right now. An account backs them up and lets them join each tree’s public timeline.")
        #expect(AccountAskCopy.consentText == "Share my tree records under the open database license. In plain words: anyone may use the data, and your name rides along only if you opt in. ")
        #expect(AccountAskCopy.consentLink == "Read the short version")
        #expect(AccountAskCopy.decline == "Not now · keep saving to this phone only")
    }

    /// ARCHITECTURE §5.7: no spaces around em dashes. Nothing on 15 carries one, and this is the
    /// assertion that it stays that way if the copy is ever revised.
    @Test("no copy on 15 puts spaces around an em dash")
    func emDashRule() {
        for line in Self.allCopy() {
            #expect(!line.contains(" — "), "spaced em dash in: \(line)")
        }
    }
}

/// A recorder for the injected sign-in action, which is `@Sendable` and therefore cannot close over
/// a mutable local.
private actor RecordedRequests {
    private(set) var all: [AccountLinkRequest] = []
    func append(_ request: AccountLinkRequest) { all.append(request) }
}
