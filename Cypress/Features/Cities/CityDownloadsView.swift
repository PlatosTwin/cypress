import SwiftUI

/// The Cities screen — the app side of R36's base layer, drawn exactly as RULINGS R43
/// specifies (§§2–3): one card for the built-in inventory, one per published city, and
/// nothing that would make it a store.
///
/// Card chrome is the You tab's setting-card idiom (screen 17's row metrics, `surfaceCard` on
/// `borderCool`), because the You tab is where this screen's door lives and the two should read
/// as one place. Not a raw hex or font size in the file (ARCHITECTURE §6).
struct CityDownloadsView: View {

    @State private var model: CityDownloadsModel
    let onBack: () -> Void

    init(model: CityDownloadsModel, onBack: @escaping () -> Void) {
        _model = State(wrappedValue: model)
        self.onBack = onBack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: CityDownloadsCopy.screenTitle, onBack: onBack)

                if let note = model.catalogNote {
                    Text(note)
                        .font(CypressFont.body115)
                        .foregroundStyle(CypressColor.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, CypressSpacing.gutter)
                        .padding(.bottom, CypressSpacing.gapVitality)
                }

                VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                    ForEach(model.sections) { section in
                        // The You tab's micro-label, the same idiom `City data` and the disclaimer
                        // heading already use — a heading, not a new component.
                        //
                        // **A section may have no title, and then it draws none** rather than an
                        // empty line. The downloaded packs continue the run `On this phone` already
                        // opened, so their section carries no heading of its own
                        // (`CityDownloadSection.sections`).
                        if !section.title.isEmpty {
                            Text(section.title)
                                .cypressMicroLabel()
                                .padding(
                                    .top,
                                    section.isCityGroup ? 0 : CityDownloadsMetrics.sectionTop
                                )
                        }

                        // **`cards`, not `rows`** — the arrangement is decided in
                        // `CityDownloadSection` as a value, and this is the only place cards come
                        // from, so a row that is contained there is contained here.
                        ForEach(section.cards) { card in
                            self.card(card)
                        }
                    }

