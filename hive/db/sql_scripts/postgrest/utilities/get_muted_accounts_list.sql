DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_muted_accounts_list;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_muted_accounts_list(in _observer_id INT)
RETURNS INT []
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$$
DECLARE
  _muted_accounts INT[];
BEGIN
  _muted_accounts := (
    SELECT 
      array_agg(ma.muted_id) 
    FROM hivemind_app.muted_accounts_by_id_view ma
    WHERE ma.observer_id = _observer_id
  );

  RETURN _muted_accounts;
END
$$;
