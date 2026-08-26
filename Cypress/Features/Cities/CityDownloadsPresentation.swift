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
    /// **"choose the one the map draws" left with the choice**. Every downloaded city
    /// is drawn, so there is nothing to choose between.
    ///
    /// Caught by looking at the running You tab. This door's subtitle is the one string about the
    /// Cities screen that is not *on* the Cities screen, so rewriting that screen's vocabulary left
    /// it behind — nothing in the feature's own copy pointed at it, and no test named it.
    static let youRowSubtitle = "Download city inventories to add them to the map"

    // The built-in inventory card (ruling §3).
    static let builtInTitle = "Built-in inventory"
    static let builtInSubtitle = "Ships with the app and cannot be removed"

    // Affordances.
    //
    // **`Use` and `In use` are gone from the vocabulary entirely**. Downloading a city
    // is what puts it in the union and `Remove` is what takes it out; there is no third state in
    // which a city is on the phone and not being drawn, so there is no verb for entering or leaving
    // one. The four below plus `revert` are the whole of what this screen can say.
    static let download = "Download"
    static let update = "Update"
    static let remove = "Remove"
    static let cancel = "Cancel"

    /// **`Remove` is not the word for undoing an update to a bundled city**. It reads
    /// as removing the city, and the city cannot be removed — what is removed is the newer copy,
    /// and the entry returns to the bundled record.
    static let revert = "Revert to the included copy"

    /// What a city says when SQLite has no attachment slot left for it.
    ///
    /// **The button is replaced by this sentence rather than disabled beside it**, because a
    /// greyed-out `Download` states a refusal without stating a remedy. The limit is real — it is
    /// how many databases one connection may attach — and the only thing the reader can do about it
    /// is make room, so that is what the row says.
    ///
    /// It never appears for an *update*: replacing a city's file uses the slot that city already
    /// holds.
    static let atInstallCap = "Remove a city to download another."

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

    /// **What a downloaded file says when the read layer refused it.**
    ///
    /// The two sentences below are the only copy this fix-round wrote that no ruling had already
    /// settled. **The owner ratified them as shipped, verbatim, on 2026-08-25** — both lines, the
    /// attention color, and the division of labor described below — so they are ruled copy now
    /// rather than a proposal. The four existing failure lines were tried first and none of them is
    /// true here:
    /// `Download failed. Nothing was changed.` describes a transfer that never landed — this file
    /// did land, and verified; `Needs a newer app` and its detail line make a specific claim about
    /// the file's *generation*, which `CityLibrary.validateCityFile` already checks and which a
    /// merely malformed file does not fail.
    ///
    /// **It states the fact and lets the button state the remedy**, which is the same division
    /// `bundledOutdated` settled — `Remove` and `Revert to the included copy` are two different
    /// right answers here depending on whether the app also carries the city, and a sentence naming
    /// one of them would be wrong on the other row.
    ///
    /// `its trees` is the *file's* trees, deliberately. For a bundled city with a bad downloaded
    /// copy over it the bundled rows are drawing exactly as they always did — nothing is missing
    /// from the map — and the button underneath says `Revert to the included copy`, which is what
    /// tells the reader an included copy is what they are looking at.
    static let unreadableInventory = "Couldn't be read"
    static let unreadableInventoryDetail =
        "The downloaded file couldn't be opened, so its trees are not on the map."

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
        return "\(bundled) · record as of \(recordDate(contentRev))"
    }

    /// D5's line without its record-date clause.
    static let bundled = "Included in the app"

    /// The line for a bundled city whose rows a downloaded copy has replaced — the third of the
    /// three states such a city can be in. `Updated`, not `Installed`: the reader did not install a
    /// city, they refreshed one
    /// they already had.
    static func bundledUpdatedLine(contentRev: String?) -> String {
        guard let contentRev else { return bundledUpdated }
        return "\(bundledUpdated) · record as of \(recordDate(contentRev))"
    }

    static let bundledUpdated = "Updated"

    /// **`content_rev` rendered for a reader: the counter suffix comes off, and nothing else
    /// does.**
    ///
    /// The publisher's rev is an opaque ordered string and every *comparison* in this app keeps it
    /// whole — `CityInstallState` compares `publishedRev > bundledRev` on the full value and splits
    /// nothing. Only this one rendering trims, because the sentence it lands in says `record as of`
    /// and a same-day republish spells that record `2026-08-22.02`, which reads as a version where
    /// a date is promised. The live catalog carries exactly that on all seven packs since the
    /// republish of 2026-08-25.
    ///
    /// **It trims only what it recognizes.** A bare `2026-08-22` is returned unchanged, and so is
    /// anything that is not an ISO date followed by a run of digits — this must never invent a date
    /// out of a string it does not understand, which is the direction that would put a wrong day on
    /// screen. `CityCopyTests` pins both halves.
    static func recordDate(_ contentRev: String) -> String {
        let parts = contentRev.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let date = parts.first, let counter = parts.last,
              date.count == 10,
              date.allSatisfy({ $0.isNumber || $0 == "-" }),
              !counter.isEmpty, counter.allSatisfy(\.isNumber)
        else { return contentRev }
        return String(date)
    }

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
    /// **The verb under this line is `Update`, not `Download`**: a newer copy of a bundled city
    /// is an update to that city's data rather than a second inventory,
    /// so the sentence no longer names the transfer. It says what is true and lets the button say
    /// what it does.
    static let bundledOutdated = "A newer record is available."

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

    /// Unique within one screen, which the title alone is **not**: since a city's packs group inside
    /// *either* run, `New York City` can head a group under `On this phone` and another under
    /// `Available to download` in the same pass — two sections with one `ForEach` id, which SwiftUI
    /// resolves by dropping rows. Composed from the run and the parent city id rather than from the
    /// display name, so two cities that share a name cannot collide either.
    let id: String
    /// The heading drawn above the run — `On this phone`, `Available to download`, `New York City`.
    let title: String
    /// Whether this is a city grouping nested under a heading **that is present above it**, rather
    /// than one that heads its run. The view draws it one step quieter; nothing else differs. A
    /// group whose umbrella heading was suppressed (see `sections(from:parentCity:)`) is not one.
    ///
    /// **This is the `New York City`-over-five-boroughs case and only that case.** It was briefly
    /// also how the cities inside the built-in inventory were meant to be drawn, and it drew
    /// nothing: the flag reaches the view through one padding modifier that sits inside
    /// `if !section.title.isEmpty`, and that group's title is empty by construction — so the one
    /// section it was added for was the one section it could not affect. Containment is `cards`
    /// now, which the view has no way to ignore.
    let isCityGroup: Bool

    /// Every row in this section, in draw order, **including the ones drawn inside another row's
    /// card**. The flattening `CityDownloadsFeedbackTests.everyRowSurvivesSectioning` checks is this
    /// one, and it stays complete: containment is an arrangement of these rows (`cards`), not a
    /// second place to keep some of them.
    let rows: [CityDownloadRow]

    init(id: String? = nil, title: String, isCityGroup: Bool = false, rows: [CityDownloadRow]) {
        self.id = id ?? title
        self.title = title
        self.isCityGroup = isCityGroup
        self.rows = rows
    }

    /// One card and the entries drawn **inside its boundary**.
    ///
    /// The built-in inventory's card contains the cities the app ships with; every other card
    /// contains nothing. See `cards`.
    struct Card: Equatable, Identifiable {
        let row: CityDownloadRow
        let contained: [CityDownloadRow]
        var id: String { row.id }
    }

    /// `rows`, arranged into the cards the screen draws.
    ///
    /// **This is the ratified nesting, and it is a value rather than a view flag because the last
    /// attempt was a view flag and drew nothing.** The owner ruled on 2026-08-25 that the bundled
    /// cities go *inside* the built-in card — one card, its `Built-in inventory` /
    /// `Ships with the app and cannot be removed` / `Includes …` header, and San Francisco and San
    /// Jose contained within its boundary. The previous arrangement gave them their own section with
    /// an empty title and a `isCityGroup` flag whose only effect was a top padding the empty title
    /// skipped, so the screen drew three cards of identical width and inset in one undifferentiated
    /// column — the peer arrangement the ruling forbids outright — with a test asserting the pair
    /// of facts (`isCityGroup && title.isEmpty`) that together guaranteed nothing would render
    /// differently.
    ///
    /// `CityDownloadsView` draws this and has no other source of cards, so a row's containment
    /// cannot be true here and absent on screen. `CypressUITests/CityCardContainmentUITests` checks
    /// the frames on the device, which is the half no value can prove.
    ///
    /// **A contained row attaches only to the built-in card, by name.** Not "to the previous card":
    /// `isInsideBuiltIn` says which card it belongs to, so the arrangement asks for that card rather
    /// than assuming order put it there. A contained row with no built-in card above it — which
    /// `sections(from:parentCity:)` cannot produce, since the built-in row always opens that run —
    /// falls back to being its own card rather than disappearing.
    var cards: [Card] {
        var containers: [(row: CityDownloadRow, contained: [CityDownloadRow])] = []
        for row in rows {
            if row.isInsideBuiltIn, containers.last?.row.id == CityDownloadRow.builtInID {
                containers[containers.count - 1].contained.append(row)
            } else {
                containers.append((row, []))
            }
        }
        return containers.map { Card(row: $0.row, contained: $0.contained) }
    }

    /// Splits decided rows into `On this phone`, then everything else — with the packs of any city
    /// that has more than one of them gathered under that city's own name.
    ///
    /// - Parameter parentCity: what the manifest says a row's pack belongs to, as
    ///   `(id, displayName)`, or nil when the catalog does not say (a format-1 manifest, an offline
    ///   render, the built-in card). **Passed in rather than looked up**, because a manifest is not
    ///   a thing this file should hold — the model has one and this stays a pure function.
    ///
    /// Four properties worth stating, because each is a way this could have gone wrong:
    ///
    /// - **Every row lands in exactly one section, and no row is dropped.** The two branches
    ///   partition on `isOnDevice`, and each is re-assembled from the same array it was split from.
    ///   `CityDownloadsFeedbackTests.everyRowSurvivesSectioning` asserts it against the flattening
    ///   rather than trusting this sentence.
    /// - **Order inside a section is the order it came in**, which is the publisher's order (R43 §2)
    ///   for the catalog rows and the library's id order for the disk ones. Grouping reorders only
    ///   by moving a city's packs to where its first pack already was.
    /// - **A city with one pack gets no heading of its own.** A `New York City` heading over five
    ///   boroughs earns its line; a `San Francisco` heading over San Francisco is furniture.
    /// - **Grouping applies to both runs, and it did not always.** Counting packs only among the
    ///   *available* rows meant that downloading the boroughs destroyed the grouping the tester had
    ///   asked for — five NYC packs sat flat under `On this phone` with no `New York City` heading
    ///   anywhere, i.e. D5 was answered right up until the reader acted on it. The count is per run,
    ///   so three boroughs downloaded and two not gives a group in each.
    ///
    /// **A run's own heading is drawn even when every one of its rows grouped**, which is not
    /// obviously right and was decided by looking at the screen — see the comment on `run` below.
    /// **The `On this phone` run is opened by the built-in card, with the cities it holds drawn
    /// inside that card**, and only then by anything downloaded. A bundled city is never a peer card
    /// beside the built-in inventory, which is what the owner ruled and what `cards` draws.
    ///
    /// The three groups partition the on-device rows — the built-in card, the cities inside it, and
    /// everything else — so no row is dropped and none is drawn twice.
    /// `CityDownloadsFeedbackTests.everyRowSurvivesSectioning` asserts that against the flattening
    /// rather than trusting this sentence.
    ///
    /// The cities inside the built-in card carry **no heading of their own**, and now cannot: they
    /// are inside a card, not under a label. `New York City` over five boroughs earns its line
    /// because it says which city they are; a line over the built-in card's own cities would repeat
    /// the `Includes …` sentence already in the card's header.
    static func sections(
        from rows: [CityDownloadRow],
        parentCity: (CityDownloadRow) -> (id: String, displayName: String)?
    ) -> [CityDownloadSection] {
        let onDevice = rows.filter(\.isOnDevice)
        let builtIn = onDevice.filter { $0.id == CityDownloadRow.builtInID }
        let insideBuiltIn = onDevice.filter(\.isInsideBuiltIn)
        let downloaded = onDevice.filter {
            $0.id != CityDownloadRow.builtInID && !$0.isInsideBuiltIn
        }

        var sections: [CityDownloadSection] = []
        if !onDevice.isEmpty {
            // **The built-in card and the cities it holds are one section, in that order**, because
            // they are one card: `cards` folds the trailing `isInsideBuiltIn` rows into the card the
            // built-in row opens. They were two sections, the second titleless and flagged
            // `isCityGroup`, and the flag drew nothing — see `cards`.
            sections.append(
                CityDownloadSection(
                    id: "on-device",
                    title: CityDownloadsCopy.onDeviceSection,
                    rows: builtIn + insideBuiltIn
                )
            )
            sections += run(
                downloaded, heading: "", key: "on-device-downloaded", parentCity: parentCity
            )
        }
        return sections + run(
            rows.filter { !$0.isOnDevice },
            heading: CityDownloadsCopy.availableSection, key: "available", parentCity: parentCity
        )
    }

    /// One run of the screen — the rows under one of the two fixed headings — split into that
    /// heading's own remainder and a section per city with more than one pack in this run.
    private static func run(
        _ rows: [CityDownloadRow],
        heading: String,
        key: String,
        parentCity: (CityDownloadRow) -> (id: String, displayName: String)?
    ) -> [CityDownloadSection] {
        guard !rows.isEmpty else { return [] }

        // Which parents have more than one pack in THIS run — the test for whether a grouping
        // heading says anything.
        var packsPerParent: [String: Int] = [:]
        for row in rows {
            guard let parent = parentCity(row) else { continue }
            packsPerParent[parent.id, default: 0] += 1
        }

        // First-seen order, so a group lands where its first pack already was.
        var groupOrder: [String] = []
        var grouped: [String: [CityDownloadRow]] = [:]
        var ungrouped: [CityDownloadRow] = []
        for row in rows {
            guard let parent = parentCity(row), packsPerParent[parent.id, default: 0] > 1 else {
                ungrouped.append(row)
                continue
            }
            if grouped[parent.id] == nil { groupOrder.append(parent.id) }
            grouped[parent.id, default: []].append(row)
        }

        // **The run's own heading is always drawn, including with nothing directly under it**, and
        // that is a decision the running screen reversed once. Dropping an empty heading is the
        // obvious tidy: today's live catalog groups *every* available pack under `New York City`, so
        // `Available to download` renders with no cards beneath it. But the moment a reader
        // downloads one borough, the same city has a group in **both** runs — and with the umbrella
        // suppressed the screen draws `New York City` twice in a row, in the same micro-label idiom,
        // with nothing between them saying that the first is installed and the second is not.
        // Photographed on the device at 402 pt with Manhattan and Staten Island installed. An empty
        // heading says nothing; two identical adjacent headings say something false. See the PR for
        // the four alternatives put to the owner.
        var sections = [CityDownloadSection(id: key, title: heading, rows: ungrouped)]
        for parentID in groupOrder {
            let packs = grouped[parentID] ?? []
            // The heading is the parent's own display name, taken from a pack that named it.
            let name = packs.compactMap { parentCity($0)?.displayName }.first ?? parentID
            sections.append(
                CityDownloadSection(
                    id: "\(key)/\(parentID)",
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

    /// Whether this row is one of the cities the **built-in inventory** holds, and so belongs
    /// nested under its card rather than beside it.
    ///
    /// A bundled city is not something the reader can add or remove, so it is never a peer card in
    /// `On this phone` — that arrangement is what let the built-in card say `Includes San Francisco`
    /// while a sibling card offered to `Use` it — the built-in card and a per-city entry may never
    /// contradict each other, and that pair did.
    ///
    /// Read off the install state rather than set by hand at each call site, for the same reason
    /// `isOnDevice` is: the two facts that decide where a card is filed both come from the one type
    /// that knows what the device holds.
    let isInsideBuiltIn: Bool

    /// **Four verbs and a revert, and no way to say `Use`**. Downloaded means in the
    /// union, so there is no active set to join or leave and no label for having joined it.
    enum Affordance: Equatable {
        case download
        case update
        case remove
        case cancel
        /// Undoes an update to a **bundled** city, returning it to the copy inside the app. Not
        /// `remove` under another name: the city stays, only the newer copy goes.
        case revert
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
        isInsideBuiltIn: Bool = false,
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
        self.isInsideBuiltIn = isInsideBuiltIn
        self.affordances = affordances
    }

    static let builtInID = "built-in"

    // MARK: - Deciding a row

    /// The built-in bundle's card. **It draws no affordance at all**.
    ///
    /// Not `Use`, not `In use`, not `Remove`. The bundled inventory cannot be switched off, so a
    /// control saying otherwise is exactly the contradiction the ruling forbids — an `In use` label
    /// above a sibling `Use` was the screen the owner ruled out. `Ships with the app and cannot be
    /// removed` already states the operative fact and needs no button under it.
    ///
    /// - Parameter cityNames: the names the bundled seed states for the cities it holds, in the
    ///   order they should be read. Empty is a legitimate answer (a test bundle with no seed), and
    ///   the card then says exactly what it said before.
    static func builtIn(cityNames: [String] = []) -> CityDownloadRow {
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
            affordances: []
        )
    }

    /// A published city's card, from the facts the model holds. Every branch is ruling §3's list.
    static func published(
        city: CityManifest.City,
        state: CityInstallState,
        hasInstallHeadroom: Bool = true,
        downloadingFraction: Double?,
        lastAttemptFailed: Bool
    ) -> CityDownloadRow {
        let coverage = city.coverage == "full" ? nil : CityDownloadsCopy.coverageNote(city.coverage)

        if let downloadingFraction {
            return CityDownloadRow(
                id: city.id, title: city.displayName, coverageNote: coverage,
                stateLine: CityDownloadsCopy.downloading, detailLine: nil,
                isFailure: false, progress: downloadingFraction,
                isOnDevice: state.isOnDevice, isInsideBuiltIn: state.isBundledCity,
                affordances: [.cancel]
            )
        }
        if lastAttemptFailed {
            // The state reverts to whatever was true before the attempt; only the line differs.
            let base = decide(city: city, state: state, hasInstallHeadroom: hasInstallHeadroom)
            return CityDownloadRow(
                id: base.id, title: base.title, coverageNote: base.coverageNote,
                stateLine: CityDownloadsCopy.downloadFailed, detailLine: nil,
                isFailure: true, progress: nil,
                isOnDevice: base.isOnDevice, isInsideBuiltIn: base.isInsideBuiltIn,
                affordances: base.affordances
            )
        }
        return decide(city: city, state: state, hasInstallHeadroom: hasInstallHeadroom)
    }

    /// An installed city the manifest could not vouch for (offline): disk facts alone, and every
    /// affordance that needs no network.
    static func installedOffline(
        _ installed: CityLibrary.InstalledCity
    ) -> CityDownloadRow {
        CityDownloadRow(
            id: installed.id,
            // This row used to be titled with the raw id — `us-ca-sj` — because "the manifest
            // carries the display name and it is unreachable". That reasoning was correct when it
            // was written and stopped being correct at s16: `dim_city.display_name` is inside every
            // published city file, narrowed to that city's single row by `publish_cities.py`, so
            // the disk does know the name now (`SeedCities`). s17 added the half that `dim_city`
            // could never answer — `dim_region.display_name`, the name of the *pack* — so a
            // borough reads `Manhattan` here offline rather than `us-ny-nyc-manhattan`. The id
            // survives as the fallback for a file too old to carry either — still never a prettier
            // name this layer made up (DECISIONS constraint 15).
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
            // A downloaded pack is in the union whether or not the catalog can be reached to
            // describe it, so the only question an offline row can put is whether to keep it.
            affordances: [.remove]
        )
    }

    /// A bundled city whose rows a downloaded copy has replaced, described from **disk facts
    /// alone** — the offline twin of `CityInstallState.bundledUpdated`.
    ///
    /// The catalog is what decides whether an even newer record exists, so an offline row cannot
    /// offer `Update` and does not pretend to. What it can say is which record is drawing and how
    /// to go back, and both are read out of the installed file's own receipt.
    static func bundledUpdatedOffline(
        _ installed: CityLibrary.InstalledCity,
        bundled: SeedCities.City
    ) -> CityDownloadRow {
        CityDownloadRow(
            id: installed.id,
            title: installed.displayName ?? bundled.displayName ?? installed.id,
            coverageNote: coverageIfPartial(installed.coverage ?? bundled.coverage),
            stateLine: CityDownloadsCopy.bundledUpdatedLine(contentRev: installed.contentRev),
            detailLine: nil,
            isFailure: false,
            progress: nil,
            isOnDevice: true,
            isInsideBuiltIn: true,
            affordances: [.revert]
        )
    }

    /// A city the app bundle holds and the catalog could not be reached to describe — or does not
    /// list at all. Disk facts alone, and the only honest thing to say is that you have it.
    ///
    /// **No affordance at all.** A bundled city cannot be added, and it cannot be removed while the
    /// app carries it; nothing this row could offer would be true. The card it nests inside says
    /// `Ships with the app and cannot be removed`, which is the operative fact for this entry too.
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
            isInsideBuiltIn: true,
            affordances: []
        )
    }

    private static func decide(
        city: CityManifest.City,
        state: CityInstallState,
        hasInstallHeadroom: Bool
    ) -> CityDownloadRow {
        var row: (stateLine: String, detail: String?, affordances: [Affordance])
        switch state {
        case .notInstalled:
            row = (CityDownloadsCopy.size(city.bytes), nil, [.download])
        case let .installedCurrent(version):
            row = (CityDownloadsCopy.installedLine(version: version), nil, [.remove])
        case let .updateAvailable(version):
            // **Two buttons again, because the third one left the vocabulary.** This row used to
            // draw `Use`, `Update` and `Remove` — three, against R43 §3's "never more than two
            // visible" — because a downloaded city that was not the active one had to offer a way
            // to become it. There is no such state now: downloaded means in the union, so the copy
            // on disk is drawing the moment it lands and the only questions left are whether to
            // take the newer record
            // and whether to keep the city at all.
            //
            // The tester report that bought the third button is answered by the union rather than
            // by this row (build 49, 2026-08-23): *"I have manhattan downloaded already and used it
            // once but then I clicked use on the default inventory and now I can't seem to use
            // manhattan even though it's on my phone"*. There is no longer a click that can put a
            // downloaded city out of use.
            row = (
                CityDownloadsCopy.updateLine(installedVersion: version), nil, [.update, .remove]
            )
        case let .needsNewerApp(installed):
            if let installed {
                // The older compatible copy is still in the union; only the update is refused.
                row = (
                    CityDownloadsCopy.installedLine(version: installed),
                    CityDownloadsCopy.needsNewerAppDetail,
                    [.remove]
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
            // to sell the reader a city already on the phone.
            //
            // **The verb is `Update`, not `Download`**, because a newer copy of a bundled city is
            // an update to that city's data rather than a second inventory to acquire.
            row = (
                CityDownloadsCopy.bundledLine(contentRev: bundledContentRev),
                CityDownloadsCopy.bundledOutdated,
                [.update]
            )
        case let .bundledUpdated(installedContentRev, updateAvailable):
            // The third state a bundled city can be in. `Revert to the included copy` rather than
            // `Remove`: the city is not going anywhere, only the newer copy is.
            row = (
                CityDownloadsCopy.bundledUpdatedLine(contentRev: installedContentRev),
                updateAvailable ? CityDownloadsCopy.bundledOutdated : nil,
                updateAvailable ? [.update, .revert] : [.revert]
            )
        }
        // ── The attachment cap ────────────────────────────────────────────────────
        //
        // Applied here, after the state decided what the row would otherwise offer, and applied
        // **only to a fetch that would add an inventory**. A city with no copy on disk needs a slot
        // of its own; an update replaces the file in the slot that city already occupies, so it is
        // never withheld — a reader at the cap can still take a newer record for everything they
        // have. `state.isOnDevice` is the test, because being on the device is exactly what having
        // a slot means here, and a bundled city's slot is the bundle's own.
        if !hasInstallHeadroom, !state.isOnDevice, row.affordances.contains(.download) {
            row = (
                row.stateLine,
                CityDownloadsCopy.atInstallCap,
                row.affordances.filter { $0 != .download }
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
            isOnDevice: state.isOnDevice, isInsideBuiltIn: state.isBundledCity,
            affordances: row.affordances
        )
    }

    /// The same row, restated for a downloaded file the read layer could not open.
    ///
    /// **A post-pass over a decided row rather than an eighth `CityInstallState` case**, and the
    /// reason is where the fact comes from. Every other line on this screen is decided from the
    /// catalog, the library and the bundle — three things this feature can ask. Whether a file
    /// *opened* is a fact only the boot knows, it is discovered after all three have spoken, and it
    /// does not change what the reader may do about the city. So it changes the two lines that state
    /// what is true and leaves the rest of the row where it was.
    ///
    /// **The affordances are kept exactly as decided, not replaced**, which is the point of
    /// surfacing this at all: for a downloaded pack they are `Remove`, for a bundled city with a bad
    /// copy over it `Revert to the included copy`, and where the catalog has a newer record,
    /// `Update` beside either — which replaces the unreadable file and is the other real remedy.
    /// Every one of those is still the right action on a file that did not open, and a row that said
    /// only that something was wrong would leave the reader where the failed boot left them.
    /// `Download` cannot appear here, because this only reaches a row already on the device.
    ///
    /// `isInsideBuiltIn` and `isOnDevice` are kept too: the file is on the phone whether or not it
    /// opened, and a bundled city does not stop being one because its update is unreadable.
    func unreadable() -> CityDownloadRow {
        CityDownloadRow(
            id: id,
            title: title,
            coverageNote: coverageNote,
            stateLine: CityDownloadsCopy.unreadableInventory,
            detailLine: CityDownloadsCopy.unreadableInventoryDetail,
            isFailure: true,
            progress: nil,
            isOnDevice: isOnDevice,
            isInsideBuiltIn: isInsideBuiltIn,
            affordances: affordances
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
