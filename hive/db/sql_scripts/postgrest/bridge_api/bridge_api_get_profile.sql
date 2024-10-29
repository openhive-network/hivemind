DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_profile;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_profile(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _observer_id INT;
  _result JSONB;
  _profile JSONB;
  _profile_text_field TEXT;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account","observer"}', '{"string","string"}', 1);
  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True);
  _account = hivemind_postgrest_utilities.valid_account(_account, False);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'observer', 2, False),
      True),
    True);

  SELECT jsonb_build_object(
    'id', row.id,
    'name', row.name,
    'created', hivemind_postgrest_utilities.json_date(row.created_at),
    'active', hivemind_postgrest_utilities.json_date(row.active_at),
    'post_count', row.post_count,
    'reputation', hivemind_postgrest_utilities.rep_log10(row.reputation),
    'blacklists', to_jsonb('{}'::INT[]),
    'stats', jsonb_build_object('rank', row.rank, 'following', row.following, 'followers', row.followers),
    'json_metadata', row.json_metadata,
    'posting_json_metadata', row.posting_json_metadata
    ) FROM (
      SELECT * FROM hivemind_app.hive_accounts_info_view WHERE name = _account
    ) row INTO _result;
  
  IF _result IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Account ''' || _account || ''' does not exist');
  END IF;

  IF _observer_id IS NOT NULL AND _observer_id <> 0 THEN
    -- tmp use _profile to get context
    SELECT jsonb_build_object(
      'followed', (CASE WHEN state = 1 THEN True ELSE False END),
      'muted', (CASE WHEN state = 2 THEN True ELSE False END)
    ) FROM (
      SELECT state FROM hivemind_app.hive_follows WHERE follower = _observer_id AND following = (_result->'id')::INT
    ) row INTO _profile;
    IF _profile IS NOT NULL THEN
      IF NOT (_profile->'muted')::BOOLEAN THEN
        _profile = _profile - 'muted';
      END IF;
      _result = jsonb_set(_result, '{context}', _profile);
      _profile = NULL;
    ELSE
      _result = jsonb_set(_result, '{context}', '{}'::jsonb);
      _result = jsonb_set(_result, '{context,followed}', to_jsonb(False));
    END IF;

  END IF;
  

  IF _result->'posting_json_metadata' IS NOT NULL AND _result->>'posting_json_metadata' <> '' THEN
    BEGIN
      _profile = (_result->>'posting_json_metadata')::jsonb;
      -- In python code, if posting_json_metadata has less then 3 elements, that we should use `json_metadata`, even before reading `profile` part.
      IF (SELECT COUNT(*) FROM jsonb_object_keys(_profile)) < 3 THEN
        _profile = NULL;
      ELSIF _profile ? 'profile' THEN
        _profile = _profile->'profile';
      END IF;
      EXCEPTION WHEN others THEN _profile = NULL;
    END;
  END IF;

  IF _profile IS NULL AND _result->'json_metadata' IS NOT NULL AND _result->>'json_metadata' <> '' THEN
    BEGIN
      _profile = (_result->>'json_metadata')::jsonb;
      IF _profile ? 'profile' THEN
        _profile = _profile->'profile';
      END IF;
    EXCEPTION WHEN others THEN _profile = NULL;
    END;
  END IF;

  _result = _result - 'json_metadata';
  _result = _result - 'posting_json_metadata';
  _result = jsonb_set(_result, '{metadata}', '{}'::jsonb);
  _result = jsonb_set(_result, '{metadata,profile}', '{}'::jsonb);
  _result = jsonb_set(_result, '{metadata,profile,name}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,about}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,location}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,website}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,profile_image}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,cover_image}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,blacklist_description}', to_jsonb(''::TEXT));
  _result = jsonb_set(_result, '{metadata,profile,muted_list_description}', to_jsonb(''::TEXT));

  IF _profile IS NOT NULL THEN
    IF _profile ? 'name' THEN
      _profile_text_field = _profile->>'name';
      IF LEFT(_profile_text_field, 1) <> '@' AND POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 20 THEN
          _profile_text_field = LEFT(_profile_text_field, 17) || '...';
        END IF;
        _result = jsonb_set(_result, '{metadata,profile,name}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'about' THEN
      _profile_text_field = _profile->>'about';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 160 THEN
          _profile_text_field = LEFT(_profile_text_field, 157) || '...';
        END IF;
        _result = jsonb_set(_result, '{metadata,profile,about}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'location' THEN
      _profile_text_field = _profile->>'location';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 30 THEN
          _profile_text_field = LEFT(_profile_text_field, 27) || '...';
        END IF;
        _result = jsonb_set(_result, '{metadata,profile,location}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'website' THEN
      _profile_text_field = _profile->>'website';
      IF LENGTH(_profile_text_field) <= 100 THEN
        IF LEFT(_profile_text_field, 7) <> 'http://' AND LEFT(_profile_text_field, 8) <> 'https://' THEN
          _profile_text_field = 'http://' || _profile_text_field;
        END IF;
        _result = jsonb_set(_result, '{metadata,profile,website}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'blacklist_description' THEN
      _profile_text_field = _profile->>'blacklist_description';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 256 THEN
          _profile_text_field = LEFT(_profile_text_field, 253) || '...';
        END IF;
        _result = jsonb_set(_result, '{metadata,profile,blacklist_description}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'muted_list_description' THEN
      _profile_text_field = _profile->>'muted_list_description';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 256 THEN
          _profile_text_field = LEFT(_profile_text_field, 253) || '...';
        END IF;
        _result = jsonb_set(_result, '{metadata,profile,muted_list_description}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'profile_image' THEN
      _profile_text_field = _profile->>'profile_image';
      IF (LEFT(_profile_text_field, 7) = 'http://' OR LEFT(_profile_text_field, 8) = 'https://') AND LENGTH(_profile_text_field) <= 1024 THEN
        _result = jsonb_set(_result, '{metadata,profile,profile_image}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _profile ? 'cover_image' THEN
      _profile_text_field = _profile->>'cover_image';
      IF (LEFT(_profile_text_field, 7) = 'http://' OR LEFT(_profile_text_field, 8) = 'https://') AND LENGTH(_profile_text_field) <= 1024 THEN
        _result = jsonb_set(_result, '{metadata,profile,cover_image}', to_jsonb(_profile_text_field));
      END IF;
    END IF;
  END IF;

  RETURN _result;
END
$$
;