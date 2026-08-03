//
//  SitePresentation.swift
//  Cypress — Features/Site
//
//  The vacant planting site. **Not in SCREENS.md**, and decided rather than transcribed: ERRATA
//  E107 closes E11 and is where the reasoning for every sentence below lives.
//
//  ── Why this is not screen 14 ─────────────────────────────────────────────────────────────
//  12,413 of the shipped seed's 145,837 rows — 8.5% of the map — are planting basins with no tree
//  in them.
//  Rendered as a cold profile they offered "be the first to photograph this tree" and a photo well,
//  both of which assert a tree. Deleting those two elements leaves a tree profile with fields
//  missing, and **a tree profile with fields missing still asserts a tree.** So a site is its own
//  record here: every string on this screen is a claim about the *site*.
//
//  ── The two rules that shape this file ────────────────────────────────────────────────────
//  - **Nothing promises an outcome.** Cypress does not plant trees and cannot ask anybody to
//    (ARCHITECTURE §5.4). There is no "report this", no "request a tree", and no sentence anywhere
//    below in which an authority has been told anything.
//  - **Nothing is written from this screen.** `TreeStatus.acceptsNewContributions` is false for a
//    vacant site, and this presentation has no CTA to withhold — it has none to offer. The finding
//    underneath that, recorded in E107: every contribution the app can express asserts a tree, down
//    to the private reminder, which cannot be written without a `HazardCategory` and whose four
//    values are all about a tree.
//
//  No SwiftUI in this file (`CypressTests/SiteTests.swift`).
//

import Foundation

/// Everything the site screen renders, derived from one `TreeProfile` plus, when there is one, the
/// nearest tree that is actually standing.
struct SitePresentation: Equatable {

