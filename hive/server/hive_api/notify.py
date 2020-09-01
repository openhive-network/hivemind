"""Hive API: Notifications"""
import logging

from hive.server.common.helpers import return_error_info, json_date
from hive.indexer.notify import NotifyType
from hive.server.hive_api.common import get_account_id, valid_limit, get_post_id
from hive.server.common.mutes import Mutes

log = logging.getLogger(__name__)

STRINGS = {
    # community
    NotifyType.new_community:  '<dst> was created', # no <src> available
    NotifyType.set_role:       '<src> set <dst> <payload>',
    NotifyType.set_props:      '<src> set properties <payload>',
    NotifyType.set_label:      '<src> label <dst> <payload>',
    NotifyType.mute_post:      '<src> mute <post> - <payload>',
    NotifyType.unmute_post:    '<src> unmute <post> - <payload>',
    NotifyType.pin_post:       '<src> pin <post>',
    NotifyType.unpin_post:     '<src> unpin <post>',
    NotifyType.flag_post:      '<src> flag <post> - <payload>',
    NotifyType.subscribe:      '<src> subscribed to <comm>',

    # personal
    NotifyType.error:          'error: <payload>',
    NotifyType.reblog:         '<src> resteemed your post',
    NotifyType.follow:         '<src> followed you',
    NotifyType.reply:          '<src> replied to your post',
    NotifyType.reply_comment:  '<src> replied to your comment',
    NotifyType.mention:        '<src> mentioned you',
    NotifyType.vote:           '<src> voted on your post',

    #NotifyType.update_account: '<dst> updated account',
    #NotifyType.receive:        '<src> sent <dst> <payload>',
    #NotifyType.send:           '<dst> sent <src> <payload>',

    #NotifyType.reward:         '<post> rewarded <payload>',
    #NotifyType.power_up:       '<dst> power up <payload>',
    #NotifyType.power_down:     '<dst> power down <payload>',
    #NotifyType.message:        '<src>: <payload>',
}

@return_error_info
async def unread_notifications(context, account, min_score=25):
    """Load notification status for a named account."""
    db = context['db']
    account_id = await get_account_id(db, account)

    sql = """SELECT lastread_at,
                    (SELECT COUNT(*) FROM hive_notifs
                      WHERE dst_id = ha.id
                        AND score >= :min_score
                        AND created_at > lastread_at) unread
               FROM hive_accounts ha
              WHERE id = :account_id"""
    row = await db.query_row(sql, account_id=account_id, min_score=min_score)
    return dict(lastread=str(row['lastread_at']), unread=row['unread'])

@return_error_info
async def account_notifications(context, account, min_score=25, last_id=None, limit=100):
    """Load notifications for named account."""
    db = context['db']
    limit = valid_limit(limit, 100)
    account_id = await get_account_id(db, account)

    return await _dynamic_notifications(db = db, limit=limit, min_score=min_score, last_id = last_id, account_id = account_id)

@return_error_info
async def post_notifications(context, author, permlink, min_score=25, last_id=None, limit=100):
    """Load notifications for a specific post."""
    # pylint: disable=too-many-arguments
    db = context['db']
    limit = valid_limit(limit, 100)
    post_id = await get_post_id(db, author, permlink)

    return await _dynamic_notifications(db = db, limit=limit, min_score=min_score, last_id = last_id, post_id = post_id)

def _notifs_sql(where):
    sql = """SELECT hn.id, hn.type_id, hn.score, hn.created_at,
                    src.name src, dst.name dst,
                    (SELECT name FROM hive_accounts WHERE id = hp.author_id) as author,
                    (SELECT permlink FROM hive_permlink_data WHERE id = hp.permlink_id) as permlink,
                    hc.name community,
                    hc.title community_title, payload
               FROM hive_notifs hn
          LEFT JOIN hive_accounts src ON hn.src_id = src.id
          LEFT JOIN hive_accounts dst ON hn.dst_id = dst.id
          LEFT JOIN hive_posts hp ON hn.post_id = hp.id
          LEFT JOIN hive_communities hc ON hn.community_id = hc.id
          WHERE %s
            AND score >= :min_score
            AND COALESCE(hp.counter_deleted, 0) = 0
       ORDER BY hn.id DESC
          LIMIT :limit"""
    return sql % where

