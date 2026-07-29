#if DEBUG
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// SCRATCH — delete before merge.
@MainActor
@Suite("scratch · diagnostic")
struct ScratchDiagnostic {

    @Test("numbers")
    func numbers() async throws {
        let available: CGFloat = 393 - VisitMetrics.Camera.trayPadding * 2
        let species = VisitCameraSessionTests.londonPlane
        let tags = VisitPhenologyVocabulary.tags(for: species)
        print("DIAG tags=\(tags.map { PhenologyTagLabel.text(for: $0) })")

        for tag in tags {
            let chip = Chip(PhenologyTagLabel.text(for: tag), style: .phenologyOff, action: {})
            let inf = await VisitCameraSessionTests.naturalSize(chip)
            let wide = await VisitCameraSessionTests.measure(chip, at: .large, width: 2_000)
            print("DIAG chip \(PhenologyTagLabel.text(for: tag)) inf=\(inf) wide2000=\(wide)")
        }

        let row = await VisitCameraSessionTests.measure(
            VisitPhenologyChips(species: species, tags: tags), at: .large, width: available
        )
        print("DIAG row@\(available) = \(row)")

        let well = await VisitCameraSessionTests.measure(
            VisitAddTreePhotoWell { Color.clear }, at: .large, width: 361
        )
        print("DIAG well@361 = \(well) ratio=\(well.width / well.height)")

        // Where does the AX5 scroll view actually sit?
        let hosted = try await VisitCameraSessionTests.host(
            VisitPreviewFixtures.camera(), at: .accessibility5, in: CGSize(width: 393, height: 852)
        )
        defer { hosted.dismiss() }
        if let scroll = VisitCameraSessionTests.controlsScrollView(in: hosted.root) {
            let inRoot = scroll.convert(scroll.bounds, to: hosted.root)
            print("DIAG scroll frame=\(scroll.frame) bounds=\(scroll.bounds) inRoot=\(inRoot) content=\(scroll.contentSize) super=\(String(describing: scroll.superview))")
        } else {
            print("DIAG no scroll view")
        }
    }
}
#endif
