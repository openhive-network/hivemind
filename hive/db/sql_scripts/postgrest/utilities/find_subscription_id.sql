DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.find_subscription_id;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.find_subscription_id(
    in _account hivemind_app.hive_accounts.name%TYPE,
    in _community_name hivemind_app.hive_communities.name%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _subscription_id INT = 0;
BEGIN
  IF (_account IS NOT NULL OR _account <> '') THEN
    SELECT INTO _subscription_id COALESCE( (
    SELECT hs.id FROM hivemind_app.hive_subscriptions hs
    JOIN hivemind_app.hive_accounts ha ON ha.id = hs.account_id
    JOIN hivemind_app.hive_communities hc ON hc.id = hs.community_id
    WHERE ha.name = _account AND hc.name = _community_name
    ), 0 );
    IF _check AND _subscription_id = 0 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_account || ' subscription on ' || _community_name || ' does not exist');
    END IF;
  END IF;
  RETURN _subscription_id;
END
$function$
;