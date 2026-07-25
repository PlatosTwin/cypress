//
//  CypressMotion.swift
//  Cypress — DesignSystem/Tokens
//
//  The six named animation curves, and the rule that they can be switched off.
//
//  ── Where the numbers come from ────────────────────────────────────────────────────────────
//  SCREENS.md §5 gap 1 lists animation as **NOT SPECIFIED** in the screen spec and then names the
//  six curves the prototype uses, with their durations. The definitions themselves are in the
//  handoff, not in SCREENS.md — `_unzipped/design_handoff_cypress/Cypress Prototype.dc.html`
//  lines 17–22 carry the `@keyframes`, and `README.md` line 119 carries the names, the durations
//  and the sentence "Keep them subtle."
//
//      @keyframes czFade    {from{opacity:0;transform:translateY(10px)} to{opacity:1}}
//      @keyframes czSheet   {from{transform:translateY(90px);opacity:0} to{opacity:1}}
//      @keyframes czPinDrop {0%{translateY(-14px) scale(.4);opacity:0} 70%{translateY(2px) scale(1.05)} 100%{}}
//      @keyframes czFlash   {0%{opacity:.9} 100%{opacity:0}}
//      @keyframes czPulse   {0%,100%{ring 0px @ .4 alpha} 50%{ring 10px @ 0 alpha}}
//      @keyframes czPop     {0%{scale(.6);opacity:0} 60%{scale(1.08)} 100%{scale(1)}}
//
//  Two easings appear in the prototype's `animation:` shorthands and nowhere else:
//  `cubic-bezier(.22,.9,.3,1)` — the house deceleration — and `cubic-bezier(.22,1.18,.36,1)`,
//  whose second control point sits above 1 so the value overshoots and settles back. Both
//  transcribe directly onto `Animation.timingCurve`, which takes the same four numbers.
//
//  ── Why these are tokens ───────────────────────────────────────────────────────────────────
//  ARCHITECTURE §6: "Never write a raw hex or a raw font size inside a feature." A duration is
//  the same kind of literal, and the same argument applies with more force — six curves used in
//  eleven places drift apart the moment each place owns its own number. Three literals existed
//  before this pass (`MapHomeView` twice, `MapKitBasemap` once) and none of them matched.
//
//  ── Reduce Motion ──────────────────────────────────────────────────────────────────────────
//  Every animation in this app is decoration over a state change that has already happened, so
//  removing it removes nothing but the decoration. `accessibilityReduceMotion` is honoured by
//  `resolved(_:reduceMotion:)` and by the `cypress*` view modifiers below, which return `nil`
//  rather than a shorter curve: a fast animation is still an animation, and the setting is a
//  request for none. An animation that cannot be turned off is an accessibility defect.
//
//  The one thing Reduce Motion does *not* switch off is the final state. A pin that drops into
//  place is at rest in the same position either way, and a pulse that does not pulse still draws
//  its ring at the resting radius — the amber pin means "this tree needs something" through its
//  colour, and the motion is emphasis on top of a meaning that is already carried.
//

import SwiftUI

enum CypressMotion {

    // MARK: - The two easings

    /// `cubic-bezier(.22,.9,.3,1)` — the house deceleration, on every `czFade` in the prototype.
    /// Fast out of the gate, long settle.
    enum Easing {
        static let house: (Double, Double, Double, Double) = (0.22, 0.9, 0.3, 1)
        /// `cubic-bezier(.22,1.18,.36,1)` — `czSheet` and `czPinDrop`. `y1 = 1.18` is above the
        /// endpoint, so the value passes its target and comes back: the overshoot the pin-drop
        /// keyframes also draw explicitly at 70 %.
        static let overshoot: (Double, Double, Double, Double) = (0.22, 1.18, 0.36, 1)
    }

    /// The durations, verbatim from the prototype's `animation:` shorthands. Named separately from
    /// the curves because two of them are also delays and offsets — `pinDropStagger` is measured
    /// off the same five pins `czPinDrop` animates.
    enum Duration {
        /// `czFade .32s`.
        static let fade: Double = 0.32
        /// `czSheet .5s`.
        static let sheet: Double = 0.5
        /// `czPinDrop .45s`.
        static let pinDrop: Double = 0.45
        /// `czPulse 2.4s` — one full there-and-back, so each half is 1.2 s.
        static let pulse: Double = 2.4
        /// `czFlash .35s`.
        static let flash: Double = 0.35
        /// `czPop .4s`.
        static let pop: Double = 0.4

        /// The prototype's five map pins carry delays `.05 .12 .19 .26 .33` — a 0.07 s step after
        /// the first. Screen 02's three cards use `.08 .16 .24`, an 0.08 s step; 0.07 is taken as
        /// the house stagger and 02 gets it too, because two staggers one hundredth apart is not a
        /// distinction anyone can see and is a second number to keep in step.
        static let stagger: Double = 0.07
    }

    // MARK: - The six curves

