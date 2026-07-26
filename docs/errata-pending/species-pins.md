## thirty green dots on one street, and the 569-colour legend that is not a design

Task **#80**, the project owner's words: *"Add ability to color different species differently so it's
easy to tell which trees are same on a local zoom."* One sentence, and the first thing to do with it
is refuse the literal reading.

**There are 569 species in the seed.** A colour per species is a colour wheel, not an encoding — the
fortieth hue and the forty-first are the same hue to anybody's eye, and a reader who *thinks* they can
tell two pins apart when they cannot has been handed a wrong answer rather than no answer. So the
question the map answers is the one the owner actually asked, which is narrower than the words: *which
of these are the same tree?* That is a question about **matching**, and matching needs colours unique
among the ones on screen right now. It does not need a colour that means *Platanus* forever.

#### What the encoding is

Four **slots** (`MapSpeciesSlot`), handed to the four species with the most drawn pins in the current
viewport (`MapSpeciesPalette`). Everything else keeps the pin it has today.

Counted against the shipped seed over ten neighbourhoods, using the pins as `TreeQueries` actually
thins them (one per 44 pt cell, `MapModel.markerCellPoints`) rather than the trees in the box:

```
zoom 19 · 0–75 pins/screen  ·  6–31 species  ·  top 4 cover 32–90 % of pins
zoom 18 · 14–133 pins       · 10–53 species  ·  top 4 cover 29–76 %
zoom 17 · 93–222 pins       · 27–64 species  ·  top 4 cover 27–64 %
```

**There is no zoom at which a screenful of San Francisco is four species**, so the residual class is
not an edge case — it is often most of the screen, and what it draws is the load-bearing decision.
It draws **today's pin, unchanged**: Canopy green, no glyph. And Canopy green is deliberately *not*
one of the four slot colours, which is what makes the residual honest rather than a fifth group.
Green says "a street tree"; it has never said "the same tree as that one" and it still does not.
`ContrastTests.slotsStayOutOfTheReservedFills` is that sentence as an assertion.

Three further rules, each of which is a decision:

- **A species with one pin in view gets no slot.** A singleton has nothing to be the same as, so a
  slot spent on it is spent on a question nobody asked. At zoom 19 in the Excelsior the tail is almost
  entirely singletons, and this is the difference between four useful colours and one.
- **Only a pin that would already draw as `.cityTree` can take a colour**, and the others are not
  even *counted*. Amber is "reserved solely for 'this tree needs something'" (SCREENS.md §1.1); the
  dashed ring is the community layer, which "never renders as part of the official city inventory
  until verified" (DECISIONS §3.16); grey and hollow mean there is no living tree. A species whose
  visible pins are nine memorials and two live trees is not two-thirds of a street's canopy.
- **Slots are sticky.** A palette recomputed from scratch permutes on every fetch: nudge the camera
  one block west, the third and fourth species swap counts, and every pin changes colour while the
  reader watches. That is E130's cluster badges re-keying on every pan, in another costume, and the
  answer has the same shape — a species that already holds a slot keeps it while it still qualifies,
  and newcomers take what is free. A reader who has learnt "the purple ones are the Victorian Box"
  keeps that for the length of a walk. `slotsAreSticky` and `slotsAreReusedWhenVacated` pin it.

#### A cluster badge is not given a species colour, and that is a refusal rather than an omission

A cluster is a **count**, produced by an absolute SQL grid that knows nothing about species (E130).
Nine trees under one badge are usually nine different trees, so any colour on that badge would assert
homogeneity the data does not support — and the honest colour for "mixed" is the one it already has.
`TreeQueries.cellSize` is untouched, MapKit's `clusteringIdentifier` is still not used, and a
clustered viewport draws no legend at all because there are no pins to rank.

#### The second channel, which was owed regardless

**RULINGS R8** settled this for C23 in a sentence that generalises: "a chart that distinguishes its
lines only by hue is unreadable to a colour-blind reader at *any* contrast ratio, so the redundant
encoding is owed regardless". A map is a data encoding on the same terms. So each slot carries a
**glyph** in the ring colour inside the pin — a dot, a triangle, a cross, a standing bar — chosen to
differ in silhouette rather than in detail, and the legend chip shows the same mark beside the name.
A reader who sees no hue at all still sees four different marks.

