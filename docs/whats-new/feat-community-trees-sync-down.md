# `internal:` for now, and that is a judgement a reviewer may overturn. This branch makes other
# people's published community trees reach the phone: the map fetches them for the tiles it shows
# at zoom 13 or closer, draws them as dashed pins, and opens their profiles. That is tester-visible.
# It is written as internal because nobody has yet seen it work against the live service on a
# signed-in phone: the UI suite runs with the remote gate off, and no test calls production. Once
# the phone check in the PR body is done, replace the line below with one like:
#   Trees other people add now appear on your map as dashed pins, and you can open them.

internal: fetches other people's published community trees into the map's cache; tester-facing note withheld until it is seen working against the live service.
