-- 008 — a community tree's "added" day is the day its adder added it on the phone, and the index
-- only the retired 10 m dedupe read is dropped.
--
-- ── The day ─────────────────────────────────────────────────────────────────────────────────────
--
-- The owner's decisions of 2026-11-14 and 2026-11-15: other people see a community tree as added on
-- "the day the person added it on their phone", for every community tree, old or new. Before this
-- file, a stranger was told the day the tree went public (`published_at`) and the adder the day the
-- service received it (`created_at`). Neither is the phone's day for a tree that waited while its
-- phone was signed out or its account declined the license.
--
-- `added_on` is that day, as a calendar date. It is written once, at insert, and never changes.
-- `store.addedDay` computes it: the phone's own local date when the `add_tree` payload states one
-- (`addedOn`), else the UTC date of the add's `occurred_at`; never later than the day the service
-- received the tree, and never earlier than the day this project began (2026-07-21), because a day
-- before it is a phone clock that was wrong, and the receipt day is used instead.
--
-- Positions are not dated by this column. Where the tree stood while it was private stays private
-- (decision 13); the history's "added" row keeps the position at publication and only takes this
-- day.
--
-- ── The backfill ────────────────────────────────────────────────────────────────────────────────
--
-- Every tree already here gets `store.addedDay`'s answer for a payload that stated no day, because no
-- build before this one sent one. The instant is the `added` event's `occurred_at` (the phone's
-- time; 007 and every insert since write one per tree, with the tree's id), then the root
-- location's (the same value, by the same writers), then `created_at` as a last resort. It is held
-- to the receipt (`created_at`), as the live path holds it, and a day before 2026-07-21 is replaced
-- by the receipt's day. The UTC date of an evening add in the Americas is the next local day; the
-- service holds no time zone for those rows, so that is the residue, and it is the same day the
-- history has shown for every other event since 007.
--
-- The column then becomes NOT NULL with no default: a writer that forgets it fails, rather than
-- dating a tree by whatever a default would say.
--
-- ── The index ───────────────────────────────────────────────────────────────────────────────────
--
-- `idx_community_trees_position` (001) existed for the 10 m dedupe's bounding box. The owner removed
-- that dedupe on 2026-11-14, and no query left reads `community_trees` by position without
-- `published_at IS NOT NULL`, which 007's partial `idx_community_trees_public_position` serves.
-- It still cost a write on every add and every pin move.

ALTER TABLE community_trees ADD COLUMN added_on DATE;

UPDATE community_trees t
   SET added_on = CASE WHEN d.day < DATE '2026-07-21' THEN (t.created_at AT TIME ZONE 'UTC')::date
                       ELSE d.day END
  FROM (SELECT tree.id,
               (LEAST(coalesce((SELECT e.occurred_at FROM community_tree_events e
                                 WHERE e.id = tree.id AND e.tree_id = tree.id AND e.kind = 'added'),
                               (SELECT l.occurred_at FROM community_tree_locations l
                                 WHERE l.id = tree.id AND l.tree_id = tree.id),
                               tree.created_at),
                      tree.created_at) AT TIME ZONE 'UTC')::date AS day
          FROM community_trees tree) d
 WHERE d.id = t.id;

ALTER TABLE community_trees ALTER COLUMN added_on SET NOT NULL;

-- A phone's local date runs at most one day ahead of the UTC date of the same instant (UTC+14 is
-- the furthest east any zone reaches), and the add happened before the service received it. So a
-- day more than one past the receipt's UTC date is not a day this tree was added on.
ALTER TABLE community_trees ADD CONSTRAINT community_trees_added_on_not_after_receipt
    CHECK (added_on <= (created_at AT TIME ZONE 'UTC')::date + 1);

DROP INDEX idx_community_trees_position;