    /// **czFade** — content arriving in place: the staggered candidate cards on 02, the scrim under
    /// a bottom sheet. `.32s cubic-bezier(.22,.9,.3,1)`, with a 10 pt rise.
    ///
    /// The prototype also puts `czFade` on every screen root, which is how a static HTML prototype
    /// draws a navigation push. It is deliberately *not* applied to screen roots here:
    /// `NavigationStack` already animates the push, and a second fade over the top of the system
    /// transition is two animations for one event. SCREENS.md §5 gap 1 lists navigation transitions
    /// as NOT SPECIFIED and nothing here invents one.
    static let fade = Animation.timingCurve(
        Easing.house.0, Easing.house.1, Easing.house.2, Easing.house.3,
        duration: Duration.fade
    )

    /// **czSheet** — a bottom sheet rising from 90 pt below (09, 10, 15).
    /// `.5s cubic-bezier(.22,1.18,.36,1)`.
    static let sheet = Animation.timingCurve(
        Easing.overshoot.0, Easing.overshoot.1, Easing.overshoot.2, Easing.overshoot.3,
        duration: Duration.sheet
    )

    /// **czPinDrop** — a pin falling in from 14 pt above at 0.4 scale, overshooting to 1.05.
    /// `.45s cubic-bezier(.22,1.18,.36,1)`, staggered by `Duration.stagger` down the list.
    static let pinDrop = Animation.timingCurve(
        Easing.overshoot.0, Easing.overshoot.1, Easing.overshoot.2, Easing.overshoot.3,
        duration: Duration.pinDrop
    )

    /// **czPulse** — the amber "this tree needs something" ring, breathing on a 2.4 s loop.
    ///
    /// The CSS names three keyframes: ring at 0 pt / 0.4 alpha, out to 10 pt / 0 alpha at 50 %,
    /// back at 100 %. That is a symmetric there-and-back, so it is one 1.2 s half with
    /// `autoreverses: true` rather than a hand-rolled phase — the same shape in a quarter of the
    /// code, and `Duration.pulse` is still the period a reader can check against the README.
    static let pulse = Animation
        .easeInOut(duration: Duration.pulse / 2)
        .repeatForever(autoreverses: true)

    /// **czFlash** — the shutter, `.9` alpha of white to nothing in `.35s ease`.
    static let flash = Animation.easeOut(duration: Duration.flash)

    /// **czPop** — a success mark arriving: 0.6 scale to 1.08 at 60 %, settling at 1. `.4s ease`.
    ///
    /// The overshoot is in the keyframes rather than the easing here, so this is the one curve that
    /// is better expressed as a spring than as its literal timing function: `.bouncy` with the
    /// prototype's own duration lands on the same 1.08-ish peak and settles in the same 0.4 s,
    /// and unlike a fixed curve it interrupts cleanly when a second selection lands on the first.
    static let pop = Animation.bouncy(duration: Duration.pop, extraBounce: 0.1)

    // MARK: - Not one of the six

    /// The map camera. **NOT SPECIFIED** anywhere — the prototype's map is a static image, so it
    /// has no camera to move and names no curve for one. Two literals existed before this pass
    /// (`easeInOut(0.4)` recentring on the user's fix, `easeInOut(0.35)` zooming into a cluster)
    /// and a third (`snappy(0.18)`) on the selected-pin scale.
    ///
    /// They are folded into two tokens on the house easing, because a camera move is the same
    /// gesture as `czFade` — a thing settling into place — and inventing a seventh curve for it
    /// would be inventing where transcribing was available. `camera` is slower than `fade` because
    /// it moves the whole screen; `selection` is faster because it moves one 18 pt circle.
    static let camera = Animation.timingCurve(
        Easing.house.0, Easing.house.1, Easing.house.2, Easing.house.3,
        duration: 0.4
    )

    /// The selected-pin scale on 01. See `camera`.
    static let selection = Animation.timingCurve(
        Easing.house.0, Easing.house.1, Easing.house.2, Easing.house.3,
        duration: 0.18
    )

    // MARK: - Reduce Motion

