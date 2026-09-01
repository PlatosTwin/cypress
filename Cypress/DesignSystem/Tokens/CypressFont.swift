//
//  CypressFont.swift
//  Cypress — DesignSystem/Tokens
//
//  Source of truth: docs/distilled/SCREENS.md §1.3 (type ramp).
//  Enforces docs/ARCHITECTURE.md §6: "Never write ... a raw font size inside a feature."
//
//  Three families, per the spec page's own three roles:
//    Display · Source Serif 4    — the field guide voice   (tree names, screen titles, story)
//    Body    · Alegreya Sans     — the walking voice       (everything you do)
//    Data    · Spline Sans Mono  — the record voice        (anything that enters the record)
//
//  ── Font names ────────────────────────────────────────────────────────────────────────────
//  The TTFs live at Cypress/Resources/Fonts/. Their internal PostScript names (`name` table
//  ID 6) were read off the actual files and happen to match the filenames exactly:
//      SourceSerif4-{Regular,SemiBold,Bold,Italic}
//      AlegreyaSans-{Regular,Medium,Bold,ExtraBold,Italic}
//      SplineSansMono-{Regular,Medium,SemiBold}
//  `Font.custom` wants the PostScript name, and that is what `Face` below holds. If a face ever
//  fails to load, SwiftUI silently substitutes the system font — call
//  `CypressFont.debugDumpAvailableFamilies()` at launch to see what the runtime actually has.
//
//  ── Weight mapping ────────────────────────────────────────────────────────────────────────
//  SCREENS.md §1.3 loads Alegreya Sans at weights 400;500;700;800 only, yet the ramp table lists
//  a few styles at weight 600 (`body.14.5`, `body.12`). CSS font-matching resolves a missing 600
//  upward, so 600 → Bold (700) here. Serif 600 → SemiBold and mono 600 → SemiBold are real faces.
//  AlegreyaSans-Medium (500) is installed but no ramp row uses it; it is exposed on `Face` only.
//
//  ── Dynamic Type ──────────────────────────────────────────────────────────────────────────
//  Every style uses `.custom(_:size:relativeTo:)` so the fixed-size mock ramp still scales
//  (ARCHITECTURE §6). Sizes below are the mock's points; `relativeTo` picks the scaling curve.
//
//  ── Skipped ───────────────────────────────────────────────────────────────────────────────
//  These rows of §1.3 are chrome for the design document / the public web page, not the iOS app,
//  and are deliberately NOT modeled here:
//      web.h1, web.wordmark, latin.name @18px (W1 only), spec.h2, spec.eyebrow, spec.backToTop,
//      caption.title (its only documented use is the spec page's `<figcaption><b>`).
//  W1 is out of scope per ARCHITECTURE §8.
//
//  ── Letter-spacing / text-transform ───────────────────────────────────────────────────────
//  Neither is a font property in SwiftUI. Styles that carry tracking or uppercasing are exposed
//  as `ViewModifier`s at the bottom of this file (`.cypressMicroLabel()`, `.cypressBadge()`, …)
//  which apply font + tracking + case + token color together, so a caller cannot get them
//  half-right. The bare `Font` is still available for layout-only uses.
//

import SwiftUI
import UIKit
import CoreText

enum CypressFont {

    // MARK: - Faces (PostScript names)

    enum Face {
        // Source Serif 4 — display / serif
        static let serifRegular = "SourceSerif4-Regular"   // 400
        static let serifSemiBold = "SourceSerif4-SemiBold" // 600
        static let serifBold = "SourceSerif4-Bold"         // 700
        static let serifItalic = "SourceSerif4-Italic"     // 400 italic

        // Alegreya Sans — body / UI
        static let sansRegular = "AlegreyaSans-Regular"     // 400
        static let sansMedium = "AlegreyaSans-Medium"       // 500 — installed, unused by the ramp
        static let sansBold = "AlegreyaSans-Bold"           // 700 (also serves ramp weight 600)
        static let sansExtraBold = "AlegreyaSans-ExtraBold" // 800
        static let sansItalic = "AlegreyaSans-Italic"       // 400 italic

