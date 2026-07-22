//
//  MapTreeCard.swift
//  Cypress — Features/Map
//
//  SCREENS.md 01 §14 — the card that appears when a pin is selected.
//
//      [58pt thumb] Ginkgo  THRIVING              ›
//                   Maidenhair tree · 6 m NE · visited 3 d ago
//
//  Every clause of the meta line is dropped rather than faked when the fact behind it is missing:
//  no species row, no fix, or no visit each simply removes its own clause. Nothing here invents
//  botany (BUILD-PLAN §15) and nothing counts a user's actions (D1) — "visited 3 d ago" is
//  recency, which is the phrasing D1 permits.
//

import SwiftUI

struct MapTreeCard: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let subject: MapCardSubject
    /// The user's fix, when there is one. Its absence is the "map without location" state, and it
    /// costs the card exactly one clause.
    let userCoordinate: Coordinate?
    var now: Date = .now
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MapLayout.cardSpacing) {
                ThumbnailGradient(subject.thumbnail, size: .mapCard)

                VStack(alignment: .leading, spacing: MapLayout.cardMetaTop) {
                    HStack(spacing: MapLayout.cardTitleBadgeGap) {
                        Text(subject.title)
                            .font(CypressFont.listNameSerif)
                            .foregroundStyle(CypressColor.textInk)
                            // One line at the mock's size, two once the type is large enough that
                            // one will not hold a street-tree name. A truncated name is the one
                            // thing this card exists to give — 01's caption is "tap any pin" and
                            // the answer to the tap is the name.
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        if let badge = subject.badge {
                            StatusBadge(badge, size: .compact)
                        }
                    }
                    if let meta {
                        Text(meta)
                            .font(CypressFont.body13)
                            .foregroundStyle(CypressColor.textMuted)
                            .lineLimit(1)
                    }
                }
                // Without this the row hands its slack to the `Spacer` and truncates the name
                // instead — "Southern Mag…" where the whole width was free.
                .layoutPriority(1)

                Spacer(minLength: 0)

                // §14 gives the chevron `#B4BCA9` (dark: `#4A5A4C`), which §1.2 had no row for.
                // It is a real gap rather than a one-card special case — every tappable card in the
                // app wants the same disclosure grey — so it is now `chevronDisclosure`, named for
                // the role, and this feature reads it like any other token (ARCHITECTURE §6).
                CypressChevron(direction: .trailing)
                    .stroke(
                        CypressColor.chevronDisclosure,
                        style: StrokeStyle(
                            lineWidth: MapLayout.chevronStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: MapLayout.chevronWidth, height: MapLayout.chevronHeight)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, MapLayout.cardPaddingV)
            .padding(.horizontal, MapLayout.cardPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
                    .fill(CypressColor.surfaceCard)
            }
            .cypressBorder(CypressColor.borderPinRing, radius: CypressRadius.cardLg)
            .cypressShadow(light: CypressShadow.bottomCard, dark: nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subject.title)
        .accessibilityHint("Opens this tree's profile")
    }

    /// `Maidenhair tree · 6 m NE · visited 3 d ago`, minus whatever is unknown.
    private var meta: String? {
        var clauses: [String] = []
        if let latin = subject.scientificName { clauses.append(latin) }
        if let userCoordinate {
            let metres = userCoordinate.distance(to: subject.pin.coordinate)
            let bearing = CompassPoint.from(userCoordinate, to: subject.pin.coordinate)
            clauses.append("\(Int(metres.rounded())) m \(bearing)")
        }
        if let visited = subject.lastVisitedAt {
            clauses.append("visited \(MapRelativeTime.string(from: visited, to: now))")
        }
        guard !clauses.isEmpty else { return nil }
        // The mock's separator is a spaced middle dot; the no-spaces rule is about em dashes
        // (ARCHITECTURE §5.7).
        return clauses.joined(separator: " · ")
    }
}

// MARK: - Relative time

/// `3 d ago`, in the mock's abbreviated-with-a-space form.
///
/// `RelativeDateTimeFormatter`'s abbreviated style writes `3d ago`; the drawn card writes `3 d ago`
/// and the unit is part of the design's mono-ish rhythm, so the string is assembled rather than
/// borrowed. Dates in prose still read "Summer 2026" elsewhere (ARCHITECTURE §5.7) — this is a
/// meta line, not prose.
enum MapRelativeTime {
    static func string(from date: Date, to now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 1 { return "just now" }
        if hours < 1 { return "\(Int(minutes)) min ago" }
        if days < 1 { return "\(Int(hours)) h ago" }
        if days < 31 { return "\(Int(days)) d ago" }
        if days < 365 { return "\(Int(days / 30)) mo ago" }
        return "\(Int(days / 365)) y ago"
    }
}
