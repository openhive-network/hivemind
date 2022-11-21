do $$
BEGIN
  ASSERT EXISTS (SELECT * FROM pg_extension WHERE extname='intarray'), 'The database requires created "intarray" extension';
  ASSERT (SELECT setting FROM pg_settings where name='join_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use setup_db.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='from_collapse_limit' and source='database')::int = 16, 'Bad optimizer settings, use setup_db.sh script to setup target database correctly';
  ASSERT (SELECT setting FROM pg_settings where name='jit' and source='database')::BOOLEAN = False, 'Bad optimizer settings, use setup_db.sh script to setup target database correctly';
END$$;

CREATE TABLE IF NOT EXISTS hivemind_app.hive_db_patch_level
(
  level SERIAL NOT NULL PRIMARY KEY,
  patch_date timestamp without time zone NOT NULL,
  patched_to_revision TEXT
);

CREATE TABLE IF NOT EXISTS hivemind_app.hive_db_data_migration
(
  migration varchar(128) not null
);

CREATE TABLE IF NOT EXISTS hivemind_app.hive_db_vacuum_needed
(
  vacuum_needed BOOLEAN NOT NULL
);

TRUNCATE TABLE hivemind_app.hive_db_vacuum_needed;

--- Put schema upgrade code here.

