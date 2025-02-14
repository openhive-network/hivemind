DROP TYPE IF EXISTS hivemind_app.follow CASCADE;
CREATE TYPE hivemind_app.follow AS (
  follower TEXT,
  following TEXT,
  block_num INT
);
DROP TYPE IF EXISTS hivemind_app.follow_updates CASCADE;
CREATE TYPE hivemind_app.follow_updates AS (
  id INTEGER,
  mode TEXT,
  changes hivemind_app.follow[]
);
DROP TYPE IF EXISTS hivemind_app.mute CASCADE;
CREATE TYPE hivemind_app.mute AS (
  follower TEXT,
  following TEXT,
  block_num INT
);
DROP TYPE IF EXISTS hivemind_app.mute_updates CASCADE;
CREATE TYPE hivemind_app.mute_updates AS (
  id INTEGER,
  mode TEXT,
  changes hivemind_app.mute[]
);
DROP TYPE IF EXISTS hivemind_app.blacklist CASCADE;
CREATE TYPE hivemind_app.blacklist AS (
  follower TEXT,
  following TEXT,
  block_num INT
);
DROP TYPE IF EXISTS hivemind_app.blacklist_updates CASCADE;
CREATE TYPE hivemind_app.blacklist_updates AS (
  id INTEGER,
  mode TEXT,
  changes hivemind_app.blacklist[]
);
DROP TYPE IF EXISTS hivemind_app.follow_mute CASCADE;
CREATE TYPE hivemind_app.follow_mute AS (
  follower TEXT,
  following TEXT,
  block_num INT
);
DROP TYPE IF EXISTS hivemind_app.follow_mute_updates CASCADE;
CREATE TYPE hivemind_app.follow_mute_updates AS (
  id INTEGER,
  mode TEXT,
  changes hivemind_app.follow_mute[]
);
DROP TYPE IF EXISTS hivemind_app.follow_blacklist CASCADE;
CREATE TYPE hivemind_app.follow_blacklist AS (
  follower TEXT,
  following TEXT,
  block_num INT
);
DROP TYPE IF EXISTS hivemind_app.follow_blacklist_updates CASCADE;
CREATE TYPE hivemind_app.follow_blacklist_updates AS (
  id INTEGER,
  mode TEXT,
  changes hivemind_app.follow_blacklist[]
);

