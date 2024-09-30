DROP TYPE IF EXISTS hivemind_postgrest_utilities.currency CASCADE;
CREATE TYPE hivemind_postgrest_utilities.currency AS ENUM( 'HBD', 'HIVE', 'VESTS');
DROP TABLE IF EXISTS hivemind_postgrest_utilities.nai_currency_map;
CREATE TABLE hivemind_postgrest_utilities.nai_currency_map
(
  name hivemind_postgrest_utilities.currency PRIMARY KEY,
  nai TEXT NOT NULL,
  precision INT NOT NULL
);
INSERT INTO hivemind_postgrest_utilities.nai_currency_map VALUES ('HBD','@@000000013', 3), ('HIVE','@@000000021', 3), ('VESTS','@@000000037', 3);

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
    'amount', cnt.amount,
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