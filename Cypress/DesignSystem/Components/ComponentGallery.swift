//
//  ComponentGallery.swift
//  Cypress — DesignSystem/Components
//
//  A visual contact sheet for C1–C30 of docs/distilled/SCREENS.md §2 — every component in every
//  documented state, labelled with its C-number. This is how the component layer is verified before
//  a screen is built: run the two previews below side by side and compare against SCREENS.md §2.
//
//  Same house style as `TokenGallery.swift`. Not shipped in any screen; imports nothing outside
//  DesignSystem and Core.
//

import SwiftUI

struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                GalleryHeader()

                GalleryC1()
                GalleryC2()
                GalleryC3()
                GalleryC4()
                GalleryC5()
                GalleryC6C7()
                GalleryC8()
                GalleryC9()
                GalleryC10()
                GalleryC11()
                GalleryC12()
                GalleryC13()
                GalleryC14C15()
                GalleryC16()
                GalleryC17()
                GalleryC18C19()
                GalleryC20C21()
                GalleryC22()
                GalleryC23()
                GalleryC24C25()
                GalleryC26C27C28()
                GalleryC29C30()
                GalleryForcedDark()
            }
            .padding(.vertical, 24)
        }
        .background(CypressColor.surfaceScreen)
    }
}

// MARK: - Section chrome

private struct GalleryHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cypress components")
                .font(CypressFont.screenTitleGrove)
                .foregroundStyle(CypressColor.textInk)
            Text("SCREENS.md §2 — C1 to C30")
                .font(CypressFont.body135)
                .foregroundStyle(CypressColor.textMuted)
        }
        .cypressLabelGutter()
    }
}

private struct GallerySection<Content: View>: View {
    let number: String
    let name: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapCandidates) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number) · \(name)").cypressMicroLabel()
                if let note {
                    Text(note)
                        .font(CypressFont.body12)
                        .foregroundStyle(CypressColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .cypressLabelGutter()
    }
}

/// A caption above one variant, so every state on screen says which row of §2 it is.
private struct VariantLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(CypressFont.mono10)
            .foregroundStyle(CypressColor.textFaint)
    }
}

private struct Variant<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            VariantLabel(label)
            content
        }
    }
}

// MARK: - Sample data

enum GallerySample {
    static let dbhTaped = Quantity(value: 64, unit: .centimeters, method: .tape)
    static let dbhPrevious = Quantity(value: 62, unit: .centimeters, method: .tape)
    static let dbhEstimated = Quantity(value: 60, unit: .centimeters, method: .estimate)
    static let heightEstimated = Quantity(value: 18, unit: .meters, method: .estimate)
    static let dbhCaliper = Quantity(value: 31, unit: .centimeters, method: .caliper)
    static let heightLaser = Quantity(value: 21.5, unit: .meters, method: .laser)

    /// An evergreen — the flagship Monterey Cypress that D5 exists because of.
    static let evergreen: Species? = try? Species(
        scientificName: "Hesperocyparis macrocarpa",
        commonName: "Monterey Cypress",
        family: "Cupressaceae",
        leafRetention: .evergreen,
        curated: true
    )

    /// A deciduous species, for the contrasting phenology chip set.
    static let deciduous: Species? = try? Species(
        scientificName: "Ginkgo biloba",
        commonName: "Ginkgo",
        family: "Ginkgoaceae",
        leafRetention: .deciduous,
        seasonal: SeasonalCalendar(fallColorMonths: [10, 11], newGrowthMonths: [4]),
        curated: true
    )

    /// One of the 59 seeded species whose habit no source states (ERRATA E9). It is `curated`
    /// precisely so the gallery shows that a species with authored content still surfaces no
    /// phenology when the attribute the whole vocabulary hangs off is unknown.
    static let unknownHabit: Species? = try? Species(
        scientificName: "Ficus laurel",
        commonName: "Laurel Fig",
        family: "Moraceae",
        leafRetention: nil,
        curated: true
    )

    /// Twelve months with a bare winter — the input D5 has to defuse for an evergreen.
    static let deciduousYear: [FoliageStrip.Density] = [
        .bare, .bare, .thin, .partial, .full, .full,
        .full, .full, .partial, .partial, .thin, .bare,
    ]
}

// MARK: - C1

private struct GalleryC1: View {
    var body: some View {
        GallerySection(number: "C1", name: "ScreenHeader") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("title only") {
                    ScreenHeader(title: "Report an issue", onBack: {})
                }
                Variant("trailing pill · neutral") {
                    ScreenHeader(title: "Check-in", trailingPill: "under a minute", onBack: {})
                }
                Variant("trailing pill · amber (17)") {
                    ScreenHeader(
                        title: "Outbox",
                        trailingPill: "3 waiting · offline",
                        pillStyle: .amber,
                        onBack: {}
                    )
                }
                Variant("no back button · wide bottom inset (02)") {
                    ScreenHeader(title: "What tree is this?", bottomInset: .wide)
                }
            }
            .padding(.horizontal, -CypressSpacing.gutterLabel)
        }
    }
}

// MARK: - C2