def _render(row):
    """Convert object to string rep."""
    # src dst payload community post
    out = {'id': row['id'],
           'type': NotifyType(row['type_id']).name,
           'score': row['score'],
           'date': json_date(row['created_at']),
           'msg': _render_msg(row),
           'url': _render_url(row),
          }

    #if row['community']:
    #    out['community'] = (row['community'], row['community_title'])

    return out

def _render_msg(row):
    msg = STRINGS[row['type_id']]
    payload = row['payload']
    if row['type_id'] == NotifyType.vote and payload:
        amt = float(payload[1:])
        if amt >= 0.01:
            msg += ' (<payload>)'
            payload = "$%.2f" % amt

    if '<dst>' in msg: msg = msg.replace('<dst>', '@' + row['dst'])
    if '<src>' in msg: msg = msg.replace('<src>', '@' + row['src'])
    if '<post>' in msg: msg = msg.replace('<post>', _post_url(row))
    if '<payload>' in msg: msg = msg.replace('<payload>', payload or 'null')
    if '<comm>' in msg: msg = msg.replace('<comm>', row['community_title'])
    return msg

def _post_url(row):
    return '@' + row['author'] + '/' + row['permlink']

def _render_url(row):
    if row['permlink']: return '@' + row['author'] + '/' + row['permlink']
    if row['community']: return 'trending/' + row['community']
    if row['src']: return '@' + row['src']
    if row['dst']: return '@' + row['dst']
    assert False, 'no url for %s' % row
    return None

def _vote_notifs_sql(min_score, account_id = None, post_id = None, last_id = None,  ):
    conditions = ()

    if ( account_id ):
        conditions = conditions + ( "hpv.author_id = {}".format( account_id ), )

    if ( post_id ):
        conditions = conditions + ( "hv1.post_id = {}".format( post_id ), )
    conditions = conditions + ( "hv1.rshares >= 10e9", "ar.abs_rshares != 0",  )
    condition = "WHERE " + ' AND '.join( conditions )

    last_id_where = ""
    if last_id:
        last_id_where = "AND scores.notif_id < {}".format(last_id)

    return """
        SELECT
              scores.notif_id as id
            , 17 as type_id
            , hv.last_update as created_at
            , scores.src as src
            , scores.dst as dst
            , scores.dst as author
            , scores.permlink as permlink
            , '' as community
            , '' as community_title
            , '' as payload
            , scores.score as score
        FROM hive_votes hv
        JOIN (
           SELECT
                  hv1.id as id
                , notification_id(hv1.block_num, 17, CAST( hv1.id as INT) ) as notif_id
                , calculate_notify_vote_score( (hpv.payout + hpv.pending_payout), ar.abs_rshares, hv1.rshares ) as score
                , hpv.author as dst
                , ha.name as src
                , hpv.permlink as permlink
            FROM hive_votes hv1
            JOIN hive_posts_view hpv ON hv1.post_id = hpv.id
            JOIN hive_accounts ha ON ha.id = hv1.voter_id
            JOIN (
            	SELECT
            		  v.post_id as post_id
            		, COALESCE(
              			  SUM( CASE v.rshares >= 0 WHEN True THEN v.rshares ELSE -v.rshares END )
                		, 0
            		) as abs_rshares
            	FROM hive_votes v
                WHERE NOT v.rshares = 0
                GROUP BY v.post_id
            ) as ar ON ar.post_id = hpv.id
            {}
        ) as scores ON scores.id = hv.id
        WHERE scores.score >= {} {}
        """.format( condition, min_score, last_id_where )

