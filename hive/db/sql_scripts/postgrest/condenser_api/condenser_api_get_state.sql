DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_state;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_state(IN _path TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
_parts TEXT[];
_state JSONB;
_ACCOUNT_TAB_KEYS TEXT[] DEFAULT '{blog, feed, comments, recent-replies}';

_field_text_1 TEXT;

BEGIN
  SELECT path, parts FROM hivemind_utilities.gs_normalize_path(_path) AS (path TEXT, parts TEXT[]) INTO _path, _parts;

  -- account (feed, blog, comments, replies)
  IF _parts[1] IS NOT NULL AND position('@' IN _parts[1]) <> 0 THEN
    IF _parts[2] = 'transfers' THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('transfers API not served here');
    END IF;
    IF _parts[3] IS NOT NULL THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('unexpected account path[2] ' || _path);
    END IF;
    IF _parts[2] = '' THEN
      _parts[2] = 'blog';
    END IF;
    -- _field_text_1 - account
    _field_text_1 = hivemind_utilities.valid_account(substring(_parts[1] FROM 2));
    -- in python get state, there is a call _load_account, which calls some others functions and calls something like that. Calling directly that method
    _state = jsonb_set(_state, '{accounts}', hivemind_utilities.gs_get_hive_account_info_view_query_string(_field_text_1));
    IF _parts[2] = ANY(_ACCOUNT_TAB_KEYS) THEN
      
    END IF;
  END IF;
  
  RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('METHOD condenser_api get state is not finished');
END;
$$
;

  --@steemit
  --category/@steemit/firstpost