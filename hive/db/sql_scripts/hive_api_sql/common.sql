DROP FUNCTION IF EXISTS hivemind_helpers.get_community_id;
CREATE OR REPLACE FUNCTION hivemind_helpers.get_community_id(IN name TEXT)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_app.find_community_id(name, TRUE);
END;
$BODY$
;

--SELECT * FROM hivemind_helpers.get_account_id('blocktrades') --HAF 440 Hivemind 441
--SELECT * FROM hivemind_helpers.get_account_id('gtg') --HAF 14007 Hivemind 14008
DROP FUNCTION IF EXISTS hivemind_helpers.get_account_id;
CREATE OR REPLACE FUNCTION hivemind_helpers.get_account_id(IN name TEXT)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_app.find_account_id(name, TRUE);
END;
$BODY$
;
