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
                INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id 
                INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id 
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
        sql = """
            SELECT
                hp.id,
                COALESCE(hp.depth, -1)
            FROM
                hive_posts hp
            INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id 
            INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id 
            WHERE ha_a.name = :author AND hpd_p.permlink = :permlink
        """
        pid, depth = DB.query_row(sql, author=author, permlink=permlink)
        return (pid, depth)

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
    def comment_op(cls, op, block_date):
        """Register new/edited/undeleted posts; insert into feed cache."""
        pid = cls.get_id(op['author'], op['permlink'])
        if not pid:
            # post does not exist, go ahead and process it.
            cls.insert(op, block_date)
        elif not cls.is_pid_deleted(pid):
            # post exists, not deleted, thus an edit. ignore.
            cls.update(op, block_date, pid)
        else:
            # post exists but was deleted. time to reinstate.
            cls.undelete(op, block_date, pid)

    @classmethod
    def comment_payout_op(cls, ops, date):
        """ Process comment payment operations """
        for k, v in ops.items():
            author, permlink = k.split("/")
            # total payout to curators
            curator_rewards_sum = 0
            # author payouts
            author_rewards = 0
            author_rewards_hive = 0
            author_rewards_hbd = 0
            author_rewards_vests = 0
            # total payout for comment
            comment_author_reward = None
            for operation in v:
                for op, value in operation.items():
                    if op == 'curation_reward_operation':
                        curator_rewards_sum = curator_rewards_sum + int(value['reward']['amount'])

                    if op == 'author_reward_operation':
                        author_rewards_hive = value['hive_payout']['amount']
                        author_rewards_hbd = value['hbd_payout']['amount']
                        author_rewards_vests = value['vesting_payout']['amount']

                    if op == 'comment_reward_operation':
                        comment_author_reward = value['payout']
                        author_rewards = value['author_rewards']
            curator_rewards = {'amount' : str(curator_rewards_sum), 'precision': 6, 'nai': '@@000000037'}

            sql = """UPDATE
                        hive_posts
                    SET
                        total_payout_value = :total_payout_value,
                        curator_payout_value = :curator_payout_value,
                        author_rewards = :author_rewards,
                        author_rewards_hive = :author_rewards_hive,
                        author_rewards_hbd = :author_rewards_hbd,
                        author_rewards_vests = :author_rewards_vests,
                        last_payout = :last_payout,
                        cashout_time = :cashout_time,
                        is_paidout = true
                    WHERE id = (
                        SELECT hp.id 
                        FROM hive_posts hp 
                        INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id 
                        INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id 
                        WHERE ha_a.name = :author AND hpd_p.permlink = :permlink
                    )
            """
            DB.query(sql, total_payout_value=legacy_amount(comment_author_reward),
                     curator_payout_value=legacy_amount(curator_rewards),
                     author_rewards=author_rewards,
                     author_rewards_hive=author_rewards_hive,
                     author_rewards_hbd=author_rewards_hbd,
                     author_rewards_vests=author_rewards_vests,
                     last_payout=date,
                     cashout_time=date,
                     author=author, permlink=permlink)

    @classmethod
    def insert(cls, op, date):
        """Inserts new post records."""
        # inserting new post
        # * Check for permlink, parent_permlink, root_permlink
        # * Check for authro, parent_author, root_author
        # * check for category data
        # * insert post basic data
        # * obtain id
        # * insert post content data

        sql = """
            SELECT id, author_id, permlink_id, parent_id, community_id, is_valid, is_muted, depth
            FROM add_hive_post((:author)::varchar, (:permlink)::varchar, (:parent_author)::varchar, (:parent_permlink)::varchar, (:date)::timestamp, (:community_support_start_date)::timestamp);
            """

        row = DB.query_row(sql, author=op['author'], permlink=op['permlink'], parent_author=op['parent_author'],
                   parent_permlink=op['parent_permlink'], date=date, community_support_start_date=START_DATE)

        result = dict(row)

        # TODO we need to enhance checking related community post validation and honor is_muted.
        error = cls._verify_post_against_community(op, result['community_id'], result['is_valid'], result['is_muted'])

        cls._set_id(op['author']+'/'+op['permlink'], result['id'])

        # add content data to hive_post_data
        sql = """
            INSERT INTO hive_post_data (id, title, preview, img_url, body, json) 
            VALUES (:id, :title, :preview, :img_url, :body, :json)"""
        DB.query(sql, id=result['id'], title=op['title'],
                 preview=op['preview'] if 'preview' in op else "",
                 img_url=op['img_url'] if 'img_url' in op else "",
                 body=op['body'], json=op['json_metadata'] if op['json_metadata'] else '{}')

        if not DbState.is_initial_sync():
            if error:
                author_id = result['author_id']
                Notify('error', dst_id=author_id, when=date,
                       post_id=result['id'], payload=error).write()
            cls._insert_feed_cache(result)

        if op['parent_author']:
            #update parent child count
            cls.update_child_count(result['id'])

    @classmethod
    def update_child_count(cls, child_id, op='+'):
        """ Increase/decrease child count by 1 """
        sql = """
            UPDATE 
                hive_posts 
            SET 
                children = GREATEST(0, (
                    SELECT 
                        CASE 
                            WHEN children=NULL THEN 0
                            WHEN children=32762 THEN 0
                            ELSE children
                        END
                    FROM 
                        hive_posts
                    WHERE id = (SELECT parent_id FROM hive_posts WHERE id = :child_id)
                )::int
        """
        if op == '+':
            sql += """ + 1)"""
        else:
            sql += """ - 1)"""
        sql += """ WHERE id = (SELECT parent_id FROM hive_posts WHERE id = :child_id)"""

        DB.query(sql, child_id=child_id)

    @classmethod
    def undelete(cls, op, date, pid):
        """Re-allocates an existing record flagged as deleted."""
        # add category to category table

        sql = """
            INSERT INTO 
                hive_category_data (category) 
            VALUES 
                (:category) 
            ON CONFLICT (category) DO NOTHING;
            UPDATE 
                hive_posts 
            SET 
                is_valid = :is_valid,
                is_muted = :is_muted,
                is_deleted = '0',
                is_pinned = '0',
                category_id = (SELECT id FROM hive_category_data WHERE category = :category),
                community_id = :community_id,
                depth = :depth
            WHERE 
                id = :id
        """
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

        pid, depth = cls.get_id_and_depth(op['author'], op['permlink'])
        DB.query("UPDATE hive_posts SET is_deleted = '1' WHERE id = :id", id=pid)

        if not DbState.is_initial_sync():
            if depth == 0:
                # TODO: delete from hive_reblogs -- otherwise feed cache gets 
                # populated with deleted posts somwrimas
                FeedCache.delete(pid)

        # force parent child recount when child is deleted
        cls.update_child_count(pid, '-')

    @classmethod
    def update(cls, op, date, pid):
        """Handle post updates."""
        # pylint: disable=unused-argument
        post = cls._build_post(op, date)

        # add category to category table
        sql = """
            INSERT INTO hive_category_data (category) 
            VALUES (:category) 
            ON CONFLICT (category) DO NOTHING"""
        DB.query(sql, category=post['category'])

        sql = """
            UPDATE hive_posts 
            SET
                category_id = (SELECT id FROM hive_category_data WHERE category = :category),
                community_id = :community_id,
                updated_at = :date,
                depth = :depth,
                is_muted = :is_muted,
                is_valid = :is_valid
            WHERE id = :id
        """

        post['id'] = pid
        DB.query(sql, **post)

        sql = """
            UPDATE 
                hive_post_data 
            SET 
                title = :title, 
                preview = :preview, 
                img_url = :img_url, 
                body = :body, 
                json = :json
            WHERE id = :id
        """

        DB.query(sql, id=pid, title=op['title'],
                 preview=op['preview'] if 'preview' in op else "",
                 img_url=op['img_url'] if 'img_url' in op else "",
                 body=op['body'], json=op['json_metadata'] if op['json_metadata'] else '{}')

    @classmethod
    def update_comment_pending_payouts(cls, hived, posts):
        comment_pending_payouts = hived.get_comment_pending_payouts(posts)
        for comment_pending_payout in comment_pending_payouts:
            if 'cashout_info' in comment_pending_payout:
                cpp = comment_pending_payout['cashout_info']
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
                        WHERE id = (
                            SELECT hp.id 
                            FROM hive_posts hp 
                            INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id 
                            INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id 
                            WHERE ha_a.name = :author AND hpd_p.permlink = :permlink
                        )
                """

                DB.query(sql, total_payout_value=legacy_amount(cpp['total_payout_value']),
                         curator_payout_value=legacy_amount(cpp['curator_payout_value']),
                         max_accepted_payout=legacy_amount(cpp['max_accepted_payout']),
                         author_rewards=cpp['author_rewards'],
                         children_abs_rshares=cpp['children_abs_rshares'],
                         net_rshares=cpp['net_rshares'],
                         abs_rshares=cpp['abs_rshares'],
                         vote_rshares=cpp['vote_rshares'],
                         net_votes=cpp['net_votes'],
                         active=cpp['active'],
                         last_payout=cpp['last_payout'],
                         cashout_time=cpp['cashout_time'],
                         max_cashout_time=cpp['max_cashout_time'],
                         percent_hbd=cpp['percent_hbd'],
                         reward_weight=cpp['reward_weight'],
                         allow_replies=cpp['allow_replies'],
                         allow_votes=cpp['allow_votes'],
                         allow_curation_rewards=cpp['allow_curation_rewards'],
                         author=cpp['author'], permlink=cpp['permlink'])

    @classmethod
    def _insert_feed_cache(cls, result):
        """Insert the new post into feed cache if it's not a comment."""
        if not result['depth']:
            account_id = Accounts.get_id(result['author'])
            cls._insert_feed_cache4(result['depth'], result['id'], account_id, result['date'])

    @classmethod
    def _insert_feed_cache4(cls, post_depth, post_id, author_id, post_date):
        """Insert the new post into feed cache if it's not a comment."""
        if not post_depth:
            FeedCache.insert(post_id, author_id, post_date)

    @classmethod
    def _verify_post_against_community(cls, op, community_id, is_valid, is_muted):
        error = None
        if community_id and is_valid and not Community.is_post_valid(community_id, op):
            error = 'not authorized'
            #is_valid = False # TODO: reserved for future blacklist status?
            is_muted = True
        return error

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
            depth = 0
            category = op['parent_permlink']
            community_id = None
            if date > START_DATE:
                community_id = Community.validated_id(category)
            is_valid = True
            is_muted = False

        # this is a comment; inherit parent props.
        else:
            sql = """
                SELECT depth, hcd.category as category, community_id, is_valid, is_muted
                FROM hive_posts hp 
                INNER JOIN hive_category_data hcd ON hcd.id = hp.category_id
                WHERE hp.id = (
                    SELECT hp1.id 
                    FROM hive_posts hp1 
                    INNER JOIN hive_accounts ha_a ON ha_a.id = hp1.author_id 
                    INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp1.permlink_id 
                    WHERE ha_a.name = :author AND hpd_p.permlink = :permlink
                )
            """
            (parent_depth, category, community_id, is_valid, is_muted) = DB.query_row(sql, author=op['parent_author'], permlink=op['parent_permlink'])
            depth = parent_depth + 1
            if not is_valid:
                error = 'replying to invalid post'
            elif is_muted:
                error = 'replying to muted post'
            #find root comment

        # check post validity in specified context
        error = None
        if community_id and is_valid and not Community.is_post_valid(community_id, op):
            error = 'not authorized'
            #is_valid = False # TODO: reserved for future blacklist status?
            is_muted = True

        ret = dict(id=pid, community_id=community_id,
                   category=category, is_muted=is_muted, is_valid=is_valid,
                   depth=depth, date=date, error=error)

        return ret
