# Tester report F23, answered. The link goes on the Journal tab's `Yours` segment rather than on My
# Grove's `Trees` pill, and the placement is put to the owner for ratification in the pull request —
# no mock draws this link (DECISIONS constraint 21). The reason it is not on My Grove is in
# `CypressTests/SeeAllOnMapTests.theMapsYoursIsNotTheGrovesList`: the grove's list includes trees you
# have only favorited, and the map's `Yours` filter deliberately does not, so the same sentence there
# would drop rows the reader could still see.
#
# "Contributed to" and not "been to" (PR #130 review, F3). The filter is `contributedTreeIDs` —
# visits, check-ins, measurements, care logs and trees you added — and a visit is only one of those.
# The journal this branch's own harness draws holds an observation and no visit at all, so the
# narrower sentence would have been false about the very screen the change ships to demonstrate.
#
# True at merge: the link is drawn, the route lands narrowed, and the chip can be cleared — driven
# on the simulator by `CypressUITests/SeeAllOnMapUITests` and looked at by hand.

Your journal now has a "See them all on the map" link. Tapping it opens the map showing only the trees you have contributed to, and the "Yours" chip is there to switch back off.
