-- This script will upgrade hivemind database to new version
-- Authors: Dariusz Kędzierski
-- Created: 26-04-2020
-- Last edit: 26-05-2020

CREATE TABLE IF NOT EXISTS hive_db_version (
  version VARCHAR(50) PRIMARY KEY,
  notes VARCHAR(1024)
);

-- Upgrade to version 1.0
-- in this version we will move data from raw_json into separate columns
-- also will split hive_posts_cache to parts and then move all data to proper tables
-- also it will add needed indexes and procedures
DO $$
  BEGIN
    RAISE NOTICE 'Upgrading database to version 1.0';
    IF NOT EXISTS (SELECT version FROM hive_db_version WHERE version = '1.0')
    THEN
      -- Begin transaction
      BEGIN TRANSACTION;
      -- Update version info
      INSERT INTO hive_db_version (version, notes) VALUES ('1.0', 'https://gitlab.syncad.com/blocktrades/hivemind/issues/5');

      -- add special author value, empty author to accounts table
      RAISE NOTICE 'add special author value, empty author to accounts table'
      INSERT INTO hive_accounts (name, created_at) VALUES ('', '1990-01-01T00:00:00');

      -- Table to hold permlink dictionary, permlink is unique
      RAISE NOTICE 'Table to hold permlink dictionary, permlink is unique'
      CREATE TABLE IF NOT EXISTS hive_permlink_data (
          id SERIAL PRIMARY KEY NOT NULL,
          permlink VARCHAR(255) NOT NULL CONSTRAINT hive_permlink_data_permlink UNIQUE
      );
      -- Populate hive_permlink_data
      -- insert special permlink, empty permlink
      RAISE NOTICE 'insert special permlink, empty permlink'
      INSERT INTO hive_permlink_data (permlink) VALUES ('');
      -- run on permlink field of hive_posts_cache
      RAISE NOTICE 'run on permlink field of hive_posts_cache'
      INSERT INTO hive_permlink_data (permlink) SELECT permlink FROM hive_posts ON CONFLICT (permlink) DO NOTHING;
      -- we should also scan parent_permlink and root_permlink but we will do that on raw_json scan
      -- Create indexes
      CREATE INDEX IF NOT EXISTS hive_permlink_data_permlink_idx ON hive_permlink_data (permlink ASC);
      CREATE INDEX IF NOT EXISTS hive_permlink_data_permlink_c_idx ON hive_permlink_data (permlink COLLATE "C" ASC);

      -- Table to hold category data, category is unique
      RAISE NOTICE 'Table to hold category data, category is unique'
      CREATE TABLE IF NOT EXISTS hive_category_data (
          id SERIAL PRIMARY KEY NOT NULL,
          category VARCHAR(255) NOT NULL CONSTRAINT hive_category_data_category UNIQUE
      );
      -- Populate hive_category_data
      -- insert special category, empty category
      RAISE NOTICE 'insert special category, empty category'
      INSERT INTO hive_category_data (category) VALUES ('');
      -- run on category field of hive_posts_cache
      RAISE NOTICE 'run on category field of hive_posts_cache'
      INSERT INTO hive_category_data (category) SELECT category FROM hive_posts ON CONFLICT (category) DO NOTHING;
      -- Create indexes
      CREATE INDEX IF NOT EXISTS hive_category_data_category_idx ON hive_category_data (category ASC);
      CREATE INDEX IF NOT EXISTS hive_category_data_category_c_idx ON hive_category_data (category COLLATE "C" ASC);

      -- Table to hold post data
      RAISE NOTICE 'Table to hold post data'
      CREATE TABLE IF NOT EXISTS hive_posts_new (
        id INT DEFAULT '-1',
        parent_id INT DEFAULT '-1',
        author_id INT DEFAULT '-1',
        permlink_id INT DEFAULT '-1',
        category_id INT DEFAULT '1',
        community_id INT,
        created_at DATE DEFAULT '1990-01-01T00:00:00',
        depth SMALLINT DEFAULT '-1',
        is_deleted BOOLEAN DEFAULT '0',
        is_pinned BOOLEAN DEFAULT '0',
        is_muted BOOLEAN DEFAULT '0',
        is_valid BOOLEAN DEFAULT '1',
        promoted NUMERIC(10, 3) DEFAULT '0.0',
        
        -- important/index
        children SMALLINT DEFAULT '-1',

        -- basic/extended-stats
        author_rep NUMERIC(6) DEFAULT '0.0',
        flag_weight NUMERIC(6) DEFAULT '0.0',
        total_votes INT DEFAULT '-1',
        up_votes INT DEFAULT '-1',
        
        -- core stats/indexes
        payout NUMERIC(10, 3) DEFAULT '0.0',
        payout_at DATE DEFAULT '1990-01-01T00:00:00',
        updated_at DATE DEFAULT '1990-01-01T00:00:00',
        is_paidout BOOLEAN DEFAULT '0',

        -- ui flags/filters
        is_nsfw BOOLEAN DEFAULT '0',
        is_declined BOOLEAN DEFAULT '0',
        is_full_power BOOLEAN DEFAULT '0',
        is_hidden BOOLEAN DEFAULT '0',
        is_grayed BOOLEAN DEFAULT '0',

        -- important indexes
        rshares BIGINT DEFAULT '-1',
        sc_trend NUMERIC(6) DEFAULT '0.0',
        sc_hot NUMERIC(6) DEFAULT '0.0',

        -- columns from raw_json
        parent_author_id INT DEFAULT '-1',
        parent_permlink_id INT DEFAULT '-1',
        curator_payout_value VARCHAR(16) DEFAULT '',
        root_author_id INT DEFAULT '-1',
        root_permlink_id INT DEFAULT '-1',
        max_accepted_payout VARCHAR(16) DEFAULT '',
        percent_steem_dollars INT DEFAULT '-1',
        allow_replies BOOLEAN DEFAULT '1',
        allow_votes BOOLEAN DEFAULT '1',
        allow_curation_rewards BOOLEAN DEFAULT '1',
        beneficiaries JSON DEFAULT '[]',
        url TEXT DEFAULT '',
        root_title VARCHAR(255) DEFAULT ''
      );

      -- Table to hold bulk post data
      RAISE NOTICE 'Table to hold bulk post data'
      CREATE TABLE IF NOT EXISTS hive_post_data (
        id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
        preview VARCHAR(1024) NOT NULL,
        img_url VARCHAR(1024) NOT NULL,
        body TEXT,
        votes TEXT,
        json JSON
      );

      -- Copy data from hive_posts table to new table
      RAISE NOTICE 'Copy data from hive_posts table to new table'
      INSERT INTO hive_posts_new (
        id,
        parent_id,
        author_id,
        permlink_id,
        category_id,
        community_id,
        created_at,
        depth,
        is_deleted,
        is_pinned,
        is_muted,
        is_valid,
        promoted
      )
      SELECT
        hp.id,
        hp.parent_id,
        (SELECT id FROM hive_accounts WHERE name = hp.author) as author_id,
        (SELECT id FROM hive_permlink_data WHERE permlink = hp.permlink) as permlink_id,
        (SELECT id FROM hive_category_data WHERE category = hp.category) as category_id,
        hp.community_id,
        hp.created_at,
        hp.depth,
        hp.is_deleted,
        hp.is_pinned,
        hp.is_muted,
        hp.is_valid,
        hp.promoted
      FROM
        hive_posts hp;

      -- Copy standard data to new posts table
      RAISE NOTICE 'Copy standard data to new posts table'
      UPDATE hive_posts_new hpn SET (                             
        children, author_rep, flag_weight, total_votes, up_votes, payout,
        payout_at, updated_at, is_paidout, is_nsfw, is_declined, is_full_power,
        is_hidden, is_grayed, rshares, sc_trend, sc_hot)
      =
        (SELECT
          children, author_rep, flag_weight, total_votes, up_votes, payout,
          payout_at, updated_at, is_paidout, is_nsfw, is_declined, is_full_power,
          is_hidden, is_grayed, rshares, sc_trend, sc_hot FROM hive_posts_cache hpc WHERE hpn.id = hpc.post_id);

      -- Populate table hive_post_data with bulk data from hive_posts_cache
      RAISE NOTICE 'Populate table hive_post_data with bulk data from hive_posts_cache'
      INSERT INTO hive_post_data (id, title, preview, img_url, body, votes, json) SELECT post_id, title, preview, img_url, body, votes, json::json FROM hive_posts_cache;

      RAISE NOTICE 'Copying raw_json data to proper colums'

      -- Helper type for use with json_populate_record
      CREATE TEMPORARY TABLE legacy_comment_data (
        id BIGINT,
        raw_json TEXT,
        parent_author VARCHAR(16),
        parent_permlink VARCHAR(255),
        curator_payout_value VARCHAR(16),
        root_author VARCHAR(16),
        root_permlink VARCHAR(255),
        max_accepted_payout VARCHAR(16),
        percent_steem_dollars INT,
        allow_replies BOOLEAN,
        allow_votes BOOLEAN,
        allow_curation_rewards BOOLEAN,
        beneficiaries JSON,
        url TEXT,
        root_title VARCHAR(255)
      );

      CREATE TYPE legacy_comment_type AS (
        id BIGINT,
        parent_author VARCHAR(16),
        parent_permlink VARCHAR(255),
        curator_payout_value VARCHAR(16),
        root_author VARCHAR(16),
        root_permlink VARCHAR(255),
        max_accepted_payout VARCHAR(16),
        percent_steem_dollars INT,
        allow_replies BOOLEAN,
        allow_votes BOOLEAN,
        allow_curation_rewards BOOLEAN,
        beneficiaries JSON,
        url TEXT,
        root_title VARCHAR(255)
      );

      INSERT INTO legacy_comment_data (id, raw_json) SELECT post_id, raw_json FROM hive_posts_cache;
      
      update legacy_comment_data lcd set (parent_author, parent_permlink, 
        curator_payout_value, root_author, root_permlink, max_accepted_payout,
        percent_steem_dollars, allow_replies, allow_votes, allow_curation_rewards,
        beneficiaries, url, root_title)
      =
      (SELECT parent_author, parent_permlink, 
        curator_payout_value, root_author, root_permlink, max_accepted_payout,
        percent_steem_dollars, allow_replies, allow_votes, allow_curation_rewards,
        beneficiaries, url, root_title from json_populate_record(null::legacy_comment_type, lcd.raw_json::json)
      );
      
      
      INSERT INTO hive_permlink_data (permlink) SELECT parent_permlink FROM legacy_comment_data ON CONFLICT (permlink) DO NOTHING;
      INSERT INTO hive_permlink_data (permlink) SELECT root_permlink FROM legacy_comment_data ON CONFLICT (permlink) DO NOTHING;

      UPDATE hive_posts_new hpn SET
        parent_author_id = (SELECT id FROM hive_accounts WHERE name = lcd.parent_author),
        parent_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = lcd.parent_permlink),
        curator_payout_value = lcd.curator_payout_value,
        root_author_id = (SELECT id FROM hive_accounts WHERE name = lcd.root_author),
        root_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = lcd.root_permlink),
        max_accepted_payout = lcd.max_accepted_payout,
        percent_steem_dollars = lcd.percent_steem_dollars,
        allow_replies = lcd.allow_replies,
        allow_votes = lcd.allow_votes,
        allow_curation_rewards = lcd.allow_curation_rewards,
        beneficiaries = lcd.beneficiaries,
        url = lcd.url,
        root_title = lcd.root_title
      FROM (SELECT id, parent_author, parent_permlink, curator_payout_value, root_author, root_permlink,
        max_accepted_payout, percent_steem_dollars, allow_replies, allow_votes, allow_curation_rewards,
        beneficiaries, url, root_title FROM legacy_comment_data) AS lcd
      WHERE lcd.id = hpn.id;

      -- Drop and rename tables after data migration
      DROP TYPE IF EXISTS legacy_comment_type;
      DROP TABLE IF EXISTS legacy_comment_data;
      DROP TABLE IF EXISTS hive_posts_cache;
      -- before deleting hive_posts we need to remove constraints
      ALTER TABLE hive_payments DROP CONSTRAINT hive_payments_fk3;
      ALTER TABLE hive_reblogs DROP CONSTRAINT hive_reblogs_fk2;
      DROP TABLE IF EXISTS hive_posts;
      -- now rename table 
      ALTER TABLE hive_posts_new RENAME TO hive_posts;
      -- in order to make id column a primary key we will need a sequence
      CREATE SEQUENCE hive_posts_serial OWNED BY hive_posts.id;
      -- and init that sequence from largest id + 1
      SELECT setval('hive_posts_serial', (SELECT max(id)+1 FROM hive_posts), false);
      -- now set that sequence as id sequence for hive_posts
      ALTER TABLE hive_posts ALTER COLUMN id set default nextval('hive_posts_serial');
      -- finally add primary key
      ALTER TABLE hive_posts ADD PRIMARY KEY (id);
      -- put constraints back
      ALTER TABLE hive_payments ADD CONSTRAINT hive_payments_fk3 FOREIGN KEY (post_id) REFERENCES hive_posts(id);
      ALTER TABLE hive_reblogs ADD CONSTRAINT hive_reblogs_fk2 FOREIGN KEY (post_id) REFERENCES hive_posts(id);

      -- Make indexes in hive_posts
      -- sa.ForeignKeyConstraint(['author'], ['hive_accounts.name'], name='hive_posts_fk1'),
      -- sa.ForeignKeyConstraint(['parent_id'], ['hive_posts.id'], name='hive_posts_fk3'),
      -- sa.UniqueConstraint('author', 'permlink', name='hive_posts_ux1'),
        
      -- Consider using simple indexes instead complex ones
      -- sa.Index('hive_posts_ix3', 'author', 'depth', 'id', postgresql_where=sql_text("is_deleted = '0'")), # API: author blog/comments
      -- sa.Index('hive_posts_ix4', 'parent_id', 'id', postgresql_where=sql_text("is_deleted = '0'")), # API: fetching children
      -- sa.Index('hive_posts_ix5', 'id', postgresql_where=sql_text("is_pinned = '1' AND is_deleted = '0'")), # API: pinned post status
      -- sa.Index('hive_posts_ix6', 'community_id', 'id', postgresql_where=sql_text("community_id IS NOT NULL AND is_pinned = '1' AND is_deleted = '0'")), # API: community pinned

      -- # index: misc
      -- sa.Index('hive_posts_cache_ix3',  'payout_at', 'post_id',           postgresql_where=sql_text("is_paidout = '0'")),         # core: payout sweep
      -- sa.Index('hive_posts_cache_ix8',  'category', 'payout', 'depth',    postgresql_where=sql_text("is_paidout = '0'")),         # API: tag stats

      -- # index: ranked posts
      -- sa.Index('hive_posts_cache_ix2',  'promoted',             postgresql_where=sql_text("is_paidout = '0' AND promoted > 0")),  # API: promoted

      -- sa.Index('hive_posts_cache_ix6a', 'sc_trend', 'post_id',  postgresql_where=sql_text("is_paidout = '0'")),                   # API: trending             todo: depth=0
      -- sa.Index('hive_posts_cache_ix7a', 'sc_hot',   'post_id',  postgresql_where=sql_text("is_paidout = '0'")),                   # API: hot                  todo: depth=0
      -- sa.Index('hive_posts_cache_ix6b', 'post_id',  'sc_trend', postgresql_where=sql_text("is_paidout = '0'")),                   # API: trending, filtered   todo: depth=0
      -- sa.Index('hive_posts_cache_ix7b', 'post_id',  'sc_hot',   postgresql_where=sql_text("is_paidout = '0'")),                   # API: hot, filtered        todo: depth=0

      -- sa.Index('hive_posts_cache_ix9a',             'depth', 'payout', 'post_id', postgresql_where=sql_text("is_paidout = '0'")), # API: payout               todo: rem depth
      -- sa.Index('hive_posts_cache_ix9b', 'category', 'depth', 'payout', 'post_id', postgresql_where=sql_text("is_paidout = '0'")), # API: payout, filtered     todo: rem depth

      -- sa.Index('hive_posts_cache_ix10', 'post_id', 'payout',                      postgresql_where=sql_text("is_grayed = '1' AND payout > 0")), # API: muted, by filter/date/payout
      CREATE INDEX IF NOT EXISTS hive_posts_ix10 ON hive_posts (id, payout) WHERE is_grayed = '1' AND payout > 0;

      -- # index: stats
      -- sa.Index('hive_posts_cache_ix20', 'community_id', 'author', 'payout', 'post_id', postgresql_where=sql_text("is_paidout = '0'")), # API: pending distribution; author payout
      CREATE INDEX IF NOT EXISTS hive_posts_ix20 ON hive_posts (community_id, author_id, payout, id) WHERE is_paidout = '0';

      -- # index: community ranked posts
      -- sa.Index('hive_posts_cache_ix30', 'community_id', 'sc_trend',   'post_id',  postgresql_where=sql_text("community_id IS NOT NULL AND is_grayed = '0' AND depth = 0")),        # API: community trend
      CREATE INDEX IF NOT EXISTS hive_posts_ix30 ON hive_posts (community_id, sc_trend, id) WHERE community_id IS NOT NULL AND is_grayed = '0' AND depth = 0;
      
      -- sa.Index('hive_posts_cache_ix31', 'community_id', 'sc_hot',     'post_id',  postgresql_where=sql_text("community_id IS NOT NULL AND is_grayed = '0' AND depth = 0")),        # API: community hot
      CREATE INDEX IF NOT EXISTS hive_posts_ix31 ON hive_posts (community_id, sc_hot, id) WHERE community_id IS NOT NULL AND is_grayed = '0' AND depth = 0;
      
      -- sa.Index('hive_posts_cache_ix32', 'community_id', 'created_at', 'post_id',  postgresql_where=sql_text("community_id IS NOT NULL AND is_grayed = '0' AND depth = 0")), # API: community created
      CREATE INDEX IF NOT EXISTS hive_posts_ix32 ON hive_posts (community_id, created_at, id) WHERE community_id IS NOT NULL AND is_grayed = '0' AND depth = 0;
      
      -- sa.Index('hive_posts_cache_ix33', 'community_id', 'payout',     'post_id',  postgresql_where=sql_text("community_id IS NOT NULL AND is_grayed = '0' AND is_paidout = '0'")), # API: community payout
      CREATE INDEX IF NOT EXISTS hive_posts_ix32 ON hive_posts (community_id, payout, id) WHERE community_id IS NOT NULL AND is_grayed = '0' AND AND is_paidout = '0';

      -- sa.Index('hive_posts_cache_ix34', 'community_id', 'payout',     'post_id',  postgresql_where=sql_text("community_id IS NOT NULL AND is_grayed = '1' AND is_paidout = '0'")), # API: community muted
      CREATE INDEX IF NOT EXISTS hive_posts_ix32 ON hive_posts (community_id, payout, id) WHERE community_id IS NOT NULL AND is_grayed = '1' AND AND is_paidout = '0';

      -- Commit transaction
      COMMIT;
    ELSE
      RAISE NOTICE 'Database already in version 1.0';
    END IF;
  END
$$;
