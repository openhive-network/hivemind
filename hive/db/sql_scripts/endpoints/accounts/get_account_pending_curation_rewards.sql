/** openapi:paths
/accounts/{account-name}/pending-curation-rewards:
  get:
    tags:
      - blog_api
    summary: Get pending (pre-payout) curation rewards for an account.
    description: |
      Returns the aggregated curation reward basis for the account, summed
      across all of the account''s votes on posts that have not yet reached payout.
      Only votes cast within the last eight chain-days (relative to the head block)
      are considered, matching the chain''s curation reward window. Posts that
      declined payout or disabled curation rewards contribute zero.
      Curation rewards resolve to HP/VESTS outside Hivemind. This endpoint returns
      only the HBD-denominated reward basis, not final VESTS/HBD/HIVE payout assets.

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
                  "curation_reward_basis": {
                    "liquid": {"amount": "0", "precision": 3, "nai": "@@000000013"},
                    "vesting": {"amount": "1000", "precision": 3, "nai": "@@000000013"},
                    "direct": {"amount": "0", "precision": 3, "nai": "@@000000013"},
                    "total": {"amount": "1000", "precision": 3, "nai": "@@000000013"}
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
  _basis hivemind_postgrest_utilities.pending_reward_basis;
  _head_time TIMESTAMP := hivemind_app.head_block_time();
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  -- Consensus payout split (HF21+): curators receive 50% of the effective payout,
  -- distributed proportionally by hive_votes.weight / hive_posts.total_vote_weight.
  -- Pre-HF21 posts (75/25 split) are all paid out, so they're filtered by `NOT is_paidout`.
  WITH vote_rows AS (
    SELECT
      CASE
        WHEN hp.total_vote_weight > 0
             AND hp.allow_curation_rewards
             AND NOT hp.is_declined
        THEN (hv.weight / hp.total_vote_weight)
             * LEAST(hp.payout + hp.pending_payout, mp.amount)
             * hivemind_postgrest_utilities.hive_curation_rewards_percent()
             / hivemind_postgrest_utilities.hive_100_percent()
        ELSE 0
      END AS reward_basis
    FROM hivemind_app.hive_votes hv
    JOIN hivemind_app.hive_posts hp ON hp.id = hv.post_id
    CROSS JOIN LATERAL hivemind_postgrest_utilities.parse_asset(hp.max_accepted_payout)
      AS mp(amount NUMERIC, currency hivemind_postgrest_utilities.currency)
    WHERE hv.voter_id = _account_id
      AND NOT hp.is_paidout
      AND hp.counter_deleted = 0
      AND hv.last_update > _head_time - interval '8 days'
  ),
  basis_rows AS (
    SELECT b.*
    FROM vote_rows vr
    CROSS JOIN LATERAL hivemind_postgrest_utilities.pending_vesting_reward_basis(
      vr.reward_basis
    ) AS b
  ),
  basis_totals AS (
    SELECT ROW(
      COALESCE(SUM(liquid), 0),
      COALESCE(SUM(vesting), 0),
      COALESCE(SUM(direct), 0),
      COALESCE(SUM(total), 0)
    )::hivemind_postgrest_utilities.pending_reward_basis AS basis
    FROM basis_rows
  )
  SELECT
    (SELECT COUNT(*)::INT FROM vote_rows),
    (basis_totals.basis).liquid,
    (basis_totals.basis).vesting,
    (basis_totals.basis).direct,
    (basis_totals.basis).total
  INTO
    _pending_vote_count,
    _basis.liquid,
    _basis.vesting,
    _basis.direct,
    _basis.total
  FROM basis_totals;

  _result.account := "account-name";
  _result.pending_vote_count := _pending_vote_count;
  _result.curation_reward_basis := hivemind_postgrest_utilities.to_pending_reward_basis_json(_basis)::JSON;

  RETURN _result;
END
$$;
