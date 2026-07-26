//
//  ReportView.swift
//  Cypress — Features/Report
//
//  Screen 06 · Report an issue. SCREENS.md lines 843–873.
//
//  Composed from C1 (header), C4 (chips), C7 (secondary button) and C14 (dashed disclosure). The
//  311 panel is screen-06-only — SCREENS.md §2 gives it no C-number — so it is built here from
//  tokens, including the 22×22 phone glyph the spec states as an SVG path.
//
//  Not a raw hex or a raw font size in the file (ARCHITECTURE §6: "A literal in `Features/` is a
//  bug"). The numbers that remain are SCREENS.md 06's own margins, named in `ReportMetrics`.
//

import SwiftUI

struct ReportView: View {

    @State private var model: ReportModel
    @Environment(AppRouter.self) private var router: AppRouter?

    init(
        treeID: UUID,
        api: any CypressAPI,
        dialer: any TelephoneDialing = SystemTelephoneDialer(),
        initialSelection: ReportSelection = .nothing,
        onSaveReminder: ((PrivateReminderDraft) async throws -> Void)? = nil
    ) {
        _model = State(
            wrappedValue: ReportModel(
                treeID: treeID,
                api: api,
                dialer: dialer,
                initialSelection: initialSelection,
                onSaveReminder: onSaveReminder
            )
        )
    }

    var body: some View {
        @Bindable var model = model
        let presentation = model.presentation

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: ReportCopy.screenTitle, onBack: { router?.pop() })

                hazardPicker(presentation)
                notePicker(presentation)

