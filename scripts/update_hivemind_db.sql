-- This script will upgrade hivemind database to new version
-- Authors: Dariusz Kędzierski
-- Created: 26-04-2020
-- Last edit: 26-05-2020

CREATE TABLE IF NOT EXISTS hive_db_version (
  version VARCHAR(50) PRIMARY KEY,
  notes VARCHAR(1024)
);

DO $$
  BEGIN
    RAISE NOTICE 'Upgrading database to version 1.0';
    IF EXISTS (SELECT version FROM hive_db_version WHERE version = '1.0')
    THEN
      RAISE EXCEPTION 'Database already in version 1.0';
    END IF;
  END
$$ LANGUAGE plpgsql;

-- Upgrade to version 1.0
-- in this version we will move data from raw_json into separate columns
-- also will split hive_posts_cache to parts and then move all data to proper tables
-- also it will add needed indexes and procedures

-- Update version info
INSERT INTO hive_db_version (version, notes) VALUES ('1.0', 'https://gitlab.syncad.com/blocktrades/hivemind/issues/5');

-- add special author value, empty author to accounts table
-- RAISE NOTICE 'add special author value, empty author to accounts table';
INSERT INTO hive_accounts (name, created_at) VALUES ('', '1990-01-01T00:00:00');

-- Table to hold permlink dictionary, permlink is unique
-- RAISE NOTICE 'Table to hold permlink dictionary, permlink is unique';
CREATE TABLE IF NOT EXISTS hive_permlink_data (
    id BIGSERIAL PRIMARY KEY NOT NULL,
    permlink VARCHAR(255) NOT NULL CONSTRAINT hive_permlink_data_permlink UNIQUE
);
-- Populate hive_permlink_data
-- insert special permlink, empty permlink
-- RAISE NOTICE 'insert special permlink, empty permlink';
INSERT INTO hive_permlink_data (permlink) VALUES ('');
-- run on permlink field of hive_posts_cache
-- RAISE NOTICE 'run on permlink field of hive_posts_cache';
INSERT INTO hive_permlink_data (permlink) SELECT permlink FROM hive_posts ON CONFLICT (permlink) DO NOTHING;
-- we should also scan parent_permlink and root_permlink but we will do that on raw_json scan

-- Table to hold category data, category is unique
-- RAISE NOTICE 'Table to hold category data, category is unique';
CREATE TABLE IF NOT EXISTS hive_category_data (
    id SERIAL PRIMARY KEY NOT NULL,
    category VARCHAR(255) NOT NULL CONSTRAINT hive_category_data_category UNIQUE
);
-- Populate hive_category_data
-- insert special category, empty category
-- RAISE NOTICE 'insert special category, empty category';
INSERT INTO hive_category_data (category) VALUES ('');
-- run on category field of hive_posts_cache
-- RAISE NOTICE 'run on category field of hive_posts_cache';
INSERT INTO hive_category_data (category) SELECT category FROM hive_posts ON CONFLICT (category) DO NOTHING;
-- Create indexes
CREATE INDEX IF NOT EXISTS hive_category_data_category_idx ON hive_category_data (category ASC);
CREATE INDEX IF NOT EXISTS hive_category_data_category_c_idx ON hive_category_data (category COLLATE "C" ASC);

