//
//  APIConformanceGuardTests.swift
//  CypressTests
//
//  **Task #76.** `CypressAPI` carries 31 requirements. `RemoteAPI` declared 17 of them and
//  inherited the other 14 from protocol extensions, and the build was green — because that is what
//  a protocol-extension default is *for*. Ten of those defaults threw `.notFound`, which is
//  survivable. Four returned a value, and a value is not survivable: a species guide with no
//  population line, an empty `mapMembership`, `.none` device contributions and a `grove()`-derived
//  `isFavorite` are answers, and a caller cannot tell an answer from an answer.
//
//  The property this file exists to make true is one sentence:
//
//      **An unimplemented requirement must be impossible to satisfy silently.**
//
//  ── Why the guard is shaped like this ───────────────────────────────────────────────────────────
//
//  Three things had to be true at once, and each of them ruled out an easier design.
//
//  1. **It must see what the app sees.** ERRATA **E125** is the day this bill came due: `photoData`
//     and `setPhotoVote` existed only as extension members, so they had no witness-table entry and
//     dispatched *statically*. `LocalAPI`'s real bodies were reached when the value was a
//     `LocalAPI` — which is what the tests held — and the extension's `throw .notFound` was reached
//     the moment it was erased to `any CypressAPI`, which is what every screen holds. Every
//     photograph failed to load on a build whose whole suite was green. So a guard that holds the
//     concrete type is disqualified: `theExistentialReachesTheConformance` below erases on purpose.
//
//  2. **It must not be able to drift from the protocol.** A guard that enumerates the requirements
//     from a hand-written list passes on the day somebody adds a thirty-second requirement and
//     forgets the list — which is this project's dominant defect class, a guard green precisely
//     when its condition is present. So the requirement set is *parsed out of
//     `Cypress/Data/API/CypressAPI.swift`* every run, and the one hand-written list in this file
//     (the existential probe's call sites) is checked **against that parse**, so a missing entry is
//     a failure rather than a smaller measurement.
//
//  3. **It must not be vacuous.** A parser that finds nothing agrees with everything. Every gate
//     here runs downstream of `theParserReadsTheProtocolItClaimsTo`, which checks the parse against
//     four answers known before it ran — including a **negative** control (`savePrivateReminder`
//     is on `LocalAPI` and deliberately *not* on the protocol; a parser scraping whole files rather
//     than the protocol body would report it as a requirement).
//
//  ── What it does not check ──────────────────────────────────────────────────────────────────────
//
//  That a declared method is *correct*. `throw .serverError` satisfies every gate here, and should:
//  #76 is the guard, #158 is the implementation, and the whole reason the spec sequences them in
//  that order is that a conformance which compiles with fourteen methods missing cannot tell anyone
//  whether the fifteenth was written
//  (`docs/design-proposals/2026-08-09-task158-live-layer.md` §3.3).
//
//  It also does not police the fourteen `#if DEBUG` preview doubles or the test doubles in this
//  target. A default answering `[]` in an Xcode canvas is a fixture; the same default reached from
//  a shipped screen is the defect. `theShippingConformancesAreTheOnesThisFileNames` is what keeps
//  that distinction from being a loophole: a new conformance outside `#if DEBUG` turns this file
//  red until somebody classifies it.
//
//  ── What review of PR #69 broke, and where the fix lives ────────────────────────────────────────
//
//  The first version of this file classified `#if` regions by asking whether the directive line
//  *contained* the substring `DEBUG`, and consulted that classification only for the position of a
//  type declaration. Three shapes defeated it — an `#else` branch (which is what a release build
//  compiles), `#if !DEBUG`, and `#if DEBUG` **inside** a shipping conformance's body — and with two
//  of them present every gate here reported green while a conformance inherited `mapMembership → []`
//  and `deviceContributions → .none`. `Parser.debugOnlyRegions` is now a real directive stack and
//  its classification is applied to members as well as declarations;
//  `theDirectiveStackClassifiesEachBranch` checks it branch by branch against source it writes
//  itself, and `theParserReadsAConformanceBody` checks it against the 330-line `#if DEBUG` region
//  that is really inside `LocalAPI`'s conformance body today.
//

import Foundation
import Testing
@testable import Cypress

// MARK: - One method declaration, reduced to what decides conformance

/// A method's identity for the purpose of "does this satisfy that requirement": the base name, the
/// argument **labels** and their types, and the return type.
///
/// Internal parameter names are deliberately dropped — `func treesNear(_ c: Coordinate, …)` in a
/// test double satisfies `func treesNear(_ coordinate: Coordinate, …)`, and this repo writes both.
/// Effects (`async`, `throws`) are deliberately dropped too, in the other direction: a synchronous
/// non-throwing witness legally satisfies an `async throws` requirement, so comparing them would
/// produce a red for a conformance that is in fact complete.
///
/// Types are compared as written, whitespace-collapsed. Two spellings of one type (`Set<UUID>` and
/// a hypothetical `Swift.Set<UUID>`) would read as different here and report a missing
/// implementation that is not missing. That is the safe direction and it is loud: it fails, names
/// the pair, and is fixed by spelling them the same way.
struct APISignature: Hashable, Comparable, CustomStringConvertible {

    struct Parameter: Hashable {
        let label: String
        let type: String
    }

    let name: String
    let parameters: [Parameter]
    let returnType: String

    var description: String {
        let args = parameters.map { "\($0.label): \($0.type)" }.joined(separator: ", ")
        return "\(name)(\(args)) -> \(returnType)"
    }

    static func < (lhs: APISignature, rhs: APISignature) -> Bool {
        lhs.description < rhs.description
    }
}

// MARK: - The source walk

/// `CypressAPI`'s surface and its conformances, read off the working tree.
///
/// Source rather than runtime because Swift has no reflection over protocol requirements: there is
/// no supported way to ask a metatype which witnesses it supplied and which it inherited. What the
/// language *does* give is the existential — see `theExistentialReachesTheConformance`, which is
/// the live half of this file and the half E125 demands.
enum CypressAPISurface {

    /// A type in the app target that conforms to `CypressAPI`.
    struct Conformance {
        let typeName: String
        /// Every path the type is declared or extended in, for a failure somebody can act on.
        let paths: [String]
        /// Whether the declaration sits in a region compiled **only** when `DEBUG` is defined — a
        /// preview double, which cannot render a screen in a shipped build.
        let isDebugOnly: Bool
        /// Every method the type declares in a region a shipped build compiles: its own body plus
        /// every `extension <TypeName>` in the app target, minus anything behind `#if DEBUG`.
        let declared: Set<APISignature>
    }

