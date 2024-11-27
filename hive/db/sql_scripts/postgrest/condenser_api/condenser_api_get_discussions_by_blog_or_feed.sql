DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_discussions_by_blog_or_feed;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_discussions_by_blog_or_feed(IN _params JSONB, IN _by_blog BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_account_tag TEXT;
_account_tag_id INT;
_observer_id INT;
_post_id INT;
_limit INT;
_truncate_body INT;

BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"tag": "string", "start_author": "string", "start_permlink": "string", "limit": "number", "truncate_body": "number", "filter_tags": "array", "observer": "string"}', 1, '{"start_permlink": "permlink must be string"}');

  IF hivemind_postgrest_utilities.parse_argument_from_json(_params, 'filter_tags', False) IS NOT NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('filter_tags not supported');
  END IF;

  _account_tag =
    hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'tag', True),
      False);

  _account_tag_id = hivemind_postgrest_utilities.find_account_id(_account_tag, True);

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    20, 1, 100, 'limit');

  _truncate_body =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'truncate_body', False),
    0, 0, NULL, 'truncate_body');

  _observer_id =
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False), True),
    True);

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False),
      True),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False),
      True),
    True);

  IF _by_blog  THEN
    RETURN hivemind_postgrest_utilities.get_account_posts_by_blog(_account_tag, _account_tag_id, _post_id, _observer_id, _limit, _truncate_body, False);
  ELSE
    RETURN hivemind_postgrest_utilities.get_account_posts_by_feed(_account_tag_id, _post_id, _observer_id, _limit, _truncate_body, False);
  END IF;
END
$$
;