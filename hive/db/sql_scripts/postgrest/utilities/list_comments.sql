DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_comments_by_cashout_time;
CREATE FUNCTION hivemind_postgrest_utilities.list_comments_by_cashout_time(IN _start JSONB, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _cashout_time TIMESTAMP;
  _author TEXT;
  _permlink TEXT;
  _post_id INT;
BEGIN
  IF jsonb_array_length(_start) <> 3 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting three arguments in ''start'' array: cashout time, optional page start author and permlink');
  END IF;
  -- cashout_time
  PERFORM hivemind_postgrest_utilities.valid_date(_start->>0, False);
  _cashout_time = _start->>0;

  IF EXTRACT(YEAR FROM _cashout_time) = 1969 THEN
    _cashout_time = 'infinity';
  END IF;

  _author = hivemind_postgrest_utilities.valid_account(_start->>1, True);
  _permlink = hivemind_postgrest_utilities.valid_permlink(_start->>2, True);
  _post_id = hivemind_postgrest_utilities.find_comment_id( _author, _permlink, True);

  RETURN (
    SELECT jsonb_build_object(
      'comments', ( SELECT to_jsonb(result.array) FROM (
                      SELECT ARRAY (
                        SELECT hivemind_postgrest_utilities.create_database_post_object(row, 0) FROM (
                          WITH comments AS MATERIALIZED
                          (
                            SELECT
                              hp.id,
                              hp.cashout_time
                            FROM hivemind_app.live_posts_comments_view hp
                            WHERE
                              NOT hp.is_muted AND hp.cashout_time >= _cashout_time AND NOT(hp.cashout_time <= _cashout_time AND NOT (hp.id >= _post_id AND hp.id != 0))
                            ORDER BY
                              hp.cashout_time ASC,
                              hp.id ASC
                            LIMIT _limit
                          )
                          SELECT
                            hp.id,
                            hp.community_id,
                            hp.author,
                            hp.permlink,
                            hp.title,
                            hp.body,
                            hp.category,
                            hp.depth,
                            hp.promoted,
                            hp.payout,
                            hp.last_payout_at,
                            hp.cashout_time,
                            hp.is_paidout,
                            hp.children,
                            hp.votes,
                            hp.created_at,
                            hp.updated_at,
                            hp.rshares,
                            hp.json,
                            hp.is_hidden,
                            hp.is_grayed,
                            hp.total_votes,
                            hp.net_votes,
                            hp.total_vote_weight,
                            hp.parent_author,
                            hp.parent_permlink_or_category,
                            hp.curator_payout_value,
                            hp.root_author,
                            hp.root_permlink,
                            hp.max_accepted_payout,
                            hp.percent_hbd,
                            hp.allow_replies,
                            hp.allow_votes,
                            hp.allow_curation_rewards,
                            hp.beneficiaries,
                            hp.url,
                            hp.root_title,
                            hp.abs_rshares,
                            hp.active,
                            hp.author_rewards,
                            hp.muted_reasons
                          FROM comments,
                          LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
                          ORDER BY comments.cashout_time ASC, comments.id ASC
                          LIMIT _limit
                        ) row
                      )
                    ) result
                  )
        )
      );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_comments_by_root_or_parent;
CREATE FUNCTION hivemind_postgrest_utilities.list_comments_by_root_or_parent(IN _start JSONB, IN _limit INT, IN _by_root BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _root_or_parent_author TEXT;
  _root_or_parent_permlink TEXT;
  _post_author TEXT;
  _post_permlink TEXT;
  _root_or_parent_id INT;
  _post_id INT;
BEGIN
  IF jsonb_array_length(_start) <> 4 THEN
    IF _by_root THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting 4 arguments in ''start'' array: discussion root author and permlink, optional page start author and permlink');
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting 4 arguments in ''start'' array: parent post author and permlink, optional page start author and permlink');
    END IF;
  END IF;

  _root_or_parent_author = hivemind_postgrest_utilities.valid_account(_start->>0, False);
  _root_or_parent_permlink = hivemind_postgrest_utilities.valid_permlink(_start->>1, False);
  _root_or_parent_id = hivemind_postgrest_utilities.find_comment_id( _root_or_parent_author, _root_or_parent_permlink, True);

  _post_author = hivemind_postgrest_utilities.valid_account(_start->>2, True);
  _post_permlink = hivemind_postgrest_utilities.valid_permlink(_start->>3, True);
  _post_id = hivemind_postgrest_utilities.find_comment_id( _post_author, _post_permlink, True);


  RETURN (
    SELECT jsonb_build_object(
      'comments', ( SELECT to_jsonb(result.array) FROM (
                      SELECT ARRAY (
                        SELECT hivemind_postgrest_utilities.create_database_post_object(row, 0) FROM (
                          WITH comments AS MATERIALIZED
                          (
                            SELECT
                              hp.id
                            FROM
                              hivemind_app.live_posts_comments_view hp
                            WHERE
                              (CASE WHEN _by_root THEN hp.root_id = _root_or_parent_id ELSE hp.parent_id = _root_or_parent_id END)
                              AND NOT hp.is_muted
                              AND NOT (_post_id <> 0 AND hp.id < _post_id)
                            ORDER BY
                              hp.id ASC
                            LIMIT
                              _limit
                          )
                          SELECT
                            hp.id,
                            hp.community_id,
                            hp.author,
                            hp.permlink,
                            hp.title,
                            hp.body,
                            hp.category,
                            hp.depth,
                            hp.promoted,
                            hp.payout,
                            hp.last_payout_at,
                            hp.cashout_time,
                            hp.is_paidout,
                            hp.children,
                            hp.votes,
                            hp.created_at,
                            hp.updated_at,
                            hp.rshares,
                            hp.json,
                            hp.is_hidden,
                            hp.is_grayed,
                            hp.total_votes,
                            hp.net_votes,
                            hp.total_vote_weight,
                            hp.parent_author,
                            hp.parent_permlink_or_category,
                            hp.curator_payout_value,
                            hp.root_author,
                            hp.root_permlink,
                            hp.max_accepted_payout,
                            hp.percent_hbd,
                            hp.allow_replies,
                            hp.allow_votes,
                            hp.allow_curation_rewards,
                            hp.beneficiaries,
                            hp.url,
                            hp.root_title,
                            hp.abs_rshares,
                            hp.active,
                            hp.author_rewards,
                            hp.muted_reasons
                          FROM comments,
                          LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
                          ORDER BY comments.id
                          LIMIT _limit
                        ) row
                      )
                    ) result
                  )
        )
      );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_comments_by_last_update;
CREATE FUNCTION hivemind_postgrest_utilities.list_comments_by_last_update(IN _start JSONB, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _parent_author TEXT;
  _parent_author_id INT;
  _updated_at TIMESTAMP;

  _post_author TEXT;
  _post_permlink TEXT;
  _post_id INT;
BEGIN
  IF jsonb_array_length(_start) <> 4 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting 4 arguments in ''start'' array: parent author, update time, optional page start author and permlink');
  END IF;

  _parent_author = hivemind_postgrest_utilities.valid_account(_start->>0, False);
  _parent_author_id = hivemind_postgrest_utilities.find_account_id(_parent_author, True);
  PERFORM hivemind_postgrest_utilities.valid_date(_start->>1, False);
  _updated_at = _start->>1;

  _post_author = hivemind_postgrest_utilities.valid_account(_start->>2, True);
  _post_permlink = hivemind_postgrest_utilities.valid_permlink(_start->>3, True);
  _post_id = hivemind_postgrest_utilities.find_comment_id( _post_author, _post_permlink, True);

  RETURN (
    SELECT jsonb_build_object(
      'comments', ( SELECT to_jsonb(result.array) FROM (
                      SELECT ARRAY (
                        SELECT hivemind_postgrest_utilities.create_database_post_object(row, 0) FROM (
                          WITH comments AS MATERIALIZED
                          (
                            SELECT
                              lpcv.id,
                              lpcv.updated_at
                            FROM
                              hivemind_app.live_posts_comments_view lpcv
                            JOIN hivemind_app.hive_posts hp ON lpcv.parent_id = hp.id
                            WHERE 
                              hp.author_id = _parent_author_id AND NOT lpcv.is_muted
                              AND (lpcv.updated_at < _updated_at OR lpcv.updated_at = _updated_at AND lpcv.id >= _post_id AND lpcv.id != 0)
                            ORDER BY
                              lpcv.updated_at DESC, lpcv.id ASC
                            LIMIT
                              _limit
                          )
                          SELECT
                            hp.id,
                            hp.community_id,
                            hp.author,
                            hp.permlink,
                            hp.title,
                            hp.body,
                            hp.category,
                            hp.depth,
                            hp.promoted,
                            hp.payout,
                            hp.last_payout_at,
                            hp.cashout_time,
                            hp.is_paidout,
                            hp.children,
                            hp.votes,
                            hp.created_at,
                            hp.updated_at,
                            hp.rshares,
                            hp.json,
                            hp.is_hidden,
                            hp.is_grayed,
                            hp.total_votes,
                            hp.net_votes,
                            hp.total_vote_weight,
                            hp.parent_author,
                            hp.parent_permlink_or_category,
                            hp.curator_payout_value,
                            hp.root_author,
                            hp.root_permlink,
                            hp.max_accepted_payout,
                            hp.percent_hbd,
                            hp.allow_replies,
                            hp.allow_votes,
                            hp.allow_curation_rewards,
                            hp.beneficiaries,
                            hp.url,
                            hp.root_title,
                            hp.abs_rshares,
                            hp.active,
                            hp.author_rewards,
                            hp.muted_reasons
                          FROM comments,
                          LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
                          ORDER BY comments.updated_at DESC, comments.id ASC
                          LIMIT _limit
                        ) row
                      )
                    ) result
                  )
        )
      );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_comments_by_author_last_update;
CREATE FUNCTION hivemind_postgrest_utilities.list_comments_by_author_last_update(IN _start JSONB, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _author TEXT;
  _author_id INT;
  _updated_at TIMESTAMP;

  _post_author TEXT;
  _post_permlink TEXT;
  _post_id INT;
BEGIN
  IF jsonb_array_length(_start) <> 4 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting 4 arguments in ''start'' array: author, update time, optional page start author and permlink');
  END IF;

  _author = hivemind_postgrest_utilities.valid_account(_start->>0, False);
  _author_id = hivemind_postgrest_utilities.find_account_id(_author, True);
  PERFORM hivemind_postgrest_utilities.valid_date(_start->>1, False);
  _updated_at = _start->>1;

  _post_author = hivemind_postgrest_utilities.valid_account(_start->>2, True);
  _post_permlink = hivemind_postgrest_utilities.valid_permlink(_start->>3, True);
  _post_id = hivemind_postgrest_utilities.find_comment_id( _post_author, _post_permlink, True);

  RETURN (
    SELECT jsonb_build_object(
      'comments', ( SELECT to_jsonb(result.array) FROM (
                      SELECT ARRAY (
                        SELECT hivemind_postgrest_utilities.create_database_post_object(row, 0) FROM (
                          WITH comments AS MATERIALIZED
                          (
                            SELECT
                              lpcv.id,
                              lpcv.updated_at
                            FROM
                              hivemind_app.live_posts_comments_view lpcv
                            WHERE 
                              lpcv.author_id = _author_id AND NOT lpcv.is_muted
                              AND (lpcv.updated_at < _updated_at OR lpcv.updated_at = _updated_at AND lpcv.id >= _post_id AND lpcv.id != 0)
                            ORDER BY
                              lpcv.updated_at DESC, lpcv.id ASC
                            LIMIT
                              _limit
                          )
                          SELECT
                            hp.id,
                            hp.community_id,
                            hp.author,
                            hp.permlink,
                            hp.title,
                            hp.body,
                            hp.category,
                            hp.depth,
                            hp.promoted,
                            hp.payout,
                            hp.last_payout_at,
                            hp.cashout_time,
                            hp.is_paidout,
                            hp.children,
                            hp.votes,
                            hp.created_at,
                            hp.updated_at,
                            hp.rshares,
                            hp.json,
                            hp.is_hidden,
                            hp.is_grayed,
                            hp.total_votes,
                            hp.net_votes,
                            hp.total_vote_weight,
                            hp.parent_author,
                            hp.parent_permlink_or_category,
                            hp.curator_payout_value,
                            hp.root_author,
                            hp.root_permlink,
                            hp.max_accepted_payout,
                            hp.percent_hbd,
                            hp.allow_replies,
                            hp.allow_votes,
                            hp.allow_curation_rewards,
                            hp.beneficiaries,
                            hp.url,
                            hp.root_title,
                            hp.abs_rshares,
                            hp.active,
                            hp.author_rewards,
                            hp.muted_reasons
                          FROM comments,
                          LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
                          ORDER BY comments.updated_at DESC, comments.id ASC
                          LIMIT _limit
                        ) row
                      )
                    ) result
                  )
        )
      );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_comments_by_permlink;
CREATE FUNCTION hivemind_postgrest_utilities.list_comments_by_permlink(IN _start JSONB, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _author_and_permlink TEXT;
  
BEGIN
  IF jsonb_array_length(_start) <> 2 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expecting two arguments in ''start'' array: author and permlink');
  END IF;
  IF jsonb_typeof(_start->0) <> 'string' THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('invalid account name type');
  END IF;
  IF jsonb_typeof(_start->1) <> 'string' THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('permlink must be string');
  END IF;
  -- no validation were called here in python, so just take arguments.
  _author_and_permlink = (_start->>0) || '/' || (_start->>1);
  RETURN (
    SELECT jsonb_build_object(
      'comments', ( SELECT to_jsonb(result.array) FROM (
                      SELECT ARRAY (
                        SELECT hivemind_postgrest_utilities.create_database_post_object(row, 0) FROM (
                          WITH comments AS MATERIALIZED
                          (
                            SELECT
                              hph.id,
                              hph.author_s_permlink
                            FROM
                              hivemind_app.hive_posts_api_helper hph
                            JOIN hivemind_app.live_posts_comments_view hp ON hp.id = hph.id
                            WHERE 
                              hph.author_s_permlink >= _author_and_permlink
                              AND NOT hp.is_muted
                              AND hph.id != 0
                            ORDER BY
                              hph.author_s_permlink
                            LIMIT
                              _limit
                          )
                          SELECT
                            hp.id,
                            hp.community_id,
                            hp.author,
                            hp.permlink,
                            hp.title,
                            hp.body,
                            hp.category,
                            hp.depth,
                            hp.promoted,
                            hp.payout,
                            hp.last_payout_at,
                            hp.cashout_time,
                            hp.is_paidout,
                            hp.children,
                            hp.votes,
                            hp.created_at,
                            hp.updated_at,
                            hp.rshares,
                            hp.json,
                            hp.is_hidden,
                            hp.is_grayed,
                            hp.total_votes,
                            hp.net_votes,
                            hp.total_vote_weight,
                            hp.parent_author,
                            hp.parent_permlink_or_category,
                            hp.curator_payout_value,
                            hp.root_author,
                            hp.root_permlink,
                            hp.max_accepted_payout,
                            hp.percent_hbd,
                            hp.allow_replies,
                            hp.allow_votes,
                            hp.allow_curation_rewards,
                            hp.beneficiaries,
                            hp.url,
                            hp.root_title,
                            hp.abs_rshares,
                            hp.active,
                            hp.author_rewards,
                            hp.muted_reasons
                          FROM comments,
                          LATERAL hivemind_app.get_post_view_by_id(comments.id) hp
                          ORDER BY hp.author, hp.permlink
                          LIMIT _limit
                        ) row
                      )
                    ) result
                  )
        )
      );
END
$$
;