        // Spline Sans Mono — data / micro
        static let monoRegular = "SplineSansMono-Regular"   // 400
        static let monoMedium = "SplineSansMono-Medium"     // 500 — installed, unused by the ramp
        static let monoSemiBold = "SplineSansMono-SemiBold" // 600

        static let all: [String] = [
            serifRegular, serifSemiBold, serifBold, serifItalic,
            sansRegular, sansMedium, sansBold, sansExtraBold, sansItalic,
            monoRegular, monoMedium, monoSemiBold,
        ]
    }

    private static func font(_ face: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(face, size: size, relativeTo: style)
    }

    // MARK: - Serif · Source Serif 4

    /// `screen.title.grove` — 26 / 600. Screen 08, "My Grove".
    static let screenTitleGrove = font(Face.serifSemiBold, 26, .title2)

    /// `tree.name.hero` — 27 / 600, line-height 1.05. Screens 03, D2, 19.
    static let treeNameHero = font(Face.serifSemiBold, 27, .title2)

    /// `species.hero` — 25 / 600, line-height 1.1. Screen 07.
    static let speciesHero = font(Face.serifSemiBold, 25, .title2)

    /// `tree.name.coldstart` — 25 / 600. Screen 14.
    static let treeNameColdStart = font(Face.serifSemiBold, 25, .title2)

    /// `screen.title` — 22 / 600. Screens 02, 05, 06, 11–14, 16, 17, D3.
    static let screenTitle = font(Face.serifSemiBold, 22, .title3)

    /// `success.title` — 22 / 600. Screen 18.
    static let successTitle = font(Face.serifSemiBold, 22, .title3)

    /// `account.title` — 21 / 600. Screen 15.
    static let accountTitle = font(Face.serifSemiBold, 21, .title3)

    /// `sheet.title` — 20 / 600. Screens 09, 10.
    static let sheetTitle = font(Face.serifSemiBold, 20, .title3)

    /// `hazard.title` — 20 / 600. Screen 06.
    static let hazardTitle = font(Face.serifSemiBold, 20, .title3)

    /// `card.title.serif` — 19 / 600. Screen 02 top candidate, 08 progress.
    static let cardTitleSerif = font(Face.serifSemiBold, 19, .title3)

    /// `list.name.serif` — 17.5 / 600. Screen 01 card, 02 rows, D1 card.
    static let listNameSerif = font(Face.serifSemiBold, 17.5, .headline)

    /// `share.name` — 17 / 600. Screen 10 preview.
    static let shareName = font(Face.serifSemiBold, 17, .headline)

    // `latin.name` — serif *italic*, 400, color `text.muted`. One row, six sizes.
    // The 18px size is W1-only and is skipped. Prefer `.cypressLatinName()` so the color rides along.

    /// `latin.name` @ 15 — screens 03, 19. The app default.
    static let latinName = font(Face.serifItalic, 15, .subheadline)
    /// `latin.name` @ 14.5 — screen 14.
    static let latinName145 = font(Face.serifItalic, 14.5, .subheadline)
    /// `latin.name` @ 14 — screen 07.
    static let latinName14 = font(Face.serifItalic, 14, .subheadline)
    /// `latin.name` @ 13.5 — screen 02 top candidate.
    static let latinName135 = font(Face.serifItalic, 13.5, .footnote)
    /// `latin.name` @ 13 — screen 02 rows.
    static let latinName13 = font(Face.serifItalic, 13, .footnote)

    // MARK: - Sans · Alegreya Sans

    /// `body.16` — 16 / 700. Primary button labels.
    static let body16 = font(Face.sansBold, 16, .body)

    /// `body.15.5` — 15.5 / 700. Screen 01 FAB.
    static let body155 = font(Face.sansBold, 15.5, .body)
    /// `body.15.5` — 15.5 / 800. D1's FAB label.
    ///
    /// Not a row in §1.3: the table pairs 15.5 with weight 700 only, and D1's delta table raises the
    /// FAB to **weight 800** without changing its size. That combination has no token, so the ramp
    /// grows by one row rather than the feature rounding to 16/800 and paying half a point of size
    /// for a hundred units of weight. Both schemes' FAB is now the same size, which is what D1 says.
    static let body155ExtraBold = font(Face.sansExtraBold, 15.5, .body)

