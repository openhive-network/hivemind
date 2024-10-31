DROP TYPE IF EXISTS hivemind_postgrest_utilities.database_api_author_permlink CASCADE;
CREATE TYPE hivemind_postgrest_utilities.database_api_author_permlink AS (author TEXT, permlink TEXT);

DROP FUNCTION IF EXISTS hivemind_endpoints.database_api_find_comments;
CREATE FUNCTION hivemind_endpoints.database_api_find_comments(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _comments JSONB;
  _comment JSONB;
  _comments_amount INT;
  _authors_and_permlinks hivemind_postgrest_utilities.database_api_author_permlink[];
  _result JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"comments"}', '{"array"}');
  _comments = hivemind_postgrest_utilities.parse_array_argument_from_json(_params, _json_is_object, 'comments', 0, True);

  IF _comments IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Expected array of author+permlink pairs');
  END IF;

  _comments_amount = jsonb_array_length(_comments);

  IF _comments_amount > 1000 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Parameters count is greather than max allowed (1000)');
  END IF;

  FOR _comment IN SELECT * FROM jsonb_array_elements(_comments) LOOP
    CONTINUE WHEN jsonb_typeof(_comment) <> 'array' OR jsonb_array_length(_comment) <> 2;
    CONTINUE WHEN jsonb_typeof(_comment->0) <> 'string' OR _comment->>0 = '' OR jsonb_typeof(_comment->1) <> 'string' OR _comment->>1 = '';
    _authors_and_permlinks = array_append(_authors_and_permlinks, (_comment->>0, _comment->>1)::hivemind_postgrest_utilities.database_api_author_permlink);
  END LOOP;

  _result = (
    SELECT jsonb_build_object(
      'comments', ( SELECT jsonb_agg (
                      hivemind_postgrest_utilities.create_database_post_object(row, 0)
                    ) FROM (
                      WITH posts AS MATERIALIZED
                      (
                        SELECT
                          hp.id
                        FROM
                          hivemind_app.live_posts_comments_view hp
                        JOIN hivemind_app.hive_accounts ha_a ON ha_a.id = hp.author_id
                        JOIN hivemind_app.hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
                        JOIN unnest(_authors_and_permlinks) AS ap ON ha_a.name = ap.author AND hpd_p.permlink = ap.permlink
                        WHERE
                          NOT hp.is_muted
                        LIMIT
                          _comments_amount
                      )
                      SELECT
                        pv.id,
                        pv.community_id,
                        pv.author,
                        pv.permlink,
                        pv.title,
                        pv.body,
                        pv.category,
                        pv.depth,
                        pv.promoted,
                        pv.payout,
                        pv.last_payout_at,
                        pv.cashout_time,
                        pv.is_paidout,
                        pv.children,
                        pv.votes,
                        pv.created_at,
                        pv.updated_at,
                        pv.rshares,
                        pv.json,
                        pv.is_hidden,
                        pv.is_grayed,
                        pv.total_votes,
                        pv.net_votes,
                        pv.total_vote_weight,
                        pv.parent_permlink_or_category,
                        pv.curator_payout_value,
                        pv.root_author,
                        pv.root_permlink,
                        pv.max_accepted_payout,
                        pv.percent_hbd,
                        pv.allow_replies,
                        pv.allow_votes,
                        pv.allow_curation_rewards,
                        pv.beneficiaries,
                        pv.url,
                        pv.root_title,
                        pv.abs_rshares,
                        pv.active,
                        pv.author_rewards,
                        pv.parent_author
                      FROM posts,
                      LATERAL hivemind_app.get_post_view_by_id (posts.id) pv
                      LIMIT _comments_amount
                    ) row
                  )
    )
  );

  IF jsonb_typeof(_result->'comments') = 'null' THEN
    _result = jsonb_set(_result, '{comments}', '[]'::jsonb);
  END IF;
  RETURN _result;
END;
$$
;