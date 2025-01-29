DROP VIEW IF EXISTS hivemind_app.muted_accounts_by_id_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.muted_accounts_by_id_view AS
SELECT
  follower AS observer_id,
  following AS muted_id
FROM hivemind_app.muted
UNION
SELECT
  muted_direct.follower AS observer_id,
  muted_indirect.following AS muted_id
FROM hivemind_app.follow_muted AS muted_direct
JOIN hivemind_app.muted AS muted_indirect ON muted_direct.following = muted_indirect.follower;