private struct GalleryC2: View {
    var body: some View {
        GallerySection(number: "C2", name: "HeroPhotoHeader") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("profile · 224pt (03)") {
                    HeroPhotoHeader(
                        style: .profile,
                        metaPill: "214 photos · since 2019",
                        eyebrow: "Best photo · Oct 2025",
                        onBack: {}
                    )
                }
                Variant("species · 190pt (07)") {
                    HeroPhotoHeader(style: .species, eyebrow: "Field guide", onBack: {})
                }
                Variant("memorial · 200pt (19)") {
                    HeroPhotoHeader(
                        style: .memorial,
                        metaPill: "86 photos · 2019–2026",
                        eyebrow: "Last photo · Apr 2026"
                    )
                }
                Variant("profile dark · 224pt (D2) — eyebrow dropped") {
                    HeroPhotoHeader(
                        style: .profileDark,
                        metaPill: "214 photos · since 2019",
                        onBack: {}
                    )
                    .cypressForcedDark()
                }
            }
            .padding(.horizontal, -CypressSpacing.gutterLabel)
        }
    }
}

// MARK: - C3

private struct GalleryC3: View {
    var body: some View {
        GallerySection(
            number: "C3",
            name: "FoliageStrip",
            note: "D5 lives in the component: an evergreen's bare months are clamped."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("profile · eyebrow + month row (03) · Grandmother Cypress sequence") {
                    FoliageStrip(
                        leafRetention: .evergreen,
                        densities: FoliageStrip.grandmotherCypress
                    )
                }
                Variant("D2 dark · no month row, no eyebrow") {
                    FoliageStrip(
                        leafRetention: .evergreen,
                        densities: FoliageStrip.grandmotherCypress,
                        showsMonthRow: false,
                        showsEyebrow: false
                    )
                    .padding(CypressSpacing.gapRows)
                    .background(CypressColor.Dark.bgScreen)
                    .cypressForcedDark()
                }
                Variant("share-card variant · 11pt squares (10)") {
                    FoliageStrip(
                        leafRetention: .evergreen,
                        densities: FoliageStrip.grandmotherCypress,
                        variant: .shareCard
                    )
                    .frame(width: 170)
                }
                Variant("deciduous · same input, bare winter renders") {
                    FoliageStrip(
                        leafRetention: .deciduous,
                        densities: GallerySample.deciduousYear,
                        showsEyebrow: false
                    )
                }
                Variant("evergreen · SAME input, D5 clamps every bare month") {
                    FoliageStrip(
                        leafRetention: .evergreen,
                        densities: GallerySample.deciduousYear,
                        showsEyebrow: false
                    )
                }
                Variant("habit unknown · SAME input, clamped too — a bare month is a claim (E9)") {
                    FoliageStrip(
                        leafRetention: nil,
                        densities: GallerySample.deciduousYear,
                        showsEyebrow: false
                    )
                }
            }
        }
    }
}

// MARK: - C4

private struct GalleryC4: View {
    /// Every row of §2's C4 table, in table order.
    private let rows: [(String, Chip.Style)] = [
        ("Filter, selected (01)", .filterSelected),
        ("Filter, idle (01)", .filterIdle),
        ("Meta chip (02, 07)", .meta),
        ("Structure flag, idle (05)", .structureFlagIdle),
        ("Structure flag, on (05)", .structureFlagOn),
        ("Hazard, on (06)", .hazardOn),
        ("Hazard, off (06)", .hazardOff),
        ("Care toggle, on (09)", .careOn),
        ("Care toggle, off (09)", .careOff),
        ("Phenology, on (04)", .phenologyOn),
        ("Phenology, off (04)", .phenologyOff),
        ("Shot type, on (04)", .shotTypeOn),
        ("Shot type, off (04)", .shotTypeOff),
        ("Dark flag, on (D3)", .darkFlagOn),
        ("Dark flag, off (D3)", .darkFlagOff),
        ("Sanity-check pill (16)", .sanityCheck),
        ("Method legend · taped (11)", .methodLegendTaped),
        ("Method legend · estimated (11)", .methodLegendEstimated),
    ]

    private func label(for style: Chip.Style) -> String {
        switch style {
        case .filterSelected: return "All"
        case .filterIdle: return "In bloom"
        case .meta: return "Evergreen conifer"
        case .structureFlagIdle: return "Lean"
        case .structureFlagOn: return "Broken limb"
        case .hazardOn: return "Hanging limb"
        case .hazardOff: return "Split trunk"
        case .careOn: return "Watered ✓"
        case .careOff: return "Weeded basin"
        case .phenologyOn: return "New growth"
        case .phenologyOff: return "Cones"
        case .shotTypeOn: return "Full tree"
        case .shotTypeOff: return "Trunk"
        case .darkFlagOn: return "Broken limb"
        case .darkFlagOff: return "Lean"
        case .sanityCheck: return "Last recorded 62 cm, Jun 2024 · +2 cm in a year sounds right"
        case .methodLegendTaped: return "taped"
        case .methodLegendEstimated: return "estimated"
        }
    }

