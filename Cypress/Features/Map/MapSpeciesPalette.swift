//
//  MapSpeciesPalette.swift
//  Cypress — Features/Map
//
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  WHO GETS A COLOUR, AND WHY IT DOES NOT CHANGE WHEN YOU PAN
//  ══════════════════════════════════════════════════════════════════════════════════════════
//  `MapSpeciesSlot` says what the four colours are and why there are four. This says who holds them.
//
//  ── The rule ──────────────────────────────────────────────────────────────────────────────────
//  Rank the species of the pins **currently drawn** by how many pins each has, keep the ones with at
//  least two, and give the top four a slot. Everything else keeps the plain Canopy pin.
//
//  Three parts of that sentence are decisions:
//
//  1. **Of the pins currently drawn, not of the trees in the box.** `TreeQueries.pins` thins to one
//     tree per 44 pt cell once the budget bites (`MapModel.markerCellPoints`), so "the trees in the
//     box" and "the pins on the glass" are different multisets at every zoom below 19. The reader is
//     asking about the dots they can see, so the count is of those.
//
//  2. **At least two.** A species with one pin in view cannot answer "which of these are the same
//     tree?" — there is nothing for it to be the same as. Spending one of four slots on a singleton
//     is spending it on a question nobody asked, and at zoom 19 in the Excelsior the tail is almost
//     all singletons, so this is the difference between four useful colours and one.
//
//  3. **Only trees that draw as `.cityTree`.** A slot is a fill, and four pins already own their
//     fill for a reason that outranks species:
//
//       - `.needsCare` is Signal Amber, "reserved solely for 'this tree needs something'"
//         (SCREENS.md §1.1). A declining London plane is a *care* problem before it is a *plane*.
//       - `.community` is the dashed unverified layer, which "never renders as part of the official
//         city inventory until verified" (DECISIONS §3.16) — colouring it in would do exactly that.
//       - `.removed` and `.vacantSite` have no living tree to have a species.
//
//     Those pins are also excluded from the *counting*, not just from the colouring: a species whose
//     visible pins are nine memorials and two live trees is not two-thirds of this street's canopy.
//
//  ── Stickiness, which is the same lesson as E130's cluster ids ────────────────────────────────
//  A palette recomputed from scratch on every fetch permutes its colours on every pan: nudge the
//  camera one block west, the third and fourth species swap counts, and every pin on screen changes
//  colour while the reader is looking at it. That is E130's badge-rekeying defect wearing a different
//  hat — the fix there was an absolute grid, and the fix here is the same shape.
//
//  **A species that already holds a slot keeps it for as long as it still qualifies.** New species
//  fill whatever slots are free, in rank order. So a pan changes only the colours that had to change,
//  and a reader who has learnt "the purple ones are the plums" keeps that for the length of a walk.
//
//  ── What it costs the renderer, which is the reason any of this is shaped this way ────────────
//  Four slots plus the residual is **five** distinct city-tree bitmaps where there was one. The
//  marker cache (`MapPinImage`) is keyed on `MapPin.Kind` and the appearance, so the fixed pin
//  vocabulary goes from 8 kinds to 12, i.e. from 16 cached images to 24 across both appearances. It
//  is bounded by the enum and does not grow with the 569 species, with the pin count, or with the
//  length of the session. A palette keyed on `speciesID` would have made the cache unbounded in the
//  one dimension `MapPinImage` explicitly cannot afford, and undone the work E130 and the MapKit
//  swap did.
//

import Foundation

/// Which species hold which colour slots on the map right now.
///
/// A value type, recomputed from the drawn pins, carried into `MapAnnotationLayer` alongside them —
/// so a pin's *kind* is a function of the pins on screen rather than of anything stored. That is what
/// keeps the annotation diff honest: when the palette changes, the kind changes, and the layer's
/// existing id-and-kind comparison notices without a second mechanism.
struct MapSpeciesPalette: Equatable {

    /// One coloured species, in rank order.
    struct Entry: Equatable, Identifiable {
        let slot: MapSpeciesSlot
        let speciesID: UUID
        /// How many drawn pins it holds. The legend does not show it; it is what the ranking is.
        let count: Int
        /// The species' common name, once `MapModel` has resolved it. `nil` until then, which is why
        /// the legend renders per entry rather than all-or-nothing.
        var name: String?

        var id: UUID { speciesID }
    }

    /// Rank order, at most `MapSpeciesSlot.allCases.count` long.
    let entries: [Entry]

    private let slots: [UUID: MapSpeciesSlot]

    static let empty = MapSpeciesPalette(entries: [])

    init(entries: [Entry]) {
        self.entries = entries
        self.slots = Dictionary(uniqueKeysWithValues: entries.map { ($0.speciesID, $0.slot) })
    }

    /// The slot a species holds, or `nil` for the residual class.
    func slot(for speciesID: UUID?) -> MapSpeciesSlot? {
        guard let speciesID else { return nil }
        return slots[speciesID]
    }

    /// The minimum number of drawn pins a species needs before a slot is spent on it. See decision 2
    /// in this file's header.
    static let minimumPinsForASlot = 2

    // MARK: - Assignment

    /// Ranks the drawn pins and hands out the slots, keeping whatever `previous` already gave away.
    ///
    /// Deterministic end to end: ties in count are broken by the species' UUID, so the same screenful
    /// of pins always produces the same palette regardless of the order the rows came back in.
    static func assign(pins: [TreePin], previous: MapSpeciesPalette = .empty) -> MapSpeciesPalette {
        var counts: [UUID: Int] = [:]
        for pin in pins where MapPinKind.kind(for: pin) == .cityTree {
            guard let id = pin.speciesID else { continue }
            counts[id, default: 0] += 1
        }

        let ranked = counts
            .filter { $0.value >= minimumPinsForASlot }
            .sorted {
                $0.value != $1.value
                    ? $0.value > $1.value
                    : $0.key.uuidString < $1.key.uuidString
            }
            .prefix(MapSpeciesSlot.allCases.count)

        // Step one: everyone who already had a slot and still qualifies keeps it.
        var held: [UUID: MapSpeciesSlot] = [:]
        var taken: Set<MapSpeciesSlot> = []
        for (id, _) in ranked {
            guard let slot = previous.slots[id] else { continue }
            held[id] = slot
            taken.insert(slot)
        }
        // Step two: the newcomers take what is left, in rank order, so the busiest newcomer gets the
        // lowest free slot rather than whichever one a dictionary happened to yield.
        var free = MapSpeciesSlot.allCases.filter { !taken.contains($0) }
        for (id, _) in ranked where held[id] == nil {
            guard let slot = free.first else { break }
            free.removeFirst()
            held[id] = slot
        }

        let entries = ranked.compactMap { id, count -> Entry? in
            guard let slot = held[id] else { return nil }
            return Entry(slot: slot, speciesID: id, count: count, name: previous.name(for: id))
        }
        return MapSpeciesPalette(entries: entries)
    }

    private func name(for speciesID: UUID) -> String? {
        entries.first { $0.speciesID == speciesID }?.name
    }

    /// The same palette with whatever names are known filled in. Called when a species read lands;
    /// the slots do not move, because a name arriving is not a change in what is on screen.
    func naming(_ names: [UUID: String]) -> MapSpeciesPalette {
        MapSpeciesPalette(entries: entries.map { entry in
            var entry = entry
            entry.name = names[entry.speciesID] ?? entry.name
            return entry
        })
    }

    /// The species whose names the legend still needs.
    var unnamedSpeciesIDs: [UUID] { entries.filter { $0.name == nil }.map(\.speciesID) }
}
