FROM python:3.6.12-buster

# Setup python environment.
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONFAULTHANDLER 1

# Install debian packages.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install debian pgdg repository.
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN echo "deb http://apt.postgresql.org/pub/repos/apt buster-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list
RUN apt-get update
# Install postgresql client programs for various postgresl versions.
RUN apt-get install -y --no-install-recommends \
        postgresql-client-10 \
        postgresql-client-11 \
        postgresql-client-12 \
        postgresql-client-13 \
    && rm -rf /var/lib/apt/lists/*

# Upgrade some crucial python packages.
RUN pip install --upgrade pip setuptools wheel

# Install python dependencies via pip.
RUN pip install pipenv poetry

ARG user
ENV user ${user}

## Add user ##
RUN groupadd --gid 1000 ${user} \
    && useradd --create-home --uid 1000 --gid ${user} ${user}
USER ${user}
WORKDIR /home/${user}
RUN chown -R ${user}:${user} /home/${user}

CMD [ "python3" ]
