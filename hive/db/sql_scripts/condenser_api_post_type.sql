DROP TYPE IF EXISTS hivemind_app.condenser_api_post CASCADE;
-- type for regular condenser_api posts
CREATE TYPE hivemind_app.condenser_api_post AS (
    id INT,
    entry_id INT, -- used for paging with offset (otherwise can be any value)
    author VARCHAR(16),
    permlink VARCHAR(255),
    author_rep BIGINT,
    title VARCHAR(512),
    body TEXT,
    category VARCHAR(255),
    depth SMALLINT,
    payout DECIMAL(10,3),
    pending_payout DECIMAL(10,3),
    payout_at TIMESTAMP,
    is_paidout BOOLEAN,
    children INT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    reblogged_at TIMESTAMP, -- used when post data is combined with hivemind_app.hive_feed_cache (otherwise can be date)
    rshares NUMERIC,
    json TEXT,
    parent_author VARCHAR(16),
    parent_permlink_or_category VARCHAR(255),
    curator_payout_value VARCHAR(30),
    max_accepted_payout VARCHAR(30),
    percent_hbd INT,
    beneficiaries JSON,
    url TEXT,
    root_title VARCHAR(512)
);
