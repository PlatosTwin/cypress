//
//  SheetDismissRule.swift
//  Cypress — DesignSystem/Components
//
//  When a downward drag on a `.standard` bottom sheet dismisses it, and when it springs back
//  (ticket #175, RULINGS R42).
//
//  Pure math, separated from `BottomSheet` so the decision is testable without a gesture
//  recognizer: `DragGesture` hands the view a translation and a predicted end translation, and
//  everything after that is arithmetic.
//
//  ── The two thresholds ─────────────────────────────────────────────────────────────────────
//  A slow, deliberate drag commits at a quarter of the card's height: far enough that a stray
//  brush of the handle never dismisses, near enough that nobody has to drag a full-height card
//  halfway down an 874pt display to leave. A flick commits earlier, on where the finger was
//  *going*: `predictedEndTranslation` already folds the gesture's velocity into a distance, so
//  "fast" needs no second unit — a flick is a drag whose predicted end crosses half the card.
//  Both numbers are **NOT SPECIFIED** anywhere; the mocks are static HTML and draw no gesture.
//  They are chosen against the system sheet's feel and recorded in RULINGS R42 §1, which states
//  both fractions in the same terms this file implements them in.
//

import Foundation

enum SheetDismissRule {

    /// A slow drag dismisses once the finger has traveled this fraction of the card's height.
    static let dragFraction: CGFloat = 0.25

    /// A flick dismisses once the *predicted* end of the gesture — translation with velocity
    /// folded in — crosses this fraction of the card's height.
    static let flickFraction: CGFloat = 0.5

    /// Whether a finished drag ends the sheet.
    ///
    /// - Parameters:
    ///   - translation: the gesture's vertical translation at release; positive is downward.
    ///   - predictedTranslation: `predictedEndTranslation.height` — where the gesture was headed,
    ///     which is how velocity participates.
    ///   - cardHeight: the sheet card's current height. Zero or negative (a card that has not
    ///     been measured yet) never dismisses: a gesture judged against nothing is a coin toss.
    /// - Returns: `true` to dismiss, `false` to spring back.
    static func shouldDismiss(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        cardHeight: CGFloat
    ) -> Bool {
        guard cardHeight > 0, translation > 0 else { return false }
        if translation >= cardHeight * dragFraction { return true }
        return predictedTranslation >= cardHeight * flickFraction
    }

    /// The card's offset while the finger holds it: it follows a downward drag one-for-one and
    /// refuses to rise above its resting place — a sheet already at full height has nowhere
    /// further up to go, and an upward slide would tear the card off the display bottom.
    static func cardOffset(forTranslation translation: CGFloat) -> CGFloat {
        max(0, translation)
    }
}