-- Table to hold post data
-- RAISE NOTICE 'Table to hold post data';
CREATE TABLE IF NOT EXISTS hive_posts_new (
  id INT NOT NULL,
  parent_id INT,
  author_id INT NOT NULL,
  permlink_id BIGINT NOT NULL,
  category_id INT NOT NULL,
  community_id INT,
  created_at TIMESTAMP NOT NULL,
  depth SMALLINT DEFAULT '0',
  is_deleted BOOLEAN DEFAULT '0',
  is_pinned BOOLEAN DEFAULT '0',
  is_muted BOOLEAN DEFAULT '0',
  is_valid BOOLEAN DEFAULT '1',
  promoted NUMERIC(10, 3) DEFAULT '0.0',
  
  -- important/index
  children SMALLINT DEFAULT '0',

  -- basic/extended-stats
  author_rep NUMERIC(6) DEFAULT '0.0',
  flag_weight NUMERIC(6) DEFAULT '0.0',
  total_votes INT DEFAULT '0',
  up_votes INT DEFAULT '0',
  
  -- core stats/indexes
  payout NUMERIC(10, 3) DEFAULT '0.0',
  payout_at TIMESTAMP DEFAULT '1970-01-01T00:00:00',
  updated_at TIMESTAMP DEFAULT '1970-01-01T00:00:00',
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

  total_payout_value VARCHAR(30) DEFAULT '',
  author_rewards BIGINT DEFAULT '0',

  author_rewards_hive BIGINT DEFAULT '0',
  author_rewards_hbd BIGINT DEFAULT '0',
  author_rewards_vests BIGINT DEFAULT '0',

  children_abs_rshares BIGINT DEFAULT '0',
  abs_rshares BIGINT DEFAULT '0',
  vote_rshares BIGINT DEFAULT '0',
  net_votes INT DEFAULT '0',
  active TIMESTAMP DEFAULT '1970-01-01T00:00:00',
  last_payout TIMESTAMP DEFAULT '1970-01-01T00:00:00',
  cashout_time TIMESTAMP DEFAULT '1970-01-01T00:00:00',
  max_cashout_time TIMESTAMP DEFAULT '1970-01-01T00:00:00',
  reward_weight INT DEFAULT '0',

  -- columns from raw_json
  parent_author_id INT DEFAULT '-1',
  parent_permlink_id BIGINT DEFAULT '-1',
  curator_payout_value VARCHAR(30) DEFAULT '',
  root_author_id INT DEFAULT '-1',
  root_permlink_id BIGINT DEFAULT '-1',
  max_accepted_payout VARCHAR(30) DEFAULT '1000000.000 HBD',
  percent_hbd INT DEFAULT '10000',
  allow_replies BOOLEAN DEFAULT '1',
  allow_votes BOOLEAN DEFAULT '1',
  allow_curation_rewards BOOLEAN DEFAULT '1',
  beneficiaries JSON DEFAULT '[]',
  url TEXT DEFAULT '',
  root_title VARCHAR(255) DEFAULT ''
);

CREATE INDEX IF NOT EXISTS hive_posts_author_id_idx ON hive_posts_new (author_id);
CREATE INDEX IF NOT EXISTS hive_posts_permlink_id_idx ON hive_posts_new (permlink_id);

-- Table to hold bulk post data
-- RAISE NOTICE 'Table to hold bulk post data';
CREATE TABLE IF NOT EXISTS hive_post_data (
  id INT PRIMARY KEY NOT NULL,
  title VARCHAR(255) NOT NULL,
  preview VARCHAR(1024) NOT NULL,
  img_url VARCHAR(1024) NOT NULL,
  body TEXT,
  json TEXT
);

CREATE TABLE IF NOT EXISTS hive_votes (
  id BIGSERIAL PRIMARY KEY NOT NULL,
  voter_id INT NOT NULL REFERENCES hive_accounts (id) ON DELETE RESTRICT,
  author_id INT NOT NULL REFERENCES hive_accounts (id) ON DELETE RESTRICT,
  permlink_id INT NOT NULL REFERENCES hive_permlink_data (id) ON DELETE RESTRICT,
  weight BIGINT DEFAULT '0',
  rshares BIGINT DEFAULT '0',
  vote_percent INT DEFAULT '0',
  last_update TIMESTAMP DEFAULT '1970-01-01T00:00:00',
  num_changes INT DEFAULT '0'
);

CREATE INDEX IF NOT EXISTS hive_votes_voter_id_idx ON hive_votes (voter_id);
CREATE INDEX IF NOT EXISTS hive_votes_author_id_idx ON hive_votes (author_id);
CREATE INDEX IF NOT EXISTS hive_votes_permlink_id_idx ON hive_votes (permlink_id);
CREATE INDEX IF NOT EXISTS hive_votes_upvote_idx ON hive_votes (vote_percent) WHERE vote_percent > 0;
CREATE INDEX IF NOT EXISTS hive_votes_downvote_idx ON hive_votes (vote_percent) WHERE vote_percent < 0;

