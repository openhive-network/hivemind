-- :mode is LOGGED or UNLOGGED (table persistence during the run)
DROP TABLE IF EXISTS hive_votes, hive_posts, hive_post_data, hive_permlink_data;
CREATE :mode TABLE hive_posts (
    id SERIAL PRIMARY KEY, root_id INTEGER NOT NULL, parent_id INTEGER NOT NULL, author_id INTEGER NOT NULL,
    permlink_id INTEGER NOT NULL, category_id INTEGER NOT NULL, community_id INTEGER, created_at TIMESTAMP NOT NULL,
    depth SMALLINT NOT NULL, counter_deleted INTEGER NOT NULL DEFAULT 0, is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    is_muted BOOLEAN NOT NULL DEFAULT FALSE, muted_reasons INTEGER NOT NULL DEFAULT 0, is_valid BOOLEAN NOT NULL DEFAULT TRUE,
    children INTEGER NOT NULL DEFAULT 0, payout DECIMAL(10,3) NOT NULL DEFAULT 0, pending_payout DECIMAL(10,3) NOT NULL DEFAULT 0,
    payout_at TIMESTAMP NOT NULL DEFAULT '1970-01-01', last_payout_at TIMESTAMP NOT NULL DEFAULT '1970-01-01',
    updated_at TIMESTAMP NOT NULL DEFAULT '1970-01-01', is_paidout BOOLEAN NOT NULL DEFAULT FALSE, is_nsfw BOOLEAN NOT NULL DEFAULT FALSE,
    is_declined BOOLEAN NOT NULL DEFAULT FALSE, is_full_power BOOLEAN NOT NULL DEFAULT FALSE, is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    sc_trend REAL NOT NULL DEFAULT 0, sc_hot REAL NOT NULL DEFAULT 0, total_payout_value VARCHAR(30) NOT NULL DEFAULT '0.000 HBD',
    author_rewards BIGINT NOT NULL DEFAULT 0, author_rewards_hive BIGINT NOT NULL DEFAULT 0, author_rewards_hbd BIGINT NOT NULL DEFAULT 0,
    author_rewards_vests BIGINT NOT NULL DEFAULT 0, abs_rshares NUMERIC NOT NULL DEFAULT 0, vote_rshares NUMERIC NOT NULL DEFAULT 0,
    total_vote_weight NUMERIC NOT NULL DEFAULT 0, total_votes BIGINT NOT NULL DEFAULT 0, net_votes BIGINT NOT NULL DEFAULT 0,
    active TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00', cashout_time TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00',
    percent_hbd INTEGER NOT NULL DEFAULT 10000, curator_payout_value VARCHAR(30) NOT NULL DEFAULT '0.000 HBD',
    max_accepted_payout VARCHAR(30) NOT NULL DEFAULT '1000000.000 HBD', allow_votes BOOLEAN NOT NULL DEFAULT TRUE,
    allow_curation_rewards BOOLEAN NOT NULL DEFAULT TRUE, beneficiaries JSON NOT NULL DEFAULT '[]',
    block_num INTEGER NOT NULL, block_num_created INTEGER NOT NULL, last_payout_block INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT hive_posts_ux1 UNIQUE (author_id, permlink_id, counter_deleted));
CREATE :mode TABLE hive_post_data (id INTEGER PRIMARY KEY, title VARCHAR(512) NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '', json TEXT NOT NULL DEFAULT '');
CREATE :mode TABLE hive_permlink_data (id SERIAL PRIMARY KEY, permlink VARCHAR(255) COLLATE "C" NOT NULL, CONSTRAINT hive_permlink_data_permlink UNIQUE (permlink));
CREATE :mode TABLE hive_votes (
    id BIGSERIAL PRIMARY KEY, post_id INTEGER NOT NULL, voter_id INTEGER NOT NULL, author_id INTEGER NOT NULL,
    permlink_id INTEGER NOT NULL, weight NUMERIC NOT NULL DEFAULT 0, rshares BIGINT NOT NULL DEFAULT 0,
    vote_percent INTEGER NOT NULL DEFAULT 0, last_update TIMESTAMP NOT NULL DEFAULT '1970-01-01 00:00:00',
    num_changes INTEGER NOT NULL DEFAULT 0, block_num INTEGER NOT NULL, is_effective BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk UNIQUE (voter_id, author_id, permlink_id));
ALTER TABLE hive_post_data SET (autovacuum_enabled = false);

-- One votes worker: per batch, upserts its share of the batch's votes on recent posts.
CREATE OR REPLACE PROCEDURE votes_worker(_w INT, _parts INT, _batches INT, _per_batch INT) AS $$
BEGIN
  FOR b IN 1.._batches LOOP
    INSERT INTO hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num, is_effective)
    SELECT p, (random()*2600000)::int, (random()*2600000)::int, p, (random()*1e12)::numeric(20,0), (random()*1e10)::bigint,
           10000, now(), 0, b*1000 + (g % 1000), true
    FROM (SELECT g, ((b*2800 + floor(random()*2800)::int) * _parts + _w) AS p FROM generate_series(1, _per_batch) g) s
    ON CONFLICT ON CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk DO UPDATE SET
      weight = EXCLUDED.weight, rshares = EXCLUDED.rshares, last_update = EXCLUDED.last_update,
      num_changes = hive_votes.num_changes + 1, block_num = GREATEST(EXCLUDED.block_num, hive_votes.block_num);
    COMMIT;
  END LOOP;
END $$ LANGUAGE plpgsql;

-- The posts worker: per batch, inserts permlinks, posts and post bodies, then updates recent posts.
CREATE OR REPLACE PROCEDURE posts_worker(_batches INT, _posts INT, _updates INT) AS $$
DECLARE _max INT;
BEGIN
  FOR b IN 1.._batches LOOP
    INSERT INTO hive_permlink_data (permlink)
      SELECT 'p-' || b || '-' || g || '-' || md5(g::text) FROM generate_series(1, _posts) g;
    INSERT INTO hive_posts (root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, beneficiaries)
      SELECT 0, 0, (random()*2600000)::int, b*_posts + g, (random()*500000)::int, now(), (random()*3)::int, b*1000, b*1000, '[]'
      FROM generate_series(1, _posts) g;
    SELECT max(id) INTO _max FROM hive_posts;
    INSERT INTO hive_post_data (id, title, body, json)
      SELECT _max - _posts + g, left(md5(g::text), 20), repeat(md5(random()::text), 1 + (random()*36)::int), '{"tags":["hive","x"],"app":"peakd/2024"}'
      FROM generate_series(1, _posts) g;
    UPDATE hive_posts SET children = children + 1, active = now(), updated_at = now(), pending_payout = pending_payout + 0.001
      WHERE id IN (SELECT greatest(1, _max - (random()*500000)::int) FROM generate_series(1, _updates));
    COMMIT;
  END LOOP;
END $$ LANGUAGE plpgsql;
