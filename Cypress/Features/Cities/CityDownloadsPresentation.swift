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

    /// The two lines R43 §3's enumeration did not have, added by the owner's ruling of 2026-08-14
    /// (`docs/design-proposals/2026-08-14-city-data-distribution.md`, decision D5 — a ruling
    /// amendment, written in the same idiom as the six states above).
    ///
    /// The claim is deliberately narrow: **record-date parity, and nothing more.** Not "identical
    /// to the published file", which would need 108 MB hashed at launch (R60), and not a version
    /// string, which the bundle cannot compute.
    static func bundledLine(contentRev: String) -> String {
        "Included in the app · record as of \(contentRev)"
    }

    /// Mirrors `updateLine`'s shape — what is newer, and what you are holding.
    static func bundledOutdatedLine(bundledContentRev: String) -> String {
        "Newer record available · included copy is \(bundledContentRev)"
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
            // This row used to be titled with the raw id — `us-ca-sj` — because "the manifest
            // carries the display name and it is unreachable". That reasoning was correct when it
            // was written and stopped being correct at s16: `dim_city.display_name` is inside every
            // published city file, narrowed to that city's single row by `publish_cities.py`, so
            // the disk does know the name now (`SeedCities`). The id survives as the fallback for a
            // file too old to carry one — still never a prettier name this layer made up
            // (DECISIONS constraint 15).
            title: installed.displayName ?? installed.id,
            coverageNote: nil,
            stateLine: CityDownloadsCopy.installedLine(version: installed.version),
            detailLine: nil,
            isFailure: false,
            progress: nil,
            affordances: isActive ? [.inUseLabel, .remove] : [.use, .remove]
        )
    }

    /// A city the app bundle holds and the catalog could not be reached to describe — or does not
    /// list at all. Disk facts alone, and the only honest thing to say is that you have it.
    ///
    /// No affordance: `Use` for the bundle belongs to the built-in card, which attaches the whole
    /// fused file rather than one of the cities inside it (R43 §1 — exactly one inventory is
    /// attached, always).
    static func bundled(_ city: SeedCities.City) -> CityDownloadRow {
        CityDownloadRow(
            id: city.id,
            title: city.displayName ?? city.id,
            coverageNote: nil,
            stateLine: city.contentRev.map(CityDownloadsCopy.bundledLine(contentRev:))
                ?? CityDownloadsCopy.builtInSubtitle,
            detailLine: nil,
            isFailure: false,
            progress: nil,
            affordances: []
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
        case let .bundled(contentRev):
            // The same principle as the branch above, applied to the opposite problem: the button
            // is not refused because it cannot work, it is refused because it would buy nothing.
            row = (CityDownloadsCopy.bundledLine(contentRev: contentRev), nil, [])
        case let .bundledOutdated(bundledContentRev):
            row = (
                CityDownloadsCopy.bundledOutdatedLine(bundledContentRev: bundledContentRev),
                nil,
                [.download]
            )
        }
        // The single rule, checked where both halves are in hand: no branch above may draw a
        // fetching affordance the state does not permit, and none may withhold one it does.
        // `CityDownloadsModel.download` refuses on the same property, so the button and the
        // transfer cannot disagree. `CityDownloadTests.everyStateAgreesWithAllowsDownload` is the
        // guard that runs in release too.
        assert(
            (row.affordances.contains(.download) || row.affordances.contains(.update))
                == state.allowsDownload,
            "row affordances \(row.affordances) disagree with \(state).allowsDownload"
        )
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
