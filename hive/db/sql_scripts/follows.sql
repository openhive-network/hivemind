DROP FUNCTION IF EXISTS hivemind_app.follow_reset_blacklist(character varying, integer)
;
CREATE OR REPLACE FUNCTION hivemind_app.follow_reset_blacklist(in _follower hivemind_app.hive_accounts.name%TYPE, in _block_num hivemind_app.hive_follows.block_num%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _follower, False );
  UPDATE hivemind_app.hive_follows hf -- follow_reset_blacklist
  SET blacklisted = false, block_num = _block_num
  WHERE hf.follower = __account_id AND hf.blacklisted;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.follow_reset_following_list(character varying, integer)
;
CREATE OR REPLACE FUNCTION hivemind_app.follow_reset_following_list(in _follower hivemind_app.hive_accounts.name%TYPE, in _block_num hivemind_app.hive_follows.block_num%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _follower, False );
  UPDATE hivemind_app.hive_follows hf -- follow_reset_following_list
  SET state = 0, block_num = _block_num
  WHERE hf.follower = __account_id AND hf.state = 1;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.follow_reset_muted_list(character varying, integer)
;
CREATE OR REPLACE FUNCTION hivemind_app.follow_reset_muted_list(in _follower hivemind_app.hive_accounts.name%TYPE, in _block_num hivemind_app.hive_follows.block_num%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _follower, False );
  UPDATE hivemind_app.hive_follows hf -- follow_reset_muted_list
  SET state = 0, block_num = _block_num
  WHERE hf.follower = __account_id AND hf.state = 2;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.follow_reset_follow_blacklist(character varying, integer)
;
CREATE OR REPLACE FUNCTION hivemind_app.follow_reset_follow_blacklist(in _follower hivemind_app.hive_accounts.name%TYPE, in _block_num hivemind_app.hive_follows.block_num%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _follower, False );
  UPDATE hivemind_app.hive_follows hf -- follow_reset_follow_blacklist
  SET follow_blacklists = false, block_num = _block_num
  WHERE hf.follower = __account_id AND hf.follow_blacklists;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.follow_reset_follow_muted_list(character varying, integer)
;
CREATE OR REPLACE FUNCTION hivemind_app.follow_reset_follow_muted_list(in _follower hivemind_app.hive_accounts.name%TYPE, in _block_num hivemind_app.hive_follows.block_num%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _follower, False );
  UPDATE hivemind_app.hive_follows hf -- follow_reset_follow_muted_list
  SET follow_muted = false, block_num = _block_num
  WHERE hf.follower = __account_id AND hf.follow_muted;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.follow_reset_all_lists(character varying, integer)
;
CREATE OR REPLACE FUNCTION hivemind_app.follow_reset_all_lists(in _follower hivemind_app.hive_accounts.name%TYPE, in _block_num hivemind_app.hive_follows.block_num%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _follower, False );
  UPDATE hivemind_app.hive_follows hf -- follow_reset_all_lists
  SET blacklisted = false, follow_blacklists = false, follow_muted = false, state = 0, block_num = _block_num
  WHERE hf.follower = __account_id;
END
$function$
;
