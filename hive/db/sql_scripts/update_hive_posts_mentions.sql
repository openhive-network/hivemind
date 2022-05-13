DROP FUNCTION IF EXISTS hivemind_app.update_hive_posts_mentions(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION hivemind_app.update_hive_posts_mentions(in _first_block INTEGER, in _last_block INTEGER)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __block_limit INT := 1200*24*90; --- 1200 blocks is equal to 1hr, so 90 days
BEGIN

  IF (_last_block - __block_limit) > _first_block THEN
    _first_block = _last_block - __block_limit;
  END IF;

  INSERT INTO hivemind_app.hive_mentions( post_id, account_id, block_num )
    SELECT DISTINCT T.id_post, ha.id, T.block_num
    FROM
      hivemind_app.hive_accounts ha
    INNER JOIN
    (
      SELECT T.id_post, LOWER( ( SELECT trim( T.mention::text, '{""}') ) ) AS mention, T.author_id, T.block_num
      FROM
      (
        SELECT
          hp.id, REGEXP_MATCHES( hpd.body, '(?:^|[^a-zA-Z0-9_!#$%&*@\\/])(?:@)([a-zA-Z0-9\\.-]{1,16}[a-zA-Z0-9])(?![a-z])', 'g') AS mention, hp.author_id, hp.block_num
        FROM hivemind_app.hive_posts hp
        INNER JOIN hivemind_app.hive_post_data hpd ON hp.id = hpd.id
        WHERE hp.block_num >= _first_block
      )T( id_post, mention, author_id, block_num )
    )T( id_post, mention, author_id, block_num ) ON ha.name = T.mention
    WHERE ha.id != T.author_id
    ORDER BY T.block_num, T.id_post, ha.id
  ON CONFLICT DO NOTHING;

END
$function$
;