    /// The 04 and D3 chips are drawn on screens that are dark regardless of the system setting.
    private func isForcedDark(_ style: Chip.Style) -> Bool {
        switch style {
        case .phenologyOn, .phenologyOff, .shotTypeOn, .shotTypeOff, .darkFlagOn, .darkFlagOff:
            return true
        default:
            return false
        }
    }

    var body: some View {
        GallerySection(
            number: "C4",
            name: "Chip",
            note: "18 documented renderings, one Chip.Style enum. 04/D3 rows are shown forced-dark."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Variant(row.0) {
                        Chip(label(for: row.1), style: row.1, action: {})
                            .padding(isForcedDark(row.1) ? 6 : 0)
                            .background(
                                isForcedDark(row.1)
                                    ? CypressColor.Dark.bgCamera
                                    : Color.clear
                            )
                            .cypressAppearance(
                                isForcedDark(row.1) ? .forcedDark : .automatic
                            )
                    }
                }
                Variant("leading dot accessory (02 `GPS ±9 m`)") {
                    Chip("GPS ±9 m", style: .meta, leadingDot: CypressColor.gpsDot)
                }
                Variant("domain-typed · Chip.care(_:isOn:) over CareAction") {
                    HStack(spacing: CypressSpacing.gapGrid) {
                        Chip.care(.watered, isOn: true)
                        Chip.care(.mulched, isOn: false)
                    }
                }
                if let evergreen = GallerySample.evergreen,
                   let deciduous = GallerySample.deciduous {
                    Variant("domain-typed · Chip.phenology — evergreen renders no fall-color chip") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: CypressSpacing.gapRows) {
                                Chip.phenology(.fullLeaf, for: evergreen, isOn: true)
                                Chip.phenology(.fallColor, for: evergreen, isOn: false)
                                Text("← evergreen: nothing")
                                    .font(CypressFont.mono10)
                                    .foregroundStyle(CypressColor.textFaint)
                            }
                            HStack(spacing: CypressSpacing.gapRows) {
                                Chip.phenology(.fullLeaf, for: deciduous, isOn: true)
                                Chip.phenology(.fallColor, for: deciduous, isOn: false)
                            }
                            if let unknown = GallerySample.unknownHabit {
                                HStack(spacing: CypressSpacing.gapRows) {
                                    Chip.phenology(.fullLeaf, for: unknown, isOn: true)
                                    Chip.phenology(.fallColor, for: unknown, isOn: false)
                                    Text("← habit unknown: nothing at all")
                                        .font(CypressFont.mono10)
                                        .foregroundStyle(CypressColor.textFaint)
                                }
                            }
                        }
                        .padding(6)
                        .background(CypressColor.Dark.bgCamera)
                        .cypressForcedDark()
                    }
                }
            }
        }
    }
}

// MARK: - C5

private struct GalleryC5: View {
    @State private var status: TreeStatus = .alive
    @State private var method: MeasurementMethod = .tape
    @State private var foliage = "Thinning"

    var body: some View {
        GallerySection(number: "C5", name: "SegmentedControl") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("status · standard 13pt (05) — over TreeStatus") {
                    SegmentedControl.status(selection: $status)
                }
                Variant("foliage · standard (05) — free options") {
                    SegmentedControl(
                        options: ["Full", "Thinning", "Sparse", "Bare"],
                        selection: $foliage,
                        label: { $0 }
                    )
                }
                Variant("method · large 14pt (16) — over MeasurementMethod, required (D7)") {
                    SegmentedControl.method(selection: $method)
                }
                Variant("dark (D3) · selected mint, weight 800") {
                    SegmentedControl.status(selection: $status)
                        .padding(CypressSpacing.gapRows)
                        .background(CypressColor.Dark.bgScreen)
                        .cypressForcedDark()
                }
            }
        }
    }
}

// MARK: - C6 / C7

private struct GalleryC6C7: View {
    var body: some View {
        GallerySection(number: "C6 / C7", name: "PrimaryButton · SecondaryOutlineButton") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("primary · standard (03)") {
                    PrimaryButton("Visit · say hello with a photo", action: {})
                }
                Variant("primary · compact, no shadow (12)") {
                    PrimaryButton("Walk the nine", style: .compact, action: {})
                }
                Variant("primary · large (18)") {
                    PrimaryButton("Next nearest: The Tea Tree · 40 m", style: .large, action: {})
                }
                Variant("primary · camera (04) — New Growth fill, weight 800") {
                    PrimaryButton("Log visit", style: .camera, action: {})
                        .padding(CypressSpacing.gapRows)
                        .background(CypressColor.Dark.bgCameraTray)
                        .cypressForcedDark()
                }
                Variant("primary · dark (D2, D3) — mint on ink, no shadow") {
                    PrimaryButton("Save check-in", action: {})
                        .padding(CypressSpacing.gapRows)
                        .background(CypressColor.Dark.bgScreen)
                        .cypressForcedDark()
                }
                Variant("outline · standard (02, 18)") {
                    SecondaryOutlineButton("None of these? Add this tree", action: {})
                }
                Variant("outline · compact (06)") {
                    SecondaryOutlineButton(
                        "Save a private reminder for yourself",
                        style: .compact,
                        action: {}
                    )
                }
            }
        }
    }
}

