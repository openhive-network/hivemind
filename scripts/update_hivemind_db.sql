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
INSERT INTO hive_accounts (id, name, created_at) VALUES (0, '', '1990-01-01T00:00:00');

-- Table to hold permlink dictionary, permlink is unique
-- RAISE NOTICE 'Table to hold permlink dictionary, permlink is unique';
CREATE TABLE IF NOT EXISTS hive_permlink_data (
    id BIGSERIAL PRIMARY KEY NOT NULL,
    permlink VARCHAR(255) NOT NULL CONSTRAINT hive_permlink_data_permlink UNIQUE
);
-- Populate hive_permlink_data
-- insert special permlink, empty permlink
-- RAISE NOTICE 'insert special permlink, empty permlink';
INSERT INTO hive_permlink_data (id, permlink) VALUES (0, '');
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
INSERT INTO hive_category_data (id, category) VALUES (0, '');
-- run on category field of hive_posts_cache
-- RAISE NOTICE 'run on category field of hive_posts_cache';
INSERT INTO hive_category_data (category) SELECT category FROM hive_posts ON CONFLICT (category) DO NOTHING;
-- Create indexes
CREATE INDEX IF NOT EXISTS hive_category_data_category_idx ON hive_category_data (category ASC);

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

CREATE INDEX IF NOT EXISTS hive_posts_id_idx ON hive_posts_new (id);
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
  post_id INT NOT NULL REFERENCES hive_posts (id) ON DELETE RESTRICT,
  voter_id INT NOT NULL REFERENCES hive_accounts (id) ON DELETE RESTRICT,
  author_id INT NOT NULL REFERENCES hive_accounts (id) ON DELETE RESTRICT,
  permlink_id INT NOT NULL REFERENCES hive_permlink_data (id) ON DELETE RESTRICT,
  weight BIGINT DEFAULT '0',
  rshares BIGINT DEFAULT '0',
  vote_percent INT DEFAULT '0',
  last_update DATE DEFAULT '1970-01-01T00:00:00',
  num_changes INT DEFAULT '0'
);

ALTER TABLE hive_votes ADD CONSTRAINT hive_votes_ux1 UNIQUE (voter_id, author_id, permlink_id);
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
INSERT INTO hive_post_data (id, title, preview, img_url, body, json) SELECT post_id, title, preview, img_url, body, json FROM hive_posts_cache;

-- Populate hive_votes table
-- RAISE NOTICE 'Populate table hive_votes with bulk data from hive_posts_cache';
INSERT INTO 
    hive_votes (post_id, voter_id, author_id, permlink_id, rshares, vote_percent)
SELECT 
    (vote_data.id) AS post_id,
    (SELECT id from hive_accounts WHERE name = vote_data.regexp_split_to_array[1]) AS voter_id,
    (SELECT author_id FROM hive_posts WHERE id = vote_data.id) AS author_id,
    (SELECT permlink_id FROM hive_posts WHERE id = vote_data.id) AS permlink_id,  
    (vote_data.regexp_split_to_array[2])::bigint AS rshares,
    (vote_data.regexp_split_to_array[3])::int AS vote_percent
