DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_discussions_by_author_before_date;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_discussions_by_author_before_date(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_author TEXT;
_permlink TEXT;
_author_id INT;
_post_id INT;
_limit INT;
_truncate_body INT;
_result JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string", "start_permlink": "string","before_date": "string", "limit": "number", "truncate_body":"number"}', 1, '{"start_permlink": "permlink must be string"}');

  -- BEFORE DATE IS IGNORED BECAUSE IN PYTHON CODE IT IS ALSO IGNORED

  _author =
    hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True),
      False);

  _author_id = hivemind_postgrest_utilities.find_account_id(_author, True);

  _permlink =
    hivemind_postgrest_utilities.valid_permlink(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False),
    True);

  _limit =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
    10, 1, 100, 'limit');

  _truncate_body =
    hivemind_postgrest_utilities.valid_number(
      hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'truncate_body', False),
    0, 0, NULL, 'truncate_body');

  _post_id = hivemind_postgrest_utilities.find_comment_id(_author, _permlink, (CASE WHEN _permlink IS NULL OR _permlink = '' THEN False ELSE True END));

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
    ) FROM (
      WITH blog_posts AS -- condenser_api_get_discussions_by_author_before_date
      (
        SELECT
          hp.id
        FROM hivemind_app.live_posts_view hp
        WHERE
          hp.author_id = _author_id
          AND (_post_id = 0 OR hp.id < _post_id)
          ORDER BY hp.id DESC
          LIMIT _limit
      )
      SELECT
        hp.id,
        hp.author,
        hp.parent_author,
        hp.author_rep,
        hp.root_title,
        hp.beneficiaries,
        hp.max_accepted_payout,
        hp.percent_hbd,
        hp.url,
        hp.permlink,
        hp.parent_permlink_or_category,
        hp.title,
        hp.body,
        hp.category,
        hp.depth,
        hp.promoted,
        hp.payout,
        hp.pending_payout,
        hp.payout_at,
        hp.is_paidout,
        hp.children,
        hp.votes,
        hp.created_at,
        hp.updated_at,
        hp.rshares,
        hp.abs_rshares,
        hp.json,
        hp.is_hidden,
        hp.is_grayed,
        hp.total_votes,
        hp.sc_trend,
        hp.role_title,
        hp.community_title,
        hp.role_id,
        hp.is_pinned,
        hp.curator_payout_value,
        hp.is_muted,
        NULL as blacklists,
        hp.muted_reasons
      FROM blog_posts,
      LATERAL hivemind_app.get_post_view_by_id(blog_posts.id) hp
      ORDER BY hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;