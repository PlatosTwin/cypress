//
//  YouTabView.swift
//  Cypress — Features/You
//
//  The `You` tab of C16, which until now rendered `NotBuiltYetView`.
//
//  ── This screen's contents are specified; its layout is not ───────────────────────────────
//  BUILD-PLAN §9's M2 list names it outright: "the You tab (profile, settings, **outbox entry
//  point**, privacy toggles)". That sentence is why screen 17 has an entrance at all (ERRATA E75) —
//  the outbox row here is **specified**, not invented. What has no mock is the *drawing*: no layout,
//  no copy, no row design anywhere in SCREENS.md or the prototype.
//
//  So it is built minimally, out of C-components that already exist, saying only what the app can
//  actually back up:
//
//  - **Profile** — the account block (ERRATA **E131**). This entry used to read "nothing. There is
//    no account on any device this app runs on: screen 15 cannot sign anyone in (ERRATA E86)", and
//    that stopped being true when ERRATA E124 flipped `BetaCapability.accountsAvailable`: sign-in
//    completes locally on the third visit save, through `claimDevice`. For a while afterwards the
//    app signed people in and then never mentioned it again — no signed-in state, no sign-out, and
//    `LocalAPI.deleteAccount()`, written to RULINGS R3 and complete, with its own test as its only
//    caller. A stale comment is how that survives review, so this one is corrected rather than
//    deleted. See `AccountSection`.
//  - **Your private reminders** — the other half of the same finding (ERRATA **E131**, on E23's
//    terms). Screen 06 saves them and confirmed "Saved. Your reminder stays yours alone." with
//    nowhere in the app to read one back. See `PrivateReminderList`.
//  - **Outbox entry point** — one C10 row, pushing `Route.outbox`. Specified.
//  - **Settings** — the wi-fi preference, which is the only persisted setting the data layer has
//    (`AppStateKey`). It is shared with screen 17 rather than copied; see `RootView`.
//  - **Privacy** — stated, not switched. See `YouCopy.privacyBody`.
//
//  ── The one rule this screen is most likely to break ──────────────────────────────────────
//  ARCHITECTURE §5.1: no streaks, points, ranks, badges, or **public counts of user actions**. A
//  "You" tab is the natural home for exactly those, and it carries none — no visit count, no species
//  tally, no dates, no ring. Everything here is either a door or a preference.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6).
//

import SwiftUI

struct YouTabView: View {

    /// Screen 17's model, shared with screen 17 itself rather than rebuilt here.
    ///
    /// Two instances would mean two copies of one preference, each reading the store when its own
    /// screen appeared and neither hearing the other change it — a toggle that disagrees with itself
    /// between two surfaces. The composition root owns the single instance (ARCHITECTURE §3).
    @Bindable var outbox: OutboxViewState

    /// The local moderation queue (ERRATA E124-B). Present on every build; it draws nothing unless the
    /// signed-in account is a lead, so a non-lead sees exactly the You tab it saw before. Owned by the
    /// composition root, like `outbox`.
    let moderation: ModerationModel

    /// The account and this contributor's own reminders (ERRATA E131). Owned by the composition
    /// root like the two above, for the reason it owns them: one instance of a signed-in state,
    /// rather than a second quiet copy that disagrees with the store after a sign-out.
    let account: AccountModel

    /// The journal export's bytes, per format — `CypressAPI.exportLatest`, resolved by the
    /// composition root.
    ///
    /// A closure rather than the API itself, for the reason `OutboxViewState` takes a
    /// `treeNameResolver`: this screen needs one operation, not a whole boundary, and handing it one
    /// keeps every state of the tab drawable in a preview without a database. Nil draws no export
    /// block at all, which is what a surface with nothing behind it should do.
    var export: (@Sendable (ExportFormat) async throws -> Data)?

    @Environment(AppRouter.self) private var router: AppRouter?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // C1 with no back circle: a tab root has nothing to go back to.
                        ScreenHeader(title: YouCopy.screenTitle)

