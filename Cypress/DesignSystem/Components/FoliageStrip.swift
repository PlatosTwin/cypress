//
//  FoliageStrip.swift
//  Cypress — DesignSystem/Components
//
//  C3 · `FoliageStrip` — SCREENS.md §2. The 12-cell season strip on 03, 10 (share card) and D2.
//
//  ── D5 lives here, not at the call site ───────────────────────────────────────────────────
//  DECISIONS D5 / ARCHITECTURE §5.5: "Evergreen species never get fall-color chips or autumn strip
//  colors — the chip set derives from `species.leafRetention`." The strip therefore takes the
//  species' `LeafRetention` as a required parameter and applies the rule itself: an evergreen's
//  months are clamped so no cell can render the leaf-off treatment. A caller cannot forget.
//
//  The parameter is optional because "nobody has established this species' habit" is a real state
//  (ERRATA E9), and it clamps exactly as an evergreen does. The asymmetry is deliberate: drawing a
//  bare month is a claim about the tree, leaving it out is not.
//
//  The 3-step ramp of §1.2 is the *only* color vocabulary SCREENS.md gives this component — there
//  is no autumn hue anywhere in the spec. So the enforcement is a clamp, not a color swap, and no
//  fourth color is invented here (SCREENS.md ground rule: nothing is invented).
//

import SwiftUI

struct FoliageStrip: View {

    /// How much foliage the tree carries in one month.
    ///
    /// `bare` is only meaningful for a species that drops its leaves; for an evergreen the
    /// initializer raises it to `thin` (D5). SCREENS.md specifies no distinct color for a bare
    /// month, so `bare` renders as the sparsest ramp step for every species — see the file header.
    enum Density: String, CaseIterable, Identifiable {
        case full
        case partial
        case thin
        case bare

        var id: String { rawValue }

        var level: CypressColor.FoliageLevel {
            switch self {
            case .full: return .densest
            case .partial: return .mid
            case .thin, .bare: return .sparsest
            }
        }
    }

    /// 03/D2 profile strip vs. the 10 share-card strip (12 × 11pt squares, `gap:2.5px`, radius 3).
    enum Variant {
        case profile
        case shareCard

        var height: CGFloat? {
            switch self {
            case .profile: return CypressSpacing.Component.foliageCellHeight
            case .shareCard: return CypressSpacing.Component.foliageShareCell
            }
        }

        var gap: CGFloat {
            switch self {
            case .profile: return CypressSpacing.Component.foliageCellGap
            case .shareCard: return CypressSpacing.Component.foliageShareGap
            }
        }

        var radius: CGFloat {
            switch self {
            case .profile: return CypressRadius.foliageCell
            case .shareCard: return CypressRadius.foliageCellShare
            }
        }
    }

    /// `Foliage through the year` — the mono eyebrow above the strip on 03/D2.
    static let eyebrowText = "Foliage through the year"
    /// The month row letters, verbatim.
    static let monthLetters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    /// The canonical Grandmother Cypress sequence of §2, J→D, as densities.
    /// `5D9159, 5D9159, 8FB573, BCD3A8, BCD3A8, 8FB573, 8FB573, 8FB573, 5D9159 ×4`.
    static let grandmotherCypress: [Density] = [
        .full, .full, .partial, .thin, .thin, .partial,
        .partial, .partial, .full, .full, .full, .full,
    ]

    private let densities: [Density]
    private let variant: Variant
    private let showsMonthRow: Bool
    private let showsEyebrow: Bool

    /// - Parameters:
    ///   - leafRetention: the species attribute that drives every phenology surface (D5), or `nil`
    ///     when no source states it (ERRATA E9).
    ///   - densities: twelve months, January first. Short arrays are padded with `.full`; long ones
    ///     are truncated, because a 12-cell strip is the component's contract.
    init(
        leafRetention: LeafRetention?,
        densities: [Density],
        variant: Variant = .profile,
        showsMonthRow: Bool = true,
        showsEyebrow: Bool = true
    ) {
        self.densities = Self.enforcingD5(densities, leafRetention: leafRetention)
        self.variant = variant
        self.showsMonthRow = showsMonthRow
        self.showsEyebrow = showsEyebrow
    }