    /// `body.15` — 15 / 400, line-height 1.55. Sheet body, W1 fact rows.
    static let body15 = font(Face.sansRegular, 15, .body)
    /// `body.15` — 15 / 700. Sheet buttons.
    static let body15Bold = font(Face.sansBold, 15, .body)

    /// `body.14.5` — 14.5 / 400. Search placeholder.
    static let body145 = font(Face.sansRegular, 14.5, .subheadline)
    /// `body.14.5` — 14.5 / 600 → Bold (Alegreya Sans has no 600; see header). Chart card titles.
    static let body145SemiBold = font(Face.sansBold, 14.5, .subheadline)
    /// `body.14.5` — 14.5 / 700. Care chips.
    static let body145Bold = font(Face.sansBold, 14.5, .subheadline)

    /// `body.14` — 14 / 700. List row titles.
    static let body14 = font(Face.sansBold, 14, .subheadline)

    /// `body.13.5` — 13.5 / 400, line-height 1.45–1.55. Callouts, activity rows.
    static let body135 = font(Face.sansRegular, 13.5, .footnote)

    /// `body.13` — 13 / 400. Chips, sublabels.
    static let body13 = font(Face.sansRegular, 13, .footnote)
    /// `body.13` — 13 / 700.
    static let body13Bold = font(Face.sansBold, 13, .footnote)

    /// `body.12.5` — 12.5 / 400. Chip labels, secondary text.
    static let body125 = font(Face.sansRegular, 12.5, .caption)

    /// 11.5 / 400. The vitality anchor line (05 §3) and 17's "Notes and numbers sync on any
    /// connection".
    ///
    /// Not a row in §1.3: the ramp jumps 12 → 12.5 and never names 11.5, yet two screens set it.
    /// The ramp grows by one row rather than the anchor sentence being rounded to 12 — this is the
    /// smallest type in the app that carries meaning a rating depends on (D3). See ERRATA (E26).
    static let body115 = font(Face.sansRegular, 11.5, .caption)

    /// The drawn size of the three `body.12` faces, named once so `body12HalfXHeight` below cannot
    /// drift away from the face it claims to measure.
    private static let body12Size: CGFloat = 12

    /// `body.12` — 12 / 400. Footnotes.
    static let body12 = font(Face.sansRegular, body12Size, .caption)
    /// `body.12` — 12 / 600 → Bold (see header). Action-row labels.
    static let body12SemiBold = font(Face.sansBold, body12Size, .caption)
    /// `body.12` — 12 / 700.
    static let body12Bold = font(Face.sansBold, body12Size, .caption)

    /// Half `body12`'s x-height, in points, at the **default** content size.
    ///
    /// **Read off the font, not guessed.** `HeaderPillButton` centers its drawn chevron on the
    /// label's optical midline, and that midline is half an x-height above the baseline — so this
    /// is the offset a baseline alignment needs to become a midline alignment. Hard-coding a ratio
    /// would have been a number nobody could check; `UIFont.xHeight` is the same metric the
    /// renderer uses to set the glyphs this is being aligned to.
    ///
    /// **The fallback is the face that would actually draw.** When a custom face is missing,
    /// `Font.custom` silently falls back to the system font at the same size
    /// (`debugDumpAvailableFamilies` exists because that failure is invisible), so measuring the
    /// system font at `body12Size` measures whatever the reader is really looking at rather than
    /// substituting an invented constant for a face that is not there.
    ///
    /// Callers must scale it — `@ScaledMetric(relativeTo: .caption)`, the curve `body12` is built
    /// on — because this is one setting's value, like every other point size in this file.
    static let body12HalfXHeight: CGFloat = {
        let face = UIFont(name: Face.sansRegular, size: body12Size)
            ?? UIFont.systemFont(ofSize: body12Size)
        return face.xHeight / 2
    }()

    /// `micro.label` — 11 / 800, tracking .08em, uppercase, `text.faint`.
    /// Prefer `.cypressMicroLabel()`; this bare font omits tracking, case and color.
    static let microLabel = font(Face.sansExtraBold, 11, .caption2)