FROM 
    (SELECT 
        votes.id, regexp_split_to_array(votes.regexp_split_to_table::text, E',') 
     FROM 
        (SELECT hpc.id, regexp_split_to_table(hpc.votes::text, E'\n') 
         FROM hive_posts_cache hpc WHERE hpc.votes IS NOT NULL AND hpc.votes != '') 
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
  percent_steem_dollars INT,
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

-- RAISE NOTICE 'Create new table structure for tags';
CREATE TABLE hive_tag_data (
  id SERIAL PRIMARY KEY NOT NULL,
  tag VARCHAR(64) NOT NULL CONSTRAINT hive_tag_data_ux1 UNIQUE
);

CREATE TABLE hive_post_tags_new(
  post_id INT REFERENCES hive_posts (id) ON DELETE RESTRICT,
  tag_id INT REFERENCES hive_tag_data (id) ON DELETE RESTRICT,
  CONSTRAINT hive_post_tags_pk1 PRIMARY KEY (post_id, tag_id)
);

-- RAISE NOTICE 'Copy tags data to new table';
INSERT INTO 
  hive_tag_data (tag) 
  SELECT 
    tag 
  FROM 
    hive_post_tags 
ON CONFLICT (tag) DO NOTHING;

INSERT INTO 
  hive_post_tags_new (post_id, tag_id) 
  SELECT 
    hpt.post_id, htd.id 
  FROM
    hive_post_tags hpt
  INNER JOIN hive_tag_data htd ON htd.tag = hpt.tag
ON CONFLICT ON CONSTRAINT hive_post_tags_pk1 DO NOTHING;

-- RAISE NOTICE 'Drop old hive_post_tags' and rename new table to old name;
DROP TABLE IF EXISTS hive_post_tags;
ALTER TABLE hive_post_tags_new RENAME TO hive_post_tags;

-- Drop and rename tables after data migration
-- RAISE NOTICE 'Droping tables';
DROP TYPE IF EXISTS legacy_comment_type;
DROP TABLE IF EXISTS legacy_comment_data;
DROP TABLE IF EXISTS hive_posts_cache;
-- before deleting hive_posts we need to remove constraints
ALTER TABLE hive_payments DROP CONSTRAINT hive_payments_fk3;
ALTER TABLE hive_reblogs DROP CONSTRAINT hive_reblogs_fk2;
ALTER TABLE hive_post_tags DROP CONSTRAINT hive_post_tags_new_post_id_fkey;
ALTER TABLE hive_votes DROP CONSTRAINT hive_votes_post_id_fkey;
-- drop old table
DROP TABLE IF EXISTS hive_posts;
-- now rename table 
-- RAISE NOTICE 'Renaming hive_posts_new to hive_posts';
DROP INDEX IF EXISTS hive_posts_id_idx;
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

ALTER TABLE hive_post_tags ADD CONSTRAINT hive_post_tags_post_id_fkey FOREIGN KEY (post_id) REFERENCES hive_posts(id);
ALTER TABLE hive_votes ADD CONSTRAINT hive_votes_post_id_fkey FOREIGN KEY (post_id) REFERENCES hive_posts(id);

ALTER TABLE hive_follows
  ADD COLUMN blacklisted BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN follow_blacklists BOOLEAN NOT NULL DEFAULT FALSE;

-- Make indexes in hive_posts
-- RAISE NOTICE 'Creating indexes';

CREATE INDEX IF NOT EXISTS hive_posts_depth_idx ON hive_posts (depth);
CREATE INDEX IF NOT EXISTS hive_posts_parent_id_idx ON hive_posts (parent_id);
CREATE INDEX IF NOT EXISTS hive_posts_community_id_idx ON hive_posts (community_id);

CREATE INDEX IF NOT EXISTS hive_posts_category_id_idx ON hive_posts (category_id);
CREATE INDEX IF NOT EXISTS hive_posts_payout_at_idx ON hive_posts (payout_at);

CREATE INDEX IF NOT EXISTS hive_posts_payout_idx ON hive_posts (payout);

CREATE INDEX IF NOT EXISTS hive_posts_promoted_idx ON hive_posts (promoted);

CREATE INDEX IF NOT EXISTS hive_posts_sc_trend_idx ON hive_posts (sc_trend);
CREATE INDEX IF NOT EXISTS hive_posts_sc_hot_idx ON hive_posts (sc_hot);

CREATE INDEX IF NOT EXISTS hive_posts_created_at_idx ON hive_posts (created_at);

INSERT INTO 
    public.hive_posts(id, parent_id, author_id, permlink_id, category_id,
        community_id, parent_author_id, parent_permlink_id, root_author_id, 
        root_permlink_id, created_at, depth
    )
VALUES 
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, now(), 0);

CREATE INDEX IF NOT EXISTS hive_communities_ft1 ON hive_communities USING GIN (to_tsvector('english', title || ' ' || about));

DROP FUNCTION if exists process_hive_post_operation(character varying,character varying,character varying,character varying,timestamp without time zone,timestamp without time zone);
CREATE OR REPLACE FUNCTION process_hive_post_operation(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _parent_author hive_accounts.name%TYPE,
  in _parent_permlink hive_permlink_data.permlink%TYPE,
  in _date hive_posts.created_at%TYPE,
  in _community_support_start_date hive_posts.created_at%TYPE)
