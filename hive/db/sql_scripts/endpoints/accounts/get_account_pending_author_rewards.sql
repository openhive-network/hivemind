/** openapi:paths
/accounts/{account-name}/pending-author-rewards:
  get:
    tags:
      - blog_api
    summary: Get pending (pre-payout) author rewards for an account.
    description: |
      Returns the aggregated pending author and beneficiary rewards across all
      of the account''s posts that have not yet reached payout (i.e. `is_paidout = false`
      and not deleted). For each unpaid post the gross pending payout is capped by
      `max_accepted_payout` and is split between the author and the beneficiaries.
      Posts that declined payout (`is_declined = true`) contribute zero.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_account_pending_author_rewards(''blocktrades'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/blocktrades/pending-author-rewards''`
    operationId: hivemind_endpoints.get_account_pending_author_rewards
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account to get pending author rewards for.
    responses:
      '200':
        description: |
          Aggregated pending author rewards.

          * Returns `hivemind_endpoints.pending_author_rewards`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.pending_author_rewards'
            example: {
                  "account": "blocktrades",
                  "pending_post_count": 1,
                  "gross_pending_payout": {
                    "amount": "2",
                    "precision": 3,
                    "nai": "@@000000013"
                  },
                  "estimated_author_payout": {
                    "amount": "1",
                    "precision": 3,
                    "nai": "@@000000013"
                  },
                  "estimated_beneficiaries_payout": {
                    "amount": "0",
                    "precision": 3,
                    "nai": "@@000000013"
                  },
                  "estimated_curators_payout": {
                    "amount": "1",
                    "precision": 3,
                    "nai": "@@000000013"
                  }
                }
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_pending_author_rewards;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_pending_author_rewards(
    "account-name" TEXT
)
RETURNS hivemind_endpoints.pending_author_rewards
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _account_id INT := hafah_backend.get_account_id("account-name", TRUE);
  _result hivemind_endpoints.pending_author_rewards;
  _pending_post_count INT;
  _gross NUMERIC;
  _author_payout NUMERIC;
  _beneficiaries_payout NUMERIC;
  _curators_payout NUMERIC;
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  WITH per_post AS (
    SELECT
      CASE
        WHEN hp.is_declined THEN 0::NUMERIC
        ELSE LEAST(hp.payout + hp.pending_payout, mp.amount)
      END AS effective_payout,
      hp.allow_curation_rewards AS allow_curation_rewards,
      COALESCE((
        SELECT SUM((b->>'weight')::NUMERIC)
        FROM json_array_elements(hp.beneficiaries) AS b
      ), 0) AS beneficiary_weight_sum
    FROM hivemind_app.hive_posts hp,
    LATERAL hivemind_postgrest_utilities.parse_asset(hp.max_accepted_payout)
      AS mp(amount NUMERIC, currency hivemind_postgrest_utilities.currency)
    WHERE hp.author_id = _account_id
      AND NOT hp.is_paidout
      AND hp.counter_deleted = 0
  )
  SELECT
    COUNT(*)::INT,
    COALESCE(SUM(effective_payout), 0),
    COALESCE(SUM(
      effective_payout
        * CASE WHEN allow_curation_rewards THEN 0.5 ELSE 1.0 END
        * (1 - beneficiary_weight_sum / 10000)
    ), 0),
    COALESCE(SUM(
      effective_payout
        * CASE WHEN allow_curation_rewards THEN 0.5 ELSE 1.0 END
        * (beneficiary_weight_sum / 10000)
    ), 0),
    COALESCE(SUM(
      effective_payout
        * CASE WHEN allow_curation_rewards THEN 0.5 ELSE 0 END
    ), 0)
  INTO _pending_post_count, _gross, _author_payout, _beneficiaries_payout, _curators_payout
  FROM per_post;

  _result.account := "account-name";
  _result.pending_post_count := _pending_post_count;
  _result.gross_pending_payout := hivemind_postgrest_utilities.to_nai(_gross, 'HBD'::hivemind_postgrest_utilities.currency)::JSON;
  _result.estimated_author_payout := hivemind_postgrest_utilities.to_nai(_author_payout, 'HBD'::hivemind_postgrest_utilities.currency)::JSON;
  _result.estimated_beneficiaries_payout := hivemind_postgrest_utilities.to_nai(_beneficiaries_payout, 'HBD'::hivemind_postgrest_utilities.currency)::JSON;
  _result.estimated_curators_payout := hivemind_postgrest_utilities.to_nai(_curators_payout, 'HBD'::hivemind_postgrest_utilities.currency)::JSON;

  RETURN _result;
END
$$;