    // MARK: Cached reads

    static let root = AppSourceLiterals.repositoryRoot()

    /// Every `.swift` file in the app target, blanked of comments and string interiors, keyed by
    /// path relative to the worktree root.
    ///
    /// Comments have to go, and in this file more than most: `CypressAPI.swift`'s own header
    /// **writes out method declarations in prose** to explain what was removed and why, and the
    /// "two methods that were requirements and are not any more" note names `outboxStatus()` and
    /// `savePrivateReminder(_:)` in a comment inside the very file whose protocol body is being
    /// parsed. Reusing `BorrowedGlyphAPI.codeOnly(in:)` rather than growing a second scanner, the
    /// same way `DrawnGlyphGuardTests` reuses `AppSourceLiterals`.
    /// One app-target file: its path, its code with comments and string interiors blanked, and the
    /// character indices a shipped build does **not** compile.
    struct SourceFile {
        let path: String
        let code: [Character]
        /// Indices inside a region compiled only when `DEBUG` is defined.
        let debugOnly: Set<Int>
    }

    static let appSources: [SourceFile] = {
        let files = AppSourceLiterals.sourceFiles(root: root)
        return files.map { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let relative = url.path.hasPrefix(root.path + "/")
                ? String(url.path.dropFirst(root.path.count + 1))
                : url.path
            let code = Array(BorrowedGlyphAPI.codeOnly(in: text))
            return SourceFile(path: relative, code: code, debugOnly: Parser.debugOnlyRegions(code))
        }
    }()

    static let fileCount = appSources.count

    // MARK: The protocol body

    /// Every method requirement of `CypressAPI`, parsed from its declaration. 31 today.
    ///
    /// The protocol body is read whole, `#if` and all: a requirement declared behind `#if DEBUG`
    /// would be one every shipping conformance still has to answer in a debug build, and there are
    /// none, so nothing is subtracted here.
    static let requirementMethods: [Parser.Method] = {
        guard let file = appSources.first(where: { $0.path == "Cypress/Data/API/CypressAPI.swift" })
        else { return [] }
        guard let body = Parser.declarationBody(of: "protocol", named: "CypressAPI", in: file.code)
        else { return [] }
        return Parser.methods(in: file.code, range: body)
    }()

    static let requirements: [APISignature] = requirementMethods.map(\.signature)

    /// The names of `CypressAPI`'s property and subscript requirements. Empty today, and gate 5
    /// depends on knowing that rather than assuming it.
    static let requirementPropertyNames: Set<String> = {
        guard let file = appSources.first(where: { $0.path == "Cypress/Data/API/CypressAPI.swift" })
        else { return [] }
        guard let body = Parser.declarationBody(of: "protocol", named: "CypressAPI", in: file.code)
        else { return [] }
        return Set(Parser.properties(in: file.code, range: body).map(\.name))
    }()

    // MARK: Protocol-extension members

    struct ExtensionMember {
        /// `func mapMembership(_: MapMembership) -> Set<UUID>`, `var apiFlavor`, `subscript`.
        let description: String
        let path: String
        /// Whether a protocol requirement of the same kind, staticness and shape exists.
        let isRequirement: Bool
    }

    /// Every member declared in a `public extension CypressAPI { … }` block anywhere in the app
    /// target — methods (instance **and** static), computed properties, and subscripts.
    ///
    /// All three kinds matter and only one of them used to be read. E125's mechanism is that a
    /// member which is not a requirement has no witness-table entry and dispatches statically; that
    /// is a fact about members, not about functions, so a `var` or a `subscript` in this extension
    /// is the same trap wearing different clothes.
    static let extensionMembers: [ExtensionMember] = {
        let requiredMethods = Set(requirementMethods.map { Parser.MethodKey($0) })
        return appSources.flatMap { file -> [ExtensionMember] in
            Parser.extensionBodies(of: "CypressAPI", in: file.code).flatMap { body -> [ExtensionMember] in
                let methods = Parser.methods(in: file.code, range: body).map { method in
                    ExtensionMember(
                        description: (method.isStatic ? "static func " : "func ") + method.signature.description,
                        path: file.path,
                        isRequirement: requiredMethods.contains(Parser.MethodKey(method))
                    )
                }
                let properties = Parser.properties(in: file.code, range: body).map { property in
                    ExtensionMember(
                        description: "\(property.keyword) \(property.name)",
                        path: file.path,
                        isRequirement: requirementPropertyNames.contains(property.name)
                    )
                }
                return methods + properties
            }
        }
    }()

    // MARK: Conformances

    /// Every `CypressAPI` conformance declared in the app target, shipping and preview alike.
    ///
    /// **A conformance is one type, not one declaration.** Its witnesses may be spread over its own
    /// body and any number of `extension <TypeName>` blocks — which is what #158 will do to
    /// `RemoteAPI` the moment 31 real bodies need `// MARK:` sections — so every declaration of the
    /// name contributes, and the union is what gate 3 measures.
    ///
    /// **What is subtracted is anything a shipped build does not compile.** A witness written inside
    /// `#if DEBUG` in a shipping conformance's own body is not a witness in a release build: the
    /// protocol-extension default is, silently. `LocalAPI` has a 330-line `#if DEBUG` region inside
    /// its conformance body today, so this is not a hypothetical shape.
    static let conformances: [Conformance] = {
        var byName: [String: (paths: [String], isDebugOnly: Bool, declared: Set<APISignature>)] = [:]

        for file in appSources {
            for found in Parser.conformances(to: "CypressAPI", in: file.code) {
                let declared = Set(
                    Parser.methods(in: file.code, range: found.body, excluding: file.debugOnly)
                        .map(\.signature)
                )
                var entry = byName[found.typeName] ?? ([], true, [])
                entry.paths.append(file.path)
                // A type is a fixture only if **every** declaration of its conformance is behind
                // `#if DEBUG`. One release-compiled declaration makes the whole type shipping,
                // which is the direction that fails loudly.
                entry.isDebugOnly = entry.isDebugOnly && found.isDebugOnly
                entry.declared.formUnion(declared)
                byName[found.typeName] = entry
            }
        }

        // Witnesses contributed by `extension <TypeName>` blocks elsewhere.
        for name in byName.keys {
            for file in appSources {
                for body in Parser.extensionBodies(of: name, in: file.code) {
                    let declared = Set(
                        Parser.methods(in: file.code, range: body, excluding: file.debugOnly)
                            .map(\.signature)
                    )
                    guard !declared.isEmpty else { continue }
                    byName[name]?.declared.formUnion(declared)
                    if byName[name]?.paths.contains(file.path) == false {
                        byName[name]?.paths.append(file.path)
                    }
                }
            }
        }

        return byName
            .map { Conformance(typeName: $0.key, paths: $0.value.paths.sorted(), isDebugOnly: $0.value.isDebugOnly, declared: $0.value.declared) }
            .sorted { $0.typeName < $1.typeName }
    }()

