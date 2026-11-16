-- 009 — a species answer on a community tree somebody else added counts for everyone (ROADMAP 144).
--
-- The owner's decisions of 2026-11-15 and 2026-11-16:
--   - On a tree with no species, the first answer names the tree for everyone, marked "species named
--     by a contributor". The adder can still correct it.
--   - On a tree that has a species, the name stays, and the profile shows "Somebody has reported this
--     species as wrong." until the adder or the operator corrects it.
--   - Only people who share count: a naming or a report from anybody but the adder changes anything
--     only when it comes from an account that has accepted a known license version.
--   - The adder's "Keep the species" (`species_review_dismissal`) clears the reported state for
--     everyone. A later report brings it back.
--   - The person who named a tree can correct their own answer until the adder corrects or keeps
--     the species. After that only the adder and the operator can change it.
--
-- `store.materializeSpecies`, `store.recordSpeciesReport` and `store.keepSpecies` hold the rules.
-- This file holds the state they need. Every rule is decided under the tree's row lock, in the
-- order the service commits the acts. No rule compares one phone's clock with another's.
--
-- ── The three columns ───────────────────────────────────────────────────────────────────────────
--
-- `species_set_by` is who set the species in force: the adder, a contributor, or the operator. NULL
-- is a species no rule here set: one the adder named before this file (only the adder could), one
-- the `add_tree` carried, or no species at all. Every reader treats NULL as "the adder".
--
-- `species_namer_user_id` is the account whose contributor naming is in force. It is what lets the
-- namer correct their own answer, and nothing else reads it. It is a column, not a lookup of the
-- naming event's actor, for two reasons. The adder's correction or keep must end the namer's right
-- even when it keeps the same species, which no event says. And the account's deletion must end it
-- too: `deleteAccountTrees` nulls it (the decision point for "the species stays"), and the foreign
-- key's `ON DELETE SET NULL` is the second guard. A naming with no namer is a naming nobody but the
-- adder and the operator can change.
--
-- `species_reports_cleared_at` is the last time the adder or the operator cleared the reported state.
-- A report counts only when the service recorded it after this moment. It is a column rather than a
-- reading of the adder's dismissal rows, because the erase door deletes those rows, and a cleared
-- state must not come back when its adder erases their account.
--
-- No backfill. Every existing tree reads NULL in all three, which is what it was before this file:
-- named by its adder (or not named), and never cleared. The only thing that can change what a reader
-- sees at deploy is a report that already counts, and none can: a report counts only through a
-- `species_reported` event, and no writer before this file wrote one. The orchestrator's pre-deploy
-- count is in the round's report.
--
-- ── The two event kinds ─────────────────────────────────────────────────────────────────────────
--
-- `species_reported` is a report that counts: written only for a report from a sharing account that
-- is not the adder, on a named tree it can see. Its `before.species_id` is the species the report
-- disputes, fixed when the service received it (the payload's `disputedSpeciesID` when the phone
-- sent one, otherwise the tree's species at that moment). So a report keeps meaning the name it was
-- about, whatever happens to the tree afterwards. `species_reports_cleared` is the adder's keep or
-- the operator's clear. Both stay out of every history (`withheldHistoryKinds`).
--
-- ADD COLUMN and ADD CONSTRAINT fail on a second run, so `TestOnlyPendingMigrationsRun` holds.

ALTER TABLE community_trees
    ADD COLUMN species_set_by TEXT
        CONSTRAINT community_trees_species_set_by_is_known
        CHECK (species_set_by = ANY (ARRAY['adder', 'contributor', 'operator'])),
    ADD COLUMN species_namer_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN species_reports_cleared_at TIMESTAMPTZ;

ALTER TABLE community_trees ADD CONSTRAINT community_trees_only_a_contributor_naming_has_a_namer
    CHECK (species_namer_user_id IS NULL OR species_set_by = 'contributor');

CREATE INDEX idx_community_trees_species_namer ON community_trees (species_namer_user_id)
    WHERE species_namer_user_id IS NOT NULL;

ALTER TABLE community_tree_events DROP CONSTRAINT community_tree_events_kind_is_known;
ALTER TABLE community_tree_events ADD CONSTRAINT community_tree_events_kind_is_known
    CHECK (kind = ANY (ARRAY['added', 'published', 'location_corrected',
                             'species_named', 'species_corrected', 'withdrawn', 'taken_down',
                             'species_reported', 'species_reports_cleared']));

CREATE INDEX idx_community_tree_events_species_reports ON community_tree_events (tree_id, recorded_at DESC)
    WHERE kind = 'species_reported';
