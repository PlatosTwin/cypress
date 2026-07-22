//
//  TokenGallery.swift
//  Cypress — DesignSystem/Tokens
//
//  A visual contact sheet for every token in docs/distilled/SCREENS.md §1: colors (with the hex
//  pair they resolve from), the type ramp, the radii, and the shadows. This is how the token layer
//  is verified before any screen is built — run the two previews below side by side and compare
//  against SCREENS.md §1.
//
//  The first three sections are the review sheet, and they are first on purpose: SCREENS.md
//  documents dark for three screens, so a majority of the palette's dark values were derived from
//  the documented pairs rather than transcribed. Those sections are exactly the values that were
//  not read off the document — the derived ones to check (ERRATA E8), the five overruled ones to
//  reverse or keep (RULINGS R1, ERRATA E108), the escalated ones to answer — so review costs one
//  screen instead of an audit of the whole palette. Run the Dark preview to review them.
//
//  Not shipped in any screen. It imports nothing outside DesignSystem.
//

import SwiftUI

// MARK: - Row models

private struct Swatch: Identifiable {
    let name: String
    let hex: String
    let color: Color
    var id: String { name }

    init(_ name: String, _ hex: String, _ color: Color) {
        self.name = name
        self.hex = hex
        self.color = color
    }
}

private struct GradientSwatch: Identifiable {
    let name: String
    let hex: String
    let gradient: LinearGradient
    var id: String { name }

    init(_ name: String, _ hex: String, _ gradient: LinearGradient) {
        self.name = name
        self.hex = hex
        self.gradient = gradient
    }
}

private struct TypeSample: Identifiable {
    let name: String
    let spec: String
    let font: Font
    let sample: String
    var id: String { name }

    init(_ name: String, _ spec: String, _ font: Font, _ sample: String) {
        self.name = name
        self.spec = spec
        self.font = font
        self.sample = sample
    }
}

private struct RadiusSample: Identifiable {
    let name: String
    let value: CGFloat
    var id: String { name }

    init(_ name: String, _ value: CGFloat) {
        self.name = name
        self.value = value
    }
}

private struct ShadowSample: Identifiable {
    let name: String
    let css: String
    let style: CypressShadowStyle
    var id: String { name }

    init(_ name: String, _ css: String, _ style: CypressShadowStyle) {
        self.name = name
        self.css = css
        self.style = style
    }
}

// MARK: - Gallery

