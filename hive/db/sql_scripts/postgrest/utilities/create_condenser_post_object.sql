DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.create_condenser_post_object;
CREATE FUNCTION hivemind_postgrest_utilities.create_condenser_post_object(IN _row RECORD, IN _truncate_body_len INT, IN _content_additions BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
_result JSONB;
_tmp_asset JSONB;
_tmp_currency hivemind_postgrest_utilities.currency;
_tmp_amount NUMERIC;

BEGIN

  _result = json_build_object(
    'author', _row.author,
    'permlink', _row.permlink,
    'category', (CASE
                  WHEN _row.category IS NULL THEN 'undefined'
                  ELSE _row.category
                END),
    'title', _row.title,
    'body', (CASE
              WHEN _truncate_body_len > 0 THEN left(_row.body, _truncate_body_len)
              ELSE _row.body
              END),
    'json_metadata', _row.json,
    'created', _row.created_at,
    'last_update', _row.updated_at,
    'depth', _row.depth,
    'children', _row.children,
    'curator_payout_value', '0.000 HBD',
    'promoted', _row.promoted || ' ' || 'HBD',
    'replies', array_to_json('{}'::INT[]),
    'body_length', LENGTH(_row.body),
    'author_reputation', _row.author_rep,
    'parent_author', _row.parent_author,
    'parent_permlink', _row.parent_permlink_or_category,
    'url', _row.url,
    'root_title', _row.root_title,
    'beneficiaries', _row.beneficiaries,
    'max_accepted_payout', _row.max_accepted_payout,
    'percent_hbd', _row.percent_hbd,
    'active_votes', hivemind_postgrest_utilities.list_votes(_row.author, _row.permlink, /* in python code it was hardcoded */ 1000, 'condenser_api')
  );

  -- afaik in all cases when currency is not HBD, assert is thrown in python code, so currency type is always HBD.
  IF _row.is_paidout THEN
    _result = jsonb_set(_result, '{last_payout}', to_jsonb(hivemind_postgrest_utilities.json_date(_row.payout_at)));
    _result = jsonb_set(_result, '{cashout_time}', to_jsonb(hivemind_postgrest_utilities.json_date()));
    _result = jsonb_set(_result, '{pending_payout_value}', to_jsonb('0.000 HBD'::text));
    _result = jsonb_set(_result, '{total_payout_value}', to_jsonb(_row.payout || ' HBD'));
  ELSE
    _result = jsonb_set(_result, '{last_payout}', to_jsonb(hivemind_postgrest_utilities.json_date()));
    _result = jsonb_set(_result, '{cashout_time}', to_jsonb(hivemind_postgrest_utilities.json_date(_row.payout_at)));
    _tmp_amount = _row.payout + _row.pending_payout;
    _result = jsonb_set(_result, '{pending_payout_value}', to_jsonb(_tmp_amount || ' HBD'));
    _result = jsonb_set(_result, '{total_payout_value}', to_jsonb('0.000 HBD'::text));
  END IF;

  IF _content_additions THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create condenser post object - not finished when _content_additions is TRUE');
  ELSE
    _result = jsonb_set(_result, '{post_id}', to_jsonb(_row.id));
    _result = jsonb_set(_result, '{net_rshares}', to_jsonb(_row.rshares));
    IF _row.is_paidout THEN
      _result = jsonb_set(_result, '{curator_payout_value}', to_jsonb(_row.curator_payout_value));
      SELECT amount, currency FROM hivemind_postgrest_utilities.parse_asset(_row.curator_payout_value) AS (amount NUMERIC, currency hivemind_postgrest_utilities.currency) INTO _tmp_amount, _tmp_currency;
      _tmp_amount = _row.payout - _tmp_amount;
      _result = jsonb_set(_result, '{total_payout_value}', to_jsonb(_tmp_amount || ' ' || _tmp_currency));
    END IF;
  END IF;

  RETURN _result;
END
$function$
;