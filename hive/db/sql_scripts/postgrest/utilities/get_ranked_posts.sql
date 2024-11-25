DROP TYPE IF EXISTS hivemind_postgrest_utilities.ranked_post_sort_type CASCADE;
CREATE TYPE hivemind_postgrest_utilities.ranked_post_sort_type AS ENUM( 'hot', 'trending', 'promoted', 'created', 'muted', 'payout', 'payout_comments');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN, IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_extract_pinned_posts BOOLEAN DEFAULT False; 
_result JSONB;
BEGIN
  IF _called_from_bridge_api AND _sort_type = ANY(ARRAY['trending'::hivemind_postgrest_utilities.ranked_post_sort_type, 'created'::hivemind_postgrest_utilities.ranked_post_sort_type])
    AND NOT (_post_id <> 0 AND NOT (SELECT is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id LIMIT 1)) THEN
    _extract_pinned_posts = True;
  END IF;

  IF _extract_pinned_posts THEN
    _result = (
      SELECT jsonb_agg (
        hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
      ) FROM (
        WITH
        community_data AS
        (
          SELECT
            id
          FROM hivemind_app.hive_communities
          WHERE
            name = _tag
          LIMIT 1
        ),
        pinned_post AS
        (
          SELECT 
            hp.id,
            blacklist.source
          FROM hivemind_app.live_posts_comments_view hp
          JOIN community_data cd ON hp.community_id = cd.id
          LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
          WHERE
            hp.is_pinned
            AND NOT (_post_id <> 0 AND hp.id >= _post_id)
            AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
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
          pinned_post.source AS blacklists,
          hp.muted_reasons
        FROM pinned_post,
        LATERAL hivemind_app.get_post_view_by_id(pinned_post.id) hp
        ORDER BY hp.id DESC
        LIMIT _limit
      ) row
    );
  END IF;

  IF _result IS NULL THEN
    _result = '[]'::jsonb;
  ELSE
    _limit = _limit - jsonb_array_length(_result);
  END IF;

  IF _limit > 0 THEN
    CASE _sort_type
      WHEN 'trending' THEN _result = _result || hivemind_postgrest_utilities.get_trending_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api);
      WHEN 'hot' THEN _result = _result || hivemind_postgrest_utilities.get_hot_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api);
      WHEN 'created' THEN _result = _result || hivemind_postgrest_utilities.get_created_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api);
      WHEN 'promoted' THEN _result = _result || hivemind_postgrest_utilities.get_promoted_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api);
      WHEN 'payout' THEN _result = _result || hivemind_postgrest_utilities.get_payout_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api);
      WHEN 'payout_comments' THEN _result = _result || hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api);
      WHEN 'muted' THEN _result = _result || hivemind_postgrest_utilities.get_muted_ranked_posts_for_communities(_post_id, _observer_id, _limit, _tag);
    END CASE;
  END IF;

  RETURN _result;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_trending_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_trending_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_result JSONB;
