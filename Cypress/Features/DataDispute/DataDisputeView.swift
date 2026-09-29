//
//  DataDisputeView.swift
//  Cypress — Features/DataDispute
//
//  Reporting a mistake in a city record (RULINGS R79, part 2). **No mocked screen.** The owner
//  ruled its shape on 2026-09-28: a pushed screen modeled on screen 06 (SCREENS.md §06) — C1's
//  header, micro-labelled sections, screen 06's multi-select chips, a C14 dashed disclosure, and a
//  C6 primary button pinned under the scrolling form the way screen 05 pins its own.
//
//  Composed from existing components only: `ScreenHeader`, `Chip` (06's neighborly pair, which is
//  the selected appearance ERRATA E22 chose for those chips), `SecondaryOutlineButton`, `Callout`,
//  `PrimaryButton`, and `SpeciesPickView` for the species — the app's one picker, not a second.
//  Every string is `DataDisputeCopy`'s.
//

import SwiftUI

struct DataDisputeView: View {

    @State private var model: DataDisputeModel
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.openURL) private var openURL
    /// Whether one of the two text fields has the keyboard. The year field's number pad has no
    /// return key, so without the keyboard toolbar's `Done` below the pad would cover the notes,
    /// the disclosure and — on a small phone — the button, with no way to put it away but a drag.
    @FocusState private var editing: Bool

    private let api: any CypressAPI
    /// The app's one location provider, from the composition root. `nil` in previews, where the
    /// location control answers from nothing and stays on its hint.
    private let location: MapLocationProvider?
    /// Called once the dispute is written. The composition root pops back to the profile.
    private let onRaised: () -> Void

    init(
        treeID: UUID,
        api: any CypressAPI,
        location: MapLocationProvider?,
        onRaised: @escaping () -> Void = {}
    ) {
        _model = State(wrappedValue: DataDisputeModel(treeID: treeID, api: api))
        self.api = api
        self.location = location
        self.onRaised = onRaised
    }

    var body: some View {
        @Bindable var model = model

        // The form scrolls; the button does not — screen 05's arrangement (`CheckInView.ctaBlock`).
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: DataDisputeCopy.screenTitle, onBack: { router?.pop() })

                    choices
                    if model.draft.choices.contains(.wrongPlace) { locationSection }
                    if model.draft.choices.contains(.wrongSpecies) { speciesSection }
                    if model.draft.choices.contains(.wrongPlantedYear) { plantedYearSection }
                    notesSection
                    disclosure
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, CypressSpacing.labelSectionTop)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            ctaBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Every change to the fix **or** to Precise Location, while the screen is open. A refused
        // fix is replaced by a later, better one (ruling 7), and a reader who turns Precise Location
        // on in Settings and comes back is read again rather than left looking at the old sentence.
        .onChange(of: fixReading) { _, reading in
            guard let reading else { return }
            model.locationChanged(reading)
        }
        .task { await model.loadOnFile() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(DataDisputeCopy.keyboardDone) { editing = false }
                    .font(CypressFont.body145Bold)
                    .foregroundStyle(CypressColor.ctaFill)
            }
        }
        .onChange(of: model.didRaise) { _, raised in
            if raised { onRaised() }
        }
        // A cover for `TreeProfileView.speciesClaim`'s reason: the picker puts a keyboard and a
        // scrolling list up, and it is the same control in the same shape everywhere it appears.
        .fullScreenCover(isPresented: $model.isChoosingSpecies) {
            SpeciesPickView(
                api: api,
                onPick: { species in model.chooseSpecies(species) },
                // "I'm not sure" is an answer here too: the species is wrong and the reporter does
                // not know the right one. Whatever was picked before stands until they pick again.
                onSkip: { model.cancelChoosingSpecies() },
                onBack: { model.cancelChoosingSpecies() }
            )
        }
    }

    /// The provider's state as the location block reads it, or `nil` in previews.
    private var fixReading: DataDisputeFixReading? {
        guard let location else { return nil }
        return DataDisputeFixReading(
            availability: location.availability,
            precision: location.precision,
            failureCount: location.failureCount
        )
    }

    // MARK: - The choices

    private var choices: some View {
        section(label: DataDisputeCopy.choicesLabel) {
            CypressChipFlow(spacing: CypressSpacing.gapDense) {
                ForEach(DataDisputeChoice.allCases, id: \.self) { choice in
                    Chip(
                        DataDisputeCopy.choice(choice),
                        style: model.draft.choices.contains(choice) ? .structureFlagOn : .structureFlagIdle
                    ) {
                        model.toggle(choice)
                    }
                    // "There's no tree here" stands alone (owner, 2026-09-28): while it is on, the
                    // other three are cleared and cannot be chosen. `.disabled` rather than a new
                    // chip style — SCREENS.md §5 gap 2 leaves disabled styling unspecified, and the
                    // platform's own dimming plus VoiceOver's "dimmed" is the least invented answer.
                    .disabled(model.draft.isDisabled(choice))
                }
            }
        }
    }

    // MARK: - Pin is in the wrong place

    private var locationSection: some View {
        section(label: DataDisputeCopy.locationLabel) {
            VStack(alignment: .leading, spacing: DataDisputeMetrics.insideSection) {
                cityHas(.wrongPlace)
                Text(DataDisputeCopy.location(model.draft.location))
                    .cypressBody135(color: CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dataDispute.locationLine")

                SecondaryOutlineButton(DataDisputeCopy.useLocation, style: .compact) {
                    location?.start()
                    if let fixReading {
                        model.useLocation(fixReading)
                    }
                }

                if model.draft.location.offersSettings, let url = location?.settingsURL {
                    linkAction(DataDisputeCopy.openSettings) { openURL(url) }
                }
            }
        }
    }

    // MARK: - Wrong species

    private var speciesSection: some View {
        section(label: DataDisputeCopy.speciesLabel) {
            VStack(alignment: .leading, spacing: DataDisputeMetrics.insideSection) {
                cityHas(.wrongSpecies)
                if let species = model.draft.species {
                    Text(SpeciesPickCopy.chosen(species))
                        .font(CypressFont.body145)
                        .foregroundStyle(CypressColor.textInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                linkAction(
                    model.draft.species == nil
                        ? DataDisputeCopy.chooseSpecies
                        : DataDisputeCopy.changeSpecies
                ) {
                    model.isChoosingSpecies = true
                }
            }
        }
    }

    // MARK: - Wrong planted year

    private var plantedYearSection: some View {
        @Bindable var model = model
        return section(label: DataDisputeCopy.plantedYearLabel) {
            VStack(alignment: .leading, spacing: DataDisputeMetrics.insideSection) {
                cityHas(.wrongPlantedYear)
                field(
                    text: $model.draft.plantedYearText,
                    prompt: DataDisputeCopy.plantedYearPrompt,
                    accessibilityLabel: DataDisputeCopy.plantedYearAccessibilityLabel,
                    multiline: false
                )
                .keyboardType(.numberPad)

                if model.plantedYearIsInvalid {
                    Text(DataDisputeCopy.plantedYearInvalid)
                        .cypressBody135(color: CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        @Bindable var model = model
        return section(label: DataDisputeCopy.notesLabel) {
            field(
                text: $model.draft.notes,
                prompt: DataDisputeCopy.notesPrompt,
                accessibilityLabel: DataDisputeCopy.notesAccessibilityLabel,
                multiline: true
            )
        }
    }

    // MARK: - The disclosure

    private var disclosure: some View {
        Callout(
            DataDisputeCopy.disclosureOpening,
            style: .dashed,
            emphasis: " " + DataDisputeCopy.disclosureEmphasis,
            continuation: DataDisputeCopy.disclosureContinuation
        )
        .padding(.top, DataDisputeMetrics.disclosureTop)
        .padding(.horizontal, CypressSpacing.gutter)
    }

    // MARK: - Sticky CTA

    private var ctaBlock: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            if let problem = model.problem {
                Text(problem)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Disabled while the position the reporter asked for is still arriving (ruling 8); the
            // location block says "Finding your location…" above it for as long as that lasts.
            PrimaryButton(DataDisputeCopy.sendCTA, isEnabled: !model.draft.isAwaitingFix) {
                Task { await model.raise() }
            }
        }
        .padding(.top, DataDisputeMetrics.ctaTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
        .padding(.bottom, CypressSpacing.bottomFootnote)
    }

    // MARK: - Pieces

    /// "The city has: …", the record's own value, under the section that corrects it (owner,
    /// 2026-09-28). In the quiet register screen 03's *What the city has on file* uses for its
    /// notes — `body135` in `textMuted` — and drawn only when the record holds a value
    /// (`DataDisputeOnFile`).
    @ViewBuilder
    private func cityHas(_ choice: DataDisputeChoice) -> some View {
        if let value = model.onFile?.value(for: choice) {
            Text(DataDisputeCopy.cityHas(value))
                .cypressBody135(color: CypressColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dataDispute.cityHas")
        }
    }

    /// `padding:14px 18px 0` — §1.6's rhythm for a block headed by an uppercase micro-label, which is
    /// `ReportView.section`'s exactly.
    private func section<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DataDisputeMetrics.labelToContent) {
            Text(label).cypressMicroLabel()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.labelSectionTop)
        .padding(.horizontal, CypressSpacing.gutterLabel)
    }

    /// The profile's quiet action — `body13Bold` in `ctaFill` with a 44 pt hit area, the shape
    /// `TreeProfileView.recordLinkAction` draws.
    private func linkAction(_ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(label)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.ctaFill)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cypressHitArea()
    }

    /// `ContributionExtras.noteField`'s field — the app's one vocabulary for text a reader may leave.
    private func field(
        text: Binding<String>,
        prompt: String,
        accessibilityLabel: String,
        multiline: Bool
    ) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(prompt).foregroundColor(CypressColor.textFaint),
            axis: multiline ? .vertical : .horizontal
        )
        .font(CypressFont.body145)
        .foregroundStyle(CypressColor.textInk)
        // An empty-titled field has no label of its own; the prompt is not one (DeepLinkVoiceOverTests).
        .accessibilityLabel(accessibilityLabel)
        .lineLimit(multiline ? 1...3 : 1...1)
        .focused($editing)
        .onChange(of: text.wrappedValue) { _, _ in model.editedText() }
        .padding(.vertical, VisitMetrics.Camera.notePaddingV)
        .padding(.horizontal, VisitMetrics.Camera.notePaddingH)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(
            CypressColor.borderCool,
            radius: CypressRadius.control,
            width: CypressSpacing.Component.hairline
        )
    }
}