                    nycDisclaimer
                }
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.bottom, CypressSpacing.bottomFootnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(CypressColor.surfaceScreen)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Re-fetched on every appearance and never persisted (ruling §3).
        .task { await model.load() }
    }

    // MARK: - The NYC Data Mine disclaimer (RULINGS R78 ruling 2)

    /// **Unconditional, and that is the decision worth reading.**
    ///
    /// R78 ruling 2 puts the verbatim block on "the actual surface offering an NYC pack,
    /// whole-city or per-borough, trial packs included per D12". The narrower reading — render it
    /// only when the catalog currently lists an NYC pack — was rejected, for three reasons:
    ///
    /// 1. **It would make a legal obligation depend on a network fetch.** `model.rows` is empty
    ///    while the catalog is loading and holds only installed cities when it fails
    ///    (`CityDownloadsCopy.offline`). A reader with an NYC pack already installed and no
    ///    connection is exactly the reader the disclaimer is for.
    /// 2. **D12 binds trial and beta packs**, which are the packs least likely to arrive through a
    ///    manifest entry this screen filtered correctly.
    /// 3. A conditional render fails *silently* — nothing goes red, the screen just stops carrying
    ///    it. Unconditional has one failure mode and a test can see it.
    ///
    /// The cost is that a reader who never downloads New York still reads a sentence about it. That
    /// is a paragraph of true text in a place it is not needed, against a compliance failure that
    /// leaves no trace — and R36 makes the source's obligations ride with the data, not with
    /// whether it happens to be on screen.
    ///
    /// Drawn as quiet footer copy in the You tab's idiom, not as a card: it is not a thing to act
    /// on, and giving it card chrome would read as a fourth city.
    private var nycDisclaimer: some View {
        VStack(alignment: .leading, spacing: CityDownloadsMetrics.rowTextGap) {
            // The You tab's own section-label idiom — the same one `citiesSection` uses for
            // `City data`, because this block sits under that tab's door and is furniture of the
            // same kind. It uppercases; the heading is ours, so that is style, not the quoted text.
            Text(CityDownloadsCopy.nycDisclaimerHeading)
                .cypressMicroLabel()

            Text(CityDownloadsCopy.nycDisclaimerRequired)
                .font(CypressFont.body115)
                .foregroundStyle(CypressColor.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            Text(CityDownloadsCopy.nycDisclaimerAttribution)
                .font(CypressFont.body115)
                .foregroundStyle(CypressColor.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, CypressSpacing.gapVitality)
        .accessibilityIdentifier(CityDownloadsView.nycDisclaimerIdentifier)
    }

    /// A stable name for the block above, for a reader inspecting the tree.
    ///
    /// **`CityDisclaimerUITests` deliberately does NOT assert on it.** An identifier survives the
    /// text being replaced by anything at all, so a test that looked for it would go green on a
    /// screen carrying the wrong words — and the words are the whole obligation. That test matches
    /// the City's sentence itself.
    static let nycDisclaimerIdentifier = "cities.nycDisclaimer"

    // MARK: - One card

    /// One card, and anything drawn **inside its boundary**.
    ///
    /// **The containment is one rounded rectangle around all of it**, which is the owner's ruling of
    /// 2026-08-25: the cities the app ships with belong inside the built-in inventory's card, under
    /// its `Includes …` line, not beside it as peer cards. The arrangement arrives already decided
    /// (`CityDownloadSection.cards`); what this adds is the chrome, and it adds none that is new —
    /// the entries share the card the header opened, and a hairline in `borderCool`, the same token
    /// the card's own border draws in, separates each from what is above it.
    ///
    /// It replaces a version where containment was a `Bool` on the section and a top padding on a
    /// heading that was never drawn, so the screen drew three identical peer cards while a green
    /// test asserted the flag.
    ///
    /// The card is one accessibility container so a UI test can ask for its **frame** and check that
    /// the entries are inside it. That is the only form of this assertion that is about pixels
    /// rather than about a value — see `CityCardContainmentUITests`.
    private func card(_ card: CityDownloadSection.Card) -> some View {
        VStack(alignment: .leading, spacing: CityDownloadsMetrics.rowTextGap) {
            entry(card.row)

            ForEach(card.contained) { contained in
                Rectangle()
                    .fill(CypressColor.borderCool)
                    .frame(height: CypressSpacing.Component.hairline)
                    .padding(.vertical, CityDownloadsMetrics.containedRuleGap)
                entry(contained)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CityDownloadsMetrics.cardPaddingV)
        .padding(.horizontal, CityDownloadsMetrics.cardPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CityDownloadsView.cardIdentifier(card.row.id))
    }

    /// A stable name per card, so a test can read the card's own frame rather than guess at it from
    /// the text inside it.
    static func cardIdentifier(_ rowID: String) -> String { "cities.card.\(rowID)" }

    /// One entry's text and controls, with no chrome of its own — a card's header when it is the
    /// card's own row, and a contained city when it is inside one.
    private func entry(_ row: CityDownloadRow) -> some View {
        VStack(alignment: .leading, spacing: CityDownloadsMetrics.rowTextGap) {
            Text(row.title)
                .font(CypressFont.body135Bold)
                .foregroundStyle(CypressColor.textInk)

            if let coverage = row.coverageNote {
                Text(coverage)
                    .font(CypressFont.body115)
                    .foregroundStyle(CypressColor.textFaint)
            }

            HStack(spacing: CityDownloadsMetrics.rowSpacing) {
                Text(row.stateLine)
                    .font(CypressFont.body115)
                    .foregroundStyle(row.isFailure ? CypressColor.signalAmber : CypressColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = row.progress {
                    Spacer(minLength: 0)
                    // Screen 08's ring is the app's one drawn progress vocabulary; a new bar
                    // would be an invention.
                    ProgressRing(
                        fraction: progress,
                        label: "\(Int(progress * 100))%",
                        spokenLabel: CityDownloadsCopy.downloading
                    )
                }
            }

            if let detail = row.detailLine {
                Text(detail)
                    .font(CypressFont.body115)
                    .foregroundStyle(CypressColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !row.affordances.isEmpty {
                HStack(spacing: CityDownloadsMetrics.rowSpacing) {
                    ForEach(row.affordances, id: \.self) { affordance in
                        control(affordance, row: row)
                    }
                }
                .padding(.top, CityDownloadsMetrics.buttonsTop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func control(_ affordance: CityDownloadRow.Affordance, row: CityDownloadRow) -> some View {
        switch affordance {
        case .download:
            PrimaryButton(CityDownloadsCopy.download, style: .compact) {
                if let city = publishedCity(for: row.id) { model.download(city) }
            }
        case .update:
            PrimaryButton(CityDownloadsCopy.update, style: .compact) {
                if let city = publishedCity(for: row.id) { model.download(city) }
            }
        case .remove:
            SecondaryOutlineButton(CityDownloadsCopy.remove, style: .compact) {
                model.remove(row.id)
            }
        case .revert:
            // The same operation as `.remove` under the name that is true for a bundled city: what
            // goes is the downloaded copy, and the city returns to the record inside the app.
            SecondaryOutlineButton(CityDownloadsCopy.revert, style: .compact) {
                model.remove(row.id)
            }
        case .cancel:
            SecondaryOutlineButton(CityDownloadsCopy.cancel, style: .compact) {
                model.cancelDownload()
            }
        }
    }

    private func publishedCity(for id: String) -> CityManifest.City? {
        guard case .loaded(let manifest) = model.catalog else { return nil }
        return manifest.cities.first { $0.id == id }
    }
}

/// **Not spec values** — the screen has no drawn geometry (its ruling is the mock), so these
/// follow the You tab's setting card, which follows screen 17's wi-fi row.
enum CityDownloadsMetrics {
    static let rowSpacing: CGFloat = 12
    static let rowTextGap: CGFloat = 4
    static let cardPaddingV: CGFloat = 12
    static let cardPaddingH: CGFloat = 14
    static let buttonsTop: CGFloat = 6
    /// Extra air above a top-level heading, so `Available to download` reads as a break rather than
    /// as a caption on the card beneath it. A city group inside that section takes none — it is
    /// already inside a break.
    static let sectionTop: CGFloat = 8
    /// Air on each side of the hairline that separates a contained city from what is above it
    /// inside the built-in card. The same 8pt the section heading takes, for the same reason: it is
    /// the smallest gap that reads as a break rather than as a line through a paragraph.
    static let containedRuleGap: CGFloat = 8
}
