FROM postgres:12.4

LABEL description="Available non-standard extensions: plpython2, pg_qualstats."

RUN apt-get update \
        && apt-get install -y --no-install-recommends \
            nano \
            postgresql-plpython3-12 \
            python3-psutil \
            postgresql-12-pg-qualstats \
        && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /docker-entrypoint-initdb.d

# Create stuff for monitoring with pgwatch2 and pghero.
COPY ./scripts/db-monitoring/setup/setup_monitoring.sh \
        /docker-entrypoint-initdb.d/
COPY ./scripts/db-monitoring/setup/sql-monitoring /sql-monitoring/
