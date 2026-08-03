import Foundation
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import Cypress

/// **The species colouring on screen 01 (task #80), and the selected pin (task #89).**
///
/// Tasks #80 and #89. What these two changes can get wrong is not "the wrong hue" — a screenshot
/// finds that. It is the four things a screenshot cannot see:
///
/// 1. **The bitmap count going unbounded.** The marker cache is keyed on `MapPin.Kind`, and the whole
///    reason `MapSpeciesSlot` exists — rather than a colour per species — is that 569 species would
///    make the key unbounded and put the map back where E130 and the MapKit swap found it. The bound
///    is asserted here as a number, so widening the enum without thinking fails a test.
/// 2. **Two species sharing a colour.** The claim the encoding makes is "same colour ⇒ same species".
///    It is only true if slots are unique per viewport and the residual class carries no slot at all.
/// 3. **A species colour eating a reserved meaning.** Amber means "this tree needs something", dashes
///    mean unverified, grey and hollow mean no living tree. None of them may become a species colour,
///    and none of those pins may even be *counted* toward a slot.
/// 4. **Colours reshuffling on a pan.** A palette recomputed from scratch permutes on every fetch,
///    which is E130's badge re-keying in another costume.
@MainActor
@Suite("Map species colouring and selection")
struct MapSpeciesColorTests {

    // MARK: - Fixtures

    private static func pin(
        species: UUID?,
        status: TreeStatus = .alive,
        source: TreeSource = .cityImport,
        verification: VerificationState = .cityRecord
    ) -> TreePin {
        TreePin(
            id: UUID(),
            coordinate: Coordinate(latitude: 37.77, longitude: -122.42),
            status: status,
            source: source,
            verificationState: verification,
            speciesID: species
        )
    }

    private static func pins(_ species: UUID, _ count: Int) -> [TreePin] {
        (0..<count).map { _ in pin(species: species) }
    }

    /// Sorted so the fixtures below can rely on `a < b < c < d < e` as UUID strings — the palette's
    /// tie-break is the uuid string, and a test whose ties resolve differently on each run is worse
    /// than no test.
    private static func ids(_ count: Int) -> [UUID] {
        (0..<(count * 4)).map { _ in UUID() }
            .sorted { $0.uuidString < $1.uuidString }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Who gets a slot

    @Test("the four commonest species get the four slots, in rank order")
    func ranksByCount() {
        let id = Self.ids(5)
        let palette = MapSpeciesPalette.assign(
            pins: Self.pins(id[0], 2) + Self.pins(id[1], 9) + Self.pins(id[2], 5)
                + Self.pins(id[3], 3) + Self.pins(id[4], 7)
        )
        #expect(palette.entries.map(\.slot) == MapSpeciesSlot.allCases)
        #expect(palette.entries.map(\.speciesID) == [id[1], id[4], id[2], id[3]])
        // Five species, four slots: the smallest is the residual and draws today's green pin.
        #expect(palette.slot(for: id[0]) == nil)
    }

    @Test("a species with one pin in view is not worth a slot")
    func singletonsAreNotColored() {
        let id = Self.ids(4)
        let palette = MapSpeciesPalette.assign(
            pins: Self.pins(id[0], 4) + Self.pins(id[1], 1) + Self.pins(id[2], 1) + Self.pins(id[3], 1)
        )
        #expect(palette.entries.count == 1)
        #expect(palette.entries.first?.speciesID == id[0])
        for singleton in id.dropFirst() {
            #expect(
                palette.slot(for: singleton) == nil,
                "a species with one pin on screen has nothing to be the same as, so a slot on it is spent"
            )
        }
    }

    @Test("a tree with no species resolved never takes a slot")
    func unidentifiedTreesTakeNoSlot() {
        let palette = MapSpeciesPalette.assign(pins: (0..<20).map { _ in Self.pin(species: nil) })
        #expect(palette.entries.isEmpty)
        #expect(palette.slot(for: nil) == nil)
    }

