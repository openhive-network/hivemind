"""Db schema definitions and setup routines."""

import sqlalchemy as sa
from sqlalchemy.sql import text as sql_text
from sqlalchemy.types import SMALLINT
from sqlalchemy.types import CHAR
from sqlalchemy.types import VARCHAR
from sqlalchemy.types import TEXT
from sqlalchemy.types import BOOLEAN

import logging
log = logging.getLogger(__name__)

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
        sa.Column('name', VARCHAR(16, collation='C'), nullable=False),
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
        sa.Column('proxy_weight', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('kb_used', sa.Integer, nullable=False, server_default='0'), # deprecated
        sa.Column('rank', sa.Integer, nullable=False, server_default='0'),

        sa.Column('lastread_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('cached_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('raw_json', sa.Text),

        sa.UniqueConstraint('name', name='hive_accounts_ux1'),
        sa.Index('hive_accounts_ix5', 'cached_at'), # core/listen sweep
	sa.Index('hive_accounts_ix6', 'reputation')
    )


    sa.Table(
        'hive_reputation_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('author_id', sa.Integer, nullable=False),
        sa.Column('voter_id', sa.Integer, nullable=False),
        sa.Column('permlink', sa.String(255, collation='C'), nullable=False),
        sa.Column('rshares', sa.BigInteger, nullable=False),
        sa.Column('block_num', sa.Integer,  nullable=False),

#        sa.ForeignKeyConstraint(['voter_id'], ['hive_accounts.id']),
#        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id']),
#        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num']),

        sa.UniqueConstraint('author_id', 'permlink', 'voter_id', name='hive_reputation_data_uk')
    )

    sa.Table(
        'hive_posts', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('root_id', sa.Integer, nullable=False), # records having initially set 0 will be updated to their id
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
        sa.Column('is_grayed', BOOLEAN, nullable=False, server_default='0'),

        # important indexes
        sa.Column('sc_trend', sa.Float(precision=6), nullable=False, server_default='0'),
        sa.Column('sc_hot', sa.Float(precision=6), nullable=False, server_default='0'),

        sa.Column('total_payout_value', sa.String(30), nullable=False, server_default='0.000 HBD'),
        sa.Column('author_rewards', sa.BigInteger, nullable=False, server_default='0'),

        sa.Column('author_rewards_hive', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_hbd', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('author_rewards_vests', sa.BigInteger, nullable=False, server_default='0'),

        sa.Column('abs_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('vote_rshares', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('total_vote_weight', sa.Numeric, nullable=False, server_default='0'),
        sa.Column('active', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('cashout_time', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('percent_hbd', sa.Integer, nullable=False, server_default='10000'),

        sa.Column('curator_payout_value', sa.String(30), nullable=False, server_default='0.000 HBD'),
        sa.Column('max_accepted_payout',  sa.String(30), nullable=False, server_default='1000000.000 HBD'),
        sa.Column('allow_votes', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('allow_curation_rewards', BOOLEAN, nullable=False, server_default='1'),
        sa.Column('beneficiaries', sa.JSON, nullable=False, server_default='[]'),
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id'], name='hive_posts_fk1'),
        sa.ForeignKeyConstraint(['root_id'], ['hive_posts.id'], name='hive_posts_fk2'),
        sa.ForeignKeyConstraint(['parent_id'], ['hive_posts.id'], name='hive_posts_fk3'),
        sa.UniqueConstraint('author_id', 'permlink_id', 'counter_deleted', name='hive_posts_ux1'),

        sa.Index('hive_posts_depth_idx', 'depth'),

        sa.Index('hive_posts_root_id_id_idx', 'root_id','id'),

        sa.Index('hive_posts_parent_id_idx', 'parent_id'),
        sa.Index('hive_posts_community_id_idx', 'community_id'),

        sa.Index('hive_posts_category_id_idx', 'category_id'),
        sa.Index('hive_posts_payout_at_idx', 'payout_at'),
        sa.Index('hive_posts_payout_idx', 'payout'),
        sa.Index('hive_posts_promoted_idx', 'promoted'),
        sa.Index('hive_posts_sc_trend_idx', 'sc_trend'),
        sa.Index('hive_posts_sc_hot_idx', 'sc_hot'),
        sa.Index('hive_posts_created_at_idx', 'created_at'),
        sa.Index('hive_posts_block_num_idx', 'block_num'),
        sa.Index('hive_posts_author_id_idx', 'author_id')
    )

    sa.Table(
        'hive_post_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('title', VARCHAR(512), nullable=False, server_default=''),
        sa.Column('preview', VARCHAR(1024), nullable=False, server_default=''), # first 1k of 'body'
        sa.Column('img_url', VARCHAR(1024), nullable=False, server_default=''), # first 'image' from 'json'
        sa.Column('body', TEXT, nullable=False, server_default=''),
        sa.Column('json', TEXT, nullable=False, server_default='')
    )

    sa.Table(
        'hive_permlink_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('permlink', sa.String(255, collation='C'), nullable=False),
        sa.UniqueConstraint('permlink', name='hive_permlink_data_permlink')
    )

    sa.Table(
        'hive_category_data', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('category', sa.String(255, collation='C'), nullable=False),
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
        sa.Column('block_num', sa.Integer,  nullable=False ),
        sa.Column('is_effective', BOOLEAN, nullable=False, server_default='0'),

        sa.UniqueConstraint('voter_id', 'author_id', 'permlink_id', name='hive_votes_ux1'),

        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_votes_fk1'),
        sa.ForeignKeyConstraint(['voter_id'], ['hive_accounts.id'], name='hive_votes_fk2'),
        sa.ForeignKeyConstraint(['author_id'], ['hive_accounts.id'], name='hive_votes_fk3'),
        sa.ForeignKeyConstraint(['permlink_id'], ['hive_permlink_data.id'], name='hive_votes_fk4'),
        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num'], name='hive_votes_fk5'),

        sa.Index('hive_votes_post_id_idx', 'post_id'),
        sa.Index('hive_votes_voter_id_idx', 'voter_id'),
        sa.Index('hive_votes_voter_id_post_id_idx', 'voter_id', 'post_id'),
        sa.Index('hive_votes_post_id_voter_id_idx', 'post_id', 'voter_id'),
        sa.Index('hive_votes_block_num_idx', 'block_num')
    )

    sa.Table(
        'hive_tag_data', metadata,
        sa.Column('id', sa.Integer, nullable=False, primary_key=True),
        sa.Column('tag', VARCHAR(64, collation='C'), nullable=False, server_default=''),
        sa.UniqueConstraint('tag', name='hive_tag_data_ux1')
    )

    sa.Table(
        'hive_post_tags', metadata,
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('tag_id', sa.Integer, nullable=False),
        sa.PrimaryKeyConstraint('post_id', 'tag_id', name='hive_post_tags_pk1'),

        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_post_tags_fk1'),
        sa.ForeignKeyConstraint(['tag_id'], ['hive_tag_data.id'], name='hive_post_tags_fk2'),

        sa.Index('hive_post_tags_tag_id_idx', 'tag_id')
    )

    sa.Table(
        'hive_follows', metadata,
        sa.Column('id', sa.Integer, primary_key=True ),
        sa.Column('follower', sa.Integer, nullable=False),
        sa.Column('following', sa.Integer, nullable=False),
        sa.Column('state', SMALLINT, nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('blacklisted', sa.Boolean, nullable=False, server_default='0'),
        sa.Column('follow_blacklists', sa.Boolean, nullable=False, server_default='0'),
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.UniqueConstraint('following', 'follower', name='hive_follows_ux1'), # core
        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num'], name='hive_follows_fk1'),
        sa.Index('hive_follows_ix5a', 'following', 'state', 'created_at', 'follower'),
        sa.Index('hive_follows_ix5b', 'follower', 'state', 'created_at', 'following'),
        sa.Index('hive_follows_block_num_idx', 'block_num')
    )

    sa.Table(
        'hive_reblogs', metadata,
        sa.Column('id', sa.Integer, primary_key=True ),
        sa.Column('account', VARCHAR(16), nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.ForeignKeyConstraint(['account'], ['hive_accounts.name'], name='hive_reblogs_fk1'),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_reblogs_fk2'),
        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num'], name='hive_reblogs_fk3'),
        sa.UniqueConstraint('account', 'post_id', name='hive_reblogs_ux1'), # core
        sa.Index('hive_reblogs_account', 'account'),
        sa.Index('hive_reblogs_post_id', 'post_id'),
        sa.Index('hive_reblogs_block_num_idx', 'block_num')
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
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_payments_fk3'),
        sa.Index('hive_payments_from', 'from_account'),
        sa.Index('hive_payments_to', 'to_account'),
        sa.Index('hive_payments_post_id', 'post_id'),
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
        'hive_state', metadata,
        sa.Column('block_num', sa.Integer, primary_key=True, autoincrement=False),
        sa.Column('db_version', sa.Integer, nullable=False),
        sa.Column('steem_per_mvest', sa.types.DECIMAL(14, 6), nullable=False),
        sa.Column('usd_per_steem', sa.types.DECIMAL(14, 6), nullable=False),
        sa.Column('sbd_per_steem', sa.types.DECIMAL(14, 6), nullable=False),
        sa.Column('dgpo', sa.Text, nullable=False),
    )

    sa.Table(
        'hive_posts_api_helper', metadata,
        sa.Column('id', sa.Integer, primary_key=True, autoincrement = False),
        sa.Column('author', VARCHAR(16, collation='C'), nullable=False),
        sa.Column('parent_author', VARCHAR(16, collation='C'), nullable=False),
        sa.Column('parent_permlink_or_category', sa.String(255, collation='C'), nullable=False),
        sa.Index('hive_posts_api_helper_parent_permlink_or_category', 'parent_author', 'parent_permlink_or_category', 'id')
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
        sa.Column('name',        VARCHAR(16, collation='C'), nullable=False),
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
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.UniqueConstraint('name', name='hive_communities_ux1'),
        sa.Index('hive_communities_ix1', 'rank', 'id'),
        sa.Index('hive_communities_block_num_idx', 'block_num')
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
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('account_id',   sa.Integer,  nullable=False),
        sa.Column('community_id', sa.Integer,  nullable=False),
        sa.Column('created_at',   sa.DateTime, nullable=False),
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.UniqueConstraint('account_id', 'community_id', name='hive_subscriptions_ux1'),
        sa.Index('hive_subscriptions_ix1', 'community_id', 'account_id', 'created_at'),
        sa.Index('hive_subscriptions_block_num_idx', 'block_num')
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

    return metadata


def teardown(db):
    """Drop all tables"""
    build_metadata().drop_all(db.engine())

def drop_fk(db):
    db.query_no_return("START TRANSACTION")
    for table in build_metadata().sorted_tables:
        for fk in table.foreign_keys:
            sql = """ALTER TABLE {} DROP CONSTRAINT IF EXISTS {}""".format(table.name, fk.name)
            db.query_no_return(sql)
    db.query_no_return("COMMIT")

def create_fk(db):
    from sqlalchemy.schema import AddConstraint
    from sqlalchemy import text
    connection = db.engine().connect()
    connection.execute(text("START TRANSACTION"))
    for table in build_metadata().sorted_tables:
        for fk in table.foreign_keys:
            connection.execute(AddConstraint(fk.constraint))
    connection.execute(text("COMMIT"))

def setup(db):
    """Creates all tables and seed data"""
    # initialize schema
    build_metadata().create_all(db.engine())

    # tune auto vacuum/analyze
    reset_autovac(db)

    # sets FILLFACTOR:
    set_fillfactor(db)

    # default rows
    sql = "INSERT INTO hive_state (block_num, db_version, steem_per_mvest, usd_per_steem, sbd_per_steem, dgpo) VALUES (0, %d, 0, 0, 0, '')" % DB_VERSION
    db.query(sql)

    # scripts are executed in order given in this list
    sql_scripts = [
        "initial_values.sql",
        "hive_communities_ft1.sql",
        "process_hive_post_operation.sql",
        "delete_hive_post.sql",
        "hive_accounts_info_view.sql",
        "hive_posts_view.sql",
        "update_hive_posts_root_id.sql",
        "update_hive_posts_children_count.sql",
        "hive_votes_view.sql",
        "database_api_vote.sql",
        "get_account.sql",
        "list_votes_by_voter_comment.sql",
        "list_votes_by_comment_voter.sql",
        "find_comment_id.sql",
        "database_api_post.sql",
        "list_comments_by_cashout_time.sql",
        "list_comments_by_permlink.sql",
        "list_comments_by_root.sql",
        "list_comments_by_parent.sql",
        "list_comments_by_last_update.sql",
        "list_comments_by_author_last_update.sql",
        "score_for_account.sql",
        "date_diff.sql",
        "calculate_time_part_of_trending.sql",
        "calculate_time_part_of_hot.sql",
        "calculate_rhsares_part_of_hot_and_trend.sql",
        "calculate_hot.sql",
        "collapse_limit.sql",
        "calculate_tranding.sql",
        "max_time_stamp.sql",
        "update_hive_posts_api_helper.sql",
        "process_reputation_data.sql",
        "calculate_notify_vote_score.sql",
        "notification_id.sql",
        "update_hive_posts_api_helper.sql"
    ]

    import os 
    dir_path = os.path.dirname(os.path.realpath(__file__))
    for script in sql_scripts:
        execute_sql_script(db.query_no_return, "{}/sql_scripts/{}".format(dir_path, script))

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


def set_fillfactor(db):
    """Initializes/resets FILLFACTOR for tables which are intesively updated"""

    fillfactor_config = {
        'hive_posts': 70,
        'hive_post_data': 70,
        'hive_votes': 70,
        'hive_reputation_data': 50
    }

    for table, fillfactor in fillfactor_config.items():
        sql = """ALTER TABLE {} SET (FILLFACTOR = {})"""
        db.query(sql.format(table, fillfactor))

def set_logged_table_attribute(db, logged):
    """Initializes/resets LOGGED/UNLOGGED attribute for tables which are intesively updated"""

    logged_config = [
        'hive_accounts',
        'hive_permlink_data',
        'hive_post_tags',
        'hive_posts',
        'hive_post_data',
        'hive_votes',
        'hive_reputation_data'
    ]

    for table in logged_config:
        log.info("Setting {} attribute on a table: {}".format('LOGGED' if logged else 'UNLOGGED', table))
        sql = """ALTER TABLE {} SET {}"""
        db.query_no_return(sql.format(table, 'LOGGED' if logged else 'UNLOGGED'))

def execute_sql_script(query_executor, path_to_script):
    """ Load and execute sql script from file 
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
        log.exception("Error running sql script: {}".format(ex))
        raise ex
    return None