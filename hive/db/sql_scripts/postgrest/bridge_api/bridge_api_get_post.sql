DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_posts;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_posts(IN _json_is_object BOOLEAN, IN _params JSON)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_author TEXT;
_permlink TEXT;

_post_id INT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink","observer"}', '{"string","string","string"}', 2);
  _author = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True);
  _permlink = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True);
  
  _author = hivemind_postgrest_utilities.valid_account(_author, False);
  _permlink = hivemind_postgrest_utilities.valid_permlink(_permlink, False);
  PERFORM hivemind_postgrest_utilities.valid_account(hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 2, False), True);

  _post_id =  hivemind_postgrest_utilities.find_comment_id( _author, _permlink, True);

  RETURN (
    SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, False, True) FROM (
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
        NULL AS blacklists,
        hp.muted_reasons
      FROM hivemind_app.get_post_view_by_id(_post_id) hp
    ) row
  );
END
$$
;