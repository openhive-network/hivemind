"""Routes then builds a get_state response object"""

from collections import OrderedDict

# pylint: disable=line-too-long,too-many-lines
import logging

from hive.conf import SCHEMA_NAME
from hive.server.common.helpers import ApiError, return_error_info, valid_account, valid_permlink, valid_sort, valid_tag
import hive.server.condenser_api.cursor as cursor
from hive.server.condenser_api.methods import get_discussions_by_feed_impl, get_posts_by_given_sort
from hive.server.condenser_api.objects import _condenser_post_object, load_accounts
from hive.server.condenser_api.tags import get_top_trending_tags_summary, get_trending_tags
from hive.server.database_api.methods import find_votes_impl, VotesPresentation

log = logging.getLogger(__name__)

# steemd account 'tabs' - specific post list queries
ACCOUNT_TAB_KEYS = {'blog': 'blog', 'feed': 'feed', 'comments': 'comments', 'recent-replies': 'recent_replies'}

# dummy account paths used by condenser - just need account object
ACCOUNT_TAB_IGNORE = ['followed', 'followers', 'permissions', 'password', 'settings']

# misc dummy paths used by condenser - send minimal get_state structure
CONDENSER_NOOP_URLS = [
    'create_account',
    'approval',
    'recover_account_step_1',
    'recover_account_step_2',
    'submit.html',
    'market',
    'change_password',
    'login.html',
    'welcome',
    'tos.html',
    'privacy.html',
    'support.html',
    'faq.html',
    'about.html',
    'pick_account',
    'waiting_list.html',
]

# post list sorts
POST_LIST_SORTS = [
    'trending',
    'hot',
    'created',
    'payout',
    'payout_comments',
    # unsupported:
    'recent',
    'trending30',
    'active',
    'votes',
    'responses',
    'cashout',
]


@return_error_info
async def get_state(context, path: str):
    """`get_state` reimplementation.

    See: https://github.com/steemit/steem/blob/06e67bd4aea73391123eca99e1a22a8612b0c47e/libraries/app/database_api.cpp#L1937
    """
    (path, part) = _normalize_path(path)

    db = context['db']

    state = {
        'feed_price': {"message": "Not further supported"},
        'props': {"message": "Not further supported"},
        'tags': {},
        'accounts': {},
        'content': {},
        'tag_idx': {'trending': []},
        'discussion_idx': {"": {}},
    }

    # account - `/@account/tab` (feed, blog, comments, replies)
    if part[0] and part[0][0] == '@':
        assert not part[1] == 'transfers', 'transfers API not served here'
        assert not part[2], f'unexpected account path[2] {path}'

        if part[1] == '':
            part[1] = 'blog'

        account = valid_account(part[0][1:])
        state['accounts'][account] = await _load_account(db, account)

        if part[1] in ACCOUNT_TAB_KEYS:
            key = ACCOUNT_TAB_KEYS[part[1]]
            posts = await _get_account_discussion_by_key(db, account, key)
            state['content'] = _keyed_posts(posts)
            state['accounts'][account][key] = list(state['content'].keys())
        elif part[1] in ACCOUNT_TAB_IGNORE:
            pass  # condenser no-op URLs
        else:
            # invalid/undefined case; probably requesting `@user/permlink`,
            # but condenser still relies on a valid response for redirect.
            state['error'] = f'invalid get_state account path {path}'

    # discussion - `/category/@account/permlink`
    elif part[1] and part[1][0] == '@':
        author = valid_account(part[1][1:])
        permlink = valid_permlink(part[2])
        state['content'] = await _load_discussion(db, author, permlink)
        state['accounts'] = await _load_content_accounts(db, state['content'], True)

    # ranked posts - `/sort/category`
    elif part[0] in POST_LIST_SORTS:
        assert not part[2], f"unexpected discussion path part[2] {path}"
        sort = valid_sort(part[0])
        tag = valid_tag(part[1].lower(), allow_empty=True)
        pids = await get_posts_by_given_sort(context, sort, '', '', 20, tag)
        state['content'] = _keyed_posts(pids)
        state['discussion_idx'] = {tag: {sort: list(state['content'].keys())}}
        state['tag_idx'] = {'trending': await get_top_trending_tags_summary(context)}

    # tag "explorer" - `/tags`
    elif part[0] == "tags":
        assert not part[1] and not part[2], 'invalid /tags request'
        for tag in await get_trending_tags(context):
            state['tag_idx']['trending'].append(tag['name'])
            state['tags'][tag['name']] = tag

    elif part[0] in CONDENSER_NOOP_URLS:
        assert not part[1] and not part[2]

    else:
        raise ApiError(f'unhandled path: /{path}')

    return state


