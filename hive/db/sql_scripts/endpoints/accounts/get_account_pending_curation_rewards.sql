/** openapi:paths
/accounts/{account-name}/pending-curation-rewards:
  get:
    tags:
      - blog_api
    summary: Get pending (pre-payout) curation rewards for an account.
    description: |
      Returns the aggregated estimated curation reward for the account, summed
      across all of the account''s votes on posts that have not yet reached payout.
      Only votes cast within the last eight chain-days (relative to the head block)
      are considered, matching the chain''s curation reward window. Posts that
      declined payout or disabled curation rewards contribute zero.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_account_pending_curation_rewards(''blocktrades'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/blocktrades/pending-curation-rewards''`
    operationId: hivemind_endpoints.get_account_pending_curation_rewards
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account to get pending curation rewards for.
    responses:
      '200':
        description: |
          Aggregated pending curation rewards.

          * Returns `hivemind_endpoints.pending_curation_rewards`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.pending_curation_rewards'
            example: {
                  "account": "blocktrades",
                  "pending_vote_count": 1,
                  "estimated_curation_payout": {
                    "amount": "1",
                    "precision": 3,
                    "nai": "@@000000013"
                  }
                }
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_pending_curation_rewards;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_pending_curation_rewards(
    "account-name" TEXT
)
RETURNS hivemind_endpoints.pending_curation_rewards
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _account_id INT := hafah_backend.get_account_id("account-name", TRUE);
  _result hivemind_endpoints.pending_curation_rewards;
  _pending_vote_count INT;
  _estimated NUMERIC;
  _head_time TIMESTAMP := hivemind_app.head_block_time();
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  SELECT
    COUNT(*)::INT,
    COALESCE(SUM(
      CASE
        WHEN hp.total_vote_weight > 0
             AND hp.allow_curation_rewards
             AND NOT hp.is_declined
        THEN (hv.weight / hp.total_vote_weight)
             * LEAST(hp.pending_payout, mp.amount)
             / 2
        ELSE 0
      END
    ), 0)::DECIMAL(10,3)
  INTO _pending_vote_count, _estimated
  FROM hivemind_app.hive_votes hv
  JOIN hivemind_app.hive_posts hp ON hp.id = hv.post_id
  CROSS JOIN LATERAL hivemind_postgrest_utilities.parse_asset(hp.max_accepted_payout)
    AS mp(amount NUMERIC, currency hivemind_postgrest_utilities.currency)
  WHERE hv.voter_id = _account_id
    AND NOT hp.is_paidout
    AND hp.counter_deleted = 0
    AND hv.last_update > _head_time - interval '8 days';

  _result.account := "account-name";
  _result.pending_vote_count := _pending_vote_count;
  _result.estimated_curation_payout := hivemind_postgrest_utilities.to_nai(_estimated, 'HBD'::hivemind_postgrest_utilities.currency)::JSON;

  RETURN _result;
END
$$;
