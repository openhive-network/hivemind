DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.extract_profile_metadata;
CREATE FUNCTION hivemind_postgrest_utilities.extract_profile_metadata(IN _json_metadata TEXT, IN _posting_json_metadata TEXT)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS
$function$
DECLARE
  _profile_text_field TEXT;
  _metadata JSONB;
  _profile JSONB;
BEGIN
  IF _posting_json_metadata IS NOT NULL AND _posting_json_metadata <> '' THEN
    BEGIN
      _metadata = _posting_json_metadata::jsonb;
      -- In python code, if posting_json_metadata has less then 3 elements, that we should use `json_metadata`, even before reading `profile` part.
      IF (SELECT COUNT(*) FROM jsonb_object_keys(_metadata)) < 3 THEN
        _metadata = NULL;
      ELSIF _metadata ? 'profile' THEN
        _metadata = _metadata->'profile';
      END IF;
      EXCEPTION WHEN others THEN _metadata = NULL;
    END;
  END IF;

  IF _metadata IS NULL AND _json_metadata IS NOT NULL AND _json_metadata <> '' THEN
    BEGIN
      _metadata = _json_metadata::jsonb;
      IF _metadata ? 'profile' THEN
        _metadata = _metadata->'profile';
      END IF;
    EXCEPTION WHEN others THEN _metadata = NULL;
    END;
  END IF;

  _profile = jsonb_build_object(
    'profile', jsonb_build_object(
      'name', to_jsonb(''::TEXT),
      'about', to_jsonb(''::TEXT),
      'location', to_jsonb(''::TEXT),
      'website', to_jsonb(''::TEXT),
      'profile_image', to_jsonb(''::TEXT),
      'cover_image', to_jsonb(''::TEXT),
      'blacklist_description', to_jsonb(''::TEXT),
      'muted_list_description', to_jsonb(''::TEXT)
    )
  );

  IF _metadata IS NOT NULL THEN
    IF _metadata ? 'name' THEN
      _profile_text_field = _metadata->>'name';
      IF LEFT(_profile_text_field, 1) <> '@' AND POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 20 THEN
          _profile_text_field = LEFT(_profile_text_field, 17) || '...';
        END IF;
        _profile = jsonb_set(_profile, '{profile,name}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'about' THEN
      _profile_text_field = _metadata->>'about';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 160 THEN
          _profile_text_field = LEFT(_profile_text_field, 157) || '...';
        END IF;
        _profile = jsonb_set(_profile, '{profile,about}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'location' THEN
      _profile_text_field = _metadata->>'location';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 30 THEN
          _profile_text_field = LEFT(_profile_text_field, 27) || '...';
        END IF;
        _profile = jsonb_set(_profile, '{profile,location}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'website' THEN
      _profile_text_field = _metadata->>'website';
      IF LENGTH(_profile_text_field) <= 100 THEN
        IF LEFT(_profile_text_field, 7) <> 'http://' AND LEFT(_profile_text_field, 8) <> 'https://' THEN
          _profile_text_field = 'http://' || _profile_text_field;
        END IF;
        _profile = jsonb_set(_profile, '{profile,website}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'blacklist_description' THEN
      _profile_text_field = _metadata->>'blacklist_description';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 256 THEN
          _profile_text_field = LEFT(_profile_text_field, 253) || '...';
        END IF;
        _profile = jsonb_set(_profile, '{profile,blacklist_description}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'muted_list_description' THEN
      _profile_text_field = _metadata->>'muted_list_description';
      IF POSITION('\x00' IN _profile_text_field) = 0 THEN
        IF LENGTH(_profile_text_field) > 256 THEN
          _profile_text_field = LEFT(_profile_text_field, 253) || '...';
        END IF;
        _profile = jsonb_set(_profile, '{profile,muted_list_description}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'profile_image' THEN
      _profile_text_field = _metadata->>'profile_image';
      IF (LEFT(_profile_text_field, 7) = 'http://' OR LEFT(_profile_text_field, 8) = 'https://') AND LENGTH(_profile_text_field) <= 1024 THEN
        _profile = jsonb_set(_profile, '{profile,profile_image}', to_jsonb(_profile_text_field));
      END IF;
    END IF;

    IF _metadata ? 'cover_image' THEN
      _profile_text_field = _metadata->>'cover_image';
      IF (LEFT(_profile_text_field, 7) = 'http://' OR LEFT(_profile_text_field, 8) = 'https://') AND LENGTH(_profile_text_field) <= 1024 THEN
        _profile = jsonb_set(_profile, '{profile,cover_image}', to_jsonb(_profile_text_field));
      END IF;
    END IF;
  END IF;
  RETURN _profile;
END
$function$
;