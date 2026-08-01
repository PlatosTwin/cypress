# The flowering tree the app had no word for (#151)

**Unnumbered — pending splice by the orchestrator.**

Owner field report, 2026-07-31: SF tree 222615 — a gold medallion tree (Cassia leptophylla) in
full flower at 34 Carl St — was photographed during a visit, and the check-in offered no
phenology option at all. The chip row was absent.

## The seed facts, verified against the row

`trees` id 100569, `sf/222615`, alive, species_current 209. Species 209 is **mapped, not a
stub** (`species_map.is_stub = 0` for both `Cassia leptophylla ::` spellings, confidence 1.0,
98 trees), carries a sourced habit (`leaf_retention = semi_deciduous`), an empty seasonal
calendar (four empty arrays), and `curated = 0`.

## The gate

Not the empty `SeasonalCalendar`, which never gated anything — `flowering` and `fruiting` are
in the base vocabulary regardless of the calendar. The list was emptied by
`VisitPhenologyVocabulary.tags(for:)`'s **curated gate**: `guard species.curated else return []`,
which offered the chip row "for the curated 40 and nobody else". 529 of the seed's 569 species —
and every tree standing under one of them — had no way to report a state the contributor was
looking at. The row is on screen 04's visit tray (the check-in card, screen 05, never carried
phenology chips; its foliage/vitality controls are a different vocabulary).

## The fix

The curated gate and the unknown-habit gate are removed from the *offering* and from the write
path's re-validation (`Species.availablePhenologyTags`), under the ruling in
`docs/rulings-pending/observed-states-not-gated.md`: observed states are the observer's report,
not the app's claim. D5's evergreen exclusion stands — a sourced evergreen is still never asked
about fall color or bare. The app's own phenology surfaces (screen 07, the season strip) still
render only authored content, and Vitality's leaf-off gating is untouched.

Pinned by `CypressTests/PhenologyObservedStatesTests.swift`, including the reported record
itself through the real read path.
