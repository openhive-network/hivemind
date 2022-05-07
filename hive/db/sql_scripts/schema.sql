DROP SCHEMA IF EXISTS hivemind_app CASCADE;

CREATE SCHEMA IF NOT EXISTS hivemind_app;

CREATE OR REPLACE PROCEDURE hivemind_app.define_schema()
    LANGUAGE 'plpgsql'
AS
$$
BEGIN
    RAISE NOTICE 'Attempting to create an application schema tables...';

    -- >> hive_blocks -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE IF NOT EXISTS hivemind_app.hive_blocks
    (
        num        integer                        NOT NULL PRIMARY KEY,
        hash       character(40)                  NOT NULL UNIQUE,
        prev       character(40) REFERENCES hivemind_app.hive_blocks (hash),
        txs        smallint DEFAULT '0'::smallint NOT NULL,
        ops        integer  DEFAULT 0             NOT NULL,
        created_at timestamp without time zone    NOT NULL,
        completed  boolean  DEFAULT false         NOT NULL
    ) INHERITS (hive.hivemind_app);

    -- << hive_blocks -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_accounts -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE IF NOT EXISTS hivemind_app.hive_accounts
    (
        id                    integer                                                                                NOT NULL PRIMARY KEY,
        name                  character varying(16)                                                                  NOT NULL UNIQUE COLLATE pg_catalog."C",
        created_at            timestamp without time zone                                                            NOT NULL,
        reputation            bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        is_implicit           boolean                     DEFAULT true                                               NOT NULL,
        followers             integer                     DEFAULT 0                                                  NOT NULL,
        following             integer                     DEFAULT 0                                                  NOT NULL,
        rank                  integer                     DEFAULT 0                                                  NOT NULL,
        lastread_at           timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        posting_json_metadata text,
        json_metadata         text
    ) INHERITS (hive.hivemind_app);

    -- << hive_accounts -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_reputation_data -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_reputation_data
    (
        id        integer                NOT NULL PRIMARY KEY,
        author_id integer                NOT NULL,
        voter_id  integer                NOT NULL,
        permlink  character varying(255) NOT NULL COLLATE pg_catalog."C",
        rshares   bigint                 NOT NULL,
        block_num integer                NOT NULL
    ) INHERITS (hive.hivemind_app);

    -- << hive_reputation_data -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_posts -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_posts
    (
        id                     integer                                                                                NOT NULL PRIMARY KEY,
        root_id                integer                                                                                NOT NULL REFERENCES hivemind_app.hive_posts (id), -- records having initially set 0 will be updated to their id
        parent_id              integer                                                                                NOT NULL REFERENCES hivemind_app.hive_posts (id),
        author_id              integer                                                                                NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        permlink_id            integer                                                                                NOT NULL,
        category_id            integer                                                                                NOT NULL,
        community_id           integer,
        created_at             timestamp without time zone                                                            NOT NULL,
        depth                  smallint                                                                               NOT NULL,
        counter_deleted        integer                     DEFAULT 0                                                  NOT NULL,
        is_pinned              boolean                     DEFAULT false                                              NOT NULL,
        is_muted               boolean                     DEFAULT false                                              NOT NULL,
        is_valid               boolean                     DEFAULT true                                               NOT NULL,
        promoted               numeric(10, 3)              DEFAULT '0'::numeric                                       NOT NULL,
        children               integer                     DEFAULT 0                                                  NOT NULL,
        -- core stats/indexes
        payout                 numeric(10, 3)              DEFAULT '0'::numeric                                       NOT NULL,
        pending_payout         numeric(10, 3)              DEFAULT '0'::numeric                                       NOT NULL,
        payout_at              timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        last_payout_at         timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        updated_at             timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        is_paidout             boolean                     DEFAULT false                                              NOT NULL,
        -- ui flags/filters
        is_nsfw                boolean                     DEFAULT false                                              NOT NULL,
        is_declined            boolean                     DEFAULT false                                              NOT NULL,
        is_full_power          boolean                     DEFAULT false                                              NOT NULL,
        is_hidden              boolean                     DEFAULT false                                              NOT NULL,
        -- important indexes
        sc_trend               real                        DEFAULT '0'::real                                          NOT NULL,
        sc_hot                 real                        DEFAULT '0'::real                                          NOT NULL,
        total_payout_value     character varying(30)       DEFAULT '0.000 HBD'::character varying                     NOT NULL,
        author_rewards         bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        author_rewards_hive    bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        author_rewards_hbd     bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        author_rewards_vests   bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        abs_rshares            numeric                     DEFAULT '0'::numeric                                       NOT NULL,
        vote_rshares           numeric                     DEFAULT '0'::numeric                                       NOT NULL,
        total_vote_weight      numeric                     DEFAULT '0'::numeric                                       NOT NULL,
        total_votes            bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        net_votes              bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        active                 timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        cashout_time           timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        percent_hbd            integer                     DEFAULT 10000                                              NOT NULL,
        curator_payout_value   character varying(30)       DEFAULT '0.000 HBD'::character varying                     NOT NULL,
        max_accepted_payout    character varying(30)       DEFAULT '1000000.000 HBD'::character varying               NOT NULL,
        allow_votes            boolean                     DEFAULT true                                               NOT NULL,
        allow_curation_rewards boolean                     DEFAULT true                                               NOT NULL,
        beneficiaries          json                        DEFAULT '[]'::json                                         NOT NULL,
        block_num              integer                                                                                NOT NULL,
        block_num_created      integer                                                                                NOT NULL,
        tags_ids               integer[]
    ) INHERITS (hive.hivemind_app);

    ALTER TABLE ONLY hivemind_app.hive_posts
        ADD CONSTRAINT hive_posts_ux1 UNIQUE (author_id, permlink_id, counter_deleted);

    -- << hive_posts -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_post_data -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_post_data
    (
        id      integer                                               NOT NULL PRIMARY KEY,
        title   character varying(512)  DEFAULT ''::character varying NOT NULL,
        preview character varying(1024) DEFAULT ''::character varying NOT NULL, -- first 1k of 'body'
        img_url character varying(1024) DEFAULT ''::character varying NOT NULL, -- first 'image' from 'json'
        body    text                    DEFAULT ''::text              NOT NULL,
        json    text                    DEFAULT ''::text              NOT NULL
    ) INHERITS (hive.hivemind_app);

    -- << hive_post_data -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_permlink_data -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_permlink_data
    (
        id       integer                NOT NULL PRIMARY KEY,
        permlink character varying(255) NOT NULL UNIQUE COLLATE pg_catalog."C"
    ) INHERITS (hive.hivemind_app);

    -- << hive_permlink_data -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_category_data -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_category_data
    (
        id       integer                NOT NULL PRIMARY KEY,
        category character varying(255) NOT NULL UNIQUE COLLATE pg_catalog."C"
    ) INHERITS (hive.hivemind_app);

    -- << hive_category_data -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_votes -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_votes
    (
        id           bigint                                                                                 NOT NULL PRIMARY KEY,
        post_id      integer                                                                                NOT NULL REFERENCES hivemind_app.hive_posts (id),
        voter_id     integer                                                                                NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        author_id    integer                                                                                NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        permlink_id  integer                                                                                NOT NULL REFERENCES hivemind_app.hive_permlink_data (id),
        weight       numeric                     DEFAULT '0'::numeric                                       NOT NULL,
        rshares      bigint                      DEFAULT '0'::bigint                                        NOT NULL,
        vote_percent integer                     DEFAULT 0,
        last_update  timestamp without time zone DEFAULT '1970-01-01 00:00:00'::timestamp without time zone NOT NULL,
        num_changes  integer                     DEFAULT 0,
        block_num    integer                                                                                NOT NULL REFERENCES hivemind_app.hive_blocks (num),
        is_effective boolean                     DEFAULT false                                              NOT NULL
    ) INHERITS (hive.hivemind_app);

    ALTER TABLE ONLY hivemind_app.hive_votes
        ADD CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk UNIQUE (voter_id, author_id, permlink_id);

    -- << hive_votes -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_tag_data -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_tag_data
    (
        id  integer                                             NOT NULL PRIMARY KEY,
        tag character varying(64) DEFAULT ''::character varying NOT NULL UNIQUE COLLATE pg_catalog."C"
    ) INHERITS (hive.hivemind_app);

    -- << hive_tag_data -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_follows -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_follows
    (
        id                integer                        NOT NULL PRIMARY KEY,
        follower          integer                        NOT NULL,
        following         integer                        NOT NULL,
        state             smallint DEFAULT '1'::smallint NOT NULL,
        created_at        timestamp without time zone    NOT NULL,
        blacklisted       boolean  DEFAULT false         NOT NULL,
        follow_blacklists boolean  DEFAULT false         NOT NULL,
        follow_muted      boolean  DEFAULT false         NOT NULL,
        block_num         integer                        NOT NULL REFERENCES hivemind_app.hive_blocks (num)
    ) INHERITS (hive.hivemind_app);

    ALTER TABLE ONLY hivemind_app.hive_follows
        ADD CONSTRAINT hive_follows_ux1 UNIQUE (following, follower);

    -- << hive_follows -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_reblogs -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_reblogs
    (
        id         integer                     NOT NULL PRIMARY KEY,
        blogger_id integer                     NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        post_id    integer                     NOT NULL REFERENCES hivemind_app.hive_posts (id),
        created_at timestamp without time zone NOT NULL,
        block_num  integer                     NOT NULL REFERENCES hivemind_app.hive_blocks (num)
    ) INHERITS (hive.hivemind_app);

    ALTER TABLE ONLY hivemind_app.hive_reblogs
        ADD CONSTRAINT hive_reblogs_ux1 UNIQUE (blogger_id, post_id);

    -- << hive_reblogs -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_payments -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_payments
    (
        id           integer              NOT NULL PRIMARY KEY,
        block_num    integer              NOT NULL,
        tx_idx       smallint             NOT NULL,
        post_id      integer              NOT NULL REFERENCES hivemind_app.hive_posts (id),
        from_account integer              NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        to_account   integer              NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        amount       numeric(10, 3)       NOT NULL,
        token        character varying(5) NOT NULL
    ) INHERITS (hive.hivemind_app);

    -- << hive_payments -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_feed_cache -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_feed_cache
    (
        post_id    integer                     NOT NULL,
        account_id integer                     NOT NULL,
        created_at timestamp without time zone NOT NULL,
        block_num  integer                     NOT NULL REFERENCES hivemind_app.hive_blocks (num),
        PRIMARY KEY (post_id, account_id)
    ) INHERITS (hive.hivemind_app);

    -- << hive_feed_cache -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_state -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_state
    (
        block_num  integer NOT NULL PRIMARY KEY,
        db_version integer NOT NULL
    ) INHERITS (hive.hivemind_app);

    -- << hive_state -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_posts_api_helper -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_posts_api_helper
    (
        id                integer                NOT NULL PRIMARY KEY,
        author_s_permlink character varying(275) NOT NULL COLLATE pg_catalog."C" -- concatenation of author '/' permlink
    ) INHERITS (hive.hivemind_app);

    -- << hive_posts_api_helper -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_mentions -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_mentions
    (
        id         integer NOT NULL PRIMARY KEY,
        post_id    integer NOT NULL REFERENCES hivemind_app.hive_posts (id),
        account_id integer NOT NULL REFERENCES hivemind_app.hive_accounts (id),
        block_num  integer NOT NULL
    ) INHERITS (hive.hivemind_app);

    ALTER TABLE ONLY hivemind_app.hive_mentions
        ADD CONSTRAINT hive_mentions_ux1 UNIQUE (post_id, account_id, block_num);

    -- << hive_mentions -----------------------------------------------------------------------------------------------------------------------------------------------


    -- ############################################################# COMMUNITY #############################################################


    -- >> hive_communities -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_communities
    (
        id          integer                                               NOT NULL PRIMARY KEY,
        type_id     smallint                                              NOT NULL,
        lang        character(2)            DEFAULT 'en'::bpchar          NOT NULL,
        name        character varying(16)                                 NOT NULL UNIQUE COLLATE pg_catalog."C",
        title       character varying(32)   DEFAULT ''::character varying NOT NULL,
        created_at  timestamp without time zone                           NOT NULL,
        sum_pending integer                 DEFAULT 0                     NOT NULL,
        num_pending integer                 DEFAULT 0                     NOT NULL,
        num_authors integer                 DEFAULT 0                     NOT NULL,
        rank        integer                 DEFAULT 0                     NOT NULL,
        subscribers integer                 DEFAULT 0                     NOT NULL,
        is_nsfw     boolean                 DEFAULT false                 NOT NULL,
        about       character varying(120)  DEFAULT ''::character varying NOT NULL,
        primary_tag character varying(32)   DEFAULT ''::character varying NOT NULL,
        category    character varying(32)   DEFAULT ''::character varying NOT NULL,
        avatar_url  character varying(1024) DEFAULT ''::character varying NOT NULL,
        description character varying(5000) DEFAULT ''::character varying NOT NULL,
        flag_text   character varying(5000) DEFAULT ''::character varying NOT NULL,
        settings    text                    DEFAULT '{}'::text            NOT NULL,
        block_num   integer                                               NOT NULL
    ) INHERITS (hive.hivemind_app);

    -- << hive_communities -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_roles -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_roles
    (
        account_id   integer                                              NOT NULL,
        community_id integer                                              NOT NULL,
        created_at   timestamp without time zone                          NOT NULL,
        role_id      smallint               DEFAULT '0'::smallint         NOT NULL,
        title        character varying(140) DEFAULT ''::character varying NOT NULL
    ) INHERITS (hive.hivemind_app);

    ALTER TABLE ONLY hivemind_app.hive_roles
        ADD CONSTRAINT hive_roles_pk PRIMARY KEY (account_id, community_id);

    -- << hive_roles -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_subscriptions -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_subscriptions
    (
        id           integer                     NOT NULL PRIMARY KEY,
        account_id   integer                     NOT NULL,
        community_id integer                     NOT NULL,
        created_at   timestamp without time zone NOT NULL,
        block_num    integer                     NOT NULL,
        UNIQUE (account_id, community_id)
    ) INHERITS (hive.hivemind_app);

    -- << hive_subscriptions -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_notifs -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_notifs
    (
        id           integer                     NOT NULL PRIMARY KEY,
        block_num    integer                     NOT NULL,
        type_id      smallint                    NOT NULL,
        score        smallint                    NOT NULL,
        created_at   timestamp without time zone NOT NULL,
        src_id       integer,
        dst_id       integer,
        post_id      integer,
        community_id integer,
        payload      text
    ) INHERITS (hive.hivemind_app);

    -- << hive_notifs -----------------------------------------------------------------------------------------------------------------------------------------------


    -- >> hive_notification_cache -----------------------------------------------------------------------------------------------------------------------------------------------

    CREATE TABLE hivemind_app.hive_notification_cache
    (
        id              bigint                      NOT NULL PRIMARY KEY,
        block_num       integer                     NOT NULL,
        type_id         integer                     NOT NULL,
        dst             integer,                              -- dst account id except persistent notifs from hive_notifs
        src             integer,                              -- src account id
        dst_post_id     integer,                              -- destination post id
        post_id         integer,
        created_at      timestamp without time zone NOT NULL, -- notification creation time
        score           integer                     NOT NULL,
        community_title character varying(32),
        community       character varying(16),
        payload         character varying
    ) INHERITS (hive.hivemind_app);

    -- << hive_notification_cache -----------------------------------------------------------------------------------------------------------------------------------------------

