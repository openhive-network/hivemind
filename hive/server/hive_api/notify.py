"""Hive API: Notifications"""
import logging

from hive.conf import SCHEMA_NAME
from hive.server.common.notify_type import NotifyType
from hive.server.common.helpers import (
    json_date,
    return_error_info,
    valid_account,
    valid_limit,
    valid_number,
    valid_permlink,
    valid_score,
)

log = logging.getLogger(__name__)

STRINGS = {
    # community
    NotifyType.new_community: '<dst> was created',  # no <src> available
    NotifyType.set_role: '<src> set <dst> <payload>',
    NotifyType.set_props: '<src> set properties <payload>',
    NotifyType.set_label: '<src> label <dst> <payload>',
    NotifyType.mute_post: '<src> mute <post> - <payload>',
    NotifyType.unmute_post: '<src> unmute <post> - <payload>',
    NotifyType.pin_post: '<src> pin <post>',
    NotifyType.unpin_post: '<src> unpin <post>',
    NotifyType.flag_post: '<src> flag <post> - <payload>',
    NotifyType.subscribe: '<src> subscribed to <comm>',
    # personal
    NotifyType.error: 'error: <payload>',
    NotifyType.reblog: '<src> reblogged your post',
    NotifyType.follow: '<src> followed you',
    NotifyType.reply: '<src> replied to your post',
    NotifyType.reply_comment: '<src> replied to your comment',
    NotifyType.mention: '<src> mentioned you and <other_mentions> others',
    NotifyType.vote: '<src> voted on your post',
    # NotifyType.update_account: '<dst> updated account',
    # NotifyType.receive:        '<src> sent <dst> <payload>',
    # NotifyType.send:           '<dst> sent <src> <payload>',
    # NotifyType.reward:         '<post> rewarded <payload>',
    # NotifyType.power_up:       '<dst> power up <payload>',
    # NotifyType.power_down:     '<dst> power down <payload>',
    # NotifyType.message:        '<src>: <payload>',
}


@return_error_info
async def unread_notifications(context, account, min_score=25):
    """Load notification status for a named account."""
    db = context['db']
    valid_account(account)
    min_score = valid_score(min_score, 100, 25)

    sql = f"SELECT * FROM {SCHEMA_NAME}.get_number_of_unread_notifications( :account, (:min_score)::SMALLINT)"
    row = await db.query_row(sql, account=account, min_score=min_score)
    return dict(lastread=str(row['lastread_at']), unread=row['unread'])


@return_error_info
async def account_notifications(context, account, min_score=25, last_id=None, limit=100):
    """Load notifications for named account."""
    db = context['db']
    valid_account(account)
    min_score = valid_score(min_score, 100, 25)
    last_id = valid_number(last_id, 0, "last_id")
    limit = valid_limit(limit, 100, 100)

    sql_query = f"SELECT * FROM {SCHEMA_NAME}.account_notifications( (:account)::VARCHAR, (:min_score)::SMALLINT, (:last_id)::BIGINT, (:limit)::SMALLINT )"

    rows = await db.query_all(sql_query, account=account, min_score=min_score, last_id=last_id, limit=limit)
    return [_render(row) for row in rows]


@return_error_info
async def post_notifications(
    context, author: str, permlink: str, min_score: int = 25, last_id: int = None, limit: int = 100
):
    """Load notifications for a specific post."""
    # pylint: disable=too-many-arguments
    db = context['db']
    valid_account(author)
    valid_permlink(permlink)
    min_score = valid_score(min_score, 100, 25)
    last_id = valid_number(last_id, 0, "last_id")
    limit = valid_limit(limit, 100, 100)

    sql_query = f"SELECT * FROM {SCHEMA_NAME}.post_notifications( (:author)::VARCHAR, (:permlink)::VARCHAR, (:min_score)::SMALLINT, (:last_id)::BIGINT, (:limit)::SMALLINT )"

    rows = await db.query_all(
        sql_query, author=author, permlink=permlink, min_score=min_score, last_id=last_id, limit=limit
    )
    return [_render(row) for row in rows]


def _notifs_sql(where):
    sql = f"""SELECT hn.id, hn.type_id, hn.score, hn.created_at,
                    src.name src, dst.name dst,
                    (SELECT name FROM {SCHEMA_NAME}.hive_accounts WHERE id = hp.author_id) as author,
                    (SELECT permlink FROM {SCHEMA_NAME}.hive_permlink_data WHERE id = hp.permlink_id) as permlink,
                    hc.name community,
                    hc.title community_title, payload
               FROM {SCHEMA_NAME}.hive_notifs hn
          LEFT JOIN {SCHEMA_NAME}.hive_accounts src ON hn.src_id = src.id
          LEFT JOIN {SCHEMA_NAME}.hive_accounts dst ON hn.dst_id = dst.id
          LEFT JOIN {SCHEMA_NAME}.hive_posts hp ON hn.post_id = hp.id
          LEFT JOIN {SCHEMA_NAME}.hive_communities hc ON hn.community_id = hc.id
          WHERE %s
            AND score >= :min_score
            AND COALESCE(hp.counter_deleted, 0) = 0
       ORDER BY hn.id DESC
          LIMIT :limit"""
    return sql % where


def _render(row):
    """Convert object to string rep."""
    # src dst payload community post
    out = {
        'id': row['id'],
        'type': NotifyType(row['type_id']).name,
        'score': row['score'],
        'date': json_date(row['created_at']),
        'msg': _render_msg(row),
        'url': _render_url(row),
    }

    # if row['community']:
    #    out['community'] = (row['community'], row['community_title'])

    return out


def _render_msg(row):
    msg = STRINGS[row['type_id']]
    payload = row['payload']
    if row['type_id'] == NotifyType.vote and payload:
        msg += ' <payload>'

    if '<dst>' in msg:
        msg = msg.replace('<dst>', '@' + row['dst'])
    if '<src>' in msg:
        msg = msg.replace('<src>', '@' + row['src'])
    if '<post>' in msg:
        msg = msg.replace('<post>', _post_url(row))
    if '<payload>' in msg:
        msg = msg.replace('<payload>', payload or 'null')
    if '<comm>' in msg:
        msg = msg.replace('<comm>', row['community_title'])
    if '<other_mentions>' in msg:
        msg = msg.replace('<other_mentions>', str(row['number_of_mentions'] - 1))
    return msg


def _post_url(row):
    return '@' + row['author'] + '/' + row['permlink']


def _render_url(row):
    if row['permlink']:
        return '@' + row['author'] + '/' + row['permlink']
    if row['community']:
        return 'trending/' + row['community']
    if row['src']:
        return '@' + row['src']
    if row['dst']:
        return '@' + row['dst']
    assert False, f'no url for {row}'
    return None
