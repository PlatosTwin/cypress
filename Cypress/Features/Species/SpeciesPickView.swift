//
//  SpeciesPickView.swift
//  Cypress — Features/Species
//
//  The list you pick a species out of. `SpeciesPickModel` is where the design is argued; this file
//  only draws it, and every string it draws is `SpeciesPickCopy`'s.
//
//  ── Why a full screen rather than a sheet ────────────────────────────────────────────────────────
//  The one caller that exists today reaches this from `VisitAddTreeView`, which is already presented
//  in the `fullScreenCover` `RootView` puts the visit flow in, and which already learned this lesson
//  once: `VisitPinAdjustView` *replaces* the composer rather than covering it, because a second modal
//  inside the first would put the photograph behind two layers of chrome. A picker with a keyboard up
//  and a scrolling list needs the whole screen anyway, so it takes it the same way the map does —
//  as a phase of the screen that owns the draft, not as a thing on top of it.
//
//  ── The row is the whole tap target, and it commits ─────────────────────────────────────────────
//  There is no separate confirm. A picker whose rows only *highlight* needs a second control and a
//  selected state to draw, and both exist to protect against a mistake this screen cannot make: the
//  choice is reversible from the screen the reader lands back on, which still shows what they picked
//  and still offers to change it.
//

import SwiftUI

struct SpeciesPickView: View {

    @State private var model: SpeciesPickModel
    @FocusState private var fieldFocused: Bool

    /// A species was chosen.
    let onPick: (Species) -> Void
    /// The reader left without naming one. Deliberately distinct from `onPick` — see
    /// `SpeciesPickCopy.skip`: declining to name a species is an answer, not a cancelled action.
    let onSkip: () -> Void
    let onBack: () -> Void

    init(
        api: any CypressAPI,
        onPick: @escaping (Species) -> Void,
        onSkip: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        _model = State(wrappedValue: SpeciesPickModel(api: api))
        self.onPick = onPick
        self.onSkip = onSkip
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: SpeciesPickCopy.title, bottomInset: .wide, onBack: onBack)

            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                SearchBar(text: $model.query, placeholder: SpeciesPickCopy.placeholder)
                    .focused($fieldFocused)

                Text(SpeciesPickCopy.prompt)
                    .cypressBody135(color: CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, CypressSpacing.gutter)

            ScrollView {
                VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                    results
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.top, CypressSpacing.gapCandidates)
                .padding(.bottom, CypressSpacing.gapCandidates)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
        // The reader arrived here to type. Anything else is a tap they should not have to make.
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .idle:
            // Nothing. The prompt above the list already says what this screen is for, and a second
            // sentence in the empty space would be the app talking to itself.
            EmptyView()

        case .searching:
            Text(SpeciesPickCopy.searching)
                .cypressBody135(color: CypressColor.textFaint)

        case let .noMatch(query):
            Text(SpeciesPickCopy.noMatch(query: query))
                .cypressBody135(color: CypressColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

        case let .matched(species):
            ForEach(species) { row($0) }
        }
    }

    /// One species. Common name in the serif list face, scientific name in the italic serif beneath —
    /// the same pairing screen 03's subtitle and `SpeciesTile` both use, so a species looks like a
    /// species everywhere in this app.
    private func row(_ species: Species) -> some View {
        Button {
            onPick(species)
        } label: {
            VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                if !species.commonName.isEmpty {
                    Text(species.commonName)
                        .font(CypressFont.listNameSerif)
                        .foregroundStyle(CypressColor.textInk)
                        .multilineTextAlignment(.leading)
                }
                Text(species.scientificName)
                    .font(species.commonName.isEmpty ? CypressFont.listNameSerif : CypressFont.latinName135)
                    .foregroundStyle(
                        species.commonName.isEmpty ? CypressColor.textInk : CypressColor.textMuted
                    )
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CypressSpacing.gutterBottomCard)
            .padding(.vertical, CypressSpacing.gutterBottomCard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var footer: some View {
        SecondaryOutlineButton(SpeciesPickCopy.skip) { onSkip() }
            .padding(.horizontal, CypressSpacing.gutter)
            .padding(.bottom, CypressSpacing.bottomCTA)
    }
}
