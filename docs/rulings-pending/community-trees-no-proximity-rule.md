# Rulings pending: the 10 m rule no longer refuses a new tree or a pin move (owner's ruling, 2026-11-14)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

---

### R??? — A tree may stand within 10 m of another: the proximity rule stops refusing (reverses part of DECISIONS constraint 16)

**The owner's ruling of 2026-11-14.** It reverses the second half of DECISIONS constraint 16
("Add-a-tree requires a photo and runs the 10 m proximity dedupe"), and the pending ruling of
2026-11-12 that a moved pin may not land within 10 m of another tree
(`community-trees-move-pin.md`). It answers the tester's request in F32, finding 3 ("need to be able
to add tree even if less than 6m to known tree").

**The owner's words**, asked how far a pin may be moved: *"can go anywhere, and also fine to go
within 10m of another tree. sometimes they will be close together and that's fine"*.

**The confirmation.** Because that answer reversed a standing rule, the owner was asked in a second
dialog how far the reversal goes: pin moves only, or pin moves and new trees. **Chosen: moves and new
trees.**

#### What changes

- **Adding a tree.** The phone and the service stop refusing a new tree because another tree is
  recorded within 10 m. The Add this tree screen keeps its "ALREADY ON RECORD" notice as a note that
  does not block: "Something is already on record within 10 m of here. Add this tree only if it is a
  different one." The list of nearby trees stays under the note and the Add this tree button stays
  active (the owner's answers of the same day, `community-trees-c3-answers.md`).
- **Moving a pin.** The phone and the service stop refusing a move that lands within 10 m of another
  tree. The Move pin screen shows no note about nearby trees.
- **Strings that go with the rule.** On the Move pin screen: the second sentence of the rule line
  ("A pin cannot be within 10 m of another tree."), which leaves "Drag the map to put the pin on the
  tree.", and the refusal "Another tree is recorded within 10 m of that spot. Move the pin farther
  from it." On the Add this tree screen: "Nothing was added." and "If one of these is the tree in
  front of you, open it."

#### What does not change (the orchestrator's reading; the owner was not asked)

- **The photo requirement** in constraint 16, and its first sentence (community trees stay in a
  visually distinct layer until verified).
- **The 10 m number where it is not this rule.** `DataDispute.positionResolutionRadiusM` reuses the
  same number to decide when a position dispute is resolved. That is a different rule and it stays.
- **The 75 m bound on the add flow's pin** (a pin stays within 75 m of the reader's fix).

#### What the round that builds it has to do (facts, not rulings)

- **It is a service change and a deploy.** The service refuses in three places today:
  `addTree` and the `add_tree` path of `POST /sync` (`server/internal/api/sync.go`), and
  `applyLocationCorrection` (`server/internal/store/community_trees.go`), each through
  `store.ProximityDedupeRadiusM`. A build that stops refusing on the phone must not ship before the
  service stops refusing, or a tree the phone accepted comes back as a conflict. Deploying
  `cypress-sync` needs the owner's go-ahead each time.
- **Builds already installed still refuse** on the phone until they update. That is safe: the phone
  is stricter than the service, never looser.
- **On the phone** the refusals are `LocalAPI.addTree` and `LocalAPI.correctLocation`
  (`ProximityConflict`), both through `TreeDraft.proximityDedupeRadiusM`. The Add this tree note
  still needs the nearby-tree lookup, so the constant and the lookup stay; only the refusal goes.
- **A double send is a different thing.** Two sends of one add are matched on `client_uuid`
  (constraint 8), which this ruling does not touch. Verify that nothing else relied on the proximity
  refusal to stop a duplicate, for example an add repeated after a failed response.
- **A tree the service refused in the past.** The phone refuses before it queues, so most refused
  adds were never recorded. A tree added offline that the service later refused as a conflict stays
  on its adder's phone with a terminal Outbox row. Whether a later build sends such a tree again is
  the owner's decision; bring it to the owner if the round finds any.
- `docs/distilled/DECISIONS.md` constraint 16 and `community-trees-move-pin.md` are edited by the
  round that builds this, when the ruling is spliced, so the documents and the code change together.
