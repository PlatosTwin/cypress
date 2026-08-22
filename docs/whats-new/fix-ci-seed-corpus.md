# Nothing a tester can see. This round repairs the unit suite against the seed the s17 publish
# put on the bucket: a fourth `SeedCorpus` entry measured from that file, San Francisco's
# bounding-box table extended to the third id space, and one build-time defect the seed contract
# caught (`Tools/build_seed.py`'s case-normalisation pass had gone a column out of step, so the
# published file still holds 'Tree'/'tree'). No app behavior changes.

internal: re-pins the seed-corpus constants against published seed 4f6ebaaa and fixes the case-normalisation index in build_seed.py; no tester-visible change.
