//
//  TreeProfilePresentation.swift
//  Cypress — Features/TreeProfile
//
//  Everything screens 03 (tree profile) and 14 (cold-start profile) render, derived from one
//  `TreeProfile` payload. Pure value code: no SwiftUI state, no I/O, no formatting decisions left
//  to the view.
//
//  ── The two screens are one screen ────────────────────────────────────────────────────────
//  SCREENS.md 14 lists its own deltas — "no hero, no foliage strip, no regulars row, no activity
//  feed, no quad-action row, badge is `PLANTED <year>`" — as "differences from 03 to encode as a
//  **variant**". So `isCold` is a property of the payload, not a second screen: a tree with no
//  photos and no visits renders the cold variant. Per D8 that is every tree in the shipped seed,
//  because the city inventory carries no community content at all.
//
//  ── Rules enforced here rather than in the view ───────────────────────────────────────────
//  - **D7**: the city's DBH is a *bucket*, never a point measurement. It becomes
//    `StatCard.Value.cityRecord`, which carries the `city record` badge and is not a `Quantity`,
//    so nothing downstream can render it as something a person taped.
//  - **D1**: no counts of user actions, no ranks, no streaks. See `caretakerHeadline`.
//  - **A8**: the caretakers line renders only at ≥3 distinct caretakers.
//  - **A3**: "best photo" is the most recent `full_tree` photo, resolution breaking ties. A3's word
//    "approved" gates the *public* surfaces; this screen is the contributor's own device, and the
//    two predicates are named apart in `Photo` so neither can be reached for the other (ERRATA E37).
//  - **A5**: the season strip is the most recent photo per calendar month across all years.
//  - **Pages are not totals**: everything that counts or spans a series reads `Series.totalCount`
//    and renders nothing when the read was a page (ERRATA E38).
//  - **BUILD-PLAN §15**: no invented botany. Absent species content produces an absent section.
//

import Foundation

struct TreeProfilePresentation {

    /// One row of the activity feed (C9).
    struct ActivityItem: Identifiable {
        enum Kind { case visit, care }

        let id: UUID
        let kind: Kind
        /// The bold lead-in: `Visit` / `Care`.
        let label: String
        /// Everything after it, verbatim including its separator.
        let detail: String
        /// Trailing mono timestamp, e.g. `Oct 12`.
        let timestamp: String
    }

    /// Where a stat card leads, when it leads anywhere.
    ///
    /// One control, two destinations, decided by whether the record carries the reading:
    ///
    /// - **A reading exists** → screen 11, the growth history. Specified: SCREENS.md 03's affordance
    ///   list says `DBH/Height cards → 11`, and 11's own caption says it "lives under Details on the
    ///   tree profile". This was never reachable, because nothing in the app could write a
    ///   measurement (ERRATA E63) — not because it was undesigned.
    /// - **No reading exists** → screen 16, the measure sheet. **Invented under the project owner's
    ///   one-time authorization** to give these six screens an entrance; see ERRATA (E98). An empty
    ///   measurement slot standing open for the number that belongs in it is the smallest thing that
    ///   makes 16 reachable, and E74 already named "add a reading" as the least-invented candidate —
    ///   this puts that control on the profile, where every other field action in the app starts,
    ///   rather than on 11, which is a history surface a contributor with a tape has no reason to
    ///   have opened.
    ///
    /// A designer may overrule either arm without archaeology: both are decided here, and the view
    /// only asks where a card goes.
    enum StatDestination: Hashable {
        case growthHistory
        /// Screen 16, **on the measurement this card is a card for**.
        ///
        /// The kind is the card's own, not a default. An empty slot is drawn inside a box labelled
        /// `Height` or `DBH` and its entire meaning is that *that* measurement is missing, so the
        /// form it opens is that measurement's form. It carried no kind until RULINGS R15, and
        /// every entrance therefore opened on `MeasureDraft`'s default of DBH — including the
        /// Height card, whose label then contradicted the screen it led to.
        case measure(MeasurementKind)

        /// Whether this is a door to screen 16 at all, without asking which measurement.
        ///
        /// Named because `== .measure` stopped compiling when the case gained its payload, and the
        /// four places that asked it — three of them checking that a read-only record is offered no
        /// write (E95) — are asking about the *door*, not the kind. Rewriting them as `if case`
        /// would have buried an E95 assertion inside a pattern match.
        var isMeasure: Bool {
            if case .measure = self { return true }
            return false
        }
    }

    /// One card of the stat grid (C11).
    struct StatItem: Identifiable {
        let id: String
        let label: String
        let value: StatCard.Value
        /// Where tapping the card goes. `nil` for the cards that are facts and not doors — the
        /// city's DBH bucket among them, deliberately (D7, ERRATA E63).
        let destination: StatDestination?

        init(id: String, label: String, value: StatCard.Value, destination: StatDestination? = nil) {
            self.id = id
            self.label = label
            self.value = value
            self.destination = destination
        }
    }

    /// The regulars row's data (A8). `count` is a count of *people who know the tree*, never of
    /// anybody's contributions (D1).
    struct Caretakers {
        let count: Int
        /// Initials for `AvatarStack`. Empty until the API carries caretaker identities — see
        /// `TreeProfileModel.caretakerInitials`.
        let initials: [String]
    }

    let profile: TreeProfile
    private let now: Date
    private let calendar: Calendar
    private let injectedCaretakerInitials: [String]

    init(
        profile: TreeProfile,
        now: Date = Date(),
        calendar: Calendar = .current,
        caretakerInitials: [String] = []
    ) {
        self.profile = profile
        self.now = now
        self.calendar = calendar
        self.injectedCaretakerInitials = caretakerInitials
    }

    private var tree: Tree { profile.tree }
    private var species: Species? { profile.species }

    // MARK: - Which variant

    /// Screen 14 rather than screen 03: nobody has photographed or visited this tree.
    ///
    /// Photos *and* visits, not photos alone: a visit whose photo is still in the outbox has
    /// already made the tree somebody's, and the cold-start copy ("be the first…") would be a lie.
    var isCold: Bool { visiblePhotos.items.isEmpty && visibleVisits.items.isEmpty }

    // `isVacantSite` used to live here, unread by anything, describing screen 14 rendering a site
    // "with the two elements that would be false removed". That state no longer exists: a vacant
    // site has its own screen (E107) and cannot become this presentation at all (E113,
    // `TreeProfileDestination`). A predicate that can only be false, left standing next to a
    // comment describing a screen the app does not draw, is the next reader's wrong turn.

    /// Whether this record can take a new contribution at all.
    ///
    /// Two statuses cannot, for opposite reasons: a vacant site has no tree yet, and a memorial had
    /// one and no longer does. Both were previously gated separately — the site here, the memorial
    /// not at all — which left a removed tree drawing a `REMOVED` badge beside a live
    /// "say hello with a photo" button. A read-only record offering a write is exactly what screen
    /// 19 exists to prevent, and the profile is reachable with a removed tree from the almanac's
    /// elder row and the visit flow, not only from the map. Gating on one property means a third
    /// such status cannot be added without answering the question. See ERRATA (E95).
    var acceptsContributions: Bool { tree.status.acceptsNewContributions }

    /// The sentence a confirmed-dead tree's profile says about itself, or nil (ERRATA E170).
    ///
    /// ── Why a profile needed a sentence and not just a badge ───────────────────────────────
    /// `dead_reported` is the one status this screen renders that a reader cannot infer from anything
    /// else on it. A memorial announces itself — screen 19, no CTA, no check-in, a `REMOVED` badge. A
    /// confirmed-dead tree renders as an ordinary profile with every button live, because
    /// `TreeStatus.deadReported.acceptsNewContributions` is `true` and that is deliberate: a dead
    /// street tree is a hazard, and reporting it is the single most useful thing a passer-by can do.
    /// So the screen was silently identical to a live tree nobody had checked in on.
    ///
    /// The `DEAD` badge alone would not do it. A badge is a word, and the word this one needs is
    /// three facts: somebody reported it, a reviewer agreed, and the buttons below are still meant
    /// for you. The last of those is why the sentence ends where it does.
    ///
    /// **Not "the city has been told."** Nothing tells the city — see `CommunityNote`'s header and
    /// DECISIONS §3.3 — and this is the surface where that temptation is strongest, because "dead"
    /// is the status a reader most wants to believe somebody official is acting on.
    var deadNotice: String? {
        guard tree.status == .deadReported else { return nil }
        return Self.deadNoticeText
    }

    /// **NOT SPECIFIED** — SCREENS.md draws no confirmed-dead profile.
    static let deadNoticeText = """
        Reported dead, and a community reviewer confirmed it. It is still standing, so anything you \
        see here is still worth reporting.
        """

    /// The bolded front of `deadNotice`, in `recognitionTip`'s shape — the one Callout lead-in this
    /// screen already draws.
    static let deadNoticeLeadIn = "Confirmed dead:"

    // MARK: - Quad action row (C8)