-- Copy data from hive_posts table to new table
-- RAISE NOTICE 'Copy data from hive_posts table to new table';
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
-- RAISE NOTICE 'Copy standard data to new posts table';
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
-- RAISE NOTICE 'Populate table hive_post_data with bulk data from hive_posts_cache';
INSERT INTO hive_post_data (id, title, preview, img_url, body, votes, json) SELECT post_id, title, preview, img_url, body, json FROM hive_posts_cache;

-- Populate hive_votes table
-- RAISE NOTICE 'Populate table hive_votes with bulk data from hive_posts_cache';
INSERT INTO 
    hive_votes (voter_id, author_id, permlink_id, rshares, vote_percent)
SELECT 
    (SELECT id from hive_accounts WHERE name = vote_data.regexp_split_to_array[1]) AS voter_id,
    (SELECT author_id FROM hive_posts WHERE id = vote_data.id) AS author_id,
    (SELECT permlink_id FROM hive_posts WHERE id = vote_data.id) AS permlink_id,  
    (vote_data.regexp_split_to_array[2])::bigint AS rshares,
    (vote_data.regexp_split_to_array[3])::int AS vote_percent
FROM 
    (SELECT 
        votes.id, regexp_split_to_array(votes.regexp_split_to_table::text, E',') 
     FROM 
        (SELECT id, regexp_split_to_table(votes::text, E'\n') 
         FROM hive_posts_cache WHERE votes IS NOT NULL AND votes != '') 
    AS votes) 
AS vote_data;


-- Helper type for use with json_populate_record
-- RAISE NOTICE 'Creating legacy_comment_data table';
CREATE TABLE legacy_comment_data (
  id BIGINT,
  raw_json TEXT,
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
  root_title VARCHAR(255)
);

-- RAISE NOTICE 'Creating legacy_comment_type table';
CREATE TYPE legacy_comment_type AS (
  id BIGINT,
  parent_author VARCHAR(16),
  parent_permlink VARCHAR(255),
  curator_payout_value VARCHAR(30),
  root_author VARCHAR(16),
  root_permlink VARCHAR(255),
  max_accepted_payout VARCHAR(16),
  percent_hbd INT,
  allow_replies BOOLEAN,
  allow_votes BOOLEAN,
  allow_curation_rewards BOOLEAN,
  beneficiaries JSON,
  url TEXT,
  root_title VARCHAR(255)
);

-- RAISE NOTICE 'Copying raw_json data to temporaty table';
INSERT INTO legacy_comment_data (id, raw_json) SELECT post_id, raw_json FROM hive_posts_cache;

update legacy_comment_data lcd set (parent_author, parent_permlink, 
  curator_payout_value, root_author, root_permlink, max_accepted_payout,
  percent_hbd, allow_replies, allow_votes, allow_curation_rewards,
  beneficiaries, url, root_title)
=
(SELECT parent_author, parent_permlink, 
  curator_payout_value, root_author, root_permlink, max_accepted_payout,
  percent_steem_dollars, allow_replies, allow_votes, allow_curation_rewards,
  beneficiaries, url, root_title from json_populate_record(null::legacy_comment_type, lcd.raw_json::json)
);

-- RAISE NOTICE 'Copying parent_permlink data to proper colums';
INSERT INTO hive_permlink_data (permlink) SELECT parent_permlink FROM legacy_comment_data ON CONFLICT (permlink) DO NOTHING;

-- RAISE NOTICE 'Copying root_permlink data to proper colums';
INSERT INTO hive_permlink_data (permlink) SELECT root_permlink FROM legacy_comment_data ON CONFLICT (permlink) DO NOTHING;