This is not R6's forbidden move. R6 refused a glyph that *replaced a word* on screen 17's queue rows.
Nothing on an 18 pt map pin has ever been a word, and the word still exists in the two places a word
belongs: `MapSpeciesLegend` names the species, and `MapPinKind.accessibilityLabel(for:palette:)`
speaks it — `City tree, Victorian Box` from every Victorian Box on the block, which answers the
owner's question better than either drawn channel does.

**The standing bar is vertical**, because a memorial is a grey pin with a *horizontal* bar across it.
Two bars at right angles cannot be read for each other; two parallel ones could. No slot uses a
hollow inner ring, because a hollow pin is a vacant planting site (R7), and none uses a check,
because a check is screen 18's visited route pin.

#### The palette, and the five constraints it had to clear at once

Four `derived` tokens — `pinSpeciesA`…`D`. **They are the only tokens in `CypressColor` whose light
half is ours too**; every other `derived` value is a documented light hex with a computed dark
counterpart, and SCREENS.md draws no species colouring at all. `derived` is still the right claim,
because it is the constructor that puts a value in `reviewTokens`, and `TokenGallery` renders those
first — four swatches on one screen for a designer to answer, rather than a palette to audit.

Chosen by search in OKLCh (`Tools/map_species_palette.py`), against:

1. **≥ 3:1 on every ground screen 01 draws**, in both appearances — map paper, map grid, street band,
   park block, park inset ring, ocean, beach. Fifty-six measurements, all in
   `ContrastTests.speciesPinsInLight`/`InDark`. **The binding grounds are the water in light (4.81,
   3.81) and the park inset ring in dark (3.15)**, with the park block next in both; the paper
   everybody would have measured against is the easiest of the seven. The suite previously measured
   the city pin and the amber pin against the paper and stopped there, which is how a palette passes
   on paper and vanishes over Golden Gate Park.
2. **≥ 0.10 OKLab ΔE from each other**, five times the ~0.02 just-noticeable difference. Measured as
   ΔE and not as WCAG contrast: contrast is a luminance ratio, so two colours of the same lightness
   and opposite hue read 1.0:1, which is the right tool for "can I see this on that" and the wrong
   one for "can I tell these two apart".
3. **≥ 0.099 ΔE from every mark whose hue already means something** — Canopy, Signal Amber, the GPS
   dot, the cluster badge, a memorial's grey. No slot sits in the amber arc (hue 20–115°), the Canopy
   arc (125–200°) or the GPS arc (232–272°) at all. **Removing those three arcs from the wheel is
   also why there are four slots and not six**: what is left will not hold six hues this far apart.
4. **The ring and the glyph read on every fill** — `pinRingStroke` is 5.4:1 or better on all eight.
5. Lightness descends A→D in light and ascends in dark, so the four are separated in luminance as well
   as in hue and no pair collapses for a reader with a severe deficiency. This is **not** a ranking
   channel — slots are sticky, so `a` is the commonest species only until the reader pans.

The tightest separation in the whole set is slot B in light against the **cluster badge**, ΔE 0.099 —
and a badge is a filled 28 pt circle carrying a number, which is not a thing a reader confuses with an
18 pt dot at any hue. The tightest against another *pin* is slot B after dark against the GPS dot,
ΔE 0.110, separated by three further channels: the dot carries no glyph, it is the only mark with an
8 pt halo, and it is drawn *under* every tree (`zPriority = .min`). Both numbers come off
`Tools/map_species_palette.py`, which prints them and re-derives all eight hexes from their (hue, L).

#### The number this whole design exists to keep small

`MapPinImage` caches one bitmap per `MapPin.Kind` per appearance, and "once per kind" is what makes a
screenful of 280 markers a handful of images. **Keying that cache on a species would make it 1,138
rasterised SwiftUI views against a 256-entry ceiling** — not a slower version of the MapKit swap, but
the defect the swap was made to fix, reintroduced, with the cache thrashing its own `removeAll`
mid-pan.