    /// Which of C8's four cells this record may offer.
    ///
    /// All four on a tree that can take a contribution, which is every tree screen 03 is drawn for.
    /// On a record that cannot — a memorial, since a vacant site no longer reaches this screen at
    /// all (E113) — two of them go, and the two that go are the two that write:
    ///
    /// - **`Care`** logs a care event: somebody watered, mulched or staked a tree that is not
    ///   there. It is a contribution in the plain sense and `acceptsNewContributions` already
    ///   refuses it everywhere else on this screen (the visit CTA, the check-in button, the empty
    ///   measurement slot). The quad row was the one control left offering one.
    /// - **`Report`** opens screen 06, whose subject is a `HazardCategory` — a hanging limb, an
    ///   uprooting, a vehicle strike, a blocked sightline. All four are statements about a standing
    ///   tree; E107 makes the same observation about a site from the other direction.
    ///
    /// **`Favorite` and `Share` stay, and the first of them is the point.** A favourite observes
    /// nothing — it writes to the person's grove, not to the tree's record — and E89's deciding
    /// argument is that gating it makes the toggle one-way for anyone whose favourite tree is later
    /// removed. R2 restates it: the gate that refuses the heart also refuses taking it off. Share
    /// is a read of a record that still exists. `SiteView` reaches the same answer from the other
    /// side, in its own words: "no quad action row, because three of its four cells act on a tree".
    ///
    /// One property, so a designer who disagrees changes one line. See ERRATA (E112).
    var quadActions: [QuadActionRow.Action] {
        acceptsContributions ? QuadActionRow.Action.allCases : [.favorite, .share]
    }

    /// Whether C8 is drawn at all — and since ERRATA E127 the answer no longer depends on the
    /// variant.
    ///
    /// **This overrides SCREENS.md 14, on the project owner's ruling.** 14 lists "no quad-action row"
    /// among its deltas from 03, and the build honoured it literally: the row was inside the view's
    /// `if !isCold`. Per D8 every tree in the shipped city inventory renders the cold variant on
    /// launch day, so what that delta actually shipped was a tree nobody had touched offering *no
    /// action of any kind* — no way to report a hanging limb, no way to log the watering somebody
    /// had just done, no way to bookmark it. The owner's words: "A tree no one has touched should at
    /// least offer a REPORT and CARE."
    ///
    /// All four cells, not the two that were ruled on, because the other two need nothing from the
    /// tree either and withholding them would need its own argument:
    ///
    /// - **`Favorite`** is a private bookmark written to the person's grove, not to the tree's
    ///   record. E89 and R2 already refuse to gate it on anything, on the grounds that a gate which
    ///   refuses the heart also refuses taking it off.
    /// - **`Share`** is a read of a record that exists, and its card is *unchanged* by the absence of
    ///   photographs: `SharePresentation` takes `isPubliclyVisible`, nothing in the shipping app can
    ///   set `.approved`, so screen 10 draws its C22 gradient thumbnail for every tree in the app
    ///   today — which is what SCREENS.md 10 §3 specifies anyway. A cold tree's share card and a
    ///   well-photographed tree's share card are the same picture, so there is nothing about a cold
    ///   tree for Share to render badly.
    ///
    /// The two things 14's delta list is still honoured on are the regulars row and the activity
    /// feed, which the view keeps behind `isCold` — and those are the two that would draw *nothing*
    /// on a cold record anyway, because there are no caretakers and no activity to draw.
    ///
    /// `acceptsContributions` still decides which cells (`quadActions`), so a memorial keeps losing
    /// the two that write (E95, E112). This is the row's existence, not its contents.
    var offersQuadActionRow: Bool { !quadActions.isEmpty }

    // MARK: - Identity

    /// The H1. A given name wins (D15); the species common name is the fallback display
    /// everywhere; the street address is what is left for a site the city lists with no species.
    var title: String {
        if let name = profile.activeName, name.isDisplayable { return name.name }
        if let common = species?.commonName, !common.isEmpty { return common }
        if let address = tree.address, !address.isEmpty { return address }
        return TreeProfilePresentation.fallbackTitle
    }

    static let fallbackTitle = "Tree"

    // MARK: - Where it is

    /// The map this screen can send the reader to, as the payload it travels on.
    ///
    /// ── **NOT SPECIFIED** (ERRATA E144) ──────────────────────────────────────────────────────
    /// SCREENS.md 03 and 14 draw no map affordance, and neither does any other screen that names a
    /// record. The project owner reported the hole on the almanac — *"clicking just takes to tree
    /// page but I have no idea where tree is"* — and it is worth being precise about where the hole
    /// actually is, because the report names the entrance rather than the dead end.
    ///
    /// **Every surface in the app that names a record hands the reader to this screen.** The
    /// almanac's season rows, My Grove, the journal, the species screen's nearby list, the map's own
    /// card and search: all six push `.treeProfile`, `.site` or `.memorial`, and not one of those
    /// three screens said where the record was. So the almanac is not a special case, it is the one
    /// case somebody happened to be looking at, and an affordance built on the almanac's rows would
    /// have to be built five more times — five more places to word it differently, and five more
    /// destinations to drift apart.
    ///
    /// It is built here instead, on the junction, and the destination is the map E129 already built
    /// for the almanac's two counted rows (`PinSet`). One control, one screen, and every list in the
    /// app reaches it in the same two taps.
    ///
    /// **A memorial and a vacant planting site both get it, unchanged.** They are reachable from the
    /// same lists, they are places in exactly the way a living tree is a place, and C19 already draws
    /// each of them with its own pin (RULINGS R7, ERRATA E107) — so the map says what kind of record
    /// stands there without a word of this screen's copy changing. "Where is it" is a question about
    /// a coordinate, and a removed tree's coordinate is the last thing anybody knows about it.
    /// Built from the payload this screen is already holding, so there is no read to disagree with
    /// what is on the screen, and named with the H1 the reader is looking at rather than a second
    /// derivation of it.
    var locateSet: PinSet { PinSet.locate(profile, name: title) }

    /// The italic serif line under the name, `·`-joined.
    ///
    /// SCREENS.md draws two versions of this line — `Monterey Cypress · Hesperocyparis macrocarpa`
    /// on 03, where the H1 is a given name, and `Lophostemon confertus · SF city inventory` on 14,
    /// where the H1 is already the common name. Both fall out of the same rule: name the tree with
    /// every fact the H1 has not already used, then state where the record came from.
    ///
    /// The provenance element is **required on both** (BUILD-PLAN §5: no UI-only provenance), which
    /// is the one place this line runs longer than the 03 mock.
    var subtitle: String {
        var parts: [String] = []
        if let species {
            if species.commonName != title, !species.commonName.isEmpty {
                parts.append(species.commonName)
            }
            // A name the ingest never read is not a scientific name and is never printed as one;
            // `unreadSpeciesNote` says so in a sentence instead. See
            // `RULINGS R54`.
            if species.scientificName != title, !species.scientificNameIsUnread {
                parts.append(species.scientificName)
            }
        }
        parts.append(provenance)
        // Coarse to fine, and each element narrower than the one before it: where the record came
        // from, then who named the species on it, then how its coordinate was arrived at.
        if let speciesClaimNote { parts.append(speciesClaimNote) }
        if let placementNote { parts.append(placementNote) }
        return parts.joined(separator: " · ")
    }

    /// Where the record came from — **read off this row's inventory, not off a literal**.
    ///
    /// SCREENS.md ships `SF city inventory` against `community-added, unverified`. The second is
    /// unchanged; the first now names the inventory the row is actually from, which is San Jose's on
    /// 52,788 rows of the shipped seed. See `CityRecordCopy.recordSource` for the whole argument and
    /// RULINGS R28 for the mock pin this overruled.
    var provenance: String {
        CityRecordCopy.recordSource(tree.source, inventory: profile.inventorySource)
    }

    /// **The sentence for a tree whose species the city's record never named** — task #185, ruled in
    /// `RULINGS R54`. Seven trees in the shipped seed.
    ///
    /// DataSF publishes species in one column as `Scientific name :: Common name`. On these rows the
    /// scientific half is empty, and the ingest kept the whole raw string as `scientific_name` — so
    /// the subtitle above printed `:: Magnolia` in the slot labelled by position as the Latin name.
    /// `RULINGS R47` took those rows out of the suggestion list on E126's principle, and said in as
    /// many words that the principle cannot be applied here: you cannot omit a tree's own species
    /// from its own page. So the fix is copy, and this is the copy.
    ///
    /// **It quotes the city rather than describing the absence in the abstract.** The common half
    /// *did* parse and is the city's own word — `Magnolia`, `Magnolia Little Gem`, `9662` — and it
    /// is already the H1 through `title`'s species fallback. A sentence that only said "the record
    /// does not say what this tree is" would leave the reader looking at the word `9662` with no
    /// account of where it came from, which is E126's failure with better manners. Naming the
    /// wording is what turns the H1 from an assertion into a quotation.
    ///
    /// **Nothing here guesses at the taxon.** `:: Podocarpus Gracilor` is probably `Podocarpus
    /// gracilor` and this screen does not say so, for the reason R47 gives and DECISIONS constraint
    /// 15 requires: that is a synonymy no source in the pipeline states.
    ///
    /// `nil` for every other tree in the app, including a tree with no species at all — that record
    /// has no wording to quote and no line that went missing, and it renders as it always has.
    var unreadSpeciesNote: String? {
        guard let wording = species?.cityWordingForUnreadName else { return nil }
        return TreeProfileCopy.unreadSpeciesNote(cityWording: wording)
    }

