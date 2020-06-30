"""Core posts manager."""

import logging
import collections

from json import dumps, loads

from hive.db.adapter import Db
from hive.db.db_state import DbState

from hive.indexer.accounts import Accounts
from hive.indexer.feed_cache import FeedCache
from hive.indexer.community import Community, START_DATE
from hive.indexer.notify import Notify
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.tags import Tags
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
    def delete_op(cls, op):
        """Given a delete_comment op, mark the post as deleted.

        Also remove it from post-cache and feed-cache.
        """
        cls.delete(op)

    @classmethod
    def comment_op(cls, op, block_date):
        """Register new/edited/undeleted posts; insert into feed cache."""

        sql = """
            SELECT id, author_id, permlink_id, post_category, parent_id, community_id, is_valid, is_muted, depth, is_edited
            FROM process_hive_post_operation((:author)::varchar, (:permlink)::varchar, (:parent_author)::varchar, (:parent_permlink)::varchar, (:date)::timestamp, (:community_support_start_date)::timestamp);
            """

        row = DB.query_row(sql, author=op['author'], permlink=op['permlink'], parent_author=op['parent_author'],
                   parent_permlink=op['parent_permlink'], date=block_date, community_support_start_date=START_DATE)

        result = dict(row)

        # TODO we need to enhance checking related community post validation and honor is_muted.
        error = cls._verify_post_against_community(op, result['community_id'], result['is_valid'], result['is_muted'])

        cls._set_id(op['author']+'/'+op['permlink'], result['id'])

        # add content data to hive_post_data
        post_data = dict(title=op['title'], preview=op['preview'] if 'preview' in op else "",
                         img_url=op['img_url'] if 'img_url' in op else "", body=op['body'],
                         json=op['json_metadata'] if op['json_metadata'] else '{}')
        PostDataCache.add_data(result['id'], post_data)

        md = {}
        # At least one case where jsonMetadata was double-encoded: condenser#895
        # jsonMetadata = JSON.parse(jsonMetadata);
        try:
            md = loads(op['json_metadata'])
            if not isinstance(md, dict):
                md = {}
        except Exception:
            pass

        tags = [result['post_category']]
        if md and 'tags' in md and isinstance(md['tags'], list):
            tags = tags + md['tags']
        tags = map(lambda tag: (str(tag) or '').strip('# ').lower()[:32], tags)
        tags = filter(None, tags)
        from funcy.seqs import distinct
        tags = list(distinct(tags))[:5]

        for tag in tags:
            Tags.add_tag(result['id'], tag)

        if not DbState.is_initial_sync():
            if error:
                author_id = result['author_id']
                Notify('error', dst_id=author_id, when=block_date,
                       post_id=result['id'], payload=error).write()
            cls._insert_feed_cache(result, block_date)

    @classmethod
    def comment_payout_op(cls, ops, date):
        ops_stats = {}
        sql = """
              UPDATE hive_posts AS ihp SET
                  total_payout_value = data_source.total_payout_value,
                  curator_payout_value = data_source.curator_payout_value,
                  author_rewards = data_source.author_rewards,
                  author_rewards_hive = data_source.author_rewards_hive,
                  author_rewards_hbd = data_source.author_rewards_hbd,
                  author_rewards_vests = data_source.author_rewards_vests,
                  last_payout = data_source.last_payout,
                  cashout_time = data_source.cashout_time,
                  is_paidout = true

              FROM 
              (
              SELECT  ha_a.id as author_id, hpd_p.id as permlink_id, 
                      t.total_payout_value,
                      t.curator_payout_value,
                      t.author_rewards,
                      t.author_rewards_hive,
                      t.author_rewards_hbd,
                      t.author_rewards_vests,
                      t.last_payout,
                      t.cashout_time
              from
              (
              VALUES
                --- put all constant values here
                {}
              ) AS T(author, permlink,
                      total_payout_value,
                      curator_payout_value,
                      author_rewards,
                      author_rewards_hive,
                      author_rewards_hbd,
                      author_rewards_vests,
                      last_payout,
                      cashout_time)
              INNER JOIN hive_accounts ha_a ON ha_a.name = t.author
              INNER JOIN hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
              ) as data_source(author_id, permlink_id, total_payout_value)
              WHERE ihp.permlink_id = data_source.permlink_id and ihp.author_id = data_source.author_id
              """

        values = []
        values_limit = 1000

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
                    if op in ops_stats:
                        ops_stats[op] += 1
                    else:
                        ops_stats[op] = 1

                    if op == 'curation_reward_operation':
                        curator_rewards_sum = curator_rewards_sum + int(value['reward']['amount'])
                    elif op == 'author_reward_operation':
                        author_rewards_hive = value['hive_payout']['amount']
                        author_rewards_hbd = value['hbd_payout']['amount']
                        author_rewards_vests = value['vesting_payout']['amount']
                    elif op == 'comment_reward_operation':
                        comment_author_reward = value['payout']
                        author_rewards = value['author_rewards']
            curator_rewards = {'amount' : str(curator_rewards_sum), 'precision': 6, 'nai': '@@000000037'}

            values.append("('{}', '{}', '{}', '{}', {}, {}, {}, {}, '{}'::timestamp, '{}'::timestamp)".format(author, permlink,
               legacy_amount(comment_author_reward), # total_payout_value
               legacy_amount(curator_rewards), #curator_payout_value
               author_rewards,
               author_rewards_hive,
               author_rewards_hbd,
               author_rewards_vests,
               date, #last_payout
               date #cashout_time
               ))

            if len(values) >= values_limit:
                values_str = ','.join(values)
                actual_query = sql.format(values_str)
                DB.query(actual_query)
                values.clear()

        if len(values) > 0:
            values_str = ','.join(values)
            actual_query = sql.format(values_str)
            DB.query(actual_query)
            values.clear()
        return ops_stats

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
                            WHEN children is NULL THEN 0
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
    def comment_options_op(cls, op):
        """ Process comment_options_operation """
        max_accepted_payout = legacy_amount(op['max_accepted_payout']) if 'max_accepted_payout' in op else '1000000.000 HBD'
        allow_votes = op['allow_votes'] if 'allow_votes' in op else True
        allow_curation_rewards = op['allow_curation_rewards'] if 'allow_curation_rewards' in op else True
        percent_hbd = op['percent_hbd'] if 'percent_hbd' in op else 10000
        extensions = op['extensions'] if 'extensions' in op else []
        beneficiaries = []
        for extension in extensions:
            if 'beneficiaries' in extensions:
                beneficiaries = extension['beneficiaries']
        sql = """
            UPDATE
                hive_posts hp
            SET
                max_accepted_payout = :max_accepted_payout,
                percent_hbd = :percent_hbd,
                allow_votes = :allow_votes,
                allow_curation_rewards = :allow_curation_rewards,
                beneficiaries = :beneficiaries
            WHERE
            hp.author_id = (SELECT id FROM hive_accounts WHERE name = :author) AND 
            hp.permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = :permlink)
        """
        DB.query(sql, author=op['author'], permlink=op['permlink'], max_accepted_payout=max_accepted_payout,
                 percent_hbd=percent_hbd, allow_votes=allow_votes, allow_curation_rewards=allow_curation_rewards,
                 beneficiaries=beneficiaries)

    @classmethod
    def delete(cls, op):
        """Marks a post record as being deleted."""

        sql = """
              SELECT id, depth
              FROM delete_hive_post((:author)::varchar, (:permlink)::varchar);
              """
        row = DB.query_row(sql, author=op['author'], permlink = op['permlink'])

        result = dict(row)
        pid = result['id']

        if not DbState.is_initial_sync():
            depth = result['depth']

            if depth == 0:
                # TODO: delete from hive_reblogs -- otherwise feed cache gets 
                # populated with deleted posts somwrimas
                FeedCache.delete(pid)

        # force parent child recount when child is deleted
        cls.update_child_count(pid, '-')

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
                         author=comment_pending_payout['author'], permlink=comment_pending_payout['permlink'])

    @classmethod
    def _insert_feed_cache(cls, result, date):
        """Insert the new post into feed cache if it's not a comment."""
        if not result['depth']:
            cls._insert_feed_cache4(result['depth'], result['id'], result['author_id'], date)

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