    /// Convenience over a concrete species — the preferred call.
    init(
        species: Species,
        densities: [Density],
        variant: Variant = .profile,
        showsMonthRow: Bool = true,
        showsEyebrow: Bool = true
    ) {
        self.init(
            leafRetention: species.leafRetention,
            densities: densities,
            variant: variant,
            showsMonthRow: showsMonthRow,
            showsEyebrow: showsEyebrow
        )
    }

    /// D5, applied once: an evergreen is never bare, in any month. Neither is a species whose
    /// habit is unknown — the strip may only draw what somebody established (ERRATA E9).
    static func enforcingD5(_ input: [Density], leafRetention: LeafRetention?) -> [Density] {
        var months = Array(input.prefix(12))
        if months.count < 12 {
            months.append(contentsOf: Array(repeating: Density.full, count: 12 - months.count))
        }
        switch leafRetention {
        case .deciduous?, .semiDeciduous?:
            return months
        case .evergreen?, nil:
            return months.map { $0 == .bare ? .thin : $0 }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsEyebrow, variant == .profile {
                Text(Self.eyebrowText)
                    .cypressMonoSectionLabel()
                    .padding(.bottom, CypressSpacing.Component.foliageEyebrowBottom)
            }

            HStack(spacing: variant.gap) {
                ForEach(Array(densities.enumerated()), id: \.offset) { _, density in
                    RoundedRectangle(cornerRadius: variant.radius, style: .continuous)
                        .fill(CypressColor.foliage(density.level))
                        .frame(maxWidth: .infinity)
                        .frame(height: variant.height)
                }
            }
            // The strip is one element saying what the year looks like, not twelve saying what
            // each square looks like. Two reasons, and the second is the one that was broken.
            //
            // A `.accessibilityLabel` on a bare `RoundedRectangle` never reaches VoiceOver — a
            // `Shape` is not an accessibility element, so there is nothing for the label to attach
            // to. Twelve cells labeled that way are twelve *silent* cells, which reads on device
            // exactly like a strip that was never labeled at all.
            //
            // And even working, twelve stops is the wrong shape for the information. The strip is
            // a visual encoding of one sentence — when this tree carries leaves — and a spoken
            // equivalent has to say that sentence, not describe the drawing square by square.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)

            if showsMonthRow, variant == .profile {
                HStack(spacing: CypressSpacing.Component.foliageMonthGap) {
                    ForEach(Array(Self.monthLetters.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(CypressFont.body85SemiBold)
                            .foregroundStyle(CypressColor.textFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, CypressSpacing.Component.foliageMonthTop)
                .accessibilityHidden(true)
                // Twelve letters that have to stay lined up with the twelve cells above them.
                // See `cypressTypographicFurniture()`.
                .cypressTypographicFurniture()
            }
        }
    }

    static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// What the strip says out loud. See the note beside `.accessibilityElement` in `body`.
    var accessibilityLabel: String {
        Self.accessibilityLabel(for: densities)
    }

    /// The twelve cells, collapsed to their runs: `full, full, partial` becomes "full canopy
    /// January to February, then partial canopy in March".
    ///
    /// Runs rather than months because the strip's meaning is the *shape* of the year — where it
    /// changes and how long each state lasts. A listener who has to hold twelve month-and-state
    /// pairs in their head to notice that a tree thins in April has been given the drawing rather
    /// than the information in it.
    static func accessibilityLabel(for densities: [Density]) -> String {
        guard !densities.isEmpty else { return eyebrowText }

        var runs: [(density: Density, start: Int, end: Int)] = []
        for (index, density) in densities.enumerated() {
            if var last = runs.last, last.density == density {
                last.end = index
                runs[runs.count - 1] = last
            } else {
                runs.append((density, index, index))
            }
        }

        let phrases = runs.map { run -> String in
            let span = run.start == run.end
                ? monthNames[run.start]
                : "\(monthNames[run.start]) to \(monthNames[run.end])"
            return "\(run.density.spokenName) \(span)"
        }
        return "\(eyebrowText): " + phrases.joined(separator: ", ") + "."
    }
}

extension FoliageStrip.Density {
    /// How a ramp step is said. The visual vocabulary is three greens; the spoken one is the thing
    /// the greens stand for, which is how much leaf the tree is carrying.
    var spokenName: String {
        switch self {
        case .full: return "full canopy"
        case .partial: return "partial canopy"
        case .thin: return "thin canopy"
        case .bare: return "bare"
        }
    }
}