    /// Who said what species this is, when the answer is "a contributor did".
    ///
    /// **NOT SPECIFIED.** SCREENS.md has no community tree carrying a species, because until now the
    /// add flow could not record one: `VisitAddTreeModel.add()` sent no species on principle. It can
    /// now, on the ruling that a species the *contributor* states is a different fact from a species
    /// the *app* guesses, and this line is the second half of that ruling — the half that makes sure
    /// the distinction survives to the screen. It sits on the provenance line for the same reason
    /// `placementNote` does: BUILD-PLAN §5 makes provenance a property of the record, and this is
    /// where `source` and `verification_state` are already read out.
    ///
    /// ── This one arm is stated and the other is not, and that is not the placement rule broken ──
    /// `placementNote` prints **both** of its values, and argues at length that printing only the
    /// unusual one turns a label into a warning. That argument was tested against this line and it
    /// does not carry, because the two cases are not the same shape.
    ///
    /// A coordinate always exists and always came from one of two instruments, so `gps` and
    /// `contributor_placed` are two provenances of one fact, and marking one of them ranks it against
    /// the other. A species does not always exist. The alternative to "species named by a
    /// contributor" is not a second way of arriving at a species — the client has no other way; there
    /// is no organisation confirming botany in this app and no photograph being classified by one —
    /// it is **no species at all**, which prints nothing here because there is nothing to attribute.
    /// A symmetric second arm would have to be a sentence about a species that does not exist.
    ///
    /// The symmetry the placement rule is really about is honoured, one level up and already: a city
    /// row's species reads its inventory's name and a community row's reads `community-added,
    /// unverified`, both on this same line, and neither is the marked case. This element only says
    /// *which part* of a community record the contributor authored — and it is not evaluative, in
    /// exactly `placementNote`'s sense: it names the author, the way `recordSource` names an
    /// inventory without praising it. It does not say "unconfirmed", "guess", or "may be wrong". A
    /// contributor who planted the tree knows it better than any row in the seed does.
    ///
    /// **Community rows with a species only.** A city row's species is the city's and `provenance`
    /// already says so; a community row with no species has nobody to attribute.
    ///
    /// No `verification_state` condition, and that is deliberate rather than overlooked: `provenance`
    /// hardcodes `community-added, unverified` for every community row, so there is no state in which
    /// this element and the one before it could disagree. If a community row ever becomes
    /// org-verified on screen, both sentences change together or neither does.
    var speciesClaimNote: String? {
        guard tree.source == .community, species != nil else { return nil }
        return TreeProfilePresentation.speciesNamedByContributor
    }

    /// "a contributor", not "the contributor". `community_trees` records no author — it has no
    /// `user_id` and no `device_id` — so the record cannot say *which* person, and a line that said
    /// "the contributor" would imply the one who added the tree and quietly be wrong the moment a
    /// second person names the species on somebody else's row.
    static let speciesNamedByContributor = "species named by a contributor"

    /// Whether this screen offers to name the species — the "after" half of the owner's request.
    ///
    /// **NOT SPECIFIED.** SCREENS.md has no such control, because until now there was no writable
    /// species anywhere in the app.
    ///
    /// Three conditions, and each of them is a refusal `LocalAPI.claimSpecies` also enforces, drawn
    /// rather than merely thrown. A control that offered an act the boundary would refuse is the
    /// defect `VisitAddTreeModel.canAdd` exists to avoid on the other screen.
    ///
    /// - **Community rows only.** A city row's species belongs to an inventory in a read-only
    ///   database. `SpeciesClaim` argues why overwriting it is a larger decision than this.
    /// - **Only when there is none.** Correcting a claim needs the `species_assertions` chain, which
    ///   is not writable on device. First claim wins, exactly as `tree_names` does for the given name
    ///   (D15). So this control appears once per tree and then never again.
    /// - **Only where a contribution is welcome.** A memorial and a vacant site refuse every other
    ///   write on this screen (E95); naming the species of a tree that has been removed, or of a site
    ///   that never had one, is the same kind of claim about a thing that is not there.
    var offersSpeciesClaim: Bool {
        tree.source == .community && species == nil && acceptsContributions
    }

    /// What this screen offers about a species that has **already** been claimed — tickets #86 and
    /// #124, the correction half of the same block.
    ///
    /// **NOT SPECIFIED**, for `offersSpeciesClaim`'s reason and one more: SCREENS.md has no control
    /// here because until AppSchema v14 there was no chain for a correction to go into. The ruling
    /// `RULINGS R45` is the mock for what this draws.
    ///
    /// Read straight off the payload rather than re-derived. Which of the three things a viewer may
    /// do turns on whether the claim in force is theirs and whether a report is already open — an
    /// `Attribution` question and a `review_flags` question, neither of which a presentation has any
    /// business answering. `SpeciesCorrectionOffer` carries that argument.
    ///
    /// No `acceptsContributions` gate, unlike the claim above, and the difference is real rather
    /// than an oversight: naming a removed tree's species is a claim about a thing that is not
    /// there, and correcting a misidentification is a claim about the **record**, which stays true
    /// after the tree is gone. A confirmed removal routes this screen to the memorial anyway
    /// (`status.isMemorial`), so the case barely arises; where it does, the honest answer is that
    /// the record can still be put right.
    var speciesCorrection: SpeciesCorrectionOffer { profile.speciesCorrection }

    /// What this screen offers about the **record** rather than about the tree on it — task #125,
    /// the owner's *"a way to flag that a tree that is listed on the map doesn't appear to exist at
    /// all"*.
    ///
    /// **NOT SPECIFIED.** SCREENS.md has no control here; `RULINGS R46` decided the kind and
    /// `RULINGS R50` is the mock for what this draws. Read straight off the payload for
    /// `speciesCorrection`'s reason — the answer needs the viewer's role and an open-flag read, and
    /// a presentation holding either would be holding something it cannot see.
    ///
    /// No `acceptsContributions` gate, and the reason is the sharper version of the species one: a
    /// claim that the record was never true is *most* worth making about a record the app has
    /// stopped taking contributions on, and a memorial for a tree that never lived is precisely the
    /// state R46 exists to prevent.
    var recordDefect: RecordDefectOffer { profile.recordDefect }

    /// How this record's coordinate was arrived at — the fourth element of the subtitle, and the last
    /// one, because it is the finest-grained provenance fact the row carries.
    ///
    /// **NOT SPECIFIED.** SCREENS.md predates the movable pin; the project owner's ruling is that the
    /// distinction be tracked *and* surfaced. It goes here, on the provenance line, rather than into a
    /// stat card or a badge of its own, because BUILD-PLAN §5 makes provenance a property of the
    /// record — "no UI-only provenance; every provenance fact is a queryable column" — and this line
    /// is where `source` and `verification_state` are already read out. A second, parallel vocabulary
    /// somewhere else on the screen would be the app describing the same kind of fact twice.
    ///
    /// ── Both values are stated, and that is the whole defence against it reading as a demerit ──
    /// It would have been cheaper to print something only for the placed case. That is exactly what
    /// makes a label a warning: the marked case is the exceptional one, and an exceptional coordinate
    /// is a suspect coordinate. It would also be untrue to the record — a hand-placed pin is not the
    /// worse pin, and is very often the better one, because the contributor could see the tree and the
    /// phone could not, and a fix in an SF street canyon is routinely 20–40 m out. So the two arms are
    /// symmetric and neither is evaluative: they name the instrument, the way `recordSource`
    /// names a source without praising it. `TreePlacement` carries the argument in full.
    ///
    /// The words are the owner's own — "added via pin by hand instead of by gps" — kept rather than
    /// improved, because the copy this screen needed was a plain statement and they wrote one.
    ///
    /// **Community rows only.** A city-import row has no `placement` column behind it: the city
    /// arrived at its coordinate by neither of these means, and printing `position from GPS` over an
    /// inventory row would be a claim nothing in the seed supports.
    var placementNote: String? {
        guard tree.source == .community else { return nil }
        switch tree.placement {
        case .gps: return TreeProfilePresentation.placementFromGPS
        case .contributorPlaced: return TreeProfilePresentation.placementByHand
        }
    }

    static let placementFromGPS = "position from GPS"
    static let placementByHand = "position placed by hand"

    /// `THRIVING` / `PLANTED 2024` / `REMOVED`, or none. The mapping is the component's (C13); a
    /// fourth badge is never invented here.
    var badge: StatusBadge.Kind? {
        StatusBadge.kind(
            status: tree.status,
            vitality: profile.latestObservation?.vitality,
            plantedYear: tree.plantedYear
        )
    }

    // MARK: - Hero (03) and empty well (14)

    /// `214 photos · since 2019`.
    ///
    /// Both halves are claims about the tree's **whole** photo series, and a page can answer
    /// neither: read off `LIMIT 30`, a tree with 214 photographs going back to 2019 rendered
    /// `30 photos · since 2024`, two wrong numbers that both look like facts (ERRATA E38). So the
    /// pill renders only from a complete series. A page renders nothing rather than a plausible
    /// lie, and nothing is a state the hero already has — this is an optional.
    var heroMetaPill: String? {
        guard let count = visiblePhotos.totalCount, count > 0 else { return nil }
        let noun = count == 1 ? "photo" : "photos"
        guard let earliest = visiblePhotos.items.map(\.capturedAt).min() else { return nil }
        let year = calendar.component(.year, from: earliest)
        return "\(count) \(noun) · since \(year)"
    }

    /// `Best photo · Oct 2025` — A3. Dropped in dark (D2); that is the view's call.
    var heroEyebrow: String? {
        guard let best = bestPhoto else { return nil }
        return "Best photo · " + TreeProfilePresentation.monthYear.string(from: best.capturedAt)
    }

    /// The photograph this tree leads with — `PhotoHero.choose` over the set this screen may show.
    ///
    /// A3's word "approved" is the *public* half of the rule and lives in
    /// `Photo.isPublicBestPhotoCandidate`; applying it here would mean this device never shows its
    /// owner a best photo of their own tree.
    ///
    /// The rule itself moved to `Core` (ERRATA E125) so that screen 03's hero and screen 20's
    /// `Hero` badge cannot answer this differently — the browser exists to change the answer, and a
    /// browser that disagreed with the screen it changes would be worse than no browser. It also
    /// gained A3's long-dead second half: a thumbs-up is the manual pin that overrides the
    /// heuristic. See `PhotoHero`.
    var bestPhoto: Photo? {
        PhotoHero.choose(from: visiblePhotos.items, tallies: profile.photoTallies)
    }

