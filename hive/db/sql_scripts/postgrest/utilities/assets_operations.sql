DROP TYPE IF EXISTS hivemind_postgrest_utilities.currency CASCADE;
CREATE TYPE hivemind_postgrest_utilities.currency AS ENUM( 'HBD', 'HIVE', 'VESTS');

DROP TABLE IF EXISTS hivemind_postgrest_utilities.nai_currency_map;
CREATE TABLE hivemind_postgrest_utilities.nai_currency_map
(
  name hivemind_postgrest_utilities.currency PRIMARY KEY,
  nai TEXT NOT NULL,
  precision INT NOT NULL
);
INSERT INTO hivemind_postgrest_utilities.nai_currency_map VALUES ('HBD','@@000000013', 3), ('HIVE','@@000000021', 3), ('VESTS','@@000000037', 6);


DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.to_nai;
CREATE FUNCTION hivemind_postgrest_utilities.to_nai(IN _amount NUMERIC, IN _currency hivemind_postgrest_utilities.currency) 
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$BODY$
BEGIN

RETURN (
WITH calculate_nai_type AS 
(
  SELECT ROUND(_amount * (10^(nai_map.precision))) as amount, nai_map.nai, nai_map.precision
  FROM hivemind_postgrest_utilities.nai_currency_map nai_map
  WHERE nai_map.name = _currency
)
  SELECT jsonb_build_object(
    'amount', cnt.amount::TEXT, -- FOR NOW TESTS ALWAYS REQUIRES AMOUNT AS TEXT
    'nai', cnt.nai,
    'precision', cnt.precision)
  FROM calculate_nai_type cnt);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.parse_asset;
CREATE FUNCTION hivemind_postgrest_utilities.parse_asset(_value VARCHAR(30))
RETURNS RECORD
LANGUAGE plpgsql
IMMUTABLE                            
AS        
$BODY$                  
DECLARE                    
  _currency_as_text VARCHAR(5) := split_part(_value, ' ', 2);                                                                                  
  _amount NUMERIC;
  _result RECORD;
BEGIN                                                        
  IF _currency_as_text = 'SBD' THEN
      _currency_as_text = 'HBD';
  ELSIF _currency_as_text = 'STEEM' THEN
      _currency_as_text = 'HIVE';
  END IF;                                                                         
  _amount = split_part(_value, ' ', 1)::NUMERIC;
  SELECT _amount, hivemind_postgrest_utilities.currency(_currency_as_text) INTO _result;
  RETURN _result;
END;                               
$BODY$                                                                                          
;

DROP TYPE IF EXISTS hivemind_postgrest_utilities.pending_reward_basis CASCADE;
CREATE TYPE hivemind_postgrest_utilities.pending_reward_basis AS (
  liquid NUMERIC,
  vesting NUMERIC,
  direct NUMERIC,
  total NUMERIC
);

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.hive_100_percent;
CREATE FUNCTION hivemind_postgrest_utilities.hive_100_percent()
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS
$BODY$
  SELECT 10000::NUMERIC;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.hive_curation_rewards_percent;
CREATE FUNCTION hivemind_postgrest_utilities.hive_curation_rewards_percent()
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS
$BODY$
  SELECT 5000::NUMERIC;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.floor_asset_amount;
