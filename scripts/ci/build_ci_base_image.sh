#! /bin/bash

REGISTRY=${1:-registry.gitlab.syncad.com/hive/hivemind/}
CI_IMAGE_TAG=:ubuntu20.04-1

export DOCKER_BUILDKIT=1

docker build --platform=amd64 --target=runtime \
  --build-arg CI_REGISTRY_IMAGE=$REGISTRY --build-arg CI_IMAGE_TAG=$CI_IMAGE_TAG \
  -t ${REGISTRY}runtime$CI_IMAGE_TAG -f Dockerfile .


docker build --platform=amd64 --target=ci-base-image \
  --build-arg CI_REGISTRY_IMAGE=$REGISTRY --build-arg CI_IMAGE_TAG=$CI_IMAGE_TAG \
  -t ${REGISTRY}ci-base-image$CI_IMAGE_TAG -f Dockerfile .