struct TokenGallery: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                header

                ReviewSection(
                    title: "Derived — check these (ERRATA E8)",
                    blurb: """
                        No dark value for these is written down anywhere. Each one below was \
                        computed from the \(TokenGalleryData.specifiedPairCount) pairs that are, \
                        by fitting the light→dark relationship per role in OKLCh. Nothing here is \
                        a per-token invention, and \(TokenGalleryData.reusedHexCount) of the \
                        \(CypressColor.derivedTokens.count) reuse a hex the designer already \
                        wrote rather than minting one.
                        """,
                    tokens: CypressColor.derivedTokens
                )

                ReviewSection(
                    title: "Overruled — reverse these or keep them (RULINGS R1)",
                    blurb: """
                        Every other row on this screen is a value SCREENS.md never gave. These \
                        five are values it gave and that were changed anyway, because they fail \
                        WCAG AA and the alternative was editing 61 call sites to route around \
                        them. Lightness moved in OKLCh; chroma and hue are where the designer \
                        put them. The hex under each name is what ships, and the line below it \
                        says what was written and what the change bought.
                        """,
                    tokens: CypressColor.overruledTokens
                )

                ReviewSection(
                    title: "Escalated — answer these (ERRATA E8)",
                    blurb: """
                        The transform was run on each of these and rejected, so they are still \
                        light-only and will look light-only after dark. The line under each says \
                        why. These need a decision, not a check.
                        """,
                    tokens: CypressColor.escalatedTokens
                )

                SwatchSection(title: "§1.1 Brand palette", swatches: TokenGalleryData.brand)
                SwatchSection(title: "§1.2 Surfaces", swatches: TokenGalleryData.surfaces)
                SwatchSection(title: "§1.2 Borders", swatches: TokenGalleryData.borders)
                SwatchSection(title: "§1.2 Text", swatches: TokenGalleryData.text)
                SwatchSection(title: "§1.2 Semantic / status", swatches: TokenGalleryData.semantic)
                SwatchSection(title: "Role pairs", swatches: TokenGalleryData.rolePairs)
                SwatchSection(title: "§1.2 Foliage ramp", swatches: TokenGalleryData.foliage)
                gradientsSection
                SwatchSection(title: "§1.2 Forced-dark palette", swatches: TokenGalleryData.dark)

                typeSection
                compoundTypeSection
                radiusSection
                shadowSection
            }
            .padding(.vertical, 24)
        }
        .background(CypressColor.surfaceScreen)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cypress design tokens")
                .font(CypressFont.screenTitleGrove)
                .foregroundStyle(CypressColor.textInk)
            Text("SCREENS.md §1 — colors, type, radii, shadows")
                .font(CypressFont.body135)
                .foregroundStyle(CypressColor.textMuted)
        }
        .cypressLabelGutter()
    }

    // MARK: Gradients

    private var gradientsSection: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            SectionTitle("§1.2 Vitality gradients · linear-gradient(140deg)")
            ForEach(TokenGalleryData.vitality) { item in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                        .fill(item.gradient)
                        .frame(width: 96, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(CypressFont.body13Bold)
                            .foregroundStyle(CypressColor.textInk)
                        Text(item.hex)
                            .font(CypressFont.mono10)
                            .foregroundStyle(CypressColor.textFaint)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                    .fill(CypressColor.calloutGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                            .strokeBorder(CypressColor.calloutGradientBorder, lineWidth: 1)
                    }
                    .frame(width: 96, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gradient callout")
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.textInk)
                    Text("120deg #EAF2E6 → #F6F2DF")
                        .font(CypressFont.mono10)
                        .foregroundStyle(CypressColor.textFaint)
                }
                Spacer(minLength: 0)
            }
        }
        .cypressLabelGutter()
    }

    // MARK: Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("§1.3 Type ramp")
            ForEach(TokenGalleryData.typeSamples) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(CypressFont.mono10)
                            .foregroundStyle(CypressColor.textFaint)
                        Text(item.spec)
                            .font(CypressFont.mono10)
                            .foregroundStyle(CypressColor.textMuted)
                    }
                    Text(item.sample)
                        .font(item.font)
                        .foregroundStyle(CypressColor.textInk)
                        .lineLimit(2)
                }
            }
        }
        .cypressLabelGutter()
    }

    /// Styles that only exist as modifiers, because they carry tracking / case / color.
    private var compoundTypeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("§1.3 Compound styles (font + tracking + case + color)")

            labelled(".cypressMicroLabel()") {
                Text("Recent visits").cypressMicroLabel()
            }
            labelled(".cypressMicroLabel10()") {
                Text("Canopy width").cypressMicroLabel10()
            }
            labelled(".cypressBadge(color:)") {
                Text("Thriving")
                    .cypressBadge(color: CypressColor.thrivingBadgeText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: CypressRadius.badge, style: .continuous)
                            .fill(CypressColor.thrivingBadgeFill)
                    )
            }
            labelled(".cypressMonoSectionLabel()") {
                Text("Foliage through the year").cypressMonoSectionLabel()
            }
            labelled(".cypressMapLabel(color:)") {
                Text("Dolores St").cypressMapLabel(color: CypressColor.textMapLabelStreet)
            }
            labelled(".cypressMonoReadout()") {
                Text("64").cypressMonoReadout()
            }
            labelled(".cypressLatinName()") {
                Text("Hesperocyparis macrocarpa").cypressLatinName()
            }
            labelled(".cypressBody15()") {
                Text("Watered, mulched. Thirty seconds, next tree.").cypressBody15()
            }
            labelled(".cypressBody135()") {
                Text("In July this tree is usually in full leaf.").cypressBody135()
            }
            labelled("CypressFont.monoStat") {
                Text("DBH 64 cm").cypressMonoStat()
            }
        }
        .cypressLabelGutter()
    }

    private func labelled<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(CypressFont.mono10)
                .foregroundStyle(CypressColor.textFaint)
            content()
        }
    }

    // MARK: Radii

    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            SectionTitle("§1.4 Radii")
            ForEach(TokenGalleryData.radii) { item in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: item.value, style: .continuous)
                        .fill(CypressColor.surfaceCard)
                        .overlay {
                            RoundedRectangle(cornerRadius: item.value, style: .continuous)
                                .strokeBorder(CypressColor.borderCool, lineWidth: 1)
                        }
                        .frame(width: 96, height: 52)
                    Text(item.name)
                        .font(CypressFont.body13)
                        .foregroundStyle(CypressColor.textBody)
                    Spacer(minLength: 0)
                    Text("\(Int(item.value))")
                        .font(CypressFont.mono11)
                        .foregroundStyle(CypressColor.textFaint)
                }
            }

            HStack(spacing: 12) {
                CypressSheetShape()
                    .fill(CypressColor.surfaceSheet)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(CypressColor.borderSheetGrabber)
                            .frame(width: 40, height: 5)
                            .padding(.top, 8)
                    }
                    .frame(width: 96, height: 52)
                Text("radius.sheet — 26 26 0 0")
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.textBody)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                CypressLeafGlyph()
                    .fill(CypressColor.canopy)
                    .frame(width: 24, height: 24)
                    .frame(width: 96, height: 52)
                Text("radius.leafGlyph — 50% 0 + rotate(45°)")
                    .font(CypressFont.body13)
                    .foregroundStyle(CypressColor.textBody)
                Spacer(minLength: 0)
            }
        }
        .cypressLabelGutter()
    }

    // MARK: Shadows

    private var shadowSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("§1.5 Shadows · CSS blur ÷ 2 = SwiftUI radius")
            ForEach(TokenGalleryData.shadows) { item in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                        .fill(CypressColor.surfaceCard)
                        .frame(width: 88, height: 52)
                        .cypressShadow(item.style)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(CypressFont.body13Bold)
                            .foregroundStyle(CypressColor.textInk)
                        Text(item.css)
                            .font(CypressFont.mono10)
                            .foregroundStyle(CypressColor.textFaint)
                        Text("radius \(item.style.radius, specifier: "%.1f") · y \(item.style.y, specifier: "%.0f")")
                            .font(CypressFont.mono10)
                            .foregroundStyle(CypressColor.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .cypressLabelGutter()
        .padding(.bottom, CypressSpacing.bottomSheet)
    }
}

