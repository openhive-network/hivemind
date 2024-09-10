-- methods which are used only for condenser_api - get state

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.gs_normalize_path;
CREATE FUNCTION hivemind_postgrest_utilities.gs_normalize_path(in _path TEXT)
RETURNS RECORD
LANGUAGE plpgsql
IMMUTABLE
AS
$BODY$
DECLARE
  _char_position INT;
  _parts TEXT[];
  _modified_path TEXT;
  _normalized_path RECORD;
BEGIN
  IF left(_path, 1) = '/' THEN
    _path = substring(_path from 2);
  END IF;

  _char_position = position('?' in _path);
  IF _char_position <> 0 THEN
    _path = substring(_path FROM 1 FOR _char_position);
  END IF;

  IF _path = '' THEN
    _path = 'trending';
  END IF;

  IF position('#' IN _path) <> 0 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('path contains hash mark (#)');
  END IF;

  _modified_path = _path;

  LOOP
    _char_position = position('/' IN _modified_path);
    IF _char_position <> 0 THEN
      _parts = array_append(_parts, substring(_modified_path FROM 1 FOR _char_position - 1));
      _modified_path = substring(_modified_path FROM _char_position + 1);
    ELSE
      _parts = array_append(_parts, substring(_modified_path FROM 1));
      EXIT;
      
    END IF;
  END LOOP;

  IF CARDINALITY(_parts) = 4 AND _parts[4] = '' THEN
    _parts = array_remove(_parts, _parts[4]);
  END IF;

  IF CARDINALITY(_parts) > 3 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('too many parts in path:' || _path);
  END IF;

  LOOP
    IF CARDINALITY(_parts) < 3 THEN
    
      _parts = array_append(_parts, NULL);
    ELSE
      EXIT;
    END IF;
  END LOOP;

  SELECT _path, _parts INTO _normalized_path;
  RETURN _normalized_path;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.gs_get_hive_account_info_view_query_string;
CREATE FUNCTION hivemind_postgrest_utilities.gs_get_hive_account_info_view_query_string(IN _name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$BODY$
DECLARE
_result JSONB DEFAULT '{"' || _name || '":""}';
BEGIN
_result = jsonb_set(_result, ('{' || _name || '}')::text[], (
  SELECT to_jsonb(row) FROM (
    SELECT
    ha.id,
    ha.name,
    ha.post_count,
    ha.created_at,
    ha.active_at,
    ha.reputation,
    ha.rank,
    ha.following,
    ha.followers,
    ha.lastread_at,
    ha.posting_json_metadata,
    ha.json_metadata
    FROM hivemind_app.hive_accounts_info_view ha
    WHERE ha.name = _name
  ) row)
);

IF _result->>_name IS NULL THEN
  RAISE EXCEPTION '%', hivemind_postgrest_utilities.invalid_account_exception('account not found: ' || _name);
ELSE
  RETURN _result;
END IF;
END;
$BODY$
;