DROP FUNCTION IF EXISTS hivemind_app.insert_follows;
CREATE OR REPLACE FUNCTION hivemind_app.insert_follows(_changes hivemind_app.follow[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.follows (follower, following, block_num)
  SELECT r.id, g.id, v.block_num
  FROM UNNEST(_changes) AS v(follower, following, block_num)
  JOIN hivemind_app.hive_accounts AS r ON v.follower = r.name
  JOIN hivemind_app.hive_accounts AS g ON v.following = g.name
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_follows;
CREATE OR REPLACE FUNCTION hivemind_app.delete_follows(_changes hivemind_app.follow[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follows f
  USING hivemind_app.hive_accounts AS follower_acc,
        hivemind_app.hive_accounts AS following_acc,
        UNNEST(_changes) AS v(follower_name, following_name)
  WHERE f.follower = follower_acc.id
    AND f.following = following_acc.id
    AND follower_acc.name = v.follower_name
    AND following_acc.name = v.following_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_follows;
CREATE OR REPLACE FUNCTION hivemind_app.reset_follows(_changes TEXT[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follows f
  USING hivemind_app.hive_accounts AS follower_acc,
        UNNEST(_changes) AS v(follower_name)
  WHERE f.follower = follower_acc.id
    AND follower_acc.name = v.follower_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_muted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_muted(_changes hivemind_app.mute[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.muted (follower, following, block_num)
  SELECT r.id, g.id, v.block_num
  FROM UNNEST(_changes) AS v(follower, following, block_num)
  JOIN hivemind_app.hive_accounts AS r ON v.follower = r.name
  JOIN hivemind_app.hive_accounts AS g ON v.following = g.name
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_muted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_muted(_changes hivemind_app.mute[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.muted f
  USING hivemind_app.hive_accounts AS follower_acc,
        hivemind_app.hive_accounts AS following_acc,
        UNNEST(_changes) AS v(follower_name, following_name)
  WHERE f.follower = follower_acc.id
    AND f.following = following_acc.id
    AND follower_acc.name = v.follower_name
    AND following_acc.name = v.following_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_muted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_muted(_changes TEXT[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.muted f
  USING hivemind_app.hive_accounts AS follower_acc,
        UNNEST(_changes) AS v(follower_name)
  WHERE f.follower = follower_acc.id
    AND follower_acc.name = v.follower_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_blacklisted(_changes hivemind_app.blacklist[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.blacklisted (follower, following, block_num)
  SELECT r.id, g.id, v.block_num
  FROM UNNEST(_changes) AS v(follower, following, block_num)
  JOIN hivemind_app.hive_accounts AS r ON v.follower = r.name
  JOIN hivemind_app.hive_accounts AS g ON v.following = g.name
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_blacklisted(_changes hivemind_app.blacklist[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.blacklisted f
  USING hivemind_app.hive_accounts AS follower_acc,
        hivemind_app.hive_accounts AS following_acc,
        UNNEST(_changes) AS v(follower_name, following_name)
  WHERE f.follower = follower_acc.id
    AND f.following = following_acc.id
    AND follower_acc.name = v.follower_name
    AND following_acc.name = v.following_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_blacklisted(_changes TEXT[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.blacklisted f
  USING hivemind_app.hive_accounts AS follower_acc,
        UNNEST(_changes) AS v(follower_name)
  WHERE f.follower = follower_acc.id
    AND follower_acc.name = v.follower_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_follow_muted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_follow_muted(_changes hivemind_app.follow_mute[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.follow_muted (follower, following, block_num)
  SELECT r.id, g.id, v.block_num
  FROM UNNEST(_changes) AS v(follower, following, block_num)
  JOIN hivemind_app.hive_accounts AS r ON v.follower = r.name
  JOIN hivemind_app.hive_accounts AS g ON v.following = g.name
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_follow_muted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_follow_muted(_changes hivemind_app.follow_mute[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_muted f
  USING hivemind_app.hive_accounts AS follower_acc,
        hivemind_app.hive_accounts AS following_acc,
        UNNEST(_changes) AS v(follower_name, following_name)
  WHERE f.follower = follower_acc.id
    AND f.following = following_acc.id
    AND follower_acc.name = v.follower_name
    AND following_acc.name = v.following_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_follow_muted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_follow_muted(_changes TEXT[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_muted f
  USING hivemind_app.hive_accounts AS follower_acc,
        UNNEST(_changes) AS v(follower_name)
  WHERE f.follower = follower_acc.id
    AND follower_acc.name = v.follower_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_follow_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_follow_blacklisted(_changes hivemind_app.follow_blacklist[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.follow_blacklisted (follower, following, block_num)
  SELECT r.id, g.id, v.block_num
  FROM UNNEST(_changes) AS v(follower, following, block_num)
  JOIN hivemind_app.hive_accounts AS r ON v.follower = r.name
  JOIN hivemind_app.hive_accounts AS g ON v.following = g.name
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_follow_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_follow_blacklisted(_changes hivemind_app.follow_blacklist[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_blacklisted f
  USING hivemind_app.hive_accounts AS follower_acc,
        hivemind_app.hive_accounts AS following_acc,
        UNNEST(_changes) AS v(follower_name, following_name)
  WHERE f.follower = follower_acc.id
    AND f.following = following_acc.id
    AND follower_acc.name = v.follower_name
    AND following_acc.name = v.following_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_follow_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_follow_blacklisted(_changes TEXT[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_blacklisted f
  USING hivemind_app.hive_accounts AS follower_acc,
        UNNEST(_changes) AS v(follower_name)
  WHERE f.follower = follower_acc.id
    AND follower_acc.name = v.follower_name
  RETURNING 1;
$$ LANGUAGE sql;

DROP PROCEDURE IF EXISTS hivemind_app.flush_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.flush_follows(_follow_updates hivemind_app.follow_updates[], _muted_updates hivemind_app.mute_updates[], _blacklisted_updates hivemind_app.blacklist_updates[], _follow_muted_updates hivemind_app.follow_mute_updates[], _follow_blacklisted_updates hivemind_app.follow_blacklist_updates[], _impacted_accounts TEXT[])
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
  _dummy INTEGER;
BEGIN
  WITH accounts_id AS MATERIALIZED (
    SELECT ha.name, ha.id
    FROM hivemind_app.hive_accounts ha
    JOIN ( SELECT UNNEST( _impacted_accounts ) AS name ) AS im ON im.name = ha.name
  ),
  change_follows AS (
    SELECT
      CASE upd.mode
        WHEN 'insert' THEN (
          SELECT hivemind_app.insert_follows(upd.changes)
        )
        WHEN 'delete' THEN (
          SELECT hivemind_app.delete_follows(upd.changes)
        )
        WHEN 'reset' THEN (
          SELECT hivemind_app.reset_follows(ARRAY(SELECT v.follower FROM UNNEST(upd.changes) AS v(follower, following, block_num)))
        )
      END
    FROM unnest(_follow_updates) AS upd
    ORDER BY upd.id
  ),
  change_muted AS (
    SELECT
      CASE upd.mode
        WHEN 'insert' THEN (
          SELECT hivemind_app.insert_muted(upd.changes)
        )
        WHEN 'delete' THEN (
          SELECT hivemind_app.delete_muted(upd.changes)
        )
        WHEN 'reset' THEN (
          SELECT hivemind_app.reset_muted(ARRAY(SELECT v.follower FROM UNNEST(upd.changes) AS v(follower, following, block_num)))
        )
      END
    FROM unnest(_muted_updates) AS upd
    ORDER BY upd.id
  ),
  change_blacklisted AS (
    SELECT
      CASE upd.mode
        WHEN 'insert' THEN (
          SELECT hivemind_app.insert_blacklisted(upd.changes)
        )
        WHEN 'delete' THEN (
          SELECT hivemind_app.delete_blacklisted(upd.changes)
        )
        WHEN 'reset' THEN (
          SELECT hivemind_app.reset_blacklisted(ARRAY(SELECT v.follower FROM UNNEST(upd.changes) AS v(follower, following, block_num)))
        )
      END
    FROM unnest(_blacklisted_updates) AS upd
    ORDER BY upd.id
  ),
  change_follow_muted AS (
    SELECT
      CASE upd.mode
        WHEN 'insert' THEN (
          SELECT hivemind_app.insert_follow_muted(upd.changes)
        )
        WHEN 'delete' THEN (
          SELECT hivemind_app.delete_follow_muted(upd.changes)
        )
        WHEN 'reset' THEN (
          SELECT hivemind_app.reset_follow_muted(ARRAY(SELECT v.follower FROM UNNEST(upd.changes) AS v(follower, following, block_num)))
        )
      END
    FROM unnest(_follow_muted_updates) AS upd
    ORDER BY upd.id
  ),
  change_follow_blacklisted AS (
    SELECT
      CASE upd.mode
        WHEN 'insert' THEN (
          SELECT hivemind_app.insert_follow_blacklisted(upd.changes)
        )
        WHEN 'delete' THEN (
          SELECT hivemind_app.delete_follow_blacklisted(upd.changes)
        )
        WHEN 'reset' THEN (
          SELECT hivemind_app.reset_follow_blacklisted(ARRAY(SELECT v.follower FROM UNNEST(upd.changes) AS v(follower, following, block_num)))
        )
      END
    FROM unnest(_follow_blacklisted_updates) AS upd
    ORDER BY upd.id
  )
  SELECT COUNT(1) INTO _dummy
  FROM (
    SELECT * FROM change_follows
    UNION ALL
    SELECT * FROM change_muted
    UNION ALL
    SELECT * FROM change_blacklisted
    UNION ALL
    SELECT * FROM change_follow_muted
    UNION ALL
    SELECT * FROM change_follow_blacklisted
  ) AS x(val)
  GROUP BY val;
END
$BODY$;