    /// One card of the stat grid (C11).
    struct Stat: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String
    }

    /// The nearest standing tree, as one C10 row.
    ///
    /// **The only affordance on the screen, and it is a read.** It states a fact about the site's
    /// surroundings — which is a thing that is true about the site — and it hands the reader
    /// somewhere real to go, which is what keeps this from being the dead end a degraded profile was.
    struct Neighbor: Equatable, Identifiable {
        let id: UUID
        /// The tree's display name, by the same precedence every other surface uses.
        let title: String
        /// `24 m away · the nearest tree to this site`.
        let detail: String
    }

    /// The H1 — the street address, which is the only thing that identifies a site.
    let title: String
    /// The italic serif line under it: what the record is, and where it came from.
    let subtitle: String

    /// The C14 dashed callout, which is the screen's one unavoidable sentence.
    let statementLeadIn: String
    let statementBody: String

    /// What the city recorded, and nothing else.
    let stats: [Stat]

    /// `From the DataSF Street Tree List, 20 July 2026.` — under the stat grid, or nothing.
    ///
    /// **This screen needs its own, and the reason is the whole of #91's second round.** The seed
    /// draws its living trees from SF Public Works' operational layer and its vacant planting sites
    /// from the DataSF export, because the layer has no vacant-site category and has therefore never
    /// listed one of these records. So the sentence the tree page draws — naming the city's
    /// inventory and the day it was read — is *false of every site on this screen*, and a screen
    /// whose entire content is a claim that nothing is growing here is the worst place in the app
    /// to be vague about who says so.
    ///
    /// Same two rules the tree page's line follows (`CityRecordCopy.provenanceNote`): the inventory
    /// is named, never "San Francisco" alone, and the sentence is absent rather than dateless when
    /// the seed cannot say when its records were read.
    let provenanceNote: String?

    /// The nearest standing tree, or nil when none is within reach — in which case the row is
    /// absent rather than reworded.
    let neighbor: Neighbor?

    /// The closing line, in the place screen 14 puts its own footnote.
    let footnote: String

    /// The map this screen can send the reader to (ERRATA E144).
    ///
    /// **A basin gets the same control a tree gets, and it is if anything the stronger case.** This
    /// screen's H1 is a street address and its whole subject is a place with nothing standing on it
    /// — "where is it" is the only question a reader can have about a vacant planting site, and
    /// until now the answer was an address and a callout. The map draws it with C19's own basin pin
    /// (RULINGS R7), so nothing here has to say a word about what kind of record it is.
    let locateSet: PinSet

    // MARK: - Derivation

    init(profile: TreeProfile, nearest: NearbyTree? = nil) {
        let tree = profile.tree

        self.title = SiteCopy.title(profile: profile)
        self.subtitle = SiteCopy.subtitle(
            title: SiteCopy.title(profile: profile),
            source: tree.source,
            inventory: profile.inventorySource
        )

        self.statementLeadIn = SiteCopy.statementLeadIn
        self.statementBody = SiteCopy.statementBody

        self.stats = Self.stats(profile: profile)
        self.provenanceNote = Self.provenanceNote(profile: profile)
        self.neighbor = nearest.map(Neighbor.init(nearby:))
        self.footnote = SiteCopy.footnote
        // Named with this screen's own H1 — the address — because that is the only thing that
        // identifies a site, and the map's title should be what the reader just read.
        self.locateSet = PinSet.locate(profile, name: SiteCopy.title(profile: profile))
    }

    // MARK: - The stat grid

    /// Three cards at most, every one of them the city's own.
    ///
    /// No measurement slot and no `Planted` card: the first is the invitation to write that a site
    /// cannot take (ERRATA E95), and the second is a claim about a tree. A card whose fact the
    /// record does not carry is absent rather than blank, exactly as on 03 and 14.
    private static func stats(profile: TreeProfile) -> [Stat] {
        let tree = profile.tree
        var stats: [Stat] = []

        // The publisher's own string verbatim — an open vocabulary kept as free text (BUILD-PLAN
        // §7), so `Sidewalk: Curb side : Cutout` is printed as the city wrote it. This is the one
        // fact on the screen that is *about* a site rather than about the absence of a tree, which
        // is why it leads.
        //
        // Through the same `siteTypeText` screens 03 and 14 use, which is the point of it being a
        // function rather than a condition written twice: this screen is not hypothetical for the
        // city whose column holds the non-values — 5,393 of San Jose's 11,787 vacant planting sites
        // in the shipped seed read `N/A`, and every one of them drew `Site — N/A` here, on a screen
        // whose whole subject is a hole in the ground with nothing in it.
        if let siteType = tree.siteType.flatMap(CityRecordPresentation.siteTypeText) {
            stats.append(Stat(id: "site", label: SiteCopy.siteLabel, value: siteType))
        }

        // `#13284` — the citable city record (BUILD-PLAN §7), under the same rule 03, 14 and 19 all
        // apply: only a city row has one. The `SF ` prefix went with #137; see
        // `CityRecordCopy.recordNumber`.
        if tree.source == .cityImport, let ref = tree.externalRef, !ref.isEmpty {
            stats.append(
                Stat(id: "cityRecord", label: SiteCopy.cityRecordLabel, value: CityRecordCopy.recordNumber(ref))
            )
        }

        if let neighborhood = profile.neighborhoodName, !neighborhood.isEmpty {
            stats.append(
                Stat(id: "neighborhood", label: SiteCopy.neighborhoodLabel, value: neighborhood)
            )
        }

        return stats
    }

    /// The line under the grid, or nil.
    ///
    /// Gated on `tree.source == .cityImport` rather than on the profile carrying an inventory,
    /// which is the same lock the tree page applies from the other side: a community-added record is
    /// nobody's inventory row, and crediting one for it would be inventing a provenance rather than
    /// reporting one. `LocalAPI` already withholds the source for such a record; this is the second
    /// gate, so a future writer that forgets cannot put an inventory's name on a stranger's basin.
    private static func provenanceNote(profile: TreeProfile) -> String? {
        guard profile.tree.source == .cityImport else { return nil }
        guard let source = profile.inventorySource, let snapshot = source.snapshotDate else { return nil }
        return CityRecordCopy.provenanceNote(
            source: source.name,
            snapshot: TreeProfilePresentation.snapshotDay.string(from: snapshot)
        )
    }
}