    /// The caption the viewer carries when the hero is pressed — `Route.photoViewer` explains why it
    /// travels with the route instead of being read again at the other end.
    ///
    /// **`TreePhotosPresentation.caption`, not the eyebrow.** The eyebrow says `Best photo · Oct
    /// 2025`, which is a claim about this photograph's *rank* and is true only for as long as
    /// nobody votes; screen 20 captions the same picture `Full tree · 12 Oct 2025`, which is a claim
    /// about what is in it. Two entrances to one viewer must not name one photograph two ways, and
    /// of the two the browser's is the one that stays true. It is also the one D2 does not drop —
    /// dark mode has no eyebrow to borrow.
    var heroPhotoCaption: String? {
        bestPhoto.map(TreePhotosPresentation.caption)
    }

    /// 14's dashed well copy, verbatim.
    static let emptyPhotoWellText = "No photos of this tree yet"

    /// The well is a control (ERRATA E127), and this is what it says it does.
    ///
    /// It is drawn exactly when a photograph *could* be added — `acceptsContributions` gates it — and
    /// `LocationPrompt` (E123) already settled that a dashed-ring card in this vocabulary is tappable
    /// when a user action would fill it. A camera glyph inside a dashed frame, sitting above a button
    /// that says "Be the first to photograph this tree", is the most photograph-shaped hole in the
    /// app; leaving it inert made it the one dashed card here that refused the tap.
    ///
    /// The hint, not the label: the label is the well's own sentence, which states the fact, and R2's
    /// argument about `Favorite` applies to it too — a control should be named for what it is rather
    /// than relabelled with the next tap.
    static let emptyPhotoWellHint = "Opens the camera for this tree"

    /// The hero as a control, and what pressing it does. **NOT SPECIFIED** — neither screen 20
    /// (ERRATA E125) nor the viewer has a mock.
    ///
    /// **Both strings changed when the hero stopped being one control.** They used to read `Photos
    /// of this tree` / `Opens every photo of this tree`, because a press anywhere on the header
    /// opened the browser. It now opens the photograph itself, whole, and the pill beside it opens
    /// the set — so a label promising "every photo" would name the wrong one of the two. The label
    /// names what is under the finger, which is one picture, and the hint names the difference
    /// between pressing and not: that the hero is a crop and the viewer is not.
    static let heroLabel = "Photo of this tree"
    static let heroHint = "Opens the whole photo"

    /// The pill as a control (see `HeroPhotoHeader.onMetaPillTap`). Its own text already says how
    /// many photographs there are, so the hint says where the press goes and does not repeat it.
    static let heroPillHint = "Opens every photo of this tree"

    // MARK: - Season strip (A5)

    /// SCREENS.md 14 drops the strip; every other state keeps it, including a tree that has been
    /// visited but not yet photographed — that strip renders empty rather than disappearing.
    ///
    /// It does need the whole photo series, though. A thin cell is a claim that this tree has no
    /// photograph from that month, and computed over a page that claim can be false — which is
    /// exactly what a well-photographed tree used to get: a strip that stopped filling and lost
    /// months it had shown before (ERRATA E38). An absent strip asserts nothing, so the partial
    /// case drops it rather than drawing it wrong.
    var showsFoliageStrip: Bool { !isCold && visiblePhotos.isComplete }

    /// Twelve months, January first (A5: "the most recent photo per calendar month across all
    /// years, so a strip fills over time").
    ///
    /// The cell is a placeholder for that month's photograph (SCREENS.md §2 preamble), so the strip
    /// encodes photo *coverage*, not a canopy density nobody measured: a month with a photo takes
    /// the densest ramp step, a month without takes the sparsest. D5 is still handed to the
    /// component — `FoliageStrip` clamps an evergreen away from the leaf-off treatment itself.
    var foliageDensities: [FoliageStrip.Density] {
        let covered = photographedMonths
        return (1...12).map { covered.contains($0) ? .full : .thin }
    }

    /// The calendar months (1–12) that carry at least one visible photo.
    var photographedMonths: Set<Int> {
        Set(visiblePhotos.items.map { calendar.component(.month, from: $0.capturedAt) })
    }

    /// `nil` for a site with no species on the record and for a species whose habit no source
    /// states (ERRATA E9). `FoliageStrip` treats both the same way it treats an evergreen: no cell
    /// may take the leaf-off treatment, because that would be a claim about a canopy nobody sourced.
    var leafRetention: LeafRetention? { species?.leafRetention }

    /// `FoliageStrip` labels every cell as a canopy state; on a coverage strip that would be a
    /// claim about foliage nobody made. The view replaces the per-cell labels with this.
    var foliageStripAccessibilityLabel: String {
        let months = photographedMonths.sorted().map { TreeProfilePresentation.monthNames[$0 - 1] }
        guard !months.isEmpty else {
            return "Season strip. No month has a photo yet."
        }
        return "Season strip. Photographed in " + months.joined(separator: ", ") + "."
    }

    // MARK: - How to recognize it

    /// The C14 green callout's body, or `nil`.
    ///
    /// **BUILD-PLAN §15 / DECISIONS §3.15**: the curated species pipeline (BUILD-PLAN §8) has run
    /// for the top 40 species, so `species.id_tips` is `[]` for the other 529 of the seed's 569.
    /// There is no empty-state copy for this callout in SCREENS.md, and ARCHITECTURE §5.8 says an
    /// unmocked state is a question for design rather than a string to invent — so the section is
    /// simply absent, and no placeholder botany is written in its place.
    var recognitionTip: IDTip? { species?.idTips.first }

    static let recognitionLeadIn = "How to recognize it:"

    // MARK: - Primary action

    /// Verbatim from 03 and 14.
    var ctaTitle: String {
        isCold ? "Be the first to photograph this tree" : "Visit · say hello with a photo"
    }

    // MARK: - Secondary action (screen 05)

    /// The C7 outline button under the primary CTA, which is the app's only door to screen 05.
    ///
    /// **Invented under the project owner's one-time authorization** (ERRATA E98). E24 laid out the
    /// two candidates it would not choose between — a fifth cell in C8's quad row, which is drawn
    /// with exactly four, and a second primary CTA, which is drawn with exactly one. This is
    /// neither: C7 is the component whose whole job is "the quieter thing beside the loud one", and
    /// that is the honest relationship between the two contributions. The visit is a photograph; the
    /// check-in is ninety seconds and no camera.
    ///
    /// The copy is assembled from words screen 05 already uses — its own title and its header pill,
    /// `under a minute` — in the `X · Y` shape the primary CTA above it is drawn in. Nothing new is
    /// claimed by it: 05 really is optional throughout and really does fit the minute it promises.
    static let checkInCTATitle = "Check in · under a minute"

    /// Whether to draw it. A memorial and a vacant site take no contribution of any kind, and a
    /// check-in is a contribution (ERRATA E95).
    var offersCheckIn: Bool { acceptsContributions }

    // MARK: - Activity link (screen 13)

    /// The link under the activity feed, which is the app's only door to screen 13.
    ///
    /// **Invented under the project owner's one-time authorization** (ERRATA E98), and it is E66's
    /// own first candidate — "a 'see the whole year' link under 03's activity feed" — down to the
    /// words. E66's second candidate, a tap on the foliage strip, stays rejected for the reason it
    /// gives: the strip is a year of photo coverage and 13 is a year of activity, and making one
    /// open the other asserts a relationship nothing states.
    static let activityLinkTitle = "See the whole year"

    /// Whether to draw it.
    ///
    /// Only where the feed itself drew, which is where there is a year to see. E67 records that
    /// screen 13's shipped state is a header and one line, because no tree in the seed carries any
    /// activity at all; a link that led there from a profile with nothing on it would be a door onto
    /// the empty state, which is ARCHITECTURE §5.6's argument in link form.
    var offersActivityLink: Bool { !activity.isEmpty }

    // MARK: - Regulars row (A8, D1)

    /// A8: "distinct users with 2 or more care_events or observations on the tree in 24 months;
    /// shown only when 3 or more".
    ///
    /// Both halves of A8's "care_events **or** observations" are now on the payload as whole series,
    /// so the count is the one A8 describes. It used to be the care half plus whatever the single
    /// `latestObservation` could add, which the code called a payload limit; screen 13 needed the
    /// check-in series for its middle chart and the limit went with it.
    var caretakers: Caretakers? {
        // A8 counts distinct people over 24 months, and the sentence this feeds spells the number
        // out at the contributor. A page of the 50 most recent care events undercounts a tree with
        // more than that — silently, and by an amount nothing on screen could hint at — so a
        // partial series produces no row rather than a wrong one. Below the threshold the row does
        // not render anyway (DECISIONS constraint 1), which is the same shape of answer.
        guard profile.careEvents.isComplete, profile.observations.isComplete else { return nil }

        var contributionsPerUser: [UUID: Int] = [:]
        for event in profile.careEvents.items where event.deletedAt == nil {
            guard let userID = event.userID, isWithinCaretakerWindow(event.capturedAt) else { continue }
            contributionsPerUser[userID, default: 0] += 1
        }

        // The latest observation is the newest row of `observations`, so counting it from both
        // places would credit one person with two check-ins they made once. The id is what tells
        // them apart, and it is what a caller who only filled `latestObservation` still gets counted
        // by.
        var counted = Set<UUID>()
        for observation in profile.observations.items where observation.deletedAt == nil {
            counted.insert(observation.id)
            guard let userID = observation.userID, isWithinCaretakerWindow(observation.capturedAt) else { continue }
            contributionsPerUser[userID, default: 0] += 1
        }
        if let latest = profile.latestObservation,
           !counted.contains(latest.id),
           latest.deletedAt == nil,
           let userID = latest.userID,
           isWithinCaretakerWindow(latest.capturedAt) {
            contributionsPerUser[userID, default: 0] += 1
        }

        let qualifying = contributionsPerUser
            .filter { $0.value >= TreeProfilePresentation.caretakerMinimumContributions }
            .keys
        guard qualifying.count >= TreeProfilePresentation.caretakerThreshold else { return nil }
        return Caretakers(count: qualifying.count, initials: injectedCaretakerInitials)
    }