async def _get_account_discussion_by_key(db, account, key):
    assert account, 'account must be specified'
    assert key, 'discussion key must be specified'

    if key == 'recent_replies':
        posts = await cursor.get_by_replies_to_account(db, account, '', 20)
    elif key == 'comments':
        posts = await cursor.get_by_account_comments(db, account, '', 20)
    elif key == 'blog':
        posts = await cursor.get_by_blog(db, account, '', '', 20)
    elif key == 'feed':
        posts = await get_discussions_by_feed_impl(db, account, '', '', 20)
    else:
        raise ApiError(f"unknown account discussion key {key}")

    return posts


def _normalize_path(path):
    if path and path[0] == '/':
        path = path[1:]

    # some clients pass the query string to get_state, and steemd allows it :(
    if '?' in path:
        path = path.split('?')[0]

    if not path:
        path = 'trending'
    assert '#' not in path, 'path contains hash mark (#)'
    assert '?' not in path, f'path contains query string: `{path}`'

    parts = path.split('/')
    if len(parts) == 4 and parts[3] == '':
        parts = parts[:-1]
    assert len(parts) < 4, f'too many parts in path: `{path}`'
    while len(parts) < 3:
        parts.append('')
    return (path, parts)


def _keyed_posts(posts):
    out = OrderedDict()
    for post in posts:
        out[_ref(post)] = post
    return out


def _ref(post):
    return post['author'] + '/' + post['permlink']


def _ref_parent(post):
    return post['parent_author'] + '/' + post['parent_permlink']


async def _load_content_accounts(db, content, lite=False):
    if not content:
        return {}
    posts = content.values()
    names = set(map(lambda p: p['author'], posts))
    accounts = await load_accounts(db, names, lite)
    return {a['name']: a for a in accounts}


async def _load_account(db, name):
    ret = await load_accounts(db, [name])
    assert ret, f'account not found: `{name}`'
    account = ret[0]
    for key in ACCOUNT_TAB_KEYS.values():
        account[key] = []
    return account


async def _child_ids(db, parent_ids):
    """Load child ids for multuple parent ids."""
    sql = f"""
             SELECT parent_id, array_agg(id)
               FROM {SCHEMA_NAME}.hive_posts
              WHERE parent_id IN :ids
                AND counter_deleted = 0
           GROUP BY parent_id
    """
    rows = await db.query_all(sql, ids=tuple(parent_ids))
    return [[row[0], row[1]] for row in rows]


async def _load_discussion(db, author, permlink, observer=None):
    """Load a full discussion thread."""

    sql = f"SELECT * FROM {SCHEMA_NAME}.bridge_get_discussion(:author,:permlink,:observer)"
    sql_result = await db.query_all(sql, author=author, permlink=permlink, observer=observer)

    posts = []
    posts_by_id = {}
    replies = {}

    for row in sql_result:
        post = _condenser_post_object(row)

        post['active_votes'] = await find_votes_impl(db, row['author'], row['permlink'], VotesPresentation.CondenserApi)
        posts.append(post)

        parent_key = _ref_parent(post)
        _key = _ref(post)
        if parent_key not in replies:
            replies[parent_key] = []
        replies[parent_key].append(_key)

    for post in posts:
        _key = _ref(post)
        if _key in replies:
            replies[_key].sort()
            post['replies'] = replies[_key]

    for post in posts:
        posts_by_id[_ref(post)] = post

    return posts_by_id