-- RAISE NOTICE 'Moving raw json data data to proper colums in hive_posts';
UPDATE hive_posts_new hpn SET
  parent_author_id = (SELECT id FROM hive_accounts WHERE name = lcd.parent_author),
  parent_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = lcd.parent_permlink),
  curator_payout_value = lcd.curator_payout_value,
  root_author_id = (SELECT id FROM hive_accounts WHERE name = lcd.root_author),
  root_permlink_id = (SELECT id FROM hive_permlink_data WHERE permlink = lcd.root_permlink),
  max_accepted_payout = lcd.max_accepted_payout,
  percent_hbd = lcd.percent_hbd,
  allow_replies = lcd.allow_replies,
  allow_votes = lcd.allow_votes,
  allow_curation_rewards = lcd.allow_curation_rewards,
  beneficiaries = lcd.beneficiaries,
  url = lcd.url,
  root_title = lcd.root_title
FROM (SELECT id, parent_author, parent_permlink, curator_payout_value, root_author, root_permlink,
  max_accepted_payout, percent_hbd, allow_replies, allow_votes, allow_curation_rewards,
  beneficiaries, url, root_title FROM legacy_comment_data) AS lcd
WHERE lcd.id = hpn.id;

-- Drop and rename tables after data migration
-- RAISE NOTICE 'Droping tables';
DROP TYPE IF EXISTS legacy_comment_type;
DROP TABLE IF EXISTS legacy_comment_data;
DROP TABLE IF EXISTS hive_posts_cache;
-- before deleting hive_posts we need to remove constraints
ALTER TABLE hive_payments DROP CONSTRAINT hive_payments_fk3;
ALTER TABLE hive_reblogs DROP CONSTRAINT hive_reblogs_fk2;
DROP TABLE IF EXISTS hive_posts;
-- now rename table 
-- RAISE NOTICE 'Renaming hive_posts_new to hive_posts';
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

ALTER TABLE hive_posts ADD CONSTRAINT hive_posts_fk1 FOREIGN KEY (author_id) REFERENCES hive_accounts(id);
ALTER TABLE hive_posts ADD CONSTRAINT hive_posts_fk3 FOREIGN KEY (parent_id) REFERENCES hive_posts(id);
ALTER TABLE hive_posts ADD CONSTRAINT hive_posts_fk4 FOREIGN KEY (permlink_id) REFERENCES hive_permlink_data(id);
ALTER TABLE hive_posts ADD CONSTRAINT hive_posts_ux1 UNIQUE (author_id, permlink_id);

-- Make indexes in hive_posts
-- RAISE NOTICE 'Creating indexes';

CREATE INDEX IF NOT EXISTS hive_posts_depth_idx ON hive_posts (depth);
CREATE INDEX IF NOT EXISTS hive_posts_parent_id_idx ON hive_posts (parent_id);
CREATE INDEX IF NOT EXISTS hive_posts_community_id_idx ON hive_posts (community_id);

CREATE INDEX IF NOT EXISTS hive_posts_category_id_idx ON hive_posts (category_id);
CREATE INDEX IF NOT EXISTS hive_posts_payout_at_idx ON hive_posts (payout_at);
CREATE INDEX IF NOT EXISTS hive_posts_payout_at_idx2 ON hive_posts (payout_at) WHERE is_paidout = '0';

CREATE INDEX IF NOT EXISTS hive_posts_payout_idx ON hive_posts (payout);

CREATE INDEX IF NOT EXISTS hive_posts_promoted_idx ON hive_posts (promoted);

CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_idx ON hive_posts (sc_trend);
CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_idx ON hive_posts (sc_hot);

CREATE INDEX IF NOT EXISTS hive_posts_created_at_idx ON hive_posts (created_at);

-- Create a materialized view and associated index to significantly speedup query for hive_posts
DROP MATERIALIZED VIEW IF EXISTS hive_posts_a_p;

CREATE MATERIALIZED VIEW hive_posts_a_p
AS
SELECT hp.id AS id,
       ha_a.name AS author,
       hpd_p.permlink AS permlink
FROM hive_posts hp
INNER JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
INNER JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
WITH DATA
;

DROP INDEX IF EXISTS hive_posts_a_p_idx;

CREATE unique index hive_posts_a_p_idx
ON hive_posts_a_p
(author collate "C", permlink collate "C")
;