So `cityTreeSpecies` takes a **slot**, and the fixed pin vocabulary goes from 8 kinds to 12: **16
cached bitmaps before, 24 after**, in both appearances, and the number does not move with the 569
species, with the pin count, or with the length of the session. Cluster badges are still one per
distinct count. `theBitmapCountIsBounded` asserts the 24 rather than the argument.

It is a **separate enum case rather than an associated value on `.cityTree`**, which is why this
change touches no existing `== .cityTree` anywhere in the app or the suite, and why "no slot" is still
spellable as the pin that was already there.

#### Measured, on a booted simulator, with the probe armed

`CYPRESS_MAP_PROBE=1`, a simulated fix at 37.77462,-122.42244 (Hayes Valley, 199 alive city trees and
21 species inside one opening viewport), iPhone 16 Pro Max, camera settled, nobody touching the glass.
Both builds installed onto the same booted device back to back — **`cc01e32` before, this branch
after** — and read off the overlay, because console logging does not work on these simulators.

```
                                        fps   worst frame   gps/body/fetch per sec
before (cc01e32) · z18, 139 markers      49        35 ms            0 / 0 / 0
before (cc01e32) · z15,  49 badges       45        40 ms            0 / 0 / 0
after            · z18, 169 markers      53        37 ms            0 / 0 / 0
after            · z18, 292 markers      53        33 ms            0 / 0 / 0   ← all four slots in use
after            · z21,   3 markers      45        52 ms            0 / 0 / 0
```

**Read the last column, not the first.** The absolute frame rate here is worthless and is reported
anyway so that nobody mistakes it for a result: this machine was carrying six booted simulators, a
second agent's `xcodebuild`, and a load average of 17–22 throughout, and the overlay read 45–55 fps
with a 33–52 ms worst frame on *every* combination of build, zoom and marker count — including 3
markers and including a build that predates this change. Nothing in that spread is attributable to the
palette; a quiet machine is owed before any absolute number off this screen means anything.

What the numbers do establish is the shape: **at 292 markers with all four slots in use, the after
build is not worse than the before build at 139**, and `body` and `fetch` are 0 per second at rest in
both. That last one is the property the design actually rests on — the palette is computed once per
*fetch* rather than per pass, and `recomputeSpeciesPalette` drops a palette equal to the one it
already had rather than republishing observable state, so a pan across a block re-derives the palette
it has and tells nobody.

#### What was looked at, because tests cannot say whether it reads

Twelve screenshots off the booted device, both appearances, every one checked for an opaque alpha
channel and a colour count (9,069–37,418 distinct colours) rather than trusted because a file was
written — the shot harness has returned fully transparent PNGs while every test passed. Compared by
eye and never by hash or `cmp`: the probe's own text ticks once a second, so a byte comparison always
reports "different".

The one that is the whole argument for the task is `11-light-localzoom.png` — **292 markers over the
Oak/Page/Lily grid**, in which Brisbane Box reads as plum dots down Gough St, Sycamore: London Plane as
lagoon triangles along the south side of Page, Swamp Myrtle as iris crosses on Oak, and Maidenhair Tree
as cherry bars in a run of eight, over a residual green that claims nothing. "Which of these are the
same?" is answerable at a glance, and before the change every one of those 292 dots was the same green.

**And the crops were converted to greyscale and looked at again**, in both appearances, which is the
check the glyph exists to pass: with every hue removed, the dot, the triangle, the cross and the
standing bar are still four different marks — and the residual pin, which carries no mark at all, is
still a fifth thing. The legend chips key them with the same four marks.

The legend's empty and near-empty states were seen rather than reasoned about: at z21 with three
markers it drew a single chip, and at z15 the map is badges and it drew nothing.

#### What was not built

**No legend for the residual class.** `MapSpeciesLegend` names the four coloured species and says
nothing about the rest, because there is nothing true and short to say — "and 27 others" is a number
that changes with every pan and answers no question. The honest surface for "what is this green one"
is the one that already exists: tap it.

**Genus was weighed and rejected.** It would have collapsed 569 species to ~130 and bought about a
tenth of a slot's worth of coverage (11 genera against 12 species in a Mission zoom-19 screenful),
while making "same colour" mean "same genus" — so two *Prunus* species would share a hue and a reader
would read "same tree" and be wrong. The whole point of the constraint is that the map must not be
able to say something false.

