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

    // MARK: - Section headings
    //
    // R43 §2 rules the screen as one flat list — "one card for the built-in inventory, then one card
    // per city the manifest lists, in manifest order. That is the whole screen." That was written
    // when the catalog held two cities. It holds seven, five of them New York boroughs, and a tester
    // filed the same complaint from two directions on the same evening (build 49, 2026-08-23):
    // *"The NYC ones should be visually grouped somehow under NYC"*, and *"there needs to be visual
    // grouping and section separation. If a city is downloaded and usable it should be at top,
    // separated from others."*
    //
    // Two headings, in the You tab's existing micro-label idiom — no new component, no new chrome.

    /// Above the inventories the device already holds: the built-in card, the cities inside it, and
    /// anything downloaded. "On this phone" rather than "Installed", because the built-in seed is
    /// not installed in any sense the reader performed.
    static let onDeviceSection = "On this phone"

    /// Above everything else. The one heading a reader has to act under.
    static let availableSection = "Available to download"

    /// A city's own name, used as a heading when several of its packs are listed together — `New
    /// York City` over the five boroughs. **The manifest's `parent_city_display_name`**, which is a
    /// civic string entered at publish; this file never composes one (DECISIONS constraint 15).
    static func cityGroupHeading(_ parentCityDisplayName: String) -> String {
        parentCityDisplayName
    }

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
    ///
    /// A nil `contentRev` **drops the suffix** rather than reaching for another card's copy. This
    /// row briefly borrowed `builtInSubtitle` for that case, which put `Ships with the app and
    /// cannot be removed` — a sentence R43 §3 wrote for the built-in card, and a removability claim
    /// — onto a city row, and invented a third state D5 never ruled. The line below is D5's own,
    /// minus a clause the file could not back: no new sentence, and nothing claimed that is not
    /// known.
    static func bundledLine(contentRev: String?) -> String {
        guard let contentRev else { return bundled }
        return "\(bundled) · record as of \(contentRev)"
    }

    /// D5's line without its record-date clause.
    static let bundled = "Included in the app"

    /// Mirrors `updateLine`'s shape — what is newer, and what you are holding.
    ///
    /// **No longer the state line; now the quieter second line.** As the state line it was the only
    /// thing a bundled city's card said, so San Francisco and San Jose — both shipped inside the
    /// app, both drawn on the map at that moment — announced a newer record and a `Download` button
    /// and never once said they were already there. A tester read that as the screen offering to
    /// sell him what he had: *"Why am I seeing option to download sf and San Jose when those cities
    /// SHIP WITH THE APP?? Bad design"* (build 49, 2026-08-23).
    ///
    /// The fix is order, not new facts. `bundledLine` states possession first — it is the more
    /// important of the two and it was the one missing — and this line states the offer underneath.
    /// Both sentences were already true; only one of them was on screen.
    ///
    /// **The record date left with the clause that used to carry it.** `bundledLine(contentRev:)`
    /// now states it directly above (`Included in the app · record as of 2026-07-31`), and repeating
    /// `included copy is 2026-07-31` under it would print one date twice in two spellings. What is
    /// left is the half the line above cannot say.
    static let bundledOutdated = "A newer record is available to download."

    /// Which cities the bundled seed holds, named from the seed itself.
    ///
    /// R43 §3 gives the built-in card a title and one subtitle, and a tester found the gap the pair
    /// leaves: *"On this view we should say WHAT CITIES ship in the pre-built seed. Right now all it
    /// says is THAT there's an inventory not WHAT ITS OF"* (build 49, 2026-08-23).
    ///
    /// **Every name here is read out of the shipped file** (`SeedCities.inMainBundle` →
    /// `dim_city.display_name`), never a list written down in this file — which is DECISIONS
    /// constraint 15, and also the only version that cannot go stale the day the bundle changes.
    /// Nil when the seed names nothing, so a card that has learned nothing says nothing extra.
    static func builtInCitiesLine(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "Includes \(names[0])"
        case 2: return "Includes \(names[0]) and \(names[1])"
        default:
            return "Includes \(names.dropLast().joined(separator: ", ")), and \(names[names.count - 1])"
        }
    }

    // MARK: - NYC Data Mine disclaimer (RULINGS R78 ruling 2)

    /// Heading above the required block. Ours, not the City's.
    static let nycDisclaimerHeading = "Data disclaimer"

    /// **VERBATIM, AND THE ONLY STRING IN THIS APP THAT MUST NOT BE EDITED.**
    ///
    /// Quoted exactly from the NYC.gov Data Mine Terms of Use, obligation (B), as recorded in
    /// `docs/operations/nyc-data-obligations.md` §1 and §4 (fetched 2026-08-01 and re-fetched
    /// 2026-08-21, text identical both times; cached at `Fixtures/raw/nyc/datamine_terms.html`).
    /// RULINGS R78 ruling 2 puts it on this screen and is the constraint-21 sign-off for doing so;
    /// R78 ruling 3 says the manifest's machine-readable `attribution` array does **not** discharge
    /// the obligation, so this text has to be rendered and human-visible.
    ///
    /// Three things a future edit will be tempted by, and must not do:
    ///
    /// - **`can not`, two words, is the City's spelling.** "cannot" is the ordinary one and is
    ///   wrong here. This is the one place CLAUDE.md's American-spellings rule does not reach,
    ///   because the rule is about copy this project writes and this is copy it quotes.
    /// - **`this web site or application`** stays as two nouns, and `web site` stays two words.
    /// - **The enclosing quotation marks are not part of it.** The terms present the block inside
    ///   quotes because the surrounding sentence is quoting it; rendering the marks on screen would
    ///   add punctuation the City did not write into its own disclaimer.
    ///
    /// `NYCDisclaimerTests` compares this against a copy read out of
    /// `docs/operations/nyc-data-obligations.md` at test time, so a drift in either direction is a
    /// red test rather than a compliance failure nobody notices.
    static let nycDisclaimerRequired = """
        The City of New York can not vouch for the accuracy or completeness of data provided by \
        this web site or application or for the usefulness or integrity of the web site or \
        application. This site provides applications using data that has been modified for use \
        from its original source, NYC.gov, the official web site of the City of New York.
        """

    /// The self-locating line `docs/operations/nyc-data-obligations.md` §4 recommends beneath the
    /// required block. **Not required by the terms** — it names which datasets and which agency, so
    /// the disclaimer above is not a floating sentence about an unnamed city. Ours, so ordinary
    /// house style applies; it is kept in a separate constant precisely so that editing it can
    /// never reach the required text.
    static let nycDisclaimerAttribution = """
        New York City tree data is drawn from the NYC Department of Parks and Recreation's \
        Forestry Tree Points and Forestry Planting Spaces datasets (NYC Open Data), used under \
        the NYC.gov Data Mine Terms of Use.
        """
}

