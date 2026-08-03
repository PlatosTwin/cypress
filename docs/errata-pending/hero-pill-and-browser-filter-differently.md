# E?? — the hero pill and the photo browser filter the same series by two different rules

**Unnumbered.** Found while building #131 (`p1/round9-a`). **Filed, not fixed** — #131 was told to
verify the premise and write it up, not to build it.

**Latent, not live.** Nothing brings anybody else's photographs down today, so the two rules are
handed the same rows and cannot disagree. The day anything syncs, they can.

---

## The premise as it reached me, and why it did not survive the code

The brief said:

> The hero's metadata pill counts the tree's photographs; screen 20 lists only what this
> installation wrote. … a tree with community photographs shows `214 photos` on the pill and an
> empty browser behind it.

That is E173's own "seen while reading" note, and **it is wrong in its mechanism and backwards in its
direction.** Both sites read the *same* `Series<Photo>`:

- `Cypress/Data/API/LocalAPI.swift` — `treeProfile(id:)` builds `TreeProfile.photos` from
  `contributions.photos(treeID:connection:)`, one read of `main.photos`. Both surfaces get it.
- `Cypress/Core/Models/Series.swift` — `totalCount` is `items.count` when the read was complete, and
  `filter` carries completeness through. So the pill's number is **the count of the rows it was
  handed after filtering**, not a `COUNT(*)` over the tree. There is no whole-tree total anywhere in
  this path for the pill to be reading.

So the pill is not counting "the tree's photographs" and the browser is not narrowing a wider set.
Neither reads a total over a page; E38's shape is not what is wrong here.

## What is actually wrong

**The two sites apply different predicates to the same series**, and only one of them is
own-aware:

- `Cypress/Features/TreeProfile/TreeProfilePresentation.swift`, `visiblePhotos` (the pill, the hero,
  the season strip):
  `profile.photos.filter { profile.isOwnPhoto($0) ? $0.isVisibleToItsContributor : $0.isPubliclyVisible }`
- `Cypress/Features/Photos/TreePhotosModel.swift`, `load()` (screen 20's list, and the viewer through
  the same model):
  `profile.photos.items.filter(\.isVisibleToItsContributor)`

They agree today for one reason and it is not a coincidence: `LocalAPI` sets
`ownPhotoIDs: Set(photos.items.map(\.id))` — *every* row — so `isOwnPhoto` is unconditionally true
and the ternary never reaches its second arm.

**The moment a read returns a row this installation did not write, the browser's filter is the wrong
one, and it fails open.** `isVisibleToItsContributor` is `deletedAt == nil`; `isPubliclyVisible` is
`.approved && deletedAt == nil`. Nothing in the app can set `.approved`. So a synced photograph of
somebody else's would be:

- **absent** from the hero pill and the hero (correctly gated on `.approved`), and
- **present** in screen 20's list and openable in the viewer.

That is the opposite of the brief's `214 photos` over an empty browser: the browser would show
*more* than the pill, and what it would show is other people's unmoderated photographs on the
contributor's own screen. That is E37's rule — moderation gates publication, not a person's own
screen — read as though every row were the reader's own.

## Why it is worth fixing before a sync exists

E38's entry is about a number that outruns the rows behind it. This is the same family seen from the
other side and it is worse than a wrong count: after a sync it presents not as data loss but as the
app showing somebody a stranger's photograph that nothing has reviewed. The repair is small while
the sets coincide — screen 20 asking `TreeProfile`'s own question rather than a photograph's — and it
is a moderation defect afterwards.

## The two code sites

- `Cypress/Features/TreeProfile/TreeProfilePresentation.swift` · `visiblePhotos`
- `Cypress/Features/Photos/TreePhotosModel.swift` · `load()`

The fact that makes them agree today, and would have to change first:
`Cypress/Data/API/LocalAPI.swift` · `ownPhotoIDs: Set(photos.items.map(\.id))`.

## What is *not* wrong, checked while here

`TreeProfile.deletablePhotoIDs` and the new `anonymizedPhotoIDs` (#131) are both asked of the
columns with their own SQL and are unaffected by any of the above.
