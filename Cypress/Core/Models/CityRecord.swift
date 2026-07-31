import Foundation

/// What San Francisco has on file about a tree, carried verbatim from DataSF `tkzw-k3nq`.
///
/// Six columns on `seed.trees`, added so that a tree page can show the city's own record rather than
/// only Cypress's reading of it. Every field is the city's string exactly as the city wrote it —
/// nothing here is normalised, corrected, parsed or ranked. Blank in the export becomes `nil`, so
/// "the city recorded nothing" and "the city recorded an empty string" are the same absence rather
/// than two states a screen has to tell apart.
///
/// **Only a city row has one.** A community-added tree is not in the city's inventory by definition,
/// so `Tree.cityRecord` is `nil` for `source == .community` and there is no column behind it in
/// `main.community_trees`.
///
/// **There is no pruning here, and there is none to find.** The project owner asked for "next pruning
/// / last pruning" (task #68). DataSF `tkzw-k3nq` has eighteen real columns and not one of them
/// records a pruning event, a pruning date or a pruning schedule — verified against the dataset's own
/// published column metadata, not only against a downloaded copy. The nearest thing in the data is
/// two `legalStatus` values, `"Prune Opt Out"` (196 rows) and `"Street Tree Maintenance Opt Out"` (58
/// rows), which say that somebody withdrew a site from the city's maintenance programme. That is a
/// standing policy about a tree, not a date on which anything happened to it, and it must never be
/// rendered as one. Pruning history would have to come from a different city system; this dataset
/// cannot answer the question at any grain.
/// `Codable` because `Tree` is (`CoreEntity`), not because anything syncs this: the city's record is
/// the city's, and Cypress never sends it back.
public struct CityRecord: Codable, Hashable, Sendable {

    /// DataSF `qLegalStatus` — the tree's standing in city law, which is mostly a statement about
    /// *jurisdiction*: whether the site is in the public right-of-way, on private land, or neither.
    /// 99.97% populated across the seed's 195,309 rows, over 12 distinct values.
    ///
    /// This is the column `LandContext.inferred(from:)` leads on. See `LandContext` for why it leads
    /// on this one and not on `caretaker`, which is the mistake that column invites.
    public var legalStatus: String?

    /// DataSF `qCaretaker` — "Agency or person that is primary caregiver to tree", in the city's own
    /// words. 100% populated, 27 distinct values, reading like a municipal org chart.
    ///
    /// **This is who waters the tree, not whose land it stands on**, and the difference is 84% of the
    /// inventory. See `LandContext`.
    public var caretaker: String?

    /// DataSF `qCareAssistant` — the secondary caregiver. 25,199 rows (12.90%); 22,879 of those say
    /// `"FUF"`, Friends of the Urban Forest, who planted them.
    public var careAssistant: String?

    /// DataSF `PlantType` — the city's own word for what the record is. 100% populated and almost
    /// constant: `"Tree"` on 194,988 rows, `"Landscaping"` on 318, and `"tree"` on 3.
    ///
    /// Carried despite being near-constant, because the 318 rows are the only place the inventory
    /// says a record on the tree map is not a tree. The three lower-case rows are the city's typo and
    /// are not corrected here; compare case-insensitively.
    public var plantType: String?

    /// DataSF `PlotSize` — the planting basin, as free text. 146,951 rows (75.24%) over 588 distinct
    /// values.
    ///
    /// **Never parse this into a number.** The values are three incompatible notations plus a bare
    /// integer of unstated unit: `"Width 3ft"` (36,866), `"3x3"` (31,760), `"3X3"` (12,135), `"60"`
    /// (782), `"10x10"` (367). DataSF's published description of the field reads "date tree was
    /// planted", copied from `PlantDate` — the field is under-curated at the source. Deriving an area
    /// from it would be D7's forbidden move, dressing an estimate as a measurement. Show the city's
    /// string or show nothing.
    public var plotSize: String?

    /// DataSF `PermitNotes` — "Tree permit number reference". 52,580 rows (26.92%), of which 52,114
    /// read `"Permit Number 45761"` and 466 are a free sentence the city typed instead, such as
    /// `"Property owner watered the tree to establishment"`. Free text, not a parseable reference.
    public var permitNotes: String?

    public init(
        legalStatus: String? = nil,
        caretaker: String? = nil,
        careAssistant: String? = nil,
        plantType: String? = nil,
        plotSize: String? = nil,
        permitNotes: String? = nil
    ) {
        self.legalStatus = legalStatus
        self.caretaker = caretaker
        self.careAssistant = careAssistant
        self.plantType = plantType
        self.plotSize = plotSize
        self.permitNotes = permitNotes
    }

    /// True when the city recorded none of the six.
    ///
    /// A screen showing "what the city has on file" needs this to decide whether to draw the panel at
    /// all: a header over six blank rows claims a record exists and is empty, which is a different
    /// and worse statement than not drawing the panel.
    public var isEmpty: Bool {
        legalStatus == nil && caretaker == nil && careAssistant == nil
            && plantType == nil && plotSize == nil && permitNotes == nil
    }
}

