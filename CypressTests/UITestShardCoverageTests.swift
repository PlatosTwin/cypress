import Foundation
import Testing

/// **The UI suite is sharded across CI runners, and this is what stops a shard list from lying.**
///
/// `.github/workflows/testflight.yml` runs `CypressUITests` as three parallel jobs, each given the
/// class names on one line of `Tools/ui-test-shards.txt` as `-only-testing:` arguments. That is a
/// hand-maintained list of what runs, which makes it a false green with a fuse on it: a UI test
/// class that belongs to no shard **never runs**, no job fails, and the release gate goes green
/// having tested less than it did the week before. Nobody would see it — a test that does not run
/// produces no output to notice the absence of.
///
/// So the list is checked rather than trusted, and checked from the unit suite, which runs on every
/// build. Forgetting to assign a new class is a red, not a silence.
///
/// Three ways it can be wrong, all of them caught here:
/// - a class in `CypressUITests/` on no line — it would silently stop being tested;
/// - a class on two lines — it would run twice, and a shard's timing would drift for no visible
///   reason;
/// - a name on a line matching no class — usually a rename or a delete, and the `-only-testing:`
///   argument for a class that does not exist makes `xcodebuild` fail the whole shard.
///
/// Deliberately NOT checked: whether the shards are balanced. Balance is a performance property
/// that changes with every test added, and a test asserting it would fail for reasons that are not
/// defects. The measured per-class times are recorded in the file's own header instead, with the
/// run they came from, to be re-measured rather than believed.
@Suite("UI test shards cover every UI test class, exactly once")
struct UITestShardCoverageTests {

    static let manifestPath = "Tools/ui-test-shards.txt"

    /// Every `XCTestCase` subclass declared under `CypressUITests/`.
    ///
    /// Read off the source rather than the built bundle: this is a unit test, the UI bundle is a
    /// different target, and the question is about what the repository contains — the same reason
    /// `BritishSpellingGuardTests` and `PendingCitationGuardTests` read from disk.
    static func declaredUITestClasses(root: URL) throws -> Set<String> {
        let directory = root.appendingPathComponent("CypressUITests")
        let names = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .flatMap { url -> [String] in
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return text.split(separator: "\n").compactMap { classDeclaration(in: String($0)) }
            }
        return Set(names)
    }

    /// `final class Foo: XCTestCase {` → `Foo`. Written as a scan rather than a regex so the
    /// modifiers it tolerates are visible: any order of `final`/`public`/`internal`/`private`.
    static func classDeclaration(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var words = trimmed.split(separator: " ").map(String.init)
        while let first = words.first, ["final", "public", "internal", "private", "fileprivate"]
            .contains(first) {
            words.removeFirst()
        }
        guard words.first == "class", words.count >= 2 else { return nil }
        let name = words[1].trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard trimmed.contains("XCTestCase") else { return nil }
        return name.isEmpty ? nil : name
    }

    /// The shard lines, comments and blanks dropped.
    static func shards(root: URL) throws -> [[String]] {
        let url = root.appendingPathComponent(manifestPath)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.split(separator: " ").map(String.init) }
    }

    @Test("every XCUITest class is assigned to exactly one shard")
    func everyClassIsAssignedExactlyOnce() throws {
        let root = AppSourceLiterals.repositoryRoot()
        let declared = try Self.declaredUITestClasses(root: root)
        let shards = try Self.shards(root: root)

        // The scanner's own control: an empty result would satisfy "every declared class is
        // assigned" vacuously, which is the shape of failure ARCHITECTURE §7 records. The suite
        // has fourteen classes today and a floor is enough to prove the reader read something.
        #expect(
            declared.count >= 10,
            """
            found only \(declared.count) XCTestCase subclasses under CypressUITests/ — the \
            scanner is not reading the source, so every check below passes vacuously
            """
        )
        #expect(!shards.isEmpty, "\(Self.manifestPath) named no shards at all")

        var seen: [String: Int] = [:]
        for names in shards {
            for name in names { seen[name, default: 0] += 1 }
        }

        let unassigned = declared.subtracting(seen.keys).sorted()
        #expect(
            unassigned.isEmpty,
            """
            \(unassigned.count) UI test class(es) belong to no shard and therefore NEVER RUN on \
            CI: \(unassigned.joined(separator: ", ")). Add each to a line of \
            \(Self.manifestPath) — the shortest one.
            """
        )

        let duplicated = seen.filter { $0.value > 1 }.keys.sorted()
        #expect(
            duplicated.isEmpty,
            """
            \(duplicated.joined(separator: ", ")) appear on more than one shard line, so they run \
            twice and one shard is slower than its measured time for no visible reason
            """
        )

        let phantom = Set(seen.keys).subtracting(declared).sorted()
        #expect(
            phantom.isEmpty,
            """
            \(Self.manifestPath) names \(phantom.joined(separator: ", ")), which no longer exists \
            under CypressUITests/. xcodebuild fails a whole shard on an -only-testing: argument \
            for a class it cannot find.
            """
        )
    }

    /// The scanner finds the shape it exists to find, and declines the near-misses — the
    /// red-proof, run on every build rather than once by hand.
    @Test("the class scanner reads a declaration and not a mention of one")
    func theScannerReadsDeclarations() {
        #expect(Self.classDeclaration(in: "final class MapSearchUITests: XCTestCase {")
                == "MapSearchUITests")
        #expect(Self.classDeclaration(in: "class AlmanacGroupTapTests: XCTestCase {")
                == "AlmanacGroupTapTests")
        #expect(Self.classDeclaration(in: "    final class Indented: XCTestCase {") == "Indented")
        // A struct is not a UI test class, and neither is a comment about one.
        #expect(Self.classDeclaration(in: "struct NotATestCase: XCTestCase {") == nil)
        #expect(Self.classDeclaration(in: "/// see class Foo: XCTestCase for the pattern") == nil)
        // A class that is not an XCTestCase never runs under -only-testing and must not be listed.
        #expect(Self.classDeclaration(in: "final class Helper: NSObject {") == nil)
    }
}
