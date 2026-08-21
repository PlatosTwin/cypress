### A photograph attributed to an account is unreachable the moment that account is not the one signed in

**The report**, from the project owner's own phone on 2026-08-15: photographs taken *before* photo
deletion existed cannot be deleted. Photographs taken since can.

The delete path is Class L and local — `RoutedAPI.deletePhoto` calls `local` and nothing else, R72
ruling 5 keeps `deletePhotoRemotely` uncalled, and no photograph has ever been uploaded because the
send sink is unbuilt. So the refusal is on this device, and it is in one of two places: the row's
owner, or the file removal. It is the owner.

#### The device arm cannot break, which is what makes the diagnosis short

`PhotoOwner.isOwned(by:)` has three arms. Two of them can be decided here without knowing anything
about the phone that produced the report:

- `.device(D)` is compared against `Attribution.deviceID`, and both sides come from the same row of
  the same file: `DataLayer.boot` reads `app_state.device_uuid` and mints one only when the key is
  absent, and `AppSchema` v12's backfill wrote that same key onto every visitless photograph. The
  Keychain outlives an app deletion and `app_state` does not (`SessionCredentials`), so a database
  that still holds the photographs still holds the id that owns them. A device-owned photograph
  cannot stop being this device's.
- `.nobody` is refused deliberately — the leaving door's promise, R3 and E157 — and says so on
  screen (task #131, `TreePhotosModel.isNobodysToRemove`).

That leaves `.user(U)`, which matches only while this installation is signed in as exactly `U`.
**An undeletable photograph on this device is therefore owned by an account, and it is not the
account the app is currently holding.**

#### Measured, not reasoned

Four instruments, in order of how much they could have refuted the above.

1. **A real upgrade across two builds.** `da51250` (the commit before photo deletion, `user_version`
   11) was built into its own worktree, installed on the 16 Plus with the container empty, and made
   to write photographs through its own writer. The rows it left are today's columns minus
   `user_id`/`device_id`. The current build was then installed **over** it, and the first launch
   migrated 11 → 15 in place. All three pre-v12 photographs came out `device_id =
   187A0F37-…-0095CA1B0F42`, which is that install's `app_state.device_uuid` — owned, and deletable.
   *A plain anonymous upgrade does not reproduce the report.*
2. **A shape sweep** over the pre-v12 rows an old build could produce (on a device-owned visit, on an
   account's visit, visitless with and without an account in `app_state`), each carrying a
   photograph written by the current build as a calibration row. Every refusal in the table was a
   photograph owned by an account other than the one signed in; the calibration row was deletable in
   every case.
3. **An identity sweep**, driven through the shipping calls rather than SQL:

   | sequence after the upgrade | the upgraded photograph | a photograph taken straight afterwards |
   | --- | --- | --- |
   | signed in | deleted | deleted |
   | signed in, then signed out | **refused, `forbidden`, no control drawn** | deleted |
   | signed in, out, in as a different account | **refused, `forbidden`, no control drawn** | deleted |

4. **The running screen.** With one of three photographs of one tree put into that state
   (`user_id` set, `device_id` null — the row shape `claimDevice` leaves), the viewer over the owned
   photograph draws the trash bottom-trailing and the viewer over the other draws **nothing at all**:
   no control, and no sentence saying why. Task #131 gave the ownerless row its sentence; this state
   has none, so the app's answer to "delete my photograph" is a blank corner.

#### Why the photographs that predate the feature are the ones that are stranded

Two changes, three weeks apart, compose into exactly the boundary the report describes.

**v12's backfill is the only path in this app that gives a photograph to an account without the
person doing anything.** Every other attribution is an act: a capture stamps `PhotoOwner(attribution)`
at the moment of the shutter, and `claimDevice` moves rows because somebody signed in. The backfill
runs on an app update, and its step 2 hands every visitless photograph to
`app_state.current_user_id` — including photographs taken on that phone long before that account
existed. The migration's own comment names this ("It can over-attribute in one case") and rules it
the same as `claimDevice`'s over-attribution. It is not the same: `claimDevice` corresponds to
something a person did.

**#158 step 5 (E270) then removed the way back.** E131 states the promise in as many words — "Sign-out
records `signed_out_user_id`, so signing in again resumes the same account and everything it wrote
stays attributed." That held while `accountLink` minted the id locally. Today the only sign-in that
succeeds is Apple's (`RootView.accountLink()` throws `.unavailable` for the other two buttons) and
the id is the service's, keyed on `apple_subject`. `LocalAPI.resumableUserID()` has no shipping
caller left, and `claimDevice` clears `signed_out_user_id` on the way past — which E272 already
records, probe and all, as destroying the evidence of a deliberate sign-out. So an account minted
during the local-account era can never be signed into again, and `claimDevice` will not adopt its
rows, because it only takes rows where `user_id IS NULL`.

A device that was signed into a local account when the v12 build was installed therefore has every
photograph that existed at that moment attributed to an id that no sign-in can produce again, while
every photograph taken since belongs to the device or to the Apple account. That is "photos from
before the delete feature cannot be deleted", exactly.

The same phone's **visits** are unaffected and it is worth saying why: `visits` carries `user_id`
and `device_id` together, so a visit adopted by an account still says which phone made it. `photos`
carries at most one owner (v12's CHECK), so `claimDevice` clears `device_id` when it adopts — E23's
"strictly less about the device" — and with it goes the only evidence that this installation took
the picture.

#### What was ruled out

- The backfill leaving rows ownerless. It cannot, while `app_state.device_uuid` exists, and that key
  exists in every database that holds a photograph (above). Measured in the two-build upgrade.
- A dangling `visit_id`. `PRAGMA foreign_keys = ON` has been set on every connection since the data
  layer's first commit, and the backfill's join is on the parent key's own collation.
- The file half of `LocalAPI.deletePhoto`. A missing file is skipped, not thrown on; only a file that
  exists and refuses to be removed throws, and a stale absolute `local_path` from an older container
  is the former.
- Moderation state and visibility. `TreeProfile.ownPhotoIDs` is every row in `main.photos`, so a
  stranded photograph is still drawn — which is what makes this visible as a missing control rather
  than as a missing photograph.

#### Telling the two states apart on the phone, in five seconds

Open the photograph that will not delete.

- **A sentence saying it is nobody's to remove** → the account was deleted through the leaving door.
  Working as ruled (R3, E157); the row is anonymous permanently and by design.
- **No sentence and no control** → this one. The photograph is owned by an account that is not the
  one signed in.

#### What a repair costs, which is why this stops here

- **Forward only, no migration, no ruling**: when a new account signs in on a device that still holds
  a previous account in `app_state.current_user_id`, re-home that account's rows onto the new id
  rather than skipping them. This is D9's "everything you have already done survives signing in"
  applied to the case that arises when an account is *replaced* rather than adopted. It repairs
  nothing already stranded, because the previous id is no longer in `app_state` — only on the rows.
- **Repairing what is already stranded** means deciding that an account which is not signed in may
  still have its photographs deleted by whoever holds the phone. That is the question R3 and E157
  answered in the other direction for the leaving door, and it is a hand-me-down-phone hazard, not a
  detail. **Owner's ruling.**
- **Keeping the evidence** — a photograph that remembers which installation took it, so the question
  can be answered without inferring anything about accounts — is a column or a side table on
  `photos`, and therefore a schema version. **Migration seat, owner-assigned.**

#### Answered, 2026-08-15

**The phone is in this state.** The owner ran the check above on the photograph that will not
delete: no sentence, no control. So the photographs are owned by an account, not anonymized by the
leaving door, and the diagnosis stands as written.

**The owner chose the third repair**: the photograph remembers which installation took it, so the
question can be answered without inferring anything about accounts.

The shape that follows from the rest of this entry, for whoever holds the migration seat:

- A new column on `photos` carrying **provenance, not ownership** — the installation that wrote the
  row. It is never an owner, so v12's "at most one owner" CHECK is untouched and nothing gains a
  precedence rule to get wrong. `claimDevice` must not clear it; clearing `device_id` on adoption
  stays exactly as it is (E23).
- The delete gate admits it *in addition to* the two owner arms, and `.nobody` keeps refusing —
  the leaving door clears provenance along with the owner, or R3 and E157 are quietly repealed.
- The backfill writes `app_state.device_uuid` onto every existing row, on the same standing fact v12
  reasoned from and that `LocalAPI.treeProfile` restates where it fills `ownPhotoIDs`: every row in
  `main.photos` was written by this installation. That is what repairs the photographs already
  stranded, and it is a weaker claim than v12's, because it attributes a machine rather than a
  person.

#### Built, in a round of its own

The owner assigned the seat in the same decision round. `AppSchema` **v16**, "a photograph
remembers which installation took it", is that column, and it is the shape above:
`taken_on_device` is provenance and no query reads it as an owner, `claimDevice` leaves it alone,
the leaving door clears it in the same statement that takes the name off, and the backfill writes
`app_state.device_uuid` onto every row that still has an owner — which is what repairs the
photographs already stranded on the phone this was reported from.

`PhotoOwner.permitsRemoval(by:takenOnDevice:)` is where the three arms meet, and it refuses
`.nobody` before it reads provenance; `ContributionStore.removalPredicate` is that rule as SQL, in
one place because it is written in three — the set that draws the control, the vote delete and the
tombstone `UPDATE` — and it leads with the same refusal. Neither of those two lines is decoration.
An earlier draft of this entry said that removing either one turns "exactly one expectation red on
its own"; that was written from reasoning rather than from a log, and the review measured otherwise
— one edit at a time, restored by file copy between runs, on iPhone 16 Pro `EA0AD796-…`:

- removing the Swift `.nobody` refusal turned **three** expectations red:
  `PhotoProvenanceTests.anOwnerlessRowIsRefusedWhateverTheProvenanceSays`' first `#expect`, and in
  `PhotoDeletionTests.anAnonymizedPhotographIsRefused` both the error expectation — `expected error
  ".forbidden" of type APIError, but ".notFound" of type APIError was thrown instead` — and the
  `fileExists` line after it;
- removing the SQL leading clause turned **two** red: the same provenance test's second `#expect`,
  and `PhotoOwnershipTests` on `an anonymized photograph is still shown and is no longer deletable`.

**The `.notFound`/`fileExists` pair was not a second copy of the same guard, and finding out why
changed the code.** `LocalAPI.deletePhoto` removed the bytes from disk before the SQL predicate was
ever evaluated, so in precisely the case the SQL clause exists to be the belt for — Swift permits,
SQL refuses — the row was correctly saved and the photograph was already destroyed, and the caller
was told `notFound`. Unreachable with both halves in place, since the two rules agree on every row
shape; reachable the moment one of them drifts, which is what belt-and-braces is for. The method
now claims the row inside its write transaction first and removes the bytes only once the tombstone
has taken, which also closes the race the `counts.photos == 1` guard used to report *after* the
files were gone. With the fix in, that same `.nobody` red-proof lands two issues rather than three:
the refused delete no longer touches the picture, so the `fileExists` line stays green.

**Not the backfill the owner ruled against on the same day.** That ruling is about sync —
pre-sync-path rows and pre-existing photo binaries stay on the device permanently, nothing is
re-enqueued, no future send path sweeps them up. v16 writes one local column, enqueues nothing and
uploads nothing.

**One existing test changed, and it is worth reading before the diff is trusted.**
`PhotoDeletionTests.astrangersPhotographIsRefused` made a stranger's photograph by writing one on
this device and then rewriting `user_id`. Since v16 that row still says, truthfully, that this
installation took it — which is the case v16 admits — so the fixture now also gives it a stranger's
installation. That is the fixture being made to mean its own name, and the guard it protects is
asserted independently by `PhotoProvenanceTests.aStrangersPhotographIsStillRefused`.

**What is deliberately not in it.** The state this report came from draws a photograph with no
delete control and no sentence. After v16 that state is much rarer and not impossible — a
photograph that genuinely came from another installation will produce it the day anything syncs one
down. Task #131 gave the ownerless row its sentence; this one still has none. New copy on a shipped
screen is a stop-and-ask (DECISIONS constraint 21), so it stays here rather than in the diff.

#### Left for the owner

**The same root cause reaches the other consumer of "is this mine", and v16 does not follow it
there.** The diagnosis in this entry is that `.user(U)` matches only while this installation is
signed in as exactly `U`, and E270 made a local-era `U` impossible to sign into again. v16 repairs
the *deletion* consumer of that comparison. It has a second consumer:
`ContributionStore.heroPhotoIDs(treeIDs:attribution:)`'s `is_own` column, which feeds
`TreeProfile.isPhotoVisible(_:own:)` — `own ? isVisibleToItsContributor : isPubliclyVisible`.

Take the photograph this report is about: taken on this phone, adopted by `claimDevice`, owned by an
account that can no longer be signed into. After v16 it is deletable again. It is still `own: false`
to `is_own`, which has the two owner arms and no provenance term, so in the species-guide nearby
heroes (07 §6) it is judged by `isPubliclyVisible`, it is `.pending`, and **it is not drawn at all**.
Nothing in the app can set `.approved`.

This is not a regression — the behaviour is identical before and after v16 — which is why it is
recorded here rather than fixed in that change. The decision it needs is the owner's, because
either answer moves a screen: leave the two predicates deliberately different (deletion is about
permission, `is_own` is about attribution-for-visibility, and provenance is not attribution), or put
`is_own` on the same three-arm rule, which starts drawing photographs on the nearby section that
are not drawn today. The doc comments on `heroPhotoIDs` and on `TreeProfile.isPhotoVisible` now say
the two comparisons differ on purpose and that the visibility consequence is the owner's to settle;
before v16 they both claimed the comparisons were the same, which is how this went unnoticed.
Neither cites this entry, because `PendingCitationGuardTests` refuses a comment that defers to a
document with no number — when this is spliced, its number is what those two comments should gain.
