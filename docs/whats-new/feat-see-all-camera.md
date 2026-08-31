# The camera half of tester report F23, ruled by the owner on build 63: "clicking See them all on
# the map should center the map on where the trees are; right now it just takes you to the map, and
# if you're nowhere near a city it shows blank. It should be centered on the city where you have the
# most trees." That supersedes the deferral ERRATA E287 records — the link shipped keeping the
# remembered viewport, and the camera was ratified as a follow-up rather than fixed.
#
# Three decisions inside it are the round's proposals rather than the owner's words, and all three
# are in the pull request for ratification: fit the whole set in the winning city rather than center
# on its middle; break a tie between two cities on the most recent contribution; and, when the
# winning city's pack has been removed, let the next city win rather than showing nothing.
#
# It rides the same one-shot the narrowing does, so pressing the `Yours` chip on the map still moves
# nothing — a reader already looking at the map chose the camera they are looking at.
#
# True at merge: driven on the simulator by `CypressUITests/SeeAllOnMapUITests`, and looked at by
# hand from a phone standing in San Jose with every contribution in San Francisco — the before and
# after are in the pull request.

"See them all on the map" now takes you to your trees, not just to the map: it opens on the city where you have the most of them, zoomed out far enough to hold them all.