    @Test("the palette is the same palette whatever order the rows arrived in")
    func assignmentIsDeterministic() {
        let id = Self.ids(4)
        let all = Self.pins(id[0], 3) + Self.pins(id[1], 3) + Self.pins(id[2], 3) + Self.pins(id[3], 3)
        let first = MapSpeciesPalette.assign(pins: all)
        for _ in 0..<12 {
            let shuffled = MapSpeciesPalette.assign(pins: all.shuffled())
            #expect(
                shuffled.entries.map(\.speciesID) == first.entries.map(\.speciesID),
                "a four-way tie resolved differently on a reshuffle; the tie-break is not deterministic"
            )
        }
        // …and the tie-break is the uuid string, ascending.
        #expect(first.entries.map(\.speciesID) == id)
    }

    // MARK: - The reserved meanings

    @Test("only a pin that would already be a plain city tree can take a species colour")
    func reservedPinsKeepTheirFills() {
        let id = UUID()
        let cases: [(String, TreePin)] = [
            ("needs care (amber is reserved for that)", Self.pin(species: id, status: .declining)),
            ("removed (there is no living tree)", Self.pin(species: id, status: .removed)),
            ("dead reported", Self.pin(species: id, status: .deadReported)),
            ("vacant site (there never was a tree)", Self.pin(species: id, status: .vacantSite)),
            (
                "unverified community (DECISIONS §3.16)",
                Self.pin(species: id, source: .community, verification: .unverified)
            ),
        ]
        // A palette that *does* hold this species, so the only thing under test is the pin's own kind.
        let palette = MapSpeciesPalette.assign(pins: Self.pins(id, 6))
        #expect(palette.slot(for: id) == .a)
        for (what, pin) in cases {
            let plain = MapPinKind.kind(for: pin)
            #expect(
                MapPinKind.kind(for: pin, palette: palette) == plain,
                "\(what): the species colouring replaced a fill that already means something else"
            )
        }
        // And the live one does take it.
        #expect(MapPinKind.kind(for: Self.pin(species: id), palette: palette) == .cityTreeSpecies(.a))
    }

    @Test("pins that cannot be coloured are not counted toward a slot either")
    func reservedPinsDoNotVote() {
        let id = Self.ids(2)
        // Nine memorials of one species against two live trees of another: the memorials must not
        // win a slot, and must not push the live species out of one.
        let palette = MapSpeciesPalette.assign(
            pins: (0..<9).map { _ in Self.pin(species: id[0], status: .removed) } + Self.pins(id[1], 2)
        )
        #expect(palette.entries.map(\.speciesID) == [id[1]])
        #expect(palette.slot(for: id[0]) == nil)
    }

    // MARK: - Stickiness

    @Test("a species that already holds a slot keeps it when a pan reorders the counts")
    func slotsAreSticky() {
        let id = Self.ids(3)
        let before = MapSpeciesPalette.assign(
            pins: Self.pins(id[0], 9) + Self.pins(id[1], 5) + Self.pins(id[2], 2)
        )
        #expect(before.slot(for: id[0]) == .a)
        #expect(before.slot(for: id[1]) == .b)
        #expect(before.slot(for: id[2]) == .c)

        // The reader pans one block. The same three species are in view; the order has inverted.
        let after = MapSpeciesPalette.assign(
            pins: Self.pins(id[0], 2) + Self.pins(id[1], 4) + Self.pins(id[2], 11),
            previous: before
        )
        for species in id {
            #expect(
                after.slot(for: species) == before.slot(for: species),
                """
                a species changed colour because the camera moved. Colours that permute on a pan are \
                E130's cluster badges re-keying, and a reader who has learnt "the purple ones" loses \
                that with every gesture.
                """
            )
        }
        // The ranking still reports the new order — it is only the *colour* that is held.
        #expect(after.entries.map(\.speciesID) == [id[2], id[1], id[0]])
    }

    @Test("a species that leaves the viewport frees its slot for whoever arrives")
    func slotsAreReusedWhenVacated() {
        let id = Self.ids(5)
        let before = MapSpeciesPalette.assign(
            pins: Self.pins(id[0], 9) + Self.pins(id[1], 5) + Self.pins(id[2], 4) + Self.pins(id[3], 3)
        )
        #expect(before.slot(for: id[1]) == .b)
        // id[1] pans off screen; id[4] arrives.
        let after = MapSpeciesPalette.assign(
            pins: Self.pins(id[0], 9) + Self.pins(id[2], 4) + Self.pins(id[3], 3) + Self.pins(id[4], 2),
            previous: before
        )
        #expect(after.slot(for: id[1]) == nil)
        #expect(after.slot(for: id[0]) == .a, "the ones that stayed did not move")
        #expect(after.slot(for: id[2]) == .c)
        #expect(after.slot(for: id[3]) == .d)
        #expect(after.slot(for: id[4]) == .b, "the newcomer took the freed slot rather than a fifth one")
    }

    @Test("no two species in one viewport ever share a colour")
    func slotsAreUniquePerViewport() {
        let id = Self.ids(4)
        var palette = MapSpeciesPalette.assign(pins: Self.pins(id[0], 5) + Self.pins(id[1], 4))
        // Twenty pans' worth of churn, each carrying the previous palette forward.
        for step in 0..<20 {
            let counts = (0..<4).map { 2 + ($0 * 3 + step * 5) % 11 }
            palette = MapSpeciesPalette.assign(
                pins: zip(id, counts).flatMap { Self.pins($0.0, $0.1) },
                previous: palette
            )
            let slots = palette.entries.map(\.slot)
            #expect(
                Set(slots).count == slots.count,
                "two species held the same slot after \(step + 1) pans — the encoding's one claim is broken"
            )
        }
    }

    // MARK: - The bitmap budget

    /// **The number this whole design exists to keep small.**
    ///
    /// `MapPinImage` caches one bitmap per `MapPin.Kind` per appearance. Cluster badges are keyed on
    /// their count and are therefore unbounded in principle — that is why the cache has a ceiling —
    /// but the *pin* vocabulary is a closed enum and must stay countable. Four slots is what four
    /// colours cost: twelve kinds, twenty-four bitmaps.
    // `Cypress.MapPin`, spelled out: MapKit ships a deprecated `MapPin` of its own and this file
    // imports MapKit for `MKAnnotationView`.
    private static let everyFixedKind: [Cypress.MapPin.Kind] =
        [.cityTree] + MapSpeciesSlot.allCases.map { Cypress.MapPin.Kind.cityTreeSpecies($0) }
            + [.needsCare, .community, .removed, .vacantSite, .gps, .routeDone, .routeActive]

    @Test("the whole pin vocabulary is twelve kinds and twenty-four bitmaps")
    func theBitmapCountIsBounded() {
        #expect(
            Self.everyFixedKind.count == 12,
            """
            the fixed pin vocabulary is no longer twelve kinds. It was 8 before the species slots and \
            12 after, which is 16 cached bitmaps before and 24 after. If a kind was added, say so in \
            ERRATA and move this number; if a *species* was made a kind, stop — that is 569 of them \
            and the cache ceiling is \(MapPinImage.capacity).
            """
        )
        #expect(Set(Self.everyFixedKind).count == Self.everyFixedKind.count)
        MapPinImage.flush()
        for kind in Self.everyFixedKind {
            for isDark in [false, true] {
                #expect(
                    MapPinImage.image(for: kind, isDark: isDark) != nil,
                    "\(kind) rendered no image in \(isDark ? "dark" : "light") — that marker is invisible"
                )
            }
        }
        #expect(MapPinImage.count == 24, "\(MapPinImage.count) bitmaps for twelve kinds in two appearances")
        #expect(MapPinImage.count < MapPinImage.capacity)
        MapPinImage.flush()
    }

    @Test("the four slots are four different pictures, in both appearances")
    func slotsRenderDifferently() {
        for isDark in [false, true] {
            MapPinImage.flush()
            let images = MapSpeciesSlot.allCases.compactMap {
                MapPinImage.image(for: .cityTreeSpecies($0), isDark: isDark)
            }
            #expect(images.count == MapSpeciesSlot.allCases.count)
            // Distinct objects, which is what the cache key promises. Distinct *pixels* is what
            // `ContrastTests` and the screenshots are for.
            #expect(Set(images.map { ObjectIdentifier($0) }).count == images.count)
            let plain = MapPinImage.image(for: .cityTree, isDark: isDark)
            #expect(plain != nil)
            #expect(!images.contains { $0 === plain })
        }
        MapPinImage.flush()
    }

    @Test("selection adds no bitmaps at all")
    func selectionIsFreeOfTheCache() {
        MapPinImage.flush()
        let view = MapMarkerView(
            annotation: TreePinAnnotation(pin: Self.pin(species: nil)),
            reuseIdentifier: MapMarkerView.reuseIdentifier
        )
        view.apply(annotation: TreePinAnnotation(pin: Self.pin(species: nil)), isDark: false)
        let afterDrawing = MapPinImage.count
        view.setSelectedAppearance(true)
        view.setSelectedAppearance(false)
        view.setSelectedAppearance(true)
        #expect(
            MapPinImage.count == afterDrawing,
            """
            selecting a pin rasterised something. The reticle is a `CALayer` precisely so that a \
            selected variant of every kind does not double the cache — see MapLayout's note and \
            E149.
            """
        )
        MapPinImage.flush()
    }

    // MARK: - The annotation layer notices

    @Test("an annotation's kind carries the palette, so the diff can see a colour change")
    func annotationKindTracksThePalette() {
        let id = UUID()
        let pin = Self.pin(species: id)
        let colored = MapSpeciesPalette.assign(pins: Self.pins(id, 4))
        let uncolored = MapSpeciesPalette.empty

        let hot = TreePinAnnotation(pin: pin, palette: colored)
        let cold = TreePinAnnotation(pin: pin, palette: uncolored)
        #expect(hot.kind == .cityTreeSpecies(.a))
        #expect(cold.kind == .cityTree)
        #expect(
            hot.kind != cold.kind,
            """
            the same tree coloured and uncoloured produced the same marker kind, so \
            `Coordinator.sync` cannot notice that the palette moved and the map would keep drawing \
            last viewport's colours.
            """
        )
    }

    /// One `MKMapView` and the coordinator that syncs annotations into it, with the delegate left
    /// off — every callback this test needs it invokes itself, in the order `updateUIView` does.
    /// Modelled on `MapCameraOwnershipTests.Screen` for the same reason: MapKit's own callbacks would
    /// turn an assertion into a race.
    private static func layerAndMap() -> (MapAnnotationLayer.Coordinator, MKMapView) {
        let opening = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42),
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )
        let box = Box(position: .opening(opening), region: opening)
        let layer = MapAnnotationLayer(
            position: Binding(get: { box.position }, set: { box.position = $0 }),
            region: Binding(get: { box.region }, set: { box.region = $0 }),
            clusters: [],
            pins: [],
            userCoordinate: nil,
            selectedPinID: nil,
            onCameraChange: { _, _ in },
            onSelectPin: { _ in },
            onSelectCluster: { _ in }
        )
        return (layer.makeCoordinator(), MKMapView(frame: CGRect(x: 0, y: 0, width: 430, height: 800)))
    }

    @MainActor
    private final class Box {
        var position: MapCameraRequest
        var region: MKCoordinateRegion
        init(position: MapCameraRequest, region: MKCoordinateRegion) {
            self.position = position
            self.region = region
        }
    }

    /// **The spoken channel is the one that arrives late, and it used to arrive never.**
    ///
    /// `MapModel` ranks the palette from the pins synchronously and then reads the four species' names
    /// asynchronously, so the palette a pin is *born* under has `name == nil` and the label it stores
    /// is the plain `City tree`. A name landing changes no pin's kind — the fill and the glyph were
    /// already right — so `sync`'s kind comparison leaves every annotation exactly where it is, and a
    /// label stored once at init stays the label it was born with for the life of the pin.
    ///
    /// Which would mean the third channel, the only one that survives the screen being off, silently
    /// did nothing in the running app while `voiceOverNamesTheSpecies` passed — because that test asks
    /// `MapPinKind` directly and never goes through the layer.
    @Test("a species name that lands after the pins are drawn reaches the pins that are already drawn")
    func spokenLabelsCatchUpWithTheSpeciesRead() {
        let id = UUID()
        let pins = Self.pins(id, 4)
        let (coordinator, mapView) = Self.layerAndMap()

        // Pass one: the palette has ranked this species and has not yet learnt its name.
        var palette = MapSpeciesPalette.assign(pins: pins)
        #expect(palette.slot(for: id) == .a)
        #expect(palette.unnamedSpeciesIDs == [id])
        coordinator.sync(clusters: [], pins: pins, palette: palette, on: mapView)
        let drawn = mapView.annotations.compactMap { $0 as? TreePinAnnotation }
        #expect(drawn.count == 4)
        for annotation in drawn { #expect(annotation.spokenLabel == "City tree") }

        // Pass two: the species read landed. Nothing about the picture changed.
        palette = palette.naming([id: "London Plane"])
        coordinator.sync(clusters: [], pins: pins, palette: palette, on: mapView)
        let after = mapView.annotations.compactMap { $0 as? TreePinAnnotation }
        #expect(
            after.count == 4,
            "the naming pass churned the annotations; a word arriving is not a change in what is drawn"
        )
        #expect(
            Set(after.map { ObjectIdentifier($0) }) == Set(drawn.map { ObjectIdentifier($0) }),
            "the same four annotation objects should still be on the map"
        )
        for annotation in after {
            #expect(
                annotation.spokenLabel == "City tree, London Plane",
                """
                a pin that was already drawn when its species' name arrived still says \
                "\(annotation.spokenLabel)". Every coloured pin in the running app is in exactly this \
                position — the palette always ranks before it can name — so the spoken channel would \
                have named nothing, ever.
                """
            )
        }
    }

    // MARK: - The channels that are not colour

    @Test("the four slots carry four different glyphs")
    func glyphsAreDistinct() {
        let glyphs = MapSpeciesSlot.allCases.map(\.glyph)
        #expect(Set(glyphs).count == glyphs.count)
        let names = MapSpeciesSlot.allCases.map(\.glyphName)
        #expect(Set(names).count == names.count)
    }

    @Test("a coloured pin speaks its species, and an uncoloured one says exactly what it always said")
    func voiceOverNamesTheSpecies() {
        let id = UUID()
        let pin = Self.pin(species: id)
        var palette = MapSpeciesPalette.assign(pins: Self.pins(id, 4))

        // Before the name read lands there is nothing to say, so nothing new is said.
        #expect(MapPinKind.accessibilityLabel(for: pin, palette: palette) == "City tree")
        palette = palette.naming([id: "London Plane"])
        #expect(MapPinKind.accessibilityLabel(for: pin, palette: palette) == "City tree, London Plane")

        // The residual class is untouched, which matters: a label that named some pins and not others
        // would read as a claim about the ones it left out.
        let other = Self.pin(species: UUID())
        #expect(MapPinKind.accessibilityLabel(for: other, palette: palette) == "City tree")
        // And a memorial keeps E107's wording rather than gaining a species.
        let site = Self.pin(species: id, status: .vacantSite)
        #expect(MapPinKind.accessibilityLabel(for: site, palette: palette) == SiteCopy.pinAccessibilityLabel)
    }

    @Test("the legend names every colour it shows, and shows no colour it cannot name")
    func theLegendOnlyDrawsWhatItCanName() {
        let id = Self.ids(2)
        var palette = MapSpeciesPalette.assign(pins: Self.pins(id[0], 5) + Self.pins(id[1], 3))
        #expect(palette.unnamedSpeciesIDs.count == 2)
        palette = palette.naming([id[0]: "Ginkgo"])
        #expect(palette.unnamedSpeciesIDs == [id[1]])
        // Naming does not move a slot: a word arriving is not a change in what is on screen.
        #expect(palette.slot(for: id[0]) == .a)
        #expect(palette.slot(for: id[1]) == .b)
        #expect(
            MapSpeciesLegendCopy.chipLabel(name: "Ginkgo", slot: .a) == "Ginkgo, plum pins marked dot"
        )
    }

    // MARK: - The selection mark cannot be read as a species colour

    /// **The reticle is achromatic and the slots are not**, and that is the whole of why one cannot be
    /// mistaken for the other. Asserted in OKLCh chroma rather than by eye: every slot fill carries
    /// chroma ≥ 0.07 in both appearances, and both reticle colours carry ≤ 0.04. There is no overlap
    /// and no near miss.
    @Test("the selection reticle is achromatic and every species colour is not")
    func theReticleCannotBeASpeciesColor() {
        for traits in [UITraitCollection(userInterfaceStyle: .light), UITraitCollection(userInterfaceStyle: .dark)] {
            for reticle in [CypressColor.textInk, CypressColor.pinRingStroke] {
                #expect(
                    Self.chroma(reticle, traits) <= 0.04,
                    "a selection ring gained chroma \(Self.chroma(reticle, traits)); it must stay ink-and-white"
                )
            }
            for slot in MapSpeciesSlot.allCases {
                #expect(
                    Self.chroma(slot.fill, traits) >= 0.07,
                    "slot \(slot.rawValue) is nearly grey at chroma \(Self.chroma(slot.fill, traits)), which puts it in the reticle's range"
                )
            }
        }
    }

    @Test("the reticle is drawn outside every pin's own footprint")
    func theReticleIsOutsideThePin() {
        #expect(MapLayout.selectedReticleInnerScale > MapLayout.selectedPinScale)
        #expect(MapLayout.selectedReticleOuterScale > MapLayout.selectedReticleInnerScale)
        // …and inside the 44 pt tap target, so the mark never claims ground the finger does not own.
        let widest = CypressSpacing.Component.pinStandard * MapLayout.selectedReticleOuterScale
        #expect(widest <= CypressSpacing.minTapTarget)
    }

    /// **The constants are not the geometry, because the view is wearing a transform.**
    ///
    /// `setSelectedAppearance` scales the whole marker view by `selectedPinScale`, and the reticle
    /// layers are children of that view — so a ring built at `2.0 × 18` lands on the glass at 45 pt,
    /// past the 44 pt tap target the test above believes it has checked. This measures what is
    /// actually drawn: the layer's own size *times* the transform it inherits.
    @Test("the ring the reader sees is the size MapLayout says, not that size times the selection scale")
    func theReticleIsDrawnAtTheDocumentedSize() {
        let view = MapMarkerView(
            annotation: TreePinAnnotation(pin: Self.pin(species: nil)),
            reuseIdentifier: MapMarkerView.reuseIdentifier
        )
        view.setSelectedAppearance(true)
        #expect(view.reticleLayers.count == 2, "the reticle is two rings; it drew \(view.reticleLayers.count)")

        let pin = CypressSpacing.Component.pinStandard
        let onGlass = view.reticleLayers
            .map { $0.bounds.width * view.transform.a }
            .sorted()
        let wanted = [
            pin * MapLayout.selectedReticleInnerScale,
            pin * MapLayout.selectedReticleOuterScale,
        ]
        for (drawn, expected) in zip(onGlass, wanted) {
            #expect(
                abs(drawn - expected) < 0.01,
                """
                a reticle ring is \(drawn) pt on the glass where MapLayout says \(expected). The layers \
                are children of a view carrying `selectedPinScale`, so their sizes have to be divided \
                by it — otherwise the documented number, the asserted number and the drawn number are \
                three different numbers.
                """
            )
        }
        #expect(
            (onGlass.last ?? 0) <= CypressSpacing.minTapTarget,
            "the outer ring is \(onGlass.last ?? 0) pt on the glass, outside the 44 pt the finger owns"
        )
    }

    @Test("a selected pin comes to the front and lets go of it again")
    func theSelectedPinIsNotOverdrawn() {
        let view = MapMarkerView(
            annotation: TreePinAnnotation(pin: Self.pin(species: nil)),
            reuseIdentifier: MapMarkerView.reuseIdentifier
        )
        view.setSelectedAppearance(true)
        // The relationship, not the raw constant: selection must outrank every unselected
        // neighbour — a reticle half-covered by the pin it distinguishes is not a mark — and it
        // sits *below* the reader's dot, which task #150 made the topmost thing on the map.
        // `.max` belongs to the dot now; `MapLayout`'s z-order block is the one ladder, and
        // `MapMarkerRenderingTests.userDotIsTopmost` holds the dot's end of it.
        #expect(view.zPriority.rawValue > MapLayout.pinZPriority.rawValue,
                "a reticle half-covered by the neighbour it distinguishes is not a mark")
        #expect(view.zPriority.rawValue < MapLayout.userDotZPriority.rawValue,
                "a selected pin above the reader's dot hides the one mark every other mark is relative to (#150)")
        view.setSelectedAppearance(false)
        #expect(view.zPriority == MapLayout.pinZPriority)
        view.setSelectedAppearance(true)
        view.prepareForReuse()
        #expect(view.transform == .identity)
        #expect(view.zPriority == MapLayout.pinZPriority, "a recycled view arrived still wearing the last selection")
    }

    // MARK: - OKLCh, for the two assertions that need it

    private static func chroma(_ color: Color, _ traits: UITraitCollection) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        let aa = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return (aa * aa + bb * bb).squareRoot()
    }
}
