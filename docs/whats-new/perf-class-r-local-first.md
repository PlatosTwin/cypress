# Tree profiles, the heart and the map's filters. Tester-visible, because all three are things the
# owner can feel with the phone in hand — this is the same defect PR #144 fixed for My Grove,
# finished off on the screens that round did not reach.
#
# ── WHAT MAKES EACH CLAUSE TRUE, AND WHAT IT DELIBERATELY DOES NOT CLAIM ───────────────────
#
#   * "Opening a tree no longer waits for the network" — `RoutedAPI.treeProfile(id:)` awaited
#     `remote.treeCommunityHalf(id:)` before it returned anything, and there are **fifteen** call
#     sites through the router, not one: screen 03, the photo browser, the memorial and
#     growth-history and activity screens, the share sheet, and the sheets that wanted nothing from
#     the profile but a name or a species. Every one of them paid a round trip with no configured
#     timeout. The paint is the phone's now; the community half — which is photographs and two id
#     sets — merges in behind the **six** surfaces that read those photographs. (`VisitGates` calls
#     the same method five more times and is not among the fifteen: it builds its own `LocalAPI`.)
#
#     **Six and not three, and PR #147's review is why.** The first cut reasoned that only the
#     surfaces that *draw* a photograph need the merge and then named three of the six; the memorial,
#     the activity screen and the share sheet read `visiblePhotos` too. Share is the sharpest: its
#     predicate is `.approved`, which is produced only by the community half's own decode, so without
#     the merge its card carries no photograph unconditionally rather than merely usually.
#
#     **Asserted as a census of requests made, not as a stopwatch reading.** `ClassRLocalFirstTests`
#     reads `transport.calls` after each read returns, and its header says why there is not a number
#     or a latch anywhere in the file.
#
#   * "the heart answers the moment you tap it" — the favorite re-read was remote-first, and the
#     heart re-reads after every write (RULINGS R2), so a round trip sat between the finger and the
#     control settling. The owner ruled on 2026-09-02 that favorites answer from the phone; the
#     server re-read still happens and reconciles behind the painted control.
#
#     **What this does not claim is that the cross-device half was dropped.** A favorite set on
#     another phone still reaches this one — a beat after the paint instead of in front of it. And a
#     toggle still sitting in the outbox still wins over the service's answer, which is the half that
#     had to be *added* rather than moved: without it the reconcile would have answered with the
#     state before the tap and taken the heart back off (#139, #153, #167).
#
#   * "the map's Yours and Favorites chips narrow instantly" — pressing a chip resolved its id set
#     through the service first, and `MapModel` deliberately resolves that narrow set *before* the
#     wide query over the city's trees, so the whole chip waited on the network. The chip reads the
#     phone's table now and unions the account's set behind it.
#
#   * "the map keeps where you were, and what you had searched or filtered to" — `MapModel` is owned by the
#     composition root now rather than by the tab's own view, which `RootView` destroys on every
#     switch. Three things were lost before: the whole viewport was re-fetched from cold on every
#     return, the search field and its narrowing were emptied, and the filter chip **silently reset
#     to All** — a reader who narrowed to `Yours`,
#     checked the Journal and came back found the whole city again with no chip pressed to explain
#     it. The camera was already kept, by a separate mechanism, and still is.
#
#     **The You tab is deliberately not mentioned and deliberately unchanged.** `YouTabView` itself
#     declares no state — its outbox, moderation and account models were already owned by the
#     composition root. Three of its subviews do own state, and it is meant to reset: a
#     destructive-confirmation flag that survived leaving the screen would be a defect, not a
#     feature. So nothing under that tab loses a read or a filter on a switch, and reporting a fix
#     for it would be reporting ceremony.
#
#   * Nothing here changes what any screen shows once everything has loaded. Every merge keeps the
#     rule it had: the phone's photograph wins a collision, the own and deletable sets are unioned,
#     the membership sets are unioned rather than replaced, and this device's status provenance is
#     still this device's.

Tree profiles, the heart and the map's Yours and Favorites chips answer instantly now instead of waiting on the network.
The map also keeps your search and filter when you come back to it, and a photo or favorite added on another device turns up a moment after the screen draws.