// MARK: - The nearest standing tree

extension SitePresentation.Neighbor {
    init(nearby: NearbyTree) {
        self.init(
            id: nearby.id,
            title: SiteCopy.neighborTitle(nearby),
            detail: SiteCopy.neighborDetail(meters: nearby.distanceM)
        )
    }
}

// MARK: - Copy

/// Every string on the screen. **All of it is authored** — SCREENS.md draws no vacant site — so it
/// is kept in one enum where a designer can read the whole screen's language at once and replace it
/// without touching a layout. See ERRATA E107 for what each sentence is allowed to claim.
enum SiteCopy {

    /// C1's title. 14 titles its header with the generic noun for the record — `Tree` — and this is
    /// the same word with the noun corrected.
    static let headerTitle = "Site"

    /// The H1.
    ///
    /// The address and nothing else. The profile's precedence — a given name, then the species
    /// common name, then the street — collapses to its last rung here, because a site has no
    /// species to be named after and D15's naming is a thing people do to trees. A site the city
    /// listed without an address falls back to the noun.
    static func title(profile: TreeProfile) -> String {
        if let address = profile.tree.address, !address.isEmpty { return address }
        return fallbackTitle
    }

    static let fallbackTitle = "Planting site"

    /// `Vacant planting site · DataSF Street Tree List`.
    ///
    /// Same rule as 03 and 14: name the record with every fact the H1 has not already used, then
    /// state where it came from. Provenance is required, not optional (BUILD-PLAN §5: no UI-only
    /// provenance), so this line is never empty even where the H1 already said everything else.
    static func subtitle(title: String, source: TreeSource, inventory: InventorySource?) -> String {
        var parts: [String] = []
        if title != fallbackTitle { parts.append(kind) }
        parts.append(provenance(source, inventory: inventory))
        return parts.joined(separator: " · ")
    }

    static let kind = "Vacant planting site"

    /// Where the record came from, from the row's own inventory.
    ///
    /// **It read `SF city inventory` and 11,787 of the seed's vacant sites are San Jose's** — this
    /// screen carried the identical defect #137 found on the tree profile, on the identical line,
    /// while `provenanceNote` twenty points below already named San Jose correctly. One derivation
    /// now feeds both (`CityRecordCopy.recordSource`), so the two lines cannot drift apart again.
    static func provenance(_ source: TreeSource, inventory: InventorySource?) -> String {
        CityRecordCopy.recordSource(source, inventory: inventory)
    }

    // MARK: The statement

    /// The C14 dashed callout — the design's own vocabulary for absence, which is what 14's empty
    /// well, C15 and 06's disclosure are all drawn in.
    static let statementLeadIn = "No tree at this site."

    /// Verbatim, leading space and un-spaced em dash included (ARCHITECTURE §5.7).
    ///
    /// The second sentence is the one that has to be exactly right. It says what Cypress does and
    /// what it does not, and it stops there: no authority has been notified, because nothing has
    /// been reported, and no tree is coming, because this app cannot plant one (ARCHITECTURE §5.4).
    static let statementBody = " The city's inventory lists a planting basin here and nothing growing in it. Cypress keeps the record of what is planted—it does not plant."

    // MARK: The stat grid

    static let siteLabel = "Site"
    static let cityRecordLabel = "City record"
    static let neighborhoodLabel = "Neighborhood"

    // MARK: The nearest tree