    /// `Six people know this tree` — identity phrasing, spelled out exactly as SCREENS.md draws it.
    /// It counts people, never contributions (D1).
    var caretakerHeadline: String? {
        guard let caretakers else { return nil }
        let spelled = TreeProfilePresentation.spellOut.string(from: NSNumber(value: caretakers.count))
            ?? String(caretakers.count)
        return spelled.prefix(1).uppercased() + spelled.dropFirst() + " people know this tree"
    }

    /// A8's "2 or more care_events or observations in 24 months".
    static let caretakerMinimumContributions = 2
    /// A8's cold-start threshold. Below it the row does not render at all (DECISIONS constraint 1).
    static let caretakerThreshold = 3
    static let caretakerWindowMonths = 24

    private func isWithinCaretakerWindow(_ date: Date) -> Bool {
        guard let cutoff = calendar.date(
            byAdding: .month,
            value: -TreeProfilePresentation.caretakerWindowMonths,
            to: now
        ) else { return true }
        return date >= cutoff
    }

    // MARK: - Activity feed

    /// Visits and care events, most recent first.
    var activity: [ActivityItem] {
        var items: [ActivityItem] = visibleVisits.items.map { visit in
            ActivityItem(
                id: visit.id,
                kind: .visit,
                label: "Visit",
                // The separator and the curly quotes are the mock's, carried verbatim.
                detail: visit.note.map { " · “\($0)”" } ?? "",
                timestamp: TreeProfilePresentation.dayStamp.string(from: visit.capturedAt)
            )
        }
        items += profile.careEvents.items.filter { $0.deletedAt == nil }.map { event in
            ActivityItem(
                id: event.id,
                kind: .care,
                label: "Care",
                detail: event.actions.isEmpty
                    ? ""
                    : " · " + event.actions.map(TreeProfilePresentation.careActionLabel).joined(separator: ", "),
                timestamp: TreeProfilePresentation.dayStamp.string(from: event.capturedAt)
            )
        }
        return Array(
            items
                .sorted { left, right in sortDate(of: left) > sortDate(of: right) }
                .prefix(TreeProfilePresentation.activityLimit)
        )
    }

    /// SCREENS.md draws two rows on 03 but does not say what bounds the feed. Four is a "recent
    /// history" window that keeps the screen near its drawn height; it is a **judgment call**, not
    /// a spec value.
    static let activityLimit = 4

    private func sortDate(of item: ActivityItem) -> Date {
        if item.kind == .visit {
            return visibleVisits.items.first { $0.id == item.id }?.capturedAt ?? .distantPast
        }
        return profile.careEvents.items.first { $0.id == item.id }?.capturedAt ?? .distantPast
    }

    /// `watered, mulched` — the BUILD-PLAN §4 vocabulary in prose.
    static func careActionLabel(_ action: CareAction) -> String {
        switch action {
        case .watered: return "watered"
        case .mulched: return "mulched"
        case .weeded: return "weeded"
        case .litterCleared: return "litter cleared"
        case .staked: return "staked"
        }
    }

    // MARK: - Stat grid (D7)

    /// The cards, in the order SCREENS.md draws them across 03 and 14: measurements first, then the
    /// city's own facts. A card whose fact the record does not carry is absent rather than blank —
    /// with the two measurement slots as the deliberate exception, see `emptyMeasurementSlot`.
    var stats: [StatItem] {
        var items: [StatItem] = []

        if let height = latestMeasurement(.height) {
            items.append(
                StatItem(
                    id: "height",
                    label: "Height",
                    value: .quantity(height.quantity),
                    destination: .growthHistory
                )
            )
        } else if offersMeasurement {
            items.append(emptyMeasurementSlot(id: "height", label: "Height", kind: .height))
        }

        if let dbh = latestMeasurement(.dbh) {
            items.append(
                StatItem(id: "dbh", label: "DBH", value: .quantity(dbh.quantity), destination: .growthHistory)
            )
        } else if let cityDBH = cityDBHRangeText {
            // D7, the whole point of this row: the city publishes a 5 cm *bucket*, not a number
            // anybody taped. `.cityRecord` is not a `Quantity`, carries the `city record` badge,
            // and cannot be mistaken downstream for a measurement.
            //
            // It stays inert, which E63 records as deliberate: a bucket is not a reading, so it
            // opens no chart. It is not turned into the measure entrance either — the invitation
            // this screen now carries is an *empty* slot, and a card already showing the city's
            // number is not empty. The Height slot beside it is the door on a city tree.
            items.append(StatItem(id: "dbh", label: "DBH", value: .cityRecord(cityDBH)))
        } else if offersMeasurement {
            items.append(emptyMeasurementSlot(id: "dbh", label: "DBH", kind: .dbh))
        }

        // The planted year is either the badge or a card, never both — 03 badges `THRIVING` and
        // cards `Planted 1898`; 14 badges `PLANTED 2024` and drops the card.
        if let plantedYear = tree.plantedYear, !badgeCarriesPlantedYear {
            items.append(StatItem(id: "planted", label: "Planted", value: .text(String(plantedYear))))
        }

        // `Site` is a 14 card, not an 03 one: SCREENS.md draws it only where the city record is
        // all there is to show. Its value is the publisher's own string verbatim — an open
        // vocabulary kept as free text (BUILD-PLAN §7), so `Sidewalk: Curb side : Cutout` and
        // San Jose's `Park Strip` are both printed as the city wrote them rather than folded into a
        // tidier phrase nobody published.
        //
        // Through `siteTypeText` rather than straight out of the row, because the column is
        // populated with a non-value on 30,445 rows across the two cities — San Jose's `N/A` and
        // `Unassigned`, San Francisco's bare `:` — and every one of those drew a card claiming the
        // city had recorded a placement. One function with `SitePresentation`, because both screens
        // draw this column under this label and two copies is how they came to disagree.
        if isCold, let siteType = tree.siteType.flatMap(CityRecordPresentation.siteTypeText) {
            items.append(StatItem(id: "site", label: "Site", value: .text(siteType)))
        }

        // No `Where it stands` card here. The ground under the tree is a sentence in §9b —
        // `landContextNote` — because the fact cannot be shown without its source and a card has
        // nowhere to put one but a badge. Two parallel rounds both built this; see `landContextNote`.

        if let record = cityRecordText {
            items.append(StatItem(id: "cityRecord", label: "City record", value: .text(record)))
        }

        if let watchFor = watchForText {
            items.append(StatItem(id: "watchFor", label: "Watch for", value: .prose(watchFor)))
        }

        return items
    }

    /// A measurement card with nothing in it, which is the app's only door to screen 16.
    ///
    /// **Invented under the project owner's one-time authorization** (ERRATA E98). Two things about
    /// it are decided here rather than in the view:
    ///
    /// - It is drawn on the cold variant too, which SCREENS.md 14 does not list among its cards.
    ///   The alternative was to show it only on 03, and that would have left 16 unreachable on the
    ///   shipped app, because per D8 every tree in the city inventory renders the cold variant on
    ///   launch day — the same shape of failure E63 records for screen 11.
    /// - Its copy is `Add a reading`, which is E74's own phrase for the control it declined to
    ///   invent. Borrowing the words already written down beats authoring new ones.
    ///
    /// **It is a per-measure door and nothing else** (RULINGS R15). It is not the app's general
    /// "record something" action and cannot be, because it exists only while its own measurement is
    /// missing: a tree carrying both a height and a DBH has no slot at all, and until R15 that tree
    /// had no way into screen 16 from anywhere. The general entrance is on screen 11, under the
    /// measurement log, where E74 first proposed it.
    ///
    /// Its copy stays `Add a reading` rather than becoming `Add a height`: the box's own label
    /// already names the measurement, and a card that says `Height` twice is arguing with nobody.
    private func emptyMeasurementSlot(id: String, label: String, kind: MeasurementKind) -> StatItem {
        StatItem(
            id: id,
            label: label,
            value: .placeholder(TreeProfilePresentation.emptyMeasurementValue),
            destination: .measure(kind)
        )
    }

    /// The empty slot's value copy. **NOT SPECIFIED**; see `emptyMeasurementSlot`.
    static let emptyMeasurementValue = "Add a reading"

    /// Whether this screen may offer to write a measurement.
    ///
    /// `TreeStatus.acceptsNewContributions`, and nothing else: a memorial and a vacant site are
    /// read-only records, and an entrance added to this screen must not be the thing that hands one
    /// of them a write (ERRATA E95).
    private var offersMeasurement: Bool { acceptsContributions }

    // MARK: - Growth history link (screen 11)