    /// The conformances a shipped build can reach — everything not behind `#if DEBUG`.
    static var shippingConformances: [Conformance] {
        conformances.filter { !$0.isDebugOnly }
    }
}

// MARK: - The parser

/// A deliberately small Swift scanner. It handles the declaration shapes this repo actually writes
/// and nothing else; anything it cannot read fails as a mismatch, which is red rather than green.
enum Parser {

    struct Method {
        let signature: APISignature
        let isStatic: Bool
    }

    /// A method's identity including staticness — what decides whether an extension member is the
    /// witness for a requirement rather than a static-dispatch trap beside one.
    struct MethodKey: Hashable {
        let signature: APISignature
        let isStatic: Bool
        init(_ method: Method) {
            self.signature = method.signature
            self.isStatic = method.isStatic
        }
    }

    /// A stored or computed property, or a subscript.
    struct Property {
        /// `var`, `let` or `subscript`, for the failure message.
        let keyword: String
        let name: String
    }

    struct FoundConformance {
        let typeName: String
        let isDebugOnly: Bool
        /// The type's own braced body.
        let body: Range<Int>
    }

    static func isIdentifier(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// Whether `word` sits at `index` as a whole token.
    static func word(_ chars: [Character], at index: Int, is word: String) -> Bool {
        let w = Array(word)
        guard index >= 0, index + w.count <= chars.count else { return false }
        guard Array(chars[index..<(index + w.count)]) == w else { return false }
        if index > 0, isIdentifier(chars[index - 1]) { return false }
        let after = index + w.count
        if after < chars.count, isIdentifier(chars[after]) { return false }
        return true
    }

    /// The index just past the bracket that opens at `open`.
    static func endOfBlock(_ chars: [Character], open: Int, opener: Character, closer: Character) -> Int {
        var depth = 0
        var i = open
        while i < chars.count {
            if chars[i] == opener { depth += 1 }
            if chars[i] == closer {
                depth -= 1
                if depth == 0 { return i + 1 }
            }
            i += 1
        }
        return chars.count
    }

    /// The braced body of `<keyword> <name>` — `protocol CypressAPI { … }`, say.
    static func declarationBody(of keyword: String, named name: String, in chars: [Character]) -> Range<Int>? {
        var i = 0
        while i < chars.count {
            guard word(chars, at: i, is: keyword) else { i += 1; continue }
            var j = i + keyword.count
            while j < chars.count, chars[j] == " " { j += 1 }
            var read = ""
            while j < chars.count, isIdentifier(chars[j]) { read.append(chars[j]); j += 1 }
            guard read == name else { i += 1; continue }
            guard let brace = nextBrace(chars, from: j) else { return nil }
            return (brace + 1)..<(endOfBlock(chars, open: brace, opener: "{", closer: "}") - 1)
        }
        return nil
    }

    /// Every `extension <name> { … }` body in the file.
    static func extensionBodies(of name: String, in chars: [Character]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            guard word(chars, at: i, is: "extension") else { i += 1; continue }
            var j = i + "extension".count
            while j < chars.count, chars[j] == " " { j += 1 }
            var read = ""
            while j < chars.count, isIdentifier(chars[j]) { read.append(chars[j]); j += 1 }
            if read == name, let brace = nextBrace(chars, from: j) {
                out.append((brace + 1)..<(endOfBlock(chars, open: brace, opener: "{", closer: "}") - 1))
                i = brace
            }
            i += 1
        }
        return out
    }

