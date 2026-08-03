//
//  AccountAskView.swift
//  Cypress — Features/AccountAsk
//
//  Screen 15 · The account ask (on the third save). SCREENS.md lines 1181–1208.
//
//  Composed from C17 (`BottomSheet`, `.account` style: `padding:22px 20px 44px`, no grabber, scrim
//  `.3`), C18's reduced canvas and C19 pins for the backdrop, and C21's leaf mark. The three
//  provider buttons are not C6/C7 — 15 gives them their own fill, radius and padding — so they are
//  drawn here from tokens, the way screen 12's composition card was.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6). The numbers that remain are
//  SCREENS.md 15's own margins, named in `AccountAskMetrics`.
//
//  Everything about *what the screen says* is decided in `AccountAskPresentation`. This file draws
//  what it is given, which is what makes the "no password field, no birthdate field" assertion
//  testable without a renderer.
//

import SwiftUI

struct AccountAskView: View {

    @State private var model: AccountAskModel

    /// Closes the sheet. Every path reaches it — a successful link, `Not now`, and the scrim — and
    /// the presenting binding turns it into `VisitSaveLedger.resolveAccountAsk()` so that no way of
    /// leaving the sheet can leave the ask owed (ERRATA E34).
    private let onFinish: () -> Void

    /// §6's `Read the short version`. Nil today: the license text has no screen in SCREENS.md and
    /// no entry in BUILD-PLAN §9, and inventing one is what DECISIONS constraint 21 forbids. The run
    /// still draws bold exactly as the mock draws it; it is simply not a button until somebody has
    /// somewhere for it to go.
    private let onReadLicense: (() -> Void)?

    init(
        api: any CypressAPI,
        onLink: AccountAskLink? = nil,
        onReadLicense: (() -> Void)? = nil,
        onFinish: @escaping () -> Void
    ) {
        _model = State(wrappedValue: AccountAskModel(api: api, onLink: onLink))
        self.onReadLicense = onReadLicense
        self.onFinish = onFinish
    }

    var body: some View {
        AccountAskScreen(
            presentation: model.presentation,
            onToggleConsent: { model.toggleConsent() },
            onTapProvider: { provider in
                Task {
                    if await model.link(provider) { onFinish() }
                }
            },
            onReadLicense: onReadLicense,
            onDecline: onFinish
        )
        .task { await model.load() }
    }
}

// MARK: - The screen itself

/// Screen 15's layout, given a finished derivation.
///
/// Split from `AccountAskView` for the reason `AlmanacScreen` is: a layout whose content only
/// arrives after an `async` read cannot be photographed offscreen, because `.task` never runs in a
/// detached window — every state would preview as the loading one. With the split, the numberless
/// headline, the two notices and the unchecked consent box can each be handed straight in.
struct AccountAskScreen: View {

    let presentation: AccountAskPresentation
    var onToggleConsent: () -> Void = {}
    var onTapProvider: (AccountAskProvider) -> Void = { _ in }
    var onReadLicense: (() -> Void)?
    var onDecline: () -> Void = {}

