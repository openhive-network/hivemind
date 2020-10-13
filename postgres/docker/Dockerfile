FROM postgres:13

RUN apt-get update && apt-get install -y --no-install-recommends \
    iputils-ping\
    && rm -rf /var/lib/apt/lists/*

COPY run_db.sh /usr/local/bin/