    /// `micro.label.10` — 10 / 700, tracking .08em, uppercase, `text.faint`. Stat-card labels.
    /// Prefer `.cypressMicroLabel10()`.
    static let microLabel10 = font(Face.sansBold, 10, .caption2)

    /// `badge` — 11 / 700, tracking .02em. `THRIVING`, `REMOVED`, `PLANTED 2024`.
    /// Prefer `.cypressBadge(color:)`.
    static let badge = font(Face.sansBold, 11, .caption2)

    // MARK: - Mono · Spline Sans Mono

    /// `mono.13` — 13 / 400. Type-sample data line.
    static let mono13 = font(Face.monoRegular, 13, .footnote)

    /// `mono.12` — 12 / 400. Distances, percentages.
    static let mono12 = font(Face.monoRegular, 12, .caption)

    /// `mono.11` — 11 / 400. Timestamps, states.
    static let mono11 = font(Face.monoRegular, 11, .caption2)
    /// `mono.11` — 11 / 600.
    static let mono11SemiBold = font(Face.monoSemiBold, 11, .caption2)
    /// `mono.11` — 11 / 700. Spline Sans Mono tops out at 600; 700 resolves to SemiBold.
    static let mono11Bold = font(Face.monoSemiBold, 11, .caption2)

    /// `mono.10.5` — 10.5 / 400. Photo-count pill, public URL.
    static let mono105 = font(Face.monoRegular, 10.5, .caption2)

    /// `mono.10` — 10 / 400. Chart axis labels.
    static let mono10 = font(Face.monoRegular, 10, .caption2)

    /// `mono.9.5` — 9.5 / 600, tracking .14em, uppercase. "Foliage through the year".
    /// Prefer `.cypressMonoSectionLabel()`.
    static let mono95 = font(Face.monoSemiBold, 9.5, .caption2)

    /// `mono.9` — 9 / 600, tracking .16–.18em. Map street labels.
    /// Prefer `.cypressMapLabel(_:tracking:)`.
    static let mono9 = font(Face.monoSemiBold, 9, .caption2)

    /// `mono.readout` — 56 / 600, tracking −.02em. Screen 16 measurement readout.
    /// Prefer `.cypressMonoReadout()`.
    static let monoReadout = font(Face.monoSemiBold, 56, .largeTitle)

    /// `mono.keypad` — 19 / 600. Screen 16 numeric keypad.
    static let monoKeypad = font(Face.monoSemiBold, 19, .title3)

    /// `mono.stat` — 14.5 / 600. Stat card values.
    static let monoStat = font(Face.monoSemiBold, 14.5, .subheadline)

    /// `mono.statBig` — 17 / 600. Screen 07 counts.
    static let monoStatBig = font(Face.monoSemiBold, 17, .headline)

    // MARK: - Tracking
    //
    // CSS letter-spacing is in `em`; SwiftUI `.tracking()` is in points. Converted at the mock's
    // size: `points = size × em`. Tracking is intentionally NOT scaled with Dynamic Type — at AX
    // sizes the extra letter-spacing hurts more than it helps on 9–11pt uppercase labels.

    enum Tracking {
        /// `micro.label` — 11 × .08em.
        static let microLabel: CGFloat = 0.88
        /// `micro.label.10` — 10 × .08em.
        static let microLabel10: CGFloat = 0.80
        /// `badge` — 11 × .02em.
        static let badge: CGFloat = 0.22
        /// `mono.9.5` — 9.5 × .14em.
        static let monoSectionLabel: CGFloat = 1.33
        /// `mono.9` — 9 × .16em (the tight end of the doc's .16–.18em range).
        static let mapLabel: CGFloat = 1.44
        /// `mono.9` — 9 × .18em (the loose end).
        static let mapLabelWide: CGFloat = 1.62
        /// `mono.readout` — 56 × −.02em.
        static let monoReadout: CGFloat = -1.12
    }

    // MARK: - Line spacing
    //
    // CSS `line-height` is a multiple of the font size and includes the glyph box; SwiftUI's
    // `.lineSpacing()` is the *extra* gap between lines. A custom font's natural line height sits
    // near 1.2× its size, so `lineSpacing ≈ size × (lineHeight − 1.2)`. These are approximations
    // of the mock, not exact transcriptions — the doc gives no leading values.

