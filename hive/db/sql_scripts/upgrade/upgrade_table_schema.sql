do $$
BEGIN
   ASSERT EXISTS (SELECT * FROM pg_extension WHERE extname='intarray'), 'The database requires created "intarray" extension';
END$$;

CREATE TABLE IF NOT EXISTS hive_db_patch_level
(
  level SERIAL NOT NULL PRIMARY KEY,
  patch_date timestamp without time zone NOT NULL,
  patched_to_revision TEXT
);

CREATE TABLE IF NOT EXISTS hive_db_data_migration
(
  migration varchar(128) not null
);

CREATE TABLE IF NOT EXISTS hive_db_vacuum_needed
(
  vacuum_needed BOOLEAN NOT NULL
);

TRUNCATE TABLE hive_db_vacuum_needed;

DO $$
DECLARE
__version INT;
BEGIN
  SELECT CURRENT_SETTING('server_version_num')::INT INTO __version;

  EXECUTE 'ALTER DATABASE '||current_database()||' SET join_collapse_limit TO 16';
  EXECUTE 'ALTER DATABASE '||current_database()||' SET from_collapse_limit TO 16';

  IF __version >= 120000 THEN
    RAISE NOTICE 'Disabling a JIT optimization on the current database level...';
    EXECUTE 'ALTER DATABASE '||current_database()||' SET jit TO False';
  END IF;
END
$$;

SHOW join_collapse_limit;
SHOW from_collapse_limit;

####################################### 1.26 release upgrades #######################################

--- Begin changes done in MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574

DROP INDEX IF EXISTS hivemind_app.hive_posts_community_id_id_idx;

CREATE INDEX IF NOT EXISTS hive_posts_community_id_id_idx
    ON public.hive_posts USING btree
    (community_id ASC NULLS LAST)
    INCLUDE(id)
    WHERE counter_deleted = 0;

DROP INDEX IF EXISTS hive_posts_community_id_is_pinned_idx;

CREATE INDEX IF NOT EXISTS hive_posts_community_id_is_pinned_idx
    ON public.hive_posts USING btree
    (community_id ASC NULLS LAST)
    INCLUDE(id)
    WHERE is_pinned AND counter_deleted = 0;

--- End of MR https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574
