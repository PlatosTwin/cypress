import Foundation
import Testing
import UIKit
@testable import Cypress

/// What the app bundle must actually contain.
///
/// These two failures have both already happened here, and neither one crashed. The seed was built
/// into `Fixtures/` where the app could not reach it, so `SeedDatabase.urlInBundle()` returned nil
/// and the map came up empty. The fonts fell back to San Francisco, which looks close enough to
/// right that you can miss it on a screenshot.
///
/// A missing resource is the failure mode that a running app is worst at reporting, because
/// everything still launches. So it gets pinned here instead.
@Suite("Bundle contract")
struct BundleContractTests {

    // MARK: - The seed

    @Test("the seeded inventory ships inside the app bundle")
    func seedIsInTheBundle() throws {
        let url = try #require(
            SeedDatabase.urlInBundle(),
            """
            \(SeedDatabase.resourceName).\(SeedDatabase.resourceExtension) is not in the app bundle. \
            It is a build product: run `python3 Tools/build_seed.py` and copy the result to \
            Cypress/Resources/. Both copies are gitignored, so a fresh clone starts without it.
            """
        )

        #expect(FileManager.default.fileExists(atPath: url.path))

        // Sized rather than exact: the seed is regenerated whenever the species content changes, and
        // a byte-count assertion would fail on every legitimate rebuild. What is worth catching is a
        // zero-byte or truncated copy, which is what a failed build step leaves behind.
        let bytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(bytes > 50_000_000, "the seed is \(bytes) bytes — that is a truncated copy, not 195,309 trees")
    }

    // MARK: - The fonts

    /// Read from Info.plist rather than hardcoded. A hardcoded list would keep passing after someone
    /// adds a weight and forgets to ship the file, which is the whole failure being tested for.
    private var declaredFontFiles: [String] {
        Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String] ?? []
    }

    @Test("every font declared in UIAppFonts is actually in the bundle")
    func declaredFontsExist() throws {
        #expect(!declaredFontFiles.isEmpty, "UIAppFonts is empty or missing from Info.plist")

        for file in declaredFontFiles {
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            #expect(
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts") != nil
                    || Bundle.main.url(forResource: name, withExtension: ext) != nil,
                "\(file) is declared in UIAppFonts but is not in the bundle"
            )
        }
    }

    @Test("the app renders in Cypress's own faces, not in a substitute")
    func facesResolve() {
        // UIFont substitutes silently: ask for a family that is not installed and you get San
        // Francisco back with no error and a screen that looks nearly right. So the check is on the
        // family list, which does not lie.
        let families = Set(UIFont.familyNames)
        for family in ["Source Serif 4", "Alegreya Sans", "Spline Sans Mono"] {
            #expect(
                families.contains(family),
                "\(family) is not registered — every label asking for it is drawing in San Francisco"
            )
        }
    }

    @Test("calling the registrar again does not unregister anything")
    func registeringTwiceIsHarmless() {
        // The host app already registered at launch, so this second call newly registers nothing and
        // returns 0 — the count is of faces *newly* added, not of faces available. What is worth
        // pinning is that a repeat call cannot take a face away, since the composition root is not
        // the only thing that may reasonably want to call it.
        _ = CypressFont.registerBundledFonts()

        let families = Set(UIFont.familyNames)
        #expect(families.contains("Source Serif 4"))
        #expect(families.contains("Alegreya Sans"))
        #expect(families.contains("Spline Sans Mono"))
    }

    /// **Core Text is never asked to register a face it already has.**
    ///
    /// The app registers its fonts twice over: `Info.plist` lists all twelve under `UIAppFonts`, and
    /// the composition root then calls `registerBundledFonts()`. The second pass is refused once per
    /// face, and each refusal writes `GSFont: file already registered` to the console — twelve lines
    /// on every single launch, in a log somebody is reading to find real problems.
    ///
    /// This asserts on the *inputs* to Core Text rather than on the count of faces registered,
    /// because that count is 0 either way: 0 when every call fails as already-registered, and 0 when
    /// every call is skipped. A test written against the count would have passed against the noisy
    /// version. Empty here means Core Text is never called at all, which is the only thing that
    /// actually makes the console quiet.
    @Test("the registrar asks Core Text for nothing it already has")
    func theRegistrarSkipsFacesAlreadyPresent() {
        let pending = CypressFont.unregisteredBundledFonts()
        let names = pending.map(\.lastPathComponent).sorted().joined(separator: ", ")
        #expect(
            pending.isEmpty,
            "\(pending.count) bundled face(s) would be handed to Core Text a second time, and each one prints 'GSFont: file already registered' on every launch: \(names)"
        )
    }
}