RETURNS TABLE (id hive_posts.id%TYPE, author_id hive_posts.author_id%TYPE, permlink_id hive_posts.permlink_id%TYPE,
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
    author_id, permlink_id, created_at)
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
      ha.id as author_id, hpd.id as permlink_id, _date as created_at
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

    --- post undelete part (if was deleted)
    is_deleted = (CASE hp.is_deleted
                    WHEN true THEN false
                    ELSE false
                  END
                  ),
    is_pinned = (CASE hp.is_deleted
                    WHEN true THEN false
                    ELSE hp.is_pinned --- no change
                  END
                  )

  RETURNING hp.id, hp.author_id, hp.permlink_id, (SELECT hcd.category FROM hive_category_data hcd WHERE hcd.id = hp.category_id) as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth, (hp.updated_at > hp.created_at) as is_edited
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
    author_id, permlink_id, created_at)
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
      ha.id as author_id, hpd.id as permlink_id, _date as created_at
  FROM hive_accounts ha,
        hive_permlink_data hpd
  WHERE ha.name = _author and hpd.permlink = _permlink 

  ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
    --- During post update it is disallowed to change: parent-post, category, community-id
    --- then also depth, is_valid and is_muted is impossible to change
    --- post edit part 
    updated_at = _date,

    --- post undelete part (if was deleted)
    is_deleted = (CASE hp.is_deleted
                    WHEN true THEN false
                    ELSE false
                  END
                  ),
    is_pinned = (CASE hp.is_deleted
                    WHEN true THEN false
                    ELSE hp.is_pinned --- no change
                  END
                  )

  RETURNING hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth, (hp.updated_at > hp.created_at) as is_edited
  ;
END IF;
END
$function$;

DROP FUNCTION if exists delete_hive_post(character varying,character varying,character varying);
CREATE OR REPLACE FUNCTION delete_hive_post(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE)
RETURNS TABLE (id hive_posts.id%TYPE, depth hive_posts.depth%TYPE)
LANGUAGE plpgsql
AS
$function$
BEGIN
  RETURN QUERY UPDATE hive_posts AS hp
    SET is_deleted = false
  FROM hive_posts hp1
  INNER JOIN hive_accounts ha ON hp1.author_id = ha.id
  INNER JOIN hive_permlink_data hpd ON hp1.permlink_id = hpd.id
  WHERE hp.id = hp1.id AND ha.name = _author AND hpd.permlink = _permlink
  RETURNING hp.id, hp.depth;
END
$function$;

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

-- drop old not needed indexes and introduce new
DROP INDEX IF EXISTS hive_accounts_ix1;
CREATE INDEX IF NOT EXISTS hive_accounts_ix1 ON hive_accounts (vote_weight);
DROP INDEX IF EXISTS hive_accounts_ix2;
DROP INDEX IF EXISTS hive_accounts_ix3;
DROP INDEX IF EXISTS hive_accounts_ix4;
DROP INDEX IF EXISTS hive_accounts_ix5;
CREATE INDEX IF NOT EXISTS hive_accounts_ix5 ON hive_accounts (cached_at);
DROP INDEX IF EXISTS hive_accounts_name_idx;

CREATE INDEX IF NOT EXISTS hive_votes_post_id_idx ON hive_votes (post_id);

-- convert unique index to primary key
ALTER TABLE hive_follows DROP CONSTRAINT hive_follows_ux3;
ALTER TABLE hive_follows ADD CONSTRAINT hive_follows_pk PRIMARY KEY (following, follower);

-- convert unique index to primary key
ALTER TABLE hive_reblogs DROP CONSTRAINT hive_reblogs_ux1;
ALTER TABLE hive_reblogs ADD CONSTRAINT hive_reblogs_pk PRIMARY KEY (account, post_id);

DROP INDEX IF EXISTS hive_reblogs_ix1;
CREATE INDEX IF NOT EXISTS hive_reblogs_account_idx ON hive_reblogs (account);
CREATE INDEX IF NOT EXISTS hive_reblogs_post_id_idx ON hive_reblogs (post_id);

CREATE INDEX IF NOT EXISTS hive_payments_from_idx ON hive_payments (from_account);
CREATE INDEX IF NOT EXISTS hive_payments_post_id_idx ON hive_payments (post_id);
CREATE INDEX IF NOT EXISTS hive_payments_to_idx ON hive_payments (to_account);

-- convert unique index to primary key
ALTER TABLE hive_feed_cache DROP CONSTRAINT hive_feed_cache_ux1;
ALTER TABLE hive_feed_cache ADD CONSTRAINT hive_feed_cache_pk PRIMARY KEY (post_id, account_id);
DROP INDEX IF EXISTS hive_feed_cache_ix1;
CREATE INDEX IF NOT EXISTS hive_feed_cache_account_id ON hive_feed_cache (account_id);

-- delete content of hive_feed_cache to force initial sync
DELETE FROM hive_feed_cache WHERE post_id >= 1;

-- force vacuum after changes
-- will take a while
VACUUM FULL;

