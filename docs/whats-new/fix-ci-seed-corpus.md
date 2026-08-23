# Nothing a tester can see. This round repaired the unit suite against the seed the s17 publish put
# on the bucket: a fourth `SeedCorpus` entry measured from that file, the bounding-box and
# row-accounting gates extended to the third id space, and one build-time defect the seed contract
# caught — `Tools/build_seed.py`'s case-normalisation pass had gone a column out of step, so seed
# 4f6ebaaa shipped still holding 'Tree'/'tree'. The corrected seed ac7b1ccc is live and CI is green
# against it. No app behavior changes.

internal: re-pins the seed-corpus constants against published seed ac7b1ccc and fixes the case-normalisation index in build_seed.py; no tester-visible change.