// MARK: - Section pieces

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).cypressMicroLabel()
    }
}

/// The ERRATA E8 review sheet. One row per token: the live swatch, the pair it resolves from, and
/// one line saying where the dark value came from — or, for an escalated token, why there is none.
private struct ReviewSection: View {
    let title: String
    let blurb: String
    let tokens: [CypressReviewToken]

    var body: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            SectionTitle("\(title) · \(tokens.count)")
            Text(blurb)
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(tokens) { token in
                    ReviewCell(token: token)
                }
            }
        }
        .cypressLabelGutter()
    }
}

private struct ReviewCell: View {
    let token: CypressReviewToken

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            swatch
            VStack(alignment: .leading, spacing: 1) {
                Text(token.name)
                    .font(CypressFont.body12Bold)
                    .foregroundStyle(CypressColor.textInk)
                Text(hexPair)
                    .font(CypressFont.mono10)
                    .foregroundStyle(CypressColor.textFaint)
                Text(token.basis)
                    .font(CypressFont.body12)
                    .foregroundStyle(CypressColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// A 2px ring in `border.cool` so a derived value that lands near the card is still bounded.
    private var swatch: some View {
        RoundedRectangle(cornerRadius: CypressRadius.thumbXs, style: .continuous)
            .fill(CypressColor.surfaceCard)
            .overlay {
                gradientOrColor
                    .clipShape(
                        RoundedRectangle(cornerRadius: CypressRadius.thumbXs, style: .continuous)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: CypressRadius.thumbXs, style: .continuous)
                    .strokeBorder(CypressColor.borderCool, lineWidth: 1)
            }
            .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var gradientOrColor: some View {
        if let gradient = token.gradient {
            Rectangle().fill(gradient)
        } else {
            Rectangle().fill(token.color)
        }
    }

    private var hexPair: String {
        let light = String(format: "%06X", token.light)
        guard let dark = token.dark else { return "\(light) · light only" }
        return "\(light) ↔ \(String(format: "%06X", dark))"
    }
}

private struct SwatchSection: View {
    let title: String
    let swatches: [Swatch]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
            SectionTitle(title)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(swatches) { swatch in
                    SwatchCell(swatch: swatch)
                }
            }
        }
        .cypressLabelGutter()
    }
}

