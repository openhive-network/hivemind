# syntax=docker/dockerfile:1.5
# Base docker file having defined environment for build and run of a Hivemind instance.
# Use scripts/ci/build_ci_base_image.sh to build a new version of the CI base image. It must be properly tagged and pushed to the container registry.

FROM --platform=$BUILDPLATFORM python:3.8-slim as runtime

ARG TARGETPLATFORM
ARG BUILDPLATFORM

ENV LANG=en_US.UTF-8
ENV TARGETPLATFORM=${TARGETPLATFORM}
ENV BUILDPLATFORM=${BUILDPLATFORM}

COPY haf/scripts/setup_ubuntu.sh /root/setup_os.sh

RUN <<EOF
  set -e
  
  apt update && DEBIAN_FRONTEND=noniteractive apt install -y  \
    bash \
    joe \
    sudo \
    git \
    ca-certificates \
    postgresql-client \
    wget \
    procps \
    xz-utils \
    python3-cffi \
  
  DEBIAN_FRONTEND=noniteractive apt-get clean && rm -rf /var/lib/apt/lists/*
  
  /root/setup_os.sh --haf-admin-account="haf_admin"
  # This user needs UID of 1000 to be able to save logs to cache when run in CI
  useradd -ms /bin/bash -c "Hivemind service account" -u 1000 "hivemind" --groups users
EOF

SHELL ["/bin/bash", "-c"] 

FROM runtime AS ci-base-image

ENV LANG=en_US.UTF-8
SHELL ["/bin/bash", "-c"] 

RUN <<EOF
  set -e

  apt update 
  DEBIAN_FRONTEND=noniteractive apt install -y gcc

  git config --global --add safe.directory /home/hivemind/app
EOF

USER hivemind

ENV PATH=/home/hivemind/.local/bin:${PATH}

RUN <<EOF
  pip install --no-cache-dir --verbose --user tox==3.25.0
EOF

FROM ci-base-image AS builder

WORKDIR /home/hivemind

SHELL ["/bin/bash", "-c"] 

COPY --chown=hivemind:hivemind . /home/hivemind/app

RUN ./app/scripts/ci/build.sh

FROM runtime AS instance

ARG BUILD_TIME
ARG GIT_COMMIT_SHA
ARG GIT_CURRENT_BRANCH
ARG GIT_LAST_LOG_MESSAGE
ARG GIT_LAST_COMMITTER
ARG GIT_LAST_COMMIT_DATE
LABEL org.opencontainers.image.created="$BUILD_TIME"
LABEL org.opencontainers.image.url="https://hive.io/"
LABEL org.opencontainers.image.documentation="https://gitlab.syncad.com/hive/hivemind"
LABEL org.opencontainers.image.source="https://gitlab.syncad.com/hive/hivemind"
#LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="$GIT_COMMIT_SHA"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.ref.name="Hivemind"
LABEL org.opencontainers.image.title="Hivemind Image"
LABEL org.opencontainers.image.description="Runs Hivemind application"
LABEL io.hive.image.branch="$GIT_CURRENT_BRANCH"
LABEL io.hive.image.commit.log_message="$GIT_LAST_LOG_MESSAGE"
LABEL io.hive.image.commit.author="$GIT_LAST_COMMITTER"
LABEL io.hive.image.commit.date="$GIT_LAST_COMMIT_DATE"

ARG HTTP_PORT=8080
ENV HTTP_PORT=${HTTP_PORT}

# Lets use by default host address from default docker bridge network
ARG POSTGRES_URL="postgresql://hivemind@172.17.0.1/haf_block_log"
ENV POSTGRES_URL=${POSTGRES_URL}

ARG POSTGRES_ADMIN_URL="postgresql://haf_admin@172.17.0.1:5432/haf_block_log"
ENV POSTGRES_ADMIN_URL=${POSTGRES_ADMIN_URL}

ENV LANG=en_US.UTF-8

USER hivemind
WORKDIR /home/hivemind

SHELL ["/bin/bash", "-c"] 

COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/dist /home/hivemind/dist 
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/.hivemind-venv /home/hivemind/.hivemind-venv 
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/docker/docker_entrypoint.sh .
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/docker/block-processing-healthcheck.sh .
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/scripts /home/hivemind/app
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/haf/scripts/create_haf_app_role.sh /home/hivemind/haf/scripts/create_haf_app_role.sh
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/haf/scripts/common.sh /home/hivemind/haf/scripts/common.sh
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/mock_data/block_data /home/hivemind/app/mock_data/block_data
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/mock_data/vops_data /home/hivemind/app/mock_data/vops_data

# JSON rpc service
EXPOSE ${HTTP_PORT}

STOPSIGNAL SIGINT

ENTRYPOINT [ "/home/hivemind/docker_entrypoint.sh" ]