                // One branch, not three blocks: the panel, the reminder and the disclosure all
                // depend on a hazard being selected. See `ReportPresentation.showsHazardBranch`.
                if presentation.showsHazardBranch {
                    hazardPanel(presentation)
                    reminderButton
                    disclosure
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, ReportMetrics.bottomInset)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Reads the tree, so the panel can know whether 311 is the right destination for it
        // (ERRATA E146). The screen draws first and is correct while this is in flight: an
        // unread tree is `HazardHandoff.city`, which is what 06 has always drawn.
        .task { await model.load() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        // C1 carries the back affordance and the `padding-top:62px` is the status-bar inset, so the
        // screen owns its whole chrome (SCREENS.md 06 "Frame").
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            ReportCopy.callUnavailableTitle,
            isPresented: $model.isShowingCallUnavailable
        ) {
            Button(ReportCopy.callUnavailableDismiss, role: .cancel) {}
        } message: {
            Text(ReportCopy.callUnavailableMessage)
        }
    }

    // MARK: - The two pickers

    private func hazardPicker(_ presentation: ReportPresentation) -> some View {
        section(label: ReportCopy.hazardSectionLabel, color: CypressColor.signalAmber) {
            CypressChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(presentation.hazardCategories, id: \.self) { category in
                    Chip(
                        HazardCategoryLabel.text(for: category),
                        style: presentation.selectedHazard == category ? .hazardOn : .hazardOff
                    ) {
                        Task { await model.select(hazard: category) }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════
    // §3's neighborly chips, **drawn and not tappable** (ERRATA E131).
    //
    // ── What was wrong ────────────────────────────────────────────────────────────────────────
    // Every chip was a button with a selected style, under a section label that reads `Neighborly
    // note · stays in Cypress`. Tapping one set `ReportSelection.note`, and nothing anywhere read
    // it except the chip's own fill: `OutboxPayload` has no `.communityNote` case, so a note cannot
    // enter the queue at all, and `ContributionStore.insert(_ note:)` has existed with no shipping
    // caller since M1. A control that highlights under a storage promise is a control that says
    // something was kept. Nothing was.
    //
    // ── Why the write path was not built instead ──────────────────────────────────────────────
    // `community_notes.user_id` is `NOT NULL` (`AppSchema` v1) and no migration has made it
    // nullable. RULINGS **R3** and ERRATA E109 already worked out what that costs: account deletion
    // can neither anonymize such a row nor delete it, and
    // `AccountDeletion.Outcome.communityNotesLeftAttributed` exists — in its own words — "so that
    // the day something does write one, the hole is a number somebody can see rather than a
    // silence". Writing notes is that day. It would put publicly visible rows on people's trees
    // that a deletion cannot honour, against DECISIONS §3.12, and closing that needs a schema
    // migration and a second pass over R3 — a decision-owner's call, not this errata's. The note
    // would also need a submit CTA, and ERRATA **E22** settled that there is none because none is
    // mocked.
    //
    // ── Why the chips stay drawn ──────────────────────────────────────────────────────────────
    // SCREENS.md 06 §3 draws all three, and draws all three **off**. Removing them would redraw a
    // mocked screen (DECISIONS constraint 21); leaving them exactly as the mock draws them shows
    // the vocabulary and claims nothing. E22 chose C4's "structure flag, on" as the unspecified
    // selected appearance and that choice stands unused rather than deleted — it is what this
    // section will need on the day the write path is built, and `ReportPreviews` still draws it.
    //
    // E22's own text reads as though these chips were already inert ("posting a community note has
    // no drawn affordance and none was added"). They were not: the ruling covered the missing submit
    // button and not the highlight, and this is the half it did not reach.
    // ══════════════════════════════════════════════════════════════════════════════════════════
    private func notePicker(_ presentation: ReportPresentation) -> some View {
        section(label: ReportCopy.noteSectionLabel, color: CypressColor.textFaint) {
            CypressChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(presentation.noteCategories, id: \.self) { category in
                    // No `action:`, so `Chip` renders a plain pill with no button trait and no hit
                    // area — VoiceOver reads it as the label it is, not as something to activate.
                    Chip(
                        CommunityNoteCategoryLabel.text(for: category),
                        style: presentation.selectedNote == category ? .structureFlagOn : .structureFlagIdle
                    )
                }
            }
        }
    }

    /// `padding:14px 18px 0` — §1.6's rhythm for a block headed by an uppercase micro-label.
    private func section<Content: View>(
        label: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ReportMetrics.labelToChips) {
            Text(label).cypressMicroLabel(color: color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    // MARK: - The 311 panel

    /// The panel, in whichever of its three handoffs this tree gets (`HazardHandoff`, ERRATA E146).
    ///
    /// **The geometry, the amber circle and the phone glyph are unchanged on every branch.** The
    /// amber is §1.1's "this tree needs something", which is true whoever owns the ground, and the
    /// glyph would otherwise have to be replaced with one nobody has drawn — SCREENS.md gives this
    /// panel no C-number and no second variant, so inventing a second illustration for it would be
    /// redrawing a mocked screen. What changes is the body paragraph, the CTA, and one optional line
    /// under it: the words, which are where a claim about who fixes this tree belongs.
    private func hazardPanel(_ presentation: ReportPresentation) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(CypressColor.signalAmber)
                .overlay {
                    HazardPhoneGlyph()
                        .fill(CypressColor.hazardPanelGlyph)
                        .frame(width: ReportMetrics.panelGlyph, height: ReportMetrics.panelGlyph)
                }
                .frame(width: ReportMetrics.panelCircle, height: ReportMetrics.panelCircle)
                .padding(.bottom, ReportMetrics.panelCircleBottom)
                .accessibilityHidden(true)

            Text(ReportCopy.hazardPanelTitle)
                .font(CypressFont.hazardTitle)
                .foregroundStyle(CypressColor.textInk)
                .multilineTextAlignment(.center)
                .padding(.bottom, ReportMetrics.panelTitleBottom)

            Text(presentation.hazardPanelBody)
                .font(CypressFont.body135)
                .lineSpacing(CypressFont.LineSpacing.body135)
                .foregroundStyle(CypressColor.hazardPanelText)
                .multilineTextAlignment(.center)
                .padding(.bottom, ReportMetrics.panelBodyBottom)

            if presentation.showsCallCTA {
                callButton
            }

            if presentation.showsDemotedCall {
                demotedCallButton
            }

            if let note = presentation.cityRecordPrivateNote {
                Text(note)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.hazardPanelText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ReportMetrics.panelNoteTop)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, ReportMetrics.panelPaddingV)
        .padding(.horizontal, ReportMetrics.panelPaddingH)
        .background {
            RoundedRectangle(cornerRadius: ReportMetrics.panelRadius, style: .continuous)
                .fill(CypressColor.hazardPanelFill)
        }
        .cypressBorder(
            CypressColor.hazardPanelBorder,
            radius: ReportMetrics.panelRadius,
            width: CypressSpacing.Component.hairlineStrong
        )
        .padding(.top, ReportMetrics.panelTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    /// C6's geometry with the panel's own amber fill — SCREENS.md §2 lists no hazard variant of C6,
    /// so this stays local to 06 rather than widening a shared component for one screen.
    private var callButton: some View {
        Button {
            Task { await model.callCity() }
        } label: {
            Text(ReportCopy.callCTA)
                .font(CypressFont.body16ExtraBold)
                .foregroundStyle(CypressColor.hazardCTAText)
                .frame(maxWidth: .infinity)
                .padding(CypressSpacing.Component.buttonPadding)
                .background {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(CypressColor.hazardCTAFill)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressShadow(light: CypressShadow.hazard, dark: nil)
    }

    /// The same call, demoted (ERRATA E146).
    ///
    /// **The demotion is the entire mechanism and it had to be a demotion rather than a removal.**
    /// The panel above has just said the city is not the party that fixes this tree; leaving an amber
    /// filled button under that sentence would be a screen arguing with itself, and deleting the
    /// number would be an app overruling somebody who is standing at the tree and can see the limb.
    /// So it becomes what every other quiet action in this app is — `body13Bold` in `ctaFill` with a
    /// 44 pt hit area, the shape `growthLink` and the species-claim control already use — and the
    /// word `anyway` says out loud what the change of weight means.
    ///
    /// Centred rather than leading, because it sits inside a panel whose every other element is
    /// centred; the leading alignment those other links use is a property of the column they live in.
    private var demotedCallButton: some View {
        Button {
            Task { await model.callCity() }
        } label: {
            Text(ReportCopy.callAnyway)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
    }

    // MARK: - Reminder and disclosure

    /// The button, and the one line that answers a tap on it.
    ///
    /// Once the reminder is saved the button is gone rather than disabled: the work is done, there
    /// is nothing to press, and SCREENS.md §5 gap 2 leaves disabled styling **NOT SPECIFIED**, so
    /// there is no drawn state to fall back on. A failure keeps the button — the reminder is not on
    /// disk and pressing again is the honest next move.
    @ViewBuilder
    private var reminderButton: some View {
        VStack(spacing: ReportMetrics.reminderNoteTop) {
            if model.reminderSaveState == .saved {
                reminderNote(ReportCopy.reminderSaved)
            } else {
                SecondaryOutlineButton(ReportCopy.saveReminder, style: .compact) {
                    Task { await model.saveReminder() }
                }
                if model.reminderSaveState == .failed {
                    reminderNote(ReportCopy.reminderFailed)
                }
            }
        }
        .padding(.top, ReportMetrics.secondaryTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    private func reminderNote(_ text: String) -> some View {
        Text(text)
            .font(CypressFont.body125)
            .foregroundStyle(CypressColor.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var disclosure: some View {
        Callout(
            ReportCopy.disclosureOpening,
            style: .dashed,
            emphasis: " " + ReportCopy.disclosureEmphasis,
            continuation: ReportCopy.disclosureContinuation
        )
        .padding(.top, ReportMetrics.disclosureTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }
}

// MARK: - The phone glyph

/// SCREENS.md 06 §4's 22×22 phone, transcribed from the SVG path it states verbatim:
/// `M5 2c1.5 0 3 2.5 3 4 0 1.2-1.4 1.8-1.4 2.8 0 1.6 4 6 5.6 6 1 0 1.6-1.4 2.8-1.4 1.5 0 4 1.5 4 3
/// s-1.8 3.6-4 3.6C9 20 2 13 2 6c0-2.2 1.8-4 3-4z`
///
/// Relative curves are resolved to absolute control points against the source's 22×22 viewBox and
/// then scaled, so the shape is the spec's own geometry rather than a redrawn approximation.
struct HazardPhoneGlyph: Shape {

    private static let viewBox: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.viewBox
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        path.move(to: point(5, 2))
        path.addCurve(to: point(8, 6), control1: point(6.5, 2), control2: point(8, 4.5))
        path.addCurve(to: point(6.6, 8.8), control1: point(8, 7.2), control2: point(6.6, 7.8))
        path.addCurve(to: point(12.2, 14.8), control1: point(6.6, 10.4), control2: point(10.6, 14.8))
        path.addCurve(to: point(15, 13.4), control1: point(13.2, 14.8), control2: point(13.8, 13.4))
        path.addCurve(to: point(19, 16.4), control1: point(16.5, 13.4), control2: point(19, 14.9))
        // `s` — the first control point is the reflection of the previous one about (19, 16.4).
        path.addCurve(to: point(15, 20), control1: point(19, 17.9), control2: point(17.2, 20))
        path.addCurve(to: point(2, 6), control1: point(9, 20), control2: point(2, 13))
        path.addCurve(to: point(5, 2), control1: point(2, 3.8), control2: point(3.8, 2))
        path.closeSubpath()
        return path
    }
}