    /// The display name of a tree from the nearby list.
    ///
    /// The species common name is the fallback display everywhere (D15); a city row the species map
    /// could not resolve has neither name, and says so rather than borrowing one.
    static func neighborTitle(_ nearby: NearbyTree) -> String {
        if let common = nearby.speciesCommonName, !common.isEmpty { return common }
        if let latin = nearby.speciesScientificName, !latin.isEmpty { return latin }
        if let address = nearby.tree.address, !address.isEmpty { return address }
        return unidentified
    }

    /// The same word screen 01's card uses for a tree with no resolved species.
    static let unidentified = "Unidentified"

    /// `24 m away · the nearest tree to this site`.
    ///
    /// `nearest` is a claim, and it holds: `TreeQueries.nearest` returns rows in ascending distance,
    /// so a standing tree its `LIMIT` dropped is farther than every row it kept. The separator is
    /// the app's spaced middle dot; the no-spaces rule is about em dashes (ARCHITECTURE §5.7).
    static func neighborDetail(meters: Double) -> String {
        "\(Int(meters.rounded())) m away · the nearest tree to this site"
    }

    // MARK: The footnote

    /// Where 14 puts `This is the almanac's "walk the nine" list, one tree at a time.`
    ///
    /// It says what a site *is* rather than what anybody should do about it. E11 reads a vacant site
    /// as the coverage gap D1 points at, and this sentence is as far as that reading can be taken
    /// without claiming a feature: the almanac excludes vacant sites today (ERRATA E107), so nothing
    /// here says it counts them.
    static let footnote = "A planting site is a gap in the canopy, not a tree with a page missing. It stays on the map because it is the city's own record of where a tree could stand."

    // MARK: - The map card (screen 01)

    /// What screen 01's bottom card calls a site.
    ///
    /// It used to read `Unidentified`, which is what `MapCardSubject` calls a tree whose species
    /// nobody resolved — a sentence about a tree, on a pin with no tree behind it.
    static let cardTitle = "Planting site"

    /// The first clause of the card's meta line, ahead of the distance. Every other clause the card
    /// can draw — a species, a last visit — is a fact about a tree and is empty here by construction.
    static let cardMeta = "no tree at this site"

    /// The pin's VoiceOver label. C19 has no pin for a site, so 12,518 pins announced themselves as
    /// `Removed tree, memorial`; the drawn pin is still the gray one (ERRATA E107) and this is the
    /// half of the distinction that could be made without inventing a component.
    static let pinAccessibilityLabel = "Planting site, no tree"

    /// The card's hint, in place of screen 01's `Opens this tree's profile`.
    static let cardAccessibilityHint = "Opens this planting site"

    // MARK: - The states this screen does not draw

    /// A record this screen was opened for that has a tree standing on it.
    ///
    /// Reachable, and the mirror of `MemorialCopy.notAMemorial`: a moderator can move a status
    /// (DECISIONS §3.7), the weekly diff can, and a link is followed later than it was made. It
    /// states the fact and offers nothing rather than silently redirecting to screen 03, which would
    /// be this feature constructing another feature's view (ARCHITECTURE §3).
    static let notASite = "There is a tree at this site."

    /// The same two failure sentences 03 and 19 use, kept identical on purpose.
    static let noRecord = "No record for this site."
    static let couldNotLoad = "This site could not be loaded."
    static let tryAgain = "Try again"
}

// MARK: - Screen metrics

/// The margins this screen borrows from SCREENS.md 14, which is the screen it sits beside.
enum SiteMetrics {
    /// 14: `padding:14px 18px 0` on the identity block.
    static let blockGap: CGFloat = 14
    /// 14 §4: `margin:12px 16px 0` between the blocks below it.
    static let calloutTop: CGFloat = 12
    /// 14 §3: `margin-top:2px` on the italic line.
    static let latinTop: CGFloat = 2
    /// 14 §7: `padding:14px 24px 36px`.
    static let footnoteTop: CGFloat = 14
    static let footnotePaddingH: CGFloat = 24
    /// Not a spec value — the retry control on the failure state, matched to 03's and 19's.
    static let retryButtonWidth: CGFloat = 200
}
