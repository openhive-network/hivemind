# Postgresql monitoring

Tutorial for Postgres version 10 on Ubuntu 18.04, assuming default
configuration. We'll setup monitoring with
[pgwatch2](https://github.com/cybertec-postgresql/pgwatch2)
and [pghero](https://github.com/ankane/pghero). If you don't need these
both tools, modify this tutorial accordingly.

1. Install required apt packages:
```
# Should be installed on Ubuntu by default, when you have Postgresql
# installed. Required both by pgwatch2 and pghero.
sudo apt-get install postgresql-contrib;

# Only for pgwatch2, if you need to monitor host's cpu load, IO
# and memory usage inside pgwatch2 instance.
postgresql-plpython3 python3-psutil

# Only for pgwatch2, if you need to get recommendations about
# monitored queries. Note: you should install official Postgresql
# ubuntu [pgdg](https://www.postgresql.org/about/news/pgdg-apt-repository-for-debianubuntu-1432/)
# repository to get apt package postgresql-10-pg-qualstats.
postgresql-10-pg-qualstats
```

2. Install postgresql custom configuration file. Be careful with line
concerning `shared_preload_libraries` (this can overrun your existing
settings). You can also append the contents of file
`scripts/db-monitoring/setup/postgresql_monitoring.conf` to the bottom
of your file `/etc/postgresql/10/main/postgresql.conf`.
```
sudo cp scripts/db-monitoring/setup/postgresql_monitoring.conf /etc/postgresql/10/main/conf.d/90-monitoring.conf
```
**Restart postgresql.**

3. Create roles `pgwatch2` and `pghero` (these are unprivileged roles
for monitoring) in postgresql and create template database
`template_monitoring`, in all postgresql instances, that you want to monitor
(we need postgres superuser here):

```
cd scripts/db-monitoring/setup
PSQL_OPTIONS="-p 5432 -U postgres -h 127.0.0.1" ./setup_monitoring.sh
```

Note that above script creates also database `pghero` for gathering
historical stats data.

Remember, that all databases under monitoring should replicate the structure
and objects from template `template_monitoring`, so you should create them with
command:
```
create database some_db template template_monitoring
```

In case of already existing database, which you can't recreate, you should
install needed stuff into it by running command:
```
cd scripts/db-monitoring/setup
PSQL_OPTIONS="-p 5432 -U postgres -h 127.0.0.1" \
    ./setup_monitoring.sh some_existing_db_name yes yes no no
```

4. Create `.env` file and create configuration file for `pghero`
(edit to your needs):
```
cp scripts/db-monitoring/docker/.env_example scripts/db-monitoring/.env
cp scripts/db-monitoring/docker/pghero_example.yml \
    scripts/db-monitoring/docker/pghero.yml
```

5. Run services `pgwatch2` and `pghero` in docker containers:
```
cd scripts/db-monitoring
docker-compose up -d
```

7. Enter databases to be monitored by `pgwatch2`
at http://ci-server.domain:8080. It's recommended to setup
[postgres-continuous-discovery](https://pgwatch2.readthedocs.io/en/latest/preparing_databases.html#different-db-types-explained).
Use unprivileged user `pgwatch2` created earlier.

8. Go to http://ci-server.domain:30000/ to see dashboard produced by
`pgwatch2`.

9. Go to http://ci-server.domain:8085/ to see dashboard produced by
`pghero`.

10. Optionally install cron tasks from file
`scripts/db-monitoring/setup/pghero_cron_jobs.txt`
for collecting historical data by your pghero instance (on the host
which runs pghero docker container).