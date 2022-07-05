"""Core posts manager."""

import logging

from diff_match_patch import diff_match_patch
from ujson import dumps, loads

from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer.block import VirtualOperationType
from hive.indexer.community import Community
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.notify import Notify
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.votes import Votes
from hive.utils.misc import chunks
from hive.utils.normalize import escape_characters, legacy_amount, safe_img_url, sbd_amount

log = logging.getLogger(__name__)
DB = Db.instance()


class Posts(DbAdapterHolder):
    """Handles critical/core post ops and data."""

    # LRU cache for (author-permlink -> id) lookup (~400mb per 1M entries)
    CACHE_SIZE = 2000000
    _hits = 0
    _miss = 0

    comment_payout_ops = {}
    _comment_payout_ops = []

    @classmethod
    def last_id(cls):
        """Get the last indexed post id."""
        sql = "SELECT MAX(id) FROM hive_posts WHERE counter_deleted = 0"
        return DB.query_one(sql) or 0

    @classmethod
    def delete_op(cls, op, block_date):
        """Given a delete_comment op, mark the post as deleted.

        Also remove it from post-cache and feed-cache.
        """
        cls.delete(op, block_date)

    @classmethod
    def comment_op(cls, op, block_date):
        """Register new/edited/undeleted posts; insert into feed cache."""

        md = {}
        # At least one case where jsonMetadata was double-encoded: condenser#895
        # jsonMetadata = JSON.parse(jsonMetadata);
        try:
            md = loads(op['json_metadata'])
            if not isinstance(md, dict):
                md = {}
        except Exception:
            pass

        tags = []

        if md and 'tags' in md and isinstance(md['tags'], list):
            for tag in md['tags']:
                if tag and isinstance(tag, str):
                    tags.append(tag)  # No escaping needed due to used sqlalchemy formatting features

        sql = """
            SELECT is_new_post, id, author_id, permlink_id, post_category, parent_id, community_id, is_valid, is_muted, depth
            FROM process_hive_post_operation((:author)::varchar, (:permlink)::varchar, (:parent_author)::varchar, (:parent_permlink)::varchar, (:date)::timestamp, (:community_support_start_block)::integer, (:block_num)::integer, (:tags)::VARCHAR[]);
            """

        row = DB.query_row(
            sql,
            author=op['author'],
            permlink=op['permlink'],
            parent_author=op['parent_author'],
            parent_permlink=op['parent_permlink'],
            date=block_date,
            community_support_start_block=Community.start_block,
            block_num=op['block_num'],
            tags=tags,
        )

        if not row:
            log.error(f"Failed to process comment_op: {op}")
            return
        result = dict(row)

        # TODO we need to enhance checking related community post validation and honor is_muted.
        error = cls._verify_post_against_community(op, result['community_id'], result['is_valid'], result['is_muted'])

        img_url = None
        if 'image' in md:
            img_url = md['image']
            if isinstance(img_url, list) and img_url:
                img_url = img_url[0]
        if img_url:
            img_url = safe_img_url(img_url)

        is_new_post = result['is_new_post']
        if is_new_post:
            # add content data to hive_post_data
            post_data = dict(
                title=op['title'] if op['title'] else '',
                img_url=img_url if img_url else '',
                body=op['body'] if op['body'] else '',
                json=op['json_metadata'] if op['json_metadata'] else '',
            )
        else:
            # edit case. Now we need to (potentially) apply patch to the post body.
            # empty new body means no body edit, not clear (same with other data)
            new_body = cls._merge_post_body(id=result['id'], new_body_def=op['body']) if op['body'] else None
            new_title = op['title'] if op['title'] else None
            new_json = op['json_metadata'] if op['json_metadata'] else None
            # when 'new_json' is not empty, 'img_url' should be overwritten even if it is itself empty
            new_img = img_url if img_url else '' if new_json else None
            post_data = dict(title=new_title, img_url=new_img, body=new_body, json=new_json)

        #        log.info("Adding author: {}  permlink: {}".format(op['author'], op['permlink']))
        PostDataCache.add_data(result['id'], post_data, is_new_post)

        if not DbState.is_massive_sync():
            if error:
                author_id = result['author_id']
                Notify(
                    block_num=op['block_num'],
                    type_id='error',
                    dst_id=author_id,
                    when=block_date,
                    post_id=result['id'],
                    payload=error,
                )

    @classmethod
    def flush_into_db(cls):
        sql = """
              UPDATE hive_posts AS ihp SET
                  total_payout_value    = COALESCE( data_source.total_payout_value,                     ihp.total_payout_value ),
                  curator_payout_value  = COALESCE( data_source.curator_payout_value,                   ihp.curator_payout_value ),
                  author_rewards        = CAST( data_source.author_rewards as BIGINT ) + ihp.author_rewards,
                  author_rewards_hive   = COALESCE( CAST( data_source.author_rewards_hive as BIGINT ),  ihp.author_rewards_hive ),
                  author_rewards_hbd    = COALESCE( CAST( data_source.author_rewards_hbd as BIGINT ),   ihp.author_rewards_hbd ),
                  author_rewards_vests  = COALESCE( CAST( data_source.author_rewards_vests as BIGINT ), ihp.author_rewards_vests ),
                  payout                = COALESCE( CAST( data_source.payout as DECIMAL ),              ihp.payout ),
                  pending_payout        = COALESCE( CAST( data_source.pending_payout as DECIMAL ),      ihp.pending_payout ),
                  payout_at             = COALESCE( CAST( data_source.payout_at as TIMESTAMP ),         ihp.payout_at ),
                  last_payout_at        = COALESCE( CAST( data_source.last_payout_at as TIMESTAMP ),    ihp.last_payout_at ),
                  cashout_time          = COALESCE( CAST( data_source.cashout_time as TIMESTAMP ),      ihp.cashout_time ),
                  is_paidout            = COALESCE( CAST( data_source.is_paidout as BOOLEAN ),          ihp.is_paidout ),
                  total_vote_weight     = COALESCE( CAST( data_source.total_vote_weight as NUMERIC ),   ihp.total_vote_weight )
              FROM
              (
              SELECT  ha_a.id as author_id, hpd_p.id as permlink_id,
                      t.total_payout_value,
                      t.curator_payout_value,
                      t.author_rewards,
                      t.author_rewards_hive,
                      t.author_rewards_hbd,
                      t.author_rewards_vests,
                      t.payout,
                      t.pending_payout,
                      t.payout_at,
                      t.last_payout_at,
                      t.cashout_time,
                      t.is_paidout,
                      t.total_vote_weight
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
                      payout,
                      pending_payout,
                      payout_at,
                      last_payout_at,
                      cashout_time,
                      is_paidout,
                      total_vote_weight)
              INNER JOIN hive_accounts ha_a ON ha_a.name = t.author
              INNER JOIN hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
              ) as data_source
              WHERE ihp.permlink_id = data_source.permlink_id and ihp.author_id = data_source.author_id
        """

        for chunk in chunks(cls._comment_payout_ops, 1000):
            cls.beginTx()

            values_str = ','.join(chunk)
            actual_query = sql.format(values_str)
            cls.db.query_prepared(actual_query)

            cls.commitTx()

        n = len(cls._comment_payout_ops)
        cls._comment_payout_ops.clear()
        return n

    @classmethod
    def comment_payout_op(cls):
        values_limit = 1000

        """ Process comment payment operations """
        for k, v in cls.comment_payout_ops.items():
            author = None
            permlink = None

            # author payouts
            author_rewards = 0
            author_rewards_hive = None
            author_rewards_hbd = None
            author_rewards_vests = None

            # total payout for comment
            # comment_author_reward     = None
            # curators_vesting_payout   = None
            total_payout_value = None
            curator_payout_value = None
            # beneficiary_payout_value  = None;

            payout = None
            pending_payout = None

            payout_at = None
            last_payout_at = None
            cashout_time = None

            is_paidout = None

            total_vote_weight = None

            # [final] payout indicator - by default all rewards are zero, but might be overwritten by other operations
            # ABW: prior to some early HF that was not necessarily final payout since those were discussion driven so new comment/vote could trigger new cashout window, see f.e.
            # soulsistashakti/re-emily-cook-let-me-introduce-myself-my-name-is-emily-cook-and-i-m-the-producer-and-presenter-of-a-monthly-film-show-film-focus-20160701t012330329z
            # it emits that "final" operation at blocks: 2889020, 3053237, 3172559 and 4028469
            if v[VirtualOperationType.COMMENT_PAYOUT_UPDATE] is not None:
                value, date = v[VirtualOperationType.COMMENT_PAYOUT_UPDATE]
                if author is None:
                    author = value['author']
                    permlink = value['permlink']
                is_paidout = True
                payout_at = date
                last_payout_at = date
                cashout_time = "infinity"

                pending_payout = 0
                total_vote_weight = 0

            # author rewards in current (final or nonfinal) payout (always comes with comment_reward_operation)
            if v[VirtualOperationType.AUTHOR_REWARD] is not None:
                value, date = v[VirtualOperationType.AUTHOR_REWARD]
                if author is None:
                    author = value['author']
                    permlink = value['permlink']
                author_rewards_hive = value['hive_payout']['amount']
                author_rewards_hbd = value['hbd_payout']['amount']
                author_rewards_vests = value['vesting_payout']['amount']
                # curators_vesting_payout = value['curators_vesting_payout']['amount']

            # summary of comment rewards in current (final or nonfinal) payout (always comes with author_reward_operation)
            if v[VirtualOperationType.COMMENT_REWARD] is not None:
                value, date = v[VirtualOperationType.COMMENT_REWARD]
                if author is None:
                    author = value['author']
                    permlink = value['permlink']
                # comment_author_reward   = value['payout']
                author_rewards = value['author_rewards']
                total_payout_value = value['total_payout_value']
                curator_payout_value = value['curator_payout_value']
                # beneficiary_payout_value = value['beneficiary_payout_value']

                payout = sum([sbd_amount(total_payout_value), sbd_amount(curator_payout_value)])
                pending_payout = 0
                last_payout_at = date

            # estimated pending_payout from vote (if exists with actual payout the value comes from vote cast after payout)
            if v[VirtualOperationType.EFFECTIVE_COMMENT_VOTE] is not None:
                value, date = v[VirtualOperationType.EFFECTIVE_COMMENT_VOTE]
                if author is None:
                    author = value['author']
                    permlink = value['permlink']
                pending_payout = sbd_amount(value['pending_payout'])
                total_vote_weight = value['total_vote_weight']

            cls._comment_payout_ops.append(
                "('{}', {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})".format(
                    author,
                    escape_characters(permlink),
                    "NULL" if (total_payout_value is None) else ("'{}'".format(legacy_amount(total_payout_value))),
                    "NULL" if (curator_payout_value is None) else ("'{}'".format(legacy_amount(curator_payout_value))),
                    author_rewards,
                    "NULL" if (author_rewards_hive is None) else author_rewards_hive,
                    "NULL" if (author_rewards_hbd is None) else author_rewards_hbd,
                    "NULL" if (author_rewards_vests is None) else author_rewards_vests,
                    "NULL" if (payout is None) else payout,
                    "NULL" if (pending_payout is None) else pending_payout,
                    "NULL" if (payout_at is None) else (f"'{payout_at}'::timestamp"),
                    "NULL" if (last_payout_at is None) else (f"'{last_payout_at}'::timestamp"),
                    "NULL" if (cashout_time is None) else (f"'{cashout_time}'::timestamp"),
                    "NULL" if (is_paidout is None) else is_paidout,
                    "NULL" if (total_vote_weight is None) else total_vote_weight,
                )
            )

        n = len(cls.comment_payout_ops)
        cls.comment_payout_ops.clear()
        return n

    @classmethod
    def update_child_count(cls, child_id, op='+'):
        """Increase/decrease child count by 1"""
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
        """Process comment_options_operation"""
        max_accepted_payout = (
            legacy_amount(op['max_accepted_payout']) if 'max_accepted_payout' in op else '1000000.000 HBD'
        )
        allow_votes = op['allow_votes'] if 'allow_votes' in op else True
        allow_curation_rewards = op['allow_curation_rewards'] if 'allow_curation_rewards' in op else True
        percent_hbd = op['percent_hbd'] if 'percent_hbd' in op else 10000
        extensions = op['extensions'] if 'extensions' in op else []
        beneficiaries = []
        for ex in extensions:
            if 'type' in ex and ex['type'] == 'comment_payout_beneficiaries' and 'beneficiaries' in ex['value']:
                beneficiaries = ex['value']['beneficiaries']
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
        DB.query(
            sql,
            author=op['author'],
            permlink=op['permlink'],
            max_accepted_payout=max_accepted_payout,
            percent_hbd=percent_hbd,
            allow_votes=allow_votes,
            allow_curation_rewards=allow_curation_rewards,
            beneficiaries=dumps(beneficiaries),
        )

    @classmethod
    def delete(cls, op, block_date):
        """Marks a post record as being deleted."""
        sql = (
            "SELECT delete_hive_post((:author)::varchar, (:permlink)::varchar, (:block_num)::int, (:date)::timestamp);"
        )
        DB.query_no_return(
            sql, author=op['author'], permlink=op['permlink'], block_num=op['block_num'], date=block_date
        )
        # all votes for that post that are still not pushed to DB have to be removed, since the same author/permlink
        # is now free to be taken by new post and we don't want those votes to match new post
        Votes.drop_votes_of_deleted_comment(op)

    @classmethod
    def _verify_post_against_community(cls, op, community_id, is_valid, is_muted):
        error = None
        if community_id and is_valid and not Community.is_post_valid(community_id, op):
            error = 'not authorized'
            # is_valid = False # TODO: reserved for future blacklist status?
            is_muted = True
        return error

    @classmethod
    def _merge_post_body(cls, id, new_body_def):
        new_body = ''
        old_body = ''

        try:
            dmp = diff_match_patch()
            patch = dmp.patch_fromText(new_body_def)
            if patch is not None and len(patch):
                old_body = PostDataCache.get_post_body(id)
                new_body, _ = dmp.patch_apply(patch, old_body)
                # new_utf8_body = new_body.decode('utf-8')
                # new_body = new_utf8_body
            else:
                new_body = new_body_def
        except ValueError as e:
            #            log.info("Merging a body post id: {} caused an ValueError exception {}".format(id, e))
            #            log.info("New body definition: {}".format(new_body_def))
            #            log.info("Old body definition: {}".format(old_body))
            new_body = new_body_def
        except Exception as ex:
            log.info(f"Merging a body post id: {id} caused an unknown exception {ex}")
            log.info(f"New body definition: {new_body_def}")
            log.info(f"Old body definition: {old_body}")
            new_body = new_body_def

        return new_body

    @classmethod
    def flush(cls):
        return cls.comment_payout_op() + cls.flush_into_db()
