DROP FUNCTION IF EXISTS update_hive_posts_mentions(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION update_hive_posts_mentions(in _first_block INTEGER, in _last_block INTEGER)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  FIRST_BLOCK_TIME TIMESTAMP;
  LAST_BLOCK_TIME TIMESTAMP;
BEGIN

  FIRST_BLOCK_TIME = ( SELECT created_at FROM hive_blocks WHERE num = _first_block );
  LAST_BLOCK_TIME = ( SELECT created_at FROM hive_blocks WHERE num = _last_block );

  IF (LAST_BLOCK_TIME - '90 days'::interval) > FIRST_BLOCK_TIME THEN
    FIRST_BLOCK_TIME = LAST_BLOCK_TIME - '90 days'::interval;
  END IF;

  INSERT INTO hive_mentions( post_id, account_id )
    SELECT DISTINCT T.id_post, ha.id
    FROM
      hive_accounts ha
    INNER JOIN
    (
      SELECT T.id_post, LOWER( ( SELECT trim( T.mention::text, '{""}') ) ) mention, T.author_id
      FROM
      (
        SELECT
          hp.id, REGEXP_MATCHES( hpd.body, '(?:^|[^a-zA-Z0-9_!#$%&*@\\/])(?:@)([a-zA-Z0-9\\.-]{1,16}[a-zA-Z0-9])(?![a-z])', 'g') mention, hp.author_id
        FROM hive_posts hp
          INNER JOIN hive_post_data hpd ON hp.id = hpd.id
        WHERE
        (
          hp.created_at >= FIRST_BLOCK_TIME
        )
      )T( id_post, mention, author_id )
    )T( id_post, mention, author_id ) ON ha.name = T.mention
    WHERE ha.id != T.author_id
  ON CONFLICT DO NOTHING;

END
$function$
;