    /// `nil` when the user has asked for less motion, the animation otherwise.
    ///
    /// `nil` and not a shorter curve: `Animation` has no "off", and `withAnimation(nil)` /
    /// `.animation(nil, value:)` are how SwiftUI is told to apply the state change without one.
    static func resolved(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - The offsets the keyframes move through

/// The transform each curve starts from, kept beside the curve so a caller cannot animate the
/// right duration through the wrong distance. Every number is from the `@keyframes` block quoted
/// in this file's header.
enum CypressMotionOffset {
    /// `czFade` `translateY(10px)`.
    static let fadeRise: CGFloat = 10
    /// `czSheet` `translateY(90px)`.
    static let sheetRise: CGFloat = 90
    /// `czPinDrop` `translateY(-14px)`.
    static let pinDropRise: CGFloat = -14
    /// `czPinDrop` `scale(.4)`.
    static let pinDropScale: CGFloat = 0.4
    /// `czFlash` `opacity:.9`.
    static let flashOpacity: Double = 0.9
    /// `czPulse` — the ring's outer spread at the far end of the breath, and its alpha at the near
    /// end. `box-shadow:0 0 0 10px rgba(180,113,31,.4)`; the colour is `CypressColor.accentAmber`.
    static let pulseSpread: CGFloat = 10
    static let pulseOpacity: Double = 0.4
}

// MARK: - View modifiers

extension View {

    /// `.animation(_:value:)` that honours Reduce Motion.
    ///
    /// Use this rather than `.animation(...)` directly anywhere in `Features/` or `DesignSystem/`:
    /// the plain modifier has no way to see the setting, and a view that animates through it is
    /// the defect this whole file exists to prevent.
    func cypressAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(CypressAnimationModifier(animation: animation, value: value))
    }

    /// **czFade** on appearance, optionally staggered by position in a list.
    ///
    /// The rise and the fade both collapse under Reduce Motion — there is no animation *and* no
    /// starting offset, so the view is simply drawn where it belongs.
    func cypressFadeIn(index: Int = 0) -> some View {
        modifier(CypressFadeInModifier(index: index))
    }

    /// **czPinDrop** on appearance, staggered by position. See `CypressMotion.pinDrop`.
    func cypressPinDrop(index: Int = 0) -> some View {
        modifier(CypressPinDropModifier(index: index))
    }

    /// **czPulse** — the amber ring around a pin that needs something.
    ///
    /// Under Reduce Motion the ring is drawn at its resting radius and does not breathe. It is not
    /// removed: it is part of what the amber pin looks like, and the meaning is in the colour.
    func cypressPulse(_ color: Color, isActive: Bool = true) -> some View {
        modifier(CypressPulseModifier(color: color, isActive: isActive))
    }

    /// **czPop** — a success mark arriving. `trigger` is the value whose change means "it happened".
    func cypressPop<V: Equatable>(on trigger: V) -> some View {
        modifier(CypressPopModifier(trigger: trigger))
    }
}

// MARK: - Modifier implementations

private struct CypressAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(CypressMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct CypressFadeInModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        // `hasAppeared` starts false and is set in `onAppear`, so the *first* render is the
        // keyframe at 0 % and every render after it is the keyframe at 100 %. Under Reduce Motion
        // it is set without an animation, which lands the same view in the same place instantly.
        content
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : CypressMotionOffset.fadeRise)
            .onAppear {
                withAnimation(
                    CypressMotion
                        .resolved(CypressMotion.fade, reduceMotion: reduceMotion)?
                        .delay(Double(index) * CypressMotion.Duration.stagger)
                ) {
                    hasAppeared = true
                }
            }
    }
}

private struct CypressPinDropModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var hasDropped = false

    private var settled: Bool { hasDropped || reduceMotion }

    func body(content: Content) -> some View {
        content
            .scaleEffect(settled ? 1 : CypressMotionOffset.pinDropScale)
            .offset(y: settled ? 0 : CypressMotionOffset.pinDropRise)
            .opacity(settled ? 1 : 0)
            .onAppear {
                withAnimation(
                    CypressMotion
                        .resolved(CypressMotion.pinDrop, reduceMotion: reduceMotion)?
                        .delay(Double(index) * CypressMotion.Duration.stagger)
                ) {
                    hasDropped = true
                }
            }
    }
}

private struct CypressPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let isActive: Bool
    @State private var isExpanded = false

    func body(content: Content) -> some View {
        content.background(alignment: .center) {
            // **The ring exists only when it is switched on.** It used to be built either way and
            // then hidden by a zero spread and a zero opacity, which is one `Circle` and one shape
            // fill per host — and `MapPin` applies this modifier to *every* pin on screen 01, of
            // which only the amber one is ever active. That was hundreds of invisible circles on the
            // map's critical path (ERRATA E130). Nothing drawn changes: the inactive branch was
            // already a fully transparent circle at zero padding.
            if isActive {
                Circle()
                    .fill(color.opacity(ringOpacity))
                    .padding(-ringSpread)
                    // The ring is decoration on a pin whose own label already says what it means
                    // (C19 `MapPin.Kind.accessibilityLabel`), so it is never its own element.
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(CypressMotion.pulse) { isExpanded = true }
        }
    }

    /// Halfway out, and quiet, when the breath is switched off — the resting state of the CSS
    /// keyframes is a 0 pt ring, which would draw nothing at all and lose the halo the mock draws.
    private var ringSpread: CGFloat {
        guard isActive else { return 0 }
        if reduceMotion { return CypressMotionOffset.pulseSpread / 2 }
        return isExpanded ? CypressMotionOffset.pulseSpread : 0
    }

    private var ringOpacity: Double {
        guard isActive else { return 0 }
        if reduceMotion { return CypressMotionOffset.pulseOpacity / 2 }
        return isExpanded ? 0 : CypressMotionOffset.pulseOpacity
    }
}

private struct CypressPopModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: V
    @State private var hasPopped = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hasPopped || reduceMotion ? 1 : 0.6)
            .opacity(hasPopped || reduceMotion ? 1 : 0)
            .onAppear { pop() }
            .onChange(of: trigger) { _, _ in
                hasPopped = false
                pop()
            }
    }

    private func pop() {
        withAnimation(CypressMotion.resolved(CypressMotion.pop, reduceMotion: reduceMotion)) {
            hasPopped = true
        }
    }
}