private struct SwatchCell: View {
    let swatch: Swatch

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: CypressRadius.thumbXs, style: .continuous)
                .fill(swatch.color)
                .overlay {
                    RoundedRectangle(cornerRadius: CypressRadius.thumbXs, style: .continuous)
                        .strokeBorder(CypressColor.borderCool, lineWidth: 1)
                }
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(swatch.name)
                    .font(CypressFont.body12Bold)
                    .foregroundStyle(CypressColor.textInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(swatch.hex)
                    .font(CypressFont.mono10)
                    .foregroundStyle(CypressColor.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Data
//
// Kept out of the view bodies so the type checker never sees a 40-element literal inside a
// `some View`.

private enum TokenGalleryData {

    /// SCREENS.md §1.2's dark table plus the dark values D1–D3 give only in prose, as a set, so
    /// the review blurb can count how many derived values reuse a hex the designer wrote.
    private static let documentedDarkHexes: Set<UInt32> = [
        0x0E1712, 0x101812, 0x141E16, 0x10160F, 0x151D15, 0x18251D, 0x1B241B, 0x1A241A,
        0x1F2E22, 0x27352B, 0x2B3A2C, 0x2A362B, 0x26332A, 0x1C2A1F, 0x14282B, 0x183034,
        0x2B3226, 0x1B3123, 0x274531, 0x232F24, 0x1F3A2C, 0x2E271A,
        0xE4EBE2, 0xD6E0CE, 0xAEBBAB, 0x94A496, 0x5F6F61, 0xB9C7B2, 0xDFE8D6, 0xCFE0D2,
        0x8EC3A5, 0x6FAE8C, 0xD99A4E, 0x6FA8E8, 0x4A5A4C,
        0x5C6B57, 0x557A50, 0x4E7A74, 0x3E6B44, 0x587D50, 0x6E8A5F,
    ]

    /// Documented light/dark pairs — every `CypressColor.dynamic` token.
    static let specifiedPairCount = 62

    /// Derived tokens whose dark value is a hex the designer already wrote.
    static let reusedHexCount = CypressColor.derivedTokens.filter {
        guard let dark = $0.dark else { return false }
        return documentedDarkHexes.contains(dark)
    }.count

    static let brand: [Swatch] = [
        Swatch("cypressDeep", "1D4634", CypressColor.cypressDeep),
        Swatch("canopy", "2F6B4F", CypressColor.canopy),
        Swatch("newGrowth", "4E8F6A", CypressColor.newGrowth),
        Swatch("bark", "7A4F33", CypressColor.bark),
        Swatch("fog", "F5F6EF ↔ 0E1712", CypressColor.fog),
        Swatch("signalAmber", "B4711F ↔ D99A4E", CypressColor.signalAmber),
    ]

    static let surfaces: [Swatch] = [
        Swatch("pageParchment", "EBE8DC", CypressColor.pageParchment),
        Swatch("surfaceScreen", "F5F6EF ↔ 0E1712", CypressColor.surfaceScreen),
        Swatch("surfaceCard", "FFFFFF ↔ 18251D", CypressColor.surfaceCard),
        Swatch("surfaceSheet", "FDFDF8 ↔ 18251D", CypressColor.surfaceSheet),
        Swatch("surfaceWarmPanel", "F7F5EC", CypressColor.surfaceWarmPanel),
        Swatch("surfaceWeb", "FBFBF5", CypressColor.surfaceWeb),
        Swatch("surfaceMapPaper", "E9E5D4 ↔ 141E16", CypressColor.surfaceMapPaper),
        Swatch("surfaceMapGrid", "F7F4E6 ↔ 1C2A1F", CypressColor.surfaceMapGrid),
        Swatch("surfaceMapStreetBand", "FAF7EC ↔ 232F24", CypressColor.surfaceMapStreetBand),
        Swatch("surfaceRouteMap", "E4E9D3 ↔ 141E16", CypressColor.surfaceRouteMap),
        Swatch("surfaceRouteMapGrid", "F4F1E2 ↔ 1C2A1F", CypressColor.surfaceRouteMapGrid),
        Swatch("surfaceEmptyThumb", "FAFBF4 ↔ 18251D", CypressColor.surfaceEmptyThumb),
        Swatch("surfaceSkeleton", "E3E8D9 ↔ 27352B", CypressColor.surfaceSkeleton),
    ]

    static let borders: [Swatch] = [
        Swatch("borderCool", "E3E8D9 ↔ 27352B", CypressColor.borderCool),
        Swatch("borderWarm", "DDD9C9", CypressColor.borderWarm),
        Swatch("borderHairline", "D8D4C4", CypressColor.borderHairline),
        Swatch("borderDashed", "C9D1BC ↔ 353F34", CypressColor.borderDashed),
        Swatch("borderDashedStrong", "C4CEB4 ↔ 364133", CypressColor.borderDashedStrong),
        Swatch("borderSheetGrabber", "DDE2D2 ↔ 2B3A2C", CypressColor.borderSheetGrabber),
        Swatch("borderWebRow", "E9ECDE", CypressColor.borderWebRow),
        Swatch("borderCalloutGreen", "DFE6CD ↔ 27352B", CypressColor.borderCalloutGreen),
        Swatch("borderCalloutGradient", "D9E3C8", CypressColor.borderCalloutGradient),
        Swatch("borderAmberSoft", "EBD3A8 ↔ D99A4E", CypressColor.borderAmberSoft),
        Swatch("borderAmberMid", "D9A05B ↔ D99A4E", CypressColor.borderAmberMid),
        Swatch("borderAmberStrong", "E0B070 ↔ D99A4E", CypressColor.borderAmberStrong),
        Swatch("borderMemorial", "C4C8B8 ↔ 39423A", CypressColor.borderMemorial),
        Swatch("borderAccount", "D8DECB ↔ 2B3A2C", CypressColor.borderAccount),
        Swatch("borderShareCard", "E0DDC9 ↔ 2B3A2C", CypressColor.borderShareCard),
        Swatch("borderRouteMap", "DBE0CB ↔ 2B3A2C", CypressColor.borderRouteMap),
        Swatch("borderPinRing", "1D4634 @14% ↔ 2B3A2C", CypressColor.borderPinRing),
        Swatch("borderGlassSearch", "1D4634 @10% ↔ 2B3A2C", CypressColor.borderGlassSearch),
        Swatch("borderGlassChip", "1D4634 @12% ↔ 2B3A2C", CypressColor.borderGlassChip),
        Swatch("borderGlassBottomBar", "1D4634 @8% ↔ 26332A", CypressColor.borderGlassBottomBar),
    ]

    static let text: [Swatch] = [
        Swatch("textInk", "1C2A21 ↔ E4EBE2", CypressColor.textInk),
        Swatch("textBody", "3C4A3E ↔ AEBBAB", CypressColor.textBody),
        Swatch("textMuted", "535F4C ↔ 94A496", CypressColor.textMuted),
        Swatch("textFaint", "697260 ↔ 7E8F80", CypressColor.textFaint),
        Swatch("textFaintAlt", "5D6855 ↔ 7E8F80", CypressColor.textFaintAlt),
        Swatch("textOnDark", "FFFFFF", CypressColor.textOnDark),
        Swatch("textOnPhoto", "EAF2E6", CypressColor.textOnPhoto),
        Swatch("textOnPhotoSpecies", "F0F5EC", CypressColor.textOnPhotoSpecies),
        Swatch("textOnPhotoMemorial", "EFF1EA", CypressColor.textOnPhotoMemorial),
        Swatch("textOnPhotoWeb", "EFF5EA", CypressColor.textOnPhotoWeb),
        Swatch("textMapLabelStreet", "98A388 ↔ 5C6B57", CypressColor.textMapLabelStreet),
        Swatch("textMapLabelPark", "7A9C64 ↔ 557A50", CypressColor.textMapLabelPark),
        Swatch("textMapLabelOcean", "5F8C84 ↔ 4E7A74", CypressColor.textMapLabelOcean),
    ]

    static let semantic: [Swatch] = [
        Swatch("thrivingBadgeFill", "E2EFE2 ↔ 1F3A2C", CypressColor.thrivingBadgeFill),
        Swatch("thrivingBadgeText", "28623F ↔ 8EC3A5", CypressColor.thrivingBadgeText),
        Swatch("tapedBadgeFill", "E2EFE2 ↔ 1F3A2C", CypressColor.tapedBadgeFill),
        Swatch("tapedBadgeText", "28623F ↔ 8EC3A5", CypressColor.tapedBadgeText),
        Swatch("estimatedBadgeFill", "F1EAD8 ↔ 2E271A", CypressColor.estimatedBadgeFill),
        Swatch("estimatedBadgeText", "836324 ↔ D99A4E", CypressColor.estimatedBadgeText),
        Swatch("cityRecordBadgeFill", "EAF0E2 ↔ 1F3A2C", CypressColor.cityRecordBadgeFill),
        Swatch("cityRecordBadgeText", "41522F ↔ 8EC3A5", CypressColor.cityRecordBadgeText),
        Swatch("plantedBadgeFill", "EAF0E2 ↔ 1F3A2C", CypressColor.plantedBadgeFill),
        Swatch("plantedBadgeText", "41522F ↔ 8EC3A5", CypressColor.plantedBadgeText),
        Swatch("removedBadgeFill", "E4E6DC ↔ 27352B", CypressColor.removedBadgeFill),
        Swatch("removedBadgeText", "5C6555 ↔ 94A496", CypressColor.removedBadgeText),
        Swatch("calloutGreenFill", "EFF3E3 ↔ 1A241A", CypressColor.calloutGreenFill),
        Swatch("calloutGreenBorder", "DFE6CD ↔ 27352B", CypressColor.calloutGreenBorder),
        Swatch("calloutGreenText", "41522F ↔ B9C7B2", CypressColor.calloutGreenText),
        Swatch("calloutGradientBorder", "D9E3C8", CypressColor.calloutGradientBorder),
        Swatch("calloutGradientText", "1C2A21 ↔ E4EBE2", CypressColor.calloutGradientText),
        Swatch("amberPillFill", "F8EFDF ↔ 2E271A", CypressColor.amberPillFill),
        Swatch("amberPillBorder", "EBD3A8 ↔ D99A4E", CypressColor.amberPillBorder),
        Swatch("amberPillText", "8A5A17 ↔ D99A4E", CypressColor.amberPillText),
        Swatch("amberChipSelectedFill", "F8EFDF ↔ 2E271A", CypressColor.amberChipSelectedFill),
        Swatch("amberChipSelectedBorder", "D9A05B ↔ D99A4E", CypressColor.amberChipSelectedBorder),
        Swatch("amberChipSelectedText", "8A5A17 ↔ D99A4E", CypressColor.amberChipSelectedText),
        Swatch("amberAttentionCardFill", "FFFFFF ↔ 18251D", CypressColor.amberAttentionCardFill),
        Swatch("amberAttentionCardBorder", "B8803A ↔ D99A4E", CypressColor.amberAttentionCardBorder),
        Swatch("hazardPanelFill", "F8EFDF ↔ 2E271A", CypressColor.hazardPanelFill),
        Swatch("hazardPanelBorder", "E0B070 ↔ D99A4E", CypressColor.hazardPanelBorder),
        Swatch("hazardPanelText", "6B5122 ↔ BDA680", CypressColor.hazardPanelText),
        Swatch("hazardCTAFill", "A35F12 ↔ D99A4E", CypressColor.hazardCTAFill),
        Swatch("hazardCTAText", "FFFFFF ↔ 0E1712", CypressColor.hazardCTAText),
        Swatch("memorialBannerFill", "EDEEE6 ↔ 27352B", CypressColor.memorialBannerFill),
        Swatch("memorialBannerBorder", "C4C8B8 ↔ 39423A", CypressColor.memorialBannerBorder),
        Swatch("memorialBannerText", "4A5344 ↔ AEBBAB", CypressColor.memorialBannerText),
        Swatch("gpsDot", "3577C9 ↔ 6FA8E8", CypressColor.gpsDot),
        Swatch("gpsDotHalo", "3577C9 @18% ↔ 16%", CypressColor.gpsDotHalo),
        Swatch("pinRingStroke", "FFFFFF ↔ 0E1712", CypressColor.pinRingStroke),
        Swatch("chevronDisclosure", "B4BCA9 ↔ 4A5A4C", CypressColor.chevronDisclosure),
    ]

    static let rolePairs: [Swatch] = [
        Swatch("ctaFill", "1D4634 ↔ 8EC3A5", CypressColor.ctaFill),
        Swatch("ctaLabel", "FFFFFF ↔ 0E1712", CypressColor.ctaLabel),
        Swatch("pinFill", "2F6B4F ↔ 6FAE8C", CypressColor.pinFill),
        Swatch("accentAmber", "B4711F ↔ D99A4E", CypressColor.accentAmber),
    ]

    static let foliage: [Swatch] = [
        Swatch("foliageDensest", "5D9159 ↔ 3E6B44", CypressColor.foliageDensest),
        Swatch("foliageMid", "8FB573 ↔ 587D50", CypressColor.foliageMid),
        Swatch("foliageSparsest", "BCD3A8 ↔ 6E8A5F", CypressColor.foliageSparsest),
    ]

    static let dark: [Swatch] = [
        Swatch("Dark.bgMap", "141E16", CypressColor.Dark.bgMap),
        Swatch("Dark.bgScreen", "0E1712", CypressColor.Dark.bgScreen),
        Swatch("Dark.bgCamera", "10160F", CypressColor.Dark.bgCamera),
        Swatch("Dark.bgCameraTray", "151D15", CypressColor.Dark.bgCameraTray),
        Swatch("Dark.surfaceCard", "18251D", CypressColor.Dark.surfaceCard),
        Swatch("Dark.surfaceCardAlt", "1B241B", CypressColor.Dark.surfaceCardAlt),
        Swatch("Dark.surfaceCallout", "1A241A", CypressColor.Dark.surfaceCallout),
        Swatch("Dark.surfaceThumb", "1F2E22", CypressColor.Dark.surfaceThumb),
        Swatch("Dark.border", "27352B", CypressColor.Dark.border),
        Swatch("Dark.borderAlt", "2B3A2C", CypressColor.Dark.borderAlt),
        Swatch("Dark.borderCamera", "2A362B", CypressColor.Dark.borderCamera),
        Swatch("Dark.textPrimary", "E4EBE2", CypressColor.Dark.textPrimary),
        Swatch("Dark.textStrong", "D6E0CE", CypressColor.Dark.textStrong),
        Swatch("Dark.textSecondary", "AEBBAB", CypressColor.Dark.textSecondary),
        Swatch("Dark.textMuted", "94A496", CypressColor.Dark.textMuted),
        Swatch("Dark.textFaint", "7E8F80", CypressColor.Dark.textFaint),
        Swatch("Dark.accentMint", "8EC3A5", CypressColor.Dark.accentMint),
        Swatch("Dark.accentPin", "6FAE8C", CypressColor.Dark.accentPin),
        Swatch("Dark.accentAmber", "D99A4E", CypressColor.Dark.accentAmber),
        Swatch("Dark.accentAmberBg", "2E271A", CypressColor.Dark.accentAmberBg),
        Swatch("Dark.accentGPS", "6FA8E8", CypressColor.Dark.accentGPS),
        Swatch("Dark.accentGPSHalo", "6FA8E8 @16%", CypressColor.Dark.accentGPSHalo),
        Swatch("Dark.mapGrid", "1C2A1F", CypressColor.Dark.mapGrid),
        Swatch("Dark.mapBeach", "2B3226", CypressColor.Dark.mapBeach),
        Swatch("Dark.mapPark", "1B3123", CypressColor.Dark.mapPark),
        Swatch("Dark.mapParkRing", "274531", CypressColor.Dark.mapParkRing),
        Swatch("Dark.mapStreet", "232F24", CypressColor.Dark.mapStreet),
        Swatch("Dark.mapStreetRing", "2B3A2C", CypressColor.Dark.mapStreetRing),
        Swatch("Dark.mapLabelStreet", "5C6B57", CypressColor.Dark.mapLabelStreet),
        Swatch("Dark.mapLabelPark", "557A50", CypressColor.Dark.mapLabelPark),
        Swatch("Dark.mapLabelOcean", "4E7A74", CypressColor.Dark.mapLabelOcean),
        Swatch("Dark.pinRing", "0E1712", CypressColor.Dark.pinRing),
        Swatch("Dark.thrivingBadgeFill", "1F3A2C", CypressColor.Dark.thrivingBadgeFill),
        Swatch("Dark.thrivingBadgeText", "8EC3A5", CypressColor.Dark.thrivingBadgeText),
        Swatch("Dark.foliageDensest", "3E6B44", CypressColor.Dark.foliageDensest),
        Swatch("Dark.foliageMid", "587D50", CypressColor.Dark.foliageMid),
        Swatch("Dark.foliageSparsest", "6E8A5F", CypressColor.Dark.foliageSparsest),
    ]

    static let vitality: [GradientSwatch] = CypressColor.Vitality.allCases.map { level in
        GradientSwatch(
            "\(level.rawValue) · \(level.name)",
            String(format: "#%06X → #%06X", level.lightStops.0, level.lightStops.1),
            level.gradient
        )
    }

    // MARK: Type

    static let typeSamples: [TypeSample] = serifSamples + sansSamples + monoSamples

    private static let serifSamples: [TypeSample] = [
        TypeSample("screen.title.grove", "Serif 26/600", CypressFont.screenTitleGrove, "My Grove"),
        TypeSample("tree.name.hero", "Serif 27/600", CypressFont.treeNameHero, "Monterey Cypress"),
        TypeSample("species.hero", "Serif 25/600", CypressFont.speciesHero, "Ginkgo biloba"),
        TypeSample("tree.name.coldstart", "Serif 25/600", CypressFont.treeNameColdStart, "Unnamed tree"),
        TypeSample("screen.title", "Serif 22/600", CypressFont.screenTitle, "What tree is this?"),
        TypeSample("success.title", "Serif 22/600", CypressFont.successTitle, "Logged."),
        TypeSample("account.title", "Serif 21/600", CypressFont.accountTitle, "Keep your record"),
        TypeSample("sheet.title", "Serif 20/600", CypressFont.sheetTitle, "Add a photo"),
        TypeSample("hazard.title", "Serif 20/600", CypressFont.hazardTitle, "This looks urgent"),
        TypeSample("card.title.serif", "Serif 19/600", CypressFont.cardTitleSerif, "Monterey Cypress"),
        TypeSample("list.name.serif", "Serif 17.5/600", CypressFont.listNameSerif, "Coast Live Oak"),
        TypeSample("share.name", "Serif 17/600", CypressFont.shareName, "Coast Live Oak"),
        TypeSample("latin.name", "Serif italic 15/400", CypressFont.latinName, "Quercus agrifolia"),
        TypeSample("latin.name @14.5", "Serif italic 14.5/400", CypressFont.latinName145, "Quercus agrifolia"),
        TypeSample("latin.name @14", "Serif italic 14/400", CypressFont.latinName14, "Quercus agrifolia"),
        TypeSample("latin.name @13.5", "Serif italic 13.5/400", CypressFont.latinName135, "Quercus agrifolia"),
        TypeSample("latin.name @13", "Serif italic 13/400", CypressFont.latinName13, "Quercus agrifolia"),
    ]

    private static let sansSamples: [TypeSample] = [
        TypeSample("body.16", "Sans 16/700", CypressFont.body16, "Log this visit"),
        TypeSample("body.15.5", "Sans 15.5/700", CypressFont.body155, "What tree is this?"),
        TypeSample("body.15.5 extrabold", "Sans 15.5/800", CypressFont.body155ExtraBold, "What tree is this?"),
        TypeSample("body.15", "Sans 15/400", CypressFont.body15, "Watered, mulched. Thirty seconds, next tree."),
        TypeSample("body.15 bold", "Sans 15/700", CypressFont.body15Bold, "Save"),
        TypeSample("body.14.5", "Sans 14.5/400", CypressFont.body145, "Search trees or streets"),
        TypeSample("body.14.5 semibold", "Sans 14.5/600→700", CypressFont.body145SemiBold, "Growth over time"),
        TypeSample("body.14.5 bold", "Sans 14.5/700", CypressFont.body145Bold, "Watered"),
        TypeSample("body.14", "Sans 14/700", CypressFont.body14, "Dolores Park"),
        TypeSample("body.13.5", "Sans 13.5/400", CypressFont.body135, "In July this tree is usually in full leaf."),
        TypeSample("body.13", "Sans 13/400", CypressFont.body13, "Needs water"),
        TypeSample("body.13 bold", "Sans 13/700", CypressFont.body13Bold, "Needs water"),
        TypeSample("body.12.5", "Sans 12.5/400", CypressFont.body125, "Within 200 m"),
        TypeSample("body.12", "Sans 12/400", CypressFont.body12, "Last visited Summer 2026"),
        TypeSample("body.12 semibold", "Sans 12/600→700", CypressFont.body12SemiBold, "Add photo"),
        TypeSample("body.12 bold", "Sans 12/700", CypressFont.body12Bold, "Add photo"),
    ]

    private static let monoSamples: [TypeSample] = [
        TypeSample("mono.13", "Mono 13/400", CypressFont.mono13, "DBH 64 cm · taped · SF #114-88"),
        TypeSample("mono.12", "Mono 12/400", CypressFont.mono12, "180 m · 62%"),
        TypeSample("mono.11", "Mono 11/400", CypressFont.mono11, "2026-07-21 09:14"),
        TypeSample("mono.11 semibold", "Mono 11/600", CypressFont.mono11SemiBold, "QUEUED"),
        TypeSample("mono.10.5", "Mono 10.5/400", CypressFont.mono105, "cypress.app/sf/tree/9f3a"),
        TypeSample("mono.10", "Mono 10/400", CypressFont.mono10, "J F M A M J J A S O N D"),
        TypeSample("mono.keypad", "Mono 19/600", CypressFont.monoKeypad, "7 8 9 ⌫"),
        TypeSample("mono.stat", "Mono 14.5/600", CypressFont.monoStat, "64 cm"),
        TypeSample("mono.statBig", "Mono 17/600", CypressFont.monoStatBig, "1,284"),
    ]

    // MARK: Radii

    static let radii: [RadiusSample] = [
        RadiusSample("radius.pill (999)", CypressRadius.pill),
        RadiusSample("radius.device (48)", CypressRadius.device),
        RadiusSample("radius.card.lg (18)", CypressRadius.cardLg),
        RadiusSample("radius.card.md (16)", CypressRadius.cardMd),
        RadiusSample("radius.card.sm (14)", CypressRadius.cardSm),
        RadiusSample("radius.control (12)", CypressRadius.control),
        RadiusSample("radius.thumb.lg (16)", CypressRadius.thumbLg),
        RadiusSample("radius.thumb.md (14)", CypressRadius.thumbMd),
        RadiusSample("radius.thumb.sm (11)", CypressRadius.thumbSm),
        RadiusSample("radius.thumb.sm alt (10)", CypressRadius.thumbSmAlt),
        RadiusSample("radius.thumb.sm xs (8)", CypressRadius.thumbXs),
        RadiusSample("radius.badge (6)", CypressRadius.badge),
        RadiusSample("radius.foliageCell (5)", CypressRadius.foliageCell),
        RadiusSample("radius.methodBadge (4)", CypressRadius.methodBadge),
        RadiusSample("radius.web.button (12)", CypressRadius.webButton),
        RadiusSample("radius.web.signIn (10)", CypressRadius.webSignIn),
    ]

    // MARK: Shadows

    static let shadows: [ShadowSample] = lightShadows + darkShadows

    private static let lightShadows: [ShadowSample] = [
        ShadowSample("shadow.rest", "0 1px 3px rgba(25,40,28,.05)", CypressShadow.rest),
        ShadowSample("shadow.restSoft", "0 1px 4px rgba(25,40,28,.08)", CypressShadow.restSoft),
        ShadowSample("shadow.selected", "0 6px 20px rgba(47,107,79,.16)", CypressShadow.selected),
        ShadowSample("shadow.selectedSm", "0 4px 12px rgba(47,107,79,.16)", CypressShadow.selectedSm),
        ShadowSample("shadow.primary", "0 4px 14px rgba(20,50,30,.28)", CypressShadow.primary),
        ShadowSample("shadow.fab", "0 8px 24px rgba(20,50,30,.4)", CypressShadow.fab),
        ShadowSample("shadow.chipActive", "0 2px 8px rgba(20,50,30,.25)", CypressShadow.chipActive),
        ShadowSample("shadow.searchBar", "0 4px 16px rgba(20,40,26,.1)", CypressShadow.searchBar),
        ShadowSample("shadow.bottomCard", "0 10px 30px rgba(20,40,26,.16)", CypressShadow.bottomCard),
        ShadowSample("shadow.sheet", "0 -12px 40px rgba(10,20,14,.32)", CypressShadow.sheet),
        ShadowSample("shadow.shareCard", "0 3px 12px rgba(25,40,28,.09)", CypressShadow.shareCard),
        ShadowSample("shadow.amberCard", "0 3px 12px rgba(180,113,31,.1)", CypressShadow.amberCard),
        ShadowSample("shadow.hazard", "0 4px 14px rgba(163,95,18,.3)", CypressShadow.hazard),
        ShadowSample("shadow.pin", "0 2px 6px rgba(20,40,26,.35)", CypressShadow.pin),
        ShadowSample("shadow.pinMuted", "0 2px 6px rgba(20,40,26,.2)", CypressShadow.pinMuted),
        ShadowSample("shadow.pinMuted strong", "0 2px 6px rgba(20,40,26,.25)", CypressShadow.pinMutedStrong),
        ShadowSample("shadow.cluster", "0 2px 8px rgba(20,40,26,.35)", CypressShadow.cluster),
        ShadowSample("shadow.heroButton", "0 2px 8px rgba(16,32,22,.25)", CypressShadow.heroButton),
        ShadowSample("shadow.toggleKnob", "0 1px 3px rgba(0,0,0,.2)", CypressShadow.toggleKnob),
    ]

    private static let darkShadows: [ShadowSample] = [
        ShadowSample("shadow.dark.sm", "0 2px 6px rgba(0,0,0,.5)", CypressShadow.Dark.sm),
        ShadowSample("shadow.dark.md", "0 2px 8px rgba(0,0,0,.5)", CypressShadow.Dark.md),
        ShadowSample("shadow.dark.lg", "0 4px 16px rgba(0,0,0,.4)", CypressShadow.Dark.lg),
        ShadowSample("shadow.dark.xl", "0 10px 30px rgba(0,0,0,.45)", CypressShadow.Dark.xl),
        ShadowSample("shadow.dark.fab", "0 8px 24px rgba(0,0,0,.5)", CypressShadow.Dark.fab),
    ]
}

// MARK: - Previews

#Preview("Tokens · Light") {
    TokenGallery()
        .preferredColorScheme(.light)
}

#Preview("Tokens · Dark") {
    TokenGallery()
        .preferredColorScheme(.dark)
}
