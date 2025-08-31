"""Core posts manager."""

import logging

from diff_match_patch import diff_match_patch
from ujson import dumps, loads
from collections import OrderedDict

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.db.db_state import DbState
from hive.indexer import community
from hive.indexer.block import VirtualOperationType
from hive.indexer.community import Community
from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.notify import Notify
from hive.indexer.post_data_cache import PostDataCache
from hive.indexer.votes import Votes
from hive.indexer.notification_cache import NotificationCache
from hive.utils.misc import chunks, UniqueCounter
from hive.utils.normalize import escape_characters, legacy_amount, sbd_amount

log = logging.getLogger(__name__)


class Posts(DbAdapterHolder):
    """Handles critical/core post ops and data."""

    comment_payout_ops = {}
    _comment_payout_ops = []
    _counter = UniqueCounter()

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

        sql = f"""
            SELECT is_new_post, id, author_id, permlink_id, post_category, parent_id, parent_author_id, community_id, is_valid, is_post_muted, depth, muted_reasons
            FROM {SCHEMA_NAME}.process_hive_post_operation((:author)::varchar, (:permlink)::varchar, (:parent_author)::varchar, (:parent_permlink)::varchar, (:date)::timestamp, (:community_support_start_block)::integer, (:block_num)::integer, (:tags)::VARCHAR[]);
            """

        row = DbAdapterHolder.common_block_processing_db().query_row(
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

        error = cls._verify_post_against_community(op, result['community_id'], result['is_valid'])

        is_new_post = result['is_new_post']
        parent_author = op.get('parent_author')
        if is_new_post:
            # add content data to hive_post_data
            post_data = dict(
                title=op['title'] if op['title'] else '',
                body=op['body'] if op['body'] else '',
                json=op['json_metadata'] if op['json_metadata'] else '',
                is_root = 'true' if parent_author is None or parent_author == '' else 'false'
            )
        else:
            # edit case. Now we need to (potentially) apply patch to the post body.
            # empty new body means no body edit, not clear (same with other data)
            new_body = cls._merge_post_body(id=result['id'], new_body_def=op['body']) if op['body'] else None
            new_title = op['title'] if op['title'] else None
            new_json = op['json_metadata'] if op['json_metadata'] else None
            post_data = dict(title=new_title, body=new_body, json=new_json, is_root='false')

        #        log.info("Adding author: {}  permlink: {}".format(op['author'], op['permlink']))
        PostDataCache.add_data(result['id'], post_data, is_new_post)
        if row['depth'] > 0:
            type_id = 12 if row['depth'] == 1 else 13
            key = f"{row['author_id']}/{row['parent_author_id']}/{type_id}/{row['id']}"
            NotificationCache.comment_notifications[key] = {
                "block_num": op['block_num'],
                "type_id": type_id,
                "created_at": block_date,
                "src": row['author_id'],
                "dst": row['parent_author_id'],
                "dst_post_id": row['parent_id'],
                "post_id": row['id'],
                'counter': cls._counter.increment(op['block_num']),
            }

        # If muted_reasons is set here, it was caused by a post getting muted by a community type 2 or 3
        # if it's not a new post we skip this step as a notification would already be sent
        if row['muted_reasons'] is not None and row['muted_reasons'] != 0 and is_new_post == False:
            raw_mask = row['muted_reasons']
            muted_reasons = community.decode_bitwise_mask(raw_mask)
            log.info(f"Raw mask: {raw_mask}, Decoded: {muted_reasons}")
            log.info(f"Full row data: {dict(row)}")
            log.info(f"Row keys: {list(row.keys())}")
            for key in row.keys():
                log.info(f"  {key}: {row[key]} (type: {type(row[key])})")

            muted_reasons = community.decode_bitwise_mask(row['muted_reasons'])
            reasons = []
            if 1 in muted_reasons:
                reasons.append("community type does not allow non member to post/comment")
            if 2 in muted_reasons:
                reasons.append("parent post/comment is muted")

            if len(reasons) == 1:
                payload = f"Post is muted because {reasons[0]}"
            else:
                payload = f"Post is muted because {reasons[0]} and {reasons[1]}"

            Notify(
                block_num=op['block_num'],
                type_id='error',
                dst_id=result['author_id'],
                when=block_date,
                post_id=result['id'],
                payload=payload,
                community_id=result['community_id'],
                src_id=result['community_id'],
            )

        if not DbState.is_massive_sync():
            if error:
                Notify(
                    block_num=op['block_num'],
                    type_id='error',
                    dst_id=result['author_id'],
                    when=block_date,
                    post_id=result['id'],
                    payload=error,
                    community_id=result['community_id'],
                    src_id=result['community_id'],
                )

    @classmethod
    def flush_into_db(cls):
        sql = f"""
              UPDATE {SCHEMA_NAME}.hive_posts AS ihp SET
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
                {{}}
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
              INNER JOIN {SCHEMA_NAME}.hive_accounts ha_a ON ha_a.name = t.author
              INNER JOIN {SCHEMA_NAME}.hive_permlink_data hpd_p ON hpd_p.permlink = t.permlink
              ) as data_source
              WHERE ihp.permlink_id = data_source.permlink_id and ihp.author_id = data_source.author_id
        """

        for chunk in chunks(cls._comment_payout_ops, 1000):
            cls.beginTx()

            cls.db.query_no_return('SELECT pg_advisory_xact_lock(777)')  # synchronise with update_posts_rshares in votes
            values_str = ','.join(chunk)
            actual_query = sql.format(values_str)
            cls.db.query_prepared(actual_query)

            cls.commitTx()

        n = len(cls._comment_payout_ops)
        cls._comment_payout_ops.clear()
        return n

    @classmethod
    def comment_payout_op(cls):
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
                author_rewards = value['author_rewards']
                total_payout_value = value['total_payout_value']
                curator_payout_value = value['curator_payout_value']
                beneficiary_payout_value = value['beneficiary_payout_value']

                payout = sum([sbd_amount(total_payout_value), sbd_amount(curator_payout_value), sbd_amount(beneficiary_payout_value)])
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
        sql = f"""
            UPDATE
                {SCHEMA_NAME}.hive_posts
            SET
                children = GREATEST(0, (
                    SELECT
                        CASE
                            WHEN children is NULL THEN 0
                            WHEN children=32762 THEN 0
                            ELSE children
                        END
                    FROM
                        {SCHEMA_NAME}.hive_posts
                    WHERE id = (SELECT parent_id FROM {SCHEMA_NAME}.hive_posts WHERE id = :child_id)
                )::int
        """
        if op == '+':
            sql += """ + 1)"""
        else:
            sql += """ - 1)"""
        sql += f""" WHERE id = (SELECT parent_id FROM {SCHEMA_NAME}.hive_posts WHERE id = :child_id)"""

        DbAdapterHolder.common_block_processing_db().query(sql, child_id=child_id)

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
        sql = f"""
            UPDATE
                {SCHEMA_NAME}.hive_posts hp
            SET
                max_accepted_payout = :max_accepted_payout,
                percent_hbd = :percent_hbd,
                allow_votes = :allow_votes,
                allow_curation_rewards = :allow_curation_rewards,
                beneficiaries = :beneficiaries
            WHERE
            hp.author_id = (SELECT id FROM {SCHEMA_NAME}.hive_accounts WHERE name = :author) AND
            hp.permlink_id = (SELECT id FROM {SCHEMA_NAME}.hive_permlink_data WHERE permlink = :permlink)
        """
        DbAdapterHolder.common_block_processing_db().query(
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
        sql = f"SELECT {SCHEMA_NAME}.delete_hive_post((:author)::varchar, (:permlink)::varchar, (:block_num)::int, (:date)::timestamp);"
        DbAdapterHolder.common_block_processing_db().query_no_return(
            sql, author=op['author'], permlink=op['permlink'], block_num=op['block_num'], date=block_date
        )
        # all votes for that post that are still not pushed to DB have to be removed, since the same author/permlink
        # is now free to be taken by new post and we don't want those votes to match new post
        Votes.drop_votes_of_deleted_comment(op)

    @classmethod
    def _verify_post_against_community(cls, op, community_id, is_valid):
        error = None
        # is_valid is always set to true for now
        if community_id and is_valid and not Community.is_post_valid(community_id, op):
            error = 'not allowed to post in this community (role is muted)'
            # is_valid = False # TODO: reserved for future blacklist status?
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
