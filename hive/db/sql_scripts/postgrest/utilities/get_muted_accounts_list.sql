DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_muted_accounts_list;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_muted_accounts_list(in _haf_id INT)
RETURNS INT []
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  _hivemind_id INT := (SELECT ha.id FROM hivemind_app.hive_accounts ha WHERE haf_id = _observer_id); -- already validated by hafah
  _muted_accounts INT[];
BEGIN
  _muted_accounts := (
    SELECT 
      array_agg(ha.haf_id) 
    FROM hivemind_app.muted_accounts_by_id_view ma
    JOIN hivemind_app.hive_accounts ha ON ha.id = ma.muted_id
    WHERE ma.observer_id = _hivemind_id
  );

  RETURN _muted_accounts;
END
$$;
