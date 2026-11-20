# Tester-visible, not `internal:` — owner ruling 2026-09-28.
#
# Before this deploy, reporting a mistake in a city tree's record (or withdrawing that report)
# added the tree to the reporter's map "Yours" filter and to their Grove, contradicting the report
# screen's own copy, "Nothing on the map changes." After this deploy neither action enrolls the
# tree. A tester who reported a tree earlier and saw it show up in Yours or the Grove will see it
# drop out on the next refresh, unless something else (a visit, adding it, etc.) also counts.
#
# 108 characters, under the 200 the checker enforces.

Reporting a mistake in a tree's record no longer adds that tree to your map's Yours filter or to your Grove.