BEGIN
  IF _post_id <> 0 AND (SELECT is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id LIMIT 1) THEN
    _post_id = 0;
  ELSE
    SELECT sc_trend INTO _trending_limit FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;
  
  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      community_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hc.name = _tag AND NOT hp.is_paidout AND NOT(_called_from_bridge_api AND hp.is_pinned)
          AND NOT (_post_id <> 0 AND hp.sc_trend >= _trending_limit AND NOT ( hp.sc_trend = _trending_limit AND hp.id < _post_id ))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_trend DESC, hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        hp.sc_trend DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_promoted_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_promoted_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_promoted_limit hivemind_app.hive_posts.promoted%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT promoted INTO _promoted_limit FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;
  
  _result = (
    SELECT jsonb_agg (
    ( CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      community_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hc.name = _tag AND hp.promoted > 0 AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.promoted >= _promoted_limit AND NOT ( hp.promoted = _promoted_limit AND hp.id < _post_id ))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.promoted DESC, hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        hp.promoted DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_payout_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_payout_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_head_block_time TIMESTAMP;
_result JSONB;
BEGIN
  _head_block_time = hivemind_app.head_block_time();

  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      community_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hc.name = _tag AND NOT hp.is_paidout AND hp.payout_at BETWEEN _head_block_time + interval '12 hours' AND _head_block_time + interval '36 hours'
          AND NOT (_post_id <> 0 AND hp.payout + hp.pending_payout >= _payout_limit AND NOT (hp.payout + hp.pending_payout = _payout_limit AND hp.id < _post_id ))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        community_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      community_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hc.name = _tag AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ( (hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id ))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        community_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_hot_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_hot_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_hot_limit FLOAT;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT sc_hot INTO _hot_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      community_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hc.name = _tag AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.sc_hot >= _hot_limit AND NOT (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_hot DESC, hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        hp.sc_hot DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_created_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_created_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _result JSONB;
BEGIN
  IF _post_id <> 0 AND (SELECT is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id LIMIT 1) THEN
    _post_id = 0;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH
      live_community_posts AS
      (
        SELECT id, author_id, is_pinned FROM hivemind_app.live_posts_view
        where community_id = (SELECT id FROM hivemind_app.hive_communities WHERE name = _tag LIMIT 1)
      ),
      community_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM live_community_posts hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT (_post_id <> 0 AND hp.id >= _post_id)
          AND NOT(_called_from_bridge_api AND hp.is_pinned)
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        community_posts.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_muted_ranked_posts_for_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_muted_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _tag TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      community_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_communities hc ON hp.community_id = hc.id
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hc.name = _tag AND NOT hp.is_paidout AND ha.is_grayed AND (hp.payout + hp.pending_payout) > 0
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        community_posts.source AS blacklists,
        hp.muted_reasons
      FROM community_posts,
      LATERAL hivemind_app.get_post_view_by_id(community_posts.id) hp
      ORDER BY
        community_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_trending_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_trending_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_tag_id INT;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id( _tag, True );

  IF _post_id <> 0 THEN
    SELECT sc_trend INTO _trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hpt.tag_id = _tag_id AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.sc_trend >= _trending_limit AND NOT (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_trend DESC, hp.id DESC
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        hp.sc_trend DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_hot_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_hot_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_hot_limit FLOAT;
_tag_id INT;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id( _tag, True );

  IF _post_id <> 0 THEN
    SELECT sc_hot INTO _hot_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hpt.tag_id = _tag_id AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.sc_hot >= _hot_limit AND NOT ( hp.sc_hot = _hot_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY hp.sc_hot DESC, hp.id DESC
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        hp.sc_hot DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_created_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_created_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_tag_id INT;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id( _tag, True );

  _result = (
    SELECT jsonb_agg (
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hpt.tag_id = _tag_id
          AND NOT (_post_id <> 0 AND hp.id >= _post_id)
          AND NOT ha.is_grayed
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_promoted_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_promoted_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_tag_id INT;
_promoted_limit hivemind_app.hive_posts.promoted%TYPE;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id( _tag, True );

  IF _post_id <> 0 THEN
      SELECT promoted INTO _promoted_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    ( CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hpt.tag_id = _tag_id AND NOT hp.is_paidout AND hp.promoted > 0
          AND NOT (_post_id <> 0 AND hp.promoted >= _promoted_limit AND NOT (hp.promoted = _promoted_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.promoted DESC, hp.id DESC
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        hp.promoted DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_payout_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_payout_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_category_id INT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_head_block_time TIMESTAMP;
_result JSONB;
BEGIN
  _category_id = hivemind_postgrest_utilities.find_category_id(_tag, True);
  _head_block_time = hivemind_app.head_block_time();
  IF _post_id <> 0 THEN
      SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_comments_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hp.category_id = _category_id AND NOT hp.is_paidout
          AND NOT (NOT(NOT _called_from_bridge_api AND hp.depth = 0) AND NOT ( _called_from_bridge_api AND hp.payout_at BETWEEN _head_block_time + interval '12 hours' AND _head_block_time + interval '36 hours'))
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        tag_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_category_id INT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  _category_id = hivemind_postgrest_utilities.find_category_id(_tag, True);

  IF _post_id <> 0 THEN
      SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_comments_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hp.category_id = _category_id AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        tag_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_muted_ranked_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_muted_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _tag TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_tag_id INT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id(_tag, True);

  IF _post_id <> 0 THEN
      SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      tag_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_comments_view hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hpt.tag_id = _tag_id AND NOT hp.is_paidout AND ha.is_grayed AND (hp.payout + hp.pending_payout) > 0
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        tag_posts.source AS blacklists,
        hp.muted_reasons
      FROM tag_posts,
      LATERAL hivemind_app.get_post_view_by_id(tag_posts.id) hp
      ORDER BY
        tag_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_trending_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_trending_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
      SELECT sc_trend INTO _trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.promoted >= _trending_limit AND NOT (hp.promoted = _trending_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_trend DESC, hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        hp.sc_trend DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_hot_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_hot_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_hot_limit FLOAT;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
      SELECT sc_hot INTO _hot_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.promoted >= _hot_limit AND NOT (hp.promoted = _hot_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_hot DESC, hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        hp.sc_hot DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_created_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_created_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _result JSONB;
BEGIN
  _result = (
    SELECT jsonb_agg (
        hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        JOIN hivemind_app.hive_subscriptions hs ON hs.community_id = hp.community_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id
          AND NOT ha.is_grayed AND NOT(_post_id <> 0 AND hp.id >= _post_id)
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_promoted_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_promoted_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_promoted_limit hivemind_app.hive_posts.promoted%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
      SELECT promoted INTO _promoted_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id AND NOT hp.is_paidout AND hp.promoted > 0
          AND NOT (_post_id <> 0 AND hp.promoted >= _promoted_limit AND NOT (hp.promoted = _promoted_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.promoted DESC, hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        hp.promoted DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_payout_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_payout_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_head_block_time TIMESTAMP;
_result JSONB;
BEGIN
  _head_block_time = hivemind_app.head_block_time();

  IF _post_id <> 0 THEN
      SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id AND NOT hp.is_paidout
          AND hp.payout_at BETWEEN _head_block_time + interval '12 hours' AND _head_block_time + interval '36 hours'
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        observer_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
      SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id AND NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        observer_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_muted_ranked_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_muted_ranked_posts_for_observer_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      observer_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
        JOIN hivemind_app.hive_accounts_view ha ON ha.id = hp.author_id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          hs.account_id = _observer_id AND NOT hp.is_paidout AND ha.is_grayed AND (hp.payout + hp.pending_payout) > 0
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        observer_posts.source AS blacklists,
        hp.muted_reasons
      FROM observer_posts,
      LATERAL hivemind_app.get_post_view_by_id(observer_posts.id) hp
      ORDER BY
        observer_posts.total_payout DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_trending_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_trending_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT sc_trend INTO _trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.sc_trend >= _trending_limit AND NOT (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_trend DESC, hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        hp.sc_trend DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_hot_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_hot_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_hot_limit FLOAT;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT sc_hot INTO _hot_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    ( CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND hp.sc_hot >= _hot_limit AND NOT (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.sc_hot DESC, hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        hp.sc_hot DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_created_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_created_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _result JSONB;
BEGIN
  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT ha.is_grayed
          AND NOT (_post_id <> 0 AND hp.id >= _post_id)
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_promoted_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_promoted_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_promoted_limit hivemind_app.hive_posts.promoted%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT promoted INTO _promoted_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          blacklist.source
        FROM hivemind_app.live_posts_comments_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT hp.is_paidout AND hp.promoted > 0
          AND NOT (_post_id <> 0 AND hp.promoted >= _promoted_limit AND NOT (hp.promoted = _promoted_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          hp.promoted DESC, hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        hp.promoted DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_payout_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_payout_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_head_block_time TIMESTAMP;
_result JSONB;
BEGIN
  _head_block_time = hivemind_app.head_block_time();

  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_comments_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT hp.is_paidout
          AND NOT (NOT(NOT _called_from_bridge_api AND hp.depth = 0) AND NOT ( _called_from_bridge_api AND hp.payout_at BETWEEN _head_block_time + interval '12 hours' AND _head_block_time + interval '36 hours'))
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        (hp.payout + hp.pending_payout) DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_payout_comments_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_payout_comments_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(row, _truncate_body, NULL, row.is_pinned, True)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_comments_view hp
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT hp.is_paidout
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
          AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
        ORDER BY
          (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        (hp.payout + hp.pending_payout) DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_all_muted_ranked_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_all_muted_ranked_posts(IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT (payout + pending_payout) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    SELECT jsonb_agg (
      hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)
    ) FROM (
      WITH 
      all_posts as
      (
        SELECT
          hp.id,
          (hp.payout + hp.pending_payout) as total_payout,
          blacklist.source
        FROM hivemind_app.live_posts_comments_view hp
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
        WHERE
          NOT hp.is_paidout AND ha.is_grayed AND (hp.payout + hp.pending_payout) > 0
          AND NOT (_post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id))
        ORDER BY (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
        all_posts.source AS blacklists,
        hp.muted_reasons
      FROM all_posts,
      LATERAL hivemind_app.get_post_view_by_id(all_posts.id) hp
      ORDER BY
        (hp.payout + hp.pending_payout) DESC, hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;