    /// The link under the stat grid, and screen 11's second entrance (ERRATA E127).
    ///
    /// ── Why a stat card was not enough ────────────────────────────────────────────────────────
    /// 11's entrance was *specified* — SCREENS.md 03 lists `DBH/Height cards → 11` and 11's own
    /// caption says it "lives under Details on the tree profile" — and E63 recorded it as
    /// unreachable only because nothing could write a measurement. E74/E98 fixed the writing half by
    /// making the empty slot open 16. What that left is a card whose **meaning changes silently**:
    /// before the first reading it says `Add a reading` and opens the measure sheet, and afterwards
    /// it shows `64 cm` and opens a chart. Nothing about a stat card says it is a door in either
    /// state — it is drawn as a fact, like `Planted 1898` and `SF #13284` beside it, which are not
    /// doors. So the person who has just taken their first measurement has no way to find the record
    /// they created except to tap a card that a minute ago meant something else.
    ///
    /// This is that entrance said out loud, in the shape screen 13's already has: a quiet text link
    /// under the block it belongs to, decided here so a designer can delete it in one file. It sits
    /// under the stat grid because the stat grid *is* 03's `Details`, which is where 11's caption
    /// puts it.
    ///
    /// ── When it draws ─────────────────────────────────────────────────────────────────────────
    /// Only where there is a record to read, which is E67's rule for the activity link and
    /// ARCHITECTURE §5.6's for empty blocks: a link onto `No measurements on this tree yet.` would be
    /// a door onto an empty room. **Any** non-deleted measurement counts, not a chartable one — D6
    /// keeps a low-accuracy reading off the chart and screen 11 still shows it in the log, and the
    /// person who took it is the last person who should be told it does not exist.
    var offersGrowthLink: Bool {
        profile.measurements.contains { $0.deletedAt == nil }
    }

    /// **NOT SPECIFIED**; see `offersGrowthLink`. The noun is `emptyMeasurementValue`'s — E74's own
    /// word for what goes into this record — so the control that writes a reading and the control
    /// that reads them back call the same thing by the same name.
    static let growthLinkTitle = "See every reading"

    private var badgeCarriesPlantedYear: Bool {
        if case .planted = badge { return true }
        return false
    }

    /// `65–70 cm`. An en dash and no spaces, matching the copy rules (ARCHITECTURE §5.7).
    ///
    /// `IntRange`'s upper bound is exclusive, mirroring the Postgres `[)` the seed was built from;
    /// the city publishes these as 5 cm buckets, and the bucket is what is shown.
    var cityDBHRangeText: String? {
        guard let range = tree.dbhCityCmRange else { return nil }
        if range.upperBound - range.lowerBound <= 1 { return "\(range.lowerBound) cm" }
        return "\(range.lowerBound)–\(range.upperBound) cm"
    }

    /// `#13284` — the publishing inventory's own id, which is the citable city record (BUILD-PLAN
    /// §7). SF's `TreeID`, San Jose's `FACILITYID`. See `CityRecordCopy.recordNumber` for why the
    /// `SF ` prefix did not survive a second city and the number did (RULINGS R28).
    var cityRecordText: String? {
        guard tree.source == .cityImport, let ref = tree.externalRef, !ref.isEmpty else { return nil }
        return CityRecordCopy.recordNumber(ref)
    }

    /// 14's `Watch for` card. Authored species care content only — 20 of the curated 40 carry any
    /// (BUILD-PLAN §8), and a species with none simply has no card.
    var watchForText: String? {
        let month = calendar.component(.month, from: now)
        return species?.careNotes.first { $0.monthRange.contains(month) }?.text
    }

    private func latestMeasurement(_ kind: MeasurementKind) -> TreeMeasurement? {
        profile.measurements
            .filter { $0.kind == kind && $0.deletedAt == nil }
            .max { $0.capturedAt < $1.capturedAt }
    }

    // MARK: - Where it stands (task #69, second half)

    /// One sentence naming both where the tree stands **and who says so**, or `nil`. **This is the
    /// only place on the screen the fact appears.**
    ///
    /// **NOT SPECIFIED.** SCREENS.md has no land context anywhere, because until E143 no record
    /// carried one. The project owner asked for it here in as many words: *"need to see this
    /// distinction on tree's landing page too, along with other tree metadata"*.
    ///
    /// ── Two rounds built this, and the sentence is what survived ──────────────────────────────
    /// E145 and E146 ran in parallel and each independently put the ground under the tree on this
    /// screen: this sentence, and a `Where it stands` stat card reading
    /// `Private property · said by a contributor`. Both landed on one branch and the same fact
    /// rendered twice. The card was removed; everything else E146 built — the column, the composer's
    /// chips, `Tree.landContext`, the 311 hazard handoff — is untouched and correct.
    ///
    /// E146's own argument was measured against the **subtitle**, not against a sentence, and that
    /// half of it still holds: the provenance line was the obvious home, and it was already full
    /// before this arrived. A community tree with a given name, a species and a moved pin renders
    /// **five** `·`-joined elements —
    ///
    ///     Monterey cypress · Hesperocyparis macrocarpa · community-added, unverified ·
    ///     species named by a contributor · position placed by hand
    ///
    /// — three wrapped lines of italic serif, and a sixth fragment would push the two notes that
    /// *are* about authorship into the middle of a list that had stopped being one sentence.
    /// `theSubtitleCouldNotCarryIt` still asserts the count of five. What that argument does not
    /// establish is a card over a sentence; it never compared the two. The reasons below do.
    ///
    /// ── Why a sentence and not a stat card ────────────────────────────────────────────────────
    /// Because the fact is inseparable from its source, and a `StatCard` has nowhere to put a source
    /// except a badge. `KnownLandContext` exists precisely so that "a contributor stood there and
    /// tapped *city park*" and "Cypress read two strings in a municipal export and concluded *street*"
    /// cannot reach a screen as the same claim — E143 built the type rather than returning a bare
    /// `LandContext` for exactly that reason, on BUILD-PLAN §5's rule that provenance is carried
    /// rather than remembered.
    ///
    /// The badge route was tried on paper and rejected. C12 has two cases, `taped`/`est.` and
    /// `city record`, and neither fits: an inference from the city's record is **not** the city's
    /// record, and stamping `city record` on it would be the app attributing its own reading to San
    /// Francisco — the single failure this whole round is written to avoid. Adding a third and fourth
    /// case to C12 would put "how a number was measured" and "who said where a tree stands" in one
    /// vocabulary, and would need a colour ramp saying which of the two ways of knowing is better.
    /// There is no such ranking: a contributor who was standing there beats the seed, and the seed
    /// covers 195,309 trees a contributor has never visited.
    ///
    /// A sentence has room to name its speaker in words, which is what `speciesClaimNote` already
    /// does one block up the screen ("species named by a contributor"). This is the same grammar.
    /// The card's best available shape was `Private property · said by a contributor` — four words
    /// after a middle dot, doing the work of a clause. It is thinnest on exactly the distinction that
    /// is the point: *Cypress reads* and *A contributor said* are different verbs by different
    /// speakers, and a `·`-joined tail flattens them into two interchangeable-looking suffixes.
    ///
    /// ── Symmetric, and inert ──────────────────────────────────────────────────────────────────
    /// All four values print and none is marked — `on a street` reads exactly as `on private
    /// property` does, and a tree in a garden is not flagged. E141 refused E138's symmetry for the
    /// species line because the alternative to "a contributor named it" is *no species*, which has
    /// nothing to attribute; that does not apply here, where a context that exists always came from
    /// one of exactly two ways of knowing. Nothing here is a door, and nothing needs to be: there is
    /// no update path on `community_trees.land_context` and a city row's context is derived in `Core`
    /// from a read-only database, so a control offering to correct it would promise an edit the app
    /// cannot make (E63's defect). When neither way of knowing has an answer there is no sentence,
    /// which asserts nothing.
    ///
    /// ── Why it is outside "What the city has on file" ─────────────────────────────────────────
    /// On a city row this is Cypress's *reading* of `legalStatus` and `caretaker`, and that reading is
    /// a rule in `LandContext.inferred(from:)` which can be wrong about any individual tree. Inside a
    /// section headed with the city's name, under a card badged `city record`, it would be the app's
    /// inference wearing the city's authority. So it sits above the section, in the app's own voice,
    /// and says whose conclusion it is.
    ///
    /// It renders for community rows too, where there is no city section at all — one fact, one place
    /// on the screen, regardless of which of the two ways it is known.
    var landContextNote: String? {
        guard let known = tree.landContext else { return nil }
        let place = TreeProfileCopy.landContextPlace(known.context)
        switch known.source {
        case .inferredFromCityRecord:
            return TreeProfileCopy.landContextInferred(place)
        case .statedByContributor:
            return TreeProfileCopy.landContextStated(place)
        }
    }

    // MARK: - What the city has on file (task #68, made city-agnostic by #137/R28)

    /// The city's own six columns, prepared for the grid — or `nil` when there is no section to draw.
    ///
    /// `nil` on every community row, because a community tree is by definition not in the city's
    /// inventory and `Tree.cityRecord` is `nil` for it. There is no empty state and no "the city has
    /// no record of this tree" copy: the subtitle already reads `community-added, unverified`, which
    /// says the same thing in the place the screen already says it, and a second sentence saying the
    /// city has nothing would be the app apologising for a tree somebody added on purpose.
    ///
    /// Also `nil` when the record produces no card — see `CityRecordPresentation.isEmpty`.
    var cityRecord: CityRecordPresentation? {
        guard let record = tree.cityRecord, !record.isEmpty else { return nil }
        // The row's id space travels with the record, because two of the section's readings are of
        // one publisher's vocabulary and R24 requires those to decline outside it — see
        // `CityRecordPresentation.listedAsText`, which drew `City lists this as — N/A` on 25,032
        // San Jose rows until it could ask this question.
        let presentation = CityRecordPresentation(record, idSpace: tree.idSpace)
        return presentation.isEmpty ? nil : presentation
    }