    enum LineSpacing {
        /// `body.15`, line-height 1.55.
        static let body15: CGFloat = 5.25
        /// `body.13.5`, line-height 1.45–1.55 → 1.50.
        static let body135: CGFloat = 4.05
        /// `body.12.5`, line-height 1.45 — 12's attention-card body (SCREENS.md 12 §4).
        static let body125: CGFloat = 3.125
        /// The 11.5pt anchor line, line-height 1.3 (SCREENS.md 05 §3).
        static let body115: CGFloat = 1.15
        /// `species.hero`, line-height 1.1 — tighter than natural; clamp at 0.
        static let speciesHero: CGFloat = 0
        /// `tree.name.hero`, line-height 1.05 — tighter than natural; clamp at 0.
        static let treeNameHero: CGFloat = 0
    }

    // MARK: - Runtime helpers

    /// Prints every font family and face the process can actually see.
    ///
    /// The bundled TTFs must either be listed under `UIAppFonts` in Info.plist or registered at
    /// runtime via `registerBundledFonts()`. If a Cypress face is missing from this dump,
    /// `Font.custom` is silently falling back to the system font.
    static func debugDumpAvailableFamilies() {
        print("── CypressFont · UIFont.familyNames ──────────────────────────────")
        for family in UIFont.familyNames.sorted() {
            print("  \(family)")
            for name in UIFont.fontNames(forFamilyName: family).sorted() {
                print("      \(name)")
            }
        }
        print("── CypressFont · expected faces ──────────────────────────────────")
        for face in Face.all {
            let loaded = UIFont(name: face, size: 12) != nil
            print("  \(loaded ? "✓" : "✗")  \(face)")
        }
        print("──────────────────────────────────────────────────────────────────")
    }

    /// Registers every `.ttf` shipped in the bundle that the process cannot already see.
    ///
    /// This exists so the design system does not depend on an Info.plist edit (see ARCHITECTURE §2:
    /// the project file is not hand-edited). `Info.plist` *does* currently list all twelve faces
    /// under `UIAppFonts`, so in the shipping app every one of them is already registered by the time
    /// this runs, and this is a safety net rather than the mechanism.
    ///
    /// ── Why it asks before it registers ───────────────────────────────────────────────────────
    /// Registering an already-registered file is harmless — `CTFontManagerRegisterFontsForURL`
    /// returns false and the error is dropped — but it is not *silent*: Core Text writes
    /// `GSFont: file already registered` to the console, once per face, on every launch. Twelve
    /// lines of noise in a log somebody is reading to find real problems, and a log nobody trusts is
    /// a log nobody reads. So the file's PostScript name is read first and the registration is
    /// skipped when that face already resolves.
    ///
    /// The check is deliberately fail-open: if the name cannot be read the font is registered anyway,
    /// because a missing face is a much worse defect than a console line. `Font.custom` falls back to
    /// the system font *silently*, so a face that failed to load looks like a design choice.
    ///
    /// Call once from the composition root in `App/`. Returns the number of faces *newly* registered,
    /// so a second call legitimately returns 0 — and, now, so does the first one in the shipping app.
    /// It is not a count of faces available; `BundleContractTests` is what checks that.
    @discardableResult
    static func registerBundledFonts(in bundle: Bundle = .main) -> Int {
        var registered = 0
        for url in unregisteredBundledFonts(in: bundle) {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            } else {
                error?.release()
            }
        }
        return registered
    }

    /// The bundled faces this process cannot already see — exactly the files
    /// `registerBundledFonts` will hand to Core Text.
    ///
    /// **Separated out because the return value of `registerBundledFonts` cannot tell the two
    /// worlds apart.** It counts faces *newly* registered, and that was 0 both before this
    /// skip existed and after: before, because every call failed with `alreadyRegistered`; after,
    /// because every call is skipped. A test asserting `== 0` would have passed against the version
    /// that printed twelve `GSFont: file already registered` lines on every launch. This is the
    /// value that actually distinguishes them — empty means Core Text is never asked, which is the
    /// only thing that makes the console quiet.
    static func unregisteredBundledFonts(in bundle: Bundle = .main) -> [URL] {
        (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            .filter { !isAlreadyRegistered($0) }
    }

    /// Whether the face in this file already resolves by name.
    ///
    /// Fail-open by design: an unreadable file returns `false` so the caller still tries to register
    /// it. See `registerBundledFonts`.
    private static func isAlreadyRegistered(_ url: URL) -> Bool {
        guard
            let provider = CGDataProvider(url: url as CFURL),
            let font = CGFont(provider),
            let postScriptName = font.postScriptName as String?
        else { return false }
        return UIFont(name: postScriptName, size: 12) != nil
    }
}

