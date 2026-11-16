//
//  LicenseAcceptanceShots.swift
//  CypressTests
//
//  The You tab's Account section in the four states "Share my tree records" adds or changes, at the
//  default text size and at the largest accessibility size: declined (the row shows), the
//  confirmation, the failure line, and agreed (the row is gone).
//
//  It follows `ScreenSweepShots`: every capture is rendered and judged by `ShotBlankGuard` on every
//  run, and PNGs are written only when `CYPRESS_SHOT_DIR` is set
//  (`export TEST_RUNNER_CYPRESS_SHOT_DIR=<dir>` before `Tools/run_tests.sh`).
//

#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import Cypress

@MainActor
@Suite("Share my tree records · the Account section, photographed")
struct LicenseAcceptanceShots {

    static let declined = AccountLinkRecord(provider: "apple", licenseVersion: nil)
    static let agreed = AccountLinkRecord(provider: "apple", licenseVersion: LicenseConsent.currentVersion)

    static let sizes: [(suffix: String, size: DynamicTypeSize, height: CGFloat)] = [
        ("default", .large, ScreenSweepShots.height),
        ("ax5", .accessibility5, 2_000),
    ]

    /// The section alone, top-aligned on the screen's own background, as the You tab draws it.
    static func section(link: AccountLinkRecord, failed: Bool = false) -> some View {
        VStack(spacing: 0) {
            AccountSection(isSignedIn: true, link: link, licenseAcceptanceFailed: failed)
            Spacer(minLength: 0)
        }
    }

    @Test("declined, failed and agreed render at the default size and at AX5")
    func states() async {
        for (suffix, size, height) in Self.sizes {
            for (name, link, failed) in [
                ("declined", Self.declined, false),
                ("failed", Self.declined, true),
                ("agreed", Self.agreed, false),
            ] {
                let image = await ScreenSweepShots.capture(
                    "share-records-\(name)-\(suffix)",
                    size: size,
                    scheme: .light,
                    viewportHeight: height
                ) {
                    Self.section(link: link, failed: failed)
                }
                #expect(image != nil, "share-records-\(name)-\(suffix) did not render")
            }
        }
    }

    /// Every non-empty `UILabel` text under `view`, depth first.
    static func labelTexts(in view: UIView) -> [String] {
        var texts: [String] = []
        if let label = view as? UILabel, let text = label.text, !text.isEmpty { texts.append(text) }
        for child in view.subviews { texts += labelTexts(in: child) }
        return texts
    }

    /// The confirmation, raised without a tap.
    ///
    /// `ScreenSweepShots.capture` draws the hosting controller's own view, and an alert is a
    /// presented controller that is not inside that view. So this waits for the presentation to
    /// land and draws the presented view over the section.
    @Test("the confirmation renders at the default size and at AX5")
    func confirmation() async throws {
        for (suffix, size, _) in Self.sizes {
            let name = "share-records-confirm-\(suffix)"
            let width = ScreenSweepShots.width
            let height = ScreenSweepShots.height
            let host = UIHostingController(
                rootView: AnyView(
                    Self.section(link: Self.declined)
                        .modifier(ShareRecordsConfirmation(isPresented: .constant(true), onShare: {}))
                        .environment(\.dynamicTypeSize, size)
                        .frame(width: width, height: height)
                        .background(CypressColor.surfaceScreen)
                )
            )
            host.overrideUserInterfaceStyle = .light
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            let window = UIWindow(frame: CGRect(x: -2_000, y: 0, width: width, height: height))
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.isHidden = false
            window.layoutIfNeeded()

            for _ in 0..<300 {
                if host.presentedViewController != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(host.presentedViewController != nil, "\(name): the alert was never presented")
            // Let the presentation animation finish before drawing.
            try await Task.sleep(for: .milliseconds(800))

            // The alert's words, read from its labels. The drawing below is for a person to look
            // at, and an off-screen capture may drop the alert's material; the labels are the fact.
            let presented = host.presentedViewController?.view
            let words = presented.map(Self.labelTexts) ?? []
            for expected in [
                AccountCopy.shareRecordsConfirmTitle,
                AccountCopy.shareRecordsConfirmMessage,
                AccountCopy.shareRecordsConfirmAction,
                AccountCopy.shareRecordsConfirmCancel,
            ] {
                #expect(words.contains(expected), "\(name): the alert does not show \"\(expected)\"; it shows \(words)")
            }

            // The section first, then the presented alert's own view over it. Drawing the window
            // alone came back blank. **This picture is not faithful on iOS 26**: the alert's glass
            // background, its dimming and its message do not draw off-screen (`layer.render` was
            // tried too and misplaced them). The label check above is the evidence for the words;
            // this image only shows the title and the two buttons over the section.
            let image = UIGraphicsImageRenderer(bounds: frame).image { _ in
                host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
                presented?.drawHierarchy(in: presented?.frame ?? frame, afterScreenUpdates: true)
            }
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil

            #expect(!ShotBlankGuard.verdict(for: image).isBlank, "\(name) was blank")
            if let directory = ScreenSweepShots.shotDirectory, let data = image.pngData() {
                #expect(ShotBlankGuard.write(data, to: directory.appendingPathComponent("\(name).png")))
            }
        }
    }
}
#endif