def _new_community_notifs_sql( min_score, account_id, last_id = None ):
    last_id_where = ""
    if last_id:
        last_id_where = "AND hc_id.notif_id < {}".format(last_id)

    return """
        SELECT
              hc_id.notif_id as id
            , 1 as type_id
            , hc.created_at as created_at
            , '' as src
            , ha.name as dst
            , '' as author
            , '' as permlink
            , hc.name as community
            , '' as community_title
            , '' as payload
            , 35 as score
        FROM
    	   hive_communities hc
        JOIN hive_accounts ha ON ha.id = hc.id
        JOIN (
            SELECT
                  hc2.id as id
                , notification_id(hc2.block_num, 11, hc2.id) as notif_id
            FROM hive_communities hc2
        ) as hc_id ON hc_id.id = hc.id
    WHERE hc.id={} {}
    """.format( account_id, last_id_where )

def _subsription_notifs_sql( min_score, account_id, last_id = None ):
    last_id_where = ""
    if last_id:
        last_id_where = "AND hs_scores.notif_id < {}".format(last_id)

    return """
        SELECT
              hs_scores.notif_id as id
            , 11 as type_id
            , hs.created_at as created_at
            , hs_scores.src as src
            , ha_com.name as dst
            , '' as author
            , '' as permlink
            , hc.name as community
            , hc.title as community_title
            , '' as payload
            , hs_scores.score
        FROM
            hive_subscriptions hs
            JOIN hive_communities hc ON hs.community_id = hc.id
            JOIN (
                SELECT
                      hs2.id as id
                    , notification_id(hs2.block_num, 11, hs2.id) as notif_id
                    , score_for_account( ha.id ) as score
                    , ha.name as src
                FROM hive_subscriptions hs2
                JOIN hive_accounts ha ON hs2.account_id = ha.id
            ) as hs_scores ON hs_scores.id = hs.id
            JOIN hive_accounts ha_com ON hs.community_id = ha_com.id
        WHERE {} = hs.community_id {}
        """.format( account_id, last_id_where )


def _reblog_notifs_sql( min_score, last_id = None, account_id = None, post_id = None ):
    conditions = ()

    if ( last_id ):
        conditions = conditions + ( "hr_scores.id < {}".format( last_id ), )

    if ( post_id ):
        conditions = conditions + ( "hr.post_id = {}".format( post_id ), )

    if ( account_id ):
        conditions = conditions + ( "hp.author_id = {}".format( account_id ), )

    conditions = conditions + ( "hr_scores.score >= {}".format( min_score ), )

    conditions = "WHERE " + ' AND '.join( conditions )

    sql = """
    SELECT
         hr_scores.notif_id as id
       , 14 as type_id
       , hr.created_at as created_at
       , hr.account as src
       , ha.name as dst
       , ha.name as author
       , hpd.permlink as permlink
       , '' as community
       , '' as community_title
       , '' as payload
       , hr_scores.score as score
    FROM
	    hive_reblogs hr
        JOIN hive_posts hp ON hr.post_id = hp.id
        JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
        JOIN (
            SELECT
                  hr2.id as id
                , notification_id(hr2.block_num, 14, hr2.id) as notif_id
                , score_for_account( has.id ) as score
            FROM hive_reblogs hr2
            JOIN hive_accounts has ON hr2.account = has.name
        ) as hr_scores ON hr_scores.id = hr.id
        JOIN hive_accounts ha ON hp.author_id = ha.id
        {}
    """
    return sql.format( conditions )