// MARK: - C8

private struct GalleryC8: View {
    var body: some View {
        GallerySection(
            number: "C8",
            name: "QuadActionRow",
            note: "NOT SPECIFIED: icons for the four actions — the spec shows text only."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("light (03)") {
                    QuadActionRow(onTap: { _ in })
                }
                Variant("dark (D2)") {
                    QuadActionRow(onTap: { _ in })
                        .background(CypressColor.Dark.bgScreen)
                        .cypressForcedDark()
                }
            }
            .padding(.horizontal, -CypressSpacing.gutterLabel)
        }
    }
}

// MARK: - C9

private struct GalleryC9: View {
    var body: some View {
        GallerySection(number: "C9", name: "ActivityRow") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("photo thumb (03)") {
                    ActivityRow(
                        leading: .photo(CypressGradient.activityVisit),
                        label: "Visit",
                        detail: " · “Fog dripping off the crown”",
                        timestamp: "Oct 12"
                    )
                }
                Variant("care tile · leaf glyph (03)") {
                    ActivityRow(
                        leading: .care,
                        label: "Care",
                        detail: " · watered, mulched",
                        timestamp: "Sep 28"
                    )
                }
                Variant("city-sync tile (19)") {
                    ActivityRow(
                        leading: .sync,
                        label: "City record",
                        detail: " · marked removed · storm damage",
                        timestamp: "May 2026"
                    )
                }
                Variant("vitality swatch thumb (19)") {
                    ActivityRow(
                        leading: .vitality(.poor),
                        label: "Check-in",
                        detail: " · vitality 2 · a steward confirmed the decline",
                        timestamp: "Mar 2026"
                    )
                }
                Variant("dark (D2)") {
                    ActivityRow(
                        leading: .photo(CypressGradient.activityVisitDark),
                        label: "Visit",
                        detail: " · “Fog dripping off the crown”",
                        timestamp: "Oct 12"
                    )
                    .padding(CypressSpacing.gapRows)
                    .background(CypressColor.Dark.bgScreen)
                    .cypressForcedDark()
                }
            }
        }
    }
}

// MARK: - C10

private struct GalleryC10: View {
    private let rows: [(CypressColor.TileAccent, String, String)] = [
        (.bloom, "First bloom of the year", "Red flowering gum on 44th Ave · Jan 22, three neighbors saw it"),
        (.elder, "The elder", "Grandmother Cypress · in the city record since 1898"),
        (.newGrowth, "Newest neighbors", "23 trees planted this spring, mostly ginkgo and tea tree"),
        (.water, "Watered through the dry weeks", "Jun–Aug · five care visits kept it going"),
        (.record, "Seven years on record", "First photo Mar 2019 · six people know this tree"),
    ]

    var body: some View {
        GallerySection(number: "C10", name: "IconTextRow") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapDense) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    IconTextRow(accent: row.0, title: row.1, subtitle: row.2)
                }
            }
        }
    }
}

// MARK: - C11

private struct GalleryC11: View {
    var body: some View {
        GallerySection(
            number: "C11",
            name: "StatCard",
            note: "A measurement value takes a Quantity, so its method badge cannot be dropped (D7)."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("2-up grid (03)") {
                    StatGrid {
                        StatCard(label: "Height", value: .quantity(GallerySample.heightEstimated))
                        StatCard(label: "DBH", value: .quantity(GallerySample.dbhTaped))
                        StatCard(label: "Planted", value: .text("1898"))
                        StatCard(label: "City record", value: .text("SF #114-88"))
                    }
                }
                Variant("city-record value + prose value (14)") {
                    StatGrid {
                        StatCard(label: "DBH", value: .cityRecord("8 cm"))
                        StatCard(label: "Watch for", value: .prose("First-summer thirst"))
                    }
                }
                // NOT SPECIFIED, and the one thing on this screen a designer is being asked to rule
                // on: the empty measurement slot that opens screen 16 (ERRATA E98). Faint rather
                // than ink so it cannot read as a reading, exactly as 16's own empty readout (E77).
                Variant("empty measurement slot · invented (03)") {
                    StatGrid {
                        StatCard(label: "Height", value: .placeholder("Add a reading"))
                        StatCard(label: "DBH", value: .cityRecord("8 cm"))
                    }
                }
                Variant("large variant · mono 17 (07)") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        StatCard(label: "In this inventory", value: .text("1,204"), size: .large)
                        StatCard(label: "Near you", value: .text("61"), size: .large)
                    }
                }
                Variant("dark (D2)") {
                    StatGrid {
                        StatCard(label: "Height", value: .quantity(GallerySample.heightEstimated))
                        StatCard(label: "DBH", value: .quantity(GallerySample.dbhTaped))
                    }
                    .padding(CypressSpacing.gapRows)
                    .background(CypressColor.Dark.bgScreen)
                    .cypressForcedDark()
                }
            }
        }
    }
}

// MARK: - C12

