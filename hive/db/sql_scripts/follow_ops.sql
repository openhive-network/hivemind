DROP PROCEDURE IF EXISTS hivemind_app.insert_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_follows(_follower_id INTEGER, _following_id INTEGER, _block_num INTEGER)
LANGUAGE 'sql'
AS $$
  INSERT INTO hivemind_app.follows(follower, following, block_num)
  VALUES (_follower_id, _following_id, _block_num)
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_follows(_follower_id INTEGER, _following_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.follows
  WHERE follower = _follower_id AND following = _following_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_muted(_follower_id INTEGER, _following_id INTEGER, _block_num INTEGER)
LANGUAGE 'sql'
AS $$
  INSERT INTO hivemind_app.muted(follower, following, block_num)
  VALUES (_follower_id, _following_id, _block_num)
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_muted(_follower_id INTEGER, _following_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.muted
  WHERE follower = _follower_id AND following = _following_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_blacklisted(_follower_id INTEGER, _following_id INTEGER, _block_num INTEGER)
LANGUAGE 'sql'
AS $$
  INSERT INTO hivemind_app.blacklisted(follower, following, block_num)
  VALUES (_follower_id, _following_id, _block_num)
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_blacklisted(_follower_id INTEGER, _following_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.blacklisted
  WHERE follower = _follower_id AND following = _following_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_follow_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_follow_muted(_follower_id INTEGER, _following_id INTEGER, _block_num INTEGER)
LANGUAGE 'sql'
AS $$
  INSERT INTO hivemind_app.follow_muted(follower, following, block_num)
  VALUES (_follower_id, _following_id, _block_num)
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_follow_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_follow_muted(_follower_id INTEGER, _following_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.follow_muted
  WHERE follower = _follower_id AND following = _following_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.insert_follow_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.insert_follow_blacklisted(_follower_id INTEGER, _following_id INTEGER, _block_num INTEGER)
LANGUAGE 'sql'
AS $$
  INSERT INTO hivemind_app.follow_blacklisted(follower, following, block_num)
  VALUES (_follower_id, _following_id, _block_num)
  ON CONFLICT (follower, following) DO UPDATE
  SET block_num = EXCLUDED.block_num
$$;

DROP PROCEDURE IF EXISTS hivemind_app.delete_follow_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.delete_follow_blacklisted(_follower_id INTEGER, _following_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.follow_blacklisted
  WHERE follower = _follower_id AND following = _following_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.reset_follows CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.reset_follows(_follower_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.follows
  WHERE follower=_follower_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.reset_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.reset_muted(_follower_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.muted
  WHERE follower=_follower_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.reset_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.reset_blacklisted(_follower_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.blacklisted
  WHERE follower=_follower_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.reset_follow_muted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.reset_follow_muted(_follower_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.follow_muted
  WHERE follower=_follower_id
$$;

DROP PROCEDURE IF EXISTS hivemind_app.reset_follow_blacklisted CASCADE;
CREATE OR REPLACE PROCEDURE hivemind_app.reset_follow_blacklisted(_follower_id INTEGER)
LANGUAGE 'sql'
AS $$
  DELETE FROM hivemind_app.follow_blacklisted
  WHERE follower=_follower_id
$$;