                        moderationSection
                        accountSection
                        remindersSection
                        contributionsSection
                        exportSection
                        settingsSection
                        privacySection
                        #if DEBUG
                        developerSection
                        #endif

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            BottomTabBar(selection: router?.bottomTabSelection ?? .constant(.you))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // C16 absorbs the home indicator with its own 30pt bottom padding (SCREENS.md §1.6).
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // The outbox row shows no count, so nothing here needs the queue to have been read — but
        // the toggle below does, and `start()` is what reads the stored preference. It guards its
        // own observer, so screen 17 calling it too costs nothing.
        .task { await outbox.start() }
        // Reads the role and, if it is a lead's, the open reviews. Runs on every appearance of the
        // tab, so a removal reported elsewhere shows up the next time a lead looks here.
        .task { await moderation.load() }
        // The account and the reminders (ERRATA E131).
        .task { await account.load() }
        // And again when a sheet closes over this tab, which `.task` does not cover: a
        // `fullScreenCover` leaves the view underneath in place, so dismissing screen 15 fires no
        // appearance at all and the block that opened the ask would go on saying `Sign in` about a
        // device that had just signed in. This is the same defect the tree profile carried until
        // ERRATA E127, and it is fixed here the same way before it can be reported.
        .onChange(of: router?.sheet == nil) { _, nothingPresented in
            guard nothingPresented, account.hasLoaded else { return }
            Task { await account.load() }
        }
    }

    // MARK: - Account (ERRATA E131)

    /// Draws nothing until the first read lands, so the tab never says `Sign in` for one frame to
    /// somebody who is signed in (ARCHITECTURE §5.6: no state is claimed before it is known).
    @ViewBuilder
    private var accountSection: some View {
        if account.hasLoaded {
            AccountSection(
                isSignedIn: account.isSignedIn,
                link: account.link,
                isBusy: account.isBusy,
                onSignIn: { router?.present(.accountAsk) },
                onSignOut: { Task { await account.signOut() } },
                onDelete: { choice in Task { await account.deleteAccount(choice) } }
            )
        }
    }

    // MARK: - Private reminders (ERRATA E131, on E23's terms)

    @ViewBuilder
    private var remindersSection: some View {
        if account.hasLoaded {
            PrivateReminderList(
                items: account.reminders,
                hasFailed: account.remindersFailed,
                onOpen: { router?.push(.treeProfile($0.treeID)) }
            )
        }
    }

    // MARK: - Reviews (leads only, ERRATA E124-B)

    /// The removal-review queue. Draws nothing at all unless `moderation.canModerate` — a non-lead
    /// never sees the section, and the authority that actually protects a tree is on the confirm write
    /// (`LocalAPI.confirmRemoval`), not on whether this view drew.
    @ViewBuilder
    private var moderationSection: some View {
        if moderation.canModerate {
            ModerationReviewList(
                items: moderation.items,
                onOpen: { router?.push(.treeProfile($0.treeID)) },
                onConfirm: { item in Task { await moderation.confirm(item) } }
            )
            .padding(.top, CypressSpacing.labelSectionTop)
            .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    // MARK: - The outbox entry point (BUILD-PLAN §9)

    /// One C10 row. C10 is the app's existing tappable row (screen 12's season rows), which is what
    /// this is: a label, a line saying what is behind it, and a destination.
    ///
    /// **It carries no count.** "3 waiting" would be true and useful, and it is also the first step
    /// onto a tab of numbers about the person using it; screen 17's own header pill says it where it
    /// belongs, on the screen that can also say what each item is and why it is stuck.
    private var contributionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(YouCopy.contributionsLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            IconTextRow(
                accent: .water,
                title: YouCopy.outboxRowTitle,
                subtitle: YouCopy.outboxRowSubtitle,
                action: { router?.push(.outbox) }
            )
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - Getting your record out

    /// The export, which had no button anywhere in the app until now.
    ///
    /// Beside the outbox row because the two are doors out of the same body of work — one is what
    /// has not left this phone yet, the other is a copy of everything that is on it. See
    /// `JournalExportRow` for why an implemented-but-unreachable `exportLatest` was a privacy
    /// commitment the app was not keeping, rather than merely a missing feature.
    ///
    @ViewBuilder
    private var exportSection: some View {
        if let export {
            JournalExportRows(export: export)
        }
    }

    // MARK: - Settings

    /// The wi-fi preference (C25), the one setting `AppStateKey` persists.
    ///
    /// It is a *sync* setting and not a privacy one — it decides when photo binaries leave the
    /// phone, not who may see them — and it is labelled as what it is. Screen 17 §3 draws the same
    /// control; both read and write the one `OutboxViewState`, so they cannot disagree.
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(YouCopy.settingsLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            HStack(spacing: YouMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: YouMetrics.rowTextGap) {
                    Text(OutboxCopy.wifiTitle)
                        .font(CypressFont.body135Bold)
                        .foregroundStyle(CypressColor.textInk)
                    Text(OutboxCopy.wifiSubtitle)
                        .font(CypressFont.body115)
                        .foregroundStyle(CypressColor.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                CypressToggle(
                    isOn: $outbox.syncPhotosOnWifiOnly,
                    accessibilityLabel: OutboxCopy.wifiTitle
                )
            }
            .padding(.vertical, YouMetrics.settingPaddingV)
            .padding(.horizontal, YouMetrics.settingPaddingH)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - Privacy

    /// C14's dashed disclosure — the style screen 06 uses to state a fact about what the app does
    /// and does not do with what you give it. See `YouCopy.privacyBody` for why this is a sentence
    /// and not a switch.
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(YouCopy.privacyLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            Callout(YouCopy.privacyBody, style: .dashed, leadIn: YouCopy.privacyLeadIn)
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.bottom, CypressSpacing.bottomFootnote)
    }

    // MARK: - Developer (DEBUG only, ERRATA E124-B)

    #if DEBUG
    /// The one way to become a lead on a device with no server to grant a role: the project owner
    /// stepping into the mocked city-personnel role to verify removals. `#if DEBUG`, so the Release
    /// build has no self-promote path — a real moderation grant is never the account's own to make.
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(YouCopy.developerLabel)
                .cypressMicroLabel()
                .padding(.bottom, CypressSpacing.gapVitality)

            IconTextRow(
                accent: .water,
                title: moderation.canModerate ? YouCopy.stepDownTitle : YouCopy.becomeLeadTitle,
                subtitle: moderation.canModerate ? YouCopy.stepDownSubtitle : YouCopy.becomeLeadSubtitle,
                action: {
                    Task {
                        if moderation.canModerate {
                            await moderation.stepDownForDebug()
                        } else {
                            await moderation.promoteToLeadForDebug()
                        }
                    }
                }
            )
        }
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }
    #endif
}

// MARK: - Copy

/// **Every string here is NOT SPECIFIED.** The You tab has no mock and no copy anywhere in the
/// source documents; only its *contents* are named, by BUILD-PLAN §9. Each is written to state a
/// fact and stop, which is the shape every other unspecified string in this app uses
/// (`OutboxCopy.emptyState`, `GrowthHistoryCopy.emptyState`, `TreeProfilePresentation
/// .coldStartFootnote`). Sentence case, no spaces around em dashes (ARCHITECTURE §5.7).
enum YouCopy {

    static let screenTitle = "You"

    static let contributionsLabel = "Your contributions"
    static let outboxRowTitle = "Outbox"
    /// Screen 17's footnote is the promise this row is a door to; this is that promise in one line.
    static let outboxRowSubtitle = "What is waiting to send, and what has gone"

    static let settingsLabel = "Settings"

    static let privacyLabel = "Privacy"
    static let privacyLeadIn = "Private by default:"

    // Developer (DEBUG only, ERRATA E124-B). Not shipped; see `YouTabView.developerSection`.
    static let developerLabel = "Developer"
    static let becomeLeadTitle = "Become a community lead"
    static let becomeLeadSubtitle = "Debug: act as mocked city personnel and review removals"
    static let stepDownTitle = "Step down from lead"
    static let stepDownSubtitle = "Debug: return to an ordinary member account"

    /// **Stated rather than switched, and that is the finding this screen exists to surface.**
    ///
    /// D11's privacy toggle is `User.publicAttribution` — "contribution feeds private by default
    /// with opt-in public attribution". It is modelled in `Core` and it is not settable anywhere:
    /// there is no `users` table in `AppSchema`, no `CypressAPI` method that reads or writes it, and
    /// no account on any device the app currently runs on (ERRATA E86). A switch here would be a
    /// control that forgets what it was told, which is worse than no control at all.
    ///
    /// So the screen says what is true today. Every clause is checkable: `publicAttribution`
    /// defaults to `false`, `LocalAPI` writes only to this device, and nothing in the app can flip
    /// it. See ERRATA (E100).
    static let privacyBody =
        " everything you save stays on this phone. Public attribution is opt-in, it is off, and "
        + "there is nothing in the app yet that can turn it on."
}

// MARK: - Screen metrics

/// **Not spec values.** The You tab has no drawn geometry, so these follow screen 17's wi-fi row,
/// which is the nearest thing in the app to the control they size.
enum YouMetrics {
    static let rowSpacing: CGFloat = 12
    static let rowTextGap: CGFloat = 2
    static let settingPaddingV: CGFloat = 12
    static let settingPaddingH: CGFloat = 14
}
