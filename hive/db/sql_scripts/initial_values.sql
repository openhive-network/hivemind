
INSERT INTO hive_blocks (num, hash, created_at) VALUES (0, '0000000000000000000000000000000000000000', '2016-03-24 16:04:57');

INSERT INTO hive_permlink_data (id, permlink) VALUES (0, '');
INSERT INTO hive_category_data (id, category) VALUES (0, '');
INSERT INTO hive_accounts (id, name, created_at) VALUES (0, '', '1970-01-01T00:00:00');

INSERT INTO hive_accounts (name, created_at) VALUES ('miners',    '2016-03-24 16:05:00');
INSERT INTO hive_accounts (name, created_at) VALUES ('null',      '2016-03-24 16:05:00');
INSERT INTO hive_accounts (name, created_at) VALUES ('temp',      '2016-03-24 16:05:00');
INSERT INTO hive_accounts (name, created_at) VALUES ('initminer', '2016-03-24 16:05:00');

INSERT INTO
    public.hive_posts(id, root_id, parent_id, author_id, permlink_id, category_id,
        community_id, created_at, depth, block_num
    )
VALUES
    (0, 0, 0, 0, 0, 0, 0, now(), 0, 0);