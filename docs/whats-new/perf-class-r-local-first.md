# Tree profiles, the heart and the map's filters. Tester-visible, because all three are things the
# owner can feel with the phone in hand — this is the same defect PR #144 fixed for My Grove,
# finished off on the screens that round did not reach.
#
# ── WHAT MAKES EACH CLAUSE TRUE, AND WHAT IT DELIBERATELY DOES NOT CLAIM ───────────────────
#
#   * "Opening a tree no longer waits for the network" — `RoutedAPI.treeProfile(id:)` awaited
#     `remote.treeCommunityHalf(id:)` before it returned anything, and there are **sixteen** call
#     sites, not one: screen 03, the photo browser, the memorial and growth-history and activity
#     screens, the share sheet, and five sheets that wanted nothing from the profile but a name or a
#     species. Every one of them paid a round trip with no configured timeout. The paint is the
#     phone's now; the community half — which is photographs and nothing else — merges in behind the
#     three surfaces that actually draw somebody else's photograph.
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
#   * "the map keeps where you were and what you'd filtered to" — `MapModel` is owned by the
#     composition root now rather than by the tab's own view, which `RootView` destroys on every
#     switch. Two things were lost before: the whole viewport was re-fetched from cold on every
#     return, and the filter chip **silently reset to All** — a reader who narrowed to `Yours`,
#     checked the Journal and came back found the whole city again with no chip pressed to explain
#     it. The camera was already kept, by a separate mechanism, and still is.
#
#     **The You tab is deliberately not mentioned and deliberately unchanged.** It owns no state of
#     its own — its outbox, moderation and account models were already owned by the composition root
#     — so there was nothing there to lose across a tab switch and nothing to hoist. Reporting a fix
#     for it would be reporting ceremony.
#
#   * Nothing here changes what any screen shows once everything has loaded. Every merge keeps the
#     rule it had: the phone's photograph wins a collision, the own and deletable sets are unioned,
#     the membership sets are unioned rather than replaced, and this device's status provenance is
#     still this device's.

Opening a tree no longer waits for the network, the heart answers the moment you tap it, and the map's Yours and Favorites chips narrow instantly. The map also keeps where you were and what you had filtered to when you come back to it. Anything added on another device — a photograph, a favorite — turns up a moment after the screen draws.