    /// The next `{` that opens a body, skipping any generic clause or inheritance list on the way.
    private static func nextBrace(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == "{" { return i }
            if chars[i] == "\n", i + 1 < chars.count {
                // A declaration's heritage can wrap; a blank line cannot appear inside one.
                var k = i + 1
                while k < chars.count, chars[k] == " " { k += 1 }
                if k < chars.count, chars[k] == "\n" { return nil }
            }
            i += 1
        }
        return nil
    }

    // MARK: Methods

    /// Every `func` declared **directly** in `range` — depth 0 relative to it.
    ///
    /// The depth check is what keeps a local `func` inside a 300-line method body, or a method on a
    /// nested helper type, out of a conformance's declared set. Neither could produce a red, only a
    /// false green, which is the direction that matters.
    ///
    /// `excluding` names character indices a shipped build does not compile — see
    /// `debugOnlyRegions`. A method declared there is not a witness in a release build, so counting
    /// it as declared is exactly the false green this parameter exists to prevent.
    static func methods(
        in chars: [Character],
        range: Range<Int>,
        excluding: Set<Int> = []
    ) -> [Method] {
        var out: [Method] = []
        var i = range.lowerBound
        var depth = 0
        while i < range.upperBound {
            if chars[i] == "{" { depth += 1; i += 1; continue }
            if chars[i] == "}" { depth -= 1; i += 1; continue }
            guard depth == 0, word(chars, at: i, is: "func"), !excluding.contains(i) else { i += 1; continue }

            // Modifiers are whatever precedes `func` on this declaration.
            var modifierStart = i
            while modifierStart > range.lowerBound,
                  !"\n{};".contains(chars[modifierStart - 1]) {
                modifierStart -= 1
            }
            let isStatic = String(chars[modifierStart..<i]).contains("static ")

            var j = i + 4
            while j < range.upperBound, chars[j] == " " || chars[j] == "\n" { j += 1 }
            var name = ""
            while j < range.upperBound, isIdentifier(chars[j]) { name.append(chars[j]); j += 1 }
            guard !name.isEmpty else { i += 4; continue }   // an operator declaration
            while j < range.upperBound, chars[j] == " " { j += 1 }
            if j < range.upperBound, chars[j] == "<" {
                j = endOfBlock(chars, open: j, opener: "<", closer: ">")
                while j < range.upperBound, chars[j] == " " { j += 1 }
            }
            guard j < range.upperBound, chars[j] == "(" else { i += 4; continue }
            let afterParen = endOfBlock(chars, open: j, opener: "(", closer: ")")
            let parameterText = String(chars[(j + 1)..<max(j + 1, afterParen - 1)])

            var k = afterParen
            var tail = ""
            while k < range.upperBound, chars[k] != "{", chars[k] != "\n" {
                tail.append(chars[k])
                k += 1
            }

            out.append(
                Method(
                    signature: APISignature(
                        name: name,
                        parameters: parameters(in: parameterText),
                        returnType: returnType(in: tail)
                    ),
                    isStatic: isStatic
                )
            )
            i = k
        }
        return out
    }

    /// Every `var`, `let` or `subscript` declared directly in `range`.
    ///
    /// Names only, not types. Gate 5 asks "is this member a requirement at all", and `CypressAPI`
    /// has no property or subscript requirements, so a name is enough to answer it: any property in
    /// `extension CypressAPI` is an orphan. If the protocol ever grows one, this comparison gets
    /// looser than the method one and should be tightened to match.
    static func properties(
        in chars: [Character],
        range: Range<Int>,
        excluding: Set<Int> = []
    ) -> [Property] {
        var out: [Property] = []
        var i = range.lowerBound
        var depth = 0
        while i < range.upperBound {
            if chars[i] == "{" { depth += 1; i += 1; continue }
            if chars[i] == "}" { depth -= 1; i += 1; continue }
            guard depth == 0, !excluding.contains(i) else { i += 1; continue }

            if word(chars, at: i, is: "subscript") {
                out.append(Property(keyword: "subscript", name: "subscript"))
                i += "subscript".count
                continue
            }
            guard let keyword = ["var", "let"].first(where: { word(chars, at: i, is: $0) }) else {
                i += 1
                continue
            }
            var j = i + keyword.count
            while j < range.upperBound, chars[j] == " " { j += 1 }
            var name = ""
            while j < range.upperBound, isIdentifier(chars[j]) { name.append(chars[j]); j += 1 }
            if !name.isEmpty { out.append(Property(keyword: keyword, name: name)) }
            i = max(j, i + keyword.count)
        }
        return out
    }

    /// The `->` clause of a declaration tail, or `Void`.
    private static func returnType(in tail: String) -> String {
        let chars = Array(tail)
        var depth = 0
        var i = 0
        while i < chars.count {
            switch chars[i] {
            case "(", "[", "<": depth += 1
            case ")", "]", ">": depth -= 1
            case "-" where depth == 0 && i + 1 < chars.count && chars[i + 1] == ">":
                return collapse(String(chars[(i + 2)...]))
            default: break
            }
            i += 1
        }
        return "Void"
    }

    private static func parameters(in text: String) -> [APISignature.Parameter] {
        splitTopLevel(text).compactMap { raw -> APISignature.Parameter? in
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { return nil }
            let chars = Array(piece)
            var depth = 0
            var colon: Int?
            for (i, c) in chars.enumerated() {
                switch c {
                case "(", "[", "<": depth += 1
                case ")", "]", ">": depth -= 1
                case ":" where depth == 0: colon = i
                default: break
                }
                if colon != nil { break }
            }
            guard let split = colon else { return nil }
            let names = String(chars[..<split])
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
                .filter { !$0.hasPrefix("@") }
            guard let label = names.first else { return nil }
            var type = String(chars[(split + 1)...])
            // A default value is not part of the type.
            if let equals = type.firstIndex(of: "=") { type = String(type[..<equals]) }
            return APISignature.Parameter(label: label, type: collapse(type))
        }
    }

    /// Split on commas that are not inside brackets.
    private static func splitTopLevel(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var depth = 0
        for c in text {
            switch c {
            case "(", "[", "<": depth += 1; current.append(c)
            case ")", "]", ">": depth -= 1; current.append(c)
            case "," where depth == 0: out.append(current); current = ""
            default: current.append(c)
            }
        }
        out.append(current)
        return out
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: Conformances

    /// Every type declaration in the file whose heritage clause names `protocolName`.
    static func conformances(to protocolName: String, in chars: [Character]) -> [FoundConformance] {
        let debug = debugOnlyRegions(chars)
        var out: [FoundConformance] = []
        var i = 0
        let keywords = ["struct", "class", "actor", "enum", "extension"]
        while i < chars.count {
            guard let keyword = keywords.first(where: { word(chars, at: i, is: $0) }) else {
                i += 1
                continue
            }
            var j = i + keyword.count
            while j < chars.count, chars[j] == " " { j += 1 }
            var typeName = ""
            while j < chars.count, isIdentifier(chars[j]) { typeName.append(chars[j]); j += 1 }
            guard !typeName.isEmpty, let brace = nextBrace(chars, from: j) else { i += 1; continue }
            let heritage = Array(String(chars[j..<brace]))
            var namesProtocol = false
            for k in 0..<heritage.count where word(heritage, at: k, is: protocolName) {
                namesProtocol = true
                break
            }
            guard namesProtocol else { i = j; continue }
            out.append(
                FoundConformance(
                    typeName: typeName,
                    isDebugOnly: debug.contains(i),
                    body: (brace + 1)..<(endOfBlock(chars, open: brace, opener: "{", closer: "}") - 1)
                )
            )
            i = brace
        }
        return out
    }

    /// The character indices in a region a shipped build does **not** compile — that is, one whose
    /// enclosing conditional compiles only when `DEBUG` is defined.
    ///
    /// ── Why this is a stack and not a `contains("DEBUG")` ───────────────────────────────────────
    ///
    /// The first version of this function marked any region whose `#if` line *contained* the
    /// substring `DEBUG`, kept the mark through `#else`, and was consulted only for the position of
    /// a type declaration. Review of PR #69 broke all three, live, on a build that really
    /// recompiled — all six gates green with the defect present:
    ///
    ///   - `#if DEBUG … #else <conformance> #endif` — the `#else` branch is what a **release** build
    ///     compiles, and it was being marked as debug-only, so a release-only conformance was
    ///     classified as a preview double and never asked to declare anything.
    ///   - `#if !DEBUG <conformance> #endif` — `contains("DEBUG")` matches the negation, with the
    ///     same result.
    ///   - `#if DEBUG` **inside** a shipping conformance's body — the mark was never applied to
    ///     members at all, so a requirement declared there counted as declared while the release
    ///     build inherited the protocol-extension default.
    ///
    /// So: a real stack. `#if` pushes, `#elseif` replaces the top, `#else` replaces the top with
    /// **false** (an else branch is compiled when the condition is not met, which includes every
    /// release build), `#endif` pops. And a condition counts as debug-only only when it is
    /// *exactly* `DEBUG` — `!DEBUG`, `DEBUG || FOO` and `os(iOS)` are all "compiled in release as
    /// far as this scan knows", which is the direction that fails loudly.
    ///
    /// The claim this comment used to make in the opposite direction — that a missed region is
    /// classified as shipping — is now true because the classification is built to make it true,
    /// rather than asserted because it seemed obvious. `theDirectiveStackClassifiesEachBranch`
    /// checks it against the three shapes above.
    static func debugOnlyRegions(_ chars: [Character]) -> Set<Int> {
        var marked: Set<Int> = []
        var stack: [Bool] = []
        var i = 0
        var lineStart = 0

        /// Whether a directive's condition is met *only* in a DEBUG build.
        func isDebugOnly(_ condition: String) -> Bool {
            var text = condition.trimmingCharacters(in: .whitespaces)
            while text.hasPrefix("("), text.hasSuffix(")") {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            }
            return text == "DEBUG"
        }

        while i <= chars.count {
            if i == chars.count || chars[i] == "\n" {
                let line = String(chars[lineStart..<i]).trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#elseif") {
                    if !stack.isEmpty { stack[stack.count - 1] = isDebugOnly(String(line.dropFirst("#elseif".count))) }
                } else if line.hasPrefix("#else") {
                    if !stack.isEmpty { stack[stack.count - 1] = false }
                } else if line.hasPrefix("#endif") {
                    if !stack.isEmpty { stack.removeLast() }
                } else if line.hasPrefix("#if") {
                    stack.append(isDebugOnly(String(line.dropFirst("#if".count))))
                }
                if stack.contains(true) {
                    for k in lineStart..<min(i + 1, chars.count) { marked.insert(k) }
                }
                lineStart = i + 1
            }
            i += 1
        }
        return marked
    }
}

