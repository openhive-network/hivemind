"""Core posts manager."""

import logging
import collections

from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.cached_post import CachedPost
from hive.indexer.feed_cache import FeedCache
from hive.indexer.community import Community, START_DATE
from hive.indexer.notify import Notify

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
                SELECT id 
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
    def insert(cls, op, date):
        """Inserts new post records."""

        # inserting new post
        # * Check for permlink, parent_permlink, root_permlink
        # * Check for authro, parent_author, root_author
        # * check for category data
        # * insert post basic data
        # * obtain id
        # * insert post content data

        # add permlinks to permlink table
        for permlink in [op['permlink'], op['parent_permlink'], op['root_permlink']]:
            sql = """
                INSERT INTO hive_permlink_data (permlink) 
                VALUES (:permlink) 
                ON CONFLICT (permlink) DO NOTHING"""
            DB.query(permlink=permlink)

        # add category to category table
        sql = """
            INSERT INTO hive_category_data (category) 
            VALUES (:category) 
            ON CONFLICT (category) DO NOTHING"""
        DB.query(category=op['category'])

        sql = """
            INSERT INTO hive_posts (parent_id, author_id, permlink_id,
                category_id, community_id, created_at, depth, is_deleted, is_pinned,
                is_muted, is_valid, promoted, children, author_rep, flag_weight,
                total_votes, up_votes, payout, payout_at, updated_at, is_paidout,
                is_nsfw, is_declined, is_full_power, is_hidden, is_grayed, rshares,
                sc_trend, sc_hot, parent_author_id, parent_permlink_id,
                curator_payout_value, root_author_id, root_permlink_id,
                max_accepted_payout, percent_steem_dollars, allow_replies, allow_votes,
                allow_curation_rewards, beneficiaries, url, root_title)
            VALUES (:parent_id, 
                (SELECT id FROM hive_accounts WHERE name = :author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :permlink),
                (SELECT id FROM hive_category_data WHERE category = :category)
                :community_id, :created_at, :depth, :is_deleted, :is_pinned,
                :is_muted, :is_valid, :promoted, :children, :author_rep, :flag_weight,
                :total_votes, :up_votes, :payout, :payout_at, :updated_at, :is_paidout,
                :is_nsfw, :is_declined, :is_full_power, :is_hidden, :is_grayed, :rshares,
                :sc_trend, :sc_hot, 
                (SELECT id FROM hive_accounts WHERE name = :parent_author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :parent_permlink),
                :curator_payout_value, 
                (SELECT id FROM hive_accounts WHERE name = :root_author),
                (SELECT id FROM hive_permlink_data WHERE permlink = :root_permlink),
                :max_accepted_payout, :percent_steem_dollars, :allow_replies, :allow_votes,
                :allow_curation_rewards, :beneficiaries, :url, :root_title)"""
        sql += ";SELECT currval(pg_get_serial_sequence('hive_posts','id'))"
        post = cls._build_post(op, date)
        result = DB.query(sql, **post)
        post['id'] = int(list(result)[0][0])
        cls._set_id(op['author']+'/'+op['permlink'], post['id'])

        # add content data to hive_post_data
        sql = """
            INSERT INTO hive_post_data (id, title, preview, img_url, body, 
                votes, json) 
            VALUES (:id, :title, :preview, :img_url, :body, :votes, :json)"""
        DB.query(sql, id=post['id'], title=op['title'], preview=op['preview'],
                 img_url=op['img_url'], body=op['body'], votes=op['votes'],
                 json=op['json_metadata'])

        if not DbState.is_initial_sync():
            if post['error']:
                author_id = Accounts.get_id(post['author'])
                Notify('error', dst_id=author_id, when=date,
                       post_id=post['id'], payload=post['error']).write()
            # TODO: [DK] Remove CachedPost
            # CachedPost.insert(op['author'], op['permlink'], post['id'])
            if op['parent_author']: # update parent's child count
                CachedPost.recount(op['parent_author'], op['parent_permlink'], post['parent_id'])
            cls._insert_feed_cache(post)

    @classmethod
    def undelete(cls, op, date, pid):
        """Re-allocates an existing record flagged as deleted."""
        sql = """UPDATE hive_posts SET is_valid = :is_valid,
                   is_muted = :is_muted, is_deleted = '0', is_pinned = '0',
                   parent_id = :parent_id, category = :category,
                   community_id = :community_id, depth = :depth
                 WHERE id = :id"""
        post = cls._build_post(op, date, pid)
        DB.query(sql, **post)

        if not DbState.is_initial_sync():
            if post['error']:
                author_id = Accounts.get_id(post['author'])
                Notify('error', dst_id=author_id, when=date,
                       post_id=post['id'], payload=post['error']).write()

            # TODO: [DK] Remove CachedPost
            #CachedPost.undelete(pid, post['author'], post['permlink'], post['category'])
            cls._insert_feed_cache(post)

    @classmethod
    def delete(cls, op):
        """Marks a post record as being deleted."""
        pid, depth = cls.get_id_and_depth(op['author'], op['permlink'])
        DB.query("UPDATE hive_posts SET is_deleted = '1' WHERE id = :id", id=pid)

        if not DbState.is_initial_sync():
            # TODO: [DK] Remove CachedPost
            #CachedPost.delete(pid, op['author'], op['permlink'])
            if depth == 0:
                # TODO: delete from hive_reblogs -- otherwise feed cache gets 
                # populated with deleted posts somwrimas
                FeedCache.delete(pid)
            else:
                # force parent child recount when child is deleted
                prnt = cls._get_parent_by_child_id(pid)
                CachedPost.recount(prnt['author'], prnt['permlink'], prnt['id'])


    @classmethod
    def update(cls, op, date, pid):
        """Handle post updates.

        Here we could also build content diffs, but for now just used
        a signal to update cache record.
        """
        # pylint: disable=unused-argument
        #if not DbState.is_initial_sync():
        #    CachedPost.update(op['author'], op['permlink'], pid)
        sql = """
            UPDATE hive_posts 
            SET 
                parent_id = :parent_id, 
                community_id = :community_id, 
                created_at = :created_at,  
                is_deleted = :is_deleted, 
                is_pinned = :is_pinned,
                is_muted = :is_muted, 
                is_valid = :is_valid, 
                promoted = :promoted, 
                children = :children, 
                author_rep = :author_rep, 
                flag_weight = :flag_weight,
                total_votes = :total_votes, 
                up_votes = :up_votes, 
                payout = :payout, 
                payout_at = :payout_at, 
                updated_at = :updated_at, 
                is_paidout = :is_paidout,
                is_nsfw = :is_nsfw, 
                is_declined = :is_declined, 
                is_full_power = :is_full_power, 
                is_hidden = :is_hidden, 
                is_grayed = :is_grayed, 
                rshares = :rshares,
                sc_trend = :sc_trend, 
                sc_hot = :sc_hot, 
                parent_author_id = (SELECT id FROM hive_accounts WHERE name = :parent_author), 
                parent_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :parent_permlink),
                curator_payout_value = :curator_payout_value, 
                root_author_id = (SELECT id FROM hive_accounts WHERE name = :root_author),
                root_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :root_permlink),
                max_accepted_payout = :max_accepted_payout, 
                percent_steem_dollars = :percent_steem_dollars, 
                allow_replies = :allow_replies, 
                allow_votes = :allow_votes,
                allow_curation_rewards = :allow_curation_rewards, 
                beneficiaries = :beneficiaries, 
                url = :url, 
                root_title = :root_title
            WHERE id = :id"""
        post = cls._build_post(op, date, pid)
        DB.query(sql, **post)

    @classmethod
    def _get_parent_by_child_id(cls, child_id):
        """Get parent's `id`, `author`, `permlink` by child id."""
        sql = """
            SELECT 
                hp.id, ha_a.name as author, hpd_p.permlink as permlink, 
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

        # check post validity in specified context
        error = None
        if community_id and is_valid and not Community.is_post_valid(community_id, op):
            error = 'not authorized'
            #is_valid = False # TODO: reserved for future blacklist status?
            is_muted = True

        return dict(parent_id=parent_id,
                    author=op['author'], permlink=op['permlink'], id=pid,
                    category=category, community_id=community_id, created_at=op['created_at'],
                    depth=depth, is_deleted=op['is_deleted'], is_pinned=op['is_pinned'],
                    is_muted=op['is_muted'], is_valid=is_valid, promoted=op['promoted'],
                    children=op['children'], author_rep=op['author_rep'], flag_weight=op['flag_weight'],
                    total_votes=op['total_votes'], up_votes=op['up_votes'], payout=op['payout'],
                    payout_at=op['payout_at'], updated_at=op['updated_at'], is_paidout=op['is_paidout'],
                    is_nsfw=op['is_nsfw'], is_declined=op['is_declined'], is_full_power=op['is_full_power'],
                    is_hidden=op['is_hidden'], is_grayed=op['is_grayed'], rshares=op['rshares'],
                    sc_trend=op['sc_trend'], sc_hot=op['sc_hot'], parent_author=op['parent_author'],
                    parent_permlink=op['parent_permlink'],
                    curator_payout_value=op['curator_payout_value'], root_author=op['root_author'],
                    root_permlink=op['root_permlink'],
                    max_accepted_payout=op['max_accepted_payout'], percent_steem_dollars=op['percent_steem_dollars'],
                    allow_replies=op['allow_replies'], allow_votes=op['allow_votes'],
                    allow_curation_rewards=op['allow_curation_rewards'], beneficiaries=op['beneficiaries'], url=op['url'],
                    root_title=op['root_title'], date=date, error=error)
