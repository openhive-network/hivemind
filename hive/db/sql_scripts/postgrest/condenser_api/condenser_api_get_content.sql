DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_content;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_content(IN _params JSONB, IN _get_replies BOOLEAN, IN _content_additions BOOLEAN)
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
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"author": "string", "permlink": "string", "observer": "string"}', 2, NULL);
  -- observer is ignored in python, so it is ignored here as well
  _author = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True);
  _permlink = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True);
  _author = hivemind_postgrest_utilities.valid_account(_author);
  _permlink = hivemind_postgrest_utilities.valid_permlink(_permlink);
  _post_id = hivemind_postgrest_utilities.find_comment_id( _author, _permlink, True );
  IF _get_replies THEN
    RETURN COALESCE((
      SELECT jsonb_agg (
        hivemind_postgrest_utilities.create_condenser_post_object(row, 0, _content_additions)
      ) FROM (
        WITH replies AS -- condenser_api_get_content with replies
        (
          SELECT id 
          FROM hivemind_app.live_posts_comments_view hp
          WHERE hp.parent_id = _post_id 
          ORDER BY hp.id
          LIMIT 5000
        )
        SELECT
          hp.id,
          hp.author,
          hp.permlink,
          hp.author_rep,
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
          hp.net_votes,
          hp.total_vote_weight,
          hp.parent_author,
          hp.parent_permlink_or_category,
          hp.curator_payout_value,
          hp.root_author,
          hp.root_permlink,
          hp.max_accepted_payout,
          hp.percent_hbd,
          hp.allow_replies,
          hp.allow_votes,
          hp.allow_curation_rewards,
          hp.beneficiaries,
          hp.url,
          hp.root_title,
          hp.active,
          hp.author_rewards
        FROM replies,
        LATERAL hivemind_app.get_post_view_by_id(replies.id) hp
        ORDER BY hp.id
      ) row )
    , '[]'::jsonb);

    RETURN COALESCE(_result, '[]'::jsonb);
  ELSE
    RETURN (
      SELECT hivemind_postgrest_utilities.create_condenser_post_object(row, 0, _content_additions) FROM (       -- condenser_api_get_content without replies
        SELECT
          hp.id,
          hp.author,
          hp.permlink,
          hp.author_rep,
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
          hp.net_votes,
          hp.total_vote_weight,
          hp.parent_author,
          hp.parent_permlink_or_category,
          hp.curator_payout_value,
          hp.root_author,
          hp.root_permlink,
          hp.max_accepted_payout,
          hp.percent_hbd,
          hp.allow_replies,
          hp.allow_votes,
          hp.allow_curation_rewards,
          hp.beneficiaries,
          hp.url,
          hp.root_title,
          hp.active,
          hp.author_rewards
        FROM hivemind_app.get_post_view_by_id(_post_id) hp
      ) row
    );
  END IF;
END;
$$
;