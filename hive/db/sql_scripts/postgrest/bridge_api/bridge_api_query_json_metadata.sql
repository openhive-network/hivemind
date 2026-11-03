DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_query_json_metadata;
CREATE FUNCTION hivemind_endpoints.bridge_api_query_json_metadata(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _path TEXT[];
    _value TEXT;
    _values JSONB[];
    _literal TEXT;
    _types JSONB;
    _posting BOOLEAN;
    _active BOOLEAN;
    _last_id INT;
    _limit INT;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"key": "string|array", "value": "string|number|boolean", "type": "string|array", "last": "string", "limit": "number"}', 2, NULL);

    -- key: one top-level key, or a list of keys naming a nested value
    PERFORM hivemind_postgrest_utilities.parse_argument_from_json(_params, 'key', True);
    IF jsonb_typeof(_params->'key') = 'string' THEN
        _path = ARRAY[_params->>'key'];
    ELSIF jsonb_array_length(_params->'key') > 0
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(_params->'key') k WHERE jsonb_typeof(k) <> 'string') THEN
        _path = ARRAY(SELECT jsonb_array_elements_text(_params->'key'));
    ELSE
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('key must be a string or a non-empty list of strings');
    END IF;

    -- value matches a JSON string equal to it and, when it is a number or boolean, that JSON number or boolean
    _value = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'value', True);
    _values = ARRAY[to_jsonb(_value)];
    _literal = _value;
    IF _value ~ '^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]{1,3})?$' THEN
        _values = _values || to_jsonb(_value::NUMERIC);
        _literal = NULL;
    ELSIF _value IN ('true', 'false') THEN
        _values = _values || to_jsonb(_value::BOOLEAN);
    END IF;

    -- type: "posting" searches posting_json_metadata, "active" json_metadata; default both
    _types = COALESCE(_params->'type', 'null'::JSONB);
    IF jsonb_typeof(_types) = 'null' THEN
        _types = '["posting", "active"]'::JSONB;
    ELSIF jsonb_typeof(_types) = 'string' THEN
        _types = jsonb_build_array(_types);
    END IF;
    IF jsonb_array_length(_types) = 0
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(_types) t WHERE t NOT IN ('"posting"'::JSONB, '"active"'::JSONB)) THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('type must be "posting", "active" or a non-empty list of them');
    END IF;
    _posting = _types @> '["posting"]'::JSONB;
    _active = _types @> '["active"]'::JSONB;

    _last_id = hivemind_postgrest_utilities.find_account_id(
        hivemind_postgrest_utilities.valid_account(
            hivemind_postgrest_utilities.parse_argument_from_json(_params, 'last', False),
            /* allow_empty */ True),
        True);

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    -- No index can cover an arbitrary key, so this walks hive_accounts in id order until _limit
    -- accounts match: a value nobody has set reads the whole table.
    RETURN COALESCE(
      (
        SELECT jsonb_agg(row.name ORDER BY row.id) FROM ( -- bridge_api_query_json_metadata
          SELECT ha.id, ha.name
          FROM hivemind_app.hive_accounts ha
          WHERE ha.id > COALESCE(_last_id, 0)
            AND (
              (_posting AND hivemind_postgrest_utilities.json_metadata_matches(ha.posting_json_metadata, _path, _values, _literal))
              OR (_active AND hivemind_postgrest_utilities.json_metadata_matches(ha.json_metadata, _path, _values, _literal))
            )
          ORDER BY ha.id ASC
          LIMIT _limit
        ) row
      ),
      '[]'::JSONB
    );
END
$$;