// MARK: - The existential probe

/// The error a probe method throws to prove that the call reached *it* and not a default.
private struct ProbeReached: Error {
    let name: String
}

private final class ProbeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func reached(_ name: String) -> ProbeReached {
        lock.lock()
        names.append(name)
        lock.unlock()
        return ProbeReached(name: name)
    }

    var seen: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(names)
    }
}

/// A conformance that implements every requirement and refuses every call with its own name.
///
/// The point is the *name*: if a call erased to `any CypressAPI` arrives here, the thrown
/// `ProbeReached` says which method it was. If it arrives at a protocol-extension default instead —
/// E125's static dispatch — the call either returns a value or throws an `APIError`, and either way
/// the assertion below fails naming the method that went missing.
/// Locates the test bundle the seed database is copied into.
private final class SeedBundleToken {}

private struct ProbeAPI: CypressAPI {
    let log: ProbeLog

    func mapContent(in viewport: MapViewport) async throws -> MapContent { throw log.reached("mapContent") }
    func treesNear(_ c: Coordinate, radiusM: Double, limit: Int) async throws -> [NearbyTree] { throw log.reached("treesNear") }
    func treeProfile(id: UUID) async throws -> TreeProfile { throw log.reached("treeProfile") }
    func addTree(_ draft: TreeDraft) async throws -> Tree { throw log.reached("addTree") }
    func claimSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree { throw log.reached("claimSpecies") }
    func correctSpecies(treeID: UUID, speciesID: UUID) async throws -> Tree { throw log.reached("correctSpecies") }
    func flagWrongSpecies(treeID: UUID) async throws { throw log.reached("flagWrongSpecies") }
    func dismissSpeciesReview(flagID: UUID) async throws { throw log.reached("dismissSpeciesReview") }
    func flagNeverExisted(treeID: UUID) async throws { throw log.reached("flagNeverExisted") }
    func withdrawRecord(flagID: UUID) async throws { throw log.reached("withdrawRecord") }
    func dismissRecordReview(flagID: UUID) async throws { throw log.reached("dismissRecordReview") }
    func species(id: UUID) async throws -> Species { throw log.reached("species") }
    func searchSpecies(query: String, limit: Int) async throws -> [Species] { throw log.reached("searchSpecies") }
    func speciesGuide(id: UUID, near coordinate: Coordinate?) async throws -> SpeciesGuide { throw log.reached("speciesGuide") }
    func almanac(near coordinate: Coordinate?) async throws -> Almanac { throw log.reached("almanac") }
    func city(near coordinate: Coordinate?) async throws -> CityAlmanac { throw log.reached("city") }
    func sync(_ items: [OutboxItem]) async throws -> [SyncResult] { throw log.reached("sync") }
    func beginPhotoUpload(_ request: PhotoUploadRequest) async throws -> PhotoUploadTicket { throw log.reached("beginPhotoUpload") }
    func uploadPhoto(at localPath: String, ticket: PhotoUploadTicket) async throws { throw log.reached("uploadPhoto") }
    func photoData(id: UUID) async throws -> Data { throw log.reached("photoData") }
    func setPhotoVote(photoID: UUID, vote: PhotoVote?) async throws { throw log.reached("setPhotoVote") }
    func deletePhoto(id: UUID) async throws -> PhotoDeletion { throw log.reached("deletePhoto") }
    func grove() async throws -> [GroveEntry] { throw log.reached("grove") }
    func isFavorite(treeID: UUID) async throws -> Bool { throw log.reached("isFavorite") }
    func groveSpecies() async throws -> GroveSpecies { throw log.reached("groveSpecies") }
    func journal(cursor: String?, limit: Int) async throws -> Page<JournalEntry> { throw log.reached("journal") }
    func claimDevice(deviceUUID: UUID, userID: UUID) async throws { throw log.reached("claimDevice") }
    func deviceContributions() async throws -> DeviceContributions { throw log.reached("deviceContributions") }
    func mapMembership(_ kind: MapMembership) async throws -> Set<UUID> { throw log.reached("mapMembership") }
    func logHazardRedirect(_ event: HazardRedirectEvent) async throws { throw log.reached("logHazardRedirect") }
    func exportLatest(_ format: ExportFormat) async throws -> Data { throw log.reached("exportLatest") }
}

// MARK: - The gates

@Suite("CypressAPI conformance (#76)")
struct APIConformanceGuardTests {

