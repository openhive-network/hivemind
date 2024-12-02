DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_discussion;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_discussion(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _post_id  INT;
  _observer_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink","observer"}', '{"string","string","string"}', 2);

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True),
        False),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True),
        False),
      True);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 2, False), True),
    True);

  RETURN COALESCE(
  (
    SELECT     -- bridge_api_get_discussion
      jsonb_object_agg((row.author || '/' || row.permlink), hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True, row.replies))
      FROM (
        SELECT
          hpv.id,
          hpv.author,
          hpv.parent_author,
          hpv.author_rep,
          hpv.root_title,
          hpv.beneficiaries,
          hpv.max_accepted_payout,
          hpv.percent_hbd,
          hpv.url,
          hpv.permlink,
          hpv.parent_permlink_or_category,
          hpv.title,
          hpv.body,
          hpv.category,
          hpv.depth,
          hpv.promoted,
          hpv.payout,
          hpv.pending_payout,
          hpv.payout_at,
          hpv.is_paidout,
          hpv.children,
          hpv.votes,
          hpv.created_at,
          hpv.updated_at,
          hpv.rshares,
          hpv.abs_rshares,
          hpv.json,
          hpv.is_hidden,
          hpv.is_grayed,
          hpv.total_votes,
          hpv.sc_trend,
          hpv.role_title,
          hpv.community_title,
          hpv.role_id,
          hpv.is_pinned,
          hpv.curator_payout_value,
          hpv.is_muted,
          hpv.parent_id,
          hpv.source AS blacklists,
          hpv.muted_reasons,
          ds.replies
        FROM
        (
          WITH RECURSIVE child_posts (id, parent_id) AS
          (
            SELECT
              hp.id,
              hp.parent_id,
              NULL::TEXT COLLATE "C" AS reply
            FROM hivemind_app.live_posts_comments_view hp 
            WHERE 
              hp.id = _post_id
              AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))

            UNION ALL

            SELECT
              children.id,
              children.parent_id,
              ha.name || '/' || hp.permlink  AS reply
            FROM hivemind_app.live_posts_comments_view children
            JOIN child_posts ON children.parent_id = child_posts.id
            JOIN hivemind_app.hive_accounts ha ON children.author_id = ha.id AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = children.author_id))
            JOIN hivemind_app.hive_permlink_data hp ON hp.id = children.permlink_id
          ),
          post_replies AS
          (
            SELECT
              parent_id,
              jsonb_agg(reply ORDER BY id) AS replies
            FROM child_posts
            GROUP BY parent_id
          )
          SELECT
            cp.id,
            r.replies
          FROM child_posts cp
          LEFT JOIN post_replies r ON r.parent_id = cp.id
          ORDER BY cp.id
        ) ds,
          LATERAL hivemind_app.get_full_post_view_by_id(ds.id, _observer_id) hpv
        ORDER BY ds.id
        LIMIT 2000
    ) row),
  '{}') ;
END
$$
;

