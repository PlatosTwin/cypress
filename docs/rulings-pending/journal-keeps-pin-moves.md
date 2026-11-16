# Rulings pending: after sign-out, the Journal keeps the pin moves made on this phone

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

### R??? — What the Journal and its export show of what you recorded while signed in

**The owner's decision of 2026-11-16 (ROADMAP chip 152).** Asked "After you sign out, what should
the Journal and its export show of what you recorded while signed in?", the owner chose
**"Everything, pin moves too"**. The option's description read: matches the sign-out row's promise,
"Keeps everything you have saved", and the export's "everything you have recorded on this phone";
needs a phone database change (one new column).

**What was wrong.** Sign-in gives this phone's earlier rows to the account. On the four contribution
tables (visits, check-ins, measurements, care events) the row keeps its `device_id` too. On
`tree_locations` it cannot: that table allows at most one owner, so the claim clears `device_id`.
The Journal and the export ask for "this device, or the signed-in account". So after sign-out the
visits stayed and the pin moves left, and they came back at the next sign-in.

**The design.**

1. **Migration v24 of the phone's writable database** adds `tree_locations.set_on_device`, the
   installation that set the position. It follows v16's `photos.taken_on_device` and R82: it records
   provenance, not ownership.
2. **The fill.** For rows already on the phone, v24 writes this phone's device id on every row that
   this phone owns or that an account owns. It skips a row with neither owner (an account deletion
   anonymized it, and it is nobody's for ever, R3 and E157), a row that another installation owns,
   and a row that already has a value. The column is added only when it is missing. A replay
   changes nothing.
3. **The writers.** `LocalAPI.addTree` (the root row, through `CommunityTreeStore.insert`) and
   `LocalAPI.correctLocation` (each move) write this phone's device id.
4. **The reader.** The Journal's pin-move part also matches a row whose `set_on_device` is this
   phone. The export is built from the Journal, so it follows. Nothing else reads the column.
5. **Provenance is not ownership.** Nothing that decides who may move a pin reads the column
   (`correctLocation` asks the tree's adder). Sign-in does not change it. Nothing sent to the service
   carries it: the queued `location_correction` payload and its wire fixture are unchanged.
6. **Account deletion.** The keep-records door clears `set_on_device` in the statement that clears
   `user_id`, as it clears `photos.taken_on_device`. Without that, the deleted account's moves would
   come back in the Journal of whoever holds the phone next. The erasing door already deletes the
   positions of the trees it deletes, and clears the rest through the same statement.
   `AccountDeletion.OwnedTable.treeLocations` lists the column.

**What this does not decide.** Whether a second account that signs in on the same phone should see
the first account's work. Today that is reachable only when the first account was deleted from a
different phone. It is a separate ROADMAP item.
