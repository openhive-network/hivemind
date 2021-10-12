DO $$
BEGIN
   ASSERT EXISTS (SELECT * FROM pg_catalog.pg_tables WHERE schemaname = 'public'), '"Public" schema is empty';
END$$;
