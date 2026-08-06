//
//  DesignProposalVariant.swift
//  Cypress — App
//
//  ⚠️ THROWAWAY. A CAMERA RIG, NOT A SHIPPING CHANGE.
//
//  This file exists only so the design proposals in `docs/design-proposals/2026-08-06-task14.md`
//  can be PHOTOGRAPHED in the real app instead of described. It is `#if DEBUG`, it is switched by
//  an environment variable nothing but the shot harness sets, and the branch it lives on
//  (`design/14-proposals`) is not meant to merge. When a proposal is picked, it is implemented
//  properly in the token layer and this file is deleted.
//
//  Everything here is deliberately rough: no tests, no registry rows, no gallery entries, and the
//  hexes are written inline rather than added to `CypressColor`, precisely so that nobody mistakes
//  it for the real change.
//

import SwiftUI

enum DesignProposalVariant {

    static let environmentKey = "CYPRESS_DESIGN"

    /// Whatever the harness asked for, lowercased; `""` means "draw what ships".
    static let current: String = (ProcessInfo.processInfo.environment[environmentKey] ?? "")
        .lowercased()

    static func isOn(_ name: String) -> Bool { current == name }

    // MARK: - Item 1 · screen 17's dark amber

    /// The dark amber ladder, lightness-only in OKLCh from `dark.accent.amber` `#D99A4E`
    /// (chroma held to ±0.0004, hue to ±0.35°). Light is untouched in every variant.
    ///
    ///  - boundary `#A2670D` — 3.39 on the dark card, matching light's own 3.39
    ///  - control  `#C18436` — 5.01 on the dark card
    ///  - mark     `#D99A4E` — 6.57, where E8's derivation already put it
    private static let boundaryDark: UInt32 = 0xA2670D
    private static let controlDark: UInt32 = 0xC18436

    /// C24's border on 17's terminal row.
    static var attentionCardBorder: Color? {
        switch current {
        case "17a", "17b": return CypressColor.dynamic(light: 0xB8803A, dark: boundaryDark)
        default: return nil
        }
    }

    /// The header pill's border, and the amber pill border generally.
    static var amberPillBorder: Color? {
        switch current {
        case "17a", "17b": return CypressColor.dynamic(light: 0xEBD3A8, dark: boundaryDark)
        default: return nil
        }
    }

    /// The `retry` / `stopped` state word — a control.
    static var stateWordAmber: Color? {
        switch current {
        case "17a": return CypressColor.dynamic(light: 0xB4711F, dark: controlDark)
        default: return nil
        }
    }

    // MARK: - Item 1 · screen 16's readout

    /// 56 pt of mono over `surface.screen`.
    ///  - `16a` — lightness-only dim of `text.ink` dark to light's own 13.77 (`#DBE1D9`)
    ///  - `16b` — the documented `text.body` dark rung `#AEBBAB`, 9.13
    static var readoutInk: Color? {
        switch current {
        case "16a": return CypressColor.dynamic(light: 0x1C2A21, dark: 0xDBE1D9)
        case "16b": return CypressColor.dynamic(light: 0x1C2A21, dark: 0xAEBBAB)
        default: return nil
        }
    }

    // MARK: - Item 2 · screen 10's share card

    enum ShareCardLayout { case shipped, fullWidthLink, indentedLink, wideStripAndLink }

    static var shareCardLayout: ShareCardLayout {
        switch current {
        case "10a": return .fullWidthLink
        case "10b": return .indentedLink
        case "10c": return .wideStripAndLink
        default: return .shipped
        }
    }

    // MARK: - Item 3 · the vacant-site tile

    enum VacantTile { case shipped, dashedWell, hollowRing }

    static var vacantTile: VacantTile {
        switch current {
        case "12a": return .dashedWell
        case "12b": return .hollowRing
        default: return .shipped
        }
    }
}