private struct GalleryC12: View {
    var body: some View {
        GallerySection(
            number: "C12",
            name: "MethodBadge",
            note: "Takes Core.Quantity, never a string — D7. `city record` is the one non-Quantity case."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("inline · taped / est. / city record (03, 14)") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        MethodBadge(GallerySample.dbhTaped)
                        MethodBadge(GallerySample.heightEstimated)
                        MethodBadge(.cityRecord)
                    }
                }
                Variant("growth-log · 11pt, `estimated` spelled out (11)") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        MethodBadge(GallerySample.dbhTaped, size: .growthLog)
                        MethodBadge(GallerySample.dbhEstimated, size: .growthLog)
                    }
                }
                Variant("caliper / laser — measured methods outside the drawn table") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        MethodBadge(GallerySample.dbhCaliper)
                        MethodBadge(GallerySample.heightLaser)
                    }
                }
                Variant("MeasuredValue — the only way a number reaches the screen") {
                    HStack(spacing: CypressSpacing.gutter) {
                        MeasuredValue(quantity: GallerySample.dbhTaped)
                        MeasuredValue(quantity: GallerySample.heightEstimated)
                    }
                }
                Variant("dark (D2) — both badges survive the theme switch") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        MethodBadge(GallerySample.dbhTaped)
                        MethodBadge(GallerySample.heightEstimated)
                    }
                    .padding(CypressSpacing.gapRows)
                    .background(CypressColor.Dark.bgScreen)
                    .cypressForcedDark()
                }
            }
        }
    }
}

// MARK: - C13

private struct GalleryC13: View {
    var body: some View {
        GallerySection(number: "C13", name: "StatusBadge") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("THRIVING · compact (01, D1 card) / standard (03, D2)") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        StatusBadge(.thriving, size: .compact)
                        StatusBadge(.thriving)
                    }
                }
                Variant("PLANTED 2024 (14) · REMOVED (19)") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        StatusBadge(.planted(year: 2024))
                        StatusBadge(.removed)
                    }
                }
                Variant("dark THRIVING (D1, D2)") {
                    StatusBadge(.thriving)
                        .padding(CypressSpacing.gapRows)
                        .background(CypressColor.Dark.bgScreen)
                        .cypressForcedDark()
                }
            }
        }
    }
}

// MARK: - C14 / C15

private struct GalleryC14C15: View {
    var body: some View {
        GallerySection(number: "C14 / C15", name: "Callout · OptionalWell") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("green · recognize-it (03)") {
                    Callout(
                        " flat, layered crown; tiny scale-like leaves; lemony scent when crushed.",
                        style: .green,
                        leadIn: "How to recognize it:"
                    )
                }
                Variant("green · lineage, radius 14 (19)") {
                    Callout(
                        " When the city replants this site, the new profile will link back here—the site keeps its lineage.",
                        style: .green,
                        leadIn: "A new tree is coming.",
                        largePadding: true
                    )
                }
                Variant("gradient · seasonal (07)") {
                    Callout(
                        " look for closed gray cones the size of a golf ball ripening in the upper crown.",
                        style: .gradient,
                        leadIn: "In July:"
                    )
                }
                Variant("memorial (19)") {
                    Callout(
                        " This profile is now read-only. Every photo, visit, and check-in stays—a record of the tree that was here.",
                        style: .memorial,
                        leadIn: "Removed by the city, May 2026."
                    )
                }
                Variant("dashed disclosure (06)") {
                    Callout(
                        "Hazards never become public notes. Your reminder stays yours alone, and the city has not been notified until you call.",
                        style: .dashed
                    )
                }
                Variant("green · dark (D2)") {
                    Callout(
                        " flat, layered crown; tiny scale-like leaves.",
                        style: .green,
                        leadIn: "How to recognize it:"
                    )
                    .padding(CypressSpacing.gapRows)
                    .background(CypressColor.Dark.bgScreen)
                    .cypressForcedDark()
                }
                Variant("C15 · OptionalWell, standard (05) and large (09)") {
                    VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                        OptionalWell("Add photos · notes (optional)")
                        OptionalWell("Photo or note (optional)", size: .large)
                    }
                }
            }
        }
    }
}

// MARK: - C16

private struct GalleryC16: View {
    @State private var tab: BottomTabBar.Tab = .map
    @State private var groveTab: BottomTabBar.Tab = .myGrove

    var body: some View {
        GallerySection(number: "C16", name: "BottomTabBar") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("Map active · with backdrop blur (01)") {
                    BottomTabBar(selection: $tab)
                }
                Variant("My Grove active · no blur (08)") {
                    BottomTabBar(selection: $groveTab, usesBlur: false)
                }
                Variant("dark (D1)") {
                    BottomTabBar(selection: $tab)
                        .background(CypressColor.Dark.bgScreen)
                        .cypressForcedDark()
                }
            }
            .padding(.horizontal, -CypressSpacing.gutterLabel)
        }
    }
}

// MARK: - C17