    /// The conformances that a shipped build can reach, and which this file therefore holds to the
    /// full surface. Cross-checked against the source walk by
    /// `theShippingConformancesAreTheOnesThisFileNames`, so it cannot go stale silently.
    static let shipping = ["LocalAPI", "RemoteAPI"]

    // MARK: Calibration

    /// **Calibrate the instrument before trusting the reading.** Four answers known before the
    /// parser ran: two requirements it must find, one method it must *not* (the negative control),
    /// and the file walk it depends on.
    @Test("the parser reads the protocol it claims to")
    func theParserReadsTheProtocolItClaimsTo() throws {
        #expect(
            CypressAPISurface.fileCount >= AppSourceLiterals.swiftFileCountFloor,
            """
            the app source walk found \(CypressAPISurface.fileCount) files, below the floor of \
            \(AppSourceLiterals.swiftFileCountFloor). Every gate in this file is vacuous until this \
            passes.
            """
        )

        let requirements = CypressAPISurface.requirements
        let named = Set(requirements.map(\.name))

        // Positive controls: one with a labelled parameter, one whose return type is generic.
        #expect(
            requirements.contains(
                APISignature(
                    name: "mapContent",
                    parameters: [.init(label: "in", type: "MapViewport")],
                    returnType: "MapContent"
                )
            ),
            "parsed requirements did not include mapContent(in: MapViewport) -> MapContent: \(requirements.sorted())"
        )
        #expect(
            requirements.contains(
                APISignature(
                    name: "mapMembership",
                    parameters: [.init(label: "_", type: "MapMembership")],
                    returnType: "Set<UUID>"
                )
            ),
            "parsed requirements did not include mapMembership(_: MapMembership) -> Set<UUID>: \(requirements.sorted())"
        )

        // Negative control. `savePrivateReminder` is a method on `LocalAPI` and was deliberately
        // removed from the protocol — `CypressAPI.swift`'s "two methods that were requirements and
        // are not any more" note is in the same file, in a comment. A parser reading the file
        // rather than the protocol body, or one that failed to blank comments, reports it here.
        #expect(
            !named.contains("savePrivateReminder"),
            "the parser reported savePrivateReminder as a protocol requirement; it is LocalAPI-only"
        )
        #expect(
            !named.contains("outboxStatus"),
            "the parser reported outboxStatus as a protocol requirement; it was removed from the protocol"
        )

        // A requirement set this small means the protocol body was not found.
        #expect(
            requirements.count >= 25,
            "only \(requirements.count) requirements parsed out of CypressAPI; the body was not read"
        )

        // Base names are the probe's key below, so they have to be unique for the cross-check to
        // measure what it claims to.
        #expect(
            named.count == requirements.count,
            "two requirements share a base name; the existential probe's key is no longer sufficient"
        )
    }

    /// The parser must read a conformance's own body, not the file it sits in — and must not count
    /// what a release build does not compile.
    @Test("the parser reads a conformance body, not a whole file")
    func theParserReadsAConformanceBody() throws {
        let local = try #require(
            CypressAPISurface.conformances.first { $0.typeName == "LocalAPI" },
            "LocalAPI was not found as a CypressAPI conformance in the app target"
        )
        // Present on the type, absent from the protocol — so it proves the two parses are distinct.
        #expect(
            local.declared.contains { $0.name == "savePrivateReminder" },
            "LocalAPI's parsed body did not include savePrivateReminder, which it declares"
        )
        #expect(!local.isDebugOnly, "LocalAPI was classified as #if DEBUG")

        // **The `#if DEBUG` exclusion, checked against a region that is really in the tree.**
        // `LocalAPI.swift` carries a 330-line `#if DEBUG` block *inside* its conformance body, and
        // `debugSeedPhotos` is declared in it. Counting it as declared is the shape review of
        // PR #69 broke gate 3 with, so the parser is measured against it here rather than trusted.
        #expect(
            !local.declared.contains { $0.name == "debugSeedPhotos" },
            """
            LocalAPI's declared set includes debugSeedPhotos, which is inside `#if DEBUG` in its own \
            body. A witness a release build does not compile is not a witness, and gate 3 is \
            worthless while this is true.
            """
        )

        let previews = CypressAPISurface.conformances.filter(\.isDebugOnly)
        #expect(
            previews.count >= 10,
            "only \(previews.count) conformances were classified as #if DEBUG; the region scan is wrong"
        )
    }

    /// **The classification, checked branch by branch on source this test writes itself.**
    ///
    /// Review of PR #69 broke the previous `contains("DEBUG")` version with three shapes, live.
    /// Each is checked here against an answer known before the scan ran, so the fix is measured
    /// rather than asserted. Written as literals fed to the parser rather than as files, so the
    /// case can be stated exactly and nothing in the repository has to carry it.
    @Test("the directive stack classifies each branch, not each spelling")
    func theDirectiveStackClassifiesEachBranch() throws {
        /// Whether the parser considers the line carrying `needle` debug-only.
        func isDebugOnly(_ source: String, _ needle: String) throws -> Bool {
            let chars = Array(source)
            let marked = Parser.debugOnlyRegions(chars)
            let index = try #require(
                source.range(of: needle).map { source.distance(from: source.startIndex, to: $0.lowerBound) },
                "the probe source does not contain \(needle)"
            )
            return marked.contains(index)
        }

        // A plain `#if DEBUG` body is debug-only — the positive control, without which every
        // expectation below could pass by the scan marking nothing at all.
        #expect(try isDebugOnly("#if DEBUG\nlet a = 1\n#endif\n", "let a"))

        // …and code outside it is not.
        #expect(try isDebugOnly("#if DEBUG\nlet a = 1\n#endif\nlet b = 2\n", "let b") == false)

        // (b) an `#else` branch is what a release build compiles.
        #expect(try isDebugOnly("#if DEBUG\nlet a = 1\n#else\nlet b = 2\n#endif\n", "let b") == false)

        // (c) `#if !DEBUG` contains the substring DEBUG and is the opposite of a debug region.
        #expect(try isDebugOnly("#if !DEBUG\nlet a = 1\n#endif\n", "let a") == false)

        // A condition that is not exactly DEBUG is compiled in release as far as this scan knows.
        #expect(try isDebugOnly("#if DEBUG || BETA\nlet a = 1\n#endif\n", "let a") == false)
        #expect(try isDebugOnly("#if os(iOS)\nlet a = 1\n#endif\n", "let a") == false)

        // `#elseif` replaces the top of the stack rather than inheriting it.
        #expect(try isDebugOnly("#if DEBUG\nlet a = 1\n#elseif BETA\nlet b = 2\n#endif\n", "let b") == false)
        #expect(try isDebugOnly("#if BETA\nlet a = 1\n#elseif DEBUG\nlet b = 2\n#endif\n", "let b"))

        // Nesting: an inner non-DEBUG region inside a DEBUG one is still debug-only.
        #expect(try isDebugOnly("#if DEBUG\n#if os(iOS)\nlet a = 1\n#endif\n#endif\n", "let a"))
        // …and the stack unwinds, so what follows both is not.
        #expect(
            try isDebugOnly("#if DEBUG\n#if os(iOS)\nlet a = 1\n#endif\n#endif\nlet b = 2\n", "let b") == false
        )

        // Parenthesised, which is how a hand-wrapped condition often arrives.
        #expect(try isDebugOnly("#if (DEBUG)\nlet a = 1\n#endif\n", "let a"))
    }

    // MARK: The guard

    /// **The gate.** Every shipping conformance declares every requirement itself — no shipped
    /// screen can reach a protocol-extension default.
    @Test("every shipping conformance declares every requirement")
    func everyShippingConformanceDeclaresEveryRequirement() throws {
        let requirements = Set(CypressAPISurface.requirements)
        #expect(!requirements.isEmpty, "no requirements parsed; the gate below would pass vacuously")

        for conformance in CypressAPISurface.shippingConformances {
            let missing = requirements.subtracting(conformance.declared).sorted()
            #expect(
                missing.isEmpty,
                """
                \(conformance.typeName) (\(conformance.paths.joined(separator: ", "))) does not \
                declare \(missing.count) of \(requirements.count) `CypressAPI` requirements in any \
                release-compiled position:
                \(missing.map { "  · \($0)" }.joined(separator: "\n"))
                Each is therefore satisfied by a protocol-extension default, and a default is not an \
                implementation. Three ways this reads red when the method is in fact written: the \
                signature does not match the requirement exactly (so the compiler is using the \
                default too — check labels, parameter types and return type), it is inside \
                `#if DEBUG` (so a release build inherits the default), or it is on a type this scan \
                does not associate with the conformance. Otherwise: declare it — a refusal is a fine \
                body — or argue in the type's header why the inherited answer is the honest one.
                """
            )
        }
    }

    /// The list of shipping conformances is checked against the tree, so a third one cannot land
    /// unclassified.
    @Test("the shipping conformances are the ones this file names")
    func theShippingConformancesAreTheOnesThisFileNames() throws {
        let found = Set(CypressAPISurface.shippingConformances.map(\.typeName))
        #expect(
            found == Set(Self.shipping),
            """
            the app target's non-`#if DEBUG` `CypressAPI` conformances are \(found.sorted()), and \
            this file expects \(Self.shipping.sorted()). A new one is either a shipping conformance \
            — add it here, and it must declare every requirement — or a fixture, which belongs \
            behind `#if DEBUG`.
            """
        )
    }

    /// **ERRATA E125's mechanism, guarded at the source.** A member that lives only in a protocol
    /// extension has no witness-table entry and dispatches statically, so a conformance's own body
    /// is unreachable through `any CypressAPI` — which is what every screen holds.
    ///
    /// **Every kind of member, not only instance methods.** The first version of this gate filtered
    /// to non-`static func`, which left a computed `var`, a `subscript` and a `static func` in
    /// `extension CypressAPI` invisible to it — the same trap in three other shapes, as review of
    /// PR #69 demonstrated by adding two of them and watching this report zero orphans.
    @Test("no protocol-extension member is invisible to the witness table")
    func noExtensionMemberIsInvisibleToTheWitnessTable() throws {
        let members = CypressAPISurface.extensionMembers
        #expect(
            members.count >= 10,
            "only \(members.count) `extension CypressAPI` members found; the extension scan is wrong"
        )

        let orphans = members.filter { !$0.isRequirement }
        #expect(
            orphans.isEmpty,
            """
            \(orphans.count) member(s) of `extension CypressAPI` are not protocol requirements:
            \(orphans.map { "  · \($0.description) — \($0.path)" }.joined(separator: "\n"))
            An extension member is not a requirement: it has no witness-table entry and dispatches \
            statically, so every screen holding `any CypressAPI` reaches the extension body and \
            never the conformance's. That is ERRATA E125 exactly. Declare it in the protocol.
            """
        )
    }

    /// **The live half.** Erases a complete conformance to `any CypressAPI` — what every screen
    /// holds — and checks that each of the 31 calls lands on the conformance rather than on a
    /// default.
    ///
    /// The call list below is hand-written, because Swift cannot generate calls from a protocol.
    /// It is therefore checked against the *parsed* requirement set: a thirty-second requirement
    /// with no probe here fails this test rather than shrinking it, which is the only thing that
    /// keeps a hand-written list from becoming the drift it was written to prevent.
    @Test("the existential reaches the conformance, not the defaults")
    func theExistentialReachesTheConformance() async throws {
        let log = ProbeLog()
        let api: any CypressAPI = ProbeAPI(log: log)

        var wrong: [String] = []

        func check(_ expected: String, _ call: () async throws -> Void) async {
            do {
                try await call()
                wrong.append("\(expected): returned a value — a protocol-extension default answered it")
            } catch let reached as ProbeReached {
                if reached.name != expected {
                    wrong.append("\(expected): reached \(reached.name) instead")
                }
            } catch {
                wrong.append("\(expected): threw \(error) — the conformance was not reached")
            }
        }

        let coordinate = Coordinate(latitude: 37.8, longitude: -122.4)
        let viewport = MapViewport(bounds: BoundingBox(around: coordinate, radiusM: 100), zoom: 17)
        let id = UUID()
        let ticket = PhotoUploadTicket(photoID: id, destination: URL(fileURLWithPath: "/dev/null"))

        await check("mapContent") { _ = try await api.mapContent(in: viewport) }
        await check("treesNear") { _ = try await api.treesNear(coordinate, radiusM: 10, limit: 1) }
        await check("treeProfile") { _ = try await api.treeProfile(id: id) }
        await check("addTree") {
            _ = try await api.addTree(
                TreeDraft(
                    coordinate: coordinate,
                    photoLocalPath: "/dev/null",
                    attribution: Attribution(userID: nil, deviceID: id)
                )
            )
        }
        await check("claimSpecies") { _ = try await api.claimSpecies(treeID: id, speciesID: id) }
        await check("correctSpecies") { _ = try await api.correctSpecies(treeID: id, speciesID: id) }
        await check("flagWrongSpecies") { try await api.flagWrongSpecies(treeID: id) }
        await check("dismissSpeciesReview") { try await api.dismissSpeciesReview(flagID: id) }
        await check("flagNeverExisted") { try await api.flagNeverExisted(treeID: id) }
        await check("withdrawRecord") { try await api.withdrawRecord(flagID: id) }
        await check("dismissRecordReview") { try await api.dismissRecordReview(flagID: id) }
        await check("species") { _ = try await api.species(id: id) }
        await check("searchSpecies") { _ = try await api.searchSpecies(query: "oak", limit: 1) }
        await check("speciesGuide") { _ = try await api.speciesGuide(id: id, near: coordinate) }
        await check("almanac") { _ = try await api.almanac(near: coordinate) }
        await check("city") { _ = try await api.city(near: coordinate) }
        await check("sync") { _ = try await api.sync([]) }
        await check("beginPhotoUpload") {
            _ = try await api.beginPhotoUpload(
                PhotoUploadRequest(treeID: id, shotType: .fullTree, localPath: "/dev/null", capturedAt: .now)
            )
        }
        await check("uploadPhoto") { try await api.uploadPhoto(at: "/dev/null", ticket: ticket) }
        await check("photoData") { _ = try await api.photoData(id: id) }
        await check("setPhotoVote") { try await api.setPhotoVote(photoID: id, vote: .up) }
        await check("deletePhoto") { _ = try await api.deletePhoto(id: id) }
        await check("grove") { _ = try await api.grove() }
        await check("isFavorite") { _ = try await api.isFavorite(treeID: id) }
        await check("groveSpecies") { _ = try await api.groveSpecies() }
        await check("journal") { _ = try await api.journal(cursor: nil, limit: 1) }
        await check("claimDevice") { try await api.claimDevice(deviceUUID: id, userID: id) }
        await check("deviceContributions") { _ = try await api.deviceContributions() }
        await check("mapMembership") { _ = try await api.mapMembership(.favorites) }
        await check("logHazardRedirect") {
            try await api.logHazardRedirect(
                HazardRedirectEvent(treeID: id, category: .hangingOrBrokenLimb, shownAt: .now)
            )
        }
        await check("exportLatest") { _ = try await api.exportLatest(.csv) }

        #expect(
            wrong.isEmpty,
            """
            \(wrong.count) requirement(s) did not dispatch to the conformance through \
            `any CypressAPI`:
            \(wrong.map { "  · \($0)" }.joined(separator: "\n"))
            """
        )

        // The cross-check that keeps the list above tied to the protocol.
        let probed = log.seen
        let required = Set(CypressAPISurface.requirements.map(\.name))
        let unprobed = required.subtracting(probed).sorted()
        #expect(
            unprobed.isEmpty,
            """
            \(unprobed.count) `CypressAPI` requirement(s) have no call in this test, so nothing here \
            can tell whether they dispatch: \(unprobed.joined(separator: ", ")).
            Add a `ProbeAPI` method and an `await check(…)` line for each.
            """
        )

        // …and the other direction, so the list cannot outlive the protocol either. A requirement
        // that is dropped while a default keeps the call compiling would otherwise leave a probe
        // here that measures a member no conformance owes anybody.
        let stale = probed.subtracting(required).sorted()
        #expect(
            stale.isEmpty,
            """
            \(stale.count) call(s) in this test name something that is no longer a `CypressAPI` \
            requirement: \(stale.joined(separator: ", ")). Either restore the requirement or delete \
            the probe — a member reached here that the protocol does not declare is E125's shape.
            """
        )
    }

    /// **N5: the same erasure, performed on a shipping conformance over a real database.**
    ///
    /// `theExistentialReachesTheConformance` erases a purpose-built `ProbeAPI`, which proves the
    /// protocol's witness table is complete but says nothing about `LocalAPI` or `RemoteAPI`. This
    /// one erases `LocalAPI` — the conformance every screen in the shipped app is actually holding —
    /// and asks it the question whose two answers are distinguishable.
    ///
    /// **Why one requirement and not four.** Of the four value-returning defaults, three are
    /// indistinguishable from the real implementation over an empty store: `mapMembership` is `[]`
    /// either way, `deviceContributions` is `.none` either way, `isFavorite` is false either way.
    /// That coincidence is the defect's whole camouflage and it is why the bug survived. Only
    /// `speciesGuide` separates cleanly against the attached seed: the default is
    /// `SpeciesGuide(species:)`, whose `cityTreeCount` is nil — literally the "species guide with no
    /// population line" this ticket names — while `LocalAPI` counts the inventory. So this gate
    /// checks the one that can be checked, and the structural gates cover the rest.
    @Test("a shipping conformance's own witness survives the erasure")
    func aShippingConformanceSurvivesTheErasure() async throws {
        let seedURL = try #require(
            SeedDatabase.urlInBundle(Bundle(for: SeedBundleToken.self)) ?? SeedDatabase.urlInBundle(),
            "no seed database; set CYPRESS_SEED_PATH"
        )
        let store = try await CypressStore.inMemory(seedURL: seedURL)
        let seed = SeedDatabase.schemaName
        let speciesID = try await store.queue.read { connection -> UUID? in
            let statement = try connection.prepare("""
                SELECT s.uuid AS species_uuid
                  FROM \(seed).species s
                  JOIN \(seed).trees t ON t.species_current = s.id
                 WHERE t.deleted_at IS NULL
                 ORDER BY s.uuid LIMIT 1
                """)
            defer { statement.finalize() }
            return try statement.fetchOne { row in try row.uuid("species_uuid") }
        }
        let species = try #require(speciesID, "the attached seed has no species with a tree on it")

        // The erasure every screen performs. Holding the concrete type here is what E125 says
        // cannot see the defect, so the type is thrown away on purpose before the call.
        let api: any CypressAPI = LocalAPI(store: store, deviceID: UUID())
        let guide = try await api.speciesGuide(id: species, near: nil)

        #expect(
            guide.cityTreeCount != nil,
            """
            `speciesGuide` returned no population count through `any CypressAPI` over a seeded store. \
            That is exactly what `SpeciesGuide(species:)` — the protocol-extension default — returns, \
            and it is the species guide with no population line #76 exists to make unshippable. \
            LocalAPI's witness was not reached.
            """
        )
    }
}
