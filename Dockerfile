# Base docker file having defined environment for build and run of HAF instance.
# Use scripts/ci/build_ci_base_image.sh to rebuild new version of CI base image. It must be properly tagged and pushed to the container registry

ARG CI_REGISTRY_IMAGE=registry.gitlab.syncad.com/hive/hivemind/
ARG CI_IMAGE_TAG=:ubuntu20.04-1

FROM python:3.8-alpine as runtime

ENV LANG=en_US.UTF-8

RUN apk update && DEBIAN_FRONTEND=noniteractive apk add --no-cache \
  bash \
  joe \
  sudo \
  ca-certificates \
  postgresql-client \
  libpq-dev \
  py3-psutil \
  wget \
  && addgroup -S haf_admin && adduser --shell=/bin/bash -S haf_admin -G haf_admin \
  && addgroup -S haf_app_admin && adduser --shell=/bin/bash -S haf_app_admin -G haf_app_admin \
  && addgroup -S hivemind && adduser --shell=/bin/bash -S hivemind -G hivemind \
  && echo "haf_admin ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

SHELL ["/bin/bash", "-c"] 

FROM ${CI_REGISTRY_IMAGE}runtime${CI_IMAGE_TAG} AS ci-base-image

ENV LANG=en_US.UTF-8
SHELL ["/bin/bash", "-c"] 

RUN apk update && DEBIAN_FRONTEND=noniteractive apk add --no-cache \
  postgresql-libs \
  git \
  && apk add --no-cache gcc musl-dev postgresql-dev libffi-dev python3-dev

FROM ${CI_REGISTRY_IMAGE}ci-base-image${CI_IMAGE_TAG} AS builder

WORKDIR /home/hivemind

COPY --chown=hivemind:hivemind . /home/hivemind/app

RUN apk update && DEBIAN_FRONTEND=noniteractive apk add --no-cache --virtual build-dependencies libpq-dev build-base \
  && git config --global --add safe.directory /home/hivemind/app \
  && ./app/scripts/ci/build.sh 
#  &&  apk del --no-cache build-dependencies

#FROM ${CI_REGISTRY_IMAGE}runtime${CI_IMAGE_TAG} AS instance
FROM builder AS instance

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

USER haf_admin

# JSON rpc service
EXPOSE ${HTTP_PORT}

STOPSIGNAL SIGINT

ENTRYPOINT [ "/home/hivemind/docker_entrypoint.sh" ]
