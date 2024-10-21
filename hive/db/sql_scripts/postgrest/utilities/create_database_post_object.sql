DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.create_database_post_object;
CREATE FUNCTION hivemind_postgrest_utilities.create_database_post_object(IN _row RECORD, IN _truncate_body_len INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
_result JSONB;
_tmp_currency hivemind_postgrest_utilities.currency;
_tmp_amount NUMERIC;
BEGIN
  _result = jsonb_build_object(
    'id', _row.id,
    'author_rewards', _row.author_rewards,
    'author', _row.author,
    'permlink', _row.permlink,
    'category', (CASE
                  WHEN _row.category IS NULL THEN ''
                  ELSE _row.category
                END),
    'title', _row.title,
    'body', (CASE
              WHEN _truncate_body_len <> 0 THEN left(_row.body, _truncate_body_len)
              ELSE _row.body
            END),
    'json_metadata', _row.json,
    'created', to_jsonb(hivemind_postgrest_utilities.json_date(_row.created_at)),
    'last_update', to_jsonb(hivemind_postgrest_utilities.json_date(_row.updated_at)),
    'last_payout', to_jsonb(hivemind_postgrest_utilities.json_date(_row.last_payout_at)),
    'cashout_time', to_jsonb(hivemind_postgrest_utilities.json_date(_row.cashout_time)),
    'max_cashout_time', to_jsonb(hivemind_postgrest_utilities.json_date()),
    'reward_weight', 10000,
    'root_author', _row.root_author,
    'root_permlink', _row.root_permlink,
    'depth', _row.depth,
    'children', _row.children,
    'allow_replies', _row.allow_replies,
    'allow_votes', _row.allow_votes,
    'allow_curation_rewards', _row.allow_curation_rewards,
    'parent_author', _row.parent_author,
    'parent_permlink', _row.parent_permlink_or_category,
    'beneficiaries', _row.beneficiaries,
    'percent_hbd', _row.percent_hbd,
    'net_votes', _row.net_votes
  );

  SELECT amount, currency FROM hivemind_postgrest_utilities.parse_asset(_row.curator_payout_value) AS (amount NUMERIC, currency hivemind_postgrest_utilities.currency) INTO _tmp_amount, _tmp_currency;
  assert _tmp_currency = 'HBD', 'expecting HBD currency';
  _result = jsonb_set(_result, '{curator_payout_value}', hivemind_postgrest_utilities.to_nai(_tmp_amount, _tmp_currency));
  _result = jsonb_set(_result, '{total_payout_value}', hivemind_postgrest_utilities.to_nai(_row.payout - _tmp_amount, _tmp_currency));
  SELECT amount, currency FROM hivemind_postgrest_utilities.parse_asset(_row.max_accepted_payout) AS (amount NUMERIC, currency hivemind_postgrest_utilities.currency) INTO _tmp_amount, _tmp_currency;
  assert _tmp_currency = 'HBD', 'expecting HBD currency';
  _result = jsonb_set(_result, '{max_accepted_payout}', hivemind_postgrest_utilities.to_nai(_tmp_amount, _tmp_currency));

  IF _row.is_paidout THEN
    _result = jsonb_set(_result, '{total_vote_weight}', to_jsonb(0));
    _result = jsonb_set(_result, '{vote_rshares}', to_jsonb(0));
    _result = jsonb_set(_result, '{abs_rshares}', to_jsonb(0));
    _result = jsonb_set(_result, '{children_abs_rshares}', to_jsonb(0));
    _result = jsonb_set(_result, '{net_rshares}', to_jsonb(0));
  ELSE
    _result = jsonb_set(_result, '{total_vote_weight}', to_jsonb(_row.total_vote_weight));
    _result = jsonb_set(_result, '{vote_rshares}', to_jsonb(FLOOR((_row.rshares + _row.abs_rshares) / 2)));
    _result = jsonb_set(_result, '{abs_rshares}', to_jsonb(_row.abs_rshares));
    _result = jsonb_set(_result, '{children_abs_rshares}', to_jsonb(0));
    _result = jsonb_set(_result, '{net_rshares}', to_jsonb(_row.rshares));
  END IF;

  RETURN _result;
END
$function$
;