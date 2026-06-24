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
      The response intentionally does not expose final HBD/HIVE/VESTS payout
      assets. Hivemind does not have exact HBD print-rate and reward-vesting
      state, so the endpoint returns only HBD-denominated reward basis values
      split into liquid, vesting, and direct buckets.

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
                  "gross_reward_basis": {
                    "amount": "2000",
                    "precision": 3,
                    "nai": "@@000000013"
                  },
                  "author_reward_basis": {
                    "liquid": {"amount": "500", "precision": 3, "nai": "@@000000013"},
                    "vesting": {"amount": "500", "precision": 3, "nai": "@@000000013"},
                    "direct": {"amount": "0", "precision": 3, "nai": "@@000000013"},
                    "total": {"amount": "1000", "precision": 3, "nai": "@@000000013"}
                  },
                  "beneficiaries_reward_basis": {
                    "liquid": {"amount": "0", "precision": 3, "nai": "@@000000013"},
                    "vesting": {"amount": "0", "precision": 3, "nai": "@@000000013"},
                    "direct": {"amount": "0", "precision": 3, "nai": "@@000000013"},
                    "total": {"amount": "0", "precision": 3, "nai": "@@000000013"}
                  },
                  "curators_reward_basis": {
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
  _author_basis hivemind_postgrest_utilities.pending_reward_basis;
  _beneficiaries_basis hivemind_postgrest_utilities.pending_reward_basis;
  _curators_basis hivemind_postgrest_utilities.pending_reward_basis;
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  -- Consensus payout split (HF21+): 50% curators, 50% (author + beneficiaries).
  -- Older posts use a 75/25 split, but those are filtered out by `NOT is_paidout`
  -- (all pre-HF21 posts are paid out long ago).
  WITH per_post AS (
    SELECT
      hp.id,
      CASE
        WHEN hp.is_declined THEN 0::NUMERIC
        ELSE LEAST(hp.payout + hp.pending_payout, mp.amount)
      END AS effective_payout,
      hp.allow_curation_rewards AS allow_curation_rewards,
      hp.percent_hbd AS percent_hbd,
      hp.beneficiaries AS beneficiaries
    FROM hivemind_app.hive_posts hp,
    LATERAL hivemind_postgrest_utilities.parse_asset(hp.max_accepted_payout)
      AS mp(amount NUMERIC, currency hivemind_postgrest_utilities.currency)
    WHERE hp.author_id = _account_id
      AND NOT hp.is_paidout
      AND hp.counter_deleted = 0
  ),
  post_split AS (
    SELECT
      id,
      effective_payout,
      effective_payout
        * (hivemind_postgrest_utilities.hive_100_percent() - hivemind_postgrest_utilities.hive_curation_rewards_percent())
        / hivemind_postgrest_utilities.hive_100_percent() AS author_pool_reward_basis,
      CASE
        WHEN allow_curation_rewards THEN effective_payout
          * hivemind_postgrest_utilities.hive_curation_rewards_percent()
          / hivemind_postgrest_utilities.hive_100_percent()
        ELSE 0::NUMERIC
      END AS paid_curators_reward_basis,
      percent_hbd,
      beneficiaries
    FROM per_post
  ),
  beneficiary_rows AS (
    SELECT
      ps.id,
      b->>'account' AS account_name,
      ps.percent_hbd,
      ps.author_pool_reward_basis * (b->>'weight')::NUMERIC / hivemind_postgrest_utilities.hive_100_percent()
        AS reward_basis
    FROM post_split ps
    CROSS JOIN LATERAL json_array_elements(ps.beneficiaries) AS b
  ),
  beneficiary_per_post AS (
    SELECT id, COALESCE(SUM(reward_basis), 0) AS reward_basis
    FROM beneficiary_rows
    GROUP BY id
  ),
  author_basis_rows AS (
    SELECT b.*
    FROM post_split ps
    LEFT JOIN beneficiary_per_post bp ON bp.id = ps.id
    CROSS JOIN LATERAL hivemind_postgrest_utilities.pending_author_reward_basis(
      GREATEST(ps.author_pool_reward_basis - COALESCE(bp.reward_basis, 0), 0),
      ps.percent_hbd
    ) AS b
  ),
  beneficiary_basis_rows AS (
    SELECT b.*
    FROM beneficiary_rows br
    CROSS JOIN LATERAL hivemind_postgrest_utilities.pending_author_reward_basis(
      br.reward_basis,
      br.percent_hbd
    ) AS b
    WHERE NOT hivemind_postgrest_utilities.is_hive_treasury_account(br.account_name)
    UNION ALL
    SELECT b.*
    FROM beneficiary_rows br
    CROSS JOIN LATERAL hivemind_postgrest_utilities.pending_direct_reward_basis(
      br.reward_basis
    ) AS b
    WHERE hivemind_postgrest_utilities.is_hive_treasury_account(br.account_name)
  ),
  curator_basis_rows AS (
    SELECT b.*
    FROM post_split ps
    CROSS JOIN LATERAL hivemind_postgrest_utilities.pending_vesting_reward_basis(
      ps.paid_curators_reward_basis
    ) AS b
  ),
  post_summary AS (
    SELECT
      COUNT(*)::INT AS pending_post_count,
      COALESCE(SUM(effective_payout), 0) AS gross
    FROM post_split
  ),
  author_basis AS (
    SELECT ROW(
      COALESCE(SUM(liquid), 0),
      COALESCE(SUM(vesting), 0),
      COALESCE(SUM(direct), 0),
      COALESCE(SUM(total), 0)
    )::hivemind_postgrest_utilities.pending_reward_basis AS basis
    FROM author_basis_rows
  ),
  beneficiary_basis AS (
    SELECT ROW(
      COALESCE(SUM(liquid), 0),
      COALESCE(SUM(vesting), 0),
      COALESCE(SUM(direct), 0),
      COALESCE(SUM(total), 0)
    )::hivemind_postgrest_utilities.pending_reward_basis AS basis
    FROM beneficiary_basis_rows
  ),
  curator_basis AS (
    SELECT ROW(
      COALESCE(SUM(liquid), 0),
      COALESCE(SUM(vesting), 0),
      COALESCE(SUM(direct), 0),
      COALESCE(SUM(total), 0)
    )::hivemind_postgrest_utilities.pending_reward_basis AS basis
    FROM curator_basis_rows
  )
  SELECT
    ps.pending_post_count,
    ps.gross,
    (aa.basis).liquid,
    (aa.basis).vesting,
    (aa.basis).direct,
    (aa.basis).total,
    (ba.basis).liquid,
    (ba.basis).vesting,
    (ba.basis).direct,
    (ba.basis).total,
    (ca.basis).liquid,
    (ca.basis).vesting,
    (ca.basis).direct,
    (ca.basis).total
  INTO
    _pending_post_count,
    _gross,
    _author_basis.liquid,
    _author_basis.vesting,
    _author_basis.direct,
    _author_basis.total,
    _beneficiaries_basis.liquid,
    _beneficiaries_basis.vesting,
    _beneficiaries_basis.direct,
    _beneficiaries_basis.total,
    _curators_basis.liquid,
    _curators_basis.vesting,
    _curators_basis.direct,
    _curators_basis.total
  FROM post_summary ps, author_basis aa, beneficiary_basis ba, curator_basis ca;

  _result.account := "account-name";
  _result.pending_post_count := _pending_post_count;
  _result.gross_reward_basis := hivemind_postgrest_utilities.to_nai(
    hivemind_postgrest_utilities.floor_asset_amount(_gross, 3),
    'HBD'::hivemind_postgrest_utilities.currency
  )::JSON;
  _result.author_reward_basis := hivemind_postgrest_utilities.to_pending_reward_basis_json(_author_basis)::JSON;
  _result.beneficiaries_reward_basis := hivemind_postgrest_utilities.to_pending_reward_basis_json(_beneficiaries_basis)::JSON;
  _result.curators_reward_basis := hivemind_postgrest_utilities.to_pending_reward_basis_json(_curators_basis)::JSON;

  RETURN _result;
END
$$;
