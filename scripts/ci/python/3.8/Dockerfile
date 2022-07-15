# Definition of base image used at hivemind CI committed in the registry.gitlab.syncad.com/hive/hivemind/CI_base_image:3.8
FROM python:3.8-buster

ARG CI_REGISTRY_IMAGE
ARG CI_DOCKER_USER

# Setup python environment.
ENV CI_DOCKER_USER ${CI_DOCKER_USER}
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
        gnupg2 \
        apt-transport-https \
        software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Install debian pgdg repository.
# Install postgresql client programs for various postgresl versions.
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    echo "deb http://apt.postgresql.org/pub/repos/apt buster-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
                    postgresql-client-12 \
    && rm -rf /var/lib/apt/lists/*

# Install docker
ENV DOCKER_VERSION "5:20.10.10~3-0~debian-buster"
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" && \
    apt-get update && \
    apt-cache policy docker-ce && \
    apt-get install -y docker-ce=$DOCKER_VERSION docker-ce-cli=$DOCKER_VERSION containerd.io docker-compose-plugin

# Upgrade some crucial python packages.
RUN pip install --upgrade pip setuptools wheel && \
    pip install pipenv poetry

## Add user ##
RUN echo The user is: $CI_DOCKER_USER && groupadd --gid 1000 $CI_DOCKER_USER \
    && useradd --create-home --uid 1000 --gid ${CI_DOCKER_USER} $CI_DOCKER_USER
USER $CI_DOCKER_USER
WORKDIR /home/$CI_DOCKER_USER
RUN chown -R $CI_DOCKER_USER:$CI_DOCKER_USER /home/$CI_DOCKER_USER

CMD [ "python3" ]
