DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_tag(IN _account_id INT, IN _tag TEXT, IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_is_community BOOLEAN;
_community_id INT;
_tag_id INT;
_posts_should_be_grayed BOOLEAN;
_result JSONB;
BEGIN
  -- Check if author should be grayed
  --DLN this should probably be changed to a straight mute instead of graying
  IF _observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = _account_id) THEN
    _posts_should_be_grayed = True;
  ELSE
    _posts_should_be_grayed = False;
  END IF;

  -- Check if tag is a community
  _is_community = hivemind_postgrest_utilities.check_community(_tag);

  IF _is_community THEN
    -- Resolve community_id
    SELECT id INTO _community_id
    FROM hivemind_app.hive_communities
    WHERE name = _tag
    LIMIT 1;

    IF _community_id IS NULL THEN
      RETURN '[]'::jsonb;
    END IF;

    -- Query for community posts
    _result = (
      SELECT jsonb_agg (
        hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, 0, NULL, row.is_pinned, True)
      ) FROM (
        WITH posts AS MATERIALIZED -- get_account_posts_by_tag (community)
        (
          SELECT hp.id, hp.author_id
          FROM hivemind_app.live_posts_view hp
          WHERE hp.author_id = _account_id
            AND hp.community_id = _community_id
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
          hp.is_grayed OR _posts_should_be_grayed AS is_grayed,
          hp.total_votes,
          hp.sc_trend,
          hp.role_title,
          hp.community_title,
          hp.role_id,
          hp.is_pinned,
          hp.curator_payout_value,
          hp.is_muted,
          hp.source AS blacklists,
          hp.muted_reasons
        FROM posts,
        LATERAL hivemind_app.get_full_post_view_by_id(posts.id, _observer_id) hp
        ORDER BY posts.id DESC
        LIMIT _limit
      ) row
    );
  ELSE
    -- Resolve tag_id
    _tag_id = hivemind_postgrest_utilities.find_tag_id(_tag, False);

    IF _tag_id = 0 THEN
      RETURN '[]'::jsonb;
    END IF;

    -- Query for tag posts
    _result = (
      SELECT jsonb_agg (
        hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, 0, NULL, row.is_pinned, True)
      ) FROM (
        WITH posts AS MATERIALIZED -- get_account_posts_by_tag (tag)
        (
          SELECT hp.id, hp.author_id
          FROM hivemind_app.live_posts_view hp
          WHERE hp.author_id = _account_id
            AND (_post_id = 0 OR hp.id < _post_id)
            AND EXISTS (
              SELECT 1 FROM hivemind_app.hive_post_tags hpt
              WHERE hpt.post_id = hp.id AND hpt.tag_id = _tag_id
            )
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
          hp.is_grayed OR _posts_should_be_grayed AS is_grayed,
          hp.total_votes,
          hp.sc_trend,
          hp.role_title,
          hp.community_title,
          hp.role_id,
          hp.is_pinned,
          hp.curator_payout_value,
          hp.is_muted,
          hp.source AS blacklists,
          hp.muted_reasons
        FROM posts,
        LATERAL hivemind_app.get_full_post_view_by_id(posts.id, _observer_id) hp
        ORDER BY posts.id DESC
        LIMIT _limit
      ) row
    );
  END IF;

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
