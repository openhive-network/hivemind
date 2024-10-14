"""Db schema definitions and setup routines."""

import logging
from pathlib import Path

import sqlalchemy as sa
from sqlalchemy.sql import text as sql_text
from sqlalchemy.types import BOOLEAN
from sqlalchemy.types import CHAR
from sqlalchemy.types import SMALLINT
from sqlalchemy.types import TEXT
from sqlalchemy.types import VARCHAR

from hive.conf import SCHEMA_NAME
from hive.conf import SCHEMA_OWNER_NAME

from hive.indexer.hive_db.haf_functions import prepare_app_context

from hive.version import GIT_DATE, GIT_REVISION, VERSION

log = logging.getLogger(__name__)

# pylint: disable=line-too-long, too-many-lines, bad-whitespace


def build_metadata():
    """Build schema def with SqlAlchemy"""
    metadata = sa.MetaData(schema=SCHEMA_NAME)
    hive_rowid_seq = sa.Sequence('hive.hivemind_app_hive_rowid_seq', metadata=metadata)

    sa.Table(
        'hive_accounts',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True), # warning this ID does not match to hive.accounts::id
        sa.Column('haf_id', sa.Integer, nullable=True), # Account ID matching hive.accounts::id
        sa.Column('name', VARCHAR(16, collation='C'), nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        # sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('followers', sa.Integer, nullable=False, server_default='0'),
        sa.Column('following', sa.Integer, nullable=False, server_default='0'),
        sa.Column('rank', sa.Integer, nullable=False, server_default='0'),
        sa.Column('lastread_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('posting_json_metadata', sa.Text),
        sa.Column('json_metadata', sa.Text),
        sa.UniqueConstraint('name', name='hive_accounts_ux1'),
        sa.Index('hive_accounts_haf_id_idx', 'haf_id'),
    )

    sa.Table(
        'hive_posts',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('root_id', sa.Integer, nullable=False),  # records having initially set 0 will be updated to their id
        sa.Column('parent_id', sa.Integer, nullable=False),
        sa.Column('author_id', sa.Integer, nullable=False),
        sa.Column('permlink_id', sa.Integer, nullable=False),
        sa.Column('category_id', sa.Integer, nullable=False),
        sa.Column('community_id', sa.Integer, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('depth', SMALLINT, nullable=False),
        sa.Column('counter_deleted', sa.Integer, nullable=False, server_default='0'),
        sa.Column('is_pinned', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_muted', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('muted_reasons', sa.Integer, nullable=False, server_default='0'),
        sa.Column('is_valid', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('promoted', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('children', sa.Integer, nullable=False, server_default='0'),
        # core stats/indexes
        sa.Column('payout', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('pending_payout', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('payout_at', sa.DateTime, nullable=False, server_default='1970-01-01'),
        sa.Column('last_payout_at', sa.DateTime, nullable=False, server_default='1970-01-01'),
        sa.Column('updated_at', sa.DateTime, nullable=False, server_default='1970-01-01'),
        sa.Column('is_paidout', BOOLEAN, nullable=False, server_default='0'),
        # ui flags/filters
        sa.Column('is_nsfw', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_declined', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_full_power', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_hidden', BOOLEAN, nullable=False, server_default='0'),
        # important indexes
        sa.Column('sc_trend', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('sc_hot', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('total_payout_value', sa.String(30), nullable=False, server_default='0.000 HBD'),
        sa.Column('author_rewards', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_hive', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_hbd', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_vests', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('abs_rshares', sa.Numeric, nullable=False, server_default='0'),
        sa.Column('vote_rshares', sa.Numeric, nullable=False, server_default='0'),
        sa.Column('total_vote_weight', sa.Numeric, nullable=False, server_default='0'),
        sa.Column('total_votes', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('net_votes', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('active', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('cashout_time', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('percent_hbd', sa.Integer, nullable=False, server_default='10000'),
        sa.Column('curator_payout_value', sa.String(30), nullable=False, server_default='0.000 HBD'),
        sa.Column('max_accepted_payout', sa.String(30), nullable=False, server_default='1000000.000 HBD'),
        sa.Column('allow_votes', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('allow_curation_rewards', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('beneficiaries', sa.JSON, nullable=False, server_default='[]'),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('block_num_created', sa.Integer, nullable=False),
        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id'], name='hive_posts_fk1', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['root_id'], ['hive_posts.id'], name='hive_posts_fk2', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['parent_id'], ['hive_posts.id'], name='hive_posts_fk3', deferrable=True, postgresql_not_valid=True),
        sa.UniqueConstraint('author_id', 'permlink_id', 'counter_deleted', name='hive_posts_ux1'),
        sa.Index('hive_posts_depth_idx', 'depth'),
        sa.Index('hive_posts_root_id_id_idx', 'root_id', 'id'),
        sa.Index(
            'hive_posts_parent_id_id_idx',
            sa.text('parent_id, id DESC'),
            postgresql_where=sql_text("counter_deleted = 0"),
        ),

        # used by i.e. bridge_get_ranked_post_by_created_for_observer_communities
        sa.Index('hive_posts_community_id_id_idx', sa.text('community_id, id DESC'),
            postgresql_where=sql_text("counter_deleted = 0")),

        sa.Index('hive_posts_community_id_is_pinned_idx', 'community_id',
            postgresql_include=['id'],
            postgresql_where=sql_text("is_pinned AND counter_deleted = 0")),

        # dedicated to bridge_get_ranked_post_by_created_for_community
        sa.Index('hive_posts_community_id_not_is_pinned_idx', sa.text('community_id, id DESC'),
            postgresql_where=sql_text("NOT is_pinned and depth = 0 and counter_deleted = 0")),

        # Specific to bridge_get_ranked_post_by_trends_for_community
        sa.Index('hive_posts_community_id_not_is_paidout_idx', 'community_id',
            postgresql_include=['id'],
            postgresql_where=sql_text("NOT is_paidout AND depth = 0 AND counter_deleted = 0")),

        sa.Index('hive_posts_payout_at_idx', 'payout_at'),
        sa.Index('hive_posts_payout_idx', 'payout'),
        sa.Index(
            'hive_posts_promoted_id_idx',
            'promoted',
            'id',
            postgresql_where=sql_text("NOT is_paidout AND counter_deleted = 0"),
        ),
        sa.Index(
            'hive_posts_sc_trend_id_idx',
            'sc_trend',
            'id',
            postgresql_where=sql_text("NOT is_paidout AND counter_deleted = 0 AND depth = 0"),
        ),
        sa.Index(
            'hive_posts_sc_hot_id_idx',
            'sc_hot',
            'id',
            postgresql_where=sql_text("NOT is_paidout AND counter_deleted = 0 AND depth = 0"),
        ),
        sa.Index('hive_posts_author_id_created_at_id_idx', sa.text('author_id DESC, created_at DESC, id')),
        # bridge_get_account_posts_by_comments, bridge_get_account_posts_by_posts

        sa.Index('hive_posts_author_id_id_idx', sa.text('author_id, id DESC'), postgresql_where=sql_text('counter_deleted = 0')),

        sa.Index('hive_posts_block_num_idx', 'block_num'),
        sa.Index('hive_posts_block_num_created_idx', 'block_num_created'),
        sa.Index('hive_posts_cashout_time_id_idx', 'cashout_time', 'id'),
        sa.Index('hive_posts_updated_at_idx', sa.text('updated_at DESC')),
        sa.Index(
            'hive_posts_payout_plus_pending_payout_id_idx',
            sa.text('(payout+pending_payout), id'),
            postgresql_where=sql_text("NOT is_paidout AND counter_deleted = 0"),
        ),
        sa.Index(
            'hive_posts_category_id_payout_plus_pending_payout_depth_idx',
            sa.text('category_id, (payout+pending_payout), depth'),
            postgresql_where=sql_text("NOT is_paidout AND counter_deleted = 0"),
        )
    )

    sa.Table(
        'hive_post_data',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('title', VARCHAR(512), nullable=False, server_default=''),
        sa.Column('preview', VARCHAR(1024), nullable=False, server_default=''),  # first 1k of 'body'
        sa.Column('img_url', VARCHAR(1024), nullable=False, server_default=''),  # first 'image' from 'json'
        sa.Column('body', TEXT, nullable=False, server_default=''),
        sa.Column('json', TEXT, nullable=False, server_default=''),
    )

    sa.Table(
        'hive_permlink_data',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('permlink', sa.String(255, collation='C'), nullable=False),
        sa.UniqueConstraint('permlink', name='hive_permlink_data_permlink'),
    )

    sa.Table(
        'hive_category_data',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('category', sa.String(255, collation='C'), nullable=False),
        sa.UniqueConstraint('category', name='hive_category_data_category'),
    )

    sa.Table(
        'hive_votes',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.BigInteger, primary_key=True),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('voter_id', sa.Integer, nullable=False),
        sa.Column('author_id', sa.Integer, nullable=False),
        sa.Column('permlink_id', sa.Integer, nullable=False),
        sa.Column('weight', sa.Numeric, nullable=False, server_default='0'),
        sa.Column('rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('vote_percent', sa.Integer, server_default='0'),
        sa.Column('last_update', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('num_changes', sa.Integer, server_default='0'),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('is_effective', BOOLEAN, nullable=False, server_default='0'),
        sa.UniqueConstraint(
            'voter_id', 'author_id', 'permlink_id', name='hive_votes_voter_id_author_id_permlink_id_uk'
        ),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_votes_fk1', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['voter_id'], ['hive_accounts.id'], name='hive_votes_fk2', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id'], name='hive_votes_fk3', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['permlink_id'], ['hive_permlink_data.id'], name='hive_votes_fk4', deferrable=True, postgresql_not_valid=True),
        sa.Index(
            'hive_votes_voter_id_post_id_idx', 'voter_id', 'post_id'
        ),  # probably this index is redundant to hive_votes_voter_id_last_update_idx because of starting voter_id.
        sa.Index(
            'hive_votes_voter_id_last_update_idx', 'voter_id', 'last_update'
        ),  # this index is critical for hive_accounts_info_view performance
        sa.Index('hive_votes_post_id_voter_id_idx', 'post_id', 'voter_id'),
        sa.Index('hive_votes_block_num_idx', 'block_num'),  # this is also important for hive_accounts_info_view
        sa.Index(
            'hive_votes_post_id_block_num_rshares_vote_is_effective_idx',
            'post_id',
            'block_num',
            'rshares',
            'is_effective',
        ),  # this index is needed by update_posts_rshares procedure.
    )

    sa.Table(
        'hive_post_tags',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('tag_id', sa.Integer, nullable=False),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_post_tags_fk1', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['tag_id'], ['hive_tag_data.id'], name='hive_post_tags_fk2', deferrable=True, postgresql_not_valid=True),
        sa.Index('hive_post_tags_idx', 'post_id', 'tag_id', postgresql_using='btree')
    )

    sa.Table(
        'hive_tag_data',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, nullable=False, primary_key=True),
        sa.Column('tag', VARCHAR(64, collation='C'), nullable=False, server_default=''),
        sa.UniqueConstraint('tag', name='hive_tag_data_ux1'),
    )

    sa.Table(
        'hive_follows',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('follower', sa.Integer, nullable=False),
        sa.Column('following', sa.Integer, nullable=False),
        sa.Column('state', SMALLINT, nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('blacklisted', sa.Boolean, nullable=False, server_default='0'),
        sa.Column('follow_blacklists', sa.Boolean, nullable=False, server_default='0'),
        sa.Column('follow_muted', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.UniqueConstraint('following', 'follower', name='hive_follows_ux1'),  # core
        sa.Index('hive_follows_following_state_id_idx', 'following', 'state', 'id'), # index used by condenser_get_followers
        sa.Index('hive_follows_follower_state_idx', 'follower', 'state'),
        sa.Index('hive_follows_follower_following_state_idx', 'follower', 'following', 'state'),
        sa.Index('hive_follows_block_num_idx', 'block_num'),
        sa.Index('hive_follows_created_at_idx', 'created_at'),
        sa.Index('hive_follows_follower_where_blacklisted_idx', 'follower', postgresql_where=sql_text('blacklisted')),
        sa.Index('hive_follows_follower_where_follow_muted_idx', 'follower', postgresql_where=sql_text('follow_muted')),
        sa.Index('hive_follows_follower_where_follow_blacklists_idx', 'follower', postgresql_where=sql_text('follow_blacklists')),
    )

    sa.Table(
        'hive_reblogs',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('blogger_id', sa.Integer, nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.ForeignKeyConstraint(['blogger_id'], ['hive_accounts.id'], name='hive_reblogs_fk1', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_reblogs_fk2', deferrable=True, postgresql_not_valid=True),
        sa.UniqueConstraint('blogger_id', 'post_id', name='hive_reblogs_ux1'),  # core
        sa.Index('hive_reblogs_post_id', 'post_id'),
        sa.Index('hive_reblogs_block_num_idx', 'block_num'),
        sa.Index('hive_reblogs_created_at_idx', 'created_at'),
    )

    sa.Table(
        'hive_payments',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('tx_idx', SMALLINT, nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('from_account', sa.Integer, nullable=False),
        sa.Column('to_account', sa.Integer, nullable=False),
        sa.Column('amount', sa.types.DECIMAL(10, 3), nullable=False),
        sa.Column('token', VARCHAR(5), nullable=False),
        sa.ForeignKeyConstraint(['from_account'], ['hive_accounts.id'], name='hive_payments_fk1', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['to_account'], ['hive_accounts.id'], name='hive_payments_fk2', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_payments_fk3', deferrable=True, postgresql_not_valid=True),
        sa.Index('hive_payments_from', 'from_account'),
        sa.Index('hive_payments_to', 'to_account'),
        sa.Index('hive_payments_post_id', 'post_id'),
    )

    sa.Table(
        'hive_feed_cache',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.PrimaryKeyConstraint('account_id', 'post_id', name='hive_feed_cache_pk'),
        sa.Index('hive_feed_cache_block_num_idx', 'block_num'),
        sa.Index('hive_feed_cache_created_at_idx', 'created_at'),
        sa.Index('hive_feed_cache_post_id_idx', 'post_id'),
        # Dedicated index to bridge_get_account_posts_by_blog
        sa.Index('hive_feed_cache_account_id_created_at_post_id_idx',
          sa.text('account_id, created_at DESC, post_id DESC')),
    )

    sa.Table(
        'hive_state',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('last_completed_block_num', sa.Integer, nullable=False),
        sa.Column('db_version', sa.Integer, nullable=False),
        sa.Column('hivemind_version', sa.Text, nullable=False, server_default=''),
        sa.Column('hivemind_git_date', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('hivemind_git_rev', sa.Text, nullable=False, server_default=''),
    )

    sa.Table(
        'hive_posts_api_helper',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column(
            'author_s_permlink', VARCHAR(275, collation='C'), nullable=False
        ),  # concatenation of author '/' permlink
        sa.Index('hive_posts_api_helper_author_s_permlink_idx', 'author_s_permlink'),
    )

    sa.Table(
        'hive_mentions',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_mentions_fk1', deferrable=True, postgresql_not_valid=True),
        sa.ForeignKeyConstraint(['account_id'], ['hive_accounts.id'], name='hive_mentions_fk2', deferrable=True, postgresql_not_valid=True),
        sa.Index('hive_mentions_account_id_idx', 'account_id'),
        sa.UniqueConstraint('post_id', 'account_id', 'block_num', name='hive_mentions_ux1'),
    )

    metadata = build_metadata_community(hive_rowid_seq, metadata)

    return metadata


def build_metadata_community(hive_rowid_seq: sa.Sequence, metadata=None):
    """Build community schema defs"""
    if not metadata:
        metadata = sa.MetaData()

    sa.Table(
        'hive_communities',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('type_id', SMALLINT, nullable=False),
        sa.Column('lang', CHAR(2), nullable=False, server_default='en'),
        sa.Column('name', VARCHAR(16, collation='C'), nullable=False),
        sa.Column('title', sa.String(32), nullable=False, server_default=''),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('sum_pending', sa.Integer, nullable=False, server_default='0'),
        sa.Column('num_pending', sa.Integer, nullable=False, server_default='0'),
        sa.Column('num_authors', sa.Integer, nullable=False, server_default='0'),
        sa.Column('rank', sa.Integer, nullable=False, server_default='0'),
        sa.Column('subscribers', sa.Integer, nullable=False, server_default='0'),
        sa.Column('is_nsfw', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('about', sa.String(120), nullable=False, server_default=''),
        sa.Column('primary_tag', sa.String(32), nullable=False, server_default=''),
        sa.Column('category', sa.String(32), nullable=False, server_default=''),
        sa.Column('avatar_url', sa.String(1024), nullable=False, server_default=''),
        sa.Column('description', sa.String(5000), nullable=False, server_default=''),
        sa.Column('flag_text', sa.String(5000), nullable=False, server_default=''),
        sa.Column('settings', TEXT, nullable=False, server_default='{}'),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.UniqueConstraint('name', name='hive_communities_ux1'),
        sa.Index('hive_communities_ix1', 'rank', 'id'),
        sa.Index('hive_communities_block_num_idx', 'block_num'),
    )

    sa.Table(
        'hive_roles',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('community_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('role_id', SMALLINT, nullable=False, server_default='0'),
        sa.Column('title', sa.String(140), nullable=False, server_default=''),
        sa.PrimaryKeyConstraint('account_id', 'community_id', name='hive_roles_pk'),
        sa.Index('hive_roles_ix1', 'community_id', 'account_id', 'role_id'),
    )

    sa.Table(
        'hive_subscriptions',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('community_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.UniqueConstraint('account_id', 'community_id', name='hive_subscriptions_ux1'),
        sa.Index('hive_subscriptions_community_idx', 'community_id'),
        sa.Index('hive_subscriptions_block_num_idx', 'block_num'),
    )

    sa.Table(
        'hive_notifs',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('type_id', SMALLINT, nullable=False),
        sa.Column('score', SMALLINT, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('src_id', sa.Integer, nullable=True),
        sa.Column('dst_id', sa.Integer, nullable=True),
        sa.Column('post_id', sa.Integer, nullable=True),
        sa.Column('community_id', sa.Integer, nullable=True),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('payload', sa.Text, nullable=True),
        sa.Index('hive_notifs_ix1', 'dst_id', 'id', postgresql_where=sql_text("dst_id IS NOT NULL")),
        sa.Index('hive_notifs_ix2', 'community_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL")),
        sa.Index(
            'hive_notifs_ix3', 'community_id', 'type_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL")
        ),
        sa.Index(
            'hive_notifs_ix4',
            'community_id',
            'post_id',
            'type_id',
            'id',
            postgresql_where=sql_text("community_id IS NOT NULL AND post_id IS NOT NULL"),
        ),
        sa.Index(
            'hive_notifs_ix5',
            'post_id',
            'type_id',
            'dst_id',
            'src_id',
            postgresql_where=sql_text("post_id IS NOT NULL AND type_id IN (16,17)"),
        ),  # filter: dedupe
        sa.Index(
            'hive_notifs_ix6', 'dst_id', 'created_at', 'score', 'id', postgresql_where=sql_text("dst_id IS NOT NULL")
        ),  # unread
    )

    sa.Table(
        'hive_notification_cache',
        metadata,
        sa.Column('hive_rowid', sa.BigInteger, server_default=hive_rowid_seq.next_value(), nullable=False),
        sa.Column('id', sa.BigInteger, primary_key=True),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('type_id', sa.Integer, nullable=False),
        sa.Column('dst', sa.Integer, nullable=True),  # dst account id except persistent notifs from hive_notifs
        sa.Column('src', sa.Integer, nullable=True),  # src account id
        sa.Column('dst_post_id', sa.Integer, nullable=True),  # destination post id
        sa.Column('post_id', sa.Integer, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False),  # notification creation time
        sa.Column('score', sa.Integer, nullable=False),
        sa.Column('community_title', sa.String(32), nullable=True),
        sa.Column('community', sa.String(16), nullable=True),
        sa.Column('payload', sa.String, nullable=True),
        sa.Index('hive_notification_cache_block_num_idx', 'block_num'),
        sa.Index('hive_notification_cache_dst_score_idx', 'dst', 'score', postgresql_where=sql_text("dst IS NOT NULL")),
    )

    return metadata


def teardown(db):
    """Drop all tables"""
    build_metadata().drop_all(db.engine())


def drop_fk(db):
    for table in build_metadata().sorted_tables:
        for fk in table.foreign_keys:
            sql = f"""ALTER TABLE {SCHEMA_NAME}.{table.name} DROP CONSTRAINT IF EXISTS {fk.name}"""
            db.query_no_return(sql)


def create_fk(db):
    from sqlalchemy.schema import AddConstraint
    from sqlalchemy.engine.reflection import Inspector

    inspector =  Inspector.from_engine( db.engine() )

    for table in build_metadata().sorted_tables:
        if inspector.get_foreign_keys( table.name, SCHEMA_NAME ):
            return # foreign keys already enabled
        for fk in table.foreign_keys:
            db.query_no_return(AddConstraint(fk.constraint), is_prepared=True)


def setup(db, admin_db):
    """Creates all tables and seed data"""

    # create schema and aux functions
    admin_db.query(f'CREATE SCHEMA IF NOT EXISTS {SCHEMA_NAME} AUTHORIZATION {SCHEMA_OWNER_NAME};')
    admin_db.query(f'CREATE SCHEMA IF NOT EXISTS hivemind_endpoints AUTHORIZATION {SCHEMA_OWNER_NAME};')
    admin_db.query(f'CREATE SCHEMA IF NOT EXISTS hivemind_postgrest_utilities AUTHORIZATION {SCHEMA_OWNER_NAME};')

    prepare_app_context(db=db)
    build_metadata().create_all(db.engine())

    # tune auto vacuum/analyze
    reset_autovac(db)

    # sets FILLFACTOR:
    set_fillfactor(db)

    # apply inheritance
    for table in build_metadata().sorted_tables:
        if table.name in ('hive_db_patch_level',):
            continue

        sql = f'ALTER TABLE {SCHEMA_NAME}.{table.name} INHERIT {SCHEMA_NAME}.{SCHEMA_NAME};'
        db.query(sql)


    # default rows
    sqls = [
        f"INSERT INTO {SCHEMA_NAME}.hive_state (last_completed_block_num, db_version, hivemind_git_rev, hivemind_git_date, hivemind_version) VALUES (1, 0, '{GIT_REVISION}', '{GIT_DATE}', '{VERSION}')",
        f"INSERT INTO {SCHEMA_NAME}.hive_permlink_data (id, permlink) VALUES (0, '')",
        f"INSERT INTO {SCHEMA_NAME}.hive_category_data (id, category) VALUES (0, '')",
        f"INSERT INTO {SCHEMA_NAME}.hive_tag_data (id, tag) VALUES (0, '')",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (id, name, created_at) VALUES (0, '', '1970-01-01T00:00:00')",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('miners',    '2016-03-24 16:05:00')",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('null',      '2016-03-24 16:05:00')",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('temp',      '2016-03-24 16:05:00')",
        f"INSERT INTO {SCHEMA_NAME}.hive_accounts (name, created_at) VALUES ('initminer', '2016-03-24 16:05:00')",
        f"""
        INSERT INTO
            {SCHEMA_NAME}.hive_posts(id, root_id, parent_id, author_id, permlink_id, category_id,
                community_id, created_at, depth, block_num, block_num_created
            )
        VALUES
            (0, 0, 0, 0, 0, 0, 0, now(), 0, 0, 0);
        """,
    ]
    for sql in sqls:
        db.query(sql)

    sql = f"CREATE INDEX hive_communities_ft1 ON {SCHEMA_NAME}.hive_communities USING GIN (to_tsvector('english', title || ' ' || about))"
    db.query(sql)

    # find_comment_id definition moved to utility_functions.sql
    # find_account_id definition moved to utility_functions.sql

    # process_hive_post_operation definition moved to hive_post_operations.sql
    # delete_hive_post moved to hive_post_operations.sql

    # In original hivemind, a value of 'active_at' was calculated from
    # max
    #   {
    #     created             ( account_create_operation ),
    #     last_account_update ( account_update_operation/account_update2_operation ),
    #     last_post           ( comment_operation - only creation )
    #     last_root_post      ( comment_operation - only creation + only ROOT ),
    #     last_vote_time      ( vote_operation )
    #   }
    # In order to simplify calculations, `last_account_update` is not taken into consideration, because this updating accounts is very rare
    # and posting/voting after an account updating, fixes `active_at` value immediately.

    # hive_accounts_view definition moved to hive_accounts_view.sql

    # hive_posts_view definition moved to hive_posts_view.sql

    # update_hive_posts_root_id moved to update_hive_posts_root_id.sql

    # hive_votes_view definition moved into hive_votes_view.sql

    # database_api_vote, find_votes, list_votes_by_voter_comment, list_votes_by_comment_voter moved into database_api_list_votes.sql

    # reputation removed from hive_accounts, index on reputation is created on reptracker's table

    sql = f"""
          CREATE TABLE IF NOT EXISTS {SCHEMA_NAME}.hive_db_patch_level
          (
            level SERIAL NOT NULL PRIMARY KEY,
            patch_date timestamp without time zone NOT NULL,
            patched_to_revision TEXT
          );
    """
    db.query_no_return(sql)

    # sqlalchemy doesn't allow to use DESC in CreateUnique
    sql = f"""
        CREATE UNIQUE INDEX IF NOT EXISTS hive_post_tags_tag_id_post_id_idx
        ON {SCHEMA_NAME}.hive_post_tags USING btree (tag_id, post_id DESC)
        """
    db.query_no_return(sql)

def setup_runtime_code(db):
    sql_scripts = [
        "utility_functions.sql",
        "hive_accounts_view.sql",
        "hive_accounts_info_view.sql",
        "hive_posts_base_view.sql",
        "hive_posts_view.sql",
        "hive_votes_view.sql",
        "hive_muted_accounts_view.sql",
        "hive_muted_accounts_by_id_view.sql",
        "hive_blacklisted_accounts_by_observer_view.sql",
        "get_post_view_by_id.sql",
        "hive_post_operations.sql",
        "head_block_time.sql",
        "update_feed_cache.sql",
        "payout_stats_view.sql",
        "update_hive_posts_mentions.sql",
        "mutes.sql",
        "bridge_get_reblog_count.sql",
        "bridge_get_ranked_post_type.sql",
        "bridge_get_ranked_post_for_communities.sql",
        "bridge_get_ranked_post_for_observer_communities.sql",
        "bridge_get_ranked_post_for_tag.sql",
        "bridge_get_ranked_post_for_all.sql",
        "update_communities_rank.sql",
        "delete_hive_posts_mentions.sql",
        "notifications_view.sql",
        "notifications_api.sql",
        "bridge_get_account_posts_by_comments.sql",
        "bridge_get_account_posts_by_payout.sql",
        "bridge_get_account_posts_by_posts.sql",
        "bridge_get_account_posts_by_replies.sql",
        "bridge_get_relationship_between_accounts.sql",
        "bridge_get_post.sql",
        "bridge_get_discussion.sql",
        "condenser_api_post_type.sql",
        "condenser_api_post_ex_type.sql",
        "condenser_get_blog.sql",
        "condenser_get_content.sql",
        "condenser_tags.sql",
        "condenser_follows.sql",
        "hot_and_trends.sql",
        "update_hive_posts_children_count.sql",
        "update_hive_posts_api_helper.sql",
        "database_api_list_comments.sql",
        "database_api_list_votes.sql",
        "update_posts_rshares.sql",
        "update_hive_post_root_id.sql",
        "condenser_get_by_account_comments.sql",
        "condenser_get_by_blog_without_reblog.sql",
        "bridge_get_by_feed_with_reblog.sql",
        "condenser_get_by_blog.sql",
        "bridge_get_account_posts_by_blog.sql",
        "condenser_get_names_by_reblogged.sql",
        "condenser_get_account_reputations.sql",
        "bridge_get_community.sql",
        "bridge_get_community_context.sql",
        "bridge_list_all_subscriptions.sql",
        "bridge_list_communities.sql",
        "bridge_list_community_roles.sql",
        "bridge_list_pop_communities.sql",
        "bridge_list_subscribers.sql",
        "update_follow_count.sql",
        "delete_reblog_feed_cache.sql",
        "follows.sql",
        "is_superuser.sql",
        "update_hive_blocks_consistency_flag.sql",
        "postgrest/home.sql",
        "update_table_statistics.sql",
        "upgrade/update_db_patchlevel.sql",  # Additionally execute db patchlevel import to mark (already done) upgrade changes and avoid its reevaluation during next upgrade.
        "hafapp_api.sql",
        "postgrest/utilities/exceptions.sql",
        "postgrest/utilities/validate_json_parameters.sql",
        "postgrest/utilities/parse_argument_from_json.sql",
        "postgrest/utilities/valid_account.sql",
        "postgrest/utilities/find_account_id.sql",
        "postgrest/condenser_api/condenser_api_get_follow_count.sql",
        "postgrest/utilities/find_comment_id.sql",
        "postgrest/utilities/valid_permlink.sql",
        "postgrest/condenser_api/condenser_api_get_reblogged_by.sql",
        "postgrest/utilities/valid_number.sql",
        "postgrest/utilities/valid_tag.sql",
        "postgrest/utilities/find_category_id.sql",
        "postgrest/condenser_api/condenser_api_get_trending_tags.sql",
        "postgrest/utilities/get_state_tools.sql",
        "postgrest/condenser_api/condenser_api_get_state.sql",
        "postgrest/condenser_api/condenser_api_get_account_reputations.sql",
        "postgrest/utilities/check_community.sql",
        "postgrest/utilities/valid_community.sql",
        "postgrest/utilities/valid_limit.sql",
        "postgrest/utilities/json_date.sql",
        "postgrest/utilities/community.sql",
        "postgrest/bridge_api/bridge_api_get_community.sql",
        "postgrest/bridge_api/bridge_api_get_community_context.sql",
        "postgrest/utilities/dispatch.sql",
        "postgrest/utilities/get_api_method.sql",
        "postgrest/utilities/check_general_json_format.sql",
        "postgrest/utilities/valid_offset.sql",
        "postgrest/utilities/list_votes.sql",
        "postgrest/utilities/assets_operations.sql",
        "postgrest/utilities/create_condenser_post_object.sql",
        "postgrest/condenser_api/condenser_api_get_blog.sql",
        "postgrest/condenser_api/condenser_api_get_content.sql",
        "postgrest/utilities/valid_follow_type.sql",
        "postgrest/utilities/follow_arguments.sql",
        "postgrest/condenser_api/condenser_api_get_followers.sql",
        "postgrest/condenser_api/condenser_api_get_following.sql",
        "postgrest/utilities/vote_arguments.sql",
        "postgrest/database_api/database_api_find_votes.sql",
        "postgrest/database_api/database_api_list_votes.sql",
        "postgrest/condenser_api/condenser_api_get_active_votes.sql",
        "postgrest/utilities/rep_log10.sql",
        "postgrest/utilities/muted_reasons_operations.sql",
        "postgrest/utilities/create_bridge_post_object.sql",
        "postgrest/bridge_api/bridge_api_get_post.sql",
        "postgrest/bridge_api/bridge_api_get_payout_stats.sql",
        "postgrest/hive_api/hive_api_get_info.sql",
        "postgrest/hive_api/hive_api_db_head_state.sql",
        "postgrest/utilities/get_account_posts.sql",
        "postgrest/bridge_api/bridge_api_get_account_posts.sql",
        "postgrest/bridge_api/bridge_api_get_relationship_between_accounts.sql",
        "postgrest/bridge_api/bridge_api_unread_notifications.sql",
    ]

    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'
    for script in sql_scripts:
        execute_sql_script(db.query_no_return, sql_scripts_dir_path / script)

    # Move this part here, to mark latest db patch level as current Hivemind revision (which just created schema).
    sql = f"""
          INSERT INTO {SCHEMA_NAME}.hive_db_patch_level
          (patch_date, patched_to_revision)
          select ds.patch_date, ds.patch_revision
          from
          (
          values
          (now(), '{{}}')
          ) ds (patch_date, patch_revision)
          WHERE NOT EXISTS (SELECT NULL FROM hivemind_app.hive_db_patch_level hpl WHERE hpl.patched_to_revision = ds.patch_revision);
          ;
          """

    # Update hivemind_app.hive_stats table
    sql_hive_state_update = f"""
                            UPDATE {SCHEMA_NAME}.hive_state
                            SET
                                hivemind_git_date = CASE
                                    WHEN hivemind_git_date != '{GIT_DATE}' THEN '{GIT_DATE}'
                                    ELSE hivemind_git_date
                                END,
                                hivemind_git_rev = CASE
                                    WHEN hivemind_git_rev != '{GIT_REVISION}' THEN '{GIT_REVISION}'
                                    ELSE hivemind_git_rev
                                END,
                                hivemind_version = CASE
                                    WHEN hivemind_version != '{VERSION}' THEN '{VERSION}'
                                    ELSE hivemind_version
                                END
                            WHERE hivemind_git_date != '{GIT_DATE}'
                                OR hivemind_git_rev != '{GIT_REVISION}'
                                OR hivemind_version != '{VERSION}';
                            """

    db.query_no_return(sql.format(GIT_REVISION))
    db.query_no_return(sql_hive_state_update)


def perform_db_upgrade(db, admin_db):
    sql_scripts_dir_path = Path(__file__).parent /'sql_scripts'

    sql_scripts = [
        "postgres_handle_view_changes.sql",
        "upgrade/upgrade_table_schema.sql",
        "upgrade/upgrade_runtime_migration.sql"
    ]

    sql_scripts_dir_path = Path(__file__).parent / 'sql_scripts'
    for script in sql_scripts:
        execute_sql_script(admin_db.query_no_return, sql_scripts_dir_path / script)

    log.info(f"Database schema upgrade completed.")

    needs_vacuum = admin_db.query_one('SELECT COALESCE((SELECT hd.vacuum_needed FROM hivemind_app.hive_db_vacuum_needed hd WHERE hd.vacuum_needed LIMIT 1), False) AS needs_vacuum')

    if needs_vacuum:
         log.info(f"Attempting to run VACUUM FULL on upgraded database")
         admin_db.query_no_return("VACUUM FULL VERBOSE ANALYZE;")
    else:
        log.info(f"Skipping VACUUM FULL on upgraded database (no vacuum request)")

def reset_autovac(db):
    """Initializes/resets per-table autovacuum/autoanalyze params.

    We use a scale factor of 0 and specify exact threshold tuple counts,
    per-table, in the format (autovacuum_threshold, autoanalyze_threshold)."""

    autovac_config = {  # vacuum  analyze
        'hive_accounts': (50000, 100000),
        'hive_posts': (2500, 10000),
        'hive_post_tags': (5000, 10000),
        'hive_follows': (5000, 5000),
        'hive_feed_cache': (5000, 5000),
        'hive_reblogs': (5000, 5000),
        'hive_payments': (5000, 5000),
    }

    for table, (n_vacuum, n_analyze) in autovac_config.items():
        sql = f"""
ALTER TABLE {SCHEMA_NAME}.{table} SET (autovacuum_vacuum_scale_factor = 0,
                                  autovacuum_vacuum_threshold = {n_vacuum},
                                  autovacuum_analyze_scale_factor = 0,
                                  autovacuum_analyze_threshold = {n_analyze});
"""
        db.query(sql)


def set_fillfactor(db):
    """Initializes/resets FILLFACTOR for tables which are intesively updated"""

    fillfactor_config = {'hive_posts': 70, 'hive_post_data': 70, 'hive_votes': 70}

    for table, fillfactor in fillfactor_config.items():
        sql = f"ALTER TABLE {SCHEMA_NAME}.{table} SET (FILLFACTOR = {fillfactor});"
        db.query(sql)


def set_logged_table_attribute(db, logged):
    """Initializes/resets LOGGED/UNLOGGED attribute for tables which are intesively updated"""

    logged_config = [
        'hive_accounts',
        'hive_permlink_data',
        'hive_post_tags',
        'hive_posts',
        'hive_post_data',
        'hive_votes',
    ]

    for table in logged_config:
        log.info(f"Setting {'LOGGED' if logged else 'UNLOGGED'} attribute on a table: {table}")
        sql = """ALTER TABLE {} SET {}"""
        db.query_no_return(sql.format(table, 'LOGGED' if logged else 'UNLOGGED'))


def execute_sql_script(query_executor, path_to_script):
    """Load and execute sql script from file
    Params:
      query_executor - callable to execute query with
      path_to_script - path to script
    Returns:
      depending on query_executor

    Example:
      print(execute_sql_script(db.query_row, "./test.sql"))
      where test_sql: SELECT * FROM hive_state WHERE block_num = 0;
      will return something like: (0, 18, Decimal('0.000000'), Decimal('0.000000'), Decimal('0.000000'), '')
    """
    try:
        sql_script = None
        with open(path_to_script, 'r') as sql_script_file:
            sql_script = sql_script_file.read()
        if sql_script is not None:
            return query_executor(sql_script)
    except Exception as ex:
        log.exception(f"Error running sql script: {ex}")
        raise ex
    return None
