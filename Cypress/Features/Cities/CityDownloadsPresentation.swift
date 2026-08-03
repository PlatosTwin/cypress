import Foundation

/// The Cities screen's copy and row states, computed as pure values so every branch
/// RULINGS R43 names is unit-testable without a network, a disk, or a view.
///
/// **Every string here is written by this feature's ruling** (RULINGS R43 §3 — the surface has
/// no mock, and the ruling is the mock, per the delegated authority it records). Civic strings — display names, coverage words — are never written here
/// at all: they arrive from the manifest, which got them from `publish_cities.py`'s hand-entered
/// table (DECISIONS constraint 15).
enum CityDownloadsCopy {

    static let screenTitle = "Cities"

    // You tab section (ruling §2).
    static let youSectionLabel = "City data"
    static let youRowTitle = "Cities"
    static let youRowSubtitle = "Download city inventories and choose the one the map draws"

    // The built-in inventory card (ruling §3).
    static let builtInTitle = "Built-in inventory"
    static let builtInSubtitle = "Ships with the app and cannot be removed"

    // Affordances.
    static let download = "Download"
    static let update = "Update"
    static let remove = "Remove"
    static let use = "Use"
    static let cancel = "Cancel"
    static let inUse = "In use"

    // Catalog-level lines.
    static let checking = "Checking what's available…"
    static let offline = "Couldn't check what's available. Downloaded cities still work."

    // Row state lines.
    static let downloading = "Downloading…"
    static let downloadFailed = "Download failed. Nothing was changed."
    static let needsNewerApp = "Needs a newer app"
    static let needsNewerAppDetail = "This city's data is a newer format than this app can read."

    static func coverageNote(_ coverage: String) -> String {
        "Covers \(coverage) only"
    }

    /// `81 MB` — megabytes, rounded, deterministic. Not `ByteCountFormatter`, whose significant-
    /// digit rounding ("80.6 MB") says more than a download decision needs.
    static func size(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
    }

    static func installedLine(version: String) -> String {
        "Installed · \(version)"
    }

    static func updateLine(installedVersion: String) -> String {
        "Update available · \(installedVersion) installed"
    }
}

/// One card on the Cities screen, fully decided — the view draws rows, it does not reason.
struct CityDownloadRow: Equatable, Identifiable {
    /// Manifest id, or `CityDownloadRow.builtInID` for the bundle's card.
    let id: String
    let title: String
    /// `Covers downtown only`, when coverage is partial (nil otherwise).
    let coverageNote: String?
    /// The state line (`81 MB`, `Installed · s14-r…`, `Downloading…`, …).
    let stateLine: String
    /// A second, quieter line (`This city's data is a newer format…`).
    let detailLine: String?
    /// Whether the state line is a failure and draws in the attention color.
    let isFailure: Bool
    /// Download progress, only while downloading.
    let progress: Double?

    enum Affordance: Equatable {
        case download
        case update
        case use
        case remove
        case cancel
        /// Not a button — the state label on the card whose inventory is attached.
        case inUseLabel
    }
    let affordances: [Affordance]

    static let builtInID = "built-in"

    // MARK: - Deciding a row

    /// The built-in bundle's card: `Use` when a city is active, the `In use` label otherwise.
    static func builtIn(isActive: Bool) -> CityDownloadRow {
        CityDownloadRow(
            id: builtInID,
            title: CityDownloadsCopy.builtInTitle,
            coverageNote: nil,
            stateLine: CityDownloadsCopy.builtInSubtitle,
            detailLine: nil,
            isFailure: false,
            progress: nil,
            affordances: isActive ? [.inUseLabel] : [.use]
        )
    }

    /// A published city's card, from the facts the model holds. Every branch is ruling §3's list.
    static func published(
        city: CityManifest.City,
        state: CityInstallState,
        isActive: Bool,
        downloadingFraction: Double?,
        lastAttemptFailed: Bool
    ) -> CityDownloadRow {
        let coverage = city.coverage == "full" ? nil : CityDownloadsCopy.coverageNote(city.coverage)

        if let downloadingFraction {
            return CityDownloadRow(
                id: city.id, title: city.displayName, coverageNote: coverage,
                stateLine: CityDownloadsCopy.downloading, detailLine: nil,
                isFailure: false, progress: downloadingFraction, affordances: [.cancel]
            )
        }
        if lastAttemptFailed {
            // The state reverts to whatever was true before the attempt; only the line differs.
            let base = decide(city: city, state: state, isActive: isActive)
            return CityDownloadRow(
                id: base.id, title: base.title, coverageNote: base.coverageNote,
                stateLine: CityDownloadsCopy.downloadFailed, detailLine: nil,
                isFailure: true, progress: nil, affordances: base.affordances
            )
        }
        return decide(city: city, state: state, isActive: isActive)
    }

    /// An installed city the manifest could not vouch for (offline): disk facts alone, and every
    /// affordance that needs no network.
    static func installedOffline(
        _ installed: CityLibrary.InstalledCity,
        isActive: Bool
    ) -> CityDownloadRow {
        CityDownloadRow(
            id: installed.id,
            // The manifest carries the display name and it is unreachable; the id is the one
            // name the disk actually knows, and inventing a prettier one is constraint 15's line.
            title: installed.id,
            coverageNote: nil,
            stateLine: CityDownloadsCopy.installedLine(version: installed.version),
            detailLine: nil,
            isFailure: false,
            progress: nil,
            affordances: isActive ? [.inUseLabel, .remove] : [.use, .remove]
        )
    }

    private static func decide(
        city: CityManifest.City,
        state: CityInstallState,
        isActive: Bool
    ) -> CityDownloadRow {
        let row: (stateLine: String, detail: String?, affordances: [Affordance])
        switch state {
        case .notInstalled:
            row = (CityDownloadsCopy.size(city.bytes), nil, [.download])
        case let .installedCurrent(version):
            row = (
                CityDownloadsCopy.installedLine(version: version), nil,
                isActive ? [.inUseLabel, .remove] : [.use, .remove]
            )
        case let .updateAvailable(version):
            row = (CityDownloadsCopy.updateLine(installedVersion: version), nil, [.update, .remove])
        case let .needsNewerApp(installed):
            if let installed {
                // The older compatible copy keeps its affordances; only the update is refused.
                row = (
                    CityDownloadsCopy.installedLine(version: installed),
                    CityDownloadsCopy.needsNewerAppDetail,
                    isActive ? [.inUseLabel, .remove] : [.use, .remove]
                )
            } else {
                // No affordance at all: a button that cannot keep its promise is not drawn.
                row = (CityDownloadsCopy.needsNewerApp, CityDownloadsCopy.needsNewerAppDetail, [])
            }
        }
        return CityDownloadRow(
            id: city.id, title: city.displayName, coverageNote: coverageIfPartial(city),
            stateLine: row.stateLine, detailLine: row.detail,
            isFailure: false, progress: nil, affordances: row.affordances
        )
    }

    private static func coverageIfPartial(_ city: CityManifest.City) -> String? {
        city.coverage == "full" ? nil : CityDownloadsCopy.coverageNote(city.coverage)
    }
}
