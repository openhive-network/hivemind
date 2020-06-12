"""Core posts manager."""

import logging
import collections

from json import dumps

from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.community import Community, START_DATE
from hive.indexer.notify import Notify
from hive.utils.normalize import legacy_amount, asset_to_hbd_hive

log = logging.getLogger(__name__)
DB = Db.instance()

class Posts:
    """Handles critical/core post ops and data."""

    # LRU cache for (author-permlink -> id) lookup (~400mb per 1M entries)
    CACHE_SIZE = 2000000
    _ids = collections.OrderedDict()
    _hits = 0
    _miss = 0

    @classmethod
    def last_id(cls):
        """Get the last indexed post id."""
        sql = "SELECT MAX(id) FROM hive_posts WHERE is_deleted = '0'"
        return DB.query_one(sql) or 0

    @classmethod
    def find_root(cls, author, permlink):
        """ Find root for post """
        print("A: ", author, "P: ", permlink)

        sql = """WITH RECURSIVE parent AS
        (
            SELECT id, parent_id, 1 AS level from hive_posts WHERE id = (SELECT hp.id 
                FROM hive_posts hp 
                LEFT JOIN hive_accounts ha_a ON ha_a.id = hp.author_id 
                LEFT JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id 
                WHERE ha_a.name = :a AND hpd_p.permlink = :p)
            UNION ALL 
            SELECT t.id, t.parent_id, level + 1 FROM parent
            INNER JOIN hive_posts t ON t.id =  parent.parent_id
        )
        SELECT id FROM parent ORDER BY level DESC LIMIT 1"""
        _id = DB.query_one(sql, a=author, p=permlink)
        return _id

    @classmethod
    def get_id(cls, author, permlink):
        """Look up id by author/permlink, making use of LRU cache."""
        url = author+'/'+permlink
        if url in cls._ids:
            cls._hits += 1
            _id = cls._ids.pop(url)
            cls._ids[url] = _id
        else:
            cls._miss += 1
            sql = """
                SELECT hp.id 
                FROM hive_posts hp 
                LEFT JOIN hive_accounts ha_a ON ha_a.id = hp.author_id 
                LEFT JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id 
                WHERE ha_a.name = :a AND hpd_p.permlink = :p
            """
            _id = DB.query_one(sql, a=author, p=permlink)
            if _id:
                cls._set_id(url, _id)

        # cache stats (under 10M every 10K else every 100K)
        total = cls._hits + cls._miss
        if total % 100000 == 0:
            log.info("pid lookups: %d, hits: %d (%.1f%%), entries: %d",
                     total, cls._hits, 100.0*cls._hits/total, len(cls._ids))

        return _id

    @classmethod
    def _set_id(cls, url, pid):
        """Add an entry to the LRU, maintaining max size."""
        assert pid, "no pid provided for %s" % url
        if len(cls._ids) > cls.CACHE_SIZE:
            cls._ids.popitem(last=False)
        cls._ids[url] = pid

    @classmethod
    def save_ids_from_tuples(cls, tuples):
        """Skim & cache `author/permlink -> id` from external queries."""
        for tup in tuples:
            pid, author, permlink = (tup[0], tup[1], tup[2])
            url = author+'/'+permlink
            if not url in cls._ids:
                cls._set_id(url, pid)
        return tuples

    @classmethod
    def get_id_and_depth(cls, author, permlink):
        """Get the id and depth of @author/permlink post."""
        _id = cls.get_id(author, permlink)
        if not _id:
            return (None, -1)
        depth = DB.query_one("SELECT depth FROM hive_posts WHERE id = :id", id=_id)
        return (_id, depth)

    @classmethod
    def is_pid_deleted(cls, pid):
        """Check if the state of post is deleted."""
        sql = "SELECT is_deleted FROM hive_posts WHERE id = :id"
        return DB.query_one(sql, id=pid)

    @classmethod
    def delete_op(cls, op):
        """Given a delete_comment op, mark the post as deleted.

        Also remove it from post-cache and feed-cache.
        """
        cls.delete(op)

    @classmethod
    def comment_op(cls, hived, op, block_date):
        """Register new/edited/undeleted posts; insert into feed cache."""
        pid = cls.get_id(op['author'], op['permlink'])
        if not pid:
            # post does not exist, go ahead and process it.
            cls.insert(hived, op, block_date)
        elif not cls.is_pid_deleted(pid):
            # post exists, not deleted, thus an edit. ignore.
            cls.update(hived, op, block_date, pid)
        else:
            # post exists but was deleted. time to reinstate.
            cls.undelete(op, block_date, pid)

    @classmethod
    def vote_op(cls, hived, op):
        """ Vote operation processing """
        pid = cls.get_id(op['author'], op['permlink'])
        assert pid, "Post does not exists in the database"
        votes = hived.get_votes(op['author'], op['permlink'])
        sql = """
            UPDATE 
                hive_post_data 
            SET 
                votes = :votes
            WHERE id = :id"""

        DB.query(sql, id=pid, votes=dumps(votes))

    @classmethod
    def comment_payout_op(cls, ops, date, price):
        """ Process comment payment operations """
        for k, v in ops.items():
            author, permlink = k.split("/")
            pid = cls.get_id(author, permlink)
            curator_rewards_sum = 0
            author_rewards_sum = 0
            comment_author_reward = None
            for operation in v:
                for op, value in operation.items():
                    if op == 'curation_reward_operation':
                        curator_rewards_sum = curator_rewards_sum + int(value['reward']['amount'])
                    if op == 'author_reward_operation':
                        hive_to_hbd = asset_to_hbd_hive(price, value['hive_payout'])
                        author_rewards_sum = int(hive_to_hbd['amount']) + int(value['hbd_payout']['amount'])
                    if op == 'comment_reward_operation':
                        comment_author_reward = value['payout']
            curator_rewards = {'amount' : str(curator_rewards_sum), 'precision': 6, 'nai': '@@000000037'}
            sql = """UPDATE
                        hive_posts
                    SET
                        total_payout_value = :total_payout_value,
                        curator_payout_value = :curator_payout_value,
                        author_rewards = :author_rewards,
                        last_payout = :last_payout,
                        cashout_time = :cashout_time,
                        is_paidout = true
                    WHERE id = :id
            """
            DB.query(sql, total_payout_value=legacy_amount(comment_author_reward),
                     curator_payout_value=legacy_amount(curator_rewards),
                     author_rewards=author_rewards_sum, last_payout=date,
                     cashout_time=date, id=pid)

    @classmethod
    def insert(cls, hived, op, date):
        """Inserts new post records."""
        print("New Post")

        # inserting new post
        # * Check for permlink, parent_permlink, root_permlink
        # * Check for authro, parent_author, root_author
        # * check for category data
        # * insert post basic data
        # * obtain id
        # * insert post content data

        # add permlinks to permlink table
        for permlink in ['permlink', 'parent_permlink', 'root_permlink']:
            if permlink in op:
                sql = """
                    INSERT INTO hive_permlink_data (permlink) 
                    VALUES (:permlink) 
                    ON CONFLICT (permlink) DO NOTHING"""
                DB.query(sql, permlink=op[permlink])

        post = cls._build_post(op, date)

        # add category to category table
        sql = """
            INSERT INTO hive_category_data (category) 
            VALUES (:category) 
            ON CONFLICT (category) DO NOTHING"""
        DB.query(sql, category=post['category'])

        sql = """
            INSERT INTO hive_posts (parent_id, author_id, permlink_id,
                category_id, community_id, created_at, depth, is_muted, 
                is_valid, parent_author_id, parent_permlink_id, root_author_id, root_permlink_id)
            VALUES (:parent_id, 
                (SELECT id FROM hive_accounts WHERE name = :author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :permlink),
                (SELECT id FROM hive_category_data WHERE category = :category),
                :community_id, :date, :depth,
                :is_muted, :is_valid, 
                (SELECT id FROM hive_accounts WHERE name = :parent_author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :parent_permlink),
                (SELECT id FROM hive_accounts WHERE name = :root_author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :root_permlink)
            )"""
        sql += ";SELECT currval(pg_get_serial_sequence('hive_posts','id'))"

        result = DB.query(sql, **post)
        post['id'] = int(list(result)[0][0])
        cls._set_id(op['author']+'/'+op['permlink'], post['id'])

        comment_pending_payouts = hived.get_comment_pending_payouts([[op['author'], op['permlink']]])
        if comment_pending_payouts and 'cashout_info' in comment_pending_payouts[0]:
            sql = """UPDATE
                        hive_posts
                    SET
                        total_payout_value = :total_payout_value,
                        curator_payout_value = :curator_payout_value,
                        max_accepted_payout = :max_accepted_payout,
                        author_rewards = :author_rewards,
                        children_abs_rshares = :children_abs_rshares,
                        rshares = :net_rshares,
                        abs_rshares = :abs_rshares,
                        vote_rshares = :vote_rshares,
                        net_votes = :net_votes,
                        active = :active,
                        last_payout = :last_payout,
                        cashout_time = :cashout_time,
                        max_cashout_time = :max_cashout_time,
                        percent_hbd = :percent_hbd,
                        reward_weight = :reward_weight,
                        allow_replies = :allow_replies,
                        allow_votes = :allow_votes,
                        allow_curation_rewards = :allow_curation_rewards
                    WHERE id = :id
            """
            DB.query(sql, total_payout_value=legacy_amount(comment_pending_payouts['cashout_info']['total_payout_value']),
                    curator_payout_value=legacy_amount(comment_pending_payouts['cashout_info']['curator_payout_value']),
                    max_accepted_payout=legacy_amount(comment_pending_payouts['cashout_info']['max_accepted_payout']),
                    author_rewards=comment_pending_payouts['cashout_info']['author_rewards'],
                    children_abs_rshares=comment_pending_payouts['cashout_info']['children_abs_rshares'],
                    net_rshares=comment_pending_payouts['cashout_info']['net_rshares'],
                    abs_rshares=comment_pending_payouts['cashout_info']['abs_rshares'],
                    vote_rshares=comment_pending_payouts['cashout_info']['vote_rshares'],
                    net_votes=comment_pending_payouts['cashout_info']['net_votes'],
                    active=comment_pending_payouts['cashout_info']['active'],
                    last_payout=comment_pending_payouts['cashout_info']['last_payout'],
                    cashout_time=comment_pending_payouts['cashout_info']['cashout_time'],
                    max_cashout_time=comment_pending_payouts['cashout_info']['max_cashout_time'],
                    percent_hbd=comment_pending_payouts['cashout_info']['percent_hbd'],
                    reward_weight=comment_pending_payouts['cashout_info']['reward_weight'],
                    allow_replies=comment_pending_payouts['cashout_info']['allow_replies'],
                    allow_votes=comment_pending_payouts['cashout_info']['allow_votes'],
                    allow_curation_rewards=comment_pending_payouts['cashout_info']['allow_curation_rewards'],
                    id=post['id']
            )

        # add content data to hive_post_data
        votes = hived.get_votes(op['author'], op['permlink'])
        sql = """
            INSERT INTO hive_post_data (id, title, preview, img_url, body, 
                votes, json) 
            VALUES (:id, :title, :preview, :img_url, :body, :votes, :json)"""
        DB.query(sql, id=post['id'], title=op['title'],
                 preview=op['preview'] if 'preview' in op else "",
                 img_url=op['img_url'] if 'img_url' in op else "",
                 body=op['body'], votes=dumps(votes),
                 json=op['json_metadata'] if op['json_metadata'] else '{}')

        if not DbState.is_initial_sync():
            if post['error']:
                author_id = Accounts.get_id(post['author'])
                Notify('error', dst_id=author_id, when=date,
                       post_id=post['id'], payload=post['error']).write()
            if op['parent_author']: # update parent's child count
                cls.update_child_count(post['parent_id'])
            cls._insert_feed_cache(post)

    @classmethod
    def update_child_count(cls, parent_id, op='+'):
        """ Increase/decrease child count by 1 """
        sql = """
            UPDATE 
                hive_posts 
            SET """
        if op == '+':
            sql += """children = (SELECT children FROM hive_posts WHERE id = :id) + 1"""
        else:
            sql += """children = (SELECT children FROM hive_posts WHERE id = :id) - 1"""
        sql += """ WHERE id = :id"""
        DB.query(sql, id=parent_id)

    @classmethod
    def undelete(cls, op, date, pid):
        """Re-allocates an existing record flagged as deleted."""
        print("Undelete")
        # add category to category table
        if 'category' in op:
            sql = """
                INSERT INTO hive_category_data (category) 
                VALUES (:category) 
                ON CONFLICT (category) DO NOTHING"""
            DB.query(sql, category=op['category'])

        sql = """UPDATE hive_posts SET is_valid = :is_valid,
                   is_muted = :is_muted, is_deleted = '0', is_pinned = '0',
                   parent_id = :parent_id, category_id = (SELECT id FROM hive_category_data WHERE category = :category),
                   community_id = :community_id, depth = :depth
                 WHERE id = :id"""
        post = cls._build_post(op, date, pid)
        DB.query(sql, **post)

        if not DbState.is_initial_sync():
            if post['error']:
                author_id = Accounts.get_id(post['author'])
                Notify('error', dst_id=author_id, when=date,
                       post_id=post['id'], payload=post['error']).write()
            cls._insert_feed_cache(post)

    @classmethod
    def delete(cls, op):
        """Marks a post record as being deleted."""
        print("Delete post")

        pid, depth = cls.get_id_and_depth(op['author'], op['permlink'])
        DB.query("UPDATE hive_posts SET is_deleted = '1' WHERE id = :id", id=pid)

        if not DbState.is_initial_sync():
            if depth == 0:
                # TODO: delete from hive_reblogs -- otherwise feed cache gets 
                # populated with deleted posts somwrimas
                FeedCache.delete(pid)
            else:
                # force parent child recount when child is deleted
                prnt = cls._get_parent_by_child_id(pid)
                cls.update_child_count(prnt['id'], '-')

    @classmethod
    def update(cls, hived, op, date, pid):
        """Handle post updates.

        Here we could also build content diffs, but for now just used
        a signal to update cache record.
        """
        print("Update post")
        # pylint: disable=unused-argument

        # add category to category table
        if 'category' in op:
            sql = """
                INSERT INTO hive_category_data (category) 
                VALUES (:category) 
                ON CONFLICT (category) DO NOTHING"""
            DB.query(sql, category=op['category'])

        sql = """
            UPDATE hive_posts 
            SET
                parent_id = :parent_id,
                author_id = (SELECT id FROM hive_accounts WHERE name = :author),
                permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink),
                category_id = (SELECT id FROM hive_category_data WHERE category = :category),
                community_id = :community_id,
                updated_at = :date,
                depth = :depth,
                is_muted = :is_muted,
                is_valid = :is_valid,
                parent_author_id = (SELECT id FROM hive_accounts WHERE name = :parent_author),
                parent_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :parent_permlink)
            WHERE id = :id"""
        post = cls._build_post(op, date)
        post['id'] = pid
        DB.query(sql, **post)

        comment_pending_payouts = hived.get_comment_pending_payouts([[op['author'], op['permlink']]])
        if comment_pending_payouts and 'cashout_info' in comment_pending_payouts[0]:
            sql = """UPDATE
                        hive_posts
                    SET
                        total_payout_value = :total_payout_value,
                        curator_payout_value = :curator_payout_value,
                        max_accepted_payout = :max_accepted_payout,
                        author_rewards = :author_rewards,
                        children_abs_rshares = :children_abs_rshares,
                        rshares = :net_rshares,
                        abs_rshares = :abs_rshares,
                        vote_rshares = :vote_rshares,
                        net_votes = :net_votes,
                        active = :active,
                        last_payout = :last_payout,
                        cashout_time = :cashout_time,
                        max_cashout_time = :max_cashout_time,
                        percent_hbd = :percent_hbd,
                        reward_weight = :reward_weight,
                        allow_replies = :allow_replies,
                        allow_votes = :allow_votes,
                        allow_curation_rewards = :allow_curation_rewards
                    WHERE id = :id
            """
            DB.query(sql, total_payout_value=legacy_amount(comment_pending_payouts['cashout_info']['total_payout_value']),
                    curator_payout_value=legacy_amount(comment_pending_payouts['cashout_info']['curator_payout_value']),
                    max_accepted_payout=legacy_amount(comment_pending_payouts['cashout_info']['max_accepted_payout']),
                    author_rewards=comment_pending_payouts['cashout_info']['author_rewards'],
                    children_abs_rshares=comment_pending_payouts['cashout_info']['children_abs_rshares'],
                    net_rshares=comment_pending_payouts['cashout_info']['net_rshares'],
                    abs_rshares=comment_pending_payouts['cashout_info']['abs_rshares'],
                    vote_rshares=comment_pending_payouts['cashout_info']['vote_rshares'],
                    net_votes=comment_pending_payouts['cashout_info']['net_votes'],
                    active=comment_pending_payouts['cashout_info']['active'],
                    last_payout=comment_pending_payouts['cashout_info']['last_payout'],
                    cashout_time=comment_pending_payouts['cashout_info']['cashout_time'],
                    max_cashout_time=comment_pending_payouts['cashout_info']['max_cashout_time'],
                    percent_hbd=comment_pending_payouts['cashout_info']['percent_hbd'],
                    reward_weight=comment_pending_payouts['cashout_info']['reward_weight'],
                    allow_replies=comment_pending_payouts['cashout_info']['allow_replies'],
                    allow_votes=comment_pending_payouts['cashout_info']['allow_votes'],
                    allow_curation_rewards=comment_pending_payouts['cashout_info']['allow_curation_rewards'],
                    id=pid
            )

        sql = """
            UPDATE 
                hive_post_data 
            SET 
                title = :title, 
                preview = :preview, 
                img_url = :img_url, 
                body = :body, 
                json = :json
            WHERE id = :id"""

        DB.query(sql, id=pid, title=op['title'],
                 preview=op['preview'] if 'preview' in op else "",
                 img_url=op['img_url'] if 'img_url' in op else "",
                 body=op['body'],
                 json=op['json_metadata'] if op['json_metadata'] else '{}')

    @classmethod
    def _get_parent_by_child_id(cls, child_id):
        """Get parent's `id`, `author`, `permlink` by child id."""
        sql = """
            SELECT 
                hp.id, ha_a.name as author, hpd_p.permlink as permlink
            FROM 
                hive_posts hp
            LEFT JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
            LEFT JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
            WHERE 
                hp.id = (SELECT parent_id FROM hive_posts WHERE id = :child_id)"""
        result = DB.query_row(sql, child_id=child_id)
        assert result, "parent of %d not found" % child_id
        return result

    @classmethod
    def _insert_feed_cache(cls, post):
        """Insert the new post into feed cache if it's not a comment."""
        if not post['depth']:
            account_id = Accounts.get_id(post['author'])
            FeedCache.insert(post['id'], account_id, post['date'])

    @classmethod
    def _build_post(cls, op, date, pid=None):
        """Validate and normalize a post operation.

        Post is muted if:
         - parent was muted
         - author unauthorized

        Post is invalid if:
         - parent is invalid
         - author unauthorized
        """
        # TODO: non-nsfw post in nsfw community is `invalid`

        # if this is a top-level post:
        if not op['parent_author']:
            parent_id = None
            depth = 0
            category = op['parent_permlink']
            community_id = None
            if date > START_DATE:
                community_id = Community.validated_id(category)
            is_valid = True
            is_muted = False
            root_author = op['author']
            root_permlink = op['permlink']

        # this is a comment; inherit parent props.
        else:
            parent_id = cls.get_id(op['parent_author'], op['parent_permlink'])
            sql = """
                SELECT depth, hcd.category as category, community_id, is_valid, is_muted
                FROM hive_posts hp 
                LEFT JOIN hive_category_data hcd ON hcd.id = hp.category_id
                WHERE hp.id = :id"""
            (parent_depth, category, community_id, is_valid,
             is_muted) = DB.query_row(sql, id=parent_id)
            depth = parent_depth + 1
            if not is_valid: error = 'replying to invalid post'
            elif is_muted: error = 'replying to muted post'
            #find root comment
            root_id = cls.find_root(op['parent_author'], op['parent_permlink'])
            sql = """
                SELECT 
                    ha_a.name as author, hpd_p.permlink as permlink
                FROM 
                    hive_posts hp
                LEFT JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
                LEFT JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
                WHERE 
                    hp.id = :id"""
            root_author, root_permlink = DB.query_row(sql, id=root_id)

        # check post validity in specified context
        error = None
        if community_id and is_valid and not Community.is_post_valid(community_id, op):
            error = 'not authorized'
            #is_valid = False # TODO: reserved for future blacklist status?
            is_muted = True

        ret = dict(parent_id=parent_id, id=pid, community_id=community_id,
                   category=category, is_muted=is_muted, is_valid=is_valid,
                   depth=depth, date=date, error=error,
                   author=op['author'], permlink=op['permlink'],
                   parent_author=op['parent_author'],
                   parent_permlink=op['parent_permlink'],
                   root_permlink=root_permlink,
                   root_author=root_author)

        return ret
