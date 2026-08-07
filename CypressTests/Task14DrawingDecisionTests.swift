//
//  Task14DrawingDecisionTests.swift
//  CypressTests
//
//  The two drawing decisions task #14's items 3 and 4 made at a **call site** rather than in a
//  token, pinned as values.
//
//  Why they need their own guards at all: `ContrastTests` measures token *pairs*, and both of these
//  changes leave every token exactly where it was. Item 4 swaps which color 17 draws its state word
//  in; item 3 swaps which drawing screen 12's vacant row uses. A contrast pin cannot see either —
//  it would pass unchanged with both reverted — and SwiftUI builds no render tree a test can walk,
//  so the rendering itself is verified by looking at the screens (ARCHITECTURE §7) and the decision
//  is verified here. Same shape as `QuadActionRow.rows` and `StatGrid.columnCount`.
//

import SwiftUI
import Testing
import UIKit
@testable import Cypress

@Suite("Task #14 · the two decisions made at a call site")
struct Task14DrawingDecisionTests {

    private static let light = UITraitCollection(userInterfaceStyle: .light)
    private static let dark = UITraitCollection(userInterfaceStyle: .dark)

    private static func hex(_ color: Color, _ traits: UITraitCollection) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        let byte: (CGFloat) -> UInt32 = { UInt32(min(max(($0 * 255).rounded(), 0), 255)) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    // MARK: - #249 · 17's terminal state word

    /// `retry` and `stopped` are mono 11 pt **bold** on `surface.card`. `accentAmber` `#B4711F`
    /// reads **3.95:1** there, against the 4.5 floor that size earns — WCAG's large-text exemption
    /// starts at 18 pt regular or 14 pt bold, and 11 pt bold is neither.
    ///
    /// The fix is this call site and not the token, so this is where it is pinned: `accentAmber` is
    /// Signal Amber, a reserved brand hue that also draws the amber map pin, and retinting it to
    /// clear a text floor on screen 17 would move a mark on screen 01.
    @Test("17 draws its terminal state word in the reason line's amber, not in Signal Amber")
    func terminalStateWordIsNotSignalAmber() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            #expect(
                Self.hex(OutboxQueueRow.terminalStateWordColor, traits)
                    == Self.hex(CypressColor.amberChipSelectedText, traits),
                """
                in \(appearance) 17's state word resolves to \
                #\(String(format: "%06X", Self.hex(OutboxQueueRow.terminalStateWordColor, traits))), \
                not to amberChipSelectedText. #249: `accentAmber` on this pair is 3.95:1 at mono \
                11 pt bold, below the 4.5 floor that size earns.
                """
            )
        }
        #expect(
            Self.hex(OutboxQueueRow.terminalStateWordColor, Self.light) != 0xB4711F,
            """
            17's state word is Signal Amber `#B4711F` again — the exact 3.95:1 pair #249 reported. \
            The closure is a call site: the reason line directly beneath this word already uses \
            `amberChipSelectedText`, which reads 5.91:1 on the card.
            """
        )
    }

    // MARK: - Item 3 · screen 12's vacant-site tile

    /// ROADMAP §1 settles what a vacant site is — "a distinct planting-site state, **not** a variant
    /// of the tree profile" — and R7/E119/E123 gave the state a drawn vocabulary the map pin, 14's
    /// empty photo well, the site screen and `LocationPrompt` all speak. The almanac tile was the
    /// one member still drawn as a living tree's radial, differing from the five beside it only in
    /// color.
    ///
    /// Exactly one accent takes the well. The five living accents are asserted too, because the
    /// opposite mistake is the same category error: a tile that says a tree is a hole in the ground.
    @Test("only the vacant-site accent is drawn as the empty well")
    func onlyTheVacantAccentDrawsTheWell() {
        #expect(IconTextRow.drawsEmptyWell(.vacantSite))
        for accent in CypressColor.TileAccent.allCases where accent != .vacantSite {
            #expect(
                !IconTextRow.drawsEmptyWell(accent),
                """
                the `\(accent.rawValue)` tile is drawn as an empty planting basin. Only a vacant \
                site is one; the other five are living trees and keep their own accent gradient.
                """
            )
        }
        // …and the enum has not quietly grown a sixth living accent that nobody classified.
        #expect(
            CypressColor.TileAccent.allCases.filter(IconTextRow.drawsEmptyWell).count == 1,
            "more than one C10 accent draws the empty well"
        )
    }

    /// The well is drawn from the two tokens the vacant-site family already owns and mints nothing —
    /// R7's discipline, and the reason item 3 costs no new hue. Pinned so a future edit cannot
    /// "improve" the tile by reaching for a value outside the family.
    @Test("the vacant tile's two colors are still the empty photo well's own")
    func theWellReusesTheFamilysTokens() {
        for (appearance, traits) in [("light", Self.light), ("dark", Self.dark)] {
            #expect(
                Self.hex(CypressColor.TileAccent.vacantSite.accent, traits)
                    == Self.hex(CypressColor.surfaceEmptyThumb, traits),
                "in \(appearance) the vacant tile's fill left surfaceEmptyThumb"
            )
            #expect(
                Self.hex(CypressColor.TileAccent.vacantSite.base, traits)
                    == Self.hex(CypressColor.borderDashedStrong, traits),
                "in \(appearance) the vacant tile's edge left borderDashedStrong"
            )
        }
    }
}