// MARK: - Compound text styles
//
// Anything in §1.3 that carries tracking, a text-transform, or a mandated color is exposed only
// as a modifier, so the three cannot drift apart at a call site.

extension View {

    /// The ceiling for typographic furniture — see `cypressTypographicFurniture()`.
    ///
    /// `.accessibility1` and not `.large`: the point is to keep a mono micro-label legible for
    /// someone who needs larger type, not to freeze it at the mock's size and call that a
    /// decision. Between `.large` and `.accessibility1` a 9.5 pt label roughly doubles, which is
    /// most of the benefit; past it the tracking stops making sense (below) and twelve of them in
    /// a row stop fitting on any phone.
    ///
    /// Deliberately *not* applied to prose. Every sentence in the app scales the whole way.

    /// Caps Dynamic Type for a label that is furniture rather than content.
    ///
    /// Three kinds of thing in this app are drawn *as type* and read as *structure*: the uppercase
    /// mono micro-labels with wide letter-spacing (`FOLIAGE THROUGH THE YEAR`), the twelve single
    /// letters under a month axis or a season strip, and the count inside a map pin. None of them
    /// is a sentence. A reader who needs larger type needs the sentence larger; the rule above the
    /// sentence is a divider that happens to be made of letters.
    ///
    /// There is a concrete failure behind this rather than a preference. `CypressFont.Tracking` is
    /// in points, fixed at the mock's size, and its own note says so: "tracking is intentionally
    /// NOT scaled with Dynamic Type". So an unclamped 9.5 pt label at AX5 renders at roughly 3×
    /// with the *same* 1.33 pt of letter-spacing — the wide tracking that makes it read as a rule
    /// is gone, and what is left is large cramped uppercase. Twelve month letters at AX5 need more
    /// width than any iPhone has, at which point the strip they label stops lining up with them,
    /// which is the entire information in a season strip.
    ///
    /// ARCHITECTURE §6 says to verify the field screens at AX1; this is the answer for the one
    /// class of label where scaling past that makes the screen worse rather than better.
    func cypressTypographicFurniture() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// `micro.label` — 11 / 800 Alegreya Sans, tracking .08em, UPPERCASE, `text.faint`.
    /// Section headers inside screens.
    func cypressMicroLabel(color: Color = CypressColor.textFaint) -> some View {
        font(CypressFont.microLabel)
            .tracking(CypressFont.Tracking.microLabel)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .cypressTypographicFurniture()
    }

    /// `micro.label.10` — 10 / 700 Alegreya Sans, tracking .08em, UPPERCASE, `text.faint`.
    /// Stat-card labels.
    func cypressMicroLabel10(color: Color = CypressColor.textFaint) -> some View {
        font(CypressFont.microLabel10)
            .tracking(CypressFont.Tracking.microLabel10)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .cypressTypographicFurniture()
    }