// MARK: - Land context

/// Where a tree stands: the ground under it, not who tends it.
///
/// The project owner asked for three (task #69): *"whether it stands on a street, in a city park, or
/// on private property"*. This enum has four, and the fourth is not a hedge — it is the 956 rows the
/// three do not fit. San Francisco's inventory holds trees whose caretaker is SFUSD, the Port, the
/// PUC, the Housing Authority, the Fire Department and the Arts Commission: public land that is
/// neither a street nor a park. Pinning a CHECK to three values would have made those rows
/// unstorable and bought the migration ERRATA E136 is about — a constraint that quietly forbids a
/// state the data already contains. A vocabulary that permits a value no screen offers costs nothing;
/// one that forbids a value the source produces costs a migration. #69's picker is free to offer
/// three.
///
/// The raw values are the stored vocabulary of `community_trees.land_context` and are frozen by
/// AppSchema v11's CHECK.
public enum LandContext: String, Codable, Sendable, Hashable, CaseIterable {

    /// The public right-of-way — sidewalk, median, unaccepted street. 182,320 seed rows (93.35%).
    case street = "street"

    /// Land the Recreation and Parks Department holds. 177 seed rows (0.09%), and that number is the
    /// finding rather than a defect: `tkzw-k3nq` is the *Street* Tree List and is not a park
    /// inventory. See `inferred(from:)`.
    case cityPark = "city_park"

    /// Private land. 11,856 seed rows (6.07%).
    ///
    /// `privateProperty` rather than `private`, because `private` is a Swift keyword and a case
    /// spelled `` `private` `` would need backticks at every use site.
    case privateProperty = "private_property"

    /// Public land that is neither a street nor a park — a school yard, a Port parcel, a PUC
    /// right-of-way, a housing project's courtyard. 956 seed rows (0.49%).
    case otherPublic = "other_public"
}

extension LandContext {

    /// Whether the ground under the tree is publicly held.
    ///
    /// One bit, and it is the only thing screen 06 needs from this enum. 311 is San Francisco's
    /// single front door for city-owned anything — a sidewalk tree, a Rec/Park tree, an SFUSD yard
    /// tree all reach a city crew through it, by different queues the caller never sees. A tree on
    /// private land reaches nobody through it, because the city does not maintain it.
    ///
    /// So the three public values answer the same way and `privateProperty` is the one that differs,
    /// which is why this is a `Bool` rather than a four-way switch somewhere in `Features`: the
    /// distinction that matters to a reporting screen is not "which of four" but "is this the city's
    /// to fix", and a screen that re-derived it would be free to disagree with this file.
    ///
    /// It says nothing about 311, and deliberately: `Core` is pure Foundation and knows about ground,
    /// not about municipal telephone numbers. `ReportPresentation.hazardHandoff` is where this
    /// becomes a statement about who takes the report.
    public var isPublicLand: Bool {
        switch self {
        case .street, .cityPark, .otherPublic: return true
        case .privateProperty: return false
        }
    }

