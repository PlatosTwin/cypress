//
//  TreePhotosFilterTests.swift
//  CypressTests
//
//  Screen 20's subject filter (task #154): the browser gains segmented access to the three
//  framings, and the narrowing must be a view of the timeline rather than a different claim about
//  the tree — the hero, the empty sentence and the segments' own names are the facts pinned here.
//

#if DEBUG
import Foundation
import Testing
@testable import Cypress

@MainActor
@Suite("Screen 20 · the subject filter")
struct TreePhotosFilterTests {

    private static let treeID = UUID(uuidString: "9F3A0000-0000-4000-8000-000000000154")!

    private static func photo(_ shotType: ShotType, daysAgo: Int) -> Photo {
        Photo(
            treeID: treeID,
            shotType: shotType,
            capturedAt: Date(timeIntervalSince1970: 1_780_000_000 - Double(daysAgo) * 86_400)
        )
    }

    /// A timeline holding every framing plus an `.other` row (a care photo's shape).
    private static func model() -> TreePhotosModel {
        TreePhotosModel(
            treeID: treeID,
            photos: [
                photo(.fullTree, daysAgo: 1),
                photo(.trunk, daysAgo: 2),
                photo(.leaf, daysAgo: 3),
                photo(.other, daysAgo: 4),
                photo(.fullTree, daysAgo: 5),
            ]
        )
    }

    @Test("the browser opens on the whole timeline, every framing in it")
    func opensUnfiltered() {
        let model = Self.model()
        #expect(model.subjectFilter == nil)
        #expect(model.filteredPhotos == model.photos)
        // The premise task #154 arrived with — a browser narrowed to `.fullTree` — is asserted
        // false as a fact about the default state: trunk, leaf and other rows are all drawn.
        #expect(Set(model.filteredPhotos.map(\.shotType)) == Set([.fullTree, .trunk, .leaf, .other]))
    }

    @Test("each segment narrows the list to its framing and nothing else")
    func segmentsNarrow() {
        let model = Self.model()
        for subject in [ShotType.fullTree, .trunk, .leaf] {
            model.subjectFilter = subject
            #expect(!model.filteredPhotos.isEmpty, "\(subject.rawValue) vanished from its own segment")
            #expect(
                model.filteredPhotos.allSatisfy { $0.shotType == subject },
                "the \(subject.rawValue) segment shows another framing"
            )
        }
        model.subjectFilter = nil
        #expect(model.filteredPhotos.count == 5, "coming back to All lost rows")
    }

    @Test("the hero is a fact about the tree, and the filter cannot move it")
    func theHeroIgnoresTheFilter() {
        let model = Self.model()
        let hero = model.heroID
        #expect(hero != nil)
        for subject in [ShotType.fullTree, .trunk, .leaf] {
            model.subjectFilter = subject
            #expect(model.heroID == hero, "narrowing to \(subject.rawValue) changed which photo leads the page")
        }
    }

    @Test("the segments are the whole timeline plus the three framings 04 offers — no segment for .other")
    func theSegments() {
        #expect(TreePhotosPresentation.subjectSegments == [nil, .fullTree, .trunk, .leaf])
        // The segment's word is the caption's word, read off the same function rather than
        // re-spelled (R30's rule: the copy names the control by reading the control's own label).
        for segment in TreePhotosPresentation.subjectSegments.compactMap({ $0 }) {
            #expect(
                TreePhotosPresentation.segmentLabel(segment) == TreePhotosPresentation.subject(segment)
            )
        }
        #expect(!TreePhotosPresentation.segmentLabel(nil).isEmpty)
    }

    @Test("an empty slice of a photographed tree gets its own sentence, and it names the framing")
    func theEmptySliceSentence() {
        let model = TreePhotosModel(treeID: Self.treeID, photos: [Self.photo(.fullTree, daysAgo: 1)])
        model.subjectFilter = .trunk
        #expect(model.filteredPhotos.isEmpty)
        #expect(model.filterHasNoPhotos)
        // Not the tree-wide empty state: the tree has photographs.
        #expect(!model.isEmpty)

        // The sentence carries the framing's own caption word — the fact, read off `subject(_:)`,
        // not a phrasing this test remembers.
        for subject in [ShotType.fullTree, .trunk, .leaf] {
            #expect(
                TreePhotosPresentation.emptyFilteredText(subject)
                    .lowercased()
                    .contains(TreePhotosPresentation.subject(subject).lowercased())
            )
        }

        // And a tree with no photographs at all is the tree-wide empty state, not the filter's.
        let bare = TreePhotosModel(treeID: Self.treeID, photos: [])
        bare.subjectFilter = .trunk
        #expect(!bare.filterHasNoPhotos)
        #expect(bare.isEmpty)
    }
}
#endif
