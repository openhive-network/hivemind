# Base docker file having defined environment for build and run of HAF instance.
# Use scripts/ci/build_ci_base_image.sh to rebuild new version of CI base image. It must be properly tagged and pushed to the container registry

ARG CI_REGISTRY_IMAGE=registry.gitlab.syncad.com/hive/hivemind/
ARG CI_IMAGE_TAG=:ubuntu20.04-1

FROM --platform=$BUILDPLATFORM python:3.8-slim as runtime

ARG TARGETPLATFORM
ARG BUILDPLATFORM

ENV LANG=en_US.UTF-8
ENV TARGETPLATFORM=${TARGETPLATFORM}
ENV BUILDPLATFORM=${BUILDPLATFORM}

RUN apt update && DEBIAN_FRONTEND=noniteractive apt install -y  \
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
  && DEBIAN_FRONTEND=noniteractive apt-get clean && rm -rf /var/lib/apt/lists/* \
  && useradd -ms /bin/bash "haf_admin" && echo "haf_admin ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
  && useradd -ms /bin/bash "haf_app_admin" \
  && useradd -ms /bin/bash "hivemind"

 
SHELL ["/bin/bash", "-c"] 

FROM ${CI_REGISTRY_IMAGE}runtime${CI_IMAGE_TAG} AS ci-base-image

ENV LANG=en_US.UTF-8
SHELL ["/bin/bash", "-c"] 

RUN apt update && DEBIAN_FRONTEND=noniteractive apt install -y gcc && \
  git config --global --add safe.directory /home/hivemind/app

FROM ${CI_REGISTRY_IMAGE}ci-base-image${CI_IMAGE_TAG} AS builder

USER hivemind
WORKDIR /home/hivemind

SHELL ["/bin/bash", "-c"] 

COPY --chown=hivemind:hivemind . /home/hivemind/app

RUN ./app/scripts/ci/build.sh

FROM ${CI_REGISTRY_IMAGE}runtime${CI_IMAGE_TAG} AS instance

ARG HTTP_PORT=8080
ENV HTTP_PORT=${HTTP_PORT}

# Lets use by default host address from default docker bridge network
ARG POSTGRES_URL="postgresql://haf_app_admin@172.17.0.1/haf_block_log"
ENV POSTGRES_URL=${POSTGRES_URL}

ENV LANG=en_US.UTF-8

USER hivemind
WORKDIR /home/hivemind

SHELL ["/bin/bash", "-c"] 

COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/dist /home/hivemind/dist 
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/.hivemind-venv /home/hivemind/.hivemind-venv 
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/docker/docker_entrypoint.sh .
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/scripts /home/hivemind/app
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/mock_data/block_data /home/hivemind/app/mock_data/block_data
COPY --from=builder --chown=hivemind:hivemind  /home/hivemind/app/mock_data/vops_data /home/hivemind/app/mock_data/vops_data

USER haf_admin

# JSON rpc service
EXPOSE ${HTTP_PORT}

STOPSIGNAL SIGINT

ENTRYPOINT [ "/home/hivemind/docker_entrypoint.sh" ]
