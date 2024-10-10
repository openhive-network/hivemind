DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_account_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_account_posts(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_sort_type INT;
_account_id INT;
_observer_id INT;
_post_id INT;
_limit INT;

_account TEXT;
_permlink TEXT;

BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"sort","account","start_author","start_permlink","limit","observer"}', '{"string","string","string","string","number","string"}', 2);

  CASE hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'sort', 0, True)
    WHEN 'blog' THEN _sort_type = 1;
    WHEN 'feed' THEN _sort_type = 2;
    WHEN 'posts' THEN _sort_type = 3;
    WHEN 'comments' THEN _sort_type = 4;
    WHEN 'replies' THEN _sort_type = 5;
    WHEN 'payout' THEN _sort_type = 6;
    ELSE _sort_type = 0;
  END CASE;

  IF _sort_type = 0 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: blog, feed, posts, comments, replies, payout');
  END IF;

  _account = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 1, True),
    False);

  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _permlink = hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_permlink', 3, False), True);

  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_author', 2, False), True),
    _permlink,
    True);

  _limit = hivemind_postgrest_utilities.valid_number(
    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 4, False),
    20, 1, 100, 'limit');
  
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 5, False), True),
    True);

  IF _sort_type = 1 THEN
  -- SORT BY BLOG ----------------------------------------------------------------------------------
    RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, (CASE WHEN row.author <> _account THEN ARRAY[_account] ELSE NULL END), False, True) FROM (
            SELECT * FROM hivemind_postgrest_utilities.get_account_posts_by_blog(_account_id, _post_id, _observer_id, _limit, True)
          ) row
        )
      ) result
    );

  ELSIF _sort_type = 2 THEN
  -- sort by feed -------------------------------------------------------------------------------------
    RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, ( CASE WHEN row.reblogged_by IS NOT NULL THEN array_remove(row.reblogged_by, row.author)
                                                                                  ELSE NULL END), False, True) FROM (
            SELECT * FROM hivemind_postgrest_utilities.get_account_posts_by_feed(_account_id, _post_id, _observer_id, _limit)
          ) row
        )
      ) result
    );

  ELSIF _sort_type = 3 THEN
  -- sort by posts
    RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, False, True) FROM (
            SELECT * FROM hivemind_postgrest_utilities.get_account_posts_by_posts(_account_id, _post_id, _observer_id, _limit)
          ) row
        )
      ) result
    );

  ELSIF _sort_type = 4 THEN
  -- sort by comments --------------------------------------------------------------------------------
    RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, False, True) FROM (
            SELECT * FROM hivemind_postgrest_utilities.get_account_posts_by_comments(_account_id, _post_id, _observer_id, _limit)
          ) row
        )
      ) result
    );

  ELSIF _sort_type = 5 THEN
  -- sort by replies
    RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          -- in python code i saw in that case is_pinned should be set, but I couldn't find an example in db to do a test case.
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, True, True) FROM (
            SELECT * FROM hivemind_postgrest_utilities.get_account_posts_by_replies(_account_id, _post_id, _observer_id, _limit, (_permlink IS NOT NULL AND _permlink <> '' ), True)
          ) row
        )
      ) result
    );

  ELSIF _sort_type = 6 THEN
  -- sort by payout
    RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, False, True) FROM (
            SELECT * FROM hivemind_postgrest_utilities.get_account_posts_by_payout(_account_id, _post_id, _observer_id, _limit)
          ) row
        )
      ) result
    );
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Invalid _sort_type value. Unsupported sort, valid sorts: blog, feed, posts, comments, replies, payout');
  END IF;
END
$$
;