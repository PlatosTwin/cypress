//
//  StatCard.swift
//  Cypress — DesignSystem/Components
//
//  C11 · `StatCard` — SCREENS.md §2. The 2-up stat grid on 03, 14, 19 and D2, and the large
//  count cards on 07.
//
//  A card whose value is a measurement takes a `Quantity` and renders it through `MeasuredValue`,
//  so the method badge rides along automatically (D7). The plain-string initializer exists for the
//  values that are not measurements — `SF #114-88`, `Sidewalk cut`, `1898`.
//

import SwiftUI

struct StatCard: View {

    /// `padding:9px 12px`, value mono 14.5 — or 07's `padding:10px 13px`, value mono 17.
    enum Size {
        case standard
        case large

        var paddingV: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.statPaddingV
            case .large: return CypressSpacing.Component.statPaddingVLarge
            }
        }

        var paddingH: CGFloat {
            switch self {
            case .standard: return CypressSpacing.Component.statPaddingH
            case .large: return CypressSpacing.Component.statPaddingHLarge
            }
        }

        var valueFont: Font {
            switch self {
            case .standard: return CypressFont.monoStat
            case .large: return CypressFont.monoStatBig
            }
        }
    }

    /// What sits under the label.
    enum Value {
        /// A measurement. Always rendered with its method badge (D7).
        case quantity(Quantity)
        /// A city-record measurement — a range or a single number the city published, never
        /// measured by a person. Carries the `city record` badge.
        case cityRecord(String)
        /// A value that is not a measurement: `SF #114-88`, `1898`, `1,204`. Mono, no badge.
        case text(String)
        /// 14's `Watch for` row — **13px/700 sans, not mono**, per §2.
        case prose(String)
        /// A card whose fact the record does not carry yet, standing open for one.
        ///
        /// **NOT SPECIFIED.** SCREENS.md draws C11 with a value in every card. The empty
        /// measurement slot on screen 03 needs a value slot that cannot be mistaken for a reading,
        /// and screen 16 already answered the same question the same way: its empty readout draws
        /// `MeasureCopy.readoutPlaceholder` in `text.faint` rather than `text.ink`, because a plain
        /// `0` in ink reads as a measurement of zero (ERRATA E77). Same geometry, same mono ramp,
        /// the faint colour carrying the difference. See ERRATA (E98).
        case placeholder(String)
    }

    let label: String
    let value: Value
    var size: Size = .standard

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).cypressMicroLabel10()
            valueView
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, size.paddingV)
        .padding(.horizontal, size.paddingH)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.surfaceCard)
        }
        .cypressBorder(CypressColor.borderCool, radius: CypressRadius.control)
        // One card, one stop (ERRATA E118). A stat is a caption and its value, and left alone each
        // was its own element: screen 03's grid read "DBH", then "30–35 cm", then "from the city
        // record" as three unrelated fragments, with the number severed from the word that says what
        // it measures. The card beside it that *is* interactive already read as one thing, because a
        // `Button` forms an accessibility element out of its content — so two cards drawn identically
        // behaved differently, and the difference was invisible to everyone who could see them.
        //
        // `.combine` rather than `.ignore`: the value is not decoration to be dropped, it is the
        // point. Combining concatenates the descendants into one label — "DBH, 30–35 cm, from the
        // city record" — which is what the interactive card was already doing.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueView: some View {
        switch value {
        case let .quantity(quantity):
            MeasuredValue(quantity: quantity, font: size.valueFont)
        case let .cityRecord(text):
            cityRecordValue(text)
        case let .text(text):
            Text(text)
                .font(size.valueFont)
                .foregroundStyle(CypressColor.textInk)
        case let .prose(text):
            Text(text)
                .font(CypressFont.body13Bold)
                .foregroundStyle(CypressColor.textInk)
                .padding(.top, 1)
        case let .placeholder(text):
            Text(text)
                .font(size.valueFont)
                .foregroundStyle(CypressColor.textFaint)
        }
    }

    /// A city value and its badge, side by side where they fit and stacked where they do not.
    ///
    /// ── Why this stopped being one `HStack` (ERRATA E145) ─────────────────────────────────────
    /// Until §9b this case held one shape of value: `30–35 cm`, a DBH bucket, six characters. Screen
    /// 03's city section put whole strings in it — `DPW Maintained`, `Landscaping`, `Friends of the
    /// Urban Forest` — inside a half-width grid cell, beside a badge that is `.fixedSize()` and
    /// therefore never yields. Two things went wrong and both were only visible on a rendered screen:
    /// the badge parked itself *between* two lines of the value it qualifies, so a card read
    /// "Prune · city record · Opt Out"; and a single long word with nowhere to wrap broke mid-word,
    /// as `Landscapin / g`.
    ///
    /// `ViewThatFits` measures the row's ideal width — the value unwrapped, plus the badge — and
    /// takes the stacked form when that does not fit. A six-character bucket is unaffected and still
    /// draws exactly as SCREENS.md 14 draws it; a long value gets the card's full width and its badge
    /// underneath. `.lastTextBaseline` on the row is the other half: with a value that wraps to two
    /// lines but still fits beside the badge, the badge belongs on the last line rather than
    /// halfway up.
    ///
    /// **No `minimumScaleFactor` and no truncation**, deliberately. Both would make the city's own
    /// string harder to read in order to protect a layout, and this section exists to show that
    /// string.
    @ViewBuilder
    private func cityRecordValue(_ text: String) -> some View {
        let value = Text(text)
            .font(size.valueFont)
            .foregroundStyle(CypressColor.textInk)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                value
                MethodBadge(.cityRecord)
            }
            VStack(alignment: .leading, spacing: 3) {
                value.fixedSize(horizontal: false, vertical: true)
                MethodBadge(.cityRecord)
            }
        }
    }
}

/// C11's `grid-template-columns:1fr 1fr; gap:8px`.
struct StatGrid<Content: View>: View {
    @ViewBuilder var content: Content

    private let columns = [
        GridItem(.flexible(), spacing: CypressSpacing.Component.statGridGap),
        GridItem(.flexible(), spacing: CypressSpacing.Component.statGridGap),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: CypressSpacing.Component.statGridGap) {
            content
        }
    }
}