    /// `badge` — 11 / 700 Alegreya Sans, tracking .02em, UPPERCASE.
    /// `THRIVING`, `REMOVED`, `PLANTED 2024`. Color is per-badge, so it is required.
    func cypressBadge(color: Color) -> some View {
        font(CypressFont.badge)
            .tracking(CypressFont.Tracking.badge)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// `mono.9.5` — 9.5 / 600 Spline Sans Mono, tracking .14em, UPPERCASE.
    /// "Foliage through the year" and its siblings.
    func cypressMonoSectionLabel(color: Color = CypressColor.textFaint) -> some View {
        font(CypressFont.mono95)
            .tracking(CypressFont.Tracking.monoSectionLabel)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .cypressTypographicFurniture()
    }

    /// `mono.9` — 9 / 600 Spline Sans Mono, tracking .16em (`wide: true` → .18em).
    /// Map street / park / ocean labels; pass the matching `text.mapLabel` token.
    func cypressMapLabel(color: Color, wide: Bool = false) -> some View {
        font(CypressFont.mono9)
            .tracking(wide ? CypressFont.Tracking.mapLabelWide : CypressFont.Tracking.mapLabel)
            .foregroundStyle(color)
            // A street name printed across a map is positioned by geography, not by a layout that
            // can reflow around it. See `cypressTypographicFurniture()`.
            .cypressTypographicFurniture()
    }

    /// `mono.readout` — 56 / 600 Spline Sans Mono, tracking −.02em, `text.ink`.
    /// Screen 16 measurement readout.
    func cypressMonoReadout(color: Color = CypressColor.textInk) -> some View {
        font(CypressFont.monoReadout)
            .tracking(CypressFont.Tracking.monoReadout)
            .foregroundStyle(color)
    }

    /// `mono.stat` — 14.5 / 600 Spline Sans Mono, `text.ink`. Stat card values.
    func cypressMonoStat(color: Color = CypressColor.textInk) -> some View {
        font(CypressFont.monoStat).foregroundStyle(color)
    }

    /// `latin.name` — Source Serif 4 italic, 400, `text.muted`. Defaults to the 15pt app size.
    func cypressLatinName(_ font: Font = CypressFont.latinName) -> some View {
        self.font(font).foregroundStyle(CypressColor.textMuted)
    }

    /// `body.15` — 15 / 400 Alegreya Sans with the mock's 1.55 line-height, `text.body`.
    func cypressBody15(color: Color = CypressColor.textBody) -> some View {
        font(CypressFont.body15)
            .lineSpacing(CypressFont.LineSpacing.body15)
            .foregroundStyle(color)
    }

    /// `body.13.5` — 13.5 / 400 Alegreya Sans with the mock's ~1.5 line-height, `text.body`.
    /// Callouts, activity rows.
    func cypressBody135(color: Color = CypressColor.textBody) -> some View {
        font(CypressFont.body135)
            .lineSpacing(CypressFont.LineSpacing.body135)
            .foregroundStyle(color)
    }
}

// MARK: - §2 component styles
//
// Weight/size combinations that SCREENS.md §2 (the C1–C30 catalog) asks for but §1.3's ramp table
// does not enumerate as their own row. Every one names the §2 line it comes from. Same family
// mapping as the header: Alegreya Sans 600 → Bold, Spline Sans Mono 700 → SemiBold (the face tops
// out at 600).

extension CypressFont {

    private static func styled(_ size: CGFloat, _ face: String, _ style: Font.TextStyle) -> Font {
        .custom(face, size: size, relativeTo: style)
    }

    /// `body.20` — 20 / 600 → Bold. C29 locked species tile `?`.
    static let body20SemiBold = styled(20, Face.sansBold, .title3)

    /// `body.16` — 16 / 800. C6 dark and 04 variants.
    static let body16ExtraBold = styled(16, Face.sansExtraBold, .body)

    /// `body.14.5` — 14.5 / 800. C5 dark selected segment, C6 dark CTA.
    static let body145ExtraBold = styled(14.5, Face.sansExtraBold, .subheadline)

    /// `body.14` — 14 / 400. C5 segment label, idle (16).
    static let body14Regular = styled(14, Face.sansRegular, .subheadline)
    /// `body.14` — 14 / 800. C5 dark selected segment at the 16 size.
    static let body14ExtraBold = styled(14, Face.sansExtraBold, .subheadline)

    /// `body.13.5` — 13.5 / 700. C9 row lead-in, C14 callout lead-in, C25 setting title.
    static let body135Bold = styled(13.5, Face.sansBold, .footnote)

    /// `body.13` — 13 / 800. C4 dark flag chips (D3), C19 cluster label.
    static let body13ExtraBold = styled(13, Face.sansExtraBold, .footnote)

