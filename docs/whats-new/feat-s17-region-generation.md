# The s17 published-seed generation: `dim_region`, `trees.region_id`, and manifest format 2.
#
# Nothing a tester can look at, and the escape hatch is the honest answer rather than a
# convenience. The round moves two version spaces and adds a dimension the publisher narrows on,
# but no pack is cut on it yet: San Francisco and San Jose publish as one `city`-level region
# each, which is what they have always been, so the Cities screen shows the same two rows with
# the same names, the same coverage and the same sizes. The first thing a tester will SEE from
# this work is a New York borough, and that is the next round's ingest.
#
# The one visible-adjacent change is a non-event by design: an unupdated install keeps a working
# Cities screen through RULING D8's dual-published format-1 manifest. A tester who notices that
# has noticed nothing happening, which is the intended outcome.

internal: seed schema generation 17 (region dimension, standing-dead condition) and manifest format 2; no tester-visible change until NYC ships.
