# Postgresql monitoring

Tutorial for Postgres version 10.

1. Install [pgwatch2](https://github.com/cybertec-postgresql/pgwatch2)
in docker container by running `docker-compose up -d` in directory
`scripts/db-monitoring`. We are going to setup monitoring by
unprivileged user `pgwatch2`, added to standard postgresql role
`pg_monitor`.

2. Install required apt packages:
```
sudo apt-get install postgresql-contrib postgresql-plpython3 python3-psutil
```

3. Set in `postgresql.conf`:
```
track_functions = pl
track_io_timing = on
shared_preload_libraries = 'pg_stat_statements'
track_activity_query_size = 2048
pg_stat_statements.max = 10000
pg_stat_statements.track = all
```
Then restart postgresql.

4. Create role `pgwatch` in postgresql:
```
CREATE ROLE pgwatch2 WITH LOGIN PASSWORD 'pgwatch2';
-- NB! For critical databases it might make sense to ensure that the user account
-- used for monitoring can only open a limited number of connections
-- (there are according checks in code, but multiple instances might be launched)
ALTER ROLE pgwatch2 CONNECTION LIMIT 50;
GRANT pg_monitor TO pgwatch2;
```

5. Create template database `template_hive_ci`
(you'll need db superuser privileges):
```
psql -p 5432 -U postgres -h 127.0.0.1 -f ./create_database.sql --set=db_name=template_hive_ci
psql -p 5432 -U postgres -h 127.0.0.1 -d template_hive_ci -f ./setup_monitoring.sql
psql -p 5432 -U postgres -h 127.0.0.1 -f ./setup_template.sql --set=db_name=template_hive_ci
```

6. Enter databases to be monitored by pgwatch2
at http://ci-server.domain:8080. It's recommended to setup
[postgres-continuous-discovery](https://pgwatch2.readthedocs.io/en/latest/preparing_databases.html#different-db-types-explained). Use unprivileged
user `pgwatch2` created earlier.

7. Go to http://ci-server.domain:30000/ to see stats.
