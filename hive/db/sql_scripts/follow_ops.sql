DROP TYPE IF EXISTS hivemind_app.follow CASCADE;
CREATE TYPE hivemind_app.follow AS (
  follower TEXT,
  following TEXT,
  block_num INT
);
DROP TYPE IF EXISTS hivemind_app.follow_ids CASCADE;
CREATE TYPE hivemind_app.follow_ids AS (
  follower_id INTEGER,
  following_id INTEGER,
  block_num INTEGER
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
DROP TYPE IF EXISTS hivemind_app.mute_ids CASCADE;
CREATE TYPE hivemind_app.mute_ids AS (
  follower_id INTEGER,
  following_id INTEGER,
  block_num INTEGER
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
DROP TYPE IF EXISTS hivemind_app.blacklist_ids CASCADE;
CREATE TYPE hivemind_app.blacklist_ids AS (
  follower_id INTEGER,
  following_id INTEGER,
  block_num INTEGER
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
DROP TYPE IF EXISTS hivemind_app.follow_mute_ids CASCADE;
CREATE TYPE hivemind_app.follow_mute_ids AS (
  follower_id INTEGER,
  following_id INTEGER,
  block_num INTEGER
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
DROP TYPE IF EXISTS hivemind_app.follow_blacklist_ids CASCADE;
CREATE TYPE hivemind_app.follow_blacklist_ids AS (
  follower_id INTEGER,
  following_id INTEGER,
  block_num INTEGER
);
DROP TYPE IF EXISTS hivemind_app.follow_blacklist_updates CASCADE;
CREATE TYPE hivemind_app.follow_blacklist_updates AS (
  id INTEGER,
  mode TEXT,
  changes hivemind_app.follow_blacklist[]
);

DROP FUNCTION IF EXISTS hivemind_app.insert_follows;
CREATE OR REPLACE FUNCTION hivemind_app.insert_follows(_changes hivemind_app.follow_ids[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.follows (follower, following, block_num)
  SELECT v.follower_id, v.following_id, v.block_num
  FROM UNNEST(_changes) AS v(follower_id, following_id, block_num)
  ORDER BY v.block_num
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_follows;
CREATE OR REPLACE FUNCTION hivemind_app.delete_follows(_changes hivemind_app.follow_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follows f
  USING UNNEST(_changes) AS v(follower_id, following_id)
  WHERE f.follower = v.follower_id
    AND f.following = v.following_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_follows;
CREATE OR REPLACE FUNCTION hivemind_app.reset_follows(_changes hivemind_app.follow_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follows f
  USING UNNEST(_changes) AS v(follower_id, following_id, block_num)
  WHERE f.follower = v.follower_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_muted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_muted(_changes hivemind_app.mute_ids[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.muted (follower, following, block_num)
  SELECT v.follower_id, v.following_id, v.block_num
  FROM UNNEST(_changes) AS v(follower_id, following_id, block_num)
  ORDER BY v.block_num
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_muted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_muted(_changes hivemind_app.mute_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.muted f
  USING UNNEST(_changes) AS v(follower_id, following_id)
  WHERE f.follower = v.follower_id
    AND f.following = v.following_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_muted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_muted(_changes hivemind_app.mute_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.muted f
  USING UNNEST(_changes) AS v(follower_id, following_id, block_num)
  WHERE f.follower = v.follower_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_blacklisted(_changes hivemind_app.blacklist_ids[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.blacklisted (follower, following, block_num)
  SELECT v.follower_id, v.following_id, v.block_num
  FROM UNNEST(_changes) AS v(follower_id, following_id, block_num)
  ORDER BY v.block_num
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_blacklisted(_changes hivemind_app.blacklist_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.blacklisted f
  USING UNNEST(_changes) AS v(follower_id, following_id)
  WHERE f.follower = v.follower_id
    AND f.following = v.following_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_blacklisted(_changes hivemind_app.blacklist_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.blacklisted f
  USING UNNEST(_changes) AS v(follower_id, following_id, block_num)
  WHERE f.follower = v.follower_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_follow_muted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_follow_muted(_changes hivemind_app.follow_mute_ids[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.follow_muted (follower, following, block_num)
  SELECT v.follower_id, v.following_id, v.block_num
  FROM UNNEST(_changes) AS v(follower_id, following_id, block_num)
  ORDER BY v.block_num
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_follow_muted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_follow_muted(_changes hivemind_app.follow_mute_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_muted f
  USING UNNEST(_changes) AS v(follower_id, following_id)
  WHERE f.follower = v.follower_id
    AND f.following = v.following_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_follow_muted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_follow_muted(_changes hivemind_app.follow_mute_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_muted f
  USING UNNEST(_changes) AS v(follower_id, following_id, block_num)
  WHERE f.follower = v.follower_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.insert_follow_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.insert_follow_blacklisted(_changes hivemind_app.follow_blacklist_ids[])
RETURNS INTEGER AS $$
  INSERT INTO hivemind_app.follow_blacklisted (follower, following, block_num)
  SELECT v.follower_id, v.following_id, v.block_num
  FROM UNNEST(_changes) AS v(follower_id, following_id, block_num)
  ORDER BY v.block_num
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.delete_follow_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.delete_follow_blacklisted(_changes hivemind_app.follow_blacklist_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_blacklisted f
  USING UNNEST(_changes) AS v(follower_id, following_id)
  WHERE f.follower = v.follower_id
    AND f.following = v.following_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP FUNCTION IF EXISTS hivemind_app.reset_follow_blacklisted;
CREATE OR REPLACE FUNCTION hivemind_app.reset_follow_blacklisted(_changes hivemind_app.follow_blacklist_ids[])
RETURNS INTEGER AS $$
  DELETE FROM hivemind_app.follow_blacklisted f
  USING UNNEST(_changes) AS v(follower_id, following_id, block_num)
  WHERE f.follower = v.follower_id
  RETURNING 1;
$$ LANGUAGE sql;

DROP PROCEDURE IF EXISTS hivemind_app.flush_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.flush_follows(_follow_updates hivemind_app.follow_updates[], _muted_updates hivemind_app.mute_updates[], _blacklisted_updates hivemind_app.blacklist_updates[], _follow_muted_updates hivemind_app.follow_mute_updates[], _follow_blacklisted_updates hivemind_app.follow_blacklist_updates[], _impacted_accounts TEXT[])
LANGUAGE plpgsql
AS $BODY$
DECLARE
  _count INTEGER;
BEGIN
  WITH accounts_id AS MATERIALIZED (
    SELECT ha.name, ha.id
    FROM hivemind_app.hive_accounts ha
    JOIN ( SELECT UNNEST( _impacted_accounts ) AS name ) AS im ON im.name = ha.name
  ),
  change_follows AS MATERIALIZED (
    SELECT
      CASE upd_with_ids.mode
        WHEN 'insert' THEN (
          hivemind_app.insert_follows(upd_with_ids.changes)
        )
        WHEN 'delete' THEN (
          hivemind_app.delete_follows(upd_with_ids.changes)
        )
        WHEN 'reset' THEN (
          hivemind_app.reset_follows(upd_with_ids.changes)
        )
      END
    FROM (
      SELECT
        upd.id,
        upd.mode,
        ARRAY_AGG( ROW(r.id, g.id, ch.block_num)::hivemind_app.follow_ids) AS changes
      FROM UNNEST(_follow_updates) AS upd
      CROSS JOIN LATERAL UNNEST(upd.changes) AS ch(follower, following, block_num)
      JOIN accounts_id AS r ON ch.follower = r.name
      LEFT JOIN accounts_id AS g ON ch.following = g.name
      GROUP BY upd.id, upd.mode
      ORDER BY upd.id
    ) AS upd_with_ids
    ORDER BY upd_with_ids.id
  ),
  change_muted AS MATERIALIZED (
    SELECT
      CASE upd_with_ids.mode
        WHEN 'insert' THEN (
          hivemind_app.insert_muted(upd_with_ids.changes)
        )
        WHEN 'delete' THEN (
          hivemind_app.delete_muted(upd_with_ids.changes)
        )
        WHEN 'reset' THEN (
          hivemind_app.reset_muted(upd_with_ids.changes)
        )
      END
    FROM (
      SELECT
        upd.id,
        upd.mode,
        ARRAY_AGG( ROW(r.id, g.id, ch.block_num)::hivemind_app.mute_ids) AS changes
      FROM UNNEST(_muted_updates) AS upd
      CROSS JOIN LATERAL UNNEST(upd.changes) AS ch(follower, following, block_num)
      JOIN accounts_id AS r ON ch.follower = r.name
      LEFT JOIN accounts_id AS g ON ch.following = g.name
      GROUP BY upd.id, upd.mode
      ORDER BY upd.id
    ) AS upd_with_ids
    ORDER BY upd_with_ids.id
  ),
  change_blacklisted AS MATERIALIZED (
    SELECT
      CASE upd_with_ids.mode
        WHEN 'insert' THEN (
          hivemind_app.insert_blacklisted(upd_with_ids.changes)
        )
        WHEN 'delete' THEN (
          hivemind_app.delete_blacklisted(upd_with_ids.changes)
        )
        WHEN 'reset' THEN (
          hivemind_app.reset_blacklisted(upd_with_ids.changes)
        )
      END
    FROM (
      SELECT
        upd.id,
        upd.mode,
        ARRAY_AGG( ROW(r.id, g.id, ch.block_num)::hivemind_app.blacklist_ids) AS changes
      FROM UNNEST(_blacklisted_updates) AS upd
      CROSS JOIN LATERAL UNNEST(upd.changes) AS ch(follower, following, block_num)
      JOIN accounts_id AS r ON ch.follower = r.name
      LEFT JOIN accounts_id AS g ON ch.following = g.name
      GROUP BY upd.id, upd.mode
      ORDER BY upd.id
    ) AS upd_with_ids
    ORDER BY upd_with_ids.id
  ),
  change_follow_muted AS MATERIALIZED (
    SELECT
      CASE upd_with_ids.mode
        WHEN 'insert' THEN (
          hivemind_app.insert_follow_muted(upd_with_ids.changes)
        )
        WHEN 'delete' THEN (
          hivemind_app.delete_follow_muted(upd_with_ids.changes)
        )
        WHEN 'reset' THEN (
          hivemind_app.reset_follow_muted(upd_with_ids.changes)
        )
      END
    FROM (
      SELECT
        upd.id,
        upd.mode,
        ARRAY_AGG( ROW(r.id, g.id, ch.block_num)::hivemind_app.follow_mute_ids) AS changes
      FROM UNNEST(_follow_muted_updates) AS upd
      CROSS JOIN LATERAL UNNEST(upd.changes) AS ch(follower, following, block_num)
      JOIN accounts_id AS r ON ch.follower = r.name
      LEFT JOIN accounts_id AS g ON ch.following = g.name
      GROUP BY upd.id, upd.mode
      ORDER BY upd.id
    ) AS upd_with_ids
    ORDER BY upd_with_ids.id
  ),
  change_follow_blacklisted AS MATERIALIZED (
    SELECT
      CASE upd_with_ids.mode
        WHEN 'insert' THEN (
          hivemind_app.insert_follow_blacklisted(upd_with_ids.changes)
        )
        WHEN 'delete' THEN (
          hivemind_app.delete_follow_blacklisted(upd_with_ids.changes)
        )
        WHEN 'reset' THEN (
          hivemind_app.reset_follow_blacklisted(upd_with_ids.changes)
        )
      END
    FROM (
      SELECT
        upd.id,
        upd.mode,
        ARRAY_AGG( ROW(r.id, g.id, ch.block_num)::hivemind_app.follow_blacklist_ids) AS changes
      FROM UNNEST(_follow_blacklisted_updates) AS upd
      CROSS JOIN LATERAL UNNEST(upd.changes) AS ch(follower, following, block_num)
      JOIN accounts_id AS r ON ch.follower = r.name
      LEFT JOIN accounts_id AS g ON ch.following = g.name
      GROUP BY upd.id, upd.mode
      ORDER BY upd.id
    ) AS upd_with_ids
    ORDER BY upd_with_ids.id
  )
  SELECT COUNT(*) INTO _count
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
