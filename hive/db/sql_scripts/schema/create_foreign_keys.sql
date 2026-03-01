-- Foreign key constraints for Hivemind tables.
-- All FKs are DEFERRABLE and NOT VALID (skip validation on creation for speed).

-- hive_posts FKs
ALTER TABLE hivemind_app.hive_posts ADD CONSTRAINT hive_posts_fk1
    FOREIGN KEY (author_id) REFERENCES hivemind_app.hive_accounts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_posts ADD CONSTRAINT hive_posts_fk2
    FOREIGN KEY (root_id) REFERENCES hivemind_app.hive_posts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_posts ADD CONSTRAINT hive_posts_fk3
    FOREIGN KEY (parent_id) REFERENCES hivemind_app.hive_posts (id) DEFERRABLE NOT VALID;

-- hive_votes FKs
ALTER TABLE hivemind_app.hive_votes ADD CONSTRAINT hive_votes_fk1
    FOREIGN KEY (post_id) REFERENCES hivemind_app.hive_posts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_votes ADD CONSTRAINT hive_votes_fk2
    FOREIGN KEY (voter_id) REFERENCES hivemind_app.hive_accounts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_votes ADD CONSTRAINT hive_votes_fk3
    FOREIGN KEY (author_id) REFERENCES hivemind_app.hive_accounts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_votes ADD CONSTRAINT hive_votes_fk4
    FOREIGN KEY (permlink_id) REFERENCES hivemind_app.hive_permlink_data (id) DEFERRABLE NOT VALID;

-- hive_post_tags FKs
ALTER TABLE hivemind_app.hive_post_tags ADD CONSTRAINT hive_post_tags_fk1
    FOREIGN KEY (post_id) REFERENCES hivemind_app.hive_posts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_post_tags ADD CONSTRAINT hive_post_tags_fk2
    FOREIGN KEY (tag_id) REFERENCES hivemind_app.hive_tag_data (id) DEFERRABLE NOT VALID;

-- hive_reblogs FKs
ALTER TABLE hivemind_app.hive_reblogs ADD CONSTRAINT hive_reblogs_fk1
    FOREIGN KEY (blogger_id) REFERENCES hivemind_app.hive_accounts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_reblogs ADD CONSTRAINT hive_reblogs_fk2
    FOREIGN KEY (post_id) REFERENCES hivemind_app.hive_posts (id) DEFERRABLE NOT VALID;

-- hive_mentions FKs
ALTER TABLE hivemind_app.hive_mentions ADD CONSTRAINT hive_mentions_fk1
    FOREIGN KEY (post_id) REFERENCES hivemind_app.hive_posts (id) DEFERRABLE NOT VALID;
ALTER TABLE hivemind_app.hive_mentions ADD CONSTRAINT hive_mentions_fk2
    FOREIGN KEY (account_id) REFERENCES hivemind_app.hive_accounts (id) DEFERRABLE NOT VALID;
