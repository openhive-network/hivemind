/** openapi:paths
/sync-status:
  get:
    tags:
      - Other
    summary: Get hivemind''s sync status
    description: |
      Get the last block processed by hivemind as an object containing both
      the block number and its timestamp (UTC). This is the uniform HAF-app
      sync/health endpoint: the timestamp lets a consumer compute staleness
      with a single call (`age = now() - last_block_time`) without needing a
      separate head-block reference.
      `last_block_time` is null if no block has been processed yet.
      While the HAF instance is still in massive sync (indexes not yet
      built) the call fails fast with an error rather than executing an
      unindexed lookup.

      SQL example
      * `SELECT hivemind_endpoints.get_sync_status();`

      REST call example
      * `GET ''https://%1$s/hivemind-api/sync-status''`
    operationId: hivemind_endpoints.get_sync_status
    responses:
      '200':
        description: |
          Last block processed by hivemind and its timestamp.

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: object
              x-sql-datatype: JSON
              properties:
                last_block_num:
                  type: integer
                  description: highest block number processed by hivemind
                last_block_time:
                  type: string
                  format: date-time
                  description: UTC timestamp of that block
            example:
              last_block_num: 5000000
              last_block_time: '2016-09-15T19:47:21'
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_sync_status;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_sync_status()
RETURNS JSON 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  -- No cache - sync status needs real-time accuracy
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=0"}]', true);

  -- Fail fast during HAF massive sync: hafd.blocks' indexes are dropped for
  -- the duration (hive.disable_indexes_of_irreversible), so the blocks_view
  -- lookup below would seq-scan. Health-check agents gate on
  -- is_instance_ready() before calling APIs; this guard protects any caller
  -- that does not (e.g. a raw haproxy httpchk) by erroring in milliseconds.
  IF NOT hive.is_instance_ready() THEN
    RAISE EXCEPTION 'HAF instance is not ready (massive sync in progress)'
      USING ERRCODE = '55000';
  END IF;

  RETURN (
    SELECT json_build_object(
      'last_block_num', c.current_block_num,
      'last_block_time', to_char(b.created_at, 'YYYY-MM-DD"T"HH24:MI:SS')
    )
    FROM hivemind_app.context_data_view c
    LEFT JOIN hivemind_app.blocks_view b ON b.num = c.current_block_num
  );
END
$$;
