"""Db schema definitions and setup routines."""

import sqlalchemy as sa
from sqlalchemy.sql import text as sql_text
from sqlalchemy.types import SMALLINT
from sqlalchemy.types import CHAR
from sqlalchemy.types import VARCHAR
from sqlalchemy.types import TEXT
from sqlalchemy.types import BOOLEAN

#pylint: disable=line-too-long, too-many-lines, bad-whitespace

# [DK] we changed and removed some tables so i upgraded DB_VERSION to 18
DB_VERSION = 18

def build_metadata():
    """Build schema def with SqlAlchemy"""
    metadata = sa.MetaData()

    sa.Table(
        'hive_blocks', metadata,
        sa.Column('num', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('hash', CHAR(40), nullable=False),
        sa.Column('prev', CHAR(40)),
        sa.Column('txs', SMALLINT, server_default='0', nullable=False),
        sa.Column('ops', SMALLINT, server_default='0', nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),

        sa.UniqueConstraint('hash', name='hive_blocks_ux1'),
        sa.ForeignKeyConstraint(['prev'], ['hive_blocks.hash'], name='hive_blocks_fk1'),
    )

    sa.Table(
        'hive_accounts', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('name', VARCHAR(16), nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        #sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('reputation', sa.Float(precision=6), nullable=False, server_default='25'),

        sa.Column('display_name', sa.String(20)),
        sa.Column('about', sa.String(160)),
        sa.Column('location', sa.String(30)),
        sa.Column('website', sa.String(1024)),
        sa.Column('profile_image', sa.String(1024), nullable=False, server_default=''),
        sa.Column('cover_image', sa.String(1024), nullable=False, server_default=''),

        sa.Column('followers', sa.Integer, nullable=False, server_default='0'),
        sa.Column('following', sa.Integer, nullable=False, server_default='0'),

        sa.Column('proxy', VARCHAR(16), nullable=False, server_default=''),
        sa.Column('post_count', sa.Integer, nullable=False, server_default='0'),
        sa.Column('proxy_weight', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('vote_weight', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('kb_used', sa.Integer, nullable=False, server_default='0'), # deprecated
        sa.Column('rank', sa.Integer, nullable=False, server_default='0'),

        sa.Column('lastread_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('active_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('cached_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('raw_json', sa.Text),

        sa.UniqueConstraint('name', name='hive_accounts_ux1'),
        sa.Index('hive_accounts_ix1', 'vote_weight'), # core: quick ranks
        sa.Index('hive_accounts_ix5', 'cached_at'), # core/listen sweep
    )

    sa.Table(
        'hive_posts', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('parent_id', sa.Integer),
        sa.Column('author_id', sa.Integer, nullable=False),
        sa.Column('permlink_id', sa.BigInteger, nullable=False),
        sa.Column('category_id', sa.Integer, nullable=False),
        sa.Column('community_id', sa.Integer, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('depth', SMALLINT, nullable=False),
        sa.Column('is_pinned', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_muted', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_valid', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('promoted', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),

        sa.Column('children', sa.Integer, nullable=False, server_default='0'),

        # basic/extended-stats
        sa.Column('author_rep', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('flag_weight', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('total_votes', sa.Integer, nullable=False, server_default='0'),
        sa.Column('up_votes', sa.Integer, nullable=False, server_default='0'),

        # core stats/indexes
        sa.Column('payout', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('pending_payout', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('payout_at', sa.DateTime, nullable=False, server_default='1970-01-01'),
        sa.Column('updated_at', sa.DateTime, nullable=False, server_default='1970-01-01'),
        sa.Column('is_paidout', BOOLEAN, nullable=False, server_default='0'),

        # ui flags/filters
        sa.Column('is_nsfw', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_declined', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_full_power', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_hidden', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_grayed', BOOLEAN, nullable=False, server_default='0'),

        # important indexes
        sa.Column('sc_trend', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('sc_hot', sa.Float(precision=6), nullable=False, server_default='0'),

        sa.Column('total_payout_value', sa.String(30), nullable=False, server_default=''),
        sa.Column('author_rewards', sa.BigInteger, nullable=False, server_default='0'),

        sa.Column('author_rewards_hive', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_hbd', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_vests', sa.BigInteger, nullable=False, server_default='0'),

        sa.Column('children_abs_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('abs_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('vote_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('net_votes', sa.Integer, nullable=False, server_default='0'),
        sa.Column('active', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('cashout_time', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('max_cashout_time', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('percent_hbd', sa.Integer, nullable=False, server_default='10000'),
        sa.Column('reward_weight', sa.Integer, nullable=False, server_default='10000'), # Seems to be always 10000

        sa.Column('parent_author_id', sa.Integer, nullable=False),
        sa.Column('parent_permlink_id', sa.BigInteger, nullable=False),
        sa.Column('curator_payout_value', sa.String(30), nullable=False, server_default=''),
        sa.Column('root_author_id', sa.Integer, nullable=False),
        sa.Column('root_permlink_id', sa.BigInteger, nullable=False),
        sa.Column('max_accepted_payout',  sa.String(30), nullable=False, server_default='1000000.000 HBD'),
        sa.Column('allow_replies', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('allow_votes', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('allow_curation_rewards', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('beneficiaries', sa.JSON, nullable=False, server_default='[]'),
        sa.Column('url', sa.Text, nullable=False, server_default=''),
        sa.Column('root_title', sa.String(255), nullable=False, server_default=''),

        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id'], name='hive_posts_fk1'),
        sa.ForeignKeyConstraint(['parent_id'], ['hive_posts.id'], name='hive_posts_fk3'),
        sa.UniqueConstraint('author_id', 'permlink_id', name='hive_posts_ux1'),
        sa.Index('hive_posts_permlink_id', 'permlink_id'),

        sa.Index('hive_posts_depth_idx', 'depth'),
        sa.Index('hive_posts_parent_id_idx', 'parent_id'),
        sa.Index('hive_posts_community_id_idx', 'community_id'),
        sa.Index('hive_posts_author_id', 'author_id'),

        sa.Index('hive_posts_category_id_idx', 'category_id'),
        sa.Index('hive_posts_payout_at_idx', 'payout_at'),
        sa.Index('hive_posts_payout_idx', 'payout'),
        sa.Index('hive_posts_promoted_idx', 'promoted'),
        sa.Index('hive_posts_sc_trend_idx', 'sc_trend'),
        sa.Index('hive_posts_sc_hot_idx', 'sc_hot'),
        sa.Index('hive_posts_created_at_idx', 'created_at'),

        sa.Index('hive_posts_root_author_id', 'root_author_id'),
        sa.Index('hive_posts_root_permlink_id', 'root_permlink_id'),
        sa.Index('hive_posts_parent_author_id', 'parent_author_id'),
        sa.Index('hive_posts_parent_permlink_id', 'parent_permlink_id')
    )

    sa.Table(
        'deleted_hive_posts', metadata,
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('parent_id', sa.Integer),
        sa.Column('author_id', sa.Integer, nullable=False),
        sa.Column('permlink_id', sa.BigInteger, nullable=False),
        sa.Column('category_id', sa.Integer, nullable=False),
        sa.Column('community_id', sa.Integer, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('depth', SMALLINT, nullable=False),
        sa.Column('is_pinned', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_muted', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_valid', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('promoted', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),

        sa.Column('children', SMALLINT, nullable=False, server_default='0'),

        # basic/extended-stats
        sa.Column('author_rep', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('flag_weight', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('total_votes', sa.Integer, nullable=False, server_default='0'),
        sa.Column('up_votes', sa.Integer, nullable=False, server_default='0'),

        # core stats/indexes
        sa.Column('payout', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('pending_payout', sa.types.DECIMAL(10, 3), nullable=False, server_default='0'),
        sa.Column('payout_at', sa.DateTime, nullable=False, server_default='1990-01-01'),
        sa.Column('updated_at', sa.DateTime, nullable=False, server_default='1990-01-01'),
        sa.Column('is_paidout', BOOLEAN, nullable=False, server_default='0'),

        # ui flags/filters
        sa.Column('is_nsfw', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_declined', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_full_power', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_hidden', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('is_grayed', BOOLEAN, nullable=False, server_default='0'),

        # important indexes
        sa.Column('sc_trend', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('sc_hot', sa.Float(precision=6), nullable=False, server_default='0'),

        sa.Column('total_payout_value', sa.String(30), nullable=False, server_default=''),
        sa.Column('author_rewards', sa.BigInteger, nullable=False, server_default='0'),

        sa.Column('author_rewards_hive', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_hbd', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_vests', sa.BigInteger, nullable=False, server_default='0'),

        sa.Column('children_abs_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('abs_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('vote_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('net_votes', sa.Integer, nullable=False, server_default='0'),
        sa.Column('active', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('last_payout', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('cashout_time', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('max_cashout_time', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('percent_hbd', sa.Integer, nullable=False, server_default='10000'),
        sa.Column('reward_weight', sa.Integer, nullable=False, server_default='0'),

        sa.Column('parent_author_id', sa.Integer, nullable=False),
        sa.Column('parent_permlink_id', sa.BigInteger, nullable=False),
        sa.Column('curator_payout_value', sa.String(30), nullable=False, server_default=''),
        sa.Column('root_author_id', sa.Integer, nullable=False),
        sa.Column('root_permlink_id', sa.BigInteger, nullable=False),
        sa.Column('max_accepted_payout',  sa.String(30), nullable=False, server_default='1000000.000 HBD'),
        sa.Column('allow_replies', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('allow_votes', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('allow_curation_rewards', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('beneficiaries', sa.JSON, nullable=False, server_default='[]'),
        sa.Column('url', sa.Text, nullable=False, server_default=''),
        sa.Column('root_title', sa.String(255), nullable=False, server_default=''),

        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id'], name='deleted_hive_posts_fk1'),
        sa.Index('deleted_hive_posts_permlink_id', 'permlink_id'),

        sa.Index('deleted_hive_posts_depth_idx', 'depth'),
        sa.Index('deleted_hive_posts_parent_id_idx', 'parent_id'),
        sa.Index('deleted_hive_posts_community_id_idx', 'community_id'),
        sa.Index('deleted_hive_posts_author_id', 'author_id'),

        sa.Index('deleted_hive_posts_category_id_idx', 'category_id'),
        sa.Index('deleted_hive_posts_payout_at_idx', 'payout_at'),
        sa.Index('deleted_hive_posts_payout_idx', 'payout'),
        sa.Index('deleted_hive_posts_promoted_idx', 'promoted'),
        sa.Index('deleted_hive_posts_sc_trend_idx', 'sc_trend'),
        sa.Index('deleted_hive_posts_sc_hot_idx', 'sc_hot'),
        sa.Index('deleted_hive_posts_created_at_idx', 'created_at'),
    )

    sa.Table(
        'hive_post_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('title', VARCHAR(512), nullable=False, server_default=''),
        sa.Column('preview', VARCHAR(1024), nullable=False, server_default=''),
        sa.Column('img_url', VARCHAR(1024), nullable=False, server_default=''),
        sa.Column('body', TEXT, nullable=False, server_default=''),
        sa.Column('json', TEXT, nullable=False, server_default='')
    )

    sa.Table(
        'deleted_hive_post_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('title', VARCHAR(512), nullable=False, server_default=''),
        sa.Column('preview', VARCHAR(1024), nullable=False, server_default=''),
        sa.Column('img_url', VARCHAR(1024), nullable=False, server_default=''),
        sa.Column('body', TEXT, nullable=False, server_default=''),
        sa.Column('json', TEXT, nullable=False, server_default='')
    )

    sa.Table(
        'hive_permlink_data', metadata,
        sa.Column('id', sa.BigInteger, primary_key=True),
        sa.Column('permlink', sa.String(255), nullable=False),
        sa.UniqueConstraint('permlink', name='hive_permlink_data_permlink')
    )

    sa.Table(
        'hive_category_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('category', sa.String(255), nullable=False),
        sa.UniqueConstraint('category', name='hive_category_data_category')
    )

    sa.Table(
        'hive_votes', metadata,
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

        sa.UniqueConstraint('voter_id', 'author_id', 'permlink_id', name='hive_votes_ux1'),

        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(['voter_id'], ['hive_accounts.id']),
        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id']),
        sa.ForeignKeyConstraint(['permlink_id'], ['hive_permlink_data.id']),

        sa.Index('hive_votes_post_id_idx', 'post_id'),
        sa.Index('hive_votes_voter_id_idx', 'voter_id'),
        sa.Index('hive_votes_author_id_idx', 'author_id'),
        sa.Index('hive_votes_permlink_id_idx', 'permlink_id'),
        sa.Index('hive_votes_upvote_idx', 'vote_percent', postgresql_where=sql_text("vote_percent > 0")),
        sa.Index('hive_votes_downvote_idx', 'vote_percent', postgresql_where=sql_text("vote_percent < 0"))
    )

    sa.Table(
        'deleted_hive_votes', metadata,
        sa.Column('id', sa.BigInteger, primary_key=True, autoincrement=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('voter_id', sa.Integer, nullable=False),
        sa.Column('author_id', sa.Integer, nullable=False),
        sa.Column('permlink_id', sa.Integer, nullable=False),
        sa.Column('weight', sa.Numeric, nullable=False, server_default='0'),
        sa.Column('rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('vote_percent', sa.Integer, server_default='0'),
        sa.Column('last_update', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('num_changes', sa.Integer, server_default='0'),

        sa.ForeignKeyConstraint(['post_id'], ['deleted_hive_posts.id']),
        sa.ForeignKeyConstraint(['voter_id'], ['hive_accounts.id']),
        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id']),
        sa.ForeignKeyConstraint(['permlink_id'], ['hive_permlink_data.id']),

        sa.Index('deleted_hive_votes_post_id_idx', 'post_id'),
        sa.Index('deleted_hive_votes_voter_id_idx', 'voter_id'),
        sa.Index('deleted_hive_votes_author_id_idx', 'author_id'),
        sa.Index('deleted_hive_votes_permlink_id_idx', 'permlink_id'),
        sa.Index('deleted_hive_votes_upvote_idx', 'vote_percent', postgresql_where=sql_text("vote_percent > 0")),
        sa.Index('deleted_hive_votes_downvote_idx', 'vote_percent', postgresql_where=sql_text("vote_percent < 0"))
    )

    sa.Table(
        'hive_tag_data', metadata,
        sa.Column('id', sa.Integer, nullable=False, primary_key=True),
        sa.Column('tag', VARCHAR(64), nullable=False, server_default=''),
        sa.UniqueConstraint('tag', name='hive_tag_data_ux1')
    )

    sa.Table(
        'hive_post_tags', metadata,
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('tag_id', sa.Integer, nullable=False),
        sa.PrimaryKeyConstraint('post_id', 'tag_id', name='hive_post_tags_pk1'),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(['tag_id'], ['hive_tag_data.id']),
        sa.Index('hive_post_tags_post_id_idx', 'post_id'),
        sa.Index('hive_post_tags_tag_id_idx', 'tag_id')
    )

    sa.Table(
        'deleted_hive_post_tags', metadata,
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('tag_id', sa.Integer, nullable=False),
        sa.ForeignKeyConstraint(['post_id'], ['deleted_hive_posts.id']),
        sa.ForeignKeyConstraint(['tag_id'], ['hive_tag_data.id']),
        sa.Index('deleted_hive_post_tags_post_id_idx', 'post_id'),
        sa.Index('deleted_hive_post_tags_tag_id_idx', 'tag_id')
    )

    sa.Table(
        'hive_follows', metadata,
        sa.Column('follower', sa.Integer, nullable=False),
        sa.Column('following', sa.Integer, nullable=False),
        sa.Column('state', SMALLINT, nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('blacklisted', sa.Boolean, nullable=False, server_default='0'),
        sa.Column('follow_blacklists', sa.Boolean, nullable=False, server_default='0'),

        sa.PrimaryKeyConstraint('following', 'follower', name='hive_follows_pk'), # core
        sa.Index('hive_follows_ix5a', 'following', 'state', 'created_at', 'follower'),
        sa.Index('hive_follows_ix5b', 'follower', 'state', 'created_at', 'following'),
    )

    sa.Table(
        'hive_reblogs', metadata,
        sa.Column('account', VARCHAR(16), nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),

        sa.ForeignKeyConstraint(['account'], ['hive_accounts.name'], name='hive_reblogs_fk1'),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_reblogs_fk2', ondelete="CASCADE"),
        sa.PrimaryKeyConstraint('account', 'post_id', name='hive_reblogs_pk'), # core
        sa.Index('hive_reblogs_account', 'account'),
        sa.Index('hive_reblogs_post_id', 'post_id'),
    )

    sa.Table(
        'deleted_hive_reblogs', metadata,
        sa.Column('account', VARCHAR(16), nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),

        sa.ForeignKeyConstraint(['account'], ['hive_accounts.name'], name='deleted_hive_reblogs_fk1'),
        sa.ForeignKeyConstraint(['post_id'], ['deleted_hive_posts.id'], name='deleted_hive_reblogs_fk2'),
        sa.Index('deleted_hive_reblogs_account', 'account'),
        sa.Index('deleted_hive_reblogs_post_id', 'post_id'),
    )

    sa.Table(
        'hive_payments', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('tx_idx', SMALLINT, nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('from_account', sa.Integer, nullable=False),
        sa.Column('to_account', sa.Integer, nullable=False),
        sa.Column('amount', sa.types.DECIMAL(10, 3), nullable=False),
        sa.Column('token', VARCHAR(5), nullable=False),

        sa.ForeignKeyConstraint(['from_account'], ['hive_accounts.id'], name='hive_payments_fk1'),
        sa.ForeignKeyConstraint(['to_account'], ['hive_accounts.id'], name='hive_payments_fk2'),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_payments_fk3', ondelete="CASCADE"),
        sa.Index('hive_payments_from', 'from_account'),
        sa.Index('hive_payments_to', 'to_account'),
        sa.Index('hive_payments_post_id', 'post_id'),
    )

    sa.Table(
        'deleted_hive_payments', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('block_num', sa.Integer, nullable=False),
        sa.Column('tx_idx', SMALLINT, nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('from_account', sa.Integer, nullable=False),
        sa.Column('to_account', sa.Integer, nullable=False),
        sa.Column('amount', sa.types.DECIMAL(10, 3), nullable=False),
        sa.Column('token', VARCHAR(5), nullable=False),

        sa.ForeignKeyConstraint(['from_account'], ['hive_accounts.id'], name='deleted_hive_payments_fk1'),
        sa.ForeignKeyConstraint(['to_account'], ['hive_accounts.id'], name='deleted_hive_payments_fk2'),
        sa.ForeignKeyConstraint(['post_id'], ['deleted_hive_posts.id'], name='deleted_hive_payments_fk3'),
        sa.Index('deleted_hive_payments_from', 'from_account'),
        sa.Index('deleted_hive_payments_to', 'to_account'),
        sa.Index('deleted_hive_payments_post_id', 'post_id'),
    )

    sa.Table(
        'hive_feed_cache', metadata,
        sa.Column('post_id', sa.Integer, nullable=False, primary_key=True),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Index('hive_feed_cache_account_id', 'account_id'), # API (and rebuild?)
        sa.UniqueConstraint('account_id', 'post_id', name='hive_feed_cache_ux1')
    )

    sa.Table(
        'deleted_hive_feed_cache', metadata,
        sa.Column('post_id', sa.Integer, nullable=False, primary_key=True, autoincrement=False),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Index('deleted_hive_feed_cache_account_id', 'account_id'), # API (and rebuild?)
    )

    sa.Table(
        'hive_state', metadata,
        sa.Column('block_num', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('db_version', sa.Integer, nullable=False),
        sa.Column('steem_per_mvest', sa.types.DECIMAL(14, 6), nullable=False),
        sa.Column('usd_per_steem', sa.types.DECIMAL(14, 6), nullable=False),
        sa.Column('sbd_per_steem', sa.types.DECIMAL(14, 6), nullable=False),
        sa.Column('dgpo', sa.Text, nullable=False),
    )

    metadata = build_metadata_community(metadata)

    return metadata

def build_metadata_community(metadata=None):
    """Build community schema defs"""
    if not metadata:
        metadata = sa.MetaData()

    sa.Table(
        'hive_communities', metadata,
        sa.Column('id',          sa.Integer,      primary_key=True, autoincrement=False),
        sa.Column('type_id',     SMALLINT,        nullable=False),
        sa.Column('lang',        CHAR(2),         nullable=False, server_default='en'),
        sa.Column('name',        VARCHAR(16),     nullable=False),
        sa.Column('title',       sa.String(32),   nullable=False, server_default=''),
        sa.Column('created_at',  sa.DateTime,     nullable=False),
        sa.Column('sum_pending', sa.Integer,      nullable=False, server_default='0'),
        sa.Column('num_pending', sa.Integer,      nullable=False, server_default='0'),
        sa.Column('num_authors', sa.Integer,      nullable=False, server_default='0'),
        sa.Column('rank',        sa.Integer,      nullable=False, server_default='0'),
        sa.Column('subscribers', sa.Integer,      nullable=False, server_default='0'),
        sa.Column('is_nsfw',     BOOLEAN,         nullable=False, server_default='0'),
        sa.Column('about',       sa.String(120),  nullable=False, server_default=''),
        sa.Column('primary_tag', sa.String(32),   nullable=False, server_default=''),
        sa.Column('category',    sa.String(32),   nullable=False, server_default=''),
        sa.Column('avatar_url',  sa.String(1024), nullable=False, server_default=''),
        sa.Column('description', sa.String(5000), nullable=False, server_default=''),
        sa.Column('flag_text',   sa.String(5000), nullable=False, server_default=''),
        sa.Column('settings',    TEXT,            nullable=False, server_default='{}'),

        sa.UniqueConstraint('name', name='hive_communities_ux1'),
        sa.Index('hive_communities_ix1', 'rank', 'id')
    )

    sa.Table(
        'hive_roles', metadata,
        sa.Column('account_id',   sa.Integer,     nullable=False),
        sa.Column('community_id', sa.Integer,     nullable=False),
        sa.Column('created_at',   sa.DateTime,    nullable=False),
        sa.Column('role_id',      SMALLINT,       nullable=False, server_default='0'),
        sa.Column('title',        sa.String(140), nullable=False, server_default=''),

        sa.PrimaryKeyConstraint('account_id', 'community_id', name='hive_roles_pk'),
        sa.Index('hive_roles_ix1', 'community_id', 'account_id', 'role_id'),
    )

    sa.Table(
        'hive_subscriptions', metadata,
        sa.Column('account_id',   sa.Integer,  nullable=False),
        sa.Column('community_id', sa.Integer,  nullable=False),
        sa.Column('created_at',   sa.DateTime, nullable=False),

        sa.UniqueConstraint('account_id', 'community_id', name='hive_subscriptions_ux1'),
        sa.Index('hive_subscriptions_ix1', 'community_id', 'account_id', 'created_at'),
    )

    sa.Table(
        'hive_notifs', metadata,
        sa.Column('id',           sa.Integer,  primary_key=True),
        sa.Column('type_id',      SMALLINT,    nullable=False),
        sa.Column('score',        SMALLINT,    nullable=False),
        sa.Column('created_at',   sa.DateTime, nullable=False),
        sa.Column('src_id',       sa.Integer,  nullable=True),
        sa.Column('dst_id',       sa.Integer,  nullable=True),
        sa.Column('post_id',      sa.Integer,  nullable=True),
        sa.Column('community_id', sa.Integer,  nullable=True),
        sa.Column('block_num',    sa.Integer,  nullable=True),
        sa.Column('payload',      sa.Text,     nullable=True),

        sa.Index('hive_notifs_ix1', 'dst_id',                  'id', postgresql_where=sql_text("dst_id IS NOT NULL")),
        sa.Index('hive_notifs_ix2', 'community_id',            'id', postgresql_where=sql_text("community_id IS NOT NULL")),
        sa.Index('hive_notifs_ix3', 'community_id', 'type_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL")),
        sa.Index('hive_notifs_ix4', 'community_id', 'post_id', 'type_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL AND post_id IS NOT NULL")),
        sa.Index('hive_notifs_ix5', 'post_id', 'type_id', 'dst_id', 'src_id', postgresql_where=sql_text("post_id IS NOT NULL AND type_id IN (16,17)")), # filter: dedupe
        sa.Index('hive_notifs_ix6', 'dst_id', 'created_at', 'score', 'id', postgresql_where=sql_text("dst_id IS NOT NULL")), # unread
    )

    sa.Table(
        'deleted_hive_notifs', metadata,
        sa.Column('id',           sa.Integer,  primary_key=True, autoincrement=False),
        sa.Column('type_id',      SMALLINT,    nullable=False),
        sa.Column('score',        SMALLINT,    nullable=False),
        sa.Column('created_at',   sa.DateTime, nullable=False),
        sa.Column('src_id',       sa.Integer,  nullable=True),
        sa.Column('dst_id',       sa.Integer,  nullable=True),
        sa.Column('post_id',      sa.Integer,  nullable=True),
        sa.Column('community_id', sa.Integer,  nullable=True),
        sa.Column('block_num',    sa.Integer,  nullable=True),
        sa.Column('payload',      sa.Text,     nullable=True),

        sa.Index('deleted_hive_notifs_ix1', 'dst_id',                  'id', postgresql_where=sql_text("dst_id IS NOT NULL")),
        sa.Index('deleted_hive_notifs_ix2', 'community_id',            'id', postgresql_where=sql_text("community_id IS NOT NULL")),
        sa.Index('deleted_hive_notifs_ix3', 'community_id', 'type_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL")),
        sa.Index('deleted_hive_notifs_ix4', 'community_id', 'post_id', 'type_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL AND post_id IS NOT NULL")),
        sa.Index('deleted_hive_notifs_ix5', 'post_id', 'type_id', 'dst_id', 'src_id', postgresql_where=sql_text("post_id IS NOT NULL AND type_id IN (16,17)")), # filter: dedupe
        sa.Index('deleted_hive_notifs_ix6', 'dst_id', 'created_at', 'score', 'id', postgresql_where=sql_text("dst_id IS NOT NULL")), # unread
    )

    return metadata


def teardown(db):
    """Drop all tables"""
    build_metadata().drop_all(db.engine())

def setup(db):
    """Creates all tables and seed data"""
    # initialize schema
    build_metadata().create_all(db.engine())

    # tune auto vacuum/analyze
    reset_autovac(db)

    # default rows
    sqls = [
        "INSERT INTO hive_state (block_num, db_version, steem_per_mvest, usd_per_steem, sbd_per_steem, dgpo) VALUES (0, %d, 0, 0, 0, '')" % DB_VERSION,
        "INSERT INTO hive_blocks (num, hash, created_at) VALUES (0, '0000000000000000000000000000000000000000', '2016-03-24 16:04:57')",

        "INSERT INTO hive_permlink_data (id, permlink) VALUES (0, '')",
        "INSERT INTO hive_category_data (id, category) VALUES (0, '')",
        "INSERT INTO hive_accounts (id, name, created_at) VALUES (0, '', '1970-01-01T00:00:00')",

        "INSERT INTO hive_accounts (name, created_at) VALUES ('miners',    '2016-03-24 16:05:00')",
        "INSERT INTO hive_accounts (name, created_at) VALUES ('null',      '2016-03-24 16:05:00')",
        "INSERT INTO hive_accounts (name, created_at) VALUES ('temp',      '2016-03-24 16:05:00')",
        "INSERT INTO hive_accounts (name, created_at) VALUES ('initminer', '2016-03-24 16:05:00')",

        """
        INSERT INTO
            public.hive_posts(id, parent_id, author_id, permlink_id, category_id,
                community_id, parent_author_id, parent_permlink_id, root_author_id,
                root_permlink_id, created_at, depth
            )
        VALUES
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, now(), 0);
        """,
        """
        INSERT INTO
            public.deleted_hive_posts(id, parent_id, author_id, permlink_id, category_id,
                community_id, parent_author_id, parent_permlink_id, root_author_id,
                root_permlink_id, created_at, depth
            )
        VALUES
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, now(), 0);
        """]
    for sql in sqls:
        db.query(sql)

    sql = "CREATE INDEX hive_communities_ft1 ON hive_communities USING GIN (to_tsvector('english', title || ' ' || about))"
    db.query(sql)

    sql = """
          DROP FUNCTION if exists process_hive_post_operation(character varying,character varying,character varying,character varying,timestamp without time zone,timestamp without time zone)
          ;
          CREATE OR REPLACE FUNCTION process_hive_post_operation(
            in _author hive_accounts.name%TYPE,
            in _permlink hive_permlink_data.permlink%TYPE,
            in _parent_author hive_accounts.name%TYPE,
            in _parent_permlink hive_permlink_data.permlink%TYPE,
            in _date hive_posts.created_at%TYPE,
            in _community_support_start_date hive_posts.created_at%TYPE)
          RETURNS TABLE (is_new_post boolean, id hive_posts.id%TYPE, author_id hive_posts.author_id%TYPE, permlink_id hive_posts.permlink_id%TYPE,
                         post_category hive_category_data.category%TYPE, parent_id hive_posts.parent_id%TYPE, community_id hive_posts.community_id%TYPE,
                         is_valid hive_posts.is_valid%TYPE, is_muted hive_posts.is_muted%TYPE, depth hive_posts.depth%TYPE,
                         is_edited boolean)
          LANGUAGE plpgsql
          AS
          $function$
          BEGIN

          INSERT INTO hive_permlink_data
          (permlink)
          values
          (
          _permlink
          )
          ON CONFLICT DO NOTHING
          ;
          if _parent_author != '' THEN
            RETURN QUERY INSERT INTO hive_posts as hp
            (parent_id, parent_author_id, parent_permlink_id, depth, community_id,
             category_id,
             root_author_id, root_permlink_id,
             is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend,active, payout_at, cashout_time)
            SELECT php.id AS parent_id, php.author_id as parent_author_id,
                php.permlink_id as parent_permlink_id, php.depth + 1 as depth,
                (CASE
                WHEN _date > _community_support_start_date THEN
                  COALESCE(php.community_id, (select hc.id from hive_communities hc where hc.name = _parent_permlink))
                ELSE NULL
              END)  as community_id,
                COALESCE(php.category_id, (select hcg.id from hive_category_data hcg where hcg.category = _parent_permlink)) as category_id,
                php.root_author_id as root_author_id,
                php.root_permlink_id as root_permlink_id,
                php.is_muted as is_muted, php.is_valid as is_valid,
                ha.id as author_id, hpd.id as permlink_id, _date as created_at,
                _date as updated_at, calculate_time_part_of_hot(_date) as sc_hot,
                 calculate_time_part_of_trending(_date) as sc_trend,
                _date as active, (_date + INTERVAL '7 days') as payout_at, (_date + INTERVAL '7 days') as cashout_time
            FROM hive_accounts ha,
                 hive_permlink_data hpd,
                 hive_posts php
            INNER JOIN hive_accounts pha ON pha.id = php.author_id
            INNER JOIN hive_permlink_data phpd ON phpd.id = php.permlink_id
            WHERE pha.name = _parent_author and phpd.permlink = _parent_permlink AND
                   ha.name = _author and hpd.permlink = _permlink

            ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
              --- During post update it is disallowed to change: parent-post, category, community-id
              --- then also depth, is_valid and is_muted is impossible to change
             --- post edit part
             updated_at = _date,
             active = _date,

              --- post undelete part (if was deleted)
              is_pinned = hp.is_pinned

            RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, (SELECT hcd.category FROM hive_category_data hcd WHERE hcd.id = hp.category_id) as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth, (hp.updated_at > hp.created_at) as is_edited
          ;
          ELSE
            INSERT INTO hive_category_data
            (category)
            VALUES (_parent_permlink)
            ON CONFLICT (category) DO NOTHING
            ;

            RETURN QUERY INSERT INTO hive_posts as hp
            (parent_id, parent_author_id, parent_permlink_id, depth, community_id,
             category_id,
             root_author_id, root_permlink_id,
             is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time)
            SELECT 0 AS parent_id, 0 as parent_author_id, 0 as parent_permlink_id, 0 as depth,
                (CASE
                  WHEN _date > _community_support_start_date THEN
                    (select hc.id from hive_communities hc where hc.name = _parent_permlink)
                  ELSE NULL
                END)  as community_id,
                (select hcg.id from hive_category_data hcg where hcg.category = _parent_permlink) as category_id,
                ha.id as root_author_id, -- use author_id as root one if no parent
                hpd.id as root_permlink_id, -- use perlink_id as root one if no parent
                false as is_muted, true as is_valid,
                ha.id as author_id, hpd.id as permlink_id, _date as created_at,
                _date as updated_at, calculate_time_part_of_hot(_date) as sc_hot,
                  calculate_time_part_of_trending(_date) as sc_trend,
                _date as active, (_date + INTERVAL '7 days') as payout_at, (_date + INTERVAL '7 days') as cashout_time
            FROM hive_accounts ha,
                 hive_permlink_data hpd
            WHERE ha.name = _author and hpd.permlink = _permlink

            ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
              --- During post update it is disallowed to change: parent-post, category, community-id
              --- then also depth, is_valid and is_muted is impossible to change
              --- post edit part
              updated_at = _date,
              active = _date,

              --- post undelete part (if was deleted)
              is_pinned = hp.is_pinned

            RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth, (hp.updated_at > hp.created_at) as is_edited
            ;
          END IF;
          END
          $function$
    """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION IF EXISTS process_deleted_hive_post();

          CREATE OR REPLACE FUNCTION process_deleted_hive_post( int[] )
          RETURNS integer
          LANGUAGE plpgsql
          AS
          $function$
          DECLARE rows integer;
          BEGIN
            INSERT INTO deleted_hive_posts
            (
              id,
              parent_id,
              author_id,
              permlink_id,
              category_id,
              community_id,
              created_at,
              depth,
              is_pinned,
              is_muted,
              is_valid,
              promoted,
              children,
              author_rep,
              flag_weight,
              total_votes,
              up_votes,
              payout,
              pending_payout,
              payout_at,
              updated_at,
              is_paidout,
              is_nsfw,
              is_declined,
              is_full_power,
              is_hidden,
              is_grayed,
              sc_trend,
              sc_hot,
              total_payout_value,
              author_rewards,
              author_rewards_hive,
              author_rewards_hbd,
              author_rewards_vests,
              children_abs_rshares,
              abs_rshares,
              vote_rshares,
              net_votes,
              active,
              cashout_time,
              max_cashout_time,
              percent_hbd,
              reward_weight,
              parent_author_id,
              parent_permlink_id,
              curator_payout_value,
              root_author_id,
              root_permlink_id,
              max_accepted_payout,
              allow_replies,
              allow_votes,
              allow_curation_rewards,
              beneficiaries,
              url,
              root_title
            )
            SELECT
              id,
              parent_id,
              author_id,
              permlink_id,
              category_id,
              community_id,
              created_at,
              depth,
              is_pinned,
              is_muted,
              is_valid,
              promoted,
              children,
              author_rep,
              flag_weight,
              total_votes,
              up_votes,
              payout,
              pending_payout,
              payout_at,
              updated_at,
              is_paidout,
              is_nsfw,
              is_declined,
              is_full_power,
              is_hidden,
              is_grayed,
              sc_trend,
              sc_hot,
              total_payout_value,
              author_rewards,
              author_rewards_hive,
              author_rewards_hbd,
              author_rewards_vests,
              children_abs_rshares,
              abs_rshares,
              vote_rshares,
              net_votes,
              active,
              cashout_time,
              max_cashout_time,
              percent_hbd,
              reward_weight,
              parent_author_id,
              parent_permlink_id,
              curator_payout_value,
              root_author_id,
              root_permlink_id,
              max_accepted_payout,
              allow_replies,
              allow_votes,
              allow_curation_rewards,
              beneficiaries,
              url,
              root_title
            FROM hive_posts
            WHERE id = ANY( $1 );

            INSERT INTO deleted_hive_votes
            SELECT
              hv.id,
              hv.post_id,
              hv.voter_id,
              hv.author_id,
              hv.permlink_id,
              hv.weight,
              hv.rshares,
              hv.vote_percent,
              hv.last_update,
              hv.num_changes
            FROM hive_votes hv
            INNER JOIN hive_posts hp ON hv.post_id = hp.id
            WHERE hp.id = ANY( $1 );

            INSERT INTO deleted_hive_feed_cache
              SELECT
                hfc.post_id,
                hfc.account_id,
                hfc.created_at
              FROM hive_feed_cache hfc
              INNER JOIN hive_posts hp ON hfc.post_id = hp.id
              WHERE hp.id = ANY( $1 );

            INSERT INTO deleted_hive_notifs
              SELECT
                hn.id,
                hn.type_id,
                hn.score,
                hn.created_at,
                hn.src_id,
                hn.dst_id,
                hn.post_id,
                hn.community_id,
                hn.block_num,
                hn.payload
              FROM hive_notifs hn
              INNER JOIN hive_posts hp ON hn.post_id = hp.id
              WHERE hp.id = ANY( $1 );

            INSERT INTO deleted_hive_payments
              SELECT
                hps.id,
                hps.block_num,
                hps.tx_idx,
                hps.post_id,
                hps.from_account,
                hps.to_account,
                hps.amount,
                hps.token
              FROM hive_payments hps
              INNER JOIN hive_posts hp ON hps.post_id = hp.id
              WHERE hp.id = ANY( $1 );

            INSERT INTO deleted_hive_post_data
              SELECT
                hpd.id,
                hpd.title,
                hpd.preview,
                hpd.img_url,
                hpd.body,
                hpd.json
              FROM hive_post_data hpd
              INNER JOIN hive_posts hp ON hpd.id = hp.id
              WHERE hp.id = ANY( $1 );

            INSERT INTO deleted_hive_post_tags
              SELECT
                hpt.post_id,
                hpt.tag_id
              FROM hive_post_tags hpt
              INNER JOIN hive_posts hp ON hpt.post_id = hp.id
              WHERE hp.id = ANY( $1 );

            INSERT INTO deleted_hive_reblogs
              SELECT
                hr.account,
                hr.post_id,
                hr.created_at
              FROM hive_reblogs hr
              INNER JOIN hive_posts hp ON hr.post_id = hp.id
              WHERE hp.id = ANY( $1 );

            DELETE FROM hive_feed_cache WHERE post_id = ANY( $1 );

            DELETE FROM hive_notifs WHERE post_id = ANY( $1 );

            DELETE FROM hive_post_data WHERE id = ANY( $1 );

            UPDATE hive_posts
            SET parent_id = 0
            WHERE parent_id = ANY( $1 );

            DELETE
              FROM hive_posts
              WHERE id = ANY( $1 );

            GET DIAGNOSTICS rows = ROW_COUNT;

            RETURN rows;

          END
          $function$
          """
    db.query_no_return(sql)

    sql = """
        DROP VIEW IF EXISTS public.hive_posts_view;

        CREATE OR REPLACE VIEW public.hive_posts_view
          AS
          SELECT hp.id,
            hp.community_id,
            hp.parent_id,
            ha_a.name AS author,
            hp.active,
            hp.author_rewards,
            hp.author_id,
            hpd_p.permlink,
            hpd.title,
            hpd.body,
            hpd.img_url,
            hpd.preview,
            hcd.category,
            hp.depth,
            hp.promoted,
            hp.payout,
            hp.pending_payout,
            hp.payout_at,
            hp.is_paidout,
            hp.children,
            0 AS votes,
            0 AS active_votes,
            hp.created_at,
            hp.updated_at,
            COALESCE(
              (
                SELECT SUM( v.rshares )
                FROM hive_votes v
                WHERE v.post_id = hp.id
                GROUP BY v.post_id
              ), 0
            ) AS rshares,
            hpd.json,
            ha_a.reputation AS author_rep,
            hp.is_hidden,
            hp.is_grayed,
            hp.total_votes,
            hp.flag_weight,
            ha_pa.name AS parent_author,
            hpd_pp.permlink AS parent_permlink,
            hp.curator_payout_value,
            ha_ra.name AS root_author,
            hpd_rp.permlink AS root_permlink,
            rcd.category as root_category,
            hp.max_accepted_payout,
            hp.percent_hbd,
            hp.allow_replies,
            hp.allow_votes,
            hp.allow_curation_rewards,
            hp.beneficiaries,
            concat('/', rcd.category, '/@', ha_ra.name, '/', hpd_rp.permlink,
              case (rp.id)
                  when hp.id then ''
                    else concat('#@', ha_a.name, '/', hpd_p.permlink)
              end ) as url,
            rpd.title AS root_title,
            hp.sc_trend,
            hp.sc_hot,
            hp.is_pinned,
            hp.is_muted,
            hp.is_nsfw,
            hp.is_valid,
            hr.title AS role_title,
            hr.role_id AS role_id,
            hc.title AS community_title,
            hc.name AS community_name,
            hp.abs_rshares,
            hp.cashout_time,
            hp.max_cashout_time,
            hp.reward_weight
            FROM hive_posts hp
            JOIN hive_posts rp ON rp.author_id = hp.root_author_id AND rp.permlink_id = hp.root_permlink_id
            JOIN hive_post_data rpd ON rp.id = rpd.id
            JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
            JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
            JOIN hive_post_data hpd ON hpd.id = hp.id
            LEFT JOIN hive_category_data hcd ON hcd.id = hp.category_id
            LEFT JOIN hive_category_data rcd ON rcd.id = rp.category_id
            JOIN hive_accounts ha_pa ON ha_pa.id = hp.parent_author_id
            JOIN hive_permlink_data hpd_pp ON hpd_pp.id = hp.parent_permlink_id
            JOIN hive_accounts ha_ra ON ha_ra.id = hp.root_author_id
            JOIN hive_permlink_data hpd_rp ON hpd_rp.id = hp.root_permlink_id
            LEFT OUTER JOIN hive_communities hc ON (hp.community_id = hc.id)
            LEFT OUTER JOIN hive_roles hr ON (hp.author_id = hr.account_id AND hp.community_id = hr.community_id)
            ;
          """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION IF EXISTS public.update_hive_posts_children_count();

          CREATE OR REPLACE FUNCTION public.update_hive_posts_children_count()
              RETURNS void
              LANGUAGE 'plpgsql'
              VOLATILE
          AS $BODY$
          BEGIN

          UPDATE hive_posts uhp
          SET children = data_source.children_count
          FROM
          (
            WITH recursive tblChild AS
            (
              SELECT s.queried_parent, s.id
              FROM
              (SELECT h1.Parent_Id AS queried_parent, h1.id
               FROM hive_posts h1
               WHERE h1.depth > 0
               ORDER BY h1.depth DESC
              ) s
              UNION ALL
              SELECT tblChild.queried_parent, p.id FROM hive_posts p
              JOIN tblChild  ON p.Parent_Id = tblChild.Id
            )
            SELECT queried_parent, cast(count(1) AS int) AS children_count
            FROM tblChild
            GROUP BY queried_parent
          ) data_source
          WHERE uhp.id = data_source.queried_parent
          ;
          END
          $BODY$;
          """
    db.query_no_return(sql)

    sql = """
        DROP VIEW IF EXISTS hive_votes_accounts_permlinks_view
        ;
        CREATE VIEW hive_votes_accounts_permlinks_view
        AS
        SELECT
            ha_v.id as voter_id,
            ha_a.name as author,
            hpd.permlink as permlink,
            vote_percent as percent,
            ha_a.reputation as reputation,
            rshares,
            last_update as time,
            ha_v.name as voter,
            weight,
            num_changes,
            hpd.id as permlink_id,
            post_id
        FROM
            hive_votes hv
        INNER JOIN hive_accounts ha_v ON ha_v.id = hv.voter_id
        INNER JOIN hive_accounts ha_a ON ha_a.id = hv.author_id
        INNER JOIN hive_permlink_data hpd ON hpd.id = hv.permlink_id
        ;
    """
    db.query_no_return(sql)

    sql = """
      DROP TYPE IF EXISTS database_api_post CASCADE;
      CREATE TYPE database_api_post AS (
        id INT,
        community_id INT,
        author VARCHAR(16),
        permlink VARCHAR(255),
        title VARCHAR(512),
        body TEXT,
        category VARCHAR(255),
        depth SMALLINT,
        promoted DECIMAL(10,3),
        payout DECIMAL(10,3),
        payout_at TIMESTAMP,
        is_paidout BOOLEAN,
        children SMALLINT,
        votes INT,
        created_at TIMESTAMP,
        updated_at TIMESTAMP,
        rshares NUMERIC,
        json TEXT,
        is_hidden BOOLEAN,
        is_grayed BOOLEAN,
        total_votes INT,
        flag_weight REAL,
        parent_author VARCHAR(16),
        parent_permlink VARCHAR(255),
        curator_payout_value VARCHAR(30),
        root_author VARCHAR(16),
        root_permlink VARCHAR(255),
        max_accepted_payout VARCHAR(30),
        percent_hbd INT,
        allow_replies BOOLEAN,
        allow_votes BOOLEAN,
        allow_curation_rewards BOOLEAN,
        beneficiaries JSON,
        url TEXT,
        root_title VARCHAR(512),
        abs_rshares BIGINT,
        active TIMESTAMP,
        author_rewards BIGINT,
        max_cashout_time TIMESTAMP,
        reward_weight INT
      )
      ;

      DROP FUNCTION IF EXISTS list_comments_by_cashout_time(timestamp, character varying, character varying, int)
      ;
      CREATE OR REPLACE FUNCTION list_comments_by_cashout_time(
        in _cashout_time timestamp,
        in _author hive_accounts.name%TYPE,
        in _permlink hive_permlink_data.permlink%TYPE,
        in _limit INT)
        RETURNS SETOF database_api_post
        AS
        $function$
        BEGIN
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.payout_at, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.flag_weight, hp.parent_author,
              hp.parent_permlink, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards, hp.max_cashout_time, hp.reward_weight
          FROM
              hive_posts_view hp
          WHERE
              NOT hp.is_muted AND
              hp.cashout_time >= _cashout_time AND
              hp.id >= (SELECT id FROM hive_posts_view hp1 WHERE hp1.author >= _author AND hp1.permlink >= _permlink ORDER BY id LIMIT 1)
          ORDER BY
              hp.cashout_time ASC,
              hp.id ASC
          LIMIT
              _limit
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;

      DROP FUNCTION IF EXISTS list_comments_by_permlink(character varying, character varying, int)
      ;
      CREATE OR REPLACE FUNCTION list_comments_by_permlink(
        in _author hive_accounts.name%TYPE,
        in _permlink hive_permlink_data.permlink%TYPE,
        in _limit INT)
        RETURNS SETOF database_api_post
        AS
        $function$
        BEGIN
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.payout_at, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.flag_weight, hp.parent_author,
              hp.parent_permlink, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards, hp.max_cashout_time, hp.reward_weight
          FROM
              hive_posts_view hp
          WHERE
              NOT hp.is_muted AND
              hp.author >= _author COLLATE "C" AND
              hp.permlink >= _permlink COLLATE "C"
          ORDER BY
              hp.author COLLATE "C" ASC,
              hp.permlink COLLATE "C" ASC
          LIMIT
              _limit
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;

      DROP FUNCTION IF EXISTS list_comments_by_root(character varying, character varying, character varying, character varying, int)
      ;
      CREATE OR REPLACE FUNCTION list_comments_by_root(
        in _root_author hive_accounts.name%TYPE,
        in _root_permlink hive_permlink_data.permlink%TYPE,
        in _start_post_author hive_accounts.name%TYPE,
        in _start_post_permlink hive_permlink_data.permlink%TYPE,
        in _limit INT)
        RETURNS SETOF database_api_post
        AS
        $function$
        BEGIN
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.payout_at, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.flag_weight, hp.parent_author,
              hp.parent_permlink, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards, hp.max_cashout_time, hp.reward_weight
          FROM
              hive_posts_view hp
          WHERE
              NOT hp.is_muted AND
              root_author >= _root_author AND
              root_permlink >= _root_permlink AND
              hp.id >= (SELECT id FROM hive_posts_view hp1 WHERE hp1.author >= _start_post_author AND hp1.permlink >= _start_post_permlink ORDER BY id LIMIT 1)
          ORDER BY
              root_author ASC,
              root_permlink ASC,
              id ASC
          LIMIT
              _limit
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;

      DROP FUNCTION IF EXISTS list_comments_by_parent(character varying, character varying, character varying, character varying, int)
      ;
      CREATE OR REPLACE FUNCTION list_comments_by_parent(
        in _parent_author hive_accounts.name%TYPE,
        in _parent_permlink hive_permlink_data.permlink%TYPE,
        in _start_post_author hive_accounts.name%TYPE,
        in _start_post_permlink hive_permlink_data.permlink%TYPE,
        in _limit INT)
        RETURNS SETOF database_api_post
        AS
        $function$
        BEGIN
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.payout_at, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.flag_weight, hp.parent_author,
              hp.parent_permlink, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards, hp.max_cashout_time, hp.reward_weight
          FROM
              hive_posts_view hp
          WHERE
              NOT hp.is_muted AND
              parent_author >= _parent_author AND
              parent_permlink >= _parent_permlink AND
              hp.id >= (SELECT id FROM hive_posts_view hp1 WHERE hp1.author >= _start_post_author AND hp1.permlink >= _start_post_permlink ORDER BY id LIMIT 1)
          ORDER BY
              parent_author ASC,
              parent_permlink ASC,
              id ASC
          LIMIT
              _limit
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;

      DROP FUNCTION IF EXISTS list_comments_by_last_update(character varying, timestamp, character varying, character varying, int)
      ;
      CREATE OR REPLACE FUNCTION list_comments_by_last_update(
        in _parent_author hive_accounts.name%TYPE,
        in _updated_at hive_posts.updated_at%TYPE,
        in _start_post_author hive_accounts.name%TYPE,
        in _start_post_permlink hive_permlink_data.permlink%TYPE,
        in _limit INT)
        RETURNS SETOF database_api_post
        AS
        $function$
        BEGIN
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.payout_at, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.flag_weight, hp.parent_author,
              hp.parent_permlink, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards, hp.max_cashout_time, hp.reward_weight
          FROM
              hive_posts_view hp
          WHERE
              NOT hp.is_muted AND
              hp.parent_author >= _parent_author AND
              hp.updated_at >= _updated_at AND
              hp.id >= (SELECT id FROM hive_posts_view hp1 WHERE hp1.author >= _start_post_author AND hp1.permlink >= _start_post_permlink ORDER BY id LIMIT 1)
          ORDER BY
              hp.parent_author ASC,
              hp.updated_at ASC,
              hp.id ASC
          LIMIT
              _limit
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;
      DROP FUNCTION IF EXISTS list_comments_by_author_last_update(character varying, timestamp, character varying, character varying, int)
      ;
      CREATE OR REPLACE FUNCTION list_comments_by_author_last_update(
        in _author hive_accounts.name%TYPE,
        in _updated_at hive_posts.updated_at%TYPE,
        in _start_post_author hive_accounts.name%TYPE,
        in _start_post_permlink hive_permlink_data.permlink%TYPE,
        in _limit INT)
        RETURNS SETOF database_api_post
        AS
        $function$
        BEGIN
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.payout_at, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.flag_weight, hp.parent_author,
              hp.parent_permlink, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards, hp.max_cashout_time, hp.reward_weight
          FROM
              hive_posts_view hp
          WHERE
              NOT hp.is_muted AND
              hp.author >= _author AND
              hp.updated_at >= _updated_at AND
              hp.id >= (SELECT id FROM hive_posts_view hp1 WHERE hp1.author >= _start_post_author AND hp1.permlink >= _start_post_permlink ORDER BY id LIMIT 1)
          ORDER BY
              hp.parent_author ASC,
              hp.updated_at ASC,
              hp.id ASC
          LIMIT
              _limit
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;
    """
    db.query_no_return(sql)

    # hot and tranding functions

    sql = """
       DROP FUNCTION IF EXISTS date_diff CASCADE
       ;
       CREATE OR REPLACE FUNCTION date_diff (units VARCHAR(30), start_t TIMESTAMP, end_t TIMESTAMP)
         RETURNS INT AS $$
       DECLARE
         diff_interval INTERVAL;
         diff INT = 0;
         years_diff INT = 0;
       BEGIN
         IF units IN ('yy', 'yyyy', 'year', 'mm', 'm', 'month') THEN
           years_diff = DATE_PART('year', end_t) - DATE_PART('year', start_t);
           IF units IN ('yy', 'yyyy', 'year') THEN
             -- SQL Server does not count full years passed (only difference between year parts)
             RETURN years_diff;
           ELSE
             -- If end month is less than start month it will subtracted
             RETURN years_diff * 12 + (DATE_PART('month', end_t) - DATE_PART('month', start_t));
           END IF;
         END IF;
         -- Minus operator returns interval 'DDD days HH:MI:SS'
         diff_interval = end_t - start_t;
         diff = diff + DATE_PART('day', diff_interval);
         IF units IN ('wk', 'ww', 'week') THEN
           diff = diff/7;
           RETURN diff;
         END IF;
         IF units IN ('dd', 'd', 'day') THEN
           RETURN diff;
         END IF;
         diff = diff * 24 + DATE_PART('hour', diff_interval);
         IF units IN ('hh', 'hour') THEN
            RETURN diff;
         END IF;
         diff = diff * 60 + DATE_PART('minute', diff_interval);
         IF units IN ('mi', 'n', 'minute') THEN
            RETURN diff;
         END IF;
         diff = diff * 60 + DATE_PART('second', diff_interval);
         RETURN diff;
       END;
       $$ LANGUAGE plpgsql IMMUTABLE
    """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION IF EXISTS public.calculate_time_part_of_trending(_post_created_at hive_posts.created_at%TYPE ) CASCADE
          ;
          CREATE OR REPLACE FUNCTION public.calculate_time_part_of_trending(
            _post_created_at hive_posts.created_at%TYPE)
              RETURNS double precision
              LANGUAGE 'plpgsql'
              IMMUTABLE
          AS $BODY$
          DECLARE
            result double precision;
            sec_from_epoch INT = 0;
          BEGIN
            sec_from_epoch  = date_diff( 'second', CAST('19700101' AS TIMESTAMP), _post_created_at );
            result = sec_from_epoch/240000.0;
            return result;
          END;
          $BODY$;
    """
    db.query_no_return(sql)

    sql = """
            DROP FUNCTION IF EXISTS public.calculate_time_part_of_hot(_post_created_at hive_posts.created_at%TYPE ) CASCADE
            ;
            CREATE OR REPLACE FUNCTION public.calculate_time_part_of_hot(
              _post_created_at hive_posts.created_at%TYPE)
                RETURNS double precision
                LANGUAGE 'plpgsql'
                IMMUTABLE
            AS $BODY$
            DECLARE
              result double precision;
              sec_from_epoch INT = 0;
            BEGIN
              sec_from_epoch  = date_diff( 'second', CAST('19700101' AS TIMESTAMP), _post_created_at );
              result = sec_from_epoch/10000.0;
              return result;
            END;
            $BODY$;
    """
    db.query_no_return(sql)

    sql = """
	DROP FUNCTION IF EXISTS public.calculate_rhsares_part_of_hot_and_trend(_rshares hive_votes.rshares%TYPE) CASCADE
	;
	CREATE OR REPLACE FUNCTION public.calculate_rhsares_part_of_hot_and_trend(_rshares hive_votes.rshares%TYPE)
	RETURNS double precision
	LANGUAGE 'plpgsql'
	IMMUTABLE
	AS $BODY$
	DECLARE
		mod_score double precision;
	BEGIN
		mod_score := _rshares / 10000000.0;
		IF ( mod_score > 0 )
		THEN
			return log( greatest( abs(mod_score), 1 ) );
		END IF;
		return  -1.0 * log( greatest( abs(mod_score), 1 ) );
	END;
	$BODY$;
    """
    db.query_no_return(sql)

    sql = """
	DROP FUNCTION IF EXISTS public.calculate_hot(hive_votes.rshares%TYPE, hive_posts.created_at%TYPE)
	;
	CREATE OR REPLACE FUNCTION public.calculate_hot(
	    _rshares hive_votes.rshares%TYPE,
	    _post_created_at hive_posts.created_at%TYPE)
	    RETURNS hive_posts.sc_hot%TYPE
	      LANGUAGE 'plpgsql'
	      IMMUTABLE
	  AS $BODY$
	BEGIN
	    return calculate_rhsares_part_of_hot_and_trend(_rshares) + calculate_time_part_of_hot( _post_created_at );
	END;
	$BODY$;
    """
    db.query_no_return(sql)

    sql = """
          DO $$
          BEGIN
            EXECUTE 'ALTER DATABASE '||current_database()||' SET join_collapse_limit TO 16';
            EXECUTE 'ALTER DATABASE '||current_database()||' SET from_collapse_limit TO 16';
          END
          $$;
          """
    db.query_no_return(sql)

    sql = """
	DROP FUNCTION IF EXISTS public.calculate_tranding(hive_votes.rshares%TYPE, hive_posts.created_at%TYPE)
	;
	CREATE OR REPLACE FUNCTION public.calculate_tranding(
	    _rshares hive_votes.rshares%TYPE,
	    _post_created_at hive_posts.created_at%TYPE)
	    RETURNS hive_posts.sc_trend%TYPE
	      LANGUAGE 'plpgsql'
	      IMMUTABLE
	  AS $BODY$
	BEGIN
	    return calculate_rhsares_part_of_hot_and_trend(_rshares) + calculate_time_part_of_trending( _post_created_at );
	END;
	$BODY$;
    """
    db.query_no_return(sql)

def reset_autovac(db):
    """Initializes/resets per-table autovacuum/autoanalyze params.

    We use a scale factor of 0 and specify exact threshold tuple counts,
    per-table, in the format (autovacuum_threshold, autoanalyze_threshold)."""

    autovac_config = { #    vacuum  analyze
        'hive_accounts':    (50000, 100000),
        'hive_posts':       (2500, 10000),
        'hive_post_tags':   (5000, 10000),
        'hive_follows':     (5000, 5000),
        'hive_feed_cache':  (5000, 5000),
        'hive_blocks':      (5000, 25000),
        'hive_reblogs':     (5000, 5000),
        'hive_payments':    (5000, 5000),
    }

    for table, (n_vacuum, n_analyze) in autovac_config.items():
        sql = """ALTER TABLE %s SET (autovacuum_vacuum_scale_factor = 0,
                                     autovacuum_vacuum_threshold = %s,
                                     autovacuum_analyze_scale_factor = 0,
                                     autovacuum_analyze_threshold = %s)"""
        db.query(sql % (table, n_vacuum, n_analyze))
