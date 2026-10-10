DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_posts(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_posts JSONB;
_posts_amount INT;
_pair JSONB;
_idx INT;
_observer TEXT;
_observer_id INTEGER;
_top_votes INT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"posts": "array", "observer": "string", "top_votes": "number"}', 1, '{"posts": "posts must be an array of [author, permlink] pairs"}');
  _posts = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'posts', True)::JSONB;

  _posts_amount = jsonb_array_length(_posts);
  IF _posts_amount NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('posts must have 1 to 100 entries, got ' || _posts_amount);
  END IF;

  FOR _pair, _idx IN SELECT value, ordinality - 1 FROM jsonb_array_elements(_posts) WITH ORDINALITY LOOP
    IF jsonb_typeof(_pair) <> 'array' OR jsonb_array_length(_pair) <> 2 OR jsonb_typeof(_pair->0) <> 'string' OR jsonb_typeof(_pair->1) <> 'string' THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('posts[' || _idx || '] must be an [author, permlink] pair of strings');
    END IF;
    PERFORM hivemind_postgrest_utilities.valid_account(_pair->>0, False);
    PERFORM hivemind_postgrest_utilities.valid_permlink(_pair->>1, False);
  END LOOP;

  _observer = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False);
  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_observer, True),
    True);

  _top_votes = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'top_votes', False), 0, 0, 10, 'top_votes');

  -- one entry per requested pair, in request order; null where the post doesn't exist or is deleted
  RETURN (
    WITH requested AS ( -- bridge_api_get_posts
      SELECT
        rq.ordinality AS idx,
        hp.id
      FROM jsonb_array_elements(_posts) WITH ORDINALITY rq
      LEFT JOIN hivemind_app.hive_accounts ha ON ha.name = rq.value->>0
      LEFT JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = rq.value->>1
      LEFT JOIN hivemind_app.hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
    )
    SELECT jsonb_agg(
      (CASE
        WHEN row.id IS NULL THEN 'null'::JSONB
        ELSE hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, 0, NULL, False, True, NULL, /* _votes_mode */ 1::SMALLINT, _top_votes)
      END)
      ORDER BY requested.idx
    )
    FROM requested
    LEFT JOIN LATERAL (
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
        hp.is_grayed,
        hp.total_votes,
        hp.sc_trend,
        hp.role_title,
        hp.community_title,
        hp.role_id,
        hp.is_pinned,
        hp.curator_payout_value,
        hp.is_muted,
        NULL AS blacklists,
        hp.muted_reasons
      FROM hivemind_app.get_post_view_by_id(requested.id) hp
    ) row ON True
  );
END
$$
;