/// One headed run of cards on the Cities screen.
///
/// **The screen is a list of these now, not a list of rows** (see `CityDownloadsCopy.onDeviceSection`
/// for the two tester reports that bought the change). The grouping is decided here, as a pure
/// function of rows the model has already decided, so the whole of it is unit-testable without a
/// view: `CityDownloadsModel.sections` is the only caller and `rows` remains the flattening.
struct CityDownloadSection: Equatable, Identifiable {

    /// The heading drawn above the run — `On this phone`, `Available to download`, `New York City`.
    let title: String
    /// Whether this is a city grouping nested under `Available to download` rather than a top-level
    /// heading. The view draws it one step quieter; nothing else differs.
    let isCityGroup: Bool
    let rows: [CityDownloadRow]

    /// The heading, which is unique among the sections of one screen: the two fixed headings are
    /// distinct from each other, and a city group is titled with a `parent_city_display_name` that
    /// names exactly one parent city per pass.
    var id: String { title }

    init(title: String, isCityGroup: Bool = false, rows: [CityDownloadRow]) {
        self.title = title
        self.isCityGroup = isCityGroup
        self.rows = rows
    }

    /// Splits decided rows into `On this phone`, then everything else — with the packs of any city
    /// that has more than one of them gathered under that city's own name.
    ///
    /// - Parameter parentCity: what the manifest says a row's pack belongs to, as
    ///   `(id, displayName)`, or nil when the catalog does not say (a format-1 manifest, an offline
    ///   render, the built-in card). **Passed in rather than looked up**, because a manifest is not
    ///   a thing this file should hold — the model has one and this stays a pure function.
    ///
    /// Three properties worth stating, because each is a way this could have gone wrong:
    ///
    /// - **Every row lands in exactly one section, and no row is dropped.** The two branches
    ///   partition on `isOnDevice`, and the second is re-assembled from the same array it was split
    ///   from. `CityDownloadSectionTests.everyRowSurvivesSectioning` asserts it against the
    ///   flattening rather than trusting this sentence.
    /// - **Order inside a section is the order it came in**, which is the publisher's order (R43 §2)
    ///   for the catalog rows and the library's id order for the disk ones. Grouping reorders only
    ///   by moving a city's packs to where its first pack already was.
    /// - **A city with one pack gets no heading of its own.** A `New York City` heading over five
    ///   boroughs earns its line; a `San Francisco` heading over San Francisco is furniture.
    static func sections(
        from rows: [CityDownloadRow],
        parentCity: (CityDownloadRow) -> (id: String, displayName: String)?
    ) -> [CityDownloadSection] {
        let onDevice = rows.filter(\.isOnDevice)
        let available = rows.filter { !$0.isOnDevice }

        var sections: [CityDownloadSection] = []
        if !onDevice.isEmpty {
            sections.append(CityDownloadSection(title: CityDownloadsCopy.onDeviceSection, rows: onDevice))
        }
        guard !available.isEmpty else { return sections }

        // Which parents have more than one pack among the available rows — the test for whether a
        // grouping heading says anything.
        var packsPerParent: [String: Int] = [:]
        for row in available {
            guard let parent = parentCity(row) else { continue }
            packsPerParent[parent.id, default: 0] += 1
        }

        // First-seen order, so a group lands where its first pack already was.
        var groupOrder: [String] = []
        var grouped: [String: [CityDownloadRow]] = [:]
        var ungrouped: [CityDownloadRow] = []
        for row in available {
            guard let parent = parentCity(row), packsPerParent[parent.id, default: 0] > 1 else {
                ungrouped.append(row)
                continue
            }
            if grouped[parent.id] == nil { groupOrder.append(parent.id) }
            grouped[parent.id, default: []].append(row)
        }

        sections.append(
            CityDownloadSection(title: CityDownloadsCopy.availableSection, rows: ungrouped)
        )
        for parentID in groupOrder {
            let packs = grouped[parentID] ?? []
            // The heading is the parent's own display name, taken from a pack that named it.
            let name = packs.compactMap { parentCity($0)?.displayName }.first ?? parentID
            sections.append(
                CityDownloadSection(
                    title: CityDownloadsCopy.cityGroupHeading(name),
                    isCityGroup: true,
                    rows: packs
                )
            )
        }
        return sections
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
    /// Whether this inventory is already on the device — installed, or inside the app bundle.
    ///
    /// **The one fact the sectioning needs, and it is read off the install state rather than off the
    /// row's buttons** (`CityInstallState.isOnDevice`) — so a card cannot be filed under
    /// `On this phone` on any ground other than the device actually holding it.
    ///
    /// A download in flight keeps whatever was true before it started: a first download stays under
    /// `Available to download` until its bytes are verified and installed, and an *update* to a city
    /// already on the phone does not leave the top section while it runs. Both follow from asking
    /// the state, and both are what the reader is looking at.
    let isOnDevice: Bool

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

    /// Spelled out rather than synthesized so `isOnDevice` can carry a default: every call site that
    /// predates sectioning describes a row that is not on the device, and saying so eight times adds
    /// nothing. The factories below state it where it is true.
    init(
        id: String,
        title: String,
        coverageNote: String?,
        stateLine: String,
        detailLine: String?,
        isFailure: Bool,
        progress: Double?,
        isOnDevice: Bool = false,
        affordances: [Affordance]
    ) {
        self.id = id
        self.title = title
        self.coverageNote = coverageNote
        self.stateLine = stateLine
        self.detailLine = detailLine
        self.isFailure = isFailure
        self.progress = progress
        self.isOnDevice = isOnDevice
        self.affordances = affordances
    }

    static let builtInID = "built-in"

    // MARK: - Deciding a row

    /// The built-in bundle's card: `Use` when a city is active, the `In use` label otherwise.
    ///
    /// - Parameter cityNames: the names the bundled seed states for the cities it holds, in the
    ///   order they should be read. Empty is a legitimate answer (a test bundle with no seed), and
    ///   the card then says exactly what it said before.
    static func builtIn(isActive: Bool, cityNames: [String] = []) -> CityDownloadRow {
        CityDownloadRow(
            id: builtInID,
            title: CityDownloadsCopy.builtInTitle,
            coverageNote: nil,
            stateLine: CityDownloadsCopy.builtInSubtitle,
            // What is actually in it — see `CityDownloadsCopy.builtInCitiesLine`.
            detailLine: CityDownloadsCopy.builtInCitiesLine(cityNames),
            isFailure: false,
            progress: nil,
            isOnDevice: true,
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
                isFailure: false, progress: downloadingFraction,
                isOnDevice: state.isOnDevice, affordances: [.cancel]
            )
        }
        if lastAttemptFailed {
            // The state reverts to whatever was true before the attempt; only the line differs.
            let base = decide(city: city, state: state, isActive: isActive)
            return CityDownloadRow(
                id: base.id, title: base.title, coverageNote: base.coverageNote,
                stateLine: CityDownloadsCopy.downloadFailed, detailLine: nil,
                isFailure: true, progress: nil,
                isOnDevice: base.isOnDevice, affordances: base.affordances
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
            // Same argument as the title, one line down: R43 §3 lists coverage as a city card's
            // second line, and since s16 the installed file's own `seed_meta` states it. A row that
            // knew San Jose's name from the file and still hid its downtown-only limit would be
            // stating the easy half of what it read.
            coverageNote: coverageIfPartial(installed.coverage),
            stateLine: CityDownloadsCopy.installedLine(version: installed.version),
            detailLine: nil,
            isFailure: false,
            progress: nil,
            isOnDevice: true,
            affordances: isActive ? [.inUseLabel, .remove] : [.use, .remove]
        )
    }

    /// A city the app bundle holds and the catalog could not be reached to describe — or does not
    /// list at all. Disk facts alone, and the only honest thing to say is that you have it.
    ///
    /// No affordance: `Use` for the bundle belongs to the built-in card, which attaches the whole
    /// fused file rather than one of the cities inside it (R43 §1 — exactly one inventory is
    /// attached, always).
    ///
    /// **Coverage is drawn here, from the file.** This row is a city card by R43 §3's definition,
    /// and that ruling lists coverage as a card's second line without conditioning it on where the
    /// facts came from; §3.3 lists coverage as one of the four things Stage 0 derives from the
    /// bundle, and §6.1 — the text D5 approved *as scoped* — repeats it. It was briefly omitted on
    /// the argument that an offline row had never drawn one, which was true of `installedOffline`
    /// and not of this row: San Jose's downtown-only limit was the one fact available and unstated.
    static func bundled(_ city: SeedCities.City) -> CityDownloadRow {
        CityDownloadRow(
            id: city.id,
            title: city.displayName ?? city.id,
            coverageNote: coverageIfPartial(city.coverage),
            stateLine: CityDownloadsCopy.bundledLine(contentRev: city.contentRev),
            detailLine: nil,
            isFailure: false,
            progress: nil,
            isOnDevice: true,
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
            // **`Use` belongs here, and R43 §3's own table left it out.** That table lists
            // `update available → Update and Remove`, which silently makes an installed city
            // unusable the moment the catalog moves ahead of it: the copy on disk is complete,
            // attachable and *not* in use, and the one button that would attach it is missing. R43
            // §1 already says such a row "shows the city as installed but not in use" — a state
            // whose whole point is that `Use` is available.
            //
            // Reported by a tester who hit exactly that (build 49, 2026-08-23): *"I have manhattan
            // downloaded already and used it once but then I clicked use on the default inventory
            // and now I can't seem to use manhattan even though it's on my phone"*. The download was
            // fine; only the affordance was gone.
            //
            // **This is the one row that draws three buttons**, against §3's parenthetical "never
            // more than two visible". Dropping `Remove` instead would strand the other direction —
            // a city you cannot delete until you have first updated it — and demoting `Update` would
            // hide the newer record the line above is announcing. The count is the thing that gives,
            // and it does so for one state; see the PR for the alternatives put to the owner.
            row = (
                CityDownloadsCopy.updateLine(installedVersion: version), nil,
                isActive ? [.inUseLabel, .update, .remove] : [.use, .update, .remove]
            )
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
            // Possession first, offer second — the card says what you have before what you could
            // fetch. Same two facts as before, in the order that stops the row reading as an offer
            // to sell the reader a city already on the phone. See `bundledOutdatedLine`.
            row = (
                CityDownloadsCopy.bundledLine(contentRev: bundledContentRev),
                CityDownloadsCopy.bundledOutdated,
                [.download]
            )
        }
        // No branch above may draw a fetching affordance `CityInstallState.allowsDownload` does not
        // permit, and none may withhold one it does. `CityDownloadsModel.download` refuses on that
        // same property, so the button and the transfer cannot disagree — which is what makes a
        // second copy of a city the device already holds structurally impossible rather than merely
        // unreachable. The invariant is asserted exhaustively over the enum in
        // `BundledCityTests.everyStateAgreesWithAllowsDownload`, not by a debug `assert` here: a
        // crash in a release-mode-invisible check is a worse guard than a test that always runs.
        return CityDownloadRow(
            id: city.id, title: city.displayName, coverageNote: coverageIfPartial(city.coverage),
            stateLine: row.stateLine, detailLine: row.detail,
            isFailure: false, progress: nil,
            isOnDevice: state.isOnDevice, affordances: row.affordances
        )
    }

    /// One reading of the coverage word for every row that draws one, whether it came from the
    /// manifest or out of a file's own `seed_meta` (`SeedCities.coverage`). `"full"` and absent are
    /// the same thing said two ways — the publisher writes the word, the seed omits the key.
    private static func coverageIfPartial(_ coverage: String?) -> String? {
        guard let coverage, coverage != "full", !coverage.isEmpty else { return nil }
        return CityDownloadsCopy.coverageNote(coverage)
    }
}
