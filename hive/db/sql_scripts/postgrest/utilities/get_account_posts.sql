DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_blog;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_blog(IN _account TEXT, IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_created_at TIMESTAMP;
BEGIN
  IF _post_id <> 0 THEN
    SELECT hfc.created_at INTO _created_at
    FROM hivemind_app.hive_feed_cache hfc
    WHERE hfc.account_id = _account_id AND hfc.post_id = _post_id;
  END IF;

  RETURN (
    SELECT to_jsonb(result.array) FROM (
      SELECT ARRAY (
        SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, (CASE WHEN row.author <> _account THEN ARRAY[_account] ELSE NULL END), False, True) FROM (
          WITH blog AS MATERIALIZED
          (
            SELECT 
              hfc.post_id,
              hfc.created_at,
              hfc.account_id,
              blacklist.source
            FROM hivemind_app.hive_feed_cache hfc
            LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hfc.account_id)
            WHERE hfc.account_id = _account_id AND NOT ( _post_id <> 0 AND hfc.created_at >= _created_at AND NOT (hfc.created_at = _created_at AND hfc.post_id < _post_id) )
              AND NOT ( _called_from_bridge_api AND EXISTS (
                SELECT NULL FROM hivemind_app.live_posts_comments_view hp1
                WHERE hp1.id = hfc.post_id AND hp1.community_id IS NOT NULL AND NOT EXISTS (
                SELECT NULL FROM hivemind_app.hive_reblogs hr WHERE hr.blogger_id = _account_id AND hr.post_id = hp1.id)
                )
              )
            ORDER BY hfc.created_at DESC, hfc.post_id DESC
            LIMIT _limit
          )
          SELECT
            hp.id,
            hp.author,
            hp.parent_author,
            hp.author_rep,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.parent_permlink_or_category,
            hp.title,
            hp.body,
            hp.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.pending_payout,
            hp.payout_at,
            hp.is_paidout,
            hp.children,
            hp.votes,
            hp.created_at,
            hp.updated_at,
            hp.rshares,
            hp.abs_rshares,
            hp.json,
            hp.is_hidden,
            -- is grayed - if author is muted by observer, make post gray
            CASE
              WHEN hp.is_grayed = FALSE AND _observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id) THEN True
              else hp.is_grayed
            END,
            hp.total_votes,
            hp.sc_trend,
            hp.role_title,
            hp.community_title,
            hp.role_id,
            hp.is_pinned,
            hp.curator_payout_value,
            hp.is_muted,
            blog.source AS blacklists,
            hp.muted_reasons
          FROM blog,
          LATERAL hivemind_app.get_post_view_by_id(blog.post_id) hp
          ORDER BY blog.created_at DESC, blog.post_id DESC
          LIMIT _limit
        ) row
      )
    ) result
  );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_comments;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_comments(IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_posts_should_be_grayed BOOLEAN;
BEGIN
  IF _observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = _account_id) THEN
    _posts_should_be_grayed = True;
  ELSE
    _posts_should_be_grayed = False;
  END IF;

  RETURN (
    SELECT to_jsonb(result.array) FROM (
      SELECT ARRAY (
        SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, False, True) FROM (
          WITH ds AS MATERIALIZED
          (
            SELECT hp1.id, hp1.author_id, blacklist.source
            FROM hivemind_app.live_comments_view hp1
            LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp1.author_id)
            WHERE hp1.author_id = _account_id
              AND NOT ( _post_id <> 0 AND hp1.id >= _post_id)
            ORDER BY hp1.id DESC
            LIMIT _limit
          )
          SELECT
            hp.id,
            hp.author,
            hp.parent_author,
            hp.author_rep,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.parent_permlink_or_category,
            hp.title,
            hp.body,
            hp.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.pending_payout,
            hp.payout_at,
            hp.is_paidout,
            hp.children,
            hp.votes,
            hp.created_at,
            hp.updated_at,
            hp.rshares,
            hp.abs_rshares,
            hp.json,
            hp.is_hidden,
            -- is grayed - if author is muted by observer, make post gray
            hp.is_grayed OR _posts_should_be_grayed AS is_grayed,
            hp.total_votes,
            hp.sc_trend,
            hp.role_title,
            hp.community_title,
            hp.role_id,
            hp.is_pinned,
            hp.curator_payout_value,
            hp.is_muted,
            ds.source AS blacklists,
            hp.muted_reasons
          FROM ds,
          LATERAL hivemind_app.get_post_view_by_id(ds.id) hp
          ORDER BY ds.id DESC
          LIMIT _limit
        ) row
      )
    ) result
  );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_feed;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_feed(IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_min_date TIMESTAMP;
_cutoff INT;
BEGIN
  IF _post_id <> 0 THEN
    SELECT MIN(hfc.created_at) INTO _min_date
    FROM hivemind_app.hive_feed_cache hfc
    JOIN hivemind_app.hive_follows hf ON hfc.account_id = hf.following
    WHERE hf.state = 1 AND hf.follower = _account_id AND hfc.post_id = _post_id;
  END IF;

  _cutoff = hivemind_app.block_before_head( '1 month' );

   RETURN (
      SELECT to_jsonb(result.array) FROM (
        SELECT ARRAY (
          SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, ( CASE WHEN row.reblogged_by IS NOT NULL THEN array_remove(row.reblogged_by, row.author)
                                                                                  ELSE NULL END), False, True) FROM (
            WITH feed AS MATERIALIZED
            (
              SELECT 
                hfc.post_id, 
                MIN(hfc.created_at) as min_created, 
                array_agg(ha.name) AS reblogged_by,
                array_agg(blacklist.source) as blacklist_source
              FROM hivemind_app.hive_feed_cache hfc
              JOIN hivemind_app.hive_follows hf ON hfc.account_id = hf.following
              JOIN hivemind_app.hive_accounts ha ON ha.id = hf.following
              LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hfc.account_id)
              WHERE hfc.block_num > _cutoff AND hf.state = 1 AND hf.follower = _account_id
              AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hfc.account_id))
              GROUP BY hfc.post_id
              HAVING NOT(_post_id <> 0 AND NOT MIN(hfc.created_at) < _min_date AND NOT ( MIN(hfc.created_at) = _min_date AND hfc.post_id < _post_id ))
              ORDER BY min_created DESC, hfc.post_id DESC
              LIMIT _limit
            )
            SELECT
              hp.id,
              hp.author,
              hp.parent_author,
              hp.author_rep,
              hp.root_title,
              hp.beneficiaries,
              hp.max_accepted_payout,
              hp.percent_hbd,
              hp.url,
              hp.permlink,
              hp.parent_permlink_or_category,
              hp.title,
              hp.body,
              hp.category,
              hp.depth,
              hp.promoted,
              hp.payout,
              hp.pending_payout,
              hp.payout_at,
              hp.is_paidout,
              hp.children,
              hp.votes,
              hp.created_at,
              hp.updated_at,
              hp.rshares,
              hp.abs_rshares,
              hp.json,
              hp.is_hidden,
              hp.is_grayed,
              hp.total_votes,
              hp.sc_trend,
              hp.role_title,
              hp.community_title,
              hp.role_id,
              hp.is_pinned,
              hp.curator_payout_value,
              hp.is_muted,
              feed.reblogged_by,
              (SELECT array_to_string(feed.blacklist_source, ',', '')) AS blacklists,
              hp.muted_reasons
            FROM feed,
            LATERAL hivemind_app.get_post_view_by_id(feed.post_id) hp
            ORDER BY feed.min_created DESC, feed.post_id DESC
            LIMIT _limit
          ) row
        )
      ) result
    );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_posts;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_posts(IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_posts_should_be_grayed BOOLEAN;
BEGIN
  IF _observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = _account_id) THEN
    _posts_should_be_grayed = True;
  ELSE
    _posts_should_be_grayed = False;
  END IF;

  RETURN (
    SELECT to_jsonb(result.array) FROM (
      SELECT ARRAY (
        SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, False, True) FROM (
          WITH posts AS MATERIALIZED
          (
            SELECT id, author_id, blacklist.source
            FROM hivemind_app.live_posts_view hp
            LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
            WHERE
              hp.author_id = _account_id
              AND NOT( _post_id <> 0 AND hp.id >= _post_id )
            ORDER BY hp.id DESC
            LIMIT _limit
          )
          SELECT
            hp.id,
            hp.author,
            hp.parent_author,
            hp.author_rep,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.parent_permlink_or_category,
            hp.title,
            hp.body,
            hp.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.pending_payout,
            hp.payout_at,
            hp.is_paidout,
            hp.children,
            hp.votes,
            hp.created_at,
            hp.updated_at,
            hp.rshares,
            hp.abs_rshares,
            hp.json,
            hp.is_hidden,
            -- is grayed - if author is muted by observer, make post gray
            hp.is_grayed OR _posts_should_be_grayed AS is_grayed,
            hp.total_votes,
            hp.sc_trend,
            hp.role_title,
            hp.community_title,
            hp.role_id,
            hp.is_pinned,
            hp.curator_payout_value,
            hp.is_muted,
            posts.source AS blacklists,
            hp.muted_reasons
          FROM posts,
          LATERAL hivemind_app.get_post_view_by_id(posts.id) hp
          ORDER BY posts.id DESC
          LIMIT _limit
        ) row
      )
    ) result
  );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_replies;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_replies(IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _permlink_was_not_empty BOOLEAN, IN _called_from_bridge_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
BEGIN
  IF NOT _called_from_bridge_api and _permlink_was_not_empty THEN
    SELECT pp.author_id INTO _account_id
    FROM hivemind_app.hive_posts hp
    JOIN hivemind_app.hive_posts pp ON hp.parent_id = pp.id
    WHERE hp.id = _post_id;
    IF _account_id = 0 THEN _account_id = NULL; END IF;
  END IF;

  RETURN (
    SELECT to_jsonb(result.array) FROM (
      SELECT ARRAY (
        -- in python code i saw in that case is_pinned should be set, but I couldn't find an example in db to do a test case.
        SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, True, True) FROM (
          WITH replies AS MATERIALIZED
          (
            SELECT hpr.id, blacklist.source
            FROM hivemind_app.live_posts_comments_view hpr
            JOIN hivemind_app.hive_posts hp1 ON hp1.id = hpr.parent_id
            LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp1.author_id)
            WHERE hp1.author_id = _account_id
              AND NOT(_post_id <> 0 AND hpr.id >= _post_id )
              AND NOT (_observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hpr.author_id))
            ORDER BY hpr.id + 1 DESC
            LIMIT _limit
          )
          SELECT
            hp.id,
            hp.author,
            hp.parent_author,
            hp.author_rep,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.parent_permlink_or_category,
            hp.title,
            hp.body,
            hp.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.pending_payout,
            hp.payout_at,
            hp.is_paidout,
            hp.children,
            hp.votes,
            hp.created_at,
            hp.updated_at,
            hp.rshares,
            hp.abs_rshares,
            hp.json,
            hp.is_hidden,
            hp.is_grayed,
            hp.total_votes,
            hp.sc_trend,
            hp.role_title,
            hp.community_title,
            hp.role_id,
            hp.is_pinned,
            hp.curator_payout_value,
            hp.is_muted,
            replies.source AS blacklists,
            hp.muted_reasons
          FROM replies,
          LATERAL hivemind_app.get_post_view_by_id(replies.id) hp
          ORDER BY replies.id DESC
          LIMIT _limit
        ) row
      )
    ) result
  );
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_account_posts_by_payout;
CREATE FUNCTION hivemind_postgrest_utilities.get_account_posts_by_payout(IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_posts_should_be_grayed BOOLEAN;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
BEGIN
  IF _observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = _account_id) THEN
    _posts_should_be_grayed = True;
  ELSE
    _posts_should_be_grayed = False;
  END IF;
  IF _post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO _payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  RETURN (
    SELECT to_jsonb(result.array) FROM (
      SELECT ARRAY (
        SELECT hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, False, True) FROM (
          WITH payouts AS MATERIALIZED
          (  
          SELECT 
            id, author_id,
            (hp.payout + hp.pending_payout) as total_payout,
            blacklist.source
          FROM hivemind_app.live_posts_comments_view hp
          LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (_observer_id != 0 AND blacklist.observer_id = _observer_id AND blacklist.blacklisted_id = hp.author_id)
          WHERE
            hp.author_id = _account_id
            AND NOT hp.is_paidout
            AND NOT( _post_id <> 0 AND (hp.payout + hp.pending_payout) >= _payout_limit AND NOT ((hp.payout + hp.pending_payout) = _payout_limit AND hp.id < _post_id) )
          ORDER BY (hp.payout + hp.pending_payout) DESC, hp.id DESC
          LIMIT _limit
          )
          SELECT
            hp.id,
            hp.author,
            hp.parent_author,
            hp.author_rep,
            hp.root_title,
            hp.beneficiaries,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.url,
            hp.permlink,
            hp.parent_permlink_or_category,
            hp.title,
            hp.body,
            hp.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.pending_payout,
            hp.payout_at,
            hp.is_paidout,
            hp.children,
            hp.votes,
            hp.created_at,
            hp.updated_at,
            hp.rshares,
            hp.abs_rshares,
            hp.json,
            hp.is_hidden,
            -- is grayed - if author is muted by observer, make post gray
            hp.is_grayed OR _posts_should_be_grayed AS is_grayed,
            hp.total_votes,
            hp.sc_trend,
            hp.role_title,
            hp.community_title,
            hp.role_id,
            hp.is_pinned,
            hp.curator_payout_value,
            hp.is_muted,
            payouts.source AS blacklists,
            hp.muted_reasons
          FROM payouts,
          LATERAL hivemind_app.get_post_view_by_id(payouts.id) hp
          ORDER BY payouts.total_payout DESC, payouts.id DESC
          LIMIT _limit
        ) row
      )
    ) result
  );
END
$$
;