    /// The sentences under the city's grid, in the order they are drawn.
    ///
    /// The opt-out arrangement first, because it is a fact about *this* tree and answers the reader
    /// who has just read `Prune Opt Out` on the card above; the general note second, because it is a
    /// fact about the dataset. Empty when there is no section.
    ///
    /// **The pruning note is San Francisco's and is absent outside it** — see
    /// `CityRecordPresentation.pruningNote(idSpace:)`. A San Jose tree's section is a shorter list,
    /// not a list with a substitute in it (RULINGS R28).
    var cityRecordNotes: [String] {
        guard showsCityRecordSection else { return [] }
        var notes: [String] = []
        if let optOut = cityRecord?.maintenanceOptOutNote() { notes.append(optOut) }
        if let pruning = CityRecordPresentation.pruningNote(idSpace: tree.idSpace) { notes.append(pruning) }
        if let provenance = inventoryProvenanceNote { notes.append(provenance) }
        return notes
    }

    /// Whether "What the city has on file" draws.
    ///
    /// **Cards, or a provenance line.** It used to be cards alone, and `CityRecordPresentation`
    /// still explains why: a header over an empty grid is worse than no header, so a record whose
    /// only content the app declines to show — a bare permit number (E145) — draws nothing.
    ///
    /// That rule silently removed the entire section from every tree in the shipped seed when #91
    /// switched sources. SF Public Works' own layer publishes exactly one of the six city columns,
    /// `PlantType`, and `plantType == "Tree"` deliberately draws no card, so every one of the
    /// 133,577 records produced an empty grid and the section vanished — taking the pruning answer
    /// and the provenance line with it.
    ///
    /// A provenance line is not an empty grid. "This came from the city's street tree inventory, read
    /// on 26 July 2026" is a fact about *this record* and is the one the section exists to carry
    /// now that the inventory publishes so little else. The pruning note alone does not open the
    /// section: it is a statement about the dataset and needs something of this tree's beside it.
    var showsCityRecordSection: Bool { cityRecord != nil || inventoryProvenanceNote != nil }

    /// `From the SF Public Works street tree inventory, 26 July 2026.` — or nothing.
    ///
    /// Renders only when the seed knows **both** which inventory it is and what day that inventory
    /// was read. A source with no date is half a provenance claim, and the half that is missing is
    /// the one this line exists for; the app says nothing rather than implying the records are
    /// current. See `InventorySource` and `CityRecordCopy.provenanceNote`.
    var inventoryProvenanceNote: String? {
        // Only for a record that came out of an inventory. A community-added tree is nobody's city
        // record, and `LocalAPI` already withholds the source for one; this is the second lock.
        guard tree.cityRecord != nil else { return nil }
        guard let source = profile.inventorySource, let snapshot = source.snapshotDate else { return nil }
        return CityRecordCopy.provenanceNote(
            source: source.name,
            snapshot: TreeProfilePresentation.snapshotDay.string(from: snapshot)
        )
    }

    /// Whether §9b draws anything at all — the land-context sentence, the city's grid, or both.
    ///
    /// The view asks this to decide which block closes the screen, so the 30 pt that SCREENS.md 03 §9
    /// puts under the stat grid keeps landing under whatever is genuinely last.
    var showsCityDetails: Bool { landContextNote != nil || showsCityRecordSection }

    // MARK: - Cold-start footnote

    /// 14's footnote, verbatim — minus its first sentence when that sentence would be false.
    ///
    /// The drawn copy reads `A young tree nobody has visited. This is the almanac’s “walk the nine”
    /// list, one tree at a time.` The second sentence is true of every cold profile. The first is a
    /// claim about *this* tree, and D8 puts this variant in front of every tree in the city
    /// inventory, including 1890s cypresses. So the age claim renders only where the city record
    /// supports it, and nothing is reworded to cover the gap.
    ///
    /// **Judgment call, not in the spec:** `recentPlantingWindowYears`. SCREENS.md says nothing
    /// about what makes a tree "young"; ten years is a street-tree establishment horizon and is
    /// named here so it can be argued with in one place.
    ///
    /// **ERRATA E129 kept this sentence and changed what it describes.** Until E129 the almanac's
    /// `Walk the nine` button opened one tree's profile, so "one tree at a time" was not a
    /// description of a list — it was the whole destination, and this footnote was the app explaining
    /// a missing screen from inside the wrong one. The button now opens a map of all nine and a tap on
    /// a pin lands here, so the reader arriving at this sentence has seen the list and chosen one tree
    /// of it. The words are unchanged because they are specified verbatim (SCREENS.md 14 §7) and are
    /// now simply true; deleting a drawn string because the route around it improved would be a design
    /// change, and this round had no standing to take one.
    var coldStartFootnote: String {
        guard isCold else { return "" }
        let almanac = "This is the almanac’s “walk the nine” list, one tree at a time."
        guard isRecentPlanting else { return almanac }
        return "A young tree nobody has visited. " + almanac
    }

    static let recentPlantingWindowYears = 10

    private var isRecentPlanting: Bool {
        guard let plantedYear = tree.plantedYear else { return false }
        let thisYear = calendar.component(.year, from: now)
        return thisYear - plantedYear <= TreeProfilePresentation.recentPlantingWindowYears
    }

    // MARK: - Filtered series

    /// The photos **this screen** may draw.
    ///
    /// This screen runs on the contributor's own device, and moderation is a gate on publication,
    /// not between somebody and the photograph they took. Nothing in the shipping app can set
    /// `.approved` — there is no moderation service — so gating this on it left every tree with no
    /// hero, no season strip and no best photo, and because a visit still landed, `isCold` was
    /// false and the cold-start copy did not render either: it read as a designed empty screen
    /// (ERRATA E37).
    ///
    /// So: the device's own photos, plus anything that has actually been approved. The photos stay
    /// `.pending`, which is the truth — nothing has moderated them.
    var visiblePhotos: Series<Photo> {
        profile.photos.filter { photo in
            profile.isOwnPhoto(photo) ? photo.isVisibleToItsContributor : photo.isPubliclyVisible
        }
    }

    /// The photos a **public** surface may draw — the shared tree page, the share card, the
    /// OpenGraph render. Approved only, always (BUILD-PLAN §10, A3). Kept beside `visiblePhotos`
    /// under a name that cannot be misread as it: one is "I can see this", the other is "the world
    /// can see this", and they are not the same question.
    var publiclyVisiblePhotos: Series<Photo> {
        profile.photos.filter(\.isPubliclyVisible)
    }

    var visibleVisits: Series<Visit> {
        profile.visits.filter { $0.deletedAt == nil }
    }

    /// The check-ins, tombstones dropped. Screen 13's middle small multiple reads this.
    var visibleObservations: Series<TreeObservation> {
        profile.observations.filter { $0.deletedAt == nil }
    }

    /// The care events, tombstones dropped.
    var visibleCareEvents: Series<CareEvent> {
        profile.careEvents.filter { $0.deletedAt == nil }
    }

    // MARK: - Formatters

    private static func fixedFormat(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }

    /// `Oct 2025`.
    static let monthYear = fixedFormat("MMMyyyy")
    /// `Oct 12`.
    static let dayStamp = fixedFormat("MMMd")

    /// `26 July 2026` — the day the city's inventory was read.
    ///
    /// Spelled out rather than `Jul 26`: this stamp is read once, at the bottom of a section, by
    /// somebody checking whether the facts above it are current. Every other date in this file is a
    /// repeated element in a list, where the short form earns its terseness. `yMMMMd` is fixed to
    /// UTC because the snapshot is a calendar day the source recorded, not a moment anybody was
    /// present for — rendering it in the reader's zone could move it a day.
    static let snapshotDay: DateFormatter = {
        let formatter = fixedFormat("yMMMMd")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static let spellOut: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter
    }()

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}

// MARK: - Copy this screen owns rather than derives

/// Strings screen 03 renders that are not in SCREENS.md, kept out of the view for the reason every
/// `*Presentation` in this app is: a sentence a state produces is a decision, and a decision is worth
/// a test that does not have to render a `View` to read it.
enum TreeProfileCopy {

    /// The control that names a species on a tree that has none.
    ///
    /// It asks rather than instructs, and it says *you think* rather than *it is*, because the act it
    /// starts records an opinion and the label should not promise more than the column stores.
    static let claimSpeciesAction = "Say what species you think this is"

    // MARK: - The species the record never named (see `TreeProfilePresentation.unreadSpeciesNote`)

    /// `The city files this tree as “Magnolia” and its record gives no scientific name.`
    ///
    /// **The claim is exactly the one the data supports and no larger.** The record does carry a
    /// word for the tree; what it does not carry is the botanical half of DataSF's species column.
    /// So the sentence states both halves in the order a reader needs them — here is where that
    /// word came from, and here is what the record stops short of — and it neither apologises for
    /// the city nor implies the tree is unidentifiable. Somebody standing in front of it can see
    /// perfectly well what it is; the *record* cannot.
    ///
    /// **`files … as` rather than `calls` or `names`.** One of the five wordings is `9662`, and a
    /// verb of naming would make the sentence read as a claim that `9662` is this tree's name. A
    /// verb of filing describes what a municipal inventory did with a cell, which is all that is
    /// known, and it survives a wording that is plainly a work-order number. It borrows the grammar
    /// of `CityRecordCopy.plantTypeLabel` — `City lists this as` — deliberately: the app already has
    /// one voice for reading a city column out without adopting it.
    ///
    /// Typographic quotes, as `neverExistedNotice`'s apostrophe already uses (ARCHITECTURE §5.7).
    /// They are load-bearing here rather than decorative: they are what marks the word as somebody
    /// else's.
    static func unreadSpeciesNote(cityWording: String) -> String {
        "The city files this tree as “\(cityWording)” and its record gives no scientific name."
    }

