DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.create_bridge_post_object;
CREATE FUNCTION hivemind_postgrest_utilities.create_bridge_post_object(IN _row RECORD, IN _truncate_body_len INT, IN _reblogged_by TEXT[], IN _set_is_pinned_field BOOLEAN, IN _update_reblogs_field BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
_result JSONB;
_tmp_currency hivemind_postgrest_utilities.currency;
_tmp_amount NUMERIC;
_tmp_muted_reasons JSONB;
BEGIN
  _tmp_amount = hivemind_postgrest_utilities.rep_log10(_row.author_rep);
  _result = jsonb_build_object(
    'post_id', _row.id,
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
    'created', to_jsonb(hivemind_postgrest_utilities.json_date(_row.created_at)),
    'updated', to_jsonb(hivemind_postgrest_utilities.json_date(_row.updated_at)),
    'depth', _row.depth,
    'children', _row.children,
    'net_rshares', _row.rshares,
    'is_paidout', _row.is_paidout,
    'payout_at', to_jsonb(hivemind_postgrest_utilities.json_date(_row.payout_at)),
    'replies', to_jsonb('{}'::INT[]),
    'reblogs',  (CASE
                  WHEN _update_reblogs_field THEN (SELECT COUNT(*) FROM hivemind_app.hive_reblogs hr WHERE hr.post_id = _row.id)
                  ELSE 0
                END),
    'url', _row.url,
    'beneficiaries', _row.beneficiaries,
    'max_accepted_payout', _row.max_accepted_payout,
    'percent_hbd', _row.percent_hbd,
    'json_metadata', (CASE
                        WHEN _row.json IS NOT NULL AND _row.json <> '' AND _row.json::jsonb IS NOT NULL THEN _row.json::jsonb
                        ELSE '{}'::jsonb
                      END),
    'stats', jsonb_build_object(
              'hide', _row.is_hidden,
              'gray', (CASE
                        WHEN _row.is_grayed OR _row.is_muted OR _row.role_id = -2 THEN True
                        ELSE False
                        END),
              'total_votes', _row.total_votes,
              -- FROM PYTHON
              -- take negative rshares, divide by 2, truncate 10 digits (plus neg sign), and count digits. creates a cheap log10, stake-based flag weight.
              -- result: 1 = approx $400 of downvoting stake; 2 = $4,000; etc
              'flag_weight', ROUND(GREATEST((LENGTH(FLOOR((FLOOR((_row.rshares - _row.abs_rshares) / 2)) / 2)::TEXT) - 11), 0.0), 2)
            ),
    'payout', (_row.payout + _row.pending_payout),
    'promoted', _row.promoted || ' HBD',
    'author_reputation',  (CASE
                            WHEN _row.author_rep = 0 THEN _tmp_amount
                            ELSE ROUND(_tmp_amount, 2)
                          END),
    'active_votes', hivemind_postgrest_utilities.list_votes(_row.author, _row.permlink, /* in python code it was hardcoded */ 1000,
                    'create_post'::hivemind_postgrest_utilities.list_votes_case, 'bridge_api'::hivemind_postgrest_utilities.vote_presentation),
    'blacklists', (CASE
                    WHEN _row.blacklists IS NOT NULL AND _row.blacklists <> '' THEN to_jsonb(string_to_array(_row.blacklists, ',')) 
                    ELSE to_jsonb('{}'::INT[])
                  END)
  );
  -- reputation
  IF _tmp_amount < 1 THEN
    _result = jsonb_set(_result, '{blacklists}', _result->'blacklists' || jsonb_build_array('reputation-0'));
  ELSIF _tmp_amount = 1 THEN
    _result = jsonb_set(_result, '{blacklists}', _result->'blacklists' || jsonb_build_array('reputation-1'));
  END IF;

  IF _set_is_pinned_field AND _row.is_pinned THEN
    _result = jsonb_set(_result, '{stats}', _result->'stats' || jsonb_build_object('is_pinned', True));
  END IF;

  IF _reblogged_by IS NOT NULL AND CARDINALITY(_reblogged_by) > 0 THEN
    IF CARDINALITY(_reblogged_by) > 1 THEN
      _reblogged_by = array_sort(_reblogged_by);
    END IF;
    _result = jsonb_set(_result, '{reblogged_by}', to_jsonb(_reblogged_by));
  END IF;

  IF _row.community_title IS NOT NULL AND _row.community_title <> '' THEN
    _result = jsonb_set(_result, '{community}', to_jsonb(_row.category));
    _result = jsonb_set(_result, '{community_title}', to_jsonb(_row.community_title));

    IF _row.role_id IS NOT NULL THEN
      _result = jsonb_set(_result, '{author_title}', to_jsonb(_row.role_title));

      IF _row.role_id IN (-2,0,2,4,6,8) THEN
        _result = jsonb_set(_result, '{author_role}', to_jsonb(CASE _row.role_id
                                                                WHEN -2 THEN 'muted'::text
                                                                WHEN 0 THEN 'guest'::text
                                                                WHEN 2 THEN 'member'::text
                                                                WHEN 4 THEN 'mod'::text
                                                                WHEN 6 THEN 'admin'::text
                                                                WHEN 8 THEN 'owner'::text
                                                                ELSE 'unknown'
                                                              END));
      ELSE
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unknown author role: ' || _row.role_id);
      END IF;

    ELSE
      _result = jsonb_set(_result, '{author_role}', to_jsonb('guest'::text));
      _result = jsonb_set(_result, '{author_title}', to_jsonb(''::text));
    END IF;
  END IF;

  IF _row.is_paidout THEN
    SELECT amount, currency FROM hivemind_postgrest_utilities.parse_asset(_row.curator_payout_value) AS (amount NUMERIC, currency hivemind_postgrest_utilities.currency) INTO _tmp_amount, _tmp_currency;
    assert _tmp_currency = 'HBD', 'expecting HBD currency';
    _result = jsonb_set(_result, '{curator_payout_value}', to_jsonb(_tmp_amount || ' HBD'));
    _tmp_amount = _row.payout - _tmp_amount;
    _result = jsonb_set(_result, '{author_payout_value}', to_jsonb(_tmp_amount || ' HBD'));
    _result = jsonb_set(_result, '{pending_payout_value}', to_jsonb('0.000 HBD'::text));
  ELSE
    _result = jsonb_set(_result, '{author_payout_value}', to_jsonb('0.000 HBD'::text));
    _result = jsonb_set(_result, '{curator_payout_value}', to_jsonb('0.000 HBD'::text));
    _result = jsonb_set(_result, '{pending_payout_value}', to_jsonb(_result->>'payout' || ' HBD'));
  END IF;

  IF _row.depth > 0 THEN
    _result = jsonb_set(_result, '{parent_author}', to_jsonb(_row.parent_author));
    _result = jsonb_set(_result, '{parent_permlink}', to_jsonb(_row.parent_permlink_or_category));
    _result = jsonb_set(_result, '{title}', to_jsonb('RE: ' || _row.root_title));
  END IF;

  _tmp_muted_reasons = hivemind_postgrest_utilities.decode_muted_reasons_mask(_row.muted_reasons);

  IF _row.is_grayed THEN
    _tmp_muted_reasons = _tmp_muted_reasons || jsonb_build_array(3);  -- MUTED_REPUTATION
  END IF;

  IF _row.role_id = -2 THEN
    _tmp_muted_reasons = _tmp_muted_reasons || jsonb_build_array(4);  -- MUTED_ROLE_COMMUNITY
  END IF;

  IF jsonb_array_length(_tmp_muted_reasons) <> 0 THEN
    _result = jsonb_set(_result, '{stats}', _result->'stats' || jsonb_build_object('muted_reasons', _tmp_muted_reasons));
  END IF;

  RETURN _result;
END
$function$
;