CREATE TYPE hivemind_app.follows_tuple AS (
  follower   INTEGER,
  following  INTEGER,
  block_num  INTEGER
);

DROP PROCEDURE IF EXISTS hivemind_app.insert_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_follows(_follows hivemind_app.follows_tuple[])
LANGUAGE sql
AS $$
  INSERT INTO hivemind_app.follows(follower, following, block_num)
  SELECT
    (x).follower,
    (x).following,
    (x).block_num
  FROM unnest(_follows) AS x
  ON CONFLICT (follower, following) DO UPDATE
    SET block_num = EXCLUDED.block_num;
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_follows(_delete bool, _reset bool)
LANGUAGE plpgsql
AS $$
BEGIN
  IF _delete THEN
    DELETE FROM hivemind_app.follows
    WHERE block_num = 0;
  END IF;
  IF _reset THEN
    DELETE FROM hivemind_app.follows AS f1
    WHERE block_num < (
       SELECT max(block_num)
       FROM hivemind_app.follows AS f2
       WHERE f2.follower = f1.follower
       AND f2.block_num = -1
   );
  END IF;
END
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_muted(_follows hivemind_app.follows_tuple[])
LANGUAGE sql
AS $$
  INSERT INTO hivemind_app.muted(follower, following, block_num)
  SELECT
    (x).follower,
    (x).following,
    (x).block_num
  FROM unnest(_follows) AS x
  ON CONFLICT (follower, following) DO UPDATE
    SET block_num = EXCLUDED.block_num;
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_muted(_delete bool, _reset bool)
LANGUAGE plpgsql
AS $$
BEGIN
  IF _delete THEN
    DELETE FROM hivemind_app.muted
    WHERE block_num = 0;
  END IF;
  IF _reset THEN
    DELETE FROM hivemind_app.muted AS f1
    WHERE block_num < (
       SELECT max(block_num)
       FROM hivemind_app.muted AS f2
       WHERE f2.follower = f1.follower
       AND f2.block_num = -1
    );
  END IF;
END
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_blacklisted(_follows hivemind_app.follows_tuple[])
LANGUAGE sql
AS $$
  INSERT INTO hivemind_app.blacklisted(follower, following, block_num)
  SELECT
    (x).follower,
    (x).following,
    (x).block_num
  FROM unnest(_follows) AS x
  ON CONFLICT (follower, following) DO UPDATE
    SET block_num = EXCLUDED.block_num;
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_blacklisted(_delete bool, _reset bool)
LANGUAGE plpgsql
AS $$
BEGIN
  IF _delete THEN
    DELETE FROM hivemind_app.blacklisted
    WHERE block_num = 0;
  END IF;
  IF _reset THEN
    DELETE FROM hivemind_app.blacklisted AS f1
    WHERE block_num < (
       SELECT max(block_num)
       FROM hivemind_app.blacklisted AS f2
       WHERE f2.follower = f1.follower
       AND f2.block_num = -1
    );
  END IF;
END
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_follow_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_follow_muted(_follows hivemind_app.follows_tuple[])
LANGUAGE sql
AS $$
  INSERT INTO hivemind_app.follow_muted(follower, following, block_num)
  SELECT
    (x).follower,
    (x).following,
    (x).block_num
  FROM unnest(_follows) AS x
  ON CONFLICT (follower, following) DO UPDATE
    SET block_num = EXCLUDED.block_num;
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_follow_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_follow_muted(_delete bool, _reset bool)
LANGUAGE plpgsql
AS $$
BEGIN
  IF _delete THEN
    DELETE FROM hivemind_app.follow_muted
    WHERE block_num = 0;
  END IF;
  IF _reset THEN
    DELETE FROM hivemind_app.follow_muted AS f1
    WHERE block_num < (
       SELECT max(block_num)
       FROM hivemind_app.follow_muted AS f2
       WHERE f2.follower = f1.follower
       AND f2.block_num = -1
    );
  END IF;
END
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_follow_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_follow_blacklisted(_follows hivemind_app.follows_tuple[])
LANGUAGE sql
AS $$
  INSERT INTO hivemind_app.follow_blacklisted(follower, following, block_num)
  SELECT
    (x).follower,
    (x).following,
    (x).block_num
  FROM unnest(_follows) AS x
  ON CONFLICT (follower, following) DO UPDATE
    SET block_num = EXCLUDED.block_num;
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_follow_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_follow_blacklisted(_delete bool, _reset bool)
LANGUAGE plpgsql
AS $$
BEGIN
  IF _delete THEN
    DELETE FROM hivemind_app.follow_blacklisted
    WHERE block_num = 0;
  END IF;
  IF _reset THEN
    DELETE FROM hivemind_app.follow_blacklisted AS f1
    WHERE block_num < (
       SELECT max(block_num)
       FROM hivemind_app.follow_blacklisted AS f2
       WHERE f2.follower = f1.follower
       AND f2.block_num = -1
    );
    DELETE FROM hivemind_app.follow_blacklisted
    WHERE block_num = -1;
  END IF;
END
$$;