END
$$
;

CREATE OR REPLACE PROCEDURE hivemind_app.create_indexes()
    LANGUAGE 'plpgsql'
AS
$$
BEGIN
    RAISE NOTICE 'Attempting to create an application schema indexes...';

    ASSERT EXISTS (SELECT * FROM pg_extension WHERE extname='intarray'), 'The database requires created "intarray" extension';

    -- hive_blocks
    CREATE INDEX hive_blocks_created_at_idx ON hivemind_app.hive_blocks (created_at);
    CREATE INDEX hive_blocks_completed_idx ON hivemind_app.hive_blocks (completed);

    -- hive_accounts
    CREATE INDEX hive_accounts_reputation_id_idx ON hivemind_app.hive_accounts (reputation DESC, id);

    -- hive_reputation_data
    CREATE INDEX hive_reputation_data_author_permlink_voter_idx ON hivemind_app.hive_reputation_data (author_id, permlink, voter_id);
    CREATE INDEX hive_reputation_data_block_num_idx ON hivemind_app.hive_reputation_data (block_num);

    -- hive_posts
    CREATE INDEX hive_posts_depth_idx ON hivemind_app.hive_posts (depth);
    CREATE INDEX hive_posts_root_id_id_idx ON hivemind_app.hive_posts (root_id, id);
    CREATE INDEX hive_posts_parent_id_id_idx ON hivemind_app.hive_posts (parent_id, id DESC) WHERE (counter_deleted = 0);
    CREATE INDEX hive_posts_community_id_id_idx ON hivemind_app.hive_posts (community_id, id DESC);
    CREATE INDEX hive_posts_payout_at_idx ON hivemind_app.hive_posts (payout_at);
    CREATE INDEX hive_posts_payout_idx ON hivemind_app.hive_posts (payout);
    CREATE INDEX hive_posts_promoted_id_idx ON hivemind_app.hive_posts (promoted, id) WHERE ((NOT is_paidout) AND (counter_deleted = 0));
    CREATE INDEX hive_posts_sc_trend_id_idx ON hivemind_app.hive_posts (sc_trend, id) WHERE ((NOT is_paidout) AND (counter_deleted = 0) AND (depth = 0));
    CREATE INDEX hive_posts_sc_hot_id_idx ON hivemind_app.hive_posts (sc_hot, id) WHERE ((NOT is_paidout) AND (counter_deleted = 0) AND (depth = 0));
    CREATE INDEX hive_posts_author_id_created_at_id_idx ON hivemind_app.hive_posts (author_id DESC, created_at DESC, id);
    CREATE INDEX hive_posts_author_id_id_idx ON hivemind_app.hive_posts (author_id, id) WHERE (depth = 0);
    CREATE INDEX hive_posts_block_num_idx ON hivemind_app.hive_posts (block_num);
    CREATE INDEX hive_posts_block_num_created_idx ON hivemind_app.hive_posts (block_num_created);
    CREATE INDEX hive_posts_cashout_time_id_idx ON hivemind_app.hive_posts (cashout_time, id);
    CREATE INDEX hive_posts_updated_at_idx ON hivemind_app.hive_posts (updated_at DESC);
    CREATE INDEX hive_posts_payout_plus_pending_payout_id_idx ON hivemind_app.hive_posts (((payout + pending_payout)), id) WHERE ((NOT is_paidout) AND (counter_deleted = 0));
    CREATE INDEX hive_posts_category_id_payout_plus_pending_payout_depth_idx ON hivemind_app.hive_posts (category_id, ((payout + pending_payout)), depth) WHERE ((NOT is_paidout) AND (counter_deleted = 0));
    CREATE INDEX hive_posts_tags_ids_idx ON hivemind_app.hive_posts USING gin (tags_ids public.gin__int_ops);

    -- hive_votes
    CREATE INDEX hive_votes_voter_id_post_id_idx ON hivemind_app.hive_votes (voter_id, post_id); -- probably this index is redundant to hive_votes_voter_id_last_update_idx because of starting voter_id.
    CREATE INDEX hive_votes_voter_id_last_update_idx ON hivemind_app.hive_votes (voter_id, last_update); -- this index is critical for hive_accounts_info_view performance
    CREATE INDEX hive_votes_post_id_voter_id_idx ON hivemind_app.hive_votes (post_id, voter_id);
    CREATE INDEX hive_votes_block_num_idx ON hivemind_app.hive_votes (block_num); -- this is also important for hive_accounts_info_view
    CREATE INDEX hive_votes_post_id_block_num_rshares_vote_is_effective_idx ON hivemind_app.hive_votes (post_id, block_num, rshares, is_effective); -- this index is needed by update_posts_rshares procedure

    -- hive_follows
    CREATE INDEX hive_follows_ix5a ON hivemind_app.hive_follows (following, state, created_at, follower);
    CREATE INDEX hive_follows_ix5b ON hivemind_app.hive_follows (follower, state, created_at, following);
    CREATE INDEX hive_follows_block_num_idx ON hivemind_app.hive_follows (block_num);
    CREATE INDEX hive_follows_created_at_idx ON hivemind_app.hive_follows (created_at);

    -- hive_reblogs
    CREATE INDEX hive_reblogs_post_id ON hivemind_app.hive_reblogs (post_id);
    CREATE INDEX hive_reblogs_block_num_idx ON hivemind_app.hive_reblogs (block_num);
    CREATE INDEX hive_reblogs_created_at_idx ON hivemind_app.hive_reblogs (created_at);

    -- hive_payments
    CREATE INDEX hive_payments_from ON hivemind_app.hive_payments (from_account);
    CREATE INDEX hive_payments_to ON hivemind_app.hive_payments (to_account);
    CREATE INDEX hive_payments_post_id ON hivemind_app.hive_payments (post_id);

    -- hive_feed_cache
    CREATE INDEX hive_feed_cache_block_num_idx ON hivemind_app.hive_feed_cache (block_num);
    CREATE INDEX hive_feed_cache_created_at_idx ON hivemind_app.hive_feed_cache (created_at);
    CREATE INDEX hive_feed_cache_post_id_idx ON hivemind_app.hive_feed_cache (post_id);

    -- hive_posts_api_helper
    CREATE INDEX hive_posts_api_helper_author_s_permlink_idx ON hivemind_app.hive_posts_api_helper (author_s_permlink);

    -- hive_mentions
    CREATE INDEX hive_mentions_account_id_idx ON hivemind_app.hive_mentions (account_id);


    -- ############################################################# COMMUNITY #############################################################


    -- hive_communities
    CREATE INDEX hive_communities_ix1 ON hivemind_app.hive_communities (rank, id);
    CREATE INDEX hive_communities_block_num_idx ON hivemind_app.hive_communities (block_num);

    -- hive_roles
    CREATE INDEX hive_roles_ix1 ON hivemind_app.hive_roles (community_id, account_id, role_id);

    -- hive_subscriptions
    CREATE INDEX hive_subscriptions_community_idx ON hivemind_app.hive_subscriptions (community_id);
    CREATE INDEX hive_subscriptions_block_num_idx ON hivemind_app.hive_subscriptions (block_num);

    -- hive_notifs
    CREATE INDEX hive_notifs_ix1 ON hivemind_app.hive_notifs (dst_id, id) WHERE (dst_id IS NOT NULL);
    CREATE INDEX hive_notifs_ix2 ON hivemind_app.hive_notifs (community_id, id) WHERE (community_id IS NOT NULL);
    CREATE INDEX hive_notifs_ix3 ON hivemind_app.hive_notifs (community_id, type_id, id) WHERE (community_id IS NOT NULL);
    CREATE INDEX hive_notifs_ix4 ON hivemind_app.hive_notifs (community_id, post_id, type_id, id) WHERE ((community_id IS NOT NULL) AND (post_id IS NOT NULL));
    CREATE INDEX hive_notifs_ix5 ON hivemind_app.hive_notifs (post_id, type_id, dst_id, src_id) WHERE ((post_id IS NOT NULL) AND (type_id = ANY (ARRAY [16, 17]))); -- filter: dedupe
    CREATE INDEX hive_notifs_ix6 ON hivemind_app.hive_notifs (dst_id, created_at, score, id) WHERE (dst_id IS NOT NULL); -- unread

    -- hive_notification_cache
    CREATE INDEX hive_notification_cache_block_num_idx ON hivemind_app.hive_notification_cache (block_num);
    CREATE INDEX hive_notification_cache_dst_score_idx ON hivemind_app.hive_notification_cache (dst, score) WHERE (dst IS NOT NULL);

END
$$
;