private struct GalleryC17: View {
    var body: some View {
        GallerySection(
            number: "C17",
            name: "BottomSheet",
            note: "Behind 09/10 sits a skeleton of the profile, not the live profile."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("standard · grabber, scrim .44 (09)") {
                    ZStack {
                        ProfileSkeleton(blockCount: 3)
                        BottomSheet {
                            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                                Text("Care log · Monterey Cypress")
                                    .font(CypressFont.sheetTitle)
                                    .foregroundStyle(CypressColor.textInk)
                                Text("Toggle what you did. Thirty seconds, then back to your walk.")
                                    .font(CypressFont.body125)
                                    .foregroundStyle(CypressColor.textFaint)
                                HStack(spacing: CypressSpacing.gapGrid) {
                                    Chip.care(.watered, isOn: true)
                                    Chip.care(.mulched, isOn: true)
                                }
                                OptionalWell("Photo or note (optional)", size: .large)
                                PrimaryButton("Done", action: {})
                            }
                        }
                    }
                    .frame(height: 420)
                    .cypressCornerRadius(CypressRadius.cardMd)
                }
                Variant("account · no grabber, scrim .3, 22/20 padding (15)") {
                    ZStack {
                        StylizedBasemap(detail: .reduced, showsLabels: false)
                        BottomSheet(style: .account) {
                            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                                Text("Keep your three visits")
                                    .font(CypressFont.accountTitle)
                                    .foregroundStyle(CypressColor.textInk)
                                Text("They live on this phone right now.")
                                    .cypressBody135(color: CypressColor.textMuted)
                                PrimaryButton("Continue with Apple", action: {})
                            }
                        }
                    }
                    .frame(height: 300)
                    .cypressCornerRadius(CypressRadius.cardMd)
                }
            }
        }
    }
}

// MARK: - C18 / C19

private struct GalleryC18C19: View {
    private let pins: [(String, MapPin.Kind)] = [
        ("City tree · 18pt", .cityTree),
        ("Needs care · amber", .needsCare),
        ("Community · dashed ring", .community),
        ("Removed · 16pt + bar", .removed),
        ("Cluster · 32pt", .cluster(count: 12)),
        ("Cluster · 30pt", .cluster(count: 7, large: false)),
        ("GPS dot + halo", .gps),
        ("Route done (18)", .routeDone),
        ("Route active (18)", .routeActive),
    ]

    var body: some View {
        GallerySection(
            number: "C18 / C19",
            name: "MapCanvas · MapPin",
            note: "MapCanvas is the styled container; the basemap is a replaceable backdrop — MapKit lands behind it."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("full canvas + overlay layer (01)") {
                    MapCanvas {
                        GeometryReader { proxy in
                            ZStack(alignment: .topLeading) {
                                pin(.cityTree, at: CGPoint(x: 0.26, y: 0.31), in: proxy.size)
                                pin(.needsCare, at: CGPoint(x: 0.61, y: 0.36), in: proxy.size)
                                pin(.community, at: CGPoint(x: 0.51, y: 0.60), in: proxy.size)
                                pin(.removed, at: CGPoint(x: 0.34, y: 0.475), in: proxy.size)
                                pin(.cluster(count: 12), at: CGPoint(x: 0.77, y: 0.22), in: proxy.size)
                                pin(.gps, at: CGPoint(x: 0.46, y: 0.565), in: proxy.size)
                            }
                        }
                    }
                    .frame(height: 260)
                    .cypressCornerRadius(CypressRadius.cardMd)
                }
                Variant("dark canvas (D1)") {
                    MapCanvas {
                        GeometryReader { proxy in
                            ZStack(alignment: .topLeading) {
                                pin(.cityTree, at: CGPoint(x: 0.30, y: 0.35), in: proxy.size)
                                pin(.needsCare, at: CGPoint(x: 0.62, y: 0.40), in: proxy.size)
                                pin(.cluster(count: 7, large: false), at: CGPoint(x: 0.20, y: 0.60), in: proxy.size)
                                pin(.gps, at: CGPoint(x: 0.50, y: 0.62), in: proxy.size)
                            }
                        }
                    }
                    .frame(height: 200)
                    .cypressCornerRadius(CypressRadius.cardMd)
                    .cypressForcedDark()
                }
                Variant("reduced canvas · grid only (15, 18)") {
                    MapCanvas<StylizedBasemap, EmptyView>.reduced { EmptyView() }
                        .frame(height: 120)
                        .cypressCornerRadius(CypressRadius.cardMd)
                }
                Variant("every pin kind · drawn size kept, 44pt hit area") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: CypressSpacing.gutter
                    ) {
                        ForEach(Array(pins.enumerated()), id: \.offset) { _, entry in
                            VStack(spacing: 6) {
                                MapPin(entry.1, action: {})
                                Text(entry.0)
                                    .font(CypressFont.mono10)
                                    .foregroundStyle(CypressColor.textFaint)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, CypressSpacing.gapRows)
                }
            }
        }
    }

    private func pin(_ kind: MapPin.Kind, at position: CGPoint, in size: CGSize) -> some View {
        MapPin(kind, action: {})
            .offset(
                x: size.width * position.x - kind.diameter / 2,
                y: size.height * position.y - kind.diameter / 2
            )
    }
}

// MARK: - C20 / C21

private struct GalleryC20C21: View {
    @State private var query = ""

