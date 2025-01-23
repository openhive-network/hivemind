DROP FUNCTION IF EXISTS hivemind_app.condenser_get_blog_helper CASCADE;
CREATE FUNCTION hivemind_app.condenser_get_blog_helper( in _blogger VARCHAR, in _last INT, in _limit INT,
                                           out _account_id INT, out _offset INT, out _new_limit INT )
AS
$function$
BEGIN
  _account_id = hivemind_app.find_account_id( _blogger, True );
  IF _last < 0 THEN -- caller wants "most recent" page
      SELECT INTO _last ( SELECT COUNT(1) - 1 FROM hivemind_app.hive_feed_cache hfc WHERE hfc.account_id = _account_id );
      _offset = _last - _limit + 1;
      IF _offset < 0 THEN
        _offset = 0;
      END IF;
      _new_limit = _limit;
  ELSIF _last + 1 < _limit THEN -- bad call, but recoverable
      _offset = 0;
      _new_limit = _last + 1;
  ELSE -- normal call
      _offset = _last - _limit + 1;
      _new_limit = _limit;
  END IF;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.condenser_get_blog;
-- blog posts [ _last - _limit + 1, _last ] oldest first (reverted by caller)
CREATE FUNCTION hivemind_app.condenser_get_blog( in _blogger VARCHAR, in _last INT, in _limit INT )
RETURNS SETOF hivemind_app.condenser_api_post
AS
$function$
DECLARE
  __account_id INT;
  __offset INT;
BEGIN
  SELECT h.* INTO __account_id, __offset, _limit FROM hivemind_app.condenser_get_blog_helper( _blogger, _last, _limit ) h;
  RETURN QUERY SELECT
      hp.id,
      blog.entry_id::INT,
      hp.author,
      hp.permlink,
      hp.author_rep,
      hp.title,
      hp.body,
      hp.category,
      hp.depth,
      hp.payout,
      hp.pending_payout,
      hp.payout_at,
      hp.is_paidout,
      hp.children,
      hp.created_at,
      hp.updated_at,
      (
        CASE hp.author_id = __account_id
          WHEN True THEN '1970-01-01T00:00:00'::timestamp
          ELSE blog.created_at
        END
      ) as reblogged_at,
      hp.rshares,
      hp.json,
      hp.parent_author,
      hp.parent_permlink_or_category,
      hp.curator_payout_value,
      hp.max_accepted_payout,
      hp.percent_hbd,
      hp.beneficiaries,
      hp.url,
      hp.root_title
  FROM
  (
      SELECT
          hfc.created_at, hfc.post_id, row_number() over (ORDER BY hfc.created_at ASC, hfc.post_id ASC) - 1 as entry_id
      FROM
          hivemind_app.hive_feed_cache hfc
      WHERE
          hfc.account_id = __account_id
      ORDER BY hfc.created_at ASC, hfc.post_id ASC
      LIMIT _limit
      OFFSET __offset
  ) as blog,
  LATERAL hivemind_app.get_post_view_by_id(blog.post_id) hp
  ORDER BY blog.created_at ASC, blog.post_id ASC;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.condenser_get_blog_entries;
-- blog entries [ _last - _limit + 1, _last ] oldest first (reverted by caller)
CREATE FUNCTION hivemind_app.condenser_get_blog_entries( in _blogger VARCHAR, in _last INT, in _limit INT )
RETURNS TABLE( entry_id INT, author hivemind_app.hive_accounts.name%TYPE, permlink hivemind_app.hive_permlink_data.permlink%TYPE, reblogged_at TIMESTAMP )
AS
$function$
DECLARE
  __account_id INT;
  __offset INT;
BEGIN
  SELECT h.* INTO __account_id, __offset, _limit FROM hivemind_app.condenser_get_blog_helper( _blogger, _last, _limit ) h;
  RETURN QUERY SELECT
      blog.entry_id::INT,
      ha.name as author,
      hpd.permlink,
      (
        CASE hp.author_id = __account_id
          WHEN True THEN '1970-01-01T00:00:00'::timestamp
          ELSE blog.created_at
        END
      ) as reblogged_at
  FROM
  (
      SELECT
          hfc.created_at, hfc.post_id, row_number() over (ORDER BY hfc.created_at ASC, hfc.post_id ASC) - 1 as entry_id
      FROM
          hivemind_app.hive_feed_cache hfc
      WHERE
          hfc.account_id = __account_id
      ORDER BY hfc.created_at ASC, hfc.post_id ASC
      LIMIT _limit
      OFFSET __offset
  ) as blog
  JOIN hivemind_app.hive_posts hp ON hp.id = blog.post_id
  JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
  JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
  ORDER BY blog.created_at ASC, blog.post_id ASC;
END
$function$
language plpgsql STABLE;

