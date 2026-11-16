# `internal:` for now, and that is a judgment a reviewer may overturn. This branch makes other
# people's published community trees reach the phone: the map fetches them for the tiles it shows
# from zoom 15 (the first zoom that draws cluster badges) out to maps about 3 km wide, about twice
# the width of a zoom-15 map. At those zooms the trees are counted inside the cluster badges; closer
# in, from zoom 16, they are drawn as dashed pins, and they open their profiles. That is
# tester-visible.
# It is written as internal because nobody has yet seen it work against the live service on a
# signed-in phone: the UI suite runs with the remote gate off, and no test calls production. Once
# the phone check in the PR body is done, replace the line below with one like:
#   Trees other people add now appear on your map as dashed pins, and you can open them.

internal: fetches other people's published community trees into the map's cache; tester-facing note withheld until it is seen working against the live service.