**The other two basemaps are left alone.** `MapKitBasemap` takes the palette with a default of
nothing, so 16's pin adjust and the pin-set map draw what they drew: both are about *one* tree and its
neighbours rather than about the mix of species on a street, and four hues there would be answering a
question nobody asked.

---

## "this one" was a pin two and a half points wider than its thirty neighbours

Task **#89**. A tapped pin was distinguished by `MapLayout.selectedPinScale` and nothing else, and
that constant's own comment says why it was defensible: **NOT SPECIFIED** in SCREENS.md, so it was
"deliberately the smallest change that still answers the tap".

The smallest change stopped being enough when the map started drawing a street. 1.25 × 18 pt is
22.5 pt, and screen 01 draws up to 288 pins on one screenful (`MapModel.markerCellPoints`) — so the
reader was being asked to find the *marginally larger* dot among thirty identical ones. The card at
the bottom of the screen names the tree and the map does not say which dot it is talking about, which
is the whole of the defect: a tap that is answered somewhere the reader cannot connect to what they
touched.

#### The reticle

Two concentric rings **outside** the pin, at 1.7× and 2.0× its diameter, in `textInk` and
`pinRingStroke`. The scale stays, because it is what makes the pin and the card read as one selection.

Three properties make it unconfusable with the species colours above, and they are properties by
construction rather than by taste:

1. **It is achromatic.** The two ring colours carry OKLCh chroma ≤ 0.026 (`textInk` in light, the
   highest of the four values); every species slot carries ≥ 0.080. No overlap, no near miss, and
   `MapSpeciesColourTests.theReticleCannotBeASpeciesColour` asserts the gap rather than describing it.
   The reader for whom four hues are the *hardest* thing on the map finds this the easiest.
2. **It is outside the pin's own footprint**, in a band where no pin of any kind draws fill. A species
   colour is always a fill *inside* a pin. It is also inside the 44 pt tap target, so the mark never
   claims ground the finger does not own.
3. **It is a ring rather than a fill**, and there is only ever one of them on the map.

**Two rings and not one, because the ground is a live MapKit basemap.** A white ring disappears on the
paper and an ink one disappears over a park polygon after dark, so the mark carries both ends of the
ramp and one of them always reads — the crossed-over trick C19's FAB glyph already uses. It is
redrawn on a scheme flip, because a `CGColor` in a `CALayer` is the one thing on a marker view that
cannot resolve itself.

**The selected marker also comes to the front** (`zPriority = .max`). Two pins 20 pt apart overlap
across 36 pt of reticle, and a reticle half-covered by the neighbour it is distinguishing itself from
is not a mark.

#### It costs no bitmaps, which is why it is layers

`MapPinImage` is keyed on `MapPin.Kind`, so a *selected* variant of every kind would double the cache
the species slots just spent their whole design keeping countable — 24 entries to 48, for a state that is true of one
marker at a time. The rings are `CALayer`s on the one selected view, the way the amber pulse already
is. `selectionIsFreeOfTheCache` asserts that selecting, deselecting and reselecting rasterises
nothing.

#### Looked at

Screenshotted selected in both appearances at z18 with 169 markers, on a **residual green** pin — which
is the case that matters, since the pin a reader taps is more often than not one of the many rather
than one of the four. In light the outer ink ring is the only black mark on the map and the eye lands
on it; the inner white ring is nearly invisible against the paper, which is exactly the failure the
second ring exists to cover, and after dark the two swap roles — the pale outer ring carries it and the
near-black inner one is the faint one. One of the two always reads, which was the claim.

The card below named `Kwanzan Flowering Cherry · Prunus serrulata 'Kwanzan' · 50 m E`, so the tap and
the card and the mark are one selection.

One thing the drawing got wrong and the screenshot did not catch, which is why there is now a test for
it: the reticle's `CALayer`s are children of a view carrying `selectedPinScale`, so a ring built at
2.0 × 18 pt was landing on the glass at **45 pt** — outside the 44 pt tap target the test believed it
had checked, because the test restated the constant instead of measuring the layer times the
transform. The sizes are divided by the scale now.
