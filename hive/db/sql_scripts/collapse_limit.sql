DO $$
BEGIN
  EXECUTE 'ALTER DATABASE '||current_database()||' SET join_collapse_limit TO 16';
  EXECUTE 'ALTER DATABASE '||current_database()||' SET from_collapse_limit TO 16';
END
$$;