CREATE FUNCTION hivemind_postgrest_utilities.floor_asset_amount(
  IN _amount NUMERIC,
  IN _precision INT
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS
$BODY$
  SELECT FLOOR(GREATEST(COALESCE(_amount, 0), 0) * POWER(10::NUMERIC, _precision)) / POWER(10::NUMERIC, _precision);
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.pending_author_reward_basis;
CREATE FUNCTION hivemind_postgrest_utilities.pending_author_reward_basis(
  IN _reward_basis NUMERIC,
  IN _percent_hbd NUMERIC
)
RETURNS hivemind_postgrest_utilities.pending_reward_basis
LANGUAGE plpgsql
STABLE
AS
$BODY$
DECLARE
  _result hivemind_postgrest_utilities.pending_reward_basis;
  _percent_hbd_clamped NUMERIC := LEAST(GREATEST(COALESCE(_percent_hbd, hivemind_postgrest_utilities.hive_100_percent()), 0), hivemind_postgrest_utilities.hive_100_percent());
  _total NUMERIC;
  _liquid NUMERIC;
BEGIN
  _total := GREATEST(COALESCE(_reward_basis, 0), 0);
  _liquid :=
    _total * _percent_hbd_clamped / (2 * hivemind_postgrest_utilities.hive_100_percent());

  _result.liquid := _liquid;
  _result.vesting := _total - _liquid;
  _result.direct := 0::NUMERIC;
  _result.total := _total;

  RETURN _result;
END;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.is_hive_treasury_account;
CREATE FUNCTION hivemind_postgrest_utilities.is_hive_treasury_account(
  IN _account_name TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS
$BODY$
  SELECT _account_name IN ('hive.fund', 'steem.dao');
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.pending_direct_reward_basis;
CREATE FUNCTION hivemind_postgrest_utilities.pending_direct_reward_basis(
  IN _reward_basis NUMERIC
)
RETURNS hivemind_postgrest_utilities.pending_reward_basis
LANGUAGE plpgsql
STABLE
AS
$BODY$
DECLARE
  _result hivemind_postgrest_utilities.pending_reward_basis;
  _total NUMERIC;
BEGIN
  _total := GREATEST(COALESCE(_reward_basis, 0), 0);
  _result.liquid := 0::NUMERIC;
  _result.vesting := 0::NUMERIC;
  _result.direct := _total;
  _result.total := _total;

  RETURN _result;
END;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.pending_vesting_reward_basis;
CREATE FUNCTION hivemind_postgrest_utilities.pending_vesting_reward_basis(
  IN _reward_basis NUMERIC
)
RETURNS hivemind_postgrest_utilities.pending_reward_basis
LANGUAGE plpgsql
STABLE
AS
$BODY$
DECLARE
  _result hivemind_postgrest_utilities.pending_reward_basis;
  _total NUMERIC;
BEGIN
  _total := GREATEST(COALESCE(_reward_basis, 0), 0);

  _result.liquid := 0::NUMERIC;
  _result.vesting := _total;
  _result.direct := 0::NUMERIC;
  _result.total := _total;

  RETURN _result;
END;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.to_pending_reward_basis_json(NUMERIC, NUMERIC, NUMERIC, NUMERIC);
CREATE FUNCTION hivemind_postgrest_utilities.to_pending_reward_basis_json(
  IN _liquid NUMERIC,
  IN _vesting NUMERIC,
  IN _direct NUMERIC,
  IN _total NUMERIC
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS
$BODY$
  WITH floored AS (
    SELECT
      hivemind_postgrest_utilities.floor_asset_amount(_liquid, 3) AS liquid,
      hivemind_postgrest_utilities.floor_asset_amount(_direct, 3) AS direct,
      hivemind_postgrest_utilities.floor_asset_amount(_total, 3) AS total
  ),
  visible AS (
    SELECT
      liquid,
      -- Keep the serialized buckets additive after flooring to HBD NAI precision.
      GREATEST(total - liquid - direct, 0) AS vesting,
      direct,
      total
    FROM floored
  )
  SELECT jsonb_build_object(
    'liquid', hivemind_postgrest_utilities.to_nai(liquid, 'HBD'::hivemind_postgrest_utilities.currency),
    'vesting', hivemind_postgrest_utilities.to_nai(vesting, 'HBD'::hivemind_postgrest_utilities.currency),
    'direct', hivemind_postgrest_utilities.to_nai(direct, 'HBD'::hivemind_postgrest_utilities.currency),
    'total', hivemind_postgrest_utilities.to_nai(total, 'HBD'::hivemind_postgrest_utilities.currency)
  )
  FROM visible;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.to_pending_reward_basis_json(hivemind_postgrest_utilities.pending_reward_basis);
CREATE FUNCTION hivemind_postgrest_utilities.to_pending_reward_basis_json(
  IN _basis hivemind_postgrest_utilities.pending_reward_basis
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS
$BODY$
  SELECT hivemind_postgrest_utilities.to_pending_reward_basis_json(
    _basis.liquid,
    _basis.vesting,
    _basis.direct,
    _basis.total
  );
$BODY$;