    // MARK: - Where the tree stands (see `TreeProfilePresentation.landContextNote`)

    /// The place, as a prepositional phrase that fits both sentences below unchanged.
    ///
    /// `otherPublic` is the 956 rows that are neither street nor park nor private — SFUSD, the Port,
    /// the PUC, the Housing Authority — and it says "other public land" rather than naming a
    /// department, because the bucket is defined by what it is not. E143's argument for the fourth
    /// value is that a vocabulary permitting a value no screen offers costs nothing; a screen that has
    /// to draw it anyway owes it a phrase that is true of all 956.
    static func landContextPlace(_ context: LandContext) -> String {
        switch context {
        case .street: return "on a street"
        case .cityPark: return "in a city park"
        case .privateProperty: return "on private property"
        case .otherPublic: return "on other public land"
        }
    }

    /// **The app names itself as the one drawing the conclusion**, which is the whole point of the
    /// sentence. "This tree stands on a street" would be a claim; "Cypress reads the city's record as"
    /// is a citation, and it puts the reader one step from disagreeing with it. The passive
    /// alternatives all hide the speaker, and the speaker is the fact being conveyed.
    ///
    /// `LandContext.inferred(from:)` resolves all 195,309 seed rows, 93.35% of them to `on a street`,
    /// so this is the sentence almost every tree in the app shows.
    static func landContextInferred(_ place: String) -> String {
        "Cypress reads the city's record as a tree \(place)."
    }

    /// "A contributor", not "the contributor" — `community_trees` records no author, exactly as
    /// `speciesNamedByContributor` explains one block up.
    ///
    /// It states the fact directly, where the inferred arm cites itself, because a contributor
    /// standing at the tree *observed* this. Softening an observation into a reading would be the
    /// mirror of the error the other arm avoids.
    static func landContextStated(_ place: String) -> String {
        "A contributor said this tree stands \(place)."
    }
    // The control that answers *where is it* is `ShowWhereButton`, and its words are `PinSetCopy`'s
    // — the screen it opens owns the sentence that names it, the same way `PinSetCopy.title` takes
    // the almanac's own micro-labels rather than inventing two of its own. Why the control is on
    // this screen at all is on `TreeProfilePresentation.locateSet` (ERRATA E144).

    /// Why a claim did not land. Three refusals, three sentences — the mapping is here rather than in
    /// the model because "already claimed" and "not allowed on a city tree" are entirely different
    /// facts about the world, and an app that showed one message for both would be telling somebody
    /// their contribution failed when it was in fact somebody else's that succeeded.
    static func speciesClaimFailure(_ error: APIError) -> String {
        switch error {
        case .conflict:
            // Was "…which this app cannot record yet", which stopped being true at AppSchema v14.
            // A correction is recordable now; what a second claimant still may not do is make one
            // over somebody else's statement without asking.
            return "Somebody has already said what this tree is. Their name for it stands until it "
                + "is corrected."
        case .forbidden:
            return "This tree comes from the city inventory, and its species is the city's record."
        case .notFound:
            return "This tree could not be found. Nothing was recorded."
        default:
            return "That species could not be recorded. Nothing was changed."
        }
    }

    // MARK: - Correcting a claim (#86, #124)

    /// The control on a claim that is this contributor's own.
    ///
    /// It says *correct*, not *change*: what the act does is append a correction to a chain that
    /// keeps the first claim, and a label promising a change would describe an overwrite that does
    /// not happen.
    static let correctSpeciesAction = "Correct the species"

    /// The control on somebody else's claim — or on one whose author the record never kept.
    static let reportSpeciesAction = "Report the species as wrong"

    /// Where a report goes, in `CheckInCopy.reviewNotice`'s register and for its reason: the person
    /// tapping this is reasonably hoping somebody official will fix the record, and DECISIONS §3.3
    /// forbids implying it (D16 made that permanent).
    static let reportSpeciesNotice = "This goes to a community reviewer. The city is not notified."

    /// Drawn while a report is open, to everybody: the disagreement is on the record and the screen
    /// says so rather than showing the species as if nobody had objected.
    static let speciesReported = "Somebody has reported this species as wrong."

    /// The second verb, for whoever may answer the report. "Keep" rather than "dismiss" because it
    /// names what the tree ends up with, and because nothing is thrown away — the report keeps its
    /// row, marked answered.
    static let keepSpeciesAction = "Keep the species"

    static func speciesCorrectionFailure(_ error: APIError) -> String {
        switch error {
        case .forbidden:
            return "This species was named by somebody else, so it is not yours to change. "
                + "You can report it as wrong instead."
        case .conflict:
            return "This species has already been corrected. Nothing was changed."
        case .validationFailed:
            return "There is no species on this tree to correct."
        case .notFound:
            return "This tree could not be found. Nothing was changed."
        default:
            return "That correction could not be recorded. Nothing was changed."
        }
    }

    static func speciesReportFailure(_ error: APIError) -> String {
        switch error {
        case .conflict:
            return "This species has already been reported. Nothing was added."
        case .validationFailed:
            return "There is nothing here to report."
        case .forbidden:
            return "This tree comes from the city inventory, and its species is the city's record."
        case .notFound:
            return "This tree could not be found. Nothing was recorded."
        default:
            return "That report could not be recorded. Nothing was changed."
        }
    }

    // MARK: - The record itself (task #125)

    /// The control. It names the observation a reader can actually make — *there is nothing here* —
    /// rather than the conclusion the record draws from it.
    ///
    /// Not "Report this tree as missing": missing is what a removal is, and the whole of
    /// `RULINGS R46` is that the two must not be said with one word. A tree that was here and is
    /// gone is screen 05's `Removed?`, which writes a memorial; this is the claim that the row was
    /// never true.
    static let reportNeverExistedAction = "Report that there is no tree here"

    /// Where the report goes — and this sentence is the one that had to be written against the
    /// build rather than against the architecture.
    ///
    /// The obvious sentence was `reportSpeciesNotice`'s, "This goes to a community reviewer. The
    /// city is not notified." It is not available. During beta there is **no contribution sync**:
    /// the outbox drains through `APIOutboxTransport` into `LocalAPI`, which writes this phone's own
    /// tables, and nothing uploads or downloads anybody's rows. A report reaches no other reader, so
    /// promising a community reviewer is D16(a)'s banned claim with a different noun — a destination
    /// named that the report does not arrive at. §3 constraint 3 forbids the city version of it
    /// permanently, and the principle underneath is that the app never says it did a thing it did
    /// not do.
    ///
    /// So the sentence says the two things that are true: the report is kept, and it is kept here.
    /// E126's rule is why it says the second half out loud instead of falling silent about the
    /// destination — a surface that cannot do the thing has to say so plainly rather than let the
    /// reader supply an answer.
    /// The negation is spelled `The city is not notified` and not `Nothing is sent to the city`,
    /// which is what this first read. Both sentences mean the same thing to a person and only one of
    /// them survives the test that guards them: the guard is a substring check for the forbidden
    /// *claim*, and a claim's negation contains the claim. The sanctioned form is already the app's
    /// — `CheckInCopy.reviewNotice` and `TreeProfileCopy.reportSpeciesNotice` both use it — so the
    /// register matches the two surfaces a reader meets this on either side of.
    static let neverExistedNotice = """
        This is kept on this phone and shows on this record. The city is not notified, and Cypress \
        cannot yet carry a report to anybody else’s phone.
        """

    /// Drawn while a report is open, to everybody including whoever raised it: a record under
    /// dispute must not render as though nobody had objected. `speciesReported`'s reason.
    static let recordReported = "This record has been reported as never having held a tree."

    /// The confirming verb. "Withdraw" rather than "delete" or "remove", and each rejected word is
    /// rejected for a reason:
    ///
    /// - *Delete* would promise an erasure that does not happen. The row keeps its place with a
    ///   `deleted_at` on it, because a confirmed "this was never here" is a fact D16's merged
    ///   inventory wants and an erased row cannot be published.
    /// - *Remove* is `TreeStatus.removed`'s word, and lending it to the one act that must never be
    ///   read as a removal would undo R46 in the label.
    static let withdrawRecordAction = "Withdraw this record"

    /// What withdrawing does, stated before it is done rather than discovered after.
    ///
    /// The act takes a pin off the map and closes this screen, which is more than any other control
    /// on the profile does, and a reader is owed the sentence. It is a line and not a dialog on
    /// purpose: #125 is a report path, not a moderation product, and the queue's own confirmation
    /// alerts belong to the surface that has a queue.
    static let withdrawRecordNotice = """
        Withdrawing takes this record off the map. It stays on this phone, marked withdrawn.
        """

    /// The second verb, for whoever may answer the report. "Keep" rather than "dismiss" because it
    /// names what the map ends up with, and because nothing is thrown away — the report keeps its
    /// row, marked answered. `keepSpeciesAction`'s argument, one seam over.
    static let keepRecordAction = "Keep this record"

    /// `.forbidden` carries two meanings across the three writes — a city row on the raise, a
    /// non-lead on the resolve — and the city sentence is the one written here because it is the
    /// only one a reader can reach: the resolve controls are drawn only when `canResolve`, which is
    /// the same role question the write re-asks.
    static func recordDefectFailure(_ error: APIError) -> String {
        switch error {
        case .conflict:
            return "This record has already been reported. Nothing was added."
        case .forbidden:
            return "This tree comes from the city inventory, and Cypress cannot withdraw a city "
                + "record."
        case .validationFailed:
            return "There is nothing here to report."
        case .notFound:
            return "This record could not be found. Nothing was changed."
        default:
            return "That report could not be recorded. Nothing was changed."
        }
    }
}
