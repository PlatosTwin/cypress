//
//  SheetDismissRuleTests.swift
//  CypressTests
//
//  Ticket #175: the arithmetic that decides whether a released drag ends a `.standard` sheet
//  or springs it back. The gesture itself is pinned from outside by `SheetExitUITests`; this
//  suite pins the decision, which is where a threshold regression would actually live.
//

import Foundation
import Testing
@testable import Cypress

@Suite("Sheet dismiss rule · ticket #175")
struct SheetDismissRuleTests {

    /// The card 09/10 present on the reference canvas: 874pt display minus the 62pt strip.
    private let cardHeight: CGFloat = 812

    // MARK: - Slow drags: distance decides

    @Test func slowDragPastAQuarterOfTheCardDismisses() {
        // Slow release: the predicted end is where the finger already is.
        let translation = cardHeight * SheetDismissRule.dragFraction + 1
        #expect(SheetDismissRule.shouldDismiss(
            translation: translation,
            predictedTranslation: translation,
            cardHeight: cardHeight
        ))
    }

    @Test func slowDragShortOfAQuarterSpringsBack() {
        let translation = cardHeight * SheetDismissRule.dragFraction - 1
        #expect(!SheetDismissRule.shouldDismiss(
            translation: translation,
            predictedTranslation: translation,
            cardHeight: cardHeight
        ))
    }

    // MARK: - Flicks: the predicted end folds velocity in

    @Test func shortFlickWhosePredictionCrossesHalfDismisses() {
        // The finger only moved 60pt, but fast: the gesture was headed past half the card.
        #expect(SheetDismissRule.shouldDismiss(
            translation: 60,
            predictedTranslation: cardHeight * SheetDismissRule.flickFraction + 1,
            cardHeight: cardHeight
        ))
    }

    @Test func shortSlowDragWhosePredictionFallsShortSpringsBack() {
        #expect(!SheetDismissRule.shouldDismiss(
            translation: 60,
            predictedTranslation: cardHeight * SheetDismissRule.flickFraction - 1,
            cardHeight: cardHeight
        ))
    }

    // MARK: - Refusals

    @Test func upwardDragNeverDismisses() {
        // Even with a wild predicted end: a sheet is dismissed downward or not at all.
        #expect(!SheetDismissRule.shouldDismiss(
            translation: -40,
            predictedTranslation: cardHeight,
            cardHeight: cardHeight
        ))
    }

    @Test func unmeasuredCardNeverDismisses() {
        // Height 0 is the card before its first geometry pass — a gesture judged against
        // nothing must refuse, not divide.
        #expect(!SheetDismissRule.shouldDismiss(
            translation: 400,
            predictedTranslation: 800,
            cardHeight: 0
        ))
    }

    // MARK: - The offset under the finger

    @Test func cardFollowsADownwardDragOneForOne() {
        #expect(SheetDismissRule.cardOffset(forTranslation: 137) == 137)
    }

    @Test func cardRefusesToRiseAboveItsRestingPlace() {
        #expect(SheetDismissRule.cardOffset(forTranslation: -50) == 0)
    }
}
