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
  _post_id_as_text TEXT;
  _parent_id_as_text TEXT;
  _bridge_post JSONB;
  _parent_author_permlink TEXT;
  _post_id_parent_id_post JSONB;
  _result JSONB DEFAULT '{}'::JSONB;
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

  SELECT
    jsonb_object_agg(row.id::TEXT, jsonb_build_array(row.parent_id::TEXT, (row.author || '/' || row.permlink), hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True)))
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
        ds.source AS blacklists,
        hpv.muted_reasons
      FROM
      (
        WITH RECURSIVE child_posts (id, parent_id) AS MATERIALIZED
        (
          SELECT hp.id, hp.parent_id, hivemind_app.blacklisted_by_observer_view.source as source
          FROM hivemind_app.live_posts_comments_view hp left outer join hivemind_app.blacklisted_by_observer_view on (hivemind_app.blacklisted_by_observer_view.observer_id = _observer_id AND hivemind_app.blacklisted_by_observer_view.blacklisted_id = hp.author_id)
          WHERE hp.id = _post_id
          AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
          UNION ALL
          SELECT children.id, children.parent_id, hivemind_app.blacklisted_by_observer_view.source as source
          FROM hivemind_app.live_posts_comments_view children left outer join hivemind_app.blacklisted_by_observer_view on (hivemind_app.blacklisted_by_observer_view.observer_id = _observer_id AND hivemind_app.blacklisted_by_observer_view.blacklisted_id = children.author_id)
          JOIN child_posts ON children.parent_id = child_posts.id
          JOIN hivemind_app.hive_accounts ON children.author_id = hivemind_app.hive_accounts.id
          AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = children.author_id))
        )
        SELECT hp2.id, cp.source
        FROM hivemind_app.hive_posts hp2
        JOIN child_posts cp ON cp.id = hp2.id
        ORDER BY hp2.id
      ) ds,
        LATERAL hivemind_app.get_post_view_by_id(ds.id) hpv
      ORDER BY ds.id
      LIMIT 2000
  ) row INTO _post_id_parent_id_post;

  IF _post_id_parent_id_post IS NOT NULL THEN
    FOR _post_id_as_text IN SELECT key FROM jsonb_each(_post_id_parent_id_post) LOOP
      _parent_id_as_text = _post_id_parent_id_post->_post_id_as_text->>0;
      _bridge_post = _post_id_parent_id_post->_post_id_as_text->2;
      _result = _result || jsonb_build_object(_post_id_parent_id_post->_post_id_as_text->>1, _bridge_post);
      IF _parent_id_as_text IS NOT NULL AND _parent_id_as_text <> '0' THEN
        IF _post_id_parent_id_post ? _parent_id_as_text THEN
          _parent_author_permlink = _post_id_parent_id_post->_parent_id_as_text->>1;
          _result = jsonb_set(_result, ARRAY[_parent_author_permlink, 'replies'], _result->(_parent_author_permlink)->'replies' || jsonb_build_array(_post_id_parent_id_post->_post_id_as_text->>1));
        END IF;
      END IF;
    END LOOP;
  END IF;

  RETURN _result;
END
$$
;

