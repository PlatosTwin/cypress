# The tester-visible half of this work is the REPUBLISH, not this build. Nothing in the app
# binary changes here: the diff is Tools/publish_cities.py, its tests, and a pending ruling.
# Devices stuck on the superseded 2026-08-22 publish start offering `Update` when the packs
# are republished under `s17-r2026-08-22.02-ac7b1ccc` — which happens in the bucket, on its
# own schedule, and would be a claim about something this build cannot deliver.
internal: the publisher can no longer reuse a content_rev across publishes of different data, so a same-day correction is visible to devices that already downloaded the superseded one.