    /// Reads the city's record for where the tree stands, or `nil` when the record does not say.
    ///
    /// **`caretaker` is the trap this function exists to avoid.** DataSF describes `qCaretaker` as
    /// "Agency or person that is primary caregiver to tree. Owner of Tree", and 163,955 of the seed's
    /// 195,309 rows say `"Private"` — 84%. Read as a location, that makes San Francisco a city whose
    /// street trees are overwhelmingly on private property, which is false. 112,955 of those same
    /// rows carry `legalStatus == "DPW Maintained"`: they stand in the sidewalk, in the public
    /// right-of-way, and the private party named is the adjacent owner who waters them. A mapping
    /// that led on `caretaker` would mislabel roughly 150,000 street trees as private property, and
    /// it would do it while looking entirely reasonable in a code review.
    ///
    /// **So jurisdiction leads and care fills in.** `legalStatus` decides wherever it names a
    /// jurisdiction. Where it names only a regulatory designation (`"Significant Tree"`, `"Landmark
    /// tree"` — both of which SF's Public Works Code can attach to a tree on either side of the
    /// property line) or says nothing at all (`"Undocumented"`, blank), there is no jurisdiction on
    /// file and `caretaker` is the only remaining signal, so it answers for those 12,286 rows and
    /// only for those.
    ///
    /// **Measured over all 195,309 seed rows:**
    ///
    /// | bucket             | rows    | share  |
    /// |--------------------|---------|--------|
    /// | `.street`          | 182,320 | 93.35% |
    /// | `.privateProperty` |  11,856 |  6.07% |
    /// | `.otherPublic`     |     956 |  0.49% |
    /// | `.cityPark`        |     177 |  0.09% |
    /// | `nil`              |       0 |  0.00% |
    ///
    /// Every row resolves. `nil` is reachable only from a record with no `legalStatus` *and* no
    /// `caretaker`, which the current export does not contain — but the export is refreshed weekly
    /// and the return type says so rather than inventing a bucket for a row that declined to say.
    ///
    /// **`.cityPark` is 177 rows and that is the honest answer, not a bug.** This dataset is the
    /// Street Tree List. 720 rows name `"Rec/Park"` as caretaker, but 543 of them also carry a DPW
    /// jurisdiction (`"DPW Maintained"` or `"Permitted Site"`), meaning a street tree along a park's
    /// edge that Rec/Park waters — and calling that "in a city park" is the wrong error to make,
    /// because it is the one a person standing on the sidewalk can see is wrong. San Francisco's
    /// actual park trees are largely not in this dataset at all. For #69 that is a feature: a
    /// contributor adding a tree in Golden Gate Park is adding something the city inventory does not
    /// have.
    /// ── The rule is San Francisco's, and it now says so (#129, ERRATA E176) ──────────────────
    ///
    /// Every string matched below is a **DataSF `qLegalStatus` / `qCaretaker` value**. Read against
    /// another city's inventory the function does not fail, which is the problem: it answers
    /// confidently and wrongly. Measured against the 52,788 San Jose rows the v14 seed carries, whose
    /// `legal_status` is San Jose's `OWNEDBY`:
    ///
    /// | San Jose value           | rows   | what this rule would return | why it is wrong |
    /// |--------------------------|-------:|-----------------------------|-----------------|
    /// | `Private`                | 48,036 | `.privateProperty`          | San Jose's model is that the *adjacent owner* maintains the street tree. The tree is in the right-of-way; `OWNEDBY` names who is responsible, not whose land it is. This is `caretaker`'s trap, one column to the left. |
    /// | `San Jose`               |  2,593 | `.otherPublic`              | falls through to `caretaker`, which reads `General Fund` — a budget line, not an agency, and certainly not a location |
    /// | *(blank)*                |  2,158 | `.otherPublic`              | same fall-through, same budget line |
    ///
    /// So all 52,788 rows of a layer literally called *Street Trees* would resolve, and **not one of
    /// them to `.street`.** That is worse than nil: nil draws nothing, and this draws a sentence that
    /// is false on a screen that presents it as the city's own record.
    ///
    /// The fix is not a San Jose branch — inventing one would be a design decision made in passing,
    /// and San Jose's `GROWSPACE` (`Park Strip`, `Well/Pit`, `Median`) is a better signal than
    /// `OWNEDBY` anyway. The fix is that a rule written over one publisher's vocabulary does not run
    /// against another's. `idSpace` nil means "not stated", which is how every seed built before the
    /// v14 pass reads and is correct for those files: they hold San Francisco and nothing else.
    /// RULINGS R24.
    public static func inferred(from record: CityRecord, idSpace: String? = nil) -> LandContext? {
        if let idSpace, idSpace != "sf" { return nil }
        switch record.legalStatus {
        // Jurisdiction: the public right-of-way. "Permitted Site" is a planting DPW issued a permit
        // for, which is a sidewalk site; the two Planning Code sections and Public Works Code
        // 806(d) are the ordinances that require and govern street trees; and only a street tree can
        // opt out of the city's street-tree maintenance or pruning programme, so both opt-outs are
        // themselves evidence of a street site.
        case "DPW Maintained",
             "Permitted Site",
             "Section 806 (d)",
             "Planning Code 138.1 required",
             "Section 143",
             "Prune Opt Out",
             "Street Tree Maintenance Opt Out":
            return .street

        // Jurisdiction: private land, said outright.
        case "Private", "Property Tree":
            return .privateProperty

        // "Significant Tree" and "Landmark tree" are protective designations rather than locations —
        // SF's Public Works Code can attach either to a tree on private property or to one in the
        // right-of-way — and "Undocumented" and a blank say nothing by construction. These are the
        // 12,286 rows where the caretaker is all that is left to go on.
        default:
            switch record.caretaker {
            case "Rec/Park": return .cityPark
            case "Private": return .privateProperty
            case .some(let agency) where !agency.isEmpty: return .otherPublic
            default: return nil
            }
        }
    }
}

/// A tree's land context together with how Cypress knows it.
///
/// The two ways of knowing are genuinely different claims and this type refuses to let a reader take
/// one for the other. A contributor who stood in Golden Gate Park and tapped "city park" *observed*
/// it. A city row's context is Cypress's *reading* of two strings in a municipal export, and that
/// reading is a rule in this file which can be wrong about any individual tree. Returning them as one
/// bare `LandContext` would have made the difference something a screen has to remember to ask about
/// separately, which is the shape of fact that eventually stops being asked about — the reason
/// BUILD-PLAN §5 requires every provenance fact to be carried rather than inferred at the point of
/// display.
public struct KnownLandContext: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable, Hashable, CaseIterable {
        /// A contributor said so when they added the tree (`community_trees.land_context`).
        case statedByContributor = "stated_by_contributor"
        /// Derived from the city's record by `LandContext.inferred(from:)`.
        case inferredFromCityRecord = "inferred_from_city_record"
    }

    public let context: LandContext
    public let source: Source

    public init(context: LandContext, source: Source) {
        self.context = context
        self.source = source
    }
}