    var body: some View {
        ZStack {
            backdrop
            BottomSheet(style: .account, onScrimTap: onDecline) {
                sheet
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceMapPaper)
    }

    // MARK: - The map behind the scrim

    /// The frame: `#E9E5D4` ground, the grid at 70 % with no ocean, park or street bands, and three
    /// pins. C18 already names this state — "the reduced version on 15/18".
    ///
    /// It is a backdrop, not a map: nothing here is a real coordinate, and the pins say only "this
    /// is the map you came from". The mock draws them 16pt in New Growth; `MapPin.cityTree` is the
    /// component that means "a tree on the map" and is 18pt in Canopy, and the two-point difference
    /// is not worth a fourth pin kind on a decorative layer. Recorded in ERRATA.
    private var backdrop: some View {
        GeometryReader { proxy in
            MapCanvas.reduced {
                ForEach(Array(AccountAskMetrics.pinPositions.enumerated()), id: \.offset) { _, position in
                    MapPin(.cityTree)
                        .position(
                            x: proxy.size.width * position.x,
                            y: proxy.size.height * position.y
                        )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - The sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            bodyCopy
            providers
            notice
            consentRow
            decline
        }
    }

    // MARK: §1 · Header row

    /// `HStack(spacing:12)` — a 40×40 mark and the serif headline.
    ///
    /// SCREENS.md 15 §1 says "40×40 Cypress logo PNG". There is no logo in the app bundle and adding
    /// one is a resource change, so the mark here is C21 — "the app's only bespoke mark" — at the
    /// same size. Recorded in ERRATA; swapping in the artwork is one line at this call site.
    private var header: some View {
        HStack(spacing: AccountAskMetrics.headerSpacing) {
            LeafGlyph(size: AccountAskMetrics.markSide, tint: CypressColor.selectionFill)
                .frame(width: AccountAskMetrics.markSide, height: AccountAskMetrics.markSide)

            Text(presentation.headline)
                .font(CypressFont.accountTitle)
                .foregroundStyle(CypressColor.textInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.bottom, AccountAskMetrics.headerBottom)
    }

    // MARK: §2 · Body

    private var bodyCopy: some View {
        Text(presentation.body)
            .cypressBody135(color: CypressColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, AccountAskMetrics.bodyBottom)
    }

    // MARK: §3–5 · The three routes

    private var providers: some View {
        VStack(spacing: AccountAskMetrics.providerGap) {
            ForEach(presentation.providers) { button in
                AccountProviderButton(
                    title: button.title,
                    isPrimary: button.isPrimary,
                    isEnabled: !presentation.isLinking,
                    action: { onTapProvider(button.provider) }
                )
            }
        }
        .padding(.bottom, presentation.notice == nil ? AccountAskMetrics.providersBottom : 0)
    }

    // MARK: The unspecified line

    @ViewBuilder
    private var notice: some View {
        if let notice = presentation.notice {
            Text(notice.text)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .lineSpacing(CypressFont.LineSpacing.body125)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AccountAskMetrics.noticeTop)
                .padding(.bottom, AccountAskMetrics.providersBottom)
        }
    }

    // MARK: §6 · Consent

    /// The checkbox and the sentence. The box is 20pt as drawn and carries a 44pt target
    /// (ARCHITECTURE §6: the target grows, the visual stays put).
    private var consentRow: some View {
        HStack(alignment: .top, spacing: AccountAskMetrics.consentSpacing) {
            Button(action: onToggleConsent) {
                consentBox
            }
            .buttonStyle(.plain)
            .cypressHitArea()
            .accessibilityLabel(AccountAskCopy.consentText)
            .accessibilityAddTraits(presentation.isConsentAccepted ? [.isSelected] : [])

            consentSentence
        }
    }

    /// **NOT SPECIFIED:** the unchecked styling. 15 draws the box checked and says nothing about the
    /// other state, so this is the smallest possible answer — the same box, without the glyph.
    /// Recorded in ERRATA.
    private var consentBox: some View {
        RoundedRectangle(cornerRadius: CypressRadius.badge, style: .continuous)
            .strokeBorder(CypressColor.selectionFill, lineWidth: AccountAskMetrics.checkboxBorder)
            .frame(width: AccountAskMetrics.checkboxSide, height: AccountAskMetrics.checkboxSide)
            .overlay {
                if presentation.isConsentAccepted {
                    Text(verbatim: "✓")
                        .font(CypressFont.body12Bold)
                        .foregroundStyle(CypressColor.selectionFill)
                }
            }
            .padding(.top, AccountAskMetrics.checkboxTop)
            .contentShape(Rectangle())
    }

    /// §6's sentence with its bold run, as one paragraph. `cypressLeadInText` is the same helper C9
    /// and C14 use, with the emphasis at the end rather than the front — which is why the argument
    /// order reads backwards here: the plain run is passed as the "lead-in" and the bold run as the
    /// "rest".
    private var consentText: Text {
        cypressLeadInText(
            presentation.consentText,
            presentation.consentLinkTitle,
            leadInFont: CypressFont.body12,
            restFont: CypressFont.body12Bold,
            leadInColor: CypressColor.textMuted,
            restColor: CypressColor.selectionFill
        )
    }

    @ViewBuilder
    private var consentSentence: some View {
        let paragraph = consentText
            .lineSpacing(CypressFont.LineSpacing.body125)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

        if let onReadLicense {
            // Whole-sentence tap rather than a link inside the run: SwiftUI cannot give a `Text`
            // fragment its own 44pt target, and a 12pt bold phrase is exactly the sub-target the
            // design's own critique flagged.
            paragraph
                .contentShape(Rectangle())
                .onTapGesture(perform: onReadLicense)
                .accessibilityAddTraits(.isLink)
        } else {
            paragraph
        }
    }

    // MARK: §7 · Decline

    /// "declining still works" — the caption's own promise, and the only control on this sheet that
    /// does anything on every build. Silence is not a decline, but this is one: it resolves the ask
    /// through the presenting binding, and `VisitSaveLedger.storageLine` changes accordingly.
    private var decline: some View {
        Button(action: onDecline) {
            Text(presentation.declineTitle)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.textMuted)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
        .padding(.top, AccountAskMetrics.declineTop)
    }
}

// MARK: - §3–5's button

/// One of screen 15's three routes.
///
/// Not `PrimaryButton`/`SecondaryOutlineButton`: 15 gives these their own fill (`#1C2A21` rather
/// than Cypress Deep), their own padding (14 / 13 rather than 15 / 14) and no shadow, and bending C6
/// into a fourth style for one screen would make every other CTA in the app answer for this one.
struct AccountProviderButton: View {

    let title: String
    let isPrimary: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CypressFont.body15Bold)
                .foregroundStyle(isPrimary ? CypressColor.accountPrimaryLabel : CypressColor.textInk)
                // A control label never gives up its own words. The `.account` sheet is a
                // content-sized card with no scroll, so at AX5 the compressed column squeezed
                // this `Text` to one line and it read `Continue with Goo…` — an ellipsis inside
                // a control (ERRATA E196 §6). Every paragraph on this sheet already carries the
                // same modifier; the button labels were the only text that could still be folded.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(
                    .vertical,
                    isPrimary ? AccountAskMetrics.primaryPadding : AccountAskMetrics.secondaryPadding
                )
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(isPrimary ? CypressColor.accountPrimaryFill : CypressColor.surfaceCard)
                }
                .overlay {
                    if !isPrimary {
                        RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                            .strokeBorder(
                                CypressColor.borderAccount,
                                lineWidth: CypressSpacing.Component.outlineWidth
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
