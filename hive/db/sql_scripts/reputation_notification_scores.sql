--- The scores of the notifications scored by their source's reputation (types 11-16) ---

-- A row while those scores await a rescore from reptracker's reputations: finalization
-- found reptracker behind hivemind's block (block_num) and went live without waiting for
-- it. Live sync runs the rescore (DbState.rescore_pending_reputation_notifications) in the
-- transaction of the first block it processes once reptracker has the blocks hivemind
-- completed; the rescore deletes the row in its transaction.
-- MUST remain LOGGED, like _batch_queue: a restarted hivemind still owes the rescore.
CREATE TABLE IF NOT EXISTS hivemind_app._reputation_rescore_pending (
    block_num INT NOT NULL
);


-- True while a source's reputation at write time may not be its final one, so the writers
-- of reputation-scored notifications keep a row whatever its score and the rescore
-- (DbState._rescore_reputation_notifications) deletes those scoring <= 0:
-- - a batch of the initial massive sync runs: a batch is in flight (_batch_queue holds its
--   range; live sync leaves it empty) and no finalization has completed yet (hive_state
--   still holds its seed), while reptracker syncs beside it;
-- - a rescore is pending (_reputation_rescore_pending): reptracker is still behind the
--   blocks hivemind writes.
CREATE OR REPLACE FUNCTION hivemind_app.reputation_notification_cut_deferred()
RETURNS BOOLEAN AS $$
    SELECT (EXISTS (SELECT 1 FROM hivemind_app._batch_queue)
            AND (SELECT last_completed_block_num FROM hivemind_app.hive_state) <= 1)
        OR EXISTS (SELECT 1 FROM hivemind_app._reputation_rescore_pending);
$$ LANGUAGE sql STABLE;