    var body: some View {
        GallerySection(number: "C20 / C21", name: "SearchBar · LeafGlyph") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("search bar (01)") {
                    SearchBar(text: $query)
                }
                Variant("search bar · dark (D1)") {
                    SearchBar(text: $query)
                        .padding(CypressSpacing.gapRows)
                        .background(CypressColor.Dark.bgMap)
                        .cypressForcedDark()
                }
                Variant("leaf glyph · 16 (tab bar) · 14 (FAB) · 12 (care thumb) · 10 (bullets)") {
                    HStack(alignment: .bottom, spacing: CypressSpacing.gutter) {
                        LeafGlyph(.tabBar)
                        LeafGlyph(.fab, tint: CypressColor.Dark.accentMint)
                        LeafGlyph(.careThumb)
                        LeafGlyph(.bullet, tint: CypressColor.bark)
                    }
                }
            }
        }
    }
}

// MARK: - C22

private struct GalleryC22: View {
    var body: some View {
        GallerySection(number: "C22", name: "ThumbnailGradient") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("the four canonical species sets + the D1 dark card thumb") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: CypressSpacing.gapRows
                    ) {
                        ForEach(CypressGradient.Thumbnail.allCases) { thumbnail in
                            VStack(spacing: 5) {
                                ThumbnailGradient(thumbnail, size: .mapCard, action: {})
                                Text(thumbnail.name)
                                    .font(CypressFont.mono10)
                                    .foregroundStyle(CypressColor.textFaint)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Variant("every drawn size · 76 · 72 · 60 · 58 · 44 · 38 · 34") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        alignment: .leading,
                        spacing: CypressSpacing.gapRows
                    ) {
                        ForEach(ThumbnailGradient<CypressGradientField>.Size.allCases) { size in
                            ThumbnailGradient(.cypress, size: size)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - C23

private struct GalleryC23: View {
    /// 11's DBH series: hollow (estimated) at the first and third points, taped elsewhere.
    private var dbhPoints: [ChartPoint] {
        let ys: [Double] = [0.20, 0.31, 0.42, 0.50, 0.61, 0.69, 0.76, 0.84]
        let methods: [MeasurementMethod] = [
            .estimate, .tape, .estimate, .tape, .tape, .tape, .tape, .tape,
        ]
        let values: [Double] = [47, 50, 53, 55, 58, 60, 62, 64]
        return (0..<8).map { index in
            ChartPoint(
                x: Double(index) / 7,
                y: ys[index],
                quantity: Quantity(
                    value: values[index],
                    unit: .centimeters,
                    method: methods[index]
                )
            )
        }
    }

    var body: some View {
        GallerySection(
            number: "C23",
            name: "ChartCard",
            note: "One polyline per series — estimated and taped points are never connected (D7)."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("line chart (11) · filled = taped, hollow = estimated") {
                    ChartCard(title: "Trunk diameter · DBH", range: "since 2019") {
                        LineChart(
                            points: dbhPoints,
                            latestLabel: "64",
                            baselineLabel: "47 cm",
                            axisLabels: ["2019", "2021", "2023", "2025"]
                        )
                    }
                }
                Variant("legend pills (11)") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        Chip("taped", style: .methodLegendTaped)
                        Chip("estimated", style: .methodLegendEstimated)
                    }
                }
                Variant("bar chart · three series on one scale (13)") {
                    ChartCard(title: "This year at a glance", range: "2026", size: .bars) {
                        VStack(alignment: .leading, spacing: CypressSpacing.gapDense) {
                            ChartSeriesLegend(name: "Photos", total: "41")
                            BarChart(
                                heights: [8, 4, 10, 13, 17, 34, 17, 10, 8, 8, 4, 4],
                                accessibilityLabel: "Photos by month. June is the tallest."
                            )
                            ChartSeriesLegend(
                                name: "Check-ins",
                                total: "18",
                                tint: CypressColor.chartSeriesSecondary
                            )
                            BarChart(
                                heights: [4, 4, 8, 8, 10, 8, 8, 4, 4, 4, 4, 4],
                                accessibilityLabel: "Check-ins by month. May is the tallest.",
                                tint: CypressColor.chartSeriesSecondary
                            )
                            ChartSeriesLegend(
                                name: "Care",
                                total: "9",
                                tint: CypressColor.chartSeriesTertiary
                            )
                            BarChart(
                                heights: [4, 4, 4, 8, 4, 4, 4, 8, 4, 4, 4, 4],
                                accessibilityLabel: "Care by month. April and August only.",
                                tint: CypressColor.chartSeriesTertiary,
                                emptyMonths: [0, 1, 6, 10, 11]
                            )
                            ChartMonthAxis()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - C24 / C25

private struct GalleryC24C25: View {
    @State private var wifiOnly = true
    @State private var wifiOff = false

    var body: some View {
        GallerySection(
            number: "C24 / C25",
            name: "AttentionCard · Toggle",
            note: "Toggle off state is NOT SPECIFIED; border.cool track + leading knob is our choice."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("attention card · standard (12), with its amber section label") {
                    VStack(alignment: .leading, spacing: 6) {
                        AttentionCard<EmptyView>.sectionLabel("Where eyes are needed")
                        AttentionCard {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("9 young trees with no visits since planting")
                                    .font(CypressFont.body145Bold)
                                    .foregroundStyle(CypressColor.textInk)
                                Text("The first two summers decide whether a street tree makes it. All nine are within a 15-minute walk.")
                                    .font(CypressFont.body125)
                                    .foregroundStyle(CypressColor.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                                    .padding(.bottom, 12)
                                PrimaryButton("Walk the nine", style: .compact, action: {})
                            }
                        }
                    }
                }
                Variant("attention card · compact (17)") {
                    AttentionCard(size: .compact) {
                        HStack(spacing: CypressSpacing.Component.iconRowSpacing) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Measurement · The Tea Tree at 46th")
                                    .font(CypressFont.body14)
                                    .foregroundStyle(CypressColor.textInk)
                                Text("DBH 31 cm, tape · upload failed twice")
                                    .font(CypressFont.body125)
                                    .foregroundStyle(CypressColor.textMuted)
                            }
                            Spacer(minLength: 0)
                            Text("retry")
                                .font(CypressFont.mono11Bold)
                                .foregroundStyle(CypressColor.accentAmber)
                        }
                    }
                }
                Variant("toggle · on (17) and off (NOT SPECIFIED)") {
                    HStack(spacing: CypressSpacing.gutter) {
                        CypressToggle(isOn: $wifiOnly, accessibilityLabel: "Sync photos on wifi only")
                        CypressToggle(isOn: $wifiOff, accessibilityLabel: "Sync photos on wifi only")
                    }
                }
            }
        }
    }
}

// MARK: - C26 / C27 / C28

private struct GalleryC26C27C28: View {
    var body: some View {
        GallerySection(number: "C26 / C27 / C28", name: "AvatarStack · ProgressRing · ConfidenceBar") {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                Variant("avatar stack (03) — N · M · J · +3") {
                    HStack(spacing: CypressSpacing.gapRows) {
                        AvatarStack(initials: ["N", "M", "J"], overflow: "+3")
                        Text("Six people know this tree")
                            .font(CypressFont.body13Bold)
                            .foregroundStyle(CypressColor.textBody)
                    }
                }
                Variant("progress ring · 30 % (08)") {
                    HStack(spacing: CypressSpacing.gutter) {
                        ProgressRing(fraction: 0.30, label: "30%")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("12 of 40 species")
                                .font(CypressFont.cardTitleSerif)
                                .foregroundStyle(CypressColor.textInk)
                            Text("you can recognize in the Outer Sunset")
                                .font(CypressFont.body13)
                                .foregroundStyle(CypressColor.textMuted)
                        }
                    }
                }
                Variant("confidence bar · 88 % (02)") {
                    ConfidenceBar(fraction: 0.88)
                }
            }
        }
    }
}

// MARK: - C29 / C30

private struct GalleryC29C30: View {
    var body: some View {
        GallerySection(
            number: "C29 / C30",
            name: "SpeciesTile · WebFactRow",
            note: "C30 is W1-only chrome and is out of scope for iOS (ARCHITECTURE §8) — not built."
        ) {
            SpeciesGrid {
                ForEach(CypressGradient.SpeciesTileArt.allCases) { art in
                    SpeciesTile(content: .known(art), action: {})
                }
                SpeciesTile(content: .locked)
                SpeciesTile(content: .locked)
            }
        }
    }
}

// MARK: - Forced dark

private struct GalleryForcedDark: View {
    @State private var shotType = "Full tree"

    var body: some View {
        GallerySection(
            number: "04 / D1–D3",
            name: "Forced dark",
            note: "Screen 04 and the D screens are dark regardless of the system setting — .cypressForcedDark()."
        ) {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                ZStack(alignment: .bottom) {
                    CypressGradientField(CypressGradient.cameraViewfinder)
                    CypressGradientField(CypressGradient.cameraGhost)
                    VStack(spacing: CypressSpacing.gapRows) {
                        Text("Full tree · match last visit’s angle")
                            .font(CypressFont.body13)
                            .foregroundStyle(CypressColor.shotTypeOffText)
                            .padding(.vertical, CypressSpacing.gapRows)
                            .padding(.horizontal, CypressSpacing.gutter)
                            .background { Capsule().fill(CypressColor.shotTypeOffFill) }
                        HStack(spacing: CypressSpacing.gapRows) {
                            Chip("Full tree", style: .shotTypeOn, action: {})
                            Chip("Trunk", style: .shotTypeOff, action: {})
                            Chip("Leaf close-up", style: .shotTypeOff, action: {})
                        }
                        .padding(.bottom, CypressSpacing.gutter)
                    }
                }
                .frame(height: 220)
                .cypressCornerRadius(CypressRadius.cardMd)
                .cypressForcedDark()
            }
        }
        .padding(.bottom, CypressSpacing.bottomSheet)
    }
}

// MARK: - Previews

#Preview("Components · Light") {
    ComponentGallery()
        .preferredColorScheme(.light)
}

#Preview("Components · Dark") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}
