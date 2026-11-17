# Unnumbered. The orchestrator splices these under the next R numbers at merge (CLAUDE.md,
# Numbering). Written by the author of `feat/picker-names-and-second-phone-grove`, 2026-11-16.
# The owner's answers 12 to 14 of the third dialog of 2026-11-16, quoted exactly.

### R??? — The nearby lists name an added tree by its species (the owner's answer, 2026-11-16)

This extends **R251** (rows in the Journal and the Outbox) and **R253** (My Grove) to the three
lists that show species only. The owner was asked (answer 12):

Q: "Three lists still call an added tree with a species "Unidentified tree": the "What tree is
this?" list, the "ALREADY ON RECORD" note when you add a tree, and the neighbor title on a site.
They show species only, never a given name. Should they show the added tree's species?"
A: "Yes, show the species (Recommended)". Option text: "An added tree with a species reads, for
example, "Sycamore, London Plane" in those three lists, as it now does in its profile, the
Journal, the Outbox, and My Grove. A tree with no species still reads "Unidentified tree". I build
it in the next batch."
Not chosen: "No, leave them" ("Those three lists keep calling every added tree "Unidentified
tree", even when someone gave it a species. Nothing to build.").

What the code does (branch `feat/picker-names-and-second-phone-grove`):

- `LocalAPI.treesNear` gives an added tree's nearby record the species its profile title shows:
  the common name and the scientific name, as the seed stores them. For somebody else's cached
  tree that the reader named or corrected, the reader's species is laid over the cache while it
  is in force. This is the same overlay the row names use (`LocalAPI.communityShownSpecies`), so
  a list and the profile cannot disagree.
- The three lists keep their rule: the common name, else the scientific name, else "Unidentified
  tree" (on a site's neighbor line: the address, else "Unidentified"). A given name is never
  shown in them.
- The same record feeds the saved screen's "Next nearest" line and the subject of a visit started
  from the "What tree is this?" list, which follow the same rule.
- The shortlist's "Tell them apart" banner does **not** use an added tree's species
  (`VisitDistinguisher`, the `.species` case returns nothing for a tree whose `source` is
  `.community`). The owner's answer approved the species as the title in the three lists. It did
  not speak to the banner, and the banner keeps to inventory data, as `VisitDistinguisher`'s header
  requires: a self-reported species is one person's guess, and a duplicate add of a city tree
  with a wrong guess would otherwise be told apart "by species". So a pair that includes an added
  tree gets the same banner as before this branch: the next inventory fact (address, planting
  site, age, trunk size), or "These two records carry the same details. Pick the one you are
  standing at." Two city trees of different species are still told apart by species. Whether a
  self-reported species may separate two trees is being put to the owner; this entry does not
  record a decision on it.

This branch also meets R253's sentence "An added tree with no name and no species still reads
"Tree"" for a tree a second phone reaches only through the account's grove (ROADMAP chip 206):
`LocalAPI.groveCityFileRows` and `RoutedAPI.resolvedCityFileRows` name such a tree with an empty
title, which My Grove draws as "Tree", where both used to drop it. A seed tree with no species and
no given name reached the same way reads "Tree" too. A tree this phone withdrew still leaves My
Grove, and none of these rows marks the read as fallen back.

### R??? — Naming or reporting a species counts as a contribution on the service (the owner's answer, 2026-11-16)

The owner was asked (answer 13):

Q: "When you name or report the species of a tree somebody else added, the service now counts
that tree as one of yours, so it joins your "Yours" trees and My Grove on the service, the same as
a tree you visited. Is that what you want?"
A: "Yes, it counts (Recommended)". Option text: "Naming or reporting a species is a contribution
like a visit, so the tree joins your trees. This is how the service works today. Nothing to build."
Not chosen: "No, it should not count".

What the code does: nothing changes. `TreeMembershipKinds` (`server/internal/store/reads.go`)
counts species statements and species reports as membership, so such a tree joins the sender's
"Yours" trees and My Grove on the service (ROADMAP chip 168).

### R??? — A refused withdrawal row that can never leave stays (the owner's answer, 2026-11-16)

The owner was asked (answer 14):

Q: "You ruled that a withdrawal the service refused stays in the Outbox with its reason and no
button. In two rare cases that row can never leave for the life of the install: after an account
deletion that keeps your records, and when the withdrawal was made while signed out. Should such a
row get a way out?"
A: "Leave it (Recommended)". Option text: "Both cases are rare, and the row is one line that says
why the tree stays on the map. Nothing to build. The roadmap keeps the note."
Not chosen: "Remove it at account deletion".

What the code does: nothing changes. The two cases are written in **R249** and in ROADMAP chip
204: after a keep-records deletion the row's payload names no account, so a later erasing deletion
does not match it; and a withdrawal made while signed out names only the device, which
`OutboxStore.forgetAccount` does not match.
