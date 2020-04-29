-- This script will upgrade hivemind database to new version
-- Authors: Dariusz Kędzierski
-- Created: 26-04-2020

CREATE TABLE IF NOT EXISTS hive_db_version (
  version VARCHAR(50) PRIMARY KEY,
  notes VARCHAR(1024)
);

-- Upgrade to version 1.0
-- in this version we will move data from raw_json into separate columns
DO $$
  DECLARE
    -- We will perform our operations in baches to conserve memory and CPU
      batch_size INTEGER := 100000;
      
      -- Get last id from hive_posts_cache
      last_id INTEGER := 0;

      current_id INTEGER := 0;

      row RECORD;
  BEGIN
    RAISE NOTICE 'Upgrading database to version 1.0';
    IF NOT EXISTS (SELECT version FROM hive_db_version WHERE version = '1.0')
    THEN
      -- Update version info
      INSERT INTO hive_db_version (version, notes) VALUES ('1.0', 'https://gitlab.syncad.com/blocktrades/hivemind/issues/5');
      -- Alter hive_comments_cache and add columns originally stored in raw_json
      RAISE NOTICE 'Attempting to alter table hive_posts_cache';
      ALTER TABLE hive_posts_cache 
        ADD COLUMN legacy_id INT NOT NULL DEFAULT -1,
        ADD COLUMN parent_author VARCHAR(16) NOT NULL DEFAULT '',
        ADD COLUMN parent_permlink VARCHAR(255) NOT NULL DEFAULT '',
        ADD COLUMN curator_payout_value VARCHAR(16) NOT NULL DEFAULT '',
        ADD COLUMN root_author VARCHAR(16) NOT NULL DEFAULT '',
        ADD COLUMN root_permlink VARCHAR(255) NOT NULL DEFAULT '',
        ADD COLUMN max_accepted_payout VARCHAR(16) NOT NULL DEFAULT '',
        ADD COLUMN percent_steem_dollars INT NOT NULL DEFAULT -1,
        ADD COLUMN allow_replies BOOLEAN NOT NULL DEFAULT TRUE,
        ADD COLUMN allow_votes BOOLEAN NOT NULL DEFAULT TRUE,
        ADD COLUMN allow_curation_rewards BOOLEAN NOT NULL DEFAULT TRUE,
        ADD COLUMN beneficiaries JSON NOT NULL DEFAULT '[]',
        ADD COLUMN url TEXT NOT NULL DEFAULT '',
        ADD COLUMN root_title VARCHAR(255) NOT NULL DEFAULT '';
      RAISE NOTICE 'Done...';
      
      -- Helper type for use with json_populate_record
      CREATE TYPE legacy_comment_type AS (
        id INT,
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

      SELECT INTO last_id post_id FROM hive_posts_cache ORDER BY post_id DESC LIMIT 1;

      RAISE NOTICE 'Attempting to parse % rows in batches %', last_id, batch_size;
      
      WHILE current_id < last_id LOOP
        RAISE NOTICE 'Processing batch: % <= post_id < % (of %)', current_id, current_id + batch_size, last_id;
        FOR row IN SELECT post_id, raw_json FROM hive_posts_cache WHERE post_id >= current_id AND post_id < current_id + batch_size LOOP
          UPDATE hive_posts_cache SET (
            legacy_id, parent_author, parent_permlink, curator_payout_value, 
            root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
            allow_replies, allow_votes, allow_curation_rewards, url, root_title
          ) = (
            SELECT id, parent_author, parent_permlink, curator_payout_value, 
              root_author, root_permlink, max_accepted_payout, percent_steem_dollars, 
              allow_replies, allow_votes, allow_curation_rewards, url, root_title 
            FROM json_populate_record(null::legacy_comment_type, row.raw_json::json)
          )
          WHERE post_id = row.post_id;
          current_id := row.post_id;
        END LOOP;
      END LOOP;
      RAISE NOTICE 'Done...';
      -- Creating indexes
      RAISE NOTICE 'Creating author_permlink_idx';
      CREATE INDEX IF NOT EXISTS author_permlink_idx ON hive_posts_cache (author ASC, permlink ASC);
      RAISE NOTICE 'Creating root_author_permlink_idx';
      CREATE INDEX IF NOT EXISTS root_author_permlink_idx ON hive_posts_cache (root_author ASC, root_permlink ASC);
      RAISE NOTICE 'Creating parent_permlink_idx';
      CREATE INDEX IF NOT EXISTS parent_author_permlink_idx ON hive_posts_cache (parent_author ASC, parent_permlink ASC);
      RAISE NOTICE 'Creating author_permlink_post_id_idx';
      CREATE INDEX IF NOT EXISTS author_permlink_post_id_idx ON hive_posts_cache (author ASC, permlink ASC, post_id ASC);
      RAISE NOTICE 'Creating post_id_author_permlink_idx';
      CREATE INDEX IF NOT EXISTS post_id_author_permlink_idx ON hive_posts_cache (post_id ASC, author ASC, permlink ASC);

      -- Creating functions
      -- for list_comments by_root
      CREATE OR REPLACE FUNCTION get_rows_by_root(root_a VARCHAR, root_p VARCHAR, child_a VARCHAR, child_p VARCHAR, query_limit INT DEFAULT 1000) RETURNS SETOF hive_posts_cache AS $$
      DECLARE
        root_row hive_posts_cache;
        child_row hive_posts_cache;
        query_count INT := 0;
      BEGIN
        FOR root_row IN SELECT * FROM hive_posts_cache WHERE author >= root_a AND permlink >= root_p ORDER BY post_id ASC, author ASC, permlink ASC
        LOOP
          EXIT WHEN query_count >= query_limit;
          FOR child_row IN SELECT * FROM hive_posts_cache WHERE author >= child_a AND permlink >= child_p AND root_author = root_row.root_author AND root_permlink = root_row.root_permlink ORDER BY post_id ASC, author ASC, permlink ASC
          LOOP 
            EXIT WHEN query_count >= query_limit;
            RETURN NEXT child_row;
            query_count := query_count + 1;
          END LOOP;
        END LOOP;
        RETURN;
      END
      $$ LANGUAGE plpgsql;
      -- for list_comments by_parent
      CREATE OR REPLACE FUNCTION get_rows_by_parent(parent_a VARCHAR, parent_p VARCHAR, child_a VARCHAR, child_p VARCHAR, query_limit INT DEFAULT 1000) RETURNS SETOF hive_posts_cache AS $$
      DECLARE
        child_id INT := 0;
      BEGIN
        SELECT INTO child_id post_id FROM hive_posts_cache WHERE author >= child_a AND permlink >= child_p ORDER BY post_id ASC LIMIT 1;
        RETURN QUERY SELECT * FROM hive_posts_cache WHERE parent_author = parent_a AND parent_permlink = parent_p AND post_id >= child_id ORDER BY post_id ASC, author ASC, permlink ASC LIMIT query_limit;
      END
      $$ LANGUAGE plpgsql;
    ELSE
      RAISE NOTICE 'Database already in version 1.0';
    END IF;
  END
$$;
