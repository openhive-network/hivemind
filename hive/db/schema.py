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
        sa.Column('reputation', sa.BigInteger, nullable=False, server_default='0'),
        sa.Column('is_implicit', sa.Boolean, nullable=False, server_default='1'),
        sa.Column('followers', sa.Integer, nullable=False, server_default='0'),
        sa.Column('following', sa.Integer, nullable=False, server_default='0'),

        sa.Column('rank', sa.Integer, nullable=False, server_default='0'),

        sa.Column('lastread_at', sa.DateTime, nullable=False, server_default='1970-01-01 00:00:00'),
        sa.Column('posting_json_metadata', sa.Text),
        sa.Column('json_metadata', sa.Text),
        sa.Column('blacklist_description', sa.String(256)),
        sa.Column('muted_list_description', sa.String(256)),

        sa.UniqueConstraint('name', name='hive_accounts_ux1'),
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

        sa.Index('hive_reputation_data_author_permlink_voter_idx', 'author_id', 'permlink', 'voter_id'),
        sa.Index('hive_reputation_data_block_num_idx', 'block_num')
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
        sa.Index('hive_posts_sc_trend_id_idx', 'sc_trend', 'id'),
        sa.Index('hive_posts_sc_hot_id_idx', 'sc_hot', 'id'),
        sa.Index('hive_posts_created_at_idx', 'created_at'),
        sa.Index('hive_posts_block_num_idx', 'block_num'),
        sa.Index('hive_posts_cashout_time_id_idx', 'cashout_time', 'id'),
        sa.Index('hive_posts_updated_at_idx', sa.text('updated_at DESC')),
        sa.Index('hive_posts_is_paidout_idx', 'is_paidout'),
        sa.Index('hive_posts_payout_plus_pending_payout_id', sa.text('(payout+pending_payout), id'))
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
        sa.Column('follow_muted', BOOLEAN, nullable=False, server_default='0'),
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.UniqueConstraint('following', 'follower', name='hive_follows_ux1'), # core
        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num'], name='hive_follows_fk1'),
        sa.Index('hive_follows_ix5a', 'following', 'state', 'created_at', 'follower'),
        sa.Index('hive_follows_ix5b', 'follower', 'state', 'created_at', 'following'),
        sa.Index('hive_follows_block_num_idx', 'block_num'),
        sa.Index('hive_follows_created_at_idx', 'created_at'),
    )

    sa.Table(
        'hive_reblogs', metadata,
        sa.Column('id', sa.Integer, primary_key=True ),
        sa.Column('blogger_id', sa.Integer, nullable=False),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('block_num', sa.Integer,  nullable=False ),

        sa.ForeignKeyConstraint(['blogger_id'], ['hive_accounts.id'], name='hive_reblogs_fk1'),
        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_reblogs_fk2'),
        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num'], name='hive_reblogs_fk3'),
        sa.UniqueConstraint('blogger_id', 'post_id', name='hive_reblogs_ux1'), # core
        sa.Index('hive_reblogs_post_id', 'post_id'),
        sa.Index('hive_reblogs_block_num_idx', 'block_num'),
        sa.Index('hive_reblogs_created_at_idx', 'created_at')
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
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False),
        sa.Column('block_num',    sa.Integer,  nullable=True),
        sa.PrimaryKeyConstraint('account_id', 'post_id', name='hive_feed_cache_pk'),
        sa.ForeignKeyConstraint(['block_num'], ['hive_blocks.num'], name='hive_feed_cache_fk1'),
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
        sa.Column('permlink', VARCHAR(255, collation='C'), nullable=False),
        sa.Index('hive_posts_api_helper_author_permlink_idx', 'author', 'permlink')
    )

    sa.Table(
        'hive_mentions', metadata,
        sa.Column('id', sa.Integer, primary_key=True),
        sa.Column('post_id', sa.Integer, nullable=False),
        sa.Column('account_id', sa.Integer, nullable=False),
        sa.Column('block_num', sa.Integer, nullable=False),

        sa.ForeignKeyConstraint(['post_id'], ['hive_posts.id'], name='hive_mentions_fk1'),
        sa.ForeignKeyConstraint(['account_id'], ['hive_accounts.id'], name='hive_mentions_fk2'),

        sa.Index('hive_mentions_account_id_idx', 'account_id'),
        sa.UniqueConstraint('post_id', 'account_id', 'block_num', name='hive_mentions_ux1')
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
        sa.Index('hive_subscriptions_community_idx', 'community_id'),
        sa.Index('hive_subscriptions_block_num_idx', 'block_num')
    )

    sa.Table(
        'hive_notifs', metadata,
        sa.Column('id',           sa.Integer,  primary_key=True),
        sa.Column('block_num',    sa.Integer,  nullable=False),
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
    sqls = [
        "INSERT INTO hive_state (block_num, db_version, steem_per_mvest, usd_per_steem, sbd_per_steem, dgpo) VALUES (0, %d, 0, 0, 0, '')" % DB_VERSION,
        "INSERT INTO hive_blocks (num, hash, created_at) VALUES (0, '0000000000000000000000000000000000000000', '2016-03-24 16:04:57')",

        "INSERT INTO hive_permlink_data (id, permlink) VALUES (0, '')",
        "INSERT INTO hive_category_data (id, category) VALUES (0, '')",
        "INSERT INTO hive_tag_data (id, tag) VALUES (0, '')",
        "INSERT INTO hive_accounts (id, name, created_at) VALUES (0, '', '1970-01-01T00:00:00')",

        "INSERT INTO hive_accounts (name, created_at) VALUES ('miners',    '2016-03-24 16:05:00')",
        "INSERT INTO hive_accounts (name, created_at) VALUES ('null',      '2016-03-24 16:05:00')",
        "INSERT INTO hive_accounts (name, created_at) VALUES ('temp',      '2016-03-24 16:05:00')",
        "INSERT INTO hive_accounts (name, created_at) VALUES ('initminer', '2016-03-24 16:05:00')",

        """
        INSERT INTO
            public.hive_posts(id, root_id, parent_id, author_id, permlink_id, category_id,
                community_id, created_at, depth, block_num
            )
        VALUES
            (0, 0, 0, 0, 0, 0, 0, now(), 0, 0);
        """]
    for sql in sqls:
        db.query(sql)

    sql = "CREATE INDEX hive_communities_ft1 ON hive_communities USING GIN (to_tsvector('english', title || ' ' || about))"
    db.query(sql)

    sql = """
      DROP FUNCTION IF EXISTS find_comment_id(character varying, character varying, boolean)
      ;
      CREATE OR REPLACE FUNCTION find_comment_id(
        in _author hive_accounts.name%TYPE,
        in _permlink hive_permlink_data.permlink%TYPE,
        in _check boolean)
      RETURNS INT
      LANGUAGE 'plpgsql'
      AS
      $function$
      DECLARE
        __post_id INT = 0;
      BEGIN
        IF (_author <> '' OR _permlink <> '') THEN
          SELECT INTO __post_id COALESCE( (
            SELECT hp.id
            FROM hive_posts hp
            JOIN hive_accounts ha ON ha.id = hp.author_id
            JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
            WHERE ha.name = _author AND hpd.permlink = _permlink AND hp.counter_deleted = 0
          ), 0 );
          IF _check AND __post_id = 0 THEN
            SELECT INTO __post_id (
              SELECT COUNT(hp.id)
              FROM hive_posts hp
              JOIN hive_accounts ha ON ha.id = hp.author_id
              JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
              WHERE ha.name = _author AND hpd.permlink = _permlink
            );
            IF __post_id = 0 THEN
            RAISE EXCEPTION 'Post %/% does not exist', _author, _permlink;
            ELSE
              RAISE EXCEPTION 'Post %/% was deleted % time(s)', _author, _permlink, __post_id;
            END IF;
          END IF;
        END IF;
        RETURN __post_id;
      END
      $function$
      ;
    """

    db.query_no_return(sql)

    sql = """
        DROP FUNCTION IF EXISTS find_account_id(character varying, boolean)
        ;
        CREATE OR REPLACE FUNCTION find_account_id(
          in _account hive_accounts.name%TYPE,
          in _check boolean)
        RETURNS INT
        LANGUAGE 'plpgsql'
        AS
        $function$
        DECLARE
          account_id INT;
        BEGIN
          SELECT INTO account_id COALESCE( ( SELECT id FROM hive_accounts WHERE name=_account ), 0 );
          IF _check AND account_id = 0 THEN
            RAISE EXCEPTION 'Account % does not exist', _account;
          END IF;
          RETURN account_id;
        END
        $function$
        ;
    """

    db.query_no_return(sql)

    sql = """
          DROP FUNCTION if exists process_hive_post_operation(character varying,character varying,character varying,character varying,timestamp without time zone,timestamp without time zone)
          ;
          CREATE OR REPLACE FUNCTION process_hive_post_operation(
            in _author hive_accounts.name%TYPE,
            in _permlink hive_permlink_data.permlink%TYPE,
            in _parent_author hive_accounts.name%TYPE,
            in _parent_permlink hive_permlink_data.permlink%TYPE,
            in _date hive_posts.created_at%TYPE,
            in _community_support_start_date hive_posts.created_at%TYPE,
            in _block_num hive_posts.block_num%TYPE)
          RETURNS TABLE (is_new_post boolean, id hive_posts.id%TYPE, author_id hive_posts.author_id%TYPE, permlink_id hive_posts.permlink_id%TYPE,
                         post_category hive_category_data.category%TYPE, parent_id hive_posts.parent_id%TYPE, community_id hive_posts.community_id%TYPE,
                         is_valid hive_posts.is_valid%TYPE, is_muted hive_posts.is_muted%TYPE, depth hive_posts.depth%TYPE)
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
            (parent_id, depth, community_id, category_id,
             root_id, is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time, counter_deleted, block_num)
            SELECT php.id AS parent_id, php.depth + 1 AS depth,
                (CASE
                   WHEN _date > _community_support_start_date THEN
                     COALESCE(php.community_id, (select hc.id from hive_communities hc where hc.name = _parent_permlink))
                   ELSE NULL
                END) AS community_id,
                COALESCE(php.category_id, (select hcg.id from hive_category_data hcg where hcg.category = _parent_permlink)) AS category_id,
                (CASE(php.root_id)
                   WHEN 0 THEN php.id
                   ELSE php.root_id
                 END) AS root_id,
                php.is_muted AS is_muted, php.is_valid AS is_valid,
                ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
                _date AS updated_at,
                calculate_time_part_of_hot(_date) AS sc_hot,
                calculate_time_part_of_trending(_date) AS sc_trend,
                _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0, _block_num as block_num
            FROM hive_accounts ha,
                 hive_permlink_data hpd,
                 hive_posts php
            INNER JOIN hive_accounts pha ON pha.id = php.author_id
            INNER JOIN hive_permlink_data phpd ON phpd.id = php.permlink_id
            WHERE pha.name = _parent_author AND phpd.permlink = _parent_permlink AND
                   ha.name = _author AND hpd.permlink = _permlink AND php.counter_deleted = 0

            ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
              --- During post update it is disallowed to change: parent-post, category, community-id
              --- then also depth, is_valid and is_muted is impossible to change
             --- post edit part
             updated_at = _date,
             active = _date
            RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, (SELECT hcd.category FROM hive_category_data hcd WHERE hcd.id = hp.category_id) as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
          ;
          ELSE
            INSERT INTO hive_category_data
            (category)
            VALUES (_parent_permlink)
            ON CONFLICT (category) DO NOTHING
            ;

            RETURN QUERY INSERT INTO hive_posts as hp
            (parent_id, depth, community_id, category_id,
             root_id, is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time, counter_deleted, block_num)
            SELECT 0 AS parent_id, 0 AS depth,
                (CASE
                  WHEN _date > _community_support_start_date THEN
                    (select hc.id FROM hive_communities hc WHERE hc.name = _parent_permlink)
                  ELSE NULL
                END) AS community_id,
                (SELECT hcg.id FROM hive_category_data hcg WHERE hcg.category = _parent_permlink) AS category_id,
                0 as root_id, -- will use id as root one if no parent
                false AS is_muted, true AS is_valid,
                ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
                _date AS updated_at,
                calculate_time_part_of_hot(_date) AS sc_hot,
                calculate_time_part_of_trending(_date) AS sc_trend,
                _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0, _block_num as block_num
            FROM hive_accounts ha,
                 hive_permlink_data hpd
            WHERE ha.name = _author and hpd.permlink = _permlink

            ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
              --- During post update it is disallowed to change: parent-post, category, community-id
              --- then also depth, is_valid and is_muted is impossible to change
              --- post edit part
              updated_at = _date,
              active = _date,
              block_num = _block_num

            RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
            ;
          END IF;
          END
          $function$
    """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION if exists delete_hive_post(character varying,character varying,character varying)
          ;
          CREATE OR REPLACE FUNCTION delete_hive_post(
            in _author hive_accounts.name%TYPE,
            in _permlink hive_permlink_data.permlink%TYPE)
          RETURNS TABLE (id hive_posts.id%TYPE, depth hive_posts.depth%TYPE)
          LANGUAGE plpgsql
          AS
          $function$
          BEGIN
            RETURN QUERY UPDATE hive_posts AS hp
              SET counter_deleted =
              (
                SELECT max( hps.counter_deleted ) + 1
                FROM hive_posts hps
                INNER JOIN hive_accounts ha ON hps.author_id = ha.id
                INNER JOIN hive_permlink_data hpd ON hps.permlink_id = hpd.id
                WHERE ha.name = _author AND hpd.permlink = _permlink
              )
            FROM hive_posts hp1
            INNER JOIN hive_accounts ha ON hp1.author_id = ha.id
            INNER JOIN hive_permlink_data hpd ON hp1.permlink_id = hpd.id
            WHERE hp.id = hp1.id AND ha.name = _author AND hpd.permlink = _permlink AND hp1.counter_deleted = 0
            RETURNING hp.id, hp.depth;
          END
          $function$
          """
    db.query_no_return(sql)

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

    sql = """
        DROP VIEW IF EXISTS public.hive_accounts_info_view;

        CREATE OR REPLACE VIEW public.hive_accounts_info_view
        AS
        SELECT
          id,
          name,
          (
            select count(*) post_count
            FROM hive_posts hp
            WHERE ha.id=hp.author_id
          ) post_count,
          created_at,
          (
            SELECT GREATEST
            (
              created_at,
              COALESCE(
                (
                  select max(hp.created_at + '0 days'::interval)
                  FROM hive_posts hp
                  WHERE ha.id=hp.author_id
                ),
                '1970-01-01 00:00:00.0'
              ),
              COALESCE(
                (
                  select max(hv.last_update + '0 days'::interval)
                  from hive_votes hv
                  WHERE ha.id=hv.voter_id
                ),
                '1970-01-01 00:00:00.0'
              )
            )
          ) active_at,
          reputation,
          rank,
          following,
          followers,
          lastread_at,
          posting_json_metadata,
          json_metadata,
          blacklist_description,
          muted_list_description
        FROM
          hive_accounts ha
          """
    db.query_no_return(sql)

    sql = """
        DROP VIEW IF EXISTS public.hive_accounts_view;

        CREATE OR REPLACE VIEW public.hive_accounts_view
        AS
        SELECT id,
          name,
          created_at,
          reputation,
          is_implicit,
          followers,
          following,
          rank,
          lastread_at,
          posting_json_metadata,
          json_metadata,
          ( reputation <= -464800000000 ) is_grayed -- biggest number where rep_log10 gives < 1.0
          FROM hive_accounts
          """
    db.query_no_return(sql)

    sql = """
        DROP VIEW IF EXISTS public.hive_posts_view;

        CREATE OR REPLACE VIEW public.hive_posts_view
        AS
        SELECT hp.id,
          hp.community_id,
          hp.root_id,
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
          hp.category_id,
          hp.depth,
          hp.promoted,
          hp.payout,
          hp.pending_payout,
          hp.payout_at,
          hp.last_payout_at,
          hp.cashout_time,
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
            COALESCE(
              (
                SELECT SUM( CASE v.rshares >= 0 WHEN True THEN v.rshares ELSE -v.rshares END )
                FROM hive_votes v
                WHERE v.post_id = hp.id AND NOT v.rshares = 0
                GROUP BY v.post_id
              ), 0
            ) AS abs_rshares,
            COALESCE(
              (
                SELECT COUNT( 1 )
                FROM hive_votes v
                WHERE v.post_id = hp.id AND v.is_effective
                GROUP BY v.post_id
              ), 0
            ) AS total_votes,
            COALESCE(
              (
                SELECT SUM( CASE v.rshares > 0 WHEN True THEN 1 ELSE -1 END )
                FROM hive_votes v
                WHERE v.post_id = hp.id AND NOT v.rshares = 0
                GROUP BY v.post_id
              ), 0
            ) AS net_votes,
          hpd.json,
          ha_a.reputation AS author_rep,
          hp.is_hidden,
          ha_a.is_grayed,
          hp.total_vote_weight,
          ha_pp.name AS parent_author,
          ha_pp.id AS parent_author_id,
            ( CASE hp.depth > 0
              WHEN True THEN hpd_pp.permlink
              ELSE hcd.category
            END ) AS parent_permlink_or_category,
          hp.curator_payout_value,
          ha_rp.name AS root_author,
          hpd_rp.permlink AS root_permlink,
          rcd.category as root_category,
          hp.max_accepted_payout,
          hp.percent_hbd,
            True AS allow_replies,
          hp.allow_votes,
          hp.allow_curation_rewards,
          hp.beneficiaries,
            CONCAT('/', rcd.category, '/@', ha_rp.name, '/', hpd_rp.permlink,
              CASE (rp.id)
                WHEN hp.id THEN ''
                ELSE CONCAT('#@', ha_a.name, '/', hpd_p.permlink)
              END
            ) AS url,
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
          hp.block_num
          FROM hive_posts hp
            JOIN hive_posts pp ON pp.id = hp.parent_id
            JOIN hive_posts rp ON rp.id = hp.root_id
            JOIN hive_accounts_view ha_a ON ha_a.id = hp.author_id
            JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
            JOIN hive_post_data hpd ON hpd.id = hp.id
            JOIN hive_accounts ha_pp ON ha_pp.id = pp.author_id
            JOIN hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
            JOIN hive_accounts ha_rp ON ha_rp.id = rp.author_id
            JOIN hive_permlink_data hpd_rp ON hpd_rp.id = rp.permlink_id
            JOIN hive_post_data rpd ON rpd.id = rp.id
            JOIN hive_category_data hcd ON hcd.id = hp.category_id
            JOIN hive_category_data rcd ON rcd.id = rp.category_id
            LEFT JOIN hive_communities hc ON hp.community_id = hc.id
            LEFT JOIN hive_roles hr ON hp.author_id = hr.account_id AND hp.community_id = hr.community_id
          WHERE hp.counter_deleted = 0;
          """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION IF EXISTS public.update_hive_posts_root_id(INTEGER, INTEGER);

          CREATE OR REPLACE FUNCTION public.update_hive_posts_root_id(in _first_block_num INTEGER, _last_block_num INTEGER)
              RETURNS void
              LANGUAGE 'plpgsql'
              VOLATILE
          AS $BODY$
          BEGIN

          --- _first_block_num can be null together with _last_block_num
          UPDATE hive_posts uhp
          SET root_id = id
          WHERE uhp.root_id = 0 AND (_first_block_num IS NULL OR (uhp.block_num >= _first_block_num AND uhp.block_num <= _last_block_num))
          ;
          END
          $BODY$;
          """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION IF EXISTS public.update_hive_posts_children_count(INTEGER, INTEGER);

          CREATE OR REPLACE FUNCTION public.update_hive_posts_children_count(in _first_block INTEGER, in _last_block INTEGER)
              RETURNS void
              LANGUAGE 'plpgsql'
              VOLATILE
          AS $BODY$
          BEGIN
          set local work_mem='2GB';

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
               WHERE h1.depth > 0 AND h1.counter_deleted = 0
                     AND h1.block_num BETWEEN _first_block AND _last_block
               ORDER BY h1.depth DESC
              ) s
              UNION ALL
              SELECT tblChild.queried_parent, p.id FROM hive_posts p
              JOIN tblChild  ON p.Parent_Id = tblChild.Id
              WHERE p.counter_deleted = 0
            )
            SELECT queried_parent, cast(count(1) AS int) AS children_count
            FROM tblChild
            GROUP BY queried_parent
          ) data_source
          WHERE uhp.id = data_source.queried_parent
          ;
          reset work_mem;
          END
          $BODY$;
          """
    db.query_no_return(sql)

    sql = """
        DROP VIEW IF EXISTS hive_votes_view
        ;
        CREATE OR REPLACE VIEW hive_votes_view
        AS
        SELECT
            hv.id,
            hv.voter_id as voter_id,
            ha_a.name as author,
            hpd.permlink as permlink,
            vote_percent as percent,
            ha_v.reputation as reputation,
            rshares,
            last_update,
            ha_v.name as voter,
            weight,
            num_changes,
            hv.permlink_id as permlink_id,
            post_id,
            is_effective
        FROM
            hive_votes hv
        INNER JOIN hive_accounts ha_v ON ha_v.id = hv.voter_id
        INNER JOIN hive_accounts ha_a ON ha_a.id = hv.author_id
        INNER JOIN hive_permlink_data hpd ON hpd.id = hv.permlink_id
        ;
    """
    db.query_no_return(sql)

    sql = """
        DROP TYPE IF EXISTS database_api_vote CASCADE;

        CREATE TYPE database_api_vote AS (
          id BIGINT,
          voter VARCHAR(16),
          author VARCHAR(16),
          permlink VARCHAR(255),
          weight NUMERIC,
          rshares BIGINT,
          percent INT,
          last_update TIMESTAMP,
          num_changes INT,
          reputation BIGINT
        );

        DROP FUNCTION IF EXISTS find_votes( character varying, character varying, int )
        ;
        CREATE OR REPLACE FUNCTION public.find_votes
        (
          in _AUTHOR hive_accounts.name%TYPE,
          in _PERMLINK hive_permlink_data.permlink%TYPE,
          in _LIMIT INT
        )
        RETURNS SETOF database_api_vote
        LANGUAGE 'plpgsql'
        AS
        $function$
        DECLARE _POST_ID INT;
        BEGIN
        _POST_ID = find_comment_id( _AUTHOR, _PERMLINK, True);

        RETURN QUERY
        (
            SELECT
                v.id,
                v.voter,
                v.author,
                v.permlink,
                v.weight,
                v.rshares,
                v.percent,
                v.last_update,
                v.num_changes,
                v.reputation
            FROM
                hive_votes_view v
            WHERE
                v.post_id = _POST_ID
            ORDER BY
                voter_id
            LIMIT _LIMIT
        );

        END
        $function$;

        DROP FUNCTION IF EXISTS list_votes_by_voter_comment( character varying, character varying, character varying, int )
        ;
        CREATE OR REPLACE FUNCTION public.list_votes_by_voter_comment
        (
          in _VOTER hive_accounts.name%TYPE,
          in _AUTHOR hive_accounts.name%TYPE,
          in _PERMLINK hive_permlink_data.permlink%TYPE,
          in _LIMIT INT
        )
        RETURNS SETOF database_api_vote
        LANGUAGE 'plpgsql'
        AS
        $function$
        DECLARE __voter_id INT;
        DECLARE __post_id INT;
        BEGIN

        __voter_id = find_account_id( _VOTER, True );
        __post_id = find_comment_id( _AUTHOR, _PERMLINK, True );

        RETURN QUERY
        (
            SELECT
                v.id,
                v.voter,
                v.author,
                v.permlink,
                v.weight,
                v.rshares,
                v.percent,
                v.last_update,
                v.num_changes,
                v.reputation
            FROM
                hive_votes_view v
            WHERE
                v.voter_id = __voter_id
                AND v.post_id >= __post_id
            ORDER BY
                v.post_id
            LIMIT _LIMIT
        );

        END
        $function$;

        DROP FUNCTION IF EXISTS list_votes_by_comment_voter( character varying, character varying, character varying, int )
        ;
        CREATE OR REPLACE FUNCTION public.list_votes_by_comment_voter
        (
          in _VOTER hive_accounts.name%TYPE,
          in _AUTHOR hive_accounts.name%TYPE,
          in _PERMLINK hive_permlink_data.permlink%TYPE,
          in _LIMIT INT
        )
        RETURNS SETOF database_api_vote
        LANGUAGE 'plpgsql'
        AS
        $function$
        DECLARE __voter_id INT;
        DECLARE __post_id INT;
        BEGIN

        __voter_id = find_account_id( _VOTER, _VOTER != '' ); -- voter is optional
        __post_id = find_comment_id( _AUTHOR, _PERMLINK, True );

        RETURN QUERY
        (
            SELECT
                v.id,
                v.voter,
                v.author,
                v.permlink,
                v.weight,
                v.rshares,
                v.percent,
                v.last_update,
                v.num_changes,
                v.reputation
            FROM
                hive_votes_view v
            WHERE
                v.post_id = __post_id
                AND v.voter_id >= __voter_id
            ORDER BY
                v.voter_id
            LIMIT _LIMIT
        );

        END
        $function$;
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
        last_payout_at TIMESTAMP,
        cashout_time TIMESTAMP,
        is_paidout BOOLEAN,
        children INT,
        votes INT,
        created_at TIMESTAMP,
        updated_at TIMESTAMP,
        rshares NUMERIC,
        json TEXT,
        is_hidden BOOLEAN,
        is_grayed BOOLEAN,
        total_votes BIGINT,
        net_votes BIGINT,
        total_vote_weight NUMERIC,
        parent_author VARCHAR(16),
        parent_permlink_or_category VARCHAR(255),
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
        abs_rshares NUMERIC,
        active TIMESTAMP,
        author_rewards BIGINT
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
        DECLARE
          __post_id INT;
        BEGIN
          __post_id = find_comment_id(_author,_permlink, True);
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
              hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards
          FROM
              hive_posts_view hp
          INNER JOIN
          (
              SELECT
                  hp1.id
              FROM
                  hive_posts hp1
              WHERE
                  hp1.counter_deleted = 0
                  AND NOT hp1.is_muted
                  AND hp1.cashout_time > _cashout_time
                  OR hp1.cashout_time = _cashout_time
                  AND hp1.id >= __post_id AND hp1.id != 0
              ORDER BY
                  hp1.cashout_time ASC,
                  hp1.id ASC
              LIMIT
                  _limit
          ) ds ON ds.id = hp.id
          ORDER BY
              hp.cashout_time ASC,
              hp.id ASC
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
        LANGUAGE sql
        STABLE
        AS
        $function$
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
              hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards
          FROM
              hive_posts_view hp
          INNER JOIN
          (
              SELECT hp1.id
              FROM
                  hive_posts_api_helper hp1
              INNER JOIN hive_posts hp2 ON hp2.id = hp1.id
              WHERE
                  hp2.counter_deleted = 0
                  AND NOT hp2.is_muted
                  AND hp1.author > _author
                  OR hp1.author = _author
                  AND hp1.permlink >= _permlink
                  AND hp1.id != 0
              ORDER BY
                  hp1.author ASC,
                  hp1.permlink ASC
              LIMIT
                  _limit
          ) ds ON ds.id = hp.id
          ORDER BY
              hp.author ASC,
              hp.permlink ASC
        $function$
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
        DECLARE
          __root_id INT;
          __post_id INT;
        BEGIN
          __root_id = find_comment_id(_root_author, _root_permlink, True);
          __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
          RETURN QUERY
          SELECT
            hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
            hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
            hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
            hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
            hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
            hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
            hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
            hp.active, hp.author_rewards
          FROM
            hive_posts_view hp
          INNER JOIN
          (
            SELECT
              hp2.id
            FROM
              hive_posts hp2
            WHERE
              hp2.counter_deleted = 0
              AND NOT hp2.is_muted
              AND hp2.root_id = __root_id
              AND hp2.id >= __post_id
            ORDER BY
              hp2.id ASC
            LIMIT _limit
          ) ds on hp.id = ds.id
          ORDER BY
            hp.id
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
      AS $function$
      DECLARE
        __post_id INT;
        __parent_id INT;
      BEGIN
        __parent_id = find_comment_id(_parent_author, _parent_permlink, True);
        __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
        RETURN QUERY
        SELECT
          hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
          hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
          hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
          hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
          hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
          hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
          hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
          hp.active, hp.author_rewards
        FROM
          hive_posts_view hp
        INNER JOIN
        (
          SELECT hp1.id FROM
            hive_posts hp1
          WHERE
            hp1.counter_deleted = 0
            AND NOT hp1.is_muted
            AND hp1.parent_id = __parent_id
            AND hp1.id >= __post_id
          ORDER BY
            hp1.id ASC
          LIMIT
            _limit
        ) ds ON ds.id = hp.id
        ORDER BY
          hp.id
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
        DECLARE
          __post_id INT;
          __parent_author_id INT;
        BEGIN
          __parent_author_id = find_account_id(_parent_author, True);
          __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
              hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards
          FROM
              hive_posts_view hp
          INNER JOIN
          (
              SELECT
                hp1.id
              FROM
                hive_posts hp1
              JOIN
                hive_posts hp2 ON hp1.parent_id = hp2.id
              WHERE
                hp1.counter_deleted = 0
                AND NOT hp1.is_muted
                AND hp2.author_id = __parent_author_id
                AND (
                  hp1.updated_at < _updated_at
                  OR hp1.updated_at = _updated_at
                  AND hp1.id >= __post_id
                )
              ORDER BY
                hp1.updated_at DESC,
                hp1.id ASC
              LIMIT
                _limit
          ) ds ON ds.id = hp.id
          ORDER BY
            hp.updated_at DESC,
            hp.id ASC
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
        DECLARE
          __author_id INT;
          __post_id INT;
        BEGIN
          __author_id = find_account_id(_author, True);
          __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
          RETURN QUERY
          SELECT
              hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
              hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
              hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
              hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
              hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
              hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
              hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
              hp.active, hp.author_rewards
          FROM
              hive_posts_view hp
          INNER JOIN
          (
            SELECT
              hp1.id
            FROM
              hive_posts hp1
            WHERE
              hp1.counter_deleted = 0
              AND NOT hp1.is_muted
              AND hp1.author_id = __author_id
              AND (
                hp1.updated_at < _updated_at
                OR hp1.updated_at = _updated_at
                AND hp1.id >= __post_id
              )
            ORDER BY
              hp1.updated_at DESC,
              hp1.id ASC
            LIMIT
              _limit
          ) ds ON ds.id = hp.id
          ORDER BY
              hp.updated_at DESC,
              hp.id ASC
          ;
        END
        $function$
        LANGUAGE plpgsql
      ;
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
        DROP FUNCTION IF EXISTS public.max_time_stamp() CASCADE;
        CREATE OR REPLACE FUNCTION public.max_time_stamp( _first TIMESTAMP, _second TIMESTAMP )
        RETURNS TIMESTAMP
        LANGUAGE 'plpgsql'
        IMMUTABLE
        AS $BODY$
        BEGIN
          IF _first > _second THEN
               RETURN _first;
            ELSE
               RETURN _second;
            END IF;
        END
        $BODY$;
        """
    db.query_no_return(sql)

    sql = """
          DROP FUNCTION IF EXISTS public.update_hive_posts_api_helper(INTEGER, INTEGER);

          CREATE OR REPLACE FUNCTION public.update_hive_posts_api_helper(in _first_block_num INTEGER, _last_block_num INTEGER)
            RETURNS void
            LANGUAGE 'plpgsql'
            VOLATILE
          AS $BODY$
          BEGIN
          IF _first_block_num IS NULL OR _last_block_num IS NULL THEN
            -- initial creation of table.

            INSERT INTO hive_posts_api_helper
            (id, author, permlink)
            SELECT hp.id, hp.author, hp.permlink
            FROM hive_posts_view hp
            ;
          ELSE
            -- Regular incremental update.
            INSERT INTO hive_posts_api_helper
            (id, author, permlink)
            SELECT hp.id, hp.author, hp.permlink
            FROM hive_posts_view hp
            WHERE hp.block_num BETWEEN _first_block_num AND _last_block_num AND
                   NOT EXISTS (SELECT NULL FROM hive_posts_api_helper h WHERE h.id = hp.id)
            ;
          END IF;

          END
          $BODY$
          """
    db.query_no_return(sql)

    sql = """
        DROP FUNCTION IF EXISTS get_discussion
        ;
        CREATE OR REPLACE FUNCTION get_discussion(
            in _author hive_accounts.name%TYPE,
            in _permlink hive_permlink_data.permlink%TYPE
        )
        RETURNS TABLE
        (
            id hive_posts.id%TYPE, parent_id hive_posts.parent_id%TYPE, author hive_accounts.name%TYPE, permlink hive_permlink_data.permlink%TYPE,
            title hive_post_data.title%TYPE, body hive_post_data.body%TYPE, category hive_category_data.category%TYPE, depth hive_posts.depth%TYPE,
            promoted hive_posts.promoted%TYPE, payout hive_posts.payout%TYPE, pending_payout hive_posts.pending_payout%TYPE, payout_at hive_posts.payout_at%TYPE,
            is_paidout hive_posts.is_paidout%TYPE, children hive_posts.children%TYPE, created_at hive_posts.created_at%TYPE, updated_at hive_posts.updated_at%TYPE,
            rshares hive_posts_view.rshares%TYPE, abs_rshares hive_posts_view.abs_rshares%TYPE, json hive_post_data.json%TYPE, author_rep hive_accounts.reputation%TYPE,
            is_hidden hive_posts.is_hidden%TYPE, is_grayed BOOLEAN, total_votes BIGINT, sc_trend hive_posts.sc_trend%TYPE,
            acct_author_id hive_posts.author_id%TYPE, root_author hive_accounts.name%TYPE, root_permlink hive_permlink_data.permlink%TYPE,
            parent_author hive_accounts.name%TYPE, parent_permlink_or_category hive_permlink_data.permlink%TYPE, allow_replies BOOLEAN,
            allow_votes hive_posts.allow_votes%TYPE, allow_curation_rewards hive_posts.allow_curation_rewards%TYPE, url TEXT, root_title hive_post_data.title%TYPE,
            beneficiaries hive_posts.beneficiaries%TYPE, max_accepted_payout hive_posts.max_accepted_payout%TYPE, percent_hbd hive_posts.percent_hbd%TYPE,
            curator_payout_value hive_posts.curator_payout_value%TYPE
        )
        LANGUAGE plpgsql
        AS
        $function$
        DECLARE
            __post_id INT;
        BEGIN
            __post_id = find_comment_id( _author, _permlink, True );
            RETURN QUERY
            SELECT
                hpv.id,
                hpv.parent_id,
                hpv.author,
                hpv.permlink,
                hpv.title,
                hpv.body,
                hpv.category,
                hpv.depth,
                hpv.promoted,
                hpv.payout,
                hpv.pending_payout,
                hpv.payout_at,
                hpv.is_paidout,
                hpv.children,
                hpv.created_at,
                hpv.updated_at,
                hpv.rshares,
                hpv.abs_rshares,
                hpv.json,
                hpv.author_rep,
                hpv.is_hidden,
                hpv.is_grayed,
                hpv.total_votes,
                hpv.sc_trend,
                hpv.author_id AS acct_author_id,
                hpv.root_author,
                hpv.root_permlink,
                hpv.parent_author,
                hpv.parent_permlink_or_category,
                hpv.allow_replies,
                hpv.allow_votes,
                hpv.allow_curation_rewards,
                hpv.url,
                hpv.root_title,
                hpv.beneficiaries,
                hpv.max_accepted_payout,
                hpv.percent_hbd,
                hpv.curator_payout_value
            FROM
            (
                WITH RECURSIVE child_posts (id, parent_id) AS
                (
                    SELECT hp.id, hp.parent_id
                    FROM hive_posts hp
                    WHERE hp.id = __post_id
                    AND NOT hp.is_muted
                    UNION ALL
                    SELECT children.id, children.parent_id
                    FROM hive_posts children
                    JOIN child_posts ON children.parent_id = child_posts.id
                    WHERE children.counter_deleted = 0 AND NOT children.is_muted
                )
                SELECT hp2.id
                FROM hive_posts hp2
                JOIN child_posts cp ON cp.id = hp2.id
                ORDER BY hp2.id
            ) ds
            JOIN hive_posts_view hpv ON ds.id = hpv.id
            ORDER BY ds.id
            LIMIT 2000
            ;
        END
        $function$
        ;
    """

    db.query_no_return(sql)

    sql_scripts = [
      "hive_posts_base_view.sql",
      "head_block_time.sql",
      "update_feed_cache.sql",
      "payout_stats_view.sql",
      "update_hive_posts_mentions.sql",
      "find_tag_id.sql",
      "bridge_get_ranked_post_type.sql",
      "bridge_get_ranked_post_for_communities.sql",
      "bridge_get_ranked_post_for_observer_communities.sql",
      "bridge_get_ranked_post_for_tag.sql",
      "bridge_get_ranked_post_for_all.sql",
      "calculate_account_reputations.sql",
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
      "condenser_api_post_ex_type.sql",
      "condenser_get_content.sql",
      "condenser_get_discussions_by_created.sql",
      "condenser_get_discussions_by_blog.sql",
      "hot_and_trends.sql",
      "condenser_get_discussions_by_trending.sql",
      "condenser_get_discussions_by_hot.sql",
      "condenser_get_discussions_by_promoted.sql",
      "condenser_get_post_discussions_by_payout.sql",
      "condenser_get_comment_discussions_by_payout.sql"
    ]
    from os.path import dirname, realpath
    dir_path = dirname(realpath(__file__))
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
