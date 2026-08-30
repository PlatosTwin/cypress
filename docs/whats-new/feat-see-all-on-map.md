# Tester report F23, answered. The link goes on the Journal tab's `Yours` segment rather than on My
# Grove's `Trees` pill, and the placement is put to the owner for ratification in the pull request —
# no mock draws this link (DECISIONS constraint 21). The reason it is not on My Grove is in
# `CypressTests/SeeAllOnMapTests.theMapsYoursIsNotTheGrovesList`: the grove's list includes trees you
# have only favorited, and the map's `Yours` filter deliberately does not, so the same sentence there
# would drop rows the reader could still see.
#
# True at merge: the link is drawn, the route lands narrowed, and the chip can be cleared — driven
# on the simulator by `CypressUITests/SeeAllOnMapUITests` and looked at by hand.

Your journal now has a "See them all on the map" link. Tapping it opens the map showing only the trees you have been to, and the "Yours" chip is there to switch back off.