def _follow_notifications_sql(min_score, account_id, last_id = None ):
    last_id_where = ""
    if last_id:
        last_id_where = "AND notifs_id.notif_id < {}".format(last_id)
    return """
        SELECT
             notifs_id.notif_id as id
           , 15 as type_id
           , hf.created_at as created_at
           , followers_scores.follower_name as src
           , ha2.name as dst
           , '' as author
           , '' as permlink
           , '' as community
           , '' as community_title
           , '' as payload
           , followers_scores.score as score
        FROM
    	   hive_follows hf
            JOIN hive_accounts ha2 ON hf.following = ha2.id
            JOIN (
                SELECT
                      ha.id as follower_id
                    , ha.name as follower_name
                    , score_for_account( ha.id ) as score
                FROM hive_accounts ha
            ) as followers_scores ON followers_scores.follower_id = hf.follower
            JOIN (
  	         SELECT
  		         hf2.id as id
                 , notification_id(hf2.block_num, 15, hf2.id) as notif_id
             FROM hive_follows hf2
            ) as notifs_id ON notifs_id.id = hf.id
        WHERE {} = hf.following AND score >= {} {}
    """.format( account_id, min_score, last_id_where )


def _replies_notifications_sql( min_score, account_id = None, post_id = None, last_id = None ):
    replies_conditions = ("WHERE hpv.depth > 0".format(min_score),)

    if ( post_id ):
        replies_conditions = replies_conditions + ( "hpv.parent_id = {}".format( post_id ), )

    if ( account_id ):
        replies_conditions = replies_conditions + ( "hpv.parent_author_id = {}".format( account_id ), )

    last_id_where = ""
    if ( last_id ):
        last_id_where = "posts_and_scores.id < {} AND ".format(last_id)

    replies_conditions = ' AND '.join( replies_conditions )

    return """
        SELECT
              posts_and_scores.id as id
            , posts_and_scores.type_id as type_id
            , posts_and_scores.created_at as created_at
            , posts_and_scores.author as src
            , posts_and_scores.parent_author as dst
            , posts_and_scores.author as author
            , posts_and_scores.permlink as permlink
            , '' as community
            , '' as community_title
            , '' as payload
            , posts_and_scores.score as score
        FROM
        (
            SELECT
                  notification_id(
                        block_num
                      , CASE ( hpv.depth )
			               WHEN 1 THEN 12
			               ELSE 13
			            END
                      , hpv.id ) as id
                , CASE ( hpv.depth )
			          WHEN 1 THEN 12
			          ELSE 13
			      END as type_id
                , created_at
                , author
                , parent_author
                , permlink
                , depth
                , parent_author_id
                , author_id
                , score_for_account( hpv.author_id ) as score
            FROM
                hive_posts_view hpv
            {}
        ) as posts_and_scores
        WHERE {} posts_and_scores.score >= {} AND NOT EXISTS(
            SELECT 1
            FROM
            hive_follows hf
            WHERE  hf.follower = posts_and_scores.parent_author_id AND hf.following = posts_and_scores.author_id AND hf.state = 2
        )
        """.format( replies_conditions, last_id_where, min_score )

async def _dynamic_notifications( db, limit, min_score, account_id = None, post_id = None, last_id = None ):
    # posts and account notifs
    sub_queries = ( _replies_notifications_sql( min_score, account_id, post_id, last_id ), )
    sub_queries += ( _reblog_notifs_sql( min_score, account_id, post_id, last_id ), )
    sub_queries += ( _vote_notifs_sql( min_score, account_id, post_id, last_id ), )

    if ( account_id ):
        sub_queries += ( _follow_notifications_sql(min_score, account_id, last_id), )
        sub_queries += ( _subsription_notifs_sql(min_score, account_id, last_id), )
        sub_queries += ( _new_community_notifs_sql(min_score, account_id, last_id), )

    sql_query = ' UNION ALL '.join( sub_queries )
    sql_query += " ORDER BY id DESC, type_id LIMIT {}".format(limit)

    print(sql_query)

    rows = await db.query_all(sql_query)
    rows = [row for row in rows if row['author'] not in Mutes.all()]
    return [_render(row) for row in rows]
