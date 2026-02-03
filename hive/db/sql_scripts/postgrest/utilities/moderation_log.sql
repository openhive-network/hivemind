DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_moderation_action_name;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_moderation_action_name(IN _action_id SMALLINT)
RETURNS TEXT
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$function$
BEGIN
  CASE _action_id
    WHEN 1 THEN RETURN 'set_role';
    WHEN 2 THEN RETURN 'set_title';
    WHEN 3 THEN RETURN 'mute_post';
    WHEN 4 THEN RETURN 'unmute_post';
    WHEN 5 THEN RETURN 'pin_post';
    WHEN 6 THEN RETURN 'unpin_post';
    WHEN 7 THEN RETURN 'flag_post';
    ELSE RETURN 'unknown';
  END CASE;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_moderation_action_id;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_moderation_action_id(IN _action_name TEXT)
RETURNS SMALLINT
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$function$
BEGIN
  CASE _action_name
    WHEN 'set_role' THEN RETURN 1;
    WHEN 'set_title' THEN RETURN 2;
    WHEN 'mute_post' THEN RETURN 3;
    WHEN 'unmute_post' THEN RETURN 4;
    WHEN 'pin_post' THEN RETURN 5;
    WHEN 'unpin_post' THEN RETURN 6;
    WHEN 'flag_post' THEN RETURN 7;
    ELSE
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('invalid moderation action type: ' || _action_name);
  END CASE;
END
$function$
;
