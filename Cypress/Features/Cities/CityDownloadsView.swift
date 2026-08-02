import SwiftUI

/// The Cities screen — the app side of R36's base layer, drawn exactly as the pending
/// city-downloads ruling specifies (§§2–3): one card for the built-in inventory, one per
/// published city, and nothing that would make it a store.
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
                    ForEach(model.rows) { row in
                        card(row)
                    }
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

    // MARK: - One card

    private func card(_ row: CityDownloadRow) -> some View {
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
        .padding(.vertical, CityDownloadsMetrics.cardPaddingV)
        .padding(.horizontal, CityDownloadsMetrics.cardPaddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.cardSm)
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
        case .use:
            PrimaryButton(CityDownloadsCopy.use, style: .compact) {
                model.use(row.id == CityDownloadRow.builtInID ? nil : row.id)
            }
        case .remove:
            SecondaryOutlineButton(CityDownloadsCopy.remove, style: .compact) {
                model.remove(row.id)
            }
        case .cancel:
            SecondaryOutlineButton(CityDownloadsCopy.cancel, style: .compact) {
                model.cancelDownload()
            }
        case .inUseLabel:
            Text(CityDownloadsCopy.inUse)
                .font(CypressFont.body145Bold)
                .foregroundStyle(CypressColor.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CypressSpacing.Component.buttonPaddingSmall)
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
}