    /// `body.12.5` — 12.5 / 700. C4 shot-type chip, on (04).
    static let body125Bold = styled(12.5, Face.sansBold, .caption)
    /// `body.12` — 12 / 800. C19 cluster label at the 30pt size.
    static let body12ExtraBold = styled(12, Face.sansExtraBold, .caption)

    /// `body.11` — 11 / 400.
    static let body11 = styled(11, Face.sansRegular, .caption2)
    /// `body.11` — 11 / 600 → Bold. C16 inactive tab label, C29 tile label.
    static let body11SemiBold = styled(11, Face.sansBold, .caption2)
    /// `body.11` — 11 / 700. C2 hero eyebrow (prefer `.cypressHeroEyebrow()`), C29 tile label.
    static let body11Bold = styled(11, Face.sansBold, .caption2)
    /// `body.11` — 11 / 800. C16 active tab label.
    static let body11ExtraBold = styled(11, Face.sansExtraBold, .caption2)

    /// `body.10.5` — 10.5 / 400. Screen 10's destination labels (`Messages`, `AirDrop`…), which
    /// SCREENS.md 10 §4 gives as "label 10.5px `#66735F`" with no weight, so the page default.
    static let body105 = styled(10.5, Face.sansRegular, .caption2)
    /// `body.10.5` — 10.5 / 600 → Bold. C12 method badge.
    ///
    /// **Family NOT SPECIFIED** in §1.3 for this row: §2 gives "10.5px/600" with no family, and the
    /// page's `body` default is Alegreya Sans, so Sans is used. Mono is reserved for the *number*,
    /// which the badge annotates rather than replaces.
    static let body105SemiBold = styled(10.5, Face.sansBold, .caption2)
    /// `body.10.5` — 10.5 / 700. C7-adjacent eyebrows (07 hero `Field guide`).
    static let body105Bold = styled(10.5, Face.sansBold, .caption2)
    /// `body.10.5` — 10.5 / 800. 02 candidate eyebrow.
    static let body105ExtraBold = styled(10.5, Face.sansExtraBold, .caption2)

    /// `body.10` — 10 / 800. C26 avatar initial.
    static let body10ExtraBold = styled(10, Face.sansExtraBold, .caption2)

    /// `body.8.5` — 8.5 / 600 → Bold. C3 month row under the season strip.
    static let body85SemiBold = styled(8.5, Face.sansBold, .caption2)

    /// `mono.14` — 14 / 600. C27 progress ring label.
    static let mono14SemiBold = styled(14, Face.monoSemiBold, .subheadline)
    /// `mono.13.5` — 13.5 / 600 (11 §5 asks for "mono bold"; the face tops out at 600).
    /// The value column of screen 11's measurement log, at that row's own 13.5px size.
    static let mono135SemiBold = styled(13.5, Face.monoSemiBold, .footnote)
    /// `mono.13` — 13 / 600 (§2 asks for 700; the face tops out at 600). C23 latest-value label.
    static let mono13SemiBold = styled(13, Face.monoSemiBold, .footnote)
    /// `mono.12` — 12 / 600. C23 series totals, 17 outbox numeral tile.
    static let mono12SemiBold = styled(12, Face.monoSemiBold, .caption)
    /// `mono.10` — 10 / 600. C9 `SYNC` tile.
    static let mono10SemiBold = styled(10, Face.monoSemiBold, .caption2)

    /// Tracking values §2 introduces on top of §1.3's.
    enum ComponentTracking {
        /// C2 hero eyebrow — 11 × .06em.
        static let heroEyebrow: CGFloat = 0.66
        /// 07 hero eyebrow — 10.5 × .1em.
        static let speciesEyebrow: CGFloat = 1.05
        /// 02 candidate eyebrow — 10.5 × .08em.
        static let candidateEyebrow: CGFloat = 0.84
    }
}

extension View {
    /// C2 bottom-left hero eyebrow — 11 / 700, tracking .06em, UPPERCASE, `text.onPhoto`.
    func cypressHeroEyebrow(color: Color = CypressColor.textOnPhoto) -> some View {
        font(CypressFont.body11Bold)
            .tracking(CypressFont.ComponentTracking.heroEyebrow)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
